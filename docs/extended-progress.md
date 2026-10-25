# Deterministic progress records

`ext::progress::render_into(state, destination, options)` writes one complete ASCII progress record into a caller's `View<u8>` and returns its byte count. It is pure rendering: it reads no clock, terminal, process, or environment state, and performs no allocation or I/O. Repeated calls with the same state and options produce the same bytes.

`State` has `current: u64` and `total: Option<u64>`. `options()` sets `bar_width = 20`, `max_output = 4096`, and `max_work = 16384`.

| State | Example with bar width 4 |
| --- | --- |
| Unknown total | `[????] 7/?\n` |
| Known, incomplete | `[##--] 1/2\n` |
| Complete | `[####] 2/2\n` |
| Known zero total | `[####] 0/0\n` |
| Overrun | `[####] 7/2 !\n` |
| Positive current, zero total | `[####] 7/0 !\n` |

For a positive total, filled columns equal `floor(min(current,total) * bar_width / total)`. The renderer uses bounded modular addition to avoid multiplication overflow even at `u64::MAX`. Unknown totals have question-mark bars. A known zero total is complete; current values above any known total retain their exact decimal value and gain ` !`. Bar width zero produces an empty `[]` bar.

`bar_width` must be in `0..=4096`; limits must be nonnegative. The renderer reserves `3 * bar_width + 128` work units before rendering, covering the fill calculation, bar writes, and bounded decimal operations. Output length includes brackets, counts, spaces, slash, optional overrun marker, and LF. `OutputLimit` and `WorkLimit` are distinct from insufficient destination `Capacity`. Invalid option values return `InvalidOptions` and invalid integer view metadata returns `Bounds`.

Every error leaves the entire destination unchanged. On success bytes outside the returned prefix remain unchanged, including any prefix before `destination.start`. The caller must physically back the claimed destination range; logical checks cannot validate actual backing. Runtime is O(bar width + decimal digits) with constant scratch space.

Focused tests compare edge states and deterministic generated `u64` values to a Rust `u128` fraction model, exercise width zero and 4096, deny all heap allocations, and verify atomic failure and destination guards. `csv-table --progress` consumes this API to emit one final record to stderr after the complete table has been written successfully.
