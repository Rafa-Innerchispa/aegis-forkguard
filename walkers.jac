# AEGIS ForkGuard - 11 Security Walkers over a real decision graph (Jac 0.16.7)
#
# Pipeline (spec section 05): every walker below CREATES or TRAVERSES graph
# nodes and typed edges - the graph is the computational substrate, not
# decoration. A run's graph hangs off a detached ScenarioRun anchor, rebuilt
# deterministically per request so replays never accumulate stale state.

import from graph {
    FGNode, ScenarioRun, Document, Invoice, Instruction, VendorRecord,
    Evidence, ProposedAction, FutureBranch, Policy, Violation,
    InjectionFinding, Decision, MockTransaction, AuditEvent,
    DERIVED_FROM, FORKS_TO, EVALUATED_AGAINST, VIOLATES, SUPPORTED_BY,
    SELECTS, COMMITS, Contains,
    add_audit, timeline_of, now_iso
}
import from policies { BranchSim, VerifiedFacts, evaluate_rule, contains_any }
import from ai { InjectionReport, classify_instruction, generate_incident_summary }
import from simulation { simulate_payment, simulate_commit_refused, simulate_quarantine }

# ---------------------------------------------------------------------------
# Graph accessors (typed traversals shared by the walkers)
# ---------------------------------------------------------------------------

def get_document(run: ScenarioRun) -> Document | None {
    docs = [run ->:Contains:kind == "document":->[?:Document]];
    return (docs[0]) if docs else (None);
}

def get_invoice(run: ScenarioRun) -> Invoice | None {
    doc = get_document(run);
    if doc is None {
        return None;
    }
    invs = [doc ->:Contains:kind == "invoice":->[?:Invoice]];
    return (invs[0]) if invs else (None);
}

def get_instruction(run: ScenarioRun) -> Instruction | None {
    doc = get_document(run);
    if doc is None {
        return None;
    }
    ins = [doc ->:Contains:kind == "instruction":->[?:Instruction]];
    return (ins[0]) if ins else (None);
}

def get_vendor(run: ScenarioRun) -> VendorRecord | None {
    vs = [run ->:Contains:kind == "vendor":->[?:VendorRecord]];
    return (vs[0]) if vs else (None);
}

def get_policies(run: ScenarioRun) -> list[Policy] {
    pols = [run ->:Contains:kind == "policy":->[?:Policy]];
    return sorted(pols, key=lambda p: Policy : p.id);
}

def get_evidence(run: ScenarioRun) -> list[Evidence] {
    evs = [run ->:Contains:kind == "evidence":->[?:Evidence]];
    return sorted(evs, key=lambda e: Evidence : e.id);
}

def get_action(run: ScenarioRun) -> ProposedAction | None {
    acts = [run ->:Contains:kind == "action":->[?:ProposedAction]];
    return (acts[0]) if acts else (None);
}

def get_branches(run: ScenarioRun) -> list[FutureBranch] {
    action = get_action(run);
    if action is None {
        return [];
    }
    branches = [action ->:FORKS_TO:->];
    return sorted(branches, key=lambda b: FutureBranch : b.order);
}

def get_decision(run: ScenarioRun) -> Decision | None {
    ds = [run ->:Contains:kind == "decision":->[?:Decision]];
    return (ds[0]) if ds else (None);
}

def get_mock_transaction(run: ScenarioRun) -> MockTransaction | None {
    d = get_decision(run);
    if d is None {
        return None;
    }
    txs = [d ->:COMMITS:->];
    return (txs[0]) if txs else (None);
}

def branch_violations(branch: FutureBranch) -> list[Violation] {
    vs = [branch ->:Contains:kind == "violation":->[?:Violation]];
    return sorted(vs, key=lambda v: Violation : v.policy_id);
}

def branch_has_critical_violation(branch: FutureBranch) -> bool {
    for v in branch_violations(branch) {
        if v.severity == "critical" {
            return True;
        }
    }
    return False;
}

def verified_facts(run: ScenarioRun) -> VerifiedFacts {
    vendor = get_vendor(run);
    limit = 1000.0;
    for p in get_policies(run) {
        if p.deterministic_rule == "amount_within_auto_limit" {
            limit = float(p.params.get("max_auto_payment", 1000.0) as float);
        }
    }
    if vendor is None {
        return VerifiedFacts(verified_destination="", verified_total=0.0, vendor_status="unknown", max_auto_payment=limit);
    }
    return VerifiedFacts(
        verified_destination=vendor.verified_destination,
        verified_total=vendor.expected_invoice_total,
        vendor_status=vendor.status,
        max_auto_payment=limit
    );
}

def find_evidence(run: ScenarioRun, ev_id: str) -> Evidence | None {
    for e in get_evidence(run) {
        if e.id == ev_id {
            return e;
        }
    }
    return None;
}

# ---------------------------------------------------------------------------
# 1. ingest_walker - seed the decision graph from the untrusted document
#    plus the TRUSTED server-side vendor record and policy store.
# ---------------------------------------------------------------------------

