# The stages

What each one asserts, and what a failure means. Stages 01–04 need nothing but the `goat` binary;
stage 05 needs Docker and the `saltlick` image; stage 05b needs a running directory; stages
06–12 need goatnets and the prerequisites below.

The rule every stage is written to: **a check that cannot fail is not a check.** For each assertion,
there is a state of the world in which it fails. Where a stage cannot run it **skips loudly** and the
runner reports the skip on its last line, because a silent skip and a pass look identical.

---

## 01 — Bundle integrity

Runs the bundle's own `verify-bundle.sh` against the tarball as received, then proves that verifier
discriminates: an unlisted file and an altered specification must both be refused.

**A failure means** the artefact a counterparty would be handed does not match its own manifest.
Nothing further in this repository is meaningful until it does.

## 02 — Linting

Every well-formed package in the bundle must lint clean. Every fixture under `vectors/malformed/`
must be refused with exit 21, and the refusal must name the rule.

**The second half is the one that discriminates.** A linter that accepts everything passes the first
half. The rule name matters because a refusal an operator cannot act on is a refusal that gets
overridden.

## 03 — Composition

Every composing pair reproduces the digest committed beside it, in both argument orders. Every
`refuse-*` fixture is refused with exit 20. Composition with the two parties' verifying keys swapped
must fail.

**Both orders** because the format's central claim is that the agreement has no perspective — two
parties compute the same bytes without agreeing who is first. **Swapped keys** because nothing in
the bundle pins it, and a composer that ignored `--key` would pass every other check here.

**A failure means** the released binary and the normative vectors disagree. One of them is wrong and
a partner implementing against the vectors would be right.

## 04 — Disagreement

Two identical agreements agree. One changed field exits 22 and the output names that field. A
trailing newline — same content, different bytes — is detected and reported as a byte difference
rather than a field difference.

**The last one matters most.** Identical-looking agreements with different digests is the failure
that sends people re-running everything for three weeks. The tool exists to say "it is a newline".

## 05 — The directory

Starts the `saltlick` image (`SALTLICK_IMAGE`), then:

- `/v1/match` returns 404. The directory makes introductions and decides nothing; anything else here
  means it has started to.
- `/v1/spec` names the package spec and carries the advisory string.
- A directory entry carries **no offers**: `transport_offer` and `data_offer` are refused 422,
  because reachability and release sets are sovereign operational detail that moves directly
  between the two parties. A conformance package carries offers by design (it exists to exercise
  composition), so the stage builds the recognition-only shape — spec, sovereign id, identity,
  issued, expires, capabilities, signature — and re-signs it (`lib/make_directory_entry.py`).
- A signed entry published to `PUT /v1/parties/<id>` comes back from `GET` **byte-identical**. A
  directory that re-serialises what it stores has broken the digest every party computes over
  exactly those bytes.
- A second, unbound key for a party that already has one is refused **403**. A package carrying its
  own key authenticates nothing: the first key seen binds, and only that key can hand over to a
  successor.

The write is signed the way the service's own tests sign it: `X-Saltlick-Key` and
`X-Saltlick-Signature` over `saltlick-request/v1 \n METHOD \n <id> \n sha256:<hex> \n <key> \n`.

saltlick binds `127.0.0.1` by design and this stage does not ask it to bind wider — it joins the
container's network namespace instead. The bind is a property worth preserving.

---

## 05b — The directory used end to end

Stage 05 proves the service behaves; 05b proves it is useful. The directory holds recognition only,
so it cannot hand anyone a link. What it does is let a party you have never met be **found**, and
then let the package that arrives directly be **corroborated** against what that party published.

| Assertion | Why it is there |
|---|---|
| both counterparties are discoverable with no prior relationship | discovery is the service |
| the entry carries no `transport_offer`, no `data_offer` | recognition only |
| the entry's signature verifies under the party's own key | self-consistency |
| the directly-exchanged package agrees with the directory on `ca_fingerprint` and `trust_domain` | corroboration |
| a package disagreeing with the directory about its own CA is detected | the check can fail |
| a key the directory never bound is refused at composition, exit 20 | without this the directory is decoration |

Being listed grants no access, establishes no authority to connect, and does not establish that a
party is who it claims to be.

---

## The cloud tier: 06 — 12

### Prerequisites

Two goatnets, each with a federation edge (goatcore roles `goat-peering-edge` and
`goat-zenoh-edge`), and on them:

1. **Members may read the key bundle for their own release set** (`zenoh_member_key_read_enabled`
   on the router). Without it no member can fetch a key bundle and stages 10 and 12 cannot pass.
2. **`goat_zenoh_edge_key_bundle_key_exprs`** set for the counterparty, per release set. It defaults
   to empty, which means unsealed exchange only — a valid configuration, and not the one under test.
3. **SPIRE federation enabled** (`spire_federation_enabled`) on both, for stage 12.

The stages read their targets from the environment:

| Variable | Used by | Meaning |
|---|---|---|
| `HG_ENV_HOST` | 06 | a host running a goat fabric |
| `HG_OURS_HOST`, `HG_PARTNER_HOST` | 07–09, 11, 12 | the two edge hosts, reached over SSH as `ubuntu` |
| `HG_OUR_SOVEREIGN`, `HG_THEIR_SOVEREIGN` | 07–09, 11, 12 | the two sovereign ids (default `xab`, `xaa`) |
| `HG_OUR_CA_SUBJECT`, `HG_THEIR_CA_SUBJECT` | 08 | the subject each side's root CA carries |
| `HG_OUR_PRIVATE_ADDR` | 08 | an address on our private subnet the partner must NOT reach |
| `HG_GOATNET_HOST`, `HG_REVOKE_CMD` | 10 | a host running `grant-keyd`; the command that removes a member |
| `HG_KEYD_CONFIG`, `HG_CORE_CONFIG`, `HG_RELEASE_SET`, `HG_PARTNER_MEMBER` | 12 | grant-keyd config, core router config, the release set, the partner's SPIFFE id |

