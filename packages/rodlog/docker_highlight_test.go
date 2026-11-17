package rodlog

import (
	"strings"
	"testing"
)

// Docker status coloring must not destroy timestamps or compose prefixes.
func TestDockerSemanticHighlight(t *testing.T) {
	input := "api-1 | 2026-11-16T12:00:00Z health: unhealthy\n"
	got := string(Render(Event{Tool: Docker, Level: Info, Text: input}, Options{Mode: Enhance, Color: true}))
	if !strings.Contains(got, "api-1 | 2026-11-16T12:00:00Z ") || !strings.Contains(got, "\x1b[31mhealth: unhealthy\x1b[0m") {
		t.Fatalf("unexpected Docker highlighting: %q", got)
	}
	if raw := string(Render(Event{Tool: Docker, Text: input}, Options{Mode: Raw, Color: true})); raw != input {
		t.Fatalf("raw output changed: %q", raw)
	}
	if plain := string(Render(Event{Tool: Docker, Text: input}, Options{Mode: Enhance, Color: false})); plain != input {
		t.Fatalf("no-color output changed: %q", plain)
	}
}

func TestDockerfileSyntaxDetection(t *testing.T) {
	if got := syntaxLanguage("FROM alpine:3.20"); got != "dockerfile" {
		t.Fatalf("expected Dockerfile lexer, got %q", got)
	}
	if got := syntaxLanguage("FROM a previous project"); got != "dockerfile" {
		t.Fatalf("expected Dockerfile lexer, got %q", got)
	}
}

// BuildKit statuses should be legible while step numbers and timing survive.
func TestDockerBuildSteps(t *testing.T) {
	cases := []struct {
		line    string
		colored string
	}{
		{"#12 CACHED\n", "\x1b[2mCACHED\x1b[0m"},
		{"#13 DONE 0.4s\n", "\x1b[32mDONE\x1b[0m"},
		{"#14 ERROR: process exited\n", "\x1b[31mERROR\x1b[0m"},
		{"#15 [stage-0 2/3] exporting layers\n", "\x1b[36mexporting\x1b[0m"},
	}
	for _, tc := range cases {
		got := string(Render(Event{Tool: Docker, Text: tc.line}, Options{Mode: Enhance, Color: true}))
		if !strings.Contains(got, tc.colored) {
			t.Errorf("step %q missing %q in %q", tc.line, tc.colored, got)
		}
		if raw := string(Render(Event{Tool: Docker, Text: tc.line}, Options{Mode: Raw, Color: true})); raw != tc.line {
			t.Errorf("raw step changed: %q", raw)
		}
	}
}
