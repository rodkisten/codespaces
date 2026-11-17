package rodlog

import (
 "regexp"
 "strings"

 "github.com/charmbracelet/lipgloss"
)

type DiagnosticCard struct {
 Tool Tool
 Title string
 Code string
 API string
 Message string
 Details []string
 Fixes []string
}
var gcloudAPI = regexp.MustCompile(`\(gcloud\.([^)]+)\)`)
var errorCode = regexp.MustCompile(`\b[A-Z][A-Z0-9_]{3,}\b`)
var wranglerCardError = regexp.MustCompile(`\[ERROR\]\s*(.*?)(?:\s*\[code:\s*(\d+)\])?$`)


func ParseDiagnosticCard(tool Tool, lines []string) DiagnosticCard {
 d:=DiagnosticCard{Tool:tool}
 for _,line:=range lines {
  clean:=strings.TrimSpace(ansi.ReplaceAllString(line,""))
  if clean=="" {continue}
  switch tool {
  case GCloud:
   if strings.HasPrefix(clean,"ERROR:") {
    if d.Title=="" {d.Title="GCLOUD ERROR"}
    if m:=gcloudAPI.FindStringSubmatch(clean);m!=nil {d.API=m[1]}
    for _,code:=range errorCode.FindAllString(clean,-1) {
     if code!="ERROR" && code!="GCLOUD" && code!="HTTP" {d.Code=code;break}
    }
    message:=strings.TrimSpace(strings.TrimPrefix(clean,"ERROR:"))
    if m:=gcloudAPI.FindString(message);m!="" {message=strings.TrimSpace(strings.Replace(message,m,"",1))}
    if d.Message=="" {d.Message=message} else {d.Details=append(d.Details,message)}
   } else {d.Details=append(d.Details,clean)}
  case Wrangler:
   if m:=wranglerCardError.FindStringSubmatch(clean);m!=nil {
    if d.Title=="" {d.Title="WRANGLER ERROR"}
    if d.Message=="" {d.Message=m[1]} else {d.Details=append(d.Details,m[1])}
    if m[2]!="" {d.Code=m[2]}
   } else if strings.HasPrefix(clean,"ERROR:") {
    if d.Title=="" {d.Title="WRANGLER ERROR"}
    if d.Message=="" {d.Message=strings.TrimSpace(strings.TrimPrefix(clean,"ERROR:"))} else {d.Details=append(d.Details,clean)}
   } else {
    d.Details=append(d.Details,clean)
   }
  }
 }
 if d.Title=="" {d.Title=strings.ToUpper(string(tool))+" ERROR"}
 // A structured code appears once in the heading, never again in its message.
 if d.Code!="" {d.Message=strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(d.Message),d.Code+":"))}
 d.Message=cleanCardText(d.Message)
 seen:=map[string]bool{}
 if d.Message!="" {seen[strings.ToLower(d.Message)]=true}
 details:=make([]string,0,len(d.Details))
 for _,detail:=range d.Details {
  detail=cleanCardText(detail)
  if detail=="" || seen[strings.ToLower(detail)] {continue}
  seen[strings.ToLower(detail)]=true
  details=append(details,detail)
 }
 d.Details=details
 if tool==Wrangler && strings.Contains(strings.ToLower(strings.Join(lines,"\n")),"not authenticated") {
  d.Fixes=append(d.Fixes,"Run wrangler login to authenticate")
 }
 if tool==GCloud && d.Code=="PERMISSION_DENIED" {
  d.Fixes=append(d.Fixes,"Verify IAM permissions and the active gcloud account")
 }
 return d
}

// cleanCardText conservatively normalizes whitespace, retaining meaningful wording.
func cleanCardText(s string) string {
 return strings.Join(strings.Fields(strings.TrimSpace(s))," ")
}

func RenderDiagnosticCard(d DiagnosticCard,opts Options) string {
 if opts.Preset==nil || !opts.Preset.Diagnostics.Card.Enabled {return ""}
 width:=cardWidth(opts)
 color:=lipgloss.Color("9")
 title:=lipgloss.NewStyle().Bold(true).Foreground(color).Render(iconOrDefault(opts.DiagnosticIcons.Error,"✖")+" "+d.Title)
 lines:=[]string{title}
 if d.API!="" {lines=append(lines,lipgloss.NewStyle().Foreground(lipgloss.Color("14")).Render("API: "+d.API))}
 if d.Code!="" {lines=append(lines,lipgloss.NewStyle().Foreground(lipgloss.Color("11")).Render("Code: "+d.Code))}
 if d.Message!="" {for _,part:=range wrapCardText(d.Message,width-6) {lines=append(lines,HighlightWithPreset(part,d.Tool,*opts.Preset,opts.SemanticColors))}}
 for _,detail:=range uniqueCardDetails(d.Message,d.Details) {for _,part:=range wrapCardText(detail,width-6) {lines=append(lines,HighlightWithPreset(part,d.Tool,*opts.Preset,opts.SemanticColors))}}
 if len(d.Fixes)>0 {lines=append(lines,"Possible fixes:");for _,fix:=range uniqueCardDetails("",d.Fixes) {lines=append(lines,wrapCardText("› "+fix,width-6)... )}}
 style:=lipgloss.NewStyle().Padding(0,1).Width(width-4).MaxWidth(width)
 switch opts.Preset.Diagnostics.Card.Border {
 case "none": // no border
 case "normal":style=style.Border(lipgloss.NormalBorder()).BorderForeground(color)
 default:style=style.Border(lipgloss.RoundedBorder()).BorderForeground(color)
 }
 content:=strings.Join(lines,"\n")
 return style.Render(content)+"\n"
}
