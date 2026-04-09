"""
ai-models.py — shared model config loader for all Python scripts.

All model metadata (icons, colors, timeouts) lives in capabilities.json.
Import this module instead of hardcoding model data.

Usage:
    from importlib.machinery import SourceFileLoader
    models_mod = SourceFileLoader("ai_models", os.path.expanduser("~/.claude/assets/ai-models.py")).load_module()
    MODELS = models_mod.load_models()

    # Or simpler:
    import ai_models  # if script is in the same directory
    MODELS = ai_models.load_models()
"""

import json
import os

CAPABILITIES_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "capabilities.json")
_FALLBACK_PATH = os.path.expanduser("~/.claude/assets/capabilities.json")

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"


def _hex_to_ansi(hex_color):
    """Convert #RRGGBB to ANSI 24-bit color escape."""
    hex_color = hex_color.lstrip("#")
    r, g, b = int(hex_color[0:2], 16), int(hex_color[2:4], 16), int(hex_color[4:6], 16)
    return f"\033[38;2;{r};{g};{b}m"


def load_models():
    """Load model config from capabilities.json, return dict keyed by model name."""
    path = CAPABILITIES_PATH if os.path.exists(CAPABILITIES_PATH) else _FALLBACK_PATH

    if not os.path.exists(path):
        return _defaults()

    try:
        with open(path) as f:
            data = json.load(f)
    except Exception:
        return _defaults()

    models = {}
    for name, cfg in data.get("models", {}).items():
        models[name] = {
            "icon": cfg.get("icon", "●"),
            "color": _hex_to_ansi(cfg.get("color", "#888888")),
            "timeout": cfg.get("timeout_seconds", 300),
            "context_window": cfg.get("context_window", 128000),
            "display_name": cfg.get("display_name", name.upper()),
            "model_id": cfg.get("model_id", name),
            "fallback_model": cfg.get("fallback_model"),
            "cli_template": cfg.get("cli_template", ""),
        }
    return models


def get_model(models, name):
    """Get model config by name, with fallback defaults for unknown models."""
    if name in models:
        return models[name]
    return {
        "icon": "●",
        "color": "\033[38;2;136;136;136m",
        "timeout": 300,
        "context_window": 128000,
        "display_name": name.upper(),
        "model_id": name,
        "fallback_model": None,
        "cli_template": "",
    }


def _defaults():
    """Hardcoded fallback if capabilities.json is missing."""
    return {
        "gemini": {
            "icon": "◆", "color": "\033[38;2;26;188;156m", "timeout": 300,
            "context_window": 1000000, "display_name": "Gemini 2.5 Pro",
            "model_id": "gemini-2.5-pro", "fallback_model": "gemini-2.5-flash",
        },
        "codex": {
            "icon": "⬡", "color": "\033[38;2;42;166;62m", "timeout": 600,
            "context_window": 128000, "display_name": "GPT-5.4 (Codex)",
            "model_id": "gpt-5.4", "fallback_model": None,
        },
        "qwen": {
            "icon": "◈", "color": "\033[38;2;200;28;222m", "timeout": 180,
            "context_window": 32768, "display_name": "Qwen Max",
            "model_id": "qwen-max", "fallback_model": None,
        },
    }


# Status colors (not model-specific, shared across scripts)
STATUS_COLORS = {
    "running": "\033[38;2;255;223;32m",
    "done": "\033[38;2;42;166;62m",
    "failed": "\033[38;2;231;24;11m",
}
