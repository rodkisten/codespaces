package main

import (
 "bufio"
 "fmt"
 "os"
 "os/exec"
 "path/filepath"
 "strconv"
 "strings"

 "github.com/spf13/cobra"
)

func scriptPath() string {
 if p:=os.Getenv("XI_BASH_SCRIPT");p!="" {return p}
 home,_:=os.UserHomeDir()
 candidates:=[]string{filepath.Join(home,".local","share","xi","xi.sh"),filepath.Join(home,"code","codespaces","scripts","xi.sh")}
 for _,p:=range candidates {if _,err:=os.Stat(p);err==nil{return p}}
 return ""
}
func runLegacy(args []string) error {
 script:=scriptPath()
 if script=="" {return fmt.Errorf("xi Bash backend not installed; run xi self-update or set XI_BASH_SCRIPT")}
 cmd:=exec.Command("bash",append([]string{script},args...)...)
 cmd.Stdin=os.Stdin;cmd.Stdout=os.Stdout;cmd.Stderr=os.Stderr
 return cmd.Run()
}
func pickSuggestion(options []string) string {
 if len(options)==0{return ""}
 if len(options)==1 {fmt.Fprintf(os.Stderr,"Did you mean %q? [y/N] ",options[0]);var answer string;fmt.Fscanln(os.Stdin,&answer);if strings.EqualFold(answer,"y")||strings.EqualFold(answer,"yes"){return options[0]};return ""}
 fmt.Fprintln(os.Stderr,"Did you mean one of these?")
 for i,name:=range options {fmt.Fprintf(os.Stderr,"  %d) %s\n",i+1,name)}
 fmt.Fprint(os.Stderr,"Choose a number (Enter cancels): ")
 line,_:=bufio.NewReader(os.Stdin).ReadString('\n')
 n,err:=strconv.Atoi(strings.TrimSpace(line))
 if err==nil&&n>0&&n<=len(options){return options[n-1]}
 return ""
}
func resolve(root *cobra.Command,args []string) []string {
 if len(args)==0||strings.HasPrefix(args[0],"-"){return args}
 cmd,_,err:=root.Find(args)
 if err==nil&&cmd!=nil&&cmd!=root{return args}
 if !isTerminal(){return args}
 suggestions:=root.SuggestionsFor(args[0])
 if selected:=pickSuggestion(suggestions);selected!="" {return append([]string{selected},args[1:]...)}
 return args
}
func isTerminal() bool {
 fi,err:=os.Stdin.Stat();return err==nil&&(fi.Mode()&os.ModeCharDevice)!=0
}
func rootCommand() *cobra.Command {
 root:=&cobra.Command{Use:"xi",Short:"Fast installer and GitHub Actions terminal",SilenceUsage:true,SilenceErrors:true,SuggestionsMinimumDistance:3}
 commands:=[]struct{name,description string}{
  {"menu","Open interactive menu"},{"doctor","Inspect PATH and installation"},
  {"self-update","Update xi"},{"zle-init","Generate Zsh ZLE integration"},
  {"gh","GitHub Actions commands"},{"tui","Bubble Tea interface"},
  {"github","Install GitHub repository"},{"releases","Install release"},
  {"zinit","Install Zsh plugin"},{"zshrc","Manage Zsh configuration"},
  {"config","Manage xi settings"},{"inventory","List installed tools"},
  {"update","Update installed tools"},{"git","Git shortcuts"},
 }
 for _,item:=range commands {
  name:=item.name
  child:=&cobra.Command{Use:name,Short:item.description,DisableFlagParsing:true,RunE:func(_ *cobra.Command,args []string)error{return runLegacy(append([]string{name},args...))}}
  root.AddCommand(child)
 }
 root.RunE=func(_ *cobra.Command,args []string)error{return runLegacy(append([]string{"menu"},args...))}
 return root
}
func main(){
 root:=rootCommand()
 args:=os.Args[1:]
 // Keep Cobra's native completion and help behavior; correct only actual command typos.
 if len(args)>0&&args[0]!="completion"&&args[0]!="__complete"&&args[0]!="__completeNoDesc" {
  args=resolve(root,args)
 }
 root.SetArgs(args)
 if err:=root.Execute();err!=nil {fmt.Fprintln(os.Stderr,"xi:",err);os.Exit(1)}
}
