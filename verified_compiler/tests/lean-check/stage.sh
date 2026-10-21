#!/usr/bin/env bash
# Raw scan status: 0 match, 1 clean, >1 scanner failure. Callers classify explicitly.
scan_log() {
  local log="$1" pattern="$2" status=0
  shift 2
  rg --no-filename "$pattern" "$@" > "$log" || status="$?"
  printf '%s\n' "$status" > "$log.status" || return 2
  return "$status"
}

# Data stdout is never scanned. Proof-body streams stay merged in their Lean log.
checked_stage() {
  local prefix="$1" stdout="$2" mode="$3" status=0
  shift 3
  stdout="${stdout:-$prefix.stdout}"
  local stderr="$prefix.stderr" diagnostics=("$stdout" "$prefix.stderr")
  printf '%q\n' "$@" > "$prefix.arguments" || return
  case "$mode" in
    data|diagnostics)
      [[ "$mode" != data ]] || diagnostics=("$stderr")
      /usr/bin/time -o "$prefix.time" -f 'stage wall=%e user=%U system=%S peakRSSKiB=%M status=%x' \
        "$@" > "$stdout" 2> "$stderr" || status="$?";;
    merged)
      : > "$stderr" || return
      diagnostics=("$stdout")
      /usr/bin/time -o "$prefix.time" -f 'stage wall=%e user=%U system=%S peakRSSKiB=%M status=%x' \
        "$@" > "$stdout" 2>&1 || status="$?";;
    *) echo "invalid stage policy: $mode" >&2; return 2;;
  esac
  printf '%s\n' "$status" > "$prefix.status" || return
  if ((status != 0)); then cat "${diagnostics[@]}" >&2; return "$status"; fi
  if scan_log "$prefix.diagnostics" 'error:|sorryAx|Error:|backtrace:' "${diagnostics[@]}"; then
    cat "$prefix.diagnostics" >&2
    return 1
  else status="$?"; [[ "$status" == 1 ]] || return "$status"; fi
}
