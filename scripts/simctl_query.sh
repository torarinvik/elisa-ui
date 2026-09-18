#!/usr/bin/env bash
# Shared bounded CoreSimulator discovery query.
#
# CoreSimulator can leave `simctl` blocked while its service database is
# unavailable. Discovery callers should treat a timeout as an unavailable
# optional device environment, not as a framework test failure.

simctl_query() {
  local query_timeout="${ELISA_UI_SIMCTL_QUERY_TIMEOUT:-10}"
  local query_file query_pid query_status
  query_file="$(mktemp "${TMPDIR:-/tmp}/elisa-ui-simctl.XXXXXX")"
  xcrun simctl "$@" >"$query_file" 2>/dev/null &
  query_pid=$!
  for _ in $(seq "$query_timeout"); do
    if ! kill -0 "$query_pid" 2>/dev/null; then
      if wait "$query_pid"; then
        cat "$query_file"
        rm -f "$query_file"
        return 0
      else
        query_status=$?
        cat "$query_file"
        rm -f "$query_file"
        return "$query_status"
      fi
    fi
    sleep 1
  done
  kill -TERM "$query_pid" 2>/dev/null || true
  wait "$query_pid" 2>/dev/null || true
  rm -f "$query_file"
  echo "uikit simulator: simctl $* timed out after ${query_timeout}s" >&2
  return 124
}
