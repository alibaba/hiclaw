package api

import (
	"net/http"
)

// GatewayHandler handles /gateway/* HTTP requests.
// Phase 1: all endpoints return 501 Not Implemented.
// Phase 2: will delegate to GatewayBackend (Higress local, APIG cloud).
type GatewayHandler struct{}

// NewGatewayHandler creates a GatewayHandler.
func NewGatewayHandler() *GatewayHandler {
	return &GatewayHandler{}
}

// CreateConsumer handles POST /gateway/consumers.
func (h *GatewayHandler) CreateConsumer(w http.ResponseWriter, r *http.Request) {
	writeError(w, http.StatusNotImplemented, "gateway consumer management not yet implemented (Phase 2)")
}

// BindConsumer handles POST /gateway/consumers/{id}/bind.
func (h *GatewayHandler) BindConsumer(w http.ResponseWriter, r *http.Request) {
	writeError(w, http.StatusNotImplemented, "gateway consumer binding not yet implemented (Phase 2)")
}

// DeleteConsumer handles DELETE /gateway/consumers/{id}.
func (h *GatewayHandler) DeleteConsumer(w http.ResponseWriter, r *http.Request) {
	writeError(w, http.StatusNotImplemented, "gateway consumer deletion not yet implemented (Phase 2)")
}