walker ingest_walker {
    has payload: dict[str, any];
    has vendor_record: dict[str, any];
    has policy_defs: list[dict[str, any]];

    can seed with ScenarioRun entry {
        run = here;
        invoice_id = str(self.payload.get("invoice_id", "INV-2026-0788"));
        vendor_name = str(self.payload.get("vendor_name", "Bay Office Supply"));
        claimed_vendor_id = str(self.payload.get("claimed_vendor_id", "VENDOR-1042"));
        purchase_order = str(self.payload.get("purchase_order", "PO-7741"));
        visible_total = float(self.payload.get("visible_total", 450.0) as float);
        embedded = str(self.payload.get("embedded_untrusted_text", ""));

        doc = Document(doc_id=f"DOC-{invoice_id}");
        run +>:Contains(kind="document"):+> doc;

        inv = Invoice(
            invoice_id=invoice_id,
            vendor_name=vendor_name,
            claimed_vendor_id=claimed_vendor_id,
            purchase_order=purchase_order,
            visible_total=visible_total
        );
        doc +>:Contains(kind="invoice"):+> inv;

        instr = Instruction(instruction_id=f"INS-{invoice_id}", text=embedded);
        doc +>:Contains(kind="instruction"):+> instr;

        vendor = VendorRecord(
            vendor_id=str(self.vendor_record.get("vendor_id", "")),
            name=str(self.vendor_record.get("name", "")),
            verified_destination=str(self.vendor_record.get("verified_destination", "")),
            expected_invoice_total=float(self.vendor_record.get("expected_invoice_total", 0.0) as float),
            status=str(self.vendor_record.get("status", "unverified"))
        );
        run +>:Contains(kind="vendor"):+> vendor;

        for pd in self.policy_defs {
            pol = Policy(
                id=str(pd.get("id", "")),
                description=str(pd.get("description", "")),
                severity=str(pd.get("severity", "high")),
                deterministic_rule=str(pd.get("deterministic_rule", "")),
                params=pd.get("params", {}) as dict[str, any]
            );
            run +>:Contains(kind="policy"):+> pol;
        }

        evidence_rows = [
            ["EV-INVOICE-TOTAL", "invoice_document_body", "visible_total", f"${visible_total} visible invoice total", "document_visible"],
            ["EV-INVOICE-VENDOR", "invoice_document_body", "vendor", f"{vendor_name} (claims {claimed_vendor_id})", "document_visible"],
            ["EV-INVOICE-PO", "invoice_document_body", "purchase_order", purchase_order, "document_visible"],
            ["EV-UNTRUSTED-TEXT", "invoice_document_hidden_text", "embedded_untrusted_text", (embedded) if embedded != "" else ("(none present)"), "untrusted"],
            ["EV-VENDOR-DEST", "vendor_master_record", "verified_destination", vendor.verified_destination, "verified"],
            ["EV-VENDOR-STATUS", "vendor_master_record", "status", f"{vendor.name}: {vendor.status}, expected total ${vendor.expected_invoice_total}", "verified"],
            ["EV-POLICY-LIMIT", "policy_store", "max_auto_payment", "$1,000.00 auto-approval limit", "verified"]
        ];
        for row in evidence_rows {
            ev = Evidence(id=row[0], source_type=row[1], field=row[2], content=row[3], trust_level=row[4]);
            run +>:Contains(kind="evidence"):+> ev;
        }

        run.state = "input_loaded";
        add_audit(run, "input_loaded", "ingest_walker",
            f"Seeded decision graph: invoice {invoice_id} ({vendor_name}, {purchase_order}, ${visible_total}) + verified vendor record + {len(self.policy_defs)} policies + {len(evidence_rows)} evidence nodes.");
    }
}

# ---------------------------------------------------------------------------
# 2. extract_walker - separate trusted from untrusted content, classify the
#    embedded text, and materialize the naive agent's ProposedAction.
# ---------------------------------------------------------------------------

