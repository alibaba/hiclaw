package main

import "os"

// Config holds all configuration for the orchestrator service.
type Config struct {
	// ListenAddr is the address to listen on (default ":2375").
	ListenAddr string

	// SocketPath is the Docker socket path (default "/var/run/docker.sock").
	SocketPath string

	// ContainerPrefix is the required prefix for worker container names (default "hiclaw-worker-").
	ContainerPrefix string

	// Runtime is the deployment runtime ("aliyun" for cloud, empty for local).
	Runtime string
}

// LoadConfig reads configuration from environment variables.
func LoadConfig() *Config {
	c := &Config{
		ListenAddr:      envOrDefault("HICLAW_PROXY_LISTEN", ":2375"),
		SocketPath:      envOrDefault("HICLAW_PROXY_SOCKET", "/var/run/docker.sock"),
		ContainerPrefix: envOrDefault("HICLAW_PROXY_CONTAINER_PREFIX", "hiclaw-worker-"),
		Runtime:         os.Getenv("HICLAW_RUNTIME"),
	}
	return c
}

func envOrDefault(key, defaultVal string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return defaultVal
}
