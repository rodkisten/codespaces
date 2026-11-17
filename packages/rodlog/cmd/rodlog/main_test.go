package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestPipe(t *testing.T) {
	var out, errs bytes.Buffer
	status := run([]string{"--color=never"}, strings.NewReader("npm ERR! broken\n"), &out, &errs)
	if status != 0 || out.String() != "npm ERR! broken\n" {
		t.Fatalf("status=%d output=%q error=%q", status, out.String(), errs.String())
	}
}
func TestInvalidMode(t *testing.T) {
	var out, errs bytes.Buffer
	if run([]string{"--mode=invalid"}, strings.NewReader(""), &out, &errs) != 2 {
		t.Fatal("expected invalid mode")
	}
}
func TestExecExitCode(t *testing.T) {
	var out, errs bytes.Buffer
	code := run([]string{"exec", "--color=never", "--", "sh", "-c", "echo 'npm ERR! bad'; exit 7"}, strings.NewReader(""), &out, &errs)
	if code != 7 || !strings.Contains(out.String(), "npm ERR! bad") {
		t.Fatalf("code=%d out=%q err=%q", code, out.String(), errs.String())
	}
}

func TestDockerSeparatorFlag(t *testing.T) {
	input := "#7 [build 1/2] RUN echo hello\n"
	var out, errs bytes.Buffer
	status := run([]string{"--tool=docker", "--color=always", "--docker-separator=++++"}, strings.NewReader(input), &out, &errs)
	if status != 0 || !strings.Contains(out.String(), "++++") {
		t.Fatalf("status=%d output=%q error=%q", status, out.String(), errs.String())
	}
}

func TestDockerSeparatorEnvironment(t *testing.T) {
	t.Setenv("RODLOG_DOCKER_SEPARATOR", "~~~~")
	input := "#7 [build 1/2] RUN echo hello\n"
	var out, errs bytes.Buffer
	status := run([]string{"--tool=docker", "--color=always"}, strings.NewReader(input), &out, &errs)
	if status != 0 || !strings.Contains(out.String(), "~~~~") {
		t.Fatalf("status=%d output=%q error=%q", status, out.String(), errs.String())
	}
}

func TestDockerSeparatorFlagOverridesEnvironment(t *testing.T) {
	t.Setenv("RODLOG_DOCKER_SEPARATOR", "ENV-DIVIDER")
	input := "#7 [build 1/2] RUN echo hello\n"
	var out, errs bytes.Buffer
	status := run([]string{"--tool=docker", "--color=always", "--docker-separator=FLAG-DIVIDER"}, strings.NewReader(input), &out, &errs)
	if status != 0 || !strings.Contains(out.String(), "FLAG-DIVIDER") || strings.Contains(out.String(), "ENV-DIVIDER") {
		t.Fatalf("status=%d output=%q error=%q", status, out.String(), errs.String())
	}
}
