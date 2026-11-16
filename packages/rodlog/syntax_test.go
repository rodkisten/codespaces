package rodlog

import (
	"strings"
	"testing"
)

func TestChromaJSONOutput(t *testing.T) {
	input := "{\"error\":\"failed\",\"code\":42}"
	output, err := SyntaxHighlight(input, "json")
	if err != nil {
		t.Fatal(err)
	}
	if got := stripColors(output); got != input {
		t.Fatalf("Chroma changed the JSON payload: %q", got)
	}
	if !strings.Contains(output, "\x1b[") {
		t.Fatalf("expected Chroma ANSI colors, got %q", output)
	}
	t.Logf("🎨 Chroma JSON:\n%s", output)
}

func TestLipGlossSeverity(t *testing.T) {
	output := StyleSeverity("ERROR", Error)
	if !strings.Contains(output, "ERROR") {
		t.Fatalf("Lip Gloss lost severity text: %q", output)
	}
	t.Logf("🎨 Lip Gloss severity: %s", output)
}

func TestSyntaxLanguage(t *testing.T) {
	if got := syntaxLanguage("{\"ok\":true}\n"); got != "json" {
		t.Fatalf("expected JSON, got %q", got)
	}
	if got := syntaxLanguage("npm ERR! broken"); got != "" {
		t.Fatalf("expected semantic fallback, got %q", got)
	}
}
