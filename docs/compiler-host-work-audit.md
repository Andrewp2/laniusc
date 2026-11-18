# Compiler host work audit

This audit lists every readback and every host compiler step in the compile path as of 2026-11-17. It is the reference for the readback allowlist in `crates/laniusc-compiler/src/gpu/readback_limit_tests.rs`. Each `ToRemove` entry there names a row here.

The rule this audit measures against:

- Source bytes go into one buffer on the GPU.
- Kernels turn them into x86 or WASM.
- The host only orchestrates. It reads files, allocates and uploads buffers, records and submits commands, and writes the output file.
- The host reads back once at the end, for the output and its status.
- After an overflow status, the host reruns with larger capacities.
- A failed build reads its diagnostics.

## How the data was taken

| Item | Value |
|---|---|
| Branch | `t3/gpu-retention-readback`, on top of `7096099f5` |
| Settings build | `tools/benchmark_settings_recompile.py --profile`, resident daemon, native x86 link, `LANIUS_REPORT=host-timing` |
| Settings source | 1,796,387 bytes, 443,871 tokens |
| Settings output | 5,866,080 bytes, executable hash `115a4d52a2ae77e0` |
| Settings VRAM peak | 5,875,808,000 bytes on a warm job, 6,646,556,824 on the first job, of 24 GB |
| Other modes | `laniusc` CLI on `tests/fixtures/language/closure.lani`, `--no-daemon` |
| Byte counts | the `readback.map: label=… bytes=…` line that `begin_readback_map` prints under `LANIUS_REPORT=host-timing` |
| Static sites | every `readback_label!("…")` in `crates/laniusc-compiler/src` |

The CLI modes probed:

| Mode | Command | Readbacks |
|---|---|---|
| check | `laniusc check --stdlib-root stdlib closure.lani` | 38 |
| x86 | `laniusc --no-daemon closure.lani -o out` | 29 |
| native | `laniusc --no-daemon --native-link closure.lani -o out` | 27 |
| host link | `laniusc --no-daemon --native-linker cc closure.lani -o out` | 27 |
| WASM | `laniusc --no-daemon --emit wasm simple.lani -o out.wasm` | 20 |
| WASM, unsupported feature | `laniusc --no-daemon --emit wasm closure.lani` | 14, fails in lowering |
| failed build | `laniusc --no-daemon bad.lani` with a type error | 7 |

Two observations from the probes:

- `laniusc check` runs the frontend twice. The first pass does not record the closure desugaring round. It fails type checking, reads one diagnostic token and the desugar sizes, then reruns everything (row R37).
- `laniusc check` lowers, retains, finalizes and links an x86 executable after the rerun. It reads `codegen.x86.link.page` and discards the bytes.

## Readbacks

Classes:

- **status**: the host checks a status word and continues or stops.
- **size**: the host reads a count to size a later buffer or dispatch.
- **data**: the host computes on the bytes it reads.
- **output**: the final output of a mode.
- **diagnostics**: the error of a failed build.

Removal methods:

- **gate**: later passes read a GPU status word and do nothing on failure. The status reaches the host with the final output.
- **bound**: the capacity comes from the source byte count or an existing capacity. An overflow sets a status, and the host reruns with larger capacities.
- **kernel**: a kernel does the host's computation, and its result stays on the GPU.
- **resident**: the consumer reads the buffer on the GPU instead of the host reading it.
- **merge**: the read joins another permanent read.
- **delete**: the path is not used by any mode and is removed.

### The settings build, in order (19 round trips at the audit, 18 since `cad995188` removed R10)

"Per build" counts round trips on one settings job. Bytes are the mapped range.

