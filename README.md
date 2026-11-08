# hello-galaxy-cross-env-federation

**Two organisations that will not join each other's networks, will not vouch for each other's
identities, and cannot inspect each other's systems — exchanging data anyway, and proving it.
Run the offline half of the proof in one command.**

This is a Hello Galaxy demo: a small, self-contained, runnable example of one thing done right.
The thing here is **cross-sovereign federation** — the case where a partner runs their own
environment, their own certificate authority and their own identity plane, and neither side
hands the other any control.

## What makes this one different from the rest of the series

It runs against **released artefacts**, not goat's source. It holds no goat code at all, and
consumes the interfaces that exist for a counterparty:

| Interface | What it is |
|---|---|
| `goat` CLI | a released binary from [`usareur-af/goatcore` releases](https://github.com/usareur-af/goatcore/releases) |
| The federation bundle | `federation-package-spec.md`, the conformance vectors and `verify-bundle.sh`, exactly as a counterparty receives them (`bundle/`) |
| `saltlick` | the peering-directory image, used by stages 05 and 05b |

If it runs green, the flow works for someone holding only those artefacts. If it vendored goat
source it would prove nothing that `cargo test` does not already prove.

## Start here

```
./run              # every stage; the offline ones run, the rest skip and say why
./run 03           # one stage
./run --list       # what each stage is
```

Requirements: `bash`, `python3`, `tar`, and a `goat` binary on `PATH` or at `$GOAT_BIN`.
Stages 05 and 05b additionally need `pip install cryptography`, and Docker to run the `saltlick`
image (`SALTLICK_IMAGE`, default `ghcr.io/usareur-af/saltlick:v0.3.0`) behind a TLS front
(`SALTLICK_TLS_IMAGE`, default `caddy:2.10`). Stage 05b takes `HG_SALTLICK`, the https URL of a
directory you already run, in place of Docker.

New to this? Read [`docs/what-you-will-learn.md`](docs/what-you-will-learn.md) first — the mental
model in five ideas. Then [`STAGES.md`](STAGES.md) for what each stage asserts, what a failure
means, and the traps the cloud stages are written to catch.

**If you are not sure this is your case:** a partner running a pod *inside* a goatnet is the
default and a different lesson ([`usareur-af/zagros-moon-pod`](https://github.com/usareur-af/zagros-moon-pod)).
Federation is the exception, for a partner who must own their own authority and identity plane.

## The stages

Stages 01–04 need no goatnet, no cloud and no credentials. Stages 05 and 05b need Docker and the
`saltlick` image, or for 05b a directory at `HG_SALTLICK`. Stages 06–12 need two goatnets you have access to,
with a federation edge on each put there by their operators (you, if you are one), and the
prerequisites listed in `STAGES.md`; without them they skip and the
runner's last line says how many skipped.

| | Stage | Needs |
|---|---|---|
| 01 | Bundle integrity — the partner's own verifier, plus its refusal self-test | nothing |
| 02 | Every conformance package lints clean; every malformed fixture is refused | nothing |
| 03 | Every composing pair reproduces its committed digest, in both orders | nothing |
| 04 | A disagreeing pair is named, not merely reported as different | nothing |
| 05 | The directory hosts a party's pointer, package and CA byte-exact, and refuses what it must | Docker, `saltlick` image |
| 05b | Two parties federate through the directory — publish, fetch, check, read back, compose | Docker, or a directory at `HG_SALTLICK` |
| 06 | `federate init` measures a real environment | a goatnet host (`HG_ENV_HOST`) |
| 07 | The tunnel comes up under the composed agreement | two federation edges |
| 08 | The peering edge terminates the relationship | two federation edges |
| 09 | Data crosses both ways, read back from storage on the receiving side | two goatnets |
| 10 | Grant-keyed encryption inside one goatnet, with the revoke timed | a goatnet with `grant-keyd` |
| 11 | The round trip — the one check the sending side can make alone | two goatnets |
| 12 | A federated partner in an audience | two goatnets with `grant-keyd` and SPIRE federation |

Any appropriate pair of goatnets works. To stand up a pair yourself, start from goatcore's
[`docs/tutorials/00-goatlite.md`](https://github.com/usareur-af/goatcore/blob/main/docs/tutorials/00-goatlite.md)
and [`docs/tutorials/04-two-sovereigns.md`](https://github.com/usareur-af/goatcore/blob/main/docs/tutorials/04-two-sovereigns.md);
the operator procedure is
[`docs/operations/sovereign-federation-runbook.md`](https://github.com/usareur-af/goatcore/blob/main/docs/operations/sovereign-federation-runbook.md).

## What a green run covers

- **Stages 01–05b are offline.** They prove the format, the tool and the directory agree with the
  specification. They involve no tunnel and no fabric; 05b plays both parties on one machine.
- **Stages 06–12 cover the software path between two goatnets.** Whether the two sides are
  separate sovereigns depends on where you run them: two goatnets under one set of cloud
  credentials prove the software path, not the separation.

## Layout

```
run                the runner (run.sh is an alias)
lib/assert.sh      assertions, and the pass/fail tally
lib/saltlick_up.sh a directory of our own: saltlick behind a TLS front (stages 05, 05b)
lib/*.py           pointer, package and CA building, signed writes, the directory flow (05, 05b)
stages/            one file per stage
bundle/            the federation conformance bundle, as a counterparty receives it
scenario/          the two notional sovereigns
STAGES.md          what each stage asserts, and what a failure means
```

## License

`hello-galaxy-cross-env-federation` was written by U.S. Federal government employees. In the U.S. it is not subject to copyright and is in the public domain; in countries where copyright is recognized, it is released under the [Apache License 2.0](LICENSE). See [INTENT.md](INTENT.md).
