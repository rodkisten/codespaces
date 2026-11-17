package rodlog

import (
	"fmt"
	"regexp"
	"strconv"
)

// DockerColors defines SGR sequences (without ESC[ and m) used by Docker cards.
// Empty values inherit defaults, preserving the existing appearance.
type DockerColors struct {
	BadgeBackground string
	BadgeText       string
	Done            string
	Cached          string
	Error           string
	Separator       string
}

func DefaultDockerColors() DockerColors {
	return DockerColors{
		BadgeBackground: "48;5;238",
		BadgeText:       "97;1",
		Done:            "32",
		Cached:          "2",
		Error:           "31",
		Separator:       "2",
	}
}

func mergeDockerColors(base, override DockerColors) DockerColors {
	if override.BadgeBackground != "" {
		base.BadgeBackground = override.BadgeBackground
	}
	if override.BadgeText != "" {
		base.BadgeText = override.BadgeText
	}
	if override.Done != "" {
		base.Done = override.Done
	}
	if override.Cached != "" {
		base.Cached = override.Cached
	}
	if override.Error != "" {
		base.Error = override.Error
	}
	if override.Separator != "" {
		base.Separator = override.Separator
	}
	return base
}

var hexColorPattern = regexp.MustCompile(`^#[0-9a-fA-F]{6}$`)
var sgrPattern = regexp.MustCompile(`^[0-9]+(?:;[0-9]+)*$`)

// ColorSGR converts a #RRGGBB color to terminal true-color SGR parameters.
// Existing SGR parameters are accepted for backwards compatibility.
// Invalid inputs return an error rather than emitting untrusted escape codes.
func ColorSGR(value string, background bool) (string, error) {
	if hexColorPattern.MatchString(value) {
		red, _ := strconv.ParseUint(value[1:3], 16, 8)
		green, _ := strconv.ParseUint(value[3:5], 16, 8)
		blue, _ := strconv.ParseUint(value[5:7], 16, 8)
		prefix := 38
		if background {
			prefix = 48
		}
		return fmt.Sprintf("%d;2;%d;%d;%d", prefix, red, green, blue), nil
	}
	if !sgrPattern.MatchString(value) {
		return "", fmt.Errorf("invalid color %q: expected #RRGGBB or ANSI SGR parameters", value)
	}
	return value, nil
}

// ParseDockerColors validates and normalizes all configured Docker colors.
// Empty fields inherit their defaults; malformed values are rejected.
func ParseDockerColors(input DockerColors) (DockerColors, error) {
	base := mergeDockerColors(DefaultDockerColors(), input)
	fields := []struct {
		name       string
		value      *string
		background bool
	}{
		{"badge_background", &base.BadgeBackground, true},
		{"badge_text", &base.BadgeText, false},
		{"done", &base.Done, false},
		{"cached", &base.Cached, false},
		{"error", &base.Error, false},
		{"separator", &base.Separator, false},
	}
	for _, field := range fields {
		converted, err := ColorSGR(*field.value, field.background)
		if err != nil {
			return DockerColors{}, fmt.Errorf("docker.%s: %w", field.name, err)
		}
		*field.value = converted
	}
	return base, nil
}
