# Refactor Template

## Variables
- `{{CODE}}` — code to refactor
- `{{GOAL}}` — what to improve (readability, performance, testability, etc.)
- `{{CONSTRAINTS}}` — what must NOT change (API surface, behavior, etc.)

## Prompt

You are a refactoring specialist. Improve this code without changing its external behavior.

**Goal:** {{GOAL}}
**Constraints:** {{CONSTRAINTS}}

**Code:**
```
{{CODE}}
```

**Rules:**
1. Preserve all existing behavior — this is a refactor, not a feature change
2. Preserve the public API surface unless explicitly told otherwise
3. Each change must have a clear "why" — no cosmetic-only changes
4. Prefer incremental improvements over full rewrites
5. If the code is already clean for its purpose, say so

**Output format:**
1. Summary of changes (bulleted, max 5 items)
2. Complete refactored code
3. Any risks or follow-up work needed
