# The federation bundle

The artefact a counterparty receives: `federation-package-spec.md`, the conformance vectors, and
`verify-bundle.sh` to check it arrived intact.

Rebuild it from [`usareur-af/goatcore`](https://github.com/usareur-af/goatcore) with:

    ops/federation/bundle/make-bundle.sh --out-dir <here>

It is committed rather than fetched so this repository runs with no access to goat at all — which is
the property the whole exercise depends on. When the specification or a vector changes, goatcore's
`ops/ci/check-federation-bundle.sh` gate fires there and the new tarball is copied here.

Committed: `goat-federation-v1-470466b007a0.tar.gz`, content hash
`470466b007a079bcf6c5ef7c0fcd1c8d1fef2269076c74064839c146dcefc872` (the same value as goatcore's
`ops/federation/bundle/content.sha256`).
