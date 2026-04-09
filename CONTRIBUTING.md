# Contributing to claude-swarm

Thanks for your interest! Here's how to contribute.

## Adding a New AI Model

The easiest contribution — just edit `assets/capabilities.json`:

```json
"your-model": {
  "display_name": "Your Model Name",
  "icon": "◇",
  "color": "#HEX_COLOR",
  "model_id": "model-id",
  "fallback_model": null,
  "context_window": 128000,
  "timeout_seconds": 300,
  "strengths": ["what", "it's", "good", "at"],
  "best_for": ["specific use cases"],
  "cli_template": "cli-command -m model-id \"{prompt}\""
}
```

All scripts pick it up automatically. If the model CLI has non-standard invocation, also add a case in `assets/ai-ping.sh` and `assets/ai-fan.sh`.

## Bug Reports

Open an issue with:
- What you expected
- What actually happened
- Your OS + shell version (`echo $SHELL --version`)

## Pull Requests

1. Fork the repo
2. Create a branch (`git checkout -b feature/my-change`)
3. Make your changes
4. Test with `./install.sh` on a clean setup if possible
5. Open a PR with a clear description

## Code Style

- Bash: POSIX-compatible where possible (macOS ships bash 3.2)
- Python: no external dependencies (stdlib only)
- Keep scripts self-contained — each should work independently
- Test on macOS (primary target) and Linux if possible

## Adding Prompt Templates

Add a new `.md` file to `assets/prompts/` following the existing format:
- `## Variables` section listing template variables
- `## Prompt` section with the actual prompt
- Use `{{VARIABLE}}` syntax for substitution points
