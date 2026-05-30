# x86_64 GPU Backend Wiring Plan

This plan advances the `stdlib/PLAN.md` native-output row while preserving the
current no-CPU-fallback objective. The target is GPU-only x86_64 ELF emission:
after source read, all frontend analysis, lowering, register allocation,
instruction sizing, relocation-record publication, branch/call displacement
handling, ELF layout, byte packing, and final binary byte production happen in
GPU passes over GPU-resident compiler data. Explicit relocation records now
exist in the active backend; `x86_reloc_patch` consumes them after byte
encoding and before ELF layout, while broader object/interface relocation
records for separate compilation remain future work.

## Current Evidence

The prior WASM-to-x86 prototype has been deleted instead of kept as an unwired
parallel backend. It was not a valid path toward the objective because it
depended on WASM-shaped intermediate bytes and did not prove direct native
emission from GPU-resident compiler data.

- `src/codegen/mod.rs` exports `x86`, and that module is the LL(1)
  HIR-to-ELF backend, not the old WASM translation prototype.
- `src/codegen/x86.rs` defines `GpuX86CodeGenerator`,
  `record_x86_elf_from_gpu_hir`, and `finish_recorded_x86` for the first direct
  GPU slice. The old `record_x86_from_gpu_token_buffer` surface is gone.
- `shaders/codegen/x86_from_wasm.slang` is absent. No compiler-facing x86 path
  consumes `body_words`, `bool_body_words`, or `functions_words`.
- `shaders/codegen/x86_func_discover.slang` records backend function metadata
  from GPU HIR function nodes and GPU `fn_entrypoint_tag` records produced
  from compiler-owned language declarations, including the current `main` span.
  It no longer discovers the entrypoint by source text, and it no longer seeds
  provisional token-derived function slots; the dense function-slot relation is
  owned by the later flag/scan/scatter compaction pass.
- `shaders/codegen/x86_node_inst_counts.slang` and
  `shaders/codegen/x86_node_inst_gen.slang` consume HIR, resolver, type,
  literal, declaration-layout, call, argument-prefix, and match records to
  produce node-local virtual instruction rows. They do not rediscover source
  shapes through token spelling or body-pattern scans.
- Branch padding comes from GPU-produced `x86_node_control_padding` rows keyed
  by child node; padding is additive when a node participates in multiple
  control contexts. Postfix/unary ownership comes from
  `x86_postfix_operand_owner`, keyed by operand node with owning postfix node.
  `x86_node_inst_counts.slang` no longer binds `x86_tree_parent`; parent and
  subtree arrays are reserved for dedicated pointer-jump / ordering passes, not
  carried through node-count payloads. Return-match and let-initializer
  aggregate destinations now fail closed through materialized ownership
  relations plus exact resolved expression identity instead of subtree
  containment.
  `x86_match_ownership.slang` likewise consumes match, return-match, and
  resolved-expression records directly rather than binding tree parent/subtree
  rows.
  The remaining bounded record consumers are not source-text recognizers, but
  they are not the final paper-aligned shape; the replacement is explicit
  owner/path relations.
- `shaders/codegen/x86_for_iterable_nodes.slang` dispatches over `for`
  statement records, reads the parser-owned iterable HIR path node directly
  from `hir_stmt_record`, and publishes `x86_for_iterable_node[for_node]`
  without probing parents, scanning source text, or re-keying through
  token-start lookup tables.
- `shaders/codegen/x86_node_inst_gen_inputs.slang` condenses upstream backend
  status rows before virtual-instruction generation, keeping the generator under
  the GPU storage-buffer binding limit while preserving explicit failure
  propagation.
- `shaders/codegen/x86_enclosing_loop_init.slang` and
  `shaders/codegen/x86_enclosing_loop_step.slang` materialize nearest enclosing
  loop nodes with pointer jumping, so break/continue lowering reads a table
  instead of walking parent chains inside instruction generation.
- `shaders/codegen/x86_expr_resolve_init.slang` and
  `shaders/codegen/x86_expr_resolve_step.slang` materialize a GPU-resident
  resolved-expression table for legacy HIR forward-node consumers with pointer
  jumping. New expression-root consumers read the parser-owned
  `hir_expr_result_root_node` relation when it is already available at their
  pass point.
- `shaders/codegen/x86_expr_semantic_type_init.slang`,
  `shaders/codegen/x86_call_records.slang`, and
  `shaders/codegen/x86_const_values.slang` consume that parser-owned expression
  root row directly for semantic-type, call-callee, and const-literal
  projection instead of carrying local `HIR_EXPR_FORWARD` resolution logic.
- `shaders/codegen/x86_postfix_operand_owner.slang` also consumes
  `hir_expr_result_root_node` directly when scattering postfix operand-owner
  rows, so postfix/unary ownership no longer depends on the backend-local
  resolved-expression table.
- `shaders/codegen/x86_match_pattern_owner_init.slang` and
  `shaders/codegen/x86_match_pattern_owner_step.slang` materialize nearest
  match-pattern owner records with Pareas-style parent-link pointer jumping.
  Match-pattern classification consumes `x86_match_pattern_node_owner` instead
  of walking parent chains per node.
- `shaders/codegen/x86_enclosing_return_init.slang` and
  `shaders/codegen/x86_enclosing_return_step.slang` materialize nearest
  enclosing return-statement records with the same pointer-jump pattern.
  `x86_return_match_records.slang` then materializes direct
  return-statement/match-expression rows from parser-owned return statement
  records and resolved expression nodes. Match ownership and later x86 stages
  consume that table and validate it by exact resolved return-expression
  identity rather than HIR subtree containment. This is still a bounded
  two-arm match lowering path rather than final general match lowering.
- `shaders/codegen/x86_node_inst_counts.slang` and
  `shaders/codegen/x86_node_inst_gen.slang` treat enum value records as supported
  only when the producer-published row has a valid ordinal and the active x86
  shape is exact: unit constructors have no payload and call constructors have
  one payload. Wider enum constructor rows fail closed before virtual
  instruction planning can count them as supported values.
- `shaders/codegen/x86_enclosing_let_init.slang` and
  `shaders/codegen/x86_enclosing_let_step.slang` materialize nearest enclosing
  let-statement records with the same pointer-jump pattern. Aggregate
  destination lowering reads those records plus the resolved let-initializer
  node and fails closed unless they match exactly, instead of accepting any HIR
  subtree-span containment inside instruction generation.
- `shaders/codegen/x86_enclosing_stmt_init.slang` and
  `shaders/codegen/x86_enclosing_stmt_step.slang` materialize nearest HIR
  statement wrapper records with the same pointer-jump pattern. Intrinsic-call
  projection reads this table instead of walking parent chains.
- The backend carries an explicit per-run virtual/native instruction capacity
  through `X86Params`/`X86ScanParams`; shader stages fail closed against that
  capacity instead of assuming every program owns the global 65k instruction
  ceiling.
- `shaders/codegen/x86_feature_counts.slang` now measures conservative scalar
  instruction capacity directly from HIR node-kind and record rows. It no
  longer walks bounded parent chains before the real x86 function-ownership
  records exist, so deep but valid function subtrees cannot be undercounted by a
  pre-sizing heuristic. Control-flow padding is counted from the owning
  statement's parser-owned `hir_stmt_record` slots, including `for` iterable and
  body slots, rather than by reclassifying child nodes through parent or token
  position probes.
