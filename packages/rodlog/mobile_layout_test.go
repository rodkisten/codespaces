package rodlog
import (
 "strings"
 "testing"
 "github.com/charmbracelet/lipgloss"
)
func TestCompactDiagnosticCardWidth(t *testing.T) {
 p:=DefaultSemanticPreset()
 d:=DiagnosticCard{Tool:GCloud,Title:"GCLOUD ERROR",Message:"Permission denied on resource project demo-project. Verify the active account and permissions.",API:"run.deploy"}
 got:=RenderDiagnosticCard(d,Options{Preset:&p,Color:true})
 for _,line:=range strings.Split(strings.TrimSpace(got),"\n") {
  if n:=lipgloss.Width(line);n>58 {t.Fatalf("card line too wide (%d): %q",n,line)}
 }
}
func TestDockerChildUsesSeparateLines(t *testing.T) {
 s:=newDockerBuildSteps()
 if _,ok:=s.format("#7 [4/4] RUN npm ci\n");!ok {t.Fatal("missing header")}
 got,ok:=s.format("#7 0.3 npm ERR! code ERESOLVE\n")
 if !ok || !strings.Contains(got,"ERESOLVE") || !strings.Contains(got,"\n     ") {t.Fatalf("child layout: %q",got)}
}
