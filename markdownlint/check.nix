# Each profile lints the fixtures and must report exactly what
# tests/expected-<profile>.txt lists. After a deliberate change to a profile or
# a custom rule, regenerate the expected files and review the diff. `off` is
# also checked as a folder config under a base, where it is used.
{ pkgs, lib }:
pkgs.runCommand "markdownlint-profiles" { nativeBuildInputs = [ pkgs.markdownlint-cli2 ]; } ''
  export HOME="$TMPDIR"
  cp ${./tests}/*.md .
  ${pkgs.lib.concatMapStrings (name: ''
    markdownlint-cli2 --config ${
      lib.markdownlint.config pkgs { profile = name; }
    }/.markdownlint-cli2.jsonc \
      noise.md builtins.md 2>&1 \
      | grep -E '^(noise|builtins)\.md:' | sed -E 's/ \[Context.*//' > actual-${name}.txt || true
    diff -u ${./tests}/expected-${name}.txt actual-${name}.txt
  '') (builtins.attrNames lib.markdownlint.profiles)}
  # off as a folder's config, linked from the store, under a --config base
  # (mdlint, the editor): it must silence the base's explicitly set rules too.
  mkdir off
  cp noise.md builtins.md off/
  ln -s ${lib.markdownlint.config pkgs { profile = "off"; }}/.markdownlint-cli2.jsonc off/
  markdownlint-cli2 --config ${
    lib.markdownlint.config pkgs { profile = "hybrid"; }
  }/.markdownlint-cli2.jsonc 'off/*.md' 2>&1 | grep -E '^off/' > actual-off-folder.txt || true
  diff -u /dev/null actual-off-folder.txt
  touch "$out"
''
