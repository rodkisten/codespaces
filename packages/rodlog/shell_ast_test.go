package rodlog

import "testing"

func TestAnalyzeShell(t *testing.T) {
	result, err := AnalyzeShell("gcloud run services list\nnpx wrangler deploy\necho $HOME\n", "bash")
	if err != nil {
		t.Fatal(err)
	}
	if len(result.Commands) != 3 {
		t.Fatalf("expected 3 commands, got %+v", result.Commands)
	}
	if result.Commands[0].Tool != GCloud || result.Commands[0].Line != 1 || result.Commands[0].Args[0] != "run" {
		t.Fatalf("unexpected gcloud command: %+v", result.Commands[0])
	}
	if result.Commands[1].Name != "npx" || result.Commands[2].Tool != Generic {
		t.Fatalf("unexpected command inventory: %+v", result.Commands)
	}
}

func TestAnalyzeShellRejectsUnsupportedSyntax(t *testing.T) {
	if _, err := AnalyzeShell("echo hi", "zsh"); err == nil {
		t.Fatal("zsh must not silently be parsed as Bash")
	}
	if _, err := AnalyzeShell("if then", "bash"); err == nil {
		t.Fatal("invalid Bash must produce syntax error")
	}
}
