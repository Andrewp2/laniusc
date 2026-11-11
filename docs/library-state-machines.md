# Native state machines in the libraries

The `codex/state_machine_rewrite` migration replaces hand-written control
state with Lanius `machine` declarations. Owners, iterators and parsers store
machine values and send events through `step`; their state is observed through
the generated state type or a named predicate. This includes local scanners,
incremental codecs and protocol drivers, beyond enums whose names end in
`State`.

The audit covers the 196 tracked Lanius files under `stdlib/` and 172 under
`extended/ext/`, plus the support modules added by the migration. The initial
file count in the discussion was not used as a completeness test. Concurrent,
untracked GPU, window and reactive-graph additions are outside this migration.
The existing native OpenSSL lifecycle remains the model for protocol state.
There are 112 machine declarations after the migration, 111 more than at the
branch's starting commit; shared declarations govern many individual owners.

## What counts as control state

A control state remembers which operations or input classes are legal next,
whether an operation has finished or failed, or which owner must clean up a
resource. Examples include an iterator that has exhausted its input, a parser
waiting for a value after a comma, and a stream that has sent its local close.
The audit searched declarations, assignments, transitions, sentinel values and
their consumers; a name match alone was not sufficient.

The following remain ordinary data:

- Error `Stage`/`Phase` labels, immutable modes and options, parsed properties,
  and returned progress, cleanup and failure receipts. These describe an
  operation or input; a controller does not advance them as its phase.
- Counters, offsets, byte lengths, identifiers, arithmetic accumulators and
  hashes. A queue's sequence number includes its generation, not just a
  full/empty state. Synchronization counts and memory orders retain that role.
- Runtime-generated regex automata and compression entropy tables. Their
  numbered nodes are explicit, input-dependent automaton data, rather than a
  fixed hand-written control switch. Their owning controllers use machines.
- `ext::settings::ChildState`, which selects a provider implementation. Its
  variants do not transition into one another; each contains its provider's
  iterator. Similarly, `Option<T>` remains appropriate for optional stored
  data. Where presence also governed a lifecycle, such as a child process's
  observed/reaped status, that lifecycle now has a machine.
- Local verdicts and reductions, such as whether any element matched, whether
  an arithmetic result rounded up, or whether an output record is valid.
  These compute a result rather than retain a phase for subsequent operations.

This distinction also applies to boolean snapshots returned by a machine.
Replacing the authoritative phase does not require changing a public result
record's boolean observations.

## Shared machines

| Module | Machines and purpose |
| --- | --- |
| `core::iter_state` | `Completion`: active or exhausted/finished. |
| `core::lifecycle` | `Lifetime`: active or released; `Health`: healthy or failed, with explicit reset. |
| `core::parse_state` | `Sequence`: first item, separator, required item; `PairPhase`: key/value; `Quoting`: unquoted/single/double; `IntegerProgress`: initial, signed/started, zero, prefix, digits and trailing whitespace. |
| `core::stream_state` | `Delivery`: feeding, ready, ended, ended with a retained item, or failed. |
| `core::io_state` | `DuplexTurn`, `Readiness`, `PendingWork`, `Registration`: alternating work, would-block waits, queued work and listener registration. |
| `core::utf8_state` | `Sequence`: partial UTF-8 bytes in state payloads, ready or invalid. Its policy preserves deferred scalar rejection in JSON/CSV and immediate prefix rejection in WebSocket. |
| `std::temp_lifecycle` | Temporary-file/directory lifecycle, including cleanup pending with or without a named entry. |
| `std::sync_state` | Local transition plans for mutexes and once initialization, sticky flags and the MPSC receiver endpoint. |
| `ext::http2_lifecycle` | Independent local/remote end-of-stream states and sent/received GOAWAY states. |
| `ext::unicode_break_state` | Regional-indicator parity used by grapheme, word and line segmentation. |

Generic iterators and owners keep generic values in their existing storage.
Their non-generic control machines describe that storage's role. This follows
the language's current non-generic machine declaration support; it does not
add a second state enum or a compatibility wrapper around the old controller.

## Converted families

