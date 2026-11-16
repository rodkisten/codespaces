package rodlog

import "strings"

// diagnosticSuggestion offers conservative, actionable hints for known codes.
func diagnosticSuggestion(d *Diagnostic) string {
	switch d.Code {
	case "TS2307":
		return "Check the import path, installed dependencies, and tsconfig paths."
	case "TS2322":
		return "Compare the expected and actual types at the highlighted assignment."
	case "TS6133":
		return "Remove the unused declaration or use it intentionally."
	case "TS7006":
		return "Add an explicit parameter type or enable contextual typing."
	case "TS18048":
		return "Check for undefined before accessing this value."
	}
	message := strings.ToLower(d.Message)
	switch d.Tool {
	case GCloud:
		if strings.Contains(message, "permission denied") || strings.Contains(message, "permission_denied") {
			return "Check the active gcloud account, project, and IAM role."
		}
		if strings.Contains(message, "authentication scopes") {
			return "Check the credential scopes and active gcloud configuration."
		}
	case NPM:
		if strings.Contains(message, "missing script") {
			return "Run npm run to list scripts defined in package.json."
		}
	case Wrangler:
		if strings.Contains(message, "authentication") {
			return "Check wrangler login or CLOUDFLARE_API_TOKEN permissions."
		}
	case Docker:
		if strings.Contains(message, "failed to solve") {
			return "Inspect the failing Dockerfile step and preceding build output."
		}
	}
	return ""
}
