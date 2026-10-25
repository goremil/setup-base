# setup-base

Shared base for repositories and agent setups: a rule core written as
requirements, the tooling every repository uses, and a template that seeds new
repositories.

Status: being built. The parts below arrive one at a time.

## What it provides

| Part | Kind | How a repository gets it |
| --- | --- | --- |
| Rule core (`rules/`) | managed | read in place, or pinned as a flake input |
| Checks, hooks, lint configurations, `formatter` | managed | flake outputs, pinned in the descendant's `flake.lock` |
| Repository skeleton (`template/`) | seeded | [Copier](https://copier.readthedocs.io): `copier copy` once, `copier update` later |

Managed parts are the same in every repository and are not edited there; a
change arrives with `nix flake update base`. Seeded parts are copied once and
then owned by the repository. A repository that departs from a rule records the
deviation in its own `AGENTS.md`.

## Development

```sh
nix develop          # tools: reuse, nixfmt, markdownlint-cli2, copier
nix flake check      # what CI runs
nix fmt              # format Nix files
```

## Licence

Code and build definitions are under MIT, documentation and rules under
CC-BY-4.0; `REUSE.toml` maps each path to its licence, and `reuse lint` checks
it.
