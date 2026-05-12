# x86_64 GPU Backend Wiring Plan

This plan advances the `stdlib/PLAN.md` native-output row while preserving the
current no-CPU-fallback objective. The target is GPU-only x86_64 ELF emission:
after source read, all frontend analysis, lowering, register allocation,
instruction sizing, relocation, ELF layout, byte packing, and final binary byte
production happen in GPU passes over GPU-resident compiler data.

## Current Evidence

The x86_64 backend exists as a code module, but it is not wired into the compiler
pipeline.

- `src/codegen/mod.rs` exports `pub mod gpu_x86;`.
- `src/codegen/gpu_x86.rs` defines `GpuX86CodeGenerator`,
  `record_x86_from_gpu_token_buffer`, `finish_recorded_x86`, resident buffers,
  x86 status/readback buffers, and pipelines for `x86_regalloc.spv`,
  `x86_from_wasm.spv`, and `pack_output.spv`.
- `shaders/codegen/x86_regalloc.slang` writes `reg_map` and `reg_status`, but it
  is only a fixed/token-index register map over `visible_decl`; it is not a real
  liveness-based allocator.
- `shaders/codegen/x86_from_wasm.slang` emits ELF header bytes and x86_64 machine
  code bytes, but its input is WASM-shaped `body_words`, `bool_body_words`, and
  `functions_words`. It parses WASM opcodes and translates them to x86_64; it is
  not direct x86_64 lowering from HIR/type-check output.
- `src/compiler.rs` has WASM wiring through
  `record_wasm_from_gpu_token_buffer`, but x86 methods intentionally return
  `gpu_x86_unavailable_error()`. `GpuCompiler` has a `wasm_generator` cache and
  no `x86_generator` cache.
- `compile_source_to_x86_64_with_gpu_codegen` and
  `compile_source_to_x86_64_with_gpu_codegen_from_path` read/prepare source and
  then return `"GPU x86_64 codegen is not currently available; the CPU backend
  route has been removed"`.
- `tests/codegen_x86.rs` locks this behavior: missing file errors must happen
  before backend unavailability, and valid source must report x86 backend
  unavailability without dispatch.
- `tests/gpu_audit.rs` explicitly asserts that `compiler.rs` does not contain
  `record_x86_from_gpu_token_buffer`, and has a test named
  `gpu_x86_codegen_module_exists_but_is_not_wired_into_compiler`.

The current state is therefore an intentionally unwired x86 prototype. Wiring it
as-is would not meet the objective because it would still depend on WASM-shaped
intermediate bytes and would not prove direct native emission from GPU-resident
compiler data.

For primitive stdlib helper execution, x86_64 is not the next unblocker. The
current x86 prototype must remain unavailable until it is replaced by direct HIR
lowering, real GPU register allocation, GPU instruction sizing, GPU relocation
patching, and GPU ELF writing. Primitive helpers should not become "native" by
feeding token-driven WASM buffers into `x86_from_wasm`; that would preserve the
same missing HIR/codegen contract and make the compiler path look more complete
than it is.

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

- token buffer and token count;
- source byte buffer for identifier/immediate decoding only where no resolved ID
  exists yet;
- GPU HIR arrays: `hir_kind`, `hir_token_pos`, `hir_token_end`, HIR status, and
  tree capacity;
- type-check metadata: `visible_decl`, `visible_type`, `call_fn_index`,
  `call_return_type`;
- later module/runtime metadata for imports, exports, target capabilities, and
  host ABI declarations.

The direct backend should add these x86-specific GPU buffers.

| Buffer | Producer | Purpose |
| --- | --- | --- |
| `x86_func_meta` | function discovery pass | Function HIR node, parameter count, return type, local count, entry block, ABI kind. |
| `x86_node_func` | function discovery pass | Owning function index per HIR node. |
| `x86_value_kind` | lowering pass | Classifies each HIR value as immediate, local, temp, call result, address, or no value. |
| `x86_vreg_def` | lowering pass | Virtual register defined by each value-producing HIR node. |
| `x86_vreg_type` | lowering pass | Scalar/layout type for each virtual register. |
| `x86_vreg_use_count` | lowering/use pass | Number of uses per virtual register. |
| `x86_use_edges` | use expansion + prefix/scatter | Compact def-use edges `(use_node, vreg, operand_slot)`. |
| `x86_live_start` / `x86_live_end` | liveness pass | Approximate linearized live interval per virtual register for the first slice. |
| `x86_phys_reg` | register allocation pass | Physical register assignment or spill slot for each virtual register. |
| `x86_spill_slot` | register allocation pass | Stack slot index for spilled virtual registers. |
| `x86_inst_count` | instruction sizing pass | Number of x86 instruction records emitted by each HIR node. |
| `x86_inst_offset` | prefix scan | First instruction record for each HIR node. |
| `x86_inst_kind` | instruction selection pass | Fixed-width internal x86 instruction template ID. |
| `x86_inst_arg0..argN` | instruction selection pass | Registers, immediates, stack slots, target function/block IDs. |
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
2. `x86_lower_values`: assign value-producing HIR nodes to virtual registers,
   record constants, locals, calls, returns, branches, and unsupported node
   errors. This must use HIR/type metadata, not source-pattern recognition.
3. `x86_use_count` and `x86_use_scatter`: count operand uses, prefix-sum use
   counts, and scatter def-use edges into compact arrays.
