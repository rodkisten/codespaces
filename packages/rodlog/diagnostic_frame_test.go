package rodlog

import (
	"bytes"
	"context"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDiagnosticFrameAndSummary(t *testing.T) {
	dir := t.TempDir()
	old, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Chdir(dir); err != nil {
		t.Fatal(err)
	}
	defer os.Chdir(old)
	if err := os.MkdirAll("src", 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join("src", "a.ts"), []byte("const a = 1;\nconst b = 2;\nconst c = 3;\n"), 0600); err != nil {
		t.Fatal(err)
	}
	input := "src/a.ts(2,7): error TS2322: invalid type\nsrc/a.ts(2,7): error TS2322: invalid type\nsrc/a.ts(3,3): warning TS6133: unused\n"
	var out bytes.Buffer
	if err := New(Options{Tool: TypeScript, Mode: Transform, Color: true}).Process(context.Background(), strings.NewReader(input), &out); err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{"const b = 2", "^", "1 errors", "1 warnings"} {
		if !strings.Contains(out.String(), want) {
			t.Fatalf("missing %q in %q", want, out.String())
		}
	}
	if strings.Count(out.String(), "invalid type") != 1 {
		t.Fatalf("duplicate diagnostic not removed: %q", out.String())
	}
}

func TestDiagnosticFrameRejectsTraversal(t *testing.T) {
	if got := diagnosticFrame(&Diagnostic{File: "../secret", Line: 1}); got != "" {
		t.Fatalf("unsafe file path: %q", got)
	}
}
