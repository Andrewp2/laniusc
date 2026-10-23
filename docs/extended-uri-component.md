# Extracting URI components

[`sample_programs/library/uri_component.lani`](../sample_programs/library/uri_component.lani)
is a native command-line program that combines borrowed URI parsing, percent
decoding, CLI parsing, owned arguments, a byte vector and checked output streams.
It extracts one component from one URI reference without network access.

```text
uri-component [--decode] [--] FIELD URI
```

`FIELD` is one of `scheme`, `authority`, `userinfo`, `host`, `port`, `path`,
`query` or `fragment`. Relative references and the empty reference are accepted
by the [generic URI parser](extended-uri.md). Output preserves the selected
component's encoded spelling, case and dot segments. Delimiters identifying
scheme, authority, port, query and fragment are excluded; the authority field
contains its complete userinfo/host/port spelling, and bracketed hosts include
their brackets.

`--decode` / `-d` applies [percent decoding](extended-percent.md) once after
selecting the component. It leaves `+` unchanged. Decoded output can contain
NUL, invalid UTF-8 or separator bytes. The program writes raw bytes without an
added newline or terminator and does not interpret them as another URI or a
filesystem path. `%252F` becomes `%2F`, not `/`.

The empty component and an absent component both produce no bytes, with distinct
exit statuses. For example, `query '/path?'` succeeds with empty output;
`query '/path'` returns status 1. Path is always present, including for the
empty reference. Empty authority, userinfo, host and port follow the parser's
generic syntax rather than a particular network protocol's policy.

| Exit | Meaning |
| --- | --- |
| 0 | Component present, including empty; or successful help output |
| 1 | Selected component absent |
| 2 | Invalid arguments, invalid URI reference or exceeded input limits |
| 3 | Output I/O failure |
| 4 | Allocation failure |

The program validates arguments and the complete URI before output starts.
Decode storage is sized and allocated before writing decoded output. A later
output error can leave a written prefix. Writes retry EINTR; EAGAIN and
zero-progress writes fail. Argument and decode owners are explicitly released
on success and failure.

Argument snapshots allow at most 16 arguments and 65,536 total argument bytes.
The parser's separate default limit is 1,048,576 bytes; the application argument
limit is lower. Options may appear between operands; `--` allows a URI beginning
with a dash. `--help` / `-h` validates CLI syntax and prints usage without
requiring the operands. Unknown options and extra operands are errors.

## Example

Compile from the repository root using the existing compiler binary:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/uri_component.lani -o /tmp/uri-component

timeout --kill-after=2s 10s /tmp/uri-component --decode path \
  'https://example.com/a%20b/%2F?name=x+y' > /tmp/uri-path
od -An -tc /tmp/uri-path
```

The output is exactly `/a b//`. Extracting the query without decoding produces
`name=x+y`. Extracting and decoding the fragment of `#%00%FF` produces the two
bytes `0` and `255`.

## Executable evidence

[`tests/extended_uri_component_execution.rs`](../tests/extended_uri_component_execution.rs)
compiles and runs the Lanius application on **x86_64 Linux**. Three groups passed
in 6.55 seconds:

- Encoded and decoded fields, absent and empty components, IPv6/IPvFuture hosts,
  retained case and dot segments, plus handling, one-pass decoding and every
  possible decoded byte.
- Argument limits, strict syntax and raw non-ASCII rejection before output,
  dash-prefixed references and exact help output.
- Each observed allocation and output syscall failing in turn; complete owner
  cleanup, output-prefix behavior, EINTR retry, EAGAIN and zero-progress writes.

The tests use Rust as a compiler/test harness, and `strace` for fault injection.
The application and libraries are implemented in Lanius. GPU-kernel execution
and other operating systems have not been verified.

An added boundary run passed in 5.67 seconds. It checks multiple descriptor-sized
writes, raw paths up to the exact 65,536-byte argument snapshot limit (including
the field name), and decoded output at that same total argument limit.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_uri_component_execution -- --nocapture
```

## Native performance sample

On 2026-10-23, one warmup and five measured processes per workload ran on CPU 0.
Elapsed times include argument snapshots, parsing, output to `/dev/null`, owner
cleanup and process startup. Decode inputs contain repeated `%41` triplets
followed by any remaining literal `a` bytes.

| Operation | URI bytes | Median | Measured range |
| --- | --- | --- | --- |
| Extract encoded path | 4,096 | 4.571 ms | 4.209–5.428 ms |
| Extract encoded path | 65,532 | 47.985 ms | 43.271–50.505 ms |
| Extract and decode path | 4,096 | 4.448 ms | 3.801–4.593 ms |
| Extract and decode path | 65,530 | 41.698 ms | 41.394–44.873 ms |

These are native application measurements at the stated sizes. They do not
measure GPU compiler speed or compare against another compiler or URI library.
