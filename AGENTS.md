# AGENTS.md

Instructions for any agent, human or AI, working in this repository.

## What this repository is

The base layer of the configuration repositories (`setup-base`, `setup-home`, `setup-para`, `setup-agents`): the agent-agnostic rule core, the managed tooling and the Copier template for new repositories. See [README.md](README.md).

## Rules

- This repository is public. Nothing personal goes in: no names of hosts, people or private repositories, no paths into a user's home directory.
- Files are written in English in Oxford spelling (R-lang-04); drafts in another language (R-lang-10) do not belong in this public repository.
- A change to a managed part reaches every descendant on its next `nix flake update base`, so it is reviewed as a change to all of them.
- `nix develop --command repo-check` passes before a commit; a check that is added or changed gets a fault in `tests/` (R-check-12).

## Layout

| Path | Content |
| --- | --- |
| `rules/` | The rule core: requirements with IDs, one file per topic |
| `rationale/` | Reasons and tests behind each requirement, same file names as `rules/` |
| `copier.yml`, `template/` | The Copier template: questions, and the files of a new repository |
| `lib/` | `lib.mkRepo`: a descendant's dev shell, `formatter` and `checks` from the managed set |
| `markdownlint/` | The Markdown lint profiles, custom rules and their check; see its README |
| `tools/` | The managed check scripts: `repo-check.py` (every check, one report) and `commit-msg-check.sh` |
| `cspell.config.yaml`, `.cspell/` | Spell-check settings and word lists; the managed profile is imported from `template/.cspell/` |
| `tests/` | Fault injection for the check scripts, run by `nix flake check` |
| `flake.nix` | Outputs: `lib`, `packages` (the check scripts), dev shell, `formatter`, `checks`; this repository uses its own `lib.mkRepo` |
| `REUSE.toml`, `LICENSES/` | Licence of each path |
| `.forgejo/workflows/` | CI: `repo-check -v` in the dev shell on every push |

## Deviations

Departures from the rule core, one row each (R-rules-03). A deviation not listed here is a mistake, not a decision; `repo-check` checks each row and asks for the departures it can see.

| Rule | What differs | Reason | Since | Decision |
| --- | --- | --- | --- | --- |
