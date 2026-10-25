# Strict in-memory unified patches

`ext::patch` parses one supported unified diff and applies it at its exact declared line positions. It returns a new owned byte vector after all hunks and base context validate. Import with `--source-root extended --stdlib-root stdlib`.

## API and ownership

`parse(input, limits)` returns `Result<Patch, Error>`. `Patch.hunk_count()`, `line_count()` and `hunk(index)` inspect the parsed structure. `Hunk` exposes zero-based `before`, `before_count`, `after`, `after_count`, and the descriptor interval `first`, `count`. `apply(base, patch.borrow(), limits)` returns `Result<alloc::vec::Vec<u8>, Error>`. `apply_unified(base, input, limits)` combines parse and apply and always frees its temporary patch descriptors.

`Patch` owns its hunk and line descriptor vectors and borrows the patch bytes. Keep those bytes alive and stable through its last use, then call `destroy()`. Borrow the active owner through `borrow()`; shallow copies alias allocations and must not become independent owners. `destroy()` resets the same active owner and is safe to repeat. Base bytes may alias patch storage. Neither operation changes base or patch bytes. Returned output owns independent storage and remains valid after both inputs are released. Use accessors; internal descriptor mutation is outside the API contract.

Empty patch input is an identity patch. Applying it returns an independent exact copy of the base, subject to the same limits. Headers with no hunks are malformed. The library has no filesystem operations, pathname traversal, multiple-file orchestration, offset search, fuzz, automatic reversal, partial application, rejects file generation or metadata application.

## Supported format

The profile follows the [POSIX unified format](https://pubs.opengroup.org/onlinepubs/9799919799/utilities/diff.html), [GNU's unified format description](https://www.gnu.org/software/diffutils/manual/html_node/Detailed-Unified.html), and [GNU incomplete-line convention](https://www.gnu.org/software/diffutils/manual/html_node/Incomplete-Lines.html). Its accepted nonempty document is:

1. One LF-terminated `--- ` header and one LF-terminated `+++ ` header, each with nonempty content. Header content is an opaque label and may contain a TAB-separated timestamp. NUL and CR in headers are rejected.
2. One or more exact `@@ -start[,count] +start[,count] @@\n` hunk headers. An omitted count means one. A zero count uses the position immediately before the empty range; nonempty ranges are one based. Decimal overflow, negative values and nonempty ranges starting at zero are malformed.
3. Hunk lines prefixed by space, minus or plus, with exact declared before/after counts and at least one changed line per hunk.
4. An optional exact `\ No newline at end of file\n` immediately after an incomplete data line. It removes the synthetic LF from that line. A marked line must contain at least one data byte and must be the final line on every side it participates in.

Hunks must be ordered, nonoverlapping, and agree on the count of unaffected lines between old and new positions. The parser rejects trailing content, extra headers, extra files, extra or misplaced markers, unknown preambles, binary patch blocks, Git extended headers and hunk section annotations. Headers are descriptive: `/dev/null` receives no creation or deletion semantics; an empty base is supplied explicitly. All structural records require LF. CR before a data line's LF remains data, so CRLF payload is preserved without stripping.

Payloads are arbitrary bytes, including NUL and invalid UTF-8. A line beginning with a diff control character remains payload after its prefix. The English no-newline marker is deliberately exact; localized alternatives require an explicit future format choice.

## Validation and errors

Apply splits the base into exact byte lines, then visits every hunk and unchanged interval. It compares all deletion and context bytes, checks the old and new line positions and counts, and checks the complete result's line endings and size. Only after this pass succeeds does it allocate and construct the result. A conflict in the final hunk publishes no output from earlier hunks. Unchanged text outside hunk context is retained; this is exact context application rather than a whole-file identity assertion.

`Error { kind, offset }` uses `ErrorKind`: `Bounds`, `InvalidLimits`, `Malformed`, `Unsupported`, `Conflict`, `LineLimit`, `WorkLimit`, `OutputLimit`, `AllocationFailed`. `Unsupported` identifies a non-unified initial header; unsupported content inside a unified document is malformed. During parse, `offset` is a byte offset in patch input. During apply, it is a zero-based base line index where available, with zero for preflight/allocation failures. No error owns storage.

Views must have nonnegative starts/lengths and nonoverflowing logical ranges; malformed view metadata returns `Bounds`. The caller supplies sufficient initialized physical storage and keeps it stable. All failed parses free descriptor storage. Failed applications free the temporary base-line index and any temporary owned state.

## Resource limits

The shared `ext::diff::Limits` type is documented in [extended-diff.md](extended-diff.md). Parse charges each patch input byte against `max_work`; repeated header/data validation uses bounded additional work per scanned byte. It caps each hunk's old/new counts and total hunk count by `max_lines`, and total data-line descriptors by `max_edits`. Apply separately charges base split bytes, hunk visits, line planning, exact comparison probes/bytes and every result byte before allocation. The result's complete line count must fit `max_lines`, and result bytes must fit `max_output`. Identity patches honor these logical result limits.

Parse is linear in patch bytes with owned storage proportional to hunk/data-line count. Apply is linear in base bytes, patch payload touched and output bytes, with storage for base line descriptors and the complete result. Trace limits belong to diff generation and are unused by patch operations. Negative count limits are invalid; zero work and output limits are valid and enforced.

The native library suite checks generated `apply(encode(compare(a,b)),a)==b`, independent minimality, malformed hunks and ranges, late conflicts, Python-formed patches, binary bytes, CRLF, missing final LF, scale and allocation failure cleanup. The `text_patch` CLI suite also checks GNU `diff`/`patch` interoperability when installed.

Verified execution is x86_64 Linux output from the GPU compiler. Other targets
and user GPU kernels have not been verified.
