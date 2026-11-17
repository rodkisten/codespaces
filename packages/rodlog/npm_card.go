package rodlog

import (
 "strings"

 "github.com/charmbracelet/lipgloss"
)

type NPMDiagnostic struct {
 Message string
 Suggestion string
 LogPath string
 Details []string
}

func ParseNPMDiagnostic(lines []string) NPMDiagnostic {
 var d NPMDiagnostic
 for _,line:=range lines {
  content:=strings.TrimSpace(strings.TrimSuffix(line,"\n"))
  content=strings.TrimSpace(strings.TrimPrefix(strings.TrimPrefix(content,"npm ERR!"),"npm error"))
  switch {
  case strings.HasPrefix(content,"Missing script:"):
   d.Message=content
  case strings.HasPrefix(content,"A complete log of this run can be found in:"):
   d.LogPath=strings.TrimSpace(strings.TrimPrefix(content,"A complete log of this run can be found in:"))
  case strings.HasPrefix(content,"npm run"):
   d.Suggestion=content
  case content!="":
   d.Details=append(d.Details,content)
  }
 }
 return d
}

func RenderNPMCard(lines []string, opts Options) string {
 if len(lines)==0{return ""}
 width:=cardWidth(opts)
 d:=ParseNPMDiagnostic(lines)
 title:=lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("9")).Render(iconOrDefault(opts.DiagnosticIcons.Error,"✖")+" NPM ERROR")
 body:=[]string{title}
 if d.Message!="" {for _,line:=range cardLines(d.Message,width) {body=append(body,lipgloss.NewStyle().Bold(true).Render(line))}}
 for _,detail:=range uniqueCardDetails(d.Message,d.Details) {body=append(body,cardLines(detail,width)...)}
 if d.Suggestion!="" {for _,line:=range cardLines("$ "+d.Suggestion,width) {body=append(body,lipgloss.NewStyle().Foreground(lipgloss.Color("10")).Render(line))}}
 if d.LogPath!="" {body=append(body,"Debug log:");for _,line:=range cardLines(d.LogPath,width) {body=append(body,lipgloss.NewStyle().Foreground(lipgloss.Color("14")).Render(line))}}
 return lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("8")).Padding(0,1).Width(width-4).MaxWidth(width).Render(strings.Join(body,"\n"))+"\n"
}
