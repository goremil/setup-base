# AGENTS.md

Instructions for any agent, human or AI, working in this repository.

## What this repository is

The base layer of the configuration repositories (`setup-base`, `setup-home`,
`setup-para`, `setup-agents`): the agent-agnostic rule core, the managed
tooling and the Copier template for new repositories. See
[README.md](README.md).

## Rules

- This repository is public. Nothing personal goes in: no names of hosts,
  people or private repositories, no paths into a user's home directory.
- Files are written in English with `-ize` spelling.
- A change to a managed part reaches every descendant on its next
  `nix flake update base`, so it is reviewed as a change to all of them.
- `nix flake check` passes before a commit.

## Layout

| Path | Content |
| --- | --- |
| `rules/` | The rule core: requirements with IDs, one file per topic |
| `rationale/` | Reasons and tests behind each requirement, same file names as `rules/` |
| `flake.nix` | Outputs: dev shell, `formatter`, `checks` |
| `REUSE.toml`, `LICENSES/` | Licence of each path |
| `.forgejo/workflows/` | CI: `nix flake check` on every push |
