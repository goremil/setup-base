A first line that is not a heading. flag: MD041 (forge)

# Built-in rule fixture

Expected: each line marked "flag" is reported by the rule and profiles named there, and nothing else is.

Press <kbd>Ctrl</kbd> to copy. flag: MD033 (agent, hybrid)

Hosted on github and nixos. flag: MD044 twice (all profiles)

`github` in code is fine, and so is [a link](https://github.com/example/repo).

A [reference link][ref] here. flag: MD054 (agent)

[ref]: https://example.org/

The repository tracks nixos-unstable, and NixOS-WSL is a project. None of these is flagged.

A themed image: <picture></picture>. flag: MD033 (all profiles; Codeberg strips it)
