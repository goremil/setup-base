# Fault injection for repo-check and commit-msg-check (R-check-12). Each test
# builds a scratch git repository in the sandbox: `clean` must pass every check
# that applies, `faults` breaks one thing per check and must report exactly the
# checks listed in faults-expected.txt. Faulty content is generated here, not
# stored, so this repository's own checks stay clean: secrets and markers are
# assembled from pieces with printf.
# The fixtures spell `color` and `organise` on purpose, and Polish drafts.
# cspell:ignore color organise Szkic Notatka którą później przetłumaczę
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
  # The spelling settings a repository gets from the template, and what
  # lib.mkRepo adds for drafts in another language (R-lang-10).
  drafts = {
    draftLanguages = [ "pl" ];
    cspellImports = [ "${(lib.cspellDictionaries pkgs).pl}/cspell-ext.json" ];
  };
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
    # Code is not prose: the spelling and link checks skip fences and code spans.
    printf '# Notes\n\nOrganize the colours with `color`, linked as `[x](gone.md)`.\n\n```css\na { color: red; }\n```\n' > notes.md
    printf 'a: 1\n' > config.yaml
    printf '#!/usr/bin/env bash\nset -euo pipefail\necho "$1"\n' > run.sh
    printf 'import sys\n\nprint(sys.argv)\n' > tool.py
    sed '/^# The repository.s name/,$d' ${../template/cspell.config.yaml.jinja} > cspell.config.yaml
    cp -r ${../template/.cspell} .cspell && chmod -R u+w .cspell cspell.config.yaml
    # Links out of the repository: a clone of another repository next to it.
    mkdir -p ../b && printf '# Doc\n' > ../b/d.md && printf 'pdf\n' > ../b/s.pdf
  '';
