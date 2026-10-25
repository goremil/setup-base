# Fault injection for repo-check and commit-msg-check (R-check-12). Each test
# builds a scratch git repository in the sandbox: `clean` must pass every check
# that applies, `faults` breaks one thing per check and must report exactly the
# checks listed in faults-expected.txt. Faulty content is generated here, not
# stored, so this repository's own checks stay clean: secrets and markers are
# assembled from pieces with printf.
{
  pkgs,
  lib,
  repo-check,
  commit-msg-check,
}:
let
  tools = lib.checkTools pkgs ++ [
    repo-check
    commit-msg-check
  ];
  setup = ''
    export HOME="$TMPDIR" RUFF_CACHE_DIR="$TMPDIR/ruff-cache"
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    mkdir repo && cd repo
    git init -q -b main
    mkdir .githooks
    printf '#!/usr/bin/env bash\nset -euo pipefail\necho hook\n' > .githooks/pre-commit
    chmod +x .githooks/pre-commit
    printf '{ pkgs }: pkgs.hello\n' > default.nix
    printf '# Title\n\nSee [the notes](notes.md).\n\n```sh\necho hi\n```\n' > README.md
    # Code is not prose: the spelling check skips fences and code spans.
    printf '# Notes\n\nOrganize the colours with `color`.\n\n```css\na { color: red; }\n```\n' > notes.md
    printf 'a: 1\n' > config.yaml
    printf '#!/usr/bin/env bash\nset -euo pipefail\necho "$1"\n' > run.sh
    printf 'import sys\n\nprint(sys.argv)\n' > tool.py
  '';