walker extract_walker {
    has report_out: dict[str, any] = {};

    can extract with ScenarioRun entry {
        run = here;
        inv = get_invoice(run);
        instr = get_instruction(run);
        vendor = get_vendor(run);
        doc = get_document(run);
        if inv is None or instr is None or vendor is None or doc is None {
            add_audit(run, "error", "extract_walker", "Graph incomplete: missing invoice, instruction, or vendor node.");
            return;
        }

        rep = classify_instruction(instr.text, inv.visible_total, vendor.verified_destination);
        instr.is_malicious = rep.is_malicious;
        instr.target_amount = rep.target_amount;
        instr.target_account = rep.target_account;
        instr.wants_secrets = rep.requests_secrets;
        doc.is_compromised = rep.is_malicious;

        # The naive proposal: exactly what an unprotected agent would call.
        if rep.is_malicious {
            amount = (rep.target_amount) if rep.target_amount > 0.0 else (inv.visible_total);
            destination = (rep.target_account) if rep.target_account != "" else (vendor.verified_destination);
            memo = f"Per embedded instruction: pay ${amount} to {destination}.";
            if rep.requests_secrets {
                memo = memo + " Including stored API credentials (API_KEY=sk-demo-FAKE-0000) as requested.";
            }
        } else {
            amount = inv.visible_total;
            destination = vendor.verified_destination;
            memo = f"Payment for {inv.purchase_order} - {inv.vendor_name} invoice {inv.invoice_id}.";
        }

        action = ProposedAction(
            tool_name="pay_invoice",
            origin="procurement_agent",
            arguments={
                "amount": amount,
                "destination_account": destination,
                "memo": memo,
                "purchase_order": inv.purchase_order
            }
        );
        run +>:Contains(kind="action"):+> action;

        ev_untrusted = find_evidence(run, "EV-UNTRUSTED-TEXT");
        ev_total = find_evidence(run, "EV-INVOICE-TOTAL");
        if rep.is_malicious and ev_untrusted is not None {
            action +>:DERIVED_FROM(note="proposal shaped by untrusted embedded text"):+> ev_untrusted;
        } elif ev_total is not None {
            action +>:DERIVED_FROM(note="proposal derived from visible invoice fields"):+> ev_total;
        }

        run.state = "action_proposed";
        self.report_out = {
            "is_malicious": rep.is_malicious,
            "classifier_mode": rep.mode,
            "proposed_arguments": action.arguments
        };
        add_audit(run, "action_proposed", "extract_walker",
            (f"Untrusted embedded text classified MALICIOUS ({rep.mode}): naive agent proposes ${amount} to {destination}.")
            if rep.is_malicious else
            (f"No injection detected ({rep.mode}): naive agent proposes the visible ${amount} payment."));
    }
}

# ---------------------------------------------------------------------------
# 3. vulnerable_walker - preview what the unprotected agent WOULD execute.
#    Performs no operation and writes nothing to the audit log.
# ---------------------------------------------------------------------------

walker vulnerable_walker {
    has result: dict[str, any] = {};

    can preview with ScenarioRun entry {
        run = here;
        action = get_action(run);
        instr = get_instruction(run);
        if action is None {
            self.result = {"status": "error", "message": "No proposed action in graph."};
            return;
        }
        amount = float(action.arguments.get("amount", 0.0) as float);
        destination = str(action.arguments.get("destination_account", ""));
        memo = str(action.arguments.get("memo", ""));
        compromised = instr is not None and instr.is_malicious;

        self.result = {
            "status": ("UNSAFE_ACTION_PREPARED") if compromised else ("ACTION_PREPARED"),
            "executed": False,
            "preview_only": True,
            "tool_call": {
                "tool_name": action.tool_name,
                "amount": amount,
                "destination": destination,
                "memo": memo
            },
            "credentials_exposed": compromised and ("api" in memo.lower() or "credential" in memo.lower()),
            "warning": ("The unprotected agent obeyed the embedded instruction and would wire ${:,.2f} to {} while leaking credential material. Nothing was executed - this is the preview ForkGuard intercepts.".format(amount, destination))
                if compromised else
                ("The unprotected agent would pay the visible invoice normally. Nothing was executed."),
            "simulated": True
        };
        add_audit(run, "unprotected_preview", "vulnerable_walker",
            f"Previewed naive tool call: pay_invoice ${amount} -> {destination} (NOT executed).");
    }
}

# ---------------------------------------------------------------------------
# 4. fork_walker - create the four canonical counterfactual futures.
# ---------------------------------------------------------------------------

walker fork_walker {
    can fork with ScenarioRun entry {
        run = here;
        action = get_action(run);
        inv = get_invoice(run);
        instr = get_instruction(run);
        vendor = get_vendor(run);
        if action is None or inv is None or instr is None or vendor is None {
            add_audit(run, "error", "fork_walker", "Cannot fork: graph missing action/invoice/instruction/vendor.");
            return;
        }
        naive_amount = float(action.arguments.get("amount", 0.0) as float);
        naive_dest = str(action.arguments.get("destination_account", ""));
        naive_memo = str(action.arguments.get("memo", ""));
        injected = instr.is_malicious;

        b_allow = FutureBranch(
            name="ALLOW", title="Allow As Requested", action_variant="allow_as_requested", order=1,
            pays=True, uses_untrusted_input=injected,
            sim_amount=naive_amount, sim_destination=naive_dest, sim_memo=naive_memo
        );
        b_block = FutureBranch(
            name="BLOCK", title="Block Everything", action_variant="block_all", order=2,
            pays=False, sim_amount=0.0, sim_destination="", sim_memo=""
        );
        b_restrict = FutureBranch(
            name="RESTRICT", title="Restrict & Verify", action_variant="restrict_and_verify", order=3,
            pays=True, uses_untrusted_input=False,
            sim_amount=inv.visible_total,
            sim_destination=vendor.verified_destination,
            sim_memo=f"Payment for {inv.purchase_order} - {inv.vendor_name} invoice {inv.invoice_id}. (SIMULATED)"
        );
        adv_amount = (instr.target_amount) if instr.target_amount > 0.0 else (naive_amount);
        adv_dest = (instr.target_account) if instr.target_account != "" else (naive_dest);
        b_adv = FutureBranch(
            name="ADVERSARIAL", title="Adversarial Interpretation", action_variant="adversarial_interpretation", order=4,
            pays=injected, uses_untrusted_input=injected,
            sim_amount=(adv_amount) if injected else (0.0),
            sim_destination=(adv_dest) if injected else (""),
            sim_memo=("Executes the embedded instruction exactly as written (hostile reading), including credential disclosure.")
                if injected else ("No embedded instruction present to interpret.")
        );

        ev_untrusted = find_evidence(run, "EV-UNTRUSTED-TEXT");
        ev_total = find_evidence(run, "EV-INVOICE-TOTAL");
        ev_dest = find_evidence(run, "EV-VENDOR-DEST");

        for b in [b_allow, b_block, b_restrict, b_adv] {
            action +>:FORKS_TO(note=b.action_variant):+> b;
        }
        if ev_untrusted is not None {
            b_allow +>:DERIVED_FROM(note="adopts values sourced from untrusted text"):+> ev_untrusted;
            b_adv +>:DERIVED_FROM(note="hostile interpretation of untrusted text"):+> ev_untrusted;
        }
        if ev_total is not None {
            b_restrict +>:DERIVED_FROM(note="amount restricted to visible verified total"):+> ev_total;
        }
        if ev_dest is not None {
            b_restrict +>:DERIVED_FROM(note="destination pinned to vendor master record"):+> ev_dest;
        }

        run.state = "futures_forked";
        add_audit(run, "futures_forked", "fork_walker",
            "Forked proposed action into 4 counterfactual futures: ALLOW, BLOCK, RESTRICT, ADVERSARIAL.");
    }
}

