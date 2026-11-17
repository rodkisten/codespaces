package rodlog

import (
 "bytes"
 "context"
 "strings"
 "testing"
)
func TestGCloudDiagnosticCard(t *testing.T) {
 p:=DefaultSemanticPreset()
 input:="ERROR: (gcloud.run.deploy) PERMISSION_DENIED: missing permission.\n"
 var out bytes.Buffer
 err:=New(Options{Mode:Transform,Tool:GCloud,Color:true,Preset:&p}).Process(context.Background(),strings.NewReader(input),&out)
 if err!=nil{t.Fatal(err)}
 plain:=ansi.ReplaceAllString(out.String(),"")
 for _,s:=range []string{"GCLOUD ERROR","run.deploy","PERMISSION_DENIED","Possible fixes:","╭"} {if !strings.Contains(plain,s){t.Errorf("missing %q: %q",s,plain)}}
}
func TestWranglerDiagnosticCard(t *testing.T) {
 p:=DefaultSemanticPreset()
 input:="✘ [ERROR] Authentication error [code: 10000]\nYou are not authenticated. Please run wrangler login.\n"
 var out bytes.Buffer
 err:=New(Options{Mode:Transform,Tool:Wrangler,Color:true,Preset:&p}).Process(context.Background(),strings.NewReader(input),&out)
 if err!=nil{t.Fatal(err)}
 plain:=ansi.ReplaceAllString(out.String(),"")
 for _,s:=range []string{"WRANGLER ERROR","Authentication error","10000","wrangler login","╭"} {if !strings.Contains(plain,s){t.Errorf("missing %q: %q",s,plain)}}
}
func TestDiagnosticCardDisabled(t *testing.T) {
 p:=DefaultSemanticPreset();p.Diagnostics.Card.Enabled=false
 input:="ERROR: (gcloud.run.deploy) PERMISSION_DENIED\n"
 var out bytes.Buffer
 if err:=New(Options{Mode:Transform,Tool:GCloud,Color:true,Preset:&p}).Process(context.Background(),strings.NewReader(input),&out);err!=nil{t.Fatal(err)}
 if strings.Contains(out.String(),"╭") {t.Fatal("card emitted while disabled")}
}

func TestDiagnosticCardHighlightsTokens(t *testing.T) {
 p:=DefaultSemanticPreset()
 d:=DiagnosticCard{Tool:GCloud,Title:"GCLOUD ERROR",Message:"PERMISSION_DENIED on [demo-project]",API:"gcloud.run.deploy"}
 got:=RenderDiagnosticCard(d,Options{Preset:&p,Color:true})
 if !strings.Contains(got,"\x1b[") || !strings.Contains(got,"PERMISSION_DENIED") {t.Fatalf("expected highlighted tokens: %q",got)}
}
func TestDiagnosticCardNoBorder(t *testing.T) {
 p:=DefaultSemanticPreset();p.Diagnostics.Card.Border="none"
 got:=RenderDiagnosticCard(DiagnosticCard{Tool:Wrangler,Title:"WRANGLER ERROR",Message:"Authentication error"},Options{Preset:&p})
 if strings.Contains(got,"╭") || strings.Contains(got,"┌") {t.Fatalf("unexpected border: %q",got)}
}
