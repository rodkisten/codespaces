package rodlog

import (
	"bytes"
	"context"
	"strings"
	"testing"
)

func stripColors(s string) string { return ansi.ReplaceAllString(s, "") }
func TestHighlightTools(t *testing.T) {
	cases := []struct {
		tool         Tool
		input, token string
	}{
		{NPM, "npm ERR! missing script: build\n", "ERR!"},
		{TypeScript, "src/app.ts(4,12): error TS2322\n", "TS2322"},
		{GCloud, "ERROR: (gcloud.run.deploy) denied\n", "ERROR"},
		{Wrangler, "wrangler deploy failed\n", "wrangler"},
		{Docker, "docker build failed\n", "docker"},
	}
	for _, tc := range cases {
		t.Run(string(tc.tool), func(t *testing.T) {
			var dst bytes.Buffer
			engine := New(Options{Tool: tc.tool, Mode: Enhance, Color: true})
			if err := engine.Process(context.Background(), strings.NewReader(tc.input), &dst); err != nil {
				t.Fatal(err)
			}
			if stripColors(dst.String()) != tc.input {
				t.Fatalf("text changed: %q", dst.String())
			}
			if !strings.Contains(dst.String(), "\x1b[") {
				t.Fatalf("missing highlight: %q", dst.String())
			}
			if !strings.Contains(dst.String(), tc.token) {
				t.Fatalf("missing token %s", tc.token)
			}
		})
	}
}
func TestHighlightPreservesExistingANSI(t *testing.T) {
	input := "\x1b[32mERROR\x1b[0m\n"
	got := string(Render(Event{Text: input, Level: Error, Tool: NPM}, Options{Color: true, Mode: Enhance}))
	if got != input {
		t.Fatalf("ANSI changed: %q", got)
	}
}
func TestHighlightCRLF(t *testing.T) {
	input := "error TS2322\r\n"
	got := string(Render(Event{Text: input, Level: Error, Tool: TypeScript}, Options{Color: true, Mode: Enhance}))
	if stripColors(got) != input {
		t.Fatalf("CRLF changed: %q", got)
	}
}
