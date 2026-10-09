#!/usr/bin/env bash
set -uo pipefail
limit="${1:?worker seconds required}"; shift
# Reserve measured descendant-cleanup headroom within the 120s whole command.
[[ "$limit" =~ ^[0-9]+$ && "$limit" -le 117 ]] || exit 2
start=$SECONDS
setsid "$@" & worker=$!
members() { ps -eo pid=,sid=,stat= | awk -v s="$worker" '$2 == s && $3 !~ /^Z/ {print $1}'; }
cleanup() {
  trap - EXIT INT TERM
  local pids
  pids="$(members)"
  [[ -z "$pids" ]] || kill -TERM $pids 2>/dev/null || true
  sleep 1
  pids="$(members)"
  [[ -z "$pids" ]] || kill -KILL $pids 2>/dev/null || true
  wait "$worker" 2>/dev/null || true
  sleep 0.1
  pids="$(members)"
  printf 'worker=%s elapsed=%ss remaining-live=[%s]\n' "$worker" "$((SECONDS-start))" "$pids" >&2
  [[ -z "$pids" ]] || exit 125
}
trap cleanup EXIT
trap 'exit 124' TERM INT
while kill -0 "$worker" 2>/dev/null && ((SECONDS-start < limit)); do sleep 0.1; done
if kill -0 "$worker" 2>/dev/null; then exit 124; fi
wait "$worker"; exit $?
