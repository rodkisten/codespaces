// Package rodlog implements streaming output enhancement with conservative tool detection.
package rodlog

import (
	"bufio"
	"context"
	"fmt"
	"io"
	"regexp"
	"strings"
)

type Mode string

const (
	Raw       Mode = "raw"
	Enhance   Mode = "enhance"
	Transform Mode = "transform"
)

type Tool string

const (
	Auto       Tool = "auto"
	NPM        Tool = "npm"
	TypeScript Tool = "typescript"
	GCloud     Tool = "gcloud"
	Wrangler   Tool = "wrangler"
	Docker     Tool = "docker"
	Generic    Tool = "generic"
)

type Level string

const (
	Info    Level = "info"
	Warning Level = "warning"
	Error   Level = "error"
	Success Level = "success"
)

type Event struct {
	Sequence uint64
	Tool     Tool
	Level    Level
	Text     string
}
type Options struct {
	Mode    Mode
	Tool    Tool
	Color   bool
	MaxLine int
}
type Renderer interface{ Render(Event) ([]byte, error) }
type Engine struct {
	Options  Options
	Renderer Renderer
}

var ansi = regexp.MustCompile("\x1b\\[[0-9;]*[A-Za-z]")
var patterns = map[Tool][]string{
	NPM:        {"npm ERR!", "npm warn", "npm error", "npm run", "npm notice"},
	TypeScript: {"error TS", "warning TS", "tsc ", ".tsx(", ".ts("},
	GCloud:     {"gcloud ", "ERROR: (gcloud", "WARNING: (gcloud", "Updated property", "Deploying container"},
	Wrangler:   {"wrangler ", "cloudflare", "workers.dev", "wrangler.toml", "wrangler.jsonc"},
	Docker:     {"docker ", "Step 1/", "=> [", "dockerfile:", "exporting layers", "writing image"},
}

func Detect(s string) Tool {
	lower := strings.ToLower(s)
	for _, tool := range []Tool{TypeScript, NPM, GCloud, Wrangler, Docker} {
		for _, token := range patterns[tool] {
			if strings.Contains(lower, strings.ToLower(token)) {
				return tool
			}
		}
	}
	return Generic
}
func Classify(s string) Level {
	lower := strings.ToLower(ansi.ReplaceAllString(s, ""))
	switch {
	case strings.Contains(lower, "error"), strings.Contains(lower, "npm err!"), strings.Contains(lower, "failed"), strings.Contains(lower, "fatal"), strings.Contains(lower, "✘"):
		return Error
	case strings.Contains(lower, "warn"), strings.Contains(lower, "deprecated"):
		return Warning
	case strings.Contains(lower, "success"), strings.Contains(lower, "done"), strings.Contains(lower, "✔"), strings.Contains(lower, "✓"):
		return Success
	default:
		return Info
	}
}
func New(opts Options) *Engine {
	if opts.Mode == "" {
		opts.Mode = Enhance
	}
	if opts.Tool == "" {
		opts.Tool = Auto
	}
	if opts.MaxLine <= 0 {
		opts.MaxLine = 1024 * 1024
	}
	return &Engine{Options: opts}
}

// Process preserves input order and delimiters, including CR progress updates.
// In raw mode it copies bytes unchanged. Renderer errors fall back to original bytes.
func (e *Engine) Process(ctx context.Context, src io.Reader, dst io.Writer) error {
	if e.Options.Mode == Raw {
		_, err := io.Copy(dst, src)
		return err
	}
	reader := bufio.NewReaderSize(src, 32*1024)
	var seq uint64
	var current Tool = Generic
	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		line, err := reader.ReadSlice('\n')
		if err == bufio.ErrBufferFull {
			// Long lines are emitted in bounded fragments, never silently truncated.
			err = nil
		}
		if len(line) > 0 {
			seq++
			text := string(line)
			if e.Options.Tool != Auto {
				current = e.Options.Tool
			} else if detected := Detect(text); detected != Generic {
				current = detected
			}
			event := Event{Sequence: seq, Tool: current, Level: Classify(text), Text: text}
			var out []byte
			var renderErr error
			if e.Renderer != nil {
				out, renderErr = e.Renderer.Render(event)
			} else {
				out = Render(event, e.Options)
			}
			if renderErr != nil {
				out = line
			}
			if _, writeErr := dst.Write(out); writeErr != nil {
				return fmt.Errorf("write output: %w", writeErr)
			}
		}
		if err == io.EOF {
			return nil
		}
		if err != nil {
			return err
		}
	}
}
func Render(ev Event, opts Options) []byte {
	if opts.Mode == Raw || !opts.Color {
		return []byte(ev.Text)
	}
	text := ev.Text
	if ansi.MatchString(text) {
		return []byte(text)
	}
	// Tool-aware spans take precedence over whole-line severity styling.
	highlighted := highlightLine(text)
	if highlighted != text {
		return []byte(highlighted)
	}
	color := ""
	switch ev.Level {
	case Error:
		color = "31"
	case Warning:
		color = "33"
	case Success:
		color = "32"
	default:
		if opts.Mode == Transform && ev.Tool != Generic {
			color = "36"
		}
	}
	if color == "" {
		return []byte(text)
	}
	suffix := ""
	body := text
	if strings.HasSuffix(body, "\n") {
		body = strings.TrimSuffix(body, "\n")
		suffix = "\n"
	}
	if strings.HasSuffix(body, "\r") {
		body = strings.TrimSuffix(body, "\r")
		suffix = "\r" + suffix
	}
	return []byte("\x1b[" + color + "m" + body + "\x1b[0m" + suffix)
}
