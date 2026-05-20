# x86_64 GPU Backend Wiring Plan

This plan advances the `stdlib/PLAN.md` native-output row while preserving the
current no-CPU-fallback objective. The target is GPU-only x86_64 ELF emission:
after source read, all frontend analysis, lowering, register allocation,
instruction sizing, relocation, ELF layout, byte packing, and final binary byte
production happen in GPU passes over GPU-resident compiler data.

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
  It no longer discovers the entrypoint by source text.
- `shaders/codegen/x86_node_inst_counts.slang` and
  `shaders/codegen/x86_node_inst_gen.slang` consume HIR, resolver, type,
  literal, declaration-layout, call, argument-prefix, and match records to
  produce node-local virtual instruction rows. They do not rediscover source
  shapes through token spelling or body-pattern scans.
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
  resolved-expression table for HIR forward nodes with pointer jumping, so later
  backend passes read `x86_expr_resolved_node` instead of each shader walking
  expression-forward chains locally.
- `shaders/codegen/x86_match_pattern_owner_init.slang` and
  `shaders/codegen/x86_match_pattern_owner_step.slang` materialize nearest
  match-pattern owner records with Pareas-style parent-link pointer jumping.
  Match-pattern classification consumes `x86_match_pattern_node_owner` instead
  of walking parent chains per node.
- `shaders/codegen/x86_enclosing_return_init.slang` and
  `shaders/codegen/x86_enclosing_return_step.slang` materialize nearest
  enclosing return-statement records with the same pointer-jump pattern. Match
  ownership combines those records with HIR subtree spans instead of walking
  parent chains.
- `shaders/codegen/x86_enclosing_let_init.slang` and
  `shaders/codegen/x86_enclosing_let_step.slang` materialize nearest enclosing
  let-statement records with the same pointer-jump pattern. Aggregate
  destination lowering reads those records plus HIR subtree spans instead of
  walking parent chains in instruction generation.
- `shaders/codegen/x86_enclosing_stmt_init.slang` and
  `shaders/codegen/x86_enclosing_stmt_step.slang` materialize nearest HIR
  statement wrapper records with the same pointer-jump pattern. Intrinsic-call
  projection reads this table instead of walking parent chains.
- The backend carries an explicit per-run virtual/native instruction capacity
  through `X86Params`/`X86ScanParams`; shader stages fail closed against that
  capacity instead of assuming every program owns the global 65k instruction
  ceiling.
- `shaders/codegen/x86_virtual_liveness.slang` reads virtual instruction
  operand records directly and atomically extends value-def live intervals,
  matching Pareas's instruction-stream register-allocation shape without
  materializing a separate def-use edge table.
- `shaders/codegen/x86_virtual_next_calls.slang` materializes a suffix-scanned
  nearest-call row per virtual instruction row inside the same function segment.
- `shaders/codegen/x86_virtual_param_masks.slang` scatters incoming parameter
  register masks per function from virtual `PARAM` rows, so register allocation
  does not scan each function just to recover ABI parameter registers.
- `shaders/codegen/x86_virtual_regalloc.slang` consumes virtual live intervals
  plus the nearest-call and parameter-mask relations and assigns physical
  registers from backend records. The old fixed token-index register map over
  `visible_decl` remains deleted.
- `shaders/codegen/x86_select.slang` consumes allocated virtual instruction
  records and scatters fixed-width x86 instruction records plus relocation
  request records. The deleted planning shaders no longer materialize
  source-shape-specific rows before selection.
- `shaders/codegen/x86_inst_size.slang` computes variable-width instruction
  sizes for those records.
- `shaders/codegen/x86_text_offsets.slang` computes instruction byte offsets
  and the current `.text` length from the GPU-produced size records.
- `shaders/codegen/x86_encode.slang` consumes instruction records plus byte
  offsets and writes packed `.text` bytes.
- `shaders/codegen/x86_reloc_patch.slang` consumes explicit GPU relocation
  records from instruction selection and patches branch relative displacements
  into the GPU-written `.text` words before ELF layout.
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
  and can now lower one resolver-backed module-qualified scalar constant return
  plus one resolver-backed module-qualified direct helper call whose callee body
  is the bounded scalar terminal-if parameter branch shape. Package imports are
  still not loaded by the host.