- `shaders/codegen/x86_virtual_liveness.slang` reads virtual instruction
  operand records directly and atomically extends value-def live intervals,
  matching Pareas's instruction-stream register-allocation shape without
  materializing a separate def-use edge table. Mixed-call operand records now
  fail closed if they claim more arguments than the four packed ABI slots, so
  liveness cannot truncate a malformed call row to the first four operands.
- The older `x86_virtual_use_counts` / `x86_virtual_use_edges` prefix-scan and
  scatter path is currently unwired, so it is not active backend evidence. The
  active liveness path is direct operand-record liveness; any future def-use
  edge table must be wired explicitly after virtual row generation and before
  the liveness/regalloc consumers that need it.
- `shaders/codegen/x86_virtual_next_calls.slang` materializes a suffix-scanned
  nearest-call row per virtual instruction row inside the same function segment.
  The suffix scan validates `x86_virtual_func_slot` against the backend
  function-slot capacity, not token capacity, and marks the pass failed if an
  active virtual row lacks a valid GPU-computed function slot.
- `shaders/codegen/x86_virtual_param_masks.slang` scatters incoming parameter
  register masks per function from virtual `PARAM` rows, so register allocation
  does not scan each function just to recover ABI parameter registers.
- `shaders/codegen/x86_virtual_regalloc.slang` consumes compact GPU
  value-definition rows, virtual live intervals, nearest-call rows, and
  parameter-mask relations, then assigns physical registers from backend
  records. The old fixed token-index register map over `visible_decl` remains
  deleted. Fixed register-rank availability now uses direct bit/table rows
  instead of per-rank shader loops. The remaining bounded value-definition chunk
  loop is the current serial linear-scan scheduling boundary. It mutates
  per-function active register-end state and the remaining parameter-register
  mask as loop-carried state, so a simple one-thread-per-row split would race
  rather than become a Pareas-style map/scatter pass. It fails closed when the
  compact value-definition stream needs chunks outside the GPU-recorded
  active-chunk span, when a dynamic register-allocation chunk is not aligned to
  the recorded fixed row count, or when the discovered function set exceeds the
  recorded function-slot slice. That prevents partial allocation from implying a
  CPU-scale fallback. The host x86 backend also exposes
  `x86_regalloc_pass_contract()` and capacity-trace counters for
  `loop_status=bounded`, `fallback_status=fail-closed`, and
  `claim_status=blocked`, so measurement artifacts cannot treat the current
  allocator as an unbounded paper-aligned pass by omission. Host capacity trace
  counters also mark the current control-flow bridge
  `bounded`/`fail-closed`/`blocked` and record the pointer-jump widths for
  same-end placement, loop ownership, short-circuit RHS ownership, and index
  source ownership before virtual instruction generation. The replacement should
  partition value-definition rows by allocation region, compose state with
  segmented scan/prefix-style records, or publish explicit pressure/spill rows
  before selection. The current x86 audit found no remaining
  executable-function gates that use bare `HIR_FN`; all function discovery,
  owner-scan, assignment, and slot-compaction seeds require `HIR_ITEM_KIND_FN`.
  The only shader `for` loop in the x86 codegen surface is this
  register-allocation chunk loop, and no existing prefix/scan/scatter table
  carries the loop-carried active-register and parameter-mask state it mutates.
- `shaders/codegen/x86_select.slang` consumes allocated virtual instruction
  records and scatters fixed-width x86 instruction records plus GPU target
  indices consumed by byte sizing/encoding. The deleted planning shaders no
  longer materialize source-shape-specific rows before selection.
- `x86_select` now also requires each non-padding virtual instruction row to
  carry a valid GPU-computed function slot before it can select native
  instruction records, so malformed ownership records fail closed through
  `X86_ERR_SELECT` instead of reaching byte encoding.
- Virtual row locations are checked against the exact prefix-summed virtual
  instruction total, not just the allocation capacity. Mixed direct-call
  selection now also validates that the callee target row has a function slot
  and that the packed argument-payload row belongs to the same call node/function
  record, so stale location or payload records fail closed before byte sizing.
- `shaders/codegen/x86_virtual_value_def_flags.slang` is the explicit resident
  optimization boundary between intermediate virtual-instruction generation and
  machine-code generation. It consumes liveness records, preserves
  side-effecting value definitions, and suppresses pure value definitions that
  have no later use. Register-allocation compaction consumes this same flag
  table, and `x86_select` emits zero-size selected rows for optimized-away
  virtual rows. This is deliberately a narrow single-pass dead-value
  optimization, not a claimable broad optimizer.
- `shaders/codegen/x86_inst_size.slang` computes variable-width instruction
  sizes for those records. It also validates selected branch, jump, call, and
  entry-jump targets against the prefix-summed instruction stream before byte
  offsets are consumed, so a stale control-transfer record fails closed in
  sizing rather than indexing an invalid target during encoding.
- `shaders/codegen/x86_text_offsets.slang` computes instruction byte offsets
  and the current `.text` length from the GPU-produced size records. It also
  validates that the prefix-summed byte ranges are contiguous and contained in
  the final text length before encoding can consume them.
- `shaders/codegen/x86_reloc_scan_local.slang` and
  `shaders/codegen/x86_reloc_records.slang` now run after byte-offset
  generation and before byte encoding. They scan selected branch/jump/call rows
  into compact GPU relocation records (`kind`, `site_inst`, `target_inst`) and
  publish `reloc_status`, so the jump-linking boundary has a fail-closed record
  artifact instead of being only encoder-local target discovery.
- `shaders/codegen/x86_encode.slang` consumes compact instruction records plus
  byte offsets and scatters instruction bytes into packed `.text` words. It no
  longer binary-searches instruction offsets per output byte; emission is
  ordered after a GPU clear of the output words, so byte-lane atomic OR is safe.
  It fails closed on wrapped `.text`/file-length arithmetic before calculating
  output ranges, and it refuses to encode if relocation-record publication did
  not succeed.
- `shaders/codegen/x86_reloc_patch.slang` runs after encoding and before ELF
  layout. Encoding leaves zero rel32 placeholders; the patch pass traverses
  compact relocation rows directly, validates target/kind consistency, and
  atomically scatters rel32 bytes into packed output words so adjacent
  relocations can share an output word without races.
- `shaders/codegen/x86_elf_layout.slang` computes the ELF text/file layout from
  the encoded text length.
- `shaders/codegen/x86_elf_write.slang` consumes the encoded `.text` bytes and
  GPU-produced layout records, then directly emits final packed ELF64 bytes.
- `src/compiler.rs` has WASM wiring through
  `record_wasm_from_gpu_token_buffer` and x86 wiring through
  `record_x86_elf_from_gpu_hir`. `GpuCompiler` has separate `wasm_generator` and
  `x86_generator` caches.
- `compile_source_to_x86_64_with_gpu_codegen`,
  `compile_source_to_x86_64_with_gpu_codegen_from_path`, and the explicit
  source-pack x86 entrypoints now route through GPU lexer, GPU LL(1) HIR, GPU
  type checking, and the direct GPU x86 emitter for the bounded scalar
  main-return slice. The source-pack route proves that supplied modules can flow
  through the native path while `main` uses the existing scalar return shape,
  and can now lower one resolver-backed module-qualified scalar constant
  arithmetic return plus one resolver-backed module-qualified direct call.
  Direct calls lower through resolver-owned callee ids, call ABI records,
  node-local virtual instruction rows, liveness, register allocation, and
  selection; they must not reintroduce whole-callee body recognizers for helper
  functions. A small executable
  `while`/scalar-local-mutation case now covers loop ownership, assignment
  lowering, branch layout, liveness/regalloc, ELF emission, and process exit.
  Package imports are still not loaded by the host.