### The stages

| | Stage | Asserts |
|---|---|---|
| 06 | `federate init` measures a real environment | capabilities are derived, not typed; a value that cannot be derived exits 23 and is named |
| 07 | The tunnel comes up under the composed agreement | the SA is ESTABLISHED under the two names the agreement derived (`fed.<issuer>.<counterparty>.01`), a child SA is INSTALLED, and the link carries only the agreed selectors |
| 08 | The peering edge terminates the relationship | each edge holds exactly ONE foreign authority; the counterparty reaches the link address and nothing on our private subnet |
| 09 | Data both ways | read back **out of storage on the receiving side**, never inferred from an ACL allow; a write outside the agreement does not cross |
| 10 | Grant-keyed encryption inside one goatnet | the router grants per-release-set key reads; with `HG_REVOKE_CMD` set, a revoke mints a new key generation and the interval is timed |
| 11 | The round trip | a nonce goes out under our wire name, a responder on the far side answers under theirs; it FAILS with their consumer stopped and with the edge stopped, and passes again once the edge is back |
| 12 | A federated partner in an audience | the audience admits a member from another trust domain, by its SPIFFE id; withdrawing the domain refuses it; the partner fetches the bundle across the edge and it holds their slot |

Stage 11 uses goatcore's `ops/federation/roundtrip/` (`fedcheck.sh` on our side, `responder.py` on
theirs, both copied to `/tmp`). It is last because it is the only check a publisher with one side
can make, and the only one that fails when an earlier stage silently half-works.

**Stage 10's timing is the point.** Rotation is the containment act for grant-keyed encryption:
removing a member mints a new generation with no copy wrapped to them. `grant-keyd` polls on
`poll_interval_secs`, which bounds detection; the wrap-and-publish term is only known by firing a
real revoke, which mutates live grant state — hence the explicit `HG_REVOKE_CMD`.

---

## Traps the cloud stages are written to catch

Each of these presents as "it is up and nothing is happening". When that is the symptom, check what
name or expression each side is actually presenting, and against what.

**A public address in `peering_edge_local_addr` on a 1:1-NAT cloud host.** The host owns only its
private address; the kernel drops every IKE packet sourced from the public one, while charon logs
`sending packet` and retransmits as if all were well. Set `peering_edge_local_addr: "%any"`, keep
the counterparty's public address in `peering_edge_remote_addr`, and NAT-T does the rest.

**`tcpdump` that loses its buffer.** `tcpdump` buffers when its output is not a terminal, and killing
it with `timeout` discards the buffer — a capture of zero packets that looks exactly like a network
that dropped them. Use `-U`, or write a pcap and read it back.

**A storage or subscriber wider than the granted lane receives nothing.** Data flows one way;
interest flows the other. The receiving side's storage declares a subscriber, that declaration
travels back through the edge, and the edge applies its ACL to the declaration. A storage declaring
`from/**` against a grant of `from/xaa/**` is refused, the far side never learns anyone wants the
data, and nothing is forwarded — link ESTABLISHED, no denial logged. Scope every storage and
subscriber behind a federation edge **no wider than the lane the agreement grants**.

**The same for queryables.** The key bundle is served by a storage answering queries; a core storing
every release set under one `keys/**` storage declares a queryable wider than a per-release-set grant
of `keys/weather/**`, and the partner's fetch returns `[]`, which reads as "no bundle published". A
goatnet serving a federated partner needs a key storage **per released release-set** — the same
shape as the per-slot data rule (ADR 1101). Stage 12 checks the core's storage scope and says which
one it found.

**The edge needs both flows for each key set.** A subscriber declaration from the partner arrives as
*ingress*; one sent to them leaves as *egress*. An edge rule granting one flow carries nothing in
either direction.

**Staging name vs wire name.** `release/<set>/**` is the staging name and never appears on the link:
the republisher lifts it onto `from/<our sovereign>/…` before anything reaches the edge, because the
fabric cannot rename a key expression in transit. Stage 09 publishes and reads the wire name.

**The key topic is authenticated data.** `gce open` takes `--keyexpr`; omit it and the additional
authenticated data does not match what `seal` used. An outsider gets *"no key slot for member"*; a
wrong topic gets *"cannot decrypt"*. Which refusal you got is the diagnosis.

**The edge's key read is egress-only and scoped to the release set.** `keys/<set>/**`, read-only,
never `keys/**` (that hands the partner every audience's keys), and no `put`/`delete` (publishing on
the key topic means wrapping a data key of your own choosing).

**Admitting a trust domain is a decision, not a consequence of federating.** The trust bundle
already carries the partner's root once SPIRE federation is on. If admission followed from that,
"we federate with them" would silently mean "they may read our sealed data". Stage 12 proves the
admission is separate by withdrawing it (ADR 1169).

**Checker traps.** `pkill -f <pattern>` matches the shell running it; bracket the pattern
(`'[f]edcheck-responder.py'`). A command whose last statement is backgrounded returns nothing, so
start and verify in separate invocations. `grant-keyd` logs `Unchanged` on every poll and
`Rotated … generation: N` only on rotation, so a `docker logs --tail` window can miss the last
generation entirely. `grant-keyd` refuses unknown config fields, so stash state in a side file,
not in the config. The zenoh REST value comes back base64 whenever it is not JSON; decode before
asserting.
