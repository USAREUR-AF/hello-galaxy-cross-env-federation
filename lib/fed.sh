# fed <verb> [args...] — the federation package verbs, from whichever tool runs them.
#
# Federation is moving from `goat` into `goatbuilder`. The six verbs (init, lint,
# compose, diff, verify, apply) take the same flags and give the same exit codes in
# both, and they run the same library, so a stage asserts the same thing either way.
#
#   FED_TOOL=goat         (default) "$GOAT_BIN" federate <verb> ...
#                         the released `goat` CLI, which partners run today
#   FED_TOOL=goatbuilder  "$GOATBUILDER_BIN" federate <verb> ...
#                         the first goatbuilder release that carries the federate verbs
#
# The runner resolves the binary and refuses a goatbuilder without the verbs, so a
# stage never runs an older goatbuilder whose `federate <name>` would take the verb
# for a partner name.
fed() {
  case "${FED_TOOL:-goat}" in
    goatbuilder) "$GOATBUILDER_BIN" federate "$@" ;;
    *)           "$GOAT_BIN" federate "$@" ;;
  esac
}
