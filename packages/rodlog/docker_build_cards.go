package rodlog

import (
	"fmt"
	"regexp"
	"strings"
)

// BuildKit IDs are concurrent. Display steps are numbered when a header first appears.
type dockerBuildSteps struct {
	numbers   map[string]int
	next      int
	separator string
	colors    DockerColors
}

func newDockerBuildSteps() *dockerBuildSteps {
	return &dockerBuildSteps{numbers: make(map[string]int), separator: strings.Repeat("─", 36), colors: DefaultDockerColors()}
}

var buildKitHeader = regexp.MustCompile(`^#(\d+)\s+\[([^]]+)\]\s+(.+?)(?:\r?\n)?$`)
var buildKitLegacyHeader = regexp.MustCompile(`^Step\s+(\d+)/(\d+)\s*:\s*(.+?)(?:\r?\n)?$`)
var buildKitStatus = regexp.MustCompile(`^#(\d+)\s+(DONE|CACHED|ERROR|FINISHED)([^\r\n]*)(?:\r?\n)?$`)
var buildKitInstruction = regexp.MustCompile(`(?i)^(?:RUN|COPY|ADD|FROM|WORKDIR|ENV|ARG|CMD|ENTRYPOINT|USER|EXPOSE|LABEL|HEALTHCHECK|SHELL|VOLUME|ONBUILD|STOPSIGNAL)\b`)

// Only command headers are transformed; progress, diagnostics and arbitrary logs survive.
func (s *dockerBuildSteps) format(text string) (string, bool) {
	if m := buildKitStatus.FindStringSubmatch(text); m != nil {
		if number, exists := s.numbers[m[1]]; exists {
			color := s.colors.Done
			switch m[2] {
			case "CACHED":
				color = s.colors.Cached
			case "ERROR":
				color = s.colors.Error
			}
			return fmt.Sprintf("\x1b[2mSTEP %d\x1b[0m  \x1b[%sm%s\x1b[0m%s\n", number, color, m[2], m[3]), true
		}
	}
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
	badge := fmt.Sprintf("\x1b[%sm\x1b[%sm STEP %d \x1b[0m", s.colors.BadgeBackground, s.colors.BadgeText, s.next)
	colored := command
	if highlighted, err := SyntaxHighlight(command, "dockerfile"); err == nil {
		colored = strings.TrimRight(highlighted, "\r\n")
	}
	// The divider is configurable through engine options.
	return fmt.Sprintf("%s  %s\n\x1b[%sm%s\x1b[0m\n", badge, colored, s.colors.Separator, s.separator), true
}