| Family | Control represented by machines |
| --- | --- |
| Core iterators, text, slice and path | Exhaustion; chain sides; skip/stride phases; lookahead cache; nested iterator activity; index exhaustion; split and leading-path phases. |
| Core/alloc I/O, buffers, arithmetic and arenas | Closed/faulted/EOF latches, arena ownership, arithmetic-workspace failure, local lexical progress and integer-reader phases. |
| Files, processes and threads | Atomic publication and sync milestones; temporary ownership and cleanup; directory/walk progress; process observation/reaping/lost authority; command-capture input/output; thread joins; worker slots; scoped allocations and io_uring transfer slots. |
| Synchronization and test support | Mutex and Once transitions, cancellation/deadline flags, MPSC receiver closure, test-run selection/finalization/error state. |
| Structured data | CSV field/record/encoding phases; JSON lexical, number, container and emission phases; CBOR/MessagePack delivery and key/value phases; TOML table definitions and emission; YAML key context; DER OID arcs; form pairs; Pratt operand/continuation state; PNG image-data ordering. |
| Compression | DEFLATE encoding and decoding, wrapper framing, XZ framing/index/LZMA context, Zstandard encoding and decoding, initialization and terminal phases, WebSocket compression framing. |
| Networking | HTTP framing and body parsing; client/server exchange stages; HTTPS retry/shutdown; HTTP/2 half-closes, GOAWAY and request slots; HPACK ordering; service/proxy transport scheduling; WebSocket upgrade, fragments, UTF-8, close and output phases; URL parsing. |
| CLI, text and Unicode | Option/command selection, response preparation and quoting; text-output failure/exhaustion; cat/uniq/tr/wc/sort phases; Unicode grapheme, word, sentence, line and casing context; local delimiter and scanner milestones. |
| Extended owners | SQLite statements, archives and extraction reservations, graph/schema workspaces, key/value logs, regex/search builders and cursors, diff/patch output lifecycles. |

The declaration inventory is generated in [docs/api](api/README.md). To inspect
the machine declarations directly:

```sh
rg -n '^(pub )?machine ' stdlib extended/ext -g '*.lani'
```

Small independent lifecycles use separate shared machines. Related flags that
formed one protocol now use a combined state: for example `ChainPhase`,
`Delivery`, `Closing`, `WritePhase`, `ProcessLifecycle` and the Unicode suffix
recognizers. Variable data, such as a worker PID or an observed process exit,
is carried in state payloads where the language permits it.

## Atomic storage and ownership

Shared atomic words remain shared atomic words. A `std::sync_state` machine
observes a local snapshot and proposes an expected word, desired word and
action. The native compare-exchange commits that proposal. A failed comparison
discards the proposal and reads again. Native atomic ordering and futex
wait/wake calls still establish synchronization; an ordinary machine mutation
does not replace them. The MPSC receiver retains its atomic exchange at close.

Worker slots now store `WorkerSlot` values instead of encoding joined PIDs as
negative integers. Allocation and deallocation use `size_of<WorkerSlot>()`.
io_uring transfer slots similarly hold `TransferPhase` values; the scratch
storage retains byte counts and sequence numbers.

Machines do not add linear ownership or automatic destruction. Copies of
owners still alias native handles and backing. Existing borrow, join, close,
destroy and transfer requirements continue to apply.

## Source API changes

Generated state types replace the old manually maintained state types. In
particular:

| Former interface | Current interface |
| --- | --- |
| `ext::sqlite_statement::State`, `start`, `transition` and `Move` | `Statement`, `statement_start`, `StatementState`, and `Statement.step(Event) -> bool`. |
| `std::atomic_file::State` | `std::atomic_file::LifecycleState`. |
| `std::temp_file::State`, `std::temp_dir::State` | Shared `std::temp_lifecycle::LifecycleState`. |
| `std::command_capture::StreamState` | Generated `OutputStreamState`; `InputState` is also generated. |
| Direct child-process `cached`/`observed` fields | `ProcessLifecycle` state payloads, queried through `cached()`/`observed()`. |

In-repository consumers and fixtures use the current interfaces. No legacy
aliases are added. Other exposed implementation fields that held phase flags
now hold machines; applications should use the owner's operations and queries.
Struct sizes can change, so callers must derive allocation sizes from types.

SQLite's Lean extraction follows the actual native machine. The four existing
proofs still establish row-only column access, finalized absorption, finality
after a finalize event, and refusal of other operations after finalize. They
do not establish the correctness of SQLite's native implementation or prove
every new library machine.

## Verification

Checks use the existing `stdlib` and `extended` integration binaries, focused
by module. GPU code generation runs on hardware and is serialized. The new
`extended_zstd_execution` module runs the existing independent Zstandard oracle
against `/usr/bin/zstd`, including chunk boundaries, concatenated/skippable
frames, malformed data and encoder interoperability. It is registered in
`tests/suites/extended.rs`, not as a separate test binary.

Recorded groups from this migration include:

