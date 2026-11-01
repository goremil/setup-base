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

## R-path-01 to R-path-06

- Goal: a location changes in one entry, not by a search through one repository or several. On 2026-11-01 the vault path `~/Knowledge` was written out 86 times in 41 files of 5 repositories, while `setup-home` already set it once as the XDG user directory `KNOWLEDGE` (`xdg-user-dir KNOWLEDGE`); nothing read it from there.
- NixOS moves paths that other systems keep fixed: there is no `/usr/bin`, programs live in the store and are reached through `PATH` or `/run/current-system`. A path assumed rather than asked for breaks there first (R-path-01).
- A Nix module option exists only while Nix evaluates; a running program never sees it. So the option is the one place a location is set, and the module writes it out to the channels a program reads (R-path-04): an environment variable for any process, a configuration file for one that did not inherit the variable. home-manager's `home.sessionVariables` are set at login (its option description), so a process not started from that session may lack them; `xdg.userDirs.setSessionVariables` defaults to `false` from `home.stateVersion` 26.05 (home-manager news 2026-02-04), which is why `XDG_KNOWLEDGE_DIR` was missing from the environment while `user-dirs.dirs` had it.
- The order of R-path-05 (flag, variable, file, default) is the usual one of command-line tools: the narrowest, most explicit setting wins.
- R-path-03: the configuration of one host or user is where its locations are named, so naming them there is no fault; the rule still asks for one place per location there.
- R-path-06: replacing every path in prose with a variable makes rules and notes hard to read; one mention with its source keeps both.

## R-l10n-01 to R-l10n-05

- Translations are not made here; the mechanism is, so that anyone may add a language without touching the code. A message added outside the catalogue is lost to translators, and finding it later costs more than routing it through the catalogue when it is written.
- The line between translated and not follows established practice, checked 2026-11-01 under `LANGUAGE=pl LC_ALL=pl_PL.UTF-8`: git 2.56 prints "fatal: not a git repository" in Polish, glibc its error texts and the sentence around an unknown option, while the option name (`--bogus`) stays as typed; systemd 262 ships catalogues for the texts a person sees in its polkit prompts, while its log messages stay English. Logs, identifiers and machine output stay English because scripts, searches and bug reports rely on them (R-l10n-02).
- R-l10n-03: `po4a` (nixpkgs 0.74) keeps the English document as the only source and translations as `.po` files beside it. How it handles this rule set's Markdown (tables, GitHub-flavoured extensions) is not checked yet.
- R-l10n-04: a `.pot` that is generated and checked shows a translator what changed and catches a message that bypassed the catalogue.

## R-git-07

- A signature ties a commit or a tag to its author's key, so a forge account, a stolen push credential or a rewritten history cannot pass off a change as the author's. Git signs with `commit.gpgSign` and `tag.gpgSign`; the rule makes the missing signature a failure, not a warning.
- A forge alone cannot carry it everywhere: on GitHub Free, branch protection and rulesets on a private repository answer "Upgrade to GitHub Pro or make this repository public to enable this feature" (the API, 2026-10-29). So it is checked in the repository, the same in every one: the pre-push hook (`pre-push-check`, on the commits about to leave, with an unsquashed `fixup!` refused too) and `repo-check` (every commit reachable from `HEAD` and every tag, locally with the user's keyring, in CI with the owner's public keys from the forge, `<server>/<owner>.gpg`, or `REPO_CHECK_SIGNING_KEYS`). A ruleset of a public repository adds the forge's own refusal.
- `%G?` `U` passes: a good signature whose key has no trust set, which is what a freshly imported key is. A lightweight tag fails, because it has no signature to carry.
- Tests: `tests/default.nix` `signatures`, with a throwaway key (signed commits and tag pass, locally and in CI with keys from a local server; an unsigned commit, a lightweight tag, CI with no key source and an outgoing unsigned or `fixup!` commit fail), and the `faults` test, whose unsigned history must fail this check.
- Updates stay signed (decided 2026-10-30): Dependabot and Renovate commit with the forge's own key, which CI's keyring rightly lacks; trusting that key would let a taken-over account pass off changes again. `pin-actions` moves the workflows' actions to their latest release by commit and a host's weekly report names what is behind, so the updates are made locally and signed. `forge-ruleset` keeps the public repositories' ruleset (`tools/ruleset.json`) as code; GitHub Free has no rulesets for a private repository (403), where the hooks and CI carry the rule.

## R-git-08

- The commit subjects are already Conventional Commits (commit-msg-check), so the changelog is a projection of history, not a second text to keep in step. git-cliff 2.13 reads them; the managed configuration (`tools/cliff.toml`) writes plain forge Markdown: its default template uses emoji (`no-emoji`) and reference links.
- The check asks only that each release tag has a section: comparing the whole file with fresh output would fail on the commit that adds the section for a tag not made yet. Maintenance types are left out, as a reader of a release asks what changed for them.
- Tests: `tests/default.nix` `repo-check-faults` (a tag without a section).

## R-rules-01 to R-rules-03

- R-rules-01: the rule core lives in `setup-base`, pinned by each repository as a flake input, so every repository reads the same version and a change arrives by a visible update.
- R-rules-02, the selection categories, strongest first:
    - A, law: mandatory for everyone; comply, it is a constraint, not a choice. A contract lifts B, C or D to A for its parties.
    - B, official and industry standards (ISO, EN, IETF, W3C, self-regulation one is a member of): rely on and cite with an exact reference.
    - C, de facto standards and customs of the ecosystem: follow unless there is a reason not to; deviating costs compatibility.
    - D, specifications, soft law, good practice: consider and decide deliberately.
    - Own rules (habits, team agreements, internal policy) sit outside the categories; a solution taken from C or D binds only once written into them, with its source.
- R-rules-03: the record form (rule ID, what differs, reason, date, decision link) is fixed so that a check can list every deviation of a repository.