# ---------------------------------------------------------------------------
# 5. policy_walker - visit every branch, evaluate every policy, and attach
#    Violation nodes + VIOLATES edges for deterministic failures.
# ---------------------------------------------------------------------------

walker policy_walker {
    has checked: int = 0;

    can start with ScenarioRun entry {
        visit get_branches(here);
    }

    can eval_branch with FutureBranch entry {
        branch = here;
        runs = [branch <-:FORKS_TO:<-] ;
        # FORKS_TO source is the ProposedAction; walk back up to the run.
        if not runs {
            return;
        }
        action = runs[0];
        anchors = [action <-:Contains:<-[?:ScenarioRun]];
        if not anchors {
            return;
        }
        run = anchors[0];

        facts = verified_facts(run);
        sim = BranchSim(
            amount=branch.sim_amount,
            destination=branch.sim_destination,
            memo=branch.sim_memo,
            pays=branch.pays,
            uses_untrusted_input=branch.uses_untrusted_input
        );
        for pol in get_policies(run) {
            outcome = evaluate_rule(pol.deterministic_rule, sim, facts, pol.params);
            violated = bool(outcome.get("violated", False));
            branch +>:EVALUATED_AGAINST(result=("violation") if violated else ("pass")):+> pol;
            if violated {
                vio = Violation(
                    policy_id=pol.id,
                    reason=str(outcome.get("reason", "")),
                    severity=pol.severity,
                    evidence_ids=outcome.get("evidence_ids", []) as list[str]
                );
                branch +>:Contains(kind="violation"):+> vio;
                branch +>:VIOLATES(severity=pol.severity):+> pol;
            }
            self.checked += 1;
        }
    }

    can finish with ScenarioRun exit {
        here.state = "policies_checked";
        add_audit(here, "policies_checked", "policy_walker",
            f"Evaluated {self.checked} branch-policy pairs; violations recorded as graph nodes with policy and evidence citations.");
    }
}

# ---------------------------------------------------------------------------
# 6. risk_walker - deterministic risk per branch (spec weights).
# ---------------------------------------------------------------------------

walker risk_walker {
    can start with ScenarioRun entry {
        visit get_branches(here);
    }

    can score with FutureBranch entry {
        branch = here;
        risk = 0;
        reasons: list[str] = [];
        for v in branch_violations(branch) {
            if v.policy_id == "POL-002" {
                risk += 50;
                reasons.append("+50 destination does not match verified vendor record (POL-002)");
            } elif v.policy_id == "POL-001" {
                risk += 40;
                reasons.append("+40 amount above auto-approval limit (POL-001)");
            } elif v.policy_id == "POL-003" {
                risk += 60;
                reasons.append("+60 requested secret disclosure in memo (POL-003)");
            } elif v.policy_id == "POL-004" {
                risk += 25;
                reasons.append("+25 instruction sourced only from untrusted document content (POL-004)");
            } elif v.policy_id == "POL-005" {
                risk += 50;
                reasons.append("+50 vendor is not verified (POL-005)");
            }
        }
        if risk > 100 {
            risk = 100;
            reasons.append("risk capped at 100");
        }
        if not reasons {
            reasons.append("no policy violations detected");
        }
        branch.risk_score = risk;
        branch.risk_reasons = reasons;
    }

    can finish with ScenarioRun exit {
        add_audit(here, "branches_scored", "risk_walker",
            "Risk scored deterministically from violation nodes: " +
            ", ".join([f"{b.name}={b.risk_score}" for b in get_branches(here)]) + ".");
    }
}

