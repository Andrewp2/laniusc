# Reusable regex storage and token scanning

Status: the selected reusable-storage increment is accepted on native Linux
x86_64 after archive checkpoint `aab5c5f2`. The contracts and finite execution
receipts below cover this increment. The full standard and extended library
goal remains open.

## Intended result

Reuse the canonical regex engine's storage across searches and token rules.
Provide capture results in reusable storage and copied whole-match spans.
Migrate token scanning, splitting and replacement to those interfaces. Keep
matching priority, Unicode boundaries, full-input assertions, empty-match
progress, resource limits and explicit failures consistent across consumers.

Before this increment, `Regex.search` created nine scratch vectors on each
call. Its returned Match took the candidate vector; the lexer destroyed that
owner after reading group zero. The historical 4,096-token lex-scan observation
recorded 36,887 whole-process allocation requests. The current receipt below
uses stricter source provenance and records its own requested-byte scope;
these separate runs are not a controlled timing comparison.

The algorithm authority remains [Cox's ordered Pike VM](https://swtch.com/~rsc/regexp/regexp2.html)
and the existing dialect guide. Captures record past execution without affecting
future transitions in this dialect. [Go's regexp executor](https://go.dev/src/regexp/exec.go)
also traverses capture instructions whose slots are outside the requested
capture range. Those properties support a two-slot whole-match mode here;
Lanius must still execute and charge each Save instruction, preserve its
successor and retain ordered first-arrival state deduplication. No backreference
or new syntax support is introduced.

## Storage and ownership

| Owner | Contract |
| --- | --- |
| `regex::Workspace` | One manual owner of nine fixed-capacity scratch vectors. It retains no Regex or input backing. Reuse across programs is allowed within its state/group capacities. |
| `regex::Search` | One manual cursor owning a workspace and borrowing the compiled Regex and validated Input. It supplies canonical search progression and reusable capture inspection. |
| `regex::Matches` | Convenience cursor over Search, returning independent owned Match captures when requested. |
| `lexer::Cursor` | Borrows compiled rules and immutable input; owns one whole-match workspace for a nonempty input. Distinct scan calls own independent workspaces. |
| `regex_text` search | Lazily owns one canonical Search after its first admitted attempt. Split/literal replacement use whole-match mode; templates use all captures. |

Shallow copies alias one owner. Cursor copies cannot advance or release
independently. Borrowed input must physically back its validated metadata and
remain unchanged. Copied Span values contain offsets; lexer Tokens and split
fields borrow input, never scratch. Their validity does not end with scratch
reuse or destruction while the input owner remains live.

### Fixed workspace

`workspace(states, groups)` accepts state capacities 1..65,536 and group
capacities 1..129, including group zero. Invalid dimensions or checked storage
arithmetic return `Limit(0)`. A failed allocation returns `AllocationFailed`
after releasing the complete partial owner. Search never grows or reallocates
the workspace. Callers choose their maximum program dimensions before the
repeated operation; a lexer already knows those dimensions from its rules.

For S state cells and C = 2 × group-capacity capture slots, the nine vectors
contain 4S + 3SC + 2C i32 elements. All element products, per-vector byte limits
and the requested byte sum must be checked before allocation. `owned_bytes`
reports requested source bytes using the actual element size. It excludes
input/program owners, allocator/kernel state, stack and RSS. Whole-match mode
needs C = 2 even when the compiled regex declares subgroups.

Workspace inspection includes state/group capacity, requested bytes, last
attempted VM work, published group count and copied `span(group)` values.
Every search attempt invalidates the previous result before start/capacity
checks. It resets work/failed state, active state/slot dimensions and list
counts, and clears the current program's active seen range. Active row stride
is consistent within one search, independent of reserved capacity and previous
list swaps. None and errors publish no captures.

`find_with` and `longest_prefix_with` publish full captures and return bool.
`find_span_with` and `longest_prefix_span_with` return copied Option<Span> using
two active slots. They accept validated Input plus a scalar-boundary start.
An insufficient workspace returns `WorkspaceTooSmall` without allocation or
VM execution. A destroyed workspace has zero capacities and produces the same
capacity error. Bounds errors and capacity errors leave the storage reusable
for a later valid search. Explicit destruction releases once, invalidates
results/capacities and preserves the last measured work for inspection.

## Canonical iteration and terminal results

`Regex.capture_iter(Input)` and `Regex.span_iter(Input)` construct a Search
owning the appropriate fixed workspace. `Search.next` returns Option<Span>;
`span(group)` reads the current result. It retains the existing unanchored,
leftmost-first policy and advances one Unicode scalar after an empty match.
Longest-prefix probes retain their separate anchored-longest policy in the
same VM.

None, error and explicit destroy fuse a Search and release its scratch once.
A successful final empty match at EOF remains readable: mark the cursor done
but retain its captures until the next attempt or destroy. A later fused next
releases that remaining scratch without another VM search. Repeated terminal
calls perform no allocation, release or matching and preserve measured work.

`find_iter(Text)` validates input and returns Matches over full-capture Search.
Each returned Match has independent captures, so it can survive later cursor
calls. One-shot owned find/prefix APIs use the same VM and may transfer the
candidate vector immediately before releasing their other temporary storage.
These ordinary convenience APIs serve callers needing independent results.
In-repository users and documentation move directly to the new ownership
contract; there is no separate fork/copy compatibility engine.

## Lexer and bounded text consumers

Lexer scan preserves validation order: scan limits, logical Text bounds, input
byte cap, UTF-8. Nonempty input then creates a group-one workspace sized to the
largest actual individual rule program. Empty input needs no workspace.
Constructor OOM is `lexer::AllocationFailed` before a cursor exists, with zero
usage. Other constructor failures remain typed `lexer::Workspace(regex_error)`.

Every normal token-selection step performs no scratch allocation or release.
EOF, error and explicit destroy release the cursor workspace once and fuse.
Terminal releases are allowed; the acceptance claim is zero source allocation
during all next calls and zero allocation/release during nonterminal selection.
Maximal endpoint, declaration-order ties, positive versus empty winners,
completed skips, later-rule failures and token/step admission stay unchanged.
Before each rule call, reserve its complete configured regex work allowance.
Per-call workspace work resets; aggregate lexer usage remains monotone.

Regex-text validates input and the complete replacement template before output
effects. It checks terminal/match truncation, call cap and aggregate work cap,
then charges the attempt before lazily creating its canonical Search. Therefore
zero matches or refused search admission need no scratch allocation. A failed
constructor remains a charged attempt. Templates consume captures before the
next attempt or release, including final empty EOF captures. Regex-text
contains no duplicate scalar-progress or regex engine implementation.

VM work still counts state visits and tested class terms. Initialization,
capture copying, seen clearing, Unicode table lookup and allocator cost retain
their separately bounded dimensions; VM work is not total CPU or wall time.

## Selected acceptance

Use executable Lanius programs with independent Python matching/fixture
producers and host ownership observations. Production remains Lanius. Root
serializes GPU compilation and native execution; commands have deadlines below
two minutes. The selected target is native Linux x86_64 emitted by the GPU
compiler, with no new user GPU-kernel or other-host claim.

- Compare full captures and span modes with the existing independent models.
  Reuse storage across different program sizes/capture counts, list-swap
  parities, hits, misses, WorkLimit and valid recovery. Check nonzero/strided
  UTF-8 and invalid scalar starts, stale-result invalidation and exact bounds.
- Deny every reached workspace-constructor allocation using verified runtime
  instruction sites and full-width requested mappings. Check partial-owner
  release, preserved borrowed owners and successful later operations. Reject
  larger programs explicitly, then reuse the same storage for smaller ones.
- Observe zero source mappings/releases in explicit workspace search phases;
  zero mappings in lexer next calls, with exact terminal releases separately.
  Inspect live owners before exit and distinguish independent cursors.
- Preserve regex, lexer and regex-text semantic models, error precedence,
  aggregate work accounting, empty progress and output failure behavior. Move
  existing OOM assertions to the actual new constructor/search boundaries.
  Historical allocation floors/distributions are not acceptance requirements.
- Exercise real lex-scan output in both modes and all reached application
  allocation failures. Repeat its 4,096-token observation with exact output,
  verified requested-byte/owner counts and timing scope. Make no compiler-speed
  comparison or universal throughput claim.

## Accepted execution

All **23 selected Rust driver tests** now have passing native receipts across
the separate invocations below. Test counts, model inputs and native process
counts are different units; they are not added together. All commands had an
outer 100-second deadline. No whole-suite, other-host or user GPU-kernel
execution is claimed.

| Gate | Accepted scope | Receipt under `target/stdlib-work/` | Seconds |
| --- | --- | --- | ---: |
| Workspace contracts | One native ACK fixture: capacity/reset/recovery, UTF-8 views, cursor/capture lifetimes and zero-allocation reuse | `regex-workspace-contracts-first.log` | 6.12 |
| Workspace construction | Baseline plus all nine reached constructor OOM processes; exact partial-owner cleanup | `regex-workspace-model-and-oom-first.log` | See note |
| Workspace model | 839 full/span/longest/reuse cases in one persistent native process | `regex-workspace-model-exhaustive-offset-retry.log` | 6.99 |
| Existing regex regressions | Both tests: independent reference, Unicode/limits, views, owned captures, bounds and fused iteration | `regex-workspace-existing-regressions-first.log` | 10.50 |
| Lexer ownership/admission | Three tests: independent/interleaved cursors, held tokens, no next-call allocation, typed construction/admission errors | `lexer-workspace-owners-contracts-admission-first.log` | 12.79 |
| Lexer models/failures | Three tests: 576 independent cases, 63 explicit tables and all 30 reached OOM positions | `lexer-workspace-model-tables-oom-first.log` | 11.88 |
| Regex-text lazy/model/tables | Three tests: lazy two-slot/full-capture storage, 288 independent cases and 89 explicit tables | `regex-text-workspace-lazy-model-tables-first.log` | 12.70 |
| Regex-text contracts/failures | Two tests: views/owned output/budgets and all 41 reached library OOM positions | `regex-text-workspace-contracts-oom-first.log` | 11.36 |
| Regex-replace CLI | Two tests: nine binary cases, 14 rejections/help, all 25 reached OOM positions and read/write EINTR/EIO | `regex-text-workspace-cli-first.log` | 10.89 |
| Lex-scan behavior/I/O | Three tests: 124 grammar inputs in both modes, boundary/admission/nonpublication cases and scripted production I/O | `lex-scan-workspace-behavior-io-first.log` | 13.63 |
| Lex-scan failures/cost | Two tests: all 30 reached OOM positions in each mode, I/O faults, publication prefix and the 4,096-token observation | `lex-scan-workspace-faults-cost-first.log` | 16.66 |

The constructor campaign's 9.19-second invocation also contains the first
model fixture admission failure, before model execution. Its constructor test
passed; 9.19 seconds is not a constructor-only timing or an all-pass result.
A second model fixture form also failed admission. Exhaustive error-offset
arms then admitted the same 839 model cases. These fixture/compiler failures
and exact source identities remain in the
[workspace fixture guide](../tests/fixtures/extended/regex_workspace/README.md).
The existing base-regex OOM subprobe uses its legacy accounting; strict
workspace ownership evidence comes from the new constructor and ACK gates.

Separate CPU resource-oracle controls passed: 24 workspace controls, 30
lexer/application controls and 11 regex-text controls. They check provenance,
phase and failure-binding rejection; they are not native execution receipts.

### Resource observations

For the same `(a)(b)?` regex, the regex-text lazy gate records nine requested
source mappings totaling **416 bytes** in span mode and nine totaling **928
bytes** in full-capture mode. Later split/search steps reuse that storage;
replacement retains no per-result Match owner. These are measured dimensions,
not constant sizes for arbitrary programs.

The real lex-scan counts program emits exactly 4,096 tokens with **32 verified
source mmap requests**, **8,895 total requested bytes**, **6,868 peak live
requested bytes** and balanced explicit releases. Its observed traced wall
time is **79.624585 ms** for the traced correctness/cost harness, including
temporary input/rule setup, the whole native process, trace reading and output/
verified-ledger checks. The native process includes rule compilation, scanning
and output; application compilation had already occurred in the earlier test
of that combined invocation. Requested bytes exclude kernel allocator state and
RSS. No fresh historical baseline was run and no timing ratio or compiler throughput
claim follows. The application guide records the exact syscall fault scope,
including logical retirement when strace skips an injected close.

### Compiler dependency and frozen sources

The first complete regex module used ten new `?` expressions and failed GPU
lowering with SSA-dominance reason 17, even from an unused-import entry. Six
small controls pass; a single causal construct has not been isolated.
Replacing those expressions with equivalent explicit checks admits the module
without changing its API, matcher, error order or ownership. The
[versioned reproduction](../tests/fixtures/stdlib_compiler_state/regex_workspace_admission/README.md)
restores the exact failed module in a temporary source root. It remains a
compiler dependency, separate from accepted propagation in other library
modules. This increment changes no compiler production source, IR, extractor,
formal proof or ABI.

| Accepted production source | SHA-256 |
| --- | --- |
| `extended/ext/regex.lani` | `4520d1fc663432af975dd774d07da0f3b747f2164c2465b8e62ff4b6b08e1659` |
| `extended/ext/lexer.lani` | `9eddce441eaed36cb38dc9eebbc6f332a4c1df173107b484c1ede1282508c8ab` |
| `extended/ext/regex_text.lani` | `bc9f87b7cebba2545238867d0a45ad9a7feba986ac6ecf832be1484a0b4b9d3c` |
| `sample_programs/library/lex_scan.lani` | `7454037c6cbdd7f46227611c5b4a317b57ec9e168c525233e1971465f05ea10c` |

The semantic guides, inventories and generated references describe these
contracts and target limits. This increment does not finish the other library
families in the [roadmap](library-roadmap.md).
