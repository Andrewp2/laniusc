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

- `src/codegen/mod.rs` exports `gpu_x86`, but the module is the new direct HIR
  backend, not the old WASM translation prototype.
- `src/codegen/gpu_x86.rs` defines `GpuX86CodeGenerator`,
  `record_x86_elf_from_gpu_hir`, and `finish_recorded_x86` for the first direct
  GPU slice. The old `record_x86_from_gpu_token_buffer` surface is gone.
- `shaders/codegen/x86_from_wasm.slang` is absent. No compiler-facing x86 path
  consumes `body_words`, `bool_body_words`, or `functions_words`.
- `shaders/codegen/x86_func_discover.slang` records backend function metadata
  from GPU HIR function nodes and GPU `fn_entrypoint_tag` records produced
  from compiler-owned language declarations, including the current `main` span.
  It no longer discovers the entrypoint by source text.
- `shaders/codegen/x86_lower_values.slang` consumes GPU function metadata, HIR
  spans, parser-owned packed `hir_expr_record` operator/operand rows,
  parser-owned literal metadata, parser-owned `hir_stmt_record` rows for local,
  return, const, and terminal `if` statement facts, and GPU declaration
  metadata for bounded local references. This is direct HIR lowering: it writes
  vreg-shaped value/status records for the supported shapes: `main` returning
  one integer or boolean literal including HIR-backed unary signed integer
  literals, one of up to two scalar locals initialized from scalar literals,
  one HIR-backed unary negation over a bounded scalar local, one HIR-backed
  logical-not expression over a bounded boolean atom, one HIR-backed binary
  expression over two integer/local atoms, one HIR-backed boolean `&&`/`||`
  return, one scalar comparison return, or one terminal HIR-backed scalar
  `if`/`else` comparison. Binary operators, comparison operators, and terminal
  branch blocks come from parser-owned HIR records rather than backend token
  punctuation/layout scans. Unsupported return shapes are rejected by
  GPU-written status.
- `shaders/codegen/x86_use_edges.slang` expands lowering operand records into
  explicit backend def-use rows (`x86_use_key`, `x86_use_value`, and
  `x86_vreg_use_count`). The key packs `(use_node, operand_slot)` to stay under
  the storage-buffer limit while keeping selection and liveness record-driven.
- `shaders/codegen/x86_liveness.slang` materializes live interval records for
  backend virtual registers by consuming those def-use rows rather than
  rereading lowering's operand layout or recognizing exact 1/3/5-vreg shapes.
- `shaders/codegen/x86_regalloc.slang` consumes those live interval records and
  assigns physical registers from backend value/liveness records. Immediate
  operands stay unallocated unless they are the final syscall argument, and
  non-immediate temps use live-overlap ranks over a small caller-save pool. The
  old fixed token-index register map over `visible_decl` remains deleted.
- `shaders/codegen/x86_entry_inst_plan.slang` consumes vreg/use/layout records
  and materializes entry/caller instruction rows, including SysV argument setup
  for the bounded direct-call slice, into planned instruction buffers plus an
  entry instruction status row.
- `shaders/codegen/x86_inst_plan.slang` consumes layout and instruction-status
  records and materializes the selected return shape, instruction count, and
  relocation count into compact planning records. It no longer binds vreg/use
  buffers or owns instruction-row templates.
- `shaders/codegen/x86_reloc_plan.slang` consumes select/layout/entry status
  records and materializes branch/call relocation rows. Direct calls target the
  callee function-layout start instruction.
