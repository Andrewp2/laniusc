#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tools/shader_loop_audit.sh [--root shaders] [--high-risk-only] [--summary|--summary-only] [--fail-on-data-dependent] [--fail-on-large-fixed-bound] [--fail-on-paper-pass-blocker] [--fail-on-codegen-large-fixed-bound] [--fail-on-x86-codegen-large-fixed-bound] [--fail-on-wasm-codegen-large-fixed-bound] [--fail-on-parser-large-fixed-bound] [--fail-on-type-checker-large-fixed-bound] [--fail-on-x86-codegen-review-required] [--fail-on-wasm-codegen-review-required] [--fail-on-parser-review-required] [--fail-on-type-checker-review-required] [--fail-on-parser-source-sized-symbolic-cap] [--fail-on-type-checker-source-sized-symbolic-cap] [--fail-on-suspicious-loop-attr] [--fail-on-raw-for-review-required] [--fail-on-source-sized-symbolic-cap]

Scans Slang shader sources for loop headers and classifies each loop by the
shape of its bound. This is a no-run audit for paper/Pareas alignment: broad
compiler passes should move toward prefix scans, sort/scatter, and record
relations rather than data-dependent shader loops.

Options:
  --high-risk-only          only emit detail rows whose advisory risk is high
  --summary                 append summary rows after detail rows
  --summary-only            emit only summary rows
  --fail-on-data-dependent  exit non-zero if review-required loops are found
  --fail-on-large-fixed-bound
                            exit non-zero if fixed-cap loops above the large
                            literal threshold are found
  --fail-on-paper-pass-blocker
                            exit non-zero if loop reasons map to non-local
                            paper/Pareas rewrite categories
  --fail-on-codegen-large-fixed-bound
                            exit non-zero if any codegen shader has fixed-cap
                            loops above the large literal threshold
  --fail-on-x86-codegen-large-fixed-bound
                            exit non-zero if x86 codegen has fixed-cap loops
                            above the large literal threshold
  --fail-on-wasm-codegen-large-fixed-bound
                            exit non-zero if WASM codegen has fixed-cap loops
                            above the large literal threshold
  --fail-on-parser-large-fixed-bound
                            exit non-zero if parser shaders have fixed-cap
                            loops above the large literal threshold
  --fail-on-type-checker-large-fixed-bound
                            exit non-zero if type-checker shaders have
                            fixed-cap loops above the large literal threshold
  --fail-on-x86-codegen-review-required
                            exit non-zero if x86 codegen has any data-dependent,
                            while, or unknown-bound loops
  --fail-on-wasm-codegen-review-required
                            exit non-zero if WASM codegen has any data-dependent,
                            while, or unknown-bound loops
  --fail-on-parser-review-required
                            exit non-zero if parser shaders have any
                            data-dependent, while, or unknown-bound loops
  --fail-on-type-checker-review-required
                            exit non-zero if type-checker shaders have any
                            data-dependent, while, or unknown-bound loops
  --fail-on-parser-source-sized-symbolic-cap
                            exit non-zero if parser shaders use symbolic caps
                            that look source, tree, or record sized
  --fail-on-type-checker-source-sized-symbolic-cap
                            exit non-zero if type-checker shaders use symbolic
                            caps that look source, tree, or record sized
  --fail-on-suspicious-loop-attr
                            exit non-zero if [loop] or [unroll] annotations are
                            attached to unbounded, unknown, while, or large
                            fixed-cap loops
  --fail-on-raw-for-review-required
                            exit non-zero if raw for-loops have data-dependent
                            or unknown bounds
  --fail-on-source-sized-symbolic-cap
                            exit non-zero if fixed symbolic caps look source,
                            tree, record, or program-structure sized

Default detail output columns:
  classification<TAB>risk<TAB>path<TAB>line<TAB>function-context<TAB>reason<TAB>loop-header<TAB>loop-flags

Summary output columns:
  summary<TAB>scope<TAB>group<TAB>name<TAB>count

Summary scope is "scanned" for the full audit. When a detail-row filter is
active, an additional "emitted" scope shows the filtered output counts.
Reason summary rows use the same stable reason strings as detail rows so
summary-only audits still show which pass-contract class needs work.
Component summary rows group counts by shader subsystem so no-run tracking can
separate parser, type-checker, lexer, x86 codegen, and legacy WASM codegen debt.
Component-risk summary rows pair each subsystem with low/medium/high audit risk
so summary-only output can route the highest-risk debt without opening detail rows.
Paper-pass summary rows map each loop reason to the paper/Pareas rewrite family
that should replace or justify it: prefix scan/scatter, sort/join/scatter,
segmented scan, or bounded local helper work.
Component-paper-pass summary rows pair each shader subsystem with its required
rewrite family so summary-only output can be assigned directly.
Component-paper-pass-blocker summary rows are the same pairings after excluding
bounded-local review categories, so they route only non-local paper/Pareas
rewrite blockers.
Component-paper-pass-local-review summary rows are the bounded-local review
pairings only, so summary-only output can route helper-loop justification debt
without treating it as a paper/Pareas rewrite blocker.
Component-rewrite-route-blocker summary rows are blocker-only assignment rows
that pair each shader subsystem with the concrete primitive route, for example
component:publish-records-map-prefix-sum-scatter.
Component-rewrite-route-local-review summary rows are the bounded-local
assignment rows for helper-loop justification routes.
Component-source-sized-symbolic-cap summary rows route symbolic caps whose names
look source, tree, record, or program-structure sized, so scale-claim blockers
can name the owning subsystem instead of hiding under generic local review.
Source-sized-symbolic-cap-name rows report the exact symbolic cap names.
Source-sized-symbolic-cap-route rows and
component-source-sized-symbolic-cap-route rows map those caps to the primitive
route that should replace or justify them: source partition/prefix/scatter,
depth-parent sort/join/scatter, record sort/reduce/scatter, or segmented
regalloc scan/scatter.
Component-source-sized-symbolic-cap-path-route rows include the component,
symbolic cap, shader path, and primitive route for each source-sized symbolic
cap row, so summary-only artifacts can route pass-shape blockers without opening
detail rows.
Pass-shape summary rows provide a mutually exclusive no-run evidence class for
each loop: Pareas primitive-shaped bounded loops, source/non-local rewrite
blockers, source-sized symbolic-cap fallbacks, bounded legacy fallbacks, and
bounded helper review. Component-pass-shape rows add the owning subsystem to
that class so summary-only output can distinguish acceptable
scan/sort/reduce/scatter loops from source-scale loops or bounded legacy
fallback debt.
Audit-evidence-role summary rows collapse pass-shape rows into no-run evidence
roles: proof, blocker, and local-review. Proof means primitive-shaped pass
structure only; it is not correctness, runtime, scaling, VRAM, throughput, or
Pareas-equivalence evidence. Blocker rows identify loop shapes that prevent a
pass-contract claim. Local-review rows identify bounded helpers that need a
behavior-facing invariant or rewrite before they can support a readiness claim.
Audit-evidence, component-audit-evidence-role, and component-audit-evidence
rows keep the same split with the underlying pass-shape reason, so summary-only
artifacts can separate proof, blocker, and local-review evidence without
opening detail rows.
Claim-blocker summary rows collapse blocker plus local-review audit evidence
into performance/scaling and Pareas-parity claim blockers. They are no-run
contract rows for saved artifacts that might otherwise report timing, VRAM, or
Pareas provenance while source-sized or unproved bounded helper loops remain.
Rewrite-route and reason-rewrite-route summary rows turn paper-pass classes
into concrete primitive routes, so source-sized loops can be routed directly to
record publication, prefix-sum, and scatter work instead of being treated as
generic loop debt.
Component-reason-rewrite-route summary rows add the owning subsystem to that
route, so summary-only audits can assign source-sized loop rewrites without
opening detail rows.
Evidence-policy summary rows are stable one-count markers that state how to
use the audit output: pass evidence must be behavior-facing, rewrite routes are
not source-grep evidence, this no-run audit is not performance evidence, and
paper/Pareas route alignment is not a Pareas comparison claim. They also state
that Rust tests inspecting product source are not pass evidence, and that a
zero paper-pass blocker queue is not pass-contract proof while blocker or
local-review audit-evidence rows remain.

Classifications:
  fixed-bound        literal/named fixed-size bound, including local scan loops
  fixed-bound-guard  fixed cap with an additional data/subtree exit condition
  data-dependent     bound appears to depend on source/program size or records
  while-loop         while loop; inspect manually
  unknown-bound      for loop whose bound did not match the simple classifier

Risk is advisory. High-risk rows are likely pass-contract blockers until they
are rewritten as scan/scatter/record passes or explicitly justified. Low-risk
fixed loops include tiny literal caps and obvious workgroup-local scan/reduce
loops. Fixed literal caps above 256 iterations are high-risk large in-shader
loops unless they are reworked or justified. Detail rows append flags such as
loop-attribute, unroll-attribute, raw-for, explicit-fixed-literal-cap-16, and
bounded-explicit-literal-candidate so bounded pass-style candidates can be
distinguished from unbounded or opaque loops. Fixed symbolic caps whose names
look source, dispatch, tree, record, or program-structure sized also get a
source-sized-symbolic-cap-candidate flag and review count; use the matching
fail gate when a lane wants to block new long symbolic caps before they become
paper/Pareas pass debt. These regex classifications are audit triage, not
correctness proof. For codegen, the Pareas-aligned shape is node-local record
mapping, prefix-summed instruction locations, depth/layer maps, scatters, and
segmented scan/scatter register layout.
EOF
}

