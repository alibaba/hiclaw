package main

import (
	"log"
	"net/http"

	"github.com/alibaba/hiclaw/orchestrator/api"
	"github.com/alibaba/hiclaw/orchestrator/backend"
	"github.com/alibaba/hiclaw/orchestrator/proxy"
)

func main() {
	cfg := LoadConfig()

	// --- Security validator (for Docker API passthrough) ---
	validator := proxy.NewSecurityValidator()

	// --- Docker API passthrough handler ---
	proxyHandler := proxy.NewHandler(cfg.SocketPath, validator)

	// --- Backend registry ---
	var workerBackends []backend.WorkerBackend

	// Docker backend (always registered; Available() checks socket at runtime)
	dockerBackend := backend.NewDockerBackend(cfg.SocketPath, cfg.ContainerPrefix)
	workerBackends = append(workerBackends, dockerBackend)

	// Future: SAE backend (Phase 2)
	// if cfg.Runtime == "aliyun" { ... }

	registry := backend.NewRegistry(workerBackends, nil)

	// --- API handlers ---
	workerHandler := api.NewWorkerHandler(registry)
	gatewayHandler := api.NewGatewayHandler()

	// --- Route registration ---
	mux := http.NewServeMux()

	// Worker lifecycle API
	mux.HandleFunc("POST /workers", workerHandler.Create)
	mux.HandleFunc("GET /workers", workerHandler.List)
	mux.HandleFunc("GET /workers/{name}", workerHandler.Status)
	mux.HandleFunc("POST /workers/{name}/start", workerHandler.Start)
	mux.HandleFunc("POST /workers/{name}/stop", workerHandler.Stop)
	mux.HandleFunc("DELETE /workers/{name}", workerHandler.Delete)

	// Gateway API (Phase 1: 501 stubs)
	mux.HandleFunc("POST /gateway/consumers", gatewayHandler.CreateConsumer)
	mux.HandleFunc("POST /gateway/consumers/{id}/bind", gatewayHandler.BindConsumer)
	mux.HandleFunc("DELETE /gateway/consumers/{id}", gatewayHandler.DeleteConsumer)

	// Docker API passthrough (catch-all, existing behavior)
	mux.Handle("/", proxyHandler)

	// --- Start server ---
	log.Printf("hiclaw-orchestrator listening on %s, docker socket: %s", cfg.ListenAddr, cfg.SocketPath)
	if len(validator.AllowedRegistries) > 0 {
		log.Printf("Allowed registries: %v", validator.AllowedRegistries)
	}
	if err := http.ListenAndServe(cfg.ListenAddr, mux); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}
