package rodlog

import (
	"regexp"
	"sort"
	"strings"
)

// Highlight matches semantic tokens in the original line, then adds ANSI escapes.
// Rules carry priorities so an error code or location wins over a generic CLI
// name when spans overlap. The original characters remain in their input order.
type highlightRule struct {
	expression *regexp.Regexp
	color      string
	priority   int
}
type highlightSpan struct {
	start, end int
	color      string
	priority   int
}

var diagnosticRules = []highlightRule{
	{regexp.MustCompile(`\bTS[0-9]{4,5}\b`), "35", 10},
	{regexp.MustCompile(`(?:[[:alnum:]_./-]+)\.(?:tsx?|jsx?|py|go|json|yaml|yml):[0-9]+(?::[0-9]+)?`), "36", 9},
	{regexp.MustCompile(`(?:[[:alnum:]_./-]+)\.(?:tsx?|jsx?|py|go)\([0-9]+,[0-9]+\)`), "4;36", 9},
	{regexp.MustCompile(`\b(?:ERROR|Error|error|FAILED|Failed|failed)\b|ERR!`), "31", 8},
	{regexp.MustCompile(`\b(?:WARN|WARNING|Warning|warning|deprecated)\b`), "33", 7},
	{regexp.MustCompile(`\b(?:SUCCESS|Success|success|DONE|Done|done)\b`), "32", 6},
	{regexp.MustCompile(`\b(?:npm|npx|gcloud|wrangler|docker|tsc)\b`), "2", 2},
}

// highlightLine first collects matches, resolves overlaps, and only then writes
// escape sequences. Matching before rendering prevents our own ANSI codes from
// being interpreted as user content. A bounded match count limits log overhead.
func highlightLine(s string) string {
	if s == "" {
		return s
	}
	spans := make([]highlightSpan, 0, 8)
	for _, rule := range diagnosticRules {
		for _, pair := range rule.expression.FindAllStringIndex(s, 64) {
			spans = append(spans, highlightSpan{pair[0], pair[1], rule.color, rule.priority})
		}
	}
	if len(spans) == 0 {
		return s
	}
	sort.SliceStable(spans, func(i, j int) bool {
		if spans[i].priority != spans[j].priority {
			return spans[i].priority > spans[j].priority
		}
		return spans[i].start < spans[j].start
	})
	occupied := make([]bool, len(s))
	accepted := make([]highlightSpan, 0, len(spans))
	for _, span := range spans {
		overlap := false
		for i := span.start; i < span.end; i++ {
			if occupied[i] {
				overlap = true
				break
			}
		}
		if overlap {
			continue
		}
		for i := span.start; i < span.end; i++ {
			occupied[i] = true
		}
		accepted = append(accepted, span)
	}
	sort.Slice(accepted, func(i, j int) bool { return accepted[i].start < accepted[j].start })
	var out strings.Builder
	out.Grow(len(s) + len(accepted)*16)
	last := 0
	for _, span := range accepted {
		out.WriteString(s[last:span.start])
		out.WriteString("\x1b[")
		out.WriteString(span.color)
		out.WriteByte('m')
		out.WriteString(s[span.start:span.end])
		out.WriteString("\x1b[0m")
		last = span.end
	}
	out.WriteString(s[last:])
	return out.String()
}
