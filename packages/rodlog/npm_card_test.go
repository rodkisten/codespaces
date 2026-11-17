package rodlog

import (
 "bytes"
 "context"
 "strings"
 "testing"
)
func TestNPMMultilineCard(t *testing.T) {
 input:="npm ERR! Missing script: \"release\"\nnpm ERR! To see a list of scripts, run:\nnpm ERR!   npm run\nnpm ERR! A complete log of this run can be found in: /tmp/npm/_logs/example-debug-0.log\n"
 var out bytes.Buffer
 err:=New(Options{Mode:Transform,Tool:NPM,Color:true}).Process(context.Background(),strings.NewReader(input),&out)
 if err!=nil {t.Fatal(err)}
 got:=ansi.ReplaceAllString(out.String(),"")
 for _,part:=range []string{"NPM ERROR","Missing script","npm run","Debug log:","╭","╰"} {
  if !strings.Contains(got,part){t.Errorf("missing %q: %q",part,got)}
 }
}
func TestNPMDiagnosticStructured(t *testing.T) {
 d:=ParseNPMDiagnostic([]string{"npm ERR! Missing script: \"release\"\n","npm ERR!   npm run\n","npm ERR! A complete log of this run can be found in: /tmp/log.txt\n"})
 if d.Message!="Missing script: \"release\"" || d.Suggestion!="npm run" || d.LogPath!="/tmp/log.txt" {t.Fatalf("unexpected parsed diagnostic: %+v",d)}
}
func TestNPMRawPreserved(t *testing.T) {
 input:="npm ERR! first\nnpm ERR! second\n"
 var out bytes.Buffer
 if err:=New(Options{Mode:Raw,Tool:NPM,Color:true}).Process(context.Background(),strings.NewReader(input),&out);err!=nil{t.Fatal(err)}
 if out.String()!=input {t.Fatalf("raw altered: %q",out.String())}
}
