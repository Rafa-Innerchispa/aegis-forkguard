# AGENTS.md — AI assistant context for ForkGuard

ForkGuard is a Jac (Jaseci) project, built and verified against **Jac 0.16.7 / Python 3.12**.

## Do not trust remembered Jac syntax

Jac evolves fast and most LLM training data about it is stale. Before editing any `.jac`
file, load the relevant guide from the **installed compiler** — these ship with the
toolchain and are the current source of truth:

```bash
jac guide                        # list all topics
jac guide jac-core-cheatsheet    # language baseline — read this first
jac guide jac-node-edge-patterns # graph shape, filters, typed edges
jac guide jac-walker-patterns    # visit/report/spawn, entry & exit abilities
jac guide jac-types              # annotations, `as` casts, any-boundary fixes
jac guide jac-by-llm             # by llm, sem, MockLLM
jac guide jac-sv-endpoints       # walker:pub / def:pub REST surface
jac guide jac-testing            # test blocks, shared root, jac clean
```

Order of authority: **installed compiler > `jac guide` / <https://docs.jaseci.org/> >
anything else**. Note that the older `candidate.txt` LLM-docs URL is dead; the release
asset is now `jac-llmdocs.md`, and it is already out of date relative to `jac guide`
(e.g. it claims ternaries and named `test` blocks don't work — both are fine in 0.16.7).

## Verify before you claim

```bash
jac script build                      # ALL FIVE GATES - run this before claiming done
jac check <file>.jac                  # type-check a single module
jac test tests/forkguard_tests.jac    # 15 acceptance tests
jac run main.jac                      # deterministic terminal demo
jac start main.jac                    # server + dashboard on :8000
jac clean --all --force               # clear caches + persisted graph data
```

`jac script build` (implemented in `build.jac`) is the authoritative gate: type check →
lint → tests → a **real** end-to-end demo asserting the $450 commit → language mix ≥40%.
It exits non-zero on any failure. `jac check` passing is **not** the same as tests
passing, and neither proves the demo still works — that's why the pipeline runs all three.

## Project rules

- Core logic (graph, walkers, policies, scoring, orchestration, tests) stays in `.jac`.
  Never port the decision path to Python or JavaScript.
- **The canonical demo must run with no API key and no network.** `by llm` is optional,
  merges by OR (can only widen suspicion), and always falls back deterministically.
- Every "irreversible" operation is a **mock** appended to `forkguard_audit.log`. Keep the
  SIMULATED ENVIRONMENT label visible in the UI and honest in all copy.
- **The UI never fabricates data.** `assets/app.js` renders only backend values. Do not add
  client-side simulations or hardcoded results — if the backend is down, show the error.
- Trusted data (vendor record, policies) is loaded server-side from `data/`. Never accept
  "verified" facts from the client payload.
- Behavior changes go in `docs/architecture.md` first, then the code.

## Gotchas this project already hit

- Non-default `has` fields must precede defaulted ones in an archetype.
- Typed edges: `a +>:Edge():+> b`. Filters: `[-->[?:Type, field > 1]]`, `[a ->:Edge:->]`.
- Declare edge endpoints (`edge E: Src --> Tgt {}`) or traversals return `Unknown`.
- `obj`, `node`, `edge`, `walker`, `can`, `has`, `report`, `entry`, `visit` are reserved —
  never use as variable or parameter names (`report = ...` inside a test is a parse error).
- `float(x)` where `x: any` fails E1053 — wrap as `float(str(x))`.
- `X | None` needs narrowing before attribute access; bind through a local
  (`sel = candidate as FutureBranch;`) or use a list comprehension instead.
- `as` casts inside a comprehension iterator need parentheses:
  `for e in (d.get("k", []) as list[dict[str, any]])`.
- Never name a test file `test_*.jac` — it collides with Python's test-module machinery.
  This repo uses `tests/forkguard_tests.jac`.
- Tests share one persisted `root` and persist to `.jac/data` between runs. ForkGuard
  sidesteps this by building each run's graph on a `ScenarioRun` anchor **detached from
  `root`** — keep it that way or replays will accumulate stale nodes.
- `jac start` requires a `jac.toml` in the cwd; static files are served from `assets/`
  at both `/static/<file>` and `/<file>`.
