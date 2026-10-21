#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
gpu="${1:-$root/debug/laniusc}"
native="${2:-$root/target/verified-compiler/compiler-direct}"
out="$(mktemp -d "$root/target/verified-compiler/nominal-identity.XXXXXX")"
trap 'rm -rf "$out"' EXIT
ulimit -c 0

# Each empty block contributes two tokens. Two padding functions contribute
# 23 more; padding=1012 therefore puts the declaration names exactly 2048 tokens
# apart. Their legacy base+token type numbers coincide. Two functions keep the
# fixture below the native parser depth limit. Neighbors must behave identically.
# Generate padding here rather than storing 1000 no-op lines.
for spec in '1011 direct' '1012 direct' '1013 direct' '1012 alias'; do
  read -r padding mode <<< "$spec"
  awk -v count="$padding" -v mode="$mode" '
    /^\/\/ NOMINAL_IDENTITY_PADDING$/ {
      blocks = count - 6
      first = int(blocks / 2)
      print "pub fn padding0() -> i32 {"
      for (i = 0; i < first; i++) print "{}"
      print "return 0; }"
      print "fn padding1() -> i32 {"
      for (i = first; i < blocks; i++) print "{}"
      print "return 0; }"
      next
    }
    /^\/\/ NOMINAL_IDENTITY_ALIAS$/ {
      if (mode == "alias") {
        print "type CandidateAlias = Candidate;"
        print "type CandidateChain = CandidateAlias;"
      }
      next
    }
    mode == "alias" && (/^fn / || /let (candidate|selected):/) {
      gsub(/Candidate/, "CandidateChain")
    }
    { print }
  ' "$root/verified_compiler/tests/x86/nominal_type_identity.lani" > "$out/input.lani"

  timeout -k 3s 30s "$gpu" --emit x86_64 -o "$out/gpu.elf" "$out/input.lani"
  timeout -k 3s 30s "$native" "$out/input.lani" > "$out/native.elf"
  chmod +x "$out/native.elf"
  for compiler in gpu native; do
    status=0
    timeout -k 3s 5s "$out/$compiler.elf" || status=$?
    if [[ "$status" -ne 37 ]]; then
      echo "$compiler: $mode, padding $padding returned $status, expected 37" >&2
      exit 1
    fi
  done
done
echo 'Nominal identity survives a struct/enum code collision, adjacent positions, and an alias chain in both compilers'
