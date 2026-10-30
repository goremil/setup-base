"""forge-ruleset: the default branch's ruleset on GitHub, as code (R-git-07).

Usage: forge-ruleset check|apply OWNER/REPO...

The ruleset is ruleset.json next to this script: on the default branch, signed
commits only, no force-push, no deletion, no bypass. `check` compares each
repository's ruleset of that name with it and exits 1 on a difference or a missing
ruleset; `apply` creates or updates it, which needs a token with the repository's
administration permission in GH_TOKEN or GITHUB_TOKEN. GitHub Free offers rulesets
only on public repositories: a private one is reported and skipped, since its
hooks and CI enforce R-git-07. FORGE_RULESET_API replaces the API's base URL, for
the tests.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

API = os.environ.get("FORGE_RULESET_API", "https://api.github.com")
FIELDS = ("target", "enforcement", "conditions", "rules", "bypass_actors")


def call(method: str, path: str, body: dict | None = None) -> object:
    req = urllib.request.Request(
        API + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={
            "Accept": "application/vnd.github+json",
            "Content-Type": "application/json",
        },
    )
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=30) as resp:
        text = resp.read().decode()
    return json.loads(text) if text else None


def normal(ruleset: dict) -> dict:
    """The fields compared, with rules in a fixed order."""
    out = {k: ruleset.get(k) for k in FIELDS}
    out["rules"] = sorted(
        out["rules"] or [], key=lambda r: json.dumps(r, sort_keys=True)
    )
    return out


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="forge-ruleset", description=__doc__.splitlines()[0]
    )
    parser.add_argument("action", choices=["check", "apply"])
    parser.add_argument("repos", nargs="+", metavar="OWNER/REPO")
    args = parser.parse_args()
    want = json.loads((Path(__file__).resolve().parent / "ruleset.json").read_text())
    status = 0
    for repo in args.repos:
        try:
            listed = call("GET", f"/repos/{repo}/rulesets")
        except urllib.error.HTTPError as e:
            if e.code == 403:
                print(
                    f"forge-ruleset: {repo}: no rulesets (private on GitHub Free), skipped"
                )
                continue
            if e.code == 404:
                print(f"forge-ruleset: {repo}: not found, or private and no token")
                status = 1
                continue
            raise
        assert isinstance(listed, list)
        found = next((r for r in listed if r.get("name") == want["name"]), None)
        have = call("GET", f"/repos/{repo}/rulesets/{found['id']}") if found else None
        if isinstance(have, dict) and normal(have) == normal(want):
            print(f"forge-ruleset: {repo}: {want['name']!r} as in ruleset.json")
            continue
        if args.action == "check":
            print(
                f"forge-ruleset: {repo}: {want['name']!r} "
                + ("differs" if have else "missing")
            )
            status = 1
        elif found:
            call("PUT", f"/repos/{repo}/rulesets/{found['id']}", want)
            print(f"forge-ruleset: {repo}: {want['name']!r} updated")
        else:
            call("POST", f"/repos/{repo}/rulesets", want)
            print(f"forge-ruleset: {repo}: {want['name']!r} created")
    return status


if __name__ == "__main__":
    sys.exit(main())
