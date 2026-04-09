#!/usr/bin/env python3
"""
ai-board — view blackboard shared state for delegate sessions.

The blackboard is a shared directory where delegates within the same session
can read/write artifacts. Each session gets its own directory under
~/.claude/blackboard/<session_id>/.

Usage:
  ai-board                    # list all sessions with summary
  ai-board <session>          # show session details and all artifacts
  ai-board <session> <model>  # show specific model's output in that session
  ai-board clean              # remove sessions older than 24h
  ai-board wipe               # remove all sessions
"""

import json
import os
import shutil
import sys
import time

BOARD_DIR = os.path.expanduser("~/.claude/blackboard")

RESET = "\033[0m"
BOLD  = "\033[1m"
DIM   = "\033[2m"

COLORS = {
    "gemini": "\033[38;2;26;188;156m",
    "codex":  "\033[38;2;42;166;62m",
    "qwen":   "\033[38;2;200;28;222m",
    "claude": "\033[38;2;21;93;252m",
}
STATUS_COLORS = {
    "0": "\033[38;2;42;166;62m",     # green = success
    "done": "\033[38;2;42;166;62m",
    "failed": "\033[38;2;231;24;11m",
}
MODEL_ICONS = {
    "gemini": "◆",
    "codex":  "⬡",
    "qwen":   "◈",
    "claude": "◉",
}


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
        manifest_path = os.path.join(path, "_manifest.json")
        manifest = {}
        if os.path.exists(manifest_path):
            try:
                with open(manifest_path) as f:
                    manifest = json.load(f)
            except Exception:
                pass

        mtime = os.path.getmtime(path)
        artifacts = [f for f in os.listdir(path) if not f.startswith("_")]
        sessions.append({
            "name": name,
            "path": path,
            "mtime": mtime,
            "artifacts": artifacts,
            "manifest": manifest,
        })

    if not sessions:
        print(f"\n  {DIM}No blackboard sessions yet.{RESET}\n")
        return

    sessions.sort(key=lambda s: s["mtime"], reverse=True)

    w = 72
    print()
    print(f"  {BOLD}Blackboard Sessions{RESET}  {DIM}{time.strftime('%H:%M:%S')}{RESET}")
    print(f"  {'─' * w}")

    for s in sessions:
        age = time.time() - s["mtime"]
        if age < 3600:
            age_str = f"{int(age / 60)}m ago"
        elif age < 86400:
            age_str = f"{int(age / 3600)}h ago"
        else:
            age_str = f"{int(age / 86400)}d ago"

        # Gather model icons from artifacts
        models_seen = set()
        for entry in s["manifest"].values():
            m = entry.get("model", "")
            if m:
                models_seen.add(m)

        icons = " ".join(
            f"{COLORS.get(m, RESET)}{MODEL_ICONS.get(m, '●')}{RESET}"
            for m in sorted(models_seen)
        )
        if not icons:
            icons = DIM + "no delegates" + RESET

        n_artifacts = len(s["artifacts"])
        success = sum(
            1 for e in s["manifest"].values()
            if str(e.get("exit_code", 1)) == "0"
        )
        failed = len(s["manifest"]) - success

        status_parts = []
        if success:
            status_parts.append(f"{STATUS_COLORS['done']}{success}✓{RESET}")
        if failed:
            status_parts.append(f"{STATUS_COLORS['failed']}{failed}✗{RESET}")
        status_str = " ".join(status_parts) if status_parts else ""

        print(f"  {BOLD}{s['name'][:40]:<40}{RESET} {icons}  {status_str}  {DIM}{age_str}{RESET}")

        for entry in s["manifest"].values():
            m = entry.get("model", "?")
            color = COLORS.get(m, RESET)
            icon = MODEL_ICONS.get(m, "●")
            ec = str(entry.get("exit_code", "?"))
            sym = f"{STATUS_COLORS.get('done', RESET)}✓{RESET}" if ec == "0" else f"{STATUS_COLORS.get('failed', RESET)}✗{RESET}"
            elapsed = entry.get("elapsed", "?")
            task = entry.get("task", "")
            if len(task) > 45:
                task = task[:44] + "…"
            print(f"    {color}{icon}{RESET} {sym} {DIM}{elapsed:<6}{RESET} {task}")

    print(f"  {'─' * w}")
    print(f"  {DIM}{len(sessions)} session(s){RESET}\n")


