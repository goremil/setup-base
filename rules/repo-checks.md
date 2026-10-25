# Repository Checks: the Nix Model

Status: requirements, 2026-10-25. How a repository checks itself on the platform of [repo-policy.md](repo-policy.md) (R-platform-01 to R-platform-03). A repository may narrow this model but records it as a deviation (R-rules-03).

Format as in [repo-policy.md](repo-policy.md): ID, one sentence with a BCP 14 keyword, then Check (enforcement level, current → target) and Since. Reasons and tests: [repo-checks.md](../rationale/repo-checks.md), under the requirement's ID.

## Where checks run

- **R-check-01**: A repository's checks MUST run in its flake `devShell`, which provides their interpreter (scripts per R-shell-01 to R-shell-04). Check: 0 → 4. Since: 2026-10-25.
- **R-check-02**: Every tool a check uses MUST be listed once, in `flake.nix` (`devShells.default`, pinned by `flake.lock`). Check: 0 → 4. Since: 2026-10-25.
- **R-check-03**: Every entry point MUST reuse that shell: direnv (`use flake`) or `nix develop` locally, `nix develop --command …` in CI. Check: 0 → 4. Since: 2026-10-25.
- **R-check-04**: If a hook runs outside the `devShell`, it MUST enter it itself through `nix develop --command`; if that fails, the hook MUST fail and say which step failed, with its error, and what to do. A check MUST NOT be skipped because a tool is missing. Check: 0 → 4. Since: 2026-10-25.

## Layout

- **R-check-05**: One entry script MUST run every check and MUST keep going past a failure. Check: 0 → 4. Since: 2026-10-18.
- **R-check-06**: The hooks MUST live in the repository in `.githooks/`, tracked, enabled by `core.hooksPath`, which the `devShell`'s `shellHook` sets, so a clone needs no manual step. Check: 0 → 4. Since: 2026-10-18.
- **R-check-07**: Checks MUST take their files from git: tracked files plus untracked ones not ignored (`git ls-files --cached --others --exclude-standard`), without deleted files. Check: 0 → 4. Since: 2026-10-25.
- **R-check-08**: Caches MUST stay under `.git/` (e.g. `.git/check-cache/`) and MUST NOT be tracked. Check: 0. Since: 2026-10-18.
- **R-check-09**: A repository MUST store text with LF line endings, set by `.gitattributes` `* text=auto eol=lf`. Check: 0 → 4. Since: 2026-10-18.

## Report

- **R-check-10**: The entry script MUST report either the problems, grouped by check, or one line saying that all N checks passed; a skipped step MUST always be listed. Check: 0 → 4. Since: 2026-10-18.
- **R-check-11**: The entry script MUST print every check's output with `-v`, and CI MUST run it with `-v`. Check: 0 → 4. Since: 2026-10-18.

## Testing a change to the checks

- **R-check-12**: When a check is added or changed, it MUST be tested by fault injection: break one thing per check (on a scratch clone, or in place and `git checkout --` after) and confirm the check reports it. Check: 0 + 1. Since: 2026-10-18.
- **R-check-13**: When a check is rewritten, its output SHOULD be compared with the old check's output on the same faults. Check: 0 + 1. Since: 2026-10-18.
- **R-check-14**: A changed check MUST be run in the `devShell` with the same command as CI (`nix develop --command <entry script>`); a hook that must also work outside the shell (R-check-04) MUST also be tested from a plain `bash` without the shell's `PATH`. Check: 0 + 1. Since: 2026-10-25.
