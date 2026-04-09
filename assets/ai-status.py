#!/usr/bin/env python3
"""
AI Delegate Dashboard — shows live status of all model tasks.
Run: ai-status  (alias in .zshrc)
"""

import os
import sys
import time

# Load shared model config
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ai_models

LOG_FILE = os.path.expanduser("~/.claude/ai-tasks.log")
SEP = "\x1f"

RESET = ai_models.RESET
BOLD = ai_models.BOLD
DIM = ai_models.DIM

MODELS = ai_models.load_models()
STATUS_COLORS = ai_models.STATUS_COLORS


def get_model_color(name):
    m = ai_models.get_model(MODELS, name)
    return m["color"]

def get_model_icon(name):
    m = ai_models.get_model(MODELS, name)
    return m["icon"]


def read_tasks():
    if not os.path.exists(LOG_FILE):
        return {}
    tasks = {}
    now = int(time.time())
    with open(LOG_FILE) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(SEP)
            if len(parts) < 6:
                continue
            ts, status = parts[0], parts[1]
            model = parts[2].lower()
            task_id = parts[3]
            desc = parts[4]
            time_str = parts[5]
            if status == "START":
                output_file = parts[6] if len(parts) > 6 else ""
                tasks[task_id] = {
                    "model": model, "desc": desc,
                    "start_ts": int(ts), "start_time": time_str,
                    "status": "running", "output": output_file, "elapsed": None,
                }
            elif status == "END" and task_id in tasks:
                exit_code = parts[6] if len(parts) > 6 else "0"
                elapsed = parts[7] if len(parts) > 7 else "?"
                tasks[task_id]["status"] = "done" if exit_code == "0" else "failed"
                tasks[task_id]["end_time"] = time_str
                tasks[task_id]["elapsed"] = elapsed
                tasks[task_id]["exit_code"] = exit_code
    for t in tasks.values():
        if t["status"] == "running":
            t["elapsed"] = f"{now - t['start_ts']}s"
    return tasks


def truncate(s, n):
    return s if len(s) <= n else s[:n-1] + "…"


def render(tasks, show_all=False):
    now_str = time.strftime('%H:%M:%S')
    items = list(tasks.values())
    if not show_all:
        running = [t for t in items if t["status"] == "running"]
        done = sorted([t for t in items if t["status"] != "running"],
                       key=lambda x: x.get("start_ts", 0), reverse=True)[:5]
        items = running + done

    if not items:
        print(f"\n  {DIM}No AI delegate tasks yet.{RESET}\n")
        print(f"  {DIM}Tasks appear here when Claude delegates to other AI models.{RESET}\n")
        return

    w = 72
    print()
    print(f"  {BOLD}AI Delegate Monitor{RESET}  {DIM}{now_str}{RESET}")
    print(f"  {'─' * w}")
    print(f"  {BOLD}{'MODEL':<10} {'STATUS':<10} {'ELAPSED':<8} {'TASK':<35} {'TIME':<8}{RESET}")
    print(f"  {'─' * w}")

    for t in items:
        model = t["model"]
        color = get_model_color(model)
        icon = get_model_icon(model)
        sc = STATUS_COLORS.get(t["status"], RESET)
        model_str = f"{color}{BOLD}{icon} {model.upper():<7}{RESET}"
        status_str = f"{sc}{t['status']:<10}{RESET}"
        elapsed = t.get("elapsed") or "-"
        desc = truncate(t["desc"], 35)
        time_str = t.get("start_time", "-")
        print(f"  {model_str} {status_str} {elapsed:<8} {desc:<35} {DIM}{time_str}{RESET}")

    print(f"  {'─' * w}")
    running_count = sum(1 for t in tasks.values() if t["status"] == "running")
    done_count = sum(1 for t in tasks.values() if t["status"] == "done")
    failed_count = sum(1 for t in tasks.values() if t["status"] == "failed")
    parts = []
    if running_count: parts.append(f"{STATUS_COLORS['running']}{running_count} running{RESET}")
    if done_count: parts.append(f"{STATUS_COLORS['done']}{done_count} done{RESET}")
    if failed_count: parts.append(f"{STATUS_COLORS['failed']}{failed_count} failed{RESET}")
    if parts:
        print(f"  {' · '.join(parts)}")
    print()


def watch_mode(interval=2):
    try:
        while True:
            os.system("clear")
            render(read_tasks(), show_all=True)
            print(f"  {DIM}Refreshing every {interval}s — Ctrl+C to exit{RESET}\n")
            time.sleep(interval)
    except KeyboardInterrupt:
        print()


if __name__ == "__main__":
    if "--watch" in sys.argv or "-w" in sys.argv:
        watch_mode()
    elif "--all" in sys.argv or "-a" in sys.argv:
        render(read_tasks(), show_all=True)
    else:
        render(read_tasks(), show_all=False)
