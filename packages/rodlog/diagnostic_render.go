package rodlog

import (
	"fmt"
	"strings"
)

func renderDiagnostic(d *Diagnostic) []byte {
	heading, color := "✖", "31"
	if d.Level == Warning {
		heading, color = "⚠", "33"
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
	return []byte(fmt.Sprintf("\x1b[1;%sm%s %s%s\x1b[0m\n  %s\n", color, heading, location, code, strings.TrimSpace(d.Message)))
}
