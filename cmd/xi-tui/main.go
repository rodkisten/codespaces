package main

import (
 "encoding/json"
 "crypto/sha256"
 "path/filepath"
 "time"
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
type loaded struct { runs []run; err error; cached bool; stale bool; request int }
type tickMsg struct{}
type detail struct { value string; err error; cached bool; request int; target int64; logs bool }
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
 frame int
 request int
 refreshing bool
 fromCache bool
 updated time.Time
 detailCache bool
 detailID int64
 detailLogs bool
 scroll int
}
type cacheEntry struct { Saved time.Time `json:"saved"`; Payload json.RawMessage `json:"payload"` }
func cachePath(key string) string {
 base,err:=os.UserCacheDir();if err!=nil {base=os.TempDir()}
 sum:=sha256.Sum256([]byte(key))
 return filepath.Join(base,"xi","github",fmt.Sprintf("%x.json",sum[:12]))
}
func readCache(key string, dest any, ttl time.Duration)(bool,bool) {
 b,err:=os.ReadFile(cachePath(key));if err!=nil{return false,false}
 var entry cacheEntry
 if json.Unmarshal(b,&entry)!=nil||entry.Saved.IsZero()||json.Unmarshal(entry.Payload,dest)!=nil{return false,false}
 return true,time.Since(entry.Saved)>ttl
}
func writeCache(key string, value any) {
 payload,err:=json.Marshal(value);if err!=nil{return}
 b,err:=json.Marshal(cacheEntry{Saved:time.Now(),Payload:payload});if err!=nil{return}
 path:=cachePath(key);if os.MkdirAll(filepath.Dir(path),0700)!=nil{return}
 tmp,err:=os.CreateTemp(filepath.Dir(path),".xi-*.tmp");if err!=nil{return}
 defer os.Remove(tmp.Name())
 if tmp.Chmod(0600)!=nil||func()bool{_,e:=tmp.Write(b);return e!=nil}(){tmp.Close();return}
 if tmp.Close()!=nil{return};_ = os.Rename(tmp.Name(),path)
}
func spinner() tea.Cmd {return tea.Tick(110*time.Millisecond,func(time.Time)tea.Msg{return tickMsg{}})}
func cachedRuns(repo string) ([]run,bool,bool) {
 var runs []run;ok,stale:=readCache("runs:"+repo,&runs,45*time.Second);return runs,ok,stale
}
func cachedDetail(repo string,id int64,logs bool)(string,bool,bool) {
 var value string;key:=fmt.Sprintf("detail:%s:%d:%t",repo,id,logs)
 ttl:=2*time.Minute;if logs {ttl=10*time.Minute}
 ok,stale:=readCache(key,&value,ttl);return value,ok,stale
}
func fetchRuns(repo string,request int)tea.Cmd{return func()tea.Msg{
 out,err:=gh("run","list","-R",repo,"--limit","30","--json","databaseId,workflowName,headBranch,status,conclusion")
 if err!=nil{return loaded{err:err,request:request}}
 var runs []run;if err=json.Unmarshal([]byte(out),&runs);err!=nil{return loaded{err:err,request:request}}
 writeCache("runs:"+repo,runs)
 return loaded{runs:runs,request:request}
}}
func fetchDetail(repo string,id int64,logs bool,request int)tea.Cmd{return func()tea.Msg{
 args:=[]string{"run","view",fmt.Sprint(id),"-R",repo};if logs {args=append(args,"--log-failed")}
 out,err:=gh(args...);if err!=nil{return detail{err:err,request:request,target:id,logs:logs}}
 writeCache(fmt.Sprintf("detail:%s:%d:%t",repo,id,logs),out)
 return detail{value:out,request:request,target:id,logs:logs}
}}
func gh(args ...string) (string,error) {
 cmd:=exec.Command("gh",args...)
 out,err:=cmd.CombinedOutput()
 if err!=nil {return "",fmt.Errorf("%s: %s",err,strings.TrimSpace(string(out)))}
 return string(out),nil
}
func initial(repo string) model {
 m:=model{repo:repo,width:80,height:24,request:1}
 if runs,ok,_:=cachedRuns(repo);ok {m.runs=runs;m.fromCache=true;m.refreshing=true} else {m.busy=true}
 return m
}
func (m model) Init() tea.Cmd {return tea.Batch(fetchRuns(m.repo,m.request),spinner())}
func (m model) openDetail(logs bool)(tea.Model,tea.Cmd) {
 if len(m.runs)==0{return m,nil}
 id:=m.runs[m.selected].ID
 m.page=1;m.detailID=id;m.detailLogs=logs;m.scroll=0;m.request++
 if value,ok,_:=cachedDetail(m.repo,id,logs);ok {m.detail=value;m.detailCache=true;m.busy=false;m.refreshing=true} else {m.detail="";m.detailCache=false;m.busy=true;m.refreshing=false}
 return m,fetchDetail(m.repo,id,logs,m.request)
}
func (m model) Update(msg tea.Msg)(tea.Model,tea.Cmd) {
 switch v:=msg.(type) {
 case tea.WindowSizeMsg: m.width=v.Width;m.height=v.Height
 case tickMsg:
  m.frame++;return m,spinner()
 case loaded:
  if v.request!=m.request||m.page!=0 {break}
  m.busy=false;m.refreshing=false
  if v.err!=nil {m.message=v.err.Error()} else {m.runs=v.runs;m.fromCache=false;m.updated=time.Now();m.message="";if m.selected>=len(m.runs){m.selected=0}}
 case detail:
  if v.request!=m.request||m.page!=1||v.target!=m.detailID||v.logs!=m.detailLogs {break}
  m.busy=false;m.refreshing=false
  if v.err!=nil {m.message=v.err.Error()} else {m.detail=v.value;m.detailCache=false;m.message="";m.updated=time.Now()}
 case tea.KeyPressMsg:
  switch v.String() {
  case "ctrl+c","q":return m,tea.Quit
  case "esc","backspace","left":
   if m.page!=0 {m.page=0;m.scroll=0;m.request++;m.busy=false;m.refreshing=false;m.message=""} else {return m,tea.Quit}
  case "r":
   m.request++;m.message="";m.refreshing=true
   if m.page==0{return m,fetchRuns(m.repo,m.request)}
   return m,fetchDetail(m.repo,m.detailID,m.detailLogs,m.request)
  case "up","k":
   if m.page==0&&m.selected>0 {m.selected--} else if m.page==1&&m.scroll>0 {m.scroll--}
  case "down","j":
   if m.page==0&&m.selected<len(m.runs)-1 {m.selected++} else if m.page==1 {m.scroll++}
  case "enter","right":if m.page==0 {return m.openDetail(false)}
  case "l":if m.page==1 {return m.openDetail(true)}
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
 if m.busy||m.refreshing {frames:=[]string{"◐","◓","◑","◒"};state:="Loading";if m.refreshing {state="Refreshing"};body.WriteString(purple.Render(frames[m.frame%len(frames)]+" "+state+" GitHub data…")+"\n")} else if m.fromCache||m.detailCache {body.WriteString(muted.Render("⚡ Cached snapshot · R refresh")+"\n")}
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
  if m.scroll>=len(lines) {m.scroll=len(lines)-1};if m.scroll<0 {m.scroll=0}
  if m.scroll<len(lines) {lines=lines[m.scroll:]}
  if len(lines)>max {lines=lines[:max];lines=append(lines,"↓ scroll for more")}
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
