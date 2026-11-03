#!/usr/bin/env python3
"""Sign and send a saltlick write, the way the service's own tests do.

The signed statement saltlick verifies on every write:
    "saltlick-request/v1" \n METHOD \n <sovereign_id> \n sha256:<hex of body> \n <presented key b64> \n
Headers: X-Saltlick-Key (44 char base64 raw Ed25519 public key)
         X-Saltlick-Signature (88 char base64 signature over that statement)

usage: saltlick_put.py <base-url> <sovereign_id> <package-file> <seed-hex-file>
prints: "<http status> <body first line>"
"""
import hashlib, sys, base64, urllib.request, urllib.error

try:
    from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
    from cryptography.hazmat.primitives import serialization
except ImportError:
    print("000 python cryptography not installed"); sys.exit(0)

base, sid, pkg, seedfile = sys.argv[1:5]
seed = bytes.fromhex(open(seedfile).read().strip())
priv = Ed25519PrivateKey.from_private_bytes(seed)
pub = priv.public_key().public_bytes(serialization.Encoding.Raw,
                                     serialization.PublicFormat.Raw)
pub_b64 = base64.standard_b64encode(pub).decode()
body = open(pkg, "rb").read()
stmt = "\n".join(["saltlick-request/v1", "PUT", sid,
                  "sha256:" + hashlib.sha256(body).hexdigest(), pub_b64, ""]).encode()
sig_b64 = base64.standard_b64encode(priv.sign(stmt)).decode()

req = urllib.request.Request(f"{base}/v1/parties/{sid}", data=body, method="PUT",
                             headers={"Content-Type": "application/json",
                                      "X-Saltlick-Key": pub_b64,
                                      "X-Saltlick-Signature": sig_b64})
try:
    with urllib.request.urlopen(req, timeout=10) as r:
        print(r.status, r.read(200).decode("utf-8", "replace").replace("\n", " "))
except urllib.error.HTTPError as e:
    print(e.code, e.read(200).decode("utf-8", "replace").replace("\n", " "))
except Exception as e:
    print("000", e)
