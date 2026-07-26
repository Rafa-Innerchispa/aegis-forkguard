# AEGIS ForkGuard - Local Tool Simulation Engine + Audit Log (Jac 0.16.7)
#
# Every "irreversible" operation in ForkGuard is a MOCK tool call. Nothing
# here touches a real bank, email system, or credential store. Committed mock
# actions are appended to a local JSONL audit log so the demo has a durable,
# inspectable record.

import json;
import os;
import from graph { now_iso }

glob AUDIT_LOG_PATH: str = "forkguard_audit.log";

def append_audit_log(record: dict[str, any]) -> None {
    try {
        record["logged_at"] = now_iso();
        record["simulated"] = True;
        with open(AUDIT_LOG_PATH, "a") as f {
            f.write(json.dumps(record) + "\n");
        }
    } except OSError {
        # The demo must not die on a read-only disk; the in-graph audit
        # timeline still records the event.
        return;
    }
}

def audit_log_size() -> int {
    if not os.path.exists(AUDIT_LOG_PATH) {
        return 0;
    }
    count = 0;
    with open(AUDIT_LOG_PATH, "r") as f {
        for _line in f {
            count += 1;
        }
    }
    return count;
}

def simulate_payment(run_id: str, amount: float, destination: str, memo: str, purchase_order: str) -> dict[str, any] {
    result = {
        "tool": "simulate_payment",
        "status": "simulated_success",
        "executed": False,
        "run_id": run_id,
        "amount": amount,
        "destination": destination,
        "memo": memo,
        "purchase_order": purchase_order,
        "audit_note": "SIMULATED ONLY - No actual fund transfer performed"
    };
    append_audit_log({"event": "mock_commit", "action": result});
    return result;
}

def simulate_commit_refused(run_id: str, reason: str) -> dict[str, any] {
    result = {
        "tool": "simulate_payment",
        "status": "commit_refused",
        "executed": False,
        "run_id": run_id,
        "reason": reason,
        "audit_note": "SIMULATED ONLY - Commit invariants failed; nothing was written"
    };
    append_audit_log({"event": "commit_refused", "run_id": run_id, "reason": reason});
    return result;
}

def simulate_credential_request(run_id: str) -> dict[str, any] {
    return {
        "tool": "simulate_credential_request",
        "status": "blocked_or_simulated",
        "executed": False,
        "run_id": run_id,
        "credentials_disclosed": False,
        "audit_note": "SIMULATED ONLY - Credential request intercepted"
    };
}

def simulate_quarantine(run_id: str, document_id: str) -> dict[str, any] {
    return {
        "tool": "simulate_quarantine",
        "status": "quarantined",
        "executed": False,
        "run_id": run_id,
        "document_id": document_id,
        "audit_note": "SIMULATED ONLY - Document flagged and isolated for forensic review"
    };
}
