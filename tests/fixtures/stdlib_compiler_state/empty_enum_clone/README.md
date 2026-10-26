# Empty enum clone layout reduction

This fixture family isolates the first `core::clone_values` scalar admission
failure. It is a compiler diagnostic/regression surface, not an alternate
production error type. Production `core::clone_values::Infallible` remains a
true empty enum with no constructible variants.

The initial scalar group failed before native execution with LNC0047,
GenericInstantiationBoundary detail 6, after 4.00 seconds. The log is
`target/stdlib-work/clone-values-scalars.log`. Its source label points at the
imported generic consumer; that label alone does not identify the missing
layout or establish that parsing an empty enum is unsupported.

## Paired minimal entries

The compact durable driver is
[`tests/compiler_empty_enum_layout_execution.rs`](../../../compiler_empty_enum_layout_execution.rs).
It uses the production stdlib and this directory as a user root. Each named
test compiles one entry, uses the unchanged strict native ELF checker, and
requires native exit zero with empty stdout/stderr. All six paired reductions
passed after the checked empty-enum layout fix, in 8.11 seconds.

| Empty enum entry | Inhabited diagnostic control | Isolated path |
| --- | --- | --- |
| `plain_empty.lani` | `plain_inhabited.lani` | A local Result<i32,E> return and direct match; no clone protocols or generic unwrap |
| `direct_empty.lani` | `direct_inhabited.lani` | Direct concrete i32 TryClone call, then checked Result projection |
| `imported_empty.lani` | `imported_inhabited.lani` | Imported generic TryClone consumer with explicit T/E |

The direct/imported empty entries use the exact production scalar
implementation and Infallible type. `fixture/control.lani` defines a separate
one-variant error and an explicit scalar implementation solely for the paired
controls. It is never imported by production. `fixture/consumer.lani` makes
both implementations visible while its explicit E selects the exact one.
The controls do not authorize replacing Infallible or weakening a public
error contract.

## Before and after receipts

Logs under `target/stdlib-work/` record:

| Receipt | Result | Elapsed |
| --- | --- | ---: |
| `empty-enum-reductions-before.log` | Three empty-enum entries rejected with LNC0017 missing callee aggregate layout; all three inhabited controls passed strict native checks | 4.57 s |
| `empty-enum-reductions-after.log` | All six entries passed strict native checks and exit-zero assertions | 8.11 s |
| `empty-enum-native-stride.log` | Both plain-result entries passed with explicit enum size assertions | 3.76 s |

The reduction failure is LNC0017, distinct from the original full scalar
group's LNC0047 replay diagnostic. Both are retained rather than flattened
into one reported error. These receipts establish Result return, direct
scalar cloning and imported generic dispatch with the real empty enum; the
inhabited controls remain diagnostic only.

The two plain-result entries now additionally assert
`core::mem::size_of<Empty>() == 8` and the analogous inhabited enum size,
without constructing an empty-enum value. Both added size assertions passed
in the separate two-test 3.76-second gate. The six-entry 8.11-second result
predates those assertions; the later receipt establishes the actual native
storage size alongside Result return behavior.

## Owner tracing and checked repair

The fixture author performed read-only source tracing and independent patch
review. The compiler owner implemented the repair. The original paths were:

- `CheckedUnitContracts::nominal_recipes` and `read_nominal_recipes` in
  `crates/laniusc-compiler/src/type_checker/checked_contracts.rs` retain zero
  variant groups for an empty enum. Recipe admission also accepts that shape.
- `shaders/type_checker/program_evidence/native_layout/materialize.slang`,
  `plm_expand_nominal`, explicitly returned unsupported detail 177 for
  `tail.x == 0`. This occurs after recipe identity/owner/operand checks.
- `CheckedConcreteValueLayout::leaf_words` in
  `shaders/type_checker/semantic/artifact/01c_generic_native_words.slang` had no
  complete leaf case for a recognized empty enum. Its layout step and the
  shared `concrete_value_layout_walk.slang` reject zero groups as missing or
  unsupported layout. That rejection remains correct for unknown metadata.
- The existing enum ABI reserves one discriminant word, even without variants:
  LIR `semantic/function_layout_collect.slang` initializes every enum to one;
  `function_scatter.slang::local_enum_word_count` returns one plus maximum
  payload; `shaders/dependency_return_layout.slang` initializes enum width one.
  This is storage layout, not a legal discriminant or an inhabitable value.
- `dependencies/enum_instance_layout.slang` instead initialized its computed
  maximum to zero and only raised it while visiting members.

The accepted repair recognizes an actual checked local enum or admitted
retained enum with zero variants as a complete one-word layout, and supports
the same shape in program-evidence materialization without inventing a group,
variant or constructor. Materialization publishes that known width in its
existing expanded-layout row after recipe, owner and operand admission; leaf
evaluation reads the checked cache. A first implementation repeated recipe
lookup in the leaf and exceeded the enabled shader budget (40,246 versus
40,000). The final form removed that repeated lookup while keeping the budget
enabled. Imported enum-instance computation now retains the same discriminant
word.

All missing identity/recipe/payload facts continue to reject. Records still
require one admitted field group; a zero-group empty enum is identified by its
actual enum recipe. Unknown zero group counts are not treated as valid
layouts. No legal discriminant, inhabitable substitute or automatic ownership
behavior was introduced. The paired tests establish this focused layout path;
other generic layout dependency fixtures retain their own status.