- `shaders/codegen/x86_select.slang` consumes those planning records and emits
  fixed-width x86 instruction records for the current return, binary,
  comparison, and terminal branch shapes. It no longer recomputes return
  operands or instruction counts from the vreg/use-edge graph.
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
The useful next step is a direct-HIR backend pass family, not isolated fixture
ELF emission.

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
| `x86_func_record` | function discovery pass | Sparse per-function HIR record: function node, entrypoint tag, ABI kind, and flags. |
| `x86_node_func` | function discovery pass | Owning function node per HIR node. |
| `x86_func_lookup_key/node` | function discovery pass | Open-addressed table from exact resolver target declaration ids, currently `hir_item_decl_token`, to HIR function nodes. |
| `x86_call_record` | call-record projection pass | Sparse per-call HIR record: owner function, resolver target token, argument start, and argument count. |
| `x86_call_type_record` | call-record projection pass | Sparse per-call type record: return type, return type token, callee token, and argument end. |
| `x86_const_value_record` | const value projection pass | Sparse declaration-token table for supported const literal values. The pass scatters from parser-owned statement/expression records, so later backend value consumers do not scan the whole HIR to rediscover const declarations. |
| `x86_const_value_status` | const value projection pass | Status/count row for the const value projection. Unsupported const expressions leave their declaration row absent and consumers fail closed if they need it. |
| `x86_local_literal_record` | local literal projection pass | Sparse declaration-token table for supported top-level literal `let` values: owning function, let statement node, literal value, and flags. Consumers resolve names through `visible_decl`, then validate same function and definition-before-use ordering from HIR node ids instead of scanning HIR statements. |
| `x86_local_literal_status` | local literal projection pass | Status/count row for local literal projection. Unsupported local initializers leave their declaration row absent and consumers fail closed when they need the value. |
| `x86_func_return_stmt_record` | return statement projection pass | Sparse per-function record for the supported top-level return statement: function node, return statement node, return expression node, and flags. Body planning consumes this record instead of scanning all HIR nodes for each function. |
| `x86_func_return_stmt_count` | return statement projection pass | Per-function top-level return count. A function with a count other than one is unsupported by the current simple body planner, so duplicate top-level returns fail closed without per-function HIR rediscovery. |
| `x86_func_return_stmt_status` | return statement projection pass | Status/count row for return-statement projection. Nested `if` returns are not projected as top-level function-body returns; body planning uses the per-function count/record to decide support. |
| `x86_block_return_stmt_record` | branch-block return projection pass | Sparse branch-block keyed record for supported `return` statements inside if/else blocks: block node, return node, return expression node, and flags. Terminal-if lowering consumes this instead of searching all HIR nodes for returns inside branch blocks. |
| `x86_block_return_stmt_count` | branch-block return projection pass | Per-branch-block return count. Terminal-if projection requires exactly one return per then/else branch, so duplicate branch returns fail closed through counts rather than lowering-time scans. |
| `x86_block_return_stmt_status` | branch-block return projection pass | Status/count row for branch-block return projection. |
| `x86_terminal_if_record` | terminal-if projection pass | Sparse per-function terminal if/else row: if node, condition expression node, then return expression node, and else return expression node. `x86_lower_values` consumes this record directly for branch returns. |
| `x86_terminal_if_count` | terminal-if projection pass | Per-function terminal-if count. Multiple top-level terminal if rows are rejected by status instead of racing in value lowering. |
| `x86_terminal_if_status` | terminal-if projection pass | Status/count row for terminal-if projection, including duplicate terminal-if errors. |
| `x86_return_call_record` | return-call projection pass | Sparse top-level-return keyed row for the supported direct call expression contained by a return statement: return node, call node, owning function, and flags. Value lowering consumes this record instead of searching the return subtree for calls. |
| `x86_return_call_count` | return-call projection pass | Per-return call count. Multiple calls under one supported top-level return fail closed through status. |
| `x86_return_call_status` | return-call projection pass | Status/count row for top-level return-call projection. |
| `x86_call_arg_value_record` | call-argument value pass | Sparse per-argument value row: parent call node, argument ordinal, value kind, and scalar/eval reference. The first slice supports literal, const-literal, local-literal, simple unary, and simple binary scalar HIR expressions. |
| `x86_call_arg_eval_record` | call-argument value pass | Sparse per-argument evaluation row: scalar-immediate value or binary-immediate left/right/operator facts derived from HIR expression/statement/resolver metadata. |
| `call_arg_value_status` | call-argument value pass | Value projection status and count of supported argument rows. Unsupported values simply leave the row absent so later direct-call lowering fails closed. |
| `x86_call_arg_lookup_record` | call-argument lookup pass | Per-call/per-ordinal slot table scattered from sparse argument value rows. This lets ABI projection read argument nodes by stable call slot instead of searching all HIR nodes. |
| `call_arg_lookup_status` | call-argument lookup pass | Slot-scatter status and count of argument value rows seeded into per-call lookup slots. |
| `x86_call_abi_record` | call ABI projection pass | Sparse two-row per-call SysV ABI record: header row with owner function, target function, and argument count; argument-reference row with supported argument HIR nodes and a validity mask. ABI rows assign/register metadata; they do not evaluate expressions. |
| `x86_call_arg_abi_record` | call ABI projection pass | Sparse per-argument ABI row: parent call node, ordinal, assigned integer argument register, and argument node id. |
| `x86_call_abi_flags` | call ABI projection pass | Per-call readiness flags for direct target, argument-window support, and typed return metadata. |
| `x86_call_arg_width_record` | call-argument width pass | Sparse per-argument eval-width row: parent call node, argument ordinal, required vreg width, and assigned ABI register. Current widths are `scalar=1` and `binary-imm=3`. |
| `call_arg_width_status` | call-argument width pass | Width projection status and count of argument rows with supported eval-width records. |
| `x86_call_arg_width_slot_record` | call-argument prefix seed pass | Per-call/per-ordinal slot table scattered from sparse width rows. This gives the prefix pass an ordered argument-width table without searching HIR nodes. |
| `call_arg_prefix_seed_status` | call-argument prefix seed pass | Slot-scatter status and count of argument width rows seeded into per-call slots. |
| `x86_call_arg_prefix_record` | call-argument prefix scan pass | Sparse per-argument prefix row: parent call node, ordinal, base vreg, and width. Later passes consume this instead of recomputing prior-argument sums. |
| `x86_call_arg_total_width_record` | call-argument prefix scan pass | Sparse per-call total-width row: call node, argument count, total argument vreg width, and call-result vreg. |
| `call_arg_prefix_status` | call-argument prefix scan pass | Prefix-scan status and count of argument prefix rows emitted for supported calls. |
| `x86_call_arg_range_record` | call-argument vreg pass | Sparse per-argument range row: parent call node, argument ordinal, base vreg, and result vreg. Ranges are materialized from explicit prefix rows. |
| `x86_call_vreg_summary_record` | call-argument vreg pass | Sparse per-call semantic summary row: owner function, target function, argument count, and callee return-eval kind. |
| `x86_call_vreg_count_record` | call-argument vreg pass | Sparse per-call vreg-count row: call node, argument count, total argument vreg width, and call-result vreg. |
| `call_arg_vreg_status` | call-argument vreg pass | Range projection status and count of argument rows that can be lowered by the current bounded backend. |
| `x86_param_reg_record` | parameter register projection pass | Declaration-token keyed parameter ABI row: owner function node, parameter ordinal, SysV integer register, and parameter HIR node. Function body planning consumes this table instead of scanning HIR parameter rows. |
| `x86_param_reg_status` | parameter register projection pass | Status/count row for declaration-token keyed parameter register projection. Unsupported high ordinals leave their declaration row absent so body planning fails closed. |
| `x86_func_return_value_record` | function body planning pass | Sparse per-function return value row: function node, return statement node, return expression node, and value form. This is the value-level body contract for later backend passes. |
| `x86_func_return_eval_record` | function body planning pass | Sparse per-function return evaluation row: eval kind plus literal/operator/register payload consumed by layout and per-function return instruction planning. |
| `x86_func_return_vreg_record` | function body planning pass | Sparse per-function return vreg row: result vreg slot, source vreg slots, and body instruction count including `ret`. Function layout consumes this count for callee ranges. |
| `x86_func_body_status` | function body planning pass | Body planning status and count of functions with a supported body row. |
| `x86_func_return_inst_status` | function return instruction planning pass | Status row for materializing callee return-body instruction rows from layout plus return eval/vreg records. |
| `x86_value_kind` | lowering pass | Classifies each HIR value as immediate, local, temp, call result, address, or no value. |
| `x86_vreg_def` | lowering pass | Virtual register defined by each value-producing HIR node. |
| `x86_vreg_args` | lowering pass | Four-slot operand record per virtual register for arithmetic, comparison, and terminal branch records. |
| `x86_vreg_type` | lowering pass | Scalar/layout type for each virtual register. |
| `x86_vreg_use_count` | use edge expansion pass | Number of uses per virtual register. |
| `x86_use_key/value` | use edge expansion pass | Def-use edge rows `(use_node, vreg, operand_slot)`, with use node and operand slot packed into the key. |
| `x86_live_start` / `x86_live_end` | liveness pass | Approximate linearized live interval per virtual register for the first slice. |
| `x86_phys_reg` | register allocation pass | Physical register assignment or spill slot for each virtual register. |
| `x86_spill_slot` | register allocation pass | Stack slot index for spilled virtual registers. |
| `x86_func_inst_count_record` | function instruction count pass | Sparse per-HIR-function instruction-count row: function node, instruction count, role, and payload. The bounded direct-call slice classifies the entry and callee bodies here instead of inside layout. |
| `x86_func_inst_order_record` | function instruction order pass | Ordered scan slot rows. Slot 0 is the compiler-owned entry function; every other HIR node owns slot `node+1`, with empty slots carrying zero count. |
| `x86_func_inst_scan_input` | function instruction order pass | Dense u32 scan input derived from ordered function count rows. |
| `x86_func_inst_scan_local_prefix` / `x86_func_inst_scan_block_sum` | local prefix pass | Per-workgroup exclusive prefixes and block sums for ordered instruction counts. |
| `x86_func_inst_scan_block_prefix` | block prefix pass | Inclusive prefix of block sums produced by ping-pong scan steps. |
| `x86_func_inst_range_record` | function instruction prefix/range apply pass | Sparse per-HIR-function instruction-range row: start instruction, instruction count, role, and payload. The compiler-owned entry function is placed first and remaining starts are applied from staged scan records, so multiple function ranges can coexist without fixed caller/callee windows. |
| `x86_func_layout_record` | function layout scatter pass | Stable sparse per-HIR-function instruction-layout row copied from the GPU range records for later instruction and relocation planning. |
| `x86_func_layout_status` | function layout pass | Global layout status and summary: total instruction count, owner function node, target function node, selected shape, return vreg, and vreg count for the current bounded backend graph. |
| `x86_entry_inst_status` | entry instruction planning pass | Status row for materializing entry/caller instruction rows and the direct-call site instruction index consumed by relocation planning. |
| `x86_select_plan` | instruction planning pass | Selected return shape, instruction count, relocation count, and return vreg. |
| `x86_planned_inst_kind/arg0` | function return instruction planning + entry instruction planning passes | Concrete internal instruction-template rows produced from vreg/use/register/function-layout records before selection. Callee return rows are materialized by a per-function pass; entry/caller rows are materialized by `x86_entry_inst_plan`. |
| `x86_planned_reloc_kind/site/target` | relocation planning pass | Concrete relative branch/call patch rows produced after instruction-row planning; direct-call targets are callee function-layout start instructions. |
| `x86_inst_count` | instruction planning/sizing pass | Number of x86 instruction records emitted by each HIR node. |
| `x86_inst_offset` | prefix scan | First instruction record for each HIR node. |
| `x86_inst_kind` | instruction selection pass | Fixed-width internal x86 instruction template ID copied from planned rows. |
| `x86_inst_arg0..argN` | instruction selection pass | Registers, immediates, stack slots, target function/block IDs copied from planned rows. |
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

