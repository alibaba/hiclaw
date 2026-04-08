package main

import (
	"context"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/signal"
	"syscall"

	v1beta1 "github.com/hiclaw/hiclaw-controller/api/v1beta1"
	"github.com/hiclaw/hiclaw-controller/internal/apiserver"
	authpkg "github.com/hiclaw/hiclaw-controller/internal/auth"
	"github.com/hiclaw/hiclaw-controller/internal/backend"
	"github.com/hiclaw/hiclaw-controller/internal/config"
	"github.com/hiclaw/hiclaw-controller/internal/controller"
	"github.com/hiclaw/hiclaw-controller/internal/credentials"
	"github.com/hiclaw/hiclaw-controller/internal/executor"
	"github.com/hiclaw/hiclaw-controller/internal/proxy"
	"github.com/hiclaw/hiclaw-controller/internal/server"
	"github.com/hiclaw/hiclaw-controller/internal/store"
	"github.com/hiclaw/hiclaw-controller/internal/watcher"
	"github.com/hiclaw/hiclaw-controller/internal/workerapi"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/log/zap"
	metricsserver "sigs.k8s.io/controller-runtime/pkg/metrics/server"
)

func main() {
	ctrl.SetLogger(zap.New())
	logger := ctrl.Log.WithName("hiclaw-controller")

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	cfg := config.LoadConfig()

	// --- Build scheme ---
	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	if err := v1beta1.AddToScheme(scheme); err != nil {
		logger.Error(err, "failed to add hiclaw types to scheme")
		os.Exit(1)
	}

	// --- Backend infrastructure (shared by HTTP API and reconcilers) ---
	cloudCreds := buildCloudCredentials(cfg)
	workerBackends, gatewayBackends := buildBackends(cfg, cloudCreds)
	registry := backend.NewRegistry(workerBackends, gatewayBackends)

	// --- Auth ---
	var persister authpkg.KeyPersister
	if cloudCreds != nil && cfg.OSSBucket != "" {
		cred, err := cloudCreds.GetCredential()
		if err != nil {
			log.Printf("[WARN] Failed to get credentials for key persistence: %v", err)
		} else {
			persister = authpkg.NewOSSKeyPersister(cfg.Region, cfg.OSSBucket, cred)
		}
	}
	keyStore := authpkg.NewKeyStore(cfg.ManagerAPIKey, persister)
	if err := keyStore.Recover(context.Background()); err != nil {
		log.Printf("[WARN] Failed to recover worker keys: %v", err)
	}
	authMw := authpkg.NewMiddleware(keyStore)

	// --- STS service ---
	var stsService *credentials.STSService
	if cfg.OIDCTokenFile != "" {
		stsService = credentials.NewSTSService(cfg.STSConfig())
	}

	// --- Executors (embedded mode shell scripts) ---
	shell := executor.NewShell(cfg.SkillsDir)
	packages := executor.NewPackageResolver("/tmp/import")

	// --- Kube mode ---
	var mgr ctrl.Manager

	if cfg.KubeMode == "embedded" {
		logger.Info("starting embedded mode", "dataDir", cfg.DataDir, "configDir", cfg.ConfigDir)

		kineServer, err := store.StartKine(ctx, store.Config{
			DataDir:       cfg.DataDir,
			ListenAddress: "127.0.0.1:2379",
		})
		if err != nil {
			logger.Error(err, "failed to start kine")
			os.Exit(1)
		}
		logger.Info("kine started", "endpoints", kineServer.ETCDConfig.Endpoints)

		restCfg, err := apiserver.Start(ctx, apiserver.Config{
			DataDir:    cfg.DataDir,
			EtcdURL:    "http://127.0.0.1:2379",
			BindAddr:   "127.0.0.1",
			SecurePort: "6443",
			CRDDir:     cfg.CRDDir,
		})
		if err != nil {
			logger.Error(err, "failed to start embedded kube-apiserver")
			os.Exit(1)
		}
		logger.Info("embedded kube-apiserver ready")

		mgr, err = ctrl.NewManager(restCfg, ctrl.Options{
			Scheme: scheme,
			Metrics: metricsserver.Options{
				BindAddress: "0",
			},
		})
		if err != nil {
			logger.Error(err, "failed to create controller manager")
			os.Exit(1)
		}

		fw := watcher.New(cfg.ConfigDir, mgr.GetClient())
		if err := fw.InitialSync(ctx); err != nil {
			logger.Error(err, "initial sync failed (non-fatal)")
		}
		go func() {
			if err := fw.Watch(ctx); err != nil && ctx.Err() == nil {
				logger.Error(err, "file watcher stopped unexpectedly")
			}
		}()
		logger.Info("file watcher started", "dir", cfg.ConfigDir)

	} else {
		logger.Info("starting in-cluster mode")

		restCfg := ctrl.GetConfigOrDie()
		var err error
		mgr, err = ctrl.NewManager(restCfg, ctrl.Options{
			Scheme: scheme,
		})
		if err != nil {
			logger.Error(err, "failed to create controller manager")
			os.Exit(1)
		}
	}

	// --- Register reconcilers ---
	higressClient := &controller.HigressClient{
		BaseURL:    cfg.HigressBaseURL,
		CookieFile: cfg.HigressCookieFile,
	}

	if err := (&controller.WorkerReconciler{
		Client:   mgr.GetClient(),
		Executor: shell,
		Packages: packages,
		Higress:  higressClient,
		Backend:  registry,
		KubeMode: cfg.KubeMode,
	}).SetupWithManager(mgr); err != nil {
		logger.Error(err, "failed to setup WorkerReconciler")
		os.Exit(1)
	}

	if err := (&controller.TeamReconciler{
		Client:   mgr.GetClient(),
		Executor: shell,
		Packages: packages,
		Higress:  higressClient,
	}).SetupWithManager(mgr); err != nil {
		logger.Error(err, "failed to setup TeamReconciler")
		os.Exit(1)
	}

	if err := (&controller.HumanReconciler{
		Client:   mgr.GetClient(),
		Executor: shell,
	}).SetupWithManager(mgr); err != nil {
		logger.Error(err, "failed to setup HumanReconciler")
		os.Exit(1)
	}

	// --- HTTP server (merged controller API routes) ---
	httpServer := server.NewHTTPServer(cfg.HTTPAddr, cfg.KubeMode)
	registerControllerAPIRoutes(httpServer.Mux, cfg, authMw, registry, keyStore, stsService)

	go func() {
		if err := httpServer.Start(); err != nil {
			logger.Error(err, "HTTP server failed")
		}
	}()

	// --- Start controller manager (blocking) ---
	logger.Info("hiclaw-controller ready",
		"kubeMode", cfg.KubeMode,
		"httpAddr", cfg.HTTPAddr,
		"backends", len(workerBackends),
		"gateways", len(gatewayBackends),
		"sts", stsService != nil,
		"auth", keyStore.AuthEnabled(),
	)
	fmt.Println("hiclaw-controller is running. Press Ctrl+C to stop.")

	if err := mgr.Start(ctx); err != nil {
		logger.Error(err, "controller manager exited with error")
		os.Exit(1)
	}
}

