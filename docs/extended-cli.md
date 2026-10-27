# Command-line arguments and parsing

Two Lanius modules separate process access from portable parsing:

- `std::args` owns a bounded snapshot of host argument bytes.
- `ext::cli` borrows argument and option-schema views and emits parsing events
  without allocating, accessing the host, printing diagnostics or exiting.

Both have execution evidence on **x86_64 Linux using the GPU compiler**.
This does not establish GPU execution of user programs or other host support.
Importing the parser requires the optional `extended` source root.

Two additional optional modules provide
[command hierarchies and generated help](extended-cli-commands.md):
`ext::cli_commands` routes through this same option lexer using caller-owned
scratch, and `ext::cli_help` renders into caller storage. Their schema,
ownership and current executable receipts are separate from the flat-parser
checkpoint below. In particular, hierarchy parser copies cannot independently
fork over shared mutable scratch.

Optional [response-file preprocessing](extended-cli-response.md) produces stable
owned arguments for either parser. Its strict byte grammar, source diagnostics,
provider ownership and native-file evidence are separate from token parsing.
[Portable completion](extended-cli-complete.md) now shares canonical prefix
classification and explicit pending-value parsing. Its selected pure/model
checks pass; query owner/OOM and output groups pass separately. The Bash
5.2/bash-completion 2.11 adapter also has finite function and actual PTY
insertion receipts in the completion guide.

## Host snapshots

`std::args::snapshot(first, maximum_count, maximum_bytes)` returns
`Result<Arguments, Error>` containing arguments in `[first, argc)`. Use first 1
to omit the executable or 0 to include it. The limits apply only to selected
arguments; byte counts exclude terminating NULs. Empty arguments remain entries.
No UTF-8 conversion, normalization or shell expansion occurs.

| API | Contract |
| --- | --- |
| `snapshot(first, maximum_count, maximum_bytes)` | Validate bounds/count/byte limits, allocate independent storage and copy selected arguments |
| `Arguments.len()`, `is_empty()`, `byte_len()` | Constant-time selected count, emptiness and total byte count |
| `get(index)` | Optional borrowed `View<u8>`; negative and past-end indices return None |
| `as_view()` | Borrow the complete `View<View<u8>>` |
| `destroy()` | Release descriptors and bytes, reset the owner; repeating on the same owner is harmless |

Errors are `Bounds` for negative inputs or a first index past argc,
`CountLimit` for too many selected arguments or descriptor-storage overflow,
`ByteLimit`, `AllocationFailed`, and `HostRead(index)` for failed or inconsistent
host reads. Index -1 denotes argument-count or aggregate-metadata failure.
Partial construction releases all acquired storage before returning an error.

The snapshot performs two metadata passes and copies each selected byte once.
It makes at most two allocations: a descriptor vector and a packed byte buffer.
An empty selection allocates nothing. Nonempty lists of empty arguments need
only the descriptor allocation. Arguments cannot contain NUL on this host.

Keep one active owner. Copies of Arguments alias the allocation, and views do
not prolong its lifetime. Treat borrowed bytes and descriptor views as read-only;
destroying the owner invalidates them. The compiler does not enforce these
ownership or immutability conventions. Independent snapshots have independent
storage. The older `std::args_checked` remains a separate caller-buffer API.

## Parser schema

`ext::cli::parser(arguments, specs, ordering)` returns `Result<Parser, Error>`.
Both inputs are counted borrowed views. Their physical backing, names and
argument bytes must remain valid and unchanged for the parser's lifetime.
Argument indices are relative to the supplied view: no executable is skipped
implicitly.

A `Spec` has a nonnegative `id`, a long-name `View<u8>`, a `short` byte and an
`Arity`. IDs and enabled spellings must be unique. An empty long name or short
byte 0 disables that spelling; at least one spelling must be enabled. Short
names are ASCII alphanumeric. Long names begin with an ASCII alphanumeric byte
and contain only ASCII alphanumeric bytes or hyphens.

`Arity::Flag` has no value, `Required` needs a value, and `Optional` accepts an
attached value only. All schema entries are validated before parsing starts.
`InvalidSpec(index)` and `DuplicateSpec(index)` identify the offending entry;
duplicate checking reports the later entry. No help flag is implicitly reserved.

## Parsing behavior

