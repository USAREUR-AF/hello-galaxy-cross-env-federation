#!/usr/bin/env python3
"""Two parties federate through the directory, as the goatcore driver's phase 5 does.

Each party publishes its signed pointer, uploads its signed package and its CA
certificate, then fetches the other's package through the other's pointer and
checks it: the sha256 against the pointer, both signatures against the verifying
key bound by the voice read-back, and the hosted CA against the package's
identity.ca_fingerprint. The directory is an input to none of those checks; the
bound key and the package's own fingerprint are.

The bound keys are the bundle's test keys (vectors/testkeys/<sid>.public.b64):
they stand for what each party read aloud to the other on the one call.

Writes: six, one pointer, one package and one CA per party, which fits a
directory's default write budget.

usage: directory_flow.py <directory-url> <bundle> <work-dir>
writes: <work>/<sid>.package.json         our package
        <work>/<sid>/theirs.package.json  the counterparty's, as fetched and checked
        <work>/<sid>/theirs-ca.pem        their CA, as fetched and checked
"""
import base64
import hashlib
import json
import os
import re
import sys
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from cryptography.exceptions import InvalidSignature  # noqa: E402
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey  # noqa: E402

from make_directory_entry import build, canonical, make_ca, sha256_of  # noqa: E402
from saltlick_put import load_seed, put, tls_context  # noqa: E402

BASE, BUNDLE, WORK = sys.argv[1].rstrip("/"), sys.argv[2], sys.argv[3]
PARTIES = ("xaa", "xab")
BOUND = {s: open(f"{BUNDLE}/vectors/testkeys/{s}.public.b64").read().strip() for s in PARTIES}

P = F = 0


def chk(name, ok, detail=""):
    global P, F
    if ok:
        print(f"  PASS  {name}")
        P += 1
    else:
        print(f"  FAIL  {name}  {detail}")
        F += 1


def get(url):
    try:
        with urllib.request.urlopen(url, timeout=10, context=tls_context()) as r:
            return r.status, {k.lower(): v for k, v in r.headers.items()}, r.read()
    except urllib.error.HTTPError as e:
        return e.code, {}, e.read()


def groups(s):
    g = [s[i:i + 4] for i in range(0, len(s), 4)]
    return f"{len(g)} groups: " + " ".join(g)


def verifies(doc, key_b64):
    try:
        Ed25519PublicKey.from_public_bytes(base64.standard_b64decode(key_b64)).verify(
            base64.standard_b64decode(doc.get("signature", "")),
            canonical({k: v for k, v in doc.items() if k != "signature"}))
        return True
    except (InvalidSignature, ValueError):
        return False


PEM_RE = re.compile(rb"-----BEGIN CERTIFICATE-----\s*(.*?)\s*-----END CERTIFICATE-----", re.S)


def ca_matches(pem, fingerprint):
    """True when a certificate in pem has SHA-256 (over its DER) equal to fingerprint."""
    return any(sha256_of(base64.b64decode(b"".join(m.group(1).split()))) == fingerprint
               for m in PEM_RE.finditer(pem))


# 1. PUBLISH. Each party: pointer first (its first write binds the key), then the
# package and the CA, which the directory accepts only for an entry that exists
# and only under that entry's key.
made = {}
for sid in PARTIES:
    made[sid] = build(BUNDLE, sid, BASE, WORK)
    seed = load_seed(f"{BUNDLE}/vectors/testkeys/{sid}.seed.hex")
    for resource, path in ((sid, made[sid]["pointer"]), (f"{sid}/package", made[sid]["package"]),
                           (f"{sid}/ca", made[sid]["ca"])):
        status, reply = put(BASE, resource, open(path, "rb").read(), seed)
        chk(f"{sid} publishes {resource.replace(sid + '/', 'its ') if '/' in resource else 'its pointer'}",
            status in (200, 201), f"HTTP {status} {reply[:200]!r}")

# 2. THE ONE CALL. What each party reads aloud, group count first; the other
# reads it back. This is the binding; the directory caches it and is never its source.
print()
for sid in PARTIES:
    fp = json.load(open(made[sid]["package"]))["identity"]["ca_fingerprint"]
    print(f"  {sid} reads aloud  verifying key  {groups(BOUND[sid])}")
    print(f"  {sid} reads aloud  CA fingerprint {groups(fp.removeprefix('sha256:'))}")
print()

# 3. FETCH AND CHECK, from each side.
for us, them in (("xaa", "xab"), ("xab", "xaa")):
    status, headers, body = get(f"{BASE}/v1/parties/{them}")
    if status != 200:
        chk(f"{us} finds {them}'s pointer", False, f"HTTP {status}")
        continue
    entry = json.loads(body)
    chk(f"{us} finds {them}'s pointer (saltlick-pointer/v1)", entry.get("spec") == "saltlick-pointer/v1",
        entry.get("spec"))
    chk(f"{them}'s pointer verifies under the key {us} read back", verifies(entry, BOUND[them]))
    status, _, pbody = get(entry.get("package_url", ""))
    chk(f"{us} fetches {them}'s package from the pointer's package_url", status == 200, f"HTTP {status}")
    chk(f"its sha256 is the pointer's package_sha256", sha256_of(pbody) == entry.get("package_sha256"),
        f"{sha256_of(pbody)} vs {entry.get('package_sha256')}")
    pkg = json.loads(pbody)
    chk(f"the package is {them}'s and verifies under the key {us} read back",
        pkg.get("sovereign_id") == them and verifies(pkg, BOUND[them]))
    status, _, ca = get(f"{BASE}/v1/parties/{them}/ca")
    chk(f"{them}'s hosted CA has the package's identity.ca_fingerprint",
        status == 200 and ca_matches(ca, pkg["identity"]["ca_fingerprint"]), f"HTTP {status}")
    os.makedirs(f"{WORK}/{us}", exist_ok=True)
    open(f"{WORK}/{us}/theirs.package.json", "wb").write(pbody)
    open(f"{WORK}/{us}/theirs-ca.pem", "wb").write(ca)

# 4. EACH CHECK CAN FAIL. The same checks, on what a wrong or hostile directory
# could serve instead.
pointer = json.loads(get(f"{BASE}/v1/parties/xab")[2])
pbody = get(pointer["package_url"])[2]
pkg = json.loads(pbody)
altered = pbody.replace(b'"accept_hz":50', b'"accept_hz":51')
chk("a package altered by one value fails the pointer's sha256",
    altered != pbody and sha256_of(altered) != pointer["package_sha256"])
other_ca, _ = make_ca("xab federation root CA")
chk("a CA that disagrees with the package's identity.ca_fingerprint is detected",
    not ca_matches(other_ca, pkg["identity"]["ca_fingerprint"]))
forged = {k: v for k, v in pointer.items() if k != "signature"}
forged["signature"] = base64.standard_b64encode(
    load_seed(f"{BUNDLE}/vectors/testkeys/xaa.seed.hex").sign(canonical(forged))).decode()
chk("a pointer for xab signed by any other key fails under the key read back",
    not verifies(forged, BOUND["xab"]))

print(f"\n  {P} passed, {F} failed")
sys.exit(1 if F else 0)
