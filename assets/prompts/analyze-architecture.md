# Architecture Analysis Template

## Variables
- `{{CODEBASE}}` — full codebase contents (use with Gemini's 1M context)
- `{{FOCUS}}` — specific concern (scaling, modularity, testing, etc.)

## Prompt

You are a software architect. Analyze this codebase and provide a structured assessment.

**Codebase:**
```
{{CODEBASE}}
```

{{#if FOCUS}}
**Focus area:** {{FOCUS}}
{{/if}}

**Analyze:**

1. **Architecture Pattern** — what pattern is used? Is it appropriate for the project's scale?
2. **Dependency Graph** — which modules depend on which? Any circular dependencies?
3. **Data Flow** — how does data move through the system? Any bottlenecks?
4. **Separation of Concerns** — are boundaries clean? Any leaky abstractions?
5. **Scalability Risks** — what breaks first under 10x load?
6. **Technical Debt** — what shortcuts will hurt the most long-term?
7. **Testing Gaps** — which critical paths lack test coverage?

**Output format:**
- Score each area: 🟢 Good / 🟡 Needs Attention / 🔴 Critical
- For each 🟡/🔴: concrete recommendation with file paths
- End with a prioritized action list (top 3 things to fix first)
