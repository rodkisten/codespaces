package rodlog

import (
 "strings"
 "testing"
 "github.com/charmbracelet/lipgloss"
)
func TestDiagnosticCardDeduplicatesMessageAndCode(t *testing.T) {
 d:=ParseDiagnosticCard(GCloud,[]string{
  "ERROR: (gcloud.run.deploy) PERMISSION_DENIED: missing permission.",
  "  missing permission.",
  "  missing permission.",
 })
 if d.Code!="PERMISSION_DENIED" || d.Message!="missing permission." || len(d.Details)!=0 {t.Fatalf("bad deduplication: %+v",d)}
}
func TestDiagnosticCardWrapLongUnbrokenToken(t *testing.T) {
 p:=DefaultSemanticPreset()
 got:=RenderDiagnosticCard(DiagnosticCard{Tool:Wrangler,Title:"WRANGLER ERROR",Message:strings.Repeat("X",160)},Options{Preset:&p})
 for _,line:=range strings.Split(strings.TrimSuffix(got,"\n"),"\n") {
  if n:=lipgloss.Width(line); n>58 {t.Fatalf("line width %d exceeds 58: %q",n,line)}
 }
}
