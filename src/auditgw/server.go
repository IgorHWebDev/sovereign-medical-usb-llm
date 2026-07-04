package main

// server.go — the auditgw HTTP server: static UI, /api/status,
// /api/shutdown, offline-guard check, and inference-route wiring.
// Binds 127.0.0.1 ONLY (hospital constraint).

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// Server holds the gateway runtime state.
type Server struct {
	uiDir     string
	uiPort    int
	llmPort   int
	modelFile string
	modelSHA  string
	buildID   string

	allowOnline   bool
	routeDetected bool

	chain     *Chain
	auditPath string
	llmClient *http.Client
	sup       *LLMSupervisor

	httpSrv  *http.Server
	shutdown chan struct{}
	logger   *log.Logger
}

func (s *Server) logf(format string, a ...any) { s.logger.Printf(format, a...) }

// defaultRouteExists reports whether the OS routing table can reach a
// public address. net.Dial on UDP sends NO packets — it only consults the
// routing table — so this stays true to the offline mandate. Works the
// same on macOS and Windows (pure stdlib).
func defaultRouteExists() bool {
	conn, err := net.DialTimeout("udp4", "203.0.113.1:9", 2*time.Second)
	if err != nil {
		return false
	}
	conn.Close()
	return true
}

func (s *Server) llmReachable() bool {
	c := &http.Client{Timeout: 1500 * time.Millisecond}
	resp, err := c.Get(fmt.Sprintf("http://127.0.0.1:%d/health", s.llmPort))
	if err != nil {
		return false
	}
	resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

func (s *Server) handleStatus(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	auditEntries, auditOK := s.chain.VerifySelf()
	json.NewEncoder(w).Encode(map[string]any{
		"ok":                     true,
		"service":                "auditgw",
		"build_id":               s.buildID,
		"ui_port":                s.uiPort,
		"llm_port":               s.llmPort,
		"llm_reachable":          s.llmReachable(),
		"model_file":             s.modelFile,
		"model_sha256":           s.modelSHA,
		"offline_strict":         !s.allowOnline,
		"allow_online":           s.allowOnline,
		"default_route_detected": s.routeDetected,
		"offline_warning":        s.routeDetected && !s.allowOnline,
		"audit_file":             s.auditPath,
		"audit_last_seq":         s.chain.LastSeq(),
		"audit_ok":               auditOK,
		"audit_entries":          auditEntries,
		"ts_utc":                 time.Now().UTC().Format("2006-01-02T15:04:05Z"),
	})
}

func (s *Server) handleShutdown(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		writeJSONError(w, http.StatusMethodNotAllowed, "POST only")
		return
	}
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]any{"ok": true, "shutting_down": true})
	if f, ok := w.(http.Flusher); ok {
		f.Flush()
	}
	select {
	case <-s.shutdown:
	default:
		close(s.shutdown)
	}
}

// Run starts the gateway and blocks until /api/shutdown or a fatal error.
func (s *Server) Run() error {
	s.routeDetected = defaultRouteExists()
	if s.routeDetected && !s.allowOnline {
		s.logf("WARNING: a default network route was detected on this host. offline_strict is ON.")
		s.logf("WARNING: auditgw itself binds 127.0.0.1 only, but this host is NOT air-gapped.")
		s.logf("WARNING: pass --allow-online to acknowledge and silence this warning.")
	}

	if s.sup != nil {
		if err := s.sup.Start(); err != nil {
			return fmt.Errorf("--spawn-llm: %w", err)
		}
		s.logf("spawned llama-server (pid %d), waiting for /health ...", s.sup.PID())
		if s.waitLLMReady(60 * time.Second) {
			s.logf("llama-server is ready on 127.0.0.1:%d", s.llmPort)
		} else {
			s.logf("WARNING: llama-server not healthy after 60s; proxy will retry per-request")
		}
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/api/status", s.handleStatus)
	mux.HandleFunc("/api/shutdown", s.handleShutdown)
	mux.HandleFunc("/v1/", s.handleInference)
	mux.HandleFunc("/completion", s.handleInference)
	mux.Handle("/", http.FileServer(http.Dir(s.uiDir)))

	addr := fmt.Sprintf("127.0.0.1:%d", s.uiPort)
	ln, err := net.Listen("tcp4", addr)
	if err != nil {
		return fmt.Errorf("cannot bind %s: %w", addr, err)
	}
	s.httpSrv = &http.Server{Handler: mux}
	s.logf("auditgw listening on http://%s (ui=%s, llm=127.0.0.1:%d, audit=%s)",
		addr, s.uiDir, s.llmPort, s.auditPath)

	errCh := make(chan error, 1)
	go func() { errCh <- s.httpSrv.Serve(ln) }()

	select {
	case <-s.shutdown:
		s.logf("shutdown requested via /api/shutdown")
	case err := <-errCh:
		if s.sup != nil {
			s.sup.Stop()
		}
		return err
	}

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	s.httpSrv.Shutdown(ctx)
	if s.sup != nil {
		s.sup.Stop()
	}
	s.logf("auditgw stopped cleanly")
	return nil
}

func (s *Server) waitLLMReady(max time.Duration) bool {
	deadline := time.Now().Add(max)
	for time.Now().Before(deadline) {
		if s.llmReachable() {
			return true
		}
		time.Sleep(500 * time.Millisecond)
	}
	return false
}

// auditFilePath returns <auditDir>/audit-YYYYMM.jsonl for the current month.
func auditFilePath(auditDir string) string {
	return filepath.Join(auditDir, "audit-"+time.Now().UTC().Format("200601")+".jsonl")
}

// resolveDir makes a path absolute relative to the executable's stick root
// heuristics are NOT used: paths are taken as given (relative = cwd).
func mustDir(p, what string) string {
	fi, err := os.Stat(p)
	if err != nil || !fi.IsDir() {
		fmt.Fprintf(os.Stderr, "auditgw: %s directory %q not found\n", what, p)
		os.Exit(2)
	}
	abs, err := filepath.Abs(p)
	if err != nil {
		return p
	}
	return abs
}

func splitArgs(s string) []string {
	fields := strings.Fields(s)
	out := make([]string, 0, len(fields))
	out = append(out, fields...)
	return out
}