- The CLI now routes explicit `--stdlib`/input source-pack file lists to the
  same direct GPU x86 source-pack entrypoint. This is still an explicit file-list
  surface; it does not discover imports, walk directories, concatenate sources,
  or run a host parser/typechecker.
- `tests/codegen_x86.rs` locks this behavior: missing file errors must happen
  before codegen, direct ELF bytes are emitted for `fn main() { return 7; }`,
  unsupported return expressions reject through `CompileError::GpuCodegen`, and
  the old WASM translation prototype files must remain absent.
- `tests/gpu_audit.rs` explicitly asserts that `compiler.rs` does not contain
  `record_x86_from_gpu_token_buffer`, that direct x86 binds HIR/type metadata,
  and that the deleted prototype files do not exist.

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
| `x86_expr_resolved_node` | expression-forward pointer-jump passes | Resolved HIR expression node for each HIR node after following parser-owned forward wrappers. Downstream backend passes read this table instead of walking `HIR_EXPR_FORWARD` chains locally. |
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
| `x86_call_arg_value_record` | call-argument value pass | Sparse per-argument value row: parent call node, argument ordinal, value kind, and scalar/eval reference. The first slice supports literal, const-literal, local-literal, simple unary, and simple binary scalar HIR expressions. |
| `call_arg_value_status` | call-argument value pass | Value projection status and count of supported argument rows. Unsupported values simply leave the row absent so later direct-call lowering fails closed. |
| `x86_call_arg_lookup_record` | call-argument lookup pass | Per-call/per-ordinal slot table scattered from sparse argument value rows. The slot index encodes call node and ordinal; the row stores only argument node and value kind. |
| `call_arg_lookup_status` | call-argument lookup pass | Slot-scatter status and count of argument value rows seeded into per-call lookup slots. |
| `x86_call_abi_record` | call ABI projection pass | Sparse per-call SysV ABI record containing target function, argument count, return width, and readiness flags. Argument nodes stay in the per-call lookup table instead of being duplicated here. |
| `x86_match_pattern_node_owner` | match-pattern owner pointer-jump passes | Nearest owning match arm for each HIR node in a pattern subtree. Pattern classification and node instruction counting consume this table instead of walking parent chains. |
| `x86_match_pattern_owner_link` | match-pattern owner pointer-jump passes | Scratch parent-link relation used while converging nearest match-pattern owners. |
| `x86_enclosing_return_node` | enclosing-return pointer-jump passes | Nearest enclosing return statement for each HIR node. Match ownership uses this with HIR subtree spans to detect return-value matches. |
| `x86_enclosing_return_link` | enclosing-return pointer-jump passes | Scratch parent-link relation used while converging nearest return-statement owners. |
| `x86_enclosing_let_node` | enclosing-let pointer-jump passes | Nearest enclosing let statement for each HIR node. Aggregate call/value destination lowering uses this with HIR subtree spans to validate initializer ownership. |
| `x86_enclosing_let_link` | enclosing-let pointer-jump passes | Scratch parent-link relation used while converging nearest let-statement owners. |
| `x86_enclosing_stmt_node` | enclosing-statement pointer-jump passes | Nearest enclosing HIR statement wrapper for each HIR node. Intrinsic-call projection consumes this instead of walking parent chains. |
| `x86_enclosing_stmt_link` | enclosing-statement pointer-jump passes | Scratch parent-link relation used while converging nearest statement owners. |
| `x86_param_reg_record` | parameter register projection pass | Declaration-token keyed parameter ABI row: owner function node, parameter ordinal, SysV integer register, and parameter HIR node. Function body planning consumes this table instead of scanning HIR parameter rows. |
| `x86_param_reg_status` | parameter register projection pass | Status/count row for declaration-token keyed parameter register projection. Unsupported high ordinals leave their declaration row absent so body planning fails closed. |
| `x86_virtual_inst_record` | node-local instruction generation pass | Virtual instruction row containing owning HIR node, selected function, virtual opcode, and value-def row. |
| `x86_virtual_inst_args` | node-local instruction generation pass | Four-slot operand record per virtual instruction for immediates, vregs, ABI registers, declaration slots, and target rows. |
| `x86_node_inst_gen_input_status` | node-instruction-generation input status pass | Aggregated upstream status/count row consumed by `x86_node_inst_gen`, replacing many independent status-buffer reads in the storage-buffer-constrained generator. |
| `x86_enclosing_loop_node` | enclosing-loop pointer-jump passes | Nearest enclosing while/for HIR node per HIR node for break/continue lowering. |
| `x86_virtual_inst_status` | node-local instruction generation pass | Status/count row for the virtual instruction stream produced from HIR/backend records. |
| `x86_virtual_live_start` / `x86_virtual_live_end` | virtual liveness init/pass | Linearized live interval per virtual value-def row. The liveness pass reads virtual instruction operands directly and extends `live_end` with atomics. |
| `x86_virtual_next_call_row` | virtual next-call suffix scan | Nearest call row at or after each virtual instruction row inside the same function segment. Register allocation uses this to detect values that span call-clobbered registers. |
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
| `x86_reloc_kind` / `x86_reloc_site` / `x86_reloc_target` | relocation pass | GPU-side relative branch/call patch requests. |
| `x86_text_bytes` | encode + patch passes | Final executable `.text` bytes. |
| `x86_elf_layout` | ELF layout pass | ELF header/program-header/file offsets, entry point, segment sizes. |
| `x86_file_bytes` | ELF writer pass | Final unpacked ELF byte stream. |
| `x86_packed_file_words` | pack pass | Final packed bytes copied to readback. |
| `x86_status` | all passes | Length, mode, and error code; no silent success on unsupported constructs. |