The syntax follows the short-option groups, attached values and terminator
described in the [GNU argument conventions](https://sourceware.org/glibc/manual/2.24/html_node/Argument-Syntax.html),
with explicit choices for ambiguity and ordering:

| Input | Behavior |
| --- | --- |
| `-abc` | Flags a, b and c; a value-taking option consumes the remainder |
| `-oVALUE`, `-o VALUE` | Attached or separate required value |
| `--output=VALUE`, `--output VALUE` | Exact long name with attached or separate required value |
| `--color=`, `--color=VALUE` | An optional value that is present, including a present empty value |
| `--color`, `-c` | Optional value absent; the next token remains independent |
| `-cVALUE` | Attached optional value; in `-c=VALUE`, the value includes the equals sign |
| `--` | End option parsing; subsequent tokens are operands |
| `-`, empty token | Ordinary operand |
| Required value `-x` or `--` | Consume verbatim as the value, without interpreting it as an option/terminator |
| `--flag=value` | `UnexpectedValue`, including an empty value |
| Abbreviated or unknown name | `UnknownOption`; no long-name abbreviation |

`Ordering::Intermixed` continues recognizing options after operands, preserving
event order and leaving the argument array untouched. `OptionsFirst` makes the
first operand end option recognition; everything afterward, including `--`, is
an operand. Neither mode reads environment variables or reorders arguments.

`Parser.explicitly_terminated()` reports whether an actual `--` terminator was
consumed. It remains false when OptionsFirst stops at an operand or when `--`
is consumed as a required option value. This distinction supports command
routing without changing the flat parser's event grammar.

`Parser.next()` returns `Result<Option<Event>, Error>`. `Event::Option` contains
an `Occurrence` with the schema ID, option `Location` and optional value
`Argument`. `Event::Operand` contains an Argument. Arguments contain borrowed
bytes and their Location. A Location gives the zero-based argument index and
byte offset within that argument. Short options point at their option byte;
long options point after the two hyphens. Value locations point at the first
value byte, including the end position for an attached empty value.

`UnknownOption`, `MissingValue` and `UnexpectedValue` contain Locations.
UnexpectedValue points at the long option's equals sign. An error is sticky:
later next calls return that error without further consumption. Earlier emitted
events remain valid. Exhaustion repeatedly returns Ok(None). Copying a Parser
forks its position without copying source storage.

Repetition emits every occurrence. Applications decide duplicate-option policy,
conflicts, defaults, numeric conversion, help and required operands. Values and
operands preserve arbitrary bytes; they need not be UTF-8. This parser consumes
already separated argument tokens; it never interprets quotes, escapes or a
command string. Optional [command routing and automatic help](extended-cli-commands.md)
now build on this parser. [Response files](extended-cli-response.md) are an
opt-in preprocessing layer; [completion](extended-cli-complete.md) has a separate
portable/host boundary and current acceptance scope.

Schema validation uses pairwise duplicate checks. Option lookup scans the
schema: parsing costs O(input bytes + occurrences × schema lookup cost), with
long-name comparison proportional to compared name bytes. The parser itself
uses constant storage and never allocates.

## Streaming checksum application

`sample_programs/checksum.lani` computes CRC-32/ISO-HDLC for each file operand,
printing one eight-digit lowercase hexadecimal checksum per line in operand
order. With no operands it reads stdin; a `-` operand reads stdin at its current
position. Filenames retain their original bytes, including non-UTF-8 bytes.

- `-d`, `--decimal`: print the checksum as an unsigned decimal integer.
- `-x`, `--hex`: select hexadecimal output explicitly.
- `-n BYTES`, `--limit=BYTES`: maximum bytes per input; the last occurrence wins.
  The default is u64::MAX. Exact-limit input succeeds; excess input fails after
  reading at most one byte beyond the limit.
- `-h`, `--help`: show usage after validating the complete command line.
- `-c FILE`, `--config FILE`: load [configuration sources](extended-config.md)
  in order; explicit CLI settings override them. Help does not load these files.
- `-l LEVEL`, `--log-level LEVEL`: select the [structured logging](extended-log.md)
  filter. Default off; enabled per-input records go to stderr.
- `--`: permit filenames beginning with a hyphen.

The program validates all options before opening inputs. It uses a fixed 4 KiB
scratch buffer and does not allocate in proportion to file size. Every opened
file receives one close attempt before its checksum is emitted. On Linux, close
is not retried, including after EINTR. Stdin remains open. Exit 2 means invalid
configuration, arguments or an input limit, 3 means I/O failure, and 4 means allocation
failure. Results for earlier files can already be emitted when a later file
fails; a write failure can leave a partial output line.

Argument snapshots are limited to 4,096 arguments and 1 MiB of argument bytes.
File paths use the existing native file binding, including its 4,095-byte path
limit. CRC32 is an error-detection checksum, not an authentication mechanism.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc sample_programs/checksum.lani --stdlib-root stdlib --source-root extended -o target/stdlib-work/checksum
printf '123456789' | timeout 5s target/stdlib-work/checksum
timeout 5s target/stdlib-work/checksum --decimal --limit=1048576 -- input.bin
```

The stdin example prints `cbf43926`.

## Execution and scale evidence

The original flat-parser/checksum checkpoint passed eight groups in
`tests/extended_cli_execution.rs`. These receipts and timings retain that source
scope. The current hierarchy increment reruns one selected flat-parser test
successfully in 6.04s after a separate 2.32s build, with seven tests filtered
out (`cli-commands-flat-parser-regression-first.log`). Current hierarchy/help
and application evidence is in the [companion guide](extended-cli-commands.md).

Original coverage:

- Schema validation, parser forks, array-stride/nonzero-offset views and fused
  exhaustion run with every allocation denied. A synthetic attached value
  checks preservation of NUL and byte 255, beyond host argv's restrictions.
- Raw-byte snapshots, empty arguments, executable inclusion, independent
  snapshots, count/byte boundaries and every observed allocation failure run
  with syscall tracing and complete allocation cleanup checks.
- Explicit spelling/error cases check option groups, empty values, raw bytes,
  both ordering modes, terminators, exact matching, error locations and sticky
  failures.
- Ninety-six generated cases construct semantic events first, vary their
  valid spellings and compare the emitted events and locations. Each has 48
  generated choices, followed by raw operands after a terminator. Seed:
  `0x0c112026`; all ten spelling categories occur more than 100 times.
- Lists of 4,096 and 32,768 arguments produce 8,192 and 65,536 option events.
  Both use exactly two snapshot allocations and make no further allocation
  attempts during parsing.
- The checksum application compares streaming results with a table-driven
  reference, checks the canonical `123456789` vector, raw file paths, options,
  malformed numbers and sizes across the 4 KiB read boundary.
- Application fault injection covers snapshot allocation, open/read/write/close
  failures, interrupted read/write, one-attempt interrupted close and zero writes.
  Traces check allocation releases and one close attempt per opened descriptor.
  Injected close errors suppress the actual syscall, so that case verifies the
  close contract rather than proving kernel release under the injection.

The host ABI's argument-query failure branches cannot be forced through syscall
injection because they read the process's initial argument data directly. These
guards remain distinct from the exercised allocation and validation failures.

On an AMD Ryzen 9 5950X, nine alternating runs of `cli_workload.lani` measured
median whole-program child CPU times of 8.83 ms for 4,096 arguments and 68.90 ms
for 32,768. Each argument was `-ab`. Timings include process startup, argument
capture, schema validation, parsing, result checks, cleanup and one output line;
they are not isolated parser timings or GPU compiler performance claims. No
timing threshold is used as a test gate.

```sh
timeout --kill-after=2s 100s env CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 cargo test --locked --test extended_cli_execution -- --nocapture
```

The suite requires the GPU compiler's Vulkan environment and `strace`. The
original CLI milestone changed no compiler or runtime implementation. Its
checksum uses packed i32 scratch storage. The earlier large-byte-repeat
checker error was subsequently [fixed in `e59a9183`](compiler-array-repeat-context.md);
the CLI measurements above retain their original checkpoint.
Configuration loading now has its own [contracts and execution suite](extended-config.md).
[Structured logging](extended-log.md),
[directory operations](stdlib-directory.md) and
[command hierarchy/help](extended-cli-commands.md) execute on their documented
profiles. [Response preprocessing](extended-cli-response.md) has separate
contracts and receipts. [Completion](extended-cli-complete.md) has selected
portable/query semantics and owner acceptance, plus finite Bash function/PTY
insertion and watchdog receipts.
Broader runtime support remains on the [library roadmap](library-roadmap.md).
