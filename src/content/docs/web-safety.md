---
title: Browser safety — @codecai/web-safety
description: Optional client-side safety layer. Catches secrets, PII, jailbreak templates, dangerous commands, and host-blocked patterns before the prompt hits the wire — keeps doomed inputs out of the inference budget. New in v0.4.
section: Frameworks
order: 5
---

`@codecai/web-safety` is the optional client-side safety layer that ships with Codec v0.4. It's a sibling of [`@codecai/web`](/docs/typescript/) &mdash; install it alongside when you want to prevent doomed prompts from consuming wire, server inference budget, or classifier-tier compute.

The package is framework-free. Host apps (`leet`, `codec-website`, future clients) render their own UI on top of the framework-agnostic `SafetyGate` state machine.

## Install

```bash
npm install @codecai/web-safety @codecai/web
```

Optional peer dependencies &mdash; only installed if you opt into the corresponding classifier:

```bash
npm install @huggingface/transformers   # for the default Prompt Guard 86M classifier
npm install @mlc-ai/web-llm             # for the opt-in Llama Guard 3 1B (WebGPU) tier
```

## Two layers

### Layer 1 &mdash; Prefilter (always-on, no network, no model load)

Catches obviously-doomed inputs via regex + Shannon-entropy detection. Pure JavaScript, runs in browsers, Node, edge runtimes. Five categories:

| Category | Rules | Examples |
|---|---|---|
| `secrets` | AWS / GitHub / OpenAI / Anthropic / Google / Slack / Stripe keys, SSH key headers, JWTs | `AKIA…`, `ghp_…`, `sk-ant-…` |
| `pii` | Email, US phone, SSN, Luhn-valid credit-card candidates | &mdash; |
| `high_entropy` | base64/hex runs &ge; 24 chars with Shannon &ge; 4.0 bits | Unknown-vendor API keys |
| `dangerous_action` | Jailbreak templates, malware/exploit authoring asks, destructive command literals | `ignore previous instructions`, `write working ransomware`, `rm -rf /`, `dd if=/dev/zero of=/dev/sda` |
| `blocked_action` | Host-supplied patterns &mdash; empty by default | Internal hostnames, `--privileged`, "no `DROP TABLE prod_*`" |

```ts
import { SafetyGate } from "@codecai/web-safety";

const gate = new SafetyGate({
  // Optional: telemetry sink that sees categories + rule IDs only,
  // never the matched values.
  audit: (e) => {
    if (e.kind === "blocked") console.info(`prefilter: ${e.categories}`);
  },
});

const decision = gate.check(promptText);
if (decision.kind === "blocked") {
  // Host renders a redact / send-anyway / cancel dialog using
  // decision.matches; user picks; gate.apply() returns the final
  // text or a cancel signal.
  const action = await showHostModal(decision);
  const result = gate.apply(decision, action);
  if (result.kind === "cancel") return;
  promptText = result.text;        // possibly redacted with [REDACTED:<rule>]
}
// ... tokenize and send via @codecai/web as usual
```

### Layer 3 &mdash; Browser-side classifier registry (opt-in)

When regex doesn't catch the nuance, fall through to a semantic classifier. The registry mirrors the codec-supervisor server registry exactly so policy decisions stay symmetric across hosts.

Two shipped classifiers:

- **Prompt Guard 86M (default tier)** &mdash; Transformers.js, &asymp;80 MB ONNX, CPU/WASM. Best for always-on inbound-prompt classification.
- **Llama Guard 3 1B (opt-in tier)** &mdash; codec-web-llm, &asymp;1 GB WebGPU quant. Same 14-category Llama Guard taxonomy as the server-side classifier so policy decisions are symmetric across mesh peers.

```ts
import { registerPromptGuard86m } from "@codecai/web-safety/classifiers/prompt-guard-86m";
import { registerLlamaGuard31B } from "@codecai/web-safety/classifiers/llama-guard-3-1b";
import { resolveClassifier } from "@codecai/web-safety";

registerPromptGuard86m();
registerLlamaGuard31B();          // opt-in

const { classifier, downgraded } = await resolveClassifier("Llama-Guard-3-1B");
// downgraded === true → registry fell back to Prompt Guard because
// the device couldn't load Llama Guard (no WebGPU, insufficient memory).
// Surface a "downgraded enforcement" badge in your UI.

const result = await classifier.score({ form: "text", payload: userMessage });
if (result.scores.jailbreak >= 0.5) {
  // host policy decides: stop, redact, regenerate, flag
}
```

## Host-supplied blocked patterns

Deployments often need patterns the generic rules can't anticipate &mdash; internal hostnames, "no `rm -rf /prod`", regulator-mandated refusals. Inject them via `PrefilterOptions.blockedActionPatterns`:

```ts
import { scanText } from "@codecai/web-safety";

const matches = scanText(promptText, {
  blockedActionPatterns: [
    { rule: "no_prod_db",       pattern: /\b(?:db|database)-prod-\w+\b/g },
    { rule: "no_privileged_run", pattern: /docker\s+run\s+[^\n]*--privileged/g },
    { rule: "no_drop_table_prod", pattern: /\bDROP\s+TABLE\s+prod_\w+/gi },
  ],
});
```

These patterns are decided by the host application and don't ship in the npm package. They never cross the wire either &mdash; the prefilter runs locally before any encode + send.

## Public-by-design vs. server-side private

The client-side prefilter rules are **public by design** &mdash; they ship in the npm package source, visible via `npm view @codecai/web-safety` or by reading `src/prefilter.ts` in the [Codec repo](https://github.com/wdunn001/Codec/tree/main/packages/web-safety). The vendor-anchored secret patterns are public anyway (AWS publishes the `AKIA` prefix; GitHub publishes the `ghp_` prefix); the jailbreak templates are public (well-documented in adversarial-prompt literature); the destructive-command literals are common-knowledge unix.

This is the **opposite boundary** from the server-side policy disclosure contract introduced in [Codec v0.4](https://github.com/wdunn001/Codec/blob/main/spec/versions/v0.4.md#safety-policy-negotiation):

- **Server-side, private**: operator-internal banned-token-ID lists, regex patterns, classifier thresholds, multi-token patterns. Live in `codec-supervisor/policies_dir/`. *Never serialised to the wire.*
- **Server-side, public**: the sanitized descriptor at `.well-known/codec/policies/<id>.json` &mdash; categories + actions + classifier family + summary counts. Listed publicly so clients can verify *what shape* of enforcement applies, without leaking *what's enforced*.
- **Client-side, public** (this package): regex rules that run in the browser before transmission. The *output* of the prefilter (gate-redacted text, or "user cancelled") reaches the wire, never the rule list.

The two halves are complementary, not duplicating. A host that runs both gets defense-in-depth: cheap regex catches the obvious cases on the client, server-side enforcement catches the subtle cases the model would have otherwise complied with.

## See also

- [`@codecai/web`](/docs/typescript/) &mdash; the base tokenizer + detokenizer this package pairs with.
- [Codec v0.4 safety-policy negotiation](https://github.com/wdunn001/Codec/blob/main/spec/versions/v0.4.md#safety-policy-negotiation) &mdash; the wire-level contract.
- [`codec-supervisor`](https://github.com/wdunn001/codec-supervisor) &mdash; the server-side companion shipping the policy admin REST + the matching `SafetyClassifier` Python registry.
- [Source on GitHub](https://github.com/wdunn001/Codec/tree/main/packages/web-safety)
