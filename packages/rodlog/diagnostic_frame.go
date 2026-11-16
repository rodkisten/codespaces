package rodlog

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"unicode"
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
			fmt.Fprintf(&b, "         | %s\x1b[31m^\x1b[0m\n", strings.Repeat(" ", visualColumn(lines[i-1], d.Column)))
		}
	}
	return b.String()
}

// visualColumn converts a one-based rune column to terminal cells.
// Tabs use 8-column stops; combining marks occupy no extra cells.
func visualColumn(line string, column int) int {
	width := 0
	position := 1
	for _, r := range line {
		if position >= column {
			break
		}
		if r == '\t' {
			width += 8 - width%8
		} else if unicode.Is(unicode.Mn, r) || unicode.Is(unicode.Me, r) {
			// Combining mark.
		} else if r >= 0x1100 && (r <= 0x115f || r >= 0x2e80 && r <= 0xa4cf || r >= 0xac00 && r <= 0xd7a3 || r >= 0xf900 && r <= 0xfaff || r >= 0xfe10 && r <= 0xfe6f || r >= 0xff01 && r <= 0xff60 || r >= 0xffe0 && r <= 0xffe6) {
			width += 2
		} else {
			width++
		}
		position++
	}
	return width
}
