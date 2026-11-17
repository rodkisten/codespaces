package rodlog

import (
	"strings"
	"testing"
)

// TestAssertionCard ensures the parser keeps the compiler/test-runner message
// while the renderer makes the expected and actual values explicit.
func TestAssertionCard(t *testing.T) {
	for _, tool := range []Tool{Vitest, NodeTest} {
		d := ParseDiagnostic(tool, "AssertionError: expected 3 to be 4")
		if d == nil {
			t.Fatalf("%s: expected diagnostic", tool)
		}
		output := string(renderDiagnostic(d))
		for _, expected := range []string{"Expected: 4", "Received: 3", "AssertionError: expected 3 to be 4"} {
			if !strings.Contains(output, expected) {
				t.Errorf("%s: missing %q in %q", tool, expected, output)
			}
		}
	}
}
