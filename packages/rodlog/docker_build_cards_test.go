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

func TestDockerBuildKitAutoDetection(t *testing.T) {
	for _, line := range []string{
		"#7 [build 1/2] RUN npm ci\n",
		"#7 DONE 2.1s\n",
		"Step 1/3 : FROM node:22\n",
	} {
		if got := Detect(line); got != Docker {
			t.Errorf("Detect(%q) = %q, want docker", line, got)
		}
	}
	var output bytes.Buffer
	input := "#7 [build 1/2] RUN npm ci\n#7 DONE 2.1s\n"
	if err := New(Options{Mode: Enhance, Tool: Auto, Color: true}).Process(context.Background(), strings.NewReader(input), &output); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(output.String(), "STEP 1") || !strings.Contains(output.String(), "DONE") {
		t.Fatalf("automatic BuildKit cards missing: %q", output.String())
	}
}

func TestDockerAutoDetectionDoesNotCaptureOtherLogs(t *testing.T) {
	for _, line := range []string{
		"#7 [build 1/2] unrelated event\n",
		"#7 [build 1/2] completed arbitrary task\n",
		"ordinary application output\n",
	} {
		if got := Detect(line); got == Docker {
			t.Errorf("false Docker detection for %q", line)
		}
	}
}

func TestDockerBuildKitInterleavedStatuses(t *testing.T) {
	steps := newDockerBuildSteps()
	steps.format("#18 [build 1/3] FROM node:22\n")
	steps.format("#4 [build 2/3] RUN npm ci\n")
	first, okFirst := steps.format("#4 CACHED\n")
	second, okSecond := steps.format("#18 DONE 0.1s\n")
	if !okFirst || !okSecond || !strings.Contains(first, "STEP 2") || !strings.Contains(first, "CACHED") || !strings.Contains(second, "STEP 1") {
		t.Fatalf("interleaved status mismatch: first=%q second=%q", first, second)
	}
}

func TestDockerCustomColors(t *testing.T) {
	steps := newDockerBuildSteps()
	steps.colors = mergeDockerColors(steps.colors, DockerColors{
		BadgeBackground: "48;2;12;34;56",
		BadgeText: "38;2;200;210;220",
		Done: "38;2;1;2;3",
		Separator: "38;2;4;5;6",
	})
	header, ok := steps.format("#8 [build 1/2] RUN echo hello\n")
	if !ok || !strings.Contains(header, "\x1b[48;2;12;34;56m") || !strings.Contains(header, "\x1b[38;2;200;210;220m") || !strings.Contains(header, "\x1b[38;2;4;5;6m") {
		t.Fatalf("custom colors missing: %q", header)
	}
	status, ok := steps.format("#8 DONE 1.2s\n")
	if !ok || !strings.Contains(status, "\x1b[38;2;1;2;3m") {
		t.Fatalf("custom status color missing: %q", status)
	}
}
