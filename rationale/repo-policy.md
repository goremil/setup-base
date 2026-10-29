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

## R-git-07

- A signature ties a commit or a tag to its author's key, so a forge account, a stolen push credential or a rewritten history cannot pass off a change as the author's. Git signs with `commit.gpgSign` and `tag.gpgSign`; the rule makes the missing signature a failure, not a warning.
- A forge alone cannot carry it everywhere: on GitHub Free, branch protection and rulesets on a private repository answer "Upgrade to GitHub Pro or make this repository public to enable this feature" (the API, 2026-10-29). So it is checked in the repository, the same in every one: the pre-push hook (`pre-push-check`, on the commits about to leave, with an unsquashed `fixup!` refused too) and `repo-check` (every commit reachable from `HEAD` and every tag, locally with the user's keyring, in CI with the owner's public keys from the forge, `<server>/<owner>.gpg`, or `REPO_CHECK_SIGNING_KEYS`). A ruleset of a public repository adds the forge's own refusal.
- `%G?` `U` passes: a good signature whose key has no trust set, which is what a freshly imported key is. A lightweight tag fails, because it has no signature to carry.
- Tests: `tests/default.nix` `signatures`, with a throwaway key (signed commits and tag pass, locally and in CI with keys from a local server; an unsigned commit, a lightweight tag, CI with no key source and an outgoing unsigned or `fixup!` commit fail), and the `faults` test, whose unsigned history must fail this check.

## R-rules-01 to R-rules-03

- R-rules-01: the rule core lives in `setup-base`, pinned by each repository as a flake input, so every repository reads the same version and a change arrives by a visible update.
- R-rules-02, the selection categories, strongest first:
  - A, law: mandatory for everyone; comply, it is a constraint, not a choice. A contract lifts B, C or D to A for its parties.
  - B, official and industry standards (ISO, EN, IETF, W3C, self-regulation one is a member of): rely on and cite with an exact reference.
  - C, de facto standards and customs of the ecosystem: follow unless there is a reason not to; deviating costs compatibility.
  - D, specifications, soft law, good practice: consider and decide deliberately.
  - Own rules (habits, team agreements, internal policy) sit outside the categories; a solution taken from C or D binds only once written into them, with its source.
- R-rules-03: the record form (rule ID, what differs, reason, date, decision link) is fixed so that a check can list every deviation of a repository.