| Row | Label | File and line | Per build | Reads | Host does with it | Class | Removal |
|---|---|---|---|---|---|---|---|
| R1 | `semantic-interface artifact metadata` | `type_checker/semantic_interface.rs:2100` | 1 | 24 B: interface length and status | sizes the R2 read | size | resident (T3) |
| R2 | `semantic-interface artifact` | `type_checker/semantic_interface.rs:2142` | 1 | 1,422,084 B: the semantic interface | keeps it on the host for dependents | data | resident (T3) |
| R3 | `lexer.source-pack.fused.metadata` | `compiler/gpu_compiler/typecheck.rs:2047` | 1 | 12 B: token count and lexer error | checks the lexer error | status | gate (T1) |
| R4 | `parser.recorded-ll1-hir.status` | `parser/driver/results.rs:546`, `parser/driver/recorded.rs:197` | 1 | 44 B: parser status and feature flags | checks parse success | status | gate (T1) |
| R5 | `type_check.call_inference` | `type_checker/resident.rs:2185`, `:2805` | 1 | 264 B: call inference counters | checks inference completion | status | gate (T1) |
| R6 | `type_check.canonical.counts` | `type_checker/resident.rs:2757`, `:2840`, `:2858` | 1 | 64 B: canonical type counters | decides whether to record canonical rounds again | size | bound (T2) |
| R7 | `type_check.status` | `type_checker/resident.rs:2843`, `:2861` | 1 | 16 B: type check status | checks for a type error | status | gate (T1) |
| R8 | `lowering status readback` | `codegen/lowering_pipeline.rs:1520` | 1 | 128 B: lowering status and x86 object metadata | sizes the R9 read | size | resident (T4) |
| R9 | `x86 object payload readback` | `codegen/x86_object_artifact.rs:873` | 1 | 455,400 B: object sections, relocations and call rows | parses the object for retention and the link | data | resident (T4) |
| R10 | `program_retention.readback` | `type_checker/program_retention.rs:1470` | 0 since `cad995188` | export status of a build with no x86 or WASM object, such as `check` (`finish_export_now`) | checks the export commit | status | gate (T7). The settings build reads the commit status words with R9. |
| R11 | `retained_substitution.readback` | `type_checker/program_retention/substitution.rs:1013` | 1 | 5,132 B: substitution status and counts | sizes discovery | size | bound (T5) |
| R12 | `discovery.status` | `type_checker/program_retention/discovery.rs:1690` | 1 | 5,524 B: discovery status and counts | sizes the projection | size | bound (T5) |
| R13 | `retained_projection.readback`, first | `type_checker/program_retention/projection.rs:1226` | 1 | 256 B: projection counts | sizes the R14 read | size | bound (T5) |
| R14 | `retained_projection.readback`, second | same site | 1 | 4,476 B: projection rows | builds the instance inputs | data | kernel (T5) |
| R15 | `lowering status readback`, instance | same site as R8 | 1 | 128 B: status and object metadata | sizes the R16 read | size | resident (T4) |
| R16 | `x86 object payload readback`, instance | same site as R9 | 1 | 126,892 B: the instance object | parses it for the link | data | resident (T4) |
| R17 | `codegen.x86.finalize.readback` | `codegen/x86/symbol_finalization.rs:761` | 1 | 285,536 B: finalize status, symbol records and identity words | checks demand against capacity and names symbols for the link | data | resident (T4) |
| R18 | `codegen.x86.link.resident.plan` | `codegen/x86/link/resident_linking.rs:1204`, `:1373` | 1 | 400 B: link status, C name status and image length | sizes the image copy | size | bound (T6) |
| R19 | `codegen.x86.link.resident.image` | `codegen/x86/link/resident_linking.rs:1425` | 1 | 5,866,080 B: the executable | writes the file | output | permanent |

### Sites the settings build does not reach, reached by the CLI modes

