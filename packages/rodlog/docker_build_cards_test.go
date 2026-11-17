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
	if strings.Contains(got, "#9 [builder") {
		t.Errorf("raw header leaked: %q", got)
	}
	if strings.Count(got, "\x1b[48;5;238m\x1b[97;1m STEP 2 ") != 1 {
		t.Errorf("duplicate card: %q", got)
	}
	if !strings.Contains(ansi.ReplaceAllString(got, ""), "#12 [builder 2/3] RUN npm ci") {
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

func TestDockerStepStatusMapping(t *testing.T) {
	steps := newDockerBuildSteps()
	steps.format("#23 [builder 1/2] RUN npm ci\n")
	got, ok := steps.format("#23 DONE 4.2s\n")
	if !ok || !strings.Contains(got, "STEP 1") || !strings.Contains(got, "DONE") || !strings.Contains(got, "4.2s") {
		t.Fatalf("status not mapped to step: %q", got)
	}
	if _, ok := steps.format("#99 DONE 1.0s\n"); ok {
		t.Fatal("unknown step status must preserve original output")
	}
}

func TestDockerBuildStatusError(t *testing.T) {
	steps := newDockerBuildSteps()
	steps.format("#5 [build 2/3] RUN false\n")
	got, ok := steps.format("#5 ERROR 0.5s\n")
	if !ok || !strings.Contains(got, "STEP 1") || !strings.Contains(got, "ERROR") || !strings.Contains(got, "0.5s") {
		t.Fatalf("error status lost: %q", got)
	}
}

func TestDockerCustomSeparator(t *testing.T) {
	input := "#1 [build 1/2] RUN echo hello\n"
	var output bytes.Buffer
	engine := New(Options{Mode: Enhance, Tool: Docker, Color: true, DockerSeparator: "===="})
	if err := engine.Process(context.Background(), strings.NewReader(input), &output); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), "====") || strings.Contains(output.String(), "────") {
		t.Fatalf("custom divider not applied: %q", output.String())
	}
}
