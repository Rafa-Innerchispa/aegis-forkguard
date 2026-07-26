# AEGIS ForkGuard - Security Graph Model (Jac 0.16.7)
#
# The decision is represented as a REAL in-memory Jac graph, built fresh for
# every run: walkers create these nodes, connect them with the typed edges
# below, and traverse the connections to evaluate policies, score branches,
# select a future, and assemble the audit report. The UI renders this same
# graph, serialized by report_walker.

import from datetime { datetime, timezone }

# Common base so mixed-endpoint edges stay typed.
node FGNode {}

# Anchor for one ForkGuard run. Deliberately NOT attached to the persistent
# root: the scenario graph is rebuilt deterministically per run, so replays
# can never accumulate stale state (acceptance test T08).
node ScenarioRun(FGNode) {
    has run_id: str;
    has mode: str = "deterministic";
    has state: str = "seeded";
    has created_at: str = "";
    has audit_seq: int = 0;
}

node Document(FGNode) {
    has doc_id: str;
    has kind: str = "invoice";
    has is_compromised: bool = False;
}

# Verified-visible fields of the invoice document.
node Invoice(FGNode) {
    has invoice_id: str;
    has vendor_name: str;
    has claimed_vendor_id: str;
    has purchase_order: str;
    has visible_total: float;
    has currency: str = "USD";
}

# Untrusted text embedded in the document (the prompt injection carrier).
node Instruction(FGNode) {
    has instruction_id: str;
    has text: str;
    has trust_level: str = "untrusted";
    has is_malicious: bool = False;
    has target_amount: float = 0.0;
    has target_account: str = "";
    has wants_secrets: bool = False;
}

# Trusted vendor master record, loaded server-side (never from the client).
node VendorRecord(FGNode) {
    has vendor_id: str;
    has name: str;
    has verified_destination: str;
    has expected_invoice_total: float;
    has status: str = "verified";
}

# A fact or claim with explicit provenance. trust_level:
# verified | document_visible | untrusted
node Evidence(FGNode) {
    has id: str;
    has source_type: str;
    has field: str;
    has content: str;
    has trust_level: str;
}

# The naive agent's requested tool call.
node ProposedAction(FGNode) {
    has tool_name: str;
    has origin: str;
    has arguments: dict[str, any] = {};
    has status: str = "proposed";
}

# One counterfactual future produced from the proposed action.
node FutureBranch(FGNode) {
    has name: str;
    has title: str;
    has action_variant: str;
    has order: int = 0;
    has pays: bool = True;
    has uses_untrusted_input: bool = False;
    has sim_amount: float = 0.0;
    has sim_destination: str = "";
    has sim_memo: str = "";
    has risk_score: int = 0;
    has utility_score: int = 0;
    has valid: bool = True;
    has verdict: str = "PENDING";
    has risk_reasons: list[str] = [];
    has utility_reasons: list[str] = [];
}

# An enforceable safety constraint (deterministic rule reference).
node Policy(FGNode) {
    has id: str;
    has description: str;
    has severity: str;
    has deterministic_rule: str;
    has params: dict[str, any] = {};
}

# A branch-specific policy failure, citing its policy and evidence.
node Violation(FGNode) {
    has policy_id: str;
    has reason: str;
    has severity: str;
    has evidence_ids: list[str] = [];
}

# A deterministic (or LLM-assisted) injection indicator on untrusted text.
node InjectionFinding(FGNode) {
    has category: str;
    has excerpt: str;
    has detail: str;
    has source: str = "deterministic";
}

# The final selection record.
node Decision(FGNode) {
    has selected_branch: str;
    has confidence: float;
    has explanation: str;
    has status: str = "pending";
}

# The committed SIMULATED action. Only ever written to the local audit log.
node MockTransaction(FGNode) {
    has tool_name: str;
    has amount: float;
    has destination: str;
    has memo: str;
    has purchase_order: str;
    has simulated: bool = True;
    has committed_at: str = "";
}

# Append-only timeline entry for the visible walker activity feed.
node AuditEvent(FGNode) {
    has seq: int;
    has stage: str;
    has actor: str;
    has details: str;
    has timestamp: str = "";
}

# ---------------------------------------------------------------------------
# Required relationship types (spec section 04) + Contains for containment.
# ---------------------------------------------------------------------------

# Action or branch originated from specified evidence.
edge DERIVED_FROM: FGNode --> Evidence {
    has note: str = "";
}

# Proposed action created a possible future branch.
edge FORKS_TO: ProposedAction --> FutureBranch {
    has note: str = "";
}

# Branch was checked against a policy.
edge EVALUATED_AGAINST: FutureBranch --> Policy {
    has result: str = "pass";
}

# Branch conflicts with a policy.
edge VIOLATES: FutureBranch --> Policy {
    has severity: str = "";
}

# Decision or finding is justified by evidence.
edge SUPPORTED_BY: FGNode --> Evidence {
    has note: str = "";
}

# Decision chose one branch.
edge SELECTS: Decision --> FutureBranch {
    has note: str = "";
}

# Approved decision produced one mock action.
edge COMMITS: Decision --> MockTransaction {
    has note: str = "";
}

# Structural containment within one scenario run.
edge Contains: FGNode --> FGNode {
    has kind: str = "";
}

# ---------------------------------------------------------------------------
# Shared graph helpers
# ---------------------------------------------------------------------------

def now_iso() -> str {
    return datetime.now(timezone.utc).isoformat();
}

# Append an audit event to the run timeline and return it.
def add_audit(run: ScenarioRun, stage: str, actor: str, details: str) -> AuditEvent {
    run.audit_seq += 1;
    ev = AuditEvent(
        seq=run.audit_seq,
        stage=stage,
        actor=actor,
        details=details,
        timestamp=now_iso()
    );
    run +>:Contains(kind="audit"):+> ev;
    return ev;
}

# All audit events of a run, in append order.
def timeline_of(run: ScenarioRun) -> list[AuditEvent] {
    events = [run ->:Contains:kind == "audit":->[?:AuditEvent]];
    return sorted(events, key=lambda e: AuditEvent : e.seq);
}
