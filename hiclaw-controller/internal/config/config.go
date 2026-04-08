package config

import (
	"os"
	"path/filepath"
	"strconv"

	"github.com/hiclaw/hiclaw-controller/internal/backend"
	"github.com/hiclaw/hiclaw-controller/internal/credentials"
)

type Config struct {
	// Controller core
	KubeMode  string // "embedded" or "incluster"
	DataDir   string
	HTTPAddr  string
	ConfigDir string
	CRDDir    string
	SkillsDir string

	// Docker proxy (embedded mode only)
	SocketPath      string
	ContainerPrefix string

	// Auth
	ManagerAPIKey string // HICLAW_CONTROLLER_API_KEY

	// Higress
	HigressBaseURL    string
	HigressCookieFile string

	// Worker backend selection
	WorkerBackend string

	// SAE Backend
	Region              string
	SAENamespaceID      string
	SAEWorkerImage      string
	SAECopawWorkerImage string
	SAEVPCID            string
	SAEVSwitchID        string
	SAESecurityGroupID  string
	SAEWorkerCPU        int32
	SAEWorkerMemory     int32

	// APIG Gateway
	GWGatewayID  string
	GWModelAPIID string
	GWEnvID      string

	// STS
	OSSBucket       string
	STSRoleArn      string
	OIDCProviderArn string
	OIDCTokenFile   string

	// Kubernetes Backend
	K8sNamespace    string
	K8sWorkerCPU    string
	K8sWorkerMemory string

	// Controller URL (advertised to workers for STS refresh etc.)
	ControllerURL string
}

func LoadConfig() *Config {
	dataDir := envOrDefault("HICLAW_DATA_DIR", "/data/hiclaw-controller")
	if !filepath.IsAbs(dataDir) {
		if wd, err := os.Getwd(); err == nil {
			dataDir = filepath.Join(wd, dataDir)
		}
	}

	return &Config{
		KubeMode:  envOrDefault("HICLAW_KUBE_MODE", "embedded"),
		DataDir:   dataDir,
		HTTPAddr:  envOrDefault("HICLAW_HTTP_ADDR", ":8090"),
		ConfigDir: envOrDefault("HICLAW_CONFIG_DIR", "/root/hiclaw-fs/hiclaw-config"),
		CRDDir:    envOrDefault("HICLAW_CRD_DIR", "/opt/hiclaw/config/crd"),
		SkillsDir: envOrDefault("HICLAW_SKILLS_DIR", "/opt/hiclaw/agent/skills"),

		SocketPath:      envOrDefault("HICLAW_PROXY_SOCKET", "/var/run/docker.sock"),
		ContainerPrefix: envOrDefault("HICLAW_PROXY_CONTAINER_PREFIX", "hiclaw-worker-"),

		ManagerAPIKey: os.Getenv("HICLAW_CONTROLLER_API_KEY"),

		HigressBaseURL:    envOrDefault("HIGRESS_BASE_URL", "http://127.0.0.1:8001"),
		HigressCookieFile: os.Getenv("HIGRESS_COOKIE_FILE"),

		WorkerBackend: firstNonEmpty(
			os.Getenv("HICLAW_WORKER_BACKEND"),
			os.Getenv("HICLAW_ALIYUN_WORKER_BACKEND"),
		),

		Region:              envOrDefault("HICLAW_REGION", "cn-hangzhou"),
		SAENamespaceID:      os.Getenv("HICLAW_SAE_NAMESPACE_ID"),
		SAEWorkerImage:      os.Getenv("HICLAW_SAE_WORKER_IMAGE"),
		SAECopawWorkerImage: os.Getenv("HICLAW_SAE_COPAW_WORKER_IMAGE"),
		SAEVPCID:            os.Getenv("HICLAW_SAE_VPC_ID"),
		SAEVSwitchID:        os.Getenv("HICLAW_SAE_VSWITCH_ID"),
		SAESecurityGroupID:  os.Getenv("HICLAW_SAE_SECURITY_GROUP_ID"),
		SAEWorkerCPU:        int32(envOrDefaultInt("HICLAW_SAE_WORKER_CPU", 1000)),
		SAEWorkerMemory:     int32(envOrDefaultInt("HICLAW_SAE_WORKER_MEMORY", 2048)),

		GWGatewayID:  os.Getenv("HICLAW_GW_GATEWAY_ID"),
		GWModelAPIID: os.Getenv("HICLAW_GW_MODEL_API_ID"),
		GWEnvID:      os.Getenv("HICLAW_GW_ENV_ID"),

		OSSBucket:       os.Getenv("HICLAW_OSS_BUCKET"),
		STSRoleArn:      os.Getenv("ALIBABA_CLOUD_ROLE_ARN"),
		OIDCProviderArn: os.Getenv("ALIBABA_CLOUD_OIDC_PROVIDER_ARN"),
		OIDCTokenFile:   os.Getenv("ALIBABA_CLOUD_OIDC_TOKEN_FILE"),

		K8sNamespace:    os.Getenv("HICLAW_K8S_NAMESPACE"),
		K8sWorkerCPU:    envOrDefault("HICLAW_K8S_WORKER_CPU", "1000m"),
		K8sWorkerMemory: envOrDefault("HICLAW_K8S_WORKER_MEMORY", "2Gi"),

		ControllerURL: firstNonEmpty(
			os.Getenv("HICLAW_CONTROLLER_URL"),
			os.Getenv("HICLAW_ORCHESTRATOR_URL"), // legacy fallback
		),
	}
}

