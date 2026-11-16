package rodlog

import (
	"bytes"
	"context"
	"strings"
	"testing"
)

func TestStreamingGroupsInterleaved(t *testing.T) {
	input := "a.ts(1,1): error TS2322: first\nb.ts(2,1): error TS2322: second\na.ts(3,1): error TS2322: third\n"
	var output bytes.Buffer
	if err := New(Options{Tool: TypeScript, Mode: Transform, Color: true}).Process(context.Background(), strings.NewReader(input), &output); err != nil {
		t.Fatal(err)
	}
	result := output.String()
	if strings.Count(result, "▸ a.ts") != 2 || strings.Count(result, "▸ b.ts") != 1 {
		t.Fatalf("expected contiguous group headers: %q", result)
	}
	if !(strings.Index(result, "first") < strings.Index(result, "second") && strings.Index(result, "second") < strings.Index(result, "third")) {
		t.Fatalf("output reordered: %q", result)
	}
}
