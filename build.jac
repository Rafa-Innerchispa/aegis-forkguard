# AEGIS ForkGuard - build pipeline (Jac 0.16.7)
#
# One command that proves the submission is sound:
#
#   jac script build
#
# Gates, in order. Any failure stops the build with a non-zero exit code.
#   1. TYPE CHECK   every first-party module passes `jac check`
#   2. LINT         no lint violations
#   3. TEST         the full acceptance suite passes
#   4. DEMO         a real `jac run main.jac` commits exactly $450.00 to the
#                   verified account (the P0 acceptance criterion)
#   5. LANG MIX     Jac is >= 40% of first-party executable source
#
# Deliberately runs the demo for real rather than trusting the test suite:
# tests and an end-to-end run are separate checks.

import os;
import shutil;
import subprocess;
import sys;
import time;
import from pathlib { Path }

glob MODULES: list[str] = [
    "main.jac", "graph.jac", "walkers.jac",
    "policies.jac", "ai.jac", "simulation.jac", "build.jac"
];
glob TEST_FILE: str = "tests/forkguard_tests.jac";

# The canonical demo must commit exactly this, or the build fails.
glob EXPECT_AMOUNT: str = "450.0";
glob EXPECT_DESTINATION: str = "acct_demo_verified_1042";
glob EXPECT_BRANCH: str = "RESTRICT";

glob MIN_JAC_PCT: float = 40.0;
glob TARGET_JAC_PCT: float = 60.0;

glob COUNTED: dict[str, str] = {
    ".jac": "Jac", ".py": "Python", ".js": "JavaScript",
    ".html": "HTML", ".css": "CSS"
};
glob EXECUTABLE: list[str] = ["Jac", "Python", "JavaScript"];
glob SKIP_DIRS: list[str] = [
    ".git", ".jac", "__pycache__", ".venv", "venv", "node_modules", "dist"
];
# Vendored upstream reference and runtime output are not first-party source.
glob SKIP_FILES: list[str] = ["jac-llmdocs.md", "forkguard_audit.log"];

obj CmdResult {
    has code: int;
    has out: str;
    has err: str;
}

obj Step {
    has name: str;
    has ok: bool;
    has detail: str;
    has seconds: float;
}

obj LangStat {
    has lang: str;
    has files: int;
    has lines: int;
}

def jac_exe() -> str {
    found = shutil.which("jac");
    return (str(found)) if found else ("jac");
}

def run_cmd(cmd: list[str]) -> CmdResult {
    try {
        proc = subprocess.run(cmd, capture_output=True, text=True);
        return CmdResult(
            code=int(proc.returncode),
            out=str(proc.stdout or ""),
            err=str(proc.stderr or "")
        );
    } except OSError as exc {
        return CmdResult(code=127, out="", err=str(exc));
    }
}

def hr(char: str) {
    print(char * 66);
}

def banner(text: str) {
    print("");
    hr("=");
    print(f"  {text}");
    hr("=");
}

# ---------------------------------------------------------------------------
# Gate 1+2: type check and lint
# ---------------------------------------------------------------------------

def gate_typecheck(jac: str) -> Step {
    started = time.time();
    failed: list[str] = [];
    for mod in MODULES {
        if not os.path.exists(mod) {
            failed.append(f"{mod} (missing)");
            continue;
        }
        res = run_cmd([jac, "check", mod]);
        marker = f"{mod} PASSED";
        combined = res.out + res.err;
        if marker not in combined {
            failed.append(mod);
            print(f"    x {mod}");
        } else {
            print(f"    + {mod}");
        }
    }
    checked = run_cmd([jac, "check", TEST_FILE]);
    if "PASSED" not in (checked.out + checked.err) {
        failed.append(TEST_FILE);
        print(f"    x {TEST_FILE}");
    } else {
        print(f"    + {TEST_FILE}");
    }
    return Step(
        name="type check",
        ok=len(failed) == 0,
        detail=(f"{len(MODULES) + 1} modules clean") if not failed else (f"failed: {', '.join(failed)}"),
        seconds=time.time() - started
    );
}

def gate_lint(jac: str) -> Step {
    started = time.time();
    res = run_cmd([jac, "lint", "."]);
    combined = res.out + res.err;
    clean = res.code == 0;
    detail = ("no violations") if clean else (combined.strip().splitlines()[-1] if combined.strip() else "lint reported violations");
    return Step(name="lint", ok=clean, detail=detail, seconds=time.time() - started);
}

# ---------------------------------------------------------------------------
# Gate 3: acceptance tests
# ---------------------------------------------------------------------------

def gate_tests(jac: str) -> Step {
    started = time.time();
    res = run_cmd([jac, "test", TEST_FILE]);
    combined = res.out + res.err;
    passed = "OK" in combined and "FAILED" not in combined;
    count = "";
    for line in combined.splitlines() {
        if line.strip().startswith("Ran ") {
            count = line.strip();
        }
    }
    return Step(
        name="acceptance tests",
        ok=passed,
        detail=(count) if count else ("no test summary found"),
        seconds=time.time() - started
    );
}

# ---------------------------------------------------------------------------
# Gate 4: the demo actually commits the right transaction
# ---------------------------------------------------------------------------

