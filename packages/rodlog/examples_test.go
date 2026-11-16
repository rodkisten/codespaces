package rodlog

import (
	"bytes"
	"context"
	"fmt"
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

			if got := ansi.ReplaceAllString(output.String(), ""); got != string(fixture) {
				t.Fatalf("highlighting changed the original text:\nwant: %q\ngot:  %q", fixture, got)
			}

			if !strings.Contains(output.String(), "\x1b[") {
				t.Fatalf("expected ANSI highlighting for %s", tt.tool)
			}

			t.Logf("\n%s", strings.Repeat("━", 48))
			t.Logf("🌈 rodlog | %s | mode=enhance | color=always", tt.tool)
			t.Logf("🧪 command: %s", exampleCommand(tt.tool))
			t.Logf("📥 Original output:\n%s", strings.TrimSuffix(string(fixture), "\n"))
			t.Logf("🎨 Highlighted output (ANSI):\n%s", strings.TrimSuffix(output.String(), "\n"))
			t.Logf("✅ Original content preserved; ANSI tokens verified")
		})
	}
}

func exampleCommand(tool Tool) string {
	switch tool {
	case NPM:
		return "rodlog exec -- npm run build"
	case TypeScript:
		return "rodlog exec -- npx tsc --noEmit"
	case GCloud:
		return "rodlog exec -- gcloud run deploy"
	case Wrangler:
		return "rodlog exec -- npx wrangler deploy"
	case Docker:
		return "rodlog exec -- docker build ."
	default:
		return fmt.Sprintf("rodlog --tool=%s", tool)
	}
}
