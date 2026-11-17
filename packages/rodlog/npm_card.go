package rodlog

import (
  "os"
 "strconv"
 "strings"
 "github.com/charmbracelet/lipgloss"
)

// RenderNPMCard formats a bounded multi-line npm error as a single terminal card.
func RenderNPMCard(lines []string, opts Options) string {
 if len(lines)==0{return ""}
 width:=80
 if n,err:=strconv.Atoi(os.Getenv("COLUMNS"));err==nil && n>=30 && n<=1000 {width=n}
 if width>100 {width=100}
 if width<30 {width=30}
 var body []string
 for _,line:=range lines {
  content:=strings.TrimSpace(strings.TrimSuffix(line,"\n"))
  content=strings.TrimPrefix(content,"npm ERR!")
  content=strings.TrimPrefix(content,"npm error")
  body=append(body,strings.TrimSpace(content))
 }
 title:=lipgloss.NewStyle().Bold(true).Foreground(lipgloss.Color("9")).Render(iconOrDefault(opts.DiagnosticIcons.Error,"✖")+" NPM ERROR")
 content:=title+"\n"+strings.Join(body,"\n")
 return lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("9")).Padding(0,1).Width(width-4).Render(content)+"\n"
}