The pass sequence should be:

1. `x86_node_tree_info`, `x86_func_discover`, `x86_func_owner_scan_*`, and
   `x86_func_assign_nodes*`: derive reusable tree and function-ownership
   records from GPU HIR. For the first slice, require one `main` with no host
   ABI imports except the existing print/assert intrinsics if they are lowered
   explicitly.
2. `x86_expr_resolve_init` and `x86_expr_resolve_step`: materialize resolved HIR
   expression nodes with pointer jumping over parser-owned `HIR_EXPR_FORWARD`
   wrappers. Later backend passes consume the resolved-node table directly.
3. `x86_call_records`: project parser-owned call nodes plus resolver/type
   metadata into backend call/type records. This is the boundary ordinary call
   ABI lowering will consume; it must not inspect source text or token layout.
4. `x86_const_values`: scatter supported const literal records by declaration
   token from HIR statement/expression records. This removes const lookup as a
   backend whole-HIR search in call-argument and function-body value planning.
5. `x86_param_regs`: scatter parser-owned `hir_param_record` rows into
   declaration-token keyed SysV register rows, so node-local instruction generation can
   resolve parameter reads with O(1) table access instead of a whole-HIR scan.
6. `x86_local_literals`: scatter supported scalar literal local records by
   declaration token from HIR statement/expression records and the precomputed
   `x86_node_func` owner table. This removes local literal lookup as a whole-HIR
   or parent-chain search from call-argument and node-local value planning.
7. `x86_call_arg_values`: project parser-owned call-argument rows plus HIR
   expression/resolver metadata into sparse argument value/eval records. It uses
   opaque declaration ids from `visible_decl` for locals and consts and does not
   inspect source text or token layout.
8. `x86_call_arg_lookup` and `x86_enclosing_stmt_*`: scatter sparse argument
   value rows into per-call / per-ordinal lookup slots and materialize nearest
   HIR statement wrappers for statement-level call projections.
9. `x86_intrinsic_calls` and `x86_call_abi`: project intrinsic calls and SysV
   ABI call rows from backend call/type records plus call-argument identity
   rows. Direct targets are mapped through the exact resolver target id in
   `x86_call_record.y`, not by re-resolving the callee name. These passes assign
   integer argument registers, argument refs, intrinsic tags, and readiness
   flags without looking back at token, source layout, or HIR expression forms.
10. `x86_call_callee_owner_init` and `x86_call_callee_owner_step`: materialize
   call-callee syntax ownership with parent-link pointer jumping. Method
   receiver subtrees stay unowned so receiver values can still become implicit
   arguments.
11. `x86_node_inst_counts`: compute node-local virtual instruction counts from
   HIR/type/resolver/backend records.
