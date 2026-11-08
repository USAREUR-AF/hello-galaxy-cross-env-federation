# Start a directory of our own: the saltlick image behind a TLS front.
# Sourced by stages 05 and 05b. A pointer's package_url is https by rule, so the
# directory is reached the way a party reaches a real instance: over TLS, at the
# same URL the pointer names. Caddy issues a certificate for localhost from its
# own local CA, and the stage trusts that CA through HG_SALTLICK_CA.
#
# On return: HG_SALTLICK and HG_SALTLICK_CA are exported, or SALTLICK_UP_SKIP
# says why the directory could not be started. The containers go with the stage.
#
# The write and read budgets are off for this private instance: stage 05 makes
# more writes in a minute than a public instance's default budget allows.

SALTLICK_IMAGE=${SALTLICK_IMAGE:-ghcr.io/usareur-af/saltlick:v0.3.0}
SALTLICK_TLS_IMAGE=${SALTLICK_TLS_IMAGE:-caddy:2.10}
SALTLICK_UP_SKIP=""
_SL=hg-saltlick-$$
_SL_TLS=hg-saltlick-tls-$$

saltlick_down() { docker rm -f "$_SL" "$_SL_TLS" >/dev/null 2>&1 || true; }
trap saltlick_down EXIT

saltlick_up() {
  if ! { command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; }; then
    SALTLICK_UP_SKIP="docker is not available"; return 1
  fi
  docker run -d --name "$_SL" -p 127.0.0.1::8443 \
      -e SALTLICK_WRITE_LIMIT=0 -e SALTLICK_READ_LIMIT=0 "$SALTLICK_IMAGE" >/dev/null 2>&1 \
    || { SALTLICK_UP_SKIP="could not start $SALTLICK_IMAGE; set SALTLICK_IMAGE to a saltlick image you can pull"; return 1; }
  docker run -d --name "$_SL_TLS" --network "container:$_SL" "$SALTLICK_TLS_IMAGE" \
      caddy reverse-proxy --from https://localhost:8443 --to 127.0.0.1:8080 >/dev/null 2>&1 \
    || { SALTLICK_UP_SKIP="could not start $SALTLICK_TLS_IMAGE for the TLS front"; return 1; }
  local port; port=$(docker port "$_SL" 8443/tcp 2>/dev/null | head -1); port=${port##*:}
  export HG_SALTLICK="https://localhost:$port"
  export HG_SALTLICK_CA="$HG_ROOT/.work/saltlick-tls-root-$$.crt"
  local i
  for i in $(seq 1 30); do
    if docker cp "$_SL_TLS:/data/caddy/pki/authorities/local/root.crt" "$HG_SALTLICK_CA" >/dev/null 2>&1 \
       && [ "$(curl -s -o /dev/null -w '%{http_code}' --cacert "$HG_SALTLICK_CA" "$HG_SALTLICK/healthz")" = "200" ]; then
      return 0
    fi
    sleep 1
  done
  SALTLICK_UP_SKIP="the directory did not answer /healthz over TLS: $(docker logs "$_SL" 2>&1 | tail -2)"
  return 1
}

# sl_get <path> [out-file] — GET from the directory; prints the HTTP status.
sl_get() {
  local ca=(); [ -n "${HG_SALTLICK_CA:-}" ] && ca=(--cacert "$HG_SALTLICK_CA")
  curl -s "${ca[@]}" -o "${2:-/dev/null}" -w '%{http_code}' "$HG_SALTLICK$1"
}
