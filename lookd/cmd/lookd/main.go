// lookd is the Look Studio daemon: Tongji Look auth with automatic renewal,
// course API, high-throughput downloader, transcription and the library index.
// The Flutter app starts it and talks to it over a token-protected local API.
package main

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"lookstudio/lookd/internal/agent"
	"lookstudio/lookd/internal/agentenv"
	"lookstudio/lookd/internal/asr"
	"lookstudio/lookd/internal/canvas"
	"lookstudio/lookd/internal/datasync"
	"lookstudio/lookd/internal/dl"
	"lookstudio/lookd/internal/events"
	"lookstudio/lookd/internal/jobs"
	"lookstudio/lookd/internal/library"
	"lookstudio/lookd/internal/localasr"
	"lookstudio/lookd/internal/mineru"
	"lookstudio/lookd/internal/notify"
	"lookstudio/lookd/internal/notion"
	"lookstudio/lookd/internal/rootfs"
	"lookstudio/lookd/internal/server"
	"lookstudio/lookd/internal/store"
	"lookstudio/lookd/internal/tongji"
)

func defaultDataDir() string {
	if d := os.Getenv("XDG_DATA_HOME"); d != "" {
		return filepath.Join(d, "look-studio")
	}
	home, _ := os.UserHomeDir()
	return filepath.Join(home, ".local", "share", "look-studio")
}

func defaultLibrary() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "LookStudio")
}

// unpack is how the Android app installs its Linux workspace:
// lookd unpack <archive.tar.gz> <dir> [sha256]. It prints "PROGRESS <bytes>"
// lines and runs without the guest, straight from the app's library folder.
func unpack(args []string) {
	if len(args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: lookd unpack <archive.tar.gz> <dir> [sha256]")
		os.Exit(2)
	}
	f, err := os.Open(args[0])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	defer f.Close()
	want := ""
	if len(args) > 2 {
		want = args[2]
	}
	var last int64
	err = rootfs.Unpack(f, args[1], want, func(n int64) {
		if n-last >= 1<<20 {
			last = n
			fmt.Printf("PROGRESS %d\n", n)
		}
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Println("DONE")
}

// prune is how release packaging slims the bundled agent:
// lookd prune <node_modules>... deletes declarations and source maps
// with the same rule as the in-app runtime setup.
func prune(dirs []string) {
	var freed int64
	for _, d := range dirs {
		freed += agentenv.PruneModules(d)
	}
	fmt.Printf("freed %d MB\n", freed>>20)
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "unpack" {
		unpack(os.Args[2:])
		return
	}
	if len(os.Args) > 1 && os.Args[1] == "prune" {
		prune(os.Args[2:])
		return
	}
	dataDir := flag.String("data", defaultDataDir(), "private state (session, keys, agent config)")
	libRoot := flag.String("library", "", "library root (courses, notes, library.db)")
	addr := flag.String("addr", "127.0.0.1:0", "listen address")
	node := flag.String("node", "", "node binary for the agent host")
	agentScript := flag.String("agent", "", "agent host entry script")
	watchStdin := flag.Bool("exit-on-stdin-eof", false, "exit when the parent closes stdin")
	flag.Parse()

	slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelInfo})))
	if err := run(*dataDir, *libRoot, *addr, *node, *agentScript, *watchStdin); err != nil {
		slog.Error("lookd failed", "err", err)
		os.Exit(1)
	}
}

type config struct {
	LibraryRoot string `json:"library_root"`
}

