#!/usr/bin/env bash
# The edge terminates the relationship — nothing behind it is reachable
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"

: "${HG_OURS_HOST:=}" ; : "${HG_PARTNER_HOST:=}"
[ -n "$HG_OURS_HOST" ] && [ -n "$HG_PARTNER_HOST" ] || {
  skip "no cloud tier" "set HG_OURS_HOST and HG_PARTNER_HOST"; tally; exit 0; }
OUR=${HG_OUR_SOVEREIGN:-xab}; THEIR=${HG_THEIR_SOVEREIGN:-xaa}
OUR_CA=${HG_OUR_CA_SUBJECT:-$OUR Root CA}; THEIR_CA=${HG_THEIR_CA_SUBJECT:-$THEIR-federation-root}
SSHO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
on() { timeout 60 ssh $SSHO "ubuntu@$1" "$2" 2>/dev/null; }

# The whole design rests on this: each side holds ONE foreign authority, on the
# edge, and never in a core router. A foreign root inside a core IS an
# authorization grant, because the access layer matches a name and cannot see
# the issuer.
for pair in "$HG_OURS_HOST:ours:$THEIR_CA:$OUR_CA" \
            "$HG_PARTNER_HOST:partner:$OUR_CA:$THEIR_CA"; do
  IFS=: read -r host label want notwant <<<"$pair"
  subs=$(on "$host" 'for f in /etc/swanctl/x509ca/*.pem; do sudo openssl x509 -in "$f" -noout -subject 2>/dev/null; done')
  case "$subs" in
    *"$want"*) ok "$label edge trusts the counterparty root ($want)" ;;
    *)         no "$label edge does not carry $want" "$subs" ;;
  esac
  # and only that one
  n=$(printf '%s' "$subs" | grep -c 'subject=' || true)
  [ "${n:-0}" -eq 1 ] && ok "$label edge holds exactly ONE foreign authority" \
                      || no "$label edge holds $n authorities, expected 1" "$subs"
done

# The edge must not be a route into anything behind it. The counterparty can
# reach the link address and nothing else — that is what "terminates" means.
if on "$HG_PARTNER_HOST" 'ping -c2 -W3 169.254.10.0 >/dev/null 2>&1 && echo up'; then
  ok "the counterparty reaches our edge on the agreed link address"
else
  no "the counterparty cannot reach our edge on 169.254.10.0"
fi
if [ -z "${HG_OUR_PRIVATE_ADDR:-}" ]; then
  skip "private-subnet reachability not checked" "set HG_OUR_PRIVATE_ADDR to an address on our private subnet"
elif on "$HG_PARTNER_HOST" "ping -c1 -W3 $HG_OUR_PRIVATE_ADDR >/dev/null 2>&1 && echo reachable"; then
  no "the counterparty can reach our PRIVATE subnet — the edge is not terminating"
else
  ok "the counterparty cannot reach anything on our private subnet"
fi

# The XFRM interface id is derived per peering so one edge host can carry two
# without them sharing a kernel policy namespace.
ifid=$(on "$HG_OURS_HOST" 'ip -d link show ipsec-s6$THEIR 2>/dev/null | grep -oE "if_id 0x[0-9a-f]+"')
[ -n "$ifid" ] && ok "the peering has its own xfrm interface id ($ifid)" \
               || no "no xfrm if_id on ipsec-s6$THEIR — two peerings would collide"

tally
