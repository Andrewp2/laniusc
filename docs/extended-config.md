# Configuration sources and overlays

`ext::config` provides owned JSON configuration sources, bounded file loading
and borrowed typed queries. Sources are immutable by contract. Layered lookup
selects the last source containing a top-level key; absent keys fall back to
earlier sources. An explicit null overrides earlier values.

The implementation is Lanius. Execution evidence covers **x86_64 Linux using
the GPU compiler**, not GPU execution of user programs or other hosts.

## Format and precedence

Configuration uses the existing [JSON implementation](extended-json.md).
Every source must have an object root. Duplicate decoded keys are rejected
throughout the document, including equivalent escaped spellings and nested
objects. This policy is enforced even if the supplied JSON options would
otherwise permit duplicates. Comments, invalid UTF-8, trailing content and
other malformed JSON produce errors.

Overlays are shallow and deterministic. For example, if an earlier source has
`{"service":{"host":"local","port":80}}` and a later source has
`{"service":{"port":443}}`, the selected service is the later object;
looking up host inside it returns None. Arrays, scalars and null follow the same
whole-value replacement rule. Empty strings, dotted names and Unicode names
are literal keys; there is no path syntax, normalization or interpolation.

Source order is explicit: index zero is the lowest priority. A resolved Value
records its source index, and its descendants retain that origin. Applications
choose source names, defaults, environment mapping, schema validation and CLI
precedence. The module does not read environment variables or search directories
implicitly. TOML support, environment adapters and reusable schema validation
remain future work.

## API and ownership

| API | Contract |
| --- | --- |
| `parse(text, json_options)` | Borrow an owned String and return `Result<Config, Error>` with independent document storage |
| `load(path, maximum_bytes, json_options)` | Read, validate and own one file source; close the acquired file on every path |
| `is_allocation_failure(error)` | Classify allocation failures across input buffering, text decoding and JSON construction |
| `Config.root()` | Borrow the object root as a Value |
| `Config.get(key: Text)` | Optional borrowed top-level Value; no allocation |
| `Config.destroy()` | Free/reset the source; repeat destruction on the same owner is harmless |
| `layers(View<Config>)` | Borrow an ordered collection of sources without taking ownership |
| `Layers.len()`, `get(key)` | Source count and optional highest-priority Value |
| `Value.source_index()`, `kind()`, `is_null()` | Origin and exact type information |
| `Value.member(key)`, `element(index)` | Result containing an optional child; wrong container type is an error |
| `Value.len()` | Result containing the child count of an object or array |
| `Value.boolean()` | Result containing a boolean; no coercion |
| `Value.text()`, `number_text()`, `key()` | Result containing borrowed decoded text, exact number spelling or an object-member key |
| `Value.integer_i64()`, `integer_u64()` | Exact integer conversion with distinct fractional/range errors |
| `Value.children()` | Result containing a borrowed cursor over object members or array elements |
| `Children.next()` | Optional next child; exhaustion repeatedly returns None |

Value query errors use `ext::json::Error`. Missing keys and past-end array
indices return None; negative indices are Bounds. Keys exist only on object
members, and child counts/cursors exist only on containers. Wrong types produce
WrongKind rather than applying an implicit default.

Keep one owner per Config. Copying a handle aliases its storage. Layers,
Values, child cursors and returned Text values borrow the sources; retain the
owners and leave their storage unchanged until all borrows are finished.
Destroying a source invalidates those borrows. After destruction only repeat
destruction is supported on that Config handle. Use `alloc::string::from_text`
when an independent text copy is needed. The compiler does not enforce these
lifetime or immutability conventions.

Loading and parsing copy their inputs. Temporary input buffers and strings are
released before a successful file load returns. All partial owners are released
on failure; the caller's path/text and previously loaded sources remain valid.
The library does not own a Layers source array and never destroys its entries.

## Exact numeric queries

