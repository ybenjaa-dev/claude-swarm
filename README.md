# claude-swarm

**Give Claude Code 3 extra brains. One command to install.**

claude-swarm turns [Claude Code](https://claude.ai/code) into a multi-AI orchestrator. Claude automatically delegates tasks to **Gemini**, **Codex/GPT**, and **Qwen** in parallel — each model handles what it's best at, and Claude synthesizes the results.

```
You (prompt) → Claude Code (orchestrator)
                 ├── ◆ Gemini 2.5 Pro  → analysis, math, 1M context
                 ├── ⬡ Codex / GPT-5.4 → frontend UI, agentic coding
                 └── ◈ Qwen Max        → debugging, code repair, boilerplate
                       ↓
              Claude merges all outputs into one response
```

## What You Get

| Feature | Description |
|---|---|
| **Automatic delegation** | Claude routes tasks to the best model based on a capability registry |
| **Parallel execution** | Multiple models work simultaneously, Claude synthesizes results |
| **Live monitoring** | See running tasks, elapsed time, success/failure in real-time |
| **Auto-retry + fallback** | Failed tasks retry once; Gemini Pro falls back to Flash automatically |
| **Blackboard sessions** | Shared state between delegates for multi-step workflows |
| **Completion sounds** | Hear when delegates finish — success (Glass) or failure (Basso) |
| **Context warnings** | Warns before sending prompts that exceed a model's context window |
| **Analytics** | Per-model success rate, timing percentiles, 24h trends |
| **Prompt templates** | Pre-built templates for code review, debugging, security audit, etc. |
| **iTerm2 status bar** | Live Claude usage % and delegate status in your terminal |

## Quick Install

```bash
git clone https://github.com/youssefbenjaa/claude-swarm.git
cd claude-swarm
chmod +x install.sh
./install.sh
source ~/.zshrc
```

The installer:
1. Copies scripts to `~/.claude/assets/`
2. Installs GNU coreutils (for timeouts on macOS)
3. Adds shell aliases + tab completions to `.zshrc`
4. Appends AI delegation config to your `CLAUDE.md`
5. Optionally sets up iTerm2 status bar components
6. Checks that Gemini, Codex, and Qwen CLIs are installed

## Prerequisites

You need Claude Code plus at least one additional AI CLI:

| Model | Install | What it's best at |
|---|---|---|
| [Gemini CLI](https://github.com/google-gemini/gemini-cli) | `npm i -g @anthropic-ai/claude-code` | Analysis, math, 1M token context |
| [Codex CLI](https://github.com/openai/codex) | `npm i -g @openai/codex` | Frontend UI, agentic coding |
| [Qwen CLI](https://github.com/QwenLM/qwen-cli) | See Qwen docs | Debugging, code repair |

> You don't need all three — claude-swarm works with whichever models you have installed.

## Commands

### Monitoring

```bash
ai-status              # dashboard of recent tasks
ai-watch               # live-updating dashboard (refreshes every 2s)
ai-read                # view last delegate's output
ai-read gemini 3       # last 3 Gemini outputs
ai-follow              # tail the currently running delegate's output
```

### Analytics

```bash
ai-stats               # per-model success rate, timing, trends
ai-stats gemini        # single model breakdown
ai-stats --json        # machine-readable output
```

### Operations

```bash
ai-ping                # health check all 3 models
ai-ping gemini         # check single model
ai-ping --quiet        # exit code only (for scripting)
ai-fan "prompt"        # same task → all 3 models → compare results
ai-fan "prompt" file   # fan-out with file context
```

### Blackboard

```bash
ai-board               # list all sessions
ai-board <session>     # view session artifacts
ai-board clean         # remove sessions older than 24h
```

### Housekeeping

```bash
ai-clear               # rotate task log (keeps last 200 lines)
```

## How It Works

### 1. Claude delegates automatically

When you ask Claude Code to do something, it reads `capabilities.json` to decide which model handles each subtask:

```
You: "Review this codebase for security issues, fix any bugs, and improve the architecture"

Claude thinks:
  → Security review? Best at: Qwen (code repair benchmarks)
  → Architecture analysis? Best at: Gemini (1M context window)
  → Fix bugs? I'll do this myself (needs full conversation context)

Claude fires delegates in parallel, works on its own task, then merges everything.
```

### 2. The wrapper tracks everything

Every delegate call goes through `ai-delegate.sh`, which:
- Logs start/end to `~/.claude/ai-tasks.log`
- Enforces per-model timeouts (Gemini: 300s, Codex: 600s, Qwen: 180s)
- Auto-retries once on failure
- Detects empty output and retries
- Falls back from Gemini Pro to Flash on failure
- Warns if context exceeds the model's window
- Plays a sound on completion
- Writes to the blackboard if a session is active

### 3. You monitor in real-time

```
  AI Delegate Monitor  14:32:08
  ────────────────────────────────────────────────────────────────────────
  MODEL      STATUS     ELAPSED  TASK                                TIME
  ────────────────────────────────────────────────────────────────────────
  ◆ GEMINI  running    12s      analyze architecture                14:31:56
  ◈ QWEN   done       4s       fix auth validation                 14:31:52
  ⬡ CODEX  done       8s       generate dashboard UI               14:31:44
  ────────────────────────────────────────────────────────────────────────
  1 running · 2 done
```

## Orchestration Patterns

### Fan-Out / Fan-In
All models get the same context but different sub-tasks. Claude merges results.
```
Claude → [Gemini: architecture] [Codex: security] [Qwen: performance] → merge
```
Best for: code review, security audits, comprehensive analysis.

### Pipeline / Chain
Each model's output feeds the next.
```
Gemini (research) → Codex (implement) → Qwen (review) → Claude (ship)
```
Best for: feature development, research-to-implementation workflows.

### Debate / Critique
One model produces, another critiques.
```
Codex (write code) → Qwen (review for bugs) → Claude (apply valid fixes)
```
Best for: auth handlers, payment logic, security-sensitive code.

### Map-Reduce
Split large tasks across models, Claude merges.
```
20 files → Gemini (1-7) + Codex (8-14) + Qwen (15-20) → Claude merges
```
Best for: large batch operations, reviewing many files.

## Prompt Templates

Pre-built templates in `~/.claude/assets/prompts/`:

| Template | Best delegate | Use case |
|---|---|---|
| `code-review.md` | Codex | Bugs, security, performance, maintainability |
| `debug.md` | Qwen | Root cause analysis + minimal fix |
| `analyze-architecture.md` | Gemini | Full codebase architecture assessment |
| `generate-tests.md` | Codex | Comprehensive test generation |
| `security-audit.md` | Qwen | OWASP-style security audit |
| `refactor.md` | Codex | Behavior-preserving improvements |

## iTerm2 Status Bar

The optional iTerm2 integration adds two status bar components:

- **Claude Usage** — shows your Claude Max plan usage (session %, weekly %, Sonnet %)
- **AI Delegates** — live status of running delegate tasks with model icons

Setup: Profiles → Session → Configure Status Bar → drag in "Claude Usage" and "AI Delegates".

## Uninstall

```bash
./uninstall.sh
source ~/.zshrc
```

Cleanly removes all scripts, aliases, completions, logs, and blackboard data.

## Architecture

```
~/.claude/
  ├── assets/
  │   ├── ai-delegate.sh        # core wrapper (retry, timeout, fallback, sound, blackboard)
  │   ├── ai-status.py          # task dashboard
  │   ├── ai-read.py            # output viewer
  │   ├── ai-board.py           # blackboard session viewer
  │   ├── ai-stats.py           # analytics dashboard
  │   ├── ai-ping.sh            # model health check
  │   ├── ai-fan.sh             # parallel fan-out + compare
  │   ├── ai-badge.py           # iTerm2 badge helper
  │   ├── capabilities.json     # model capability registry
  │   └── prompts/              # reusable prompt templates
  │       ├── code-review.md
  │       ├── debug.md
  │       ├── analyze-architecture.md
  │       ├── generate-tests.md
  │       ├── security-audit.md
  │       └── refactor.md
  ├── ai-tasks.log              # delegate task log (auto-rotated)
  ├── blackboard/               # shared state for multi-delegate sessions
  └── CLAUDE.md                 # AI delegation instructions for Claude Code
```

## License

MIT

## Author

Built by [@youssefbenjaa](https://github.com/youssefbenjaa) — one conversation with Claude Code at a time.
