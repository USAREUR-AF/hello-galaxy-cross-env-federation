# The two sovereigns

`xaa` and `xab`, deliberately not named after countries.

They are the identities the conformance vectors already use, so the scenario in this repository and
the normative fixtures in the bundle refer to the same two parties. That is the point: the packages
exercised here are the packages a counterparty implements against, not look-alikes written for a
test.

Their signing keys live in the bundle at `vectors/testkeys/`, **private material included**. Those
keys are public, they are in a public repository, and they are worthless — they exist so that anyone
can rebuild every signature in the vector set from scratch. Never use them for anything.

The cloud stages (06–12) put a real goatnet behind each name. "Ours" is the goatnet you run the
stages from; its sovereign id is `HG_OUR_SOVEREIGN` (default `xab`). The counterparty is
`HG_THEIR_SOVEREIGN` (default `xaa`). The edge names, wire prefixes and certificate names the
stages check are all derived from those two ids.
