package rodlog

import "fmt"

// SemanticColors customizes the meaning-based palette without changing the
// original bytes or existing ANSI styling supplied by child processes.
type SemanticColors struct {
	Error string `toml:"error"`
	Warning string `toml:"warning"`
	Success string `toml:"success"`
	Info string `toml:"info"`
	Muted string `toml:"muted"`
	Code string `toml:"code"`
	Location string `toml:"location"`
}

func semanticColor(value, fallback string) string {
	if value == "" { return fallback }
	return value
}

func ParseSemanticColors(input SemanticColors) (SemanticColors, error) {
	fields := []struct {
		name string
		value *string
	}{
		{"error", &input.Error},
		{"warning", &input.Warning},
		{"success", &input.Success},
		{"info", &input.Info},
		{"muted", &input.Muted},
		{"code", &input.Code},
		{"location", &input.Location},
	}
	for _, field := range fields {
		if *field.value == "" { continue }
		normalized, err := ColorSGR(*field.value, false)
		if err != nil { return SemanticColors{}, fmt.Errorf("semantic.%s: %w", field.name, err) }
		*field.value = normalized
	}
	return input, nil
}

func semanticRuleColor(original string, colors SemanticColors) string {
	switch original {
	case "31": return semanticColor(colors.Error, original)
	case "33": return semanticColor(colors.Warning, original)
	case "32": return semanticColor(colors.Success, original)
	case "35": return semanticColor(colors.Code, original)
	case "36": return semanticColor(colors.Location, original)
	case "4;36":
		if colors.Location != "" { return "4;" + colors.Location }
	case "2": return semanticColor(colors.Muted, original)
	}
	return original
}
