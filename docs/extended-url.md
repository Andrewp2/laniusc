# WHATWG URLs

`ext::url` parses URLs the way browsers and `new URL(input, base)` do, following
the [WHATWG URL Standard](https://url.spec.whatwg.org/) basic URL parser. It
then serializes the result. Unlike [`ext::uri`](extended-uri.md), which is
strict RFC 3986 syntax over borrowed views, this module:

- normalizes the input
- resolves it against an optional base
- percent-encodes as the standard requires
- returns an owned href with a span for every component

Execution is verified on **Linux x86_64 CPU output from the GPU compiler**.

```lanius
let base = ext::url::parse(base_text).unwrap();
let url = ext::url::parse_with_base(input, base.borrow()).unwrap();
// url.href(), url.hostname(), url.port_or_default(), url.pathname(), url.query() ...
url.destroy(); base.destroy();
```

## What is implemented

The whole basic URL parser state machine is implemented, with no state
override. That covers:

- **Preprocessing.** Leading and trailing C0 control or space bytes are
  stripped, and tab, LF and CR are removed everywhere.
- **Schemes.** Scheme case is folded. The special schemes are http, https, ws,
  wss, ftp and file. In special URLs, `\` counts as `/`.
- **Relative references.** Every relative form resolves against a base:
  scheme-relative, path-absolute, path-relative, query-only and fragment-only.
  This includes bases with an opaque path, where only `#fragment` is allowed.
- **Paths.** Dot segments are removed, including the `%2e` spellings.
  Windows drive letters in file URLs are normalized (`C|` becomes `C:`), and a
  drive letter is never popped. `file://localhost` gets an empty host.
- **Credentials and ports.** Username and password are split at the first `:`.
  An `@` inside the userinfo is encoded. A port above 65535 fails, and a
  scheme's default port is dropped.
- **Hosts.**
  - Special hosts are percent-decoded, ASCII-lowercased and checked for
    forbidden domain code points.
  - A host ending in a number goes to the IPv4 parser, which accepts decimal,
    octal, `0x` hex and one to four parts.
  - Bracketed IPv6 is parsed and serialized in compressed form, including an
    embedded dotted IPv4.
  - Hosts of non-special URLs stay opaque, with C0 percent-encoding.
- **Percent-encoding.** Each component uses its own encode set: fragment,
  query, special-query, path, userinfo and C0. Non-ASCII bytes are encoded as
  their UTF-8 bytes.
- **Opaque paths.** Opaque paths (`mailto:`, `data:`, `javascript:`) keep
  their spaces; a space directly before `?` or `#` becomes `%20`.
- **Serialization.** A path that would otherwise look like an authority gets
  the `/.` prefix (`web+demo:/.//x`).
- **Origins.** `origin()` returns the ASCII origin. For `blob:` URLs it is the
  inner http(s) URL's origin.

## Not implemented: IDNA

This module does not implement UTS #46 mapping or Punycode. A special host
that contains a non-ASCII code point after percent-decoding fails with
`UnsupportedIdna`, and so does any label beginning with `xn--`. ASCII
hostnames are complete: lowercasing and the forbidden code point check are
all UTS #46 does to them. The parser does not guess. In particular, no host
silently comes out different from the one a browser would produce.

Non-ASCII text elsewhere in a URL is fully supported: in the path, query,
fragment, userinfo and opaque hosts.

## Input

The input is UTF-8 bytes. Invalid UTF-8 fails with `InvalidUtf8`: overlong
forms, surrogates, values past U+10FFFF and truncated sequences. A JavaScript
string cannot carry invalid UTF-8, so no browser behaviour is copied here.

Inputs longer than `MAX_INPUT_BYTES` (16 MiB) fail with `TooLong`, and an
invalid view fails with `Bounds`. Parsing allocates. Failed allocation returns
`AllocationFailed` and frees everything the parse allocated.

## API

| Item | Meaning |
| --- | --- |
| `parse(input)` / `parse_with_base(input, &base)` | A `Url` or an `Error`. The base is any URL that was parsed earlier. |
| `can_parse(input)` | Whether `parse` succeeds. |
| `href()`, `href_without_fragment()` | The serialization, with or without `#fragment`. |
| `scheme()`, `protocol()` | The scheme without `:`, and with it. |
| `username()`, `password()` | Encoded userinfo. Both are empty when absent. |
| `hostname()`, `host()`, `host_kind()` | The serialized host (IPv6 keeps its brackets); `host()` adds `:port`. `HostKind` is `None`, `Empty`, `Domain`, `Ipv4`, `Ipv6` or `Opaque`. |
| `port()`, `port_number()`, `port_or_default()` | The port text, the explicit port (-1 when absent or default), and that port or the scheme's default. |
| `pathname()`, `has_opaque_path()` | The serialized path, without the `/.` prefix. |
| `query()`, `fragment()` | `None` for a null component. `Some(empty)` for `?` or `#` with nothing after it. |
| `search()`, `hash()` | The JavaScript getters: `?query` or `#fragment`, and empty for both null and empty. |
| `origin()` | An owned ASCII origin, or `null`. |
| `is_special()`, `default_port(scheme)` | Special-scheme helpers. |
| `try_clone()`, `destroy()` | A `Url` owns its href. Destroy it exactly once. |

Error meanings:

- `MissingScheme`: relative input without a usable base.
- `MissingHost`: an empty special host, or credentials with no host after them.
- `InvalidHost`, `InvalidPort`, `InvalidIpv4`, `InvalidIpv6`: the named
  component is invalid.
- `UnsupportedIdna`: see above.

Validation errors that the standard does not treat as failures are not
reported.

## Application: url-parse

[`url_parse.lani`](../sample_programs/library/url_parse.lani) has two modes.

- `url-parse URL [BASE]` prints one `name<TAB>value` line for each of:
  href, protocol, username, password, host, hostname, port, pathname, search,
  hash, origin and host kind.
- `url-parse --batch` reads lines of the form `INPUT` or `INPUT<TAB>BASE`. It
  decodes the escapes `\t`, `\n`, `\r`, `\\` and `\xHH`, so any input can be
  given, including control characters. It prints one tab-separated row per
  line: `ok` with the eleven getters, `fail<TAB>error` or
  `base-fail<TAB>error`.

Exit codes:

| Code | Single URL | Batch |
| --- | --- | --- |
| 0 | Success | Success |
| 1 | Parse failure | — |
| 2 | Usage error | Bad escape |
| 3 | — | I/O failure |

## Verification

[`tests/fixtures/extended_url/oracle.py`](../tests/fixtures/extended_url/oracle.py)
is an independent differential oracle. It checks `url-parse` against
`whatwg.js`, which is Node.js's WHATWG `URL` (checked with v24.21.0).

The **whatwg group** builds a fixed corpus of 4,828 distinct cases:

- 164 hand-picked edge cases
- 2,600 seeded random absolute URLs
- 1,600 random relative references against 23 bases
- the full grid of 53 relative references × 23 bases

The random URLs combine:

- 21 schemes and 10 separators
- credentials
- 76 hosts: IPv4 forms, IPv6 compression and failures, percent escapes,
  forbidden code points, and IDNA inputs
- 14 ports
- 34 paths: dot segments, drive letters, backslashes and non-ASCII
- queries and fragments
- injected tabs, newlines and C0 controls

For each case it requires one of two results:

- Both sides fail.
- Both sides succeed, with the same href, all ten other getters and the origin.

It then parses every href Node produced a second time, on both sides.

Cases containing non-ASCII or `xn--` are tagged. In those cases an
`unsupported-idna` failure is accepted in place of Node's result: about 50
cases where Node succeeds, and about 40 where it fails. Untagged cases must
match exactly. The group runs in about 2 seconds.

The **cli group** checks:

- the single-URL output format and host kinds
- every error name and exit code
- base failures
- invalid UTF-8 (lone continuation bytes, surrogates, values past U+10FFFF,
  overlong forms)
- batch escapes and the bad-escape stop

[`contracts.lani`](../tests/fixtures/extended_url/contracts.lani) checks the
API directly:

- null versus empty query and fragment
- the port helpers and default ports
- host kinds, opaque paths and origins
- reuse of a cloned base
- span partitioning
- `Bounds`, `TooLong` and the other error variants

Receipts are from direct runs on native Linux x86_64:

- the contracts program exits 0
- `oracle.py whatwg` reports `url-whatwg cases=9174`
- `oracle.py cli` reports `url-cli cases=25`

[`tests/extended_url_execution.rs`](../tests/extended_url_execution.rs) wraps
the same three checks. It skips the whatwg group when Node is not installed.
