# TOML normalization program

`sample_programs/library/toml_normalize.lani` reads TOML **1.1.0** from stdin,
validates it, and writes deterministic TOML preserving the document's types and
values. `--check` performs validation with quiet success. It uses the real
[Lanius TOML parser/encoder](extended-toml.md), without a host parser or JSON
conversion.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/toml_normalize.lani -o target/stdlib-work/toml-normalize
printf 'name = "example"\n[server]\nport = 8080\n' | \
  timeout 10s target/stdlib-work/toml-normalize
```

## Output semantics

Each root member is emitted as a quoted key, `=`, an inline value and LF.
Tables become inline tables, including tables inside arrays. Key and array
order are retained; comments, indentation, quote choices and original number
spelling are discarded. Integers emit in decimal; floats use shortest binary64
round trips with a decimal marker when necessary to preserve floating type.
Negative zero, infinity and NaN signs are retained. TOML NaN has no payload
syntax. Local dates/times remain local, and unknown offset `-00:00` remains
distinct from known UTC. Temporal spellings use canonical `T`/`Z`, include
seconds and trim redundant fractional zeros without rounding away information.
Reprocessing output produces identical bytes.

Input is valid UTF-8. Escaped NUL is a valid string character and is re-escaped
in output; literal NUL in the TOML syntax is invalid. The program supports
TOML 1.1 escape additions, optional seconds, multiline inline tables and their
trailing commas. It appends no extra blank line. An empty document emits no bytes.

## Options and bounds

| Option | Default | Meaning |
| --- | --- | --- |
| `--check` | off | Parse/validate; do not encode or write stdout. |
| `--max-input-bytes N` | 16,777,216 | Whole stdin bound. |
| `--max-output-bytes N` | 67,108,864 | Canonical output bound, checked before stdout. |
| `--max-nodes N` | 1,000,000 | Root, intermediate tables, arrays and values. |
| `--max-depth N` | 128 | Document nesting depth. |
| `--max-string-bytes N` | 16,777,216 | Per decoded key/string/temporal spelling. |
| `--max-number-bytes N` | 1,024 | Numeric source spelling length. |
| `--max-work N` | 1,000,000,000 | Each parser or encoder operation's budget. |
| `--help`, `-h` | off | Usage without reading stdin. |

There are no operands. Values are unsigned decimal digits. Byte/string/number
bounds are capped at 67,108,864, node count at 1,000,000 and depth at 4,096.
Work accepts the full `u64` range. This allows a caller to raise the conservative
floating conversion budget for large numerical configurations. Each finite
float currently reserves one million work units for parsing and one million
for shortest formatting, besides lexical work. The decimal converter has a
768-mantissa-digit ceiling; exceeding it is an explicit number-limit error even
if the byte option is larger. See the engine guide for precise accounting and
native integer/float range policies.

Parser, output measurement and atomic encoding each receive their own work
budget; the option is not a cumulative process budget. The program reserves
measured output storage before initializing it. Input, indexed-document and
output owners can coexist; individual limits are not a total memory quota.
Atomic encoding also creates a temporary provider-owned output string alongside
the application's measured byte vector before copying the completed result.
Argument capture allows at most 32 tokens and 8,192 raw bytes.

`--check` does not measure/encode, so an output limit of zero still allows a
nonempty valid document. Encoding resource errors happen before any stdout.
Host write errors can leave a prefix. All owners are released on returned
errors. Short writes advance, interruptions retry, and zero writes fail.

## Status and diagnostics

| Exit | Meaning |
| --- | --- |
| 0 | Valid document successfully written, quiet validation success, or help. |
| 2 | Invalid arguments, malformed UTF-8/TOML, value range or resource error. |
| 3 | Host I/O error, including failure to write a diagnostic. |
| 4 | Allocation failure. |

Errors attempt a stderr diagnostic with stage, TOML error kind where applicable,
and input byte offset where available. No malformed input is replaced or
silently truncated. `--help` does not suppress invalid arguments elsewhere.

## Executable evidence

`tests/extended_toml_normalize_execution.rs` covers real nested configuration,
all value types, TOML 1.1 additions, canonical byte idempotence, independent Python
`tomllib` comparison for shared 1.0 syntax, exact/failed limits, invalid arguments,
UTF-8 read boundaries and returned diagnostics. Every observed allocation is
denied in turn; read/write errors, short/zero/interrupted writes, failed stderr,
`/dev/full` and late malformed input leave no traced mappings live.

A 1,200-worker configuration contains 100,299 input bytes and emits 100,315
canonical bytes. An observed native run took 233 ms including process/file
setup and I/O, excluding compilation. The typed and idempotent result was
checked; this is not a performance comparison with a host parser.

Verified target: native **x86_64 Linux**, emitted by GPU compilation. No other
native target or user-program GPU execution is claimed.
