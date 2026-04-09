#!/usr/bin/env python3
"""
ai-stats — analytics dashboard for AI delegate performance.

Parses ~/.claude/ai-tasks.log and shows per-model:
  - Total runs, success rate, failure rate
  - Average / median / max completion time
  - Recent trend (last 24h vs all-time)
  - Most common failure patterns

Usage:
  ai-stats              # full dashboard
  ai-stats gemini       # single model stats
  ai-stats --json       # machine-readable output
"""

import json
import os
import sys
import time
from collections import defaultdict

LOG_FILE = os.path.expanduser("~/.claude/ai-tasks.log")
SEP = "\x1f"

RESET = "\033[0m"
BOLD = "\033[1m"
DIM = "\033[2m"
GREEN = "\033[38;2;80;220;100m"
RED = "\033[38;2;240;80;80m"
YELLOW = "\033[38;2;255;200;50m"

COLORS = {
    "gemini": "\033[38;2;26;188;156m",
    "codex": "\033[38;2;42;166;62m",
    "qwen": "\033[38;2;200;28;222m",
    "claude": "\033[38;2;21;93;252m",
}
ICONS = {
    "gemini": "◆",
    "codex": "⬡",
    "qwen": "◈",
    "claude": "◉",
}


def parse_log():
    if not os.path.exists(LOG_FILE):
        return {}

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

            try:
                ts_int = int(ts)
            except ValueError:
                continue

            if status == "START" and len(parts) >= 7:
                tasks[task_id] = {
                    "model": model,
                    "desc": desc,
                    "start_ts": ts_int,
                    "status": "running",
                }
            elif status == "END" and task_id in tasks and len(parts) >= 8:
                exit_code = parts[6].strip()
                elapsed_str = parts[7].rstrip("s")
                try:
                    elapsed = int(elapsed_str)
                except ValueError:
                    elapsed = 0
                tasks[task_id]["status"] = "done" if exit_code == "0" else "failed"
                tasks[task_id]["exit_code"] = exit_code
                tasks[task_id]["elapsed"] = elapsed
                tasks[task_id]["end_ts"] = ts_int

    return tasks


def compute_stats(tasks, model_filter=None):
    now = int(time.time())
    day_ago = now - 86400

    stats = defaultdict(lambda: {
        "total": 0, "success": 0, "failed": 0, "running": 0,
        "times": [], "recent_total": 0, "recent_success": 0,
        "recent_times": [], "tasks": [],
    })

    for tid, t in tasks.items():
        model = t["model"]
        if model_filter and model != model_filter:
            continue

        s = stats[model]
        s["total"] += 1

        if t["status"] == "running":
            s["running"] += 1
            continue

        elapsed = t.get("elapsed", 0)

        if t["status"] == "done":
            s["success"] += 1
            s["times"].append(elapsed)
        else:
            s["failed"] += 1

        # Recent (last 24h)
        if t.get("start_ts", 0) > day_ago:
            s["recent_total"] += 1
            if t["status"] == "done":
                s["recent_success"] += 1
                s["recent_times"].append(elapsed)

        s["tasks"].append(t)

    return dict(stats)


def fmt_time(seconds):
    if seconds < 60:
        return f"{seconds}s"
    return f"{seconds // 60}m{seconds % 60}s"


def percentile(arr, p):
    if not arr:
        return 0
    arr = sorted(arr)
    idx = int(len(arr) * p / 100)
    return arr[min(idx, len(arr) - 1)]


def render_bar(value, max_val, width=20):
    if max_val == 0:
        return "░" * width
    filled = int(value / max_val * width)
    return "█" * filled + "░" * (width - filled)


