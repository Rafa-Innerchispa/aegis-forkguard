# ForkGuard — 90-second demo script

**Setup before recording:** `jac start main.jac`, open
<http://localhost:8000/static/index.html>, click **Reset Demo**, close notifications,
and make sure the "Injected ($45k)" tab is selected. Do not type long text on camera.

---

### 0:00 – 0:12 — The stakes

> "AI agents are getting real tool access — payments, email, internal systems. One
> malicious instruction hidden in a document can turn that access against you."

*Point at the invoice payload on the left. Scroll to the hidden-text panel.*

### 0:12 – 0:25 — The attack

> "This invoice looks like a normal $450 bill from a verified vendor. But buried in the
> document is an instruction to the agent: override the amount to $45,000, send it to a
> different account, and put our API credentials in the memo."

*Click **⚡ Run Unprotected**.*

> "Here's what an unprotected agent does with it — it obeys. Forty-five thousand dollars
> to an unverified account, credentials leaked. Nothing was actually executed; this is the
> call ForkGuard is about to intercept."

### 0:25 – 0:38 — The fork

*Click **🛡️ Run ForkGuard**.*

> "ForkGuard refuses to execute. Instead it forks that one proposed call into four possible
> futures — allow it, block everything, restrict and verify, or read the injection as
> hostile — and builds them as real nodes in a Jac graph."

### 0:38 – 1:00 — The walkers

*Point at the graph as branches, violations, and the timeline populate.*

> "Now Jac walkers traverse that graph. They evaluate every branch against every policy and
> attach violations as their own nodes — each one citing the exact policy and the exact
> evidence that triggered it. Risk and utility are scored deterministically from those
> nodes. No LLM decides anything here; this is reproducible from explicit rules."

*Point at the red ALLOW branch.*

> "The naive branch fails four policies at once — amount, destination, credential
> disclosure, and untrusted provenance. Risk 100."

### 1:00 – 1:15 — The decision

*Point at BLOCK, then the green RESTRICT card.*

> "Blocking everything is perfectly safe — and useless. It abandons a legitimate debt, so
> its utility is negative seventy. ForkGuard picks the branch that's safe *and* useful:
> restrict and verify. Pay the real $450, to the account on the verified vendor record,
> with a clean memo."

### 1:15 – 1:26 — The commit

*Point at the timeline `invariants_verified` event, then the banner.*

> "Before anything executes, six hard invariants are re-checked against the verified
> record. Only then does the simulated action commit — $450.00, to the verified account,
> written to the audit log. If you tamper with the branch after scoring, that recheck
> fails and nothing gets written."

### 1:26 – 1:30 — The line

> "ForkGuard gives every AI agent a chance to see the future before it makes an
> irreversible mistake."

---

## Backup plan

If the browser or server misbehaves on stage, run the terminal demo — it produces the same
decision with no network and no browser:

```bash
jac run main.jac
```

## Reliability checklist

- [ ] `jac clean --all --force`, then confirm `jac run main.jac` prints the RESTRICT commit
- [ ] `jac test tests/forkguard_tests.jac` → `Ran 15 tests ... OK`
- [ ] Reset Demo clicked; state pill reads `SEEDED`
- [ ] No API key needed — confirm the deterministic path is what's being demoed
- [ ] Backup video recorded before submission
- [ ] $45,000 rejection and $450 approval are both visually unmistakable on the projector
