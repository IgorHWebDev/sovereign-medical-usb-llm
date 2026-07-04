package main

// spawn.go — optional --spawn-llm mode: auditgw launches llama-server
// itself and supervises it (restart on crash, kill on shutdown).

import (
	"log"
	"os/exec"
	"sync"
	"time"
)

const maxRestarts = 5

// LLMSupervisor launches and babysits one llama-server process.
type LLMSupervisor struct {
	bin    string
	args   []string
	logger *log.Logger

	mu       sync.Mutex
	cmd      *exec.Cmd
	stopping bool
	restarts int
}

func NewLLMSupervisor(bin string, args []string, logger *log.Logger) *LLMSupervisor {
	return &LLMSupervisor{bin: bin, args: args, logger: logger}
}

// Start launches llama-server and begins supervision.
func (sv *LLMSupervisor) Start() error {
	sv.mu.Lock()
	defer sv.mu.Unlock()
	return sv.launchLocked()
}

func (sv *LLMSupervisor) launchLocked() error {
	cmd := exec.Command(sv.bin, sv.args...)
	// llama-server logs go to auditgw's stderr so launchers can capture them.
	cmd.Stdout = logWriter{sv.logger, "llama-server"}
	cmd.Stderr = logWriter{sv.logger, "llama-server"}
	if err := cmd.Start(); err != nil {
		return err
	}
	sv.cmd = cmd
	go sv.watch(cmd)
	return nil
}

func (sv *LLMSupervisor) watch(cmd *exec.Cmd) {
	err := cmd.Wait()
	sv.mu.Lock()
	if sv.stopping {
		sv.mu.Unlock()
		return
	}
	sv.logger.Printf("WARNING: llama-server exited unexpectedly: %v", err)
	if sv.restarts >= maxRestarts {
		sv.logger.Printf("ERROR: llama-server crashed %d times; giving up on restarts", sv.restarts)
		sv.mu.Unlock()
		return
	}
	sv.restarts++
	backoff := time.Duration(sv.restarts) * 2 * time.Second
	sv.logger.Printf("restarting llama-server in %s (attempt %d/%d)", backoff, sv.restarts, maxRestarts)
	sv.mu.Unlock()

	time.Sleep(backoff)

	sv.mu.Lock()
	defer sv.mu.Unlock()
	if sv.stopping {
		return
	}
	if err := sv.launchLocked(); err != nil {
		sv.logger.Printf("ERROR: llama-server restart failed: %v", err)
	}
}

// Stop terminates the supervised process (no restart).
func (sv *LLMSupervisor) Stop() {
	sv.mu.Lock()
	defer sv.mu.Unlock()
	sv.stopping = true
	if sv.cmd != nil && sv.cmd.Process != nil {
		sv.cmd.Process.Kill()
	}
}

// PID returns the supervised process id (0 if not running).
func (sv *LLMSupervisor) PID() int {
	sv.mu.Lock()
	defer sv.mu.Unlock()
	if sv.cmd != nil && sv.cmd.Process != nil {
		return sv.cmd.Process.Pid
	}
	return 0
}

type logWriter struct {
	l      *log.Logger
	prefix string
}

func (w logWriter) Write(p []byte) (int, error) {
	w.l.Printf("[%s] %s", w.prefix, string(p))
	return len(p), nil
}
