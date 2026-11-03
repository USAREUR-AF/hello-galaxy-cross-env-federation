#!/usr/bin/env bash
# Every conformance package lints clean; every malformed fixture is refused
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"
B=$(cat "$HG_ROOT/.bundle-path" 2>/dev/null)
[ -d "${B:-}" ] || { no "stage 01 must run first (no unpacked bundle)"; tally; exit 1; }

good=0; badgood=0
for p in "$B"/vectors/compose-*/package-*.canonical.json "$B"/vectors/refuse-*/package-*.canonical.json; do
  [ -f "$p" ] || continue
  case "$p" in *signing-input*) continue ;; esac
  "$GOAT_BIN" federate lint "$p" --json >/dev/null 2>&1
  if [ $? -eq 0 ]; then good=$((good+1)); else badgood=$((badgood+1)); note "accepted nothing: $(basename "$(dirname "$p")")/$(basename "$p")"; fi
done
[ "$badgood" -eq 0 ] && ok "$good well-formed packages all lint clean" \
                     || no "$badgood of $((good+badgood)) well-formed packages were refused"

# The other direction, which is the one that discriminates: a linter that
# accepts everything passes the loop above and is worthless.
ref=0; missed=0
for p in "$B"/vectors/malformed/*.json; do
  [ -f "$p" ] || continue
  "$GOAT_BIN" federate lint "$p" --json >/dev/null 2>&1
  if [ $? -eq 21 ]; then ref=$((ref+1)); else missed=$((missed+1)); note "NOT refused: $(basename "$p")"; fi
done
[ "$missed" -eq 0 ] && ok "$ref malformed fixtures all refused with exit 21" \
                    || no "$missed of $((ref+missed)) malformed fixtures were accepted"

# The refusal must name the rule, or an operator cannot act on it.
out=$("$GOAT_BIN" federate lint "$B/vectors/malformed/no-signature.json" --json 2>&1)
assert_contains "a refusal names the rule it broke" '"rule":"M_' "$out"

tally