| Row | Label | File and line | Modes, per build | Reads | Host does with it | Class | Removal |
|---|---|---|---|---|---|---|---|
| R20 | `lex.source-pack.resident.count` | `lexer/driver.rs:1013` | all CLI, 1–2 | 12 B: token count | sizes the parser buffers | size | bound (T2) |
| R21 | `parser.partial_parse_tree_capacity.status` | `parser/driver.rs:604` | all CLI, 1 | 44 B: parse tree size | sizes the tree buffer | size | bound (T2) |
| R22 | `retained producer state` | `compiler/gpu_compiler/trait_solver/dispatch/retained.rs:798` | x86, native, WASM, 1 | 496 B: trait producer counters | sizes the catalog | size | bound (T7) |
| R23 | `program proof wave progress` | `compiler/gpu_compiler/trait_solver/dispatch/mod.rs:1022` | x86, native, 2 | 760 B each: proof directory, receipt and result rows | decides another wave | data | kernel (T7) |
| R24 | `retained catalog admission` | `compiler/gpu_compiler/trait_solver/dispatch/retained.rs:1431` | x86, native, 1 | 176 B: admission receipts | checks admission | status | gate (T7) |
| R25 | `codegen.x86.link.symbol_partition.status` | `codegen/x86/link/symbol_resolution.rs:489` | x86, 1 | 16 B: partition status and count | sizes the R26 read | size | delete with the GPU-only x86 link (T7) |
| R26 | `codegen.x86.link.symbol_partition.values` | `codegen/x86/link/symbol_resolution.rs:520` | x86, 1 | 92 B: resolved symbol values | lays out sections | data | delete (T7) |
| R27 | `codegen.x86.link.layout_chunk` | `codegen/x86/link/section_layout.rs:432` | x86, 1 | 16 B: layout chunk rows | places sections | data | delete (T7) |
| R28 | `codegen.x86.link.page` | `codegen/x86/link/executable.rs:761` | x86, check, 1 | 65,568 B: the executable page | writes the file | output | permanent |
| R29 | `codegen.x86.link.resident.sections` | `codegen/x86/link/resident_linking.rs:288` | host link, 2 | 19,412 B: text and rodata | hands them to the host linker | output | permanent |
| R30 | `Wasm object metadata readback` | `codegen/wasm_object_artifact.rs:476` | WASM, 1 | 96 B: object status and lengths | sizes the R31 read | size | resident (T8) |
| R31 | `Wasm object payload readback` | `codegen/wasm_object_artifact.rs:562` | WASM, 1 | 128 B: the WASM object | parses it for the link | data | resident (T8) |
| R32 | `codegen.wasm.link.resolve.status` | `codegen/wasm/link/symbol_resolution.rs:550` | WASM, 1 | 16 B: resolution status | checks it and sizes the target read | size | gate (T8) |
| R33 | `codegen.wasm.link.page.output` | `codegen/wasm/link/executable.rs:500` | WASM, 1 | 65,536 B: the module page | writes the file | output | permanent |
| R34 | `codegen.wasm.link.page.status` | `codegen/wasm/link/executable.rs:506` | WASM, 1 | 16 B: link status | checks it beside the output | status | merge into R33 (T8) |
| R35 | `compiler.typecheck.diagnostic-token` | `compiler/gpu_compiler/typecheck.rs:4735` | failed builds, check, 1 | 12 B: the token of the first error | renders the diagnostic | diagnostics | permanent |
| R36 | `compiler.lowering.diagnostic-hir` | `compiler/gpu_compiler/typecheck.rs:3375` | WASM failure, 1 | 16 B: the HIR row of the error | finds its token | diagnostics | merge into R35 (T9) |
| R37 | `desugar.readback` | `compiler/desugar.rs:296` | check, WASM failure, 1 | 768 B: desugar round sizes | sizes the rerun | size | bound and record every round (T10) |

### Sites no probed mode reaches

These compile and are called from the compile path, but none of the probes reached them. Each is a candidate for deletion. One that stays needs the removal in its row.

