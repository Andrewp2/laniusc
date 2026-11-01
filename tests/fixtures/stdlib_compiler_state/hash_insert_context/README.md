# Hash insertion result-context compiler dependency

Status (2026-10-27): fixed on `lang`. The literal was the cause. In a call's value environment, an argument claim came before the receiver's binding, so the unsuffixed literal's default `i32` claim set `V`. `try_insert` then returned `Result<Option<Entry<i32,i32>>,...>`. The value environment now ranks claims from literals that can take context after the context bindings, as the expected environment already did. `primitive_nested.lani` compiles and runs with exit 0. The regression test is `a_receiver_binding_types_a_literal_argument` (`tests/fixtures/language/receiver_binds_literal_argument.lani`).

These retain a primitive-key reproducer and an accepted explicitly typed
control for an observed failure in the owning-hash sequence fixture. They are
outside the ordinary runtime fixture root. The root ran both with the current
CLI and ran the typed control on native Linux x86-64. No Rust driver or compiler
change accompanies them, and no compiler fix is claimed.

## Observed full-context failure

The first owning-hash gate recorded three passing groups and one compilation
failure in 11.98 seconds. Its retained log is:

```text
target/stdlib-work/owning-hash-native.log
```

The failed source was
[`tests/fixtures/stdlib_foundation/owning_hash/model.lani`](../../stdlib_foundation/owning_hash/model.lani),
line 56, column 90 at the time of the failure. The exact original call was:

```lani
map_item(recovered.try_insert(fixture::key::make(inserted,999),-9223372036854775807).unwrap());
```

The compiler reported `LNC0006`, `AssignMismatch`, at `.unwrap()`:

```text
value type does not match this context
```

`map_item` requires `Option<Entry<fixture::key::Key,i64>>`. The receiver was
recovered from a `HashMap<fixture::key::Key,i64>` owning cursor, and the preceding
`get_entry` result was passed to the same consumer. `HashMap.try_insert` returns
`Result<Option<Entry<K,V>>,hash_map::Error>`. The diagnostic location supports
investigating the nested generic result context; it does not establish that
the literal range or signed i64 storage is invalid.

The runtime fixture now explicitly binds the insertion value as `i64` and the
insertion result as `Result<Option<Entry<fixture::key::Key,i64>>,hash_map::Error>`.
Its model oracle and exact value were preserved. The outcome of that annotated
full-context rerun was a pass through production GPU compilation, the strict
native executable checker and all 5,368 model cases on native Linux x86-64.
The focused run took 5.85 seconds and filtered out the other three groups. Its
separate receipt is `target/stdlib-work/owning-hash-model-typed.log`.

Together these receipts show three groups passing in the earlier mixed suite
and the typed model passing afterward. They do not record one all-green suite
run or establish a compiler fix for the original nested expression. The
separate primitive-key probes below reproduce the same distinction.

## Primitive reproducer and typed control

| Source | Deliberate difference | Observed status |
| --- | --- | --- |
| `primitive_nested.lani` | Replace the custom key and sequence/model machinery with a primitive key; retain owning recovery and the nested insertion/unwrap argument with the same negative literal | CLI compile exit 1, LNC0006 AssignMismatch at line 14, column 58, `.unwrap()`; no native execution |
| `primitive_typed_control.lani` | Same setup and checks, with explicit i64 and exact Result locals | CLI compile exit 0 and native exit 0 |

The separate receipts are `target/stdlib-work/hash-context-nested.log`,
`target/stdlib-work/hash-context-typed.log`, and
`target/stdlib-work/hash-context-typed-native.log`. These CLI probes establish
the observed compile rejection and typed native result; the full-model Rust
gate above also supplies the strict shared executable validation.

Both sources require only the current canonical stdlib root, with no user root.
They replace one stored value, verify the returned previous Entry, and check
that the new stored i64 has bit pattern `0x8000000000000001`. The typed control
executed those checks successfully. The decimal source value remains exactly
`-9223372036854775807` in both files.

Primitive keys are sufficient to reproduce the nested-context failure, so the
custom key is not required for this reduction. The accepted control changes
both the literal context and the Result context. Which annotation alone would
be sufficient remains untested. The rejected nested form remains a compiler
dependency; these probes do not establish that signed i64 storage or this
literal range is invalid.

## Bounded reproduction commands

From the repository root with the current CLI already built, use 20-second
compilation bounds and a two-second native bound:

```sh
timeout --kill-after=1s 20s target/stdlib-build/debug/laniusc --stdlib-root stdlib tests/fixtures/stdlib_compiler_state/hash_insert_context/primitive_nested.lani -o target/stdlib-work/hash-context-nested > target/stdlib-work/hash-context-nested.log 2>&1
timeout --kill-after=1s 20s target/stdlib-build/debug/laniusc --stdlib-root stdlib tests/fixtures/stdlib_compiler_state/hash_insert_context/primitive_typed_control.lani -o target/stdlib-work/hash-context-typed > target/stdlib-work/hash-context-typed.log 2>&1
timeout --kill-after=1s 2s target/stdlib-work/hash-context-typed > target/stdlib-work/hash-context-typed-native.log 2>&1
```

The expected statuses are 1, 0 and 0 respectively. Future compiler probes
should record their outcomes separately from the original mixed suite and the
focused full-model receipt.
