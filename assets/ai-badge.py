#!/usr/bin/env python3
"""
Sets iTerm2 badge (top-right corner) with compact AI task status.
Called by ai-delegate.sh on task start/end and by zsh precmd hook.
"""

import fcntl
import os
import sys
import time
import base64
import unicodedata

LOG_FILE = "/tmp/ai-tasks.log"
SEP = "\x1f"

ICONS = {"gemini": "◆", "codex": "⬡", "qwen": "◈"}
STATUS_SYM = {"running": "…", "done": "✓", "failed": "✗"}


def trim_log(max_lines=500):
    try:
        with open(LOG_FILE) as f:
            lines = f.readlines()
        if len(lines) > max_lines:
            with open(LOG_FILE, "w") as f:
                f.writelines(lines[-max_lines:])
    except OSError:
        pass


def read_tasks():
    if not os.path.exists(LOG_FILE):
        return {}
    tasks = {}
    now = int(time.time())
    try:
        with open(LOG_FILE) as f:
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
    trim_log()
    return tasks


def truncate(s, n):
    if len(s) <= n:
        return s
    truncated = unicodedata.normalize("NFC", s[:n - 1])
    return truncated + "…"


def build_badge(tasks):
    if not tasks:
        return ""

    running = [t for t in tasks.values() if t["status"] == "running"]
    recent  = sorted(
        [t for t in tasks.values() if t["status"] != "running"],
        key=lambda x: x.get("start_ts", 0), reverse=True
    )[:3]

    lines = []
    for t in running + recent:
        icon    = ICONS.get(t["model"], "●")
        sym     = STATUS_SYM.get(t["status"], "?")
        elapsed = t.get("elapsed", 0)
        desc    = truncate(t["desc"], 18)
        lines.append(f"{icon} {sym}{elapsed}s  {desc}")

    if not lines:
        return ""
    return "\n".join(lines)


def set_badge(text):
    if not text:
        return
    encoded = base64.b64encode(text.encode()).decode()
    seq = f"\033]1337;SetBadgeFormat={encoded}\007"
    try:
        with open("/dev/tty", "w") as tty:
            tty.write(seq)
            tty.flush()
    except OSError:
        if sys.stdout.isatty():
            sys.stdout.write(seq)
            sys.stdout.flush()


if __name__ == "__main__":
    tasks = read_tasks()
    badge = build_badge(tasks)
    set_badge(badge)
