# Native layout of an empty enum

A checked enum with no variants has a known native layout of **one eight-byte
word**. It keeps the existing enum discriminant cell, although no legal
discriminant can construct a value of that type. This is different from a type
whose definition or native layout is unavailable.

The GPU layout change is implemented and independently reviewed. On Linux
x86-64, all six paired reductions, the five `core::clone_values` groups, four
inhabited structural controls, explicit native-size checks and the existing
zero-sized composition regression pass. These receipts cover the cases below.

## Existing ABI and the failure

The native ABI already reserves a discriminant word for every enum. LIR
declaration collection initializes enum widths to one word, local enum result
layout computes `1 + maximum_payload_words`, and imported result projection
starts at one word. An enum with no variants therefore has width one word and
stride eight bytes. This representation does not make the type inhabited or
invent a valid tag.

The checked native layout path did not preserve that fact. It represented a
known empty enum with zero payload groups, then treated zero groups as an
unavailable layout. Program-evidence materialization also explicitly rejected
that case. These failures could block `Result<i32,Empty>` even when a function
returned only `Ok(37)`.

An initial scalar-clone gate reported `LNC0047`, detail 6, at an imported generic
consumer: a replay argument lacked a complete GPU native layout. The paired
reductions also failed without cloning or an imported generic consumer, so the
investigation did not depend on the clone implementation alone.

## Complete empty definitions and missing layouts

The existing definition records already distinguish the relevant cases:

| Evidence | Meaning |
| --- | --- |
| Admitted enum recipe with zero variant groups | Known empty enum; width one word |
| Admitted record recipe with one empty field group | Known empty record; its existing zero-word layout |
| Complete retained enum kind with zero variant groups | Known imported empty enum; width one word |
| Missing recipe, incomplete retained payloads or unresolved nominal identity | No authority to assign an empty-enum width |

Recipe admission still requires a record to have exactly one field group. An
enum retains one group per variant, including a group with no payloads for a
variant such as `Only`. No fake variant or field is added for `enum Empty {}`.
Raw declaration member counts are not variant counts: generic parameters and
other members must not change whether an enum has a variant.

## Three GPU producers

The change aligns three existing GPU layout sites:

1. [Checked native widths](../shaders/type_checker/semantic/artifact/01c_generic_native_words.slang)
   recognize a proven local empty enum or a complete retained enum with no
   variant groups. The local check runs before the bare nominal scalar path
   returns an unresolved layout; local monomorphic replay can use that path.
   Retained recognition requires enum kind 7 with the completion bit admitted
   by `retained_layout_kind`, plus a zero group count. A provisional width of
   zero does not satisfy it.
2. [Program-evidence materialization](../shaders/type_checker/program_evidence/native_layout/materialize.slang)
   accepts an admitted enum recipe with zero groups and publishes width one in
   its existing expansion row. The ordinary leaf reader then consumes that
   completed width. Recipe lookup, exact owner identity, operand arity and
   parameter checks remain in the expansion path. A missing recipe still fails.
   This uses the producer's existing recipe read; leaf evaluation adds no
   repeated recipe lookup.
3. [Imported enum projection](../shaders/type_checker/dependencies/enum_instance_layout.slang)
   starts its maximum at the discriminant width after checking the enum
   declaration, signature reference and member range. Variant payloads can
   increase that width; unavailable payload widths still fail closed.

The shared layout walker continues to reject an unexplained zero group count.
Retained width witnesses remain optional facts checked by the existing native
publication path. The host does not calculate or guess a replacement width.

## Source ordering and lookup cost

The local check first resolves the exact enum declaration and validates its
source-token span. It then uses a lower bound over variant name tokens to find
the first candidate in that span. It accepts emptiness only when no variant
name lies inside the declaration, with adjacent owner checks rejecting an
owned row outside the span.

The ordering comes from the parser producer:
[variant marking](../shaders/parser/hir/canonical/variants/mark.slang) indexes
candidates by their name-token anchor, and
[variant scattering](../shaders/parser/hir/canonical/variants/scatter.slang)
prefix-compacts those anchors. The search uses that source order. It does not
assume that canonical HIR owner IDs are sorted.

