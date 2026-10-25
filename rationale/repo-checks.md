# Repository Checks: Reasons

Explanation for the requirements in [repo-checks.md](../rules/repo-checks.md), one section per requirement ID or group. Read on demand.

## History of the model

- 2026-10-18: first model, cross-platform: a portable Perl core, a dev container, a bare-host path, a Windows test matrix. R-check-05, 06 and 08 to 13 come from it unchanged in substance.
- 2026-10-25: revised to the single platform of [repo-policy.md](../rules/repo-policy.md) (R-platform-01 to R-platform-03). The cross-platform parts were dropped, and R-check-01 to 04 were written for the Nix-only model.

## R-check-01 to R-check-03

One place for tools, pinned by `flake.lock`: a local run and CI use the same versions, so a check never passes in one and fails in the other because of a tool version.

## R-check-04

A hook can run outside the `devShell`: a git GUI, an editor's commit button. Skipping a check there would let unchecked commits through without anyone noticing, so the hook either enters the shell or stops and says why.

## R-check-05 and R-check-06

One script that keeps going reports every problem in one run instead of one per attempt. Hooks tracked in the repository and enabled by the `shellHook` reach every clone without a manual step; `.git/hooks/` is not tracked.

## R-check-07

Changed 2026-10-25. Reading `git ls-files` alone means a new file needs `git add` before a check sees it, which forces staging before a commit is ready. Tracked plus untracked files that `.gitignore` does not exclude keeps build output and third-party sources out without staging.

## R-check-08 and R-check-09

- Caches under `.git/` are never tracked and never show in `git status`.
- LF regardless of a clone's `core.autocrlf`, so the content does not depend on the machine; `.editorconfig` covers only editors that read it.

## R-check-10 and R-check-11

A quiet report keeps an agent's context and the terminal short when everything passes; `-v` gives CI the full log to read after a failure.

## R-check-12 to R-check-14

A green run alone does not show that a check can fail. Fault injection does; comparing old and new output on the same faults shows a rewrite lost nothing. R-check-14 tests the path outside the shell, which an agent working inside the `devShell` would otherwise never exercise.