- The CLI now routes explicit `--stdlib`/input source-pack file lists to the
  same direct GPU x86 source-pack entrypoint. This is still an explicit file-list
  surface; it does not discover imports, walk directories, concatenate sources,
  or run a host parser/typechecker.
- `tests/codegen_x86.rs` locks this behavior: missing file errors must happen
  before codegen, direct ELF bytes are emitted for scalar programs, a small
  `while`/scalar-local-mutation program exits with the expected value, a
  bounded scalar-op program executes division, modulo, bitwise, and shift
  expression rows through native output,
  `while` program with `break`/`continue` and an array `for` program with
  `break`/`continue` execute through native control-flow output, local-array
  indexed assignments execute through native indexed store output, struct
  aggregate parameters can be passed to helpers and read through member loads, a
  bool-returning helper can feed a native branch condition, a four-argument
  direct call with mixed local/expression/literal argument sources executes
  through the packed call-ABI path in both single-source and source-pack
  imported-helper programs, an imported helper can return a bounded aggregate
  array through the native call ABI for local indexing, and a
  five-argument direct call fails through a source-spanned x86 diagnostic. The
  old WASM translation prototype files must remain absent.
- Missing `main` now fails through x86 entry selection as source-spanned
  `LNC0017` with `missing main entrypoint` instead of falling through to a
  generic selection failure. The diagnostic anchors to the source when no
  entrypoint token exists; real package entrypoint discovery remains future
  work.
- The x86 executable tests now validate a public ELF64 artifact contract beyond
  the magic bytes: the program-header table must fit in the returned bytes, load
  segment file ranges must fit the file, and the entry point must map into an
  executable `PT_LOAD` segment.
- The SysV call ABI projection now leaves ABI rows absent for non-direct
  callees and for direct calls that fail bounded ABI checks, so later
  node-local virtual instruction generation cannot accidentally consume a
  partial direct-call record after a fail-closed diagnostic has been published.
  The virtual-instruction generator also revalidates both words of the ABI row,
  the target function node, the packed argument count, and nonzero return width
  before treating a row as supported, so a stale half-written bounded record
  cannot imply call support.
- `tests/codegen_x86_properties.rs` adds record-first x86 evidence without
  checking private helper names or backend source strings: generated executable
  programs with helper-like names versus renamed functions must both execute the
  resolver target's body semantics, including imported callees that combine
  array parameters, loop-carried locals, nested arithmetic, branch-local
  updates, and local-dependent call-argument expression nodes. The generated
  fail-closed cases also exercise loop-contained calls through assignment and
  `let`-initializer statement consumers plus postfix increment/decrement
  rejection, proving those diagnostic boundaries are not tied to one source
  statement spelling. The same property file also treats the current
  register-allocation chunk span as a bounded backend contract: generated
  straight-line value-definition chains with different binding names must fail
  closed instead of returning fallback ELF bytes when they exceed the recorded
  allocator chunk coverage.
- Calls inside loop subtrees are an explicit fail-closed x86 boundary:
  `x86_node_inst_gen` reads the GPU-resident nearest-enclosing-loop table and
  reports source-spanned `LNC0017` as `unsupported x86 loop-contained call`
  before lowering. Statement value consumers also check resolved call nodes
  against the same loop-owner table before falling back to generic assignment,
  let, return, or branch failures, so loop-condition, loop-body assignment, and
  loop-local let-initializer calls now fail at the call token without adding a
  helper-name, source-text, or whole-function recognizer. Implementing calls in
  loop conditions, loop-carried assignments, and loop bodies remains required
  before those programs can become executable x86 tests.
- Postfix expressions are now a GPU-written fail-closed x86 boundary:
  `x86_node_inst_counts` rejects `HIR_POSTFIX_EXPR` rows with source-spanned
  `LNC0017` as `unsupported x86 postfix expression` before prefix-summed
  instruction ranges can treat them as zero-instruction no-ops. Property
  coverage checks both increment and decrement forms through diagnostic behavior
  rather than source-line spelling. Real `++`/`--` lowering still needs explicit
  read/modify/write virtual instruction rows.
- Unsupported prefix/unrecorded unary expressions are now the matching
  GPU-written fail-closed x86 boundary: `x86_node_inst_counts` rejects
  `HIR_UNARY_EXPR` rows whose parser-owned `hir_expr_record` form is absent
  with source-spanned `LNC0017` as `unsupported x86 unary expression` before a
  prefix update such as `++local` can become a zero-instruction no-op. Real
  support needs explicit read/modify/write virtual rows from parser-owned unary
  operator records.
- Non-return match expressions are now a GPU-written fail-closed x86 boundary:
  `x86_node_inst_counts` rejects `HIR_MATCH_EXPR` rows outside the currently
  supported return-position match lowering with source-spanned `LNC0017` as
  `unsupported x86 match expression` before later virtual-instruction emission
  can report a generic source shape.
- Local-array indexed assignments now execute through GPU-produced array and
  index records: `x86_node_inst_gen` lowers `HIR_INDEX_EXPR` assignment targets
  to `STORE_LOCAL_INDEX` virtual rows, liveness treats both the index and RHS as
  operands, and instruction selection/encoding writes an indexed local-memory
  store. Unsupported indexed assignment targets still fail closed through the
  backend status row instead of falling through to generic assignment lowering.
- Statically known out-of-bounds array indexes are now a GPU-written
  fail-closed x86 boundary: `x86_node_inst_gen` rejects literal and
  resolver-backed const atom indexes outside the aggregate width with
  source-spanned `LNC0017` as
  `unsupported x86 array index bounds` before native indexed stack access is
  emitted. Local literal names and shaped index expressions now flow through
  ordinary virtual value/register rows and the native runtime bounds check
  instead of being rediscovered as a function-body/static-proof shape.
- Aggregate-parameter member assignment is now an explicit GPU-written
  fail-closed boundary: `x86_node_inst_gen` reads the member-access record plus
  aggregate source records, accepts local aggregate fields as writable slots, and
  reports source-spanned `LNC0017` as
  `unsupported x86 parameter aggregate assignment` for parameter-backed members.
  Real support needs writable parameter-copy or by-reference aggregate storage
  rows before a member write can become executable output.
- Aggregate-parameter indexed assignment is now the matching GPU-written
  fail-closed boundary for array-style aggregate parameters: `x86_node_inst_gen`
  reads the index expression plus aggregate source records, accepts only local
  aggregate slots as writable indexed stores, and reports source-spanned
  `LNC0017` as `unsupported x86 parameter aggregate indexed assignment` for
  parameter-backed indexed targets. Real support needs the same writable
  parameter-copy or by-reference aggregate storage rows before indexed parameter
  writes can become executable output.
- Aggregate-return temporary member reads are now a GPU-written fail-closed
  boundary: `x86_node_inst_counts` rejects member expressions whose receiver is
  not a named local or parameter aggregate source with source-spanned `LNC0017`
  as `unsupported x86 aggregate temporary member`, and a small `pair().left`
  fixture covers the aggregate-return case without a timeout. Real support
  still needs aggregate return temporaries materialized as explicit slots or
  value rows that member loads can consume. Nested aggregate-valued member
  receivers (`outer.inner.left`) remain future work and should not be revived as
  timeout-heavy aggregate-temporary tests.
