package rodlog

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"

	"github.com/charmbracelet/lipgloss"
)

// JSONTable renders a compact summary of a JSON object or array of objects.
// The original JSON remains available in raw/enhance mode.
func JSONTable(input string, color bool) (string, bool) {
	var payload any
	if err := json.Unmarshal([]byte(input), &payload); err != nil {
		return "", false
	}
	var records []map[string]any
	switch value := payload.(type) {
	case map[string]any:
		records = []map[string]any{value}
	case []any:
		for _, item := range value {
			record, ok := item.(map[string]any)
			if !ok {
				return "", false
			}
			records = append(records, record)
		}
	default:
		return "", false
	}
	if len(records) == 0 {
		return "", false
	}
	priority := []string{"name", "status", "state", "id", "region", "url", "version", "created", "updated", "message"}
	seen := map[string]bool{}
	var keys []string
	for _, key := range priority {
		for _, record := range records {
			if _, ok := record[key]; ok && !seen[key] {
				keys = append(keys, key)
				seen[key] = true
			}
		}
	}
	var extra []string
	for _, record := range records {
		for key := range record {
			if !seen[key] {
				extra = append(extra, key)
				seen[key] = true
			}
		}
	}
	sort.Strings(extra)
	keys = append(keys, extra...)
	if len(keys) > 6 {
		keys = keys[:6]
	}
	header := strings.Join(keys, "  │  ")
	if color {
		header = lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("12")).Render(header)
	}
	var output strings.Builder
	output.WriteString(header)
	output.WriteByte('\n')
	for i, record := range records {
		if i >= 30 {
			fmt.Fprintf(&output, "… %d additional records\n", len(records)-i)
			break
		}
		values := make([]string, 0, len(keys))
		for _, key := range keys {
			value := fmt.Sprint(record[key])
			if record[key] == nil {
				value = "—"
			}
			value = strings.ReplaceAll(strings.ReplaceAll(value, "\n", " "), "\r", " ")
			if len(value) > 60 {
				value = value[:57] + "..."
			}
			values = append(values, value)
		}
		output.WriteString(strings.Join(values, "  │  "))
		output.WriteByte('\n')
	}
	return output.String(), true
}
