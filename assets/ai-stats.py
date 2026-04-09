#!/usr/bin/env python3
"""
ai-stats — analytics dashboard for AI delegate performance.

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

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ai_models

LOG_FILE = os.path.expanduser("~/.claude/ai-tasks.log")
SEP = "\x1f"

RESET = ai_models.RESET
BOLD = ai_models.BOLD
DIM = ai_models.DIM
GREEN = "\033[38;2;80;220;100m"
RED = "\033[38;2;240;80;80m"
YELLOW = "\033[38;2;255;200;50m"
MODELS = ai_models.load_models()


def parse_log():
    if not os.path.exists(LOG_FILE):
        return {}
    tasks = {}
    with open(LOG_FILE) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            parts = line.split(SEP)
            if len(parts) < 6: continue
            ts, status, model = parts[0], parts[1], parts[2].lower()
            task_id, desc = parts[3], parts[4]
            try: ts_int = int(ts)
            except ValueError: continue
            if status == "START" and len(parts) >= 7:
                tasks[task_id] = {"model": model, "desc": desc, "start_ts": ts_int, "status": "running"}
            elif status == "END" and task_id in tasks and len(parts) >= 8:
                exit_code = parts[6].strip()
                try: elapsed = int(parts[7].rstrip("s"))
                except ValueError: elapsed = 0
                tasks[task_id]["status"] = "done" if exit_code == "0" else "failed"
                tasks[task_id]["exit_code"] = exit_code
                tasks[task_id]["elapsed"] = elapsed
                tasks[task_id]["end_ts"] = ts_int
    return tasks


def compute_stats(tasks, model_filter=None):
    now = int(time.time()); day_ago = now - 86400
    stats = defaultdict(lambda: {"total": 0, "success": 0, "failed": 0, "running": 0,
                                   "times": [], "recent_total": 0, "recent_success": 0, "recent_times": []})
    for t in tasks.values():
        model = t["model"]
        if model_filter and model != model_filter: continue
        s = stats[model]; s["total"] += 1
        if t["status"] == "running": s["running"] += 1; continue
        elapsed = t.get("elapsed", 0)
        if t["status"] == "done": s["success"] += 1; s["times"].append(elapsed)
        else: s["failed"] += 1
        if t.get("start_ts", 0) > day_ago:
            s["recent_total"] += 1
            if t["status"] == "done": s["recent_success"] += 1; s["recent_times"].append(elapsed)
    return dict(stats)


def fmt_time(s): return f"{s}s" if s < 60 else f"{s // 60}m{s % 60}s"

def percentile(arr, p):
    if not arr: return 0
    arr = sorted(arr); return arr[min(int(len(arr) * p / 100), len(arr) - 1)]

def render_bar(v, mx, w=20): filled = int(v / mx * w) if mx else 0; return "█" * filled + "░" * (w - filled)


def render(stats, json_mode=False):
    if json_mode:
        out = {}
        for model, s in stats.items():
            rate = (s["success"] / s["total"] * 100) if s["total"] else 0
            out[model] = {"total": s["total"], "success": s["success"], "failed": s["failed"],
                          "success_rate": round(rate, 1),
                          "avg_time": round(sum(s["times"]) / len(s["times"]), 1) if s["times"] else 0,
                          "median_time": percentile(s["times"], 50), "p95_time": percentile(s["times"], 95),
                          "max_time": max(s["times"]) if s["times"] else 0}
        print(json.dumps(out, indent=2)); return

    if not stats: print(f"\n  {DIM}No delegate data yet.{RESET}\n"); return

    w = 68
    print(f"\n  {BOLD}AI Delegate Analytics{RESET}  {DIM}{time.strftime('%H:%M:%S')}{RESET}")
    print(f"  {'─' * w}")

    for model_name in list(MODELS.keys()) + [m for m in stats if m not in MODELS]:
        if model_name not in stats: continue
        s = stats[model_name]
        mi = ai_models.get_model(MODELS, model_name)
        rate = (s["success"] / s["total"] * 100) if s["total"] else 0
        rc = GREEN if rate >= 80 else YELLOW if rate >= 50 else RED

        print(f"\n  {mi['color']}{BOLD}{mi['icon']} {model_name.upper()}{RESET}")
        print(f"    Success   {rc}{BOLD}{rate:5.1f}%{RESET}  {mi['color']}{render_bar(s['success'], s['total'])}{RESET}  "
              f"{DIM}{s['success']}/{s['total']} runs{RESET}")

        if s["times"]:
            avg, med, p95, mx = sum(s["times"]) / len(s["times"]), percentile(s["times"], 50), percentile(s["times"], 95), max(s["times"])
            print(f"    Timing    {DIM}avg {fmt_time(int(avg))}  med {fmt_time(med)}  p95 {fmt_time(p95)}  max {fmt_time(mx)}{RESET}")
        else:
            print(f"    Timing    {DIM}no successful runs{RESET}")

        parts = []
        if s["success"]: parts.append(f"{GREEN}{s['success']} ✓{RESET}")
        if s["failed"]: parts.append(f"{RED}{s['failed']} ✗{RESET}")
        if s["running"]: parts.append(f"{YELLOW}{s['running']} ⟳{RESET}")
        print(f"    Breakdown {' '.join(parts)}")

        if s["recent_total"]:
            rr = s["recent_success"] / s["recent_total"] * 100
            tc = GREEN if rr >= 80 else YELLOW if rr >= 50 else RED
            ra = f"  avg {fmt_time(int(sum(s['recent_times']) / len(s['recent_times'])))}" if s["recent_times"] else ""
            print(f"    24h trend {tc}{rr:.0f}%{RESET} {DIM}({s['recent_success']}/{s['recent_total']} runs{ra}){RESET}")

    print(f"\n  {'─' * w}")
    ta = sum(s["total"] for s in stats.values()); sa = sum(s["success"] for s in stats.values())
    fa = sum(s["failed"] for s in stats.values()); ra = sum(s["running"] for s in stats.values())
    at = []; [at.extend(s["times"]) for s in stats.values()]
    or_ = (sa / ta * 100) if ta else 0; aa = fmt_time(int(sum(at) / len(at))) if at else "-"
    print(f"  {BOLD}Overall{RESET}  {ta} tasks  {GREEN}{sa}✓{RESET} {RED}{fa}✗{RESET} {YELLOW}{ra}⟳{RESET}  rate {or_:.0f}%  avg {aa}")
    print()


if __name__ == "__main__":
    args = sys.argv[1:]
    model_filter = None; json_mode = False
    known = set(MODELS.keys())
    for arg in args:
        if arg == "--json": json_mode = True
        elif arg in known: model_filter = arg
    render(compute_stats(parse_log(), model_filter), json_mode)
