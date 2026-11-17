package rodlog

import "strings"

// colorizeRenderedCard runs AFTER Lip Gloss has finished layout. Lip Gloss
// detects a non-TTY in GitHub Actions and may strip styles while rendering.
// Apply semantic ANSI codes only to the final text cells, preserving the
// Unicode border geometry and ensuring --color=always actually means always.
func colorizeRenderedCard(rendered string, tool Tool, opts Options) string {
 if !opts.Color {return rendered}
 lines:=strings.Split(rendered,"\n")
 for i,line:=range lines {
  if line=="" {continue}
  // Borders are single-cell glyphs. Never apply semantic rules to them.
  r:=[]rune(line)
  if len(r)<3 {continue}
  if r[0]=='╭' || r[0]=='╰' || r[0]=='┌' || r[0]=='└' {
   lines[i]="\x1b[2;90m"+line+"\x1b[0m"
   continue
  }
  if r[0]!='│' && r[0]!='┃' && r[0]!='║' && r[0]!='|' {continue}
  left,right:=string(r[0]),string(r[len(r)-1])
  if right!="│" && right!="┃" && right!="║" && right!="|" {continue}
  inner:=string(r[1:len(r)-1])
  plain:=strings.TrimSpace(inner)
  if plain!="" {
   switch {
   case strings.Contains(plain,"ERROR"):
    inner="\x1b[1;31m"+inner+"\x1b[0m"
   case strings.HasPrefix(plain,"API:"):
    inner="\x1b[36m"+inner+"\x1b[0m"
   case strings.HasPrefix(plain,"Code:"):
    inner="\x1b[33m"+inner+"\x1b[0m"
   case strings.HasPrefix(plain,"Possible fixes:") || strings.HasPrefix(plain,"›") || strings.HasPrefix(plain,"$ "):
    inner="\x1b[32m"+inner+"\x1b[0m"
   default:
    if opts.Preset!=nil {inner=HighlightWithPreset(inner,tool,*opts.Preset,opts.SemanticColors)}
    // Keep the principal message visually distinct even when no token matches.
    if !strings.Contains(inner,"\x1b[") {inner="\x1b[37m"+inner+"\x1b[0m"}
   }
  }
  lines[i]="\x1b[2;90m"+left+"\x1b[0m"+inner+"\x1b[2;90m"+right+"\x1b[0m"
 }
 return strings.Join(lines,"\n")
}
