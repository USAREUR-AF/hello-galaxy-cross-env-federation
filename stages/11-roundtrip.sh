#!/usr/bin/env bash
# The round trip — the only check the SENDING side can make alone
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"

: "${HG_OURS_HOST:=}" ; : "${HG_PARTNER_HOST:=}"
[ -n "$HG_OURS_HOST" ] && [ -n "$HG_PARTNER_HOST" ] || {
  skip "no cloud tier" "set HG_OURS_HOST and HG_PARTNER_HOST"; tally; exit 0; }
SSHO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
on() { timeout 90 ssh $SSHO "ubuntu@$1" "$2" 2>/dev/null; }

OUR=${HG_OUR_SOVEREIGN:-xab}; THEIR=${HG_THEIR_SOVEREIGN:-xaa}
OUR_WIRE=${HG_OUR_WIRE:-from/$OUR}
THEIR_WIRE=${HG_THEIR_WIRE:-from/$THEIR}
EDGE=${HG_EDGE_CONTAINER:-goat-zenoh-edge-$THEIR}

# `pkill -f <pattern>` matches the command line of the shell RUNNING it, which
# contains the pattern, so the plain form kills the very command that is about to
# start the responder. The bracket class matches the process and not the pattern.
PAT='[f]edcheck-responder.py'

# Start and verify in SEPARATE invocations: a command whose last statement is
# backgrounded returns nothing, so checking in the same one reads empty and looks
# like a responder that failed to start.
stop_responder()  { on "$HG_PARTNER_HOST" "pkill -f '$PAT'" >/dev/null; sleep 1; }
start_responder() { on "$HG_PARTNER_HOST" "nohup python3 /tmp/fedcheck-responder.py $OUR_WIRE $THEIR_WIRE >/tmp/responder.log 2>&1 &" >/dev/null; sleep 3; }
responder_up()    { on "$HG_PARTNER_HOST" "pgrep -fc '$PAT'"; }

# Every OTHER assertion in this exercise reads the far side directly, which needs
# shell on both sovereigns. A real publisher has one side. This is the only stage
# whose evidence a publisher could actually obtain for itself.
stop_responder; start_responder
[ "$(responder_up)" -ge 1 ] 2>/dev/null || {
  skip "no responder on the receiving side" \
       "copy goatcore ops/federation/roundtrip/responder.py to /tmp/fedcheck-responder.py there, and fedcheck.sh to /tmp on our side"; tally; exit 0; }

out=$(on "$HG_OURS_HOST" "/tmp/fedcheck.sh $OUR_WIRE $THEIR_WIRE 25")
case "$out" in
  *PASS*) ok "a nonce we published came back acknowledged by THEIR router$(printf '%s' "$out" | grep -oE ' in [0-9]+ms')" ;;
  *)      no "the round trip did not complete" "$out"; tally; exit 1 ;;
esac

# A CHECK THAT CANNOT FAIL IS NOT A CHECK. Both states below are ones in
# which every one-way assertion in stage 09 still passes.
stop_responder
out=$(on "$HG_OURS_HOST" "/tmp/fedcheck.sh $OUR_WIRE $THEIR_WIRE 8")
case "$out" in
  *FAIL*) ok "with their consumer stopped it FAILS — so the pass above meant something" ;;
  *)      no "it passed with the far side not consuming; this check cannot fail" ;;
esac

start_responder
on "$HG_OURS_HOST" "sudo docker stop $EDGE" >/dev/null
out=$(on "$HG_OURS_HOST" "/tmp/fedcheck.sh $OUR_WIRE $THEIR_WIRE 8")
case "$out" in
  *FAIL*) ok "with the peering edge stopped it FAILS" ;;
  *)      no "it passed with the edge down" ;;
esac

on "$HG_OURS_HOST" "sudo docker start $EDGE" >/dev/null; sleep 18
out=$(on "$HG_OURS_HOST" "/tmp/fedcheck.sh $OUR_WIRE $THEIR_WIRE 25")
case "$out" in
  *PASS*) ok "and PASSES again once the edge is back" ;;
  *)      no "it did not recover after the edge returned" "$out" ;;
esac

tally