- Struct-literal local sizing/layout now consumes parser-owned
  `hir_struct_lit_head_node` through backend `x86_struct_access_record` aliases,
  so declaration width/layout projection no longer probes sibling/child tree
  shape to rediscover the literal behind a head expression.
- Struct- and array-literal local store ownership now require the let
  initializer's resolved expression record to be exactly the aggregate literal
  node. Nested aggregate ownership intentionally fails closed until an explicit
  aggregate owner/path record exists; it is not inferred from subtree spans.
- Aggregate-literal return copy remains record-driven: array element records and
  struct literal field records scatter directly into the enclosing return range.
  The compact copy pass now also fails closed if a stale or over-wide record
  presents an ordinal beyond the current 32-element row cap, publishing the same
  aggregate-return width status detail instead of silently dropping that element.
- Divisor safety is now a GPU-written fail-closed x86 boundary:
  `x86_node_inst_gen` rejects division and modulo expressions or compound
  assignments whose RHS is zero, or whose RHS is not a literal or
  resolver-backed immutable scalar atom. The previous one-level unary/binary
  expression proof is intentionally gone; shaped RHS expressions now fail closed
  until trap-check lowering exists as explicit virtual instruction rows. Mutable
  local literal records are not accepted as either zero or nonzero divisor proof
  because later assignments can make the original initializer stale. Known
  nonzero RHS atoms other than signed `-1` are accepted. Known zero RHS atoms
  report
  source-spanned `LNC0017` as
  `unsupported x86 zero divisor`; dynamic RHS values and known `-1` RHS values
  report `unsupported x86 dynamic divisor` before native `idiv` can fault on
  zero or signed-overflow cases. General runtime divisor checks still need real
  panic/trap lowering.
- Shift counts now lower through ordinary node-local virtual binary
  instructions and native selection adds a byte-level unsigned `< 32` runtime
  trap before `shl`/`sar` can observe x86's masked count behavior. This keeps
  dynamic `<<`, `>>`, `<<=`, and `>>=` in the HIR/virtual-instruction pipeline
  instead of recognizing a source shape or relying on static proof. The current
  trap is still a tiny process-exit boundary, not the final language panic
  model.
- Virtual-instruction generation now checks each emitted row against the
  GPU-computed subtree instruction bounds before writing `x86_virtual_inst_*`.
  This keeps branch/loop rows allowed in child padding slots while rejecting a
  stale or corrupted prefix/location record before selection can consume it.
  `tests/codegen_x86.rs` can enable the public x86 status trace and assert that
  node-local count rows, prefix-summed range rows, corrected locations, virtual
  rows, liveness, and register allocation publish matching GPU row counts for a
  small loop program.
- Non-array `for` iterables are now a GPU-written fail-closed x86 boundary:
  `x86_node_inst_counts` rejects unsupported iterable layout records before
  child expression lowering can report a generic virtual-instruction error, and
  `x86_node_inst_gen` keeps the same boundary for stale records with
  source-spanned `LNC0017` instead of falling through to the generic
  virtual-instruction error. The earlier two-field-struct interval shortcut is
  gone because width alone is not an iterable/range contract. Scalar and struct
  `for`-iterable execution still require real iterable records before they can
  become executable support.
- Nested `while`/`for` loops are now a GPU-written fail-closed x86 boundary:
  `x86_node_inst_gen` reads the materialized nearest-enclosing-loop table and
  rejects loop nodes that already have a loop owner before branch rows can be
  emitted for a shape the current native loop layout does not support.
- Calls in the RHS operand of `&&`/`||` are now a GPU-written fail-closed x86
  boundary: `x86_node_inst_gen` rejects the resolved RHS call node with
  source-spanned `LNC0017` as `unsupported x86 short-circuit call operand`
  before the eager binary-op lowering can produce wrong short-circuit
  semantics. Real support needs conditional RHS blocks and call rows wired
  through prefix-summed instruction ranges, not token spelling or function-body
  recognizers.
- Calls nested one expression level inside the RHS operand of `&&`/`||`, such as
  a direct call inside a comparison, now fail through the same GPU-written
  source-spanned `LNC0017` boundary before the call row can be eagerly emitted.
- The backend now materializes a `&&`/`||` RHS-owner relation with
  Pareas-style parent-link pointer jumping before virtual instruction
  generation. Calls at any supported HIR depth under that RHS owner fail
  through the same source-spanned boundary without fixed-depth parent probes in
  `x86_node_inst_gen`. Real support still needs conditional RHS blocks and
  call rows wired through prefix-summed instruction ranges.
- Division, modulo, shift expressions, and dynamic aggregate indexes under a
  `&&`/`||` RHS owner now also fail closed when the trap-sensitive operand
  cannot be proven statically safe. This uses the same GPU-owned RHS relation,
  so eager evaluation is rejected before ordinary virtual-instruction lowering
  without source-text or fixed-depth parent recognizers. Only literal/path/const
  atom evidence is accepted as statically safe here; shaped arithmetic and local
  literal records fail closed until conditional RHS blocks plus runtime
  trap/range checks exist.

For primitive stdlib helper execution, x86_64 is still not the next broad
unblocker. The current native backend slice is intentionally tiny and exists
only to prove the compiler can write final ELF64 bytes directly from GPU HIR
state. Primitive helpers should not become "native" by feeding token-driven WASM
buffers into `x86_from_wasm`; that was the deleted prototype's mistake and
would make the compiler path look more complete than it is.

An isolated direct-ELF shader prototype was attempted for exactly
`fn main() { return 0; }`. It could write a tiny ELF from GPU lanes when tests
provided hand-built token/HIR/type buffers, but the end-to-end compiler route
timed out while creating the existing `type_check_tokens` pipeline before x86
codegen ran. That prototype was not merged as compiler support because it did
not prove the normal source-to-GPU-HIR-to-GPU-x86 path, and its shader still
recognized the slice through source/token text instead of a real backend IR.
The useful next step is the LL(1) HIR-to-ELF backend pass family, not isolated
fixture ELF emission.

## Production-Readiness Audit: May 2026

The active x86 path is aligned with the GPU code generation papers in its core
shape, with the active exceptions listed below: it consumes GPU parser/HIR/type
records, computes node-local virtual
instruction counts, uses prefix-summed locations, emits virtual instruction
rows, performs GPU liveness and register allocation, selects x86 operations,
sizes/encodes bytes, computes bounded branch/call displacements during GPU
relocation patching, and writes ELF records. The old WASM-to-x86 translator is
gone, so new x86 work should extend this direct pass chain instead of adding a
translation fallback.

Current pass-architecture violations and risks:

- The active x86 path now follows the resident pass order: lex/count source
  bytes, run the LL(1)/HIR parser once, snapshot the original parser/HIR buffers
  for type checking and x86 lowering, release only the parser resident cache,
  run GPU type checking, then measure and record x86 from the retained HIR/type
  rows. Do not reintroduce backend parser replay, source-text recognizers, or
  metadata copies whose only purpose is to survive replay.
- The x86 finish payload now keeps only source length plus token rows for
  diagnostics. It does not retain source bytes, token-count buffers, or
  token-file-id buffers, so backend lowering cannot replay the parser without
  explicitly reintroducing lexer/parser inputs across the phase boundary.
