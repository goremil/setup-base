#!/usr/bin/env bash
# pre-push-check <remote> <url>: the git pre-push hook's check (.githooks/pre-push,
# in the dev shell), on the commits about to leave, before the remote sees them:
#   - every commit carries a good signature (R-git-07): a forge marks an unsigned
#     one unverified, or rejects it where a ruleset asks for signed commits, and
#     signing it after the push means rewriting what others may have fetched;
#   - no fixup!/squash!/amend! commit is left: `git commit --fixup` and
#     `git absorb` make them, `git rebase -i --autosquash` folds them in.
# git passes one line per ref on stdin: <local ref> <local sha> <remote ref> <remote sha>.
# Skip with `git push --no-verify` (not recommended).
set -euo pipefail

zero=0000000000000000000000000000000000000000
status=0

while read -r local_ref local_sha _remote_ref remote_sha; do
  [ "$local_sha" != "$zero" ] || continue # deleting a remote ref
  if [ "$remote_sha" = "$zero" ]; then
    range=("$local_sha" --not --remotes) # a new ref: what no remote has yet
  else
    range=("$remote_sha..$local_sha")
  fi
  while IFS=' ' read -r sha sig subject; do
    case "$sig" in
      G | U) ;; # a good signature (U: good, the key's validity unknown)
      *)
        echo "pre-push: ${sha:0:8} on $local_ref is not signed with a good signature (%G? = $sig): $subject"
        status=1
        ;;
    esac
    case "$subject" in
      fixup!* | squash!* | amend!*)
        echo "pre-push: ${sha:0:8} on $local_ref is an unsquashed $subject"
        status=1
        ;;
    esac
  done < <(git log --format='%H %G? %s' "${range[@]}")
done

if [ "$status" -ne 0 ]; then
  echo "pre-push: nothing was pushed. Sign the commits (git rebase --exec 'git commit --amend --no-edit -S'), fold the fixups (git rebase -i --autosquash), then push again."
fi
exit "$status"
