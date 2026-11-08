#!/usr/bin/env bash
# The directory hosts a party's pointer, package and CA byte-exact, and refuses what it must
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"
B=$(cat "$HG_ROOT/.bundle-path" 2>/dev/null)
[ -d "${B:-}" ] || { no "stage 01 must run first (no unpacked bundle)"; tally; exit 1; }
python3 -c 'import cryptography' 2>/dev/null \
  || { skip "python3 cryptography is not installed" "needed to sign packages, pointers and writes (pip install cryptography)"; tally; exit 0; }

# This stage always runs its own directory: it binds keys and tests refusals,
# which needs a directory with no history.
unset HG_SALTLICK HG_SALTLICK_CA
. "$HG_ROOT/lib/saltlick_up.sh"
saltlick_up || { skip "no directory" "$SALTLICK_UP_SKIP"; tally; exit 0; }
ok "the published image starts behind TLS and answers /healthz ($SALTLICK_IMAGE)"

W="$HG_ROOT/.work/05"; rm -rf "$W"; mkdir -p "$W"
PUT() { python3 "$HG_ROOT/lib/saltlick_put.py" "$HG_SALTLICK" "$1" "$2" "$B/vectors/testkeys/$3.seed.hex"; }
code() { local r; r=$(PUT "$@"); printf '%s' "${r%% *}"; }
same() { [ "$(shasum -a 256 < "$1")" = "$(shasum -a 256 < "$2")" ] && echo same || echo differ; }

# The invariant the service exists to keep. Anything but 404 means the directory
# has started making decisions, which is the one thing it must never do.
assert_eq "/v1/match does not exist — the directory decides nothing" "404" "$(sl_get /v1/match)"

sl_get /v1/spec "$W/spec.json" >/dev/null
assert_contains "it accepts the pointer record as an entry" "saltlick-pointer/v1" "$(cat "$W/spec.json")"
assert_contains "and says that being listed grants nothing" "advisory" "$(cat "$W/spec.json")"

# xaa's pointer, package and CA. The package is the conformance package, offers
# included, re-signed over a CA of xaa's own (lib/make_directory_entry.py).
python3 "$HG_ROOT/lib/make_directory_entry.py" "$B" xaa "$HG_SALTLICK" "$W" >/dev/null \
  || { no "build xaa's pointer, package and CA"; tally; exit 1; }

# A file never claims a sovereign id: the entry binds the key, so a hosted
# package with no entry is refused.
assert_eq "a package for a party with no entry is refused (409)" "409" "$(code xaa/package "$W/xaa.package.json" xaa)"

assert_eq "xaa's signed pointer is accepted, binding its key on first use (201)" "201" \
          "$(code xaa "$W/xaa.pointer.json" xaa)"
sl_get /v1/parties/xaa "$W/back.pointer.json" >/dev/null
assert_eq "the pointer comes back byte-identical" "same" "$(same "$W/xaa.pointer.json" "$W/back.pointer.json")"
bound=$(curl -s -D - -o /dev/null --cacert "$HG_SALTLICK_CA" "$HG_SALTLICK/v1/parties/xaa" \
        | tr -d '\r' | sed -n 's/^[Xx]-[Ss]altlick-[Bb]ound-[Kk]ey: //p')
assert_eq "the directory serves the key it bound beside the entry" "$(cat "$B/vectors/testkeys/xaa.public.b64")" "$bound"

# A pointer is six members and nothing else: no key, no identity, no contact, no offer.
python3 - "$W/xaa.pointer.json" "$W/extra.pointer.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["cut"] = {"contact": "fed-ops@xaa.example"}
open(sys.argv[2], "w").write(json.dumps(d, sort_keys=True, separators=(",", ":")))
PY
assert_eq "a pointer carrying anything beyond its six members is refused (422)" "422" \
          "$(code xaa "$W/extra.pointer.json" xaa)"

assert_eq "xaa's signed package is hosted beside its entry (201)" "201" "$(code xaa/package "$W/xaa.package.json" xaa)"
sl_get /v1/parties/xaa/package "$W/back.package.json" >/dev/null
assert_eq "the package comes back byte-identical" "same" "$(same "$W/xaa.package.json" "$W/back.package.json")"
assert_eq "xaa's CA certificate is hosted beside its entry (201)" "201" "$(code xaa/ca "$W/xaa-ca.pem" xaa)"
sl_get /v1/parties/xaa/ca "$W/back-ca.pem" >/dev/null
assert_eq "the CA comes back byte-identical" "same" "$(same "$W/xaa-ca.pem" "$W/back-ca.pem")"

sl_get /v1/parties "$W/list.json" >/dev/null
assert_contains "the listing links xaa's hosted package" "/v1/parties/xaa/package" "$(cat "$W/list.json")"
assert_contains "and its hosted CA" "/v1/parties/xaa/ca" "$(cat "$W/list.json")"

# Trust on first use: the first key seen binds, and only that key writes.
assert_eq "a second, unbound key is refused for xaa's entry (403)" "403" "$(code xaa "$W/xaa.pointer.json" xab)"
assert_eq "and for xaa's hosted package (403)" "403" "$(code xaa/package "$W/xaa.package.json" xab)"
assert_eq "and for xaa's hosted CA (403)" "403" "$(code xaa/ca "$W/xaa-ca.pem" xab)"

tally
