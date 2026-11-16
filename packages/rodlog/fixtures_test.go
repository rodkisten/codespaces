package rodlog

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestToolFixtures(t *testing.T) {
	tests := []struct {
		file  string
		tool  Tool
		level Level
	}{
		{"npm.log", NPM, Error},
		{"typescript.log", TypeScript, Error},
		{"gcloud.log", GCloud, Error},
		{"wrangler.log", Wrangler, Info},
		{"docker.log", Docker, Info},
	}
	for _, tc := range tests {
		t.Run(tc.file, func(t *testing.T) {
			input, err := os.ReadFile(filepath.Join("testdata", tc.file))
			if err != nil {
				t.Fatal(err)
			}
			var out bytes.Buffer
			if err := New(Options{Mode: Enhance, Color: false}).Process(context.Background(), bytes.NewReader(input), &out); err != nil {
				t.Fatal(err)
			}
			if !bytes.Equal(input, out.Bytes()) {
				t.Fatal("fixture text changed")
			}
			if got := Detect(string(input)); got != tc.tool {
				t.Fatalf("detect %s, want %s", got, tc.tool)
			}
			if tc.level == Error && !strings.Contains(string(input), "ERROR") && !strings.Contains(string(input), "error") && !strings.Contains(string(input), "ERR!") {
				t.Fatal("fixture missing error")
			}
		})
	}
}
