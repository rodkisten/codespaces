package rodlog

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
