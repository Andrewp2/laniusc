# Typed settings

`ext::settings` composes the existing `ext::config` JSON owners, `ext::toml`
owners, and explicit environment/argument bindings through one borrowed typed
API. It allocates no tree and never serializes one format into another.
`ext::settings_env` provides an owned snapshot for an explicit environment
allowlist. The offline `settings_inspect` application demonstrates both modules.

## Ownership and precedence

A `Source` is `Json(config)`, `Toml(document)`, or `Bindings(View<Binding>)`.
These are **borrows**, including the shallow copies of native owner handles in
those variants. Keep all owners, binding arrays, keys, text, and source ordering
alive and unchanged while layers, values, or iterators exist. Destroy each
original owner once after the views expire. The facade has no `destroy` method.
Do not mutate native documents through another alias during this period.

Call `layers(sources, limits, work.borrow())` to validate a source set. Later
sources replace **whole top-level values**, matching `ext::config`. Missing keys
fall back; JSON null masks earlier values. Tables and arrays replace complete
subtrees. `lookup(["server", "port"], work)` selects the winning `server` first
and then descends inside it. A missing child stays missing; it cannot revive an
older subtree. Descending through a scalar/null returns `WrongKind`. No deep
merge is implied.

Bindings have unique literal UTF-8 keys within each source. A dot is an
ordinary key byte; use a counted sequence of keys for path traversal. Empty,
non-ASCII, and embedded-NUL keys are supported. Different spellings are distinct;
there is no case folding or Unicode normalization. Repeated keys across sources
are expected overrides. A binding can contain a complete native borrowed table,
array, or temporal value as well as a scalar.

`get` and `lookup` return `Result<Option<Resolved>, Error>`. `Resolved.value` is
the unified value and `source_index` is its zero-based position in the supplied
source view. The index survives subtree selection. Keep source names or file
paths in a parallel application-owned list if they are needed for diagnostics.
Child `Value`s do not invent a new origin: retain their parent's resolved index.
Native JSON/TOML parse errors retain their native kind/byte-offset contracts;
the application knows which file it is loading. The facade does not synthesize
source line locations that native trees do not retain.

## Types and accessors

| Unified kind | Meaning | Access |
| --- | --- | --- |
| `Null` | JSON null or an explicit binding | `is_null()` |
| `Boolean` | A boolean | `boolean()` |
| `Text` | UTF-8 string, including NUL | `text()` |
| `Array`, `Table` | Native ordered children | `len()`, `children()`, `element(index, work)`, `member(key, work)` |
| `ExactDecimal` | Exact RFC 8259 JSON number spelling | `decimal_text()`, exact integer accessors |
| `Integer` | TOML or explicit signed 64-bit integer | `integer_i64(work)`, checked unsigned access |
| `UnsignedInteger` | Explicit unsigned 64-bit binding | `integer_u64(work)`, checked signed access |
| `Float64` | TOML or explicit IEEE binary64, including signed zero, infinities, NaNs | `float64()` |
| Four temporal kinds | TOML offset/local date-time, local date, local time | `temporal_text()`, `temporal(work)` |

`Value.kind()` identifies the kind; `kind_text` supplies its stable report name.
`json(config_value)` borrows an existing JSON value. `toml(document, node)`
checks the native node ID and borrows it. `scalar(Scalar::...)` borrows text or
stores a primitive value. Layers validate raw scalar decimal spellings; prefer
`exact_decimal(text, maximum_bytes, work)` for a checked standalone decimal.

JSON numbers never pass through binary floating point. `1e4000` stays exact
number text; `8.1e1` converts exactly to integer 81; `1.1` returns `NotInteger`;
a mathematically integral value outside the requested integer range returns
`NumberOutOfRange`. All-zero values, including negative zero with enormous
negative exponents, convert to zero. Exponents never cause exponent-sized loops.
A JSON exact number cannot be read with `float64`. TOML floats cannot be read
with integer accessors. Text is never implicitly parsed by a value accessor.

TOML's existing parser has already normalized integer spellings and rounded
floats to binary64. The facade preserves those native types and values, including
negative zero and nonfinite values; it does not promise the original TOML numeric
lexeme. It keeps the four temporal kinds distinct. Native `Temporal` includes
calendar fields and **all fractional digits**; its nanosecond field truncates
beyond nine digits. `temporal_text` retains the native temporal spelling. No
implicit timezone conversion or string/date coercion is performed.