- The retained-HIR invariant still needs behavior-level guardrails. Gate: a
  small source-pack x86 status/timing trace proves exactly one parser boundary
  before type checking and backend recording from retained HIR/type/module
  records. Do not test this by searching compiler source strings.
- x86 capacity remains a host sizing decision around `RecordCapacity::for_hir`
  and the GPU feature summary. This is allowed control-plane work only while it
  is conservative. Gate: a small CPU-only capacity property over 64/128/256-line
  generated inputs plus one tiny GPU status trace must show monotonic virtual
  instruction, selected instruction, text-byte, and output-byte floors without
  changing language semantics on CPU.
- Source-pack artifact execution currently writes JSON descriptor artifacts for
  codegen objects, partial links, and linked outputs. That is a contract
  scaffold, not native artifact production. Gate: a codegen job writes
  GPU-produced object bytes plus symbol/relocation/interface records, and a
  link job consumes those records to produce linked ELF bytes without
  descriptor-only success.
- Remaining unsupported x86 constructs must keep failing from GPU status rows.
  Do not widen executable support by adding whole-function recognizers for
  loop-contained calls, short-circuit RHS calls, aggregate temporaries, dynamic
  divisors, or parameter aggregate writes.

Next verifiable gates:

1. `x86-retained-hir-guard`: assert, through a status/timing trace, that
   source-pack x86 parses once before type checking and codegen consumes
   retained HIR/type/module records.
2. `x86-object-artifact-gate`: emit one per-job GPU codegen object artifact with
   byte length, symbols, relocations, and required interface hash, not a JSON
   contract descriptor alone.
3. `x86-gpu-link-gate`: link two tiny libraries, one helper library and one
   importing entry library, into final ELF bytes through GPU object/link records.
4. `x86-loop-call-gate`: replace the current loop-contained-call diagnostic for
   one `while` condition/body call fixture with node-local call/ABI rows and
   prefix-summed virtual instruction records.

## Direct GPU Pipeline

The x86_64 backend should consume the same GPU-resident frontend artifacts that
the WASM backend receives today:

- token count for bounds checking token ids stored in parser/type metadata;
- GPU HIR arrays: `hir_kind`, `parent`, HIR status, and tree capacity;
- parser-owned expression metadata: packed `hir_expr_record` rows, operand
  records, and literal value records such as `hir_expr_int_value`;
- parser-owned statement metadata: `hir_stmt_record` rows for local binding
  names and initializers, return value nodes and value tokens, const names and
  value-expression nodes, and bounded control-flow block references;
- parser-owned parameter metadata: `hir_param_record` rows for function owner,
  stable parameter ordinal, declaration token id, and parameter HIR node;
- type-check metadata: `visible_decl`, `visible_type`, `call_fn_index`,
  `call_return_type`, `fn_entrypoint_tag`, and intrinsic tags;
- later module/runtime metadata for imports, exports, target capabilities, and
  host ABI declarations.

The direct backend should add these x86-specific GPU buffers.

| Buffer | Producer | Purpose |
| --- | --- | --- |
| `x86_func_meta` | function discovery pass | Global function counts and the selected entrypoint function node. |
| `x86_node_func` | function discovery pass | Owning function node per HIR node. |
| `x86_func_lookup_key/node` | function discovery pass | Open-addressed table from exact resolver target declaration ids, currently `hir_item_decl_token`, to HIR function nodes. |
| `x86_expr_resolved_node` | expression-forward pointer-jump passes | Resolved HIR expression node for legacy backend consumers that still need the x86-local forward-wrapper relation. New expression-root consumers should prefer the parser-owned `hir_expr_result_root_node` row when it is already available at their pass point. |
| `x86_expr_resolve_link` | expression-forward pointer-jump passes | Scratch relation used by the pointer-jump passes while converging `x86_expr_resolved_node`. |
| `x86_call_record` | call-record projection pass | Sparse per-call HIR record: owner function, resolver target token, argument start, and argument count. |
| `x86_call_type_record` | call-record projection pass | Sparse per-call type record: return type, return type token, callee token, and argument end. |
| `x86_call_callee_root_call` | call-record projection pass | Sparse callee-root marker keyed by resolved callee HIR node. Zero means no call owns the node; nonzero means the node is the root of a callee expression. |
| `x86_call_callee_owner_call` | call-callee owner pointer-jump passes | Sparse ownership row for nodes inside a callee expression. Instruction counting consumes this table to suppress callee syntax as ordinary values while excluding method receiver subtrees. |
| `x86_call_callee_owner_link` | call-callee owner pointer-jump passes | Scratch parent-link relation used while converging callee-expression ownership. |
| `x86_const_value_record` | const value projection pass | Sparse declaration-token table for supported const literal values. The pass scatters from parser-owned statement/expression records, so later backend value consumers do not scan the whole HIR to rediscover const declarations. |
| `x86_const_value_status` | const value projection pass | Status/count row for the const value projection. Unsupported const expressions leave their declaration row absent and consumers fail closed if they need it. |
| `x86_local_literal_record` | local literal projection pass | Sparse declaration-token table for supported scalar literal `let` values: owning function from `x86_node_func`, let statement node, literal value, and flags. Consumers resolve names through `visible_decl`, then validate same function and definition-before-use ordering from HIR node ids instead of scanning HIR statements. |
| `x86_local_literal_status` | local literal projection pass | Status/count row for local literal projection. Unsupported local initializers leave their declaration row absent and consumers fail closed when they need the value. |
| `x86_call_arg_lookup_record` | call-argument lookup projection pass | Per-call/per-ordinal slot table scattered from parser-owned call argument links. The slot index encodes call token and ordinal; the row stores the argument node. |
| `x86_call_abi_record` | call ABI projection pass | Sparse per-call SysV ABI record containing target function, argument count, return width, and readiness flags. Non-direct callees and unsupported direct-call ABI shapes leave the row absent, and argument nodes stay in the per-call lookup table instead of being duplicated here. |
| `x86_enum_value_record` | enum-record projection pass | Sparse per-value enum constructor row containing packed kind/payload count and variant ordinal. Instruction counting and generation consume it only for exact active x86 shapes, so invalid ordinals or wider constructor payloads fail closed before being counted as supported values. |
| `x86_match_pattern_node_owner` | match-pattern owner pointer-jump passes | Nearest owning match arm for each HIR node in a pattern subtree. Pattern classification and node instruction counting consume this table instead of walking parent chains. |
| `x86_match_pattern_owner_link` | match-pattern owner pointer-jump passes | Scratch parent-link relation used while converging nearest match-pattern owners. |
| `x86_enclosing_return_node` | enclosing-return pointer-jump passes | Nearest enclosing return statement for each HIR node. The return-match projection uses this with resolved return-expression identity to publish direct `x86_match_return_node` rows. |
| `x86_enclosing_return_link` | enclosing-return pointer-jump passes | Scratch parent-link relation used while converging nearest return-statement owners. |
| `x86_enclosing_let_node` | enclosing-let pointer-jump passes | Nearest enclosing let statement for each HIR node. Aggregate call/value destination lowering uses this with exact resolved initializer identity to validate initializer ownership and fail closed on nested aggregate ownership. |
| `x86_enclosing_let_link` | enclosing-let pointer-jump passes | Scratch parent-link relation used while converging nearest let-statement owners. |
| `x86_enclosing_stmt_node` | enclosing-statement pointer-jump passes | Nearest enclosing HIR statement wrapper for each HIR node. Intrinsic-call projection consumes this instead of walking parent chains. |
| `x86_enclosing_stmt_link` | enclosing-statement pointer-jump passes | Scratch parent-link relation used while converging nearest statement owners. |
| `x86_param_reg_record` | parameter register projection pass | Declaration-token keyed parameter ABI row: owner function node, parameter ordinal, SysV integer register, and parameter HIR node. Function body planning consumes this table instead of scanning HIR parameter rows. |
| `x86_param_reg_status` | parameter register projection pass | Status/count row for declaration-token keyed parameter register projection. Unsupported high ordinals leave their declaration row absent so body planning fails closed. |
| `x86_node_control_padding` | control-padding scatter pass | Child-node keyed padding count for if/while/for and return-match branch rows. `x86_node_inst_counts` consumes this table instead of reading `x86_tree_parent` to reclassify direct statement children. |
| `x86_postfix_operand_owner` | postfix operand-owner scatter pass | Operand-node keyed relation from postfix expression roots to their parser-published result unary operator node. `x86_node_inst_counts` consumes this table so postfix/unary fail-closed classification is a table read instead of a parent probe. |
| `x86_virtual_inst_record` | node-local instruction generation pass | Virtual instruction row containing owning HIR node, selected function, virtual opcode, and value-def row. |
| `x86_virtual_inst_args` | node-local instruction generation pass | Four-slot operand record per virtual instruction for immediates, vregs, ABI registers, declaration slots, and target rows. |
| `x86_node_inst_gen_input_status` | node-instruction-generation input status pass | Aggregated upstream status/count row consumed by `x86_node_inst_gen`, replacing many independent status-buffer reads in the storage-buffer-constrained generator. |
| `x86_enclosing_loop_node` | enclosing-loop pointer-jump passes | Nearest enclosing while/for HIR node per HIR node for break/continue lowering. |
| `x86_virtual_inst_status` | node-local instruction generation pass | Status/count row for the virtual instruction stream produced from HIR/backend records. |
| `x86_virtual_live_start` / `x86_virtual_live_end` | virtual liveness init/pass | Linearized live interval per virtual value-def row. The liveness pass reads virtual instruction operands directly and extends `live_end` with atomics. |
| `x86_virtual_next_call_row` | virtual next-call suffix scan | Nearest call row at or after each virtual instruction row inside the same function segment. The scan consumes `x86_virtual_func_slot` and fails closed when an active virtual row lacks a valid backend function slot. Register allocation uses this to detect values that span call-clobbered registers. |
| `x86_func_param_reg_mask` | virtual parameter-mask scatter | Per-function bitset of incoming ABI parameter registers materialized from virtual `PARAM` rows for register allocation. |
| `x86_virtual_phys_reg` | virtual register allocation pass | Physical register assignment or sentinel for each virtual value-def row. |
| `x86_virtual_regalloc_status` | virtual register allocation pass | Status/count row for GPU register allocation over virtual instruction records. |
| `x86_inst_count` | instruction planning/sizing pass | Number of x86 instruction records emitted by each HIR node. |
| `x86_inst_offset` | prefix scan | First instruction record for each HIR node. |
| `x86_inst_kind` | instruction selection pass | Fixed-width internal x86 instruction template ID selected from allocated virtual instruction rows. |
| `x86_inst_arg0..argN` | instruction selection pass | Registers, immediates, stack slots, target function/block IDs selected from allocated virtual instruction rows. |
| `x86_inst_size` | instruction encoding size pass | Encoded byte count per instruction record. |
| `x86_inst_byte_offset` | prefix scan | Byte offset of each encoded instruction inside `.text`. |
| `x86_block_start` / `x86_block_end` | block layout pass | Byte ranges for branch and loop targets. |
| `x86_reloc_kind` / `x86_reloc_site_inst` / `x86_reloc_target_inst` | relocation-record scan/scatter pass | Active GPU-side relative branch/call patch requests produced after byte offsets and consumed by `x86_reloc_patch` before ELF layout. |
| `x86_text_bytes` | encode + patch passes | Final executable `.text` bytes. |
| `x86_elf_layout` | ELF layout pass | ELF header/program-header/file offsets, entry point, segment sizes. |
| `x86_file_bytes` | ELF writer pass | Final unpacked ELF byte stream. |
| `x86_packed_file_words` | pack pass | Final packed bytes copied to readback. |
| `x86_status` | all passes | Length, mode, and error code; no silent success on unsupported constructs. |

