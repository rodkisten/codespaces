package rodlog

import (
	"bytes"
	"context"
	"errors"
	"strings"
	"testing"
)

func TestDetect(t *testing.T) {
	cases := map[string]Tool{"npm ERR! missing script": NPM, "src/app.ts(3,4): error TS2322": TypeScript, "ERROR: (gcloud.run.deploy) denied": GCloud, "wrangler deploy": Wrangler, "docker build .": Docker, "hello": Generic}
	for input, want := range cases {
		if got := Detect(input); got != want {
			t.Errorf("%q: got %s want %s", input, got, want)
		}
	}
}
func TestRawExact(t *testing.T) {
	data := []byte("one\rprogress\n\x1b[31mred\x1b[0m\n\x00end")
	var dst bytes.Buffer
	err := New(Options{Mode: Raw}).Process(context.Background(), bytes.NewReader(data), &dst)
	if err != nil || !bytes.Equal(data, dst.Bytes()) {
		t.Fatalf("raw mismatch: %v", err)
	}
}
func TestEnhanceNoColor(t *testing.T) {
	data := "npm ERR! broken\nwarning deprecated\n"
	var dst bytes.Buffer
	err := New(Options{Mode: Enhance}).Process(context.Background(), strings.NewReader(data), &dst)
	if err != nil || dst.String() != data {
		t.Fatalf("output: %q, %v", dst.String(), err)
	}
}
func TestColors(t *testing.T) {
	var dst bytes.Buffer
	e := New(Options{Color: true})
	_ = e.Process(context.Background(), strings.NewReader("npm ERR! broken\n"), &dst)
	// Severity stays red even when the theme changes its intensity.
	if !strings.Contains(dst.String(), "\x1b[31m") && !strings.Contains(dst.String(), "\x1b[1;31m") {
		t.Fatal(dst.String())
	}
}

type failingRenderer struct{}

func (failingRenderer) Render(Event) ([]byte, error) { return nil, errors.New("boom") }
func TestRendererFallback(t *testing.T) {
	var dst bytes.Buffer
	e := New(Options{Color: true})
	e.Renderer = failingRenderer{}
	_ = e.Process(context.Background(), strings.NewReader("ERROR hello\n"), &dst)
	if dst.String() != "ERROR hello\n" {
		t.Fatal(dst.String())
	}
}
func TestLongLine(t *testing.T) {
	input := strings.Repeat("a", 100000) + "\n"
	var dst bytes.Buffer
	if err := New(Options{}).Process(context.Background(), strings.NewReader(input), &dst); err != nil || dst.String() != input {
		t.Fatalf("long line: %v", err)
	}
}
