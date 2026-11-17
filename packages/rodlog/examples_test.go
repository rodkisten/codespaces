package rodlog

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestOutputExamples prints real, colored rodlog output into go test -v and
// GitHub Actions logs. Each tool has a fixture and an exact-text assertion.
func TestOutputExamples(t *testing.T) {
	tests := []struct {
		name string
		tool Tool
		file string
	}{
		{name: "npm", tool: NPM, file: "npm.log"},
		{name: "typescript", tool: TypeScript, file: "typescript.log"},
		{name: "gcloud", tool: GCloud, file: "gcloud.log"},
		{name: "wrangler", tool: Wrangler, file: "wrangler.log"},
		{name: "docker", tool: Docker, file: "docker.log"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			fixture, err := os.ReadFile(filepath.Join("testdata", tt.file))
			if err != nil {
				t.Fatal(err)
			}

			engine := New(Options{
				Mode:  Enhance,
				Tool:  tt.tool,
				Color: true,
			})

			var output bytes.Buffer
			if err := engine.Process(context.Background(), bytes.NewReader(fixture), &output); err != nil {
				t.Fatal(err)
			}

			if got := ansi.ReplaceAllString(output.String(), ""); tt.tool != Docker && got != string(fixture) {
				t.Fatalf("highlighting changed the original text:\nwant: %q\ngot:  %q", fixture, got)
			}

			if tt.tool == Docker {
				plain := ansi.ReplaceAllString(output.String(), "")
				if !strings.Contains(plain, "STEP 1") || !strings.Contains(plain, "RUN npm ci") || !strings.Contains(plain, "ERROR: failed to solve") {
					t.Fatalf("Docker output lost step cards or diagnostics: %q", plain)
				}
			}

			if !strings.Contains(output.String(), "\x1b[") {
				t.Fatalf("expected ANSI highlighting for %s", tt.tool)
			}

		})
	}
}

