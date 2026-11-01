# Imported PNG header controls

Status (2026-10-27): both fixtures compile on `lang`. `original_result` and `original_value` each exit 0 natively, with the command from `evidence.json`.

These fixtures preserve two observations encountered while implementing
`ext::png`. `evidence.json` records bounded commands, diagnostics, execution
exit codes, and SHA-256 source hashes. They use the GPU compiler targeting
x86_64 Linux, with `stdlib` as the standard library root. Probe modules are
user source modules; they must not be loaded as standard library files.

`original_result` preserves the imported PNG implementation with a parser
returning `Result<Header, Error>`. It reports LNC0006 at the consumer's
`core::result::unwrap(parsed)` expression.

`original_value` uses a caller-owned parser header but passes it by value to
the internal reconstruction helpers. It compiles, yet its 1 × 1 grayscale
tRNS test returns 1 because the decoded pixel is opaque. The expected alpha
is zero. `borrowed_png_control.lani` runs the same input against the production
library with borrowed internal header arguments and returns zero.

The small `result4`, `result8`, `result11`, `value4`, `value8`, `value11`, and
`borrow11` controls all compile and return zero. Those results do not support
a general record-field-count limit. The underlying compiler cause is
unestablished. No compiler changes were made for these observations. The two
preserved PNG copies are diagnostic artifacts, not alternate production APIs.

`borrowed_control_at_observation.lani` preserves the exact production source
hash used for the recorded borrowed control. All diagnostic snapshots predate
the separate PNG reserved-chunk-bit correction; that correction cannot affect
this grayscale tRNS input, which contains no unknown chunks. The evidence also
records the final corrected production source hash.