| Row | Label | File and line | Reads | Class | Removal |
|---|---|---|---|---|---|
| U1 | `lex.count` | `lexer/driver.rs:347` | token count of the standalone lexer | size | delete (T12) |
| U2 | `lex.tokens` | `lexer/driver.rs:406` | tokens of the standalone lexer | data | delete (T12) |
| U3 | `lex.resident.count` | `lexer/driver.rs:1335`, `:1518`, `:1707` | token count | size | bound (T2) |
| U4 | `lex.source-pack.count` | `lexer/driver/readback.rs:46` | token count of a source pack | size | delete (T12) |
| U5 | `lex.source-pack.tokens` | `lexer/driver/readback.rs:91` | tokens of a source pack | data | delete (T12) |
| U6 | `lexer.fused.metadata` | `compiler/gpu_compiler/typecheck.rs:1629` | token count and lexer error | status | gate (T1) |
| U7 | `parser.readback` | `parser/readback.rs:1479`, `:1616` | parse results | data | delete (T12) |
| U8 | `parser.hir_item_readback` | `parser/readback/hir_item_readbacks.rs:1347`, `:1527` | HIR items | data | delete (T12) |
| U9 | `parser.hir_fn_return_readback` | `parser/readback/hir_item_readbacks/function_return_readbacks.rs:215` | function return records | data | delete (T12) |
| U10 | `parser.hir_semantic_count` | `parser/driver/recorded.rs:48` | HIR counts | size | bound (T2) |
| U11 | `parser.resident-ll1.status` | `parser/driver.rs:196` | parser status | status | gate (T1) |
| U12 | `parser.resident-tree` | `parser/driver/resident_tree.rs:61`, `:2486` | the parse tree | data | delete (T12) |
| U13 | `parser.syntax.status_counters` | `parser/syntax.rs:1727` | syntax check status | status | gate (T1) |
| U14 | `compiler.syntax.diagnostic-token` | `compiler/diagnostics.rs:3996` | token of a syntax error | diagnostics | merge into R35 (T9) |
| U15 | `type_check.canonical` | `type_checker/resident.rs:372` | canonical counters, synchronous mode | size | bound (T2) |
| U16 | `type_check.preflight_capacities` | `type_checker/preflight.rs:262` | module record capacities | size | bound (T2) |
| U17 | `checked contract facts` | `type_checker/checked_contracts.rs:460` | contract facts | data | kernel (T5) |
| U18 | `generic call counts` | `type_checker/generic_calls.rs:2019` | generic call counts | size | kernel (T5) |
| U19 | `generic call claims` | `type_checker/generic_calls.rs:2156` | call claims | data | kernel (T5) |
| U20 | `generic call rows` | `type_checker/generic_calls.rs:1251` and four more | call rows | data | kernel (T5) |
| U21 | `checked type frontier` | `type_checker/generic_calls.rs:1353` | type rows | data | kernel (T5) |
| U22 | `checked nominal frontier` | `type_checker/generic_calls.rs:1456` | argument rows | data | kernel (T5) |
| U23 | `retained constant frontier` | `type_checker/generic_calls.rs:1631` | constant atoms | data | kernel (T5) |
| U24 | `retained binder links` | `type_checker/generic_calls.rs:2389` | binder links | data | kernel (T5) |
| U25 | `checked result constants` | `type_checker/generic_calls.rs:2906` | result constants | data | kernel (T5) |
| U26 | `checked contextual arguments` | `type_checker/generic_calls.rs:3014` | contextual arguments | data | kernel (T5) |
| U27 | `instance closure` | `type_checker/generic_calls.rs:3187` | the instance closure | data | kernel (T5) |
| U28 | `instance exec entries` | `type_checker/generic_calls.rs:3329` | instance execution rows | data | kernel (T5) |
| U29 | `method_routes.state` | `type_checker/program_retention/method_routes.rs:234` | route state | status | gate (T5) |
| U30 | `retained_schema.status` | `type_checker/program_retention/projection/schema.rs:323` | schema status | status | gate (T5) |
| U31 | `retained publication status` | `compiler/gpu_compiler/trait_solver/dispatch/retained.rs:1267` | publication status and store counters | status | gate (T7) |
| U32 | `retained route query` | `compiler/gpu_compiler/trait_solver/dispatch/retained.rs:1393` | a route view | data | kernel (T7) |
| U33 | `retained diagnostic` | `compiler/gpu_compiler/trait_solver/dispatch/retained.rs:1304` | span of a refuted call | diagnostics | merge into R35 (T9) |
| U34 | `closed store counters` | `compiler/gpu_compiler/trait_solver/dispatch/retained/closed.rs:485` | closed solver counters | size | bound (T7) |
| U35 | `closed trait demand` | `compiler/gpu_compiler/trait_solver/dispatch/retained/closed.rs:619` | closed solver demand | data | kernel (T7) |
| U36 | `closed publication receipt` | `compiler/gpu_compiler/trait_solver/dispatch/retained/closed.rs:790` | closed solver status | status | gate (T7) |
| U37 | `native layout completions` | `compiler/gpu_compiler/trait_solver/dispatch/native_layout.rs:194` | layout completion rows | data | kernel (T7) |
| U38 | `native semantic graph prefixes` | `compiler/gpu_compiler/trait_solver/dispatch/native_layout.rs:270` | semantic graph prefixes | data | kernel (T7) |
| U39 | `implementation projection receipt` | `compiler/gpu_compiler/trait_solver/dispatch/implementation_application.rs:324` | status and counts | size | bound (T7) |
| U40 | `implementation application rows` | `compiler/gpu_compiler/trait_solver/dispatch/implementation_application.rs:355` | implementation rows | data | kernel (T7) |
| U41 | `semantic-interface validation` | `compiler/semantic_interface/gpu_validation.rs:209` | validation status of stored interfaces | status | gate (T3) |
| U42 | `x86 artifact length readback` | `codegen/x86_artifact.rs:489` | unlinked x86 artifact length | size | delete, or bound if the path stays (T12) |
| U43 | `x86 artifact byte readback` | `codegen/x86_artifact.rs:506` | unlinked x86 artifact | output | delete, or permanent if the path stays (T12) |
| U44 | `Wasm artifact length readback` | `codegen/wasm_lowering.rs:839` | unlinked WASM artifact length | size | delete, or bound (T12) |
| U45 | `Wasm artifact byte readback` | `codegen/wasm_lowering.rs:857` | unlinked WASM artifact | output | delete, or permanent (T12) |
| U46 | `codegen.wasm.link.resolve.targets` | `codegen/wasm/link/symbol_resolution.rs:570` | WASM symbol targets | data | resident (T8) |

