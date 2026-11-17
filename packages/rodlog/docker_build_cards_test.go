package rodlog

import (
	"bytes"
	"context"
	"strings"
	"testing"
)

func TestDockerBuildStepCards(t *testing.T) {
	input := "#9 [builder 1/3] FROM node:22\n#9 DONE 0.1s\n#12 [builder 2/3] RUN npm ci\n#12 [builder 2/3] RUN npm ci\n#12 DONE 2.3s\n"
	var output bytes.Buffer
	if err := New(Options{Mode: Enhance, Tool: Docker, Color: true}).Process(context.Background(), strings.NewReader(input), &output); err != nil {
		t.Fatal(err)
	}
	got := output.String()
	for _, expected := range []string{"STEP 1", "STEP 2", "FROM", "RUN", "DONE", "────────────────"} {
		if !strings.Contains(got, expected) {
			t.Errorf("missing %q in %q", expected, got)
		}
	}
	if strings.Contains(got, "#9 [builder") || strings.Contains(got, "#12 [builder") {
		t.Errorf("raw header leaked: %q", got)
	}
	if strings.Count(got, "STEP 2") != 1 {
		t.Errorf("duplicate card: %q", got)
	}
	if !strings.Contains(got, "#12 [builder 2/3] RUN npm ci") {
		t.Errorf("repeated header was silently dropped: %q", got)
	}
}

func TestDockerBuildStepCardsRaw(t *testing.T) {
	input := "#9 [builder 1/3] FROM node:22\n"
	for _, opts := range []Options{{Mode: Raw, Tool: Docker, Color: true}, {Mode: Enhance, Tool: Docker, Color: false}} {
		var output bytes.Buffer
		if err := New(opts).Process(context.Background(), strings.NewReader(input), &output); err != nil {
			t.Fatal(err)
		}
		if output.String() != input {
			t.Errorf("input changed: %q", output.String())
		}
	}
}

func TestDockerLegacyStepCards(t *testing.T) {
	got, ok := newDockerBuildSteps().format("Step 2/5 : RUN echo hello\n")
	if !ok || !strings.Contains(got, "STEP 1") || !strings.Contains(got, "RUN") {
		t.Fatalf("legacy header: %q", got)
	}
}
