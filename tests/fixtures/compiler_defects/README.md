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
| `u64_cast_literal.lani` | `4000000000 as u64` | compiles, exit 4 | **fixed 2026-10-31**: was LNC0069 "invalid integer literal" (the literal was checked as i32 before the cast); now exits 4 |
| `u64_cast_literal_forms.lani` | literal casts to u32/u64/i64 at their extremes, plus `-1 as u32`, `-1 as u64`, `300 as u8`, `(3 + 4) as u64`, `3 as f64` | exit 0 | exit 0 since the fix |
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

## Cast-target literals

The [literal-context projection](../../../shaders/type_checker/calls/03k1_project_literal_contexts.slang)
gives an integer literal that is the direct operand of `as T` (through
parentheses and unary minus) the type `T` when `T` is a 32- or 64-bit integer.
Every non-negative `i32` value is unchanged in those types, so programs that
compiled before keep their values. Three shapes keep the old `i32` context:

- a negated literal under an unsigned `T`, so `-1 as u32` and `-1 as u64` still
  wrap to the maximum;
- a narrow `T` (`i8`, `u8`, `i16`, `u16`), so `300 as u8` still wraps to 44;
- an operand of arithmetic, so `(1 + 4000000000) as u64` still reports LNC0069.

Float literals and integer literals under a float `T` are unchanged.
`18446744073709551616 as u64`, `4294967296 as u32` and
`9223372036854775808 as i64` report LNC0069 at the literal.

The kernel grew from 31,663 to 31,901 fully inlined instructions (limit 40,000;
no local arrays). On 2026-10-31, the compiler binaries from before and after
the change each compiled the same 72 programs in one `laniusc daemon` under
`heavy`: 66 sample programs and stdlib fixtures, the 5 cast cases above and
`u64_cast_literal.lani`. The only accept/reject changes were the two fixed
programs, now exit 0 and exit 4; the four over-range casts and 16 other
programs are rejected by both with the same code. The 50 programs that compiled
with both ran with empty, small and 300 KB stdin: 144 of 150 runs were
identical. The other 6 came from `library_tests` and `timer_ticks`, which print
elapsed times, and match once the numbers are masked. The emitted binaries
differ because stdlib literals such as `0 as u64` are now typed `u64`.
