#!/usr/bin/env bash
# Bundle integrity — the partner's own verifier, and its refusal self-test
set -uo pipefail
. "$HG_ROOT/lib/assert.sh"

BUNDLE_TGZ=$(ls "$HG_ROOT"/bundle/*.tar.gz 2>/dev/null | head -1)
if [ -z "$BUNDLE_TGZ" ]; then
  no "a bundle to verify" "put the tarball from ops/federation/bundle/make-bundle.sh in bundle/"
  tally; exit 1
fi

# Unpacked into a shared workdir, NOT a mktemp that this stage then deletes:
# later stages read the same tree. .work/ is gitignored and rebuilt every run.
WORK="$HG_ROOT/.work"
rm -rf "$WORK"; mkdir -p "$WORK"
tar xzf "$BUNDLE_TGZ" -C "$WORK"
B=$(ls -d "$WORK"/goat-federation-* 2>/dev/null | head -1)
[ -d "$B" ] || { no "the tarball unpacks to a bundle directory"; tally; exit 1; }
echo "$B" > "$HG_ROOT/.bundle-path"

# The partner's own verifier, on the artefact as received. This is the check a
# counterparty runs before trusting anything else in the tarball.
assert_exit "the bundle verifies against its own MANIFEST" 0 bash -c "cd '$B' && ./verify-bundle.sh"

# A verifier that always says yes is not a verifier. Prove it refuses.
C=$(mktemp -d); cp -R "$B/." "$C/"
printf 'x' > "$C/vectors/compose-full/UNLISTED.json"
assert_exit "it refuses a file the MANIFEST does not list" 1 bash -c "cd '$C' && ./verify-bundle.sh"
rm -f "$C/vectors/compose-full/UNLISTED.json"
printf '\n#tampered\n' >> "$C/federation-package-spec.md"
assert_exit "it refuses an altered specification" 1 bash -c "cd '$C' && ./verify-bundle.sh"
rm -rf "$C"

n_vec=$(find "$B/vectors" -maxdepth 1 -mindepth 1 -type d | wc -l | tr -d ' ')
[ "$n_vec" -ge 10 ] && ok "the bundle carries $n_vec vector directories" \
                    || no "expected 10+ vector directories, found $n_vec"

tally
