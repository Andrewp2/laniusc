# Array repetition counts and element contexts

The GPU checker now treats an array repetition count as an unsigned 32-bit
extent, independently of the element type. The existing grammar, HIR, layout,
runtime ABI and element range checks are unchanged.

## Cause and correction

In `[u8; 4100] = [0; 4100]`, the checker previously gave both numeric children
the element's `u8` context. It then correctly rejected the incorrectly typed
count with LNC0069. The file-copy descriptor fixture exposed this error before
any native execution. A named-count attempt was also rejected: the language
grammar requires a literal repetition count.

The [literal-context projection](../shaders/type_checker/calls/03k1_project_literal_contexts.slang)
already visits each literal's expression owner. Three added lines recognize
the count using the existing repeat tag and exact `payload.b` operand identity,
then select `SCALAR_U32`. Other children continue through the existing element
context path. The [HIR contract](../shaders/hir_records.slang#L141) records that
role and separately rejects high-word counts and the reserved `0xffffffff`
sentinel. Unary element expressions and nested arrays keep their own contexts.

This does not add named-count syntax, remove extent validation, or establish
that arbitrarily large arrays fit native layout, stack or slice limits. It
adds no pass, scratch allocation or scan. Changing a count's effective scalar
can request another round through the existing inference convergence counter;
instruction counts alone cannot establish its performance cost.

## Executable gates

All six tests in
[`compiler_array_repeat_context_execution.rs`](../tests/compiler_array_repeat_context_execution.rs)
passed on 2026-10-24. The driver built in 6.92 seconds.

| Exact test suffix after `array_repeat_context_` | Compile jobs | Result | Time |
| --- | ---: | --- | ---: |
| `executes_modest_native_arrays` | 1 | Strict native ELF check and Linux x86_64 execution, exit 0 | 3.56 s |
| `rejects_unsigned_element_range_errors` | 3 | LNC0069 at actual element magnitudes | 2.61 s |
| `rejects_signed_element_range_errors` | 3 | LNC0069 at actual element magnitudes | 2.60 s |
| `rejects_reserved_and_oversized_counts` | 2 | Reserved and greater-than-u32 extents reject | 2.55 s |
| `rejects_nonliteral_counts` | 3 | Named, negative and floating counts reject | 3.63 s |
| `rejects_malformed_and_mismatched_arrays` | 3 | Later-list repeat, wrong length and wrong element type reject | 2.29 s |

The positive program checks zero and nonzero `u8` repeats at 255, 256 and 4100,
the signed minimum at count 128, boolean repeats at 256, nested byte arrays,
and ordinary signed/unsigned element arrays. It reads both ends and mutates a
large array's last element. Native execution is enabled only on Linux x86_64;
other hosts do not pass a compile-only version of this positive test.

The unchanged original file-copy fixture subsequently passed its strict ELF
check and all 84 native cases in 6.33 seconds. That independently exercises its
4100-element strided byte backing and 4096-byte scratch capacity.

Logs are under `target/stdlib-work/array-repeat-context-admission/`; the original
failure and successful descriptor logs are under
`target/stdlib-work/file-copy-admission/`. Each test ran separately with an
outer 100-second timeout, a 35-second lock wait, a 60-second process limit,
`RUST_MIN_STACK=16777216` and `LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=45000`.

## Size and bounded performance comparison

The rebuild changed only `type_checker/calls/03k1_project_literal_contexts.spv`
among 918 SPIR-V files. Fully inlined size changed from **31,592 to 31,663**
instructions, below the existing 40,000 limit; local-array count and bytes
remain zero. The current manifest is
`target/stdlib-work/array-repeat-context-admission/current-spv.sha256`, SHA256
`ea02569e143cb458cc50aa68bdc280fc331e55c69c2bc80367ff15cf4f898d07`.

The existing `examples/stdlib_gpu_perf.rs` harness measured the same
86,616-byte entry containing 768 repeat-array helpers and one main function.
Every helper uses `[i32; 32] = [7; 32]`, exercising the previous i32 count
context. Each process used one warmup and three measured private entry
rebuilds, with `LANIUS_PERF_REBUILD_ENTRY=1`. Each emitted 707,195-byte ELF was
executed and checked outside its measured compilation span. The benchmark
harness checks ELF magic and native results; the strict transfer checker is
provided by the separate execution gates above.

Only the one SPIR-V file was switched; compiler binary and input stayed
identical. The order was baseline, current, current, baseline:

| Run | Median | Range |
| --- | ---: | ---: |
| Baseline, first pair | 86.233 ms | 72.794–93.660 ms |
| Current, first pair | 80.080 ms | 78.044–82.699 ms |
| Current, reversed pair | 79.636 ms | 74.100–80.790 ms |
| Baseline, reversed pair | 88.312 ms | 82.966–89.174 ms |

This comparison shows no observed regression for this workload. The sample is
small and desktop activity was uncontrolled; it does not establish a causal
speedup, cold compilation performance, large-workload scaling or a ratio
against another compiler. Inference rounds were not instrumented.

The workload SHA256 is
`fb84ac62d02d8de229b61a47a354b3c1b46940ec9b1475c048574e279f5bec9f`;
the shared benchmark binary SHA256 is
`ce04de0164e9f9d8a877a47d6468f33e0ffd11738d2d54485d32fd885cdf7d6c`.
The workload, baseline/current shader copies, size rows, four performance logs
and commands remain in `target/stdlib-work/array-repeat-context-admission/`.
The current shader was restored and the complete current manifest checked
after both baseline runs.
