# Test Generation Template

## Variables
- `{{CODE}}` — source code to test
- `{{FRAMEWORK}}` — test framework (jest, vitest, pytest, flutter_test, etc.)
- `{{STYLE}}` — testing style (unit, integration, e2e)

## Prompt

You are a testing expert. Generate comprehensive tests for this code.

**Source code:**
```
{{CODE}}
```

**Framework:** {{FRAMEWORK}}
**Style:** {{STYLE}}

**Requirements:**
1. Cover all public functions/methods
2. Test happy path, edge cases, and error cases
3. Use descriptive test names that read like documentation
4. Mock external dependencies (APIs, databases, file system)
5. No testing implementation details — test behavior and contracts
6. Group related tests with describe/context blocks

**Edge cases to always consider:**
- Empty inputs, null/undefined
- Boundary values (0, -1, MAX_INT)
- Concurrent access (if applicable)
- Invalid types (if dynamically typed)
- Large inputs (performance)

**Output:** Complete, runnable test file. No explanatory text — just the code.
