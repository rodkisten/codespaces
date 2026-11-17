package rodlog

import "testing"

// TestRunnerDetection ensures node itself is not misclassified as a test runner.
func TestRunnerDetection(t *testing.T) {
	cases := []struct {
		args []string
		want Tool
	}{
		{[]string{"vitest", "run"}, Vitest},
		{[]string{"npx", "vitest", "run"}, Vitest},
		{[]string{"node", "--test", "example.test.js"}, NodeTest},
		{[]string{"node", "--version"}, Generic},
	}
	for _, tc := range cases {
		if got := DetectCommand(tc.args); got != tc.want {
			t.Errorf("DetectCommand(%q) = %q, want %q", tc.args, got, tc.want)
		}
	}
}

func TestRunnerDiagnostics(t *testing.T) {
	cases := []struct {
		tool Tool
		input, want string
	}{
		{Vitest, " ❯ src/button.test.ts > renders label", "src/button.test.ts > renders label"},
		{NodeTest, "✖ adds numbers (3.1ms)", "adds numbers (3.1ms)"},
		{NodeTest, "not ok 2 - fails assertion", "fails assertion"},
	}
	for _, tc := range cases {
		d := ParseDiagnostic(tc.tool, tc.input)
		if d == nil || d.Level != Error || d.Message != tc.want {
			t.Errorf("ParseDiagnostic(%q, %q) = %#v", tc.tool, tc.input, d)
		}
	}
}
