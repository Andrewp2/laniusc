# Compiler Debugging And Observability

This guide is for compiler maintainers debugging a failing compile, a surprising
diagnostic, a GPU hang, or a performance regression. It connects the phase
guides to the actual signals the compiler can emit.

Start from the smallest failing source input and the boundary where the failure
first becomes visible. Do not begin with full readback or broad generated tests:
those are expensive and often hide the phase that first broke the contract.

## Debugging Order

Use this order unless the failure is already isolated:

1. Reproduce the issue with the smallest source text or source-pack slice that
   still fails.
2. Decide which boundary reports the first bad fact: CLI/input, lexer, parser,
   type checker, backend, source-pack planning, or GPU infrastructure.
3. Read the status or diagnostic path for that boundary before inspecting later
   phases.
4. Turn on the cheapest signal that can confirm the boundary.
5. Escalate to readback, GPU timing, or benchmark artifacts only after a smaller
   signal cannot answer the question.

The important distinction is between where a failure is reported and where it is
owned. For example, x86 codegen may report an error whose root cause is missing
retained parser or type-check metadata. The fix belongs at the phase boundary
that should have preserved the source-mappable fact, not in a downstream
fallback message.

## Signal Cost

| Signal | Use first when | Cost |
| --- | --- | --- |
| Normal diagnostic output | A user-visible compile/check error is present | Low |
| Generated reference | You need current pass/status/buffer names | Low |
| Host timing | You need coarse stage order or a quick slowdown hint | Low to moderate |
| Pipeline/progress trace | Pipeline creation, submit, or map progress is suspect | Moderate |
| wgpu validation scopes | Bind layouts, resource usage, or submission validity is suspect | Moderate |
| GPU trace JSON | You need a Perfetto/Chrome timeline | Moderate |
| GPU timers | You need device-side spans and timestamp queries are supported | Moderate to high |
| Phase readback | A compact status or retained buffer must be inspected | High |
| Acceptance/performance artifacts | You are making a measured performance claim | High |

Prefer a lower-cost signal when it can answer the same question. Readback maps
can dominate runtime, especially inside generated or benchmark-sized programs.

## Environment Flags

Common interactive debugging flags:

| Flag | Meaning |
| --- | --- |
| `LANIUS_GPU_COMPILE_HOST_TIMING=1` | print host-side compiler stage timings |
| `LANIUS_PERFETTO_TRACE=/path/trace.json` | write Chrome/Perfetto trace events |
| `LANIUS_GPU_TRACE_JSON=/path/trace.json` | alternate trace output path |
| `LANIUS_GPU_PIPELINE_PROGRESS=1` | log submit/map/poll progress |
| `LANIUS_PIPELINE_TRACE=1` | log pipeline creation stages and progress |
| `LANIUS_VALIDATION_SCOPES=1` | wrap selected GPU work in wgpu validation scopes |
| `LANIUS_READBACK=1` | enable optional phase readback in paths that support it |
| `LANIUS_READBACK_TIMEOUT_MS=120000` | set the shared blocking readback timeout |
| `LANIUS_X86_READBACK_TIMEOUT_MS=60000` | set x86-specific readback timeout paths |
| `LANIUS_WASM_READBACK_TIMEOUT_MS=60000` | set WASM-specific status/output readback timeout paths |
| `LANIUS_X86_STATUS_TRACE=1` | copy selected x86 status buffers into a trace readback |
| `LANIUS_BATCH_COMPUTE_PASSES=0` | disable compute-pass batching while debugging pass boundaries |
| `LANIUS_PIPELINE_CACHE_BREAKDOWN=1` | sample and trace pipeline-cache byte size |

Use `LANIUS_GPU_COMPILE_HOST_TIMING=1` before GPU timers when the question is
"which host stage got slower?" Use `LANIUS_PERFETTO_TRACE=...` when comparing
host spans, submit spans, readback spans, and optional GPU spans in one view.
Use `LANIUS_READBACK=1` only when the compact status or retained buffer content
is the evidence you need.
Use [Maintainer tools and generated inputs](maintainer-tools.md) when a triage
path depends on generated tables, fuzz/demo binaries, benchmark scaffolds,
acceptance tiers, shader-loop audits, generated references, or repo maps.

## Boundary Triage

