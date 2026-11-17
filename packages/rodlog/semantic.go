package rodlog

import (
	"regexp"
	"strconv"
	"strings"
)

// Diagnostic is the renderer-independent representation of a tool message.
// Original output remains in Event.Text; parsers must never rewrite source bytes.
type Diagnostic struct {
	Tool    Tool   `json:"tool"`
	Level   Level  `json:"level"`
	Code    string `json:"code,omitempty"`
	File    string `json:"file,omitempty"`
	Line    int    `json:"line,omitempty"`
	Column  int    `json:"column,omitempty"`
	Message string `json:"message"`
}

var (
	tsLocation      = regexp.MustCompile(`^(.+?)\((\d+),(\d+)\):\s*(error|warning)\s+(TS\d+):\s*(.+)$`)
	tsColon         = regexp.MustCompile(`^(.+?):(\d+):(\d+)\s*[-:]\s*(error|warning)\s+(TS\d+):\s*(.+)$`)
	tsPlain         = regexp.MustCompile(`^(error|warning)\s+(TS\d+):\s*(.+)$`)
	npmPrefix       = regexp.MustCompile(`(?i)^npm\s+(ERR!|error|WARN|warn|notice)\s*(.*)$`)
	gcloudPrefix    = regexp.MustCompile(`^(ERROR|WARNING):\s*(?:\(gcloud(?:\.[^)]+)?\)\s*)?(.+)$`)
	dockerPrefix    = regexp.MustCompile(`(?i)^(?:ERROR:\s*)?(?:failed to solve|failed to compute cache key|dockerfile parse error):\s*(.+)$`)
	dockerLocation  = regexp.MustCompile(`(?i)^Dockerfile:(\d+)(?::(\d+))?\b`)
	wranglerPrefix  = regexp.MustCompile(`^(?:✘\s*)?\[(ERROR|WARNING)\]\s*(.+)$`)
	runnerAssertion  = regexp.MustCompile(`(?i)^(?:AssertionError:\s*)?expected\s+(.+?)\s+to\s+(?:deeply\s+)?(?:equal|be)\s+(.+?)\.?$`)
	vitestFailure   = regexp.MustCompile(`^\s*(?:❯|✖|×)\s+(.+)$`)
	nodeTestFailure = regexp.MustCompile(`^\s*(?:✖\s+|not ok\s+\d+\s*-\s*)(.+)$`)
	wranglerError   = regexp.MustCompile(`(?i)^(?:✘\s*)?(?:error|warning):\s*(.+)$`)
)

// ParseDiagnostic extracts stable fields from tool-specific error formats.
// The adapter never executes or modifies the original command output: Event.Text
// remains authoritative, while this optional record powers cards and annotations.
// Unknown lines return nil so ordinary logs keep their original presentation.
func ParseDiagnostic(tool Tool, input string) *Diagnostic {
	line := strings.TrimSpace(ansi.ReplaceAllString(input, ""))
	if line == "" {
		return nil
	}
	if tool == Auto || tool == Generic {
		tool = Detect(line)
	}
	d := &Diagnostic{Tool: tool, Level: Error}
	switch tool {
	case TypeScript:
		for _, re := range []*regexp.Regexp{tsLocation, tsColon} {
			if m := re.FindStringSubmatch(line); m != nil {
				d.File = m[1]
				d.Line, _ = strconv.Atoi(m[2])
				d.Column, _ = strconv.Atoi(m[3])
				if m[4] == "warning" {
					d.Level = Warning
				}
				d.Code, d.Message = m[5], m[6]
				return d
			}
		}
		if m := tsPlain.FindStringSubmatch(line); m != nil {
			if m[1] == "warning" {
				d.Level = Warning
			}
			d.Code, d.Message = m[2], m[3]
			return d
		}
	case NPM:
		if m := npmPrefix.FindStringSubmatch(line); m != nil {
			d.Message = strings.TrimSpace(m[2])
			switch strings.ToLower(m[1]) {
			case "warn":
				d.Level = Warning
			case "notice":
				d.Level = Info
			}
			if d.Message != "" {
				return d
			}
		}
	case GCloud:
		if m := gcloudPrefix.FindStringSubmatch(line); m != nil {
			if m[1] == "WARNING" {
				d.Level = Warning
			}
			d.Message = m[2]
			return d
		}
	case Docker:
		if m := dockerPrefix.FindStringSubmatch(line); m != nil {
			d.Message = m[1]
			return d
		}
		if m := dockerLocation.FindStringSubmatch(line); m != nil {
			d.File = "Dockerfile"
			d.Line, _ = strconv.Atoi(m[1])
			if m[2] != "" {
				d.Column, _ = strconv.Atoi(m[2])
			}
			d.Message = line
			return d
		}
	case Vitest, NodeTest:
		// Assertion messages are handled before runner-specific status markers.
		// Capture both values without consuming multiline stack traces.
		if m := runnerAssertion.FindStringSubmatch(line); m != nil {
			d.Message = line
			return d
		}
		if tool == Vitest {
			if m := vitestFailure.FindStringSubmatch(line); m != nil {
				d.Message = m[1]
				return d
			}
		} else if m := nodeTestFailure.FindStringSubmatch(line); m != nil {
			d.Message = m[1]
			return d
		}
	case Wrangler:
		if m := wranglerPrefix.FindStringSubmatch(line); m != nil {
			if m[1] == "WARNING" {
				d.Level = Warning
			}
			d.Message = m[2]
			return d
		}
		if m := wranglerError.FindStringSubmatch(line); m != nil {
			if strings.Contains(strings.ToLower(line), "warning:") {
				d.Level = Warning
			}
			d.Message = m[1]
			return d
		}
	}
	return nil
}
