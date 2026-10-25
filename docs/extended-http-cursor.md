# Incremental HTTP framing

`ext::http::Cursor` finds one HTTP/1 message boundary in a growing byte buffer. It performs no allocation or I/O, retains only scalar state and offsets, and uses the existing strict head and chunk-size parsers. The complete-message APIs retain their existing behavior.

## API and events

```text
cursor(CursorMode::{Request,Response}, Limits, rawcap:i32, maximum_work:u64)
    -> Result<Cursor,Error>
cursor.advance(cumulative_bytes, original_request_method, eof) -> Result<Scan,Error>
cursor.work() -> u64

Scan::NeedMore
Scan::HeadReady(HeadInfo { status, version, kind, content_length, head_end })
Scan::Boundary(FrameBoundary { consumed, decoded_length })
```

Construct a cursor with nonnegative HTTP limits and raw cap. Request mode ignores the method contents (both View arguments still require valid metadata); response mode requires the exact original request method, supplied consistently on every call. As with the existing parser, method matching is case sensitive.

`HeadReady` is emitted exactly once, after strict head validation and before scanning any body bytes, even when the supplied buffer already contains the body. It reports the parser's framing decision. Call `advance` again with the same prefix to scan the body. Fixed, empty, chunked and tunnel messages stop at their exact boundary; bytes after that boundary belong to the caller. A close-delimited response completes only after actual EOF. A timeout, would-block result, capacity exhaustion or host error is not EOF.

`Boundary` is a framing candidate. **Freeze the bytes and call `parse_request` or `parse_response` once before publishing a Message or its contents.** Require the final parser's `consumed` and `decoded_length` to agree with the boundary. The cursor checks trailer syntax and the explicit prohibited-field list; the full parser additionally checks Connection-nominated trailer fields. A candidate does not establish application-level trailer semantics.

A boundary or error is terminal: every subsequent call returns the same boundary or error without examining its arguments or adding work. An incomplete prefix with EOF produces terminal `Error::Incomplete`, unless a resource cap has already been exhausted (`Limit`). EOF is sticky through `HeadReady`; before a terminal event, appending bytes after declaring EOF or shortening the prefix produces terminal `Bounds`. Other failures are also terminal; construct a new cursor for another message.

## Buffer and state rules

Supply a physically backed `core::slice::View<u8>` with valid logical metadata. Every previously supplied logical byte must remain identical. Prefix length may grow and its allocation, logical start or physical stride may change between calls. The cursor does not retain a source View, so it remains valid across buffer growth. Input and method storage must be disjoint from the mutable Cursor storage. Concurrent mutation during a call is unsupported. Metadata checks cannot establish actual backing capacity.

Cursor fields are library maintained: create with `cursor`, advance through its methods, and do not forge or edit fields. Use one active mutable cursor per scan; copying an active record to branch a scan is outside this contract. No destruction is needed. `HeadInfo` and `FrameBoundary` contain scalars and remain independent of the input buffer. Final Head/Message/Field views borrow the frozen wire bytes; response Head.method also borrows the original method bytes. Preserve both lifetimes and immutability.

An informational response is one head-only frame. A transport handling several 1xx responses creates subsequent cursors with the same original method and retains cumulative limits across them. A 101 response or successful CONNECT response is a protocol handoff, not an instruction to parse the following bytes as HTTP. The cursor does not implement connection reuse, pipelining policy, Expect handling or message association.

## Limits and work

`rawcap` bounds bytes consumed for the selected message, including head, chunk framing and trailers. A supplied prefix may include a pipeline tail beyond that cap if a boundary occurs within it. `Limits.body_bytes` bounds decoded content. Existing head, line, header-count, chunk-count and trailer limits also apply. Checked arithmetic rejects oversized lengths with `Limit`; constructor/metadata errors use `Bounds`.

An incomplete phase that requires another byte returns `Limit` at the raw cap. Close-delimited bodies may return `NeedMore` at the exact raw or decoded body cap because EOF consumes no bytes. A transport can use a separate **positive-capacity one-byte EOF probe**: zero means actual EOF; a byte exceeding the applicable cap is a limit error. Never infer EOF from a zero-capacity receive.

`work()` counts abstract scan units: each line/framing/payload byte advanced, plus one additional unit per head byte and response method byte submitted to head validation, and one per chunk-size or nonempty trailer-line byte submitted to its grammar parser. Grammar helpers have a bounded number of passes over those bytes. The counter charges no per-call overhead, is invariant under partitioning valid input into fragments, and does not grow on repeated unchanged incomplete input. Every charge is checked against `maximum_work` before its corresponding work. Exhaustion is terminal `Limit`, with the used counter never exceeding the maximum. Failed span charges can leave different used totals and error offsets under different partitions; those failure details are not partition invariant.

The incremental scan therefore makes linear progress in the selected raw message size plus the original method size, including one-byte delivery of long chunk extensions. It does not repeatedly parse the entire growing prefix. This work budget covers the cursor only. Reserve a separate budget for final canonical parsing and decoding; the existing strict parser's Connection-nominated trailer check can scan the head for each trailer. Transport code must also bound buffering, informational responses, I/O attempts and its own copying. Compact a pipeline buffer in batches to avoid quadratic tail copying.

## Evidence

Focused native fixtures exercise every split and one-byte fragments, relocated counted/strided views, all framing kinds, exact caps and EOF, fused outcomes, malformed chunk grammar, strict-parser differential boundaries, and a large fragmented chunk/extension workload with equal work across partitions. The Rust gate traces the allocation-free contract fixture and checks that no mapping or I/O service is used.

Run `cargo test --test extended_http_cursor_execution -- --test-threads=1` on Linux x86_64. Both focused native tests pass. The scale fixture frames 57,923 wire bytes into 512 binary payload bytes using 113,283 charged units under all three partitions. Its two caller-owned buffers are released with exact mapping lengths; the small contract fixture makes no allocations.

Framing precedence and chunk syntax follow [RFC 9112 sections 6.3 and 7.1](https://www.rfc-editor.org/rfc/rfc9112.html#section-6.3), through the existing strict parser.
