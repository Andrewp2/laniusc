# Validate a JSON document from stdin

`sample_programs/library/json_check.lani` integrates `ext::schema`, `ext::json`,
raw-byte file paths, CLI arguments and native streams. Four focused acceptance
test groups compile and execute the program on x86_64 Linux.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc --emit x86_64 \
  --stdlib-root stdlib --source-root extended \
  -o target/stdlib-work/json-check sample_programs/library/json_check.lani
timeout --kill-after=2s 100s target/stdlib-work/json-check \
  application.schema.json < application.json
```

Success is quiet. Exit 0 means the complete JSON document satisfies the schema.
Exit 1 means a well-formed instance violates a supported schema constraint.
Exit 2 means invalid arguments, malformed UTF-8/JSON, an invalid or unsupported
schema, or an exhausted resource bound. Exit 3 reports host I/O failure; exit 4
reports allocation failure. Every failure attempts one stderr diagnostic;
failure while writing that diagnostic also exits 3. `--help`/`-h` prints usage
to stdout after checking argument syntax.

## Schema and instance behavior

The schema file and stdin must contain UTF-8 JSON. Raw NUL is not JSON syntax;
an escaped `\u0000` inside a string is a valid scalar. Unicode strings retain
their decoded scalar meaning rather than using their UTF-8 byte count for
schema string-length constraints.

Duplicate decoded keys are rejected anywhere in either document, including
equivalent spellings such as `"a"` and `"\u0061"`. A schema is fully parsed and
compiled before stdin is read. Malformed unused definitions and unsupported
keywords therefore fail even when the selected instance would not reach them.
Local references and the engine's supported constraints are handled by
`ext::schema`; external schema retrieval is not performed.

Constraint diagnostics include the keyword and schema/instance node identifiers,
for example:

```text
json-check: schema-violation stage=validation keyword=minimum schema-node=8 instance-node=3
```

Node identifiers refer to the parsed documents, not source byte offsets or JSON
Pointers. JSON syntax and UTF-8 errors report a byte offset where available.
Only the first schema violation is reported. Operational errors such as work
exhaustion remain exit 2; they do not become an invalid-instance result.
Diagnostics preserve the innermost failing assertion, so an extra property
rejected by `additionalProperties: false` reports `keyword=false` at that boolean
schema. A failure evaluating a property name adds `property-name=true`.

Numbers are validated through the schema engine's exact decimal operations.
The application does not convert them to floating point. Bounds can distinguish
values such as `123456789012345678901234567890.00001` and
`123456789012345678901234567890.000009`.

## Resource bounds

| Option | Default | Accepted range |
| --- | --- | --- |
| `--max-schema-bytes N` | 1048576 | 0–67108864 |
| `--max-input-bytes N` | 16777216 | 0–67108864 |
| `--max-depth N` | 128 | 0–128 |
| `--max-nodes N` | 100000 | 0–1000000 |
| `--max-work N` | 10000000 | 0–1000000000 |
| `--max-scratch-bytes N` | 8388608 | 0–67108864 |

Values use unsigned decimal; the last occurrence of an option wins. Exactly one
schema path is required. Use `--` before a path beginning with a hyphen. The
argument snapshot is limited to 32 arguments and 8192 bytes.

The byte bounds apply separately to schema and instance input. The node bound
applies to each parsed document and the compiled schema. The depth bound feeds
the JSON parser and the schema engine's schema/validation depth limits. Work is
bounded for schema compilation and for instance validation. The scratch bound
is checked against the compiled schema's required byte count before reading
stdin. Syntax depth and parser node limits remain in force even for a schema
that would otherwise accept every instance. JSON number tokens are limited to
1048576 bytes; parsed strings remain within the 67108864-byte input cap.

Readers may consume one 1024-byte chunk beyond a byte limit to detect excess
input. Both documents are buffered and parsed into owned JSON trees; this is
bounded document validation, not streaming schema evaluation. Buffer, text,
document, plan and scratch allocations are distinct and all have explicit
cleanup.

## Files, ownership and supported target

File paths are raw Unix bytes, including non-UTF-8 names. The native file binding
limits them to 4095 bytes, follows symlinks and closes the acquired schema handle
on every exit path. Reads retry interruptions. Open and close each make one
host attempt; a read failure takes priority over a simultaneous close failure.
No path bytes are printed in diagnostics.

The compiled schema borrows its schema document. The application keeps that
owner alive and unchanged until after `Schema.destroy()`. Validation completes
before the instance document is destroyed. Input buffers and copied source text
are destroyed after parsing; returned diagnostic data contains values and static
keyword names rather than dangling document views.

The supported executable target is x86_64 Linux through the GPU compiler's native
output. GPU kernel execution has not been verified. Production behavior is
implemented in Lanius.

## Focused acceptance tests

`tests/extended_json_check_execution.rs` checks a configuration schema combining
object properties, required names, local references, enum values, integer bounds,
arrays and Unicode strings. It covers exact large decimals, malformed and
unsupported schema, invalid instances, duplicate keys, exact byte limits,
depth/work/scratch limits, a binary file name and a 5000-item document. Where
installed, Python `jsonschema` supplies an independent test oracle.

Fault tests use a schema with `multipleOf` to include allocated decimal scratch,
deny every observed allocation and each schema/instance read in turn, inject
open/close/write failures, and check that all heap owners are freed
and every acquired schema descriptor receives one close attempt. An injected
close error follows the native API's rule to invalidate the owner without
retrying its descriptor. Rust and Python are test drivers and references only.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR=/home/andrew-peterson/code/laniusc/target/stdlib-build \
  CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_json_check_execution
```
