## AI Delegation (Parallel Models)

You have 3 additional AI agents. Route every task to the model objectively best at it. Always wrap delegate calls in `~/.claude/assets/ai-delegate.sh` so the user can see live status in their terminal with `ai-status` / `ai-watch`.

**Capability registry:** Read `~/.claude/assets/capabilities.json` for machine-readable model strengths, context windows, timeouts, and routing hints.

**Prompt templates:** Reusable templates in `~/.claude/assets/prompts/` — code-review.md, debug.md, analyze-architecture.md, generate-tests.md, security-audit.md, refactor.md. Use these as structured prompts when delegating common tasks.

### Delegate Command Wrapper (ALWAYS use this — never call models directly)
```bash
# Template:
~/.claude/assets/ai-delegate.sh <model> "<task description>" <output_file> <actual command...>

# Gemini 2.5 Pro — best for analysis, math, multimodal (1M context)
~/.claude/assets/ai-delegate.sh gemini "analyze repo structure" /tmp/gemini-out.txt \
  gemini -m gemini-2.5-pro -p "..."

# Codex / GPT-5.4 — best for frontend UI, agentic coding
~/.claude/assets/ai-delegate.sh codex "generate dashboard UI" /tmp/codex-out.txt \
  codex exec --ephemeral --skip-git-repo-check --dangerously-bypass-approvals-and-sandbox "..." -o /tmp/codex-out.txt

# Qwen Max — best for code repair, debugging, boilerplate
~/.claude/assets/ai-delegate.sh qwen "fix broken auth module" /tmp/qwen-out.txt \
  qwen -m qwen-max "..." --approval-mode yolo --output-format text
```

### Best Models (always use these — never use smaller/cheaper variants)
- **Gemini:** `gemini-2.5-pro` (best reasoning + 1M context)
- **Codex/GPT:** `gpt-5.4` (default in ~/.codex/config.toml — do not override)
- **Qwen:** `qwen-max` (most capable general model via OAuth)

### Routing Rules — Task → Best Model

**→ Gemini 2.5 Pro** (analysis, math, multimodal)
- Full repo/codebase analysis >500 lines — use its 1M token window
- Math problems, algorithm proofs, complexity analysis
- Image/screenshot → code, diagram understanding
- Summarizing long docs, logs, research papers

**→ Codex / GPT-5.4** (frontend, agentic coding, review)
- Frontend UI generation — GPT leads on visual aesthetics and responsive design
- Autonomous multi-step coding tasks that modify files
- Code review: `codex exec review` in the project directory
- Fact-checking or tasks needing web-grounded knowledge

**→ Qwen Max** (code repair, debugging, boilerplate)
- Fixing/debugging broken code — Qwen leads code repair benchmarks
- High-volume boilerplate (fastest turnaround)
- Low-level tasks: regex, data transforms, parsing, shell scripts
- Multilingual code or non-English documentation

**→ Claude (yourself)** — primary role, never delegate this
- Architecture decisions and production feature implementation
- Long-horizon agentic work requiring full conversation context
- Final synthesis and integration of all delegate outputs
- Anything requiring taste, judgment, or design decisions

### Parallel Execution Protocol
1. Identify parallel subtasks before starting anything
2. Fire all delegates with `run_in_background: true` first
3. Immediately tell the user: "◆ Gemini → [task A] · ⬡ Codex → [task B] · working on [task C] myself"
4. Work on your own task while delegates run
5. When a background task completes, read its output file and incorporate it
6. Synthesize everything into one cohesive response — never dump raw model output

### Context Passing to Delegates

**Small context (< 200 lines):** Inline directly in the prompt string.

**File references:** Pass file paths — let the delegate read them.
```bash
CONTEXT=$(cat src/auth.ts src/middleware.ts)
~/.claude/assets/ai-delegate.sh qwen "fix auth bug" /tmp/out.txt \
  qwen -m qwen-max "Files:\n\`\`\`\n${CONTEXT}\n\`\`\`\n\nTask: fix the JWT validation" --approval-mode yolo
```

**Large codebase (> 500 lines):** Use Gemini's 1M context window.
```bash
CONTEXT=$(cat $(fd --type f --extension ts src/ | head -50 | xargs))
~/.claude/assets/ai-delegate.sh gemini "analyze architecture" /tmp/out.txt \
  gemini -m gemini-2.5-pro -p "Codebase:\n${CONTEXT}\n\nAnalyze the architecture and identify issues."
```

**Chaining delegates (pipeline pattern):** Pass previous output as next input.
```bash
# Step 1: Gemini analyzes
~/.claude/assets/ai-delegate.sh gemini "analyze repo" /tmp/analysis.txt \
  gemini -m gemini-2.5-pro -p "Analyze: $(cat src/main.ts)"

# Step 2: Codex implements (reads Gemini's analysis)
~/.claude/assets/ai-delegate.sh codex "implement feature" /tmp/impl.txt \
  codex exec --ephemeral "Based on this analysis: $(cat /tmp/analysis.txt)\n\nImplement: ..."
```

**Debate pattern (producer + reviewer):** Use for critical code.
```bash
# Codex produces → Qwen reviews
~/.claude/assets/ai-delegate.sh codex "write auth handler" /tmp/code.txt codex exec ...
# After codex finishes:
~/.claude/assets/ai-delegate.sh qwen "review auth handler for bugs" /tmp/review.txt \
  qwen -m qwen-max "Review this code for bugs and security issues:\n$(cat /tmp/code.txt)"
```

### Coordination Patterns

Use these multi-agent patterns for complex tasks. Choose the pattern that fits the task structure.

