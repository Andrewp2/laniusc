# Heap view composition and checked sample controls

Observed on 2026-10-23 with the active `target/stdlib-build` compiler, based on
repository checkpoint `d20fface`. These files retain the failed migration
contexts and successful controls. They are outside the production source roots
and are not all passing runtime fixtures.

| Source | Observed result |
| --- | --- |
| `nested_view_builder.lani` | Exact full `top_scores` attempt: `alloc::vec::from_view(heap.as_view())`, then Vec sort. The sample entry failed LNC0047. |
| `typed_view_builder.lani` | Exact full attempt with an explicit `View<i64>` intermediate and `from_view<i64>`. The sample entry still failed LNC0047. |
| `minimal_view_builder.lani` | Reduced heap view → alloc Vec builder → sort; CLI native compilation fails LNC0047. |
| `minimal_heap_view.lani` | Eleven-line heap creation/push/view/read case; CLI native compilation fails LNC0047. No alloc Vec or sorting is involved. |
| `heap_view_builder.lani` | Full attempt using the existing checked heap `from_view<i64>` into a Max heap. CLI native compilation fails LNC0047, without importing alloc Vec. |
| `minimal_vec_sort_control.lani` | Independent canonical `Vec<i64>` push/sort/read control; compiles and exits 0. |
| `legacy_transfer_control.lani` | Same full input, signal policy and checked writers with the old `take_sorted_vec` transfer; compiles and prints `42\n42\n7\n` for the input below. This is a historical compiler control, not a production fallback. |
| `drain_builder_control.lani` | Checked destination reserve, transfers through the shared heap's `pop`, reverse traversal; compiles and prints the same result. The production sample uses this source form. |

The two full alloc Vec attempts were first compiled through the actual
`sample_programs/top_scores.lani` entry by the focused Rust target; their exact
source text is retained here. The reduced failures and remaining controls were
compiled directly with the CLI. No compiler, heap implementation or protected
vector implementation was edited during these probes.

The diagnostic is LNC0047 with this detail:

```text
a replay argument has no complete GPU native layout; its defining nominal
payloads or a retained checked width witness are required
```

Its reported `core::cmp` module location identifies the replay scope; it does
not establish that primitive ordering is broken. The independent vector sort
control passes. At probe time, `BinaryHeap.as_view` wrapped
`unwrap(core::slice::view(...))`, resembling the source shape in the earlier
`vec_view_dependency` record. This is not a confirmed common compiler cause;
packet/layout evidence would be needed to establish one. The compiler owner
subsequently tested a source-only direct View return for the heap. The
production sample deliberately keeps the checked drain form independently of
that correction. The separate attempted alloc-Vec-backed heap migration
remains its own retained dependency.

`binary_heap_before_view_correction.lani` pins the exact original module
(SHA-256 `9ca8a757116a70d672858365ecfe43740888825280098a6c9e963277d122b903`).
Reproduce a case with that module in a temporary copy of the current stdlib:

```sh
timeout --kill-after=2s 100s python3 \
  tests/fixtures/stdlib_compiler_state/checked_sample_heap/reproduce.py minimal_heap_view
```

The helper takes one source name from the table, acquires the shared GPU lock,
bounds compilation to 60 seconds, and removes only its newly created temporary
copy. It executes successful controls with a ten-second runtime bound, using
this input for full application controls:

```text
3
-1
42
42
7
```

The successful drain form reserves before consuming any score, checks every
append and destroys both owners on errors. It uses the existing min-heap
priority engine; it does not implement another selection or sorting algorithm.
