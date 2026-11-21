package main

import (
 "encoding/json"
 "fmt"
 "os"
 "os/exec"
 "strings"

 tea "charm.land/bubbletea/v2"
 "charm.land/lipgloss/v2"
)

type run struct {
 ID int64 `json:"databaseId"`
 Name string `json:"workflowName"`
 Branch string `json:"headBranch"`
 Status string `json:"status"`
 Conclusion string `json:"conclusion"`
}
type loaded struct { runs []run; err error }
type detail struct { value string; err error }
type model struct {
 repo string
 runs []run
 selected int
 page int
 busy bool
 message string
 detail string
 width int
 height int
}
func gh(args ...string) (string,error) {
 cmd:=exec.Command("gh",args...)
 out,err:=cmd.CombinedOutput()
 if err!=nil {return "",fmt.Errorf("%s: %s",err,strings.TrimSpace(string(out)))}
 return string(out),nil
}
func load(repo string) tea.Cmd {return func() tea.Msg {
 out,err:=gh("run","list","-R",repo,"--limit","30","--json","databaseId,workflowName,headBranch,status,conclusion")
 if err!=nil{return loaded{err:err}}
 var runs []run
 err=json.Unmarshal([]byte(out),&runs)
 return loaded{runs:runs,err:err}
}}
func getDetail(repo string,id int64) tea.Cmd {return func() tea.Msg {
 out,err:=gh("run","view",fmt.Sprint(id),"-R",repo)
 return detail{out,err}
}}
func initial(repo string) model {return model{repo:repo,busy:true,width:80,height:24}}
func (m model) Init() tea.Cmd {return load(m.repo)}
func (m model) Update(msg tea.Msg)(tea.Model,tea.Cmd) {
 switch v:=msg.(type) {
 case tea.WindowSizeMsg: m.width=v.Width;m.height=v.Height
 case loaded:
  m.busy=false
  if v.err!=nil {m.message=v.err.Error()} else {m.runs=v.runs;m.message="";if m.selected>=len(m.runs){m.selected=0}}
 case detail:
  m.busy=false
  if v.err!=nil {m.message=v.err.Error()} else {m.detail=v.value;m.page=1}
 case tea.KeyPressMsg:
  switch v.String() {
  case "ctrl+c":return m,tea.Quit
  case "esc","backspace","left":
   if m.page!=0 {m.page=0;m.detail="";m.message=""} else {return m,tea.Quit}
  case "q":return m,tea.Quit
  case "r":m.busy=true;return m,load(m.repo)
  case "up","k":if m.page==0&&m.selected>0 {m.selected--}
  case "down","j":if m.page==0&&m.selected<len(m.runs)-1 {m.selected++}
  case "enter","right":
   if m.page==0&&len(m.runs)>0 {m.busy=true;return m,getDetail(m.repo,m.runs[m.selected].ID)}
  case "l":
   if m.page==1&&len(m.runs)>0 {
    m.page=2;m.busy=true
    id:=m.runs[m.selected].ID
    return m,func()tea.Msg {out,err:=gh("run","view",fmt.Sprint(id),"-R",m.repo,"--log-failed");return detail{out,err}}
   }
  }
 }
 return m,nil
}
func (m model) View() tea.View {
 purple:=lipgloss.NewStyle().Foreground(lipgloss.Color("#B6A4FF")).Bold(true)
 muted:=lipgloss.NewStyle().Foreground(lipgloss.Color("#9495A8"))
 green:=lipgloss.NewStyle().Foreground(lipgloss.Color("#65D6AE"))
 border:=lipgloss.NewStyle().Border(lipgloss.RoundedBorder()).BorderForeground(lipgloss.Color("#77718F")).Padding(1,2)
 w:=m.width-4;if w>84 {w=84};if w<28 {w=28}
 var body strings.Builder
 body.WriteString(purple.Render("⚡ xi  /  GitHub Actions")+"\n")
 body.WriteString(muted.Render(m.repo)+"\n\n")
 if m.busy {body.WriteString("◌ Loading GitHub data…\n")}
 if m.message!="" {body.WriteString("⚠ "+m.message+"\n")}
 if m.page==0 {
  body.WriteString(purple.Render("WORKFLOW RUNS")+"\n")
  if len(m.runs)==0&&!m.busy {body.WriteString("No runs found.\n")}
  max:=m.height-11;if max<3 {max=3}
  start:=0;if m.selected>=max {start=m.selected-max+1}
  for i:=start;i<len(m.runs)&&i<start+max;i++ {
   r:=m.runs[i];cursor:="  ";if i==m.selected {cursor="❯ "}
   state:=r.Conclusion;if state=="" {state=r.Status}
   label:=fmt.Sprintf("%s%s  %s  ·  %s",cursor,state,r.Name,r.Branch)
   if i==m.selected {body.WriteString(purple.Render(label))} else if state=="success" {body.WriteString(green.Render(label))} else {body.WriteString(label)}
   body.WriteString("\n")
  }
 } else {
  body.WriteString(purple.Render("RUN DETAILS / COMMAND OUTPUT")+"\n")
  if len(m.runs)>0 {body.WriteString(muted.Render(fmt.Sprintf("❯ gh run view %d -R %s",m.runs[m.selected].ID,m.repo))+"\n\n")}
  lines:=strings.Split(m.detail,"\n")
  max:=m.height-13;if max<3 {max=3}
  if len(lines)>max {lines=lines[:max];lines=append(lines,"… output truncated")}
  for _,line:=range lines {body.WriteString(line+"\n")}
 }
 body.WriteString("\n"+muted.Render("← Esc Back   ↑↓ Navigate   Enter Details   L Failed logs   R Refresh   Q Quit"))
 v:=tea.NewView(border.Width(w).Render(body.String()))
 v.AltScreen=true
 return v
}
func main() {
 repo:="rodkisten/codespaces";if len(os.Args)>1 {repo=os.Args[1]}
 p:=tea.NewProgram(initial(repo))
 if _,err:=p.Run();err!=nil {fmt.Fprintln(os.Stderr,err);os.Exit(1)}
}