4. `x86_liveness`: compute conservative live intervals in the backend's
   linearized HIR/order space. The first implementation can use one interval per
   vreg from definition to last use; later work can refine per block.
5. `x86_regalloc`: allocate SysV x86_64 registers from a fixed pool
   (`rax`, `rcx`, `rdx`, `rsi`, `rdi`, `r8`-`r11` for caller-saved temps,
   reserving ABI scratch as needed) and assign spill slots. This replaces the
   current fixed `visible_decl` modulo map. It must write explicit failure for
   unsupported pressure before stack-slot spilling exists.
6. `x86_inst_count`: compute instruction record counts per HIR node, including
   prologue/epilogue, argument moves, spill loads/stores, calls, branches, and
   return/exit sequences.
7. `x86_inst_offsets`: prefix-sum instruction counts to assign instruction
   record ranges.
8. `x86_select`: scatter fixed-width x86 instruction records using the register
   allocation and type metadata.
9. `x86_inst_size`: compute exact encoded byte length for every instruction
   record. x86_64 is variable-width, so this cannot assume the RISC-V-style
   fixed instruction width from the paper summaries.
10. `x86_text_offsets`: prefix-sum instruction byte sizes and produce block and
    function byte starts.
11. `x86_encode`: emit instruction bytes into `x86_text_bytes` by byte offset.
12. `x86_reloc_collect` and `x86_reloc_patch`: record and patch relative
    branches/calls on GPU. Relative displacements must not be calculated on the
    CPU after readback.
13. `x86_elf_layout`: compute ELF64 executable layout, entry virtual address,
    program header values, `.text` file offset, and final file length.
14. `x86_elf_write`: write ELF header, program header, padding, and `.text`
    into `x86_file_bytes` on GPU.
15. `pack_output`: pack `x86_file_bytes` into `x86_packed_file_words` for the
    only allowed host readback: copying already-final bytes.

This pass shape follows the paper summaries: use array records, maps, scans,
scatters, reductions, and GPU-side patching instead of recursive CPU compiler
algorithms. The CPU may allocate buffers, dispatch passes, submit command
buffers, check a GPU-written status code, and read back final bytes. It must not
interpret HIR, allocate registers, assemble instructions, patch offsets, write
ELF headers, or repair emitted bytes.

## Minimal First Implementation Slice

The first useful slice should intentionally be small: direct x86_64 ELF emission
for the same narrow single-file subset that the current WASM path can prove
through GPU lexer, parser, type checker, and codegen. It should support:

- `fn main() { return <i32/i64 constant-or-expression>; }`;
- local `let` declarations and scalar arithmetic already accepted by GPU type
  checking;
- boolean expressions and simple `if`/`while` only if the direct HIR lowering
  can produce branch records without routing through WASM-shaped buffers;
- a clear GPU status failure for calls, arrays, imports, modules, generics,
  structs/enums, traits, heap allocation, and host `std` APIs until direct x86
  lowering exists for them.

After WASM has a HIR-driven primitive-helper slice, the first native helper
slice should mirror only that proven no-loop scalar subset: module-local scalar
constants, parameters, return expressions, arithmetic/comparison/boolean ops,
`if`/`else`, and direct calls resolved to GPU function IDs. `while`-based
helpers, `test::assert`, arrays, slices, allocation, and host APIs must still
fail with GPU-written status until their direct x86 lowering and runtime ABI are
implemented.

Exact files to change in that slice:

- `src/compiler.rs`: add `codegen::gpu_x86`, add an `x86_generator:
  OnceLock<Result<gpu_x86::GpuX86CodeGenerator, String>>`, add `x86_generator()`,
  and wire `compile_expanded_source_to_x86_64` through the same resident
  lexer/parser/type-check closure shape as WASM. It must call the new direct
  x86 recorder only inside `with_codegen_buffers`.
- `src/codegen/gpu_x86.rs`: replace the WASM-reuse pipeline list with direct
  x86 passes and direct buffers. Rename the recorder to something like
  `record_x86_elf_from_gpu_hir` so tests cannot confuse it with the existing
  WASM-translating prototype.
- Add direct shader files under `shaders/codegen/`, for example:
  `x86_func_discover.slang`, `x86_lower_values.slang`,
  `x86_use_count.slang`, `x86_use_scatter.slang`, `x86_liveness.slang`,
  `x86_regalloc.slang`, `x86_inst_count.slang`, `x86_inst_offsets.slang`,
  `x86_select.slang`, `x86_inst_size.slang`, `x86_text_offsets.slang`,
  `x86_encode.slang`, `x86_reloc_patch.slang`, `x86_elf_layout.slang`,
  `x86_elf_write.slang`, and reuse `pack_output.slang`.
- `shaders/codegen/x86_regalloc.slang`: replace the current fixed map with the
  liveness/pressure/spill-slot allocator, or create a new direct allocator file
  and stop wiring the old shader.
- Stop wiring `shaders/codegen/x86_from_wasm.slang` from the compiler-facing x86
  path. It can remain temporarily as a prototype only if tests assert it is not
  used by the default x86 compiler route.
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
  token positions, type metadata, declaration/call resolution, and later module
  metadata. Identifier text checks should be limited to temporary intrinsic
  recognition already represented as declarations, and should be removed once
  symbol IDs exist.
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
