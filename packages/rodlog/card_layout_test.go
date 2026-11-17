package rodlog

import (
 "strings"
 "testing"
 "github.com/charmbracelet/lipgloss"
)
func TestSmartCardWrapAndHighlight(t *testing.T) {
 p:=DefaultSemanticPreset()
 d:=DiagnosticCard{Tool:GCloud,Title:"GCLOUD ERROR",Code:"PERMISSION_DENIED",Message:"PERMISSION_DENIED "+strings.Repeat("long-token/",16),Details:[]string{"duplicate detail","duplicate detail"}}
 got:=RenderDiagnosticCard(d,Options{Preset:&p,Color:true})
 for _,line:=range strings.Split(strings.TrimSuffix(got,"\n"),"\n") {
  if w:=lipgloss.Width(line);w>58 {t.Fatalf("card overflow: width=%d line=%q",w,line)}
 }
 if strings.Count(got,"duplicate detail")!=1 {t.Fatalf("duplicate details: %q",got)}
 if !strings.Contains(got,"\x1b[") {t.Fatal("semantic highlighting lost")}
}
func TestNPMCardNarrowWidthAndDedup(t *testing.T) {
 t.Setenv("COLUMNS","38")
 got:=RenderNPMCard([]string{"npm ERR! Missing script: \"release\"","npm ERR! Duplicate line","npm ERR! Duplicate line","npm ERR! "+strings.Repeat("X",90)},Options{Color:true})
 for _,line:=range strings.Split(strings.TrimSuffix(got,"\n"),"\n") {
  if w:=lipgloss.Width(line);w>38 {t.Fatalf("npm card overflow: width=%d line=%q",w,line)}
 }
 if strings.Count(got,"Duplicate line")!=1 {t.Fatalf("npm duplicate: %q",got)}
}
