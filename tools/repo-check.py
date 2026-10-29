"""Repository health gate: every check of a repository, in one run.

Run by the git pre-commit hook (.githooks/pre-commit, which enters the devShell first)
and by CI with -v (R-check-05, R-check-11). Keeps going past a failure and exits 1 if
any check failed.

Quiet report (R-check-10): one line when every check passes, else only the failed
checks with their output; skipped checks are always listed. -v prints every check's
output.

Which checks run follows the files the repository has: a tool check is skipped when
there is nothing for it (no YAML files, no cspell config). Per-repository settings
come from the JSON file named by REPO_CHECK_CONFIG, which `lib.mkRepo` writes from its
arguments: `exclude` (regexes per check), `hugeFileKiB`, `extraChecks` (name and
command, run like the tool checks) and `vendored` (folders kept verbatim, which every
check but gitleaks skips), `public`, `draftLanguages` and `cspellImports` (R-lang-10:
drafts in another language, refused in a public repository and spell-checked with
the dictionaries imported on top of the repository's cspell config).
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

VERBOSE = False

DEFAULT_CONFIG = {
    "exclude": {
        "spelling": [],
        "keys": [],
        "trailing-whitespace": [r"\.lock$"],
        "final-newline": [r"\.lock$"],
    },
    "hugeFileKiB": 1024,
    "extraChecks": [],
    "rulesDir": None,
    "requiredDeviations": [],
    "vendored": [],
    "public": False,
    "draftLanguages": [],
    "cspellImports": [],
}


def load_config() -> dict:
    config = json.loads(json.dumps(DEFAULT_CONFIG))
    path = os.environ.get("REPO_CHECK_CONFIG")
    if path:
        with open(path, encoding="utf-8") as f:
            given = json.load(f)
        for key, patterns in given.get("exclude", {}).items():
            config["exclude"][key] = config["exclude"].get(key, []) + patterns
        for key in (
            "hugeFileKiB",
            "extraChecks",
            "rulesDir",
            "requiredDeviations",
            "vendored",
            "public",
            "draftLanguages",
            "cspellImports",
        ):
            if key in given:
                config[key] = given[key]
    return config


def excluded(config: dict, check: str, path: str) -> bool:
    return any(re.search(p, path) for p in config["exclude"].get(check, []))


def is_draft(config: dict, path: str) -> bool:
    """A draft in another language (R-lang-10): `note.pl.md` for each draft language."""
    return any(path.endswith(f".{lang}.md") for lang in config["draftLanguages"])


def git(*args: str) -> list[str]:
    out = subprocess.run(["git", *args], check=True, capture_output=True, text=True)
    return [line for line in out.stdout.splitlines() if line]


def is_binary(path: str) -> bool:
    """Like `grep -I`: a NUL byte in the content marks a file as binary."""
    with open(path, "rb") as f:
        return b"\0" in f.read()


def read_lines(path: str) -> list[str]:
    with open(path, encoding="utf-8", errors="replace") as f:
        return f.read().splitlines()


# The files the checks look at (R-check-07): tracked plus new ones, never what
# .gitignore excludes; deleted but still tracked files are dropped. Symlinks are left
# to their targets, vendored folders to their upstream (gitleaks still scans them).
def repo_files(config: dict) -> list[str]:
    files = git("ls-files", "--cached", "--others", "--exclude-standard")
    return [
        f
        for f in files
        if os.path.isfile(f)
        and not os.path.islink(f)
        and not f.startswith(tuple(config["vendored"]))
    ]


def text_files(files: list[str]) -> list[str]:
    return [f for f in files if os.path.getsize(f) > 0 and not is_binary(f)]


def run_tool(*cmd: str, env: dict | None = None) -> tuple[bool, str]:
    try:
        out = subprocess.run(
            cmd,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            env=env,
        )
    except FileNotFoundError:
        return False, f"    {cmd[0]}: not found (is this the devShell?)"
    return out.returncode == 0, out.stdout.rstrip("\n")


def is_bash_script(path: str) -> bool:
    if path.endswith(".sh"):
        return True
    with open(path, "rb") as f:
        first = f.readline()
    return first.startswith(b"#!") and b"bash" in first


CSPELL_CONFIGS = [
    "cspell.config.yaml",
    "cspell.config.yml",
    "cspell.config.json",
    "cspell.json",
    ".cspell.json",
    "cspell.yaml",
    ".cspell.yaml",
]
YAMLLINT_CONFIGS = [".yamllint", ".yamllint.yml", ".yamllint.yaml"]


# --- no dead relative .md links, in prose: a link shown as code is an example. Links
#     out of the repository are the next check's. ---
MD_LINK = re.compile(r"\]\([^)]+\.md[^)]*\)")


def leaves_repo(path: str) -> bool:
    """A path relative to the top level that points outside it, symlinks not followed."""
    return os.path.relpath(os.path.abspath(path)).startswith("..")


def check_md_links(md_files: list[str]) -> tuple[bool, str]:
    msgs = []
    for f in md_files:
        base = os.path.dirname(f)
        for _, _, prose in prose_lines(f):
            for match in MD_LINK.findall(prose):
                link = match[2:-1].split("#", 1)[0]
                if re.match(r"[a-z]+:", link) or leaves_repo(os.path.join(base, link)):
                    continue
                target = os.path.realpath(os.path.join(base, link))
                if not os.path.isfile(target):
                    msgs.append(f"    {f} -> {link} (missing)")
    return not msgs, "\n".join(msgs)


# --- links out of the repository by a local path (R-link-15): a pair, the remote link
#     then `([local](path))`, or `([local](path))` alone for a place with no remote.
#     Locally the local half must exist, and a pair's two halves must name the same
#     file; a pair whose clone is missing is reported, not failed. In CI (CI=true)
#     there is no home directory: the remote half is checked through the forge's API,
#     anonymously for a public repository, with REPO_CHECK_FORGE_TOKEN for a private
#     one (which answers 404 without it), and local-only links are skipped and
#     counted. REPO_CHECK_FORGE_API replaces the API's base URL, for the tests. ---
LINK = re.compile(r"\[([^\]]*)\]\(([^)\s]+)\)")
FORGE_URL = re.compile(
    r"^https://(?P<host>[^/]+)/(?P<owner>[^/]+)/(?P<repo>[^/]+)"
    r"/(?:src/branch|blob|tree)/(?P<ref>[^/]+)/?(?P<path>[^#?]*)"
)


def forge_has(m: re.Match, token: str) -> str | None:
    """None when the forge has the file at that ref, else why not."""
    path = urllib.parse.unquote(m["path"]).rstrip("/")
    if m["host"] == "github.com":
        base = os.environ.get("REPO_CHECK_FORGE_API", "https://api.github.com")
        api = f"{base}/repos/{m['owner']}/{m['repo']}/contents/{path}"
    else:
        base = os.environ.get("REPO_CHECK_FORGE_API", f"https://{m['host']}")
        api = f"{base}/api/v1/repos/{m['owner']}/{m['repo']}/contents/{path}"
    headers = {"Authorization": f"token {token}"} if token else {}
    req = urllib.request.Request(f"{api}?ref={m['ref']}", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30):
            return None
    except urllib.error.HTTPError as e:
        if e.code in (401, 404) and not token:
            return "missing on the forge, or private: set REPO_CHECK_FORGE_TOKEN"
        return "missing on the forge" if e.code == 404 else f"forge answered {e.code}"
    except urllib.error.URLError as e:
        return f"forge not reached ({e.reason})"


def check_outside_links(md_files: list[str]) -> tuple[bool, str]:
    in_ci = os.environ.get("CI") == "true"
    token = os.environ.get("REPO_CHECK_FORGE_TOKEN", "")
    bad, notes = [], []
    pairs = local_only = 0
    for f in md_files:
        base = os.path.dirname(f)
        for n, _, prose in prose_lines(f):
            prev = None
            for m in LINK.finditer(prose):
                link = m[2].split("#", 1)[0]
                outside = (
                    link
                    and not re.match(r"[a-z]+:", link)
                    and leaves_repo(os.path.join(base, link))
                )
                if not outside:
                    prev = m
                    continue
                where = f"{f}:{n}: {link}"
                wrapped = (
                    prose[m.start() - 1 : m.start()] == "("
                    and prose[m.end() : m.end() + 1] == ")"
                )
                if m[1] != "local" or not wrapped:
                    bad.append(
                        f"    {where}: write `name ([local](path))`, after the remote link if there is one"
                    )
                    prev = m
                    continue
                remote = (
                    FORGE_URL.match(prev[2])
                    if prev and prose[prev.end() : m.start()] == " ("
                    else None
                )
                if remote:
                    pairs += 1
                    if in_ci:
                        if why := forge_has(remote, token):
                            bad.append(f"    {where}: {prev[2]} {why}")
                    else:
                        local = os.path.abspath(os.path.join(base, link)).rstrip("/")
                        tail = "/".join(
                            p
                            for p in [
                                remote["repo"],
                                urllib.parse.unquote(remote["path"]).rstrip("/"),
                            ]
                            if p
                        )
                        if not local.endswith("/" + tail):
                            bad.append(f"    {where}: does not match {prev[2]}")
                        elif not os.path.isdir(local[: -len(tail)] + remote["repo"]):
                            notes.append(f"    {where}: not cloned here")
                        elif not os.path.exists(local):
                            bad.append(f"    {where} (missing)")
                else:
                    local_only += 1
                    if not in_ci and not os.path.exists(os.path.join(base, link)):
                        bad.append(f"    {where} (missing)")
                prev = m
    summary = f"    {pairs} pair(s), {local_only} local-only link(s)" + (
        " (local-only not checkable in CI)" if in_ci and local_only else ""
    )
    if bad:
        return False, "\n".join(bad)
    return True, "\n".join([summary] + notes) if VERBOSE else ""


# The forbidden forms below are spelled out on purpose. cspell:disable
# --- -ize spelling in prose (R-lang-04), and the British nouns that go with it. Two
#     fixed word lists, not a general regex, which would hit code and option names
#     that must stay as they are (`color` in CSS, `auto-optimise-store` in Nix). Only
#     the prose of .md files is checked, for the same reason: fenced code blocks and
#     inline code spans are skipped. ---
WRONG_VERBS = [
    stem + ending
    for stem in [
        "authoris",
        "generalis",
        "memoris",
        "minimis",
        "optimis",
        "materialis",
        "initialis",
        "organis",
        "recognis",
        "realis",
        "prioritis",
        "summaris",
    ]
    for ending in ["e", "ed", "es", "ing", "ation", "ations"]
] + ["uninitialised", "unauthorised"]
WRONG_NOUNS = [
    "color",
    "colors",
    "colored",
    "coloring",
    "behavior",
    "behaviors",
    "favorite",
    "favorites",
]
# cspell:enable


FENCE = re.compile(r"^\s*(`{3,}|~{3,})")
CODE_SPAN = re.compile(r"(`+).+?\1")


def prose_lines(path: str) -> list[tuple[int, str, str]]:
    """Line number, line and its prose (code spans removed), outside fenced blocks."""
    lines, fence = [], None
    for n, line in enumerate(read_lines(path), 1):
        if m := FENCE.match(line):
            marker = m.group(1)
            if fence is None:
                fence = marker
            elif marker[0] == fence[0] and len(marker) >= len(fence):
                fence = None
            continue
        if fence is None:
            lines.append((n, line, CODE_SPAN.sub("", line)))
    return lines


def grep_words(files: list[str], words: list[str]) -> list[str]:
    """Like `grep -nwH WORD` over the prose of each file: whole words, case-sensitive."""
    pattern = re.compile(
        r"(?<![A-Za-z0-9_])(" + "|".join(map(re.escape, words)) + r")(?![A-Za-z0-9_])"
    )
    hits = []
    for f in files:
        for n, line, prose in prose_lines(f):
            if pattern.search(prose):
                hits.append(f"{f}:{n}:{line}")
    return hits


def check_spelling(md_files: list[str], config: dict) -> tuple[bool, str]:
    prose = [
        f
        for f in md_files
        if not excluded(config, "spelling", f) and not is_draft(config, f)
    ]
    hits = grep_words(prose, WRONG_VERBS + WRONG_NOUNS)
    return not hits, "\n".join(hits)


# --- cspell with the repository's own config, plus the dictionaries of the draft
#     languages (R-lang-10) imported on top in a config of its own, so the
#     repository's file never names a store path. The user's global cspell config
#     ($XDG_CONFIG_HOME/cspell) is kept out with an empty XDG_CONFIG_HOME, so a
#     word passes locally only if it passes in CI. ---
def run_cspell(cspell_config: str, config: dict, files: list[str]) -> tuple[bool, str]:
    with tempfile.TemporaryDirectory() as tmp:
        env = dict(os.environ, XDG_CONFIG_HOME=os.path.join(tmp, "config"))
        if not config["cspellImports"]:
            return run_tool("cspell", "--no-progress", *files, env=env)
        combined = os.path.join(tmp, "cspell.json")
        with open(combined, "w", encoding="utf-8") as f:
            imports = [os.path.abspath(cspell_config)] + config["cspellImports"]
            json.dump({"version": "0.2", "import": imports}, f)
        return run_tool(
            "cspell", "--no-progress", "--config", combined, *files, env=env
        )


# --- drafts in another language (R-lang-10): allowed in a private repository or a
#     vault, refused in a public one. ---
def check_drafts(md_files: list[str], config: dict) -> tuple[bool, str]:
    drafts = [f for f in md_files if is_draft(config, f)]
    if config["public"] and drafts:
        return False, "\n".join(
            f"{f}: a draft in another language, in a public repository" for f in drafts
        )
    note = f"    {len(drafts)} draft(s) in another language"
    return True, note if VERBOSE else ""


# --- no private-key material in plaintext: the age secret-key prefix and the standard
#     PEM private-key headers. A deliberate test key goes into `exclude.keys`. ---
KEY_PATTERNS = [
    "AGE-SECRET-KEY-1",
    "BEGIN OPENSSH PRIVATE KEY",
    "BEGIN RSA PRIVATE KEY",
    "BEGIN EC PRIVATE KEY",
    "BEGIN PRIVATE KEY",
    "BEGIN PGP PRIVATE KEY BLOCK",
]


def check_no_leaked_keys(files: list[str], config: dict) -> tuple[bool, str]:
    hits = []
    for f in files:
        if excluded(config, "keys", f):
            continue
        for n, line in enumerate(read_lines(f), 1):
            if any(p in line for p in KEY_PATTERNS):
                hits.append(f"{f}:{n}: private-key material")
    return not hits, "\n".join(hits)


# --- git-crypt: every tracked file its attributes give to git-crypt is stored
#     encrypted, so a missing filter (git-crypt not installed, or not set up in this
#     clone) never commits plain text. The check reads the index, so it holds in an
#     unlocked checkout and a locked one alike. A locked file (CI, a clone without
#     the key) is ciphertext, which every text check skips as binary; the count is
#     reported, so the skip is never silent. ---
GIT_CRYPT_HEADER = b"\0GITCRYPT\0"


def git_crypt_files() -> list[tuple[str, str]]:
    """(path, blob ID in the index) of each tracked file, not a symlink, with
    filter=git-crypt."""
    staged = subprocess.run(
        ["git", "ls-files", "--stage", "-z"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split("\0")
    # git-crypt leaves a symlink's target as it is.
    blobs = {
        e.split("\t", 1)[1]: e.split()[1]
        for e in staged
        if e and not e.startswith("120000 ")
    }
    if not blobs:
        return []
    attrs = subprocess.run(
        ["git", "check-attr", "-z", "--stdin", "filter"],
        input="\0".join(blobs),
        check=True,
        capture_output=True,
        text=True,
    ).stdout.split("\0")
    return [
        (path, blobs[path])
        for path, value in zip(attrs[0::3], attrs[2::3])
        if value == "git-crypt"
    ]


def check_git_crypt(entries: list[tuple[str, str]]) -> tuple[bool, str]:
    batch = subprocess.run(
        ["git", "cat-file", "--batch"],
        input="".join(f"{blob}\n" for _, blob in entries).encode(),
        check=True,
        capture_output=True,
    ).stdout
    plain, pos = [], 0
    for path, _ in entries:
        header_end = batch.index(b"\n", pos)
        size = int(batch[pos:header_end].split()[2])
        content = batch[header_end + 1 : header_end + 1 + size]
        pos = header_end + 1 + size + 1
        if not content.startswith(GIT_CRYPT_HEADER):
            plain.append(f"    {path}: given to git-crypt, but stored in plain text")
    if plain:
        return False, "\n".join(plain)
    locked = 0
    for path, _ in entries:
        if os.path.isfile(path):
            with open(path, "rb") as f:
                locked += f.read(len(GIT_CRYPT_HEADER)) == GIT_CRYPT_HEADER
    msg = f"    {len(entries)} file(s) encrypted with git-crypt"
    if locked:
        msg += f", {locked} locked here (their content is not checked)"
    return True, msg


# --- R-git-07: every commit reachable from HEAD and every tag carries a good
#     signature. Locally git verifies with the user's keyring. In CI (CI=true) there
#     is none, so the owner's public keys go into a scratch keyring, from the URL in
#     REPO_CHECK_SIGNING_KEYS or else from the forge, which serves a user's keys at
#     $GITHUB_SERVER_URL/$GITHUB_REPOSITORY_OWNER.gpg (GitHub and Forgejo alike).
#     %G? G is good, U good with a key of unknown validity, which an imported key
#     is; anything else fails, and so does a lightweight tag, which has no
#     signature to carry. ---
GOOD_SIGNATURE = {"G", "U"}


def ci_keyring() -> tuple[str | None, str]:
    """A scratch GNUPGHOME holding the owner's public keys, else why not."""
    src = os.environ.get("REPO_CHECK_SIGNING_KEYS", "")
    if not src:
        server = os.environ.get("GITHUB_SERVER_URL", "")
        owner = os.environ.get("GITHUB_REPOSITORY_OWNER", "")
        if not (server and owner):
            return None, "    no keys to verify with: set REPO_CHECK_SIGNING_KEYS"
        src = f"{server}/{owner}.gpg"
    try:
        with urllib.request.urlopen(src, timeout=30) as response:
            keys = response.read()
    except (urllib.error.URLError, ValueError) as e:
        return None, f"    keys not fetched from {src} ({e})"
    home = tempfile.mkdtemp(prefix="repo-check-gnupg-")
    imported = subprocess.run(
        ["gpg", "--batch", "--quiet", "--homedir", home, "--import"],
        input=keys,
        capture_output=True,
        check=False,
    )
    if imported.returncode != 0:
        return None, f"    keys from {src} not imported: {imported.stderr.decode()}"
    return home, src


