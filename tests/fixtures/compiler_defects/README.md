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
| `question_comparison.lani` (removed) | `?` inside a comparison: `if (three()? != 3)` | exit 0 | **fixed**: the operator after `?` was dropped; now `tests/codegen_x86.rs` `x86_try_operand_keeps_the_following_binary_operator` |
| `i64_view_writes.lani` (removed) | `words[2] = 5` through `typed_slice_from_raw_parts<i64>(base, 4)` over a local `[i32; 8]` | — | **not a defect**: raw `[i64]` views descend (element i at `base - 8 * i`, as `core::mem` documents), so the store landed below the array; now `tests/codegen_x86.rs` `x86_i64_raw_views_store_at_descending_word_addresses` |
| `u64_cast_literal.lani` | `4000000000 as u64` | compiles, exit 4 | **fixed 2026-10-31**: was LNC0069 "invalid integer literal" (the literal was checked as i32 before the cast); now exits 4 |
| `u64_cast_literal_forms.lani` | literal casts to u32/u64/i64 at their extremes, plus `-1 as u32`, `-1 as u64`, `300 as u8`, `(3 + 4) as u64`, `3 as f64` | exit 0 | exit 0 since the fix |
| `untyped_generic_trait_result.lani` | untyped `let got = reader.read(...)` where `R: core::io::Read` | compiles, exit 1 with one stdin byte | LNC0006 "type mismatch" at the later `unwrap`; the same program with `let got: Result<i32, core::io::Error>` works. The reported variant of this defect was LNC0027 "call resolution failed" |
| `bound_trait_result_argument.lani` | the same untyped `got` passed to a nongeneric `Result<i32, core::io::Error>` parameter | exit 1 with one stdin byte | **fixed 2026-10-31**: compiled before, then died with SIGILL (exit 132) |
| `bound_trait_open_result.lani` | untyped `let x = it.next()` where `I: core::iter::Iterator<i32>` (a result that names the trait's parameter) | compiles, exit 6 | **fixed 2026-10-31**: was LNC0006 "type mismatch" at the `unwrap_or` |
| `bound_trait_open_param.lani` | the same through `I: core::iter::Iterator<T>` in a generic caller | exit 3 | exit 3 since the fix (was LNC0006) |
| `bound_trait_open_forms.lani` | `let r = f.try_apply(2, 3 as u8)` where `F: core::iter::TryFolder<i32, u8, bool>` | exit 6 | exit 6 since the fix (was LNC0006) |
| `bound_trait_open_argument.lani` | the untyped `Option` from `it.next()` passed to a nongeneric parameter | exit 12 | **fixed 2026-10-31**: compiled before, then died with SIGILL (exit 132) |
| `u64_stack_carry.lani` | performance: u64 values and every expression temporary live in stack slots | exit 10, carry and temporaries in registers | exit 10 in 0.12 s with no memory operand in the loop. Before 2026-10-31: 0.42 s, all u64 values in slots. 64-bit declarations became register-eligible (0.31 s), then temporaries got a per-function linear-scan allocator over r8-r11, rbx and r12-r14 (`allocation_words.slang`), `>> 32` became an immediate shift and `j < n` a fused compare-branch. Left: register-to-register move chains and dead constant loads (`mov $0x20,%ebx`) |
| `u32_slice_row.lani` | performance: the big-integer multiply-add row costs about 13 ns per limb (26 ns under load) instead of about 1 ns | exit 72 in about 0.1 s | exit 72 in 0.29 s (2.9 ns per limb, was 1.34 s). Slice parameters are now read in place (no descriptor copies), temporaries stay in registers and the loop test is a fused `cmp; jge`: about 60 instructions per limb. Left: `factor` reloads from its slot each pass, each access still bounds-checks and multiplies by the runtime stride (`imul` plus a stride==1 branch, even for 4-byte elements), and move chains. The asm excerpt is in the file |
| `candidate_nested_generic_match.lani` | reported: LNC0047 "type-check execution failed" on a nested match on a generic enum bound in an outer arm | compiles, exit 4 | **not reproduced**: compiles and exits 4 |
| `candidate_slice_select_label.lani` | reported: LNC0008 "unsatisfied trait bound" labels pointing at `stdlib/core/slice.lani:899` (inside `select_nth_unstable`) instead of the caller | compiles, exit 1 | **not reproduced**: compiles and exits 1 |
| `candidate_missing_module_long.lani` | reported: LNC0016 "syntax error" on a long file without a `module` line | compiles, exit 0 | **not reproduced**: 401 functions and no `module` line compile and exit 0 |
| `b14_path_self_method_inherent.lani` | a self method called through its type's path: `S::get(s, 1)`, `S::peek(s.borrow(), 2)` for `&self` | exit 0 | **fixed 2026-10-31**: was LNC0027 "call resolution failed"; registered in `tests/compiler_defect_fixtures_execution.rs` |
| `b14_path_self_method_bound.lani` | a bound's self member called through the parameter's path, `T::tw(x, 3)` with `T: Tw<T>`, on `i32` and a record | exit 0 | **fixed 2026-10-31**: was LNC0027 "call resolution failed"; registered in `tests/compiler_defect_fixtures_execution.rs` |
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
