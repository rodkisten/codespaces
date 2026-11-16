package rodlog

import "strings"

// JSONCommand adds --json only for known command/subcommand combinations.
// Never mutate unknown commands or commands already selecting an output format.
func JSONCommand(argv []string) ([]string, bool) {
	if len(argv) < 2 {
		return argv, false
	}
	for _, arg := range argv[1:] {
		if arg == "--json" || strings.HasPrefix(arg, "--json=") || arg == "--format" || strings.HasPrefix(arg, "--format=") || arg == "--help" || arg == "-h" {
			return argv, false
		}
	}
	// Explicit allowlist: both commands support --json.
	if argv[0] == "npm" && argv[1] == "outdated" {
		return append(append([]string(nil), argv...), "--json"), true
	}
	if argv[0] == "npm" && argv[1] == "audit" {
		return append(append([]string(nil), argv...), "--json"), true
	}
	return argv, false
}