### Readbacks outside the compile path

The test holds these to their files with `debug_readback_label!`. A normal build does not run them.

| File | Labels | Why |
|---|---|---|
| `bin/shader_dispatch_replay.rs` | `replay` | the shader replay tool |
| `codegen/lowering_capture.rs` | `lowering capture` | the lowering capture tool |
| `gpu/dispatch_capture.rs` | `lanius-debug-capture` | the dispatch capture tool |
| `gpu/passes_core.rs` | `lanius-debug-dump` | the buffer dump tool |
| `gpu/timer.rs` | `gpu.timer.readback` | GPU timestamps under a timing report |
| `parser/driver/debug.rs` | five `parser.semantic_token_kinds*` and `parser.token_feature_flags` labels | parser debug dump |
| `compiler/gpu_compiler/trait_solver/dispatch/retained.rs` | `retained batch directory`, `retained rows`, `retained routes` | opt-in row assertions and a test oracle |
| `lexer/driver.rs` | `lexer.parser_feature_flags.debug` | test oracle |
| `type_checker/program_retention/projection.rs` | `retained_projection.test_readback` | test oracle |
| `type_checker/generic_calls.rs` | `instance table`, `instance table counts`, `instance table function tokens` | instance table validation mode |
| `type_checker/resident.rs` | `type_check.canonical.validation` | canonical validation mode |

### Row counts by class

| Class | Settings rows (R1–R19) | CLI rows (R20–R37) | Unreached rows (U1–U46) | All rows |
|---|---|---|---|---|
| status | 4 | 2 | 8 | 14 |
| size | 8 | 7 | 11 | 26 |
| data | 6 | 4 | 23 | 33 |
| output | 1 | 3 | 2 | 6 |
| diagnostics | 0 | 2 | 2 | 4 |
| total | 19 | 18 | 46 | 83 |

The 83 rows cover 80 labels. R13 and R14 share a label, and so do R8 with R15 and R9 with R16. The allowlist has 5 permanent labels and 75 to remove.

## Size readbacks: bounds and VRAM

The settings capacities come from `LANIUS_REPORT=buffers,memory` on the same job. "Not logged" means no report prints that capacity today. The task that removes the row adds the log.