`parse_integer(text, work)` explicitly parses the existing core signed-decimal
integer grammar (optional ASCII sign, decimal digits, no surrounding whitespace;
leading zeros are accepted). The scalar parser caps the complete integer token
at 20 bytes, including signs and leading zeros. `parse_boolean` accepts exactly
`true` or `false` and caps its token at five bytes. Exceeding either scalar cap
returns `TextLimit` before grammar conversion.
`exact_decimal` validates a strict JSON number token with
`core::decimal_number`, without constructing a JSON document. These helpers
return typed scalar values; their input storage remains borrowed.

`Children.next(work)` returns an ordered optional value. `key()` applies only to
a native table/object child. Exhaustion is fused; a work error leaves the cursor
at the same item. Negative array indices are `Bounds`; an index beyond the end
is absent. Invalid accessor kinds are errors, including null. Missing and null
remain different states.

## Bounds and cumulative work

`default_limits()` permits 64 sources, 256 bindings per binding source, one
million visited nodes across all sources, depth 128, 65,536 bytes per key,
16 MiB per text/decimal/temporal spelling, and 128 path components. Limits must
be nonnegative; depth is capped at 256 to bound recursive validation stack use.
Native source roots are depth zero; a top-level binding value is depth one.
Repeated appearances of a borrowed value count as repeated visits. Parser input,
number, node, allocation, and parse-work limits remain the native owners'
responsibility; settings admission adds its own traversal limits.

Create one `Budget` with `budget(max_work)` and pass its borrowed reference to
validation, lookup, traversal, scalar parsing, integer conversion, temporal
conversion, and environment snapshotting. **Reuse the same budget** for a bounded
session; copying a budget descriptor creates a separate allowance. Functions
never reset it. `remaining_work()` exposes what remains and `charge(amount)`
lets application work join the same allowance. Failed charges exhaust it.
Constant-time kind/text/bool/float/count accessors do not need a budget.

Validation charges sources, visited nodes, cursor advances, and key/text bytes.
Equality charges its length check and candidate bytes when lengths match. UTF-8
validation and number parsing are charged before scanning; exact numeric
conversion reserves a linear allowance before scans and at most 20 additional
digits. Temporal conversion charges its spelling length. Lookup and iteration
charge their actual scan progress, including exhausted cursor calls. Work units
are conservative operation allowances, not nanoseconds. A failed operation can
consume work and never replenishes it. `WorkLimit` is distinct from missing data.
Binding uniqueness checks are quadratic in binding count; the binding cap and
shared budget bound them. Native table lookup and array indexing are linear.

Counted views validate logical metadata, including negative/overflowing bounds.
As with `core::slice` and `core::text`, callers must provide enough physical
backing, valid typed layout/stride, and live immutable storage. Overclaiming a
physical allocation is outside the view contract. These lifetime rules are
manual in the current language. See the preserved compiler-state fixture under
`tests/fixtures/stdlib_compiler_state/settings_array_view` for an independently
reproduced implicit array-to-slice conversion defect in a direct record initializer; settings does not redefine the
view contract to conceal that defect.

## Explicit environment snapshot

`settings_env::Spec { environment, setting, parse }` maps one nonempty environment
name to one literal settings key. Names cannot contain `=` or NUL; setting keys
must be unique in the allowlist. Several settings may deliberately read the same
environment name. `Parse` selects `Text`, `Boolean`, `Integer`, or `ExactDecimal`;
there is no guessing from a value's spelling.

`snapshot(specs, maximum_count, maximum_value_bytes, maximum_total_bytes, work)`
checks the allowlist before reads, enforces per-value and cumulative value-byte
caps, and owns all copied values. Names/settings keys are also capped by
`maximum_total_bytes` individually and remain borrowed from the allowlist.
`Snapshot.as_source()` borrows its bindings; destroy the snapshot after those
views expire. Partial owners are released on every failure. Empty text is a
present value; empty numeric/boolean text is a parse error. Invalid UTF-8 is an
error. Absent values produce no binding.

The existing environment ABI reports an absent variable as negative length and
cannot distinguish every host lookup failure from absence. The adapter checks
availability first and reports short/changed-length reads as `HostRead`. It reads
each present value once after measuring it; this is not an atomic snapshot of
concurrent changes to the whole process environment. No implicit enumeration,
prefix discovery, filesystem search, or global mutable settings state is used.

