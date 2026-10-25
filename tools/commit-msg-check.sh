#!/usr/bin/env bash
# commit-msg-check: git commit-msg hook (.githooks/commit-msg), separate from
# repo-check because the message does not exist yet at the pre-commit stage.
# Enforces Conventional Commits 1.0.0: `type(scope): description`, scope
# optional, `!` for a breaking change.
set -euo pipefail

msg_file="$1"
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
  exit 1
fi
