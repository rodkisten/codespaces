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
		{Tool: Vitest, Commands: []string{"vitest"}, Description: "Vitest test runner"},
		{Tool: NodeTest, Commands: []string{"node"}, Description: "Node.js built-in test runner"},
	}
}

// DetectCommand selects a parser by executable identity, not log contents.
func DetectCommand(argv []string) Tool {
	if len(argv) == 0 {
		return Generic
	}
	name := strings.ToLower(filepath.Base(argv[0]))
	// Node has many subcommands; only select the test adapter for --test.
	if (name == "node" || name == "node.exe") && len(argv) > 1 {
		for _, arg := range argv[1:] {
			if arg == "--test" || strings.HasPrefix(arg, "--test=") {
				return NodeTest
			}
		}
		return Generic
	}
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
		if spec.Tool == NodeTest {
			continue
		}
		for _, command := range spec.Commands {
			if name == command {
				return spec.Tool
			}
		}
	}
	return Generic
}
