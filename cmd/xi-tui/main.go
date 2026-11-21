package main

import (
 "encoding/json"
 "crypto/sha256"
 "path/filepath"
 "time"
 "fmt"
 "os"
 "os/exec"
 "context"
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
type job struct { ID int64 `json:"databaseId"`; Name string `json:"name"`; Status string `json:"status"`; Conclusion string `json:"conclusion"`; Steps []step `json:"steps"` }
type step struct { Name string `json:"name"`; Status string `json:"status"`; Conclusion string `json:"conclusion"`; Number int `json:"number"` }
type jobResponse struct { jobs []job; err error; request int; id int64 }
type logChunk struct { text string; done bool; err error; request int; id int64 }
type logReady struct { chunks <-chan logChunk; request int }
func waitChunk(ch <-chan logChunk) tea.Cmd {return func()tea.Msg {v,ok:=<-ch;if !ok{return logChunk{done:true}};return v}}
func streamJobLogs(ctx context.Context,repo string,jobID int64,runID int64,request int)tea.Cmd {return func()tea.Msg {
 ch:=make(chan logChunk,32)
 go func(){
  defer close(ch)
  ctx,cancel:=context.WithTimeout(ctx,90*time.Second);defer cancel()
  cmd:=exec.CommandContext(ctx,"gh","run","view",fmt.Sprint(runID),"-R",repo,"--job",fmt.Sprint(jobID),"--log")
  pipe,err:=cmd.StdoutPipe();if err!=nil {ch<-logChunk{err:err,done:true,request:request,id:jobID};return}
  cmd.Stderr=cmd.Stdout
  if err=cmd.Start();err!=nil {ch<-logChunk{err:err,done:true,request:request,id:jobID};return}
  buf:=make([]byte,8192)
  for {n,e:=pipe.Read(buf);if n>0 {select {case ch<-logChunk{text:string(buf[:n]),request:request,id:jobID}:case <-ctx.Done():_ = cmd.Wait();return}};if e!=nil {break}}
  err=cmd.Wait();if ctx.Err()!=nil {err=ctx.Err()}
  select {case ch<-logChunk{done:true,err:err,request:request,id:jobID}:case <-ctx.Done():}
 }()
 return logReady{chunks:ch,request:request}
}}
func fetchJobs(repo string,id int64,request int)tea.Cmd {return func()tea.Msg {
 out,err:=gh("run","view",fmt.Sprint(id),"-R",repo,"--json","jobs")
 if err!=nil{return jobResponse{err:err,request:request,id:id}}
 var payload struct { Jobs []job `json:"jobs"` }
 err=json.Unmarshal([]byte(out),&payload)
 if err==nil {writeCache(fmt.Sprintf("jobs:%s:%d",repo,id),payload.Jobs)}
 return jobResponse{jobs:payload.Jobs,err:err,request:request,id:id}
}}

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
 jobs []job
 jobSelected int
 stepSelected int
 stepFocus bool
 logFilter string
 logJobID int64
 logChannel <-chan logChunk
 logCancel context.CancelFunc
 logStep string
 searchMode bool
 searchQuery string
}
type cacheEntry struct { Saved time.Time `json:"saved"`; Payload json.RawMessage `json:"payload"` }
func cachePath(key string) string {
 base,err:=os.UserCacheDir();if err!=nil {base=os.TempDir()}
 sum:=sha256.Sum256([]byte(key))
 return filepath.Join(base,"xi","github",fmt.Sprintf("%x.json",sum[:12]))
}
func readCache(key string, dest any, ttl time.Duration)(bool,bool) {
 if ok,stale:=hotCache.get(key,dest,ttl);ok {return true,stale}
 b,err:=os.ReadFile(cachePath(key));if err!=nil{return false,false}
 var entry cacheEntry
 if json.Unmarshal(b,&entry)!=nil||entry.Saved.IsZero()||json.Unmarshal(entry.Payload,dest)!=nil{return false,false}
 hotCache.put(key,dest)
 return true,time.Since(entry.Saved)>ttl
}
func writeCache(key string, value any) {
 hotCache.put(key,value)
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
 ctx,cancel:=context.WithTimeout(context.Background(),18*time.Second)
 defer cancel()
 cmd:=exec.CommandContext(ctx,"gh",args...)
 out,err:=cmd.CombinedOutput()
 if ctx.Err()!=nil {return "",fmt.Errorf("GitHub request timed out after 18s; cached data remains available")}
 if err!=nil {return "",fmt.Errorf("%s: %s",err,strings.TrimSpace(string(out)))}
 return string(out),nil
}
func initial(repo string) model {
 m:=model{repo:repo,width:80,height:24,request:1}
 if runs,ok,_:=cachedRuns(repo);ok {m.runs=runs;m.fromCache=true;m.refreshing=true} else {m.busy=true}
 return m
}
func (m model) Init() tea.Cmd {
 if len(m.runs)>0 {return tea.Batch(fetchRuns(m.repo,m.request),spinner())}
 return tea.Batch(fetchRuns(m.repo,m.request),spinner())
}
func (m model) stopLog() model {if m.logCancel!=nil {m.logCancel();m.logCancel=nil};m.logChannel=nil;return m}
func (m model) startLog() (tea.Model,tea.Cmd) {
 m=m.stopLog();ctx,cancel:=context.WithCancel(context.Background());m.logCancel=cancel
 return m,streamJobLogs(ctx,m.repo,m.logJobID,m.detailID,m.request)
}
func (m model) openJobs()(tea.Model,tea.Cmd) {
 if len(m.runs)==0{return m,nil}
 m.page=2;m.request++;m.busy=true;m.refreshing=false;m.message="";m.jobSelected=0;m.stepSelected=0;m.stepFocus=false
 var jobs []job
 if ok,_:=readCache(fmt.Sprintf("jobs:%s:%d",m.repo,m.detailID),&jobs,2*time.Minute);ok {m.jobs=jobs;m.busy=false;m.refreshing=true}
 return m,fetchJobs(m.repo,m.detailID,m.request)
}
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
 case jobResponse:
  if v.request!=m.request||m.page!=2||v.id!=m.detailID {break}
  m.busy=false;m.refreshing=false
  if v.err!=nil {m.message=v.err.Error()} else {m.jobs=v.jobs;m.message="";m.updated=time.Now()}
 case logReady:
  if v.request!=m.request||m.page!=3 {break}
  m.logChannel=v.chunks
  return m,waitChunk(v.chunks)
 case logChunk:
  if v.request!=m.request||m.page!=3||v.id!=m.logJobID {break}
  if v.text!="" {m.detail+=v.text}
  if v.done {m.logCancel=nil;m.busy=false;m.refreshing=false;if v.err!=nil {m.message=v.err.Error()} else {writeCache(fmt.Sprintf("joblogs:%s:%d",m.repo,m.logJobID),m.detail)}} else {return m,waitChunk(m.logChannel)}
 case detail:
  if v.request!=m.request||m.page!=1||v.target!=m.detailID||v.logs!=m.detailLogs {break}
  m.busy=false;m.refreshing=false
  if v.err!=nil {m.message=v.err.Error()} else {m.detail=v.value;m.detailCache=false;m.message="";m.updated=time.Now()}
 case tea.KeyPressMsg:
  if m.searchMode {
   switch v.String() {
   case "esc":m.searchMode=false
   case "enter":m.searchMode=false
   case "backspace":if len(m.searchQuery)>0 {m.searchQuery=m.searchQuery[:len(m.searchQuery)-1]}
   default:if len(v.String())==1&&len(m.searchQuery)<80 {m.searchQuery+=v.String()}
   }
   m.scroll=0;return m,nil
  }
  switch v.String() {
  case "ctrl+c":m=m.stopLog();return m,tea.Quit
  case "q":if !m.searchMode {m=m.stopLog();return m,tea.Quit}
  case "esc","backspace","left":
   if m.searchMode {m.searchMode=false;break}
   m=m.stopLog()
   if m.page!=0 {if m.page==3 {m.page=2} else if m.page==2 {m.page=1} else {m.page=0};m.scroll=0;m.request++;m.busy=false;m.refreshing=false;m.message=""} else {return m,tea.Quit}
  case "r":
   if m.busy||m.refreshing {break}
   m.request++;m.message="";m.refreshing=true
   if m.page==0{return m,fetchRuns(m.repo,m.request)}
   if m.page==2{return m,fetchJobs(m.repo,m.detailID,m.request)}
   if m.page==3 {m.detail="";m.busy=true;m.refreshing=false;return m.startLog()}
   return m,fetchDetail(m.repo,m.detailID,m.detailLogs,m.request)
  case "up","k":
   if m.page==0&&m.selected>0 {m.selected--} else if m.page==2&&m.stepFocus&&len(m.jobs)>0&&m.stepSelected>0 {m.stepSelected--} else if m.page==2&&m.jobSelected>0 {m.jobSelected--;m.stepSelected=0} else if (m.page==1||m.page==3)&&m.scroll>0 {m.scroll--}
  case "down","j":
   if m.page==0&&m.selected<len(m.runs)-1 {m.selected++} else if m.page==2&&m.stepFocus&&len(m.jobs)>0&&m.stepSelected<len(m.jobs[m.jobSelected].Steps)-1 {m.stepSelected++} else if m.page==2&&!m.stepFocus&&m.jobSelected<len(m.jobs)-1 {m.jobSelected++;m.stepSelected=0} else if m.page==1||m.page==3 {m.scroll++}
  case "/":m.searchMode=true;m.searchQuery="";m.scroll=0
  case "f":if m.page==3 {if m.logFilter=="" {m.logFilter="error"} else {m.logFilter=""};m.scroll=0}
  case "tab":if m.page==2&&len(m.jobs)>0&&len(m.jobs[m.jobSelected].Steps)>0 {m.stepFocus=!m.stepFocus}
  case "enter","right":
   if m.page==0 {return m.openDetail(false)}
   if m.page==1 {return m.openJobs()}
   if m.page==2&&len(m.jobs)>0 {m.page=3;m.request++;m.logJobID=m.jobs[m.jobSelected].ID;m.detail="";m.scroll=0;m.message="";m.busy=true;m.refreshing=false
    var cached string;if ok,_:=readCache(fmt.Sprintf("joblogs:%s:%d",m.repo,m.logJobID),&cached,10*time.Minute);ok {m.detail=cached;m.busy=false;m.refreshing=true}
    m.logStep="";if m.stepFocus&&m.stepSelected<len(m.jobs[m.jobSelected].Steps) {m.logStep=m.jobs[m.jobSelected].Steps[m.stepSelected].Name}
    return m.startLog()
   }
  case "l":if m.page==1&&!m.detailLogs {return m.openDetail(true)}
  case "J":if m.page==1 {return m.openJobs()}
  case "d":if m.page==1&&m.detailLogs {return m.openDetail(false)}
  case "home","g":if m.page==1||m.page==3 {m.scroll=0}
  case "end","G":if m.page==1||m.page==3 {m.scroll=len(strings.Split(m.detail,"\n"))}
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
 if m.busy||m.refreshing {frames:=[]string{"◐","◓","◑","◒"};state:="Loading";if m.refreshing {state="Syncing"};body.WriteString(purple.Render(frames[m.frame%len(frames)]+" "+state+" GitHub data…")+"\n")}
 if (m.page==0&&m.fromCache)||(m.page==1&&m.detailCache) {body.WriteString(muted.Render("⚡ Instant cache · refreshing in background")+"\n")}
 if m.message!="" {body.WriteString("⚠ "+m.message+"\n")}
 if !m.updated.IsZero()&&!m.refreshing&&!m.busy {body.WriteString(muted.Render("✓ Synced "+m.updated.Format("15:04:05"))+"\n")}
 if m.page==0 {
  body.WriteString(purple.Render("WORKFLOW RUNS")+"\n")
  if len(m.runs)==0&&!m.busy {body.WriteString("No runs found.\n")}
  if m.searchQuery!="" {body.WriteString(muted.Render("Search: "+m.searchQuery)+"\n")}
  max:=m.height-11;if max<3 {max=3}
  start:=0;if m.selected>=max {start=m.selected-max+1}
  shown:=0
  for i:=start;i<len(m.runs)&&shown<max;i++ {
   if m.searchQuery!=""&&!strings.Contains(strings.ToLower(m.runs[i].Name+" "+m.runs[i].Branch+" "+fmt.Sprint(m.runs[i].ID)),strings.ToLower(m.searchQuery)) {continue}
   shown++
   r:=m.runs[i];cursor:="  ";if i==m.selected {cursor="❯ "}
   state:=r.Conclusion;if state=="" {state=r.Status}
   label:=fmt.Sprintf("%s%s  %s  ·  %s",cursor,state,r.Name,r.Branch)
   if i==m.selected {body.WriteString(purple.Render(label))} else if state=="success" {body.WriteString(green.Render(label))} else {body.WriteString(label)}
   body.WriteString("\n")
  }
 } else if m.page==2 {
  body.WriteString(purple.Render("JOBS & STEPS")+"\n")
  max:=m.height-12;if max<3 {max=3};start:=0;if m.jobSelected>=max {start=m.jobSelected-max+1}
  for i:=start;i<len(m.jobs)&&i<start+max;i++ {j:=m.jobs[i];if m.searchQuery!=""&&!strings.Contains(strings.ToLower(j.Name),strings.ToLower(m.searchQuery)) {continue};prefix:="  ";if i==m.jobSelected {prefix="❯ "};body.WriteString(fmt.Sprintf("%s%s  %s  (%d steps)\n",prefix,j.Conclusion,j.Name,len(j.Steps)))}
  if len(m.jobs)==0&&!m.busy {body.WriteString("No jobs available.\n")}
  if len(m.jobs)>0 {
   if m.searchQuery!="" {body.WriteString(muted.Render("Search: "+m.searchQuery)+"\n")}
   body.WriteString(muted.Render("Tab switches focus between jobs and steps")+"\n")
   steps:=m.jobs[m.jobSelected].Steps
   room:=m.height-14-max;if room<2 {room=2};startStep:=0;if m.stepSelected>=room {startStep=m.stepSelected-room+1}
   for i:=startStep;i<len(steps)&&i<startStep+room;i++ {s:=steps[i];prefix:="  ";if m.stepFocus&&i==m.stepSelected {prefix="❯ "};line:=fmt.Sprintf("%s%d · %s · %s",prefix,s.Number,s.Name,s.Conclusion);if m.stepFocus&&i==m.stepSelected {body.WriteString(purple.Render(line)+"\n")} else {body.WriteString(muted.Render(line)+"\n")}}
  }
 } else {
  body.WriteString(purple.Render("RUN DETAILS / COMMAND OUTPUT")+"\n")
  if m.page==3 {if m.logStep!="" {body.WriteString(purple.Render("STEP: "+m.logStep)+"\n")};body.WriteString(muted.Render(fmt.Sprintf("❯ gh run view %d --job %d --log",m.detailID,m.logJobID))+"\n");if m.logFilter!="" {body.WriteString(purple.Render("FILTER: "+m.logFilter)+"\n")} else {body.WriteString("\n")}} else if len(m.runs)>0 {body.WriteString(muted.Render(fmt.Sprintf("❯ gh run view %d -R %s",m.runs[m.selected].ID,m.repo))+"\n\n")}
  lines:=strings.Split(m.detail,"\n")
  if m.page==3&&(m.logFilter!=""||m.logStep!="") {filtered:=make([]string,0,len(lines)/4);for _,line:=range lines {if m.logFilter!=""&&!strings.Contains(strings.ToLower(line),strings.ToLower(m.logFilter)) {continue};if m.logStep!=""&&!strings.Contains(strings.ToLower(line),strings.ToLower(m.logStep)) {continue};filtered=append(filtered,line)};lines=filtered}
  if m.searchQuery!="" {filtered:=make([]string,0,len(lines)/4);for _,line:=range lines {if strings.Contains(strings.ToLower(line),strings.ToLower(m.searchQuery)) {filtered=append(filtered,line)}};lines=filtered}
  max:=m.height-13;if max<3 {max=3}
  maxScroll:=len(lines)-max;if maxScroll<0 {maxScroll=0}
  if m.scroll>maxScroll {m.scroll=maxScroll};if m.scroll<0 {m.scroll=0}
  lines=lines[m.scroll:]
  if len(lines)>max {lines=lines[:max]}
  for _,line:=range lines {body.WriteString(line+"\n")}
 }
 if m.searchMode {body.WriteString("\n"+purple.Render("⌕ Search: "+m.searchQuery+"▏")+"\n")}
 body.WriteString("\n"+muted.Render("← Esc Back  ↑↓ Scroll  Enter Open  Tab Steps  F Errors  L Logs  D Details  R Refresh  Q Quit"))
 v:=tea.NewView(border.Width(w).Render(body.String()))
 v.AltScreen=true
 return v
}
func main() {
 repo:="rodkisten/codespaces";if len(os.Args)>1 {repo=os.Args[1]}
 p:=tea.NewProgram(initial(repo))
 if _,err:=p.Run();err!=nil {fmt.Fprintln(os.Stderr,err);os.Exit(1)}
}