func run(dataDir, libRoot, addr, node, agentScript string, watchStdin bool) error {
	if err := os.MkdirAll(dataDir, 0o700); err != nil {
		return err
	}
	cfgPath := filepath.Join(dataDir, "config.json")
	var cfg config
	if b, err := os.ReadFile(cfgPath); err == nil {
		json.Unmarshal(b, &cfg)
	}
	if libRoot != "" {
		cfg.LibraryRoot = libRoot
	}
	if cfg.LibraryRoot == "" {
		cfg.LibraryRoot = defaultLibrary()
	}
	b, _ := json.MarshalIndent(cfg, "", "  ")
	os.WriteFile(cfgPath, b, 0o600)

	token := os.Getenv("LOOKD_TOKEN")
	if token == "" {
		var t [24]byte
		rand.Read(t[:])
		token = hex.EncodeToString(t[:])
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if watchStdin {
		go func() {
			io.Copy(io.Discard, os.Stdin)
			slog.Info("parent closed stdin, shutting down")
			stop()
		}()
	}

	if err := os.MkdirAll(cfg.LibraryRoot, 0o755); err != nil {
		return err
	}
	st, err := store.Open(filepath.Join(cfg.LibraryRoot, "library.db"))
	if err != nil {
		return err
	}
	defer st.Close()
	lib, err := library.Open(cfg.LibraryRoot, st)
	if err != nil {
		return err
	}

	bus := events.New()
	tongji.KeyPath = filepath.Join(dataDir, "seal.key")
	sess := tongji.NewSession(filepath.Join(dataDir, "session.json"), func(s tongji.AuthState) { bus.Publish("auth", s) })
	client := &tongji.Client{S: sess}
	eng := dl.New(sess.Transport(), dl.Options{MaxConns: 8})
	mgr := jobs.New(st, lib, client, eng, asr.NewPool(filepath.Join(dataDir, "asr-usage.json")), bus)

	ln, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}
	port := ln.Addr().(*net.TCPAddr).Port
	base := fmt.Sprintf("http://127.0.0.1:%d", port)

	rt := &agentenv.Manager{Dir: filepath.Join(dataDir, "runtime"), FlagNode: node,
		Publish: func(in agentenv.Install) { bus.Publish("runtime", in) }}
	if agentScript != "" {
		rt.AgentDir = filepath.Dir(filepath.Dir(agentScript)) // agent/src/host.mjs → agent
	}
	node, _ = rt.Node() // -node, else the Node.js an in-app install left
	sup := &agent.Supervisor{Node: node, Script: agentScript, Env: []string{
		"LOOKD_URL=" + base, "LOOKD_TOKEN=" + token,
		"AGENT_DATA_DIR=" + filepath.Join(dataDir, "agent"), "LIBRARY_ROOT=" + cfg.LibraryRoot,
	}}
	mgr.MinerU = mineru.NewService(filepath.Join(dataDir, "mineru.json"), tongji.Seal, tongji.Unseal)
	rt.Restart = sup.Restart
	local := &localasr.Manager{Dir: filepath.Join(dataDir, "asr")}
	srv := &server.Server{Token: token, Sess: sess, Cl: client, St: st, Lib: lib, Jobs: mgr, Eng: eng, Bus: bus, Agent: sup, Runtime: rt, Ctx: ctx, MinerU: mgr.MinerU, Local: local}
	local.Publish = srv.OnLocalASR
	srv.Notes = notify.Open(filepath.Join(dataDir, "notifications.json"), func(it notify.Item) { bus.Publish("notification", it) })
	srv.ApplySettings(ctx)

	go sess.Run(ctx)
	go mgr.Run(ctx)
	srv.Canvas = &canvas.Service{Dir: dataDir, Transport: sess.Transport(), AuthFor: srv.CanvasAuth,
		Notify: srv.Notes.Add, Publish: bus.Publish}
	srv.Notion = &notion.Service{Path: filepath.Join(dataDir, "notion.json"), Docs: srv.NotionDocs, Publish: bus.Publish,
		HC: &http.Client{Timeout: 2 * time.Minute, Transport: sess.Transport()}}
	srv.Data = &datasync.Service{Roots: datasync.Roots{Library: cfg.LibraryRoot, Data: dataDir}, App: server.Version,
		State: srv.UserState, MergeState: srv.MergeUserState, Changed: srv.DataArrived, Publish: bus.Publish,
		Seal: tongji.Seal, Unseal: tongji.Unseal}
	go srv.Data.Run(ctx)
	go srv.RunWatcher(ctx)
	go sup.Run(ctx)
	go func() {
		t := time.NewTicker(2 * time.Second)
		defer t.Stop()
		last := sup.Status()
		for {
			select {
			case <-ctx.Done():
				return
			case <-t.C:
				if cur := sup.Status(); cur != last {
					last = cur
					bus.Publish("agent", cur)
				}
			}
		}
	}()

	hs := &http.Server{Handler: srv.Handler(), ReadHeaderTimeout: 10 * time.Second}
	go func() {
		<-ctx.Done()
		sctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
		defer cancel()
		hs.Shutdown(sctx)
	}()
	ready, _ := json.Marshal(map[string]any{"port": port, "token": token, "library": cfg.LibraryRoot, "version": server.Version})
	fmt.Printf("LOOKD_READY %s\n", ready)
	os.Stdout.Sync()
	slog.Info("lookd listening", "addr", ln.Addr().String(), "library", cfg.LibraryRoot)
	if err := hs.Serve(ln); err != nil && err != http.ErrServerClosed {
		return err
	}
	return nil
}
