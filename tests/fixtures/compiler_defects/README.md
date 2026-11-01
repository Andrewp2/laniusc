# laniusc defect reproductions (2026-10-31)

Each file is a complete entry program. Compile it with the worktree's roots:

```sh
target/claude-work/bin/lcc --stdlib-root stdlib --source-root extended \
  -o target/claude-work/defect tests/fixtures/compiler_defects/NAME.lani
printf x | target/claude-work/defect; echo $?
```

These files are not registered as tests: they record wrong behavior, and each
one should become a passing regression test once its defect is fixed.

| File | Defect | Expected | Actual |
| --- | --- | --- | --- |
| `question_comparison.lani` | `?` inside a comparison: `if (three()? != 3)` | exit 0 | exit 1 (silent miscompile) |
| `i64_view_writes.lani` | `words[2] = 5` through `typed_slice_from_raw_parts<i64>(base, 4)` over a local `[i32; 8]` | exit 5 | exit 0: the store is lost (silent miscompile) |
| `u64_cast_literal.lani` | `4000000000 as u64` | compiles, exit 4 | LNC0069 "invalid integer literal": the literal is checked as i32 before the cast |
| `untyped_generic_trait_result.lani` | untyped `let got = reader.read(...)` where `R: core::io::Read` | compiles, exit 1 with one stdin byte | LNC0006 "type mismatch" at the later `unwrap`; the same program with `let got: Result<i32, core::io::Error>` works. The reported variant of this defect was LNC0027 "call resolution failed" |
| `candidate_nested_generic_match.lani` | reported: LNC0047 "type-check execution failed" on a nested match on a generic enum bound in an outer arm | compiles, exit 4 | **not reproduced**: compiles and exits 4 |
| `candidate_slice_select_label.lani` | reported: LNC0008 "unsatisfied trait bound" labels pointing at `stdlib/core/slice.lani:899` (inside `select_nth_unstable`) instead of the caller | compiles, exit 1 | **not reproduced**: compiles and exits 1 |
| `candidate_missing_module_long.lani` | reported: LNC0016 "syntax error" on a long file without a `module` line | compiles, exit 0 | **not reproduced**: 401 functions and no `module` line compile and exit 0 |

The three candidates are the closest shapes tried from the reports. Six other
shapes also compiled correctly: generic-function and user-enum nested matches,
`Option<Result<T, i32>>`, an untyped `let` of `T::lt`, `try_clone`, generic
`select_nth_unstable<T>`, and 3,000-line, import-first and struct/enum/impl-heavy
files without `module`. The agent that hit each of those diagnostics should
replace its candidate with the failing program.

## Performance defects

These programs compute the right result, but the generated code is far slower
than it should be. Each one should become a timing or instruction-count check
once its defect is fixed.

| File | Defect | Expected | Actual |
| --- | --- | --- | --- |
| `slice_byte_copy_cost.lani` | `target[at + index] = source[start + index]` loop over `[u8]` parameters | about 5–8 instructions per byte; 64 MiB in under 0.1 s | 62 instructions per byte; 64 MiB in 0.42 s on the laptop (exit 7 either way) |

To read the loop, disassemble the binary. The output is a static ELF without
symbols, loaded at 0x400000:

```sh
objdump -D -b binary -m i386:x86-64 --adjust-vma=0x400000 target/claude-work/defect
```

Each loop iteration of `copy` executes 62 instructions:

- The two slice descriptors (pointer, length, stride) are copied into fresh
  stack temporaries for every index expression. That is 12 `mov`s per
  iteration.
- Each access computes `base + index * stride` with an `imul`, then branches
  at run time on `stride == 1` to choose a byte or word load or store, even
  though the element type is `u8`.
- The loop condition is materialized as a bool (`setl`, `movzbl`, a store, a
  reload and `test`) before the branch.
- Every value goes through a stack slot. There is no register allocation
  across statements, and dead stores are kept.

The same costs apply to every `[T]` index in library code. They are why the
S5 byte loops in ext::cbor_stream and ext::json_stream cost about 60–140
instructions per byte, and why a `Result` return and check costs about
100 instructions against about 8 for a `bool` return. The S5 fast paths
(`Writer.fast_*`, `Decoder.advance`) work around the Result cost; only the
compiler can fix the per-byte cost.
