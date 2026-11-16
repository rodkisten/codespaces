package rodlog

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestJSONLRenderer(t *testing.T) {
	event := Event{Sequence: 3, Tool: TypeScript, Level: Error, Text: "bad\n", Diagnostic: &Diagnostic{Tool: TypeScript, Level: Error, Code: "TS2322", Message: "bad"}}
	output, err := (JSONLRenderer{}).Render(event)
	if err != nil {
		t.Fatal(err)
	}
	var decoded Event
	if err := json.Unmarshal(output, &decoded); err != nil {
		t.Fatal(err)
	}
	if decoded.Text != event.Text || decoded.Diagnostic.Code != "TS2322" {
		t.Fatalf("unexpected event: %+v", decoded)
	}
}

func TestAnnotationRenderer(t *testing.T) {
	event := Event{Diagnostic: &Diagnostic{Tool: TypeScript, Level: Error, File: "src/a,b.ts", Line: 12, Column: 3, Code: "TS2322", Message: "bad\nvalue%"}}
	output, err := (AnnotationRenderer{}).Render(event)
	if err != nil {
		t.Fatal(err)
	}
	expected := "::error file=src/a%2Cb.ts,line=12,col=3,title=TS2322::bad%0Avalue%25\n"
	if string(output) != expected {
		t.Fatalf("got %q, want %q", output, expected)
	}
	output, err = (AnnotationRenderer{}).Render(Event{Text: "normal"})
	if err != nil || strings.TrimSpace(string(output)) != "" {
		t.Fatalf("unrecognized output must be ignored: %q %v", output, err)
	}
}
