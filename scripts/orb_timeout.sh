#!/usr/bin/env bash
# Shared bounded OrbStack invocation for the Linux portability gates.
# Source this file after defining ROOT; orb_run preserves the wrapped command's
# status and returns 124 when the OrbStack client does not answer in time.

ORB_TIMEOUT_SECONDS="${ELISA_UI_ORB_TIMEOUT_SECONDS:-30}"
case "$ORB_TIMEOUT_SECONDS" in
  ''|*[!0-9]*|0)
    echo "core linux: ELISA_UI_ORB_TIMEOUT_SECONDS must be a positive integer" >&2
    return 2
    ;;
esac

orb_run() {
  local child elapsed
  "$@" &
  child=$!
  elapsed=0
  while kill -0 "$child" 2>/dev/null; do
    if (( elapsed >= ORB_TIMEOUT_SECONDS )); then
      echo "core linux: orb command timed out after ${ORB_TIMEOUT_SECONDS}s" >&2
      kill -TERM "$child" 2>/dev/null || true
      sleep 1
      kill -KILL "$child" 2>/dev/null || true
      wait "$child" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  wait "$child"
}