1. `x86_func_discover`: map function HIR nodes to dense function IDs and compute
   first-level metadata. For the first slice, require one `main` with no host ABI
   imports except the existing print/assert intrinsics if they are lowered
   explicitly.
2. `x86_call_records`: project parser-owned call nodes plus resolver/type
   metadata into backend call/type records. This is the boundary ordinary call
   ABI lowering will consume; it must not inspect source text or token layout.
3. `x86_const_values`: scatter supported const literal records by declaration
   token from HIR statement/expression records. This removes const lookup as a
   backend whole-HIR search in call-argument and function-body value planning.
4. `x86_param_regs`: scatter parser-owned `hir_param_record` rows into
   declaration-token keyed SysV register rows, so per-function body planning can
   resolve parameter reads with O(1) table access instead of a whole-HIR scan.
5. `x86_local_literals`: scatter supported top-level literal local records by
   declaration token from HIR statement/expression records. This removes local
   literal lookup as a whole-HIR search from call-argument and function-body
   value planning.
6. `x86_func_return_stmts`: scatter top-level return statement rows by owning
   function from HIR statement records. Nested control-flow returns are filtered
   by parent-chain ownership checks, and per-function return counts let body
   planning reject duplicates without scanning all HIR nodes.
7. `x86_block_return_stmts`: scatter return statements inside if/else branch
   blocks into branch-block keyed rows. This gives terminal-if projection a
   direct record for each branch return instead of having value lowering search
   the whole HIR for returns under a block.
