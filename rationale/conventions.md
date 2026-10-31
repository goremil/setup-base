# Text and Communication Conventions: Reasons, Tests and Tool Details

Explanation for the requirements in [conventions.md](../rules/conventions.md), one section per requirement ID or group. Read on demand.

## R-lang-01 to R-lang-10

- R-lang-01: the Unicode Standard 16.0 (section 2.6) does not require a byte-order mark for UTF-8 and recommends neither for nor against one; the rule refuses it because tools that read the first bytes (a shebang, `jq`, Nix) break on one, and no file had one when the check arrived (2026-10-29). A file is text unless it has a NUL byte or `.gitattributes` marks it `-text` or `binary`, the way git decides.
- R-lang-04: Oxford spelling is the closest a written standard comes to international English: the United Nations spells by the Oxford Dictionary in its British setting, and `-ize` is shared with US spelling. cspell's `en-GB` accepts both `-ize` and `-ise`, so the managed profile (`template/.cspell/oxford.yaml`) forbids the `-ise` forms by list (`oxford-ize.txt`). Two gaps, checked 2026-10-27 with cspell: in Markdown the `html` dictionary accepts `color`, which the `-ize` check of `repo-check` covers in prose; Nix spells some flags and options with `-ise` (`--realise`, `auto-optimise-store`), so the profile skips the forbidden forms inside hyphenated tokens.
- R-lang-10: an author whose first language is not English writes a complex thought better in it first. The suffix lets cspell switch language by file name (an `overrides` entry); the dictionary is the npm package `@cspell/dict-pl_pl`, fetched by `lib.cspellDictionaries` and imported by `repo-check` in a config of its own, since a missing import fails cspell outright and an editor outside the dev shell would lose the whole repository's check. A public repository is published as it is, so a draft has no place there.
- R-lang-06: the agent profile saves tokens without losing context. The forge and hybrid profiles relax it (R-media-02).
- R-lang-09: inline code marks a name unambiguously as an identifier for agents and keeps prose checks (MD044, cspell's prose rules) off it.

## R-media-01 to R-media-03

- The agent profile is the common base; forge and hybrid each extend it, differently: a forge does not render Obsidian callouts the same way, Obsidian does not render forge HTML.
- What both forges render was checked on 2026-10-24.
- R-media-03: agents read the cheap source; HTML presents, it does not store.

## R-md-01 to R-md-07

- R-md-03, no Markdown formatter (tested 2026-10-29): mdformat 1.0 with mdformat-gfm, `--wrap no --compact-tables`, would join hard-wrapped lines, but it also folds a callout or alert (`> [!Note]` and its lines) into one line, writes the table delimiter as `| -- |` (R-md-02), turns `---` rules into underscores and renumbers ordered lists as `1.`; Prettier 3.8 pads table columns with no option against it (R-md-02). markdownlint, with `--fix` for its fixable rules, stays the only Markdown tool.
- R-md-01: `**bold**` and `_italic_` are Prettier's default output. markdownlint's default (`consistent`) accepts either per file; MD049 `underscore` and MD050 `asterisk` enforce it across files.
- R-md-02: the compact style is GFM spec example 198. `markdownlint-cli2 --fix` applies it. Caution: `--fix` also applies MD044 and rewrites lowercase identifiers outside backticks (paths, package names); put them in backticks first or fix with MD044 off, and review the diff.
- R-md-05, no `extends` in repositories: an absolute path breaks in another clone, and a relative one outside the repository breaks on the forge and in CI. Until 2026-10-25 each repository carried a flattened copy, seeded and watched by a drift report; the owner then chose managed profiles: `lib.mkRepo` builds the config from `markdownlint/` and the dev shell links it into the repository, gitignored. The store path is pinned by `flake.lock`, so the link resolves the same in every clone and in CI, which keeps the reason against `extends`. Without the dev shell a repository has no lint config; direnv enters it on the first `cd`.
- R-md-06: linters configure per directory, not per file, and inline disable comments are noise. `AGENTS.md` at a repository root falls under the forge profile, which is fine because it is a thin pointer and the agent content lives in `.agents/`.
- R-md-07: Obsidian indents a list with a tab or exactly 4 spaces (its editor code, `useTab ? "\t" : "    "`, app 1.14.5), and the Google Markdown style guide puts list text at column 4, so 4 is the default for Markdown and for files with no formatter of their own. The exceptions follow the tools: nixfmt (RFC 166) writes 2 and does not read `.editorconfig`; shfmt reads it unless given style flags, so `repo-check` and `nix fmt` pass `-i 2 -ci` (the Google Shell Style Guide) and a script without an extension, which no section can name, gets 2 as well; the shell sections remain for editors; Prettier writes 2 for YAML, JSON and the web formats; Make and Go need tabs. ruff writes 4 for Python by default. `markdownlint-cli2 --fix` re-indents nested bullets under bullets but not a list item's continuation lines or a bullet under a numbered item (tested 2026-10-31); those are fixed by hand. An EditorConfig section whose pattern has a slash is anchored at the file's folder, so `.githooks/*` gets a section of its own beside `*.{sh,bash}`.
- Tested facts (markdownlint-cli2 0.23.3, 2026-10-24): without `--config`, a directory's own config replaces the parent's, with no merge; `extends` inherits and lets local settings win. With a `.markdownlint-cli2.jsonc` given as `--config`, a directory's `.markdownlint-cli2.jsonc` is merged over it key by key, so turning rules off needs each key by name; a plain `.markdownlint.jsonc` replaced the base. `markdownlint-cli2` looks for config only from the folder it runs in downwards, and with a `--config` base it resolves a folder config's relative `customRules` against the base's folder.
- Built-in rules cover only part of R-lang-06: HTML (MD033), table padding (MD060), hard wraps (MD013, off). Callouts, emoji, decorative rules and heavy emphasis need custom rules; whether context is kept stays a human or agent judgement.

## R-link-01 to R-link-12

- R-link-02, exceptions decided 2026-10-29: only the file's own name is checked, not its folders (the vault's `20_Projects/` is a PARA name). All-caps names are a convention readers and forges expect (`README.md`, `LICENSE`); Rust and Python module names must be identifiers, so snake_case; tool-fixed names such as `Cargo.toml` and insta's `__`-joined snapshots cannot change.
- R-link-01 to 05: one convention for agents, the VSCodium preview, GitHub, Codeberg, Obsidian and a web UI. Wiki-links are a non-standard extension. A space in a file name needs `%20` or `<…>`. GitHub, Obsidian and VSCodium disagree on what the root of an absolute path is.
- R-link-04, checked 2026-10-24: no anchor form resolves on both sides. GitHub and VSCodium use the slug; Obsidian expects the heading text URL-encoded (`#My%20section`) and does not resolve slugs (open feature request since 2022-01-11).
- R-link-05: a public repository is read by people who have none of the author's other files.
- R-link-08, tested 2026-10-25 with markdownlint-cli2 0.23.3 and cspell: MD044 checks the visible link text, never the URL, and cannot exempt links, so `[nixos.org](…)` or `[vscodium.nix](…)` fail; cspell flags unknown words in plain link text. Both skip code spans. Rendering, checked the same day: Obsidian and the built-in VSCodium preview show a code-text link as a link; Markdown Preview Enhanced styles it as plain code unless a style rule (`a code`) gives it the link colour. GitHub and Codeberg were not checked.
- R-link-10: GitHub opens folder links. Checked 2026-10-27 for a folder outside the repository: the built-in VSCodium preview reveals it in the sidebar, Markdown Preview Enhanced shows a link that does nothing, Obsidian fails with `EACCES`.
- R-link-12, `repo-check`, 2026-10-29: lychee 0.24 offline with `--include-fragments` replaced the check of `.md` links, since it also checks other targets (a script, an image) and fragments. A trial on every repository found 25 broken links the old check missed. Errors for links leaving the repository are dropped: those are R-link-15's, and a CI checkout has no neighbours.
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
