---
name: fix-issue
description: Check out an unblocked AFK GitHub issue, implement the fix via TDD, run a quality review loop, and submit a pull request for human review. Use when asked to work on, fix, or resolve a GitHub issue.
---

# Fix Issue

Autonomously resolve a single AFK GitHub issue for the Ribasim water resources modeling system: select it, gate on complexity, implement via TDD, review, and submit a pull request.

Read `CONTEXT.md` and all `.github/adr/*.md` before touching any code. Use the project's domain vocabulary (Basin, Node, FlowBoundary, etc.) in all names. Respect every ADR in the area you are touching, and flag conflicts explicitly rather than silently overriding.

---

## Phase A — Issue Acquisition

### 1. List candidates

```bash
gh issue list --label ready-for-agent --state open \
  --json number,title,body,labels \
  --jq '[.[] | {number, title, body, labels: [.labels[].name]}]'
```

> **If `gh` is not available**: use the `github-pull-request_doSearch` tool with query `is:issue is:open label:ready-for-agent repo:owner/name`. Always include the `repo:` qualifier — the tool searches all repos by default. See `.github/agents/issue-tracker.md` for the full fallback table.

All issues returned by this query are AFK by definition — `ready-for-agent` means AFK (see `.github/agents/triage-labels.md`).

### 2. Verify no unresolved blockers

For each candidate, parse the `## Blocked by` section. For every issue number listed (e.g. `#12`):

```bash
gh issue view 12 --json state --jq '.state'
```

> **If `gh` is not available**: use `github-pull-request_issue_fetch` with `issueNumber: 12`; check the `.state` field of the returned object.

Keep only candidates where every blocker returns `CLOSED` (or the section reads "None — can start immediately").

### 3. Select and confirm *(HITL checkpoint)*

Present the top eligible issue to the user:

```
Selected issue #N: {title}
Blocked by: {summary}

Proceed? (yes / no / pick a different issue)
```

**Stop here and wait for confirmation.** Do not write any code until the user confirms. If the user declines, repeat with the next eligible issue or stop if none remain.

---

## Phase B — Branch, Exploration, and Complexity Gate

### 1. Create a branch

```bash
git checkout main
git pull origin main
git checkout -b fix/{number}-{5-word-kebab-slug}
```

The slug is derived from the issue title: lowercase, spaces → hyphens, max 5 words, no special characters.

### 2. Explore

- Read `CONTEXT.md` and all `.github/adr/*.md` in full.
- Run semantic searches and targeted file reads to map every source file and test file touched by the issue's acceptance criteria.
- Do not guess — confirm your understanding of the affected modules before proceeding.

### 3. Complexity gate *(before writing any code)*

Assess the issue against these thresholds:

| Signal | Threshold | Action |
|---|---|---|
| Acceptance criteria count | > 5 | Too complex |
| Distinct unrelated modules affected | > 3 | Too complex |
| Requires an ADR decision or new architectural component | Any | Too complex |

If **any threshold is triggered**:

1. Delete the branch: `git checkout main && git branch -D fix/{number}-{slug}`
2. Report your complexity findings to the user in plain language.
3. Recommend using the `to-issues` skill to break the issue into smaller child issues.
4. **Stop. Do not write any code.**

If all thresholds pass, continue to Phase C.

---

## Phase C — TDD Implementation

Follow the `tdd` skill's red-green-refactor loop. Work through the acceptance criteria one at a time as vertical tracer bullets — not horizontal slices.

### For Julia code (core/)

```
For each acceptance criterion:
  RED:   Write one failing test in core/test/ that specifies the behavior
  GREEN: Write the minimal implementation to make it pass
  CHECK: pixi run test-ribasim-core   ← must stay green
  REFACTOR: improve without breaking tests; check with @code_warntype for type stability
```

### For Python code (python/, ribasim_qgis/)

```
For each acceptance criterion:
  RED:   Write one failing test that specifies the behavior
  GREEN: Write the minimal implementation to make it pass
  CHECK: pixi run test-ribasim-python   ← must stay green
  REFACTOR: improve without breaking tests
```

