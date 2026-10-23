# Borrowed URI references

`ext::uri` validates one complete URI reference and returns borrowed views of
its encoded components. The implementation is Lanius and uses constant local
storage. Parsing neither allocates nor changes the input.

The grammar is [RFC 3986 sections 3–4 and Appendix A](https://www.rfc-editor.org/rfc/rfc3986.html#appendix-A),
including empty and relative references, authority subcomponents, IPv4, IPv6
and IPvFuture literals. The verified errata
[2525](https://www.rfc-editor.org/errata/eid2525) and
[7590](https://www.rfc-editor.org/errata/eid7590) do not change this grammar.

Executable evidence covers **x86_64 Linux using the GPU compiler**. Other hosts
and GPU-kernel execution have not been established.

## Entry points

```text
parse(bytes: View<u8>) -> Result<Reference, Error>
parse_with_limit(bytes: View<u8>, max_bytes: i32) -> Result<Reference, Error>
DEFAULT_MAX_BYTES: i32 = 1048576
```

The limit counts encoded input bytes. An input exactly at the limit is valid
if its syntax is valid. A caller may choose a larger nonnegative limit.
Parsing takes O(n) time and O(1) additional storage.

`Reference` exposes:

| Field | Type | Contents |
| --- | --- | --- |
| `raw` | `View<u8>` | The complete selected input |
| `scheme` | `Option<View<u8>>` | Scheme, excluding `:` |
| `authority` | `Option<Authority>` | Present after the authority introducer |
| `path` | `View<u8>` | Path; always present, possibly empty |
| `query` | `Option<View<u8>>` | Query, excluding `?` |
| `fragment` | `Option<View<u8>>` | Fragment, excluding `#` |

`Reference.as_bytes()` returns `raw`. `Reference.is_relative()` reports whether
the scheme is absent.

`Authority` exposes:

| Field | Type | Contents |
| --- | --- | --- |
| `raw` | `View<u8>` | Authority, excluding `//` |
| `userinfo` | `Option<View<u8>>` | User information, excluding `@` |
| `host` | `View<u8>` | Host; includes brackets around IP literals |
| `port` | `Option<View<u8>>` | Decimal spelling, excluding `:` |
| `kind` | `HostKind` | `RegName`, `Ipv4`, `Ipv6` or `IpvFuture` |

Absent components are `None`; present empty components are `Some(empty)`.
For example, `//@:?#` contains an empty authority userinfo, host, port, query
and fragment, while its path is empty. An empty input has only an empty path.

## Exact syntax and spelling

Only the URI ASCII alphabet is accepted. Percent escapes need exactly two
hexadecimal digits. Encoded bytes remain encoded, including `%00`, `%2F` and
`%FF`; an encoded delimiter does not split a component. A scheme starts with
an ASCII letter. A relative reference's first path segment cannot contain a
literal colon. Query and fragment admit literal `/` and `?`.

Bracketed IPv6 accepts one compression marker and optional strict IPv4 tail.
IPvFuture accepts either case of its version prefix. Zone identifiers are
outside this RFC grammar. An unbracketed host matching strict IPv4 syntax gets
`Ipv4`; other valid registered names get `RegName`.

The returned views preserve the input exactly: scheme and host case, percent
escape case, repeated slashes, dot segments, leading zeroes in a port and an
empty port all survive. Ports remain strings; their size and numeric value do
not imply a usable network port. For example, `//01.2.3.4` is a registered name,
and `//host:99999999999999999999` is syntactically accepted.

This parser supplies syntax and component boundaries. Scheme policy, DNS and
IDNA rules, decoded text validation, WHATWG URL processing, relative resolution,
normalization and network operations belong to their respective layers.

## Errors and bounds

| Error | Meaning |
| --- | --- |
| `Bounds` | Negative logical start/length/limit, or overflowing logical end |
| `LengthLimit` | Encoded input exceeds the caller's limit |
| `InvalidByte(i32)` | Invalid raw byte or byte forbidden in its component |
| `InvalidPercent(i32)` | Incomplete or nonhex escape, pointing at `%` |
| `InvalidScheme(i32)` | Invalid scheme start or first invalid scheme byte |
| `InvalidAuthority(i32)` | A second `@`, or unexpected text after a bracketed host |
| `InvalidHost(i32)` | Invalid bracketed IP literal, pointing at its opening bracket |
| `InvalidPort(i32)` | First nondecimal byte in a port |

Every indexed error uses a zero-based logical offset relative to the selected
input view, even when that view begins partway through its backing slice.
Bounds and length limits are checked first. A complete lexical pass checks
ASCII and percent syntax before component structure; the reported error is
therefore not guaranteed to be the earliest structural fault in a multiply
malformed input. Parsing never returns partially valid components on error.

As with `core::slice::View`, callers must provide actual backing elements for
the claimed logical range. The current language cannot check the physical
slice length here. Packed storage and native strided arrays both work.

Views alias the caller's storage. Keep it alive and unchanged while using a
parsed reference. Copies do not create ownership, and there is nothing to
destroy. The compiler does not enforce these lifetime or read-only rules;
changing the backing bytes can invalidate the parse while leaving old component
boundaries in place.

## Executable evidence

`tests/extended_uri_execution.rs` drives Lanius executables for:

- RFC URI examples and relative-reference forms, plus constructed components
  whose exact returned ranges are checked against their concatenation model.
- Every possible percent-encoded byte retained in all opaque components.
- IPv6 spellings compared with Rust's native address parser, IPvFuture grammar
  cases and strict IPv4 classification with registered-name fallback.
- Malformed syntax, exact error offsets, excluded raw bytes, logical bounds,
  empty versus absent components and aliased native arrays.
- The 1 MiB default boundary and an explicit larger limit. Allocation failure
  injection after caller setup confirms that large parses request no storage.

Rust supplies test orchestration and address references only. The production
module imports `core` and has no host services or codec dependency.

Run the focused gate with the repository's existing build target:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_uri_execution -- --nocapture
```