def check_signatures() -> tuple[bool, str]:
    has_head = (
        subprocess.run(
            ["git", "rev-parse", "--verify", "--quiet", "HEAD"],
            capture_output=True,
            check=False,
        ).returncode
        == 0
    )
    tags = git("for-each-ref", "--format=%(refname:short) %(objecttype)", "refs/tags")
    if not has_head and not tags:
        return True, "    no commits or tags yet"
    env = dict(os.environ)
    if os.environ.get("CI") == "true":
        home, why = ci_keyring()
        if home is None:
            return False, why
        env["GNUPGHOME"] = home
    msgs = []
    commits = 0
    if has_head:
        log = subprocess.run(
            ["git", "log", "--format=%H %G? %s", "HEAD"],
            capture_output=True,
            text=True,
            check=True,
            env=env,
        ).stdout.splitlines()
        commits = len(log)
        for line in log:
            sha, status, subject = (line.split(" ", 2) + [""])[:3]
            if status not in GOOD_SIGNATURE:
                msgs.append(
                    f"    {sha[:8]} not signed with a good signature ({status}): {subject}"
                )
    for line in tags:
        name, kind = line.rsplit(" ", 1)
        if kind != "tag":
            msgs.append(f"    tag {name}: lightweight, so it carries no signature")
            continue
        verified = subprocess.run(
            ["git", "verify-tag", "--raw", name],
            capture_output=True,
            text=True,
            check=False,
            env=env,
        )
        if "[GNUPG:] GOODSIG" not in verified.stderr:
            msgs.append(f"    tag {name}: not signed with a good signature")
    if env.get("GNUPGHOME") != os.environ.get("GNUPGHOME"):
        subprocess.run(
            ["gpgconf", "--homedir", env["GNUPGHOME"], "--kill", "all"],
            capture_output=True,
            check=False,
        )
        shutil.rmtree(env["GNUPGHOME"], ignore_errors=True)
    if msgs:
        return False, "\n".join(msgs)
    return True, f"    {commits} commit(s) and {len(tags)} tag(s) signed"