| Check | Result and scope |
| --- | --- |
| Integer stream/file readers and concurrency | 81 passed; one source-inventory test fails because it expects a runtime case for `std::file::open`. Includes signed/unsigned binary/hex/decimal cases and worker/channel/io_uring execution. |
| Child/process/capture/group ownership | All 11 passed, including observation before reaping, ECHILD, cancellation and native fault models. |
| Test runner | All five development-support tests passed. |
| CSV, JSON stream, CBOR stream, schema, Unicode casing, WebSocket | 29 passed in the combined batch. The five additional server-poll tests stop at the allocation-profile assertion described below. |
| Archive extraction, HTTP client/server, HTTPS fetch, text sort/tr | 31 passed in the combined batch, including all 11 archive-materializer groups. The five other failures are the HTTP syscall-count assertion, XZ and URL checks listed below. |
| CBOR, DER, form and TOML parsing | All 26 focused tests passed. |
| Unicode segmentation, CLI response and HTTP cursor | All 15 focused tests passed, including official grapheme, word and line vectors. Sentence vectors passed in their separate group. |
| MessagePack, HTTP/2 request slots and TLS | All 13 focused tests passed with `msgpack` installed in an isolated Python environment. |
| HTTPS, PNG, Pratt, decimal, merge and TOML streaming | All 26 final parser/codec tests passed. |
| Shared-helper consumers | 18 stdlib tests passed for line I/O, exact decimals, parallel checksums and path helpers; 32 extended tests passed for DER, glob, HTTP agent, settings and patch behavior. |
| Final network slot controls and text cat | All 11 passed after replacing HTTP/2 taken/completion and queued-flush markers and the multiplexed-member sentinel. |
| CLI commands, JSON, text tail/wc and WebSocket service | All ten passed. |
| Key/value log | Independent oracle passed 300 model cases, 600 crash cases and 40 CLI sessions. |
| Zstandard | New integration test passed its independent quick oracle, including encoder probes. |
| CLI and YAML standalone oracles | CLI: 526 model cases, 342 getopt agreements and seven help cases. YAML: 87 agreements, 32 expected differences, 56 errors, 12 limits and 160 generated cases. No unexpected disagreement. |
| SQLite lifecycle | All state/event cells matched the independent model; regenerated extraction and the four Lean proofs checked. The final Lean/native differential comparison passed 120 cases with zero mismatches and no non-returning cases. |
| Final path, iterator and parallelism consumers | All 11 tests reported success. The test process then hung during shutdown and was terminated; this is not a successful harness exit. |

These are focused receipts, not a claim that the entire workspace test suite
passes or that every target has been tested. Earlier groups cover iterator,
buffer, owner, service/proxy and codec behavior; a later representation change
is checked again where it affects the exercised path.

### Outstanding validation limits

- Atomic-file and server-poll allocation ledgers require the historical
  `MAP_32BIT` allocator profile. The current runtime returns full-width
  mappings, so those checks reject the profile before completing their fault
  schedules. Some CSV-writer, archive-index and TLS allocation checks have
  related runtime-recognition limits. Their assertions were not weakened.
- The XZ oracle reports 23,217 agreeing cases and 134 disagreements, principally
  malformed LZMA-alone header acceptance. The original source reproduces the
  header disagreements. Encoder, chunk-size, concatenation and ordinary
  decoder cases run; this receipt is not a clean oracle pass.
- The original sources reproduce the sed in-place `$=` ordering difference
  (`X\n2\nb\n`) and the URL caret-escaping and Unicode/Node classification
  mismatches. URL's IDNA-generation test also has a 500 ms timeout.
- The unchanged HTTP-server native oracle assumes exactly two pre-accept
  `sendto` calls, while its current fixture can send the complete request in
  one call. The HTTP-rewrite summary expects 11 cases while its probe prints
  13. These gates are not counted as passing.
- The parse-model fixture still hits nested generic inference at line 47;
  the original `ext::parse` source reproduces it. Two iterator assignment
  fixtures reference the former `core::iter::Mapper` path. Neither is evidence
  of successful execution of the corresponding test.
- Some GPU test processes remain alive after printing their complete test
  summary. The final path/iterator/parallelism process was terminated after
  its successful summary to release the GPU lock. SQLite differential testing
  used direct compiler invocation because the local daemon wrapper referenced
  a missing log directory; the compared source and cases were unchanged.

Useful reproduction commands (additional native dependencies are documented
by each module's guide):

```sh
cargo test --release --test stdlib -- stdlib_concurrency_execution:: --test-threads=1
cargo test --release --test stdlib -- stdlib_command_execution:: stdlib_command_group_execution:: stdlib_command_capture_execution:: --test-threads=1
cargo test --release --test extended -- extended_zstd_execution:: --test-threads=1
python3 -I formal/tools/lani_extract.py --check sqlite
cd formal && lake build Lanius.Machines.SqliteStatementCorrect
```