func (c *Config) DockerConfig() backend.DockerConfig {
	return backend.DockerConfig{
		SocketPath:       c.SocketPath,
		WorkerImage:      envOrDefault("HICLAW_WORKER_IMAGE", "hiclaw/worker-agent:latest"),
		CopawWorkerImage: envOrDefault("HICLAW_COPAW_WORKER_IMAGE", "hiclaw/copaw-worker:latest"),
		DefaultNetwork:   envOrDefault("HICLAW_DOCKER_NETWORK", "hiclaw-net"),
	}
}

func (c *Config) SAEConfig() backend.SAEConfig {
	return backend.SAEConfig{
		Region:           c.Region,
		NamespaceID:      c.SAENamespaceID,
		WorkerImage:      c.SAEWorkerImage,
		CopawWorkerImage: c.SAECopawWorkerImage,
		VPCID:            c.SAEVPCID,
		VSwitchID:        c.SAEVSwitchID,
		SecurityGroupID:  c.SAESecurityGroupID,
		CPU:              c.SAEWorkerCPU,
		Memory:           c.SAEWorkerMemory,
	}
}

func (c *Config) APIGConfig() backend.APIGConfig {
	return backend.APIGConfig{
		Region:     c.Region,
		GatewayID:  c.GWGatewayID,
		ModelAPIID: c.GWModelAPIID,
		EnvID:      c.GWEnvID,
	}
}

func (c *Config) STSConfig() credentials.STSConfig {
	return credentials.STSConfig{
		Region:          c.Region,
		RoleArn:         c.STSRoleArn,
		OIDCProviderArn: c.OIDCProviderArn,
		OIDCTokenFile:   c.OIDCTokenFile,
		OSSBucket:       c.OSSBucket,
	}
}

func (c *Config) K8sConfig() backend.K8sConfig {
	return backend.K8sConfig{
		Namespace:        c.K8sNamespace,
		WorkerImage:      envOrDefault("HICLAW_WORKER_IMAGE", "hiclaw/worker-agent:latest"),
		CopawWorkerImage: envOrDefault("HICLAW_COPAW_WORKER_IMAGE", "hiclaw/copaw-worker:latest"),
		WorkerCPU:        c.K8sWorkerCPU,
		WorkerMemory:     c.K8sWorkerMemory,
	}
}

func envOrDefault(key, defaultVal string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultVal
}

func envOrDefaultInt(key string, defaultVal int) int {
	if v := os.Getenv(key); v != "" {
		if n, err := strconv.Atoi(v); err == nil {
			return n
		}
	}
	return defaultVal
}

func firstNonEmpty(values ...string) string {
	for _, v := range values {
		if v != "" {
			return v
		}
	}
	return ""
}
