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
	Node   string // node binary; change it with Restart once running
	Script string // agent host entry (host.mjs)
	Env    []string

	mu      sync.Mutex
	status  Status
	proxy   *httputil.ReverseProxy
	logTail []string
	wake    chan struct{} // Restart signals the run loop
	stopRun context.CancelFunc
}

func (s *Supervisor) wakeCh() chan struct{} {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.wake == nil {
		s.wake = make(chan struct{}, 1)
	}
	return s.wake
}

// Restart stops the running host, if any, and starts it again with node
// (unchanged when empty). A supervisor waiting for Node.js starts now.
func (s *Supervisor) Restart(node string) {
	wake := s.wakeCh()
	s.mu.Lock()
	if node != "" {
		s.Node = node
	}
	stop := s.stopRun
	s.mu.Unlock()
	select {
	case wake <- struct{}{}:
	default:
	}
	if stop != nil {
		stop()
	}
}

func (s *Supervisor) config() (node, script string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.Node, s.Script
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
// Run keeps the agent host running until ctx ends, restarting it with a
// growing delay after a crash. Without Node.js or the script it reports
// disabled and waits for Restart.
func (s *Supervisor) Run(ctx context.Context) {
	wake := s.wakeCh()
	backoff := time.Second
	for ctx.Err() == nil {
		node, script := s.config()
		var why string
		if script == "" {
			why = "找不到助手程序（agent/src/host.mjs）"
		} else if _, err := os.Stat(script); err != nil {
			why = "agent host 不存在: " + script
		} else if node == "" {
			why = "未找到 Node.js"
		}
		if why != "" {
			s.set(Status{State: "disabled", Error: why})
			select {
			case <-ctx.Done():
				return
			case <-wake:
				continue
			}
		}
		select { // a Restart before this start is already served by it
		case <-wake:
		default:
		}
		started := time.Now()
		octx, cancel := context.WithCancel(ctx)
		s.mu.Lock()
		s.stopRun = cancel
		s.mu.Unlock()
		err := s.once(octx, node, script)
		cancel()
		s.mu.Lock()
		s.stopRun = nil
		s.mu.Unlock()
		if ctx.Err() != nil {
			return
		}
		if octx.Err() != nil { // Restart
			backoff = time.Second
			continue
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
		case <-wake:
			backoff = time.Second
			continue
		case <-time.After(backoff):
		}
		backoff = min(backoff*2, 30*time.Second)
	}
}

func (s *Supervisor) once(ctx context.Context, node, script string) error {
	s.set(Status{State: "starting"})
	cmd := exec.CommandContext(ctx, node, script)
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
