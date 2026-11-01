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
| `untyped_generic_trait_result.lani` | untyped `let got = reader.read(...)` where `R: core::io::Read` | compiles, exit 1 with one stdin byte | **fixed 2026-10-31**: was LNC0006 "type mismatch" at the later `unwrap` (LNC0027 for `got.unwrap()`, LNC0047 for `w.flush()` and `core::random::Source64::draw`); see [bound trait results](#bound-trait-results) |
| `bound_trait_result_argument.lani` | the same untyped `got` passed to a nongeneric `Result<i32, core::io::Error>` parameter | exit 1 with one stdin byte | **fixed 2026-10-31**: compiled before, then died with SIGILL (exit 132) |
| `bound_trait_open_result.lani` | untyped `let x = it.next()` where `I: core::iter::Iterator<i32>` (a result that names the trait's parameter) | compiles, exit 6 | **fixed 2026-10-31**: was LNC0006 "type mismatch" at the `unwrap_or` |
| `bound_trait_open_param.lani` | the same through `I: core::iter::Iterator<T>` in a generic caller | exit 3 | exit 3 since the fix (was LNC0006) |
| `bound_trait_open_forms.lani` | `let r = f.try_apply(2, 3 as u8)` where `F: core::iter::TryFolder<i32, u8, bool>` | exit 6 | exit 6 since the fix (was LNC0006) |
| `bound_trait_open_argument.lani` | the untyped `Option` from `it.next()` passed to a nongeneric parameter | exit 12 | **fixed 2026-10-31**: compiled before, then died with SIGILL (exit 132) |
| `u64_stack_carry.lani` | performance: u64 values and every expression temporary live in stack slots | exit 10, carry and temporaries in registers | exit 10. Before 2026-10-31: 0.42 s, all u64 values in slots. 64-bit declarations are now register-eligible (`decl_slots_scatter.slang`, `allocation_words.slang`), which brings it to 0.31 s. Temporaries still take slots, and `>> 32` still range-checks its constant amount at run time. The asm excerpt is in the file |
| `u32_slice_row.lani` | performance: the big-integer multiply-add row costs about 13 ns per limb (26 ns under load) instead of about 1 ns | exit 72 in about 0.1 s | exit 72 in 1.34 s. Each slice access copies the three descriptor words into fresh slots, bounds-checks, multiplies by the runtime stride and spills the loaded value. About 100 instructions and 70 memory operands per limb. The asm excerpt is in the file |
| `candidate_nested_generic_match.lani` | reported: LNC0047 "type-check execution failed" on a nested match on a generic enum bound in an outer arm | compiles, exit 4 | **not reproduced**: compiles and exits 4 |
| `check_slice_select_label.lani` | reported: LNC0008 "unsatisfied trait bound" labels pointing at `stdlib/core/slice.lani:899` (inside `select_nth_unstable`) instead of the caller | `laniusc check` accepts; compiles, exit 1 | **fixed 2026-10-31**: real in `laniusc check` only, which rejected it at `slice.lani:899`; builds were never affected. See [check and generic impls](#check-and-generic-impls) |
| `check_slice_import.lani` | `laniusc check --stdlib-root stdlib` on any program importing `core::slice` | check accepts; exit 3 | **fixed 2026-10-31**: was LNC0008 at `slice.lani:899` |
| `check_generic_impl_bound.lani` | `laniusc check` on a call bound met only by a generic impl (`impl<T> Cmp for N<T>`) | check accepts; exit 3 | **fixed 2026-10-31**: was LNC0008 "no matching impl satisfies this call" at the call |
| `candidate_missing_module_long.lani` | reported: LNC0016 "syntax error" on a long file without a `module` line | compiles, exit 0 | **not reproduced, closed 2026-10-31**: this file and 2,000- to 20,000-function files (up to 2 MB) with or without `module`, CRLF or import-first all compile. Large files fail on GPU memory instead; see [GPU out of memory](#gpu-out-of-memory) |
| `byte_loop_codegen.lani` | performance: a `[u8]` newline-count loop, 160 M byte reads; compare `byte_loop_codegen.c` and the loop disassembly in `byte_loop_codegen.s` | about `gcc -O0` speed (0.14 s; `-O2` 0.02 s) | 0.50 s (2.8 ns/byte), exit 0: per-iteration slice copy, bounds check, stride `imul` and branch, spills of every temporary |

The nested-match candidate is the closest shape tried from its report. Five
other shapes also compiled correctly: generic-function and user-enum nested
matches, `Option<Result<T, i32>>`, an untyped `let` of `T::lt` and
`try_clone`. The agent that hit that diagnostic should replace the candidate
with the failing program.

## check and generic impls

`laniusc check` runs only the frontend. Its trait solver indexes concrete
impls only (`impl_row_has_supported_exact_key` in
[`02_obligations.slang`](../../../shaders/type_checker/predicates/02_obligations.slang)).
A generic impl head such as `impl<T> Cmp for N<T>` is selected by the
whole-program admission that only a build runs. So check rejected every call
whose bound only a generic impl meets. The rejection was LNC0008 "no matching
impl satisfies this call". It hit `selection_engine<T,Natural<T>>` in
`core::slice::select_nth_unstable`, so check rejected every program that
imports `core::slice` at `stdlib/core/slice.lani:899`. Under the min-token
rule that false error also replaced the real label of a program with a real
unsatisfied bound. Builds, and the label tests that compile, were never
affected.

The fix is in the CLI (`cli/compile/entry.rs`, `check_with_build_fallback`).
When the frontend check fails with exactly that diagnostic, check builds the
program for x86-64 and discards the output, then reports what the build
reports. Every other check result is unchanged, and so is its cost. The
library functions `type_check_entry_with_*` and the language server still run
the frontend alone, so they still reject these programs.

Before the fix, check rejected `check_generic_impl_bound.lani`,
`check_slice_import.lani`, `check_slice_select_label.lani`, seven other
generic-impl reductions and all 17 negative label fixtures. That covers 13
in `stdlib_borrowed_lookup/direct` and 4 in
`stdlib_ordered_navigation`; all 17 were labeled `slice.lani:899`. After the
fix, the valid programs pass check and the 17 negatives are labeled at their
`rejected_lookup_bound` or `rejected_navigation_bound` call in the fixture, as
a build labels them. A
program that uses a generic impl and also has an earlier type error still
reports that error.

## GPU out of memory

What large files actually hit is GPU memory. When `create_buffer` runs out of
memory, wgpu reports the error asynchronously and the dispatches that use the
buffer do not run. The compiler then read zeroed results and reported a
wrong diagnostic, usually LNC0017 "missing main entrypoint", even with `main`
first in the file. Two cases were found on the 8 GB laptop GPU, both with
2026-10-31 builds:

- One compile of an `import core::result;` file with 16,500 one-line helpers
  (1.65 MB; 16,000 helpers pass) runs out creating
  `program_evidence.thread_scratch`. Generate it with
  `python3 -c 'print("import core::result;"); [print(f"fn helper_{i}(x: i32) -> i32 {{ let y: i32 = x + {i % 97}; if (y > 1000) {{ return y - 1000; }} return y; }}") for i in range(16500)]; print("fn main() -> i32 { return helper_0(3); }")'`.
- A poisoned daemon. After one 18,000- to 20,000-helper compile without
  imports (about 2 MB), the daemon's resident buffers stay sized for it.
  Every later compile with an import then ran out creating
  `codegen.lowering.arena.2` and reported LNC0017 until the daemon restarted.

The GPU device now counts uncaptured errors and keeps the first message
(`gpu/device.rs`). A daemon compile that saw an error drops its compiled-unit
cache and resident job buffers and retries once. If the retry also fails, it
reports LNC0057 "GPU device error during compilation", naming the resource
that ran out. A one-shot compile reports the same LNC0057 instead of the
bogus diagnostic. The poisoned-daemon sequences now recover on the retry.

The compilers built before and after this change compiled the same 84
programs in one daemon each. The 68 programs that compile give byte-identical
executables, the other 16 are rejected by both, and the 198 runs of those 68
match apart from 6 timing lines.

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

A result that names the trait's parameters, such as `Iterator<T>::next`
returning `Option<T>`, was fixed the same day. The bound's trait arguments
(`Iterator<i32>`) are already the call's context arguments: the dependency
bound-member offer (`dependencies/15b_offer_bound_members.slang`) publishes
them. The materializer now substitutes such a result in that environment
whenever the call has one. This change grew the kernel from 18,657 to 18,695
instructions. The before and after builds compiled 84 programs: the 78 above,
plus five open-result reductions and this fixture. All 50 regular programs
that compile again produce byte-identical executables, and 16 are rejected by
both. `bound_trait_open_result`, `bound_trait_open_param` and
`bound_trait_open_forms` went from LNC0006 to exits 6, 3 and 6.
`bound_trait_open_argument` went from SIGILL to exit 12. The typed `let`
control and the closed-result reductions are unchanged.

The kernel grew from 18,463 to 18,657 fully inlined instructions (limit
40,000; no local arrays). On 2026-10-31 the private compiler built before and
after the change each compiled the same 78 programs in one daemon under
`heavy`: 66 sample programs and stdlib fixtures and 12 reductions of this
defect. All 50 regular programs that compile produce byte-identical
executables, and 16 are rejected by both with the same code. Of the 12
reductions, 9 went from rejected to accepted and now give the expected exit
code. `bound_trait_result_argument.lani` went from SIGILL to exit 1. The typed
`let` and the concrete-receiver control were unchanged.
