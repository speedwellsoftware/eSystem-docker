package main

import (
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/exec"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

var (
	idleTimeout    time.Duration
	listenPort     string
	forwardAddress string
	commandArgs    []string
	verbose        bool

	startProcessChan = make(chan struct{}, 1)
	activityPingChan = make(chan struct{}, 1)
	quitChan         = make(chan struct{})

	lastActivity time.Time
	processLock  sync.Mutex
	processCmd   *exec.Cmd
	// expectedExit is set (under processLock) immediately before we SIGTERM the
	// backend for idle timeout, so the cmd.Wait watcher can tell a deliberate
	// shutdown apart from a genuine crash and keep the proxy alive.
	expectedExit atomic.Bool

	activeConnections atomic.Int64
)

func main() {
	var idleStr, listenStr, forwardStr, healthStr string

	flag.StringVar(&idleStr, "idle", "", "Idle timeout duration")
	flag.StringVar(&listenStr, "listen", "", "Port to listen on")
	flag.StringVar(&forwardStr, "forward", "", "Address to forward to")
	flag.StringVar(&healthStr, "health", "", "Optional HTTP health listener; answers /ping without waking the backend")
	flag.BoolVar(&verbose, "v", false, "Enable verbose logging")
	flag.Parse()

	if idleStr == "" || listenStr == "" || forwardStr == "" {
		log.Fatalf("[proxy] Missing required flags: -idle, -listen, -forward")
	}

	commandArgs = flag.Args()
	if len(commandArgs) == 0 {
		log.Fatalf("[proxy] No command provided to run")
	}

	var err error
	idleTimeout, err = time.ParseDuration(idleStr)
	if err != nil {
		log.Fatalf("[proxy] Invalid idle duration: %v", err)
	}

	listenPort = listenStr
	forwardAddress = forwardStr

	lastActivity = time.Now()
	go processManager()

	if healthStr != "" {
		go healthServer(healthStr)
	}

	log.Println("[proxy] Starting lazy proxy on", listenPort)
	ln, err := net.Listen("tcp", listenPort)
	if err != nil {
		log.Fatalf("[proxy] Failed to listen on %s: %v", listenPort, err)
	}
	defer ln.Close()

	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("[proxy] Failed to accept connection: %v", err)
			continue
		}
		if verbose {
			log.Printf("[proxy] New connection from %s", conn.RemoteAddr())
		}
		go handleConnection(conn)
	}
}

func processManager() {
	for {
		select {
		case <-startProcessChan:
			processLock.Lock()
			if processCmd == nil {
				cmd := exec.Command(commandArgs[0], commandArgs[1:]...)
				cmd.Stdout = os.Stdout
				cmd.Stderr = os.Stderr
				cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

				if err := cmd.Start(); err != nil {
					log.Fatalf("[proxy] Failed to start backend: %v", err)
				}
				processCmd = cmd
				if verbose {
					log.Println("[proxy] Backend process started")
				}
				go func() {
					err := cmd.Wait()
					if expectedExit.Swap(false) {
						// We killed it for idle timeout. processManager has
						// already cleared processCmd, so the next connection
						// relaunches the backend. Keep the proxy running.
						log.Printf("[proxy] Backend stopped (idle); proxy staying up")
						return
					}
					log.Printf("[proxy] Backend crashed: %v", err)
					os.Exit(1)
				}()
			}
			processLock.Unlock()
		case <-activityPingChan:
			lastActivity = time.Now()
		case <-time.After(5 * time.Second): // check every 5 seconds
			processLock.Lock()
			if processCmd != nil && activeConnections.Load() == 0 && time.Since(lastActivity) > idleTimeout {
				if verbose {
					log.Println("[proxy] Idle timeout reached, killing backend")
				}
				// Flag the shutdown as deliberate before signalling, so the
				// cmd.Wait watcher doesn't mistake it for a crash and exit.
				expectedExit.Store(true)
				_ = syscall.Kill(-processCmd.Process.Pid, syscall.SIGTERM)
				processCmd = nil
			}
			processLock.Unlock()
		case <-quitChan:
			return
		}
	}
}

// healthServer answers monitoring probes on a separate port. It only reads
// state — it must never touch startProcessChan or activityPingChan, so probes
// neither wake a sleeping backend nor keep a running one alive.
func healthServer(addr string) {
	mux := http.NewServeMux()
	mux.HandleFunc("/ping", func(w http.ResponseWriter, r *http.Request) {
		processLock.Lock()
		running := processCmd != nil
		processLock.Unlock()
		state := "sleeping"
		if running {
			state = "running"
		}
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprintf(w, "{\"proxy\":\"ok\",\"backend\":%q,\"connections\":%d}\n", state, activeConnections.Load())
	})
	log.Println("[proxy] Health listener on", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatalf("[proxy] Health listener failed: %v", err)
	}
}

func handleConnection(client net.Conn) {
	activeConnections.Add(1)
	defer activeConnections.Add(-1)

	defer client.Close()
	select {
	case startProcessChan <- struct{}{}:
	default:
	}

	var server net.Conn
	for {
		var err error
		server, err = net.Dial("tcp", forwardAddress)
		if err == nil {
			break
		}
		time.Sleep(100 * time.Millisecond)
	}
	defer server.Close()

	activityPingChan <- struct{}{}

	wg := sync.WaitGroup{}
	wg.Add(2)
	go func() {
		defer wg.Done()
		io.Copy(server, client)
		activityPingChan <- struct{}{}
	}()
	go func() {
		defer wg.Done()
		io.Copy(client, server)
		activityPingChan <- struct{}{}
	}()
	wg.Wait()
}
