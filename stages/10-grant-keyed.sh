#!/usr/bin/env bash
# Grant-keyed encryption INSIDE one goatnet, and the revoke is TIMED (12 crosses the boundary)
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"

: "${HG_GOATNET_HOST:=}"
[ -n "$HG_GOATNET_HOST" ] || {
  skip "no goatnet with grant-keyd" "set HG_GOATNET_HOST to a host running grant-keyd and a fabric router"
  tally; exit 0; }
SSHO="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"
on() { timeout 90 ssh ${HG_SSH_PORT:+-p $HG_SSH_PORT} $SSHO "${HG_SSH_USER:-ubuntu}@$HG_GOATNET_HOST" "$1" 2>/dev/null; }

# PREREQUISITE: a member must be able to read the key bundle for its own
# release set (zenoh_member_key_read_enabled). Assert the rule exists before testing anything that depends on it, so a failure
# here names the cause instead of looking like a crypto problem.
n=$(on 'sudo docker exec $(sudo docker ps --format "{{.Names}}" | grep -m1 zenoh-router) cat /etc/zenoh/config.json5 2>/dev/null | grep -c "keys/"')
[ "${n:-0}" -gt 1 ] \
  && ok "the router grants per-release-set key reads ($n rules name keys/)" \
  || { no "no key-read rule on the router" "members cannot read their key bundle here (zenoh_member_key_read_enabled); grant-keyed encryption cannot work end to end"; tally; exit 1; }

# grant-keyd has to be running for a rotation to happen at all.
st=$(on 'sudo docker inspect grant-keyd --format "{{.State.Status}}" 2>/dev/null')
[ "$st" = "running" ] && ok "grant-keyd is running" || { no "grant-keyd is $st"; tally; exit 1; }

poll=$(on 'sudo find /opt -name config.json -path "*grant-keyd*" -exec grep -o "\"poll_interval_secs\":[0-9]*" {} \; 2>/dev/null | head -1 | grep -oE "[0-9]+$"')
[ -n "$poll" ] && note "poll interval is ${poll}s — the containment window is bounded by this"

# Rotation is the containment act for grant-keyed encryption: removing a member
# mints a new generation with no copy wrapped to them. grant-keyd publishes no
# ports, so the rotation_duration metric cannot be read from outside; this stage
# times the revoke instead.
# grant-keyd logs `Unchanged { ... }` every poll and `Rotated { ... generation: N }`
# only when it actually rotates, so the last Rotated can be tens of thousands of
# lines back. A --tail window silently finds nothing and reads as "no generation".
gen_now() { on 'sudo docker logs grant-keyd 2>&1 | grep -oE "generation: [0-9]+" | tail -1 | grep -oE "[0-9]+"'; }
before=$(gen_now)
[ -n "$before" ] && ok "current key generation is $before" || skip "no generation in the log yet"

if [ -n "${HG_REVOKE_CMD:-}" ]; then
  t0=$(date +%s)
  on "$HG_REVOKE_CMD" >/dev/null
  for i in $(seq 1 60); do
    after=$(gen_now)
    if [ -n "$after" ] && [ "$after" != "$before" ]; then
      t1=$(date +%s)
      ok "revoke minted a new generation ($before -> $after) in $((t1-t0))s"
      note "this is the containment latency for grant-keyed encryption"
      break
    fi
    sleep 2
  done
  [ "${after:-}" = "${before:-}" ] && no "no new generation within 120s of the revoke"
else
  skip "revoke not fired" "set HG_REVOKE_CMD to the command that removes a member, e.g. 'goat access revoke ...'"
  note "the rotation latency stays unmeasured until this runs"
fi

tally