| Symptom | First evidence to inspect | Likely owner |
| --- | --- | --- |
| CLI rejects arguments | `cli.md`, argument parser path, rendered diagnostic | `cli` |
| Formatter output surprises | formatter contract, smallest direct formatting case, CLI/LSP boundary used | `formatter` plus `cli/fmt` or `cli/lsp` |
| LSP request fails | LSP JSON-RPC error data, failure boundary, supported method metadata | `cli/lsp` |
| Generated table or maintainer command is stale | generator output, generated metadata, tool-local check mode | `crates/laniusc-compiler/src/bin` or `tools` |
| Source text tokenizes incorrectly | lexer resident token readback or token table docs | `lexer` |
| Syntax is rejected | parser six-word status and source span mapping | `parser` |
| Parser HIR row is malformed | parser readback validator error and row family | `parser::readback` |
| Compile/check operation mixes stale phase state | resident lock scope, retained buffer wrapper, phase cache release point | `compiler/gpu_compiler` |
| Semantic error points at wrong code | type-check status payload and token/HIR mapping | `type_checker` plus `compiler/gpu_compiler` mapping |
| Backend error lacks a useful label | x86 status detail classification and retained metadata | `codegen` plus retained frontend data |
| x86 backend rejects after type check | x86 status trace, generated x86 status constants, retained parser/type-check rows | `codegen::x86` |
| WASM backend rejects after type check | WASM status words, `WasmOutputError` detail classification, retained token rows | `codegen::wasm` |
| Source-pack build resumes incorrectly | manifest/work-queue validation and claimed batch state | `compiler/source_pack` |
| Stdlib helper type-checks but should not execute | source-root manifest, runtime descriptor contract, backend boundary | `stdlib` plus source-root/package loader and target backend |
| Shader resource mismatch | Slang reflection, Rust resource map, validation scopes | phase owner plus `gpu::passes_core` |
| Slow compile with no wrong output | host timing, trace JSON, then benchmark artifacts | phase that owns the slow span |
| Readback appears hung | GPU progress logs, readback timeout, validation scope | `gpu::passes_core` or owning phase |

The generated reference is useful before editing because it lists current shader
load sites, status codes, buffer carrier structs, and Rustdoc coverage:

```bash
tools/compiler_inventory.py --check docs/compiler/generated/reference.md
```

If that check fails, regenerate the reference first or avoid relying on stale
generated tables.

## Parser Failures

Parser status is a six-word GPU/host transport record. The diagnostic owner is
the host mapping that turns the token position and parser code into a source
label. See `diagnostics.md` for the layout and `parser.md` for parser pass
ownership. Use `parser-readback.md` when the parser accepts/rejects correctly
but a parser-owned HIR row, list relation, source address, or retained parser
fact is internally malformed.

When a valid-looking source file is rejected:

1. Minimize to the smallest source that still fails.
2. Check whether the failing token position points at the user construct that
   made the parse impossible.
3. If the position is a derived token or sentinel, inspect the parser pass that
   wrote the status and preserve a better source token there.
4. Add a focused diagnostic test with the minimized source.

For fixed pass-count or loop-exhaustion errors, the status should point at the
construct whose shape exceeded the algorithmic limit. If the limit can be
replaced with a scan, range query, or segmented formulation, remove the error
instead of documenting it as an accepted language restriction.

## Type-Check Failures

The resident type checker reports a four-word status record. The code is a
`GpuTypeCheckCode`; the other words are only useful if the host can map them
back to a token, HIR node, source file, or retained row with source metadata.

When a type-check diagnostic is wrong:

1. Identify the `GpuTypeCheckCode` in `generated/reference.md`.
2. Find the shader or Rust record site that writes the status payload.
3. Check whether the payload is source-mappable without guessing.
4. If the payload is only a row id, preserve the token/HIR owner at the pass
   that creates the row.
5. Map the status in `compiler/gpu_compiler/typecheck.rs` or the source-pack
   equivalent.

Do not surface raw GPU rows, path ids, or capacity counters when a source token
or HIR node can be carried cheaply. A status that cannot become a user-facing
source label is an incomplete compiler contract.

## Backend And x86 Failures

x86 lowering depends on retained frontend metadata. A backend diagnostic can be
correct only when the backend knows whether its detail payload is a token, HIR
node, or backend-local row.

Use this order for x86 failures:

1. Confirm parser and type-check status accepted the input.
2. Check the generated `X86_ERR_*` inventory in `generated/reference.md`.
3. Inspect `detail_is_hir_node` and `detail_is_token` classification.
4. If necessary, enable `LANIUS_X86_STATUS_TRACE=1` to copy selected status
   buffers into a contiguous readback.
5. Use `LANIUS_X86_READBACK_TIMEOUT_MS=...` when the readback timeout itself is
   the suspected failure.

