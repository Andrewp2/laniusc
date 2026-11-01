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
| `u64_stack_carry.lani` | performance: u64 values and every expression temporary live in stack slots | exit 10, carry and temporaries in registers | exit 10. Before 2026-10-31: 0.42 s, all u64 values in slots. 64-bit declarations are now register-eligible (`decl_slots_scatter.slang`, `allocation_words.slang`), which brings it to 0.31 s. Temporaries still take slots, and `>> 32` still range-checks its constant amount at run time. The asm excerpt is in the file |
| `u32_slice_row.lani` | performance: the big-integer multiply-add row costs about 13 ns per limb (26 ns under load) instead of about 1 ns | exit 72 in about 0.1 s | exit 72 in 1.34 s. Each slice access copies the three descriptor words into fresh slots, bounds-checks, multiplies by the runtime stride and spills the loaded value. About 100 instructions and 70 memory operands per limb. The asm excerpt is in the file |
| `candidate_nested_generic_match.lani` | reported: LNC0047 "type-check execution failed" on a nested match on a generic enum bound in an outer arm | compiles, exit 4 | **not reproduced**: compiles and exits 4 |
| `candidate_slice_select_label.lani` | reported: LNC0008 "unsatisfied trait bound" labels pointing at `stdlib/core/slice.lani:899` (inside `select_nth_unstable`) instead of the caller | compiles, exit 1 | **not reproduced**: compiles and exits 1 |
| `candidate_missing_module_long.lani` | reported: LNC0016 "syntax error" on a long file without a `module` line | compiles, exit 0 | **not reproduced**: 401 functions and no `module` line compile and exit 0 |

The three candidates are the closest shapes tried from the reports. Six other
shapes also compiled correctly: generic-function and user-enum nested matches,
`Option<Result<T, i32>>`, an untyped `let` of `T::lt`, `try_clone`, generic
`select_nth_unstable<T>`, and 3,000-line, import-first and struct/enum/impl-heavy
files without `module`. The agent that hit each of those diagnostics should
replace its candidate with the failing program.