def gate_demo(jac: str) -> Step {
    started = time.time();
    res = run_cmd([jac, "run", "main.jac"]);
    combined = res.out + res.err;
    problems: list[str] = [];
    if res.code != 0 {
        problems.append(f"exit code {res.code}");
    }
    if EXPECT_BRANCH not in combined {
        problems.append(f"did not select {EXPECT_BRANCH}");
    }
    if EXPECT_AMOUNT not in combined {
        problems.append(f"did not commit ${EXPECT_AMOUNT}");
    }
    if EXPECT_DESTINATION not in combined {
        problems.append(f"did not pay {EXPECT_DESTINATION}");
    }
    if "45000" in combined and "contained" not in combined {
        problems.append("injected amount was not contained");
    }
    return Step(
        name="end-to-end demo",
        ok=len(problems) == 0,
        detail=(f"{EXPECT_BRANCH} committed ${EXPECT_AMOUNT} -> {EXPECT_DESTINATION}")
            if not problems else ("; ".join(problems)),
        seconds=time.time() - started
    );
}

# ---------------------------------------------------------------------------
# Gate 5: language mix (replaces the old scripts/langmix.py)
# ---------------------------------------------------------------------------

def is_skipped(path: Path) -> bool {
    for part in path.parts {
        if part in SKIP_DIRS {
            return True;
        }
    }
    return path.name in SKIP_FILES;
}

def count_lines(path: Path) -> int {
    try {
        text = path.read_text(encoding="utf-8", errors="replace");
        return len(text.splitlines());
    } except OSError {
        return 0;
    }
}

def language_stats() -> list[LangStat] {
    files: dict[str, int] = {};
    lines: dict[str, int] = {};
    for path in Path(".").rglob("*") {
        if not path.is_file() or is_skipped(path) {
            continue;
        }
        lang = COUNTED.get(path.suffix, "");
        if lang == "" {
            continue;
        }
        files[lang] = files.get(lang, 0) + 1;
        lines[lang] = lines.get(lang, 0) + count_lines(path);
    }
    stats = [LangStat(lang=k, files=files[k], lines=lines[k]) for k in files.keys()];
    return sorted(stats, key=lambda s: LangStat : -s.lines);
}

def gate_langmix() -> Step {
    started = time.time();
    stats = language_stats();
    total = sum([s.lines for s in stats]);
    exec_total = sum([s.lines for s in stats if s.lang in EXECUTABLE]);
    jac_lines = sum([s.lines for s in stats if s.lang == "Jac"]);
    if exec_total == 0 {
        return Step(name="language mix", ok=False, detail="no source found", seconds=time.time() - started);
    }
    jac_pct = 100.0 * jac_lines / exec_total;
    all_pct = (100.0 * jac_lines / total) if total > 0 else (0.0);

    print(f"    {'Language'.ljust(13)}{'Files'.rjust(6)}{'Lines'.rjust(8)}{'% exec'.rjust(9)}");
    print("    " + ("-" * 36));
    for s in stats {
        share = (f"{100.0 * s.lines / exec_total:.1f}%".rjust(9)) if s.lang in EXECUTABLE else ("".rjust(9));
        print(f"    {s.lang.ljust(13)}{str(s.files).rjust(6)}{str(s.lines).rjust(8)}{share}");
    }
    print("    " + ("-" * 36));
    print(f"    Jac: {jac_pct:.1f}% of executable source, {all_pct:.1f}% of all source");

    ok = jac_pct >= MIN_JAC_PCT;
    note = ("" ) if jac_pct >= TARGET_JAC_PCT else (f" (below {TARGET_JAC_PCT}% target)");
    return Step(
        name="language mix",
        ok=ok,
        detail=(f"{jac_pct:.1f}% Jac >= {MIN_JAC_PCT}% required{note}")
            if ok else (f"{jac_pct:.1f}% Jac is BELOW the {MIN_JAC_PCT}% requirement"),
        seconds=time.time() - started
    );
}

# ---------------------------------------------------------------------------
# Pipeline
# ---------------------------------------------------------------------------

def report(steps: list[Step]) -> bool {
    banner("BUILD SUMMARY");
    all_ok = True;
    for s in steps {
        mark = ("PASS") if s.ok else ("FAIL");
        print(f"  [{mark}] {s.name.ljust(20)} {s.seconds:5.1f}s  {s.detail}");
        if not s.ok {
            all_ok = False;
        }
    }
    hr("=");
    if all_ok {
        print("  BUILD PASSED - submission gates satisfied.");
        print("  Run the demo:  jac start main.jac  ->  http://localhost:8000/static/index.html");
    } else {
        print("  BUILD FAILED - fix the gates marked FAIL above.");
    }
    hr("=");
    return all_ok;
}

with entry:__main__ {
    root_dir = Path(str(__file__)).resolve().parent;
    os.chdir(str(root_dir));
    jac = jac_exe();

    banner("AEGIS FORKGUARD - BUILD PIPELINE");
    print(f"  toolchain : {jac}");
    print(f"  python    : {sys.version.split()[0]}");
    print(f"  project   : {root_dir}");

    steps: list[Step] = [];

    print("\n[1/5] Type checking modules...");
    steps.append(gate_typecheck(jac));

    print("\n[2/5] Linting...");
    steps.append(gate_lint(jac));

    print("\n[3/5] Running acceptance tests...");
    steps.append(gate_tests(jac));

    print("\n[4/5] Running the end-to-end demo...");
    steps.append(gate_demo(jac));

    print("\n[5/5] Measuring language mix...");
    steps.append(gate_langmix());

    ok = report(steps);
    sys.exit(0 if ok else 1);
}
