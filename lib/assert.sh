# Assertions and the tally. Sourced by every stage.
#
# The rule this file exists to enforce: a check that cannot fail is not a check
#. Every assertion here takes the observed value, not a boolean the
# caller computed, so the failure message can print what was actually seen.

PASS=0; FAIL=0; SKIP=0
_g="\033[32m"; _r="\033[31m"; _y="\033[33m"; _d="\033[2m"; _0="\033[0m"

ok()   { printf "  ${_g}pass${_0}  %s\n" "$1"; PASS=$((PASS+1)); }
no()   { printf "  ${_r}FAIL${_0}  %s\n" "$1"; [ -n "${2:-}" ] && printf "        ${_d}%s${_0}\n" "$2"; FAIL=$((FAIL+1)); }
skip() { printf "  ${_y}skip${_0}  %s\n" "$1"; [ -n "${2:-}" ] && printf "        ${_d}%s${_0}\n" "$2"; SKIP=$((SKIP+1)); }
note() { printf "        ${_d}%s${_0}\n" "$1"; }

# assert_eq <what> <expected> <actual>
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"
  else no "$1" "expected: $2
        actual:   $3"; fi
}

# assert_exit <what> <expected-code> <command...>
assert_exit() {
  local what="$1" want="$2"; shift 2
  "$@" >/tmp/.hg_out 2>&1; local got=$?
  if [ "$got" = "$want" ]; then ok "$what (exit $got)"
  else no "$what" "expected exit $want, got $got
        $(head -3 /tmp/.hg_out)"; fi
}

# assert_contains <what> <needle> <haystack>
assert_contains() {
  case "$3" in *"$2"*) ok "$1" ;;
    *) no "$1" "expected to contain: $2
        in: $(printf '%s' "$3" | head -c 300)" ;;
  esac
}

tally() {
  echo
  printf "  %d passed, %d failed" "$PASS" "$FAIL"
  [ "$SKIP" -gt 0 ] && printf ", %d skipped" "$SKIP"
  echo; echo
  [ "$FAIL" -eq 0 ]
}