root="shaders"
fail_on_data_dependent=false
fail_on_large_fixed_bound=false
fail_on_paper_pass_blocker=false
fail_on_codegen_large_fixed_bound=false
fail_on_x86_codegen_large_fixed_bound=false
fail_on_wasm_codegen_large_fixed_bound=false
fail_on_parser_large_fixed_bound=false
fail_on_type_checker_large_fixed_bound=false
fail_on_x86_codegen_review_required=false
fail_on_wasm_codegen_review_required=false
fail_on_parser_review_required=false
fail_on_type_checker_review_required=false
fail_on_parser_source_sized_symbolic_cap=false
fail_on_type_checker_source_sized_symbolic_cap=false
fail_on_suspicious_loop_attr=false
fail_on_raw_for_review_required=false
fail_on_source_sized_symbolic_cap=false
high_risk_only=false
show_summary=false
summary_only=false
large_fixed_bound_threshold=256

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root)
      root="${2:-}"
      if [[ -z "$root" ]]; then
        printf 'shader_loop_audit: --root requires a path\n' >&2
        exit 2
      fi
      shift 2
      ;;
    --fail-on-data-dependent)
      fail_on_data_dependent=true
      shift
      ;;
    --fail-on-large-fixed-bound)
      fail_on_large_fixed_bound=true
      shift
      ;;
    --fail-on-paper-pass-blocker)
      fail_on_paper_pass_blocker=true
      shift
      ;;
    --fail-on-codegen-large-fixed-bound)
      fail_on_codegen_large_fixed_bound=true
      shift
      ;;
    --fail-on-x86-codegen-large-fixed-bound)
      fail_on_x86_codegen_large_fixed_bound=true
      shift
      ;;
    --fail-on-wasm-codegen-large-fixed-bound)
      fail_on_wasm_codegen_large_fixed_bound=true
      shift
      ;;
    --fail-on-parser-large-fixed-bound)
      fail_on_parser_large_fixed_bound=true
      shift
      ;;
    --fail-on-type-checker-large-fixed-bound)
      fail_on_type_checker_large_fixed_bound=true
      shift
      ;;
    --fail-on-x86-codegen-review-required)
      fail_on_x86_codegen_review_required=true
      shift
      ;;
    --fail-on-wasm-codegen-review-required)
      fail_on_wasm_codegen_review_required=true
      shift
      ;;
    --fail-on-parser-review-required)
      fail_on_parser_review_required=true
      shift
      ;;
    --fail-on-type-checker-review-required)
      fail_on_type_checker_review_required=true
      shift
      ;;
    --fail-on-parser-source-sized-symbolic-cap)
      fail_on_parser_source_sized_symbolic_cap=true
      shift
      ;;
    --fail-on-type-checker-source-sized-symbolic-cap)
      fail_on_type_checker_source_sized_symbolic_cap=true
      shift
      ;;
    --fail-on-suspicious-loop-attr)
      fail_on_suspicious_loop_attr=true
      shift
      ;;
    --fail-on-raw-for-review-required)
      fail_on_raw_for_review_required=true
      shift
      ;;
    --fail-on-source-sized-symbolic-cap)
      fail_on_source_sized_symbolic_cap=true
      shift
      ;;
    --high-risk-only)
      high_risk_only=true
      shift
      ;;
    --summary)
      show_summary=true
      shift
      ;;
    --summary-only)
      show_summary=true
      summary_only=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'shader_loop_audit: unknown argument %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ! -d "$root" ]]; then
  printf 'shader_loop_audit: root does not exist: %s\n' "$root" >&2
  exit 2
fi

scan_loop_headers() {
  find "$root" -type f -name '*.slang' -print0 \
    | sort -z \
    | while IFS= read -r -d '' path; do
        awk -v path="$path" '
          function strip_comments(s) {
            sub(/\/\/.*/, "", s)
            return s
          }
          function trim(s) {
            sub(/^[[:space:]]+/, "", s)
            sub(/[[:space:]]+$/, "", s)
            return s
          }
          function squash(s) {
            gsub(/[[:space:]]+/, " ", s)
            return trim(s)
          }
          function paren_delta(s,    i, c, d) {
            d = 0
            for (i = 1; i <= length(s); i += 1) {
              c = substr(s, i, 1)
              if (c == "(") {
                d += 1
              } else if (c == ")") {
                d -= 1
              }
            }
            return d
          }
          function function_context(line_no,    i, s) {
            for (i = line_no - 1; i >= 1 && i >= line_no - 120; i -= 1) {
              s = squashed[i]
              if (s == "" || s ~ /;$/ || s ~ /^\/\//) {
                continue
              }
              if (s ~ /^(if|for|while|switch|return|else|case|do)([[:space:]]|\()/) {
                continue
              }
              if (s ~ /^([A-Za-z_][A-Za-z0-9_]*[[:space:]]+)*(void|bool|uint|int|float|float[234]?|uint[234]?|int[234]?|[A-Za-z_][A-Za-z0-9_]*)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(/) {
                sub(/[[:space:]]*\{[[:space:]]*$/, "", s)
                return s
              }
            }
            return "<unknown>"
          }
          function loop_attr_name(has_loop_attr, has_unroll_attr) {
            if (has_loop_attr && has_unroll_attr) {
              return "loop+unroll-attr"
            }
            if (has_loop_attr) {
              return "loop-attr"
            }
            if (has_unroll_attr) {
              return "unroll-attr"
            }
            return "raw"
          }
          function emit_loop(header, line_no, loop_attr,    attr) {
            header = squash(header)
            gsub(/\t/, " ", header)
            context = function_context(line_no)
            gsub(/\t/, " ", context)
            attr = loop_attr == "" ? "raw" : loop_attr
            printf "%s\t%s\t%s\t%s\t%s\n", path, line_no, context, attr, header
          }
          {
            raw[NR] = $0
            cleaned = strip_comments($0)
            has_attr = cleaned ~ /\[loop\]/
            has_unroll_attr = cleaned ~ /\[unroll\]/
            if (has_attr || has_unroll_attr) {
              pending_loop_attr = loop_attr_name(has_attr, has_unroll_attr)
              gsub(/\[loop\]/, "", cleaned)
              gsub(/\[unroll\]/, "", cleaned)
            }
            squashed[NR] = squash(cleaned)
            if (collecting) {
              header = header " " cleaned
              balance += paren_delta(cleaned)
              if (balance <= 0) {
                emit_loop(header, start_line, current_loop_attr)
                collecting = 0
                header = ""
                start_line = 0
                balance = 0
                current_loop_attr = "raw"
              }
              next
            }
            if (cleaned ~ /(^|[^A-Za-z0-9_])(for|while)[[:space:]]*\(/) {
              collecting = 1
              header = cleaned
              start_line = NR
              current_loop_attr = pending_loop_attr
              pending_loop_attr = "raw"
              balance = paren_delta(cleaned)
              if (balance <= 0) {
                emit_loop(header, start_line, current_loop_attr)
                collecting = 0
                header = ""
                start_line = 0
                balance = 0
                current_loop_attr = "raw"
              }
            } else if (squashed[NR] != "" && !has_attr && !has_unroll_attr) {
              pending_loop_attr = "raw"
            }
          }
          END {
            if (collecting) {
              emit_loop(header, start_line, current_loop_attr)
            }
          }
        ' "$path"
      done
}

has_data_dependent_bound() {
  local header="$1"
  local dynamic_guard_re='&&[[:space:]]*!?[A-Za-z_][A-Za-z0-9_]*(\([^)]*\))?[[:space:]]*([!<>=]=?|[<>])'
  [[ "$header" =~ (active_token_count|active_[a-z0-9_]*count|n_active|n_[a-z0-9_]*(tokens|nodes|records|rows|items|decls|fns|types|modules|blocks|bytes|chars|fields|methods|variants|edges|relations|ranges|segments|params|calls|imports|libraries|files)|num_[a-z0-9_]*(tokens|nodes|records|rows|items|decls|fns|types|modules|blocks|bytes|chars|fields|methods|variants|edges|relations|ranges|segments|params|calls|imports|libraries|files)|total_[a-z0-9_]*(tokens|nodes|records|rows|items|decls|fns|types|modules|blocks|bytes|chars|fields|methods|variants|edges|relations|ranges|segments|params|calls|imports|libraries|files)|[a-z0-9_]*(token|tokens|node|nodes|record|records|row|rows|item|items|decl|decls|fn|fns|function|functions|type|types|module|modules|block|blocks|byte|bytes|char|chars|field|fields|method|methods|variant|variants|edge|edges|relation|relations|range|ranges|segment|segments|param|params|call|calls|import|imports|library|libraries|file|files|source|hir|ast|symbol|symbols|reloc|relocs)[a-z0-9_]*_(count|len|size|limit|end|capacity)|token_count|source_len|byte_len|n_blocks|bucket_count|capacity|record_count|node_count|row_count|emit_len|rhs_len|max_steps|max_[a-z0-9_]*steps|actual_args|arg_count|fn_count|extern_count|probe_limit|subtree|parent|child|sibling|ancestor|descendant|valid_node|fixed_stack_empty) ]] ||
    has_dispatch_sized_alias "$header" ||
    [[ "$header" =~ [\<\>]=?[[:space:]]*([[:alnum:]_]+\.)?(lo|hi|n|begin|end|end_exclusive|start|limit|count|len|size|row|node|child|parent|lane_count|bucket_count|cap|params|actual_args|arg_count|open_i|close_i|semi|end_i|fn_i|fn_end|main_end|active_count|rel_end|tIdx|scl|epl|segment_i)($|[[:space:]\;&\),]) ]] ||
    [[ "$header" =~ $dynamic_guard_re ]] ||
    [[ "$header" =~ [\<\>]=?[[:space:]]*gParams\.[A-Za-z0-9_]+ ]]
}

has_dispatch_sized_alias() {
  local header="$1"
  [[ "$header" =~ (n|num|total)_[a-z0-9_]*(dispatch|dispatches|invocation|invocations|work_item|work_items|workitem|workitems)[a-z0-9_]* ]] ||
    [[ "$header" =~ [a-z0-9_]*(dispatch|dispatches|invocation|invocations|work_item|work_items|workitem|workitems)[a-z0-9_]*_(count|len|size|limit|end|capacity) ]]
}

has_fixed_bound() {
  local header="$1"
  [[ "$header" =~ [\<\>]=?[[:space:]]*[0-9]+u?($|[[:space:]\;&\),]) ]] ||
    [[ "$header" =~ [\<\>]=?[[:space:]]*(uint\()?([A-Z][A-Z0-9_]*|[A-Z0-9_]*MAX[A-Z0-9_]*|[A-Z0-9_]*LIMIT[A-Z0-9_]*)\)?($|[[:space:]\;&\),]) ]] ||
    [[ "$header" =~ (offs|step|stride)[[:space:]]*=[^\;]*(GSIZE|WG_SIZE|SCAN_SLOTS|REG_COUNT|CHUNK_COUNT) ]] ||
    [[ "$header" =~ (offs|step|stride)[[:space:]]*(<<=|>>=) ]]
}

fixed_cap_value() {
  local header="$1"
  local induction_var

  induction_var="$(for_induction_var "$header")"
  if [[ -z "$induction_var" ]]; then
    printf '\n'
    return
  fi

  if [[ "$header" =~ (^|[^A-Za-z0-9_])${induction_var}[[:space:]]*[\<\>]=?[[:space:]]*([0-9]+)u?($|[[:space:]\;&\),]) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
  elif [[ "$header" =~ (^|[^A-Za-z0-9_])([0-9]+)u?[[:space:]]*[\<\>]=?[[:space:]]*${induction_var}($|[^A-Za-z0-9_]) ]]; then
    printf '%s\n' "${BASH_REMATCH[2]}"
  else
    printf '\n'
  fi
}

for_induction_var() {
  local header="$1"

  if [[ "$header" =~ (^|[^A-Za-z0-9_])for[[:space:]]*\([[:space:]]*([A-Za-z_][A-Za-z0-9_]*[[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*= ]]; then
    printf '%s\n' "${BASH_REMATCH[3]}"
  else
    printf '\n'
  fi
}

fixed_symbolic_cap_name() {
  local header="$1"
  local induction_var

  induction_var="$(for_induction_var "$header")"
  if [[ -z "$induction_var" ]]; then
    printf '\n'
    return
  fi

  if [[ "$header" =~ (^|[^A-Za-z0-9_])${induction_var}[[:space:]]*[\<\>]=?[[:space:]]*(uint\()?([A-Z][A-Z0-9_]*|[A-Z0-9_]*MAX[A-Z0-9_]*|[A-Z0-9_]*LIMIT[A-Z0-9_]*|[A-Z0-9_]*CAPACITY[A-Z0-9_]*)\)?($|[[:space:]\;&\),]) ]]; then
    printf '%s\n' "${BASH_REMATCH[3]}"
  elif [[ "$header" =~ (^|[^A-Za-z0-9_])(uint\()?([A-Z][A-Z0-9_]*|[A-Z0-9_]*MAX[A-Z0-9_]*|[A-Z0-9_]*LIMIT[A-Z0-9_]*|[A-Z0-9_]*CAPACITY[A-Z0-9_]*)\)?[[:space:]]*[\<\>]=?[[:space:]]*${induction_var}($|[^A-Za-z0-9_]) ]]; then
    printf '%s\n' "${BASH_REMATCH[3]}"
  else
    printf '\n'
  fi
}

is_source_sized_symbolic_cap() {
  local cap="$1"
  [[ -n "$cap" ]] || return 1
  [[ "$cap" =~ (^|_)(MAX|LIMIT|CAPACITY)($|_) ]] || return 1
  [[ "$cap" =~ (TOKEN|TOKENS|NODE|NODES|RECORD|RECORDS|ROW|ROWS|ITEM|ITEMS|DECL|DECLS|FN|FNS|FUNCTION|FUNCTIONS|TYPE|TYPES|MODULE|MODULES|BLOCK|BLOCKS|FIELD|FIELDS|METHOD|METHODS|VARIANT|VARIANTS|EDGE|EDGES|RELATION|RELATIONS|RANGE|RANGES|SEGMENT|SEGMENTS|PARAM|PARAMS|CALL|CALLS|IMPORT|IMPORTS|LIBRARY|LIBRARIES|FILE|FILES|SOURCE|DISPATCH|DISPATCHES|INVOCATION|INVOCATIONS|WORK_ITEM|WORK_ITEMS|WORKITEM|WORKITEMS|HIR|AST|SYMBOL|SYMBOLS|RELOC|RELOCS|EXPR|STATEMENT|STATEMENTS|BODY|BRANCH|PATH|CONTEXT|PARENT|CHILD|SIBLING|ANCESTOR|DESCENDANT|TREE|ALIAS|CHAIN|HOP|HOPS|STACK|CANDIDATE|CANDIDATES|CONTRACT|CONTRACTS|OBLIGATION|OBLIGATIONS|PRINT|PRINTS|REGALLOC) ]]
}

reason_for_loop() {
  local classification="$1"
  local header="$2"
  local cap="$3"
  case "$classification" in
    fixed-bound)
      if [[ -n "$cap" && "$cap" -le 16 ]]; then
        printf '%s\n' 'tiny-fixed-literal'
      elif [[ "$header" =~ (offs|step|stride).*(<<=|>>=|GSIZE|WG_SIZE|SCAN_SLOTS|REG_COUNT) ]]; then
        printf '%s\n' 'workgroup-local-scan-or-reduce'
      elif [[ -n "$cap" && "$cap" -gt "$large_fixed_bound_threshold" ]]; then
        printf 'large-fixed-literal-cap-%s\n' "$cap"
      elif [[ -n "$cap" ]]; then
        printf 'fixed-literal-cap-%s\n' "$cap"
      else
        printf '%s\n' 'fixed-symbolic-cap'
      fi
      ;;
    fixed-bound-guard)
      if [[ -n "$cap" && "$cap" -le 16 ]]; then
        printf '%s\n' 'tiny-fixed-cap-with-dynamic-exit'
      elif [[ -n "$cap" && "$cap" -gt "$large_fixed_bound_threshold" && "$header" =~ (subtree|parent|child|sibling|ancestor|descendant|valid_node) ]]; then
        printf '%s\n' 'large-fixed-cap-subtree-or-parent-walk'
      elif [[ -n "$cap" && "$cap" -gt "$large_fixed_bound_threshold" ]]; then
        printf '%s\n' 'large-fixed-cap-with-data-dependent-exit'
      elif [[ "$header" =~ (subtree|parent|child|sibling|ancestor|descendant|valid_node) ]]; then
        printf '%s\n' 'fixed-cap-subtree-or-parent-walk'
      else
        printf '%s\n' 'fixed-cap-with-data-dependent-exit'
      fi
      ;;
    data-dependent)
      if [[ "$header" =~ (subtree|parent|child|sibling|ancestor|descendant|valid_node) ]]; then
        printf '%s\n' 'subtree-or-parent-sized-loop'
      elif [[ "$header" =~ (active_token_count|active_[a-z0-9_]*count|n_active|n_[a-z0-9_]*(tokens|nodes|records|rows|items|decls|fns|types|modules|blocks|bytes|chars|fields|methods|variants|edges|relations|ranges|segments|params|calls|imports|libraries|files)|num_[a-z0-9_]*(tokens|nodes|records|rows|items|decls|fns|types|modules|blocks|bytes|chars|fields|methods|variants|edges|relations|ranges|segments|params|calls|imports|libraries|files)|total_[a-z0-9_]*(tokens|nodes|records|rows|items|decls|fns|types|modules|blocks|bytes|chars|fields|methods|variants|edges|relations|ranges|segments|params|calls|imports|libraries|files)|[a-z0-9_]*(token|tokens|node|nodes|record|records|row|rows|item|items|decl|decls|fn|fns|function|functions|type|types|module|modules|block|blocks|byte|bytes|char|chars|field|fields|method|methods|variant|variants|edge|edges|relation|relations|range|ranges|segment|segments|param|params|call|calls|import|imports|library|libraries|file|files|source|hir|ast|symbol|symbols|reloc|relocs)[a-z0-9_]*_(count|len|size|limit|end|capacity)|token_count|source_len|byte_len|gParams) ]] || has_dispatch_sized_alias "$header"; then
        printf '%s\n' 'source-or-dispatch-sized-loop'
      else
        printf '%s\n' 'record-or-range-sized-loop'
      fi
      ;;
    while-loop)
      if [[ "$header" =~ (fixed_stack|WG_SIZE|SCAN_SLOTS|n_blocks) ]]; then
        printf '%s\n' 'while-loop-with-apparent-bounded-helper'
      else
        printf '%s\n' 'while-loop-manual-review'
      fi
      ;;
    *)
      printf '%s\n' 'unclassified-for-loop-bound'
      ;;
  esac
}

