package rodlog

import (
	"encoding/json"
	"fmt"
	"strings"
)

// JSONLRenderer emits one machine-readable event per input frame.
// The original text is included to allow lossless downstream inspection.
type JSONLRenderer struct{}

func (JSONLRenderer) Render(event Event) ([]byte, error) {
	data, err := json.Marshal(event)
	if err != nil {
		return nil, err
	}
	return append(data, '\n'), nil
}

// AnnotationRenderer writes GitHub Actions workflow commands for diagnostics.
// Unrecognized output is deliberately ignored.
type AnnotationRenderer struct{}

func (AnnotationRenderer) Render(event Event) ([]byte, error) {
	d := event.Diagnostic
	if d == nil || (d.Level != Error && d.Level != Warning) {
		return nil, nil
	}
	kind := "error"
	if d.Level == Warning {
		kind = "warning"
	}
	properties := []string{}
	if d.File != "" {
		properties = append(properties, "file="+escapeAnnotationProperty(d.File))
	}
	if d.Line > 0 {
		properties = append(properties, fmt.Sprintf("line=%d", d.Line))
	}
	if d.Column > 0 && d.Line > 0 {
		properties = append(properties, fmt.Sprintf("col=%d", d.Column))
	}
	if d.Code != "" {
		properties = append(properties, "title="+escapeAnnotationProperty(d.Code))
	}
	header := "::" + kind
	if len(properties) > 0 {
		header += " " + strings.Join(properties, ",")
	}
	return []byte(header + "::" + escapeAnnotationData(d.Message) + "\n"), nil
}

func escapeAnnotationData(s string) string {
	r := strings.NewReplacer("%", "%25", "\r", "%0D", "\n", "%0A")
	return r.Replace(s)
}
func escapeAnnotationProperty(s string) string {
	return strings.NewReplacer(":", "%3A", ",", "%2C").Replace(escapeAnnotationData(s))
}
