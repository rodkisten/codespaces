package main

import (
	"context"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"strings"
	"syscall"

	"github.com/rodkisten/codespaces/packages/rodlog"
)

func run(args []string, stdin io.Reader, stdout, stderr io.Writer) int {
	if len(args) > 0 && args[0] == "version" {
		fmt.Fprintln(stdout, "rodlog v0.1.0-dev")
		return 0
	}
	commandMode := len(args) > 0 && args[0] == "exec"
	if commandMode {
		args = args[1:]
	}
	flags := flag.NewFlagSet("rodlog", flag.ContinueOnError)
	flags.SetOutput(stderr)
	mode := flags.String("mode", env("RODLOG_MODE", "enhance"), "raw|enhance|transform")
	tool := flags.String("tool", env("RODLOG_TOOL", "auto"), "auto|npm|typescript|gcloud|wrangler|docker")
	color := flags.String("color", env("RODLOG_COLOR", "auto"), "auto|always|never")
	if err := flags.Parse(args); err != nil {
		return 2
	}
	if *mode != "raw" && *mode != "enhance" && *mode != "transform" {
		fmt.Fprintln(stderr, "invalid mode:", *mode)
		return 2
	}
	valid := map[string]bool{"auto": true, "npm": true, "typescript": true, "gcloud": true, "wrangler": true, "docker": true}
	if !valid[*tool] {
		fmt.Fprintln(stderr, "invalid tool:", *tool)
		return 2
	}
	if *color != "auto" && *color != "always" && *color != "never" {
		fmt.Fprintln(stderr, "invalid color:", *color)
		return 2
	}
	enableColor := *color == "always" || (*color == "auto" && os.Getenv("NO_COLOR") == "" && os.Getenv("TERM") != "dumb" && isTerminal(stdout))
	engine := rodlog.New(rodlog.Options{Mode: rodlog.Mode(*mode), Tool: rodlog.Tool(*tool), Color: enableColor})
	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if !commandMode {
		if err := engine.Process(ctx, stdin, stdout); err != nil {
			fmt.Fprintln(stderr, err)
			return 1
		}
		return 0
	}
	argv := flags.Args()
	if len(argv) == 0 {
		fmt.Fprintln(stderr, "usage: rodlog exec [flags] -- COMMAND [ARGS...]")
		return 2
	}
	cmd := exec.CommandContext(ctx, argv[0], argv[1:]...)
	// Combined pipe preserves order observed by the reader and the child's exit status.
	pipeReader, pipeWriter := io.Pipe()
	cmd.Stdout = pipeWriter
	cmd.Stderr = pipeWriter
	if err := cmd.Start(); err != nil {
		fmt.Fprintln(stderr, err)
		return 127
	}
	waitCh := make(chan error, 1)
	go func() { err := cmd.Wait(); pipeWriter.Close(); waitCh <- err }()
	processErr := engine.Process(ctx, pipeReader, stdout)
	if processErr != nil {
		fmt.Fprintln(stderr, processErr)
		if cmd.Process != nil {
			_ = cmd.Process.Kill()
		}
	}
	waitErr := <-waitCh
	if processErr != nil {
		return 1
	}
	if waitErr == nil {
		return 0
	}
	if exit, ok := waitErr.(*exec.ExitError); ok {
		return exit.ExitCode()
	}
	fmt.Fprintln(stderr, waitErr)
	return 1
}
func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
func isTerminal(w io.Writer) bool {
	f, ok := w.(*os.File)
	if !ok {
		return false
	}
	s, e := f.Stat()
	return e == nil && (s.Mode()&os.ModeCharDevice) != 0
}
func main() { os.Exit(run(os.Args[1:], os.Stdin, os.Stdout, os.Stderr)) }

var _ = strings.TrimSpace