8. `x86_terminal_ifs`: scatter supported top-level terminal if/else rows per
   owning function from HIR statement records and branch-block return rows.
   Duplicate terminal-if rows fail closed through status buffers.
9. `x86_return_calls`: scatter supported direct call nodes under projected
   top-level return statements into return-keyed rows, so value lowering does
   not search return-expression subtrees to find call nodes.
10. `x86_call_arg_values`: project parser-owned call-argument rows plus HIR
   expression/resolver metadata into sparse argument value/eval records. It uses
   opaque declaration ids from `visible_decl` for locals and consts and does not
   inspect source text or token layout.
11. `x86_call_arg_lookup`: scatter sparse argument value rows into per-call /
   per-ordinal lookup slots, so ABI projection has O(1) argument identity
   reads and no full-HIR argument rediscovery.
12. `x86_call_abi`: project backend call/type rows plus call-argument identity
   rows into SysV ABI call and argument records. Direct targets are mapped
   through the exact resolver target id in `x86_call_record.y`, not by
   re-resolving the callee name. This pass assigns integer argument registers,
   argument refs, and readiness flags without looking back at token, source
   layout, or HIR expression forms.
13. `x86_call_arg_widths`: project supported argument value/eval rows plus ABI
   assignment rows into sparse eval-width records. This separates expression
   shape classification from vreg range assignment.
