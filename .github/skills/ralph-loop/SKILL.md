---
name: ralph-loop
description: Autonomously fix open GitHub issues one at a time using fresh-context subagents. Loops until no eligible issues remain, a fix-issue invocation is halted by the complexity gate or an error, or a HITL checkpoint is encountered. AFK-safe: no human input required during the loop. Use when asked to "run the ralph loop", work through all open issues, or fix issues autonomously.
user-invocable: false
---

# Ralph Loop

Orchestrate repeated fix-issue runs — one issue per fresh-context subagent — until a stopping condition is met.

**AFK contract**: this skill requires no human input during execution. The fix-issue Phase A step 4 HITL confirmation is pre-approved by the user invoking this skill. If any other HITL checkpoint is reached inside fix-issue, the loop halts and reports to the user.

**Fresh context contract**: each issue is handled by an isolated subagent. The orchestrating agent (you, running this skill) never reads source files, writes code, or runs tests. It only manages the queue and delegates. This prevents context pollution across a long session.

---

## Phase 0 — Build the candidate pool

Fetch all open AFK candidates once, at the start of the session:

```bash
gh issue list --label ready-for-agent --state open \
  --json number,title,body,labels \
  --jq '[.[] | {number, title, body, labels: [.labels[].name]}]'
```

> **If `gh` is not available**: use the `github-pull-request_doSearch` tool with query `is:issue is:open label:ready-for-agent repo:owner/name`. Always include the `repo:` qualifier — the tool searches all repos by default. See `.github/agents/issue-tracker.md` for the full fallback table.

All issues returned by this query are AFK by definition — `ready-for-agent` means AFK (see `.github/agents/triage-labels.md`). No further type filtering is needed.

Sort candidates by issue number, ascending. This is the **candidate pool**.

Do **not** check blockers yet — that happens dynamically inside the loop, so newly unblocked issues are discovered after each fix.

Initialise two session-level sets:
- `resolved_this_session`: issue numbers for which a PR was created in this loop run (initially empty)
- `attempted`: issue numbers already processed in this run (initially empty)

If the candidate pool is empty, output:

```
Ralph Loop: no eligible AFK issues found. Nothing to do.
```

and stop.

---

## Phase 1 — Loop

Repeat until a stopping condition is met:

### Step 0 — Select next eligible issue

From the candidate pool, exclude all issues in `attempted`. For each remaining candidate (in ascending number order), check whether it is unblocked:

Parse the `## Blocked by` section. For every blocker issue number listed (e.g. `#12`):
1. First check: is `12` in `resolved_this_session`? If yes, treat it as resolved without a network call.
2. Otherwise run:

```bash
gh issue view 12 --json state --jq '.state'
```

> **If `gh` is not available**: use `github-pull-request_issue_fetch` with `issueNumber: 12`; check the `.state` field of the returned object.

The candidate is **eligible** if every blocker is in `resolved_this_session` OR returns `CLOSED` (or the section reads "None — can start immediately").

Pick the lowest-numbered eligible candidate.

- If no candidates remain in the pool (excluding `attempted`): proceed to Phase 2 with halt reason `QUEUE_EXHAUSTED`.
- If candidates remain but none are eligible (all are still blocked): proceed to Phase 2 with halt reason `ALL_BLOCKED`.

### Step 1 — Spawn a fresh-context subagent

Invoke a subagent using the `runSubagent` tool with `model: "Claude Sonnet 4.5 (copilot)"`. Pass it the following prompt, substituting `{number}` and `{title}`:

> Read the fix-issue skill at `.github/skills/fix-issue/SKILL.md` in full, then execute it for issue #{number} ("{title}").
>
> **Skip Phase A entirely.** The Ralph loop orchestrator has already selected this issue, confirmed it is AFK type, and verified it has no open blockers. Begin at Phase B (branch creation).
>
> Complete all remaining phases (B through E) and return a structured result with these fields:
> - outcome: one of `PR_CREATED`, `COMPLEXITY_GATE`, `ERROR`, `HITL_REQUIRED`
> - pr_url: the pull request URL (if outcome is PR_CREATED), otherwise null
> - detail: a one-paragraph plain-language summary of what happened

### Step 2 — Evaluate the result

Add `{number}` to `attempted` regardless of outcome.

| Subagent outcome | Loop action |
|---|---|
| `PR_CREATED` | Add `{number}` to `resolved_this_session`; log the PR URL; return to Step 0 |
| `COMPLEXITY_GATE` | Proceed to Phase 2 with halt reason `COMPLEXITY_GATE` |
| `ERROR` | Proceed to Phase 2 with halt reason `ERROR` |
| `HITL_REQUIRED` | Proceed to Phase 2 with halt reason `HITL_REQUIRED` |

---

## Phase 2 — End-of-loop report

After the loop ends for any reason, output this summary to the user:

```
Ralph Loop Summary
==================
Issues attempted : {N}
PRs created      : {list of PR URLs, one per line, or "none"}
Stopped because  : {reason — see table below}
```

| Halt reason | Message |
|---|---|
| `QUEUE_EXHAUSTED` | "All eligible issues processed — nothing more to do." |
| `ALL_BLOCKED` | "Remaining candidates are still blocked. PRs may need to be merged before they can proceed." |
| `COMPLEXITY_GATE` | "Issue #{number} exceeded the complexity gate. Run the `to-issues` skill to break it into smaller child issues." |
| `ERROR` | "An unrecoverable error occurred on issue #{number}. Detail: {subagent detail field}" |
| `HITL_REQUIRED` | "Issue #{number} requires human input. Detail: {subagent detail field}" |

---

Do not attempt to retry a failed iteration. Proceed to Phase 2 and stop.
