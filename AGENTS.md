# AGENTS.md

Instructions for AI coding agents, and a short version for anyone working here. [CONTRIBUTING.md](CONTRIBUTING.md) is the full process.

## What this repository is

hello-galaxy-cross-env-federation demonstrates cross-sovereign federation: two organizations, each with its own environment, certificate authority and identity plane, exchange data without either giving the other any control. It runs against released artifacts: a released `goat` binary and a federation bundle.

It is one of the Hello Galaxy demonstrations: small, runnable examples, each showing one part of [goat](https://github.com/USAREUR-AF/goatcore). It holds no goat source code.

## Layout

| Path | What |
|---|---|
| `run` | the runner; `run.sh` is an alias. `./run --list` names each stage |
| `stages/` | one script per stage |
| `bundle/` | the federation bundle the stages read |
| `lib/` | shared shell and Python helpers |
| `scenario/`, `docs/`, `STAGES.md` | the scenario and what each stage proves |

## Before you push

CI (`.github/workflows/ci.yml`) runs every stage with a released `goat` binary. Stages that cannot run where you are skip and say why.

```bash
pip install cryptography
./run              # needs a goat binary on PATH or at $GOAT_BIN
./run 03           # one stage
```

## Rules

1. **Nothing from a real deployment.** No hostname, domain, address, key or person of a real goatnet goes into a file or a commit message. Use made-up names, documentation addresses (RFC 5737) and `example.org` mail.
2. **Commits.** Conventional Commits subject of 100 characters or fewer, with a scope (`fix(<component>): …`). Every commit is signed off (`git commit -s`, the DCO) and signed with a key GitHub verifies. The organization's required check `verified-commits` refuses a pull request that holds an unverified commit.
3. **One logical change per pull request.**
4. **Vulnerabilities** go through [SECURITY.md](SECURITY.md), never a public issue.

The contribution guide for goat as a whole is [goatcore CONTRIBUTING.md](https://github.com/USAREUR-AF/goatcore/blob/main/CONTRIBUTING.md).