14. `x86_call_arg_prefix_seed`: scatter sparse argument width rows into a
   per-call/per-ordinal slot table.
15. `x86_call_arg_prefix_scan`: scan the per-call slot table into explicit
   argument prefix/base rows and per-call total-width rows.
16. `x86_func_body_plan`: project per-HIR-function return value/eval/vreg
   records for currently supported callee bodies. This uses HIR
   function/param/return/expression records and does not infer callee behavior
   from the caller template.
17. `x86_call_arg_vregs`: consume prefix/total records plus call/body metadata and
   materialize explicit argument base/result ranges and per-call total vreg
   count rows. The call result vreg follows the prefix-scan total instead of
   being recomputed from prior ordinal slots in lowering.
18. `x86_lower_values`: assign value-producing HIR nodes to virtual registers,
   record constants, locals, calls, returns, branches, and unsupported node
   errors. Const and supported local-literal references consume declaration-id
   keyed backend records, top-level returns consume per-function return rows,
   direct calls in returns consume return-call rows, and terminal if/else
   lowering consumes per-function terminal-if rows instead of scanning HIR
   statements. This must use HIR/type metadata, not source-pattern recognition.
19. `x86_use_edges`: expand operand records into def-use edge rows and per-vreg
   use counts. This first implementation uses a bounded edge table; later work
   can split it into count/scan/scatter passes when the backend grows past the
   current fixed vreg window.
