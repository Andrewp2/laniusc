#!/usr/bin/env bash
set -euo pipefail

formal_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd "$formal_dir/.." && pwd)"
grammar="$repo_dir/grammar/lanius.bnf"
params="$repo_dir/crates/laniusc-compiler/src/type_checker/params.rs"

fail() {
  printf 'formal source audit failed: %s\n' "$1" >&2
  exit 1
}

grammar_hash="$(sha256sum "$grammar" | awk '{print $1}')"
[[ "$grammar_hash" == \
  d9cc4b72b3dc8373ba5ea6d12f4bf0cd8baf5956b03010d76ebff1a1a6e06976 ]] ||
  fail "grammar/lanius.bnf changed; reconcile the concrete syntax and update CurrentFeatureAudit"

read -r production_count tagged_count nonterminal_count < <(
  awk '
    /^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*(\[[^]]+\][[:space:]]*)?->[[:space:]]*/ {
      productions++
      lhs[$1] = 1
      if ($0 ~ /\[[^]]+\][[:space:]]*->/) tagged++
    }
    END {
      for (name in lhs) nonterminals++
      print productions, tagged, nonterminals
    }
  ' "$grammar"
)
[[ "$production_count" == 290 ]] || fail "expected 290 grammar productions, found $production_count"
[[ "$tagged_count" == 276 ]] || fail "expected 276 tagged grammar productions, found $tagged_count"
[[ "$nonterminal_count" == 136 ]] || fail "expected 136 grammar nonterminals, found $nonterminal_count"

language_table_hash="$({
  awk '
    /LANGUAGE_SYMBOL_COUNT/ { capture = 1 }
    capture { print }
    /LANGUAGE_SYMBOL_LENS/ { lengths = 1 }
    lengths && /];/ { exit }
  ' "$params"
} | sha256sum | awk '{print $1}')"
[[ "$language_table_hash" == \
  13197728404607bab7536a85f5f63bc4b6545f0378c46f3f4daec3e836290556 ]] ||
  fail "the compiler language-symbol table changed; reconcile CurrentFeatureAudit"

extern_snapshot="$(mktemp)"
trap 'rm -f "$extern_snapshot"' EXIT
find "$repo_dir/stdlib" -type f -name '*.lani' -print0 |
  sort -z |
  xargs -0 perl -0777 -ne '
    while (/pub\s+extern\b[^;]*;/sg) {
      $declaration = $&;
      $declaration =~ s/\s+/ /g;
      print "$declaration\n";
    }
  ' > "$extern_snapshot"

extern_count="$(wc -l < "$extern_snapshot")"
extern_hash="$(sha256sum "$extern_snapshot" | awk '{print $1}')"
[[ "$extern_count" == 65 ]] ||
  fail "expected 65 stdlib extern declarations, found $extern_count"
[[ "$extern_hash" == \
  d78c1b2e691a66334ffe79d8df03284886b272ba6f4376b1a14e254eed71cc77 ]] ||
  fail "the stdlib extern catalog changed; reconcile RuntimeBindings"

printf 'formal source audit passed: 290 productions, 68 compiler symbols, 65 stdlib externs\n'
