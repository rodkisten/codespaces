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
		BadgeText:       "38;2;200;210;220",
		Done:            "38;2;1;2;3",
		Separator:       "38;2;4;5;6",
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

func TestColorSGR(t *testing.T) {
	cases := []struct {
		value      string
		background bool
		want       string
	}{
		{"#A78BFA", false, "38;2;167;139;250"},
		{"#0c2238", true, "48;2;12;34;56"},
		{"32", false, "32"},
	}
	for _, tc := range cases {
		got, err := ColorSGR(tc.value, tc.background)
		if err != nil || got != tc.want {
			t.Errorf("ColorSGR(%q) = %q, %v; want %q", tc.value, got, err, tc.want)
		}
	}
	for _, invalid := range []string{"#fff", "#xyzxyz", "red", "31m\\x1b[2J", ""} {
		if _, err := ColorSGR(invalid, false); err == nil {
			t.Errorf("expected invalid color %q to fail", invalid)
		}
	}
}

func TestParseDockerColors(t *testing.T) {
	got, err := ParseDockerColors(DockerColors{BadgeBackground: "#0C2238", Done: "#4ADE80"})
	if err != nil {
		t.Fatal(err)
	}
	if got.BadgeBackground != "48;2;12;34;56" || got.Done != "38;2;74;222;128" || got.Cached != "2" {
		t.Fatalf("incorrect palette merge: %+v", got)
	}
	if _, err := ParseDockerColors(DockerColors{Error: "not-a-color"}); err == nil {
		t.Fatal("invalid theme color was accepted")
	}
}

func TestEngineDockerHexColors(t *testing.T) {
	input := "#8 [build 1/2] RUN echo hello\n#8 DONE 1.2s\n"
	var output bytes.Buffer
	engine := New(Options{
		Mode:  Enhance,
		Tool:  Docker,
		Color: true,
		DockerColors: DockerColors{
			BadgeBackground: "#0C2238",
			BadgeText:       "#E8EAF0",
			Done:            "#4ADE80",
			Separator:       "#A78BFA",
		},
	})
	if err := engine.Process(context.Background(), strings.NewReader(input), &output); err != nil {
		t.Fatal(err)
	}
	for _, expected := range []string{
		"\x1b[48;2;12;34;56m",
		"\x1b[38;2;232;234;240m",
		"\x1b[38;2;74;222;128m",
		"\x1b[38;2;167;139;250m",
	} {
		if !strings.Contains(output.String(), expected) {
			t.Errorf("missing configured color %q in %q", expected, output.String())
		}
	}
}

func TestDockerNestedBuildKitOutput(t *testing.T) {
	input := "#1 [internal] load build definition from Dockerfile\n#1 transferring dockerfile: 615B done\n#2 [internal] load metadata for docker.io/library/node:22-alpine\n#3 [internal] load .dockerignore\n#3 transferring context: 2B done\n#4 [1/4] FROM docker.io/library/node:22-alpine\n#5 [2/4] WORKDIR /app\n#6 [3/4] COPY package.json package-lock.json ./\n#7 [4/4] RUN npm ci\n#7 0.3 npm ERR! code ERESOLVE\nSTEP 4  ERROR: process \"/bin/sh -c npm ci\" did not complete successfully: exit code: 1\n"
	var out bytes.Buffer
	if err := New(Options{Mode: Enhance, Tool: Auto, Color: true}).Process(context.Background(), strings.NewReader(input), &out); err != nil { t.Fatal(err) }
	plain := ansi.ReplaceAllString(out.String(), "")
	for _, expected := range []string{"STEP 1", "load build definition", "STEP 1.1/1", "transferring dockerfile: 615B done", "load metadata", "load .dockerignore", "STEP 3.1/3", "transferring context: 2B done", "STEP 7", "STEP 7.1/4", "npm ERR! code ERESOLVE", "STEP 4 ERROR", "exit code: 1", "╰──"} {
		if !strings.Contains(plain, expected) { t.Errorf("missing %q in output: %s", expected, plain) }
	}
}
func TestDockerInterleavedNestedOutput(t *testing.T) {
	s := newDockerBuildSteps()
	s.format("#8 [build 1/2] RUN echo hello\n")
	s.format("#9 [build 2/2] RUN echo world\n")
	got, ok := s.format("#8 0.2 hello\n")
	if !ok || !strings.Contains(got, "STEP 1.1/2") || !strings.Contains(got, "0.2s") { t.Fatalf("nested step association: %q", got) }
}