risk_for_loop() {
  local classification="$1"
  local reason="$2"
  case "$classification" in
    fixed-bound)
      if [[ "$reason" =~ ^large-fixed-literal-cap- ]]; then
        printf '%s\n' 'high'
      else
        printf '%s\n' 'low'
      fi
      ;;
    fixed-bound-guard)
      if [[ "$reason" =~ ^tiny-fixed-cap ]]; then
        printf '%s\n' 'low'
      elif [[ "$reason" =~ ^large-fixed-cap- ]]; then
        printf '%s\n' 'high'
      else
        printf '%s\n' 'medium'
      fi
      ;;
    data-dependent)
      printf '%s\n' 'high'
      ;;
    while-loop)
      printf '%s\n' 'high'
      ;;
    *)
      printf '%s\n' 'medium'
      ;;
  esac
}

is_large_fixed_bound_reason() {
  case "$1" in
    large-fixed-literal-cap-*|large-fixed-cap-*) return 0 ;;
    *) return 1 ;;
  esac
}

is_bounded_literal_cap() {
  local cap="$1"
  [[ -n "$cap" ]] && ((10#$cap <= large_fixed_bound_threshold))
}

is_bounded_explicit_literal_candidate() {
  local classification="$1"
  local cap="$2"
  case "$classification" in
    fixed-bound|fixed-bound-guard) ;;
    *) return 1 ;;
  esac
  is_bounded_literal_cap "$cap"
}

is_for_header() {
  [[ "$1" =~ (^|[[:space:]])for[[:space:]]*\( ]]
}

has_loop_hint_attr() {
  case "$1" in
    loop-attr|unroll-attr|loop+unroll-attr) return 0 ;;
    *) return 1 ;;
  esac
}

has_loop_attr() {
  case "$1" in
    loop-attr|loop+unroll-attr) return 0 ;;
    *) return 1 ;;
  esac
}

has_unroll_attr() {
  case "$1" in
    unroll-attr|loop+unroll-attr) return 0 ;;
    *) return 1 ;;
  esac
}

is_suspicious_loop_attr() {
  local classification="$1"
  local reason="$2"
  case "$classification" in
    data-dependent|while-loop|unknown-bound) return 0 ;;
  esac
  if is_large_fixed_bound_reason "$reason"; then
    return 0
  fi
  return 1
}

is_raw_for_review_required() {
  local classification="$1"
  local header="$2"
  local loop_attr="$3"
  has_loop_hint_attr "$loop_attr" && return 1
  is_for_header "$header" || return 1
  case "$classification" in
    data-dependent|unknown-bound) return 0 ;;
    *) return 1 ;;
  esac
}

is_pass_contract_review() {
  local classification="$1"
  local reason="$2"
  local header="$3"
  local loop_attr="$4"
  case "$classification" in
    data-dependent|while-loop|unknown-bound) return 0 ;;
  esac
  if is_large_fixed_bound_reason "$reason"; then
    return 0
  fi
  if has_loop_hint_attr "$loop_attr" && is_suspicious_loop_attr "$classification" "$reason"; then
    return 0
  fi
  if is_raw_for_review_required "$classification" "$header" "$loop_attr"; then
    return 0
  fi
  return 1
}

loop_flags_for_row() {
  local classification="$1"
  local reason="$2"
  local header="$3"
  local loop_attr="$4"
  local cap="$5"
  local symbolic_cap="$6"
  local flags=()

  if has_loop_hint_attr "$loop_attr"; then
    flags+=("loop-hint-attribute")
    if has_loop_attr "$loop_attr"; then
      flags+=("loop-attribute")
    fi
    if has_unroll_attr "$loop_attr"; then
      flags+=("unroll-attribute")
    fi
    if is_suspicious_loop_attr "$classification" "$reason"; then
      flags+=("suspicious-loop-hint-attribute")
      if has_loop_attr "$loop_attr"; then
        flags+=("suspicious-loop-attribute")
      fi
      if has_unroll_attr "$loop_attr"; then
        flags+=("suspicious-unroll-attribute")
      fi
    fi
  elif is_for_header "$header"; then
    flags+=("raw-for")
    if is_raw_for_review_required "$classification" "$header" "$loop_attr"; then
      flags+=("raw-for-review-required")
    fi
  elif [[ "$classification" == "while-loop" ]]; then
    flags+=("raw-while")
  fi

  if [[ -n "$cap" ]]; then
    flags+=("explicit-fixed-literal-cap-$cap")
    if is_bounded_explicit_literal_candidate "$classification" "$cap"; then
      flags+=("bounded-explicit-literal-candidate")
    fi
  elif [[ "$classification" == "fixed-bound" || "$classification" == "fixed-bound-guard" ]]; then
    flags+=("symbolic-fixed-bound")
  fi
  if [[ -n "$symbolic_cap" ]]; then
    flags+=("symbolic-fixed-cap-$symbolic_cap")
    if is_source_sized_symbolic_cap "$symbolic_cap"; then
      flags+=("source-sized-symbolic-cap-candidate")
    fi
  fi

  if [[ "${#flags[@]}" -eq 0 ]]; then
    printf '%s\n' 'none'
  else
    local IFS=,
    printf '%s\n' "${flags[*]}"
  fi
}

is_codegen_path() {
  case "$1" in
    */codegen/*|codegen/*) return 0 ;;
    *) return 1 ;;
  esac
}

is_wasm_codegen_path() {
  case "$1" in
    */codegen/wasm*|codegen/wasm*) return 0 ;;
    *) return 1 ;;
  esac
}

