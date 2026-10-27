# Text and Communication Conventions: Reasons, Tests and Tool Details

Explanation for the requirements in [conventions.md](../rules/conventions.md), one section per requirement ID or group. Read on demand.

## R-lang-01 to R-lang-09

- R-lang-06: the agent profile saves tokens without losing context. The forge and hybrid profiles relax it (R-media-02).
- R-lang-09: inline code marks a name unambiguously as an identifier for agents and keeps prose checks (MD044, cspell's prose rules) off it.

## R-media-01 to R-media-03

- The agent profile is the common base; forge and hybrid each extend it, differently: a forge does not render Obsidian callouts the same way, Obsidian does not render forge HTML.
- What both forges render was checked on 2026-10-24.
- R-media-03: agents read the cheap source; HTML presents, it does not store.

## R-md-01 to R-md-06

- R-md-01: `**bold**` and `_italic_` are Prettier's default output. markdownlint's default (`consistent`) accepts either per file; MD049 `underscore` and MD050 `asterisk` enforce it across files.
- R-md-02: the compact style is GFM spec example 198. `markdownlint-cli2 --fix` applies it. Caution: `--fix` also applies MD044 and rewrites lowercase identifiers outside backticks (paths, package names); put them in backticks first or fix with MD044 off, and review the diff.
- R-md-05, no `extends` in repositories: an absolute path breaks in another clone, and a relative one outside the repository breaks on the forge and in CI. Until 2026-10-25 each repository carried a flattened copy, seeded and watched by a drift report; the owner then chose managed profiles: `lib.mkRepo` builds the config from `markdownlint/` and the dev shell links it into the repository, gitignored. The store path is pinned by `flake.lock`, so the link resolves the same in every clone and in CI, which keeps the reason against `extends`. Without the dev shell a repository has no lint config; direnv enters it on the first `cd`.
- R-md-06: linters configure per directory, not per file, and inline disable comments are noise. `AGENTS.md` at a repository root falls under the forge profile, which is fine because it is a thin pointer and the agent content lives in `.agents/`.
- Tested facts (markdownlint-cli2 0.23.3, 2026-10-24): without `--config`, a directory's own config replaces the parent's, with no merge; `extends` inherits and lets local settings win. With a `.markdownlint-cli2.jsonc` given as `--config`, a directory's `.markdownlint-cli2.jsonc` is merged over it key by key, so turning rules off needs each key by name; a plain `.markdownlint.jsonc` replaced the base. `markdownlint-cli2` looks for config only from the folder it runs in downwards, and with a `--config` base it resolves a folder config's relative `customRules` against the base's folder.
- Built-in rules cover only part of R-lang-06: HTML (MD033), table padding (MD060), hard wraps (MD013, off). Callouts, emoji, decorative rules and heavy emphasis need custom rules; whether context is kept stays a human or agent judgement.

## R-link-01 to R-link-12

- R-link-01 to 05: one convention for agents, the VSCodium preview, GitHub, Codeberg, Obsidian and a web UI. Wiki-links are a non-standard extension. A space in a file name needs `%20` or `<…>`. GitHub, Obsidian and VSCodium disagree on what the root of an absolute path is.
- R-link-04, checked 2026-10-24: no anchor form resolves on both sides. GitHub and VSCodium use the slug; Obsidian expects the heading text URL-encoded (`#My%20section`) and does not resolve slugs (open feature request since 2022-01-11).
- R-link-05: a public repository is read by people who have none of the author's other files.
- R-link-08, tested 2026-10-25 with markdownlint-cli2 0.23.3 and cspell: MD044 checks the visible link text, never the URL, and cannot exempt links, so `[nixos.org](…)` or `[vscodium.nix](…)` fail; cspell flags unknown words in plain link text. Both skip code spans. Rendering, checked the same day: Obsidian and the built-in VSCodium preview show a code-text link as a link; Markdown Preview Enhanced styles it as plain code unless a style rule (`a code`) gives it the link colour. GitHub and Codeberg were not checked.
- R-link-10: GitHub opens folder links. Checked 2026-10-27 for a folder outside the repository: the built-in VSCodium preview reveals it in the sidebar, Markdown Preview Enhanced shows a link that does nothing, Obsidian fails with `EACCES`.
- R-link-12, tool settings: lychee (offline by default, online on demand); VSCodium `markdown.validate.enabled` and `markdown.updateLinksOnFileMove.enabled`; Obsidian with `Use [[Wikilinks]]` off, "New link format" relative path, "Automatically update internal links" on; MD051 for anchors.

## R-link-15

- CommonMark gives a link one destination, so no single link falls back from a local file to its remote copy. Two links, the remote one first, keep the name clickable everywhere and add the local one where it works.
- Checked 2026-10-27, a link out of a vault to a file in another checkout: the VSCodium editor follows every form; its built-in preview and Markdown Preview Enhanced follow a relative path but not `file://`; Obsidian (1.14.5) fails on a relative path with `EACCES`, opens `file://` in the system's default application, and opens `https://` in the browser. The remote link is the only form that works in all of them.
- `file://` and absolute paths tie a note to one user name and one machine (R-link-03).
- CI has no home directory, so a local path alone cannot be checked there; the remote half of a pair gives it something to check. A place with no remote is marked as local-only by its form, so skipping it in CI is the author's statement, not an accident.
- The word `local` as link text reads without a legend.

## R-index-01 to R-index-06

- An `INDEX.md` is a router for agents, not a copy of `ls`: agents list a folder anyway.
- R-index-04: an index that repeats a status goes stale.
- R-index-05: forges show a `README.md` when browsing a folder; two lists would compete.
