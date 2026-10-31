#!/usr/bin/env bash
# commit-msg-check: git commit-msg hook (.githooks/commit-msg), separate from
# repo-check because the message does not exist yet at the pre-commit stage.
# Enforces Conventional Commits 1.0.0: `type(scope): description`, scope
# optional, `!` for a breaking change. Then runs the repository's own checks of
# the message: the extraChecks with hook = "commit-msg" in REPO_CHECK_CONFIG
# (lib.mkRepo), each with the message file appended to its command.
set -euo pipefail

msg_file="$1"
status=0
# First real line: skip git's comment lines (an editor or a rebase leaves them
# in the file at this stage) and blank lines.
subject=$(grep -vE '^\s*#' "$msg_file" | grep -m1 -E '\S') || true

types="feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert"
if ! [[ "$subject" =~ ^($types)(\([a-z0-9_-]+\))?!?:\ .+ ]]; then
  echo "commit-msg: the subject is not a Conventional Commit:"
  echo "  \"$subject\""
  echo
  echo "Expected: type(scope): description, scope optional, type one of:"
  echo "  $types"
  echo "Examples:"
  echo "  feat(template): ask for the forge"
  echo "  docs: explain the licences"
  status=1
fi

if [ -n "${REPO_CHECK_CONFIG:-}" ]; then
  while IFS= read -r extra; do
    name=$(jq -r '.name' <<<"$extra")
    mapfile -t command < <(jq -r '.command[]' <<<"$extra")
    if ! output=$("${command[@]}" "$msg_file" 2>&1); then
      echo "commit-msg: $name failed:"
      printf '  %s\n' "${output//$'\n'/$'\n'  }"
      status=1
    fi
  done < <(jq -c '.extraChecks[]? | select(.hook == "commit-msg")' "$REPO_CHECK_CONFIG")
fi
exit "$status"
