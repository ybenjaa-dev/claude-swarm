#!/usr/bin/env python3
"""
ai-board — view blackboard shared state for delegate sessions.

Usage:
  ai-board                    # list all sessions
  ai-board <session>          # show session details
  ai-board <session> <model>  # show specific model's output
  ai-board clean              # remove sessions older than 24h
  ai-board wipe               # remove all sessions
"""

import json
import os
import shutil
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ai_models

BOARD_DIR = os.path.expanduser("~/.claude/blackboard")
RESET = ai_models.RESET
BOLD = ai_models.BOLD
DIM = ai_models.DIM
MODELS = ai_models.load_models()
STATUS_COLORS = {"0": "\033[38;2;42;166;62m", "done": "\033[38;2;42;166;62m", "failed": "\033[38;2;231;24;11m"}


def _m(name):
    return ai_models.get_model(MODELS, name)


def list_sessions():
    if not os.path.exists(BOARD_DIR):
        print(f"\n  {DIM}No blackboard sessions yet.{RESET}")
        print(f"  {DIM}Set AI_SESSION=<name> before calling ai-delegate.sh to enable.{RESET}\n")
        return
    sessions = []
    for name in os.listdir(BOARD_DIR):
        path = os.path.join(BOARD_DIR, name)
        if not os.path.isdir(path):
            continue
        manifest = {}
        mp = os.path.join(path, "_manifest.json")
        if os.path.exists(mp):
            try:
                with open(mp) as f: manifest = json.load(f)
            except Exception: pass
        sessions.append({"name": name, "path": path, "mtime": os.path.getmtime(path),
                          "artifacts": [f for f in os.listdir(path) if not f.startswith("_")], "manifest": manifest})
    if not sessions:
        print(f"\n  {DIM}No blackboard sessions yet.{RESET}\n"); return
    sessions.sort(key=lambda s: s["mtime"], reverse=True)
    w = 72
    print(f"\n  {BOLD}Blackboard Sessions{RESET}  {DIM}{time.strftime('%H:%M:%S')}{RESET}")
    print(f"  {'─' * w}")
    for s in sessions:
        age = time.time() - s["mtime"]
        age_str = f"{int(age/60)}m ago" if age < 3600 else f"{int(age/3600)}h ago" if age < 86400 else f"{int(age/86400)}d ago"
        models_seen = {e.get("model", "") for e in s["manifest"].values() if e.get("model")}
        icons = " ".join(f"{_m(m)['color']}{_m(m)['icon']}{RESET}" for m in sorted(models_seen)) or f"{DIM}no delegates{RESET}"
        success = sum(1 for e in s["manifest"].values() if str(e.get("exit_code", 1)) == "0")
        failed = len(s["manifest"]) - success
        sp = []
        if success: sp.append(f"{STATUS_COLORS['done']}{success}✓{RESET}")
        if failed: sp.append(f"{STATUS_COLORS['failed']}{failed}✗{RESET}")
        print(f"  {BOLD}{s['name'][:40]:<40}{RESET} {icons}  {' '.join(sp)}  {DIM}{age_str}{RESET}")
        for e in s["manifest"].values():
            m = e.get("model", "?"); mi = _m(m)
            ec = str(e.get("exit_code", "?")); sym = f"{STATUS_COLORS.get('done', RESET)}✓{RESET}" if ec == "0" else f"{STATUS_COLORS.get('failed', RESET)}✗{RESET}"
            task = e.get("task", ""); task = task[:44] + "…" if len(task) > 45 else task
            print(f"    {mi['color']}{mi['icon']}{RESET} {sym} {DIM}{e.get('elapsed', '?'):<6}{RESET} {task}")
    print(f"  {'─' * w}\n  {DIM}{len(sessions)} session(s){RESET}\n")


