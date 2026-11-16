package rodlog

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// diagnosticFrame reads only local relative source paths, never absolute paths
// or parent traversal. It is terminal-only and never changes structured events.
func diagnosticFrame(d *Diagnostic) string {
	if filepath.IsAbs(d.File) || filepath.Clean(d.File) != d.File || d.File == ".." || strings.HasPrefix(d.File, ".."+string(filepath.Separator)) {
		return ""
	}
	info, err := os.Stat(d.File)
	if err != nil || info.IsDir() || info.Size() > 1024*1024 {
		return ""
	}
	content, err := os.ReadFile(d.File)
	if err != nil {
		return ""
	}
	lines := strings.Split(string(content), "\n")
	if d.Line < 1 || d.Line > len(lines) {
		return ""
	}
	first := d.Line - 2
	if first < 1 {
		first = 1
	}
	last := d.Line + 2
	if last > len(lines) {
		last = len(lines)
	}
	var b strings.Builder
	for i := first; i <= last; i++ {
		marker := " "
		if i == d.Line {
			marker = ">"
		}
		fmt.Fprintf(&b, "  %s %4d | %s\n", marker, i, lines[i-1])
		if i == d.Line && d.Column > 0 && d.Column < 512 {
			fmt.Fprintf(&b, "         | %s\x1b[31m^\x1b[0m\n", strings.Repeat(" ", d.Column-1))
		}
	}
	return b.String()
}
