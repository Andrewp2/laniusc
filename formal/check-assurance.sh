#!/usr/bin/env bash
set -euo pipefail

profile="${1:-fast}"
case "$profile" in
  fast|kernel-clean) ;;
  *)
    echo "usage: $0 [fast|kernel-clean]" >&2
    exit 2
    ;;
esac

output="$(mktemp)"
trap 'rm -f "$output"' EXIT

if [[ "$profile" == "kernel-clean" ]]; then
  target="Lanius.Relational.AssuranceKernel"
else
  target="Lanius.Relational.AssuranceFast"
fi

lake build "$target" 2>&1 | tee "$output"

if rg -n 'sorryAx|declaration uses .*(sorry|admit)' "$output"; then
  echo "assurance failure: unresolved proof escape" >&2
  exit 1
fi

native_axioms="$(rg '_native\.native_decide\.ax_' "$output" || true)"

if [[ "$profile" == "kernel-clean" ]]; then
  if [[ -n "$native_axioms" ]]; then
    echo "kernel-clean assurance failure: native_decide dependency remains" >&2
    echo "$native_axioms" >&2
    exit 1
  fi
else
  unexpected="$(printf '%s\n' "$native_axioms" |
    rg -v 'verifiedFrontendPack_completely_checked\._native\.native_decide\.ax_1_1' || true)"
  if [[ -n "$unexpected" ]]; then
    echo "fast assurance failure: native_decide dependency is not allowlisted" >&2
    echo "$unexpected" >&2
    exit 1
  fi
fi

echo "$profile assurance profile passed"
