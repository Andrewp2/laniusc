# Existing-type composition probes

Executed on 2026-10-11 using the preserved native caller-evidence compiler and
its matching shaders, before the sibling-method emission change. Each JSON
record retains the command, binary hash, source hash, duration, and process exit.
The performance harness compiles the source and checks the emitted ELF program's
exit status, stdout, and stderr. These one-sample runs are correctness probes,
not performance measurements.

| Probe | Observed result | Meaning |
| --- | --- | --- |
| `pointer-slice-composition.lani` | Exit 0; emitted output verified | Full pointers survive a slice inside a generic record through local and imported identity. Slice mutation preserves aliases while copied scalar fields remain independent. |
| `nested-reference-forwarding.lani` | LNC0021: inherent impl target path is malformed | Structural reference impl targets are rejected before a second reference layer can be produced. Nested-reference forwarding and matching are not assessed by this failure. |
| `wide-scalar-composition.lani` | Compilation succeeds; emitted program exits 1 | The ordinary `u64` literal/control path fails before generic wrapper assertions. This is an existing scalar-production dependency, not evidence that generic forwarding corrupts the value. |

The latter two are unresolved reproductions, not expected-failure acceptance
tests. No general support claim follows from this small matrix.
