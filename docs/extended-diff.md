# Exact byte line diff

`ext::diff` computes a shortest insertion/deletion script and encodes a deterministic single-file unified patch. Import it with `--source-root extended --stdlib-root stdlib`. The implementation is Lanius source in `extended/ext/diff.lani`; native Rust and Python tests provide independent oracles.

## Inputs and ownership

`compare_bytes(before, after, limits)` accepts `core::slice::View<u8>` values. A file line includes its terminating LF byte. Empty input has zero lines. A final nonempty fragment is one line. CR is ordinary data, so CRLF and LF differ; NUL, invalid UTF-8 and every other byte are preserved. A missing final LF differs from a present LF.

`split(input, limits)` returns owned `Lines` descriptors with `len()`, `line(index)` and `as_view()`. `compare_lines(before, after, limits)` accepts `View<View<u8>>` and compares arbitrary byte-sequence elements, including empty elements and embedded LF. It copies the outer descriptors and borrows each element. This sequence API need not represent a byte file; unified encoding checks that additional constraint.

Views must describe live, initialized backing storage. The library rejects negative starts/lengths and overflowing logical ranges. Physical backing size cannot be discovered by Lanius's current view API and remains the caller's responsibility.

A returned `Script` owns two descriptor vectors and one step vector. Inputs may overlap or be the same view. Keep every borrowed input stable until `Script.destroy()`. `Lines.destroy()` and `Script.destroy()` reset their own buffers and may be called again on the same active owner. Shallow copies alias allocations: keep one active owner, borrow it through `borrow()`, and never destroy two copies. No input allocation transfers to the library.

## Script API

`Script.distance()` is the number of insertions plus deletions. Replacing a line costs two. `len()` counts every step, including equal lines. `step(index)` returns `Step { kind, before, after }`, with zero-based positions in the original sequences:

| kind | meaning | position advanced |
| --- | --- | --- |
| 0 | equal exact byte lines | before and after |
| 1 | delete | before |
| 2 | insert | after |

`before_len()`, `after_len()`, `before_line(index)` and `after_line(index)` expose borrowed inputs. Bounds errors return `Error::Bounds`. A script is complete: walking all steps consumes both sequences in order. Internal fields are implementation state; callers must use the accessors rather than mutate them.

## Algorithm and limits

The implementation follows Figure 2 and trace reconstruction in Eugene Myers, [*An O(ND) Difference Algorithm and Its Variations*](https://neil.fraser.name/writing/diff/myers.pdf), sections 3 and 4a. It scans edit distance in ascending order, extends each furthest-reaching diagonal through exact byte equality, then walks stored predecessor rows backward and reverses the steps. Equal predecessor endpoints choose deletion. This tie rule is deterministic; another minimal diff can choose a different script. There are no heuristics that trade minimality for speed.

The mature reference inspected was Git's [xdiff implementation](https://github.com/git/git/blob/master/xdiff/xdiffi.c). This library uses the paper's compact saved trace rather than Git's bidirectional divide-and-conquer and heuristic cutoff. Each row stores `d+1` endpoints, so retained trace storage is at most `(D+1)(D+2)/2` i32 entries; the final row stops when it reaches the goal. Search requires `O((N+M)D)` line comparisons (linear work for identical inputs), `O(D²)` trace entries and `O(N+M)` descriptors/steps. Line comparisons verify length and every byte; no hash can certify equality. Byte comparison cost is additional and bounded by `max_work`.

`Limits` has these fields; all counts are nonnegative:

| field | default | bounds |
| --- | ---: | --- |
| `max_lines` | 1,000,000 | each input sequence's lines |
| `max_work` | 100,000,000 | split bytes, copied descriptors, diagonal states, equality probes and compared bytes, reconstructed steps |
| `max_trace` | 4,000,000 | retained i32 trace entries |
| `max_edits` | 2,000,000 | complete step count, including equal lines; also caps searched distance |
| `max_output` | 67,108,864 | unified output bytes |

The combined input sequence length must also fit 1,073,741,822 lines so doubled diagonal arithmetic stays representable; otherwise generation returns `LineLimit`.

The encoder starts its own work budget and charges line/header validation, hunk scanning and output bytes. Trace and steps are dynamically owned; all failure paths release temporary buffers. Allocation and container capacity failures return `AllocationFailed`. Other errors are `InvalidLimits`, `Bounds`, `LineLimit`, `WorkLimit`, `TraceLimit`, `EditLimit`, `OutputLimit`, `InvalidLine` and `InvalidHeader`. Failure publishes no script or encoded buffer.

## Unified encoding

`encode_unified(script.borrow(), old_name, new_name, context, limits)` returns an owned `alloc::vec::Vec<u8>`. Destroy it when finished. An identical script returns an empty byte vector. Context must be nonnegative and at most 1,073,741,822. Context groups merge when at most `2*context` equal lines separate changes. Each affected area includes up to `context` preceding and following lines.

Headers are exactly `--- old_name\n` and `+++ new_name\n`. Names must be nonempty and contain no NUL, TAB, CR or LF; other bytes are copied. Names are labels with no filesystem interpretation. Hunk ranges always include the count, including `,1` and `,0`. Positions follow the [POSIX diff unified format](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/diff.html) and [GNU diffutils description](https://www.gnu.org/software/diffutils/manual/html_node/Detailed-Unified.html). LF-terminated records use space, minus or plus prefixes. An incomplete final line gets a synthetic LF followed by the exact English GNU marker `\ No newline at end of file\n`.

For encoding, each sequence element must be nonempty, contain LF only as its final byte, and end in LF unless it is the last element. Other sequence inputs return `InvalidLine`. This restriction applies only to the unified file representation. The companion [patch library](extended-patch.md) parses and applies this format exactly in memory. Neither module orchestrates files or multiple-file patches.

## Verification

`tests/extended_diff_patch_execution.rs` compiles native Lanius fixtures. It checks minimal edit distance against an independent quadratic dynamic program, generated byte-file roundtrips, deterministic output, overlapping borrowed input, general byte-sequence elements, CRLF and missing LF, malformed metadata and limits. Python `difflib` forms independent complete-line patches. A 25,000-line mostly equal case exercises scale. Native `strace` allocation failure sweeps verify cleanup and absence of partial output. The separate `text_patch` CLI suite exercises GNU interoperability and staged command output.

Verified execution is x86_64 Linux output from the GPU compiler. Other targets
and user GPU kernels have not been verified.
