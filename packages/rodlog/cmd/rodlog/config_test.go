package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestTOMLConfigLoadAndPrecedence(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "rodlog.toml")
	source := `mode = "raw"
tool = "docker"
color = "always"
output = "terminal"
[docker]
separator = "CUSTOM"
[docker.colors]
badge_background = "#123456"
done = "#4ADE80"
`
	if err := os.WriteFile(path, []byte(source), 0600); err != nil {
		t.Fatal(err)
	}
	got, err := loadConfig(path)
	if err != nil {
		t.Fatal(err)
	}
	if got.Mode != "raw" || got.Tool != "docker" || got.Docker.Separator != "CUSTOM" || got.Docker.Colors.Done != "#4ADE80" {
		t.Fatalf("incorrect TOML decode: %+v", got)
	}
	t.Setenv("RODLOG_MODE", "")
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--config", path}, strings.NewReader("hello\n"), &stdout, &stderr); code != 0 || stdout.String() != "hello\n" {
		t.Fatalf("TOML raw mode: code=%d stdout=%q stderr=%q", code, stdout.String(), stderr.String())
	}
	stdout.Reset()
	stderr.Reset()
	t.Setenv("RODLOG_MODE", "raw")
	if code := run([]string{"--config", path, "--mode", "enhance", "--color", "never"}, strings.NewReader("hello\n"), &stdout, &stderr); code != 0 {
		t.Fatalf("CLI override: code=%d stderr=%q", code, stderr.String())
	}
}

func TestTOMLConfigErrors(t *testing.T) {
	dir := t.TempDir()
	path := filepath.Join(dir, "config.toml")
	for _, tc := range []struct {
		name string
		data string
	}{
		{"unknown", "surprise = true\n"},
		{"invalid", "[docker\n"},
		{"unknown_nested", "[docker.colors]\nunknown = \"red\"\n"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if err := os.WriteFile(path, []byte(tc.data), 0600); err != nil {
				t.Fatal(err)
			}
			if _, err := loadConfig(path); err == nil {
				t.Fatal("expected config error")
			}
		})
	}
	if _, err := loadConfig(filepath.Join(dir, "missing.toml")); err == nil {
		t.Fatal("explicit missing config must fail")
	}
}

func TestConfigFlagSelection(t *testing.T) {
	t.Setenv("RODLOG_CONFIG", "/tmp/from-env.toml")
	for _, tc := range []struct {
		args []string
		want string
	}{
		{[]string{"--config", "/tmp/cli.toml"}, "/tmp/cli.toml"},
		{[]string{"--config=/tmp/equals.toml"}, "/tmp/equals.toml"},
		{nil, "/tmp/from-env.toml"},
	} {
		got, err := findConfigPath(tc.args)
		if err != nil || got != tc.want {
			t.Errorf("findConfigPath(%v) = %q, %v; want %q", tc.args, got, err, tc.want)
		}
	}
	for _, args := range [][]string{{"--config"}, {"--config="}, {"--config", "--mode"}} {
		if _, err := findConfigPath(args); err == nil {
			t.Errorf("expected error for %v", args)
		}
	}
}

func TestTOMLInvalidColorRejected(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config.toml")
	if err := os.WriteFile(path, []byte("[docker.colors]\ndone = \"not-a-color\"\n"), 0600); err != nil {
		t.Fatal(err)
	}
	var stdout, stderr bytes.Buffer
	if code := run([]string{"--config", path}, strings.NewReader(""), &stdout, &stderr); code != 2 || !strings.Contains(stderr.String(), "invalid color") {
		t.Fatalf("expected color validation error: code=%d stderr=%q", code, stderr.String())
	}
}
