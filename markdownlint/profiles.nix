# The three Markdown lint profiles (agent, forge, hybrid), as
# plain attrsets of markdownlint rule settings. `agent` is the base; `forge`
# and `hybrid` are the base with their own overrides merged in, so every
# profile is complete and flat (no `extends` inside the generated files).
# Pure data: lib.markdownlint and the flake check import it.
let
  agent = {
    MD013 = false; # line length: one paragraph per line, the editor soft-wraps
    MD033 = true; # no inline HTML
    MD041 = false; # first line need not be a heading (front matter, routers)
    MD024.siblings_only = true; # duplicate headings ok unless siblings
    MD003.style = "atx"; # # Heading
    MD004.style = "dash"; # - bullet
    MD046.style = "fenced";
    MD048.style = "backtick";
    MD049.style = "underscore"; # _italic_
    MD050.style = "asterisk"; # **bold**
    MD054 = {
      # inline links only: the target stays next to the text
      autolink = true;
      inline = true;
      url_inline = true;
      full = false;
      collapsed = false;
      shortcut = false;
    };
    MD060.style = "compact"; # | a | b | and | --- | --- |; fixable with --fix
    MD044 = {
      # capitalization only; cspell accepts `github` because its dictionaries
      # hold the lowercase form
      names = [
        "NixOS"
        "NixOS-WSL"
        # a channel name that starts with "nixos"; other identifiers belong in
        # backticks, which MD044 skips. A repository adds its own names
        # through `markdownlint.overrides` in lib.mkRepo.
        "nixos-unstable"
        "GitHub"
        "Codeberg"
        "Forgejo"
        "VSCodium"
      ];
      code_blocks = false;
    };

    # custom rules (noise-rules.mjs)
    no-alerts = true;
    no-emoji = true;
    no-hr = true;
    bold-density = {
      severity = "warning"; # a heuristic: warns, never blocks a commit
      max = 1;
    };
    no-wikilinks = true;
  };

  referenceLinksAllowed = {
    MD054 = agent.MD054 // {
      full = true;
      collapsed = true;
      shortcut = true;
    };
  };
in
{
  inherit agent;

  # Read by people on GitHub or Codeberg.
  forge =
    agent
    // referenceLinksAllowed
    // {
      # Only what both forges keep (rendered through both Markdown APIs,
      # 2026-10-24): Codeberg (Forgejo) strips <picture> and <source>.
      MD033.allowed_elements = [
        "details"
        "summary"
        "img"
        "br"
        "kbd"
        "sub"
        "sup"
      ];
      MD041 = true; # a README starts with its title
      no-alerts = false; # both forges render all five alert types, any case
      no-emoji = false;
      no-hr = false;
      bold-density = false;
    };

  # Knowledge for agents and people, read in an editor (the PARA vault).
  hybrid =
    agent
    // referenceLinksAllowed
    // {
      no-alerts = false; # callouts render in VSCodium and Obsidian
      no-hr = false;
      bold-density = agent.bold-density // {
        max = 3;
      };
    };
}
