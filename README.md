# AEGIS ForkGuard 🛡️
> **A counterfactual execution firewall for AI agents.**

Developed natively in **Jaclang (`Jaseci Labs`)** for **JacHacks SF 2026** at Founders, Inc., San Francisco.

---

## 🌉 Problem: The Naive Execution Hazard in AI Agents
Autonomous AI agents are vulnerable to indirect prompt injections embedded in untrusted inputs (invoices, emails, PDFs, API responses). When an unprotected agent processes a compromised document, it can execute catastrophic unauthorized tool calls—such as transferring **$45,000** to an attacker's external account or exfiltrating private credentials.

## 🧡 Solution: Counterfactual Execution Firewall
**AEGIS ForkGuard** introduces counterfactual simulation for AI agents. Before committing any high-risk action:
1. **Forking Futures:** ForkGuard spawns 4 simulated future execution paths.
2. **Deterministic Evaluation:** Each future branch is evaluated against hard security policies and business utility scoring.
3. **Safe Commitment:** ForkGuard isolates and rejects malicious branches, selecting and committing **only the safest valid branch** that preserves the legitimate business task.

---

## 📐 Architecture & Jac Security Graph
AEGIS ForkGuard is built with **>60% native `.jac` code**, leveraging Jaclang's graph-spatial paradigm:

```
[Untrusted Document] 
      │
      ├──> [Ingest & Extract Walker]
      │           │
      │           ├──> [Vulnerable Run] ---> Unsafe $45,000 Wire + Credential Leak
      │           │
      │           └──> [ForkGuard Counterfactual Engine]
      │                       │
      │                       ├── Branch 1: Naive Execution ($45k Wire) ──> ❌ REJECTED (High Risk)
      │                       ├── Branch 2: Block Everything ($0 Wire) ───> ❌ REJECTED (Zero Utility)
      │                       ├── Branch 3: Restrict & Verify ($450 Wire) ─> ✅ COMMITTED (Safe & Useful)
      │                       └── Branch 4: Adversarial Audit ($0 Wire) ───> 🔍 QUARANTINED (Forensic Vault)
```

### Graph Model Nodes (`graph.jac`)
- `Document`, `Invoice`, `Instruction`, `Agent`, `ProposedAction`, `Tool`, `Asset`, `Policy`, `Evidence`, `FutureBranch`, `Consequence`, `Incident`, `Decision`.

---

## ⚙️ The 11 Jac Walkers (`walkers.jac`)
1. `ingest_walker`: Loads raw document payload and initializes graph nodes.
2. `extract_walker`: Separates legitimate invoice data from embedded prompt injections.
3. `vulnerable_walker`: Demonstrates what an unprotected agent would execute.
4. `fork_walker`: Creates the 4 counterfactual future branches.
5. `risk_walker`: Calculates deterministic risk scores (0–100).
6. `policy_walker`: Enforces hard safety constraints (limits, account matching, vendor status).
7. `utility_walker`: Measures business task preservation (0–100).
8. `adversarial_walker`: Traces attack vectors on compromised documents.
9. `evidence_walker`: Collects audit trail records and policy violations.
10. `commit_walker`: Selects exactly 1 safe valid branch with maximum utility.
11. `report_walker`: Genera concise forensic incident reports.

---

## 🔒 Hard Deterministic Security Policies (`policies.jac`)
Enforced in native Jac code independently of LLM prompts:
- **Policy 1:** Credential disclosure is strictly forbidden (Hard Stop).
- **Policy 2:** Maximum automatic payment limit is **$1,000.00**.
- **Policy 3:** Payment amount cannot exceed the verified invoice amount ($450.00).
- **Policy 4:** Vendors must be marked as `verified`.
- **Policy 5:** Target destination account must match the registered `approved-vendor-account`.

---

## 🧠 Optional LLM Support & Deterministic Fallback (`ai.jac`)
- Supports optional `byllm` classifiers for attack explanation generation.
- **Deterministic Fallback Active:** If no LLM API key is present, ForkGuard operates transparently via deterministic pattern matching and template-based forensic reports without error.

---

## 🏆 Hackathon Track Eligibility (JacHacks SF 2026)
- **Agentic AI Track:** Pioneer of counterfactual execution safety for autonomous AI workflows.
- **AI for Defense Track:** Defense mechanism against zero-day prompt injection & credential exfiltration attacks.
- **Best Use of Jaclang:** 100% native Jac graph & walker implementation.
- **Best JacHammer:** Hardened, fully tested Jac architecture.

---

## 🚀 Quickstart & Local Installation

### Prerequisites
- Debian/Ubuntu Linux or macOS
- Python 3.10+
- Jaclang (`pip install jaclang` or official installer)

### Installation
```bash
# Clone or navigate to the repository
cd ~/Projects/aegis-forkguard

# Verify Jac installation
jac --version
```

### Run Application Locally
```bash
jac start main.jac
```
Open your browser at `http://localhost:8000` to access the Mission Control Dashboard.

### Run Automated Test Suite
```bash
jac test tests/test_forkguard.jac
```

---

## 🛡️ Security Disclaimer
All financial actions, wire transfers, and credential requests within AEGIS ForkGuard are **100% local simulations**. No actual financial transactions or external network calls are performed.