| Row | Count it reads | Upper bound that replaces it | Capacity now | Used on settings | Bound-sized capacity |
|---|---|---|---|---|---|
| R1 | interface length | interface capacity, already allocated | 251,658,240 B | 1,422,083 B | no change. The interface stays on the GPU. |
| R6 | canonical type rows | types capacity of the semantic interface | 1,843,218 types | not logged | no change |
| R8, R15 | object section lengths | `artifact_bytes` of the lowering arena, already allocated | 32,137,216 B | 455,400 B and 126,892 B | no change. The object stays on the GPU. |
| R11 | substitution rows | instance rows ≤ call rows | not logged | 5,132 B read | not logged |
| R12 | discovery rows | call rows, 466,944 in the lowering arena | not logged | 5,524 B read | not logged |
| R13 | projection rows | discovery rows | not logged | 4,476 B read | not logged |
| R18 | image length | sum of object capacities plus the dynamic table bound, at most `max_output_bytes` (256 MiB) | output buffer already sized to the bound | 5,866,080 B | no VRAM change. See T6 for the read. |
| R20, U3 | tokens | source bytes | 466,944 tokens | 443,871 tokens | see below |
| R21 | parse tree rows | 6.6 rows per token, measured | 2,940,928 rows | 2,891,776 rows | see below |
| R22, U34 | catalog rows | implementations and predicates of the semantic interface | not logged | 496 B read | not logged |
| R25 | symbol partitions | object symbol capacity | not logged | 16 B read | removed with the GPU-only x86 link |
| R30 | WASM object lengths | WASM artifact capacity, already allocated | not logged | 96 B read | no change. The object stays on the GPU. |
| R32 | WASM resolve targets | object symbol capacity | not logged | 16 B read | no change |
| R37 | desugar round sizes | 1.25 × tokens for rows, measured capacity for pieces and regions | 499,420 token rows, 611,694 output rows | `needs=[0,0,0,0]` | no change. Record every round. |
| U10, U16 | HIR and module record counts | token count | not logged | not reached | follows the token bound |
| U39 | implementation rows | implementations of the semantic interface | not logged | not reached | not logged |
| U42, U44 | unlinked artifact length | artifact capacity, already allocated | 32,137,216 B | not reached | no change |

### The token bound

The parser buffers scale with the token capacity. Settings has 1,249 MB of resident parser workspace at 466,944 tokens, about 2,675 B per token.

| Token bound | Tokens | Parser workspace | Peak VRAM |
|---|---|---|---|
| Now, measured by a readback | 466,944 | 1,249 MB | 5.88 GB |
| One token per source byte | 1,796,387 | about 4,805 MB | about 9.4 GB |
| 0.35 tokens per byte, overflow reruns | 628,736 | about 1,682 MB | about 6.3 GB |

- One token per byte is a hard bound and needs no rerun. It fits in 24 GB.
- A ratio bound costs about 0.4 GB on settings. A source above 0.35 tokens per byte overflows once and reruns with the one-per-byte bound.
- Settings has 0.247 tokens per byte.
- The resident daemon already sizes its parser before R3, from the capacity of the previous job. R3 is a status check there.

## Host steps

Times are from the settings job under `LANIUS_REPORT=host-timing`. "Orchestration" means reading files, allocating, uploading, recording, submitting, waiting, rerunning after an overflow, or writing the output.

