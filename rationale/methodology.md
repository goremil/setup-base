# Problem-Solving Methodology: Reasons

Explanation for the requirements in [methodology.md](../rules/methodology.md), one section per requirement ID or group. Read on demand.

## R-evidence-01 to R-evidence-07

- R-evidence-01: the order (run, read the source, read the docs) goes from the most to the least direct evidence of what the tool actually does.
- R-evidence-05: the ranking measures how far a source can be trusted as evidence for a claim. It is a separate question from which rule to follow ([repo-policy.md](../rules/repo-policy.md) R-rules-02, the selection categories A–D).
- R-evidence-07 (user, 2026-10-26): R-evidence-01 covers single facts; this rule covers what the user decides on. A flagged guess inside a plan still shifts the checking to the user, who decides on the plan as a whole; asking instead makes the gap visible where the decision is taken. R-evidence-06 is personal and lives in the user's own repository.

## R-determinism-01 to R-determinism-04

- A deterministic result can be repeated and checked; a heuristic one (a model's judgement) cannot, so heuristics are bracketed by deterministic validation of their input (correctness, security, data sensitivity) and output.
- R-determinism-04: memory is context, not enforcement; a check that a hook or CI runs holds whoever does the work. Checks prone to false positives train people to ignore failures, so they are not added.

## R-structure-01 to R-structure-05

- R-structure-01: one source of truth stops copies from drifting apart.
- R-structure-03: a project mirrors the global layer so that agents find project rules where they expect them. The template does not seed `.agents/`: an empty `INDEX.md` would break R-index-03 (decided 2026-10-29).
- R-structure-04: no reason was recorded with the decision.

## R-consent-01 to R-consent-04

- R-consent-02: a structural choice is hard to undo once other work builds on it, so the user chooses from a comparison, not from a finished change.
- R-consent-01 and 03 are backed where the harness allows it: `ask` rules for paths whose change needs confirmation, `deny` rules for key material and shell history. Path rules cover only the harness's own file tools, not every command that could touch the same path.
- R-consent-04: a probe that sends a valid body, or calls an endpoint that changes state by itself, changes data whenever the token turns out to have the permission, which is exactly the case a probe cannot rule out in advance. Forgejo checks token scopes before it validates the body (observed 2026-10-25 with `{}` bodies), so an invalid body still answers the question: a refusal names the missing scope, while a 422 means the scope exists and nothing was created.

## R-list-01

Working point by point keeps each decision small and reviewable. It is a procedure, so it is meant to become a skill; the requirement stays as the rule the skill implements.
