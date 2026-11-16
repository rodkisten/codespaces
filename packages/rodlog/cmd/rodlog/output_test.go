package main

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func TestSemanticOutputCLI(t *testing.T) {
	var out, errOut bytes.Buffer
	code := run([]string{"--tool=typescript", "--output=jsonl"}, strings.NewReader("src/a.ts(4,2): error TS2322: bad\n"), &out, &errOut)
	if code != 0 {
		t.Fatalf("exit %d: %s", code, errOut.String())
	}
	var event struct {
		Diagnostic struct {
			Code string
			Line int
		}
		Text string
	}
	if err := json.Unmarshal(out.Bytes(), &event); err != nil {
		t.Fatal(err)
	}
	if event.Diagnostic.Code != "TS2322" || event.Diagnostic.Line != 4 || !strings.Contains(event.Text, "TS2322") {
		t.Fatalf("unexpected event: %+v", event)
	}
	out.Reset()
	errOut.Reset()
	code = run([]string{"--tool=typescript", "--output=github"}, strings.NewReader("src/a.ts(4,2): error TS2322: bad\n"), &out, &errOut)
	if code != 0 || !strings.Contains(out.String(), "::error file=src/a.ts,line=4,col=2,title=TS2322::bad") {
		t.Fatalf("exit %d output %q stderr %q", code, out.String(), errOut.String())
	}
}

func TestInvalidOutputCLI(t *testing.T) {
	var out, errOut bytes.Buffer
	if code := run([]string{"--output=unknown"}, strings.NewReader(""), &out, &errOut); code != 2 {
		t.Fatalf("expected exit 2, got %d", code)
	}
}
