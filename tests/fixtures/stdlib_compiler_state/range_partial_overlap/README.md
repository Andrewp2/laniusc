# Partial-order overlap defect and total-order repair

This is a historical **library semantic/API defect**, not a compiler failure.
The former `overlaps` signatures accepted `PartialOrd`, although the four
endpoint comparisons do not establish a shared member for every partial order.

`before.lani` supplies a lawful partial order on four values: 0 and 1 are
incomparable lower values, 2 and 3 are incomparable upper values, and each
lower value is below each upper value. Equality is identity. It enumerates
all members of [0,2) and [1,3), and of [0,2] and [1,3]. Neither pair shares a
member, but the former free/method half-open/inclusive overlap calls all
return true.

Before the repair, native compilation and execution against the production
stdlib succeeded at base `917b594d5cc43ba91fb0b6306c93bd7ab6a03986`. The executable
printed:

```text
0
0
15
```

The first two lines count common members. The last is the four false-positive
flags. Exit status was 0 because the reproducer asserts the observed defect.
Ignored artifacts are `target/stdlib-work/range-overlap-before{,-compile.log,-run.log}`.
Their SHA-256 hashes at capture were:

| Artifact | SHA-256 |
| --- | --- |
| `before.lani` | `0479a379032a3ed3072d838c11f9255e302ef2b18f1a80434e7cb8c9490054fe` |
| `range-before.lani` | `d0fda185395214a7ef4fb15d3a1c0854ba6d2c2fb545a333c0e362e9812397ad` |
| Native ELF | `0dd08c9da64e27ee66b1f22b07ec37a1cd48cca06dd23bd56656dc3ec65cf9c9` |

`range-before.lani` preserves the exact old library source. To reproduce with
a current compiler, copy the current stdlib to a temporary root and replace
only its range module with this snapshot:

```sh
range_root=$(mktemp -d)
cp -a stdlib "$range_root/stdlib"
cp tests/fixtures/stdlib_compiler_state/range_partial_overlap/range-before.lani \
  "$range_root/stdlib/core/range.lani"
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
  timeout --kill-after=2s 60s target/stdlib-build/debug/laniusc \
  --stdlib-root "$range_root/stdlib" \
  tests/fixtures/stdlib_compiler_state/range_partial_overlap/before.lani \
  -o target/stdlib-work/range-overlap-before
timeout --kill-after=2s 5s target/stdlib-work/range-overlap-before
rm -rf "$range_root"
```

The repair requires `Ord` and uses `lt`/`le` in all four overlap APIs. It keeps
`PartialOrd` membership/emptiness and raw IEEE float behavior there. For a
total order, the greater start is a common-member witness whenever the
nonempty guards and crossing comparisons hold. Native floats need an explicit
policy such as TotalF32/TotalF64 before overlap. There is no old-behavior alias.

Current acceptance lives in `tests/stdlib_range_overlap_execution.rs`: a native
Ord-only record and independent common-member model, native partial-only
membership control, and separate bound-rejection tests for every overlap call
form on the partial-only record and both raw float widths. The historical
reproducer itself is intentionally outside the positive runtime inventory.

Focused repaired acceptance passed on x86_64 Linux after the shared runtime
and jump-checker controls closed:

| Exact test in `stdlib_range_overlap_execution` | Result |
| --- | --- |
| `total_order_overlap_matches_enumerated_common_members_and_migrated_caller` | 1 passed, 0 failed; 88114 quadruples through all four APIs plus the migrated comprehensive caller; 8.48 s |
| `partial_order_membership_executes_and_all_overlap_forms_reject` | 1 passed, 0 failed; native membership control plus four separate `LNC0008` bound rejections; 4.06 s |
| `native_f32_overlap_requires_an_explicit_total_order` | 1 passed, 0 failed; four separate `LNC0008` bound rejections; 3.61 s |
| `native_f64_overlap_requires_an_explicit_total_order` | 1 passed, 0 failed; four separate `LNC0008` bound rejections; 3.63 s |

Logs are `target/stdlib-work/range-overlap-{model,partial,f32,f64}-tests.log`.
Each test ran separately under the shared GPU lock and a 60-second command
cap. No broad foundation or comparison suite rerun was needed. An initial
`LNC0016` in the new model fixture was an unsupported `else if` spelling;
separate tagged `if` branches fixed that test syntax before the accepted run.