in
{
  # The deviation check reads the rule IDs from ../rules; both tests require a
  # row for R-lang-04, as lib.mkRepo does for `exclude.spelling`. The clean
  # test also has a vendored folder full of faults, which every check skips.
  repo-check-clean =
    pkgs.runCommand "repo-check-clean"
      {
        nativeBuildInputs = tools;
        config = builtins.toJSON (
          drafts
          // {
            rulesDir = "${../rules}";
            requiredDeviations = [
              {
                rule = "R-lang-04";
                why = "exclude.spelling";
              }
              {
                rule = "R-check-07";
                why = "vendored";
              }
            ];
            vendored = [ "vendor/" ];
          }
        );
        passAsFile = [ "config" ];
      }
      ''
        ${setup}
        # A draft in Polish, checked with the Polish dictionary in a private repository.
        printf '# Szkic\n\nNotatka, którą później przetłumaczę.\n' > draft.pl.md
        printf '# Agents\n\n## Deviations\n\n| Rule | What differs | Reason | Since | Decision |\n| --- | --- | --- | --- | --- |\n| R-lang-04 | A quoted British text | Verbatim quote | 2026-10-25 | A note |\n| R-check-07 | vendor/ is not checked | Verbatim copies | 2026-10-27 | A note |\n' > AGENTS.md
        mkdir -p vendor/deep
        printf '{ unused }: let a = 1; in { a = a; }\n' > vendor/deep/bad.nix
        printf '#Heading\n\n[gone](missing.md)\n\nThe color.\n' > vendor/lint.md
        printf '#!/usr/bin/env bash\necho $1\n' > vendor/unsafe.sh
        printf 'no newline' > vendor/nonl.txt
        # A pair, a pair whose clone is missing, a local-only link, a web link.
        printf '# Out\n\n[d.md](https://c.org/o/b/src/branch/main/d.md) ([local](../b/d.md))\n\n[x.md](https://c.org/o/g/src/branch/main/x.md) ([local](../g/x.md))\n\nData sheet ([local](../b/s.pdf))\n\n[A page](https://example.org/page)\n' > out.md
        git add -A
        REPO_CHECK_CONFIG="$configPath" repo-check -v | tee "$TMPDIR/out"
        grep -q '2 deviation(s) recorded' "$TMPDIR/out"
        grep -q '1 draft(s) in another language' "$TMPDIR/out"
        grep -q '2 pair(s), 1 local-only link(s)' "$TMPDIR/out"
        grep -q 'out.md:5: ../g/x.md: not cloned here' "$TMPDIR/out"
        grep -q '^repo-check: all [0-9]* checks passed' "$TMPDIR/out"
        touch $out
      '';

  repo-check-faults =
    pkgs.runCommand "repo-check-faults"
      {
        nativeBuildInputs = tools;
        config = builtins.toJSON (
          drafts
          // {
            hugeFileKiB = 1;
            public = true;
            rulesDir = "${../rules}";
            vendored = [ "vendor/" ];
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
          }
        );
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
        # links out of the repository: halves that disagree, a file missing in its
        # clone, a link out with no form
        printf '# Out\n\n[d.md](https://c.org/o/b/src/branch/main/d.md) ([local](../b/e.md))\n\n[a.md](https://c.org/o/b/src/branch/main/a.md) ([local](../b/a.md))\n\n[d](../b/d.md)\n' > out.md
        printf '# Spelling\n\nThe color.\n' > spelling.md            # -ize spelling
        printf '# Oxford\n\nWe organise it.\n' > oxford.md          # cspell (also -ize)
        printf '# Szkic\n\nNotatka.\n' > draft.pl.md               # a draft, public repository
        printf -- '-----BEGIN %s PRIVATE KEY-----\n' OPENSSH > key.txt  # private-key material
        # gitleaks (staged), which scans vendored folders too
        mkdir vendor && printf 'token = "%s"\n' "$(token zZ9yY8xX7wW6vV5uU4tT3sS2rR1qQ0pP9oO8)" > vendor/new.txt
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
        grep -q '../b/e.md: does not match' "$TMPDIR/out"
        grep -q '../b/a.md (missing)' "$TMPDIR/out"
        grep -q '../b/d.md: write' "$TMPDIR/out"
        touch $out
      '';

  # In CI the remote half of a pair is checked through the forge's API, here a
  # local server with the forge's paths, and local-only links are counted.
  repo-check-ci = pkgs.runCommand "repo-check-ci" { nativeBuildInputs = tools; } ''
    ${setup}
    mkdir -p "$TMPDIR/api/api/v1/repos/o/b/contents"
    printf '{}\n' > "$TMPDIR/api/api/v1/repos/o/b/contents/d.md"
    python3 -m http.server --bind 127.0.0.1 --directory "$TMPDIR/api" 8765 > "$TMPDIR/server.log" 2>&1 &
    for _ in $(seq 50); do
      python3 -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8765/")' 2>/dev/null && break
      sleep 0.1
    done
    export CI=true REPO_CHECK_FORGE_API=http://127.0.0.1:8765
    printf '# Out\n\n[d.md](https://c.org/o/b/src/branch/main/d.md) ([local](../b/d.md))\n\nData sheet ([local](../x/s.pdf))\n' > out.md
    git add -A
    # No token: a public repository answers anyway.
    repo-check -v | tee "$TMPDIR/out"
    grep -q '1 pair(s), 1 local-only link(s) (local-only not checkable in CI)' "$TMPDIR/out"
    # A remote half the forge does not have: without a token it may be private.
    printf '\n[a.md](https://c.org/o/b/src/branch/main/a.md) ([local](../b/a.md))\n' >> out.md
    git add -A
    if repo-check > "$TMPDIR/out"; then cat "$TMPDIR/out"; exit 1; fi
    grep -q 'missing on the forge, or private: set REPO_CHECK_FORGE_TOKEN' "$TMPDIR/out"
    # With a token, a 404 means missing.
    export REPO_CHECK_FORGE_TOKEN=t
    if repo-check > "$TMPDIR/out"; then cat "$TMPDIR/out"; exit 1; fi
    grep -q 'a.md missing on the forge$' "$TMPDIR/out"
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
      + expect "vendored" (rules { vendored = [ "v/" ]; }) [ "R-check-07" ]
      +
        expect "folder overrides"
          (rules {
            markdownlint.directories.docs = {
              profile = "forge";
              overrides.MD041 = false;
            };
          })
          [
            "R-md-05"
            "R-md-06"
          ]
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
