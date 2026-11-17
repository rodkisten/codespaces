package rodlog

import (
 "os"
 "strconv"
 "strings"
 "github.com/charmbracelet/lipgloss"
)

// cardWidth caps physical output, rather than relying on the CI viewer to wrap it.
func cardWidth(opts Options) int {
 // GitHub Actions mobile shows fewer columns than the CI runner reports.
 // Keep the default safe for a narrow phone; allow explicit opt-in overrides.
 width:=36
 if n,err:=strconv.Atoi(os.Getenv("RODLOG_CARD_WIDTH"));err==nil && n>=24 && n<=160 {width=n}
 if n,err:=strconv.Atoi(os.Getenv("COLUMNS"));err==nil && n>=24 && n<width {width=n}
 if opts.Preset!=nil && opts.Preset.Diagnostics.Card.MaxWidth>=24 && opts.Preset.Diagnostics.Card.MaxWidth<width {width=opts.Preset.Diagnostics.Card.MaxWidth}
 return width
}

// wrapCardText wraps before adding ANSI styling, preserving semantic highlighting
// and never breaking an escape sequence or a Unicode display cell.
func wrapCardText(input string, width int) []string {
 if width<1 {return []string{input}}
 var result []string
 for _,paragraph:=range strings.Split(input,"\n") {
  if strings.TrimSpace(paragraph)=="" {result=append(result,"");continue}
  line:=""
  for _,word:=range strings.Fields(paragraph) {
   if line!="" && lipgloss.Width(line)+1+lipgloss.Width(word)>width {result=append(result,line);line=""}
   for lipgloss.Width(word)>width {
    if line!="" {result=append(result,line);line=""}
    r:=[]rune(word)
    count:=0
    for count<len(r) && lipgloss.Width(string(r[:count+1]))<=width {count++}
    if count==0 {count=1}
    result=append(result,string(r[:count]))
    word=string(r[count:])
   }
   if word!="" {
    if line!="" {line+=" "}
    line+=word
   }
  }
  if line!="" {result=append(result,line)}
 }
 return result
}

func uniqueCardDetails(message string, details []string) []string {
 seen:=map[string]bool{}
 if s:=cleanCardText(message);s!="" {seen[strings.ToLower(s)]=true}
 var result []string
 for _,detail:=range details {
  detail=cleanCardText(detail)
  key:=strings.ToLower(detail)
  if detail=="" || seen[key] {continue}
  seen[key]=true
  result=append(result,detail)
 }
 return result
}

// cardLines wraps every field, including API names and error codes, before
// Lip Gloss adds padding and borders. This avoids viewer-side reflow.
func cardLines(value string, width int) []string {
 return wrapCardText(value,width-4)
}
