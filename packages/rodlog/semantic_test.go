package rodlog

import "testing"

func TestParseDiagnostic(t *testing.T) {
	cases := []struct {
		tool              Tool
		input, code, file string
		line              int
		level             Level
	}{
		{TypeScript, "src/main.ts(12,4): error TS2322: Type mismatch", "TS2322", "src/main.ts", 12, Error},
		{TypeScript, "src/a.ts:8:2 - warning TS6133: Unused", "TS6133", "src/a.ts", 8, Warning},
		{NPM, "npm WARN deprecated package", "", "", 0, Warning},
		{GCloud, "ERROR: (gcloud.run.deploy) permission denied", "", "", 0, Error},
		{Docker, "Dockerfile:14", "", "Dockerfile", 14, Error},
	}
	for _, tc := range cases {
		d := ParseDiagnostic(tc.tool, tc.input)
		if d == nil || d.Code != tc.code || d.File != tc.file || d.Line != tc.line || d.Level != tc.level {
			t.Errorf("ParseDiagnostic(%q, %q) = %+v", tc.tool, tc.input, d)
		}
	}
	if d := ParseDiagnostic(Generic, "ordinary unstructured output"); d != nil {
		t.Fatalf("unexpected diagnostic: %+v", d)
	}
}
