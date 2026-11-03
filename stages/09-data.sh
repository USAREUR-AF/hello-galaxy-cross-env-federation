#!/usr/bin/env bash
# Data crosses both ways, read back from storage on the RECEIVING side
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"

: "${HG_OURS_HOST:=}" ; : "${HG_PARTNER_HOST:=}"
[ -n "$HG_OURS_HOST" ] && [ -n "$HG_PARTNER_HOST" ] || {
  skip "no cloud tier" "set HG_OURS_HOST and HG_PARTNER_HOST"; tally; exit 0; }
OUR=${HG_OUR_SOVEREIGN:-xab}; THEIR=${HG_THEIR_SOVEREIGN:-xaa}
SSHO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
on() { timeout 60 ssh $SSHO "ubuntu@$1" "$2" 2>/dev/null; }

# A fabric has to exist on both ends. Without one this stage would be asserting
# nothing, so it says so rather than passing.
have=$(on "$HG_OURS_HOST" 'sudo docker ps --format "{{.Names}}" 2>/dev/null | grep -c zenoh')
[ "${have:-0}" -ge 1 ] || {
  skip "no fabric router on the edge hosts" \
       "stage 09 needs goat-zenoh-edge deployed on both; the tunnel (07/08) is up and independent of this"
  tally; exit 0; }

# The REST value comes back base64 whenever it is not JSON, and nothing says so.
# A literal grep for the payload silently finds nothing and reads as "the data
# never arrived" — decode before asserting.
value_of() { # host, key
  on "$1" "curl -s -m 8 http://127.0.0.1:8000/$2" \
    | grep -oE '\"value\":\"[^\"]*\"' | head -1 | sed 's/.*\"value\":\"//;s/\"$//' \
    | { read -r b64 || true; [ -n "${b64:-}" ] && printf '%s' "$b64" | base64 -d 2>/dev/null || true; }
}

STAMP="hg-$(date +%s)"

# DIRECTION 1 — them to us, into the prefix the agreement names.
on "$HG_PARTNER_HOST" "curl -s -m 8 -X PUT -d '$STAMP-in' http://127.0.0.1:8000/from/$THEIR/probe" >/dev/null
sleep 4
got=$(value_of "$HG_OURS_HOST" "from/$THEIR/probe")
# Read back from the RECEIVING side's storage. An ACL allow proves the write was
# permitted; only reading it back proves it was delivered.
[ "$got" = "$STAMP-in" ] && ok "their write into from/$THEIR/** arrived and reads back on our side" \
                         || no "not delivered" "expected '$STAMP-in', read '${got:-<nothing>}'"

# DIRECTION 2 — us to them, the declared release set, UNDER ITS WIRE NAME.
#
# `release/weather/**` is the STAGING name and it never appears on the link: the
# republisher lifts it onto `from/<our sovereign>/` before anything reaches the
# edge, because the fabric cannot rename a key expression in transit.
# A peering configured from the agreement refuses the staging name at the far
# side, whose ingress prefix admits `from/<our sovereign>/**`.
on "$HG_OURS_HOST" "curl -s -m 8 -X PUT -d '$STAMP-out' http://127.0.0.1:8000/from/$OUR/weather/probe" >/dev/null
sleep 4
got=$(value_of "$HG_PARTNER_HOST" "from/$OUR/weather/probe")
[ "$got" = "$STAMP-out" ] && ok "our release set arrived under its WIRE name and reads back on their side" \
                          || no "not delivered" "expected '$STAMP-out', read '${got:-<nothing>}'"

# THE REFUSAL — a write outside the agreed prefixes must be denied. Without this
# the two passes above only prove a pipe, not a boundary.
on "$HG_PARTNER_HOST" "curl -s -m 8 -X PUT -d 'nope' http://127.0.0.1:8000/ops/fabric/hijack" >/dev/null
sleep 4
got=$(value_of "$HG_OURS_HOST" "ops/fabric/hijack")
[ -z "$got" ] && ok "their write outside the agreement did NOT cross" \
              || no "a write to ops/** crossed the edge — the boundary is not holding"

tally
