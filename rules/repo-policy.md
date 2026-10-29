# Repository Policy: One Platform, One Rule Set

Status: requirements, 2026-10-25. Applies to every repository that takes `setup-base`.

Format: each requirement has an ID, one sentence with a BCP 14 keyword (MUST, MUST NOT, SHOULD, MAY in capitals; lowercase carries no special meaning), and two attributes. "Check" is the enforcement level the rule aims at (0 context, 1 heuristic review, 2 harness hook, 3 harness permissions, 4 repository hook or CI, 5 operating system), as "current → target" where they differ; the level a given repository reaches, and any deviation, is recorded in that repository. "Since" is the date of the decision. IDs are never reused; an ID missing from the sequence belongs to a rule kept outside `setup-base`. Reasons and tests: [repo-policy.md](../rationale/repo-policy.md), under the requirement's ID.

## Platform

- **R-platform-01**: A repository's development environment MUST be a flake `devShell`, entered with direnv (`use flake`) or `nix develop`. Check: 0 → 4. Since: 2026-10-25.
- **R-platform-02**: Where a repository has CI, the CI MUST run its checks through the same flake (`nix develop --command …`). Check: 0 → 4. Since: 2026-10-25.
- **R-platform-03**: A repository MUST NOT be developed, built, tested or checked on anything but `x86_64-linux` with flakes: no other architecture (ARM included), no Nix without flakes, no Linux without Nix, no macOS or Windows, no dev containers, bare-host fallbacks or other environment managers. Check: 0. Since: 2026-10-25.
- **R-platform-04**: VMs and containers MAY be used when built on NixOS (NixOS VM tests, `nixos-rebuild build-vm`, NixOS containers, images built by Nix). Check: 0. Since: 2026-10-25.

## Scripts

- **R-shell-01**: A script MUST be written in bash 5, Python, or safe Rust (`#![forbid(unsafe_code)]`); it MUST NOT be zsh or POSIX `sh`. Check: 0 → 4. Since: 2026-10-25.
- **R-shell-02**: bash SHOULD be used only for short glue, Python for anything with real logic, Rust only where performance is needed. Check: 0 + 1. Since: 2026-10-25.
- **R-shell-03**: A bash script MUST set `set -euo pipefail` and MUST pass ShellCheck. Check: 0 → 4. Since: 2026-10-25.
- **R-shell-04**: A script MUST take its interpreter from nixpkgs (the `devShell`, `writeShellApplication` or a Nix-built shebang). Check: 0. Since: 2026-10-25.

## Git

- **R-git-07**: Every commit and every tag MUST carry a good signature of its author's key; a pre-push hook and `repo-check` refuse a commit or tag that does not, and a public repository SHOULD also require signed commits in a ruleset of its forge. Check: 0 → 4. Since: 2026-10-29.

## Rule set and deviations

- **R-rules-01**: Every repository MUST follow the shared rule set instead of its own habits. Check: 0 → 4. Since: 2026-10-20.
- **R-rules-02**: When a rule is chosen, it MUST be the one closest to the strongest applicable standard, ranked by the selection categories A (law) over B (official and industry standards) over C (de facto standards and customs) over D (specifications, soft law, good practice). Check: 0 + 1. Since: 2026-10-20.
- **R-rules-03**: A deviation from a rule MUST be decided explicitly by the owner after discussion, and MUST be recorded with the rule ID, what differs, the reason, the date and a decision link (an ADR or a decision note). Check: 0 → 4. Since: 2026-10-20; record form 2026-10-25.