// registerControllerAPIRoutes adds the worker/gateway/credentials/proxy routes
// to the controller's mux.
func registerControllerAPIRoutes(
	mux *http.ServeMux,
	cfg *config.Config,
	authMw *authpkg.Middleware,
	registry *backend.Registry,
	keyStore *authpkg.KeyStore,
	stsService *credentials.STSService,
) {
	controllerURL := cfg.ControllerURL
	workerHandler := workerapi.NewWorkerHandler(registry, keyStore, controllerURL)
	gatewayHandler := workerapi.NewGatewayHandler(registry)
	stsHandler := credentials.NewHandler(stsService)

	// Worker lifecycle — manager only
	mux.Handle("POST /workers", authMw.RequireManager(http.HandlerFunc(workerHandler.Create)))
	mux.Handle("GET /workers", authMw.RequireManager(http.HandlerFunc(workerHandler.List)))
	mux.Handle("GET /workers/{name}", authMw.RequireManager(http.HandlerFunc(workerHandler.Status)))
	mux.Handle("POST /workers/{name}/start", authMw.RequireManager(http.HandlerFunc(workerHandler.Start)))
	mux.Handle("POST /workers/{name}/stop", authMw.RequireManager(http.HandlerFunc(workerHandler.Stop)))
	mux.Handle("DELETE /workers/{name}", authMw.RequireManager(http.HandlerFunc(workerHandler.Delete)))

	// Worker readiness — workers report themselves
	mux.Handle("POST /workers/{name}/ready", authMw.RequireWorker(http.HandlerFunc(workerHandler.Ready)))

	// Gateway — manager only
	mux.Handle("POST /gateway/consumers", authMw.RequireManager(http.HandlerFunc(gatewayHandler.CreateConsumer)))
	mux.Handle("POST /gateway/consumers/{id}/bind", authMw.RequireManager(http.HandlerFunc(gatewayHandler.BindConsumer)))
	mux.Handle("DELETE /gateway/consumers/{id}", authMw.RequireManager(http.HandlerFunc(gatewayHandler.DeleteConsumer)))

	// STS token refresh — workers only
	mux.Handle("POST /credentials/sts", authMw.RequireWorker(http.HandlerFunc(stsHandler.RefreshToken)))

	// Docker API passthrough (embedded mode only)
	if cfg.KubeMode == "embedded" {
		validator := proxy.NewSecurityValidator()
		proxyHandler := proxy.NewHandler(cfg.SocketPath, validator)
		mux.Handle("/docker/", authMw.RequireManager(http.StripPrefix("/docker", proxyHandler)))
	}
}

