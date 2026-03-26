package api

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/alibaba/hiclaw/orchestrator/backend"
)

// mockBackend implements backend.WorkerBackend for handler tests.
type mockBackend struct {
	name      string
	available bool
	workers   map[string]*backend.WorkerResult

	createErr error
	startErr  error
	stopErr   error
	deleteErr error
}

func newMockBackend() *mockBackend {
	return &mockBackend{
		name:      "mock",
		available: true,
		workers:   map[string]*backend.WorkerResult{},
	}
}

func (m *mockBackend) Name() string                          { return m.name }
func (m *mockBackend) Available(_ context.Context) bool      { return m.available }

func (m *mockBackend) Create(_ context.Context, req backend.CreateRequest) (*backend.WorkerResult, error) {
	if m.createErr != nil {
		return nil, m.createErr
	}
	r := &backend.WorkerResult{
		Name:        req.Name,
		Backend:     "mock",
		Status:      backend.StatusRunning,
		ContainerID: "mock-" + req.Name,
		RawStatus:   "running",
	}
	m.workers[req.Name] = r
	return r, nil
}

func (m *mockBackend) Delete(_ context.Context, name string) error {
	if m.deleteErr != nil {
		return m.deleteErr
	}
	delete(m.workers, name)
	return nil
}

func (m *mockBackend) Start(_ context.Context, name string) error {
	if m.startErr != nil {
		return m.startErr
	}
	if w, ok := m.workers[name]; ok {
		w.Status = backend.StatusRunning
		return nil
	}
	return backend.ErrNotFound
}

func (m *mockBackend) Stop(_ context.Context, name string) error {
	if m.stopErr != nil {
		return m.stopErr
	}
	if w, ok := m.workers[name]; ok {
		w.Status = backend.StatusStopped
		return nil
	}
	return backend.ErrNotFound
}

func (m *mockBackend) Status(_ context.Context, name string) (*backend.WorkerResult, error) {
	if w, ok := m.workers[name]; ok {
		return w, nil
	}
	return &backend.WorkerResult{
		Name:    name,
		Backend: "mock",
		Status:  backend.StatusNotFound,
	}, nil
}

func (m *mockBackend) List(_ context.Context) ([]backend.WorkerResult, error) {
	results := make([]backend.WorkerResult, 0, len(m.workers))
	for _, w := range m.workers {
		results = append(results, *w)
	}
	return results, nil
}

func setupHandler(mb *mockBackend) (*WorkerHandler, *http.ServeMux) {
	reg := backend.NewRegistry([]backend.WorkerBackend{mb}, nil)
	h := NewWorkerHandler(reg)
	mux := http.NewServeMux()
	mux.HandleFunc("POST /workers", h.Create)
	mux.HandleFunc("GET /workers", h.List)
	mux.HandleFunc("GET /workers/{name}", h.Status)
	mux.HandleFunc("POST /workers/{name}/start", h.Start)
	mux.HandleFunc("POST /workers/{name}/stop", h.Stop)
	mux.HandleFunc("DELETE /workers/{name}", h.Delete)
	return h, mux
}

func TestCreateWorker(t *testing.T) {
	mb := newMockBackend()
	_, mux := setupHandler(mb)

	body, _ := json.Marshal(CreateWorkerRequest{
		Name:  "alice",
		Image: "hiclaw/worker-agent:latest",
	})
	req := httptest.NewRequest(http.MethodPost, "/workers", bytes.NewReader(body))
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", w.Code, w.Body.String())
	}

	var resp WorkerResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.Name != "alice" {
		t.Errorf("expected name alice, got %s", resp.Name)
	}
	if resp.Status != backend.StatusRunning {
		t.Errorf("expected status running, got %s", resp.Status)
	}
	if resp.Backend != "mock" {
		t.Errorf("expected backend mock, got %s", resp.Backend)
	}
}