For V retained variants, this lookup takes O(log V) comparisons and O(1) local
storage. It adds no full-table scan, new layout relation or persistent cache
field. The patch changes no IR row shape, object ABI, extractor or proof system.

## Focused evidence

[The reduction driver](../tests/compiler_empty_enum_layout_execution.rs) uses
[six small programs](../tests/fixtures/stdlib_compiler_state/empty_enum_clone/):

| Pair | Empty-enum case | Inhabited control |
| --- | --- | --- |
| Plain result | Return `Result<i32,Empty>` and match it directly | Same path with one unused constructible variant |
| Direct scalar clone | Production `i32::try_clone_value` with `Infallible` | Explicit test clone with an inhabited error enum |
| Imported generic clone | Generic consumer with explicit `Infallible` | Same consumer with the inhabited control error |

Before the change, all three empty-enum programs failed and all three inhabited
controls passed in **4.57 seconds**. The empty reductions reported `LNC0017` for
a callee aggregate result layout; the plain result case needed no clone trait
or imported generic consumer. The local log is
`target/stdlib-work/empty-enum-reductions-before.log`.

After the change, all six paired programs compiled and executed successfully in
**8.11 seconds**, retaining the unchanged strict native executable checker. The
local log is `target/stdlib-work/empty-enum-reductions-after.log`. These finite
cases cover the three paths above; they do not establish broad native support.

Additional checks passed with the rebuilt compiler:

| Gate | Result | Covered behavior | Local log under `target/stdlib-work/` |
| --- | --- | --- | --- |
| `stdlib_clone_values_execution` | 5 groups, 19.37 s | Exact scalar/Unicode/IEEE values; nested Option/Result/Pair/Vec owners; inactive payloads and minimal bounds; 18 callback cases, 14 owned errors and all 45 reached allocation failures; expected source rejections | `clone-values-native-current.log` |
| `compiler_structural_clone_result_execution` | 4 controls, 7.95 s | Inhabited nested result layouts through concrete, imported generic, local trait and imported trait calls | `structural-clone-result-controls.log` |
| Explicit native size | 2 tests, 3.76 s | `size_of<Empty>() == 8` and the inhabited control's eight-byte layout, followed by the plain Result calls | `empty-enum-native-stride.log` |
| Existing zero-sized composition regression | 1 test, 3.86 s | Zero-sized payloads preserve neighboring values and array bounds | `empty-enum-zero-sized-regression.log` |
| Existing native materializer and recipe contracts | 4 tests, 6.38 s | Nested layouts and terminal descriptors, exact parameter identities, capacity recovery, stale epochs, broken groups and foreign lexical bindings | `empty-enum-native-layout-contract-regression-stack.log` |

The size checks directly test the retained discriminant width. The neighboring
zero-sized regression keeps the distinction between an empty enum and a known
zero-word aggregate observable. Expected source rejections remain part of the
clone-values gate; passing it does not relax leaf protocol or opt-in bounds.
The four internal compiler tests use `RUST_MIN_STACK=67108864` for their Rust
test threads. The default test stack overflowed before the first case could
finish; the larger test stack does not change the production compiler or GPU
layout limits.

## Shader size gate

The first materializer revision repeated recipe lookup during leaf evaluation.
It reached **40,246 fully inlined instructions** and failed the enforced 40,000
instruction budget. The accepted revision publishes the complete empty-enum
width in the existing expansion row, reusing the recipe already checked there.

The rebuilt focused drivers passed the active size gate in **7.59 seconds**.
The final materializer has **39,677 fully inlined instructions**; the checked
native-width kernel has **25,728**. No budget was raised or disabled. Local
receipts are `target/stdlib-work/empty-enum-layout-fix-compact-build.log` and
`target/stdlib-build/laniusc-shader-artifacts/debug/inlined_sizes.txt`.

These instruction counts describe the compiled kernels, not runtime latency.
The build and test durations are observations from these runs, not performance
guarantees or directly comparable benchmarks. Static review and
`git diff --check` also passed. The runtime receipts establish these named Linux
x86-64 cases, not complete enum or generic-layout coverage.