is_x86_codegen_path() {
  case "$1" in
    */codegen/x86_*|codegen/x86_*) return 0 ;;
    *) return 1 ;;
  esac
}

is_parser_path() {
  case "$1" in
    */parser/*|parser/*) return 0 ;;
    *) return 1 ;;
  esac
}

is_type_checker_path() {
  case "$1" in
    */type_checker/*|type_checker/*) return 0 ;;
    *) return 1 ;;
  esac
}

component_for_path() {
  case "$1" in
    */codegen/x86_*|codegen/x86_*) printf '%s\n' 'codegen-x86' ;;
    */codegen/wasm*|codegen/wasm*) printf '%s\n' 'codegen-wasm' ;;
    */codegen/*|codegen/*) printf '%s\n' 'codegen-other' ;;
    */type_checker/*|type_checker/*) printf '%s\n' 'type-checker' ;;
    */parser/*|parser/*) printf '%s\n' 'parser' ;;
    */lexer/*|lexer/*) printf '%s\n' 'lexer' ;;
    *) printf '%s\n' 'other' ;;
  esac
}

paper_pass_for_loop() {
  local reason="$1"
  case "$reason" in
    record-or-range-sized-loop)
      printf '%s\n' 'record-map-prefix-scan-scatter'
      ;;
    source-or-dispatch-sized-loop)
      printf '%s\n' 'source-record-partition-prefix-scan'
      ;;
    subtree-or-parent-sized-loop|fixed-cap-subtree-or-parent-walk|large-fixed-cap-subtree-or-parent-walk)
      printf '%s\n' 'depth-sort-parent-join-scatter'
      ;;
    large-fixed-cap-with-data-dependent-exit|fixed-cap-with-data-dependent-exit)
      printf '%s\n' 'publish-guard-records-scan-scatter'
      ;;
    large-fixed-literal-cap-*)
      printf '%s\n' 'split-large-cap-into-record-scan'
      ;;
    while-loop-with-apparent-bounded-helper|workgroup-local-scan-or-reduce)
      printf '%s\n' 'bounded-local-scan-reduce-review'
      ;;
    while-loop-manual-review)
      printf '%s\n' 'fixed-point-or-worklist-review'
      ;;
    tiny-fixed-literal|tiny-fixed-cap-with-dynamic-exit|fixed-literal-cap-*|fixed-symbolic-cap)
      printf '%s\n' 'bounded-local-helper-review'
      ;;
    *)
      printf '%s\n' 'manual-paper-pass-classification'
      ;;
  esac
}

rewrite_route_for_paper_pass() {
  local paper_pass="$1"
  case "$paper_pass" in
    record-map-prefix-scan-scatter)
      printf '%s\n' 'publish-records-map-prefix-sum-scatter'
      ;;
    source-record-partition-prefix-scan)
      printf '%s\n' 'partition-source-records-prefix-sum-scatter'
      ;;
    depth-sort-parent-join-scatter)
      printf '%s\n' 'sort-depth-parent-join-scatter'
      ;;
    publish-guard-records-scan-scatter)
      printf '%s\n' 'publish-guard-records-prefix-sum-scatter'
      ;;
    split-large-cap-into-record-scan)
      printf '%s\n' 'split-cap-records-prefix-sum-scatter'
      ;;
    fixed-point-or-worklist-review)
      printf '%s\n' 'frontier-worklist-scan-scatter'
      ;;
    bounded-local-scan-reduce-review)
      printf '%s\n' 'bounded-local-scan-reduce-justify'
      ;;
    bounded-local-helper-review)
      printf '%s\n' 'bounded-local-helper-justify'
      ;;
    *)
      printf '%s\n' 'manual-pass-contract-classification'
      ;;
  esac
}

source_sized_symbolic_cap_route() {
  local cap="$1"
  case "$cap" in
    *REGALLOC*)
      printf '%s\n' 'segmented-regalloc-scan-scatter'
      ;;
    *TREE*|*PARENT*|*CHILD*|*SIBLING*|*ANCESTOR*|*DESCENDANT*|*HOP*|*HOPS*|*CONTEXT*|*ALIAS*|*CHAIN*|*EXPR*|*BODY*|*BRANCH*|*STACK*|*HIR*|*AST*|*NODE*|*STATEMENT*|*STATEMENTS*)
      printf '%s\n' 'sort-depth-parent-join-scatter'
      ;;
    *TOKEN*|*SOURCE*|*DISPATCH*|*INVOCATION*|*WORK_ITEM*|*WORK_ITEMS*|*WORKITEM*|*WORKITEMS*|*BYTE*|*CHAR*|*PATH*|*PRINT*|*PRINTS*|*FILE*|*FILES*)
      printf '%s\n' 'partition-source-records-prefix-sum-scatter'
      ;;
    *METHOD*|*CONTRACT*|*CONTRACTS*|*OBLIGATION*|*OBLIGATIONS*|*CANDIDATE*|*CANDIDATES*|*PARAM*|*PARAMS*|*CALL*|*CALLS*|*RELATION*|*RELATIONS*|*RANGE*|*RANGES*|*SEGMENT*|*SEGMENTS*|*ROW*|*ROWS*|*RECORD*|*RECORDS*|*FIELD*|*FIELDS*|*VARIANT*|*VARIANTS*|*DECL*|*DECLS*|*FN*|*FNS*|*FUNCTION*|*FUNCTIONS*|*MODULE*|*MODULES*|*IMPORT*|*IMPORTS*|*LIBRARY*|*LIBRARIES*|*SYMBOL*|*SYMBOLS*|*RELOC*|*RELOCS*)
      printf '%s\n' 'publish-records-sort-reduce-scatter'
      ;;
    *)
      printf '%s\n' 'manual-symbolic-cap-classification'
      ;;
  esac
}

is_paper_pass_blocker() {
  case "$1" in
    bounded-local-helper-review|bounded-local-scan-reduce-review) return 1 ;;
    *) return 0 ;;
  esac
}

has_pareas_primitive_context() {
  local text="${1,,}"
  [[ "$text" =~ (prefix|scan|reduce|scatter|sort|radix|partition|compact|histogram|bucket|join) ]]
}

has_legacy_fallback_context() {
  local text="${1,,}"
  [[ "$text" =~ (legacy|fallback|compat) ]]
}

is_pareas_primitive_bounded_loop() {
  local classification="$1"
  local reason="$2"
  local header="$3"
  local path="$4"
  local context="$5"
  local symbolic_cap="$6"

  if is_source_sized_symbolic_cap "$symbolic_cap"; then
    return 1
  fi
  case "$reason" in
    workgroup-local-scan-or-reduce) return 0 ;;
  esac
  [[ "$classification" == "fixed-bound" ]] || return 1
  case "$reason" in
    tiny-fixed-literal|fixed-literal-cap-*|fixed-symbolic-cap)
      has_pareas_primitive_context "${path} ${context} ${header}"
      ;;
    *) return 1 ;;
  esac
}

pass_shape_for_loop() {
  local classification="$1"
  local reason="$2"
  local header="$3"
  local path="$4"
  local context="$5"
  local symbolic_cap="$6"
  local paper_pass="$7"
  local loop_text="${path} ${context} ${header} ${symbolic_cap}"

  if is_source_sized_symbolic_cap "$symbolic_cap"; then
    if has_legacy_fallback_context "$loop_text"; then
      printf '%s\n' 'bounded-source-sized-legacy-fallback'
    else
      printf '%s\n' 'bounded-source-sized-symbolic-cap'
    fi
    return
  fi

  if is_paper_pass_blocker "$paper_pass"; then
    printf '%s\n' 'source-scale-or-nonlocal-loop'
    return
  fi

  if has_legacy_fallback_context "$loop_text"; then
    printf '%s\n' 'bounded-legacy-fallback'
    return
  fi

  if is_pareas_primitive_bounded_loop "$classification" "$reason" "$header" "$path" "$context" "$symbolic_cap"; then
    printf '%s\n' 'pareas-primitive-bounded-loop'
    return
  fi

  case "$classification" in
    fixed-bound|fixed-bound-guard)
      printf '%s\n' 'bounded-local-helper-review'
      ;;
    *)
      printf '%s\n' 'manual-review'
      ;;
  esac
}

audit_evidence_role_for_pass_shape() {
  case "$1" in
    pareas-primitive-bounded-loop)
      printf '%s\n' 'proof'
      ;;
    source-scale-or-nonlocal-loop|bounded-source-sized-symbolic-cap|bounded-source-sized-legacy-fallback|manual-review)
      printf '%s\n' 'blocker'
      ;;
    bounded-local-helper-review|bounded-legacy-fallback)
      printf '%s\n' 'local-review'
      ;;
    *)
      printf '%s\n' 'blocker'
      ;;
  esac
}

audit_evidence_for_pass_shape() {
  case "$1" in
    pareas-primitive-bounded-loop)
      printf '%s\n' 'proof-pass-primitive-shape-only'
      ;;
    source-scale-or-nonlocal-loop)
      printf '%s\n' 'blocker-source-scale-or-nonlocal'
      ;;
    bounded-source-sized-symbolic-cap)
      printf '%s\n' 'blocker-source-sized-symbolic-cap'
      ;;
    bounded-source-sized-legacy-fallback)
      printf '%s\n' 'blocker-source-sized-legacy-fallback'
      ;;
    manual-review)
      printf '%s\n' 'blocker-manual-review'
      ;;
    bounded-legacy-fallback)
      printf '%s\n' 'local-review-legacy-fallback'
      ;;
    bounded-local-helper-review)
      printf '%s\n' 'local-review-bounded-helper'
      ;;
    *)
      printf '%s\n' 'blocker-unclassified-pass-shape'
      ;;
  esac
}

print_summary_rows() {
  local scope="$1"
  local total class risk review count

  if [[ "$scope" == "emitted" ]]; then
    total="$emitted_total"
  else
    total="$scanned_total"
  fi

  for class in fixed-bound fixed-bound-guard data-dependent while-loop unknown-bound; do
    if [[ "$scope" == "emitted" ]]; then
      count="${emitted_class_counts[$class]:-0}"
    else
      count="${scanned_class_counts[$class]:-0}"
    fi
    printf 'summary\t%s\tclassification\t%s\t%s\n' "$scope" "$class" "$count"
  done

  for risk in low medium high; do
    if [[ "$scope" == "emitted" ]]; then
      count="${emitted_risk_counts[$risk]:-0}"
    else
      count="${scanned_risk_counts[$risk]:-0}"
    fi
    printf 'summary\t%s\trisk\t%s\t%s\n' "$scope" "$risk" "$count"
  done

  if [[ "$scope" == "emitted" ]]; then
    print_component_summary_rows "$scope" emitted_component_counts
    print_component_risk_summary_rows "$scope" emitted_component_risk_counts
    print_reason_summary_rows "$scope" emitted_reason_counts
    print_paper_pass_summary_rows "$scope" emitted_paper_pass_counts
    print_rewrite_route_summary_rows "$scope" emitted_rewrite_route_counts
    print_reason_rewrite_route_summary_rows "$scope" emitted_reason_rewrite_route_counts
    print_component_reason_rewrite_route_summary_rows "$scope" emitted_component_reason_rewrite_route_counts
    print_component_paper_pass_summary_rows "$scope" emitted_component_paper_pass_counts
    print_component_paper_pass_blocker_summary_rows "$scope" emitted_component_paper_pass_blocker_counts
    print_component_rewrite_route_blocker_summary_rows "$scope" emitted_component_rewrite_route_blocker_counts
    print_component_paper_pass_local_review_summary_rows "$scope" emitted_component_paper_pass_local_review_counts
    print_component_rewrite_route_local_review_summary_rows "$scope" emitted_component_rewrite_route_local_review_counts
    print_component_source_sized_symbolic_cap_summary_rows "$scope" emitted_component_source_sized_symbolic_cap_counts
    print_source_sized_symbolic_cap_name_summary_rows "$scope" emitted_source_sized_symbolic_cap_name_counts
    print_source_sized_symbolic_cap_route_summary_rows "$scope" emitted_source_sized_symbolic_cap_route_counts
    print_component_source_sized_symbolic_cap_route_summary_rows "$scope" emitted_component_source_sized_symbolic_cap_route_counts
    print_component_source_sized_symbolic_cap_path_route_summary_rows "$scope" emitted_component_source_sized_symbolic_cap_path_route_counts
    print_pass_shape_summary_rows "$scope" emitted_pass_shape_counts
    print_component_pass_shape_summary_rows "$scope" emitted_component_pass_shape_counts
    print_audit_evidence_role_summary_rows "$scope" emitted_audit_evidence_role_counts
    print_audit_evidence_summary_rows "$scope" emitted_audit_evidence_counts
    print_component_audit_evidence_role_summary_rows "$scope" emitted_component_audit_evidence_role_counts
    print_component_audit_evidence_summary_rows "$scope" emitted_component_audit_evidence_counts
    print_claim_blocker_summary_rows "$scope" emitted_audit_evidence_role_counts
  else
    print_component_summary_rows "$scope" scanned_component_counts
    print_component_risk_summary_rows "$scope" scanned_component_risk_counts
    print_reason_summary_rows "$scope" scanned_reason_counts
    print_paper_pass_summary_rows "$scope" scanned_paper_pass_counts
    print_rewrite_route_summary_rows "$scope" scanned_rewrite_route_counts
    print_reason_rewrite_route_summary_rows "$scope" scanned_reason_rewrite_route_counts
    print_component_reason_rewrite_route_summary_rows "$scope" scanned_component_reason_rewrite_route_counts
    print_component_paper_pass_summary_rows "$scope" scanned_component_paper_pass_counts
    print_component_paper_pass_blocker_summary_rows "$scope" scanned_component_paper_pass_blocker_counts
    print_component_rewrite_route_blocker_summary_rows "$scope" scanned_component_rewrite_route_blocker_counts
    print_component_paper_pass_local_review_summary_rows "$scope" scanned_component_paper_pass_local_review_counts
    print_component_rewrite_route_local_review_summary_rows "$scope" scanned_component_rewrite_route_local_review_counts
    print_component_source_sized_symbolic_cap_summary_rows "$scope" scanned_component_source_sized_symbolic_cap_counts
    print_source_sized_symbolic_cap_name_summary_rows "$scope" scanned_source_sized_symbolic_cap_name_counts
    print_source_sized_symbolic_cap_route_summary_rows "$scope" scanned_source_sized_symbolic_cap_route_counts
    print_component_source_sized_symbolic_cap_route_summary_rows "$scope" scanned_component_source_sized_symbolic_cap_route_counts
    print_component_source_sized_symbolic_cap_path_route_summary_rows "$scope" scanned_component_source_sized_symbolic_cap_path_route_counts
    print_pass_shape_summary_rows "$scope" scanned_pass_shape_counts
    print_component_pass_shape_summary_rows "$scope" scanned_component_pass_shape_counts
    print_audit_evidence_role_summary_rows "$scope" scanned_audit_evidence_role_counts
    print_audit_evidence_summary_rows "$scope" scanned_audit_evidence_counts
    print_component_audit_evidence_role_summary_rows "$scope" scanned_component_audit_evidence_role_counts
    print_component_audit_evidence_summary_rows "$scope" scanned_component_audit_evidence_counts
    print_claim_blocker_summary_rows "$scope" scanned_audit_evidence_role_counts
  fi

  for review in review-required codegen-review-required wasm-codegen-review-required x86-codegen-review-required parser-review-required type-checker-review-required wasm-codegen-fixed-bound x86-codegen-fixed-bound parser-fixed-bound type-checker-fixed-bound large-fixed-bound codegen-large-fixed-bound wasm-codegen-large-fixed-bound x86-codegen-large-fixed-bound parser-large-fixed-bound type-checker-large-fixed-bound parser-source-sized-symbolic-cap type-checker-source-sized-symbolic-cap loop-attribute unroll-attribute suspicious-loop-attribute suspicious-unroll-attribute raw-for-loop raw-for-review-required explicit-fixed-literal-bound bounded-explicit-literal-candidate source-sized-symbolic-cap; do
    if [[ "$scope" == "emitted" ]]; then
      count="${emitted_review_counts[$review]:-0}"
    else
      count="${scanned_review_counts[$review]:-0}"
    fi
    printf 'summary\t%s\treview\t%s\t%s\n' "$scope" "$review" "$count"
  done

  for contract in bounded-explicit-literal-candidate paper-pass-blocker paper-pass-local-review pass-contract-review; do
    if [[ "$scope" == "emitted" ]]; then
      count="${emitted_review_counts[$contract]:-0}"
    else
      count="${scanned_review_counts[$contract]:-0}"
    fi
    printf 'summary\t%s\tpass-contract\t%s\t%s\n' "$scope" "$contract" "$count"
  done

  print_evidence_policy_summary_rows "$scope"

  printf 'summary\t%s\ttotal\tall\t%s\n' "$scope" "$total"
}

print_evidence_policy_summary_rows() {
  local scope="$1"

  printf 'summary\t%s\tevidence-policy\tbehavior-facing-pass-evidence\t1\n' "$scope"
  printf 'summary\t%s\tevidence-policy\trewrite-routes-not-source-grep-evidence\t1\n' "$scope"
  printf 'summary\t%s\tevidence-policy\trust-product-source-inspection-not-pass-evidence\t1\n' "$scope"
  printf 'summary\t%s\tevidence-policy\taudit-proof-is-pass-shape-only\t1\n' "$scope"
  printf 'summary\t%s\tevidence-policy\taudit-blockers-and-local-review-are-not-performance-evidence\t1\n' "$scope"
  printf 'summary\t%s\tevidence-policy\taudit-debt-blocks-performance-and-pareas-parity-claims\t1\n' "$scope"
  printf 'summary\t%s\tevidence-policy\tzero-paper-pass-blocker-not-pass-contract-proof\t1\n' "$scope"
  printf 'summary\t%s\tevidence-policy\tno-run-not-performance-evidence\t1\n' "$scope"
  printf 'summary\t%s\tevidence-policy\tno-run-not-pareas-claim-evidence\t1\n' "$scope"
}

print_component_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component; do
    [[ -n "$component" ]] || continue
    count="${counts[$component]:-0}"
    printf 'summary\t%s\tcomponent\t%s\t%s\n' "$scope" "$component" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_component_risk_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component_risk count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component_risk; do
    [[ -n "$component_risk" ]] || continue
    count="${counts[$component_risk]:-0}"
    printf 'summary\t%s\tcomponent-risk\t%s\t%s\n' "$scope" "$component_risk" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_paper_pass_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local paper_pass count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r paper_pass; do
    [[ -n "$paper_pass" ]] || continue
    count="${counts[$paper_pass]:-0}"
    printf 'summary\t%s\tpaper-pass\t%s\t%s\n' "$scope" "$paper_pass" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_rewrite_route_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local route count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r route; do
    [[ -n "$route" ]] || continue
    count="${counts[$route]:-0}"
    printf 'summary\t%s\trewrite-route\t%s\t%s\n' "$scope" "$route" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_reason_rewrite_route_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local reason_route count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r reason_route; do
    [[ -n "$reason_route" ]] || continue
    count="${counts[$reason_route]:-0}"
    printf 'summary\t%s\treason-rewrite-route\t%s\t%s\n' "$scope" "$reason_route" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_component_reason_rewrite_route_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component_reason_route count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component_reason_route; do
    [[ -n "$component_reason_route" ]] || continue
    count="${counts[$component_reason_route]:-0}"
    printf 'summary\t%s\tcomponent-reason-rewrite-route\t%s\t%s\n' "$scope" "$component_reason_route" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_component_paper_pass_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component_paper_pass count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component_paper_pass; do
    [[ -n "$component_paper_pass" ]] || continue
    count="${counts[$component_paper_pass]:-0}"
    printf 'summary\t%s\tcomponent-paper-pass\t%s\t%s\n' "$scope" "$component_paper_pass" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_component_paper_pass_blocker_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component_paper_pass count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component_paper_pass; do
    [[ -n "$component_paper_pass" ]] || continue
    count="${counts[$component_paper_pass]:-0}"
    printf 'summary\t%s\tcomponent-paper-pass-blocker\t%s\t%s\n' "$scope" "$component_paper_pass" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_component_rewrite_route_blocker_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component_rewrite_route count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component_rewrite_route; do
    [[ -n "$component_rewrite_route" ]] || continue
    count="${counts[$component_rewrite_route]:-0}"
    printf 'summary\t%s\tcomponent-rewrite-route-blocker\t%s\t%s\n' "$scope" "$component_rewrite_route" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_component_paper_pass_local_review_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component_paper_pass count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component_paper_pass; do
    [[ -n "$component_paper_pass" ]] || continue
    count="${counts[$component_paper_pass]:-0}"
    printf 'summary\t%s\tcomponent-paper-pass-local-review\t%s\t%s\n' "$scope" "$component_paper_pass" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_component_rewrite_route_local_review_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component_rewrite_route count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component_rewrite_route; do
    [[ -n "$component_rewrite_route" ]] || continue
    count="${counts[$component_rewrite_route]:-0}"
    printf 'summary\t%s\tcomponent-rewrite-route-local-review\t%s\t%s\n' "$scope" "$component_rewrite_route" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_component_source_sized_symbolic_cap_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component; do
    [[ -n "$component" ]] || continue
    count="${counts[$component]:-0}"
    printf 'summary\t%s\tcomponent-source-sized-symbolic-cap\t%s\t%s\n' "$scope" "$component" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_source_sized_symbolic_cap_name_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local cap count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r cap; do
    [[ -n "$cap" ]] || continue
    count="${counts[$cap]:-0}"
    printf 'summary\t%s\tsource-sized-symbolic-cap-name\t%s\t%s\n' "$scope" "$cap" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_source_sized_symbolic_cap_route_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local route count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r route; do
    [[ -n "$route" ]] || continue
    count="${counts[$route]:-0}"
    printf 'summary\t%s\tsource-sized-symbolic-cap-route\t%s\t%s\n' "$scope" "$route" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_component_source_sized_symbolic_cap_route_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component_route count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component_route; do
    [[ -n "$component_route" ]] || continue
    count="${counts[$component_route]:-0}"
    printf 'summary\t%s\tcomponent-source-sized-symbolic-cap-route\t%s\t%s\n' "$scope" "$component_route" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_component_source_sized_symbolic_cap_path_route_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component_cap_path_route count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component_cap_path_route; do
    [[ -n "$component_cap_path_route" ]] || continue
    count="${counts[$component_cap_path_route]:-0}"
    printf 'summary\t%s\tcomponent-source-sized-symbolic-cap-path-route\t%s\t%s\n' "$scope" "$component_cap_path_route" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_pass_shape_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local pass_shape count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r pass_shape; do
    [[ -n "$pass_shape" ]] || continue
    count="${counts[$pass_shape]:-0}"
    printf 'summary\t%s\tpass-shape\t%s\t%s\n' "$scope" "$pass_shape" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_component_pass_shape_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component_pass_shape count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component_pass_shape; do
    [[ -n "$component_pass_shape" ]] || continue
    count="${counts[$component_pass_shape]:-0}"
    printf 'summary\t%s\tcomponent-pass-shape\t%s\t%s\n' "$scope" "$component_pass_shape" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_audit_evidence_role_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local role count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  for role in proof blocker local-review; do
    count="${counts[$role]:-0}"
    printf 'summary\t%s\taudit-evidence-role\t%s\t%s\n' "$scope" "$role" "$count"
  done
}

print_audit_evidence_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local evidence count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r evidence; do
    [[ -n "$evidence" ]] || continue
    count="${counts[$evidence]:-0}"
    printf 'summary\t%s\taudit-evidence\t%s\t%s\n' "$scope" "$evidence" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_component_audit_evidence_role_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component_role count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component_role; do
    [[ -n "$component_role" ]] || continue
    count="${counts[$component_role]:-0}"
    printf 'summary\t%s\tcomponent-audit-evidence-role\t%s\t%s\n' "$scope" "$component_role" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_component_audit_evidence_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local component_evidence count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r component_evidence; do
    [[ -n "$component_evidence" ]] || continue
    count="${counts[$component_evidence]:-0}"
    printf 'summary\t%s\tcomponent-audit-evidence\t%s\t%s\n' "$scope" "$component_evidence" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

print_claim_blocker_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local blocker local_review audit_debt
  local -n counts="$counts_name"

  blocker="${counts[blocker]:-0}"
  local_review="${counts[local-review]:-0}"
  audit_debt=$((blocker + local_review))

  printf 'summary\t%s\tclaim-blocker\tperformance-scaling-or-pareas-parity-audit-debt\t%s\n' "$scope" "$audit_debt"
  printf 'summary\t%s\tclaim-blocker\tperformance-scaling-or-pareas-parity-audit-blocker\t%s\n' "$scope" "$blocker"
  printf 'summary\t%s\tclaim-blocker\tperformance-scaling-or-pareas-parity-local-review\t%s\n' "$scope" "$local_review"
}

print_reason_summary_rows() {
  local scope="$1"
  local counts_name="$2"
  local reason count
  local -n counts="$counts_name"

  if [[ "${#counts[@]}" -eq 0 ]]; then
    return
  fi

  while IFS= read -r reason; do
    [[ -n "$reason" ]] || continue
    count="${counts[$reason]:-0}"
    printf 'summary\t%s\treason\t%s\t%s\n' "$scope" "$reason" "$count"
  done < <(printf '%s\n' "${!counts[@]}" | LC_ALL=C sort)
}

bad_count=0
scanned_total=0
emitted_total=0
declare -A scanned_class_counts=()
declare -A scanned_risk_counts=()
declare -A scanned_component_counts=()
declare -A scanned_component_risk_counts=()
declare -A scanned_reason_counts=()
declare -A scanned_paper_pass_counts=()
declare -A scanned_rewrite_route_counts=()
declare -A scanned_reason_rewrite_route_counts=()
declare -A scanned_component_reason_rewrite_route_counts=()
declare -A scanned_component_paper_pass_counts=()
declare -A scanned_component_paper_pass_blocker_counts=()
declare -A scanned_component_rewrite_route_blocker_counts=()
declare -A scanned_component_paper_pass_local_review_counts=()
declare -A scanned_component_rewrite_route_local_review_counts=()
declare -A scanned_component_source_sized_symbolic_cap_counts=()
declare -A scanned_source_sized_symbolic_cap_name_counts=()
declare -A scanned_source_sized_symbolic_cap_route_counts=()
declare -A scanned_component_source_sized_symbolic_cap_route_counts=()
declare -A scanned_component_source_sized_symbolic_cap_path_route_counts=()
declare -A scanned_pass_shape_counts=()
declare -A scanned_component_pass_shape_counts=()
declare -A scanned_audit_evidence_role_counts=()
declare -A scanned_audit_evidence_counts=()
declare -A scanned_component_audit_evidence_role_counts=()
declare -A scanned_component_audit_evidence_counts=()
declare -A scanned_review_counts=()
declare -A emitted_class_counts=()
declare -A emitted_risk_counts=()
declare -A emitted_component_counts=()
declare -A emitted_component_risk_counts=()
declare -A emitted_reason_counts=()
declare -A emitted_paper_pass_counts=()
declare -A emitted_rewrite_route_counts=()
declare -A emitted_reason_rewrite_route_counts=()
declare -A emitted_component_reason_rewrite_route_counts=()
declare -A emitted_component_paper_pass_counts=()
declare -A emitted_component_paper_pass_blocker_counts=()
declare -A emitted_component_rewrite_route_blocker_counts=()
declare -A emitted_component_paper_pass_local_review_counts=()
declare -A emitted_component_rewrite_route_local_review_counts=()
declare -A emitted_component_source_sized_symbolic_cap_counts=()
declare -A emitted_source_sized_symbolic_cap_name_counts=()
declare -A emitted_source_sized_symbolic_cap_route_counts=()
declare -A emitted_component_source_sized_symbolic_cap_route_counts=()
declare -A emitted_component_source_sized_symbolic_cap_path_route_counts=()
declare -A emitted_pass_shape_counts=()
declare -A emitted_component_pass_shape_counts=()
declare -A emitted_audit_evidence_role_counts=()
declare -A emitted_audit_evidence_counts=()
declare -A emitted_component_audit_evidence_role_counts=()
declare -A emitted_component_audit_evidence_counts=()
declare -A emitted_review_counts=()

while IFS=$'\t' read -r path line context loop_attr header; do
  [[ -n "$path" && -n "$line" && -n "$header" ]] || continue

  classification="unknown-bound"
  if [[ "$header" =~ (^|[[:space:]])while[[:space:]]*\( ]]; then
    classification="while-loop"
  else
    fixed=false
    data_dependent=false
    if has_fixed_bound "$header"; then
      fixed=true
    fi
    if has_data_dependent_bound "$header"; then
      data_dependent=true
    fi

    if [[ "$fixed" == true && "$data_dependent" == true ]]; then
      classification="fixed-bound-guard"
    elif [[ "$data_dependent" == true ]]; then
      classification="data-dependent"
    elif [[ "$fixed" == true ]]; then
      classification="fixed-bound"
    fi
  fi

  cap="$(fixed_cap_value "$header")"
  symbolic_cap="$(fixed_symbolic_cap_name "$header")"
  reason="$(reason_for_loop "$classification" "$header" "$cap")"
  risk="$(risk_for_loop "$classification" "$reason")"
  component="$(component_for_path "$path")"
  component_risk="${component}:${risk}"
  paper_pass="$(paper_pass_for_loop "$reason")"
  rewrite_route="$(rewrite_route_for_paper_pass "$paper_pass")"
  pass_shape="$(pass_shape_for_loop "$classification" "$reason" "$header" "$path" "$context" "$symbolic_cap" "$paper_pass")"
  audit_evidence_role="$(audit_evidence_role_for_pass_shape "$pass_shape")"
  audit_evidence="$(audit_evidence_for_pass_shape "$pass_shape")"
  component_paper_pass="${component}:${paper_pass}"
  component_rewrite_route="${component}:${rewrite_route}"
  component_pass_shape="${component}:${pass_shape}"
  component_audit_evidence_role="${component}:${audit_evidence_role}"
  component_audit_evidence="${component}:${audit_evidence}"
  reason_rewrite_route="${reason}:${rewrite_route}"
  component_reason_rewrite_route="${component}:${reason}:${rewrite_route}"
  loop_flags="$(loop_flags_for_row "$classification" "$reason" "$header" "$loop_attr" "$cap" "$symbolic_cap")"

  scanned_total=$((scanned_total + 1))
  scanned_class_counts[$classification]=$((${scanned_class_counts[$classification]:-0} + 1))
  scanned_risk_counts[$risk]=$((${scanned_risk_counts[$risk]:-0} + 1))
  scanned_component_counts[$component]=$((${scanned_component_counts[$component]:-0} + 1))
  scanned_component_risk_counts[$component_risk]=$((${scanned_component_risk_counts[$component_risk]:-0} + 1))
  scanned_reason_counts[$reason]=$((${scanned_reason_counts[$reason]:-0} + 1))
  scanned_paper_pass_counts[$paper_pass]=$((${scanned_paper_pass_counts[$paper_pass]:-0} + 1))
  scanned_rewrite_route_counts[$rewrite_route]=$((${scanned_rewrite_route_counts[$rewrite_route]:-0} + 1))
  scanned_reason_rewrite_route_counts[$reason_rewrite_route]=$((${scanned_reason_rewrite_route_counts[$reason_rewrite_route]:-0} + 1))
  scanned_component_reason_rewrite_route_counts[$component_reason_rewrite_route]=$((${scanned_component_reason_rewrite_route_counts[$component_reason_rewrite_route]:-0} + 1))
  scanned_component_paper_pass_counts[$component_paper_pass]=$((${scanned_component_paper_pass_counts[$component_paper_pass]:-0} + 1))
  scanned_pass_shape_counts[$pass_shape]=$((${scanned_pass_shape_counts[$pass_shape]:-0} + 1))
  scanned_component_pass_shape_counts[$component_pass_shape]=$((${scanned_component_pass_shape_counts[$component_pass_shape]:-0} + 1))
  scanned_audit_evidence_role_counts[$audit_evidence_role]=$((${scanned_audit_evidence_role_counts[$audit_evidence_role]:-0} + 1))
  scanned_audit_evidence_counts[$audit_evidence]=$((${scanned_audit_evidence_counts[$audit_evidence]:-0} + 1))
  scanned_component_audit_evidence_role_counts[$component_audit_evidence_role]=$((${scanned_component_audit_evidence_role_counts[$component_audit_evidence_role]:-0} + 1))
  scanned_component_audit_evidence_counts[$component_audit_evidence]=$((${scanned_component_audit_evidence_counts[$component_audit_evidence]:-0} + 1))
  if is_paper_pass_blocker "$paper_pass"; then
    scanned_review_counts[paper-pass-blocker]=$((${scanned_review_counts[paper-pass-blocker]:-0} + 1))
    scanned_component_paper_pass_blocker_counts[$component_paper_pass]=$((${scanned_component_paper_pass_blocker_counts[$component_paper_pass]:-0} + 1))
    scanned_component_rewrite_route_blocker_counts[$component_rewrite_route]=$((${scanned_component_rewrite_route_blocker_counts[$component_rewrite_route]:-0} + 1))
  else
    scanned_review_counts[paper-pass-local-review]=$((${scanned_review_counts[paper-pass-local-review]:-0} + 1))
    scanned_component_paper_pass_local_review_counts[$component_paper_pass]=$((${scanned_component_paper_pass_local_review_counts[$component_paper_pass]:-0} + 1))
    scanned_component_rewrite_route_local_review_counts[$component_rewrite_route]=$((${scanned_component_rewrite_route_local_review_counts[$component_rewrite_route]:-0} + 1))
  fi
  if has_loop_hint_attr "$loop_attr"; then
    scanned_review_counts[loop-attribute]=$((${scanned_review_counts[loop-attribute]:-0} + 1))
    if has_unroll_attr "$loop_attr"; then
      scanned_review_counts[unroll-attribute]=$((${scanned_review_counts[unroll-attribute]:-0} + 1))
    fi
    if is_suspicious_loop_attr "$classification" "$reason"; then
      scanned_review_counts[suspicious-loop-attribute]=$((${scanned_review_counts[suspicious-loop-attribute]:-0} + 1))
      if has_unroll_attr "$loop_attr"; then
        scanned_review_counts[suspicious-unroll-attribute]=$((${scanned_review_counts[suspicious-unroll-attribute]:-0} + 1))
      fi
    fi
  fi
  if ! has_loop_hint_attr "$loop_attr" && is_for_header "$header"; then
    scanned_review_counts[raw-for-loop]=$((${scanned_review_counts[raw-for-loop]:-0} + 1))
    if is_raw_for_review_required "$classification" "$header" "$loop_attr"; then
      scanned_review_counts[raw-for-review-required]=$((${scanned_review_counts[raw-for-review-required]:-0} + 1))
    fi
  fi
  if [[ -n "$cap" ]]; then
    scanned_review_counts[explicit-fixed-literal-bound]=$((${scanned_review_counts[explicit-fixed-literal-bound]:-0} + 1))
    if is_bounded_explicit_literal_candidate "$classification" "$cap"; then
      scanned_review_counts[bounded-explicit-literal-candidate]=$((${scanned_review_counts[bounded-explicit-literal-candidate]:-0} + 1))
    fi
  fi
  if is_source_sized_symbolic_cap "$symbolic_cap"; then
    symbolic_cap_route="$(source_sized_symbolic_cap_route "$symbolic_cap")"
    component_symbolic_cap_route="${component}:${symbolic_cap_route}"
    component_symbolic_cap_path_route="${component}:${symbolic_cap}:${path}:${symbolic_cap_route}"
    scanned_review_counts[source-sized-symbolic-cap]=$((${scanned_review_counts[source-sized-symbolic-cap]:-0} + 1))
    scanned_component_source_sized_symbolic_cap_counts[$component]=$((${scanned_component_source_sized_symbolic_cap_counts[$component]:-0} + 1))
    scanned_source_sized_symbolic_cap_name_counts[$symbolic_cap]=$((${scanned_source_sized_symbolic_cap_name_counts[$symbolic_cap]:-0} + 1))
    scanned_source_sized_symbolic_cap_route_counts[$symbolic_cap_route]=$((${scanned_source_sized_symbolic_cap_route_counts[$symbolic_cap_route]:-0} + 1))
    scanned_component_source_sized_symbolic_cap_route_counts[$component_symbolic_cap_route]=$((${scanned_component_source_sized_symbolic_cap_route_counts[$component_symbolic_cap_route]:-0} + 1))
    scanned_component_source_sized_symbolic_cap_path_route_counts[$component_symbolic_cap_path_route]=$((${scanned_component_source_sized_symbolic_cap_path_route_counts[$component_symbolic_cap_path_route]:-0} + 1))
    if is_parser_path "$path"; then
      scanned_review_counts[parser-source-sized-symbolic-cap]=$((${scanned_review_counts[parser-source-sized-symbolic-cap]:-0} + 1))
    fi
    if is_type_checker_path "$path"; then
      scanned_review_counts[type-checker-source-sized-symbolic-cap]=$((${scanned_review_counts[type-checker-source-sized-symbolic-cap]:-0} + 1))
    fi
  fi
  if is_pass_contract_review "$classification" "$reason" "$header" "$loop_attr"; then
    scanned_review_counts[pass-contract-review]=$((${scanned_review_counts[pass-contract-review]:-0} + 1))
  fi
  if is_large_fixed_bound_reason "$reason"; then
    scanned_review_counts[large-fixed-bound]=$((${scanned_review_counts[large-fixed-bound]:-0} + 1))
    if is_codegen_path "$path"; then
      scanned_review_counts[codegen-large-fixed-bound]=$((${scanned_review_counts[codegen-large-fixed-bound]:-0} + 1))
    fi
    if is_wasm_codegen_path "$path"; then
      scanned_review_counts[wasm-codegen-large-fixed-bound]=$((${scanned_review_counts[wasm-codegen-large-fixed-bound]:-0} + 1))
    fi
    if is_x86_codegen_path "$path"; then
      scanned_review_counts[x86-codegen-large-fixed-bound]=$((${scanned_review_counts[x86-codegen-large-fixed-bound]:-0} + 1))
    fi
    if is_parser_path "$path"; then
      scanned_review_counts[parser-large-fixed-bound]=$((${scanned_review_counts[parser-large-fixed-bound]:-0} + 1))
    fi
    if is_type_checker_path "$path"; then
      scanned_review_counts[type-checker-large-fixed-bound]=$((${scanned_review_counts[type-checker-large-fixed-bound]:-0} + 1))
    fi
  fi

  case "$classification" in
    data-dependent|while-loop|unknown-bound)
      bad_count=$((bad_count + 1))
      scanned_review_counts[review-required]=$((${scanned_review_counts[review-required]:-0} + 1))
      if is_codegen_path "$path"; then
        scanned_review_counts[codegen-review-required]=$((${scanned_review_counts[codegen-review-required]:-0} + 1))
      fi
      if is_wasm_codegen_path "$path"; then
        scanned_review_counts[wasm-codegen-review-required]=$((${scanned_review_counts[wasm-codegen-review-required]:-0} + 1))
      fi
      if is_x86_codegen_path "$path"; then
        scanned_review_counts[x86-codegen-review-required]=$((${scanned_review_counts[x86-codegen-review-required]:-0} + 1))
      fi
      if is_parser_path "$path"; then
        scanned_review_counts[parser-review-required]=$((${scanned_review_counts[parser-review-required]:-0} + 1))
      fi
      if is_type_checker_path "$path"; then
        scanned_review_counts[type-checker-review-required]=$((${scanned_review_counts[type-checker-review-required]:-0} + 1))
      fi
      ;;
  esac
  if [[ "$classification" == "fixed-bound" ]] && is_x86_codegen_path "$path"; then
    scanned_review_counts[x86-codegen-fixed-bound]=$((${scanned_review_counts[x86-codegen-fixed-bound]:-0} + 1))
  fi
  if [[ "$classification" == "fixed-bound" ]] && is_wasm_codegen_path "$path"; then
    scanned_review_counts[wasm-codegen-fixed-bound]=$((${scanned_review_counts[wasm-codegen-fixed-bound]:-0} + 1))
  fi
  if [[ "$classification" == "fixed-bound" ]] && is_parser_path "$path"; then
    scanned_review_counts[parser-fixed-bound]=$((${scanned_review_counts[parser-fixed-bound]:-0} + 1))
  fi
  if [[ "$classification" == "fixed-bound" ]] && is_type_checker_path "$path"; then
    scanned_review_counts[type-checker-fixed-bound]=$((${scanned_review_counts[type-checker-fixed-bound]:-0} + 1))
  fi

  if [[ "$high_risk_only" == true && "$risk" != "high" ]]; then
    continue
  fi

  emitted_total=$((emitted_total + 1))
  emitted_class_counts[$classification]=$((${emitted_class_counts[$classification]:-0} + 1))
  emitted_risk_counts[$risk]=$((${emitted_risk_counts[$risk]:-0} + 1))
  emitted_component_counts[$component]=$((${emitted_component_counts[$component]:-0} + 1))
  emitted_component_risk_counts[$component_risk]=$((${emitted_component_risk_counts[$component_risk]:-0} + 1))
  emitted_reason_counts[$reason]=$((${emitted_reason_counts[$reason]:-0} + 1))
  emitted_paper_pass_counts[$paper_pass]=$((${emitted_paper_pass_counts[$paper_pass]:-0} + 1))
  emitted_rewrite_route_counts[$rewrite_route]=$((${emitted_rewrite_route_counts[$rewrite_route]:-0} + 1))
  emitted_reason_rewrite_route_counts[$reason_rewrite_route]=$((${emitted_reason_rewrite_route_counts[$reason_rewrite_route]:-0} + 1))
  emitted_component_reason_rewrite_route_counts[$component_reason_rewrite_route]=$((${emitted_component_reason_rewrite_route_counts[$component_reason_rewrite_route]:-0} + 1))
  emitted_component_paper_pass_counts[$component_paper_pass]=$((${emitted_component_paper_pass_counts[$component_paper_pass]:-0} + 1))
  emitted_pass_shape_counts[$pass_shape]=$((${emitted_pass_shape_counts[$pass_shape]:-0} + 1))
  emitted_component_pass_shape_counts[$component_pass_shape]=$((${emitted_component_pass_shape_counts[$component_pass_shape]:-0} + 1))
  emitted_audit_evidence_role_counts[$audit_evidence_role]=$((${emitted_audit_evidence_role_counts[$audit_evidence_role]:-0} + 1))
  emitted_audit_evidence_counts[$audit_evidence]=$((${emitted_audit_evidence_counts[$audit_evidence]:-0} + 1))
  emitted_component_audit_evidence_role_counts[$component_audit_evidence_role]=$((${emitted_component_audit_evidence_role_counts[$component_audit_evidence_role]:-0} + 1))
  emitted_component_audit_evidence_counts[$component_audit_evidence]=$((${emitted_component_audit_evidence_counts[$component_audit_evidence]:-0} + 1))
  if is_paper_pass_blocker "$paper_pass"; then
    emitted_review_counts[paper-pass-blocker]=$((${emitted_review_counts[paper-pass-blocker]:-0} + 1))
    emitted_component_paper_pass_blocker_counts[$component_paper_pass]=$((${emitted_component_paper_pass_blocker_counts[$component_paper_pass]:-0} + 1))
    emitted_component_rewrite_route_blocker_counts[$component_rewrite_route]=$((${emitted_component_rewrite_route_blocker_counts[$component_rewrite_route]:-0} + 1))
  else
    emitted_review_counts[paper-pass-local-review]=$((${emitted_review_counts[paper-pass-local-review]:-0} + 1))
    emitted_component_paper_pass_local_review_counts[$component_paper_pass]=$((${emitted_component_paper_pass_local_review_counts[$component_paper_pass]:-0} + 1))
    emitted_component_rewrite_route_local_review_counts[$component_rewrite_route]=$((${emitted_component_rewrite_route_local_review_counts[$component_rewrite_route]:-0} + 1))
  fi
  if has_loop_hint_attr "$loop_attr"; then
    emitted_review_counts[loop-attribute]=$((${emitted_review_counts[loop-attribute]:-0} + 1))
    if has_unroll_attr "$loop_attr"; then
      emitted_review_counts[unroll-attribute]=$((${emitted_review_counts[unroll-attribute]:-0} + 1))
    fi
    if is_suspicious_loop_attr "$classification" "$reason"; then
      emitted_review_counts[suspicious-loop-attribute]=$((${emitted_review_counts[suspicious-loop-attribute]:-0} + 1))
      if has_unroll_attr "$loop_attr"; then
        emitted_review_counts[suspicious-unroll-attribute]=$((${emitted_review_counts[suspicious-unroll-attribute]:-0} + 1))
      fi
    fi
  fi
  if ! has_loop_hint_attr "$loop_attr" && is_for_header "$header"; then
    emitted_review_counts[raw-for-loop]=$((${emitted_review_counts[raw-for-loop]:-0} + 1))
    if is_raw_for_review_required "$classification" "$header" "$loop_attr"; then
      emitted_review_counts[raw-for-review-required]=$((${emitted_review_counts[raw-for-review-required]:-0} + 1))
    fi
  fi
  if [[ -n "$cap" ]]; then
    emitted_review_counts[explicit-fixed-literal-bound]=$((${emitted_review_counts[explicit-fixed-literal-bound]:-0} + 1))
    if is_bounded_explicit_literal_candidate "$classification" "$cap"; then
      emitted_review_counts[bounded-explicit-literal-candidate]=$((${emitted_review_counts[bounded-explicit-literal-candidate]:-0} + 1))
    fi
  fi
  if is_source_sized_symbolic_cap "$symbolic_cap"; then
    symbolic_cap_route="$(source_sized_symbolic_cap_route "$symbolic_cap")"
    component_symbolic_cap_route="${component}:${symbolic_cap_route}"
    component_symbolic_cap_path_route="${component}:${symbolic_cap}:${path}:${symbolic_cap_route}"
    emitted_review_counts[source-sized-symbolic-cap]=$((${emitted_review_counts[source-sized-symbolic-cap]:-0} + 1))
    emitted_component_source_sized_symbolic_cap_counts[$component]=$((${emitted_component_source_sized_symbolic_cap_counts[$component]:-0} + 1))
    emitted_source_sized_symbolic_cap_name_counts[$symbolic_cap]=$((${emitted_source_sized_symbolic_cap_name_counts[$symbolic_cap]:-0} + 1))
    emitted_source_sized_symbolic_cap_route_counts[$symbolic_cap_route]=$((${emitted_source_sized_symbolic_cap_route_counts[$symbolic_cap_route]:-0} + 1))
    emitted_component_source_sized_symbolic_cap_route_counts[$component_symbolic_cap_route]=$((${emitted_component_source_sized_symbolic_cap_route_counts[$component_symbolic_cap_route]:-0} + 1))
    emitted_component_source_sized_symbolic_cap_path_route_counts[$component_symbolic_cap_path_route]=$((${emitted_component_source_sized_symbolic_cap_path_route_counts[$component_symbolic_cap_path_route]:-0} + 1))
    if is_parser_path "$path"; then
      emitted_review_counts[parser-source-sized-symbolic-cap]=$((${emitted_review_counts[parser-source-sized-symbolic-cap]:-0} + 1))
    fi
    if is_type_checker_path "$path"; then
      emitted_review_counts[type-checker-source-sized-symbolic-cap]=$((${emitted_review_counts[type-checker-source-sized-symbolic-cap]:-0} + 1))
    fi
  fi
  if is_pass_contract_review "$classification" "$reason" "$header" "$loop_attr"; then
    emitted_review_counts[pass-contract-review]=$((${emitted_review_counts[pass-contract-review]:-0} + 1))
  fi
  if is_large_fixed_bound_reason "$reason"; then
    emitted_review_counts[large-fixed-bound]=$((${emitted_review_counts[large-fixed-bound]:-0} + 1))
    if is_codegen_path "$path"; then
      emitted_review_counts[codegen-large-fixed-bound]=$((${emitted_review_counts[codegen-large-fixed-bound]:-0} + 1))
    fi
    if is_wasm_codegen_path "$path"; then
      emitted_review_counts[wasm-codegen-large-fixed-bound]=$((${emitted_review_counts[wasm-codegen-large-fixed-bound]:-0} + 1))
    fi
    if is_x86_codegen_path "$path"; then
      emitted_review_counts[x86-codegen-large-fixed-bound]=$((${emitted_review_counts[x86-codegen-large-fixed-bound]:-0} + 1))
    fi
    if is_parser_path "$path"; then
      emitted_review_counts[parser-large-fixed-bound]=$((${emitted_review_counts[parser-large-fixed-bound]:-0} + 1))
    fi
    if is_type_checker_path "$path"; then
      emitted_review_counts[type-checker-large-fixed-bound]=$((${emitted_review_counts[type-checker-large-fixed-bound]:-0} + 1))
    fi
  fi
  case "$classification" in
    data-dependent|while-loop|unknown-bound)
      emitted_review_counts[review-required]=$((${emitted_review_counts[review-required]:-0} + 1))
      if is_codegen_path "$path"; then
        emitted_review_counts[codegen-review-required]=$((${emitted_review_counts[codegen-review-required]:-0} + 1))
      fi
      if is_wasm_codegen_path "$path"; then
        emitted_review_counts[wasm-codegen-review-required]=$((${emitted_review_counts[wasm-codegen-review-required]:-0} + 1))
      fi
      if is_x86_codegen_path "$path"; then
        emitted_review_counts[x86-codegen-review-required]=$((${emitted_review_counts[x86-codegen-review-required]:-0} + 1))
      fi
      if is_parser_path "$path"; then
        emitted_review_counts[parser-review-required]=$((${emitted_review_counts[parser-review-required]:-0} + 1))
      fi
      if is_type_checker_path "$path"; then
        emitted_review_counts[type-checker-review-required]=$((${emitted_review_counts[type-checker-review-required]:-0} + 1))
      fi
      ;;
  esac
  if [[ "$classification" == "fixed-bound" ]] && is_x86_codegen_path "$path"; then
    emitted_review_counts[x86-codegen-fixed-bound]=$((${emitted_review_counts[x86-codegen-fixed-bound]:-0} + 1))
  fi
  if [[ "$classification" == "fixed-bound" ]] && is_wasm_codegen_path "$path"; then
    emitted_review_counts[wasm-codegen-fixed-bound]=$((${emitted_review_counts[wasm-codegen-fixed-bound]:-0} + 1))
  fi
  if [[ "$classification" == "fixed-bound" ]] && is_parser_path "$path"; then
    emitted_review_counts[parser-fixed-bound]=$((${emitted_review_counts[parser-fixed-bound]:-0} + 1))
  fi
  if [[ "$classification" == "fixed-bound" ]] && is_type_checker_path "$path"; then
    emitted_review_counts[type-checker-fixed-bound]=$((${emitted_review_counts[type-checker-fixed-bound]:-0} + 1))
  fi

  if [[ "$summary_only" != true ]]; then
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$classification" \
      "$risk" \
      "$path" \
      "$line" \
      "$context" \
      "$reason" \
      "$header" \
      "$loop_flags"
  fi
done < <(scan_loop_headers)

if [[ "$show_summary" == true ]]; then
  print_summary_rows scanned
  if [[ "$high_risk_only" == true ]]; then
    print_summary_rows emitted
  fi
fi

if [[ "$fail_on_data_dependent" == true && "$bad_count" -gt 0 ]]; then
  printf 'shader_loop_audit: %s loop(s) require paper-alignment review\n' "$bad_count" >&2
  exit 1
fi

if [[ "$fail_on_large_fixed_bound" == true && "${scanned_review_counts[large-fixed-bound]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s large fixed-bound loop(s) require paper-alignment review\n' "${scanned_review_counts[large-fixed-bound]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_paper_pass_blocker" == true && "${scanned_review_counts[paper-pass-blocker]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s loop(s) require non-local paper/Pareas pass rewrite\n' "${scanned_review_counts[paper-pass-blocker]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_codegen_large_fixed_bound" == true && "${scanned_review_counts[codegen-large-fixed-bound]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s codegen large fixed-bound loop(s) require paper-alignment review\n' "${scanned_review_counts[codegen-large-fixed-bound]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_x86_codegen_large_fixed_bound" == true && "${scanned_review_counts[x86-codegen-large-fixed-bound]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s x86 codegen large fixed-bound loop(s) require paper-alignment review\n' "${scanned_review_counts[x86-codegen-large-fixed-bound]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_wasm_codegen_large_fixed_bound" == true && "${scanned_review_counts[wasm-codegen-large-fixed-bound]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s WASM codegen large fixed-bound loop(s) require paper-alignment review\n' "${scanned_review_counts[wasm-codegen-large-fixed-bound]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_parser_large_fixed_bound" == true && "${scanned_review_counts[parser-large-fixed-bound]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s parser large fixed-bound loop(s) require paper-alignment review\n' "${scanned_review_counts[parser-large-fixed-bound]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_type_checker_large_fixed_bound" == true && "${scanned_review_counts[type-checker-large-fixed-bound]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s type-checker large fixed-bound loop(s) require paper-alignment review\n' "${scanned_review_counts[type-checker-large-fixed-bound]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_x86_codegen_review_required" == true && "${scanned_review_counts[x86-codegen-review-required]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s x86 codegen loop(s) require paper-alignment review\n' "${scanned_review_counts[x86-codegen-review-required]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_wasm_codegen_review_required" == true && "${scanned_review_counts[wasm-codegen-review-required]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s WASM codegen loop(s) require paper-alignment review\n' "${scanned_review_counts[wasm-codegen-review-required]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_parser_review_required" == true && "${scanned_review_counts[parser-review-required]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s parser loop(s) require paper-alignment review\n' "${scanned_review_counts[parser-review-required]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_type_checker_review_required" == true && "${scanned_review_counts[type-checker-review-required]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s type-checker loop(s) require paper-alignment review\n' "${scanned_review_counts[type-checker-review-required]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_parser_source_sized_symbolic_cap" == true && "${scanned_review_counts[parser-source-sized-symbolic-cap]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s parser source-sized symbolic cap loop(s) require bounded-helper justification or rewrite\n' "${scanned_review_counts[parser-source-sized-symbolic-cap]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_type_checker_source_sized_symbolic_cap" == true && "${scanned_review_counts[type-checker-source-sized-symbolic-cap]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s type-checker source-sized symbolic cap loop(s) require bounded-helper justification or rewrite\n' "${scanned_review_counts[type-checker-source-sized-symbolic-cap]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_suspicious_loop_attr" == true && "${scanned_review_counts[suspicious-loop-attribute]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s [loop]/[unroll] annotation(s) require paper-alignment review\n' "${scanned_review_counts[suspicious-loop-attribute]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_raw_for_review_required" == true && "${scanned_review_counts[raw-for-review-required]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s raw for-loop(s) require paper-alignment review\n' "${scanned_review_counts[raw-for-review-required]:-0}" >&2
  exit 1
fi

if [[ "$fail_on_source_sized_symbolic_cap" == true && "${scanned_review_counts[source-sized-symbolic-cap]:-0}" -gt 0 ]]; then
  printf 'shader_loop_audit: %s source-sized symbolic cap loop(s) require bounded-helper justification or rewrite\n' "${scanned_review_counts[source-sized-symbolic-cap]:-0}" >&2
  exit 1
fi
