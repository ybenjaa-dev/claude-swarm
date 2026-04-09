#!/usr/bin/env python3
"""
ai-read — display recent delegate output files with colored headers.

Usage:
  ai-read              # show last completed task's output
  ai-read 3            # show last 3 completed tasks' outputs
  ai-read gemini       # show last gemini output
  ai-read gemini 2     # show last 2 gemini outputs
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ai_models

LOG_FILE = os.path.expanduser("~/.claude/ai-tasks.log")
SEP = "\x1f"

RESET = ai_models.RESET
BOLD = ai_models.BOLD
DIM = ai_models.DIM
MODELS = ai_models.load_models()
STATUS_COLORS = {
    "done": "\033[38;2;42;166;62m",
    "failed": "\033[38;2;231;24;11m",
}


def read_tasks():
    if not os.path.exists(LOG_FILE):
        return []
    tasks = {}
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
            if status == "START" and len(parts) >= 7:
                try:
                    start_ts = int(ts)
                except ValueError:
                    continue
                tasks[task_id] = {
                    "model": model, "desc": desc, "start_ts": start_ts,
                    "start_time": time_str, "status": "running", "output": parts[6],
                }
            elif status == "END" and task_id in tasks and len(parts) >= 8:
                exit_code = parts[6].strip()
                tasks[task_id]["status"] = "done" if exit_code == "0" else "failed"
                tasks[task_id]["end_time"] = time_str
                tasks[task_id]["elapsed"] = parts[7]
                tasks[task_id]["exit_code"] = exit_code
    completed = [t for t in tasks.values() if t["status"] != "running"]
    return sorted(completed, key=lambda x: x.get("start_ts", 0), reverse=True)


def show_output(task):
    model = task["model"]
    m = ai_models.get_model(MODELS, model)
    color, icon = m["color"], m["icon"]
    sc = STATUS_COLORS.get(task["status"], RESET)
    symbol = "✓" if task["status"] == "done" else "✗"
    output_file = task.get("output", "")

    print()
    print(f"  {color}{BOLD}{'─' * 68}{RESET}")
    print(f"  {color}{BOLD}{icon} {model.upper()}{RESET}  {sc}{symbol} {task['status']}{RESET}  "
          f"{DIM}{task.get('elapsed', '?')}  {task.get('start_time', '')} → {task.get('end_time', '')}{RESET}")
    print(f"  {DIM}{task['desc']}{RESET}")
    print(f"  {DIM}{output_file}{RESET}")
    print(f"  {color}{BOLD}{'─' * 68}{RESET}")
    print()

    if not output_file or not os.path.exists(output_file):
        print(f"  {DIM}{'(no output file recorded)' if not output_file else f'output file not found: {output_file}'}{RESET}\n")
        return
    if os.path.getsize(output_file) == 0:
        print(f"  {DIM}(empty output){RESET}\n")
        return
    try:
        with open(output_file) as f:
            for line in f.read().splitlines():
                print(f"  {line}")
    except Exception as e:
        print(f"  {DIM}error reading file: {e}{RESET}")
    print()


def main():
    args = sys.argv[1:]
    model_filter = None
    count = 1
    known_models = set(MODELS.keys())
    for arg in args:
        if arg.isdigit():
            count = int(arg)
        elif arg in known_models:
            model_filter = arg
    tasks = read_tasks()
    if model_filter:
        tasks = [t for t in tasks if t["model"] == model_filter]
    if not tasks:
        label = f" for {model_filter}" if model_filter else ""
        print(f"\n  {DIM}No completed delegate tasks{label} found.{RESET}\n")
        return
    for task in tasks[:count]:
        show_output(task)


if __name__ == "__main__":
    main()