The current resident pass sequence is:

1. `active_scan_dispatch_args`, `x86_node_tree_info`, `x86_func_discover`,
   `x86_func_owner_scan_*`, `x86_func_assign_nodes*`, and `x86_func_slot_*`:
   derive reusable tree, function-ownership, and compact function-slot records
   from GPU HIR. The executable-function boundary is `HIR_FN` plus
   `HIR_ITEM_KIND_FN`, not `HIR_FN` alone: trait method signature rows can use
   function-shaped HIR records for parser/type-check metadata, but they must not
   seed x86 ownership, lookup, entrypoint, or function-slot compaction.
   Function-slot rows are published only after the compact-scan scatter stage,
   so downstream consumers never observe a token-keyed placeholder slot. For
   the first slice, require one `main` with no host ABI imports except the
   existing print/assert intrinsics if they are lowered explicitly.
2. `x86_expr_resolve_init` and `x86_expr_resolve_step`: materialize resolved HIR
   expression nodes with pointer jumping over parser-owned `HIR_EXPR_FORWARD`
   wrappers. Later backend passes consume the resolved-node table directly.
3. `x86_enum_records`, `x86_match_records`, `x86_enclosing_return_*`,
   `x86_return_match_records`, `x86_match_result_owner_*`,
   `x86_enclosing_let_*`, `x86_match_ownership`, `x86_match_pattern_*`,
   `x86_struct_records`, `x86_array_records`, `x86_enclosing_stmt_*`,
   `x86_decl_widths`, and `x86_decl_layout`: materialize match, aggregate,
   statement-owner, and declaration-layout relations from HIR before call and
   instruction planning consume them. Return-match projection is intentionally
   ordered after enclosing-return records because it consumes
   `x86_enclosing_return_node`. Enum value rows are producer-owned facts, but
   instruction planning still validates their packed ordinal/payload shape before
   treating them as supported x86 values.
4. `x86_call_records`, `x86_const_values`, `x86_param_regs`, and
   `x86_local_literals`: project parser-owned call nodes plus resolver/type
   metadata into backend call/type records, and scatter const, parameter, and
   local literal facts by declaration token. This removes whole-HIR searches
   from call-argument and function-body value planning.
5. `x86_call_arg_values`: scatter parser-owned call-argument links into
   per-call / per-ordinal lookup slots. Argument expression lowering remains in
   instruction counting/generation, where it consumes HIR expression, resolver,
   and type metadata without inspecting source text or token layout.
6. `x86_intrinsic_calls` and `x86_call_abi`: project intrinsic calls and SysV
   ABI call rows from backend call/type records plus call-argument identity
   rows. Direct targets are mapped through the exact resolver target id in
   `x86_call_record.y`, not by re-resolving the callee name. These passes assign
   integer argument registers, argument refs, intrinsic tags, and readiness
   flags without looking back at token, source layout, or HIR expression forms.
   Direct-call ABI rows are published only after the target function and bounded
   ABI shape are valid; unsupported calls keep the initialized absent row, and
   instruction generation treats partial/stale ABI rows as absent.