func TestCreateWorkerMissingName(t *testing.T) {
	mb := newMockBackend()
	_, mux := setupHandler(mb)

	body, _ := json.Marshal(CreateWorkerRequest{Image: "img:latest"})
	req := httptest.NewRequest(http.MethodPost, "/workers", bytes.NewReader(body))
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestCreateWorkerMissingImage(t *testing.T) {
	mb := newMockBackend()
	_, mux := setupHandler(mb)

	body, _ := json.Marshal(CreateWorkerRequest{Name: "alice"})
	req := httptest.NewRequest(http.MethodPost, "/workers", bytes.NewReader(body))
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestCreateWorkerInvalidJSON(t *testing.T) {
	mb := newMockBackend()
	_, mux := setupHandler(mb)

	req := httptest.NewRequest(http.MethodPost, "/workers", bytes.NewReader([]byte("not json")))
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusBadRequest {
		t.Errorf("expected 400, got %d", w.Code)
	}
}

func TestCreateWorkerConflict(t *testing.T) {
	mb := newMockBackend()
	mb.createErr = backend.ErrConflict
	_, mux := setupHandler(mb)

	body, _ := json.Marshal(CreateWorkerRequest{Name: "alice", Image: "img:latest"})
	req := httptest.NewRequest(http.MethodPost, "/workers", bytes.NewReader(body))
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusConflict {
		t.Errorf("expected 409, got %d: %s", w.Code, w.Body.String())
	}
}

func TestCreateWorkerBackendUnavailable(t *testing.T) {
	mb := newMockBackend()
	mb.available = false
	_, mux := setupHandler(mb)

	body, _ := json.Marshal(CreateWorkerRequest{Name: "alice", Image: "img:latest"})
	req := httptest.NewRequest(http.MethodPost, "/workers", bytes.NewReader(body))
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusServiceUnavailable {
		t.Errorf("expected 503, got %d", w.Code)
	}
}

func TestListWorkersEmpty(t *testing.T) {
	mb := newMockBackend()
	_, mux := setupHandler(mb)

	req := httptest.NewRequest(http.MethodGet, "/workers", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp WorkerListResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if len(resp.Workers) != 0 {
		t.Errorf("expected empty list, got %d", len(resp.Workers))
	}
}

func TestListWorkersNoBackend(t *testing.T) {
	mb := newMockBackend()
	mb.available = false
	_, mux := setupHandler(mb)

	req := httptest.NewRequest(http.MethodGet, "/workers", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 even with no backend, got %d", w.Code)
	}

	var resp WorkerListResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if len(resp.Workers) != 0 {
		t.Errorf("expected empty list, got %d", len(resp.Workers))
	}
}

func TestStatusWorker(t *testing.T) {
	mb := newMockBackend()
	mb.workers["alice"] = &backend.WorkerResult{
		Name: "alice", Backend: "mock", Status: backend.StatusRunning, ContainerID: "mock-alice",
	}
	_, mux := setupHandler(mb)

	req := httptest.NewRequest(http.MethodGet, "/workers/alice", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp WorkerResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.Status != backend.StatusRunning {
		t.Errorf("expected running, got %s", resp.Status)
	}
}

func TestStatusWorkerNotFound(t *testing.T) {
	mb := newMockBackend()
	_, mux := setupHandler(mb)

	req := httptest.NewRequest(http.MethodGet, "/workers/ghost", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var resp WorkerResponse
	json.NewDecoder(w.Body).Decode(&resp)
	if resp.Status != backend.StatusNotFound {
		t.Errorf("expected not_found, got %s", resp.Status)
	}
}

func TestStartWorkerNotFound(t *testing.T) {
	mb := newMockBackend()
	_, mux := setupHandler(mb)

	req := httptest.NewRequest(http.MethodPost, "/workers/ghost/start", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d: %s", w.Code, w.Body.String())
	}
}

func TestStopWorkerNotFound(t *testing.T) {
	mb := newMockBackend()
	_, mux := setupHandler(mb)

	req := httptest.NewRequest(http.MethodPost, "/workers/ghost/stop", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404, got %d: %s", w.Code, w.Body.String())
	}
}

func TestDeleteWorker(t *testing.T) {
	mb := newMockBackend()
	mb.workers["alice"] = &backend.WorkerResult{Name: "alice"}
	_, mux := setupHandler(mb)

	req := httptest.NewRequest(http.MethodDelete, "/workers/alice", nil)
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusNoContent {
		t.Errorf("expected 204, got %d", w.Code)
	}
	if _, exists := mb.workers["alice"]; exists {
		t.Error("expected worker to be deleted")
	}
}

func TestCreateWorkerGenericError(t *testing.T) {
	mb := newMockBackend()
	mb.createErr = errors.New("something broke")
	_, mux := setupHandler(mb)

	body, _ := json.Marshal(CreateWorkerRequest{Name: "alice", Image: "img:latest"})
	req := httptest.NewRequest(http.MethodPost, "/workers", bytes.NewReader(body))
	w := httptest.NewRecorder()
	mux.ServeHTTP(w, req)

	if w.Code != http.StatusInternalServerError {
		t.Errorf("expected 500, got %d", w.Code)
	}
}

func TestGatewayStubs(t *testing.T) {
	h := NewGatewayHandler()
	mux := http.NewServeMux()
	mux.HandleFunc("POST /gateway/consumers", h.CreateConsumer)
	mux.HandleFunc("POST /gateway/consumers/{id}/bind", h.BindConsumer)
	mux.HandleFunc("DELETE /gateway/consumers/{id}", h.DeleteConsumer)

	endpoints := []struct {
		method string
		path   string
	}{
		{http.MethodPost, "/gateway/consumers"},
		{http.MethodPost, "/gateway/consumers/test-id/bind"},
		{http.MethodDelete, "/gateway/consumers/test-id"},
	}

	for _, ep := range endpoints {
		req := httptest.NewRequest(ep.method, ep.path, nil)
		w := httptest.NewRecorder()
		mux.ServeHTTP(w, req)
		if w.Code != http.StatusNotImplemented {
			t.Errorf("%s %s: expected 501, got %d", ep.method, ep.path, w.Code)
		}
	}
}
