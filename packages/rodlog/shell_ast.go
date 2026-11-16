package rodlog

import (
	"fmt"
	"strings"

	"mvdan.cc/sh/v3/syntax"
)

// ShellCommand describes a command invocation extracted from a real shell AST.
type ShellCommand struct {
	Name   string   `json:"name"`
	Args   []string `json:"args,omitempty"`
	Line   uint     `json:"line"`
	Column uint     `json:"column"`
	Tool   Tool     `json:"tool"`
}

// ShellAnalysis contains syntax-aware command invocations without executing them.
type ShellAnalysis struct {
	Commands []ShellCommand `json:"commands"`
}

// AnalyzeShell parses POSIX shell or Bash using mvdan's syntax AST.
// Dynamic expansions are intentionally not resolved or executed.
func AnalyzeShell(source string, dialect string) (ShellAnalysis, error) {
	var variant syntax.LangVariant
	switch strings.ToLower(dialect) {
	case "", "bash":
		variant = syntax.LangBash
	case "sh", "posix":
		variant = syntax.LangPOSIX
	case "mksh":
		variant = syntax.LangMirBSDKorn
	case "zsh":
		return ShellAnalysis{}, fmt.Errorf("zsh syntax is not supported by the shell AST parser")
	default:
		return ShellAnalysis{}, fmt.Errorf("unsupported shell dialect %q", dialect)
	}
	parser := syntax.NewParser(syntax.Variant(variant), syntax.KeepComments(true))
	file, err := parser.Parse(strings.NewReader(source), "script")
	if err != nil {
		return ShellAnalysis{}, err
	}
	result := ShellAnalysis{Commands: []ShellCommand{}}
	syntax.Walk(file, func(node syntax.Node) bool {
		call, ok := node.(*syntax.CallExpr)
		if !ok || len(call.Args) == 0 {
			return true
		}
		name, ok := literalShellWord(call.Args[0])
		if !ok {
			return true
		}
		entry := ShellCommand{Name: name, Line: call.Pos().Line(), Column: call.Pos().Col(), Tool: DetectCommand([]string{name})}
		for _, arg := range call.Args[1:] {
			if literal, ok := literalShellWord(arg); ok {
				entry.Args = append(entry.Args, literal)
			}
		}
		result.Commands = append(result.Commands, entry)
		return true
	})
	return result, nil
}

func literalShellWord(word *syntax.Word) (string, bool) {
	if word == nil || len(word.Parts) != 1 {
		return "", false
	}
	switch part := word.Parts[0].(type) {
	case *syntax.Lit:
		return part.Value, true
	case *syntax.SglQuoted:
		return part.Value, true
	}
	return "", false
}
