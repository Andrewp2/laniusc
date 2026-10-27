# Portable response grammar and expansion verification

Status: both focused semantic gates passed on their first attempt, together in
8.93s after a separate 3.37s Rust build. The reused pure contract also passed the
all-syscall/all-mmap-denied observation below. CPU controls and scoped independent
reviews are complete. Native Files-provider and allocation/FD-resource
acceptance are recorded separately in [the native fixture guide](files_README.md),
and application acceptance in [the KV guide](../../../../docs/extended-kv.md#current-application-receipts).
The overall standard and extended library goal remains open.

## Scope and independent expectations

`contracts.lani` imports actual `ext::response`. `model.lani` imports actual
`ext::response`, `ext::cli_response`, `ext::cli` and `ext::cli_commands`.
`ScriptProvider<HostError>` is a caller-defined public Provider implementation
with a nominal error payload. Each successful load transfers an independent
Vec copied from test-peer bytes. It normally respects the actual granted cap;
one explicit profile deliberately returns an oversized successful Vec to check
ProviderContract. This is not a native filesystem provider or a substitute
cryptographic/host implementation.

The Python peer contains explicit decoded bytes, raw spans and byte mappings
for the finite grammar/file contents. It does not tokenize arbitrary strings.
For healthy expansion it walks that authored include tree, recording every
source occurrence, including token, provider path/grant and final output. Error
and limit cases state their expected cause, exact origin, retained snapshots
and calls explicitly. The reference does not copy the production owner's
Vec/frame/offset state machine. Binary framing belongs only to these tests;
no product transport or JSON layer is added.

## Pure byte contracts

Six literal success profiles cover empty/separator-only inputs, mixed ASCII
separators, adjacent bare/single/double quoted pieces, empty quoted tokens,
escapes inside/outside both quote types, escaped literal newline, raw 128/255 and
literal `#$*~`. Six malformed profiles check exact NUL, trailing-escape and
unclosed-quote offsets, including escape precedence over an unclosed quote.

Each success profile runs with native negative byte stride and packed positive
byte stride, using live stack backing, nonzero logical starts and actual
negative Span stride. Required output prefixes are checked byte-for-byte;
prefixes, unused tails and whole untouched spans are checked. The fixture tests
zero/exact/one-short capacities and full syntax preflight before mutation, plus
negative starts/counts and overflowing logical ranges. It does not claim to
validate forged physical backing or runtime overlap detection.

Every decoded offset and endpoint is checked against literal raw maps.
Negative/past-end decoded offsets, no token, leading/trailing separators and
multiple tokens are rejected. Empty quoted tokens map to their raw endpoint.
The contract program has no intended host service or allocation. Both its
ordinary native run and reused-ELF syscall/allocation-denial observation are
accepted below; the latter is not inferred from source inspection.

## Finite binary model

One native process receives 96 bounded records:

- 17 grammar goldens, with exact shapes, decoded bytes, spans and every raw map.
- 10 malformed grammar records, with exact error categories and offsets.
- 69 expansion/error/limit records.

The expansion records cover literal `@`, one-prefix `@@` removal without a
second expansion, ordinary argv retaining quote/backslash bytes, empty and
nested files, depth-first ordering, repeated file occurrences, quoted/escaped
directives, filename `-`, non-UTF-8 paths/content and cycles bounded by depth.
Input directives and empty file tokens count toward max_tokens even when they
emit nothing or have zero decoded bytes.

Every signed limit has a negative admission case. Categories also exercise zero
and relevant exact/one-below boundaries: argument count/bytes, decoded token
count, output bytes, file bytes, aggregate source bytes, file count, depth, path
bytes and work. Exact work/grant cases distinguish initial bulk charge, file
charge, four units per raw file byte, decoded token charge and final descriptor
charge. The provider receives the minimum file/source/work grant; a provider
error caused by a lower grant remains the original nominal error. FileLimit
means file-request count, not a separate file-byte error.

Initial NUL and invalid descriptor/limit cases assert no provider call and no
published partial argv. Four additional executable logical-bounds controls run
before the records, checking outer argument bounds and invalid token descriptors
at a known original index. Loaded-file syntax/token/work failures retain the
loaded source; provider failure/oversized success retain an unloaded request
record with its path. A file's late oversized token rejects before any earlier
child directive in that file can call the provider.

After every first prepare, the probe attempts a second prepare with invalid
limits and checks inert InvalidState. It then overwrites the entire peer input
buffer before reading results. Output arguments, original argv, source paths,
raw files, inclusion origins and every locate byte/endpoint must still match
independent snapshots. Locate bounds/readiness/work failures are checked.
Destroy is called twice; captured views are no longer used. The same owner is
then prepared with empty argv, checked ready/empty and destroyed twice again.
This checks manual-owner behavior; no allocation/FD provenance or arbitrary
owned-H destructor claim is made by this portable semantic gate.

Four records feed the same expanded argv into both actual parsers. Expected
option/command/operand events and original expanded locations are explicit.
They cover required values supplied by files, `--` consumed as a required value,
actual terminators, expansion after a terminator, `@@` literals and quoted error
positions. The actual Token command ID is checked before serialization. Parser
error locations are translated to exact retained raw source bytes via locate.

## Bounded execution and CPU controls

Root serializes compiler/native commands; the fixture author performs only CPU
or static work. The two filters are:

```text
response_byte_grammar_preflight_raw_mapping_and_strides_execute
expanded_arguments_provenance_limits_snapshots_and_both_parsers_match_finite_model
```

Driver: `tests/extended_cli_response_execution.rs`. A future focused invocation
can build it with `cargo test --test extended_cli_response_execution --no-run`
and run exactly these two filters. The contract executable requires status 0
with empty stdout/stderr; the model peer requires status 0, empty stderr and the
exact complete binary output, then reports `cli-response model cases=96`.
The model's native child has a 20-second deadline; the Rust process deadlines
are five seconds and 30 seconds. The established TempArtifact path validates the
emitted x86_64 ELF before execution. Each root command must stay below two
minutes; no broad old CLI/library rerun is required.

CPU-only command:

```text
python3 -B tests/fixtures/extended/cli_response/model.py --self-test
cli-response model CPU controls passed
```

Controls validate every authored lexical map against its raw bytes, token/span
and endpoint invariants, fixed record lengths, healthy work/source bounds and
same-case byte mutations against their own complete expected frame. Changed
bytes must be rejected without relying on a length mismatch against a different
case. These CPU controls do not execute Lanius or establish runtime behavior.
All four new source/driver files were explicitly checked for trailing whitespace,
including untracked files, before first execution.

## Frozen files

| File | SHA256 |
| --- | --- |
| `contracts.lani` | `73c92829cf2c286a53bb579ca6dc2111082b2e905660382850311866683c9b43` |
| `model.lani` | `4583374bf200863a7ac7fd8f210cba96d53bffc610d5bb72fcc97c9985237b2b` |
| `model.py` | `831f9430a599eda8c421e19a1a98f106259c8cfd030a6a9729fce973835ad3ec` |
| `tests/extended_cli_response_execution.rs` | `4b25729d195d9d58c250457a04e2f067490b71b757c07d7ab2efedaf2a360451` |

These are the exact source hashes executed in the accepted semantic gates below.
Native Files-provider behavior, source allocation failures, ownership/FD
ledgers and application acceptance have separate receipts in the guides linked
above. This semantic acceptance establishes Linux x86_64
CPU executables emitted by the GPU compiler; it establishes neither user-program
GPU execution nor another host/backend. No successful type check alone is
accepted as evidence that an API works.

## Actual first semantic receipts

`target/stdlib-work/response-semantics-first.log` records the Rust driver build
in 3.37s and both tests passing together in 8.93s, with no fixture or production
correction. These are separate build and combined-test durations, not per-test
timings. The first test executed the pure contract assertions. The second ran
one native model process with all 96 records (17 grammar, 10 syntax, 69 expansion)
and required the complete expected binary receipt, empty stderr and status 0.
The source hashes in the frozen table above are unchanged. The test binary is
`extended_cli_response_execution-c0ffed8c77221bb8`.

| Retained executable | ELF SHA256 |
| --- | --- |
| `/tmp/cli_response_native_model_lani_553596_0` | `13accaeed213f621a01a911ca150e64c48cdf346a7c82c8a0a906090c004316d` |
| `/tmp/cli_response_native_contracts_lani_553596_2` | `d13583182fb0f3b74533b21f71e66eb371e252ee2acfd5968f4ba052869210bd` |

The fixture author performed no compiler, Cargo or native execution; those
receipts are root's serialized gates. No repeated smoke registration or broad
old-library rerun was required. Native filesystem/error/ownership and KV consumer
acceptance are not inferred from these portable ScriptProvider results.

Independent read-only grammar/preflight/canary review completed without a
material finding; that reviewer performed no execution. The separate independent
model/driver review closed without a material finding on the exact frozen
`4583374b`/`831f9430`/`4b25729d` hashes. Its scope was finite reference independence,
provenance, work/provider grants and failure origins, post-input-clear snapshots,
nominal H transfer, both parser receipts and the strict TempArtifact validator
path. The model reviewer did not review the pure contract or native provider
and performed no edits, tests or native execution. Neither review establishes
allocation-fault, native-filesystem or application coverage.

Accepted production SHA256:

- `ext::response`: `a997585cd691edf2d53781410568da8c72a65dfe4edb45b2502f8d7bdc6d05b7`.
- `ext::cli_response`: `35b6ee8391724450976aa765e279015cb2fab391bc80c608d1009a21f5895a09`.

## Actual pure-contract observation

Root reused the accepted `d1358318...` contract ELF with all syscalls traced and
all mmap calls denied (`trace=all`, `inject=mmap:error=ENOMEM:when=1+`). The
process exited 0 with empty stdout/stderr. The complete
`target/stdlib-work/response-contracts-no-host.trace` contains only successful
launch `execve(...)=0` and final raw `exit(0)=?`; its corresponding
`response-contracts-no-host.log` is empty. No mmap was attempted, so no injection
was reached. This is finite no-host/no-allocation evidence, not OOM recovery or
a proof for all inputs. No fresh GPU compile or unrelated rerun was required.

The model executable deliberately uses stdin/stdout and is not included in the
pure-program claim. Native Files-provider, allocation-error/FD ownership and
real application behavior retain their separate acceptance campaigns; no result
for them is inferred from the portable ScriptProvider tests above.
