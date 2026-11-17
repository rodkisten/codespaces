package rodlog

// cardSemanticHighlight respects --color=never before any ANSI reaches Lip Gloss.
func cardSemanticHighlight(text string, tool Tool, opts Options) string {
 if !opts.Color || opts.Preset==nil {return text}
 return HighlightWithPreset(text,tool,*opts.Preset,opts.SemanticColors)
}
