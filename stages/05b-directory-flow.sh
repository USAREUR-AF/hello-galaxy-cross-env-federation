#!/usr/bin/env bash
# The directory used end to end — discover, corroborate, then compose
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"
B=$(cat "$HG_ROOT/.bundle-path" 2>/dev/null)
[ -d "${B:-}" ] || { no "stage 01 must run first"; tally; exit 1; }
: "${HG_SALTLICK:=}"
[ -n "$HG_SALTLICK" ] || { skip "no directory to talk to" "set HG_SALTLICK, e.g. http://127.0.0.1:18080"; tally; exit 0; }
python3 -c 'import cryptography' 2>/dev/null || { skip "python3 cryptography needed"; tally; exit 0; }

# Discovery, then corroboration. The directory holds recognition only, so it
# cannot hand anyone a link — what it does is let a party you have never met be
# FOUND, and then let the package that arrives directly be checked against what
# that party published about itself.
out=$(python3 "$HG_ROOT/lib/directory_flow.py" "$HG_SALTLICK" "$B" 2>&1); rc=$?
printf '%s\n' "$out" | sed 's/^  //' | while read -r l; do [ -n "$l" ] && echo "  $l"; done
[ $rc -eq 0 ] && ok "the directory flow holds end to end" || no "the directory flow failed"

# The binding the directory publishes is load-bearing: composition must refuse a
# key it did not corroborate. Without this the checks above are description.
KA=$(cat "$B/vectors/testkeys/xaa.public.b64"); KB=$(cat "$B/vectors/testkeys/xab.public.b64")
NOW=$(tr -d '\n' < "$B/vectors/now.txt"); DIR="$B/vectors/compose-full"
got=$("$GOAT_BIN" federate compose "$DIR/package-xaa.canonical.json" "$DIR/package-xab.canonical.json" \
        --key "xaa=$KA" --key "xab=$KB" --now "$NOW" --json 2>/dev/null \
        | python3 -c 'import json,sys;print(json.load(sys.stdin).get("digest",""))' 2>/dev/null)
assert_eq "the agreement composes to its committed digest" "$(tr -d '\n' < "$DIR/agreement.digest.txt")" "$got"
"$GOAT_BIN" federate compose "$DIR/package-xaa.canonical.json" "$DIR/package-xab.canonical.json" \
   --key "xaa=$KA" --key "xab=$KA" --now "$NOW" --json >/dev/null 2>&1
[ $? -ne 0 ] && ok "a key the directory never bound is refused at composition" \
             || no "composed under an unbound key — the directory binding is not load-bearing"
tally