20. `x86_liveness`: compute conservative live intervals in the backend's
   linearized HIR/order space. The first implementation can use one interval per
   vreg from definition to last use; later work can refine per block.
21. `x86_regalloc`: allocate SysV x86_64 registers from a fixed pool
   (`rax`, `rcx`, `rdx`, `rsi`, `rdi`, `r8`-`r11` for caller-saved temps,
   reserving ABI scratch as needed) and assign spill slots. This replaces the
   current fixed `visible_decl` modulo map. It must write explicit failure for
   unsupported pressure before stack-slot spilling exists.
22. `x86_func_inst_counts`: classify the supported backend graph and emit
   sparse per-function instruction-count rows. This is the only current
   count/classification owner for entry/callee instruction ranges.
23. `x86_func_inst_order`: scatter sparse count rows into explicit ordered scan
   slots. Slot 0 is the entry function; the remaining slots are HIR-node order.
24. `x86_func_inst_scan_local`: compute per-workgroup exclusive prefixes and
   block sums over ordered instruction counts.
25. `x86_func_inst_scan_blocks`: ping-pong inclusive prefixes over block sums
   with `scan_step = 0, 1, 2, 4, ...`.
19. `x86_func_inst_prefix_scan`: apply local and block prefixes into sparse
   per-function start/count range records with total-capacity validation.
20. `x86_func_layout`: scatter validated function range rows into stable layout
   records consumed by instruction and relocation planning.
21. `x86_func_return_inst_plan`: materialize callee return instruction rows
   from `x86_func_layout_record`, `x86_func_return_eval_record`, and
   `x86_func_return_vreg_record`. This keeps callee body behavior out of the
   caller/direct-call template.
21. `x86_entry_inst_plan`: materialize entry/caller instruction rows at the
   owner function's planned range start from vreg/use/layout records and publish
   `x86_entry_inst_status`.
22. `x86_inst_plan`: compute the current selected shape, instruction count,
   and relocation count from layout and instruction-status rows. Later this
   should split into per-HIR-node instruction counts inside each function as
   multiple blocks are added.
23. `x86_reloc_plan`: materialize branch/call relocation rows from select,
   layout, and entry instruction status records.
18. `x86_inst_offsets`: prefix-sum instruction counts to assign instruction
   record ranges.
19. `x86_select`: scatter fixed-width x86 instruction records using planning
   records, register allocation, and type metadata.
20. `x86_inst_size`: compute exact encoded byte length for every instruction
   record. x86_64 is variable-width, so this cannot assume the RISC-V-style
   fixed instruction width from the paper summaries.
21. `x86_text_offsets`: prefix-sum instruction byte sizes and produce block and
    function byte starts.
