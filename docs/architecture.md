# ForkGuard Architecture

> **SIMULATED ENVIRONMENT.** Every vendor, account, credential string, and
> transaction described here is fictional. "Committing" writes a JSON line to
> a local audit log. Nothing touches a real bank, mail system, or credential store.

## The core idea

A conventional guardrail answers *"does this request look bad?"* — a classifier
verdict on a single proposed action. ForkGuard asks a different question:

> **What would actually happen if we ran this — and what else could we run instead?**

The proposed tool call is never executed directly. It is **forked into explicit
future branches** as nodes in a Jac graph. Walkers traverse those branches,
attach policy violations as first-class nodes, score each future
deterministically, select the safest valid one, re-verify hard invariants, and
only then commit a mock action. The graph is both the computational substrate
and the visible explanation — the UI renders exactly the nodes and edges the
walkers built.

## Pipeline

```
                        ┌──────────────────────────────────┐
   UNTRUSTED            │  Document / Invoice / Instruction │
   document ───────────▶│  (client-supplied, never trusted)│
                        └──────────────┬───────────────────┘
   TRUSTED                             │
   server-side ──▶ VendorRecord ───────┤   ingest_walker
   stores      ──▶ Policy × 5  ────────┤   → 7 Evidence nodes w/ trust labels
                                       ▼
                            ┌──────────────────────┐
                            │    ProposedAction    │  extract_walker
                            │  pay_invoice $45,000 │  (classifies untrusted text,
                            │  → acct_..._991      │   builds the naive proposal)
                            └──────────┬───────────┘
                                       │ FORKS_TO ×4
              ┌────────────────┬───────┴────────┬─────────────────┐
              ▼                ▼                ▼                 ▼
        ┌──────────┐    ┌───────────┐    ┌────────────┐    ┌──────────────┐
        │ A. ALLOW │    │ B. BLOCK  │    │ C.RESTRICT │    │D.ADVERSARIAL │
        │ $45,000  │    │ pay $0    │    │  $450 →    │    │ hostile read │
        │ → ..._991│    │           │    │ ..._1042   │    │ of injection │
        └────┬─────┘    └─────┬─────┘    └─────┬──────┘    └──────┬───────┘
             │                │                │                  │
             └────────────────┴────────────────┴──────────────────┘
                                       │  policy_walker: EVALUATED_AGAINST / VIOLATES
                                       │  risk_walker + utility_walker: deterministic scores
                                       │  adversarial_walker: InjectionFinding nodes
                                       ▼
                            ┌──────────────────────┐
                            │       Decision       │  commit_walker
                            │  SELECTS → RESTRICT  │  (selection rule, then hard
                            │  confidence 0.875    │   invariants RE-checked)
                            └──────────┬───────────┘
                                       │ COMMITS
                                       ▼
                            ┌──────────────────────┐
                            │   MockTransaction    │  → forkguard_audit.log
                            │  $450.00 SIMULATED   │     (JSONL, append-only)
                            │  → acct_demo_..._1042│
                            └──────────────────────┘
```

## Graph model (`graph.jac`)

All archetypes inherit a shared `FGNode` base so mixed-endpoint edges stay typed.

| Node | Purpose |
|---|---|
| `ScenarioRun` | Per-run anchor. **Detached from `root` on purpose** — see determinism below. |
| `Document` / `Invoice` / `Instruction` | The untrusted document, its visible fields, and its embedded text. |
| `VendorRecord` | Trusted vendor master record, loaded server-side. |
| `Evidence` | A fact with provenance: `verified` \| `document_visible` \| `untrusted`. |
| `ProposedAction` | The naive agent's requested tool call. |
| `FutureBranch` | One counterfactual future, with simulated args + scores + verdict. |
| `Policy` | An enforceable constraint bound to a deterministic rule name. |
| `Violation` | A branch-specific failure citing its policy and evidence ids. |
| `InjectionFinding` | An injection indicator found in untrusted text. |
| `Decision` | The selection record (branch, confidence, explanation, status). |
| `MockTransaction` | The committed simulated action. |
| `AuditEvent` | Append-only timeline entry rendered in the UI. |

**Edges** (all typed, with endpoint types declared so traversals infer correctly):
`DERIVED_FROM`, `FORKS_TO`, `EVALUATED_AGAINST`, `VIOLATES`, `SUPPORTED_BY`,
`SELECTS`, `COMMITS`, plus `Contains` for run-scoped containment.

A canonical run builds **27 graph nodes and 51 edges**.

## Walkers (`walkers.jac`)

| Walker | Responsibility |
|---|---|
| `ingest_walker` | Builds document/invoice/instruction/vendor/policy/evidence nodes with trust labels. |
| `extract_walker` | Classifies untrusted text; materializes the `ProposedAction` + `DERIVED_FROM` provenance. |
| `vulnerable_walker` | Previews what the naive agent *would* call. Executes nothing, logs nothing. |
| `fork_walker` | Creates the 4 canonical `FutureBranch` nodes with `FORKS_TO` + evidence links. |
| `policy_walker` | `visit`s each branch; evaluates every policy; attaches `Violation` nodes + `VIOLATES` edges. |
| `risk_walker` | Deterministic risk from violation nodes (walker-side traversal). |
| `utility_walker` | Deterministic utility + validity; sets each branch verdict. |
| `adversarial_walker` | `visit`s the `Instruction`; attaches `InjectionFinding` nodes. |
| `commit_walker` | Selection rule → hard invariant recheck → mock commit or refusal. |
| `evidence_walker` | Collects the evidence trail for the report. |
| `report_walker` | Serializes the whole graph + report + timeline for the UI. |