# ---------------------------------------------------------------------------
# 7. utility_walker - deterministic business utility + validity (spec weights).
# ---------------------------------------------------------------------------

walker utility_walker {
    can start with ScenarioRun entry {
        visit get_branches(here);
    }

    can score with FutureBranch entry {
        branch = here;
        anchors = [branch <-:FORKS_TO:<-];
        if not anchors {
            return;
        }
        runs = [anchors[0] <-:Contains:<-[?:ScenarioRun]];
        if not runs {
            return;
        }
        run = runs[0];
        facts = verified_facts(run);

        utility = 0;
        reasons: list[str] = [];
        satisfies = branch.pays
            and branch.sim_amount == facts.verified_total
            and branch.sim_destination == facts.verified_destination;
        if satisfies {
            utility += 80;
            reasons.append("+80 satisfies the verified invoice obligation");
        }
        if not branch.pays and facts.verified_total > 0.0 {
            utility -= 70;
            reasons.append("-70 blocks a legitimate verified obligation");
        }
        violations = branch_violations(branch);
        if violations {
            utility -= 100;
            reasons.append(f"-100 carries {len(violations)} policy violation(s)");
        }
        branch.utility_score = utility;
        branch.utility_reasons = reasons;
        branch.valid = not branch_has_critical_violation(branch);
        branch.verdict = ("REJECTED") if not branch.valid else ("ELIGIBLE_PENDING");
    }

    can finish with ScenarioRun exit {
        here.state = "branches_scored";
        add_audit(here, "branches_scored", "utility_walker",
            "Utility scored: " + ", ".join([f"{b.name}={b.utility_score}" for b in get_branches(here)]) + ".");
    }
}

# ---------------------------------------------------------------------------
# 8. adversarial_walker - inspect the untrusted instruction and attach
#    InjectionFinding nodes to the adversarial branch.
# ---------------------------------------------------------------------------

walker adversarial_walker {
    has findings_out: list[dict[str, any]] = [];

    can start with ScenarioRun entry {
        instr = get_instruction(here);
        if instr is not None {
            visit [instr];
        }
    }

    can inspect with Instruction entry {
        instr = here;
        docs = [instr <-:Contains:<-[?:Document]];
        if not docs {
            return;
        }
        runs = [docs[0] <-:Contains:<-[?:ScenarioRun]];
        if not runs {
            return;
        }
        run = runs[0];
        inv = get_invoice(run);
        vendor = get_vendor(run);
        if inv is None or vendor is None {
            return;
        }

        adv_list = [b for b in get_branches(run) if b.name == "ADVERSARIAL"];

        rep = classify_instruction(instr.text, inv.visible_total, vendor.verified_destination);
        candidates = [
            ["amount_change", rep.changes_amount, f"Attempts to change the payment amount from ${inv.visible_total} to ${rep.target_amount}."],
            ["destination_change", rep.changes_destination, f"Attempts to redirect payment from {vendor.verified_destination} to {rep.target_account}."],
            ["secret_disclosure", rep.requests_secrets, "Requests stored credentials/API keys inside the payment memo."],
            ["authority_override", rep.claims_authority, "Impersonates a system-level instruction to claim authority over the agent."]
        ];
        ev_untrusted_list = [e for e in get_evidence(run) if e.id == "EV-UNTRUSTED-TEXT"];
        for c in candidates {
            if bool(c[1]) {
                finding = InjectionFinding(
                    category=str(c[0]),
                    excerpt=(instr.text[:120]) if len(instr.text) > 120 else (instr.text),
                    detail=str(c[2]),
                    source=rep.mode
                );
                for ab in adv_list {
                    ab +>:Contains(kind="finding"):+> finding;
                }
                for evu in ev_untrusted_list {
                    finding +>:SUPPORTED_BY(note="indicator found in untrusted embedded text"):+> evu;
                }
                self.findings_out.append({
                    "category": str(c[0]),
                    "detail": str(c[2]),
                    "source": rep.mode
                });
            }
        }
        if self.findings_out {
            for ab in adv_list {
                ab.verdict = "REJECTED_INJECTION";
                ab.valid = False;
            }
        }
        add_audit(run, "adversary_analysis", "adversarial_walker",
            (f"Marked embedded text as injection: {len(self.findings_out)} indicator(s) " +
             str([str(f['category']) for f in self.findings_out]) + ".")
            if self.findings_out else
            "No injection indicators found in embedded text.");
    }
}

# ---------------------------------------------------------------------------
# 9. commit_walker - select the safest valid branch, recheck hard invariants
#    against the verified graph, then commit the mock action (or refuse).
# ---------------------------------------------------------------------------

