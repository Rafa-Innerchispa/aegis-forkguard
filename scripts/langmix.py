#!/usr/bin/env python3
"""Report first-party source lines by extension.

Counts only hand-written source in this repository. Excludes vendored docs,
build output, caches, git metadata, and the runtime audit log so the reported
Jac percentage reflects real authored code.

Usage:  python scripts/langmix.py
"""

from __future__ import annotations

import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent

EXCLUDED_DIRS = {".git", ".jac", "__pycache__", ".venv", "venv", "node_modules", "dist"}
EXCLUDED_FILES = {"forkguard_audit.log"}
# Vendored upstream reference, not first-party source.
EXCLUDED_PATHS = {REPO / "docs" / "jac-llmdocs.md"}

COUNTED = {
    ".jac": "Jac",
    ".py": "Python",
    ".js": "JavaScript",
    ".html": "HTML",
    ".css": "CSS",
}
# Executable source only (docs/config excluded from the headline percentage).
EXECUTABLE = {"Jac", "Python", "JavaScript"}


def iter_files():
    for path in REPO.rglob("*"):
        if not path.is_file():
            continue
        if any(part in EXCLUDED_DIRS for part in path.parts):
            continue
        if path.name in EXCLUDED_FILES or path in EXCLUDED_PATHS:
            continue
        if path.suffix in COUNTED:
            yield path


def main() -> int:
    totals: dict[str, int] = {}
    files: dict[str, int] = {}
    for path in iter_files():
        lang = COUNTED[path.suffix]
        try:
            lines = len(path.read_text(encoding="utf-8", errors="replace").splitlines())
        except OSError as exc:
            print(f"skip {path}: {exc}", file=sys.stderr)
            continue
        totals[lang] = totals.get(lang, 0) + lines
        files[lang] = files.get(lang, 0) + 1

    grand = sum(totals.values())
    exec_total = sum(v for k, v in totals.items() if k in EXECUTABLE)
    jac = totals.get("Jac", 0)

    print(f"{'Language':<12}{'Files':>7}{'Lines':>9}{'% all':>9}{'% exec':>9}")
    print("-" * 46)
    for lang, lines in sorted(totals.items(), key=lambda kv: -kv[1]):
        pct_all = 100 * lines / grand if grand else 0
        pct_exec = 100 * lines / exec_total if lang in EXECUTABLE and exec_total else 0
        exec_col = f"{pct_exec:8.1f}%" if lang in EXECUTABLE else " " * 9
        print(f"{lang:<12}{files[lang]:>7}{lines:>9}{pct_all:8.1f}%{exec_col}")
    print("-" * 46)
    print(f"{'TOTAL':<12}{sum(files.values()):>7}{grand:>9}")
    print()
    print(f"Jac share of first-party executable source: {100 * jac / exec_total:.1f}%"
          f"  (requirement: >=40%, target: >=60%)")
    print(f"Jac share of all first-party source:        {100 * jac / grand:.1f}%")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
