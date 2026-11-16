package rodlog

import (
	"fmt"
	"os"
	"strings"
)

// renderDiagnostic formats a structured error with a clear severity, location,
// diagnostic code, and message. Only transform mode uses this presentation.
func renderDiagnostic(d *Diagnostic) []byte {
	heading, color := "✖ ERROR", "31"
	if d.Level == Warning {
		heading, color = "⚠ WARNING", "33"
	} else if d.Level == Info {
		heading, color = "ℹ INFO", "36"
	}
	location := d.File
	if d.Line > 0 {
		location += fmt.Sprintf(":%d", d.Line)
		if d.Column > 0 {
			location += fmt.Sprintf(":%d", d.Column)
		}
	}
	if location == "" {
		location = string(d.Tool)
	}
	code := ""
	if d.Code != "" {
		code = " [" + d.Code + "]"
	}
	message := strings.TrimSpace(d.Message)
	var out strings.Builder
	fmt.Fprintf(&out, "\x1b[1;%sm%s\x1b[0m  \x1b[2m%s\x1b[0m%s\n", color, heading, location, code)
	for _, line := range strings.Split(message, "\n") {
		fmt.Fprintf(&out, "  %s\n", line)
	}
	if d.File != "" && d.Line > 0 && d.Line <= 100000 {
		if frame := diagnosticFrame(d); frame != "" {
			out.WriteString(frame)
		}
	}
	return []byte(out.String())
}
