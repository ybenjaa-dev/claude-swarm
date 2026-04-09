#!/usr/bin/env python3
"""
iTerm2 status bar components:
  1. Claude usage   — S:24%   W:62%   ♦16%
  2. AI delegates   — ◆ GEMINI 12s…  ◈ ✓5s
"""

import asyncio
import fcntl
import iterm2
import json
import os
import time
import urllib.request
import subprocess

USAGE_CACHE = os.path.expanduser("~/.claude/usage-cache.json")
TASKS_LOG   = os.path.expanduser("~/.claude/ai-tasks.log")
CACHE_TTL   = 300  # 5 minutes — avoids 429 from frequent polling
SEP         = "\x1f"
ICONS = {"gemini": "◆", "codex": "⬡", "qwen": "◈"}


# ── Claude usage ──────────────────────────────────────────────────────────────

def get_token():
    result = subprocess.run(
        ["security", "find-generic-password", "-s", "Claude Code-credentials", "-w"],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout.strip())["claudeAiOauth"]["accessToken"]
    except Exception:
        return None


def get_usage():
    cached = None
    if os.path.exists(USAGE_CACHE):
        try:
            with open(USAGE_CACHE) as f:
                cached = json.load(f)
            if time.time() - cached.get("cached_at", 0) < CACHE_TTL:
                return cached  # fresh cache — skip API call
        except Exception:
            cached = None

    token = get_token()
    if not token:
        return cached  # no token — return stale cache rather than nothing

    try:
        req = urllib.request.Request(
            "https://api.anthropic.com/api/oauth/usage",
            headers={"Authorization": f"Bearer {token}", "anthropic-beta": "oauth-2025-04-20"},
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            data = json.loads(resp.read())
        data["cached_at"] = int(time.time())
        with open(USAGE_CACHE, "w") as f:
            json.dump(data, f)
        return data
    except Exception:
        return cached  # API error (429, network, etc.) — return stale cache


def format_usage(data):
    if not data:
        return "Claude: --"
    s  = data.get("five_hour", {}).get("utilization", "?")
    w  = data.get("seven_day", {}).get("utilization", "?")
    sn = (data.get("seven_day_sonnet") or {}).get("utilization")
    s_str = f"{s:.0f}%" if isinstance(s, (int, float)) else "?"
    w_str = f"{w:.0f}%" if isinstance(w, (int, float)) else "?"
    if sn is not None:
        return f"S:{s_str}   W:{w_str}   ♦{sn:.0f}%"
    return f"S:{s_str}   W:{w_str}"


# ── AI delegate tasks ─────────────────────────────────────────────────────────

def read_tasks():
    if not os.path.exists(TASKS_LOG):
        return {}
    tasks = {}
    now = int(time.time())
    try:
        with open(TASKS_LOG) as f:
            fcntl.flock(f.fileno(), fcntl.LOCK_SH)
            try:
                for line in f:
                    parts = line.strip().split(SEP)
                    if len(parts) < 6:
                        continue
                    ts_raw, status, model = parts[0], parts[1], parts[2].lower()
                    task_id, desc = parts[3], parts[4]
                    try:
                        ts = int(ts_raw)
                    except (ValueError, TypeError):
                        continue
                    if status == "START" and len(parts) >= 7:
                        tasks[task_id] = {
                            "model": model, "desc": desc,
                            "start_ts": ts, "status": "running",
                        }
                    elif status == "END" and task_id in tasks and len(parts) >= 8:
                        exit_code = parts[6].strip()
                        tasks[task_id]["status"] = "done" if exit_code == "0" else "failed"
                        tasks[task_id]["elapsed"] = ts - tasks[task_id]["start_ts"]
            finally:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)
    except Exception:
        pass
    for t in tasks.values():
        if t["status"] == "running":
            t["elapsed"] = now - t["start_ts"]
    return tasks


def format_status_bar(tasks):
    """Rich single-line for status bar with live elapsed times."""
    if not tasks:
        return ""
    running = [t for t in tasks.values() if t["status"] == "running"]
    recent  = sorted(
        [t for t in tasks.values() if t["status"] != "running"],
        key=lambda x: x.get("start_ts", 0), reverse=True
    )[:2]
    parts = []
    for t in running:
        icon = ICONS.get(t["model"], "●")
        desc = t["desc"][:12] + "…" if len(t["desc"]) > 12 else t["desc"]
        parts.append(f"{icon} {t['model'].upper()} {t['elapsed']}s… {desc}")
    for t in recent:
        icon = ICONS.get(t["model"], "●")
        sym  = "✓" if t["status"] == "done" else "✗"
        parts.append(f"{icon} {sym}{t.get('elapsed', '?')}s")
    return "  ".join(parts)


# ── iTerm2 main ───────────────────────────────────────────────────────────────

async def main(connection):
    app = await iterm2.async_get_app(connection)

    # ── Status bar: Claude usage ──────────────────────────────────────────────
    usage_component = iterm2.StatusBarComponent(
        short_description="Claude Usage",
        detailed_description="Claude Max plan: Session %, Weekly %, Sonnet %",
        knobs=[],
        exemplar="S:24% W:62% ♦16%",
        update_cadence=300,
        identifier="com.youssefbenjaa.claude-usage",
    )

    @iterm2.StatusBarRPC
    async def claude_usage_callback(knobs):
        try:
            return format_usage(get_usage())
        except Exception:
            return "Claude: --"

    await usage_component.async_register(connection, claude_usage_callback)

    # ── Status bar: AI delegates ──────────────────────────────────────────────
    delegates_component = iterm2.StatusBarComponent(
        short_description="AI Delegates",
        detailed_description="Live status of Gemini / Codex / Qwen delegate tasks",
        knobs=[],
        exemplar="◆ GEMINI 12s… analyze…  ◈ ✓8s",
        update_cadence=2,
        identifier="com.youssefbenjaa.ai-delegates",
    )

    @iterm2.StatusBarRPC
    async def delegates_callback(knobs):
        try:
            return format_status_bar(read_tasks())
        except Exception:
            return ""

    await delegates_component.async_register(connection, delegates_callback)

    # ── Clear any leftover badge ──────────────────────────────────────────────
    import base64
    empty_badge = f"\033]1337;SetBadgeFormat={base64.b64encode(b'').decode()}\007".encode()
    try:
        for window in app.terminal_windows:
            for tab in window.tabs:
                for session in tab.sessions:
                    await session.async_inject(empty_badge)
    except Exception:
        pass


iterm2.run_forever(main)
