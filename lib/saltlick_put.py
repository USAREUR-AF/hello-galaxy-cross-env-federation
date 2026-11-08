#!/usr/bin/env python3
"""Sign and send one saltlick write: an entry, a hosted package, or a hosted CA.

The statement saltlick verifies on every write, five newline-terminated lines:
    saltlick-request/v1
    PUT
    <resource: the path below /v1/parties/ -- xaa, xaa/package or xaa/ca>
    sha256:<hex of the body>
    <the presented key, base64>
Headers: X-Saltlick-Key (44-character base64 raw Ed25519 verifying key)
         X-Saltlick-Signature (88-character base64 signature over that statement)

usage: saltlick_put.py <base-url> <resource> <file> <seed-hex-file>
prints: "<http status> <first 200 bytes of the reply>"

HG_SALTLICK_CA names a PEM file of extra roots for the directory's TLS
certificate, for an instance behind a private CA.
"""
import base64
import hashlib
import os
import ssl
import sys
import urllib.error
import urllib.request

try:
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
except ImportError:
    print("000 python cryptography not installed")
    sys.exit(0)


def tls_context():
    ctx = ssl.create_default_context()
    ca = os.environ.get("HG_SALTLICK_CA", "")
    if ca:
        ctx.load_verify_locations(ca)
    return ctx


def load_seed(path):
    return Ed25519PrivateKey.from_private_bytes(bytes.fromhex(open(path).read().strip()))


def key_b64(priv):
    raw = priv.public_key().public_bytes(serialization.Encoding.Raw, serialization.PublicFormat.Raw)
    return base64.standard_b64encode(raw).decode()


def statement(method, resource, body, key):
    return "\n".join(["saltlick-request/v1", method, resource,
                      "sha256:" + hashlib.sha256(body).hexdigest(), key, ""]).encode()


def put(base, resource, body, priv):
    """PUT body to <base>/v1/parties/<resource>; returns (status, reply bytes)."""
    key = key_b64(priv)
    ctype = "application/pem-certificate-chain" if resource.endswith("/ca") else "application/json"
    req = urllib.request.Request(
        f"{base.rstrip('/')}/v1/parties/{resource}", data=body, method="PUT",
        headers={"Content-Type": ctype, "X-Saltlick-Key": key,
                 "X-Saltlick-Signature": base64.standard_b64encode(
                     priv.sign(statement("PUT", resource, body, key))).decode()})
    try:
        with urllib.request.urlopen(req, timeout=10, context=tls_context()) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


if __name__ == "__main__":
    base, resource, path, seedfile = sys.argv[1:5]
    try:
        status, reply = put(base, resource, open(path, "rb").read(), load_seed(seedfile))
        print(status, reply[:200].decode("utf-8", "replace").replace("\n", " "))
    except Exception as e:  # the stage prints whatever went wrong beside the failed check
        print("000", e)
