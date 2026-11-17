package rodlog

import (
	"fmt"
	"regexp"
	"strings"
)

// TypeScript emits quoted type names in TS2322/TS2345 messages. We extract
// them only when the diagnostic code is known; guessing from arbitrary errors
// could produce misleading advice. Chroma and Lip Gloss already handle generic
// syntax and terminal styling, so this layer adds only domain-specific meaning.
var tsTypePair = regexp.MustCompile(`(?i)(?:argument of )?type '([^']+)' is not assignable to (?:type|parameter of type) '([^']+)'`)

// diagnosticExplanation returns a short interpretation, not an automatic fix.
// TypeScript's actual message remains visible and authoritative.
func diagnosticExplanation(d *Diagnostic) string {
	if d.Tool != TypeScript {
		return ""
	}
	switch d.Code {
	case "TS2322", "TS2345":
		if m := tsTypePair.FindStringSubmatch(d.Message); m != nil {
			return fmt.Sprintf("Expected: %s  |  Received: %s", m[2], m[1])
		}
	case "TS2307":
		return "Module could not be resolved. Check the import path, installed dependencies and TypeScript module resolution."
	case "TS7006":
		return "A parameter has an implicit any type. Add an explicit type or improve inference."
	case "TS18048":
		return "This value may be undefined. Narrow the type before accessing it."
	}
	return ""
}

// renderDiagnostic formats a structured error with a clear severity, location,
// diagnostic code, and message. Only transform mode uses this presentation.
func renderDiagnostic(d *Diagnostic) []byte {
	return renderDiagnosticWithTheme(d, SemanticColors{}, DiagnosticIcons{})
}

func renderDiagnosticWithTheme(d *Diagnostic, colors SemanticColors, icons DiagnosticIcons) []byte {
	heading, color := iconOrDefault(icons.Error, "✖") + " ERROR", semanticColor(colors.Error, "31")
	if d.Level == Warning {
		heading, color = iconOrDefault(icons.Warning, "⚠") + " WARNING", semanticColor(colors.Warning, "33")
	} else if d.Level == Info {
		heading, color = iconOrDefault(icons.Info, "ℹ") + " INFO", semanticColor(colors.Info, "36")
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
	fmt.Fprintf(&out, "\x1b[1;%sm%s\x1b[0m  \x1b[%sm%s\x1b[0m%s\n", color, heading, semanticColor(colors.Location, "2"), location, code)
	for _, line := range strings.Split(message, "\n") {
		fmt.Fprintf(&out, "  %s\n", line)
	}
	if d.File != "" && d.Line > 0 && d.Line <= 100000 {
		if frame := diagnosticFrame(d); frame != "" {
			out.WriteString(frame)
		}
	}
	if d.Tool == Vitest || d.Tool == NodeTest {
		if m := runnerAssertion.FindStringSubmatch(message); m != nil {
			// Keep both sides explicit instead of relying on terminal color alone.
			fmt.Fprintf(&out, "  \x1b[%smExpected: %s\x1b[0m\n  \x1b[%smReceived: %s\x1b[0m\n", semanticColor(colors.Success, "32"), m[2], semanticColor(colors.Error, "31"), m[1])
		}
	}
	if explanation := diagnosticExplanation(d); explanation != "" {
		fmt.Fprintf(&out, "  \x1b[%sm%s %s\x1b[0m\n", semanticColor(colors.Info, "36"), iconOrDefault(icons.Explanation, "↳"), explanation)
	}
	if suggestion := diagnosticSuggestion(d); suggestion != "" {
		fmt.Fprintf(&out, "  \x1b[%sm%s %s\x1b[0m\n", semanticColor(colors.Info, "36"), iconOrDefault(icons.Suggestion, "💡"), suggestion)
	}
	return []byte(out.String())
}