## Offline application

Build and run with the established compiler roots:

```sh
target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  sample_programs/library/settings_inspect.lani -o target/stdlib-work/settings-inspect
SETTINGS_PORT=8081 target/stdlib-work/settings-inspect \
  --json defaults.json --toml local.toml --host example
```

The application resolves `host` (nonempty text, at most 256 UTF-8 bytes), `port`
(exact integer 1..65535), and `enabled` (boolean). Its ordered layers are:

1. Defaults: `localhost`, 8080, true (source 0).
2. Up to eight `--json FILE` / `--toml FILE` inputs, in argument order.
3. `SETTINGS_HOST`, `SETTINGS_PORT`, `SETTINGS_ENABLED`, explicitly typed.
4. `--host TEXT`, `--port INTEGER`, `--enabled true|false`; the last repeated
   scalar option wins.

The environment and CLI layers have stable indices even when empty. File values
are checked only after precedence is resolved for the application schema; invalid
syntax is always rejected when the file is loaded. An invalid environment/CLI
scalar is rejected when read, even if a later layer would hide it.

The normal deterministic report prints each effective value and its source
index. Text is UTF-8 encoded as hexadecimal, so arbitrary text cannot inject
report lines. `--get KEY [--member KEY]...` inspects any winning value through the
same API. It reports `missing` or `source N` and a recursive typed report: decimal,
text, key, and temporal payloads are hex; integers are decimal; float64 payloads
are unsigned IEEE bit patterns; arrays/tables carry child counts. This inspection
mode preserves null, exact huge numbers, custom tables, and TOML temporal types.
It does not apply the three-field application schema.

`--max-input N` defaults to 1 MiB per file, `--max-output N` to 4 MiB staged output,
and `--max-nodes N` to 100,000 across admitted sources. Each option accepts
0..16 MiB. Native depth is 64 and number spelling is capped at 1024 bytes. The
settings session uses 100 million work units for facade/adaptor operations;
native parsing retains each parser's separate limits. Earlier file owners remain
live while later files are parsed, so loading memory is bounded by the eight-file
cap times the per-parser limits before aggregate admission. Environment values
are capped at 4096 bytes each / 12,288 total. Arguments are capped at 64 tokens / 8192 bytes;
paths at 32 components. Files are closed on success and failure. The complete
report is staged before the first stdout write; an output host failure may leave
a prefix already written, as with any stream. Interrupted reads/writes retry and
short writes advance correctly. Owners are cleaned after parse, schema, limit,
allocation, or host errors. This Linux native executable explicitly selects
`std::signal::BrokenPipe Ignore` before allocation or output, so actual closed
stdout/stderr pipes return checked errors and owner cleanup runs. If installing
that process-wide policy fails, it exits with status 5 without attempting output.
A failed stderr write returns the I/O status.

Exit codes: 0 success, 2 arguments, 3 invalid document/value/schema, 4 allocation,
5 host I/O, unavailable environment or signal setup, 6 configured resource/work
limit.
There is no network access, host configuration parser, or JSON transport bridge.

## Verification and sources

`tests/extended_settings_execution.rs` executes the native contract fixture and
application. The Python oracle independently uses `json` with exact numeric token
callbacks/`decimal.Decimal` and `tomllib`, generates nested trees with seed
`0x5e771a65`, and checks precedence, types, absence/null, scalar/schema errors,
CLI/input/output limits, and a large-table report. Native contracts additionally
exercise temporal fractional precision, integer endpoints, signed zero/nonfinite
floats, borrowed iteration, no allocations during queries, cumulative budget
exhaustion, and each facade limit. Fault drivers inject every reached allocation
failure, file open/read/close errors, interrupted reads/writes, short writes,
stdout failure, `/dev/full`, actual closed stdout/stderr pipes and signal setup
failure, checking allocation/handle cleanup.

Source semantics come from [RFC 8259 number grammar](https://www.rfc-editor.org/rfc/rfc8259.html#section-6)
and [TOML 1.1 types](https://toml.io/en/v1.1.0), as implemented by the existing
native modules. The independent TOML model uses the supported TOML 1.0 overlap
when the installed Python's `tomllib` predates 1.1. No Python package is a
production dependency. Tests require the native Vulkan compiler, Python 3.11+
and `strace`.
