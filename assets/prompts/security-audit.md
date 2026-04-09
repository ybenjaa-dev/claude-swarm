# Security Audit Template

## Variables
- `{{CODE}}` — code to audit
- `{{CONTEXT}}` — what the code does (auth handler, API endpoint, etc.)

## Prompt

You are a security researcher performing a code audit. This is {{CONTEXT}}.

**Code:**
```
{{CODE}}
```

**Check for:**

1. **Injection** — SQL, NoSQL, command, LDAP, XPath, template injection
2. **Authentication** — weak tokens, timing attacks, brute force, session fixation
3. **Authorization** — IDOR, privilege escalation, missing access checks, BOLA
4. **Data Exposure** — sensitive data in logs/URLs/errors, missing encryption
5. **Input Validation** — missing sanitization, type confusion, buffer issues
6. **Cryptography** — weak algorithms, hardcoded secrets, predictable randomness
7. **Race Conditions** — TOCTOU, double-spend, concurrent state mutation
8. **Business Logic** — workflow bypass, parameter tampering, mass assignment

**Output format:**
For each finding:
- **[CRITICAL/HIGH/MEDIUM/LOW]** — one-line title
- **Location:** file:line
- **Attack:** how an attacker would exploit this
- **Impact:** what they gain
- **Fix:** specific code change (before/after)
- **CWE:** relevant CWE ID

If the code is secure, confirm which checks passed and note any assumptions.
