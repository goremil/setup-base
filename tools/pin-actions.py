"""pin-actions: GitHub workflow actions pinned by commit, at their latest release.

Usage: pin-actions [--check] [FILE...]

Default files: .github/workflows/*.yml and *.yaml, and the same in a
Copier template (template/.github/workflows/).

Each `uses: OWNER/REPO[/PATH]@REF` whose comment, or else whose REF, is a version
(`v7`, `v7.0.1`) moves to the commit of OWNER/REPO's latest release, the release's
tag as the comment: `uses: actions/checkout@<sha> # v7.0.1`. Any other reference (a
branch, a local `./action`, a URL) is listed and left alone. With --check nothing is
written and the exit status is 1 when an action is behind. The updates are written
locally and committed with the author's signature (R-git-07), never by a bot.

GITHUB_TOKEN or GH_TOKEN, when set, raises GitHub's rate limit for anonymous calls
(60 an hour); PIN_ACTIONS_API replaces the API's base URL, for the tests.
"""

import argparse
import glob
import json
import os
import re
import sys
import urllib.request

API = os.environ.get("PIN_ACTIONS_API", "https://api.github.com")
USES = re.compile(
    r"^(?P<lead>\s*-?\s*uses:\s*)(?P<repo>[\w.-]+/[\w.-]+)(?P<path>/[^@\s]*)?"
    r"@(?P<ref>[^\s#]+)(?:\s*#\s*(?P<comment>.*?))?\s*$"
)
VERSION = re.compile(r"^v?\d+(\.\d+)*$")


def get(path: str, accept: str = "application/vnd.github+json") -> str:
    req = urllib.request.Request(API + path, headers={"Accept": accept})
    token = os.environ.get("GITHUB_TOKEN") or os.environ.get("GH_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode()


def latest(repo: str, cache: dict[str, tuple[str, str]]) -> tuple[str, str]:
    """(tag, commit) of the repository's latest release."""
    if repo not in cache:
        tag = json.loads(get(f"/repos/{repo}/releases/latest"))["tag_name"]
        sha = get(f"/repos/{repo}/commits/{tag}", "application/vnd.github.sha").strip()
        cache[repo] = (tag, sha)
    return cache[repo]


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="pin-actions", description=__doc__.splitlines()[0]
    )
    parser.add_argument("--check", action="store_true", help="report, write nothing")
    parser.add_argument("files", nargs="*")
    args = parser.parse_args()
    files = args.files or sorted(
        f
        for pattern in (".github/workflows/*.y*ml", "template/.github/workflows/*.y*ml")
        for f in glob.glob(pattern)
    )
    cache: dict[str, tuple[str, str]] = {}
    behind, left = [], []
    for f in files:
        with open(f, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
        changed = False
        for n, line in enumerate(lines):
            m = USES.match(line)
            if not m:
                continue
            current = (m["comment"] or m["ref"]).split()[0]
            if not VERSION.match(current):
                left.append(
                    f"{f}:{n + 1}: {m['repo']}@{m['ref']} (not a version, left alone)"
                )
                continue
            tag, sha = latest(m["repo"], cache)
            if m["ref"] == sha and m["comment"] == tag:
                continue
            behind.append(f"{f}:{n + 1}: {m['repo']} {current} -> {tag}")
            lines[n] = f"{m['lead']}{m['repo']}{m['path'] or ''}@{sha} # {tag}"
            changed = True
        if changed and not args.check:
            with open(f, "w", encoding="utf-8") as fh:
                fh.write("\n".join(lines))
    for msg in left:
        print(f"pin-actions: {msg}")
    for msg in behind:
        print(f"pin-actions: {msg}" + ("" if args.check else " (updated)"))
    if not behind:
        print(f"pin-actions: {len(cache)} action(s) at their latest release")
    return 1 if behind and args.check else 0


if __name__ == "__main__":
    sys.exit(main())
