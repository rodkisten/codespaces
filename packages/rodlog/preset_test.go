package rodlog

import (
 "strings"
 "testing"
)
func TestDefaultSemanticPreset(t *testing.T) {
 p:=DefaultSemanticPreset()
 if !p.GCloud.Enabled || !p.Wrangler.Enabled || !p.Docker.Enabled || !p.Diagnostics.Card.Enabled {t.Fatalf("default preset not loaded: %+v",p)}
 if !IsStepLine("Deploying container to Cloud Run",GCloud,p) {t.Fatal("expected deploying step")}
 if IsStepLine("Something interesting",GCloud,p) {t.Fatal("false step detection")}
 got:=HighlightWithPreset("ERROR: (gcloud.run.deploy) PERMISSION_DENIED [api]",GCloud,p,SemanticColors{})
 for _,part:=range []string{"gcloud.run.deploy","PERMISSION_DENIED","[api]","\x1b["} {if !strings.Contains(got,part){t.Fatalf("missing %q in %q",part,got)}}
}
func TestInvalidSemanticPreset(t *testing.T) {
 _,err:=ParseSemanticPreset([]byte("[gcloud.tokens]\ncommand = '['\n"))
 if err==nil {t.Fatal("invalid regex accepted")}
}
