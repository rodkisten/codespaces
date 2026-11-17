package rodlog

import (
	"fmt"
	"strings"
	"unicode/utf8"

	"github.com/alecthomas/chroma/v2/styles"
)

type DiagnosticIcons struct {
	Error string `toml:"error"`
	Warning string `toml:"warning"`
	Info string `toml:"info"`
	Suggestion string `toml:"suggestion"`
	Explanation string `toml:"explanation"`
}

type SyntaxTheme struct {
	Style string `toml:"style"`
}

func iconOrDefault(icon, fallback string) string {
	if icon == "" { return fallback }
	return icon
}

// Reject control sequences so icons cannot inject terminal commands.
func ParseDiagnosticIcons(input DiagnosticIcons) (DiagnosticIcons, error) {
	for name, icon := range map[string]string{
		"error": input.Error, "warning": input.Warning, "info": input.Info,
		"suggestion": input.Suggestion, "explanation": input.Explanation,
	} {
		if !utf8.ValidString(icon) || utf8.RuneCountInString(icon) > 12 {
			return DiagnosticIcons{}, fmt.Errorf("icons.%s: expected at most 12 valid Unicode characters", name)
		}
		for _, r := range icon {
			if r < 32 || r == 127 || r >= 0x80 && r <= 0x9f || r == 0x2028 || r == 0x2029 {
				return DiagnosticIcons{}, fmt.Errorf("icons.%s: control characters are not allowed", name)
			}
		}
	}
	return input, nil
}

func ParseSyntaxTheme(input SyntaxTheme) (SyntaxTheme, error) {
	if input.Style == "" { return input, nil }
	if strings.TrimSpace(input.Style) != input.Style || styles.Get(input.Style) == nil {
		return SyntaxTheme{}, fmt.Errorf("syntax.style: unknown Chroma style %q", input.Style)
	}
	return input, nil
}
