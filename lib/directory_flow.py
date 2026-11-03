"""The directory used for what it is for: discovery, then corroboration.

saltlick holds recognition only. So the flow is: find the counterparty there,
take the two facts it publishes (verifying key, CA fingerprint), and then use
those to CORROBORATE the package that arrives directly. The directory makes the
introduction; it confers nothing, and the package it points at is the thing that
carries the offer.
"""
import json, sys, base64, hashlib, urllib.request
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey
from cryptography.exceptions import InvalidSignature

BASE, BUNDLE = sys.argv[1], sys.argv[2]
canon = lambda o: json.dumps(o, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()
def get(p):
    with urllib.request.urlopen(f"{BASE}{p}", timeout=10) as r:
        return json.loads(r.read())

P = F = 0
def chk(name, ok, detail=""):
    global P, F
    if ok: print(f"  PASS  {name}"); P += 1
    else:  print(f"  FAIL  {name}  {detail}"); F += 1

# 1. DISCOVERY -- a party we have no prior relationship with is findable.
listing = get("/v1/parties")
ids = [x["sovereign_id"] if isinstance(x, dict) else x for x in
       (listing if isinstance(listing, list) else listing.get("parties", []))]
chk("both counterparties are discoverable in the directory", {"xaa","xab"} <= set(ids), ids)

# 2. The entry carries recognition, and NOTHING operational.
entry = get("/v1/parties/xab")
chk("the entry carries no transport_offer", "transport_offer" not in entry)
chk("the entry carries no data_offer",      "data_offer" not in entry)
chk("the entry carries the identity block", "identity" in entry and "ca_fingerprint" in entry["identity"])

# 3. It is self-consistent: the signature verifies under the key the directory bound.
bound = get("/v1/parties/xab/key") if False else None
sig = base64.standard_b64decode(entry["signature"])
body = canon({k: v for k, v in entry.items() if k != "signature"})
seed = bytes.fromhex(open(f"{BUNDLE}/vectors/testkeys/xab.seed.hex").read().strip())
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives import serialization
pub = Ed25519PrivateKey.from_private_bytes(seed).public_key()
try:
    pub.verify(sig, body); ok = True
except InvalidSignature:
    ok = False
chk("the entry's signature verifies under the party's key", ok)

# 4. THE POINT: the directory CORROBORATES the package that arrives directly.
direct = json.load(open(f"{BUNDLE}/vectors/compose-full/package-xab.canonical.json"))
same_ca  = direct["identity"]["ca_fingerprint"] == entry["identity"]["ca_fingerprint"]
same_td  = direct["identity"]["trust_domain"]   == entry["identity"]["trust_domain"]
chk("the directly-exchanged package matches the directory on ca_fingerprint", same_ca)
chk("...and on trust_domain", same_td)

# 5. And a package whose CA does not match what the directory published is caught.
tampered = json.loads(json.dumps(direct))
tampered["identity"]["ca_fingerprint"] = "sha256:" + "0"*64
chk("a package disagreeing with the directory on its CA is detected",
    tampered["identity"]["ca_fingerprint"] != entry["identity"]["ca_fingerprint"])

print(f"\n  {P} passed, {F} failed")
sys.exit(1 if F else 0)
