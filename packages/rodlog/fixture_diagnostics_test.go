package rodlog

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestExtendedLogFixtures(t *testing.T) {
	type fixtureCase struct {
		name string
		tool Tool
		want string
	}
	cases := []fixtureCase{
		{"typescript", TypeScript, "TS2322"},
		{"npm", NPM, "missing script"},
		{"gcloud", GCloud, "Permission"},
		{"docker", Docker, "Dockerfile"},
		{"wrangler", Wrangler, "Authentication"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			raw, err := os.ReadFile(filepath.Join("testdata", tc.name+".log"))
			if err != nil {
				t.Fatal(err)
			}
			if len(bytes.Split(raw, []byte("\n"))) < 12 {
				t.Fatalf("fixture too small: %d lines", len(bytes.Split(raw, []byte("\n"))))
			}
			var plain bytes.Buffer
			if err := New(Options{Tool: tc.tool, Mode: Enhance, Color: false}).Process(context.Background(), bytes.NewReader(raw), &plain); err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(raw, plain.Bytes()) {
				t.Fatal("no-color fallback must preserve fixture bytes")
			}
			var transformed bytes.Buffer
			if err := New(Options{Tool: tc.tool, Mode: Transform, Color: true}).Process(context.Background(), bytes.NewReader(raw), &transformed); err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(strings.ToLower(ansi.ReplaceAllString(transformed.String(), "")), strings.ToLower(tc.want)) || !strings.Contains(transformed.String(), "\x1b[") {
				t.Fatalf("missing diagnostic %q or ANSI in transformed fixture (output bytes=%d)", tc.want, transformed.Len())
			}
		})
	}
}

func TestDiagnosticCards(t *testing.T) {
	cases := []struct {
		tool  Tool
		line  string
		level Level
	}{
		{Wrangler, "✘ [ERROR] Authentication error [code: 10000]", Error},
		{Wrangler, "[WARNING] Deprecated configuration field", Warning},
		{Docker, "ERROR: failed to solve: process exited with code 1", Error},
		{TypeScript, "src/app.ts(8,2): error TS2322: Invalid type", Error},
	}
	for _, tc := range cases {
		d := ParseDiagnostic(tc.tool, tc.line)
		if d == nil || d.Level != tc.level {
			t.Fatalf("ParseDiagnostic(%q) = %+v", tc.line, d)
		}
		rendered := string(renderDiagnostic(d))
		if !strings.Contains(rendered, d.Message) || !strings.Contains(rendered, "\x1b[") {
			t.Fatalf("invalid diagnostic card: %q", rendered)
		}
	}
}
