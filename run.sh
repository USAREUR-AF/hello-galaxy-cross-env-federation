#!/usr/bin/env bash
# The series convention is run.sh; the runner itself is ./run. This is the door
# the other hello-galaxy repos taught people to knock on.
exec "$(dirname "$0")/run" "$@"