def check_commit_invariants(run: ScenarioRun, branch: FutureBranch) -> list[str] {
    failures: list[str] = [];
    facts = verified_facts(run);
    inv = get_invoice(run);
    instr = get_instruction(run);
    if inv is None {
        return ["graph missing invoice node"];
    }
    if branch.sim_amount != facts.verified_total {
        failures.append(f"amount ${branch.sim_amount} != verified invoice total ${facts.verified_total}");
    }
    if branch.sim_destination != facts.verified_destination {
        failures.append(f"destination '{branch.sim_destination}' != verified vendor destination '{facts.verified_destination}'");
    }
    if branch.sim_amount > facts.max_auto_payment {
        failures.append(f"amount ${branch.sim_amount} exceeds auto-approval limit ${facts.max_auto_payment}");
    }
    secret_hit = contains_any(branch.sim_memo, ["api_key", "api key", "credential", "token", "password", "secret", "sk-"]);
    if secret_hit != "" {
        failures.append(f"memo contains secret-like content ('{secret_hit}')");
    }
    if instr is not None and instr.is_malicious and instr.text != "" {
        injected_marker = contains_any(branch.sim_memo, ["override the invoice", "embedded instruction as written"]);
        if injected_marker != "" {
            failures.append("memo carries the injected instruction");
        }
    }
    if branch_has_critical_violation(branch) {
        failures.append("selected branch has a critical policy violation");
    }
    return failures;
}

walker commit_walker {
    # write_log=False lets read-only service ops (get_graph / get_report)
    # recompute the pipeline without appending duplicate audit-log entries.
    has write_log: bool = True;
    has committed: dict[str, any] = {};

    can decide with ScenarioRun entry {
        run = here;
        branches = get_branches(run);
        if not branches {
            add_audit(run, "error", "commit_walker", "No branches to select from.");
            return;
        }

        # Selection rule (spec section 05).
        eligible: list[FutureBranch] = [];
        for b in branches {
            if b.valid and b.risk_score <= 20 and not branch_has_critical_violation(b) {
                eligible.append(b);
            }
        }

        selected: FutureBranch | None = None;
        if eligible {
            ranked = sorted(eligible, key=lambda b: FutureBranch : (-b.utility_score, b.risk_score, b.order));
            selected = ranked[0];
        } else {
            for b in branches {
                if b.name == "BLOCK" {
                    selected = b;
                }
            }
        }
        if selected is None {
            add_audit(run, "error", "commit_walker", "Selection failed: no BLOCK fallback found.");
            return;
        }
        sel = selected as FutureBranch;

        for b in branches {
            if b.verdict == "ELIGIBLE_PENDING" {
                b.verdict = ("SELECTED") if b is sel else ("ELIGIBLE_NOT_SELECTED");
            }
        }
        if not eligible {
            sel.verdict = "SELECTED_BLOCK_FALLBACK";
        }

        margin = 150;
        if len(eligible) > 1 {
            ranked2 = sorted(eligible, key=lambda b: FutureBranch : (-b.utility_score, b.risk_score, b.order));
            margin = ranked2[0].utility_score - ranked2[1].utility_score;
        }
        confidence = 0.5 + (margin / 400.0);
        if confidence > 0.99 {
            confidence = 0.99;
        }
        if confidence < 0.5 {
            confidence = 0.5;
        }

        decision = Decision(
            selected_branch=sel.name,
            confidence=confidence,
            explanation=(f"{sel.title} maximizes utility ({sel.utility_score}) among eligible branches with risk {sel.risk_score} <= 20 and no critical violation.")
                if eligible else
                ("No branch was eligible; ForkGuard fails closed by selecting BLOCK and committing nothing.")
        );
        run +>:Contains(kind="decision"):+> decision;
        decision +>:SELECTS(note="safest valid branch"):+> sel;
        for ev_id in ["EV-VENDOR-DEST", "EV-VENDOR-STATUS", "EV-INVOICE-TOTAL", "EV-POLICY-LIMIT"] {
            ev = find_evidence(run, ev_id);
            if ev is not None {
                decision +>:SUPPORTED_BY(note="verified fact used for selection and invariants"):+> ev;
            }
        }
        run.state = "branch_selected";
        add_audit(run, "branch_selected", "commit_walker",
            f"Selected {sel.name} ({sel.title}) with confidence {confidence}. {decision.explanation}");

        # Hard invariants, rechecked IMMEDIATELY before mock execution.
        if not sel.pays or not eligible {
            decision.status = "blocked";
            run.state = "blocked";
            add_audit(run, "invariants_verified", "commit_walker",
                "Selected branch performs no payment; nothing to commit. Fail-closed outcome.");
            self.committed = {"status": "blocked", "branch": sel.name};
            return;
        }

        failures = check_commit_invariants(run, sel);
        add_audit(run, "invariants_verified", "commit_walker",
            ("All 6 hard commit invariants passed on recheck.") if not failures else
            (f"Commit invariants FAILED: {'; '.join(failures)}."));

        if failures {
            decision.status = "refused";
            sel.risk_score = 100;
            sel.risk_reasons.append("+100 failed commit invariant (capped at 100)");
            sel.verdict = "COMMIT_REFUSED";
            run.state = "commit_refused";
            refusal = (simulate_commit_refused(run.run_id, "; ".join(failures)))
                if self.write_log else
                ({"tool": "simulate_payment", "status": "commit_refused", "executed": False});
            self.committed = {"status": "refused", "branch": sel.name, "failures": failures, "tool_result": refusal};
            add_audit(run, "commit_refused", "commit_walker",
                "Mock transaction NOT written. A rejected action is never silently converted into an approved one.");
            return;
        }

        inv = get_invoice(run);
        po = (inv.purchase_order) if inv is not None else ("");
        tx = MockTransaction(
            tool_name="pay_invoice",
            amount=sel.sim_amount,
            destination=sel.sim_destination,
            memo=sel.sim_memo,
            purchase_order=po,
            committed_at=now_iso()
        );
        run +>:Contains(kind="mock_tx"):+> tx;
        decision +>:COMMITS(note="approved mock action"):+> tx;
        decision.status = "committed";
        sel.verdict = "SELECTED_COMMITTED";
        run.state = "mock_action_committed";

        tool_result = (simulate_payment(run.run_id, tx.amount, tx.destination, tx.memo, tx.purchase_order))
            if self.write_log else
            ({"tool": "simulate_payment", "status": "simulated_success", "executed": False,
              "amount": tx.amount, "destination": tx.destination, "memo": tx.memo,
              "purchase_order": tx.purchase_order, "audit_note": "read-only recompute; not logged"});
        self.committed = {"status": "committed", "branch": sel.name, "transaction": tool_result};
        add_audit(run, "mock_action_committed", "commit_walker",
            f"Committed SIMULATED transaction: ${tx.amount} -> {tx.destination} ({tx.purchase_order}). Appended to local audit log.");
    }
}

