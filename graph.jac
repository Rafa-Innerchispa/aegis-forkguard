# AEGIS ForkGuard - Security Graph Model in Jaclang (Jac 0.16.7)

node Source {
    has name: str = "External Input";
    has source_type: str = "untrusted_document";
}

node Document {
    has doc_id: str;
    has raw_text: str;
    has is_compromised: bool = False;
}

node Invoice {
    has invoice_id: str;
    has vendor: str;
    has vendor_status: str;
    has valid_amount: float;
    has payment_account: str;
}

node Instruction {
    has instruction_id: str;
    has text: str;
    has is_malicious: bool;
    has target_amount: float = 0.0;
    has target_account: str = "";
}

node Agent {
    has agent_id: str = "invoice_processor_v1";
    has role: str = "Automated Accounts Payable Agent";
}

node ProposedAction {
    has action_id: str;
    has action_type: str;
    has amount: float;
    has destination: str;
}

node Tool {
    has tool_id: str;
    has tool_name: str;
}

node Asset {
    has asset_id: str;
    has name: str;
    has max_limit: float = 1000.00;
}

node Policy {
    has policy_id: str;
    has name: str;
    has description: str;
    has max_allowed_payment: float = 1000.00;
    has require_verified_vendor: bool = True;
    has forbid_credential_leak: bool = True;
}

node Evidence {
    has evidence_id: str;
    has description: str;
    has severity: str;
}

node FutureBranch {
    has branch_id: str;
    has label: str;
    has proposed_amount: float;
    has target_account: str;
    has risk_score: int = 0;
    has utility_score: int = 0;
    has status: str = "pending";
    has explanation: str = "";
}

node Consequence {
    has desc: str;
    has risk_delta: int;
}

node Incident {
    has incident_id: str;
    has timestamp: str;
    has summary: str;
}

node Decision {
    has decision_id: str;
    has selected_branch: str;
    has status_message: str;
}

edge Contains {}
edge OriginatedFrom {}
edge Proposes {}
edge UsesTool {}
edge Affects {}
edge ProtectedBy {}
edge Violates {}
edge Produces {}
edge ForksInto {}
edge ResultsIn {}
edge SelectedAs {}
edge RejectedAs {}