**Fan-Out / Fan-In** — same context, different sub-tasks, Claude merges.
```bash
# All three analyze the same codebase from different angles
export AI_SESSION="audit-$(date +%s)"
# Fire all in parallel:
ai-delegate.sh gemini "analyze architecture" /tmp/g.txt gemini -m gemini-2.5-pro -p "..."  # run_in_background
ai-delegate.sh codex "review security" /tmp/c.txt codex exec "..."                         # run_in_background
ai-delegate.sh qwen "check performance" /tmp/q.txt qwen -m qwen-max "..."                  # run_in_background
# Claude merges all findings into one response
```
When: complex analysis needing multiple perspectives (security audit, code review, architecture analysis).

**Pipeline / Chain** — each delegate's output feeds the next.
```bash
export AI_SESSION="feature-$(date +%s)"
# Sequential: research → implement → review
ai-delegate.sh gemini "research API design" /tmp/research.txt gemini ...
# Wait, then pass output:
ai-delegate.sh codex "implement based on: $(cat /tmp/research.txt)" /tmp/impl.txt codex exec ...
# Wait, then review:
ai-delegate.sh qwen "review for bugs: $(cat /tmp/impl.txt)" /tmp/review.txt qwen ...
```
When: multi-stage workflows where each step depends on the previous.

**Debate / Critique** — one produces, another critiques.
```bash
# Codex produces → Qwen reviews → Claude decides
ai-delegate.sh codex "write auth handler" /tmp/code.txt codex exec ...
ai-delegate.sh qwen "review for vulnerabilities: $(cat /tmp/code.txt)" /tmp/review.txt qwen ...
# Claude reads both, applies the review's valid points
```
When: security-sensitive code, auth handlers, payment logic, data migrations.

**Map-Reduce** — split large task across delegates, Claude merges.
```bash
export AI_SESSION="review-$(date +%s)"
# 20 files → split across 3 models
ai-delegate.sh gemini "review files 1-7"   /tmp/g.txt gemini ...  # run_in_background
ai-delegate.sh codex  "review files 8-14"  /tmp/c.txt codex exec ...  # run_in_background
ai-delegate.sh qwen   "review files 15-20" /tmp/q.txt qwen ...  # run_in_background
# Claude merges all findings
```
When: batch operations — review many files, test many endpoints, audit multiple services.

### Session & Blackboard

For multi-delegate tasks that share state, set `AI_SESSION` before firing delegates. All outputs are automatically copied to `~/.claude/blackboard/$AI_SESSION/` with a `_manifest.json` tracking each delegate's result.

```bash
export AI_SESSION="auth-refactor-$(date +%s)"
# All delegates in this session write to the same blackboard directory
ai-delegate.sh gemini "analyze auth" /tmp/g.txt gemini ...
ai-delegate.sh codex "implement auth" /tmp/c.txt codex exec ...
# View session: ai-board $AI_SESSION
```

Use `ai-board` to list sessions, `ai-board <session>` to view artifacts, `ai-board clean` to prune old ones.

### Quick Fan-Out (3 opinions, 1 command)

For critical decisions, use `ai-fan` to get all 3 models' opinions in parallel:
```bash
# From Claude — fires all 3 models on same prompt, shows comparison
bash ~/.claude/assets/ai-fan.sh "review this auth handler for security issues" src/auth.ts
# Or filter to specific models:
bash ~/.claude/assets/ai-fan.sh --models gemini,qwen "analyze this algorithm"
```

### Health Check

Before complex multi-delegate tasks, verify all models are reachable:
```bash
bash ~/.claude/assets/ai-ping.sh           # check all 3
bash ~/.claude/assets/ai-ping.sh gemini    # check one
bash ~/.claude/assets/ai-ping.sh --quiet   # exit code only (for scripting)
```

### Error Recovery Protocol

The wrapper handles automatic retry (once), empty output detection, context size warnings, and Gemini Pro→Flash fallback. For intelligent recovery:

1. **Read the failure output** — don't blindly re-delegate
2. **Augment the prompt** with the error when re-delegating:
   ```bash
   ERROR=$(cat /tmp/failed-output.txt | head -20)
   ai-delegate.sh qwen "fix: previous attempt failed: ${ERROR}" /tmp/retry.txt qwen ...
   ```
3. **Switch models** if one is struggling — a Qwen debugging failure might succeed on Gemini with more context
4. **Escalate to Claude** if two retries fail — don't infinite-loop delegates

### Using Prompt Templates

Reusable templates live in `~/.claude/assets/prompts/`. Load and fill variables:
```bash
# Read template, substitute variables, delegate
TEMPLATE=$(cat ~/.claude/assets/prompts/security-audit.md)
CODE=$(cat src/auth.ts)
PROMPT=$(echo "$TEMPLATE" | sed "s|{{CODE}}|$CODE|g" | sed "s|{{CONTEXT}}|JWT auth handler|g")
ai-delegate.sh qwen "security audit auth.ts" /tmp/audit.txt qwen -m qwen-max "$PROMPT" --approval-mode yolo
```

Available templates: `code-review`, `debug`, `analyze-architecture`, `generate-tests`, `security-audit`, `refactor`.

### Hard Rules
- ALWAYS use the wrapper script `ai-delegate.sh` — this is what powers the user's `ai-status` dashboard
- Never run a delegate synchronously when you can parallelize
- Never delegate if Bash/Read/Grep answers it faster
- Never show raw delegate output — always synthesize before responding
- On delegate failure: retry once with error context in prompt ("Previous attempt failed: {error}. Fix this.")
- Timeouts: gemini=300s, codex=600s, qwen=180s (enforced by wrapper, auto-retry built in)
- Set `AI_SESSION` for any multi-delegate task to enable blackboard shared state
- Set `AI_SILENT=1` to suppress completion sounds during batch operations

