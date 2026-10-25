# Each profile lints the fixtures and must report exactly what
# tests/expected-<profile>.txt lists. After a deliberate change to a profile or
# a custom rule, regenerate the expected files and review the diff.
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
  touch "$out"
''