| Step | File and line | Settings time | What it computes | Class | Why compiler work |
|---|---|---|---|---|---|
| H1 source discovery and import scan | `compiler/public_planning_api/inputs.rs:500`, `:937` | 0.92 ms (`daemon.job.sources_planned`, includes H2) | parses `import` lines from source text and resolves them to files | compiler work | The GPU parser and module resolver already parse and resolve imports. |
| H2 closure trait inclusion | removed | — | removed: `core::function` is a language item. The type checker resolves `core::function::*` without an import edge (`10c_resolve_qualified_paths`), the closure desugar inserts no import, and a build with a stdlib root always loads the module | — | Done in T10 step 1. |
| H3 daemon source cache | `cli/daemon.rs:281`, `:1949` | in H1 | reuses the last job's import graph when file contents match | compiler work | It caches the result of H1. |
| H4 desugar round selection and rerun | `compiler/desugar.rs:660` | not timed | records only rounds earlier builds used, and reruns when a source needs another | orchestration | It reruns after a status. It doubles the frontend on a cold `check`. |
| H5 capacity planning from readback counts | `lexer/driver/inputs.rs:26`, `parser/driver/resident_buffers.rs:174`, `compiler/desugar.rs:241`, `type_checker/resident.rs:2757` | under 0.1 ms each | sizes buffers from R6, R20, R21 and R37 | orchestration | It allocates. The counts it needs are size readbacks. |
| H6 `finish.parser_status` | `compiler/gpu_compiler/typecheck.rs:981` | 0.032 ms | checks R4 | orchestration | |
| H7 `finish.typecheck_status` | `compiler/gpu_compiler/typecheck.rs:1004` | 0.083 ms | checks R5 to R7 | orchestration | |
| H8 `finish.semantic_interface` | `compiler/gpu_compiler/typecheck.rs:1062` | 0.040 ms | keeps the R2 bytes on the host for dependents | compiler work | Dependents could read the interface on the GPU. |
| H9 `finish.target_artifact` | `compiler/gpu_compiler/typecheck.rs:1093` | 0.012 ms | takes the target artifact handle | orchestration | |
| H10 `finish.native_object` | `compiler/gpu_compiler/typecheck.rs:1155`, `codegen/x86_object_artifact.rs:742`, `:812` | 0.485 ms | parses the object metadata and payload from R8 and R9 | compiler work | The host decodes sections, relocations and call rows that the link and retention use on the GPU. |
| H11 `finish.program_retention` | `compiler/gpu_compiler/typecheck.rs:1185` | 0.015–0.029 ms since `cad995188`, 2.073 ms before | checks the commit status words read with R9. The export and the call rewrite run in kernels. | orchestration | Removed as compiler work. The store is sized from the source byte count, and an overflow rolls back on the GPU (`export/19_uncommit`) and reruns. |
| H12 `finish.unit_facts` | `compiler/gpu_compiler/typecheck.rs:1211`, `type_checker/generic_calls.rs:2019` | 0.015 ms, elided on settings | decodes checked unit facts (U17 to U28) | compiler work | Other builds decode type and call facts on the host. |
| H13 retention planning between submits | `compiler/gpu_compiler/retained_native.rs:692` | 2.938 ms (`tail.after_projection`) | reads R11 to R14 and builds each next stage's inputs | compiler work | It plans instances from counts and rows on the host. |
| H14 `tail.instance.finish_object` | `compiler/gpu_compiler/retained_projection.rs:125` | 0.218 ms | parses the instance object from R15 and R16 | compiler work | Same as H10. |
| H15 `tail.finalize` | `compiler/gpu_compiler/retained_native.rs:704`, `codegen/x86/symbol_finalization.rs:740` | 0.249 ms | checks symbol demand and reads symbol records from R17 | compiler work | The link reads the symbol records, and they can stay on the GPU. |
| H16 `tail.native.resident.inputs` | `codegen/x86/native/resolve.rs:481`, `:303`, `:119` | 0.577 ms | finds libraries on disk, parses ELF symbol tables and archive indexes, and caches them by file stamp | compiler work | File reads are orchestration, but parsing symbol tables is linking. The cache keeps parsed results. |
| H17 `tail.native.resident.record` | `codegen/x86/link/resident_linking.rs:872` | 0.581 ms | maps parked objects to slots and records the link | orchestration | |
| H18 link waits and image recording | `codegen/x86/link/resident_linking.rs:1341`, `:1415`, `:548` | 0.466, 0.051, 0.669 ms | waits on R18 and R19 and records the image copy | orchestration | |
| H19 output write | `compiler/gpu_compiler/retained_native.rs:766`, `:780` | 2.115 ms, of which 0.998 ms is the file | writes the executable | orchestration | |
| H20 diagnostics rendering | `compiler/diagnostics.rs:4256` | failed builds only | turns the token span from R35 into source text and a message | orchestration | It is the failed-build exception. |
| H21 GPU-linker x86 layout | `codegen/x86/link/symbol_resolution.rs:489`, `codegen/x86/link/section_layout.rs:432` | CLI only | lays out sections from R25 to R27 | compiler work | The resident link does the same on the GPU. |
| H22 WASM object and link | `codegen/wasm_object_artifact.rs:476`, `codegen/wasm/link/symbol_resolution.rs:550` | WASM only | parses the WASM object and resolves symbols from R30 to R32 | compiler work | Same pattern as H10 and H21. |
| H23 check mode codegen | `cli/compile/entry.rs:68` | CLI only | `check` lowers, retains, finalizes and links an executable it discards | compiler work | A check needs only the frontend status. |

