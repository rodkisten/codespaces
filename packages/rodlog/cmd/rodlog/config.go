package main

import (
	"fmt"
	"os"
	"path/filepath"
	"strings"

	"github.com/pelletier/go-toml/v2"
	"github.com/rodkisten/codespaces/packages/rodlog"
)

type fileConfig struct {
	Mode   string `toml:"mode"`
	Tool   string `toml:"tool"`
	Color  string `toml:"color"`
	Output string `toml:"output"`
	Semantic rodlog.SemanticColors `toml:"semantic"`
	Icons rodlog.DiagnosticIcons `toml:"icons"`
	Syntax rodlog.SyntaxTheme `toml:"syntax"`
	Docker struct {
		Separator string `toml:"separator"`
		Colors rodlog.DockerColors `toml:"colors"`
	} `toml:"docker"`
}

func fallback(value, defaultValue string) string {
	if value != "" {
		return value
	}
	return defaultValue
}

// findConfigPath resolves --config before regular flag parsing so it works
// independently of the position of other rodlog flags.
func findConfigPath(args []string) (string, error) {
	for i, arg := range args {
		if arg == "--config" {
			if i+1 >= len(args) || args[i+1] == "" || strings.HasPrefix(args[i+1], "--") {
				return "", fmt.Errorf("--config requires a path")
			}
			return args[i+1], nil
		}
		if strings.HasPrefix(arg, "--config=") {
			path := strings.TrimPrefix(arg, "--config=")
			if path == "" {
				return "", fmt.Errorf("--config requires a path")
			}
			return path, nil
		}
	}
	if value := os.Getenv("RODLOG_CONFIG"); value != "" {
		return value, nil
	}
	dir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(dir, "rodlog", "config.toml"), nil
}

func loadConfig(path string) (fileConfig, error) {
	var config fileConfig
	data, err := os.ReadFile(path)
	if os.IsNotExist(err) {
		// The default path is optional. Explicit paths should fail loudly.
		if os.Getenv("RODLOG_CONFIG") == "" {
			dir, dirErr := os.UserConfigDir()
			if dirErr == nil && path == filepath.Join(dir, "rodlog", "config.toml") {
				return config, nil
			}
		}
		return config, fmt.Errorf("config %s: %w", path, err)
	}
	if err != nil {
		return config, fmt.Errorf("config %s: %w", path, err)
	}
	decoder := toml.NewDecoder(strings.NewReader(string(data)))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&config); err != nil {
		return config, fmt.Errorf("config %s: %w", path, err)
	}
	return config, nil
}