12. `x86_node_inst_order`, `x86_node_inst_scan_*`, and
   `x86_node_inst_prefix_scan`: place node-local instruction rows with staged
   prefix scans.
13. `x86_node_inst_locations`, `x86_enclosing_loop_init`,
   `x86_enclosing_loop_step`, `x86_enclosing_let_init`,
   `x86_enclosing_let_step`, `x86_node_inst_gen_inputs`, and
   `x86_node_inst_gen`: materialize virtual instruction rows from node-local
   locations, HIR metadata, call records, call ABI rows, declaration layout,
   literals, match records, and precomputed loop/let-owner records. The
   input-status pass preserves upstream failure propagation without making the
   storage-buffer-constrained generator bind every status row directly. This
   must use HIR/type/backend metadata, not source-pattern recognition.
14. `x86_virtual_liveness`: compute conservative live intervals directly from
   virtual instruction operand records in the backend's linearized virtual
   instruction space.
15. `x86_virtual_next_calls` and `x86_virtual_param_masks`: materialize
   function-local call-clobber and incoming-parameter register facts with
   suffix scan / scatter passes before register allocation.
17. `x86_virtual_regalloc`: allocate SysV x86_64 registers from a fixed pool
   (`rax`, `rcx`, `rdx`, `rsi`, `rdi`, `r8`-`r11` for caller-saved temps,
   reserving ABI scratch as needed) and assign spill slots. This replaces the
   current fixed `visible_decl` modulo map. It must write explicit failure for
   unsupported pressure before stack-slot spilling exists.
18. `x86_select`: scatter fixed-width x86 instruction records and relocation
   records from allocated virtual instruction rows. This replaces the deleted
   planning shaders that classified whole entry/callee shapes.
19. `x86_inst_offsets`: prefix-sum instruction counts to assign instruction
   record ranges.
20. `x86_inst_size`: compute exact encoded byte length for every instruction
   record. x86_64 is variable-width, so this cannot assume the RISC-V-style
   fixed instruction width from the paper summaries.
21. `x86_text_offsets`: prefix-sum instruction byte sizes and produce block and
   function byte starts.
22. `x86_encode`: emit instruction bytes into `x86_text_bytes` by byte offset.
23. `x86_reloc_patch`: patch relative branches/calls on GPU. Relative
   displacements must not be calculated on the CPU after readback.
24. `x86_elf_layout`: compute ELF64 executable layout, entry virtual address,
   program header values, `.text` file offset, and final file length.
25. `x86_elf_write`: write ELF header, program header, padding, and `.text`
   into `x86_file_bytes` on GPU.
26. `pack_output`: pack `x86_file_bytes` into `x86_packed_file_words` for the
   only allowed host readback: copying already-final bytes.

This pass shape follows the paper summaries: use array records, maps, scans,
scatters, reductions, and GPU-side patching instead of recursive CPU compiler
algorithms. The CPU may allocate buffers, dispatch passes, submit command
buffers, check a GPU-written status code, and read back final bytes. It must not
interpret HIR, allocate registers, assemble instructions, patch offsets, write
ELF headers, or repair emitted bytes.

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
  broader local dataflow, non-literal local initializers, broader scalar arithmetic, and
  wider constant expressions are still rejected by GPU x86 status until direct
  value lowering, instruction selection, and register allocation expand beyond
  this bounded shape;
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
  byte offsets, encoding, and relocation patching produce real `cmp`,
  conditional branch, and jump records on GPU without backend token-layout
  scanning or routing through WASM-shaped buffers. Broader boolean expressions, nested
  branches, `while`, and non-scalar arms still fail with GPU status;
