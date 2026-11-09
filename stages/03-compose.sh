#!/usr/bin/env bash
# Every composing pair reproduces its committed digest, in both orders
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"
. "$HG_ROOT/lib/fed.sh"
B=$(cat "$HG_ROOT/.bundle-path" 2>/dev/null)
[ -d "${B:-}" ] || { no "stage 01 must run first (no unpacked bundle)"; tally; exit 1; }

KA=$(cat "$B/vectors/testkeys/xaa.public.b64"); KB=$(cat "$B/vectors/testkeys/xab.public.b64")
NOW=$(tr -d '\n' < "$B/vectors/now.txt")

digest_of() { # $1 dir, $2 first, $3 second
  fed compose "$1/$2" "$1/$3" --key "xaa=$KA" --key "xab=$KB" --now "$NOW" --json 2>/dev/null \
    | python3 -c 'import json,sys
try: print(json.load(sys.stdin).get("digest",""))
except Exception: print("")'
}

pairs=0; mismatch=0; asym=0
for d in "$B"/vectors/compose-*; do
  [ -f "$d/agreement.digest.txt" ] || continue
  want=$(tr -d '\n' < "$d/agreement.digest.txt")
  fwd=$(digest_of "$d" package-xaa.canonical.json package-xab.canonical.json)
  rev=$(digest_of "$d" package-xab.canonical.json package-xaa.canonical.json)
  pairs=$((pairs+1))
  [ "$fwd" = "$want" ] || { mismatch=$((mismatch+1)); note "$(basename "$d"): got $fwd want $want"; }
  [ "$fwd" = "$rev" ]  || { asym=$((asym+1));    note "$(basename "$d"): order changed the digest"; }
done

[ "$pairs" -gt 0 ] && ok "$pairs composing pairs exercised" || no "no composing pairs found"
[ "$mismatch" -eq 0 ] && ok "every pair reproduces its committed digest" \
                      || no "$mismatch of $pairs pairs produced a different digest"
[ "$asym" -eq 0 ] && ok "the agreement has no perspective — order does not change the digest" \
                  || no "$asym of $pairs pairs depended on argument order"

# Composition must refuse, and the refusals are the mechanism working.
# Discover the pair rather than assume the filenames: refuse-same-sovereign-id
# holds package-xaa and package-xaa-second, because both parties claim one id.
n=0; wrong=0
for d in "$B"/vectors/refuse-*; do
  [ -d "$d" ] || continue
  set -- $(ls "$d" | grep -E '^package-.*\.canonical\.json$' | grep -v signing-input)
  [ $# -eq 2 ] || { note "$(basename "$d"): expected 2 packages, found $#"; continue; }
  fed compose "$d/$1" "$d/$2" \
      --key "xaa=$KA" --key "xab=$KB" --now "$NOW" --json >/dev/null 2>&1
  rc=$?; n=$((n+1))
  [ "$rc" -eq 20 ] || { wrong=$((wrong+1)); note "$(basename "$d") exited $rc, expected 20"; }
done
[ "$n" -eq 0 ] && skip "no refusal fixtures in this bundle" \
  || { [ "$wrong" -eq 0 ] && ok "$n refusal fixtures all refused with exit 20" \
                          || no "$wrong of $n refusal fixtures did not refuse"; }

# A wrong key must break composition. Nothing in the bundle pins this, and a
# composer that ignored --key would pass every check above.
d="$B/vectors/compose-full"
fed compose "$d/package-xaa.canonical.json" "$d/package-xab.canonical.json" \
    --key "xaa=$KB" --key "xab=$KA" --now "$NOW" --json >/dev/null 2>&1
rc=$?
[ "$rc" -ne 0 ] && ok "swapping the two parties' verifying keys is refused (exit $rc)" \
                || no "composition succeeded with the wrong keys — signatures are not being checked"

tally