7. `x86_call_callee_owner_init` and `x86_call_callee_owner_step`: materialize
   call-callee syntax ownership with parent-link pointer jumping. Method
   receiver subtrees stay unowned so receiver values can still become implicit
   arguments.
8. `x86_for_iterable_nodes`: materialize the `for`-statement to
   iterable-HIR-node relation directly from parser-owned statement records.
9. `x86_node_control_padding`: scatter control-statement records to child-node
   padding counts before instruction counting, so branch-padding classification
   is a GPU table read rather than parent reclassification inside
   `x86_node_inst_counts`.
10. `x86_postfix_operand_owner`: scatter postfix roots to parser-published
   result unary operand nodes before instruction counting, so postfix/unary
   fail-closed classification is a GPU table read rather than parent
   reclassification or backend-local expression-root resolution.
11. `x86_node_inst_counts`, `x86_node_inst_same_end_rank_*`,
   `x86_node_inst_end_counts`, staged `x86_node_inst_scan_*`,
   `x86_node_inst_order`, `x86_node_inst_prefix_scan`, and
   `x86_node_inst_subtree_bounds`: compute node-local virtual instruction
   counts and place rows through scan/scatter records.
12. `x86_expr_semantic_type_*`, `x86_node_inst_locations`,
   `x86_node_inst_gen_worklist_*`, `x86_enclosing_loop_*`,
   `x86_short_circuit_rhs_*`, `x86_index_source_owner_*`,
   `x86_node_inst_gen_inputs`, `x86_virtual_inst_clear*`,
   `x86_node_inst_gen`, and aggregate-copy passes: materialize virtual
   instruction rows from node-local locations, HIR metadata, call records, call
   ABI rows, declaration layout, literals, match records, and precomputed
   owner records. The input-status pass preserves upstream failure propagation
   without making the storage-buffer-constrained generator bind every status row
   directly. This must use HIR/type/backend metadata, not source-pattern
   recognition.
13. `x86_virtual_dispatch_args`, `x86_virtual_func_rows_init`,
   `x86_virtual_func_first_row`, and `x86_virtual_func_span_max`: materialize
   per-function virtual-row spans before call-clobber, liveness, and register
   allocation.
14. `x86_virtual_next_calls` and `x86_virtual_param_masks`: materialize
   function-local call-clobber and incoming-parameter register facts with
   suffix scan / scatter passes before register allocation. The suffix scan is
   segmented by `x86_virtual_func_slot` and treats invalid slots as a pass
   failure rather than allowing call-clobber facts to cross an unknown function
   boundary.
15. `x86_virtual_liveness`: compute conservative live intervals directly from
   virtual instruction operand records in the backend's linearized virtual
   instruction space.
16. `x86_virtual_spans_fixed_barrier`, `x86_virtual_value_def_flags`, value-def
   scan/compact passes, `x86_virtual_regalloc_dispatch_args`, and
   `x86_virtual_regalloc`: publish the current value-definition keep flags,
   compact live value-definition rows, and allocate SysV x86_64 registers from
   a fixed pool (`rax`, `rcx`, `rdx`, `rsi`, `rdi`, `r8`-`r11` for
   caller-saved temps, reserving ABI scratch as needed). The optimization
   boundary is paper-ordered because it runs before register allocation and
   selection, but it is intentionally narrow: it removes only pure
   single-pass-dead virtual values. This replaces the current fixed
   `visible_decl` modulo map. It must write explicit failure for unsupported
   pressure before stack-slot spilling exists. The active shader is still
   transitional here: the paper translation calls this lifetime-analysis stage
   largely sequential inside a function, and its own future-work section points
   to full-expression/statement partitioning plus segmented scans as the route
   for parallel allocation. The production pass order should therefore be:
   region-boundary publication from node/statement instruction locations,
   value-definition rows keyed by region/function, segmented
   allocation/pressure records, segmented stack-slot scans for spills, then
   selection from the resolved virtual-register table.
17. `x86_select`: scatter fixed-width x86 instruction records and GPU target
   indices from allocated virtual instruction rows. This replaces the deleted
   planning shaders that classified whole entry/callee shapes.
18. `x86_inst_size`: compute exact encoded byte length for every live selected
   instruction and zero byte length for optimized-away rows. x86_64 is
   variable-width, so this cannot assume the RISC-V-style fixed instruction
   width from the paper summaries.
19. `x86_text_scan_*` and `x86_text_offsets`: prefix-sum instruction byte sizes
   and produce block and function byte starts.
20. `x86_reloc_scan_*` and `x86_reloc_records`: scan selected control-transfer
   rows, scatter compact relocation rows, and publish relocation status after
   text offsets and before byte emission.
21. `x86_encode`: scatter instruction bytes from compact instruction rows into
   `x86_text_bytes` by byte offset.
22. `x86_reloc_patch`: consume compact relocation rows and GPU byte offsets to
   patch rel32 fields in packed output words before layout reads encoded
   status.
23. `x86_elf_layout`: compute ELF64 executable layout, entry virtual address,
   program header values, `.text` file offset, and final file length.
24. `x86_elf_write`: write ELF header, program header, padding, and `.text`
   into `x86_file_bytes` on GPU.
25. `pack_output`: pack `x86_file_bytes` into `x86_packed_file_words` for the
   only allowed host readback: copying already-final bytes.

This pass shape follows the paper summaries: use array records, maps, scans,
scatters, reductions, and GPU-side byte-offset/displacement records instead of
recursive CPU compiler algorithms. The CPU may allocate buffers, dispatch
passes, submit command buffers, check a GPU-written status code, and read back
final bytes. It must not interpret HIR, allocate registers, assemble
instructions, patch offsets, write ELF headers, or repair emitted bytes.

## Minimal First Implementation Slice

The first useful slice is intentionally small: direct x86_64 ELF emission
for the same narrow single-file subset that the current WASM path can prove
through GPU lexer, parser, type checker, and codegen. It should support:

- `fn main() { return <i32 literal>; }` and `fn main() -> bool { return true; }`,
  including a HIR-backed unary signed integer literal such as `return -1;`, are
  implemented;
- `fn main() { return <i32 literal> + <i32 literal>; }` and the same bounded
  two-literal `-` / `*` expression shape are implemented through parser-owned
  `hir_expr_record` operator/operand rows, HIR-backed vreg lowering,
  instruction selection, sizing, text encoding, ELF layout, and ELF writing;
- up to two scalar `let` declarations initialized from scalar literals,
  including HIR-backed unary signed integer literals such as
  `let value: i32 = -3;` and boolean literals such as `let value: bool = true;`,
  can feed `return local`, HIR-backed `return -local`, HIR-backed `return !local`,
  or one bounded binary return over literal/local atoms through parser-owned
  expression/statement records plus `visible_decl`-backed GPU lowering;
  the exercised scalar-op slice includes nonzero `/` and `%`, `&`, `|`, `^`,
  `<<`, and `>>` over literal/local atoms in let initializers and return
  expressions;
  broader expression graphs, arbitrary local initializer forms, and wider
  constant expressions are still rejected by GPU x86 status until direct value
  lowering, instruction selection, and register allocation expand beyond this
  bounded shape;
- one bounded boolean `&&`/`||` return over literal/local atoms is implemented
  through parser-owned expression records and `and eax, imm32` / `or eax, imm32`
  instruction records;
- one scalar comparison return over literal/local atoms, including HIR-backed
  `-local` atoms, is implemented through parser-owned expression records plus
  `cmp`, `setcc`, and `movzx`
  instruction records so bounded predicate-shaped `main` bodies can emit `0` or
  `1` directly;