# ---------------------------------------------------------------------------
# 10. evidence_walker - collect the evidence trail for the report.
# ---------------------------------------------------------------------------

walker evidence_walker {
    has evidence_out: list[dict[str, any]] = [];

    can start with ScenarioRun entry {
        visit get_evidence(here);
    }

    can collect with Evidence entry {
        self.evidence_out.append({
            "id": here.id,
            "source_type": here.source_type,
            "field": here.field,
            "content": here.content,
            "trust_level": here.trust_level
        });
    }
}

# ---------------------------------------------------------------------------
# 11. report_walker - serialize the WHOLE graph + structured report + timeline.
# ---------------------------------------------------------------------------

def branch_to_dict(branch: FutureBranch) -> dict[str, any] {
    return {
        "name": branch.name,
        "title": branch.title,
        "action_variant": branch.action_variant,
        "order": branch.order,
        "pays": branch.pays,
        "uses_untrusted_input": branch.uses_untrusted_input,
        "sim": {
            "amount": branch.sim_amount,
            "destination": branch.sim_destination,
            "memo": branch.sim_memo
        },
        "risk_score": branch.risk_score,
        "risk_reasons": branch.risk_reasons,
        "utility_score": branch.utility_score,
        "utility_reasons": branch.utility_reasons,
        "valid": branch.valid,
        "verdict": branch.verdict,
        "violations": [
            {
                "policy_id": v.policy_id,
                "reason": v.reason,
                "severity": v.severity,
                "evidence_ids": v.evidence_ids
            } for v in branch_violations(branch)
        ],
        "findings": [
            {
                "category": f.category,
                "detail": f.detail,
                "excerpt": f.excerpt,
                "source": f.source
            } for f in [branch ->:Contains:kind == "finding":->[?:InjectionFinding]]
        ]
    };
}