func buildCloudCredentials(cfg *config.Config) backend.CloudCredentialProvider {
	if cfg.SAEWorkerImage != "" || cfg.GWGatewayID != "" || cfg.OIDCTokenFile != "" || cfg.OSSBucket != "" {
		return backend.NewDefaultCloudCredentialProvider()
	}
	return nil
}

func buildBackends(cfg *config.Config, cloudCreds backend.CloudCredentialProvider) ([]backend.WorkerBackend, []backend.GatewayBackend) {
	var workers []backend.WorkerBackend
	var gateways []backend.GatewayBackend

	if cfg.KubeMode == "embedded" {
		workers = append(workers, backend.NewDockerBackend(cfg.DockerConfig(), cfg.ContainerPrefix))
	}

	switch cfg.WorkerBackend {
	case "k8s":
		if k8s, err := backend.NewK8sBackend(cfg.K8sConfig(), cfg.ContainerPrefix); err != nil {
			log.Printf("[WARN] Failed to create K8s backend: %v", err)
		} else {
			workers = append(workers, k8s)
		}
	case "sae":
		if cfg.SAEWorkerImage == "" || cloudCreds == nil {
			log.Printf("[WARN] SAE backend requested but config incomplete")
		} else {
			sae, err := backend.NewSAEBackend(cloudCreds, cfg.SAEConfig(), cfg.ContainerPrefix)
			if err != nil {
				log.Printf("[WARN] Failed to create SAE backend: %v", err)
			} else {
				workers = append(workers, sae)
			}
		}
	default:
		if cfg.SAEWorkerImage != "" && cloudCreds != nil {
			sae, err := backend.NewSAEBackend(cloudCreds, cfg.SAEConfig(), cfg.ContainerPrefix)
			if err != nil {
				log.Printf("[WARN] Failed to create SAE backend: %v", err)
			} else {
				workers = append(workers, sae)
			}
		} else if cfg.K8sNamespace != "" {
			if k8s, err := backend.NewK8sBackend(cfg.K8sConfig(), cfg.ContainerPrefix); err != nil {
				log.Printf("[WARN] Failed to create K8s backend: %v", err)
			} else {
				workers = append(workers, k8s)
			}
		}
	}

	if cfg.GWGatewayID != "" && cloudCreds != nil {
		apig, err := backend.NewAPIGBackend(cloudCreds, cfg.APIGConfig())
		if err != nil {
			log.Printf("[WARN] Failed to create APIG backend: %v", err)
		} else {
			gateways = append(gateways, apig)
		}
	}

	return workers, gateways
}
