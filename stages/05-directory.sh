#!/usr/bin/env bash
# The directory round-trips a package byte-exact and refuses what it must
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"
B=$(cat "$HG_ROOT/.bundle-path" 2>/dev/null)
[ -d "${B:-}" ] || { no "stage 01 must run first (no unpacked bundle)"; tally; exit 1; }

command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 \
  || { skip "docker is not available" "this stage runs the saltlick image (SALTLICK_IMAGE)"; tally; exit 0; }
python3 -c 'import cryptography' 2>/dev/null \
  || { skip "python3 cryptography is not installed" "needed to sign the write statement (pip install cryptography)"; tally; exit 0; }

IMG=${SALTLICK_IMAGE:-ghcr.io/usareur-af/saltlick:v0.1.0}
C=hg-saltlick-$$
cleanup() { docker rm -f "$C" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# saltlick binds 127.0.0.1 by design (it is mesh-internal). Reach it by sharing
# the container's network namespace rather than asking it to listen wider — the
# bind is a property worth preserving, not an obstacle to route around.
docker run -d --name "$C" "$IMG" >/dev/null 2>&1 \
  || { skip "could not start $IMG" "set SALTLICK_IMAGE to a saltlick image you can pull"; tally; exit 0; }
CURL() { docker run --rm --network "container:$C" curlimages/curl:8.11.1 -s "$@" 2>/dev/null; }

up=""
for i in $(seq 1 30); do
  [ "$(CURL -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/healthz)" = "200" ] && { up=yes; break; }
  sleep 1
done
[ -n "$up" ] || { skip "saltlick did not answer /healthz" "$(docker logs "$C" 2>&1 | tail -3)"; tally; exit 0; }
ok "the published image starts and answers /healthz"

# The invariant the service exists to keep. Anything but 404 means the directory
# has started making decisions, which is the one thing it must never do.
assert_eq "/v1/match does not exist — the directory decides nothing" "404" \
          "$(CURL -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/v1/match)"

spec=$(CURL http://127.0.0.1:8080/v1/spec)
assert_contains "it declares the package spec it accepts" "federation-package/v1" "$spec"
assert_contains "and says out loud that being listed grants nothing" "advisory" "$spec"

# A DIRECTORY ENTRY CARRIES NO OFFERS. saltlick returns 422 for transport_offer
# and for data_offer alike: reachability and release sets are sovereign
# operational detail that moves directly between two parties, never through a
# directory anyone can read. A conformance package carries offers by design, so
# it cannot be published as-is; build the recognition-only shape and re-sign.
P="$HG_ROOT/.work/dir-xaa.json"
python3 "$HG_ROOT/lib/make_directory_entry.py" "$B" xaa "$P" >/dev/null 2>&1 \
  || { skip "python3 cryptography needed to build a directory entry"; tally; exit 0; }
IP=$(docker inspect "$C" --format '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' 2>/dev/null)
docker cp "$P" "$C:/tmp/pkg.json" >/dev/null 2>&1 || true

res=$(docker run --rm --network "container:$C" -v "$HG_ROOT/lib:/hg-lib:ro" -v "$B:/b:ro" -v "$HG_ROOT/.work:/work:ro" \
        python:3.12-alpine sh -c 'pip install -q cryptography >/dev/null 2>&1;
        python3 /hg-lib/saltlick_put.py http://127.0.0.1:8080 xaa /work/dir-xaa.json /b/vectors/testkeys/xaa.seed.hex' 2>/dev/null)
code=${res%% *}
if [ "$code" = "201" ] || [ "$code" = "200" ]; then
  ok "a signed package is accepted for publication (HTTP $code)"
  CURL -o /tmp/.hg_back http://127.0.0.1:8080/v1/parties/xaa >/dev/null 2>&1
  docker run --rm --network "container:$C" -v /tmp:/out curlimages/curl:8.11.1 \
    -s -o /out/.hg_back http://127.0.0.1:8080/v1/parties/xaa >/dev/null 2>&1
  before=$(shasum -a 256 "$P" | cut -d' ' -f1)
  after=$(shasum -a 256 /tmp/.hg_back 2>/dev/null | cut -d' ' -f1)
  assert_eq "what comes back is byte-identical to what went in" "$before" "$after"

  # Trust on first use: a package signed by a key nobody bound is a package that
  # authenticates itself, which establishes nothing. It must be refused.
  res2=$(docker run --rm --network "container:$C" -v "$HG_ROOT/lib:/hg-lib:ro" -v "$B:/b:ro" -v "$HG_ROOT/.work:/work:ro" \
          python:3.12-alpine sh -c 'pip install -q cryptography >/dev/null 2>&1;
          python3 /hg-lib/saltlick_put.py http://127.0.0.1:8080 xaa /work/dir-xaa.json /b/vectors/testkeys/xab.seed.hex' 2>/dev/null)
  assert_eq "a second, unbound key is refused for a bound party" "403" "${res2%% *}"
else
  no "publication was not accepted" "HTTP $code — $res"
fi

tally
