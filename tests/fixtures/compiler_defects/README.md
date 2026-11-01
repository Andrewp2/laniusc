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
| `untyped_generic_trait_result.lani` | untyped `let got = reader.read(...)` where `R: core::io::Read` | compiles, exit 1 with one stdin byte | **fixed 2026-10-31**: was LNC0006 "type mismatch" at the later `unwrap` (LNC0027 for `got.unwrap()`, LNC0047 for `w.flush()` and `core::random::Source64::draw`); see [bound trait results](#bound-trait-results) |
| `bound_trait_result_argument.lani` | the same untyped `got` passed to a nongeneric `Result<i32, core::io::Error>` parameter | exit 1 with one stdin byte | **fixed 2026-10-31**: compiled before, then died with SIGILL (exit 132) |
| `bound_trait_open_result.lani` | untyped `let x = it.next()` where `I: core::iter::Iterator<i32>` (a result that names the trait's parameter) | compiles, exit 6 | **fixed 2026-10-31**: was LNC0006 "type mismatch" at the `unwrap_or` |
| `bound_trait_open_param.lani` | the same through `I: core::iter::Iterator<T>` in a generic caller | exit 3 | exit 3 since the fix (was LNC0006) |
| `bound_trait_open_forms.lani` | `let r = f.try_apply(2, 3 as u8)` where `F: core::iter::TryFolder<i32, u8, bool>` | exit 6 | exit 6 since the fix (was LNC0006) |
| `bound_trait_open_argument.lani` | the untyped `Option` from `it.next()` passed to a nongeneric parameter | exit 12 | **fixed 2026-10-31**: compiled before, then died with SIGILL (exit 132) |
| `u64_stack_carry.lani` | performance: u64 values and every expression temporary live in stack slots | exit 10, carry and temporaries in registers | exit 10 in 0.12 s with no memory operand in the loop. Before 2026-10-31: 0.42 s, all u64 values in slots. 64-bit declarations became register-eligible (0.31 s), then temporaries got a per-function linear-scan allocator over r8-r11, rbx and r12-r14 (`allocation_words.slang`), `>> 32` became an immediate shift and `j < n` a fused compare-branch. Left: register-to-register move chains and dead constant loads (`mov $0x20,%ebx`) |
| `u32_slice_row.lani` | performance: the big-integer multiply-add row costs about 13 ns per limb (26 ns under load) instead of about 1 ns | exit 72 in about 0.1 s | exit 72 in 0.29 s (2.9 ns per limb, was 1.34 s). Slice parameters are now read in place (no descriptor copies), temporaries stay in registers and the loop test is a fused `cmp; jge`: about 60 instructions per limb. Left: `factor` reloads from its slot each pass, each access still bounds-checks and multiplies by the runtime stride (`imul` plus a stride==1 branch, even for 4-byte elements), and move chains. The asm excerpt is in the file |
| `candidate_nested_generic_match.lani` | reported: LNC0047 "type-check execution failed" on a nested match on a generic enum bound in an outer arm | compiles, exit 4 | **not reproduced**: compiles and exits 4 |
| `check_slice_select_label.lani` | reported: LNC0008 "unsatisfied trait bound" labels pointing at `stdlib/core/slice.lani:899` (inside `select_nth_unstable`) instead of the caller | `laniusc check` accepts; compiles, exit 1 | **fixed 2026-10-31**: real in `laniusc check` only, which rejected it at `slice.lani:899`; builds were never affected. See [check and generic impls](#check-and-generic-impls) |
| `check_slice_import.lani` | `laniusc check --stdlib-root stdlib` on any program importing `core::slice` | check accepts; exit 3 | **fixed 2026-10-31**: was LNC0008 at `slice.lani:899` |
| `check_generic_impl_bound.lani` | `laniusc check` on a call bound met only by a generic impl (`impl<T> Cmp for N<T>`) | check accepts; exit 3 | **fixed 2026-10-31**: was LNC0008 "no matching impl satisfies this call" at the call |
| `candidate_missing_module_long.lani` | reported: LNC0016 "syntax error" on a long file without a `module` line | compiles, exit 0 | **not reproduced, closed 2026-10-31**: this file and 2,000- to 20,000-function files (up to 2 MB) with or without `module`, CRLF or import-first all compile. Large files fail on GPU memory instead; see [GPU out of memory](#gpu-out-of-memory) |
| `b14_path_self_method_inherent.lani` | a self method called through its type's path: `S::get(s, 1)`, `S::peek(s.borrow(), 2)` for `&self` | exit 0 | **fixed 2026-10-31**: was LNC0027 "call resolution failed"; registered in `tests/compiler_defect_fixtures_execution.rs` |
| `b14_path_self_method_bound.lani` | a bound's self member called through the parameter's path, `T::tw(x, 3)` with `T: Tw<T>`, on `i32` and a record | exit 0 | **fixed 2026-10-31**: was LNC0027 "call resolution failed"; registered in `tests/compiler_defect_fixtures_execution.rs` |
| `lnc0005_nested_variant_pattern.lani` | a variant named inside another pattern, `Ok(V5(p))` or `Some(None)`, then the same variant bare in a later pattern or expression | exit 0 | **fixed 2026-10-31**: was LNC0005 "unresolved identifier" (the nested variant was declared as a match binder); found by `formal/tools/fuzz_oracle.py`; registered in `tests/compiler_defect_fixtures_execution.rs` |
| `lnc0017_payload_after_nested_variant.lani` | a payload binder after a nested local variant, `V6(V3(p), q) -> (q as usize)` | exit 0 | **fixed 2026-10-31**: was LNC0017 "first unsupported target LIR opcode: 8" (the nested pattern's slot had no type, so q had no word offset); found by `formal/tools/fuzz_oracle.py`; registered in `tests/compiler_defect_fixtures_execution.rs` |
| `b19_stdlib_path_self_method.lani` | self methods of stdlib types through the type's path: `TotalF32::to_bits(t)`, `Descriptor::raw_handle(d.borrow())`, `Option<i32>::is_some(o)` | exit 0 | **fixed 2026-10-31**: was LNC0027 "call resolution failed". The bare `Option::is_some(o)` (was LNC0005) is generics matrix p83 |
| `b19_bare_imported_generic_path.lani` | self methods of imported generic types through the bare type's path: `Option::is_some(o)`, `Option::unwrap_or(n, 9)`, `Result::unwrap(r)` | exit 0 | **fixed 2026-11-01**: was LNC0005 "unresolved identifier" at `Option`. dependencies/14 gives the bare qualifier its declaration's own application (an external canonical type), methods/06, 07, 08 and candidate.slang accept it as a receiver key, and calls/03d binds no parameter from it |
| `generic_impl_path_inference.lani` | a bare generic type's path infers the impl's parameters: `W::wrap(5)`, `W::get(w)`, `W::peek(u.borrow())` on `impl<T> W<T>` | exit 0 | **fixed 2026-10-31**: was LNC0006 "type mismatch" (the bare `W` bound T to the declaration's own parameter) |
| `ptr_zero_local.lani` | `let value: ptr = 0; return value;` after an earlier call | exit 1 | **fixed 2026-11-01**: exit 2, the pointer was non-null; see [immediate stack stores](#immediate-stack-stores) |
| `ptr_zero_socket_args.lani` | std::socket's shape: `[word(5), address(null()), address(null())]` | exit 11 | **fixed 2026-11-01**: was exit 22. In `std::socket` every `receive`/`receive_until` failed with EFAULT |
| `u64_raw_view_direction.lani` | reported: a store through `typed_slice_from_raw_parts<u64>(p, n)` at index 1 writes below `p` and segfaults | exit 79 | **not a defect**: raw views of types other than i32 and u8 descend in eight-byte words, as `core::mem` documents, so element 1 is at `p - 8`. The fixture views the storage with `typed_slice_from_storage` and exits 79 |
| `ptr_zero_paths.lani` | a null pointer through a return, struct field, `Option`, assignment, copy and enum payload, after calls that leave stack addresses behind | exit 12 | exit 12 since the 2026-11-01 fix. S2's h2c programs (`h2c_service`, `h2c_events` and the 100-client load test) pass with the unpatched `std::socket` on that build. `probe/recv.lani` exits 5 against a local server; its SIGILL is the `unwrap` trap when it runs without a port argument |
| `byte_loop_codegen.lani` | performance: a `[u8]` newline-count loop, 160 M byte reads; compare `byte_loop_codegen.c` and the loop disassembly in `byte_loop_codegen.s` | about `gcc -O0` speed (0.14 s; `-O2` 0.02 s) | 0.50 s (2.8 ns/byte), exit 0: per-iteration slice copy, bounds check, stride `imul` and branch, spills of every temporary |
| `ptr_literal_store_width.lani` | `let empty: ptr = 0;` in a function whose slot last held a stack address | exit 0 (null) | **fixed 2026-11-01** (fe60937c2: an immediate stored to a stack slot writes the whole word): the literal was stored with `mov %eax,-0x8(%rbp)` (32 bits) and reloaded with a 64-bit `mov`, giving 0x00007ffe00000000. Found when `alloc::vec::new()` returned a nonnull `storage` after a push. Four fixtures that trapped on such a `storage` pass with the plain literal (`stdlib_vec_edit_model`, `stdlib_vec_edit_resources/zero_sized.lani`, `stdlib_vec_transfer_model`, `stdlib_vec_transfer/zero_sized.lani`) |

An imported method called with too few arguments, `o.unwrap_or()` on an
`Option<i32>` or `TotalF32::to_bits()`, compiled and ran with an undefined
argument until 2026-10-31. dependencies/08c now checks a method's arity as it
did a function's, and both report LNC0027.

The nested-match candidate is the closest shape tried from its report. Five
other shapes also compiled correctly: generic-function and user-enum nested
matches, `Option<Result<T, i32>>`, an untyped `let` of `T::lt` and
`try_clone`. The agent that hit that diagnostic should replace the candidate
with the failing program.

## Immediate stack stores

`x86_put_imm32_to_location` (`shaders/codegen/lir/x86/encoding.slang`) wrote an
integer or pointer immediate to a stack slot with a 32-bit
`mov [rbp+d], eax`. Readers of a pointer or 64-bit value load the slot's
whole eight-byte word. Since the linear-scan allocator (d4453f42b) moved more
temporaries onto the stack, the upper half could be stale from an earlier
call's frame. For example, `null()` in `ptr_zero_local.lani` returned a stack
address with its low half cleared, and so did `std::socket`'s `null()`. The
store now carries REX.W. RAX already holds the zero-extended immediate, as the
register form leaves it, so i32 readers see the same value. The change adds
one byte per such store and no kernel instructions (`emit` 26,250,
`byte_count` 21,652; limit 40,000).

The compilers built before and after this change compiled 97 programs in
one daemon each: 84 sample programs and stdlib fixtures, 11 reductions and
the two `u64_slice` probes. Every executable changed by the extra REX byte.
16 programs are rejected by both. Of the 243 runs, 204 match. Six of the rest
differ only in clock output. 30 are the 10 reductions, which went from the
wrong result to the expected one. The other three are
`stdlib_foundation/owned_delimited/bounds.lani`, which died with SIGILL on
lang and now exits 0.

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

The fix is in `compiler/gpu_public_api.rs`
(`frontend_check_missed_generic_impl`). When the frontend check fails with
exactly that diagnostic, the check builds the program for x86-64 and discards
the output, then reports what the build reports. Every other check result is
unchanged, and so is its cost. Since 2026-11-01 the fallback sits in the
library functions themselves (`type_check_entry_with_stdlib`,
`_with_source_root`, `_with_source_roots`, `type_check_source_with_gpu` and
`type_check_source_with_gpu_from_path`), so `laniusc check` and the language
server share it. The language server's pull diagnostics now accept
`check_generic_impl_bound.lani` (before: LNC0008 at its call).

The server also loads the stdlib now. Before, it checked each document on
its own, so it reported every `core::slice` import as LNC0010 "imported
module not found". The root comes from `initializationOptions.stdlibRoot` (a
path or `file:` URI). Without that option, the server uses `stdlib/` next to
the laniusc binary, then `stdlib/` in the workspace root (`rootUri`,
`rootPath` or the first workspace folder). With a root, a document is
checked as `laniusc check --stdlib-root ROOT FILE` checks it. If the open
text differs from the file on disk, the text is written to a private overlay
file for the check. A label in an imported file keeps its own path in
`relatedInformation`, and the diagnostic sits at the start of the document.
`tests/cli_lsp.rs` drives the server over stdio on `check_slice_import.lani`,
`check_generic_impl_bound.lani` and `tests/fixtures/lsp/slice_import_type_error.lani`
(saved and unsaved), and on the workspace-root fallback.

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

## Diagnostic defects

| File | Defect | Expected | Actual |
| --- | --- | --- | --- |
| `stdlib_stray_body_diagnostic.lani` | a stray function body (`let stray: i32 = 2; return stray;` then `}`) at top level of a stdlib module, `core::float_decimal` | LNC0016 "syntax error" at the stray line | **fixed 2026-11-01**: LNC0016 at the stray `let` (`float_decimal.lani:337:5`). Was LNC0008 "unsatisfied trait bound" at `stdlib/core/result.lani:93` (`and_then`'s `Mapper<T,Result<U,E>>` bound), which named neither the file nor the line; see [parser labels in a source pack](#parser-labels-in-a-source-pack) |
| `byte_order_mark_source.lani` | the file starts with a UTF-8 byte-order mark (EF BB BF) | rejected with a message that names the mark | **fixed 2026-11-01**: LNC0046 at 1:1, labeled "this file starts with a UTF-8 byte-order mark", with help "save the file as UTF-8 without a byte-order mark (U+FEFF)". Was "tokenization fails at this byte". The same label applies to a module under `--source-root` |

The program compiles and exits 0 against the real stdlib. To reproduce,
insert the stray lines into a copy of the stdlib:

```sh
D=target/claude-work/stdlib_stray; rm -rf $D; cp -r stdlib $D
sed -i '0,/^fn decimal_digit/{/^fn decimal_digit/i\    let stray: i32 = 2; return stray;\n}
}' $D/core/float_decimal.lani
target/claude-work/bin/lcc --stdlib-root $D -o target/claude-work/defect \
  tests/fixtures/compiler_defects/stdlib_stray_body_diagnostic.lani
```

The stray lines were left by deleting only the first line of a removed
function, and the misreport cost a bisection during the S5 Schubfach work.

### Parser labels in a source pack

Two host-side steps mislabeled the stray. Both are in
`compiler/diagnostics.rs`.

1. The trait-argument heuristic (`find_trait_parser_rejection`) turns a
   parser rejection into "trait bound argument shape is not supported here"
   (LNC0008) or "trait impl header uses an unsupported trait argument shape"
   (LNC0021) when it finds such a shape. It searched every line of every file
   in the pack, so any parse error in a program importing `core::result`
   matched the valid `Mapper<T,Result<U,E>>` bound at `result.lani:93`. It now
   searches only the line of the parser's error token, in that token's file.
2. The LL(1) label indexed a token stream that the host rebuilt from the
   files' text. That stream drifts from the GPU's stream after some stdlib
   constructs, so a rejection was labeled up to about 20 tokens early, inside
   the previous item. With `core::iter` imported, the stray module's label
   moved from its `let` to the `pub` of the function before it. The label now
   uses the GPU token at the rejection position, and the host stream is the
   fallback.

Probes of both cases were compiled through `laniusc daemon`. They used a
stray body in `core::float_decimal`, a stray in a new `core::straybad`
module imported beside `core::cmp`, `core::option`, `core::iter` or
`core::slice`, and a missing `;`. Every probe now reports LNC0016 at the stray
`let` or the missing `;`. `impl Rel<Boxed> for i32 {` still reports LNC0021.
The comparison run was 72 sample programs plus 112 syntax-error mutants of
40 of them (a dropped `;`, a stray body, an unclosed `(`). All 72 programs
and 104 mutants gave identical results, and the 53 binaries were identical.
The 8 mutants that changed all had wrong labels before. Six had a false
LNC0021 at a valid `Mapper<View<u8>,Result<i64,i32>>` impl header, and two
had LNC0016 labels three lines before the error. Six now point at the error.
The two `return (status;` mutants reported "expected ';' after return
statement" at the end of the file, just past the `}` after the unclosed
`(`. That label came from the statement heuristic
(`missing_statement_semicolon_label`), which counted bracket depth and so
read past the `;` inside the `(`. Since 2026-11-01 it tracks the open
brackets, and a `;` directly inside a `(` (never valid, unlike `[0; 8]` or a
block) labels that `(` "this `(` is not closed". An unclosed `(` at the end
of the file gets the same label. All 40 unclosed-paren mutants now point at
their `return (`. Before, 31 said "expected ';' after return statement" at
the end of the file or the line, and 9 said "expected `)`, found `;`" at the
`;`. The other 72 mutants are unchanged.
