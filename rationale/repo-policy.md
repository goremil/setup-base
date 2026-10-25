# Repository Policy: Reasons

Explanation for the requirements in [repo-policy.md](../rules/repo-policy.md), one section per requirement ID or group. Read on demand, when a rule is questioned or changed; the requirements file alone is enough to follow the rules.

## Goal of the whole policy

The same way of working across projects, picked from recognized standards, with deliberate, documented deviations.

## R-platform-01 to R-platform-04

- One stack, nothing else supported, tested or designed for. A second platform doubles the matrix of what can break, and a fallback that nobody runs rots unnoticed.
- R-platform-03 binds how a repository is developed, not who may use what it ships: a public product may target other platforms, recorded as a deviation with its reason.

## R-shell-01 to R-shell-04

- Interactive shells and script languages are separate choices: a user may type in any shell, scripts are bash 5.
- Why not zsh for scripts (checked 2026-10-25): ShellCheck refuses zsh (`SC1071`); `zsh -n` and `shfmt -ln zsh` check only syntax and layout. A test script with a typo in a variable name and `[ $f == x ]` passed both; ShellCheck found 5 problems in the bash twin, the typo included, while the zsh twin failed only at run time (`= not found`, a zsh-only pitfall). nixpkgs `writers` has no zsh writer, so there is no build-time check either. And Nix itself is bash: every `shellHook`, `runCommand` and build phase, and CI `run:` steps.
- R-shell-04: since every script pins its interpreter from nixpkgs, no compatibility with POSIX `sh` or older bash is kept; bash 5 features (arrays, `[[ ]]`, `mapfile`) are fine.

## R-rules-01 to R-rules-03

- R-rules-01: the rule core lives in `setup-base`, pinned by each repository as a flake input, so every repository reads the same version and a change arrives by a visible update.
- R-rules-02, the selection categories, strongest first:
  - A, law: mandatory for everyone; comply, it is a constraint, not a choice. A contract lifts B, C or D to A for its parties.
  - B, official and industry standards (ISO, EN, IETF, W3C, self-regulation one is a member of): rely on and cite with an exact reference.
  - C, de facto standards and customs of the ecosystem: follow unless there is a reason not to; deviating costs compatibility.
  - D, specifications, soft law, good practice: consider and decide deliberately.
  - Own rules (habits, team agreements, internal policy) sit outside the categories; a solution taken from C or D binds only once written into them, with its source.
- R-rules-03: the record form (rule ID, what differs, reason, date, decision link) is fixed so that a check can list every deviation of a repository.