- one zero-, one-, or two-argument direct call from `main` to a
  scalar literal-, first-parameter-, first-parameter-plus-literal-, or
  first-parameter-plus-second-parameter-return, or bounded
  first-parameter-compare-second-parameter terminal-if return
  function
  is implemented by projecting resolver-owned target declaration ids into
  backend function lookup records,
  projecting call-argument value/eval records from HIR expression/statement/
  resolver metadata, projecting SysV call ABI records from those value rows,
  mapping supported argument expressions through per-call lookup slots and
  per-argument ABI rows, planning
  each supported callee body into sparse `x86_func_return_value_record`,
  `x86_func_return_eval_record`, and `x86_func_return_vreg_record` rows from
  HIR/parameter/resolver metadata, and lowering the caller to a generic
  direct-call virtual instruction value whose operands are consumed directly by
  liveness.
  The active backend now emits node-local virtual instruction rows, assigns
  locations with prefix scans, allocates virtual registers, and lets selection
  scatter concrete instruction and relocation records directly from those
  allocated rows. For the terminal-if callee slice, match/branch/call records
  come from parser and HIR metadata rather than whole-function planning
  recognizers. The first nontrivial
  argument expression path lowers a one-argument binary scalar expression as
  left/right immediate vregs plus a binary-result vreg before moving that result
  into the SysV argument register. Calls with non-scalar arguments, broader
  runtime argument expression graphs, more than two arguments, calls returning
  non-scalar values, recursive calls, multi-call functions, and broader callee bodies still
  fail with GPU status until function layout and value lowering become general;
- one resolver-backed module-qualified scalar constant return from an explicit
  source pack, such as `return core::i32::MAX;`, is implemented by deriving the
  declaration from GPU resolver metadata and reading the constant declaration
  value on the GPU. Return path identity comes from parser-owned value tokens
  and HIR path spans, and the const value comes from the const item's
  value-expression child rather than a backend token-layout parse. This is not
  package loading and does not lower helper calls or broader constant
  expressions;
- a clear GPU status failure for unsupported calls, arrays, imports, modules,
  generics, structs/enums, traits, heap allocation, and host `std` APIs until
  direct x86 lowering exists for them.

After WASM has a HIR-driven primitive-helper slice, the native helper slice
should mirror only that proven no-loop scalar subset: module-local scalar
constants, parameters, return expressions, arithmetic/comparison/boolean ops,
`if`/`else`, and direct calls resolved to GPU function IDs. The direct-call
infrastructure now exists for the narrow zero-argument scalar-return case;
parameter passing and broader callee bodies remain the next backend work.
`while`-based helpers, `test::assert`, arrays, slices, allocation, and host APIs
must still fail with GPU-written status until their direct x86 lowering and
runtime ABI are implemented.

Next files to change for the broader direct backend:

- `src/codegen/x86.rs`: continue growing the LL(1) GPU HIR-to-ELF backend. It
  already has parser/HIR projection, node-local instruction counts, staged
  prefix scans for instruction locations, virtual instruction generation,
  liveness, virtual register allocation, selection, instruction sizing,
  byte-offset scans, x86 encoding, relocation patching, ELF layout, and ELF
  writing. The deleted planning shaders must not be restored; selection should
  keep consuming allocated virtual instruction records directly.
  Keep the recorder named `record_x86_elf_from_gpu_hir` or similarly direct so
  tests cannot confuse it with the deleted WASM-translating prototype.
- Keep broadening the active direct shader set under `shaders/codegen/`:
  function discovery, metadata projection, call/argument records, node-local
  virtual instruction counting/generation, direct virtual liveness, virtual
  register allocation, selection, sizing, byte-offset scans, encoding,
  relocation patching, ELF layout/write, and `pack_output.slang`.
- `shaders/codegen/x86_virtual_regalloc.slang`: add a real liveness/pressure/spill-slot
  allocator, or use a different direct allocator filename. Do not restore the
  deleted fixed token-index map.
- Do not restore `shaders/codegen/x86_from_wasm.slang` in the compiler-facing x86
  path.
- Build/reflection generation must include the new shader files through the
  existing shader build mechanism.
- `tests/codegen_x86.rs`: change the unavailability tests into executable ELF
  tests for the minimal direct subset. Keep the missing-input ordering test.
  Add tests that reject unsupported constructs with a `CompileError::GpuCodegen`
  status produced by the GPU pass, not by a CPU precheck.
- `tests/gpu_audit.rs`: update the wiring assertions from "x86 exists but is not
  wired" to "x86 is wired only through LL(1) GPU HIR-to-ELF passes." Add negative
  string checks so `src/compiler.rs` does not call `x86_from_wasm`, does not
  call `record_x86_from_gpu_token_buffer`, and does not contain any CPU
  assembler/backend fallback names. Add shader checks that direct x86 shaders
  bind HIR/type metadata and do not consume `body_words`, `bool_body_words`, or
  `functions_words`.
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