def render(stats, json_mode=False):
    if json_mode:
        output = {}
        for model, s in stats.items():
            rate = (s["success"] / s["total"] * 100) if s["total"] > 0 else 0
            output[model] = {
                "total": s["total"],
                "success": s["success"],
                "failed": s["failed"],
                "running": s["running"],
                "success_rate": round(rate, 1),
                "avg_time": round(sum(s["times"]) / len(s["times"]), 1) if s["times"] else 0,
                "median_time": percentile(s["times"], 50),
                "p95_time": percentile(s["times"], 95),
                "max_time": max(s["times"]) if s["times"] else 0,
            }
        print(json.dumps(output, indent=2))
        return

    if not stats:
        print(f"\n  {DIM}No delegate data yet. Run some tasks first.{RESET}\n")
        return

    w = 68
    print()
    print(f"  {BOLD}AI Delegate Analytics{RESET}  {DIM}{time.strftime('%H:%M:%S')}{RESET}")
    print(f"  {'─' * w}")

    # Find max total for bar scaling
    max_total = max(s["total"] for s in stats.values()) if stats else 1

    for model in ["gemini", "codex", "qwen", "claude"]:
        if model not in stats:
            continue
        s = stats[model]
        color = COLORS.get(model, RESET)
        icon = ICONS.get(model, "●")

        rate = (s["success"] / s["total"] * 100) if s["total"] > 0 else 0
        rate_color = GREEN if rate >= 80 else YELLOW if rate >= 50 else RED

        print(f"\n  {color}{BOLD}{icon} {model.upper()}{RESET}")

        # Success rate bar
        bar = render_bar(s["success"], s["total"])
        print(f"    Success   {rate_color}{BOLD}{rate:5.1f}%{RESET}  {color}{bar}{RESET}  "
              f"{DIM}{s['success']}/{s['total']} runs{RESET}")

        # Timing stats
        if s["times"]:
            avg = sum(s["times"]) / len(s["times"])
            med = percentile(s["times"], 50)
            p95 = percentile(s["times"], 95)
            mx = max(s["times"])
            print(f"    Timing    {DIM}avg {fmt_time(int(avg))}  "
                  f"med {fmt_time(med)}  "
                  f"p95 {fmt_time(p95)}  "
                  f"max {fmt_time(mx)}{RESET}")
        else:
            print(f"    Timing    {DIM}no successful runs{RESET}")

        # Breakdown
        parts = []
        if s["success"]:
            parts.append(f"{GREEN}{s['success']} ✓{RESET}")
        if s["failed"]:
            parts.append(f"{RED}{s['failed']} ✗{RESET}")
        if s["running"]:
            parts.append(f"{YELLOW}{s['running']} ⟳{RESET}")
        print(f"    Breakdown {' '.join(parts)}")

        # 24h trend
        if s["recent_total"] > 0:
            recent_rate = s["recent_success"] / s["recent_total"] * 100
            trend_color = GREEN if recent_rate >= 80 else YELLOW if recent_rate >= 50 else RED
            recent_avg = ""
            if s["recent_times"]:
                ra = sum(s["recent_times"]) / len(s["recent_times"])
                recent_avg = f"  avg {fmt_time(int(ra))}"
            print(f"    24h trend {trend_color}{recent_rate:.0f}%{RESET} "
                  f"{DIM}({s['recent_success']}/{s['recent_total']} runs{recent_avg}){RESET}")

    print(f"\n  {'─' * w}")

    # Overall summary
    total_all = sum(s["total"] for s in stats.values())
    success_all = sum(s["success"] for s in stats.values())
    failed_all = sum(s["failed"] for s in stats.values())
    running_all = sum(s["running"] for s in stats.values())
    all_times = []
    for s in stats.values():
        all_times.extend(s["times"])

    overall_rate = (success_all / total_all * 100) if total_all > 0 else 0
    avg_all = fmt_time(int(sum(all_times) / len(all_times))) if all_times else "-"

    print(f"  {BOLD}Overall{RESET}  {total_all} tasks  "
          f"{GREEN}{success_all}✓{RESET} {RED}{failed_all}✗{RESET} "
          f"{YELLOW}{running_all}⟳{RESET}  "
          f"rate {overall_rate:.0f}%  avg {avg_all}")
    print()


def main():
    args = sys.argv[1:]
    model_filter = None
    json_mode = False

    for arg in args:
        if arg == "--json":
            json_mode = True
        elif arg in ("gemini", "codex", "qwen", "claude"):
            model_filter = arg

    tasks = parse_log()
    stats = compute_stats(tasks, model_filter)
    render(stats, json_mode)


if __name__ == "__main__":
    main()
