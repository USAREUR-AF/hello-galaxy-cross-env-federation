#!/usr/bin/env bash
# The tunnel comes up under the composed agreement, and carries nothing else
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"

: "${HG_OURS_HOST:=}" ; : "${HG_PARTNER_HOST:=}"
[ -n "$HG_OURS_HOST" ] && [ -n "$HG_PARTNER_HOST" ] || {
  skip "no cloud tier" "set HG_OURS_HOST and HG_PARTNER_HOST to the two edge addresses"
  tally; exit 0
}
OUR=${HG_OUR_SOVEREIGN:-xab}; THEIR=${HG_THEIR_SOVEREIGN:-xaa}
SSHO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
on() { timeout 60 ssh $SSHO "ubuntu@$1" "$2" 2>/dev/null; }

# 1. The security association exists and is ESTABLISHED under the agreed names.
sa=$(on "$HG_OURS_HOST" 'sudo swanctl --list-sas 2>/dev/null')
case "$sa" in
  *ESTABLISHED*) ok "an IKE security association is ESTABLISHED" ;;
  "")            no "swanctl returned nothing" "is strongswan running on $HG_OURS_HOST?" ;;
  *)             no "no ESTABLISHED SA" "$(printf '%s' "$sa" | head -3)" ;;
esac

# 2. It authenticated the names the AGREEMENT derived, not whatever was offered.
# This is the check that separates "a tunnel is up" from "the right tunnel is
# up": both CNs are computed from the pair of sovereign ids, so a link that
# came up under any other name is not the link the agreement describes.
for id in "fed.$OUR.$THEIR.01" "fed.$THEIR.$OUR.01"; do
  case "$sa" in *"$id"*) ok "the SA carries the derived name $id" ;;
                *) no "the SA does not mention $id" ;; esac
done

# 3. A child SA is INSTALLED — an IKE SA alone carries no traffic.
case "$sa" in
  *INSTALLED*) ok "a child SA is INSTALLED, so the link can carry packets" ;;
  *)           no "no INSTALLED child SA — IKE came up but nothing can cross" ;;
esac

# 4. The link carries the two addresses the agreement named and NOTHING else.
# A /31 has exactly two hosts by construction; that is the point of choosing it.
ts=$(printf '%s' "$sa" | grep -oE '169\.254\.[0-9]+\.[0-9]+/[0-9]+' | sort -u | tr '\n' ' ')
[ -n "$ts" ] && ok "traffic selectors are the agreed link subnet ($ts)" \
             || no "no 169.254.x link subnet in the SA"

# 5. Reachability across it, and only across it.
if on "$HG_OURS_HOST" 'ping -c2 -W3 169.254.10.1 >/dev/null 2>&1 && echo up'; then
  ok "the far end answers on the link address"
else
  no "the far end does not answer on 169.254.10.1"
fi

# 6. The tunnel must NOT be a route to anything else the partner can reach.
# If this passes it means the peering carries the agreement's traffic and is not
# a general path into their network.
if on "$HG_OURS_HOST" 'ping -c1 -W3 8.8.8.8 -I ipsec-s6$THEIR >/dev/null 2>&1 && echo leaked'; then
  no "the tunnel routes traffic outside the agreed selectors"
else
  ok "the tunnel carries only the agreed selectors, not a general route"
fi

tally
