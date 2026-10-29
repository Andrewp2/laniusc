# Resumable TOML serialization

Starting point: `e9d1c8df`, with the full standard/extended-library goal active.
The preceding text matching/replacement increment is tested and pushed. This
increment removes complete output staging from TOML caller-buffer encoding and
the existing `toml_normalize` consumer. Parsing and value queries stay outside
the change. Production implementations remain Lanius.

## Shared contract

Use one constant-storage byte machine over the document's parent/first/next
links for all serialization. Preserve the existing deterministic bytes and
TOML 1.1 semantics, including quoted keys, root lines, nested inline containers,
canonical stored numbers, signed zero, exact fractions, inserted seconds,
uppercase T/Z, +00:00 becoming Z and distinct -00:00. The normative format is
[TOML 1.1](https://toml.io/en/v1.1.0). Keep partial escape, UTF-8 and temporal
positions; scan/trim a fraction once per traversal, regardless of read sizes.

Public API:

```text
Document.encoded_len() -> Result<u64, Error>
Document.encoding() -> Result<Encoding, Error>
Encoding.borrow() -> &Encoding
Encoding.remaining() -> u64
core::io::Read for Encoding
encode(document) -> Result<String, Error>
encode_into(document, output:View<u8>) -> Result<i32, Error>
```

Replace the free `measure` function and migrate internal users. No known human
consumer requires a duplicate alias. Keep owned and caller-buffer operations
because their ownership/error contracts are useful and distinct.

Let W be emitted bytes + nonroot node visits + scanned fraction digits +
trimmed trailing-zero digits. Measurement admits W. Reader construction,
owned encoding and caller-buffer encoding admit 2W for preflight and replay.
This is a serializer-work bound; allocator/collector operations and host calls
are not charged by it. Old encode admitted W and old encode_into admitted
2W + output bytes. Document this deliberate change, including CLI effects.
Parsing has its separate existing budget; max_work is not process-cumulative.
Within preflight, the first exhausted bound in generator order wins. Each byte
checks the output cap before charging its byte work; node/fraction work is
charged where encountered. This can differ from the old scalar/raw-chunk
checks when both limits are insufficient. No whole-pass output-over-work
precedence is promised. Cursor copies fork their replay allowance rather than
sharing a cumulative meter.

Preflight returns exact length and W without allocating. Reader construction
reserves replay work before returning. A valid positive Read fills exactly
min(request, remaining); invalid logical ranges return InvalidInput before
state/backing changes, even at EOF or with a zero count. Valid zero reads are
inert, EOF is fused, and no TOML/output/work failure occurs during emission.
Cursor copies fork complete state. All document storage remains stable, live
and immutable. Destinations and cursor storage must be backed and disjoint
from document backing and each other. An empty live document emits zero bytes;
a destroyed document is rejected at admission. No forged-tree validator is
introduced. One small read may trigger a whole bounded fraction scan; the
work bound is not a per-read latency bound.

encode_into precedence: logical output metadata, semantic/output preflight,
caller capacity, replay-work reservation, direct infallible fill. Every
returned error leaves the complete destination untouched. It allocates no
temporary output. Owned encode drives the same reader through the existing
alloc::io::read_to_string collector with exact length and ceil(length/1024)+1
calls including EOF; destroy retained partial output on failure. The collector
adopts its Vec, avoiding a second whole-output copy. Empty output allocates
nothing. Preserve source owners on all outcomes.

## Existing normalizer

Preserve option names/defaults/caps, repeated-option last-win behavior,
normal form, --check bypass, and current exit/diagnostic policy. Retire argv
after parsing scalar options and retire input after obtaining the independent
Document. Bound input through the canonical collector at 131072 actual reads,
including its EOF probe. Use Encoding and Copier with 1024-byte scratch and
262144 combined provider calls. That admits the CLI's 64 MiB cap with EOF and
retry headroom. Help/diagnostics allow 64 writes. SIGPIPE ignore failure returns
3. Output failure reports the confirmed written prefix; failed diagnostics
retain the existing status-3 override. No new output-sized owner is created.
Destroy/abort transfer state before document cleanup and diagnostics.

## Ownership and gates

Eight agents: shared machine; owned/caller facades plus caller migration;
normalizer; independent byte/state model; reader/resources; normalizer tests;
documentation; independent review. The machine and facade authors serialize
edits to ext/toml.lani. Root alone runs native/compiler commands, serially
under target/stdlib-work/library-gpu.lock, each outer command at most 100s.

Focused gates: tiny executable admission; exact wire and cursor-state model;
range/cap/work/atomicity contracts; allocation-free borrowed phases and
document identity stability at two sizes; reached owned-output allocation
failures and same-document retry; real normalizer output, bounded faults,
confirmed prefixes and owner cleanup. Run selected existing TOML serialization
and consumer regressions. No broad parser corpus or GPU/performance rerun.
Initial supported receipt target is Linux x86_64 CPU binaries produced by the
GPU compiler, not programs executing on GPU devices. Compiler limitations get
a reduction and dependency report, not compiler changes in this increment.

Protect README.md, AI_POLICY.md, CONTRIBUTING.md, stdlib/std/vec.lani,
stdlib/core/mem.lani and tests/common/mod.rs. Keep guides, inventory and receipts
in docs. Commit/push only the reviewed manifest; verify remote and clean tree.
Completion of this increment does not complete the full library goal.

## Acceptance

All five new library groups passed on Linux x86_64 CPU output from the GPU
compiler, including the 280-case independent wire/state model, exact work and
range contracts, allocation-free borrowed phases at 4 KiB and 256 KiB, and
two reached owned-output allocation failures with successful retries. The
selected existing TOML public-contract test passed separately. All four new
normalizer groups passed (64 cases, including 25 reached allocation denials),
as did the existing semantic/idempotence and malformed/resource-error groups.
Detailed source hashes and finite receipts are in the streaming guide and
dedicated fixture READMEs; no separate standalone CLI-example run is claimed.

Two test-fixture compile failures were corrected: unsupported `else if`
syntax, and a chained generic Read/unwrap call resolved by adding an explicit
Result intermediate and import. The latter's original expression is retained
in the resource fixture guide; its import/inference cause was not isolated.
Production source required no corrections after native acceptance began. No
compiler, ABI, proof or protected-file change was made.