The new JSON numeric queries work on the [RFC 8259 number grammar](https://www.rfc-editor.org/rfc/rfc8259.html#section-6).
They preserve exact decimal meaning rather than rounding through floating point:
`1.25e2` becomes 125, `1200e-2` becomes 12, and `1.25` produces NotInteger.
An integral value outside the destination range produces NumberOutOfRange.
Negative nonzero integers are out of range for u64; every spelling of negative
zero converts to zero. Booleans and numeric strings are WrongKind.

Conversion removes insignificant zeros, combines decimal scale with the
exponent, then checks the destination bound while accumulating at most twenty
significant digits. Huge exponents are classified without exponent-sized loops
or allocations. Runtime is linear in the source number length, with constant
working storage. The exact original spelling remains available through
`number_text()` / `Document.number_view()`.

## Loading limits and errors

`maximum_bytes` bounds file input. A negative limit is InvalidLimit. Other
document limits come from `ext::json::Options`; invalid options fail before
opening a file. Duplicate rejection is always enabled. Input and document
limits do not constitute a total process-memory budget.

Load errors retain the cause: Json, Text, RootNotObject, InvalidLimit,
InputLimit, AllocationFailed or Io. JSON offsets are preserved; invalid UTF-8
reports its byte offset through the String error. Query errors use offset -1.
A read failure takes precedence over a simultaneous close failure. The loader
uses existing stream behavior for interrupted reads, makes one open attempt,
and follows the native file contract of one close attempt, including on EINTR.
It can read a scratch-buffer chunk past the byte limit before rejecting input.

Object member lookup scans siblings. An overlay lookup scans sources from
highest to lowest priority until it finds a key; nested lookup stays within that
selected source. Array indexing scans preceding siblings. Child traversal is
linear and does not allocate. JSON duplicate rejection currently scans previous
members and can be quadratic for large objects; this remains a performance
limitation, not a constant-time lookup claim.

## Configured checksum application

The existing checksum program now accepts repeated `-c FILE` / `--config FILE`
options and `-x` / `--hex`. It reads settings from files in command-line order,
then applies explicit command-line settings regardless of their positions.
Within the CLI, the last limit and the last decimal/hex selection win.

Supported file keys are `decimal` (boolean) and `limit` (an exact nonnegative
integer fitting u64). All supplied sources must pass this application schema,
including sources later overridden. Unknown keys and null/wrong-type values
are errors. Each file is limited to 1 MiB, depth 32, 4,096 nodes, 65,536 bytes
per key/string and 4,096 bytes per number. Sources are freed after scalar
settings are resolved, before processing data inputs. Help validates CLI syntax
and shows usage without loading configuration files.

For `settings.json` containing `{"decimal":true,"limit":9.0}`:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc sample_programs/checksum.lani --stdlib-root stdlib --source-root extended -o target/stdlib-work/checksum
printf '123456789' | timeout 5s target/stdlib-work/checksum -c settings.json
printf '123456789' | timeout 5s target/stdlib-work/checksum --hex -c settings.json
```

These print `3421780262` and `cbf43926`. Exit 2 denotes invalid configuration,
schema, arguments or a data limit; 3 denotes I/O failure; 4 denotes allocation
failure. Previous-file output can remain after a later data failure. Configuration
errors occur before data inputs are opened or checksums are emitted.

## Execution evidence

Eight groups in `tests/extended_config_execution.rs` cover:

- Layer precedence, null masking, whole-object replacement, exact types,
  origin tracking, child traversal, missing values, bounds and empty layers.
  Traces show no allocations during the query phase.
- Borrowed JSON strings/numbers/keys surviving node-vector growth and caller
  String destruction; wrong kinds and invalid IDs; no query allocations.
- 670 exact numeric cases: integer boundaries, 512 generated decimal/exponent
  forms, fractional values, wrong types, exponents beyond 32-bit counts and
  10,000-digit forms that cancel to a small integer. The reference uses integer
  rational arithmetic; seed `0xc0f12026`.
- 64 generated configurations with zero through four layers, querying five
  keys per case against a shallow reference map. Nested arrays/objects, all
  value kinds, Unicode and embedded NUL are included; seed `0x1a9e2026`.
- Invalid UTF-8/JSON, scalar roots, nested/escaped duplicate keys, exact input
  limits and each configurable JSON document limit.
- Every observed allocation failure during file loading, plus open/read/close
  failures and interrupted read/close behavior. Traces check allocation cleanup
  and close attempts.
- Checksum config schema, repeated files and CLI overrides, including rejection
  of invalid sources even when a later source or CLI option would override them.
- Every observed allocation and I/O failure in a two-config-file checksum run,
  including cleanup when adopting sources into the owner vector. The successful
  run observes 19 allocations and opens the two configs and one data file.

The existing three JSON execution groups and two checksum application groups
also pass. These exercise the changed JSON member-query path and preserve the
previous application's streaming, raw-path, limit and failure behavior.
Injected close errors suppress the actual syscall: those cases establish the
one-attempt close contract rather than proving kernel release under injection.

```sh
timeout --kill-after=2s 100s env CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 cargo test --locked --test extended_config_execution -- --nocapture
```

The tests require the compiler's Vulkan environment and `strace`. No compiler,
extractor, formal proof or runtime implementation changed. Logging and the
remaining configuration features are still on the [library roadmap](library-roadmap.md).
