package rodlog
import (
 "strings"
 "testing"
)
func TestCardUsesDimBorderAndHighlightedMessage(t *testing.T) {
 p:=DefaultSemanticPreset()
 got:=RenderDiagnosticCard(DiagnosticCard{Tool:GCloud,Title:"GCLOUD ERROR",Code:"PERMISSION_DENIED",Message:"missing permission.",Fixes:[]string{"Verify IAM permissions"}},Options{Preset:&p,Color:true})
 if !strings.Contains(got,"╭") || !strings.Contains(got,"╯") {t.Fatalf("rounded border missing: %q",got)}
 if !strings.Contains(got,"Possible fixes:") {t.Fatalf("fix label missing: %q",got)}
 if !strings.Contains(got,"missing permission.") {t.Fatalf("message missing: %q",got)}
}
