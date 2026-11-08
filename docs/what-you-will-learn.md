# What you will learn

Read this before the stages. It is the mental model; the stages are the proof.

## The problem

Two organisations need to exchange data. **Neither will join the other's network. Neither will
vouch for the other's identities. Neither can inspect the other's systems.** Both still have to
say exactly what crosses, and prove it to someone who was not in the room.

That last clause is what makes this hard. Any two engineers can get packets between two hosts.
Producing something an approving authority will sign is a different exercise.

## The five ideas

**1. A tunnel grants nothing.** It carries traffic and knows nothing about who you are or what you
sent. Everything that decides who may send what happens one layer above it, on a component that
exists to handle exactly one partner. If you remember one thing: the middle layer is the only one
that can refuse anything.

**2. The name carries the issuer, because the rules cannot see it.** The access layer matches a
certificate's Subject Common Name by string equality and cannot tell which authority signed it. So
a partner's authority sitting anywhere near your core is not a smaller risk than granting access —
it *is* granting access. Hence one dedicated process, holding one foreign authority, per
relationship. Stage 08 measures exactly that: each edge holds **one** foreign root, and the
counterparty can reach the agreed link address and nothing behind it.

**3. Names are derived, never chosen.** Each side computes `fed.<issuer>.<counterparty>.<ordinal>`
from the pair of sovereign ids. Neither party picks it, so neither can pick something the other
must accept. Stage 07 asserts the live security association carries both derived names — a tunnel
that came up under any other name is not the tunnel the agreement describes.

**4. The agreement has no perspective.** Each side signs its own half; the two compose
deterministically into one document with one digest. Both sides compute it independently and
compare — over any channel at all, including one nobody trusts. Equal digests prove both hold the
identical configuration. Stage 03 proves the composition is order-independent, which is what "no
perspective" means in practice.

**5. Matching digests are not approval.** They establish no authority to connect, no handling
obligation, no notification timeline, no terms of termination. Those are decisions by people
empowered to make them, recorded in a separate written instrument. The technical agreement is an
annex to that instrument and never a substitute for it.

## The directory, and what is left to people

Packages move through a directory, `saltlick`: a public service on the internet, outside every
party's network. Each party publishes a signed pointer — its sovereign id, where its package is
served, that package's sha256, an expiry date — and uploads its signed package and its CA
certificate beside it, so a party behind NAT needs no public host of its own. The other party
fetches the package through the pointer and checks the digest, the signatures and the CA
fingerprint itself. The directory is advisory: being listed grants nothing, and `compose` verifies
a package only against the key bound by voice, never against anything the directory served.

What people do, and nothing else:

| Act | Who |
|---|---|
| Decide to federate, and what data flows | each party, on its own authority |
| Read the verifying key and the CA fingerprint aloud, groups of four, and hear them read back | one call per party |
| Read the agreement digest aloud after `compose` | the same call, or a second one |

Everything between those acts is machine-driven and deterministic.

## How the stages map to the ideas

| Idea | Proved by |
|---|---|
| The format is exact and implementable by someone else | 01, 02 — the bundle verifies itself; 46 packages lint clean and 11 malformed ones are refused |
| The agreement has no perspective | 03 — 13 pairs reproduce their committed digest in **both** argument orders |
| Disagreement is loud, not silent | 04 — a changed field is named; a trailing newline is reported as a byte difference, not a field one |
| A directory carries the exchange and decides nothing | 05 — `/v1/match` returns 404, stored bytes come back identical, a second unbound key is refused |
| The only trust is the voice read-back | 05b — each party fetches the other's package through its pointer and checks it against the key and CA fingerprint read aloud; a key never bound is refused at composition |
| Capabilities are measured, not typed | 06 — a value that cannot be derived exits 23 and names itself |
| Names are derived | 07 — the live SA carries both derived names |
| The edge terminates | 08 — one foreign authority per edge; the private subnet is unreachable |
| Only what the agreement names crosses | 09 — read back from storage on the receiving side, never inferred from an ACL allow |
| Sealed data survives the boundary | 10 — the partner fetches its key bundle, opens sealed data, and a revoke is timed |

## What a green run covers

- **Stages 01–05b are offline.** They prove the format, the tool and the directory agree with the
  specification. No tunnel, no fabric; 05b plays both parties on one machine.
- **Stages 06–12 prove the software path between two goatnets.** Sovereignty separation is a
  property of where you run them: two goatnets reachable with one set of credentials do not
  demonstrate it.

## Where to go next

- [`STAGES.md`](../STAGES.md) — what each stage asserts and what a failure means, and the traps the
  cloud stages are written to catch.
- In [`usareur-af/goatcore`](https://github.com/usareur-af/goatcore):
  `docs/design/federation-package-spec.md` (the format), `docs/design/federated-trust-model.md`
  (why recognition is not authorization), ADR 1157 (the edge-terminated design) and
  `docs/operations/sovereign-federation-runbook.md` (the operator procedure).
- [`usareur-af/zagros-moon-pod`](https://github.com/usareur-af/zagros-moon-pod) — the neighbouring
  case, where a partner runs a pod inside a goatnet instead of their own environment. **Read that
  one first if you are not sure which case you have**: a pod is the default and federation is the
  exception.
