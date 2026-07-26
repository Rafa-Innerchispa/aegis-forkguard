# AEGIS ForkGuard - Entrypoint, Orchestration & Service Operations (Jac 0.16.7)
#
# SIMULATED ENVIRONMENT: every vendor, account, credential string, and
# transaction in this application is fictional. Mock actions are appended to
# a local audit log; nothing touches real systems.
#
# Serve:   jac start main.jac      ->  UI at http://localhost:8000/static/index.html
# CLI:     jac run main.jac        ->  deterministic terminal demo
# Tests:   jac test tests/forkguard_tests.jac

import json;
import os;
import from uuid { uuid4 }
import from graph { ScenarioRun, add_audit, now_iso }
import from walkers {
    ingest_walker, extract_walker, vulnerable_walker, fork_walker,
    policy_walker, risk_walker, utility_walker, adversarial_walker,
    commit_walker, evidence_walker, report_walker
}
import from ai { llm_enabled }

# ---------------------------------------------------------------------------
# Trusted server-side stores (never taken from the client payload)
# ---------------------------------------------------------------------------

def load_json_file(path: str) -> dict[str, any] {
    if not os.path.exists(path) {
        return {};
    }
    with open(path, "r") as f {
        data = json.loads(f.read());
    }
    return data as dict[str, any];
}

def vendor_record() -> dict[str, any] {
    return load_json_file(os.path.join("data", "vendor_record.json"));
}

def policy_defs() -> list[dict[str, any]] {
    data = load_json_file(os.path.join("data", "policies.json"));
    return data.get("policies", []) as list[dict[str, any]];
}

def demo_invoice(name: str) -> dict[str, any] {
    return load_json_file(os.path.join("data", name));
}

# ---------------------------------------------------------------------------
# Pipeline orchestration over a detached, per-run decision graph
# ---------------------------------------------------------------------------

def new_run(mode: str) -> ScenarioRun {
    return ScenarioRun(
        run_id=f"RUN-{str(uuid4())[:8]}",
        mode=mode,
        created_at=now_iso()
    );
}

def seed_run(run: ScenarioRun, payload: dict[str, any]) -> None {
    add_audit(run, "seeded", "forkguard", f"Run {run.run_id} created in SIMULATED environment (llm={'on' if llm_enabled() else 'off/deterministic'}).");
    run spawn ingest_walker(payload=payload, vendor_record=vendor_record(), policy_defs=policy_defs());
}

def run_unprotected_pipeline(payload: dict[str, any]) -> dict[str, any] {
    run = new_run("unprotected_preview");
    seed_run(run, payload);
    run spawn extract_walker();
    vw = vulnerable_walker();
    run spawn vw;
    rw = report_walker();
    run spawn rw;
    result = rw.report;
    result["mode"] = "VULNERABLE_RUN";
    result["unprotected_preview"] = vw.result;
    return result;
}

def run_forkguard_pipeline(payload: dict[str, any], write_log: bool) -> dict[str, any] {
    run = new_run("forkguard");
    seed_run(run, payload);
    run spawn extract_walker();
    run spawn fork_walker();
    run spawn policy_walker();
    run spawn risk_walker();
    run spawn utility_walker();
    run spawn adversarial_walker();
    run spawn commit_walker(write_log=write_log);
    rw = report_walker();
    run spawn rw;
    result = rw.report;
    result["mode"] = "FORKGUARD_RUN";
    return result;
}

def reset_pipeline() -> dict[str, any] {
    run = new_run("seeded");
    seed_run(run, demo_invoice("malicious_invoice.json"));
    rw = report_walker();
    run spawn rw;
    result = rw.report;
    result["mode"] = "RESET";
    result["state"] = "seeded";
    return result;
}

def effective_payload(payload: dict[str, any]) -> dict[str, any] {
    return (payload) if payload else (demo_invoice("malicious_invoice.json"));
}

# ---------------------------------------------------------------------------
# Service operations (spec section 08) - REST via `jac start`
# ---------------------------------------------------------------------------

# Preview what the naive agent proposed. Performs no action.
walker:pub run_vulnerable_api {
    has payload: dict[str, any] = {};

    can execute with Root entry {
        report run_unprotected_pipeline(effective_payload(self.payload));
    }
}

# Full deterministic pipeline: fork, evaluate, score, select, mock-commit.
walker:pub run_forkguard_api {
    has payload: dict[str, any] = {};

    can execute with Root entry {
        report run_forkguard_pipeline(effective_payload(self.payload), True);
    }
}

# Restore and return the canonical seeded state.
walker:pub reset_demo_api {
    can execute with Root entry {
        report reset_pipeline();
    }
}

# Nodes and edges used by the visualization (read-only recompute).
walker:pub get_graph_api {
    has payload: dict[str, any] = {};

    can execute with Root entry {
        full = run_forkguard_pipeline(effective_payload(self.payload), False);
        report {"run_id": full.get("run_id"), "state": full.get("state"), "graph": full.get("graph"), "simulated": True};
    }
}

# Structured evidence, violations, scores, decision, and mock commit.
walker:pub get_report_api {
    has payload: dict[str, any] = {};

    can execute with Root entry {
        report run_forkguard_pipeline(effective_payload(self.payload), False);
    }
}

# Seeded demo documents for the UI presets.
def:pub get_demo_safe_invoice() -> dict[str, any] {
    return demo_invoice("safe_invoice.json");
}

def:pub get_demo_attacked_invoice() -> dict[str, any] {
    return demo_invoice("malicious_invoice.json");
}

# ---------------------------------------------------------------------------
# Terminal demo (jac run main.jac)
# ---------------------------------------------------------------------------

with entry:__main__ {
    print("==============================================================");
    print("  AEGIS FORKGUARD  |  SIMULATED ENVIRONMENT  |  Jac 0.16.7");
    print("  A time machine for autonomous AI agents");
    print("==============================================================");
    payload = demo_invoice("malicious_invoice.json");
    print(f"\n[1] Untrusted invoice loaded: {payload.get('invoice_id')} from {payload.get('vendor_name')} (visible total ${payload.get('visible_total')}).");

    naive = run_unprotected_pipeline(payload);
    preview = naive.get("unprotected_preview", {}) as dict[str, any];
    print(f"\n[2] UNPROTECTED AGENT would call: {preview.get('tool_call')}");

    print("\n[3] Running ForkGuard counterfactual pipeline...");
    result = run_forkguard_pipeline(payload, True);
    for ev in result.get("timeline", []) as list[dict[str, any]] {
        print(f"    {ev.get('seq'):>2}. [{ev.get('stage')}] {ev.get('details')}");
    }
    decision = result.get("decision", {}) as dict[str, any];
    tx = result.get("mock_transaction");
    print(f"\n[4] DECISION: {decision.get('selected_branch')} ({decision.get('status')}) confidence={decision.get('confidence')}");
    if tx is not None {
        txd = tx as dict[str, any];
        print(f"    APPROVED WITH RESTRICTIONS -> SIMULATED payment of ${txd.get('amount')} to {txd.get('destination')} ({txd.get('purchase_order')}).");
    } else {
        print("    No transaction committed.");
    }
    print(f"\n    {result.get('summary')}");
}
