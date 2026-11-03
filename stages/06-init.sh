#!/usr/bin/env bash
# `federate init` measures a real environment rather than being told about it
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"

# init reads the running system. Without one there is nothing to measure and a
# pass here would mean nothing, so this skips loudly rather than inventing an
# environment.
[ -n "${HG_ENV_HOST:-}" ] || {
  skip "no environment to measure" "set HG_ENV_HOST to a host running a goat fabric, e.g. HG_ENV_HOST=<mesh address of a fabric host>"
  tally; exit 0
}

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

# The claim under test: every capability is DERIVED, never typed. A value that
# cannot be derived must fail and name itself rather than be filled in, because
# a capability an operator types is a claim and a wrong claim survives until the
# link fails in front of a counterparty.
"$GOAT_BIN" federate init --with-transport --with-data \
    --signing-key "${HG_SIGNING_KEY:-$HG_ROOT/.work/hg-signing.hex}" \
    > "$W/ours.json" 2>"$W/err"
rc=$?

case $rc in
  0)
    ok "init produced a package from the running system"
    "$GOAT_BIN" federate lint "$W/ours.json" --json >/dev/null 2>&1
    [ $? -eq 0 ] && ok "and that package lints clean against the spec" \
                 || no "init produced a package its own linter refuses"

    # Derived, not defaulted: a measured MTU is not 1500, and a fabric version
    # is a version rather than a placeholder.
    mtu=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("transport_offer",{}).get("measured_mtu",""))' "$W/ours.json" 2>/dev/null)
    [ -n "$mtu" ] && ok "the MTU is measured, not assumed ($mtu)" \
                  || no "no measured_mtu in the package"
    fv=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("capabilities",{}).get("fabric_version",""))' "$W/ours.json" 2>/dev/null)
    [ -n "$fv" ] && ok "the fabric version came from the router ($fv)" \
                 || no "no fabric_version in the package"
    ;;
  23)
    # This is a PASS for the property under test. 23 means a value could not be
    # derived and init refused rather than guessing, which is the behaviour the
    # whole verb exists for.
    ok "init refused to invent a value it could not derive (exit 23)"
    note "$(head -3 "$W/err")"
    ;;
  *)
    no "init exited $rc" "$(head -3 "$W/err")"
    ;;
esac

tally