**Rules**
- All test names and interface vocabulary must match `CONTEXT.md` domain terms (Basin, Node, FlowBoundary, Outlet, TabulatedRatingCurve, etc.)
- Tests must exercise public interfaces only — never internal methods or private state
- For Julia: avoid allocations in hot paths; maintain type stability
- For Python: use Pydantic models for data structures; prefer pandas-style method chaining

**Run the test suite after every GREEN step.** If a previously passing test breaks, fix it before moving on.

---

## Phase D — Review Loop

Run this loop up to **3 times**, or until only MINOR issues remain — whichever comes first.

### Each iteration

#### 1. Language-specific code review

**For Python code:**
- PEP 8: line length ≤ 120 chars (per ruff.toml), 4-space indentation, two blank lines between top-level definitions
- Every public symbol has a complete type annotation
- Import order: stdlib → third-party → local, each group separated by a blank line
- Use Pydantic/Pandera models for data validation
- Pandas-style method chaining where appropriate
- No bare `except:` or `except Exception:` without re-raise

**For Julia code:**
- Follow Julia community conventions (lowercase functions, UpperCamelCase types)
- Use multiple dispatch effectively; avoid type-switch conditionals
- Prefer immutable structs with `@kwdef` for struct definitions with defaults
- Avoid allocations in simulation hot paths
- Check type stability with `@code_warntype` on critical functions
- Use meaningful variable names from the water resources domain

#### 2. SOLID audit

- **SRP**: each class/struct and function has one reason to change
- **OCP**: new behaviors added by extension (new type / multiple dispatch), not mutation
- **LSP**: subtypes are fully substitutable
- **ISP**: interfaces are thin — no fat protocols clients must partially implement
- **DIP**: depend on abstractions (Julia: abstract types; Python: protocols), not concrete implementations

#### 3. ADR compliance

Check all `.github/adr/*.md` files relevant to the changed area. Ensure no decision is contradicted.

#### 4. TDD validation

- Every changed or added behavior has at least one test
- Tests describe behavior ("Basin spills when storage exceeds capacity"), not implementation
- No test reaches into private attributes or internal methods
- For Julia: integration tests in `core/integration_test/`, regression tests in `core/regression_test/` where appropriate

#### 5. Full validation suite

**For Python changes:**
```bash
pixi run test-ribasim-python
```

**For Julia changes:**
```bash
pixi run test-ribasim-core
```

**For combined changes or quality checks:**
```bash
pixi run pre-commit-run  # runs ruff, mypy, and other configured checks
```

All commands must pass. Address any warnings or errors before proceeding.

#### 6. Classify findings

| Severity | Criteria | Must fix before PR? |
|---|---|---|
| CRITICAL | Correctness bug; security flaw; test suite failure; type instability in Julia hot paths | Yes |
| MAJOR | SOLID violation; ADR breach; missing type annotation on public Python symbol; allocations in Julia solver paths | Yes |
| MODERATE | Style violation; missing test for changed behavior; poor naming; non-idiomatic code | Yes |
| MINOR | Style preference; optional improvement; cosmetic | No — report in PR body |

#### 7. Fix and iterate

Fix every CRITICAL, MAJOR, and MODERATE finding. Then run the next iteration. After 3 iterations (or when only MINORs remain), exit the loop.

---

## Phase E — PR Submission

### 1. Single commit

```bash
git add -A
git commit -m "fix(#${number}): ${issue_title}"
```

One commit per issue. Do not squash or amend after this point.

### 2. Push

```bash
git push origin fix/${number}-${slug}
```

### 3. Create the pull request

```bash
gh pr create \
  --title "fix(#${number}): ${issue_title}" \
  --body "$(cat <<'PREOF'
## Summary

{One paragraph describing what was changed and why.}

## Changes

- {Bullet 1}
- {Bullet 2}

## Acceptance criteria

- [x] Criterion 1
- [ ] Criterion 2 (explain if unchecked)

Closes #{number}

## Remaining issues

{List any MINOR findings from the review loop, or write "None".}
PREOF
)"
```

> **If `gh` is not available**: use the `github-pull-request_create_pull_request` tool with equivalent title, body, and head branch fields. See `.github/agents/issue-tracker.md` for the full fallback table.

### 4. Report

Print the PR URL to the user and summarise what was done, what was left as MINOR, and any acceptance criteria that were not fully addressed.