def show_session(session_name, model_filter=None):
    session_path = os.path.join(BOARD_DIR, session_name)
    if not os.path.exists(session_path) and os.path.exists(BOARD_DIR):
        matches = [d for d in os.listdir(BOARD_DIR) if d.startswith(session_name) and os.path.isdir(os.path.join(BOARD_DIR, d))]
        if len(matches) == 1: session_name, session_path = matches[0], os.path.join(BOARD_DIR, matches[0])
        elif len(matches) > 1:
            print(f"\n  Ambiguous prefix '{session_name}':"); [print(f"    {m}") for m in matches]; print(); return
        else: print(f"\n  {DIM}Session '{session_name}' not found.{RESET}\n"); return
    manifest = {}
    mp = os.path.join(session_path, "_manifest.json")
    if os.path.exists(mp):
        try:
            with open(mp) as f: manifest = json.load(f)
        except Exception: pass
    artifacts = sorted(f for f in os.listdir(session_path) if not f.startswith("_"))
    if model_filter: artifacts = [a for a in artifacts if a.startswith(model_filter + "_")]
    if not artifacts:
        print(f"\n  {DIM}No artifacts{' for ' + model_filter if model_filter else ''} in '{session_name}'.{RESET}\n"); return
    w = 68
    print(f"\n  {BOLD}Session: {session_name}{RESET}\n  {BOLD}{'─' * w}{RESET}")
    for artifact in artifacts:
        filepath = os.path.join(session_path, artifact)
        model = artifact.split("_")[0] if "_" in artifact else "unknown"
        mi = _m(model)
        entry = next((e for e in manifest.values() if e.get("file") == artifact), None)
        ec = str(entry.get("exit_code", "?")) if entry else "?"
        sym = f"{STATUS_COLORS.get('done', RESET)}✓{RESET}" if ec == "0" else f"{STATUS_COLORS.get('failed', RESET)}✗{RESET}"
        print(f"  {mi['color']}{BOLD}{mi['icon']} {model.upper()}{RESET}  {sym}  {DIM}{entry.get('elapsed', '?') if entry else '?'}{RESET}")
        print(f"  {DIM}{entry.get('task', artifact) if entry else artifact}{RESET}")
        print(f"  {mi['color']}{'─' * w}{RESET}")
        try:
            if os.path.getsize(filepath) == 0: print(f"  {DIM}(empty){RESET}")
            else:
                with open(filepath) as f: lines = f.read().splitlines()
                for line in lines[:80]: print(f"  {line}")
                if len(lines) > 80: print(f"\n  {DIM}… {len(lines) - 80} more lines{RESET}")
        except Exception as e: print(f"  {DIM}error: {e}{RESET}")
        print()
    print(f"  {BOLD}{'─' * w}{RESET}\n  {DIM}{len(artifacts)} artifact(s){RESET}\n")


def clean_sessions(max_age_hours=24):
    if not os.path.exists(BOARD_DIR): print(f"  {DIM}Nothing to clean.{RESET}"); return
    now = time.time(); removed = 0
    for name in os.listdir(BOARD_DIR):
        path = os.path.join(BOARD_DIR, name)
        if os.path.isdir(path) and (now - os.path.getmtime(path)) / 3600 > max_age_hours:
            shutil.rmtree(path); removed += 1
    print(f"  Removed {removed} session(s) older than {max_age_hours}h.")


def wipe_all():
    if not os.path.exists(BOARD_DIR): print(f"  {DIM}Nothing to wipe.{RESET}"); return
    count = sum(1 for n in os.listdir(BOARD_DIR) if os.path.isdir(os.path.join(BOARD_DIR, n)))
    for n in os.listdir(BOARD_DIR):
        p = os.path.join(BOARD_DIR, n)
        if os.path.isdir(p): shutil.rmtree(p)
    print(f"  Wiped {count} session(s).")


if __name__ == "__main__":
    args = sys.argv[1:]
    if not args: list_sessions()
    elif args[0] == "clean": clean_sessions()
    elif args[0] == "wipe": wipe_all()
    elif len(args) == 1: show_session(args[0])
    elif len(args) == 2: show_session(args[0], model_filter=args[1])
    else: print(__doc__)