def show_session(session_name, model_filter=None):
    session_path = os.path.join(BOARD_DIR, session_name)

    if not os.path.exists(session_path):
        # Try prefix match
        if os.path.exists(BOARD_DIR):
            matches = [
                d for d in os.listdir(BOARD_DIR)
                if d.startswith(session_name) and os.path.isdir(os.path.join(BOARD_DIR, d))
            ]
            if len(matches) == 1:
                session_name = matches[0]
                session_path = os.path.join(BOARD_DIR, session_name)
            elif len(matches) > 1:
                print(f"\n  Ambiguous session prefix '{session_name}'. Matches:")
                for m in matches:
                    print(f"    {m}")
                print()
                return
            else:
                print(f"\n  {DIM}Session '{session_name}' not found.{RESET}\n")
                return
        else:
            print(f"\n  {DIM}Session '{session_name}' not found.{RESET}\n")
            return

    manifest_path = os.path.join(session_path, "_manifest.json")
    manifest = {}
    if os.path.exists(manifest_path):
        try:
            with open(manifest_path) as f:
                manifest = json.load(f)
        except Exception:
            pass

    artifacts = sorted(
        f for f in os.listdir(session_path)
        if not f.startswith("_")
    )

    if model_filter:
        artifacts = [a for a in artifacts if a.startswith(model_filter + "_")]

    if not artifacts:
        label = f" for {model_filter}" if model_filter else ""
        print(f"\n  {DIM}No artifacts{label} in session '{session_name}'.{RESET}\n")
        return

    w = 68
    print()
    print(f"  {BOLD}Session: {session_name}{RESET}")
    print(f"  {BOLD}{'─' * w}{RESET}")

    for artifact in artifacts:
        filepath = os.path.join(session_path, artifact)

        # Determine model from filename prefix
        model = artifact.split("_")[0] if "_" in artifact else "unknown"
        color = COLORS.get(model, RESET)
        icon = MODEL_ICONS.get(model, "●")

        # Find manifest entry for this artifact
        entry = None
        for e in manifest.values():
            if e.get("file") == artifact:
                entry = e
                break

        ec = str(entry.get("exit_code", "?")) if entry else "?"
        sym = f"{STATUS_COLORS.get('done', RESET)}✓{RESET}" if ec == "0" else f"{STATUS_COLORS.get('failed', RESET)}✗{RESET}"
        elapsed = entry.get("elapsed", "?") if entry else "?"
        task = entry.get("task", artifact) if entry else artifact

        print(f"  {color}{BOLD}{icon} {model.upper()}{RESET}  {sym}  {DIM}{elapsed}{RESET}")
        print(f"  {DIM}{task}{RESET}")
        print(f"  {color}{'─' * w}{RESET}")

        # Read and display content
        try:
            size = os.path.getsize(filepath)
            if size == 0:
                print(f"  {DIM}(empty){RESET}")
            else:
                with open(filepath) as f:
                    content = f.read()
                lines = content.splitlines()
                if len(lines) > 80:
                    for line in lines[:80]:
                        print(f"  {line}")
                    print(f"\n  {DIM}… {len(lines) - 80} more lines (full: {filepath}){RESET}")
                else:
                    for line in lines:
                        print(f"  {line}")
        except Exception as e:
            print(f"  {DIM}error reading: {e}{RESET}")

        print()

    print(f"  {BOLD}{'─' * w}{RESET}")
    print(f"  {DIM}{len(artifacts)} artifact(s) in {session_path}{RESET}\n")


def clean_sessions(max_age_hours=24):
    if not os.path.exists(BOARD_DIR):
        print(f"  {DIM}Nothing to clean.{RESET}")
        return

    now = time.time()
    removed = 0
    for name in os.listdir(BOARD_DIR):
        path = os.path.join(BOARD_DIR, name)
        if not os.path.isdir(path):
            continue
        age_hours = (now - os.path.getmtime(path)) / 3600
        if age_hours > max_age_hours:
            shutil.rmtree(path)
            removed += 1

    print(f"  Removed {removed} session(s) older than {max_age_hours}h.")


def wipe_all():
    if not os.path.exists(BOARD_DIR):
        print(f"  {DIM}Nothing to wipe.{RESET}")
        return
    count = 0
    for name in os.listdir(BOARD_DIR):
        path = os.path.join(BOARD_DIR, name)
        if os.path.isdir(path):
            shutil.rmtree(path)
            count += 1
    print(f"  Wiped {count} session(s).")


def main():
    args = sys.argv[1:]

    if not args:
        list_sessions()
    elif args[0] == "clean":
        clean_sessions()
    elif args[0] == "wipe":
        wipe_all()
    elif len(args) == 1:
        # Could be a session name or a model name
        if args[0] in ("gemini", "codex", "qwen", "claude"):
            # Show all sessions but filter to this model — use list view
            list_sessions()
        else:
            show_session(args[0])
    elif len(args) == 2:
        show_session(args[0], model_filter=args[1])
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
