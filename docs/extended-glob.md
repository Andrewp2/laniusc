# Compiled byte globs

`ext::glob` compiles a raw-byte pattern once and matches complete
[`core::path::Path`](stdlib-paths.md) values with reusable caller storage.
The implementation is Lanius. It performs no filesystem lookup, path expansion
or normalization. A match says nothing about whether a file exists or is a
directory.

Executable evidence covers **x86_64 Linux using the GPU compiler**. GPU-kernel
execution and other hosts have not been established.

## Matching rules

Matching consumes the entire input. An empty pattern matches only an empty path.
Pattern and path bytes need not be UTF-8. NUL is invalid in either: compilation
rejects it in a pattern, and a path must satisfy the `core::path` contract.
Repeated slashes, `.` and `..` remain literal input bytes.

| Syntax | Meaning |
| --- | --- |
| Ordinary byte | Match the same byte, subject to the ASCII case option |
| `?` | Match one byte |
| `*` | Match zero or more bytes |
| `[abc]`, `[a-z]` | Match one member of a byte set or inclusive range |
| `[!abc]`, `[^abc]` | Match one byte outside the set |
| `\x` | Match literal `x` when escaping is enabled |

Within brackets, `]` is literal when it is the first member after an optional
negation marker. A leading or trailing `-` is literal. Escaping applies inside
brackets as well. Named ASCII classes use the form `[[:digit:]]`; supported
names are `alnum`, `alpha`, `blank`, `cntrl`, `digit`, `graph`, `lower`, `print`,
`punct`, `space`, `upper` and `xdigit`.

