# setup-base

Shared base for repositories and agent setups: a rule core written as requirements, the tooling every repository uses, and a template that seeds new repositories.

Status: being built. The parts below arrive one at a time.

## What it provides

| Part | Kind | How a repository gets it |
| --- | --- | --- |
| Rule core (`rules/`) | managed | read in place, or pinned as a flake input |
| Checks, hooks, lint profiles (`markdownlint/`), `formatter` | managed | flake outputs, pinned in the descendant's `flake.lock` |
| Repository skeleton (`template/`) | seeded | [Copier](https://copier.readthedocs.io): `copier copy` once, `copier update` later |

Managed parts are the same in every repository and are not edited there; a change arrives with `nix flake update base`. Seeded parts are copied once and then owned by the repository. A repository that departs from a rule records the deviation in its own `AGENTS.md`.

## Tool profiles

Every dev shell has the core: git, GnuPG, gitleaks, Python (for `repo-check`), nixfmt, statix, deadnix, cspell, markdownlint, lychee, yamllint and ShellCheck (every repository has bash hooks). The rest comes in profiles, so a repository fetches only what it checks:

| Profile | Tools | Switched on by |
| --- | --- | --- |
| `rust` | cargo, rustc, clippy, rustfmt, cargo-deny, rust-analyzer | `Cargo.toml` |
| `reuse` | reuse | `REUSE.toml` |
| `github-actions` | actionlint, zizmor | `.github/workflows/` |
| `changelog` | `changelog` (git-cliff with the managed `tools/cliff.toml`) | `CHANGELOG.md` |
| `python` | ruff, mypy | `features = [ "python" ]` in `lib.mkRepo` |

A profile without a marker file is named, since finding a `.py` file would walk the whole tree on every evaluation. `repo-check` fails the checks of a profile that is off while its files are there, so a missing tool is never a check skipped in silence. The template asks for the named profiles.

## A new repository from the template

```sh
nix shell nixpkgs#copier -c copier copy \
  https://github.com/goremil/setup-base.git <new-repo>
cd <new-repo> && git init && git add -A
nix develop --command repo-check   # entering the shell enables the hooks
```

Give the forge URL, not a local clone: `.copier-answers.yml` records the source, and a local path would end up in the repository. The questions: `project_name`, `description`, `visibility` (`private` or `public`; public repositories get REUSE licensing and its check), `network_service` (public only: AGPL-3.0-only instead of GPL-3.0-only for the code), `forge` (`github`, the default, or `codeberg`, for the CI workflow), `forge_owner` (public only) and `features` (the named tool profiles above). Later template versions arrive with `copier update` from inside the repository. Copier takes the latest release tag (`v0.1.0` and later) unless `--vcs-ref` names another.

## Development

```sh
nix develop               # every check tool, plus copier
repo-check                # every check, one report; -v for each check's output
nix flake check           # the flake checks and the fault-injection tests
nix fmt                   # treefmt: nixfmt, shfmt, and ruff with the python profile
```

A release: `changelog --tag vX.Y.Z -o CHANGELOG.md`, commit it as `chore(release): vX.Y.Z`, then `git tag -s vX.Y.Z` (R-git-08, R-git-07).

## Licence

Code and build definitions are under GPL-3.0-only, documentation and rules under CC-BY-SA-4.0; the template (`template/`), whose files are copied into other repositories, is under 0BSD, so a copy carries no conditions. `REUSE.toml` maps each path to its licence, and `reuse lint` checks it.
