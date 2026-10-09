#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C PATH=/usr/bin:/bin
unset LEAN_PATH LEAN_SRC_PATH LEAN_SYSROOT LEAN_OPTS
out="$1"; config="$2"; root="$3"; module="$4"
cd "$root"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$here/stage.sh"
lean="$(< "$config/lean-bin.txt")"; toolchain="$(< "$config/toolchain.txt")"
path="$out/modules:$toolchain/lib/lean"
IFS=$'\t' read -r name source_root source < <(awk -F '\t' -v m="$module" '$1 == m' "$config/jobs.tsv")
[[ "$name" == "$module" ]] || exit 2
base="$out/modules/${module//./\/}"; mkdir -p "$(dirname "$base")"
printf '%s\n' -R "$source_root" -o "$base.olean" "$source" > "$out/logs/$module.arguments"
checked_stage "$out/logs/$module.deps" "$out/logs/$module.dependencies" data \
  env LEAN_PATH="$path" "$lean" --deps -R "$source_root" "$source"
while IFS= read -r dependency; do
  case "$dependency" in
    "$out/modules/"*)
      [[ -f "$dependency" ]] || exit 2
      relative="${dependency#"$out/modules/"}"
      if [[ -L "$dependency" ]]; then
        grep -Fxq "$(printf '%s\t%s' "$relative" "$(readlink "$dependency")")" "$config/cache-artifacts.tsv" || exit 2
      else
        imported="${relative%%.olean*}"; imported="${imported%%.ilean*}"; imported="${imported%%.ir*}"; imported="${imported//\//.}"
        [[ -f "$out/completed/$imported" ]] || { echo "incomplete fresh dependency $imported" >&2; exit 2; }
      fi;;
    "$toolchain/lib/lean/"*) [[ -f "$dependency" ]] && grep -Fq "  $dependency" "$config/toolchain.sha256" || exit 2;;
    *) echo "undeclared or stale dependency $dependency" >&2; exit 2;;
  esac
done < "$out/logs/$module.dependencies"
checked_stage "$out/logs/$module" "$out/logs/$module.log" merged \
  env LEAN_PATH="$path" "$lean" -R "$source_root" -o "$base.olean" "$source"
[[ -f "$base.olean" && ! -L "$base.olean" ]] || exit 2
awk -f "$here/axioms.awk" "$out/logs/$module.log" > "$out/logs/$module.axioms"
while IFS=$'\t' read -r owner theorem; do
  [[ "$owner" != "$module" ]] || grep -Fq "'$theorem' depends on axioms: [" "$out/logs/$module.log" || \
    grep -Fxq "'$theorem' does not depend on any axioms" "$out/logs/$module.log"
done < "$config/required-axioms.tsv"
while IFS=$'\t' read -r owner marker; do
  [[ "$owner" != "$module" ]] || grep -Fxq "$marker" "$out/logs/$module.log"
done < "$config/fixture-markers.tsv"
touch "$out/completed/$module"
