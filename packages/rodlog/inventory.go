package rodlog

import (
	"path/filepath"
	"strings"
)

type ToolSpec struct {
	Tool        Tool     `json:"tool"`
	Commands    []string `json:"commands"`
	Description string   `json:"description"`
}

func ToolInventory() []ToolSpec {
	return []ToolSpec{
		{Tool: NPM, Commands: []string{"npm", "npm.cmd"}, Description: "npm package manager"},
		{Tool: TypeScript, Commands: []string{"tsc"}, Description: "TypeScript compiler"},
		{Tool: GCloud, Commands: []string{"gcloud"}, Description: "Google Cloud CLI"},
		{Tool: Wrangler, Commands: []string{"wrangler"}, Description: "Cloudflare Wrangler"},
		{Tool: Docker, Commands: []string{"docker"}, Description: "Docker CLI"},
	}
}

// DetectCommand selects a parser by executable identity, not log contents.
func DetectCommand(argv []string) Tool {
	if len(argv) == 0 {
		return Generic
	}
	name := strings.ToLower(filepath.Base(argv[0]))
	if name == "npx" || name == "npx.cmd" || name == "bunx" {
		for _, arg := range argv[1:] {
			if strings.HasPrefix(arg, "-") {
				continue
			}
			return DetectCommand([]string{arg})
		}
		return Generic
	}
	for _, spec := range ToolInventory() {
		for _, command := range spec.Commands {
			if name == command {
				return spec.Tool
			}
		}
	}
	return Generic
}
