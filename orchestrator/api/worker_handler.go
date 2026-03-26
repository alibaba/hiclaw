package api

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"

	"github.com/alibaba/hiclaw/orchestrator/backend"
)

// WorkerHandler handles /workers/* HTTP requests.
type WorkerHandler struct {
	registry *backend.Registry
}

// NewWorkerHandler creates a WorkerHandler with the given backend registry.
func NewWorkerHandler(registry *backend.Registry) *WorkerHandler {
	return &WorkerHandler{registry: registry}
}

// Create handles POST /workers.
func (h *WorkerHandler) Create(w http.ResponseWriter, r *http.Request) {
	var req CreateWorkerRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, http.StatusBadRequest, "invalid JSON: "+err.Error())
		return
	}
	if req.Name == "" {
		writeError(w, http.StatusBadRequest, "name is required")
		return
	}
	if req.Image == "" {
		writeError(w, http.StatusBadRequest, "image is required")
		return
	}

	b, err := h.registry.GetWorkerBackend(r.Context(), req.Backend)
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, err.Error())
		return
	}

	result, err := b.Create(r.Context(), backend.CreateRequest{
		Name:       req.Name,
		Image:      req.Image,
		Runtime:    req.Runtime,
		Env:        req.Env,
		Network:    req.Network,
		ExtraHosts: req.ExtraHosts,
		WorkingDir: req.WorkingDir,
	})
	if err != nil {
		log.Printf("[ERROR] create worker %s: %v", req.Name, err)
		writeBackendError(w, err)
		return
	}

	writeJSON(w, http.StatusCreated, toWorkerResponse(result))
}

// List handles GET /workers.
func (h *WorkerHandler) List(w http.ResponseWriter, r *http.Request) {
	b, err := h.registry.GetWorkerBackend(r.Context(), "")
	if err != nil {
		writeJSON(w, http.StatusOK, WorkerListResponse{Workers: []WorkerResponse{}})
		return
	}

	results, err := b.List(r.Context())
	if err != nil {
		log.Printf("[ERROR] list workers: %v", err)
		writeBackendError(w, err)
		return
	}

	workers := make([]WorkerResponse, 0, len(results))
	for _, r := range results {
		workers = append(workers, toWorkerResponse(&r))
	}
	writeJSON(w, http.StatusOK, WorkerListResponse{Workers: workers})
}

// Status handles GET /workers/{name}.
func (h *WorkerHandler) Status(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	if name == "" {
		writeError(w, http.StatusBadRequest, "worker name is required")
		return
	}

	b, err := h.registry.GetWorkerBackend(r.Context(), "")
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, err.Error())
		return
	}

	result, err := b.Status(r.Context(), name)
	if err != nil {
		log.Printf("[ERROR] status worker %s: %v", name, err)
		writeBackendError(w, err)
		return
	}

	writeJSON(w, http.StatusOK, toWorkerResponse(result))
}

// Start handles POST /workers/{name}/start.
func (h *WorkerHandler) Start(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	if name == "" {
		writeError(w, http.StatusBadRequest, "worker name is required")
		return
	}

	b, err := h.registry.GetWorkerBackend(r.Context(), "")
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, err.Error())
		return
	}

	if err := b.Start(r.Context(), name); err != nil {
		log.Printf("[ERROR] start worker %s: %v", name, err)
		writeBackendError(w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// Stop handles POST /workers/{name}/stop.
func (h *WorkerHandler) Stop(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	if name == "" {
		writeError(w, http.StatusBadRequest, "worker name is required")
		return
	}

	b, err := h.registry.GetWorkerBackend(r.Context(), "")
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, err.Error())
		return
	}

	if err := b.Stop(r.Context(), name); err != nil {
		log.Printf("[ERROR] stop worker %s: %v", name, err)
		writeBackendError(w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// Delete handles DELETE /workers/{name}.
func (h *WorkerHandler) Delete(w http.ResponseWriter, r *http.Request) {
	name := r.PathValue("name")
	if name == "" {
		writeError(w, http.StatusBadRequest, "worker name is required")
		return
	}

	b, err := h.registry.GetWorkerBackend(r.Context(), "")
	if err != nil {
		writeError(w, http.StatusServiceUnavailable, err.Error())
		return
	}

	if err := b.Delete(r.Context(), name); err != nil {
		log.Printf("[ERROR] delete worker %s: %v", name, err)
		writeBackendError(w, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// --- helpers ---

func toWorkerResponse(r *backend.WorkerResult) WorkerResponse {
	return WorkerResponse{
		Name:        r.Name,
		Backend:     r.Backend,
		Status:      r.Status,
		ContainerID: r.ContainerID,
		AppID:       r.AppID,
		RawStatus:   r.RawStatus,
	}
}

func writeJSON(w http.ResponseWriter, status int, v interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(v); err != nil {
		log.Printf("[WARN] failed to write JSON response: %v", err)
	}
}

func writeError(w http.ResponseWriter, status int, message string) {
	writeJSON(w, status, ErrorResponse{Message: message})
}

// writeBackendError maps typed backend errors to appropriate HTTP status codes.
func writeBackendError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, backend.ErrConflict):
		writeError(w, http.StatusConflict, err.Error())
	case errors.Is(err, backend.ErrNotFound):
		writeError(w, http.StatusNotFound, err.Error())
	default:
		writeError(w, http.StatusInternalServerError, err.Error())
	}
}