22. `x86_encode`: emit instruction bytes into `x86_text_bytes` by byte offset.
23. `x86_reloc_collect` and `x86_reloc_patch`: record and patch relative
    branches/calls on GPU. Relative displacements must not be calculated on the
    CPU after readback.
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
  mapping supported argument expressions into width, prefix, total-width, and
  range records (`x86_call_arg_width_record`, `x86_call_arg_prefix_record`,
  `x86_call_arg_total_width_record`, `x86_call_arg_range_record`,
  `x86_call_vreg_count_record`), planning
  each supported callee body into sparse `x86_func_return_value_record`,
  `x86_func_return_eval_record`, and `x86_func_return_vreg_record` rows from
  HIR/parameter/resolver metadata, and lowering the caller to a generic
  `X86_VREG_CALL_DIRECT_I32` backend value with explicit argument use edges.
  Function layout assigns separate caller and callee instruction ranges from
  `x86_func_layout_record`, sizes the callee range from the return vreg row,
  `x86_func_return_inst_plan` materializes callee body rows from return
  eval/vreg records, `x86_entry_inst_plan` materializes SysV argument setup
  from argument vregs plus the `call rel32` row, and relocation planning patches
  the call relocation to the callee layout start on GPU. For the terminal-if
  callee slice, the function-return planner emits compare, conditional-branch,
  jump, parameter-return, and `ret` rows from the callee's
  `x86_terminal_if_record`, parameter-register records, and return eval/vreg
  records, and relocation planning patches those branch rows on GPU. The first nontrivial
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

- `src/codegen/gpu_x86.rs`: continue splitting the current direct-ELF slice into
  the pass family below as the backend grows. It already has distinct
  `x86_func_discover`, `x86_const_values`, `x86_local_literals`,
  `x86_func_return_stmts`, `x86_block_return_stmts`, `x86_terminal_ifs`,
  `x86_return_calls`, `x86_lower_values`, `x86_use_edges`, `x86_liveness`,
  `x86_regalloc`, `x86_func_inst_counts`, `x86_func_inst_prefix_scan`,
  `x86_func_inst_order`, `x86_func_inst_scan_local`,
  `x86_func_inst_scan_blocks`, `x86_func_layout`,
  `x86_func_return_inst_plan`, `x86_entry_inst_plan`, `x86_inst_plan`,
  `x86_reloc_plan`, `x86_select`, `x86_inst_size`, `x86_text_offsets`,
  `x86_encode`, `x86_reloc_patch`, `x86_elf_layout`, and `x86_elf_write`
  passes, with
  liveness/register-allocation records between lowering and selection,
  per-function instruction count/range/layout records before instruction
  materialization, instruction sizing/byte-offset records before byte encoding,
  explicit relocation records before final text bytes are consumed, and ELF
  layout records before final file writing. The next step is replacing the
  remaining bounded vreg/instruction-capacity checks with broader per-function
  body/block records.
  Keep the recorder named `record_x86_elf_from_gpu_hir` or similarly direct so
  tests cannot confuse it with the deleted WASM-translating prototype.
- Add direct shader files under `shaders/codegen/`, for example:
  `x86_func_discover.slang`, `x86_lower_values.slang`,
  `x86_const_values.slang`,
  `x86_local_literals.slang`,
  `x86_func_return_stmts.slang`,
  `x86_block_return_stmts.slang`,
  `x86_terminal_ifs.slang`,
  `x86_return_calls.slang`,
  `x86_use_edges.slang`, `x86_liveness.slang`,
  `x86_regalloc.slang`, `x86_func_inst_counts.slang`,
  `x86_func_inst_order.slang`, `x86_func_inst_scan_local.slang`,
  `x86_func_inst_scan_blocks.slang`, `x86_func_inst_prefix_scan.slang`,
  `x86_func_layout.slang`,
  `x86_func_return_inst_plan.slang`, `x86_entry_inst_plan.slang`,
  `x86_inst_plan.slang`, `x86_inst_count.slang`, `x86_inst_offsets.slang`,
  `x86_select.slang`, `x86_inst_size.slang`, `x86_text_offsets.slang`,
  `x86_encode.slang`, `x86_reloc_patch.slang`, `x86_elf_layout.slang`,
  `x86_elf_write.slang`, and reuse `pack_output.slang`.
- `shaders/codegen/x86_regalloc.slang`: add a real liveness/pressure/spill-slot
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
  wired" to "x86 is wired only through direct GPU HIR passes." Add negative
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
