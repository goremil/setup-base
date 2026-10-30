# Fault injection for repo-check and commit-msg-check (R-check-12). Each test
# builds a scratch git repository in the sandbox: `clean` must pass every check
# that applies, `faults` breaks one thing per check and must report exactly the
# checks listed in faults-expected.txt. Faulty content is generated here, not
# stored, so this repository's own checks stay clean: secrets and markers are
# assembled from pieces with printf.
# The fixtures spell `color` and `organise` on purpose, and Polish drafts.
# cspell:ignore color organise qwzxv Szkic Notatka którą później przetłumaczę
{
  pkgs,
  lib,
  repo-check,
  commit-msg-check,
  pre-push-check,
}:
let
  tools = lib.checkTools pkgs ++ [
    repo-check
    commit-msg-check
    pre-push-check
  ];
  # The spelling settings a repository gets from the template, and what
  # lib.mkRepo adds for drafts in another language (R-lang-10).
  drafts = {
    draftLanguages = [ "pl" ];
    cspellImports = [ "${(lib.cspellDictionaries pkgs).pl}/cspell-ext.json" ];
  };
  setup = ''
    export HOME="$TMPDIR" RUFF_CACHE_DIR="$TMPDIR/ruff-cache" MYPY_CACHE_DIR="$TMPDIR/mypy-cache"
    # lychee builds its HTTP client even offline, and the sandbox's SSL_CERT_FILE
    # names no file.
    export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
    export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
    mkdir repo && cd repo
    git init -q -b main
    mkdir .githooks
    printf '#!/usr/bin/env bash\nset -euo pipefail\necho hook\n' > .githooks/pre-commit
    chmod +x .githooks/pre-commit
    printf '{ pkgs }: pkgs.hello\n' > default.nix
    printf '# Title\n\nSee [the notes](notes.md#notes) and [the script](run.sh).\n\n```sh\necho hi\n```\n' > README.md
    # Code is not prose: the spelling and link checks skip fences and code spans.
    printf '# Notes\n\nOrganize the colours with `color`, linked as `[x](gone.md)`.\n\n```css\na { color: red; }\n```\n' > notes.md
    printf 'a: 1\n' > config.yaml
    printf '#!/usr/bin/env bash\nset -euo pipefail\ncase "$1" in\n  a) echo "$1" ;;\nesac\n' > run.sh
    cp ${../template/.editorconfig} .editorconfig
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
        # git-crypt, with a stand-in filter that writes its header: one file unlocked
        # (plain here, encrypted in the index), one locked (ciphertext here too), and a
        # symlink, which git-crypt leaves as it is.
        git config filter.git-crypt.clean "printf '\\000GITCRYPT\\000'; cat"
        printf 'secret/** filter=git-crypt diff=git-crypt\n' > .gitattributes
        mkdir secret
        printf '# Open\n\nPlain here.\n' > secret/open.md
        printf '\0GITCRYPT\0#Heading\n' > secret/locked.md
        ln -s open.md secret/link.md
        # Names a language fixes (Cargo.toml is in the Rust test), and a binary file without a NUL byte
        # (a git-crypt key file), which no text check reads.
        mkdir LICENSES && printf 'licence text\n' > LICENSES/GPL-3.0-only.txt
        printf 'fn main() {}\n' > my_mod.rs
        printf '*.key binary\n' >> .gitattributes
        printf 'k\351y' > a.key
        # The workflow a repository gets, which actionlint and zizmor pass.
        mkdir -p .github/workflows && cp ${../.github/workflows/check.yml} .github/workflows/check.yml
        git add -A
        REPO_CHECK_CONFIG="$configPath" repo-check -v | tee "$TMPDIR/out"
        grep -q '2 file(s) encrypted with git-crypt, 1 locked here' "$TMPDIR/out"
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
        # changelog: a release tag with no section (v0.1.0 has one)
        git tag v0.1.0 HEAD~1 && git tag v0.2.0
        printf '# Changelog\n\n## 0.1.0 - 2026-10-30\n\n- first\n' > CHANGELOG.md
        # One fault per check:
        printf '{ unused }: let a = 1; in { a = a; }\n' > bad.nix  # nixfmt, statix, deadnix
        printf '#Heading\n' > lint.md                                # markdownlint
        printf 'a: [1, 2\n' > broken.yaml                            # yamllint
        printf '#!/usr/bin/env bash\necho $1\n' > unsafe.sh          # shellcheck
        printf '#!/usr/bin/env bash\nset -euo pipefail\nif true;then echo x;fi\n' > fmt.sh  # shfmt
        # actionlint: a job without runs-on; zizmor: an action not pinned by commit
        mkdir -p .github/workflows
        printf 'on: push\npermissions: {}\njobs:\n  a:\n    steps:\n      - run: "true"\n' > .github/workflows/lint.yml
        printf 'on: push\npermissions: {}\njobs:\n  a:\n    runs-on: ubuntu-latest\n    steps:\n      - uses: actions/checkout@v7\n        with:\n          persist-credentials: false\n' > .github/workflows/pin.yml
        printf 'import os\nx=1\n' > unused.py                        # ruff check, ruff format
        printf 'x: int = "a"\n' > typed.py                          # mypy
        # links inside the repository: a missing file, a missing non-Markdown target,
        # a missing fragment
        printf '# Links\n\n[gone](missing.md), [script](gone.sh), [fragment](README.md#nowhere)\n' > links.md
        # links out of the repository: halves that disagree, a file missing in its
        # clone, a link out with no form
        printf '# Out\n\n[d.md](https://c.org/o/b/src/branch/main/d.md) ([local](../b/e.md))\n\n[a.md](https://c.org/o/b/src/branch/main/a.md) ([local](../b/a.md))\n\n[d](../b/d.md)\n' > out.md
        printf '# Spelling\n\nThe color.\n' > spelling.md            # -ize spelling
        printf '# Oxford\n\nWe organise it.\n' > oxford.md          # cspell (also -ize)
        # cspell keeps the user's global config out: a word only that config allows is
        # still reported. (A global config takes effect through `import`, as
        # `cspell link` writes it; a made-up word, since the -ise forms are flagged anyway.)
        printf '# Global\n\nThe qwzxv word.\n' > global.md
        mkdir -p "$TMPDIR/xdg/cspell" && printf '{"version": "0.2", "words": ["qwzxv"]}\n' > "$TMPDIR/allow.json"
        printf '{"import": ["%s"]}\n' "$TMPDIR/allow.json" > "$TMPDIR/xdg/cspell/cspell.json"
        export XDG_CONFIG_HOME="$TMPDIR/xdg"
        printf '# Szkic\n\nNotatka.\n' > draft.pl.md               # a draft, public repository
        printf 'caf\351\n' > latin1.txt                               # UTF-8: Latin-1
        printf '\357\273\277bom\n' > bom.txt                          # UTF-8: a byte-order mark
        printf 'x\n' > Bad_Name.txt                                  # kebab-case file names
        printf -- '-----BEGIN %s PRIVATE KEY-----\n' OPENSSH > key.txt  # private-key material
        # git-crypt: a file given to it, with no filter set up in this clone, and one
        # forced to text by a nested .gitattributes
        printf 'plain.md filter=git-crypt diff=git-crypt\n' > .gitattributes
        printf '# Plain\n\nStored as it is.\n' > plain.md
        mkdir crlf && printf '* filter=git-crypt\n*.md eol=lf\n' > crlf/.gitattributes
        printf '# Forced\n\nTo text.\n' > crlf/forced.md
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
        grep -q 'v0.2.0: no section in CHANGELOG.md' "$TMPDIR/out"
        grep -q 'links.md -> missing.md: ' "$TMPDIR/out"
        grep -q 'links.md -> gone.sh: ' "$TMPDIR/out"
        grep -q 'links.md -> README.md#nowhere: ' "$TMPDIR/out"
        grep -q 'latin1.txt:1: not UTF-8 (byte 0xe9)' "$TMPDIR/out"
        grep -q 'bom.txt: starts with a byte-order mark' "$TMPDIR/out"
        grep -q "Bad_Name.txt: 'Bad_Name.txt' is not kebab-case" "$TMPDIR/out"
        grep -q '../b/e.md: does not match' "$TMPDIR/out"
        grep -q '../b/a.md (missing)' "$TMPDIR/out"
        grep -q '../b/d.md: write' "$TMPDIR/out"
        grep -q 'Unknown word (qwzxv)' "$TMPDIR/out"
        grep -q 'plain.md: given to git-crypt, but stored in plain text' "$TMPDIR/out"
        grep -q 'crlf/forced.md: given to git-crypt, but forced to text' "$TMPDIR/out"
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

  # R-git-07 with a throwaway key: signed commits and an annotated signed tag
  # pass, locally with the keyring and in CI with the keys fetched from a local
  # server; an unsigned commit, a lightweight tag and CI without a key source
  # fail. pre-push-check refuses an unsigned or fixup! commit on its way out.
  signatures =
    pkgs.runCommand "signatures"
      {
        nativeBuildInputs = tools;
      }
      ''
        ${setup}
        export GNUPGHOME="$TMPDIR/gnupg"
        mkdir -m 700 "$GNUPGHOME"
        gpg --batch --quiet --passphrase "" --quick-gen-key "t <t@t>" ed25519 sign never
        git config user.signingkey t@t
        git add -A && git commit -qS -m "feat: signed"
        git commit -qS --allow-empty -m "fix: signed too"
        git tag -s v1 -m v1
        sig() { repo-check -v > "$TMPDIR/out" || true; sed -n '/^==> signed commits and tags$/,/^==> /p' "$TMPDIR/out"; }
        sig | tee "$TMPDIR/sig"
        grep -q '2 commit(s) and 1 tag(s) signed' "$TMPDIR/sig"

        mkdir -p "$TMPDIR/keys" && gpg -a --export t@t > "$TMPDIR/keys/t.gpg"
        python3 -m http.server --bind 127.0.0.1 --directory "$TMPDIR/keys" 8766 > "$TMPDIR/server.log" 2>&1 &
        for _ in $(seq 50); do
          python3 -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:8766/")' 2>/dev/null && break
          sleep 0.1
        done
        CI=true REPO_CHECK_SIGNING_KEYS=http://127.0.0.1:8766/t.gpg sig | tee "$TMPDIR/sig"
        grep -q '2 commit(s) and 1 tag(s) signed' "$TMPDIR/sig"
        CI=true sig | tee "$TMPDIR/sig"
        grep -q 'no keys to verify with: set REPO_CHECK_SIGNING_KEYS' "$TMPDIR/sig"

        printf 'refs/heads/main %s refs/heads/main %s\n' "$(git rev-parse HEAD)" 0000000000000000000000000000000000000000 > "$TMPDIR/push"
        pre-push-check origin url < "$TMPDIR/push"

        git commit -q --no-gpg-sign --allow-empty -m "feat: unsigned"
        git tag light
        sig | tee "$TMPDIR/sig"
        grep -q 'not signed with a good signature (N): feat: unsigned' "$TMPDIR/sig"
        grep -q 'tag light: lightweight' "$TMPDIR/sig"

        printf 'refs/heads/main %s refs/heads/main %s\n' "$(git rev-parse HEAD)" 0000000000000000000000000000000000000000 > "$TMPDIR/push"
        if pre-push-check origin url < "$TMPDIR/push" > "$TMPDIR/pp"; then cat "$TMPDIR/pp"; exit 1; fi
        grep -q 'is not signed with a good signature (%G? = N): feat: unsigned' "$TMPDIR/pp"
        git reset -q --hard HEAD~1
        git commit -qS --allow-empty -m "fixup! feat: signed"
        printf 'refs/heads/main %s refs/heads/main %s\n' "$(git rev-parse HEAD)" 0000000000000000000000000000000000000000 > "$TMPDIR/push"
        if pre-push-check origin url < "$TMPDIR/push" > "$TMPDIR/pp"; then cat "$TMPDIR/pp"; exit 1; fi
        grep -q 'is an unsquashed fixup! feat: signed' "$TMPDIR/pp"
        touch $out
      '';

  # A Rust workspace: cargo fmt, clippy and cargo-deny pass on a clean crate and
  # fail on one fault each. buildInHook = false names the flake check it narrows.
  repo-check-rust =
    pkgs.runCommand "repo-check-rust"
      {
        nativeBuildInputs = tools;
        config = builtins.toJSON { buildInHook = false; };
        passAsFile = [ "config" ];
      }
      ''
        ${setup}
        export CARGO_HOME="$TMPDIR/cargo"
        printf '[package]\nname = "t"\nversion = "0.1.0"\nedition = "2021"\nlicense = "MIT"\n' > Cargo.toml
        mkdir src && printf 'fn main() {\n    println!("hi");\n}\n' > src/main.rs
        printf '[licenses]\nallow = ["MIT"]\n' > deny.toml
        printf 'target/\n' > .gitignore
        cargo generate-lockfile --offline
        git add -A
        REPO_CHECK_CONFIG="$configPath" repo-check -v | tee "$TMPDIR/out"
        grep -q '^repo-check: all [0-9]* checks passed' "$TMPDIR/out"
        grep -q 'skipped: nix flake check --no-build (built in CI) (no flake.nix)' "$TMPDIR/out"

        # One fault each: formatting, a clippy lint, a licence deny.toml does not allow.
        printf 'fn main() { let x = 5; if x == x { println!("hi"); } }\n' > src/main.rs
        sed -i 's/license = "MIT"/license = "0BSD"/' Cargo.toml
        git add -A
        status=0
        REPO_CHECK_CONFIG="$configPath" repo-check > "$TMPDIR/out" || status=$?
        cat "$TMPDIR/out"
        [ "$status" -eq 1 ]
        grep '^==> FAILED: ' "$TMPDIR/out" | sed 's/^==> FAILED: //' > "$TMPDIR/failed"
        printf 'cargo fmt --check\ncargo clippy\ncargo deny\n' | diff -u - "$TMPDIR/failed"
        touch $out
      '';

  # A profile left off while its files are there fails its checks: the setup has
  # a Python file, and no profile is named.
  repo-check-features =
    pkgs.runCommand "repo-check-features"
      {
        nativeBuildInputs = tools;
        config = builtins.toJSON { features = [ ]; };
        passAsFile = [ "config" ];
      }
      ''
        ${setup}
        git add -A
        status=0
        REPO_CHECK_CONFIG="$configPath" repo-check > "$TMPDIR/out" || status=$?
        cat "$TMPDIR/out"
        [ "$status" -eq 1 ]
        grep '^==> FAILED: ' "$TMPDIR/out" | sed 's/^==> FAILED: //' > "$TMPDIR/failed"
        printf 'ruff check\nruff format --check\nmypy\n' | diff -u - "$TMPDIR/failed"
        grep -q "1 file(s) need the 'python' tool profile" "$TMPDIR/out"
        touch $out
      '';

  # lib.mkRepo switches profiles on by marker file and by name, and refuses an
  # unknown name. setup-base itself has CHANGELOG.md, REUSE.toml and
  # .github/workflows/.
  mkrepo-features =
    let
      enabled =
        args:
        (builtins.fromJSON (
          builtins.unsafeDiscardStringContext (
            builtins.readFile
              (lib.mkRepo ({ self = ../.; } // args))
              .devShells.${pkgs.stdenv.hostPlatform.system}.default.REPO_CHECK_CONFIG
          )
        )).features;
      bad = builtins.tryEval (enabled {
        features = [ "cobol" ];
      });
    in
    assert
      enabled { } == [
        "changelog"
        "github-actions"
        "reuse"
      ];
    assert
      enabled { features = [ "python" ]; } == [
        "changelog"
        "github-actions"
        "python"
        "reuse"
      ];
    assert !bad.success;
    pkgs.runCommand "mkrepo-features" { } "touch $out";

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
            exclude = {
              spelling = [ "x" ];
              encoding = [ "x" ];
              file-names = [ "x" ];
            };
          })
          [
            "R-md-05"
            "R-md-06"
            "R-md-06"
            "R-lang-04"
            "R-lang-01"
            "R-link-02"
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
