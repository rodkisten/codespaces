package rodlog

import (
	"strings"
	"testing"
)

// TestDiagnosticExplanation protects the semantic meaning of a type mismatch:
// the right-hand type is what TypeScript expects, not what it received.
func TestDiagnosticExplanation(t *testing.T) {
	cases := []struct {
		code, message, want string
	}{
		{"TS2322", "Type 'number' is not assignable to type 'string'.", "Expected: string  |  Received: number"},
		{"TS2345", "Argument of type 'null' is not assignable to parameter of type 'string'.", ""},
		{"TS2307", "Cannot find module './missing'", "Module could not be resolved"},
		{"TS7006", "Parameter 'event' implicitly has an 'any' type.", "implicit any"},
	}
	for _, tc := range cases {
		t.Run(tc.code, func(t *testing.T) {
			d := &Diagnostic{Tool: TypeScript, Code: tc.code, Message: tc.message}
			got := diagnosticExplanation(d)
			if !strings.Contains(got, tc.want) {
				t.Fatalf("explanation %q does not contain %q", got, tc.want)
			}
		})
	}
}
