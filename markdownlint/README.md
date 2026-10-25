# Markdown lint profiles

Three markdownlint profiles, one per Markdown medium, and five custom rules.
A repository built on `setup-base` picks one in `lib.mkRepo`; its dev shell
links `.markdownlint-cli2.jsonc` (gitignored) to the generated file, so
`repo-check`, the editor and the CLI lint the same way, and a new version
arrives with `nix flake update base`.

## Profiles

- `agent`: Markdown read by agents as raw text. The base: no HTML, inline
  links only, no alerts, emoji or horizontal rules, at most one bold span per
  paragraph (warning).
- `forge`: Markdown read by people on GitHub or Codeberg, the default. The base
  plus what both forges render: a few HTML elements (`details`, `summary`,
  `img`, `br`, `kbd`, `sub`, `sup`; not `picture` or `source`, which Codeberg
  strips), reference links, alerts, emoji and rules; the first line must be a
  heading.
- `hybrid`: knowledge for agents and people, read in an editor. The base plus
  reference links, callouts and rules; at most three bold spans per paragraph
  (warning).

Every profile keeps: no hard wrap (MD013 off), compact tables (MD060),
`_italic_` and `**bold**`, ATX headings, `-` bullets, fenced code, MD044
capitalization for a short list of names, and no wiki-links.

## Custom rules

`noise-rules.mjs` adds five rules on the micromark token tree, so code and
front matter are never inspected: `no-alerts`, `no-emoji` (emoji presentation
and `:shortcode:` emoji; `©`, `™`, `→`, `10:30:00` and `std::vec` pass),
`no-hr`, `bold-density` (option `max`) and `no-wikilinks`.

## In a repository

```nix
base.lib.mkRepo {
  inherit self;
  markdownlint = {
    profile = "forge";                  # agent, forge or hybrid
    overrides.MD044.names = [ "..." ];  # a deviation: record it in AGENTS.md
    ignores = [ "tests/fixtures/**" ];
  };
}
```

`markdownlint = null` turns the link off. A tracked `.markdownlint-cli2.jsonc`
is left alone, so a repository can keep its own file while it moves over.

`--fix` caution: MD044 is fixable, so `--fix` rewrites every lowercase match
outside code, identifiers included. Put identifiers in backticks first, or fix
with MD044 off for that run, and review the diff.

## Check

`checks.<system>.markdownlint-profiles` lints `tests/noise.md` and
`tests/builtins.md` with each profile and compares the result with
`tests/expected-<profile>.txt`. After a deliberate change to a profile or a
rule, regenerate the expected files and review the diff.
