#!/usr/bin/env bash
# A disagreeing pair is named, not merely reported as different
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"
. "$HG_ROOT/lib/fed.sh"
B=$(cat "$HG_ROOT/.bundle-path" 2>/dev/null)
[ -d "${B:-}" ] || { no "stage 01 must run first (no unpacked bundle)"; tally; exit 1; }

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
A="$B/vectors/compose-full/agreement.canonical.json"
cp "$A" "$W/ours.json"

# Identical inputs must agree. If this fails nothing below means anything.
assert_exit "two identical agreements agree" 0 fed diff "$A" "$W/ours.json"

# One field changed: the diff has to say WHICH.
python3 - "$A" "$W/theirs.json" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
d["transport"]["mtu"] = 1200
open(sys.argv[2],"w").write(json.dumps(d,separators=(",",":"),sort_keys=True))
PY
out=$(fed diff "$A" "$W/theirs.json" 2>&1); rc=$?
[ "$rc" -eq 22 ] && ok "a real disagreement exits 22" || no "expected exit 22, got $rc"
assert_contains "the disagreement names the field" "mtu" "$out"

# The case that reads as impossible: same content, different bytes. A trailing
# newline is the classic cause and the tool is meant to name it rather than
# send someone re-running everything.
printf '\n' >> "$W/ours.json"
out=$(fed diff "$A" "$W/ours.json" 2>&1); rc=$?
if [ "$rc" -eq 0 ]; then
  no "a trailing newline changed nothing" "the byte difference was not detected at all"
else
  ok "a byte-level-only difference is detected (exit $rc)"
  case "$out" in
    *newline*|*byte*|*encoding*|*BOM*) ok "and it is named as a byte difference, not a field" ;;
    *) no "detected but not explained" "$(printf '%s' "$out" | head -c 200)" ;;
  esac
fi

tally
