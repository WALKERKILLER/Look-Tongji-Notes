// Package agent supervises the Node.js Pi SDK agent host and proxies to it.
package agent

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httputil"
	"net/url"
	"os"
	"os/exec"
	"strings"
	"sync"
	"time"
)

type Status struct {
	State string `json:"state"` // disabled | starting | ready | crashed
	Error string `json:"error,omitempty"`
	Port  int    `json:"port,omitempty"`
}

type Supervisor struct {
	Node   string // node binary
	Script string // agent host entry (host.mjs)
	Env    []string

	mu      sync.Mutex
	status  Status
	proxy   *httputil.ReverseProxy
	logTail []string
}

func (s *Supervisor) Status() Status {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.status
}

func (s *Supervisor) Logs() []string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]string(nil), s.logTail...)
}

func (s *Supervisor) set(st Status) {
	s.mu.Lock()
	s.status = st
	if st.State != "ready" {
		s.proxy = nil
	}
	s.mu.Unlock()
}

func (s *Supervisor) log(line string) {
	s.mu.Lock()
	s.logTail = append(s.logTail, line)
	if len(s.logTail) > 200 {
		s.logTail = s.logTail[len(s.logTail)-200:]
	}
	s.mu.Unlock()
}

// Run starts the host and restarts it with backoff until ctx ends.
func (s *Supervisor) Run(ctx context.Context) {
	if s.Script == "" || s.Node == "" {
		s.set(Status{State: "disabled", Error: "未配置 Node.js 或 agent host"})
		return
	}
	if _, err := os.Stat(s.Script); err != nil {
		s.set(Status{State: "disabled", Error: "agent host 不存在: " + s.Script})
		return
	}
	backoff := time.Second
	for ctx.Err() == nil {
		started := time.Now()
		err := s.once(ctx)
		if ctx.Err() != nil {
			return
		}
		msg := "agent host 已退出"
		if err != nil {
			msg = err.Error()
		}
		s.set(Status{State: "crashed", Error: msg})
		slog.Warn("agent host exited", "err", err)
		if time.Since(started) > time.Minute {
			backoff = time.Second
		}
		select {
		case <-ctx.Done():
			return
		case <-time.After(backoff):
		}
		backoff = min(backoff*2, 30*time.Second)
	}
}

func (s *Supervisor) once(ctx context.Context) error {
	s.set(Status{State: "starting"})
	cmd := exec.CommandContext(ctx, s.Node, s.Script)
	cmd.Env = append(os.Environ(), s.Env...)
	cmd.Cancel = func() error { return cmd.Process.Signal(os.Interrupt) }
	cmd.WaitDelay = 5 * time.Second
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	stderr, _ := cmd.StderrPipe()
	if err := cmd.Start(); err != nil {
		return err
	}
	go s.drain(stderr)
	ready := make(chan int, 1)
	go func() {
		sc := bufio.NewScanner(stdout)
		for sc.Scan() {
			line := sc.Text()
			var port int
			if _, err := fmt.Sscanf(line, "AGENT_READY %d", &port); err == nil {
				ready <- port
				continue
			}
			s.log(line)
		}
	}()
	select {
	case port := <-ready:
		target, _ := url.Parse(fmt.Sprintf("http://127.0.0.1:%d", port))
		p := httputil.NewSingleHostReverseProxy(target)
		p.FlushInterval = -1 // stream SSE immediately
		s.mu.Lock()
		s.status = Status{State: "ready", Port: port}
		s.proxy = p
		s.mu.Unlock()
		slog.Info("agent host ready", "port", port)
	case <-time.After(45 * time.Second):
		cmd.Process.Kill()
		cmd.Wait()
		return fmt.Errorf("agent host 启动超时")
	}
	return cmd.Wait()
}

func (s *Supervisor) drain(r io.Reader) {
	sc := bufio.NewScanner(r)
	for sc.Scan() {
		s.log(sc.Text())
	}
}

// ServeHTTP proxies /agent/* to the host.
func (s *Supervisor) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	p, st := s.proxy, s.status
	s.mu.Unlock()
	if p == nil {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusServiceUnavailable)
		fmt.Fprintf(w, `{"error":%q,"state":%q}`, strings.TrimSpace("助手未就绪 "+st.Error), st.State)
		return
	}
	r.URL.Path = strings.TrimPrefix(r.URL.Path, "/agent")
	p.ServeHTTP(w, r)
}
