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
| `u64_stack_carry.lani` | performance: u64 values and every expression temporary live in stack slots | exit 10, carry and temporaries in registers | exit 10. Before 2026-10-31: 0.42 s, all u64 values in slots. 64-bit declarations are now register-eligible (`decl_slots_scatter.slang`, `allocation_words.slang`), which brings it to 0.31 s. Temporaries still take slots, and `>> 32` still range-checks its constant amount at run time. The asm excerpt is in the file |
| `u32_slice_row.lani` | performance: the big-integer multiply-add row costs about 13 ns per limb (26 ns under load) instead of about 1 ns | exit 72 in about 0.1 s | exit 72 in 1.34 s. Each slice access copies the three descriptor words into fresh slots, bounds-checks, multiplies by the runtime stride and spills the loaded value. About 100 instructions and 70 memory operands per limb. The asm excerpt is in the file |
| `untyped_generic_trait_result.lani` | untyped `let got = reader.read(...)` where `R: core::io::Read` | compiles, exit 1 with one stdin byte | **fixed 2026-10-31**: was LNC0006 "type mismatch" at the later `unwrap` (LNC0027 for `got.unwrap()`, LNC0047 for `w.flush()` and `core::random::Source64::draw`); see [bound trait results](#bound-trait-results) |
| `bound_trait_result_argument.lani` | the same untyped `got` passed to a nongeneric `Result<i32, core::io::Error>` parameter | exit 1 with one stdin byte | **fixed 2026-10-31**: compiled before, then died with SIGILL (exit 132) |
| `bound_trait_open_result.lani` | untyped `let x = it.next()` where `I: core::iter::Iterator<i32>` (a result that names the trait's parameter) | compiles, exit 6 | LNC0006 "type mismatch" at the `unwrap_or`; annotating the `let` works |
| `candidate_nested_generic_match.lani` | reported: LNC0047 "type-check execution failed" on a nested match on a generic enum bound in an outer arm | compiles, exit 4 | **not reproduced**: compiles and exits 4 |
| `candidate_slice_select_label.lani` | reported: LNC0008 "unsatisfied trait bound" labels pointing at `stdlib/core/slice.lani:899` (inside `select_nth_unstable`) instead of the caller | compiles, exit 1 | **not reproduced**: compiles and exits 1 |
| `candidate_missing_module_long.lani` | reported: LNC0016 "syntax error" on a long file without a `module` line | compiles, exit 0 | **not reproduced**: 401 functions and no `module` line compile and exit 0 |
| `byte_loop_codegen.lani` | performance: a `[u8]` newline-count loop, 160 M byte reads; compare `byte_loop_codegen.c` and the loop disassembly in `byte_loop_codegen.s` | about `gcc -O0` speed (0.14 s; `-O2` 0.02 s) | 0.50 s (2.8 ns/byte), exit 0: per-iteration slice copy, bounds check, stride `imul` and branch, spills of every temporary |

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

## Bound trait results

A method called through a bound on a trait from another library (every
stdlib trait, seen from a program) is typed by the trait's required member.
[`calls/03e_materialize_return_types.slang`](../../../shaders/type_checker/calls/03e_materialize_return_types.slang)
only produced a call's result when the receiver was already a concrete
instance, and the receiver of such a call is still the bounded parameter. The
call then had no type: a typed `let` checked fine, but an untyped `let` or a
direct argument did not. A trait in the program's own source roots goes
through the local route and was never affected. The fix keeps the receiver
requirement except for a closed result, one that names no type or constant
parameter, such as `Result<i32, core::io::Error>`. Such a result is complete
without the receiver's environment.

A result that names the trait's parameter, such as `Iterator<T>::next`
returning `Option<T>`, is still open and still needs the annotation
(`bound_trait_open_result.lani`).

The kernel grew from 18,463 to 18,657 fully inlined instructions (limit
40,000; no local arrays). On 2026-10-31 the private compiler built before and
after the change each compiled the same 78 programs in one daemon under
`heavy`: 66 sample programs and stdlib fixtures and 12 reductions of this
defect. All 50 regular programs that compile produce byte-identical
executables, and 16 are rejected by both with the same code. Of the 12
reductions, 9 went from rejected to accepted and now give the expected exit
code. `bound_trait_result_argument.lani` went from SIGILL to exit 1. The typed
`let` and the concrete-receiver control were unchanged.
