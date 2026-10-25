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
arguments: `exclude` (regexes per check), `hugeFileKiB` and `extraChecks` (name and
command, run like the tool checks).
"""

import argparse
import json
import os
import re
import subprocess
import sys
import time
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
}


def load_config() -> dict:
    config = json.loads(json.dumps(DEFAULT_CONFIG))
    path = os.environ.get("REPO_CHECK_CONFIG")
    if path:
        with open(path, encoding="utf-8") as f:
            given = json.load(f)
        for key, patterns in given.get("exclude", {}).items():
            config["exclude"][key] = config["exclude"].get(key, []) + patterns
        for key in ("hugeFileKiB", "extraChecks", "rulesDir", "requiredDeviations"):
            if key in given:
                config[key] = given[key]
    return config


def excluded(config: dict, check: str, path: str) -> bool:
    return any(re.search(p, path) for p in config["exclude"].get(check, []))


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
# to their targets.
def repo_files() -> list[str]:
    files = git("ls-files", "--cached", "--others", "--exclude-standard")
    return [f for f in files if os.path.isfile(f) and not os.path.islink(f)]


def text_files(files: list[str]) -> list[str]:
    return [f for f in files if os.path.getsize(f) > 0 and not is_binary(f)]


def run_tool(*cmd: str) -> tuple[bool, str]:
    try:
        out = subprocess.run(
            cmd,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
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


# --- no dead relative .md links ---
MD_LINK = re.compile(r"\]\([^)]+\.md[^)]*\)")


def check_md_links(md_files: list[str]) -> tuple[bool, str]:
    msgs = []
    for f in md_files:
        base = os.path.dirname(f)
        for line in read_lines(f):
            for match in MD_LINK.findall(line):
                link = match[2:-1].split("#", 1)[0]
                if re.match(r"[a-z]+:", link):
                    continue
                target = os.path.realpath(os.path.join(base, link))
                if not os.path.isfile(target):
                    msgs.append(f"    {f} -> {link} (missing)")
    return not msgs, "\n".join(msgs)


# --- -ize spelling in prose (R-lang-04), and the British nouns that go with it. Two
#     fixed word lists, not a general regex, which would hit code and option names
#     that must stay as they are (`color` in CSS, `auto-optimise-store` in Nix). Only
#     .md files are checked, for the same reason. ---
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


def grep_words(files: list[str], words: list[str]) -> list[str]:
    """Like `grep -nwH WORD` for each word in turn: whole words, case-sensitive."""
    pattern = re.compile(
        r"(?<![A-Za-z0-9_])(" + "|".join(map(re.escape, words)) + r")(?![A-Za-z0-9_])"
    )
    hits = []
    for f in files:
        for n, line in enumerate(read_lines(f), 1):
            if pattern.search(line):
                hits.append(f"{f}:{n}:{line}")
    return hits


def check_spelling(md_files: list[str], config: dict) -> tuple[bool, str]:
    prose = [f for f in md_files if not excluded(config, "spelling", f)]
    hits = grep_words(prose, WRONG_VERBS + WRONG_NOUNS)
    return not hits, "\n".join(hits)


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
    files = repo_files()
    text = text_files(files)
    nix = [f for f in text if f.endswith(".nix")]
    md = [f for f in text if f.endswith(".md")]
    yaml = [f for f in text if re.search(r"\.ya?ml$", f)]
    py = [f for f in text if f.endswith(".py")]
    sh = [f for f in text if not f.endswith(".md") and is_bash_script(f)]
    cspell_config = next((c for c in CSPELL_CONFIGS if os.path.isfile(c)), None)
    yamllint_config = next((c for c in YAMLLINT_CONFIGS if os.path.isfile(c)), None)

    def tool(cmd: list[str], files: list[str], reason: str) -> object:
        return (lambda: run_tool(*cmd, *files)) if files else reason

    checks: list[tuple[str, object]] = [
        ("nixfmt --check", tool(["nixfmt", "--check"], nix, "no Nix files")),
        (
            "statix check",
            (lambda: run_tool("statix", "check", ".")) if nix else "no Nix files",
        ),
        ("deadnix --fail", tool(["deadnix", "--fail"], nix, "no Nix files")),
        (
            "cspell",
            tool(["cspell", "--no-progress"], nix + md, "no Nix or Markdown files")
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
        ("-ize spelling in prose", lambda: check_spelling(md, config)),
        ("no private-key material", lambda: check_no_leaked_keys(text, config)),
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