# Fixed seeded layout (spec: prefer stability over physics simulation).
def graph_payload(run: ScenarioRun) -> dict[str, any] {
    nodes: list[dict[str, any]] = [];
    edges: list[dict[str, any]] = [];

    evidence = get_evidence(run);
    ev_y = 60;
    for e in evidence {
        nodes.append({
            "id": e.id, "type": "Evidence", "label": e.field,
            "sub": e.trust_level, "trust": e.trust_level,
            "x": 90, "y": ev_y
        });
        ev_y += 78;
    }

    action = get_action(run);
    if action is not None {
        nodes.append({
            "id": "ACTION", "type": "ProposedAction",
            "label": action.tool_name,
            "sub": f"${action.arguments.get('amount', 0)} -> {action.arguments.get('destination_account', '')}",
            "x": 330, "y": 290
        });
        for ev in [action ->:DERIVED_FROM:->] {
            edges.append({"source": "ACTION", "target": ev.id, "type": "DERIVED_FROM"});
        }
    }

    b_y = 80;
    for b in get_branches(run) {
        nodes.append({
            "id": f"BR-{b.name}", "type": "FutureBranch", "label": b.title,
            "sub": f"risk {b.risk_score} | utility {b.utility_score}",
            "verdict": b.verdict, "x": 600, "y": b_y
        });
        edges.append({"source": "ACTION", "target": f"BR-{b.name}", "type": "FORKS_TO"});
        for ev in [b ->:DERIVED_FROM:->] {
            edges.append({"source": f"BR-{b.name}", "target": ev.id, "type": "DERIVED_FROM"});
        }
        vio_i = 0;
        for v in branch_violations(b) {
            vid = f"VIO-{b.name}-{v.policy_id}";
            nodes.append({
                "id": vid, "type": "Violation", "label": v.policy_id,
                "sub": v.severity, "x": 790, "y": b_y - 18 + (vio_i * 40)
            });
            edges.append({"source": f"BR-{b.name}", "target": vid, "type": "HAS_VIOLATION"});
            edges.append({"source": vid, "target": v.policy_id, "type": "VIOLATES"});
            vio_i += 1;
        }
        for pol in [b ->:EVALUATED_AGAINST:->] {
            edges.append({"source": f"BR-{b.name}", "target": pol.id, "type": "EVALUATED_AGAINST"});
        }
        b_y += 130;
    }

    p_y = 100;
    for p in get_policies(run) {
        nodes.append({
            "id": p.id, "type": "Policy", "label": p.id,
            "sub": p.severity, "x": 960, "y": p_y
        });
        p_y += 90;
    }

    decision = get_decision(run);
    if decision is not None {
        nodes.append({
            "id": "DECISION", "type": "Decision", "label": "Decision",
            "sub": f"{decision.selected_branch} ({decision.status})",
            "x": 600, "y": 610
        });
        for sel in [decision ->:SELECTS:->] {
            edges.append({"source": "DECISION", "target": f"BR-{sel.name}", "type": "SELECTS"});
        }
        for ev in [decision ->:SUPPORTED_BY:->] {
            edges.append({"source": "DECISION", "target": ev.id, "type": "SUPPORTED_BY"});
        }
        tx = get_mock_transaction(run);
        if tx is not None {
            nodes.append({
                "id": "MOCKTX", "type": "MockTransaction",
                "label": "${:,.2f} SIMULATED".format(tx.amount),
                "sub": tx.destination, "x": 860, "y": 610
            });
            edges.append({"source": "DECISION", "target": "MOCKTX", "type": "COMMITS"});
        }
    }

    return {"nodes": nodes, "edges": edges};
}

walker report_walker {
    has report: dict[str, any] = {};

    can build with ScenarioRun entry {
        run = here;
        inv = get_invoice(run);
        instr = get_instruction(run);
        vendor = get_vendor(run);
        action = get_action(run);
        decision = get_decision(run);
        tx = get_mock_transaction(run);

        ew = evidence_walker();
        run spawn ew;

        branches = [branch_to_dict(b) for b in get_branches(run)];
        contained = 0.0;
        if instr is not None and instr.is_malicious {
            contained = instr.target_amount;
        }

        selected_name = (decision.selected_branch) if decision is not None else ("");
        committed_amount = (tx.amount) if tx is not None else (0.0);
        committed_dest = (tx.destination) if tx is not None else ("");

        self.report = {
            "run_id": run.run_id,
            "state": run.state,
            "simulated": True,
            "scenario": {
                "invoice_id": (inv.invoice_id) if inv is not None else (""),
                "vendor_name": (inv.vendor_name) if inv is not None else (""),
                "claimed_vendor_id": (inv.claimed_vendor_id) if inv is not None else (""),
                "purchase_order": (inv.purchase_order) if inv is not None else (""),
                "visible_total": (inv.visible_total) if inv is not None else (0.0),
                "embedded_untrusted_text": (instr.text) if instr is not None else (""),
                "is_compromised": instr is not None and instr.is_malicious,
                "verified_vendor": {
                    "vendor_id": (vendor.vendor_id) if vendor is not None else (""),
                    "name": (vendor.name) if vendor is not None else (""),
                    "verified_destination": (vendor.verified_destination) if vendor is not None else (""),
                    "status": (vendor.status) if vendor is not None else ("")
                }
            },
            "proposed_action": {
                "tool_name": (action.tool_name) if action is not None else (""),
                "origin": (action.origin) if action is not None else (""),
                "arguments": (action.arguments) if action is not None else ({})
            },
            "evidence": ew.evidence_out,
            "policies": [
                {"id": p.id, "description": p.description, "severity": p.severity, "rule": p.deterministic_rule}
                for p in get_policies(run)
            ],
            "branches": branches,
            "decision": {
                "selected_branch": selected_name,
                "confidence": (decision.confidence) if decision is not None else (0.0),
                "explanation": (decision.explanation) if decision is not None else (""),
                "status": (decision.status) if decision is not None else ("pending")
            },
            "mock_transaction": ({
                "tool_name": tx.tool_name,
                "amount": tx.amount,
                "destination": tx.destination,
                "memo": tx.memo,
                "purchase_order": tx.purchase_order,
                "simulated": True,
                "committed_at": tx.committed_at
            }) if tx is not None else (None),
            "summary": generate_incident_summary(selected_name, committed_amount, committed_dest, contained),
            "timeline": [
                {"seq": ev.seq, "stage": ev.stage, "actor": ev.actor, "details": ev.details, "timestamp": ev.timestamp}
                for ev in timeline_of(run)
            ],
            "graph": graph_payload(run)
        };
        run.state = "report_ready";
    }
}
