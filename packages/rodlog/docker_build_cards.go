package rodlog

import (
	"fmt"
	"regexp"
	"strings"
)

// BuildKit IDs are concurrent. Display steps are numbered when a header first appears.
type dockerBuildSteps struct {
	numbers map[string]int
	next    int
}

func newDockerBuildSteps() *dockerBuildSteps {
	return &dockerBuildSteps{numbers: make(map[string]int)}
}

var buildKitHeader = regexp.MustCompile(`^#(\d+)\s+\[([^]]+)\]\s+(.+?)(?:\r?\n)?$`)
var buildKitLegacyHeader = regexp.MustCompile(`^Step\s+(\d+)/(\d+)\s*:\s*(.+?)(?:\r?\n)?$`)
var buildKitInstruction = regexp.MustCompile(`(?i)^(?:RUN|COPY|ADD|FROM|WORKDIR|ENV|ARG|CMD|ENTRYPOINT|USER|EXPOSE|LABEL|HEALTHCHECK|SHELL|VOLUME|ONBUILD|STOPSIGNAL)\b`)

// Only command headers are transformed; progress, diagnostics and arbitrary logs survive.
func (s *dockerBuildSteps) format(text string) (string, bool) {
	var key, command string
	if m := buildKitHeader.FindStringSubmatch(text); m != nil && buildKitInstruction.MatchString(m[3]) {
		key, command = m[1], m[3]
	} else if m := buildKitLegacyHeader.FindStringSubmatch(text); m != nil && buildKitInstruction.MatchString(m[3]) {
		key, command = "legacy-"+m[1], m[3]
	} else {
		return "", false
	}
	if _, exists := s.numbers[key]; exists {
		// Repeated headers may carry new information in the command text.
		// Preserve them rather than silently dropping output.
		return "", false
	}
	s.next++
	s.numbers[key] = s.next
	badge := fmt.Sprintf("\x1b[48;5;238m\x1b[97;1m STEP %d \x1b[0m", s.next)
	colored := command
	if highlighted, err := SyntaxHighlight(command, "dockerfile"); err == nil {
		colored = strings.TrimRight(highlighted, "\r\n")
	}
	// The separator is intentionally fixed until TOML configuration lands.
	return fmt.Sprintf("%s  %s\n\x1b[2m%s\x1b[0m\n", badge, colored, strings.Repeat("─", 36)), true
}