- one terminal scalar `if`/`else` in `main` is implemented when parser-owned
  statement records provide the condition/then/else block nodes, the condition
  is one HIR-backed comparison over literal/local atoms, and both arms return
  scalar atoms, including boolean literal atoms. Instruction selection, sizing,
  byte offsets, and encoding produce real `cmp`,
  conditional branch, and jump records on GPU without backend token-layout
  scanning or routing through WASM-shaped buffers. One small `while` case with
  scalar local mutation now executes through the same record pipeline. Broader
  boolean expressions, nested branches, nested loops, and non-scalar arms still
  fail with GPU status;
- one zero-, one-, two-, three-, or four-argument direct call from `main` to a
  bounded scalar-return function is implemented by projecting resolver-owned
  target declaration ids into
  backend function lookup records,
  projecting call-argument value/eval records from HIR expression/statement/
  resolver metadata, projecting SysV call ABI records from those value rows,
  mapping supported argument expressions through per-call lookup slots and
  per-argument ABI rows, and lowering the caller and callee through generic
  node-local virtual instruction rows whose operands are consumed directly by
  liveness. The active backend assigns locations with prefix scans, allocates
  virtual registers, and lets selection scatter concrete instruction and
  target records directly from those allocated rows. Branch and call
  targets come from parser/HIR/resolver metadata rather than whole-function
  planning recognizers. The first nontrivial
  argument expression path lowers a one-argument binary scalar expression as
  left/right immediate vregs plus a binary-result vreg before moving that result
  into the SysV argument register. Calls with non-scalar arguments, broader
  runtime argument expression graphs, calls returning
  non-scalar values, recursive calls, multi-call functions, and broader callee bodies still
  fail with GPU status until function layout and value lowering become general;
- one resolver-backed module-qualified scalar constant arithmetic return from
  an explicit source pack, such as
  `return core::numbers::LIMIT + core::numbers::STEP;`, is implemented by
  deriving declarations from GPU resolver metadata and reading constant
  declaration values on the GPU. Return path identity comes from parser-owned
  value tokens and HIR path spans, and const values come from const item
  value-expression children rather than a backend token-layout parse. This is
  not package loading and does not make broader constant expressions general;
- a clear GPU status failure for unsupported calls, arrays, imports, modules,
  generics, structs/enums, traits, heap allocation, and host `std` APIs until
  direct x86 lowering exists for them.

After WASM has a HIR-driven primitive-helper slice, the native helper slice
should mirror only that proven no-loop scalar subset: module-local scalar
constants, parameters, return expressions, arithmetic/comparison/boolean ops,
`if`/`else`, and direct calls resolved to GPU function IDs. The direct-call
infrastructure now exists for a bounded scalar-return and four-argument ABI
slice; broader parameter/value graphs and broader callee bodies remain the next
backend work.
Broader helper loops, `test::assert`, arrays, slices, allocation, and host APIs
must still fail with GPU-written status until their direct x86 lowering and
runtime ABI are implemented.

Next files to change for the broader direct backend:

- `src/codegen/x86.rs`: continue growing the LL(1) GPU HIR-to-ELF backend. It
  already has parser/HIR projection, node-local instruction counts, staged
  prefix scans for instruction locations, virtual instruction generation,
  liveness, virtual register allocation, selection, instruction sizing,
  byte-offset scans, relocation-record scan/scatter, x86 encoding, relocation
  patching, ELF layout, and ELF writing. The deleted planning shaders must not
  be restored; selection
  should keep consuming allocated virtual instruction records directly.
  Keep the recorder named `record_x86_elf_from_gpu_hir` or similarly direct so
  tests cannot confuse it with the deleted WASM-translating prototype.
- Keep broadening the active direct shader set under `shaders/codegen/`:
  function discovery, metadata projection, call/argument records, node-local
  virtual instruction counting/generation, direct virtual liveness, virtual
  register allocation, selection, sizing, byte-offset scans, encoding,
  relocation records, ELF layout/write, and `pack_output.slang`.
- `shaders/codegen/x86_virtual_regalloc.slang`: add a real liveness/pressure/spill-slot
  allocator, or use a different direct allocator filename. The current shader
  still processes bounded value-definition chunks serially inside one
  invocation and fails closed when the GPU-recorded active chunk span is too
  small; remove that scheduling boundary instead of raising the chunk size.
  Changing the host chunk size to one row would remove the shader loop but leave
  a long serial dispatch chain, so it should not be treated as the final
  performance answer without a measured allocator redesign. Do not restore the
  deleted fixed token-index map.
- Do not restore `shaders/codegen/x86_from_wasm.slang` in the compiler-facing x86
  path.
- Build/reflection generation must include the new shader files through the
  existing shader build mechanism.
- `tests/codegen_x86.rs`: change the unavailability tests into executable ELF
  tests for the minimal direct subset. Keep the missing-input ordering test.
  Add tests that reject unsupported constructs with a `CompileError::GpuCodegen`
  status produced by the GPU pass, not by a CPU precheck.
- Add or update focused wiring coverage so the behavior proves "x86 is wired
  only through LL(1) GPU HIR-to-ELF passes." Prefer executable programs,
  source-pack programs, and fail-closed diagnostics that require HIR/type
  metadata; do not test this by grepping compiler or shader source strings.
- Add focused golden/structural tests only where they inspect final ELF bytes
  enough to prove GPU output shape: ELF magic, `e_machine == EM_X86_64`, entry
  inside executable segment, status length equal to returned bytes, and no
  post-readback byte patching.

The first slice should not attempt to make `std` host APIs work. It only unblocks
the native-output row in `stdlib/LANGUAGE_REQUIREMENTS.md` from "compiler reports
unavailable" to "direct GPU x86_64 binary emission exists for the current backend
subset." `std::fs`, `std::process`, `std::io`, networking, allocation, modules,
and target-specific runtime bindings remain blocked until the GPU module model,
ABI declarations, and runtime capability model exist.

## No-CPU-Fallback Guardrails

- No CPU prepass may expand imports, modules, type aliases, generics, Option,
  Result, Ordering, or stdlib source before x86 codegen.
- No CPU backend, assembler, object writer, linker, relocation patcher, or ELF
  writer may be introduced.
- No CPU conversion from WASM bytes to x86 bytes in the compiler path.
- No CPU postprocessing of emitted binary bytes. After readback, Rust may trim to
  the GPU-reported byte length and return the bytes. It may not inspect and
  mutate opcodes, displacements, ELF fields, section/program headers, or symbol
  tables.
- No source-recognition shortcuts in shaders. x86 lowering must consume HIR,
  parser-owned expression/statement records, token positions only as metadata
  spans, type metadata, declaration/call resolution, and later module metadata.
- Unsupported language/runtime constructs must fail through a GPU-written status
  code with a deterministic error class. The CPU should only map that status to a
  `CompileError::GpuCodegen` message.
- Tests should keep asserting that deleted CPU routes remain deleted:
  `cpu_wasm`, `cpu_native`, `emit_c`, `emit_wasm`, CPU parser/HIR modules, import
  expansion, and type-alias expansion must not reappear in the compiler path.
- The only accepted host readback for x86 is final packed ELF bytes plus compact
  status/debug buffers. Intermediate HIR, register maps, instruction records, and
  relocation tables are debug-only readbacks and must not be required for normal
  compilation.