These ordinary wildcard, slash, escape and leading-dot rules follow the
[`fnmatch` flags](https://man7.org/linux/man-pages/man3/fnmatch.3.html).
The [`glob` grammar](https://man7.org/linux/man-pages/man7/glob.7.html) is the
reference for bracket syntax. This module chooses fixed byte and ASCII rules:
it does not consult a host locale, decode Unicode or implement collating
symbols and equivalence classes.

`default_options()` returns:

| `Options` field | Default | Contract |
| --- | --- | --- |
| `pathname` | `true` | Ordinary wildcards and brackets cannot consume `/`; only literal slash and the recursive extension can |
| `literal_leading_dot` | `true` | A dot at input start, or immediately after `/` with `pathname`, requires a literal dot token |
| `escape` | `true` | Backslash quotes the next byte; a final backslash is an error |
| `ascii_case_insensitive` | `false` | Fold ASCII `A`–`Z` to `a`–`z` for literals and range endpoints |
| `globstar` | `true` | Enable recursive whole-component `**` when `pathname` is also true |

A bracket containing `.` does not count as an explicit leading dot. With the
defaults, `.*` matches `.hidden`, while `*`, `*.*` and `[.]hidden` do not.
With `pathname = false`, slash is an ordinary byte and only the initial dot is
protected. Disabling `literal_leading_dot` lets wildcards consume such dots.

Case-insensitive literal and range members include both ASCII cases. A range
uses the folded endpoints: `[A-z]` then means ASCII letters, while the same
case-sensitive range also includes the punctuation between `Z` and `a`.
Named classes retain their stated ASCII categories; `[[:upper:]]` still selects
uppercase bytes when case-insensitive matching is enabled. Bytes above 127
retain their exact values.

## Recursive components

An unescaped run of **exactly two stars** is recursive only at a component
boundary and directly before a slash separator or pattern end. With escaping
enabled, `\/` has the same separator identity as `/`, including before or
after recursive stars. A recursive `**/` consumes zero or more complete
components, including their slashes. A final recursive `**` consumes the
remaining bytes, including slashes. Both obey the leading-dot option. Other
star runs collapse to an ordinary `*`. With escaping disabled, backslash is an
ordinary byte, so the `**\/` spelling does not form a recursive token.

| Pattern | Input | Default result |
| --- | --- | --- |
| `**/a` | `a`, `x/y/a`, `/a` | Match |
| `**\/a` | `a`, `x/y/a` | Match |
| `a/**/b` | `a/b`, `a//b`, `a/x/y/b` | Match |
| `a\/**\/b` | `a/b` | Match |
| `a/**` | `a/`, `a/x/y` | Match |
| `a/**` | `a` | No match: the literal slash is required |
| `**` | Empty path, `a/b` | Match |
| `**/*.txt` | `.hidden/a.txt` | No match |
| `**/.*` | `a/.hidden` | Match |
| `a/***/b` | `a/x/b` | Match |
| `a/***/b` | `a/x/y/b` | No match |

The recursive forms draw on the documented
[`gitignore` double-star rules](https://git-scm.com/docs/gitignore#_pattern_format).
The module matches one explicit whole-path pattern. Gitignore file parsing,
negation rules, implicit basename matching and directory-only rules are outside
this API. Braces, grouping, alternation and extglob operators have no special
meaning.

## API and ownership

| API | Contract |
| --- | --- |
| `compile(bytes: View<u8>, options: Options, limits: Limits)` | Return `Result<Pattern, Error>`; copy the selected pattern into owned tokens |
| `default_options()`, `default_limits()` | Construct the defaults described here |
| `Pattern.borrow()` | Borrow the owner without cloning its storage |
| `Pattern.is_live()` | Whether this handle has been destroyed |
| `Pattern.token_count()` | Compiled token count; repeated stars and bracket expressions may use fewer tokens than source bytes |
| `Pattern.scratch_len()` | Required scratch byte count: `2 * (token_count + 1)` |
| `Pattern.new_scratch()` | Allocate and return an independent `alloc::vec::Vec<u8>` of the required length |
| `Pattern.matches(path, scratch: View<u8>, max_work: u64)` | Return `Result<bool, Error>`; allocate nothing |
| `Pattern.work_bound(input_bytes: i32)` | Return the conservative work count for an input length |
| `Pattern.try_clone()` | Return an independent compiled owner; allocation failure leaves the source valid |
| `Pattern.destroy()` | Release/reset tokens; repeated destruction on the same handle is harmless |

Keep one owner per Pattern. Copying its value aliases its storage; use
`try_clone` for an independent owner. Destroy each owner and each allocated
scratch vector explicitly. Compilation releases partial storage on failure and
does not retain the source pattern view.

The input path must remain valid and unchanged for the call. Scratch must be
writable and **must not alias the input path or compiled pattern storage**.
Each simultaneous match needs its own scratch. A match clears and reuses the
first `scratch_len()` bytes; their previous contents do not matter. Extra bytes
outside that region are untouched. Logical bounds, scratch length and work
budget are checked before scratch is written. The caller must supply a valid
underlying slice with sufficient physical storage: the compiler does not enforce
these alias, lifetime or physical-length contracts.

After destruction, `matches`, `work_bound`, `new_scratch` and `try_clone` return
`Destroyed`. `is_live()` becomes false, `token_count()` becomes zero, and
`scratch_len()` becomes two. Those queries do not revive the owner.

For a small complete Lanius usage example, see
[`glob_contracts.lani`](../tests/fixtures/extended/glob_contracts.lani). The
normal sequence is compile, allocate scratch once, match many borrowed paths,
destroy scratch, then destroy the Pattern.

## Limits, errors and work

`default_limits()` permits 16,384 pattern bytes and 4,096 compiled tokens.
Limits may be zero; an empty pattern needs no tokens. Negative limits and a
token limit above 1,073,741,822 are Bounds. Compilation may allocate before it
finds a syntax error, and frees that storage before returning the error.

| `Error` | Meaning |
| --- | --- |
| `Bounds` | Invalid logical view bounds, invalid limits or negative work-bound input length |
| `PatternLimit`, `TokenLimit` | Selected pattern bytes or emitted tokens exceed their limit |
| `Nul(index)` | NUL in the selected pattern view |
| `InvalidEscape(index)` | Backslash without a following byte |
| `UnclosedClass(index)` | Bracket expression without a closing bracket |
| `InvalidRange(index)` | Reversed range or class syntax used as a range endpoint |
| `UnknownClass(index)` | Unrecognized ASCII class name |
| `UnsupportedClass(index)` | Collating-symbol or equivalence-class syntax |
| `CapacityOverflow`, `AllocationFailed` | Storage size cannot be represented, or allocation failed |
| `ScratchTooSmall(required)` | The scratch view is shorter than the required byte count |
| `WorkLimit` | Conservative match work exceeds the supplied budget |
| `Destroyed` | An operation requires a live Pattern |

Syntax offsets are zero-based byte indices relative to the selected pattern
view. UnclosedClass identifies the outer opening bracket. InvalidRange
identifies the range dash; unknown and unsupported classes identify their inner
opening bracket. Malformed syntax is an error rather than a literal fallback
or a successful non-match. Ordinary non-matches return `Ok(false)`.

Matching tracks current and next sets of token positions, with forward scans
for empty star transitions. This follows the state-set simulation described by
[Russ Cox](https://swtch.com/~rsc/regexp/regexp1.html), adapted to byte glob
tokens. It avoids recursive backtracking. For `m` tokens and `n` input bytes,
matching takes `O((m + 1) * (n + 1))` time and `2 * (m + 1)` scratch bytes.
Compilation scans the pattern and builds fixed-size byte-class bitmaps.

`work_bound(n)` counts loop slots, not elapsed time or machine instructions:

```text
2 * (m + 1) + (2 * n + 1) * m + n * (m + 1)
```

`matches` rejects a bound greater than `max_work` before starting the match.
`DEFAULT_WORK_LIMIT` is 67,108,864. The conservative budget can reject an input
that a different algorithm would dismiss quickly. Compile limits, work budgets
and scratch requirements are separate; they do not impose a total process
memory limit. A path below an application's byte limit can still exceed its
work budget.

## Path-filter application

[`sample_programs/library/path_filter.lani`](../sample_programs/library/path_filter.lani)
filters a stream of raw paths:

```text
path-filter [--all] [--ignore-case] [--no-globstar]
            [--max-path-bytes N] [--max-work N] [--] PATTERN
```

Input records end with NUL. Each matching record is written unchanged followed
by NUL. A final nonempty record at EOF is accepted and gets an output terminator
if it matches. An empty stream contains no records; an explicit NUL contains one
empty path. Paths can contain newlines and invalid UTF-8. Shell quotes preserve
the pattern for the application.

`--all` / `-a` disables leading-dot protection, `--ignore-case` / `-i` enables
ASCII case matching, and `--no-globstar` makes all star runs ordinary. The
default path limit is 65,536 bytes, configurable from zero up to 1,048,576
bytes. The work budget defaults to 67,108,864 **per record**. Numeric options
accept unsigned decimal digits; signs and overflow are errors. A value may
follow its option or use `--name=value`. The argument snapshot permits at most
32 arguments and 65,536 total argument bytes, separate from pattern and record
limits. Use `--` before a pattern beginning with a dash.

Filtering validates argument syntax and compiles the pattern before writing
any path records. A later input, allocation or output failure can leave a prefix
of output already written. `--help` / `-h` validates CLI syntax and writes usage
without requiring a pattern or reading stdin. Reads and writes retry EINTR;
other I/O errors, including EAGAIN and a zero-progress write, fail.

Exit status is 0 for success, including no matches; 2 for argument, pattern,
input-limit or work-limit errors; 3 for I/O errors; and 4 for allocation failure.
This is a path-stream filter. Filesystem enumeration is a separate host service.

With an existing compiler binary, compile from the repository root and filter
two matching paths into a binary output file:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/path_filter.lani -o /tmp/path-filter

printf '%s\0' 'src/main.lani' 'src/lib/tool.lani' \
  'src/.cache/tool.lani' 'readme.txt' \
  | timeout --kill-after=2s 10s /tmp/path-filter 'src/**/*.lani' \
  > /tmp/matching-paths
od -An -tc /tmp/matching-paths
```

The output bytes are `src/main.lani\0src/lib/tool.lani\0`. The hidden component
is excluded by default. Add `--all` to include it. `od` displays delimiters
without assuming records contain only printable text.

## Execution evidence

[`tests/extended_glob_execution.rs`](../tests/extended_glob_execution.rs)
compiles Lanius fixtures to native executables and checks their runtime behavior.
The six current groups cover:

- Over 34,000 ordinary-glob comparisons against libc `fnmatch` in a thread-local
  C locale, across pathname/dot/escape/case flags, named classes, raw bytes and
  generated valid patterns. Libc is a test oracle, not the library implementation.
- Explicit recursive-component cases and generated comparisons against a
  separate component model, including hidden components, repeated slashes and
  escaped-slash equivalence.
- Syntax offsets, logical bounds, compile limits, exact scratch length,
  work-limit boundaries, cloning and destruction.
- Denied compile, clone and scratch allocations, with all acquired storage
  released and existing compiled patterns preserved.
- Adversarial and repeated matches with fixed storage and no matching allocation.

The bounded command is:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test extended_glob_execution -- --nocapture
```

The current six-group run passed in 13.94 seconds. These results establish the
covered byte-glob contract; they do not establish arbitrary POSIX locale
equivalence, gitignore behavior or GPU execution.

[`tests/extended_path_filter_execution.rs`](../tests/extended_path_filter_execution.rs)
adds three application groups, passed in 7.46 seconds. These execute non-UTF-8
and newline-containing paths, empty/EOF/chunk-boundary records, flags, argument
validation, exact record/work limits and repeated buffer reuse. They deny each
observed allocation, read and write in turn, check all owners are freed, and
exercise EINTR, EAGAIN and zero-progress writes. Reuse tests deny all allocations
after the longest record has established buffer capacity. Run them with the
same bounded command and `--test extended_path_filter_execution`.

## Native performance sample

On 2026-10-23, the `glob_batch.lani` fixture was compiled once and run on CPU 0
with one warmup and five measured processes per workload. These elapsed times
include process startup and owner setup/cleanup; they measure native library
execution, not GPU compiler speed or a comparison with another implementation.

| Workload | Size | Median | Measured range |
| --- | --- | --- | --- |
| Adversarial 33-byte pattern non-match | 1,025 input bytes | 7.143 ms | 7.090–8.394 ms |
| Same adversarial non-match | 16,384 input bytes | 100.579 ms | 93.667–102.257 ms |
| Reuse compiled `src/**/*.lani` and scratch on `src/lib/foo.lani` | 4,096 matches | 62.261 ms | 59.850–63.688 ms |
| Same reused match | 65,536 matches | 707.621 ms | 702.735–816.390 ms |

The adversarial input ends in a byte that prevents a match after many possible
star positions. The state-set matcher scans within its explicit work bound;
the repeated-match execution test separately verifies that matching makes no
allocation. These samples establish bounded behavior at the measured sizes.
