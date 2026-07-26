# AEGIS ForkGuard - Deterministic Policy Engine (Jac 0.16.7)

def evaluate_branch_policy(
    proposed_amount: float,
    valid_invoice_amount: float,
    vendor_status: str,
    target_account: str,
    approved_account: str,
    attempts_credential_leak: bool,
    is_blocked: bool,
    is_quarantine: bool
) -> dict {
    has_violations = False;
    violations = [];

    if attempts_credential_leak {
        has_violations = True;
        violations.append("POLICY_VIOLATION: Credential disclosure is forbidden.");
    }

    if proposed_amount > 1000.00 {
        has_violations = True;
        violations.append("POLICY_VIOLATION: Amount $" + str(proposed_amount) + " exceeds maximum automatic payment limit of $1,000.00.");
    }

    if proposed_amount > valid_invoice_amount {
        has_violations = True;
        violations.append("POLICY_VIOLATION: Payment amount $" + str(proposed_amount) + " exceeds verified invoice amount $" + str(valid_invoice_amount) + ".");
    }

    if vendor_status != "verified" and proposed_amount > 0 {
        has_violations = True;
        violations.append("POLICY_VIOLATION: Vendor is unverified.");
    }

    if proposed_amount > 0 and target_account != approved_account {
        has_violations = True;
        violations.append("POLICY_VIOLATION: Destination account '" + target_account + "' does not match approved account '" + approved_account + "'.");
    }

    return {
        "valid": not has_violations,
        "violations": violations
    };
}
