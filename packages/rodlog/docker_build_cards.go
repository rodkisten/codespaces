package rodlog

import (
 "fmt"
 "regexp"
 "strings"

 "github.com/charmbracelet/lipgloss"
 "github.com/charmbracelet/lipgloss/tree"
)

type dockerBuildSteps struct {
 numbers map[string]int
 children map[string]int
 totals map[string]string
 next int
 separator string
 colors DockerColors
}

func newDockerBuildSteps() *dockerBuildSteps {
 return &dockerBuildSteps{numbers: make(map[string]int), children: make(map[string]int), totals: make(map[string]string), separator: strings.Repeat("─", 36), colors: DefaultDockerColors()}
}

var buildKitHeader = regexp.MustCompile(`^#(\d+)\s+\[([^]]+)\]\s+(.+?)(?:\r?\n)?$`)
var buildKitLegacyHeader = regexp.MustCompile(`^Step\s+(\d+)/(\d+)\s*:\s*(.+?)(?:\r?\n)?$`)
var buildKitStatus = regexp.MustCompile(`^#(\d+)\s+(DONE|CACHED|ERROR|FINISHED)([^\r\n]*)(?:\r?\n)?$`)
var buildKitChild = regexp.MustCompile(`^#(\d+)\s+(?:(\d+(?:\.\d+)?)\s+)?(.+?)(?:\r?\n)?$`)
var buildKitFinalError = regexp.MustCompile(`(?i)^STEP\s+(\d+)\s+ERROR:\s*(.+?)(?:\r?\n)?$`)
var buildKitInstruction = regexp.MustCompile(`(?i)^(?:RUN|COPY|ADD|FROM|WORKDIR|ENV|ARG|CMD|ENTRYPOINT|USER|EXPOSE|LABEL|HEALTHCHECK|SHELL|VOLUME|ONBUILD|STOPSIGNAL)\b`)
var buildKitFraction = regexp.MustCompile(`(?:^|\s)(\d+)/(\d+)(?:\]|\s|$)`)

func (s *dockerBuildSteps) format(text string) (string, bool) {
 if m := buildKitFinalError.FindStringSubmatch(text); m != nil {
  return lipgloss.NewStyle().Foreground(lipgloss.Color("9")).Render("✖ STEP "+m[1]+" ERROR")+"  "+m[2]+"\n", true
 }
 if m := buildKitStatus.FindStringSubmatch(text); m != nil {
  if number, ok := s.numbers[m[1]]; ok {
   color := s.colors.Done
   if m[2]=="CACHED" {color=s.colors.Cached}
   if m[2]=="ERROR" {color=s.colors.Error}
   return fmt.Sprintf("\x1b[2mSTEP %d\x1b[0m  \x1b[%sm%s\x1b[0m%s\n",number,color,m[2],m[3]),true
  }
 }
 // Headers must be recognized before nested progress so that #7 [4/4] RUN
 // is not accidentally classified as a child of an existing BuildKit ID.
 var key, command, total string
 if m := buildKitHeader.FindStringSubmatch(text); m != nil {
  key,command=m[1],m[3]
  if fraction:=buildKitFraction.FindStringSubmatch(m[2]); fraction!=nil {total=fraction[2]}
 } else if m := buildKitLegacyHeader.FindStringSubmatch(text); m!=nil && buildKitInstruction.MatchString(m[3]) {
  key,command,total="legacy-"+m[1],m[3],m[2]
 }
 if key!="" {
  if _, exists:=s.numbers[key]; exists {return "",false}
  s.next++
  s.numbers[key]=s.next
  if total!="" {s.totals[key]=total}
  badge:=fmt.Sprintf("\x1b[%sm\x1b[%sm STEP %d \x1b[0m",s.colors.BadgeBackground,s.colors.BadgeText,s.next)
  colored:=command
  if highlighted,err:=SyntaxHighlight(command,"dockerfile");err==nil {colored=strings.TrimRight(highlighted,"\r\n")}
  return fmt.Sprintf("%s  %s\n\x1b[%sm%s\x1b[0m\n",badge,colored,s.colors.Separator,s.separator),true
 }
 if m:=buildKitChild.FindStringSubmatch(text);m!=nil {
  if number,ok:=s.numbers[m[1]];ok {
   s.children[m[1]]++
   total:=s.totals[m[1]]
   if total=="" {total=fmt.Sprint(number)}
   label:=fmt.Sprintf("STEP %d.%d/%s",number,s.children[m[1]],total)
   body:=strings.TrimSpace(m[3])
   if m[2]!="" {body=m[2]+"s  "+body}
   // Lip Gloss owns the nested tree layout, padding and enumerator.
   enumeratorStyle:=lipgloss.NewStyle().Foreground(lipgloss.Color("63")).MarginRight(1)
   itemStyle:=lipgloss.NewStyle().Foreground(lipgloss.Color("212"))
   if strings.Contains(strings.ToLower(body),"err!") || strings.Contains(strings.ToLower(body),"error") {itemStyle=lipgloss.NewStyle().Foreground(lipgloss.Color("9"))}
   nested:=tree.New().Child(label+"  "+body).Enumerator(tree.RoundedEnumerator).EnumeratorStyle(enumeratorStyle).ItemStyle(itemStyle)
   return "  "+nested.String()+"\n",true
  }
 }
 return "",false
}
