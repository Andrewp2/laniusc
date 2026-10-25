# Schema view literal dependency closeout

`schema_view_literal_repro.lani` is a compiler/layout reproduction, with no schema
module imported. A live native `[u8;8]` initialized to 77 supplies the slice
field of an explicitly specialized imported `core::slice::View<u8>`. Its
remaining fields are `start:-1` and `length:2`. The historical execution at
compiler base `bface65d` printed `77,77` instead of the expected `-1,2`.
`schema_view_factory_control.lani` constructs through `core::slice::view`, then
sets start to -1; its expected output is also `-1,2`.

## Current result

Both exact, unchanged sources compiled and executed once on x86_64 Linux at
HEAD `10be2529abfd7085053a1f37608f188ccc4c57fa`, after record-field descriptor
repair `678bf559`. Both compilations and native runs returned 0. Both programs
printed exactly `-1,2\n`, with empty stderr. No compiler or library edits were
made for this check. The explicit direct literal no longer corrupts the fields
following its slice descriptor.

| Case | Source SHA-256 | Emitted ELF SHA-256 |
| --- | --- | --- |
| `schema_view_literal_repro.lani` | `0043002da0a30365edb5144cc7376796a3138a29631064c95c15c63c0daca67a` | `ef221c04a58a6d485b187f486677f36b1c17ce80643c3a436d9083f41731e5b4` |
| `schema_view_factory_control.lani` | `742716372bc434825dbc6ddfce5a67e3e8394c8af191481d2e7a0300280b7cd9` | `c82f9da30f08d0c4af5155fff210b87fbe86c89b50a0e7e5fc533b42e631c582` |

The [path-view closeout](../stdlib_foundation/path_view_dependency/README.md)
records the paired inferred literal/control, compiler and shader hashes, and
ignored log location. The [descriptor-layout repair evidence](../stdlib_compiler_state/settings_array_view/README.md)
explains the general adjustment and its native regression coverage. The old
dependency row can be marked repaired for these retained forms. These results
test view construction; they do not constitute a new schema validation suite.

## Reproduction

From the repository root, after building the compiler and its shader artifacts:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
 timeout --kill-after=2s 60s target/stdlib-build/debug/laniusc \
 --stdlib-root stdlib tests/fixtures/extended_library/schema_view_literal_repro.lani \
 -o target/stdlib-work/schema-view-literal && \
 timeout --kill-after=2s 3s target/stdlib-work/schema-view-literal
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
 timeout --kill-after=2s 60s target/stdlib-build/debug/laniusc \
 --stdlib-root stdlib tests/fixtures/extended_library/schema_view_factory_control.lani \
 -o target/stdlib-work/schema-view-factory && \
 timeout --kill-after=2s 3s target/stdlib-work/schema-view-factory
```

Neither entry imports `ext::schema`, so no extended source root is required.
Lock status 75 means no compiler invocation occurred.
