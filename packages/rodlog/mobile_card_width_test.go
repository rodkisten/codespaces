package rodlog

import (
 "strings"
 "testing"

 "github.com/charmbracelet/lipgloss"
)

func assertCardWithin(t *testing.T, rendered string, width int) {
 t.Helper()
 for _,line:=range strings.Split(strings.TrimSuffix(rendered,"\n"),"\n") {
  if got:=lipgloss.Width(line);got>width {t.Fatalf("line exceeds card width %d: %d %q",width,got,line)}
 }
}
func TestMobileCardsFitNarrowGitHubViewer(t *testing.T) {
 t.Setenv("COLUMNS","90")
 t.Setenv("RODLOG_CARD_WIDTH","36")
 p:=DefaultSemanticPreset()
 d:=DiagnosticCard{Tool:GCloud,Title:"GCLOUD ERROR",API:"artifacts.repositories.downloadArtifacts",Code:"PERMISSION_DENIED",Message:"Permission denied on resource project demo-project with a very long resource path /projects/demo-project/locations/us-central1/repositories/test."}
 got:=RenderDiagnosticCard(d,Options{Preset:&p,Color:true})
 assertCardWithin(t,got,36)
 if !strings.Contains(got,"API:") || !strings.Contains(got,"Code:") {t.Fatalf("missing labels: %q",got)}
 npm:=RenderNPMCard([]string{"npm ERR! Missing script: \"release\"","npm ERR! A complete log of this run can be found in: /tmp/npm/_logs/example-debug-0.log"},Options{Color:true})
 assertCardWithin(t,npm,36)
}
func TestCardWidthOverrideAndColumns(t *testing.T) {
 t.Setenv("RODLOG_CARD_WIDTH","48")
 t.Setenv("COLUMNS","32")
 if got:=cardWidth(Options{});got!=32 {t.Fatalf("expected COLUMNS to cap card at 32, got %d",got)}
 t.Setenv("COLUMNS","90")
 if got:=cardWidth(Options{});got!=48 {t.Fatalf("expected override 48, got %d",got)}
}
