package rodlog

import (
 "embed"
 "fmt"
 "regexp"
 "sort"
 "strings"

 "github.com/pelletier/go-toml/v2"
)

//go:embed presets/default.toml
var presetFS embed.FS

type SemanticPreset struct {
 Steps struct { Enabled bool `toml:"enabled"`; Italic bool `toml:"italic"`; Dimmed bool `toml:"dimmed"` } `toml:"steps"`
 Diagnostics struct { Card struct { Enabled bool `toml:"enabled"`; Border string `toml:"border"`; MaxWidth int `toml:"max_width"` } `toml:"card"` } `toml:"diagnostics"`
 GCloud struct { Enabled bool `toml:"enabled"`; Tokens map[string]string `toml:"tokens"` } `toml:"gcloud"`
 Wrangler struct { Enabled bool `toml:"enabled"`; Tokens map[string]string `toml:"tokens"` } `toml:"wrangler"`
 Docker struct { Enabled bool `toml:"enabled"`; Steps map[string]string `toml:"steps"`; Tokens map[string]string `toml:"tokens"` } `toml:"docker"`
}

func ParseSemanticPreset(data []byte) (SemanticPreset,error) {
 var p SemanticPreset
 if err:=toml.Unmarshal(data,&p);err!=nil{return p,err}
 for tool,tokens:=range map[string]map[string]string{"gcloud":p.GCloud.Tokens,"wrangler":p.Wrangler.Tokens,"docker":p.Docker.Tokens} {
  for name,expression:=range tokens {
   if _,err:=regexp.Compile(expression);err!=nil{return p,fmt.Errorf("%s token %s: %w",tool,name,err)}
  }
 }
 if p.Diagnostics.Card.MaxWidth<0{return p,fmt.Errorf("max_width cannot be negative")}
 return p,nil
}
func DefaultSemanticPreset() SemanticPreset {
 data,err:=presetFS.ReadFile("presets/default.toml")
 if err!=nil {panic(err)}
 p,err:=ParseSemanticPreset(data)
 if err!=nil {panic(err)}
 return p
}

func presetRules(tool Tool,p SemanticPreset) []highlightRule {
 var tokens map[string]string
 switch tool {
 case GCloud: if p.GCloud.Enabled {tokens=p.GCloud.Tokens}
 case Wrangler: if p.Wrangler.Enabled {tokens=p.Wrangler.Tokens}
 case Docker: if p.Docker.Enabled {tokens=p.Docker.Tokens}
 }
 var rules []highlightRule
 names:=make([]string,0,len(tokens))
 for name:=range tokens {names=append(names,name)}
 sort.Strings(names)
 for _,name:=range names {
  color:="36"
  switch name {
  case "error_code":color="31"
  case "environment":color="35"
  case "scope":color="33"
  case "package","path","type":color="36"
  case "value":color="35"
  }
  rules=append(rules,highlightRule{expression:regexp.MustCompile(tokens[name]),color:color,priority:12})
 }
 return rules
}
func HighlightWithPreset(line string,tool Tool,p SemanticPreset,palette SemanticColors) string {
 rules:=append([]highlightRule{},presetRules(tool,p)...)
 rules=append(rules,diagnosticRules...)
 if tool==TypeScript {rules=append(rules,highlightRule{expression:regexp.MustCompile(`\x27[^\x27\r\n]+\x27`),color:"35",priority:11})}
 return highlightWithRules(line,palette,rules)
}
func IsStepLine(line string,tool Tool,p SemanticPreset) bool {
 if !p.Steps.Enabled || (tool!=GCloud && tool!=Wrangler) {return false}
 first:=strings.Fields(strings.TrimSpace(line))
 if len(first)==0{return false}
 verb:=strings.ToLower(strings.TrimSuffix(first[0],":"))
 if !strings.HasSuffix(verb,"ing") {return false}
 switch verb {
 case "deploying","building","uploading","creating","routing","publishing","installing","transforming","rendering","computing","listing","exporting":
  return true
 }
 return false
}
