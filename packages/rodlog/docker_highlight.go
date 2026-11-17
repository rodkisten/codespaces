package rodlog

import (
	"regexp"
	"strings"
)

// Dockerfile instructions are lexed by Chroma rather than by a homegrown
// keyword-to-ANSI formatter. The anchor avoids mistaking arbitrary prose for
// a Dockerfile command in a noisy container log.
var dockerfileInstruction = regexp.MustCompile(`(?i)^(?:FROM|RUN|COPY|ADD|WORKDIR|ENV|ARG|EXPOSE|ENTRYPOINT|CMD|USER|LABEL|VOLUME|HEALTHCHECK|SHELL|STOPSIGNAL|ONBUILD)\\s+\S`)

var dockerEvents = []struct {
	pattern *regexp.Regexp
	color   string
}{
	{regexp.MustCompile(`(?i)\\b(?:healthy|health: healthy|started|running|created|pulled|ready|listening)\\b`), "32"},
	{regexp.MustCompile(`(?i)\\b(?:unhealthy|health: unhealthy|oomkilled|out of memory|permission denied|connection refused|exited \\(\\d+\\)|fatal)\\b`), "31"},
	{regexp.MustCompile(`(?i)\\b(?:restarting|stopping|waiting|retrying|health: starting)\\b`), "33"},
}

// highlightDocker colors a meaningful event token, not the entire line.
// It preserves container prefixes, timestamps, and original bytes around the
// token. Existing ANSI is handled by Render before this function is called.
func highlightDocker(text string) (string, bool) {
	for _, rule := range dockerEvents {
		if loc := rule.pattern.FindStringIndex(text); loc != nil {
			var b strings.Builder
			b.WriteString(text[:loc[0]])
			b.WriteString("\\x1b[")
			b.WriteString(rule.color)
			b.WriteString("m")
			b.WriteString(text[loc[0]:loc[1]])
			b.WriteString("\\x1b[0m")
			b.WriteString(text[loc[1]:])
			return b.String(), true
		}
	}
	return "", false
}
