# Owned URI resolution

`ext::uri_resolve` resolves a borrowed URI reference against an absolute base
and returns independently owned packed bytes. It also recomposes a parsed
reference into owned storage. The implementation is Lanius, built on
[`ext::uri`](extended-uri.md) and `alloc::vec`.

The selected algorithm is strict
[RFC 3986 sections 5.2–5.3](https://www.rfc-editor.org/rfc/rfc3986.html#section-5.2).
Only literal path dot segments are removed during resolution. Scheme and host
case, percent escapes, empty components and repeated slashes remain encoded
as supplied. Query and fragment contents are never treated as path segments.

Executable evidence covers **x86_64 Linux using the GPU compiler**. Other hosts
and GPU-kernel execution have not been established.

## API

```text
resolve(base: ext::uri::Reference,
        reference: ext::uri::Reference,
        max_bytes: i32) -> Result<alloc::vec::Vec<u8>, Error>

recompose(reference: ext::uri::Reference,
          max_bytes: i32) -> Result<alloc::vec::Vec<u8>, Error>

Error = InvalidBase | Bounds | OutputLimit | CapacityOverflow | AllocationFailed
```

`resolve` requires a base with a scheme and **no fragment**, including no empty
fragment delimiter. A relative base or a base containing `#` returns
`InvalidBase`, even if the reference already has its own scheme. The caller
must establish and strip any fragment from a base before parsing it for this
API. No base discovery or scheme guessing occurs.

A reference with a scheme supplies its own target scheme; the resolver does
not reinterpret a matching scheme as relative. Thus resolving `http:g` against
`http://a/b/c/d;p?q` produces `http:g`.

`recompose` copies scheme, authority, path, query and fragment with each present
delimiter. It performs no dot removal. For valid parsed inputs, its result is
byte-for-byte identical to the input. The operation uses the component fields,
including `Authority.raw`; it does not copy `Reference.raw` directly.

Each successful result has one owner. Use `as_view()` for borrowed bytes and
call `destroy()` once when finished. Copies of a `Vec` alias ownership. The
result remains independent of its inputs after their storage changes or is
released. Neither operation mutates input bytes or takes input ownership.

## Resolution behavior

An authority in the reference replaces the base authority. An empty reference
path inherits the base path unchanged; an absent query then inherits the base
query, while a present empty query replaces it. Other relative paths merge with
the base path's directory prefix. A base authority with an empty path supplies
the leading slash needed for that merge. The reference alone supplies the
fragment.

Only complete literal `.` and `..` path segments participate in dot removal.
`%2e`, `%2E`, `%2f`, `%2F`, `.g` and `g..` retain their spelling. Removing a final
dot segment preserves the resulting trailing slash. A borrowed base need not
have been normalized: when its path is inherited unchanged, its dot segments
remain unchanged too.

For example, using `http://a/b/c/d;p?q` as the base:

| Reference | Result |
| --- | --- |
| `../g` | `http://a/b/g` |
| `../../../../g` | `http://a/g` |
| `?` | `http://a/b/c/d;p?` |
| `#` | `http://a/b/c/d;p?q#` |
| `g?y/../x` | `http://a/b/c/g?y/../x` |
| `%2e/%2F` | `http://a/b/c/%2e/%2F` |

The routine follows the RFC's literal recomposition rules. With no selected
authority, dot removal can expose two leading path slashes: base `x:/` and
reference `.//a` produce `x://a`. Parsing that result yields an authority.
The resolver adds no protective `/.` prefix. Applications needing an authority
or origin restriction must check the resolved result against that policy.

## Limits, storage and failures

`max_bytes` limits the **final encoded output**. An exact fit succeeds. A long
merged path may normalize to a short result that fits a small limit.

Resolution uses one temporary packed path and one final packed result. It
reserves their storage before writing, then compacts dot segments in place.
The temporary capacity is bounded by the selected base directory prefix plus
reference path, with at most one inserted slash. Recomposition needs only the
final result allocation; an empty result needs none. Empty-path inheritance
does not allocate a temporary path.

Time is O(base bytes + reference bytes + output bytes), with no recursive
backtracking. Each input path byte is consumed once during compaction; backward
scans only visit output bytes being removed. Temporary storage may exceed
`max_bytes`, since that limit concerns the final result. It remains bounded by
the checked merged-input length.

| Error | Contract |
| --- | --- |
| `InvalidBase` | Base lacks a scheme or has a fragment |
| `Bounds` | Negative output limit or invalid logical component metadata |
| `OutputLimit` | Final encoded result exceeds `max_bytes` |
| `CapacityOverflow` | A checked merged-path or complete-output size exceeds `i32` |
| `AllocationFailed` | An allocator request fails |

A negative limit is checked first. Resolution then checks its base contract
and the logical bounds of both inputs' used component views. Recomposition
checks logical bounds and its complete size before allocating. Resolution may
need path storage to determine its final size, so allocation failure may precede
an eventual output-limit failure. Every failure releases internal temporary
storage and leaves the caller's sources and prior results unchanged.

Inputs must still satisfy the parser's syntax, component-boundary and backing
storage contracts. The used views are scheme, authority raw bytes, path, query
and fragment; the raw reference and authority's split host/userinfo/port fields
are not consumed. Logical checks do not recover the physical backing length or
revalidate forged component fields. Keep all source backing storage live and
unchanged until the call returns. Lanius does not enforce these lifetimes.

## Executable evidence

`tests/extended_uri_resolve_execution.rs` checks:

- Every normal and abnormal strict resolution example from RFC section 5.4.
- More than 12,000 generated resolution and exact recomposition comparisons
  against a separate implementation using the specification's two buffers.
- Empty components, percent opacity, repeated slashes, bases without authority,
  inherited unnormalized paths and literal no-authority recomposition.
- Exact output limits, independent owned results, native strided inputs,
  logical bounds and size preflight overflow.
- Each observed allocation denied in turn, with no leaked partial owners and
  preserved source/prior-result contents.
- 1,024, 16,384 and 262,144 cancelling path groups. The largest input exceeds
  1 MiB yet resolves to 14 bytes, using three allocations including caller
  setup and with all further allocation requests denied.

The production module has no host, Rust, Python or percent-codec dependency.
The real `uri-resolve` application is documented in
[URI resolution program](extended-uri-resolve-program.md).

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_uri_resolve_execution -- --nocapture
```
