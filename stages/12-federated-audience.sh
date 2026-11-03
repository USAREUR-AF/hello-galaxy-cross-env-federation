#!/usr/bin/env bash
# A FEDERATED partner holds an audience slot, and fetches the key bundle
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"

: "${HG_OURS_HOST:=}" ; : "${HG_PARTNER_HOST:=}"
[ -n "$HG_OURS_HOST" ] && [ -n "$HG_PARTNER_HOST" ] || {
  skip "no cloud tier" "set HG_OURS_HOST and HG_PARTNER_HOST"; tally; exit 0; }
SSHO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -o LogLevel=ERROR"
ours()   { timeout 90 ssh $SSHO "ubuntu@$HG_OURS_HOST" "$1" 2>/dev/null; }
theirs() { timeout 90 ssh $SSHO "ubuntu@$HG_PARTNER_HOST" "$1" 2>/dev/null; }

THEIR=${HG_THEIR_SOVEREIGN:-xaa}
KEYD_CFG=${HG_KEYD_CONFIG:-/opt/lab/keyd/config.json}
CORE_CFG=${HG_CORE_CONFIG:-/opt/lab/core.json5}
RS=${HG_RELEASE_SET:-weather}
PARTNER_ID=${HG_PARTNER_MEMBER:-spiffe://$THEIR.fed.example/member/partner}

ours "test -f $KEYD_CFG" >/dev/null 2>&1 || {
  skip "no grant-keyd config on our side" "set HG_KEYD_CONFIG; stage 12 needs a keyd audience to admit into"
  tally; exit 0; }

# WHY THIS STAGE EXISTS. Stage 10 exercises grant-keyed encryption inside ONE
# goatnet. A federated partner is, by construction, in a different trust domain;
# ADR 1169 decisions 2 and 3 let grant-keyd admit a member from a federated domain
# and let the edge render the partner's key read. This stage proves both.

# ---- 1. the audience admits a member from ANOTHER trust domain --------------
out=$(ours "sudo grant-keyd $KEYD_CFG --once 2>&1 | tail -2")
case "$out" in
  *Rotated*) ok "grant-keyd rotated with the federated member in the audience — $(printf '%s' "$out" | grep -oE 'members: [0-9]+')" ;;
  *)         no "grant-keyd did not rotate" "$out"; tally; exit 1 ;;
esac

# The slot has to be THEIRS, by their own SPIFFE id. A member count alone would
# pass with the partner silently dropped and a local member counted twice.
slots=$(ours "curl -s -m 8 'http://127.0.0.1:8000/keys/$RS/**'" | python3 -c "
import json,sys,base64
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
for r in d:
    b=json.loads(base64.b64decode(r['value']))
    print('\n'.join(b.get('members',{})))
" 2>/dev/null)
case "$slots" in
  *"$PARTNER_ID"*) ok "the bundle carries a slot for $PARTNER_ID" ;;
  *)               no "no slot for the federated partner" "slots seen: ${slots:-<none>}" ;;
esac

# ---- 2. admitting the domain is a DECISION, not a consequence of federation --
# The trust bundle already carries their root — that is what federation put
# there. Withdrawing the admission must still refuse, or "we federate with them"
# would silently mean "they may read our sealed data".
# Stash the value in a SIDE FILE, not in the config: grant-keyd refuses unknown
# fields, which is the right fail-closed behaviour and makes a config-resident
# scratch key a parse error rather than a no-op.
ours "sudo cp $KEYD_CFG ${KEYD_CFG}.bak && sudo python3 - <<'PY'
import json
p='$KEYD_CFG'; c=json.load(open(p))
c['federated_trust_domains']=[]; json.dump(c,open(p,'w'),indent=2)
PY" >/dev/null
out=$(ours "sudo grant-keyd $KEYD_CFG --once 2>&1 | tail -1")
case "$out" in
  *Failed*|*nor\ federated*) ok "withdrawing the domain refuses the same member, fail-closed" ;;
  *)                         no "the member was admitted with no federated domain configured" "$out" ;;
esac
ours "sudo mv ${KEYD_CFG}.bak $KEYD_CFG" >/dev/null
ours "sudo grant-keyd $KEYD_CFG --once >/dev/null 2>&1"

# ---- 3. the partner can actually FETCH it across the edge -------------------
# THE TRAP WORTH KNOWING: a queryable declared WIDER than the granted lane is
# refused silently. A core storing "keys/**"
# declares exactly that against a per-release-set grant, so the fetch returns []
# and reads as "no bundle published".
store=$(ours "sudo grep -oE '\"keys/[^\"]*\"' $CORE_CFG 2>/dev/null | head -1")
case "$store" in
  *"keys/$RS/"*) ok "our core's key storage is scoped to the granted set ($store)" ;;
  *keys/\*\**)   no "our core stores keys/** — WIDER than the grant, so the declaration is refused silently" \
                    "narrow it to keys/$RS/**" ;;
  *)             note "could not read the core's key storage scope" ;;
esac

got=$(theirs "curl -s -m 12 'http://127.0.0.1:8000/keys/$RS/**'" | python3 -c "
import json,sys,base64
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
for r in d:
    b=json.loads(base64.b64decode(r['value']))
    print(r['key'], '|', ','.join(b.get('members',{})))
" 2>/dev/null)
if [ -n "$got" ]; then
  ok "the partner fetched the bundle ACROSS THE EDGE — ${got%% |*}"
  case "$got" in
    *"$PARTNER_ID"*) ok "and it contains the slot wrapped to them" ;;
    *)               no "the bundle they fetched has no slot for them" "$got" ;;
  esac
else
  no "the partner could not fetch the bundle" \
     "with the audience configured this should return it; check the edge's partner-keys rules and the core's storage scope"
fi

tally
