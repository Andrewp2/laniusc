# Standard and extended library overview

The full library goal remains open. The current
[response-file increment](library-response-files-plan.md) adds pure byte
tokenization, owned provider-driven expansion and an explicit native file
provider. Portable semantic tests, all three public smokes, direct native
provider/resource groups and the focused response-backed KV application group
pass. This increment is accepted on the finite native profile below. The preceding
[command hierarchy and help increment](library-cli-commands-plan.md) is
implemented and accepted on the finite native profile below. Two semantic Rust
tests, pure contract/smoke programs under full syscall observation, a selected
flat-parser regression and three migrated KV application groups pass. The
preceding [ordinary nested-iteration increment](library-infallible-nested-plan.md)
implements `Flatten` and `FlatMap` through the existing nested engine and the
true empty `Infallible` error type. Public admission, two semantic/model Rust
tests, three negative-bound tests, all eight strict-owner cases and the migrated
real `flatten_sum` groups pass on the finite native profile below. The selected
increment is accepted. The preceding
[replacement-sink increment](library-replacement-sinks-plan.md) is implemented
and accepted on the finite native profile below. Two semantic Rust gates,
five negative-bound tests, strict owner/reached-OOM groups and the real
latest-values campaigns now pass, separately from the initial direct smokes.
The accepted
[scan and nested-iteration increment](library-nested-iteration-plan.md) is
implemented through the canonical iterator protocol. Two direct public smoke
programs, three semantic/model Rust tests and all four historical fallible
`flatten_sum` tests pass. All four direct strict-owner groups pass as well;
the selected increment is accepted on the finite profile below. The accepted
[filesystem increment](library-filesystem-completion-plan.md) implements owned
temporary directories, checked link/readlink and permission operations, and a
real `mktemp_dir` program. All 13 selected Rust tests pass across separate
native commands on the profile below; this completes the selected increment.
The preceding [reusable regex-workspace increment](library-regex-workspace-plan.md) is
implemented and passes the selected Workspace/Search, regex, lexer,
regex-text and real-application gates on the native profile below. The preceding
[archive increment](library-archive-extraction-plan.md) adds shared namespace
planning, extraction metadata policy, complete TAR/ZIP preparation, a bounded
materializer and a real [unpack program](extended-unpack.md). The prerequisites,
preparation, direct materializer and finite CLI groups pass on the documented
native profile. The branch is rebased onto `origin/lang`
`0d2e4a07`; the first [language-feature cleanup](library-language-adoption.md)
executes across six library modules and the range-dot application. Item imports,
local inference and selected `?` paths have focused native receipts, with a
nested generic Option compiler dependency retained separately. This adds no new
API family. The preceding accepted increment is
[AtomicFile publication and the key-value application migration](library-atomic-files-plan.md).
[AtomicFile](stdlib-atomic-files.md) and the
[earlier migrated CLI](extended-kv.md#historical-atomic-publication-application-receipts) have finite native
acceptance on the profile below. The accepted TempFile prerequisite and server
evidence retain their checkpoint scope. The
[remaining-work audit](library-roadmap.md#remaining-work-beyond-atomic-files)
keeps the broader standard and extended library work visible.

**Accepted response files.**

[Response preprocessing](extended-cli-response.md) is opt-in and runs before
either existing CLI parser. `ext::response` owns the byte grammar and raw-offset
mapping; `ext::cli_response` retains copied argv and file diagnostics through a
generic provider; `ext::cli_response_files` loads from one borrowed base
directory. Expansion publishes stable argument views only after complete
success. Providers transfer content owners or caller-owned errors; cleanup and
borrowed lifetimes remain explicit.

| Surface | Current finite scope |
| --- | --- |
| Portable semantics | Two Rust tests pass together in 8.93s after a separate 3.37s build. One native model processes 96 records: 17 grammar, ten syntax and 69 expansion/limit cases; a separate pure contract program checks mapping, bounds, canaries and signed strides. |
| Pure programs | The public tokenizer smoke and contract program pass full syscall tracing with mmap denial. Only launch/final exit occur; no allocation attempt is made. This is not OOM-recovery evidence. |
| Public composition | Tokenizer, generic expansion and native-provider public smokes compile and exit zero. The expansion smoke feeds the same final argv to both actual parsers and retains provider-failure diagnostics. |
| Native provider | One direct oracle group passes 39 cases for file admission, fixed-base lookup, actual EOF/byte caps, call budgets and native failure/cleanup behavior. |
| Expansion resources | One direct oracle group passes 31 cases: 29 reached source allocation failures and two baselines. Live ACK checkpoints check source maps/fds; an owned provider error remains usable after Expansion destruction. |
| [Current KV application](extended-kv.md#current-application-receipts) | The response group passes 55 overlapping process cases, including all 18 source allocation denials in its nested-help baseline, one post-database OOM and the published/unsynced status 6 case. The latter cases are included in 55. |

Portable sources are tokenizer `a997585c...` and expansion `35b6ee83...`;
the provider is `461037b8...`. The current application is `789143f6...` with
artifact-aware oracle `057bb27a...`. Receipts under `target/stdlib-work/` include
`response-semantics-first.log`, `response-{public-smoke,contracts}-no-host.{trace,log}`,
the three public smoke receipts linked in the
[module guide](extended-cli-response.md#current-executable-evidence), and
`response-kv-native-artifact-retry.log`. Native receipts are
`response-files-provider-native-first.log` and
`response-files-resources-native-first.log`: 70 overlapping group cases,
not two current Rust-libtest passes. Current resource/KV drivers have separate
combined `--no-run` admission in 2.09s. Native probe `f8a564cb...`, resource probe
`5b28229c...` and reviewed oracle `a472...` retain their exact scope in the guide.
Earlier hierarchy source `f07fd52f...`
and its 130 cases were not rerun on this application revision and are not
added to 55. Native Linux x86_64 CPU output from the GPU compiler is the current
target; no user-program GPU execution follows. Shell completion, richer
application policy and the broader library goal remain open. Fixed-base lookup
is not containment, and byte/work limits are not an exact heap/RSS cap.

**Accepted command hierarchy and help.**

[Command routing and generated help](extended-cli-commands.md) use the existing
option lexer. Whole-schema admission checks inherited option scopes and maximum
scratch capacity before parsing. Help measures before writing into caller
storage, preserving output on failure. These pure modules allocate no storage
and perform no host I/O. A hierarchy parser exclusively borrows its scratch;
the flat parser's position-copy contract remains separate.

| Surface | Accepted finite scope |
| --- | --- |
| Public and pure admission | Both actual public smokes and the current contract program exit zero. Full syscall traces contain only launch/final raw exit, with no allocation attempt under mmap denial. This is not OOM-recovery evidence. |
| Semantics | Two Rust tests pass together in 10.10s after a separate 0.39s build: 30 schema mutations, six literal help goldens and 28 routing/event/location sequences in one model process. |
| Existing flat parser | One selected test passes in 6.04s after a separate 2.32s build; seven tests were filtered out. Earlier flat-parser/checksum receipts retain their original scope. |
| [Historical hierarchy KV application](extended-kv.md#historical-hierarchy-application-receipts) | Three direct groups pass 130 overlapping cases on source `f07fd52f...`: hierarchy66, roundtrips33, publication31, including 13 reached source OOMs and 15 I/O faults. Every syscall is observed; these are not three current Rust-libtest passes or reruns of the response-file application. |

Sources are flat parser `9f11981f...`, routing `6eb4db7a...`, help
`a7198a2a...` and application `f07fd52f...`. Receipts under
`target/stdlib-work/` are `cli-commands-semantic-owner-aliases.log`,
`cli-commands-flat-parser-regression-first.log`,
`cli-commands-contracts-aliases-no-host.{trace,log}` and
`cli-commands-{public-smoke,help-smoke}-no-host.{trace,log}`. Hierarchy app logs
are `cli-commands-kv-{hierarchy,roundtrips,publication}-all-syscalls.log`.
Earlier selected-call traces missed possible unlisted calls; their repeated
130 cases are weaker observations, not another 130 accepted cases. The new KV
driver has `--no-run` admission in 51.67s, separately from direct execution.

The application validates the complete CLI before file access and generates
root/child help, with `--` for dashed database paths. Its Store/snapshot and
AtomicFile publication logic retain their prior contracts. A separate minimal
nested-error-pattern compiler dependency has an executable typed-match control.
Targets remain native Linux x86_64 CPU output from the GPU compiler. Shell
completion, richer application validation and the full library goal remain
open. Response preprocessing has its separate acceptance scope above; no
user-program GPU execution follows.

**Accepted ordinary nested iteration.**

The [contract](stdlib-infallible-nested.md) adds plain `Iterator<T>` adapters
with `Mapper<S,J>` and an explicit
`InnerRetirement<J,Infallible>` policy. Construction is lazy, active-inner
take/finish preserves recovery, and retirement precedes another outer pull.
The existing fallible engine and adapters are unchanged. Owning inners still
require real retirement; the empty error type does not imply automatic cleanup.

| Surface | Current finite scope |
| --- | --- |
| Public adapter admission | One actual stdlib-import program compiles and exits zero through the direct CLI. |
| [Semantics and shapes](../tests/fixtures/stdlib_foundation/infallible_nested_iteration/README.md) | Two Rust tests pass together in 9.38s: 24 modeled action schedules in one native process, plus a separate optional/Result/wide, actual positive/negative-stride, zero-sized and Scan/Take composition program. |
| [Negative bounds](../tests/fixtures/stdlib_foundation/infallible_nested_bounds/README.md) | Three Rust tests pass in 4.77s, requiring source-local rejection of fallible retirement, a fallible mapper and the wrong inner item. They establish no native behavior. |
| [Current flatten_sum program](stdlib-flatten-sum.md#current-ordinary-adapter-receipts) | Four direct oracle groups pass 219 overlapping cases: models138, bounds54, allocations11 (baseline plus ten reached OOMs), faults16. These are not four current Rust-libtest receipts. |
| [Strict native owners](../tests/fixtures/stdlib_execution/infallible_nested_iteration_owners/README.md) | Eight direct cases pass: Vec/wrapped Deque × Flatten/FlatMap × full/early-take-resume. Four live acknowledged checkpoints verify exact owner partitions and pre-exit mapping/descriptor cleanup. No source allocation attempt occurs after setup, including callbacks and recovery. |

Core source is `5034fbac...`; the migrated application is `65cfcdfc...`.
Receipts under `target/stdlib-work/` are
`infallible-nested-public-smoke-{first,native-first}.log`,
`infallible-nested-model-shapes-first.log`,
`infallible-nested-bounds-first.log` and
`infallible-flatten-sum-{models,bounds,allocations,faults}-first.log`.
Owner receipt `infallible-nested-owners-lifecycle-first.log` uses probe
`0a8aa0d4...`, retained ELF `530cbe74...` and oracle `7f7c77c8...`.
It is a direct native receipt, not a passing Rust libtest or an OOM campaign.
Nine semantic and 25 owner CPU controls are separate from runtime.
The semantic and negative test-profile builds take 1.76s and 1.80s separately
from their test phases. Targets remain native Linux x86_64 CPU programs
emitted by the GPU compiler. No current ordinary-app scale observation or
user-program GPU support is inferred. Earlier receipts below retain their
original source scope; the complete library goal remains open.

**Accepted replacement-sink increment.**

The [contract](stdlib-replacement-sinks.md) adds one bounded helper and four
thin canonical map/set implementations. Rejected returns the incoming owner
before commit; Undelivered returns the complete old item after commit. Recovery
must not repeat that replacement. Both old map fields retain cleanup authority;
prior collection and TrySink bodies are unchanged. Core source is `a6fc9e0d...`.

| Surface | Accepted finite scope |
| --- | --- |
| Public/owning admission | Two direct stdlib-import programs exit zero. |
| Semantics and shapes | Two separate Rust tests pass: model53 scenarios in 9.73s and wide/optional/zero-sized/four-duplicate-policy checks in 9.49s. |
| Negative bounds | Five compiler-rejection Rust tests pass in 5.67s, separate from a 1m00s test-profile build; they prove no native behavior. |
| Strict owners | Five direct groups pass 219 group cases with overlap and 183 individually reached OOMs. Lifecycle includes 16 healthy cases plus four unreached no-growth controls. |
| [Latest-values program](stdlib-latest-values.md) | Four direct groups pass 248 overlapping cases: models136, bounds61, allocations34 (baseline plus33 OOMs), faults17. The strengthened bounds oracle verifies causal old/new/remainder owner lifetime. |

The model/shape receipts are `replacement-model-typed-prime-retry.log` and
`replacement-shapes-local-projection-retry.log`. Strict owners use
`replacement-owners-{lifecycle,hash-map-oom,tree-map-oom,hash-set-oom,tree-set-oom}-first.log`.
App groups use `replacement-latest-values-{models-first,bounds-live-order-retry,allocations-first,faults-first}.log`.
All are under `target/stdlib-work/`; linked guides own exact identities and
scope. The five resource and four app groups are direct retained-ELF oracle
receipts, not five/four passing Rust libtests. Their registered drivers build
with `--no-run` together in 3.42s. CPU controls number 18 semantic, 45 resource
and 26 app, separately from runtime.

A separate zero-sized return-call compiler dependency remains in an
[import-free reproduction](../tests/fixtures/stdlib_compiler_state/replacement_zst_return/README.md).
The API's public Failure/Result Unit storage and direct projection pass; a
separate `(Progress,Unit,Unit)->Unit` function traps while its u64-return control
executes. No compiler/library implementation was changed to hide that boundary.
One 4,096-row/512-key untraced app observation takes 0.087919031s, including
launch/input validation/owners/maps/history/staging/output capture, with exact
checking outside the timer. It adds no case, allocation/RSS count or general
compiler/performance ratio. Target evidence is native Linux x86_64 CPU programs
emitted by the GPU compiler. The selected increment is accepted; the complete
library goal remains open.

**Accepted scan and nested-iteration increment.**

| Surface | Accepted historical source scope |
| --- | --- |
| [Public adapter admission](stdlib-nested-iteration.md#verification-status) | Two actual stdlib-import programs compile and exit zero, covering all four adapters. These are direct CLI/native receipts; the two corresponding libtest registrations were not rerun. |
| [Semantic and payload models](../tests/fixtures/stdlib_foundation/nested_iteration/README.md) | All three Rust tests pass in 9.31s: 360 nested and 672 scan binary command scenarios plus actual nested Option/Result/array, wide, strided and zero-sized payload checks. |
| [Earlier fallible flatten_sum program](stdlib-flatten-sum.md#historical-fallible-adapter-receipts) | All four tests pass 219 process group cases across two commands: models 138/bounds 54 in 8.51s; allocations 11 (baseline plus ten reached OOMs)/faults 16 in 8.23s. Baselines/setup overlap; the earlier direct smoke adds no cases. |
| [Strict native owners](../tests/fixtures/stdlib_execution/nested_iteration_owners/README.md) | All four direct oracle groups pass on one retained ELF: lifecycle 14, flatten OOM 30, Vec flat-map OOM 56 and Deque flat-map OOM 56. Total 156 group cases includes overlapping baselines; 132 OOM runs are individually reached. This is not a four-libtest receipt. |

This accepted freeze is core `7256a394...` and application `946043fe...`;
the current ordinary-adapter migration has separate receipts above. Scan borrows
caller-owned state. One nested engine transfers an exhausted inner to explicit
retirement, restores the actual returned updated inner on failure, yields one
error and fuses. Early take/finish preserves inner and outer recovery duties.
No automatic destruction or borrowed-lifetime enforcement is added.

Receipts under `target/stdlib-work/` are
`nested-public-models-shapes-first.log`,
`nested-flatten-sum-models-bounds-first.log` and
`nested-flatten-sum-allocations-faults-first.log`; the separate direct smoke
logs and exact source/ELF identities are in the linked guides. Seven Rust tests
pass across those commands, plus two direct programs; this is not an all-five
semantic-libtest run. The separate four direct owner groups verify actual
Vec/Deque/String backing, owned errors and acknowledged live cleanup; the app
checks source release at traced exit without that ACK protocol. Separate
semantic/app CPU controls number 18 each; owner oracle controls number 41. Target evidence is native Linux
x86_64 CPU code emitted by the GPU compiler, kernel `7.0.0-38-generic` with
local ext4 `/tmp` fixtures. No other host or user GPU-kernel support follows.

Direct owner receipts are `nested-owners-lifecycle-lazy-count-retry.log`,
`nested-owners-flatten-oom-first.log`, `nested-owners-flatmap-vec-oom-first.log`
and `nested-owners-flatmap-deque-oom-first.log`. Probe `e92ee3b8...`, retained
ELF `3d99ec69...` and oracle `eb37f142...` establish actual updated-inner
recovery, retirement-before-acquisition and held output/error release through
strict site/size/prefix/phase and live mapping checkpoints. Initial fixture
admission corrected an unsupported applied where-subject and generic cursor
locals; later lazy/eager-count oracle corrections reused the emitted ELF.
Production and compiler sources were unchanged by those fixture/oracle fixes.

One separate historical untraced application observation processes 65,536
values in 3,072 rows, including 2,048 empty rows, in 0.157614975s. The timer includes startup,
stdin, parsing, ownership traversal, formatting and stdout capture; exact
output validation is outside it. `nested-flatten-sum-scale-first.log` supplies
one local observation, not a new fault case, source allocation count, compiler
benchmark or general ratio. Nested calls can cross many empty inners, so output
quotas do not bound outer/callback work. The
[remaining-work audit](library-roadmap.md#remaining-work-beyond-atomic-files)
keeps remaining iterator and library work visible.

**Accepted filesystem increment.**

| Surface | Current status |
| --- | --- |
| [Link and permission primitives](stdlib-filesystem-links.md) | All five groups pass: links 28, readlink 19, permissions 12, bounds 45 and faults 35, totaling 139 accepted group cases across separate commands. The first 34 fault cases repeat in the corrected fault-only receipt; this is not cumulative native-process counting. Exact syscall provenance and zero source allocation are checked. |
| [Owned temporary directories](stdlib-temp-directories.md) | All four groups pass: owner 9, admission/entropy 19, creation faults 8 and cleanup faults 10, totaling 46 accepted group cases across three commands. Corrected harness attempts repeat earlier work; this is not cumulative process counting. TempFile receipts do not establish this distinct mkdir/open/removal lifecycle. |
| [`mktemp_dir` program](stdlib-mktemp-dir.md) | All four tests pass 48 native process invocations across separate 7.64s/7.32s commands: normal 5, arguments 13, allocations 4 (baseline plus all three reached OOM positions), faults 26. This includes actual closed-reader help/creation pipes, retained-name cleanup and close-once retirement. Baselines and setup overlap. |

Current FileOps source is `21269e34...`, TempDir is `56898b00...`, and the
application is `118f9a78...`. Selected services target native
Linux x86_64 through the existing checked syscall boundary. Namespaces remain
cooperative, cleanup is nonrecursive, and close retirement is explicit. Earlier
TempFile, AtomicFile, archive-directory and server evidence below retains its
original source/target scope. The reference inventory records this accepted
source/API freeze separately from the runtime receipts.

Receipts are under `target/stdlib-work/`: `filesystem-links-native-first.log`
(6.67s, four passing groups and the incomplete fault attempt),
`filesystem-links-faults-small-poke-retry.log` (6.36s, all 35 faults),
`filesystem-mktemp-behavior-local-guard.log` and
`filesystem-mktemp-faults-first.log`. TempDir owner 9 passes within the mixed
6.88s `filesystem-temp-dir-native-first.log`; creation 8 and cleanup 10 pass
within the mixed 7.66s `filesystem-temp-dir-callback-retry.log`. Those commands
contain harness failures in other groups and are not isolated passing-group
timings. Admission/entropy 19 passes in the 6.07s
`filesystem-temp-dir-single-entropy-rule-retry.log`. The first link fault
attempt reaches 34 cases
before strace rejects its final oversized command-line poke, before starting
that child. The retry constrains a 16-byte supplied prefix plus the full
returned count; real readlink cases still compare the entire destination.
Initial source admission isolated a comparison/cast parse ambiguity; the
[small reproduction](../tests/fixtures/stdlib_compiler_state/filesystem_imports/README.md)
and an equivalent widening-cast local preserve the API/effect/error contract
without a compiler change. TempDir callback-shadowing failures and a duplicate
getrandom injection rule were oracle defects: the final retry uses one
first-draw rule and verifies actual subsequent entropy. Production remained
unchanged across those oracle retries. The separate CPU controls number 40
for link primitives, 45 for TempDir and 16 for the application; they are not
native cases. Skipped-close fault injections establish logical
retirement and separately record remaining physical descriptors. Native
receipts use Linux x86_64, kernel `7.0.0-38-generic`, ext4 under `/tmp`; they
establish no broader host, namespace-security or crash-durability guarantee.

**Accepted reusable regex storage.**

One canonical fixed `Workspace` serves full-capture and two-slot span searches;
`Search` owns that storage and centralizes scalar progress and terminal release.
The lexer owns one span workspace per nonempty cursor. Regex-text creates its
Search lazily after admitting and charging an attempt, using span mode for
split/literal replacement and full captures for templates. Ordinary convenience
Match APIs retain independent result ownership; this is one engine, with
explicit manual lifetimes and no new regex syntax.

| Surface | Current finite evidence |
| --- | --- |
| Canonical Workspace/Search | Strict capacity/reset, zero-allocation reuse, EOF-capture and owner checks pass one native fixture in 6.12s. Constructor baseline plus all nine reached OOM cases pass ten processes. The corrected reuse/span model passes 839 cases in 6.99s. Both ordinary Regex/input regression tests pass in 10.50s. |
| Lexer workspace integration | All six tests pass across separate 12.79s and 11.88s invocations: owner interleaving/admission/contracts, 576 model cases, 63 explicit tables and all 30 reached OOM positions. |
| Regex-text and rewrite CLI | All seven tests pass across separate 12.70s, 11.36s and 10.89s invocations: lazy storage, 288 model cases, 89 tables, direct contracts, all 41 library/25 CLI reached OOMs, 24 CLI cases and four I/O fault schedules. |
| Lex-scan application | All five tests pass across separate 13.63s and 16.66s invocations: 124 grammar inputs in both modes plus boundaries, malformed admission/nonpublication, scripted I/O, all 30 reached OOM positions per mode and a 4,096-token cost observation. |

Current receipts are under `target/stdlib-work/`:
`regex-workspace-contracts-first.log`,
`regex-workspace-model-and-oom-first.log`,
`regex-workspace-model-exhaustive-offset-retry.log`,
`regex-workspace-existing-regressions-first.log`,
`lexer-workspace-owners-contracts-admission-first.log`,
`lexer-workspace-model-tables-oom-first.log`,
`regex-text-workspace-lazy-model-tables-first.log`,
`regex-text-workspace-contracts-oom-first.log`,
`regex-text-workspace-cli-first.log`,
`lex-scan-workspace-behavior-io-first.log` and
`lex-scan-workspace-faults-cost-first.log`. These are 23 selected passing Rust
tests across separate commands: Workspace 3, base regex 2, lexer 6, regex-text 7
and lex-scan 5. Separate CPU controls number 24 for Workspace, 30 for lexer
resources and 11 for regex-text resources; they are not native library tests.
The 9.19s mixed
constructor/model command accepted the ten constructor processes but rejected
that model fixture before native execution; it is not an allocation-only time.
Two model admission attempts failed before exhaustive error-offset arms fixed
the fixture; source matching/capacity contracts were unchanged. The corrected
839 cases are model scenarios, not 839 native process invocations. The lazy
regex-text fixture observes nine allocations/416 requested bytes in span mode
versus nine/928 in capture mode for the same `(a)(b)?` program; it does not
measure total process memory. The older allocation subprobe in the ordinary
Regex regression uses legacy accounting; the new strict constructor/workspace
ledger supplies the current storage evidence.

The current 4,096-token application observation records 32 verified source mmap
requests, 8,895 total requested source bytes and 6,868 peak live requested bytes,
with balanced releases. Its 79.624585ms traced correctness/cost harness wall
time includes temporary-input setup, process execution and output/ledger
verification. Requested-byte counts do not measure total native memory, kernel
state or RSS. This establishes no compiler-speed or general throughput ratio.

Native evidence is Linux x86_64 code emitted by the GPU compiler. Fixed capacity
and VM work allowances do not bound initialization/capture-copy/Unicode-table
CPU, process RSS or wall time. Competing token rules can rescan suffixes. Older
77/43 regex-text OOM counts, 120 lexer OOM positions and the 36,887-allocation
lex-scan observation describe the prior per-probe implementation, not current
allocation acceptance. The [declaration reference](library-api-reference.md)
records the current source/API freeze separately from runtime acceptance.

The production regex uses equivalent explicit propagation guards. An
[unused-import module reproduction](../tests/fixtures/stdlib_compiler_state/regex_workspace_admission/README.md)
retains a lowering-dominance dependency in the original question-mark module;
six smaller constructor/arithmetic/propagation controls execute. No individual
operator or aggregate shape has been isolated as the cause, and ordinary `?`
support is not declared unavailable. Compiler repair remains separate work.

**Accepted bounded archive increment.**

The new production code is Lanius over the existing TAR/ZIP engines,
AtomicFile and checked Linux descriptor operations. Current finite receipts
use native x86_64 Linux, with local guard/output directories under ext4 `/tmp`:

| Surface | Current scope |
| --- | --- |
| [Descriptor-relative directory operations](stdlib-directory-at.md) | Allocation-free `create_dir_at`/`remove_dir_at`: namespace 24, bounds 19 and faults 12 process invocations, including two fault baselines; all three Rust tests pass in 6.51s. |
| [ZIP creator metadata](extended-zip.md#errors-and-executable-evidence) | The canonical Entry retains the raw `version_made_by` word. Eight independent central records execute through packed and nonzero strided views, plus unchanged writer defaults, in one Rust test/6.11s. This does not classify unknown creators as safe extraction types. |
| [Namespace planner](extended-archive-plan.md) | Direct contracts and 76 independently modeled namespaces pass through a corrected fixture import. A separate four-process allocation receipt covers its baseline and three reached reservation failures. Model namespaces are not native process counts. |
| [Extraction profile](extended-archive-profile.md) | Four groups pass 222 authored cases: TAR kinds 18, ZIP creator/attributes 84, extras 108 and direct bounds/strides 12, in 5.95s. Classification performs no filesystem operation or payload integrity check. |
| [Complete archive source](extended-archive-source.md) | TAR 26, ZIP 26, limits 58 and allocation cleanup 10 process invocations pass four Rust tests in 8.09s. The 120 includes repeated baselines and eight reached source OOM cases. Admission and explicit release are checked before exit. |
| [Materializer](extended-archive-extraction.md) | Eleven direct Python oracle groups pass 100 process invocations against one CLI-compiled ELF: success 12, existing eight, partial three, bounds 25, allocation eight plus eight, namespace nine, sync five, writes eight, close/rename six and recovery eight. Allocation groups include two calibrations and 14 reached ENOMEM cases. This direct receipt is separate from Rust driver build admission and earlier pre-native fixture failures; no passing direct Rust-libtest rerun is claimed. |
| [Unpack CLI](extended-unpack.md#verification-scope) | Four Rust tests pass 69 process invocations in 10.64s: trees seven, arguments 27, bounds 30 and reporting five. Five additional input-fault invocations pass directly against the retained ELF: one calibration and four reached read injections. The added fifth libtest has build admission, not execution. |

One separate observation reuses the accepted CLI ELF for a 273-entry ZIP:
256 small files, 16 directories and one 2 MiB compressed payload, totaling
71,261 archive bytes and 2,129,920 decoded bytes. Startup, read, extraction,
fsync and reports take **1.653438s untraced** in this one sample; exact
tree/content/status validation occurs outside that timer. The receipt is
`target/stdlib-work/archive-unpack-observation-first.log`, with evidence under
`/tmp/unpack-observation-5cqwou2x`. It adds no finite-case count, compiler
throughput comparison or general filesystem performance claim.

Preparation seals the entire namespace and validates all TAR footer/ZIP metadata
before output effects. ZIP payload CRC/decode checks remain a separate canonical
extraction step, including for zero-byte directories. The materializer uses
NoReplace per file, preserves partial publication and explicit cleanup/recovery
facts, and requires a cooperative stable namespace. Neither the CLI receipts
nor generated declarations prove hostile namespace containment, supply a
directory transaction, or bound native blocking time/aggregate DEFLATE CPU.
GPU compilation here produces native CPU programs.
The existing AtomicFile/TempFile/server receipts retain their separate scopes.

The direct Run receipts under `target/stdlib-work/` are
`archive-materializer-tree-single-owner-retry.log`,
`archive-materializer-bounds-first.log`,
`archive-materializer-allocations-first.log`,
`archive-materializer-namespace-sync-fcntl-retry.log`,
`archive-materializer-write-close-first.log` and
`archive-materializer-recovery-first.log`. The 100 invocations include
calibrations/overlap. They use frozen production `cf1347d5...` and probe ELF
`268b8bed...`; full identities and each fixture correction remain in the
[materializer guide](extended-archive-extraction.md). This selected workflow
does not complete the full standard or extended library goal.

**Atomic publication and key-value application checkpoint.**

The actual AtomicFile probe passes owner nine, bounds 25, publication six and
faults 26: **66 process invocations across four groups**, including baselines.
The preliminary smoke case overlaps and is not a 67th distinct behavior.
The target is native Linux x86_64, kernel `7.0.0-38-generic`, on ext4 under
`/tmp`. The publication gate observes complete new bytes and Published visibility
while the directory anchor is still live, then permits explicit directory-sync
retry; the retry never repeats rename. Recoverable preflight/EINTR, real partial
writes, NoReplace conflict/contenders, ambiguous rename and retained cleanup have
finite executable coverage. The bounds retry corrected the fixture's owned-fd
write selector; it changed no product/probe source and reused the same ELF.

Receipts under `target/stdlib-work/` are `atomic-file-owner-group-first.log`,
`atomic-file-bounds-selector-retry.log`, `atomic-file-publication-first.log` and
`atomic-file-faults-first.log`. The separate 36 CPU ledger controls are not native
cases. Source allocations and native descriptor generations are checked before
exit; this does not account for all host/kernel memory or prove every schedule.

The earlier AtomicFile-migrated `kv_tool` passes round trips 33 and publication
31: **64 process invocations across two groups**, including 13 reached source-allocation failures
and 15 I/O controls in the publication group. Its new arities omit SCRATCH and
anchor mutation load/publication to one parent/leaf, with NoReplace init and
Replace updates. Published-but-unsynced, unconfirmed visibility and retained
cleanup remain explicit outcomes, including when stderr delivery fails.
The historical receipts are `kv-tool-atomic-syntax-retry-compile.log`,
`kv-tool-atomic-roundtrips-first.log` and `kv-tool-atomic-publication-first.log`.
The first compile failure was unsupported application match-arm syntax; the
correction required no compiler change. Eleven CPU binding controls and two
Rust driver `--no-run` admissions remain separate from native oracle execution;
no Rust libtest execution is claimed. The current hierarchy application has its
separate 130-case receipt above; the old 64 cases are not added to it. Portable
Store/snapshot tests retain their prior scope, and earlier caller-scratch CLI
receipts remain historical.

These operations use Lanius over existing Linux calls. The accepted namespace is
exclusive/cooperative; no locking, hostile-directory, network-filesystem or
universal crash/power-loss guarantee follows. The
[archive increment](library-archive-extraction-plan.md) now composes those
owners within the accepted finite extraction profile recorded above.

**Temporary-file checkpoint.**

[Owned temporary files](stdlib-temp-files.md) and the new
[descriptor-relative name primitives](stdlib-file-operations.md#descriptor-relative-name-mutations)
pass five native groups: owner eight, collisions six, validation 18, faults 19
and primitives 27. These are **78 process invocations**, including repeated
baselines; two preliminary overlapping receipts do not make 80 distinct cases.
The accepted profile is Linux x86_64, kernel `7.0.0-38-generic`, using ext4 under
`/tmp`. The fault group includes its baseline, one reached 37-byte dynamic
source-allocation failure and 17 other cases. The 26 CPU oracle controls are
separate from native runs. Three source-runtime pairs are verified per ELF;
owner probes check source/fd release before exit, and primitive traces balance
their allocation-free descriptor operations.

TempFile keeps one manual owner, duplicates its parent directory anchor,
creates exclusively from bounded OS entropy, and supports explicit close,
same-owner keep and fallible cleanup with retained recovery authority. Its
parent namespace must be exclusive/cooperative; no hostile-directory, crash
scavenging or durability guarantee is added. All production code is Lanius over
the existing raw Linux boundary, with no new runtime binding or cryptographic
implementation. The separately accepted AtomicFile/KV layer above builds on
this prerequisite; its new receipts do not expand the original TempFile group.

**Server checkpoint evidence.**

Current finite evidence uses native Linux x86_64/glibc, with OpenSSL 3 for TLS.
The accepted scopes below come from separate invocations:

| Surface | Accepted scope |
| --- | --- |
| Plain direct Exchange | 50 distinct cases: four steps, 11 decisions/views, four drain, six lifecycle, 23 faults and two additive abort/close-error cases. The stronger typed OOM campaign repeats 23 cases across 15 reached allocation sites; two typed invalid-count reruns repeat lifecycle coverage, adding no cases to the total. |
| Synchronous Connection facade | Three current retained-view, atomic-preflight and sticky-failure cases, in `http-server-shared-facade-close-history-retry.log` (10.72 seconds). |
| [HTTPS direct Exchange](extended-https-server-exchange.md) | 34 cases across seven groups through separate receipts: six verified steps, two early closures, four fatal-preparation/abort cleanup, four normal-close cleanup, six constructor/quota (11.07 seconds) and four constructor-allocation cases (10.88 seconds). The allocation group reaches three dynamic source-allocation failures; native OpenSSL heap allocation is outside that ledger. Eight paired TLS 1.2/1.3 teardown cases additionally pass in 21.05 seconds, with pre-exit owner/descriptor checks and sticky replay. |
| [Generic server scheduler](extended-server-poll.md) | 17 scripted profiles execute the actual Server: seven earlier owner/publication/refill/reservation profiles, three owned E/A profiles (13.60 seconds) and seven active-cap/cancellation profiles (13.42 seconds). The no-Destroy empty-report helper control remains a separate 21.84-second receipt. |
| Actual plain-driver poll faults | Two reached fault cases and one calibration, separately from the 17 scripted profiles. EINTR requires a fresh publication and recovery without stale readiness reads; EIO publishes shared PollIo(5), cleans up live owners and preserves the caller's listener. The retry reuses the compiled ELF. |
| [Plain health/echo program](extended-http-serve.md) | Two causal cases: held partial-head/queued refill (0.060573 traced seconds) and a held 4 MiB response reader (5.149525 traced seconds). Each peaks at two accepted owners and three sockets including the listener; the reader requires actual write EAGAIN before its healthy sibling completes. |
| Current plain application regressions | Matrix 30, quota one, limits 16, boundaries 25 and faults 41, through separate invocations. These total 113 process-case invocations, not distinct coverage: the standalone quota case repeats within faults. The fault group reaches 23 source-allocation failures and 18 other cases. |
| [Verified HTTPS health/echo program](extended-https-server.md) | Two corresponding TLS 1.3 causal cases pass in 0.158297 and 6.473137 traced seconds. They retain the same owner/socket caps, and the 4 MiB reader requires real EAGAIN, verified response bytes and authenticated closure. |
| Current HTTPS application regressions | 102 cases across separate matrix/failure/limit invocations: 30, 23 and 49. These exercise the current server scheduler and have no recorded wall-time claim. |
| Current mutual-TLS application regressions | 101 cases across separate matrix/failure/limit invocations: 35, 34 and 32, using the accepted fetch executable with the current server executable. Earlier client-only receipts remain separate. |
| [Scale observation](../tests/fixtures/extended/server_concurrency/README.md#separate-scale-observation) | Plain and TLS each complete 64 exact 64 KiB echoes with demand eight, four active owners and five sockets. Plain: 1,224 source allocations, 1,165,325 peak requested source bytes, 3.346761 traced seconds. TLS: 1,419 allocations, 1,352,377 bytes, 4.226492 traced seconds. |

The [connected fixture guide](../tests/fixtures/extended/server_concurrency/README.md)
records the exact application receipts and the preceding artificial-buffer
timeouts. These are traced observations, not deployment-capacity or compiler
speedup measurements. Source metrics count verified dynamic requested bytes,
excluding the bootstrap mapping, native/OpenSSL heap, kernel memory and RSS.
The focused poll-fault receipt is
`target/stdlib-work/server-poll-marked-poll-faults-format-retry.log`
(`cases=2 calibration=1`); its Python-only retry supplies no wall-time claim.
Rare WANT schedules, clock failures after native TLS calls and concurrent
mixed invalid/valid mutual-TLS admissions retain finite coverage gaps. The
sequential mutual-TLS matrices do not establish that mixed concurrent schedule.
The [declaration reference](library-api-reference.md#current-generation-receipt)
passes its bounded writer and final check for the command hierarchy/help
source/API freeze: 253 pages, 252 modules and 8,346 lexical public declaration
markers. Five outputs change: the index, flat parser, new command/help pages
and KV metadata, relative to the preceding ordinary nested freeze. Runtime acceptance is recorded separately; source extraction
and negative compiler admission accept no runtime gate themselves. Source
inventory evidence does not establish runtime support or library completion.

Two lower-layer controls remain distinct from those current transport gates:

- The public Protocol/Reply/generic Report admission control compiled and ran,
  including handler-local response staging and nested owned error disposal.
  Its scripted transport does not establish socket I/O or scheduling.
- The OpenSSL server shutdown experiment passed four groups and 12 cases
  across TLS 1.2 and 1.3, including write backpressure, late upload bytes,
  authenticated EOF, deadline expiry and truncated transport. This establishes
  the tested native peer profile, not the new HTTPS Exchange implementation.

The accepted client checkpoint `75ab38d1` extracts
the shared HTTP Protocol owner, generalizes batch scheduling and adds
resumable verified HTTPS. All selected current transport and integration gates
pass on native Linux x86_64/glibc. Earlier
HTTP/TLS receipts below describe the preceding accepted implementations;
they do not establish acceptance of these revised boundaries.
The production-shaped generic trait/Report control compiles and executes
with two error types, including nested owned errors. All nine new OpenSSL duplex
groups pass 36 cases, including five reached source-allocation failures. All six connected
HTTPS groups pass 108 cases across separate invocations, including peer
policy, transport failures, quotas, direct stepping and source-owner cleanup.
The transport-free Protocol passes its direct state/ownership group with 247
balanced mapping events and no network calls. The revised plain client passes
six synchronous groups (188 cases) and five direct Exchange groups (83 cases).
Plain batches pass eight groups (103 cases), including queued refill after
`before_wait` retires a driver. The migrated HTTPS fetch
application passes four groups and 63 cases; its mutual-TLS application
regressions pass three groups and 101 cases, excluding the prepared-context
stream group. The current fetch-many application passes all five groups,
including all 59 reached allocation failures and a 64-job control with at most
four sockets. Focused native client/server/mutual-TLS retry guards pass ten
cases across three selected groups. Historical full native TLS matrices and
excluded buffered/prepared-context groups retain their older receipt scope.
The first wait-retirement regression failed before its report because its
fixture allowed less work than canonical validation reserves. The fixture now
uses coherent HTTP caps; its unchanged behavioral assertions pass the retry.
One nested enum-pattern compiler limitation is isolated by a confirmed
14-line rejection and an executable explicit-match control; production
behavior and compiler source are unchanged. These finite profile gates do not
enumerate every input or network schedule. Worker threads, complete server
runtime acceptance and the remaining library roadmap stay open.

The [execution audit and portable foundation](stdlib-foundation.md) lists
the stdlib APIs verified on x86_64, their edge behavior, and the remaining
compiler and runtime dependencies.

The [standard and extended library roadmap](library-roadmap.md) tracks the
full scope and delivery requirements. New APIs follow the
[library conventions](library-api-conventions.md); the first
[owned UTF-8 String](stdlib-string.md) has executable native examples and
allocation-failure tests.
[Borrowed UTF-8 text](stdlib-text.md) provides subviews, splitting, scalar
iteration and hashing without copying.
The [byte stream APIs](stdlib-streams.md) provide shared reader/writer
contracts, owned byte buffers and native descriptor adapters.
The [generic hash map](stdlib-hash-collections.md) provides hashed lookup,
explicit allocation errors and returned displaced keys/values.
[Opt-in deep HashMap cloning](stdlib-clone-hash-map.md) now executes with
independent nested owners, typed key/value errors and allocation-failure cleanup.
[Opt-in recursive deque cloning](stdlib-clone-deque.md) also executes across
four groups, including ring-order models and owned-error rollback. [Opt-in deep heap cloning](stdlib-clone-binary-heap.md) also passes all five
native groups, including priority models and nested/owned-error failure cleanup.
[Opt-in deep TreeMap cloning](stdlib-clone-tree-map.md) also passes all five
native groups, including sorted staging, independent nested owners, typed
key/value rollback, allocation failures and zero-sized keys and values.
[Opt-in deep HashSet cloning](stdlib-clone-hash-set.md) and
[TreeSet cloning](stdlib-clone-tree-set.md) also execute with independent
String owners, representative-preserving models, typed failures and complete
cleanup at every allocation position reached by their focused fixtures.
[Scalar and structural clone implementations](stdlib-clone-values.md) compose
Option, Result and pairs with Strings and vectors, preserving exact scalar bits,
active payloads and typed rollback. Their five native groups pass after the
[empty-enum layout correction](compiler-empty-enum-layout.md).
The [shared iterator protocol](stdlib-iterators.md) connects ranges, views,
collections and text with borrowed adapters. A checked
[range dot-product program](stdlib-range-dot.md) composes zip, take, map
and enumeration, including arithmetic and output failures.
[Canonical slice cursors](stdlib-cursor-integration.md),
[text splits](stdlib-text-split-iterators.md) and
[heap iteration](stdlib-heap-iterators.md) use that same protocol.
[Selection, searches and folds](stdlib-iterator-selection.md) add lazy
filtering and typed short circuits. The [column-sum program](stdlib-column-sum.md)
combines text splitting, filtering, Result items and checked reduction.
[Lookahead and extrema](stdlib-iterator-lookahead.md) add a recoverable one-item
cache, relative position searches and explicit minimum/maximum tie policies.
The [column extrema program](stdlib-column-extrema.md) reports checked counts,
values and physical source rows, including input, allocation and output failures.
[Fallible collection](stdlib-iterator-transfer.md) transfers items into
vectors and deques with explicit progress and rejected-item recovery. The
[word sorter](stdlib-sort-words.md) collects borrowed text before sorting.
[Map, set and heap sinks](stdlib-iterator-collection-sinks.md) preserve
rejected items and stored representatives. The
[identifier index](stdlib-index-words.md) rejects duplicates and prints
ordered identifiers with their original positions.
[Owning Vec and Deque cursors](stdlib-owning-iterators.md) transfer items,
recover unconsumed storage and provide explicit nested cleanup.
[Hash map/set](stdlib-owning-hash.md), [ordered map/set](stdlib-owning-tree.md)
and [priority heap](stdlib-owning-heap.md) owning cursors now provide the same
explicit transfer, recovery and remaining-owner cleanup. Hash traversal is
unordered; ordered-tree and priority-heap pulls use the canonical removal
engines and take O(log n) per item. Their focused native models and owner
ledgers pass through the GPU compiler. The
[streaming word deduplicator](stdlib-unique-words.md) moves independent
Strings into an ordered set while reusing its batch allocation, then transfers
them through the set's owning cursor for publication and failure cleanup.
[Runtime formatting to byte writers](stdlib-format-write.md) validates
before publication and uses bounded scratch with explicit partial progress.
The [CSV report program](stdlib-format-report.md) composes it with numeric
parsing and buffered output.

[System hostname and service resolution](stdlib-resolve.md) now wraps libc
`getaddrinfo` on Linux x86_64/glibc, with explicit ASCII input, family,
TCP/UDP and flag policies. It copies native order and duplicates into owned
socket-address values; unsupported shapes and result limits fail atomically.
The [resolve-host program](stdlib-resolve-host.md) formats those values without
opening a connection. All four library groups and five application groups pass
through separate native receipts; the
[verification guide](stdlib-resolve-testing.md) records independent libc,
malformed-result, limit and reached-allocation coverage.
Lookup blocks in NSS/libc. Local byte/result limits do not impose native memory
quotas, a lookup deadline or DNS authentication.

[Child process groups](stdlib-command-groups.md) add explicit creation,
confirmed signaling authority and non-reaping exit observation. The original
unreaped leader anchors the group ID; final reaping or lost-child evidence
revokes that authority. Pipe capture can retain an observed status while
draining descendant-held pipes, then perform the final reap. The
[run-group supervisor](stdlib-run-group.md) adds explicit TERM/grace/KILL policy
and reports incomplete cleanup. Five API groups and five application groups
pass across separate receipts; the supervisor covers 53 cases.
Descendants can escape a group, and deadlines do not guarantee kernel-stuck
processes become reapable; these APIs do not provide process-tree containment.

[Resumable cleartext HTTP exchanges](extended-http-client.md) expose owned
Prepared request staging and caller-driven Exchange steps. At `480432e8`,
all five direct [Exchange groups](extended-http-exchange-testing.md) passed
across separate receipts, covering 83 cases, alongside all six synchronous
client regression groups (188 cases).
[Bounded HTTP batches](extended-http-batch.md) schedule several numeric-endpoint
connections using one thread and reusable polling, with input-order outcomes,
one common deadline, manual response owners, logical pending/retained byte
caps and explicit operation/work allowances. At that checkpoint, all seven
batch groups passed across separate receipts, including consecutive begin
failures followed by a valid queued job without a blocking poll that delays
admission. The [fetch-many program](extended-fetch-many.md) composes bounded CSV
jobs, the batch scheduler and an ordered Stored ZIP, validating all requests
before sockets and staging the archive before stdout. All five application
groups passed across separate receipts, including 59 reached allocation failures
and a 64-job scale control with at most four active sockets. Logical retention
caps do not bound allocator capacity, temporary candidates or process RSS.
The current [generic scheduler](extended-http-batch.md) uses one engine for
plain and [HTTPS batches](extended-https-batch.md), with typed driver errors
and explicit nested cleanup. The [resumable HTTPS driver](extended-https-client.md)
uses the canonical HTTP Protocol and OpenSSL's verified transport, including
stable retries and version-specific early-final closure. All six connected
HTTPS groups pass 108 cases across three receipts. These are current native
gates; the preceding HTTP/TLS receipts retain their separate historical scope.
The [direct Protocol group](extended-http-protocol-testing.md) passes in 7.94
seconds with 247 explicitly balanced mapping events and no network calls;
these are successful allocations, not 247 allocation-denial tests.
The revised plain client passes all six synchronous groups (188 cases) and
all five direct groups (83 cases), while the generic plain batch passes eight
groups (103 cases) across two receipts. The migrated
[HTTPS fetch](extended-https-fetch.md) passes four application groups (63 cases),
including empty-body zero allowances and an exact 1 MiB binary output. The affected
[mutual-TLS modes](extended-https-mutual-tls.md) pass three groups (101 cases).
The current [fetch-many integration](extended-fetch-many.md) also passes all
five groups in 24.18 seconds, including 59 reached allocation failures and a
64-job control with at most four active sockets. Historical buffered/prepared
stream receipts remain distinct from these selected current program gates.
The [current concurrent-server increment](library-server-concurrency-plan.md)
has the finite passes recorded above; its complete acceptance remains open.
Executable worker threads also remain part of the full goal. The
[concurrency admission audit](library-concurrency-dependencies.md) records
separate compiler/runtime boundaries. The historical execution receipts cover
native Linux x86-64 CPU programs built by the GPU compiler.

[Checked native C calls](library-native-c.md) execute on Linux x86_64/glibc
through ordinary ELF objects, the system C linker and libc startup.
[OpenSSL digest contexts](extended-openssl-digest.md) provide streaming
SHA-256, SHA-512, SHA3-256 and SHA3-512 through `libcrypto`; the
[hashing program](extended-openssl-hash.md) hashes bounded binary stdin.
All cryptographic operations use the native library. C `f32`/`f64` calls also
execute with independent SSE/GPR banks and up to 32 total scalar parameters.
An owned [SQLite adapter](extended-sqlite.md) and
a [persistent binary key/value program](extended-sqlite-kv.md) execute
through system SQLite on Linux x86_64/glibc, including typed values, transactions,
persistence, locking and failure tests. Their guides record the execution
evidence and measured bulk workload. [Persistent indexed ZIP snapshots](extended-archive-index.md)
compose ZIP and SQLite with atomic catalog replacement, independent snapshot
owners, binary names/keys and explicit uncertain transaction outcomes. The
application passes all seven native groups, including allocation/native faults
and a measured 1,024-entry workload. [Client TLS with peer verification](extended-openssl-tls.md)
executes through OpenSSL 3 `libssl`/`libcrypto`, with 34 cases across four groups
covering peer identity/trust, binary transfers, closure/truncation and stable
nonblocking retries. It uses manual context/session owners and a borrowed
nonblocking socket with explicit caller deadlines and SIGPIPE policy. The
[TLS stream adapter and HTTPS application](extended-https-fetch.md) execute
62 cases across four groups on Linux x86_64, covering stream progress,
verification/HTTP failures, limits and binary response framing. The application
uses a numeric endpoint, explicit trust/peer identity, bounded deadlines and
manual socket/TLS/buffer cleanup. [Server TLS](extended-openssl-tls-server.md)
also passes six native groups and 53 cases, including credential validation,
stable retries and native/allocation cleanup. The explicit unauthenticated
server policy remains available. [Mutual TLS](extended-openssl-mutual-tls.md)
adds required client-chain verification and client credentials through OpenSSL,
with 107 cases across six groups. Required authentication disables resumption
and checks each fresh peer; certificate verification does not assign an
application principal or authorization. Standalone encryption/signature APIs
and certificate trust APIs outside TLS remain work. The
[bounded HTTPS health/echo service](extended-https-server.md) passed 106 cases
across four groups using the shared TLS stream and canonical HTTP codec.
[Prepared client contexts and mutual-TLS HTTPS modes](extended-https-mutual-tls.md)
add 109 process cases across four groups on the preceding TLS wrapper. The
current independent read/write retry, context-retention and shutdown revision
has separate passing [OpenSSL duplex and selected regression receipts](extended-openssl-tls.md).
The client can
present an explicit certificate/key pair while still verifying the server; the service can require
client certificates from an explicit CA file before processing HTTP.
The [remaining native prerequisites](library-native-integration-prerequisites.md)
record those boundaries. Native linking now spools opaque original/replay
sections and supports source packs above one resident unit, while source
snapshots and global metadata still grow with the program. TCP/UDP sockets and
[bounded OS entropy](stdlib-entropy-bounded.md) are also available.
[DER](extended-der.md) and
[X.509 structure parsing](extended-x509.md) provide data inspection; they
do not verify signatures, certificate trust or TLS peers.

Optional modules use the [`extended` source root](../extended/README.md).
[`ext::csv`](extended-csv.md) and [`ext::json`](extended-json.md)
include executable normalizers, generated round trips and allocation-failure
coverage.
[Reusable CSV records and bounded stream writing](extended-csv-write.md)
share the canonical encoder, preflight the complete record and retain exact
accepted-prefix progress. The [column rewrite program](extended-csv-rewrite.md)
selects, repeats and reorders fields while reusing decoder and record storage;
its five native groups cover independent output models, limits, I/O and
allocation failures, plus a 4,096-row resource control. The
[reduced compiler dependencies](library-context-inference-dependencies.md)
retain original failing expressions beside native passing controls.

[Regex splitting and replacement](extended-regex-text.md) now reuse canonical
Search with one lazily acquired workspace. Borrowed split fields, independent
literal/template outputs and explicit search/output bounds retain their
documented contracts. All seven current groups pass, including 41 reached
library and 25 CLI allocation failures, with exact output and I/O failure
behavior. The preceding six-group receipts remain historical. Search work
reserves per-search VM allowances rather than total CPU or I/O work.

[Reusable lexical scanning](extended-lexer.md) selects the longest anchored
regex span at each position, with declaration-order ties, borrowed UTF-8
tokens and explicit progress, call and work limits. It shares the canonical
regex engine and validates each input once. Each nonempty cursor now owns one
eager span workspace, reused during token selection; terminal calls can release
it. All six current groups pass: owner/admission/contracts, 576 model cases,
63 explicit tables and all 30 reached OOM positions. The earlier 120-position
receipt retains its preceding per-probe scope. Competing patterns can rescan
input; neither reusable scratch nor these receipts establish whole-input
linear time.
The [CSV-rules lexer program](extended-lex-scan.md) emits staged token spans or
per-kind counts through bounded native I/O. All five current groups pass the
124-input/two-mode model, boundaries, admission, I/O, 30 reached OOM positions
per mode and a verified 4,096-token cost observation. Its earlier allocation
observation retains its historical implementation/accounting scope.

The [CSV report application](csv-report.md) combines streams, UTF-8 text,
checked decimal parsing, generic collections, CSV and JSON to validate and
group records with executable failure coverage.
