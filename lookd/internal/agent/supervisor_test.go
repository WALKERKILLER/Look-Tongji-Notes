package agent

import (
	"context"
	"os"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func waitState(t *testing.T, s *Supervisor, want string) Status {
	t.Helper()
	deadline := time.Now().Add(10 * time.Second)
	for time.Now().Before(deadline) {
		if st := s.Status(); st.State == want {
			return st
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Fatalf("state %q, want %q", s.Status().State, want)
	return Status{}
}

func TestSupervisorWaitsForNodeAndRestarts(t *testing.T) {
	if runtime.GOOS == "windows" {
		t.Skip("shell script stands in for node")
	}
	dir := t.TempDir()
	script := filepath.Join(dir, "host.mjs")
	os.WriteFile(script, []byte("// host"), 0o644)
	node := filepath.Join(dir, "node")
	// Each start reports a new port so a restart is visible.
	os.WriteFile(node, []byte("#!/bin/sh\nn=$(cat \"$0.count\" 2>/dev/null || echo 4000)\necho $((n+1)) > \"$0.count\"\necho \"AGENT_READY $((n+1))\"\nexec sleep 30\n"), 0o755)

	s := &Supervisor{Script: script}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	done := make(chan struct{})
	go func() { s.Run(ctx); close(done) }()

	if st := waitState(t, s, "disabled"); st.Error == "" {
		t.Fatal("disabled without a reason")
	}
	s.Restart(node)
	first := waitState(t, s, "ready").Port
	s.Restart("")
	deadline := time.Now().Add(10 * time.Second)
	for s.Status().Port == first || s.Status().State != "ready" {
		if time.Now().After(deadline) {
			t.Fatalf("not restarted: %+v", s.Status())
		}
		time.Sleep(20 * time.Millisecond)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(10 * time.Second):
		t.Fatal("Run did not stop")
	}
}
