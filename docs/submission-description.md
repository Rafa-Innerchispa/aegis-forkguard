# ForkGuard — submission description

## One-liner

ForkGuard gives every AI agent a chance to see the future before it makes an irreversible
mistake.

## Short description (for the submission form)

ForkGuard is a counterfactual execution layer for autonomous AI agents. Before a
consequential tool call reaches the real world, ForkGuard represents the proposed action
and its evidence as a Jac graph, creates multiple possible future branches, and sends
specialized walkers through those branches to test policies, trace provenance, calculate
risk, and select the safest valid outcome.

In our demonstration, a procurement agent encounters a prompt injection that tries to turn
a legitimate $450 invoice into a $45,000 transfer and expose credentials. ForkGuard rejects
the unsafe futures and commits only a simulated $450 payment to the verified vendor.

Jac is the core of the application: typed nodes and edges model the decision space, walkers
perform the investigation and policy evaluation, and `by llm` optionally adds semantic
analysis behind a deterministic fallback. The result is a visible, auditable preview of
what an AI agent's action could cause before anything irreversible happens.

**Everything in the demo is a simulation** — all vendors, accounts, credentials, and
transactions are fictional, and committed actions are written only to a local audit log.

## What makes it different

Most agent-safety work scores a single proposed action: *"does this request look
malicious?"* That produces one opinion about one action, with no notion of what else the
agent could have done instead — which is why such systems tend to collapse into blanket
blocking.

ForkGuard's differentiator is **counterfactual pre-execution**. The risky call is forked
into explicit future-state branches that are simulated, scored, and selectively committed.
That reframing is what lets the system reject a $45,000 wire *and still pay the real $450
invoice* — the difference between a guardrail that says no and one that finds the safe
version of yes.

The graph is not a visualization of reasoning that happened elsewhere; it is the
computational substrate. Walkers traverse it, violations attach to it as first-class nodes
citing their policy and evidence, branch risk is derived from each branch's graph
neighborhood, and the UI renders exactly those nodes and edges.

## How Jac / Jaseci is used

**~75% of first-party executable source is Jac.** Every component that makes a decision is
in `.jac`.

- **Object-Spatial Programming.** Twelve typed node archetypes on a shared `FGNode` base,
  connected by eight typed edges with declared endpoints (`FORKS_TO: ProposedAction -->
  FutureBranch`, `VIOLATES: FutureBranch --> Policy`, `COMMITS: Decision -->
  MockTransaction`, …), so every traversal infers its node type.
- **Walkers.** Eleven walkers implement the pipeline. The evaluation stages are genuine
  traversals: `policy_walker`, `risk_walker`, `utility_walker`, `evidence_walker`, and
  `adversarial_walker` `visit` nodes and act inside node-typed entry abilities, with
  `with ScenarioRun exit` abilities aggregating after traversal completes.
- **Graph-derived scoring.** A branch's risk is computed by reading the `Violation` nodes
  attached to it — the score is a property of graph shape, not of a passed-in dict.
- **`by llm` with a deterministic spine.** A typed `by llm` classifier returns an
  `InjectionReport` obj described with `sem` annotations. Its findings merge by OR, so the
  model can only widen suspicion, never clear a deterministic marker; any failure falls
  back silently and the run records which path executed. Verified with a `MockLLM` test.
- **Full-stack Jac.** `jac start main.jac` serves both the REST surface (`walker:pub`
  endpoints) and the dashboard from `assets/` in a single process — no separate Python web
  server.
- **Jac tests.** 15 acceptance tests in `tests/forkguard_tests.jac` spawn real walkers
  against real graphs.

## Demo determinism

The seeded scenario runs with no network access and no API key, and produces byte-identical
decisions on every replay. Each request builds a fresh per-run graph on a `ScenarioRun`
anchor deliberately detached from `root`, so Jac's auto-persistence cannot accumulate stale
state across runs or restarts. Trusted data (vendor record, policy store) is loaded
server-side, so a malicious client payload cannot assert its own "verified" facts.

## Tracks

- **Agentic AI** — pre-execution safety for autonomous tool-using agents.
- **AI for Defense** — indirect prompt-injection containment with auditable provenance.
- **Best Use of Jaclang** — graph, walkers, policies, scoring, invariants, orchestration,
  and tests all in Jac.

## Honesty statement

ForkGuard is a hackathon prototype and a decision-support demonstration, not a certified
security product. Its deterministic classifier matches known injection patterns and does
not claim to detect all attacks; its guarantee is narrower and stronger — no committed
action can deviate from the verified invoice total and vendor destination, because those
invariants are re-checked immediately before execution. No LLM prediction is presented as
proof of real-world safety.
