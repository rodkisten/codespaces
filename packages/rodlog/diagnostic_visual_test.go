package rodlog

import "testing"

func TestVisualColumn(t *testing.T) {
	cases := []struct {
		input	string
		column	int
		want	int
	}{
		{"abc", 3, 2},
		{"\tx", 2, 8},
		{"éx", 2, 1},
		{"界x", 2, 2},
	}
	for _, tc := range cases {
		if got := visualColumn(tc.input, tc.column); got != tc.want {
			t.Errorf("visualColumn(%q, %d) = %d, want %d", tc.input, tc.column, got, tc.want)
		}
	}
}

func TestDiagnosticSuggestions(t *testing.T) {
	if got := diagnosticSuggestion(&Diagnostic{Tool: TypeScript, Code: "TS2307"}); got == "" {
		t.Fatal("missing TS2307 suggestion")
	}
	if got := diagnosticSuggestion(&Diagnostic{Tool: Generic, Message: "ordinary output"}); got != "" {
		t.Fatalf("unexpected suggestion: %q", got)
	}
}
