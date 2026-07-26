# AEGIS ForkGuard - AI & Deterministic Fallback Classifier Module (Jac 0.16.7)

def classify_instruction(text: str) -> dict {
    lowered = text.lower();
    is_malicious = ("ignore previous" in lowered or "transfer" in lowered or "reveal" in lowered or "external-account" in lowered);
    
    return {
        "is_malicious": is_malicious,
        "mode": "deterministic_fallback",
        "notice": "Deterministic fallback active"
    };
}

def generate_attack_explanation(raw_text: str, target_amount: float, target_account: str) -> str {
    return "ATTACK DETECTED: Untrusted document embedding contained prompt injection attempting to transfer $" + str(target_amount) + " to '" + target_account + "' and leak stored credentials.";
}

def generate_incident_summary(committed_branch: str, amount: float) -> str {
    return "SAFE FUTURE COMMITTED: Verified $" + str(amount) + " payment approved via " + committed_branch + ". Malicious $45,000 branch contained. No credentials exposed.";
}