Host step counts at the audit: 9 orchestration rows and 14 compiler-work rows. H11 has since moved to orchestration.

## Proposed order of removal

Each task fits one sitting. "Needs" lists the tasks that must land first.

| Task | Removes | Needs | Work |
|---|---|---|---|
| T1 frontend gate | R3, R4, R5, R7, U6, U11, U13 | none | One GPU status block that lexer, parser and type check write. Later passes read it and zero their indirect dispatch on failure. The final output read carries it. |
| T2 frontend capacities from source bytes | R6, R20, R21, U3, U10, U15, U16 | T1 | Size tokens, tree and canonical rows from the source byte count with the ratio bound. Overflow sets a bit in the T1 status, and the host reruns with the one-per-byte bound. |
| T3 semantic interface on the GPU | R1, R2, U41, H8 | none | Dependents read the interface from a GPU store. It reaches the host only when a library build asks for it as output. |
| T4a retention reads the object on the GPU | R8, R9, R15, R16, H10, H11, H14 | none | `provisionalize_x86_calls` and the instance object finish become kernels over the parked object. |
| T4b finalize symbols stay on the GPU | R17, H15 | T4a | The resident link reads the finalize symbol records on the GPU. Demand and capacity go into the T1 status. |
| T5 retention planning on the GPU | R10 to R14, U17 to U30, H12, H13 | T1, T4a | Substitution, discovery and projection run in one submit with indirect dispatch sized by kernels. Capacities come from call-row bounds. This may need two sittings. |
| T6 one map for the image | R18 | T4b | Write the image into a host-visible buffer sized to the output bound and map it once. Read its length from its header. |
| T7 CLI joins the daemon path | R22 to R27, U31, U32, U34 to U40, H21, H23 | T1 | The CLI x86 build uses the resident link, which deletes the GPU-linker readbacks. Proof waves loop on the GPU with a bounded wave count. `check` stops after the frontend. |
| T8 WASM resident link | R30 to R32, R34, U46, H22 | T1 | The same plan as the x86 resident link. The status joins the output map. |
| T9 one diagnostics read | R36, U14, U33 | T1 | The GPU writes one diagnostic record with the error code and token span. R35 reads it. |
| T10 source discovery on the GPU | R37, H1, H2, H3, H4 | T2 | Upload the entry, the stdlib and the source roots. The GPU module resolver selects the files the entry imports. Record every desugar round, gated on the GPU feature flags. |
| T11 native inputs on the GPU | H16 | none | Upload library file bytes. Kernels parse ELF dynamic symbol tables and archive indexes. Delete `cached_input`. |
| T12 delete unused readback paths | U1, U2, U4, U5, U7, U8, U9, U12, U42 to U45 | none | Delete the standalone lexer and parser readback APIs and the unlinked artifact readbacks. A readback a test still needs moves to `debug_readback_label!`. |

After T1 to T12, the compile path has these readbacks:

| Readback | When |
|---|---|
| `codegen.x86.link.resident.image` | native x86 build |
| `codegen.x86.link.resident.sections` | `--native-linker cc` |
| `codegen.wasm.link.page.output` | WASM build |
| `compiler.typecheck.diagnostic-token`, renamed to a diagnostics read | failed build and `check` |

`codegen.x86.link.page` goes away when T7 moves the CLI to the resident link.