`policy_walker`, `risk_walker`, `utility_walker`, `evidence_walker`, and
`adversarial_walker` are true traversals: they `visit` nodes and act in
node-typed entry abilities rather than looping over local data.

## Deterministic scoring

**Risk** starts at 0 and adds, per violation actually present on the graph:

| Trigger | Policy | Δ risk |
|---|---|---|
| Destination ≠ verified vendor destination | POL-002 | +50 |
| Amount above the auto-approval limit | POL-001 | +40 |
| Secret-like content in the memo | POL-003 | +60 |
| Values sourced only from untrusted text | POL-004 | +25 |
| Vendor not verified | POL-005 | +50 |
| Failed commit invariant | — | +100 |

Capped at 100. **Utility** starts at 0: `+80` satisfies the verified invoice
obligation, `−70` blocks a legitimate verified obligation, `−100` carries any
policy violation.

Canonical scenario result:

| Branch | Risk | Utility | Valid | Verdict |
|---|---:|---:|---|---|
| ALLOW | 100 | −100 | no | REJECTED |
| BLOCK | 0 | −70 | yes | ELIGIBLE_NOT_SELECTED |
| **RESTRICT** | **0** | **80** | **yes** | **SELECTED_COMMITTED** |
| ADVERSARIAL | 100 | −100 | no | REJECTED_INJECTION |

## Selection rule

```
eligible = branches where valid == true
                    AND risk_score <= 20
                    AND no critical violation
selected = eligible ordered by (highest utility, then lowest risk, then order)
if no eligible branch: select BLOCK and commit nothing   # fail closed
```

## Hard commit invariants

Re-checked **immediately before** mock execution, against the verified graph —
not against the values that were scored earlier. Any failure refuses the commit,
sets risk to 100, and writes a refusal record:

1. Amount equals the verified invoice total.
2. Destination equals the verified vendor destination.
3. Amount does not exceed the auto-approval limit.
4. Memo contains no credentials, tokens, or secrets.
5. Memo does not carry the injected instruction.
6. Selected branch has no critical violation.

This is what test **T06** exercises: tamper with the selected branch after
scoring, and the commit is refused with no transaction written.

## Determinism

The demo must produce byte-identical decisions on every replay:

- **Per-run detached graph.** `ScenarioRun` is deliberately *not* attached to
  `root`. Jac auto-persists anything reachable from `root` into `.jac/data`, so
  a root-anchored scenario would accumulate stale nodes across runs and across
  server restarts. Each request builds its own graph, which is then garbage.
- **Trusted data is server-side.** The vendor record and policy store are loaded
  from `data/` on the server. The client payload carries only the untrusted
  document, so a malicious payload can never assert its own "verified" facts.
- **No LLM in the decision path.** Scoring, policy evaluation, selection, and
  invariants are pure functions of explicit inputs.

Verified: three consecutive HTTP runs return identical decisions and
transactions (T08).

## LLM integration (`ai.jac`)

The deterministic classifier is the source of truth. With `OPENAI_API_KEY` or
`ANTHROPIC_API_KEY` set, a typed `by llm` classifier returning an
`InjectionReport` obj (described with `sem` annotations) runs *in addition*:

- Its findings are **merged by OR** — the LLM can only *widen* suspicion.
  An LLM "all clear" can never unflag a deterministic marker.
- Any exception, timeout, or malformed output falls back silently, and the
  report's `mode` field records which path ran
  (`deterministic_fallback` / `llm+deterministic` / `deterministic_fallback(llm_error)`).
- Hard policies always win; the LLM never influences commit invariants.

Covered by a `MockLLM` test that asserts a contradicting LLM cannot clear a
malicious document.

## Service surface

Served by `jac start main.jac` — one process, no separate Python web server.

| Endpoint | Response |
|---|---|
| `POST /walker/run_forkguard_api` | Full pipeline: timeline, branches, decision, mock commit, graph. |
| `POST /walker/run_vulnerable_api` | Naive proposal preview. Executes nothing. |
| `POST /walker/reset_demo_api` | Canonical seeded state. |
| `POST /walker/get_graph_api` | Nodes + edges for the visualization (read-only recompute). |
| `POST /walker/get_report_api` | Structured evidence, violations, scores, decision, commit. |
| `POST /function/get_demo_attacked_invoice` | Seeded injected document. |
| `POST /function/get_demo_safe_invoice` | Seeded clean document. |

Read-only operations pass `write_log=False` so recomputing the graph for the UI
never appends duplicate audit-log entries.

## UI honesty contract

`assets/app.js` renders **only** values returned by the backend. There are no
client-side simulations and no hardcoded results; if the server is unreachable
the dashboard shows an explicit error rather than a fabricated decision. Staged
playback paces the *real* walker timeline from a single backend response — it
controls presentation timing only, never content.