If a backend error reports "internal" or a raw detail value for a source-level
construct, fix the retained metadata or detail classification. Do not add a
catch-all diagnostic that hides the missing source mapping.

## WASM Failures

WASM lowering depends on retained parser/type-check metadata, but its current
support surface is narrower than x86. A WASM rejection is expected for some
unsupported source shapes; the debugging question is whether the rejection is
fail-closed, source-addressable, and owned by the right boundary.

Use this order for WASM failures:

1. Confirm parser and type-check status accepted the input.
2. Read [WASM backend internals](wasm-backend.md) for the current stage order
   and status mapping.
3. Check whether `WasmOutputError::detail_is_token` should classify the detail
   as a token.
4. Use `LANIUS_WASM_TRACE=1` to confirm which Rust-side WASM stage ran last.
5. Use `LANIUS_WASM_READBACK_TIMEOUT_MS=...` only when the status or output
   readback timeout is itself the suspected failure.

If the WASM backend labels the first source byte for a construct that has a
better token or HIR node available, fix the status detail or retained metadata.
Do not document the fallback span as acceptable source mapping.

## GPU Setup And Submission

Use the GPU guide for infrastructure ownership and this checklist for debugging:

1. If pipeline creation fails, enable `LANIUS_PIPELINE_TRACE=1` and inspect the
   shader key, SPIR-V path, reflection path, and reflected thread-group size.
2. If bind groups fail validation, enable `LANIUS_VALIDATION_SCOPES=1` and
   compare the Slang parameter names with the Rust resource map.
3. If pass ordering is suspect, temporarily set `LANIUS_BATCH_COMPUTE_PASSES=0`
   so compatible passes are not combined into one compute pass.
4. If submit or readback appears stuck, use `LANIUS_GPU_PIPELINE_PROGRESS=1` and
   the readback timeout flag before adding more readbacks.
5. If timing is needed, prefer host trace spans first; add GPU timers only when
   device timestamp support is relevant to the question.

Reflection removes hand-written binding indices, but it does not remove the
resource-name contract. The shader parameter name, Rust bind resource name, and
resident buffer lifetime must still change together.

## Source-Pack Debugging

Source packs add persistence, manifests, artifacts, and resumable work queues to
the same compiler phases. Debug them at the planning boundary before blaming
individual shader passes.

First inspect:

- package lock/source scan output for the source file set
- manifest paths and target-specific artifact descriptors
- source-file metadata that maps packed file ids back to paths
- work-queue claims, completion state, and ready batch indexes
- validation modules under `compiler/source_pack/validation`

If a single-source compile works and the equivalent source-pack compile fails,
look for missing file id, artifact id, or source span metadata. Source-pack
diagnostics should point at the original file path and byte span, not the packed
storage layout.

## Performance Debugging

Do not make a performance claim from an incidental local run. Use the signal
that matches the claim:

| Claim | Required evidence |
| --- | --- |
| A stage got slower | host timing before and after, same input and build profile |
| A GPU pass got slower | GPU timing or trace spans with timestamp support noted |
| Readback dominates runtime | trace/readback spans and the flags used |
| Generated input scale is acceptable | acceptance/performance artifacts with line count, seed, command env, and hardware |
| A shader loop is safe | shader-loop audit plus focused compile evidence |

For broad measurement checkpoints, use `tools/compiler_acceptance.sh` rather
than ad hoc commands. It records command environment, trace paths, source
replay, hashes, resource usage, and optional VRAM evidence. Keep those artifacts
out of hand-written docs unless the doc is explicitly recording a measured
result.

## Adding A New Signal

Add observability at the boundary that owns the fact:

1. Prefer existing diagnostics/status over a new debug-only path.
2. If the signal is user-facing, route it through diagnostics.
3. If the signal is maintainer-facing, choose host trace, progress log, timer,
   or readback based on cost.
4. Document any new environment flag in `gpu.md` or the owning phase guide.
5. Add generated-reference extraction only for facts expected to change often.
6. Add focused tests for pure decoding or mapping helpers.

Compatibility aliases for old flags are not useful unless another human
maintainer or user actually depends on them. Otherwise they create fake evidence
that the old path is important and make debugging harder.

## Stop Conditions

Stop debugging when the evidence reaches the owning boundary:

- a minimized source proves the diagnostic span and message
- a generated-reference check proves inventories are current
- a validation scope points at a concrete resource contract
- a trace shows the slow span being claimed
- a readback proves the exact status payload written by the owning pass

Do not keep widening tests or readbacks after the boundary is clear. Convert the
evidence into a focused fix and a focused regression check.
