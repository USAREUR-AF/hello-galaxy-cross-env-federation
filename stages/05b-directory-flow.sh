#!/usr/bin/env bash
# Two parties federate through the directory — publish, fetch, check, read back, compose
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"
. "$HG_ROOT/lib/fed.sh"
B=$(cat "$HG_ROOT/.bundle-path" 2>/dev/null)
[ -d "${B:-}" ] || { no "stage 01 must run first"; tally; exit 1; }
python3 -c 'import cryptography' 2>/dev/null || { skip "python3 cryptography needed"; tally; exit 0; }

# A directory to use: HG_SALTLICK (its https URL; HG_SALTLICK_CA for a private
# CA), or one of our own.
. "$HG_ROOT/lib/saltlick_up.sh"
if [ -n "${HG_SALTLICK:-}" ]; then
  note "directory: $HG_SALTLICK"
else
  saltlick_up || { skip "no directory" "$SALTLICK_UP_SKIP; or set HG_SALTLICK"; tally; exit 0; }
  note "directory: our own, $SALTLICK_IMAGE behind TLS"
fi

W="$HG_ROOT/.work/05b"; rm -rf "$W"; mkdir -p "$W"
out=$(python3 "$HG_ROOT/lib/directory_flow.py" "$HG_SALTLICK" "$B" "$W" 2>&1); rc=$?
printf '%s\n' "$out" | while IFS= read -r l; do echo "  ${l#  }"; done
[ $rc -eq 0 ] && ok "each party publishes, fetches and checks the other's package through the directory" \
              || no "the directory flow failed"

# Compose. Each party composes its own package with the one it fetched, under the
# keys read back on the call. The agreement has no perspective: both compute the
# same digest, and reading that digest back is the last human act.
KA=$(cat "$B/vectors/testkeys/xaa.public.b64"); KB=$(cat "$B/vectors/testkeys/xab.public.b64")
NOW=$(tr -d '\n' < "$B/vectors/now.txt")
digest() {
  fed compose "$1" "$2" --key "xaa=$KA" --key "xab=$KB" --now "$NOW" --json 2>/dev/null \
    | python3 -c 'import json,sys;print(json.load(sys.stdin).get("digest",""))' 2>/dev/null
}
d_xaa=$(digest "$W/xaa.package.json" "$W/xaa/theirs.package.json")
d_xab=$(digest "$W/xab.package.json" "$W/xab/theirs.package.json")
[ -n "$d_xaa" ] && ok "xaa composes the agreement from the package it fetched" \
                || no "xaa composes the agreement from the package it fetched" "no digest"
assert_eq "xab composes the same agreement digest from its side" "$d_xaa" "$d_xab"
[ -n "$d_xaa" ] && note "both read aloud: agreement $(printf '%s' "${d_xaa#sha256:}" | fold -w4 | paste -sd' ' -)"

# The key read back is load-bearing: composition refuses a package under any
# key but the one bound by voice, whatever the directory served.
assert_exit "a key the directory never bound is refused at composition" 20 \
  fed compose "$W/xaa.package.json" "$W/xaa/theirs.package.json" \
    --key "xaa=$KA" --key "xab=$KA" --now "$NOW" --json
tally
