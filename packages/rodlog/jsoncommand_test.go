package rodlog

import (
	"strings"
	"testing"
)

func TestJSONCommandAllowlist(t *testing.T) {
	for _, tc := range []struct {
		command []string
		want bool
	}{
		{[]string{"npm", "outdated"}, true},
		{[]string{"npm", "audit"}, true},
		{[]string{"npm", "run", "build"}, false},
		{[]string{"gcloud", "run", "deploy"}, false},
		{[]string{"npm", "audit", "--json"}, false},
		{[]string{"npm", "audit", "--help"}, false},
	} {
		got, ok := JSONCommand(tc.command)
		if ok != tc.want {
			t.Fatalf("%v: added=%t, want=%t", tc.command, ok, tc.want)
		}
		if ok && got[len(got)-1] != "--json" {
			t.Fatalf("missing --json: %v", got)
		}
	}
}

func TestJSONTable(t *testing.T) {
	input := `[{"name":"api","status":"ready","region":"us-central1"},{"name":"web","status":"failed","region":"eu-west1"}]`
	output, ok := JSONTable(input, true)
	if !ok || !strings.Contains(output, "api") || !strings.Contains(output, "web") {
		t.Fatalf("invalid table: %q", output)
	}
	t.Logf("📊 Colored JSON summary:\n%s", output)
}
