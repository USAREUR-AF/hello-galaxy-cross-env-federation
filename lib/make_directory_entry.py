# Build a recognition-only directory entry and re-sign it.
# A directory entry carries NO offers: saltlick returns 422 for transport_offer
# and for data_offer, because reachability and release sets are sovereign
# operational detail that moves directly between the two parties. A conformance
# package carries offers by design -- it exists to exercise composition -- so it
# cannot be published as-is.
import json, sys, base64
from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
bundle, sid, out = sys.argv[1], sys.argv[2], sys.argv[3]
canon = lambda o: json.dumps(o, sort_keys=True, separators=(',', ':'), ensure_ascii=False).encode()
src = json.load(open(f"{bundle}/vectors/compose-full/package-{sid}.canonical.json"))
entry = {k: v for k, v in src.items()
         if k not in ("transport_offer", "data_offer", "cut", "signature")}
seed = bytes.fromhex(open(f"{bundle}/vectors/testkeys/{sid}.seed.hex").read().strip())
entry["signature"] = base64.standard_b64encode(
    Ed25519PrivateKey.from_private_bytes(seed).sign(canon(entry))).decode()
open(out, "wb").write(canon(entry))
print(out)