# --- unresolved merge-conflict markers: these strings at line start mean nothing
#     else. ---
CONFLICT = re.compile(r"^(<{7}|={7}|>{7})( |$)")


def check_no_conflict_markers(files: list[str]) -> tuple[bool, str]:
    hits = []
    for f in files:
        for n, line in enumerate(read_lines(f), 1):
            if CONFLICT.match(line):
                hits.append(f"{f}:{n}:{line}")
    return not hits, "\n".join(hits)


# --- the git hooks stay executable: git skips a non-executable hook silently.
#     Symlinked hooks are checked through to their target. ---
def check_hooks_executable() -> tuple[bool, str]:
    msgs = []
    for hook in sorted(Path(".githooks").iterdir()):
        if not os.access(hook, os.X_OK):
            msgs.append(f"    not executable: {hook}")
    return not msgs, "\n".join(msgs)


# --- an odd number of ``` fences in a Markdown file leaves a code block open and
#     breaks the rendering of everything after it. ---
def check_balanced_fences(md_files: list[str]) -> tuple[bool, str]:
    msgs = []
    for f in md_files:
        count = sum(1 for line in read_lines(f) if line.lstrip().startswith("```"))
        if count % 2:
            msgs.append(f"    unbalanced ``` fences ({count}) in {f}")
    return not msgs, "\n".join(msgs)


