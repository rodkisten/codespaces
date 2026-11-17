package rodlog

import (
	"strings"

	"github.com/alecthomas/chroma/v2/quick"
	"github.com/charmbracelet/lipgloss"
)

// SyntaxHighlight uses Chroma lexers for structured log payloads.
// The existing diagnostic renderer remains the fallback for ordinary log lines.
func SyntaxHighlight(text, language string) (string, error) {
	var out strings.Builder
	if err := quick.Highlight(&out, text, language, "terminal16m", "monokai"); err != nil {
		return text, err
	}
	return out.String(), nil
}

// StyleSeverity uses Lip Gloss for terminal presentation without changing the
// semantic classification performed by tool adapters.
func StyleSeverity(text string, level Level) string {
	var color string
	switch level {
	case Error:
		color = "9"
	case Warning:
		color = "11"
	case Success:
		color = "10"
	default:
		return text
	}
	return lipgloss.NewStyle().Foreground(lipgloss.Color(color)).Render(text)
}

func syntaxLanguage(text string) string {
	trimmed := strings.TrimSpace(text)
	if strings.HasPrefix(trimmed, "{") && strings.HasSuffix(trimmed, "}") {
		return "json"
	}
	if strings.HasPrefix(trimmed, "[") && strings.HasSuffix(trimmed, "]") {
		return "json"
	}
	if strings.HasPrefix(trimmed, "$ ") || strings.HasPrefix(trimmed, "#!/bin/bash") || strings.HasPrefix(trimmed, "#!/bin/sh") {
		return "bash"
	}
	if dockerfileInstruction.MatchString(trimmed) {
		return "dockerfile"
	}
	if strings.HasPrefix(trimmed, "const ") || strings.HasPrefix(trimmed, "interface ") || strings.HasPrefix(trimmed, "type ") || strings.HasPrefix(trimmed, "export ") {
		return "typescript"
	}
	if strings.HasPrefix(trimmed, "---\n") && strings.Contains(trimmed, "\n") {
		return "yaml"
	}
	return ""
}
