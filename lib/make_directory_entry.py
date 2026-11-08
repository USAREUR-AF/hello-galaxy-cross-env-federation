#!/usr/bin/env python3
"""Build what one party puts in the directory: its CA, its package, its pointer.

  <out>/<sid>-ca.pem         a self-signed CA certificate, the party's trust anchor
  <out>/<sid>.package.json   the compose-full conformance package, offers included,
                             with identity.ca_fingerprint set to the SHA-256 of that
                             CA's DER and re-signed with the party's test key
  <out>/<sid>.pointer.json   the saltlick-pointer/v1 entry: where the directory
                             hosts that package and its sha256, signed with the
                             same key

The pointer's package_url is the directory's own /v1/parties/<sid>/package, so a
party behind NAT needs no public host.

usage: make_directory_entry.py <bundle> <sid> <directory-url> <out-dir>
"""
import base64
import datetime
import hashlib
import json
import os
import sys

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.x509.oid import NameOID


def canonical(o):
    """RFC 8785 for what a package carries: ASCII member names, strings, integers, booleans."""
    return json.dumps(o, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()


def sha256_of(b):
    return "sha256:" + hashlib.sha256(b).hexdigest()


def signed(doc, priv):
    body = {k: v for k, v in doc.items() if k != "signature"}
    return dict(body, signature=base64.standard_b64encode(priv.sign(canonical(body))).decode())


def make_ca(name):
    """A self-signed CA certificate; returns (PEM bytes, DER bytes)."""
    key = ec.generate_private_key(ec.SECP256R1())
    subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, name)])
    now = datetime.datetime.now(datetime.timezone.utc)
    cert = (x509.CertificateBuilder()
            .subject_name(subject).issuer_name(subject)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - datetime.timedelta(minutes=5))
            .not_valid_after(now + datetime.timedelta(days=30))
            .add_extension(x509.BasicConstraints(ca=True, path_length=1), critical=True)
            .add_extension(x509.KeyUsage(digital_signature=False, content_commitment=False,
                                         key_encipherment=False, data_encipherment=False,
                                         key_agreement=False, key_cert_sign=True, crl_sign=True,
                                         encipher_only=False, decipher_only=False), critical=True)
            .sign(key, hashes.SHA256()))
    return cert.public_bytes(serialization.Encoding.PEM), cert.public_bytes(serialization.Encoding.DER)


def build(bundle, sid, directory, out):
    priv = Ed25519PrivateKey.from_private_bytes(
        bytes.fromhex(open(f"{bundle}/vectors/testkeys/{sid}.seed.hex").read().strip()))
    ca_pem, ca_der = make_ca(f"{sid} federation root CA")
    pkg = json.load(open(f"{bundle}/vectors/compose-full/package-{sid}.canonical.json"))
    pkg["identity"]["ca_fingerprint"] = sha256_of(ca_der)
    pkg_bytes = canonical(signed(pkg, priv))
    pointer = {"spec": "saltlick-pointer/v1", "sovereign_id": sid,
               "package_url": f"{directory.rstrip('/')}/v1/parties/{sid}/package",
               "package_sha256": sha256_of(pkg_bytes), "expires": pkg["expires"]}
    os.makedirs(out, exist_ok=True)
    paths = {"ca": f"{out}/{sid}-ca.pem", "package": f"{out}/{sid}.package.json",
             "pointer": f"{out}/{sid}.pointer.json"}
    open(paths["ca"], "wb").write(ca_pem)
    open(paths["package"], "wb").write(pkg_bytes)
    open(paths["pointer"], "wb").write(canonical(signed(pointer, priv)))
    return paths


if __name__ == "__main__":
    for p in build(*sys.argv[1:5]).values():
        print(p)
