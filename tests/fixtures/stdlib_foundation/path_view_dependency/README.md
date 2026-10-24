# Direct malformed View construction

## Historical failure

On compiler base `441e66f9`, `inline.lani` reports LNC0017 with unsupported target
LIR opcode 31 at the `core::slice::View` literal. It supplies a native byte array
directly to the slice field of the imported generic record, with a negative
start, then calls `core::path::from_view`. This is a reduced construction failure;
it does not establish the compiler's internal root cause.

`from_view.lani` constructs the same one-byte view through `core::slice::view`,
sets its start to -1, and executes the expected Bounds result. It is included in
the normal path execution suite. Production path construction uses the checked
byte/range/view APIs.

## Current closeout

Both exact, unchanged sources compiled and executed once on x86_64 Linux at
HEAD `10be2529abfd7085053a1f37608f188ccc4c57fa`, after the general record-field
descriptor repair `678bf559`. Both compilations returned 0; both native programs
returned 0 with empty stdout and stderr. The inferred inline literal therefore
now reaches `core::path::from_view` and receives the expected error for its
negative start. No new compiler or library edits were made for this check.

The repair retains the accepted array-to-slice descriptor adjustment for record
fields and uses its three-word width during aggregate construction. See the
[four-way Text regression and layout controls](../../stdlib_compiler_state/settings_array_view/README.md).
The related [explicit schema literal and factory control](../../extended_library/schema_view_dependency.README.md)
also pass unchanged. The old dependency row for these exact forms can be marked
repaired; this does not claim arbitrary inferred record expressions execute.

| Case | Source SHA-256 | Emitted ELF SHA-256 |
| --- | --- | --- |
| `inline.lani` | `a176bc242b67b3d1fc630dbba4400a814b616370ec286d6cdfd4b6f25ee3169e` | `18383766fe4579747d0f5be47e831ef2be5220a5dec8a8abda55e9072e77e8c8` |
| `from_view.lani` | `150594308bbef2c2793264a97dd7c22f886c316c6440517b89c0e0598c5f46fc` | `f191eec3311d23c4b498837bbe817adeb7aa01952d4eba5584f58cf9005e975c` |

Compiler binary SHA-256:
`51704757e738dfbf37d7ed3bc33fc976f7bf8348ab340d1f4068efbed58abfcf`.
The compiler loads shaders at runtime, so the binary alone does not pin its
behavior. The two repaired shader artifacts had SHA-256 values
`cee754436d1ce14f48b2f91d5eea78c97cc91a2db91eca0e6b851918c5890624`
(`compact_aggregate_requests.spv`) and
`4db00809789372fd4a3dc2a2095f50e8bddeaedd5f35481b88d654884aedf6af`
(`aggregate_elements.spv`). Logs and ELF files are retained under the ignored
`target/stdlib-work/view-dependency-closeout-10be2529/` directory.

Current reproduction from the repository root, after building the compiler and
its shader artifacts:

```sh
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
 timeout --kill-after=2s 60s target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_foundation/path_view_dependency/inline.lani \
  --stdlib-root stdlib -o target/stdlib-work/path-view-inline && \
 timeout --kill-after=2s 3s target/stdlib-work/path-view-inline
timeout --kill-after=2s 100s flock -E 75 -w 35 target/stdlib-work/library-gpu.lock \
 timeout --kill-after=2s 60s target/stdlib-build/debug/laniusc \
  tests/fixtures/stdlib_foundation/path_view_dependency/from_view.lani \
  --stdlib-root stdlib -o target/stdlib-work/path-view-control && \
 timeout --kill-after=2s 3s target/stdlib-work/path-view-control
```

Both native runs are now expected to exit zero without output. Lock status 75
means the compiler did not run; it is not a compiler failure.
