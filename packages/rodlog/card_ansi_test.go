package rodlog

import (
 "strings"
 "testing"
 "github.com/charmbracelet/lipgloss"
)
func TestCardColorAlwaysNonTTY(t *testing.T) {
 p:=DefaultSemanticPreset()
 d:=DiagnosticCard{Tool:GCloud,Title:"GCLOUD ERROR",API:"run.deploy",Code:"PERMISSION_DENIED",Message:"missing permission."}
 got:=RenderDiagnosticCard(d,Options{Preset:&p,Color:true})
 if !strings.Contains(got,"\x1b[") {t.Fatalf("color=always must emit ANSI even without TTY: %q",got)}
 if !strings.Contains(got,"\x1b[36m") || !strings.Contains(got,"\x1b[33m") {t.Fatalf("missing API/code colors: %q",got)}
 for _,line:=range strings.Split(strings.TrimSuffix(got,"\n"),"\n") {if lipgloss.Width(line)>36 {t.Fatalf("card overflow: %q",line)}}
}
func TestCardColorNever(t *testing.T) {
 p:=DefaultSemanticPreset()
 got:=RenderDiagnosticCard(DiagnosticCard{Tool:GCloud,Title:"GCLOUD ERROR",Message:"failed"},Options{Preset:&p,Color:false})
 if strings.Contains(got,"\x1b[") {t.Fatalf("unexpected ANSI with color=false: %q",got)}
}
