#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C PATH=/usr/bin:/bin
unset LEAN_PATH LEAN_SRC_PATH LEAN_SYSROOT LEAN_OPTS
out="$1"; config="$2"; root="$3"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/stage.sh"
cd "$root"
mkdir -p "$out/modules" "$out/logs" "$out/completed"
authenticate() {
  /usr/bin/time -a -o "$out/authentication.time" -f "input auth $1 wall=%e status=%x" \
    bash -ec 'sha256sum -c "$1/snapshot.sha256" > "$2/snapshot.$3.log"; sha256sum -c "$1/inputs.sha256" > "$2/inputs.$3.log"' -- "$config" "$out" "$1"
}
authenticate before
mapfile -t sources < "$config/proof-sources.txt"
[[ ${#sources[@]} -gt 0 ]] || exit 2
awk -F '\t' 'NF != 3 || seen[$1]++ {exit 1}' "$config/jobs.tsv"
if scan_log "$out/source-trust-scan.log" '\bsorry\b|^[[:space:]]*axiom\b|\bnative_decide\b|Lean\.ofReduceBool|set_option[[:space:]]+(maxHeartbeats|maxRecDepth|maxRecursionDepth)' \
    "${sources[@]}"; then exit 1
else status=$?; [[ "$status" == 1 ]] || exit "$status"; fi
while IFS=$'\t' read -r relative artifact; do
  [[ "$relative" != /* && "$relative" != *..* && -f "$artifact" ]] || exit 2
  grep -Fq "  $artifact" "$config/inputs.sha256"
  mkdir -p "$(dirname "$out/modules/$relative")"; ln -s "$artifact" "$out/modules/$relative"
done < "$config/cache-artifacts.tsv"
while IFS=$'\t' read -r module source_root source; do
  base="$out/modules/${module//./\/}"
  for artifact in "$base".olean* "$base".ilean* "$base".ir*; do [[ ! -e "$artifact" && ! -L "$artifact" ]] || exit 2; done
done < "$config/jobs.tsv"
ruby -E UTF-8 "$here/schedule.rb" "$out" "$config" "$root" "$here" > "$out/scheduler.log" 2>&1
artifacts=()
while IFS=$'\t' read -r module source_root source; do
  cat "$out/logs/$module.arguments" >> "$out/arguments.txt"
  cat "$out/logs/$module.time" >> "$out/timings.txt"
  base="$out/modules/${module//./\/}"
  [[ -f "$out/completed/$module" && -f "$base.olean" && ! -L "$base.olean" ]] || exit 2
  for artifact in "$base".olean* "$base".ilean* "$base".ir*; do [[ ! -f "$artifact" ]] || artifacts+=("$artifact"); done
done < "$config/jobs.tsv"
authenticate after
sha256sum "$out/arguments.txt" "${artifacts[@]}" > "$out/outputs.sha256"
sha256sum -c "$out/outputs.sha256" > "$out/outputs-recheck.log"
echo 'Fresh specialized catalog bodies checked with authenticated current shared foundations; no fresh-all or ACCEPT claim.'
