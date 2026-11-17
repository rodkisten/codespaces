package rodlog

import (
 "os"
 "strconv"
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
 width:=80
 if n,err:=strconv.Atoi(os.Getenv("COLUMNS"));err==nil && n>=30 && n<=1000 {width=n}
 if width>100 {width=100}
 d:=ParseNPMDiagnostic(lines)
 title:=lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("9")).Render(iconOrDefault(opts.DiagnosticIcons.Error,"✖")+" NPM ERROR")
 body:=[]string{title}
 if d.Message!="" {body=append(body,lipgloss.NewStyle().Bold(true).Render(d.Message))}
 body=append(body,d.Details...)
 if d.Suggestion!="" {body=append(body,lipgloss.NewStyle().Foreground(lipgloss.Color("10")).Render("$ "+d.Suggestion))}
 if d.LogPath!="" {body=append(body,"Debug log:",lipgloss.NewStyle().Foreground(lipgloss.Color("14")).Render(d.LogPath))}
 return lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("9")).Padding(0,1).Width(width-4).Render(strings.Join(body,"\n"))+"\n"
}
