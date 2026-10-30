# Text and Communication Conventions

Status: requirements, 2026-10-25. Encoding, language, style, Markdown, links and `INDEX.md` files.

Format as in [repo-policy.md](repo-policy.md): ID, one sentence with a BCP 14 keyword, then Check (enforcement level, current → target) and Since; "not recorded" where the source gave no date. Reasons, tests and tool details: [conventions.md](../rationale/conventions.md), under the requirement's ID. Files older than a requirement follow it when they are edited anyway, not in bulk.

## Language and text

- **R-lang-01**: Text MUST be UTF-8 without a byte-order mark, except in a context where UTF-8 is unavailable. Check: 4 (`repo-check`, "UTF-8 text"; an exception goes into `exclude.encoding`). Since: not recorded, byte-order mark 2026-10-29.
- **R-lang-02**: Before rewording content to get around a character that breaks a renderer or parser, the author SHOULD look for a UTF-8 character that looks the same (`⟨domain⟩` for `<domain>`); a real ASCII-only constraint MUST be named as an exception. Check: 0. Since: 2026-09.
- **R-lang-03**: Text MUST use the extended Latin alphabet; a proper noun or trademark in another script MUST come with a Latin transliteration. Check: 0. Since: not recorded.
- **R-lang-04**: Everything written to a file or repository MUST be in international English in Oxford spelling (`en-GB-oxendict`: British spelling with `-ize`), except a draft under R-lang-10; a proper noun or idiom in another language MUST come with a transliteration and a translation. Check: 4 in part (cspell with the managed profile, the `-ize` check of `repo-check`), else 0 + 1. Since: not recorded; Oxford spelling 2026-10-27.
- **R-lang-06**: Text MUST be concise and factual; Markdown files MUST be plain, professional, unambiguous English in short sentences that keep their context, without decorative elements. Check: 4 in part (custom rules `no-emoji`, `no-hr`, `no-alerts`, `bold-density` in the lint profiles), else 0 + 1. Since: 2026-10-23.
- **R-lang-07**: When a reply refers to steps, commands or content from earlier in the conversation, it MUST repeat them instead of "see above" or "steps 4–5"; a document location MUST be given as a link with the line range. Check: 0. Since: 2026-09.
- **R-lang-08**: Dates MUST be ISO 8601 (`YYYY-MM-DD`), times on the 24-hour clock, units metric. Check: 0. Since: not recorded.
- **R-lang-09**: Names of repositories, commands, packages, files, options and note slugs MUST be written as inline code (`setup-base`, `nixos-rebuild`); proper names of projects and products MUST stay prose (NixOS, GitHub). Check: 4 in part (MD044 with a names list), else 0. Since: 2026-10-24.
- **R-lang-10**: A draft MAY be written in another language in a private repository or a notes vault, in a file named for the language (`note.pl.md`); its English translation MUST replace it, the original staying in history, and a public repository MUST NOT contain one. Check: 4 (cspell checks a draft with its language's dictionary; `repo-check` refuses one in a public repository). Since: 2026-10-27.

## Content media

- **R-media-01**: The medium MUST be chosen by the main reader and where the content is displayed: agent Markdown for content read by agents as raw text (the user-level agent configuration, `.agents/` in repositories, `INDEX.md` files); forge Markdown for people on a forge (`README.md`, `CONTRIBUTING.md`, `docs/`); hybrid Markdown for a notes vault, read by agents and people in an editor; HTML and CSS (and JS) for presentation that Markdown cannot carry. Check: 0. Since: 2026-10-24.
- **R-media-02**: Agent Markdown is the base profile; forge Markdown MAY add what both GitHub and Codeberg render (a few HTML elements such as `details`, `img`, `kbd`; alerts), hybrid Markdown MAY add moderate emphasis and callouts. A profile is a ceiling: writing leaner MAY always be done. Check: 4 (one lint profile per medium). Since: 2026-10-24.
- **R-media-03**: HTML MUST NOT be the source of truth: the content it presents MUST stay in Markdown or data (JSON, CSV). Check: 0. Since: 2026-10-24.

## Markdown style

- **R-md-01**: Emphasis MUST be `**bold**` and `_italic_`. Check: 4 (MD049, MD050 in every lint profile). Since: not recorded.
- **R-md-02**: Tables MUST be compact: `| a | b |`, delimiter row `| --- | --- |`, one space inside each pipe, no column padding. Check: 4 (MD060 `compact`). Since: 2026-10-18.
- **R-md-03**: Prose MUST be one paragraph per line, without hard wraps at a fixed column. Check: 0 (MD013 is off; no Markdown formatter fits the other rules, see the rationale). Since: 2026-10-20.
- **R-md-05**: Every repository MUST take its lint configs from the shared profiles, pinned through `setup-base` (managed, T3), with any change recorded as a deviation; `extends` MUST NOT be used in a repository. Check: 4 (`repo-check`: a tracked own config needs a recorded deviation). Since: 2026-10-24; managed since 2026-10-25.
- **R-md-06**: Inside a repository the forge profile MUST apply at the root and in `docs/`, the agent profile in `.agents/`; inline disable comments SHOULD NOT be used. Check: 0. Since: 2026-10-24.

## Links

- **R-link-01**: Links MUST be CommonMark inline links with a path relative to the linking file, `.md` extension included; wiki-links (`[[name]]`) MUST NOT be used, except in a format a harness dictates. Check: 4 (custom rule `no-wikilinks`). Since: 2026-10-24.
- **R-link-02**: File names MUST be kebab-case without spaces; a leading dot, an all-caps name (`README.md`), snake_case where a language needs it for module names (`.rs`, `.py`), names a tool fixes, folders a tool owns (`LICENSES/`, `.git-crypt/`) and names that are Jinja templates are allowed. Check: 4 (`repo-check`, "kebab-case file names"; an exception goes into `exclude.file-names`). Since: 2026-10-24, exceptions 2026-10-29.
- **R-link-03**: A link MUST NOT use an absolute path or a leading `/`. Check: 0. Since: 2026-10-24.
- **R-link-04**: Agent and hybrid Markdown MUST link to files, not to headings; a section that needs its own link target MUST become its own note. Forge Markdown MAY link to a heading in the GitHub slug form (`#my-section`). Check: 4 for forge (MD051), else 0. Since: 2026-10-24.
- **R-link-05**: A public repository MUST NOT link outside itself. Check: 0. Since: 2026-10-24.
- **R-link-06**: A reference MUST be classified as a LINK (a concrete, existing place, linked when the link helps: navigation, the target's content, the place where an action happens), a PATH (a place in inline code, not linked: abstract, an example, missing, or not linked here) or a NAME or CODE (not a place; inline code, or a fenced block when long; never a link). Check: 0 + 1. Since: 2026-10-25.
- **R-link-07**: Within a section, the first mention of a place that qualifies MUST be a LINK and later mentions a PATH; a list of files to open or change MUST link every item. Lists, tables and other sets MUST be uniform: every item a LINK, or none; an inventory table stays PATH. Check: 0 + 1. Since: 2026-10-25.
- **R-link-08**: An identifier as link text MUST be in backticks (`` [`disko.nix`](path) ``), descriptive link text without; a bare URL MUST be an autolink (`<https://…>`). Check: 4 in part (MD044, cspell on visible link text). Since: 2026-10-25.
- **R-link-09**: The link text for a file MUST be its name, or the shortest unambiguous path when the name is ambiguous (`system/INDEX.md`); a line number MUST go in plain text next to the link ("line 40"), not in an anchor. Check: 0. Since: 2026-10-25.
- **R-link-10**: A folder SHOULD NOT be linked until folder links are checked in Obsidian and the VSCodium preview; link its `INDEX.md` or `README.md`, or leave it as a PATH. Check: 0. Since: 2026-10-25.
- **R-link-12**: Links MUST be kept valid by tools: a link checker (lychee, offline by default), editor link validation and link update on move, MD051 for anchors. Check: 4 (`repo-check`: lychee offline with fragments for links inside the repository, MD051 for anchors in the same file; R-link-15 for links out). Since: 2026-10-24, lychee in `repo-check` 2026-10-29.
- **R-link-15**: A link to a place outside the repository by a local path MUST take one of two forms. A place in a repository with a remote: the remote link, then its local twin, `[name](https://…) ([local](relative-path))`. A place with no remote, such as content kept only locally: `name ([local](relative-path))`. The local path is relative (R-link-03). A link by URL alone, such as to a web page, needs no local twin. Any other link out of the repository by a local path is an error. Check: 0 → 4 (`repo-check`: locally the local half and the match of a pair, a missing clone reported, not failed; in CI the remote half through the forge's API, anonymously for a public repository and with a read-only token for a private one; local-only links skipped in CI and counted). Since: 2026-10-27.

## `INDEX.md` files

- **R-index-01**: An `INDEX.md` MUST add only what a listing, a file's name and its first lines do not: the meaning of a non-obvious name, which file is authoritative, what not to read or touch, where new material of a kind goes. It MUST NOT list self-explanatory items or carry generic definitions; it is not required to be complete. Check: 0 + 1. Since: 2026-10-23, extended 2026-10-25 (dated as one item).
- **R-index-02**: The title of an `INDEX.md` MUST name the content, not the file. Check: 0. Since: 2026-10-23, extended 2026-10-25 (dated as one item).
- **R-index-03**: A folder with nothing to add MUST NOT get an `INDEX.md`; its rules go in the nearest `AGENTS.md`. Check: 0 + 1. Since: 2026-10-23, extended 2026-10-25 (dated as one item).
- **R-index-04**: A document's status MUST live in the document itself, as a first line such as `Status: plan, accepted 2026-10-24`; an index MUST NOT repeat it. Check: 0. Since: 2026-10-23, extended 2026-10-25 (dated as one item).
- **R-index-05**: A `README.md` is for people: it MUST point at the folder's `INDEX.md` when one exists and MUST NOT be a second list. Check: 0. Since: 2026-10-23, extended 2026-10-25 (dated as one item).
- **R-index-06**: A check of an `INDEX.md` MUST verify only that its entries resolve. Check: 0 → 4. Since: 2026-10-23, extended 2026-10-25 (dated as one item).
