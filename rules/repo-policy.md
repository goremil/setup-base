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

## Paths

Files older than these requirements are brought into line by a migration per repository, not only when they are edited.

- **R-path-01**: Code MUST take a location the platform provides from where the platform provides it, never from an assumed default: the XDG base directories (`$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`, `$XDG_STATE_HOME`, `$XDG_CACHE_HOME`, `$XDG_RUNTIME_DIR`, with the specification's fallbacks), `$HOME`, `$TMPDIR`, the directories systemd hands a service (`$STATE_DIRECTORY`, `$RUNTIME_DIRECTORY`, `$CREDENTIALS_DIRECTORY`), programs from `PATH`, and in Nix a package's store path. Check: 0 + 1 → 4. Since: 2026-11-01.
- **R-path-02**: A location specific to a user or a host (a notes vault, a folder of clones) MUST be a setting with a documented default, never a literal in code. Check: 0 + 1 → 4. Since: 2026-11-01.
- **R-path-03**: A repository that is the configuration of one host or one user MAY name that host's or user's locations, since they are its content; it SHOULD still take them from the sources of R-path-01 where one exists, and set each once (R-path-04). Check: 0 + 1. Since: 2026-11-01.
- **R-path-04**: The owner of a location others may need MUST set it in exactly one place and expose it at run time through at least an environment variable and a configuration file (an XDG user directory counts as one); in Nix the place is a module option, and the module writes the variable and the file from it. Check: 0 + 1. Since: 2026-11-01.
- **R-path-05**: A consumer MUST resolve a location in the order command-line flag, environment variable, configuration file, default, and MUST NOT repeat its value; Nix code MUST read the owner's option directly. Check: 0 + 1. Since: 2026-11-01.
- **R-path-06**: Prose MAY name a default location to explain it, with its source at the first mention ("the vault, `$XDG_KNOWLEDGE_DIR`, here `~/Knowledge`"); a command given in prose MUST resolve the location rather than copy it. Check: 0 + 1. Since: 2026-11-01.

## Localization

Files older than these requirements are brought into line by a migration per repository, not only when they are edited.

- **R-l10n-01**: Everything a program presents to a person MUST be translatable: interface text (GUI, TUI, prompts), help text, and the error and status messages a person reads; English is the source, passed through the language's standard message catalogue (GNU `gettext` where one exists). Check: 0 + 1 → 4. Since: 2026-11-01.
- **R-l10n-02**: Option and subcommand names, configuration keys, identifiers, machine-readable output (JSON, `--porcelain`-style formats, exit codes) and log messages MUST NOT be translated; the English of every message MUST be reachable with `LC_ALL=C`. Check: 0 + 1. Since: 2026-11-01.
- **R-l10n-03**: Documentation MUST stay translatable from its English source with a catalogue tool (`po4a`), so a translation is added as a `.po` file without changing the source. Check: 0 → 4. Since: 2026-11-01.
- **R-l10n-04**: A repository MUST ship the mechanism and a message template (`.pot`) generated from its source and kept current, not translations of its own; translations come from contributors, and the repository's own text stays in English (R-lang-04). Check: 0 → 4. Since: 2026-11-01.
- **R-l10n-05**: Human output SHOULD format dates and numbers by the locale; files keep ISO 8601 (R-lang-08). Check: 0 + 1. Since: 2026-11-01.

## Git

- **R-git-07**: Every commit and every tag MUST carry a good signature of its author's key; a pre-push hook and `repo-check` refuse a commit or tag that does not, and a public repository SHOULD also require signed commits in a ruleset of its forge. Check: 0 → 4. Since: 2026-10-29.

- **R-git-08**: A repository that tags releases (`vX.Y.Z`) MUST keep a `CHANGELOG.md` with a section per release tag, generated by git-cliff with the managed configuration (`changelog --tag vX.Y.Z -o CHANGELOG.md`, committed before the tag is made). Check: 4 (`repo-check`, "changelog covers each release tag"). Since: 2026-10-30.

## Rule set and deviations

- **R-rules-01**: Every repository MUST follow the shared rule set instead of its own habits. Check: 0 → 4. Since: 2026-10-20.
- **R-rules-02**: When a rule is chosen, it MUST be the one closest to the strongest applicable standard, ranked by the selection categories A (law) over B (official and industry standards) over C (de facto standards and customs) over D (specifications, soft law, good practice). Check: 0 + 1. Since: 2026-10-20.
- **R-rules-03**: A deviation from a rule MUST be decided explicitly by the owner after discussion, and MUST be recorded with the rule ID, what differs, the reason, the date and a decision link (an ADR or a decision note). Check: 0 → 4. Since: 2026-10-20; record form 2026-10-25.