in
{
  # The deviation check reads the rule IDs from ../rules; both tests require a
  # row for R-lang-04, as lib.mkRepo does for `exclude.spelling`.
  repo-check-clean =
    pkgs.runCommand "repo-check-clean"
      {
        nativeBuildInputs = tools;
        config = builtins.toJSON {
          rulesDir = "${../rules}";
          requiredDeviations = [
            {
              rule = "R-lang-04";
              why = "exclude.spelling";
            }
          ];
        };
        passAsFile = [ "config" ];
      }
      ''
        ${setup}
        printf '# Agents\n\n## Deviations\n\n| Rule | What differs | Reason | Since | Decision |\n| --- | --- | --- | --- | --- |\n| R-lang-04 | A quoted British text | Verbatim quote | 2026-10-25 | A note |\n' > AGENTS.md
        git add -A
        REPO_CHECK_CONFIG="$configPath" repo-check -v | tee "$TMPDIR/out"
        grep -q '1 deviation(s) recorded' "$TMPDIR/out"
        grep -q '^repo-check: all [0-9]* checks passed' "$TMPDIR/out"
        touch $out
      '';

  repo-check-faults =
    pkgs.runCommand "repo-check-faults"
      {
        nativeBuildInputs = tools;
        config = builtins.toJSON {
          hugeFileKiB = 1;
          rulesDir = "${../rules}";
          requiredDeviations = [
            {
              rule = "R-lang-04";
              why = "exclude.spelling";
            }
          ];
          extraChecks = [
            {
              name = "extra check";
              command = [ "false" ];
            }
          ];
        };
        passAsFile = [ "config" ];
      }
      ''
        ${setup}
        token() { printf 'gh%s_%s' p "$1"; }
        # gitleaks (history): a token in an earlier commit.
        printf 'token = "%s"\n' "$(token aB3dE5fG7hJ9kL1mN3pQ5rS7tU9vW1xY3zA5)" > old.txt
        git add -A && git commit -qm init
        git rm -q old.txt && git commit -qm 'drop it'
        # One fault per check:
        printf '{ unused }: let a = 1; in { a = a; }\n' > bad.nix  # nixfmt, statix, deadnix
        printf '#Heading\n' > lint.md                                # markdownlint
        printf 'a: [1, 2\n' > broken.yaml                            # yamllint
        printf '#!/usr/bin/env bash\necho $1\n' > unsafe.sh          # shellcheck
        printf 'import os\nx=1\n' > unused.py                        # ruff check, ruff format
        printf '# Links\n\n[gone](missing.md)\n' > links.md          # .md links
        printf '# Spelling\n\nThe color.\n' > spelling.md            # -ize spelling
        printf -- '-----BEGIN %s PRIVATE KEY-----\n' OPENSSH > key.txt  # private-key material
        printf 'token = "%s"\n' "$(token zZ9yY8xX7wW6vV5uU4tT3sS2rR1qQ0pP9oO8)" > new.txt  # gitleaks (staged)
        printf '%s HEAD\n' "$(printf '<%.0s' 1 2 3 4 5 6 7)" > conflict.txt  # conflict markers
        chmod -x .githooks/pre-commit                                # hooks executable
        printf '# Fence\n\n```sh\necho open\n' > fence.md            # code fences
        head -c 2048 /dev/zero | tr '\0' 'a' > big.txt; echo >> big.txt  # huge files
        printf 'line   \n' > spaces.txt                              # trailing whitespace
        printf 'no newline' > nonl.txt                               # final newline
        # deviations: an unknown rule, a bad date, and R-lang-04 unrecorded
        printf '# Agents\n\n## Deviations\n\n| Rule | What differs | Reason | Since | Decision |\n| --- | --- | --- | --- | --- |\n| R-made-99 | x | y | 2026-10-25 | z |\n| R-md-06 | x | y | soon | z |\n' > AGENTS.md
        git add -A
        status=0
        REPO_CHECK_CONFIG="$configPath" repo-check > "$TMPDIR/out" || status=$?
        cat "$TMPDIR/out"
        [ "$status" -eq 1 ]
        grep '^==> FAILED: ' "$TMPDIR/out" | sed 's/^==> FAILED: //' > "$TMPDIR/failed"
        diff -u ${./faults-expected.txt} "$TMPDIR/failed"
        touch $out
      '';

  # lib.mkRepo turns its arguments into the deviations repo-check requires.
  mkrepo-deviations =
    let
      required =
        args:
        (builtins.fromJSON (
          builtins.unsafeDiscardStringContext (
            builtins.readFile
              (lib.mkRepo ({ self = ../.; } // args))
              .devShells.${pkgs.stdenv.hostPlatform.system}.default.REPO_CHECK_CONFIG
          )
        )).requiredDeviations;
      rules = args: map (d: d.rule) (required args);
      expect =
        name: got: want:
        if got == want then
          ""
        else
          throw "mkrepo-deviations ${name}: got ${builtins.toJSON got}, want ${builtins.toJSON want}";
    in
    pkgs.runCommand "mkrepo-deviations" { } (
      expect "defaults" (rules { }) [ ]
      + expect "ignores only" (rules { markdownlint.ignores = [ "x/**" ]; }) [ ]
      + expect "null" (rules { markdownlint = null; }) [ "R-md-05" ]
      +
        expect "all"
          (rules {
            markdownlint = {
              profile = "agent";
              overrides.MD013 = true;
              directories = { };
            };
            exclude.spelling = [ "x" ];
          })
          [
            "R-md-05"
            "R-md-06"
            "R-md-06"
            "R-lang-04"
          ]
      + "touch $out"
    );

  commit-msg-check = pkgs.runCommand "commit-msg-check" { nativeBuildInputs = tools; } ''
    printf 'feat(template): ask for the forge\n' > good
    printf '# a comment\n\nfix!: drop the old flag\n' > good-bang
    printf 'Add a thing\n' > bad
    printf 'feat: \n' > empty
    commit-msg-check good
    commit-msg-check good-bang
    if commit-msg-check bad; then exit 1; fi
    if commit-msg-check empty; then exit 1; fi
    touch $out
  '';
}