# --- no accidental huge file (a downloaded image, a build artefact). ---
def check_no_huge_files(files: list[str], config: dict) -> tuple[bool, str]:
    limit = config["hugeFileKiB"]
    msgs = []
    for f in files:
        if excluded(config, "huge-files", f):
            continue
        if (size := os.path.getsize(f) // 1024) > limit:
            msgs.append(f"    {f} is {size} KiB (limit {limit} KiB)")
    return not msgs, "\n".join(msgs)


# --- trailing whitespace, except in .md, where two trailing spaces are a hard line
#     break. Independent of any editor's trim-on-save setting. ---
TRAILING = re.compile(r"[ \t]+$")


def check_no_trailing_whitespace(files: list[str], config: dict) -> tuple[bool, str]:
    msgs = []
    for f in files:
        if f.endswith(".md") or excluded(config, "trailing-whitespace", f):
            continue
        bad = [
            f"      {n}:{line}"
            for n, line in enumerate(read_lines(f), 1)
            if TRAILING.search(line)
        ]
        if bad:
            msgs.append(f"    trailing whitespace: {f}")
            msgs.extend(bad)
    return not msgs, "\n".join(msgs)


# --- every text file ends with a newline. Generated files that never do (flake.lock)
#     are excluded. ---
def check_final_newline(files: list[str], config: dict) -> tuple[bool, str]:
    msgs = []
    for f in files:
        if excluded(config, "final-newline", f):
            continue
        with open(f, "rb") as fh:
            fh.seek(-1, os.SEEK_END)
            if fh.read(1) != b"\n":
                msgs.append(f"    missing final newline: {f}")
    return not msgs, "\n".join(msgs)


# --- deviations (T4, R-rules-03): the "Deviations" table in AGENTS.md has a row
#     per departure from the setup-base rule core, with a rule ID that exists
#     there, what differs, the reason, a date and a decision. A departure that
#     lib.mkRepo can see (`requiredDeviations`) or a tracked lint config of the
#     repository's own (R-md-05) must have its row. With -v the rows are listed. ---
RULE_ID = re.compile(r"\*\*(R-[a-z]+-\d+)\*\*")
ROW_ID = re.compile(r"R-[a-z]+-\d+")
DATE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


def deviation_rows(path: str) -> list[list[str]]:
    rows, inside = [], False
    for line in read_lines(path):
        if line.startswith("## "):
            inside = line.strip() == "## Deviations"
            continue
        if inside and line.startswith("|"):
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            if cells[0] == "Rule" or set(cells[0]) <= {"-", " ", ":"}:
                continue
            rows.append(cells)
    return rows


def check_deviations(config: dict) -> tuple[bool, str]:
    known = set()
    for rules in Path(config["rulesDir"]).glob("*.md"):
        known.update(RULE_ID.findall(rules.read_text(encoding="utf-8")))
    required = list(config["requiredDeviations"])
    lint = Path(".markdownlint-cli2.jsonc")
    if lint.is_file() and not lint.is_symlink():
        required.append(
            {"rule": "R-md-05", "why": "a tracked .markdownlint-cli2.jsonc"}
        )
    rows = deviation_rows("AGENTS.md") if os.path.isfile("AGENTS.md") else []
    msgs, recorded = [], set()
    for cells in rows:
        ids = ROW_ID.findall(cells[0])
        problems = []
        if len(cells) != 5:
            problems.append(f"{len(cells)} columns, not 5")
        elif not all(cells):
            problems.append("an empty column")
        elif not DATE.match(cells[3]):
            problems.append(f"date {cells[3]!r} is not YYYY-MM-DD")
        if not ids:
            problems.append("no rule ID")
        problems += [f"{i} is not a setup-base rule" for i in ids if i not in known]
        recorded.update(ids)
        line = " | ".join(cells)
        msgs.append(f"    {line}" + (f"  <- {'; '.join(problems)}" if problems else ""))
    bad = [m for m in msgs if "  <- " in m]
    for need in required:
        if need["rule"] not in recorded:
            bad.append(f"    unrecorded: {need['rule']} ({need['why']})")
    listing = [f"    {len(rows)} deviation(s) recorded in AGENTS.md"] + msgs
    if not bad:
        return True, "\n".join(listing) if VERBOSE else ""
    return False, "\n".join(bad)


def checks_for(config: dict) -> list[tuple[str, object]]:
    files = repo_files(config)
    text = text_files(files)
    nix = [f for f in text if f.endswith(".nix")]
    md = [f for f in text if f.endswith(".md")]
    yaml = [f for f in text if re.search(r"\.ya?ml$", f)]
    py = [f for f in text if f.endswith(".py")]
    sh = [f for f in text if not f.endswith(".md") and is_bash_script(f)]
    cspell_config = next((c for c in CSPELL_CONFIGS if os.path.isfile(c)), None)
    yamllint_config = next((c for c in YAMLLINT_CONFIGS if os.path.isfile(c)), None)
    crypt = git_crypt_files()

    def tool(cmd: list[str], files: list[str], reason: str) -> object:
        return (lambda: run_tool(*cmd, *files)) if files else reason

    checks: list[tuple[str, object]] = [
        ("nixfmt --check", tool(["nixfmt", "--check"], nix, "no Nix files")),
        (
            "statix check",
            (
                lambda: run_tool(
                    "statix",
                    "check",
                    ".",
                    *(a for v in config["vendored"] for a in ("-i", f"{v}**")),
                )
            )
            if nix
            else "no Nix files",
        ),
        ("deadnix --fail", tool(["deadnix", "--fail"], nix, "no Nix files")),
        (
            "cspell",
            (lambda: run_cspell(cspell_config, config, nix + md))
            if cspell_config and nix + md
            else "no Nix or Markdown files"
            if cspell_config
            else "no cspell config",
        ),
        ("markdownlint", tool(["markdownlint-cli2"], md, "no Markdown files")),
        (
            "yamllint",
            tool(
                ["yamllint"] + ([] if yamllint_config else ["-d", "relaxed"]),
                yaml,
                "no YAML files",
            ),
        ),
        ("shellcheck", tool(["shellcheck"], sh, "no bash scripts")),
        ("ruff check", tool(["ruff", "check"], py, "no Python files")),
        (
            "ruff format --check",
            tool(["ruff", "format", "--check"], py, "no Python files"),
        ),
        (
            "reuse lint",
            (lambda: run_tool("reuse", "lint"))
            if os.path.isfile("REUSE.toml")
            else "no REUSE.toml",
        ),
        (
            "nix flake check",
            (lambda: run_tool("nix", "flake", "check"))
            if os.path.isfile("flake.nix")
            else "no flake.nix",
        ),
        ("no broken relative .md links", lambda: check_md_links(md)),
        ("links out of the repository", lambda: check_outside_links(md)),
        ("-ize spelling in prose", lambda: check_spelling(md, config)),
        ("drafts in another language", lambda: check_drafts(md, config)),
        ("no private-key material", lambda: check_no_leaked_keys(text, config)),
        (
            "git-crypt files encrypted",
            (lambda: check_git_crypt(crypt)) if crypt else "no git-crypt files",
        ),
        # gitleaks: what is staged now, then the whole history; in CI nothing is staged,
        # so the history scan carries it. --redact keeps a hit out of logs.
        (
            "gitleaks (staged)",
            lambda: run_tool(
                "gitleaks",
                "git",
                "--staged",
                "--redact",
                "--no-banner",
                "--log-level",
                "warn",
                ".",
            ),
        ),
        (
            "gitleaks (history)",
            lambda: run_tool(
                "gitleaks", "git", "--redact", "--no-banner", "--log-level", "warn", "."
            ),
        ),
        ("signed commits and tags", check_signatures),
        ("no merge-conflict markers", lambda: check_no_conflict_markers(text)),
        (
            "git hooks stay executable",
            check_hooks_executable if os.path.isdir(".githooks") else "no .githooks",
        ),
        ("balanced Markdown code fences", lambda: check_balanced_fences(md)),
        ("no huge files", lambda: check_no_huge_files(files, config)),
        (
            "no trailing whitespace (except .md)",
            lambda: check_no_trailing_whitespace(text, config),
        ),
        ("final newline", lambda: check_final_newline(text, config)),
        (
            "deviations recorded",
            (lambda: check_deviations(config))
            if config["rulesDir"]
            and (os.path.isfile("AGENTS.md") or config["requiredDeviations"])
            else "no AGENTS.md",
        ),
    ]
    for extra in config["extraChecks"]:
        checks.append((extra["name"], lambda cmd=extra["command"]: run_tool(*cmd)))
    return checks


def main() -> int:
    global VERBOSE
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="print every check's output"
    )
    VERBOSE = parser.parse_args().verbose
    os.chdir(git("rev-parse", "--show-toplevel")[0])

    start = time.monotonic()
    failed, skipped, ran = [], [], 0
    for name, check in checks_for(load_config()):
        if isinstance(check, str):
            skipped.append(f"{name} ({check})")
            continue
        ran += 1
        if VERBOSE:
            print(f"==> {name}", flush=True)
        ok, output = check()
        if VERBOSE and output:
            print(output, flush=True)
        if not ok:
            failed.append((name, output))
            if VERBOSE:
                print(f"    FAILED: {name}", flush=True)

    took = f"{time.monotonic() - start:.0f} s"
    if failed:
        if not VERBOSE:
            for name, output in failed:
                print(f"==> FAILED: {name}")
                if output:
                    print(output)
        print(
            f"\nrepo-check: {len(failed)} of {ran} checks failed ({took}). "
            "Fix the above and commit again."
        )
    else:
        print(f"repo-check: all {ran} checks passed ({took}).")
    for s in skipped:
        print(f"repo-check: skipped: {s}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
