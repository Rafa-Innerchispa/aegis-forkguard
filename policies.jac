# AEGIS ForkGuard - Deterministic Policy Rule Engine (Jac 0.16.7)
#
# Each rule is a pure function of explicit inputs and returns
# {"violated": bool, "reason": str, "evidence_ids": list[str]}, so every
# verdict is reproducible without any LLM. policy_walker connects the results
# to the graph as Violation nodes plus VIOLATES edges.

# Simulated facts of one future branch, as evaluated by the rules.
obj BranchSim {
    has amount: float;
    has destination: str;
    has memo: str;
    has pays: bool;
    has uses_untrusted_input: bool;
}

# Verified facts assembled from VendorRecord + Invoice graph nodes.
obj VerifiedFacts {
    has verified_destination: str;
    has verified_total: float;
    has vendor_status: str;
    has max_auto_payment: float;
}

def contains_any(text: str, markers: list[str]) -> str {
    low = text.lower();
    for m in markers {
        if m.lower() in low {
            return m;
        }
    }
    return "";
}

def rule_amount_within_auto_limit(sim: BranchSim, facts: VerifiedFacts, _params: dict[str, any]) -> dict[str, any] {
    if sim.pays and sim.amount > facts.max_auto_payment {
        return {
            "violated": True,
            "reason": f"Simulated payment of ${sim.amount} exceeds the ${facts.max_auto_payment} auto-approval limit.",
            "evidence_ids": ["EV-POLICY-LIMIT"]
        };
    }
    return {"violated": False, "reason": "", "evidence_ids": []};
}

def rule_destination_matches_vendor_record(sim: BranchSim, facts: VerifiedFacts, _params: dict[str, any]) -> dict[str, any] {
    if sim.pays and sim.destination != facts.verified_destination {
        return {
            "violated": True,
            "reason": f"Simulated destination '{sim.destination}' does not match the verified vendor destination '{facts.verified_destination}'.",
            "evidence_ids": ["EV-VENDOR-DEST"]
        };
    }
    return {"violated": False, "reason": "", "evidence_ids": []};
}

def rule_no_secrets_in_memo(sim: BranchSim, _facts: VerifiedFacts, params: dict[str, any]) -> dict[str, any] {
    markers: list[str] = params.get("secret_markers", []) as list[str];
    hit = contains_any(sim.memo, markers);
    if sim.pays and hit != "" {
        return {
            "violated": True,
            "reason": f"Simulated memo contains secret-like content (matched marker '{hit}'). Credentials may never enter payment memos.",
            "evidence_ids": ["EV-UNTRUSTED-TEXT"]
        };
    }
    return {"violated": False, "reason": "", "evidence_ids": []};
}

def rule_no_untrusted_instruction_override(sim: BranchSim, _facts: VerifiedFacts, _params: dict[str, any]) -> dict[str, any] {
    if sim.pays and sim.uses_untrusted_input {
        return {
            "violated": True,
            "reason": "Branch adopts payment values that originate only from untrusted embedded document text, not from any verified record.",
            "evidence_ids": ["EV-UNTRUSTED-TEXT", "EV-INVOICE-TOTAL"]
        };
    }
    return {"violated": False, "reason": "", "evidence_ids": []};
}

def rule_vendor_must_be_verified(sim: BranchSim, facts: VerifiedFacts, _params: dict[str, any]) -> dict[str, any] {
    if sim.pays and facts.vendor_status != "verified" {
        return {
            "violated": True,
            "reason": f"Vendor record status is '{facts.vendor_status}', not 'verified'. Payments require a verified vendor.",
            "evidence_ids": ["EV-VENDOR-STATUS"]
        };
    }
    return {"violated": False, "reason": "", "evidence_ids": []};
}

# Dispatch a named deterministic rule against a simulated branch.
def evaluate_rule(rule: str, sim: BranchSim, facts: VerifiedFacts, params: dict[str, any]) -> dict[str, any] {
    match rule {
        case "amount_within_auto_limit":
            return rule_amount_within_auto_limit(sim, facts, params);
        case "destination_matches_vendor_record":
            return rule_destination_matches_vendor_record(sim, facts, params);
        case "no_secrets_in_memo":
            return rule_no_secrets_in_memo(sim, facts, params);
        case "no_untrusted_instruction_override":
            return rule_no_untrusted_instruction_override(sim, facts, params);
        case "vendor_must_be_verified":
            return rule_vendor_must_be_verified(sim, facts, params);
        case _:
            return {"violated": False, "reason": f"Unknown rule '{rule}' treated as pass.", "evidence_ids": []};
    }
}
