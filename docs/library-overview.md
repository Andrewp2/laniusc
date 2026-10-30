# Standard and extended library overview

The full library goal remains open. The current
[lazy Option/Result increment](stdlib-lazy-outcomes.md) adds nineteen
free-function/method pairs over one shared `core::function::Mapper` and
argument-free `Producer` protocol. Invocation is lazy; callback construction,
static bounds and owner cleanup stay explicit. The
[optional-sum consumer](stdlib-optional-sum.md) skips checked arithmetic after
parse failure while retaining its exact output contract. All eight library
groups pass, including all 76 branch routes in the independent model and
actual nested-owner callback effects. The four current application groups
pass 98 cases, and six selected migration/Option/Result regressions pass
separately. Acceptance is finite native Linux x86_64 CPU execution; lifetime
enforcement and the broader library goal remain open.
The preceding
[owned Vec editing](stdlib-vec-edit.md) adds explicit stable filtering,
adjacent deduplication and reverse tail cleanup while retaining capacity.
Temporary predicate borrows, exact cleanup order and zero-sized effects stay
manual and explicit. The [sort-rows consumer](stdlib-sort-rows.md) gains
filter/unique/limit policies. All nine library groups pass, including the
24-case state model and complete large-owner observations. All four new
application groups/132 cases pass with 57 reached allocation denials; three
selected older groups/109 cases remain separate. This finite native Linux
x86_64 increment is accepted; enforced ownership and broader work remain open.
The preceding
[relocatable development SDK](library-sdk.md) packages a supplied Linux x86_64
compiler and shaders with library sources, offline contract guides, three
examples and existing suite/vendor tools. Compiler identity, source snapshot
and selected-resolution notice inputs stay separate. Thirty host controls, one
trace-parser control and all four relocated native gates pass, covering six
application executions. The guide binds these receipts to the tested debug
snapshot and records earlier timeouts and host prerequisites. Stable releases,
broader target support and the whole library goal remain open.
The preceding
[resumable TOML serializer](extended-toml-streaming.md) shares one byte machine
across sizing, borrowed Read, owned encoding and direct caller-buffer output.
Reader construction admits preflight and replay under the explicit 2W policy;
caller-buffer errors preserve the complete destination without a temporary
output allocation. The [existing normalizer](extended-toml-normalize.md) now
uses fixed scratch and bounded publication. All five library groups pass,
including the 280-case state model and two reached collector-allocation denials
with same-document recovery. All four normalizer groups/64 native cases pass,
including 25 reached allocation denials and exact call-budget observations.
Three selected existing groups pass separately. This finite Linux x86_64 CPU
increment is accepted; earlier TOML receipts retain their scope.
The preceding
[literal text matching and replacement increment](stdlib-text-replacement.md)
adds a borrowed match cursor and bounded independent String results over the
existing search engine. Its [stdin/stdout consumer](stdlib-literal-rewrite.md)
validates and constructs output before publication. All five library groups
and four application groups/94 cases pass, including the 440-case independent
model, one library allocation denial with recovery and 12 application denials.
Selected old regressions and standalone build/examples pass separately. This
finite Linux x86_64 CPU increment is accepted; earlier receipts retain their
original API/source scope.
The preceding
[resumable compression encoder](extended-streaming-deflate.md) adds fixed
32 KiB blocks, retained pending output and u64 raw/zlib/gzip limits over shared
block helpers. The [file compressor](extended-compress-file.md) uses fixed
workspace and NoReplace publication. All five library groups and five
application groups/99 native cases pass, including the 112-case chunk/block
model and nine reached application allocation denials. This finite native
Linux x86_64 increment is accepted; earlier receipts keep their source/API scope.
The preceding
[vector-transfer increment](stdlib-vec-transfer.md) adds whole-owner `take`,
consuming append, suffix split and owned range extraction to `alloc::vec`.
Ordered shallow transfer, unchanged owners on error, retained source capacity
and manual exclusive authority are explicit. All eight library groups pass on
Linux x86_64 CPU output from the GPU compiler, including a 56-case/3,584-action
independent model, three reached reservation failures with same-owner recovery,
and complete large typed outputs. The
[CSV row-moving consumer](stdlib-move-rows.md) passes all four groups/133 native
cases, including 40 reached allocation denials; the standalone build and both
exact examples and five selected existing groups pass separately. This finite
increment is accepted; protected-vector migration remains separate.
The preceding
[image-resize increment](extended-image-resize.md) adds Nearest, Bilinear and
exact Area sampling to the existing RGBA8 module and
[PNG transformation program](extended-image-tool.md). Source preservation,
alpha-weighted rounding, byte-preserving identity and bounded tiled Area work
are explicit. All seven library groups pass, including the 626-case independent
model, two reached allocation failures with same-process recovery and five
scale shapes with at most 16 KiB scratch. The application passes four groups/
102 native cases, including 22 reached allocation denials. Two selected old
image groups, three old consumer groups/346 cases, standalone compilation and
both documented examples pass separately. This finite native Linux x86_64
increment is accepted; historical receipts retain their original scopes.
Other codec capabilities and the broader roadmap gaps remain separate work.
The preceding
[ordered form-byte increment](extended-form.md) adds borrowed form parsing,
forgiving percent decoding, canonical streaming serialization and an optional
packed Form owner. Ordered duplicates and arbitrary decoded bytes survive;
checked Text projections retain explicit UTF-8 errors. Append preserves logical
contents on error but may relocate backing, so prior borrows end before every
attempt. The borrowed serializer is shared by owned output and a
[field-selection consumer](extended-form-select.md). All nine library gates pass,
including the 607-case independent model and six reached allocation denials with
same-process recovery. The application passes four groups/86 native cases,
including 20 reached allocation denials; standalone build/examples pass
separately. This finite native Linux x86_64 increment is accepted. A reduced
nested-error-match compiler dependency retains an executing typed-helper
control; no production or compiler repair was needed. The preceding
[scoped map-update increment](stdlib-map-updates.md) adds a value transformation
to HashMap and TreeMap using Mapper<V,Pair<V,R>>. One lookup preserves the exact
stored key and map structure; a present callback returns the latest V even when
R is a Result error. Manual exclusive authority and cleanup remain explicit.
All seven new library gates pass on Linux x86_64 CPU output, including the
72-case operation model and four reached callback-allocation failures with
latest-owner reinstall and same-process recovery. The
[word-concordance consumer](stdlib-word-concordance.md) passes four groups/103
native cases, including 38 reached allocation failures. Three selected old
regressions and standalone build/exact examples also pass. This finite native
increment is accepted; earlier map and clone receipts retain their original
scope. The preceding
[stream-encoding increment](library-stream-encoding-plan.md) joins a portable
[resumable copier](stdlib-resumable-copy.md) to a borrowed
[JSON byte reader](extended-json-streaming.md). Pending suffixes, direct-call
quotas, exact output admission and manual immutable document lifetimes are
explicit. Blocking copy and owned JSON encode use those same engines; the
[normalizer](extended-json-normalize.md) publishes through fixed scratch without
an output String. All ten new library gates pass, including separate 72-case
transfer and 978-case ordered-document models, live backing and two reached
owned-encoding allocation failures with recovery. The normalizer passes four
groups/100 native cases, including 33 reached allocation failures. Three
selected old regressions and the standalone build/exact examples also pass.
This finite native Linux x86_64 increment is accepted.
The preceding
[generic slice-segmentation increment](stdlib-slice-segmentation.md) adds
checked Split, SplitInclusive and ChunkBy factories with Mapper capabilities
at iteration. Lazy callback order, shallow operands, borrowed aliases and
manual lifetimes are explicit; no reverse or exact-size promise is added.
All eight new library gates pass, including 5,496 independent model cases,
183,248 pulls, stateful alias/copy observations and exact live-owner cleanup.
The binary record-summary application passes four groups/94 native cases,
including 11 reached allocation failures. Its standalone build and exact guide
examples also pass. This finite native Linux x86_64 increment is accepted. The preceding
[borrowed bidirectional text increment](stdlib-bidirectional-text.md) adds
LF/CRLF lines and backward scalar/ASCII-word pulls through the canonical iterator
traits. Mixed directions share one remainder; original scalar indices, six-byte
ASCII whitespace and manual immutable backing remain explicit. These cursors
make no exact-size promise. A line-summary program and a borrowed reverse-scalar
Unicode report exercise the APIs. All seven new library gates pass, including
4,878 independent model cases, 276,732 pulls, exact live-owner cleanup and
allocation-free reporting with reached write-failure recovery. The canonical
Unicode-report stdin regression also passes. Line-summary passes all four
groups/102 native cases, including 11 reached allocation failures; standalone
build/examples also pass. This finite native Linux x86_64 increment is accepted.
Its previously listed generic slice-segmentation gap is the current increment
above, with its own evidence and remaining broader slice scope.
The preceding
[resumable decompression increment](extended-streaming-inflate.md) preserves
DEFLATE bits, tables, history and pending output across chunks; zlib/gzip framing
and owned decoding use the same engine. An atomic file decompressor validates
complete input before publication. Fixed workspace, provisional output and
per-call final-input promises are explicit. All seven new library tests pass,
including 1,925 model cases plus 311 reset passes, fixed backing at 2 MiB and
4 MiB output, and 28 reached owned-decoder allocation failures. All seven
decompress_file groups/98 native cases also pass, including eight reached
application allocation failures and actual publication outcomes. This finite
native Linux x86_64 increment is accepted. Existing codec regressions and the
six-workload native comparison have separate receipts in its guide.
The preceding
[borrowed reader-adapter increment](stdlib-io-adapters.md) adds Take quotas and
Chain concatenation through independent Read/BufRead implementations. Provider
errors, permanent first-source handoff, full-width quota and manual borrowing
have explicit contracts. All seven library tests pass, including 1,576 model
cases / 14,544 actions and four reached allocation denials with recovery. All
four concat_bytes groups/115 cases and standalone build/examples also pass.
This finite native Linux x86_64 increment is accepted. Historical stream
receipts retain their original scope.
The preceding
[strong-component increment](extended-graph-components.md) adds independent
component mappings and canonical condensation graphs, with component IDs ordered
by minimum original node and explicit admission/cleanup contracts. All six new
library tests pass, including the 3,218-case model, 17 reached allocation denials
and three 65,536-node shapes. All four dependency-order groups/312 cases also
pass, as do the standalone build and documented examples. This finite native
Linux x86_64 increment is accepted. Historical graph receipts retain their original scope.
The preceding
[stable-sort increment](stdlib-stable-sort.md) adds checked alloc::slice
sorting with one typed workspace, stable equivalent-key order and explicit
reservation errors before input reads or mutation. Core sorts retain their
allocation-free/unstable contracts. All eight library tests and migrated
sort_rows's four groups/123 cases pass, alongside standalone build/examples.
This finite native Linux x86_64 increment is accepted. The preceding
[iterator sequence increment](stdlib-iterator-sequences.md) adds equality,
total/partial lexicographic comparison and sortedness through canonical
Iterator/Mapper/Comparator protocols. Exact pull order, prefix witnesses,
shared-state aliases and manual cleanup are explicit. All eight library tests,
all 119 program cases and three migrated-consumer regressions pass, as do the
standalone build/examples. This finite native Linux x86_64 increment is accepted.
Historical slice and iterator evidence retains its original scope. The preceding
[owned delimiter/line increment](stdlib-owned-delimited.md) composes BufRead
with retained records, exact fill/consume budgets and terminal UTF-8 adoption.
Unacknowledged staged bytes, pending provider data and manual cleanup remain
explicit. All eight registered library tests pass, including the 15,724-case
model and resource/guarded-failure gates. All 131 application cases and two
line-sample migrations pass, as do two selected older admission regressions.
The standalone program and documented examples are verified. This finite
native Linux x86_64 increment is accepted. Source scanning confirms 21 other
legacy line-helper consumers remain outside this increment.
The preceding
[directed-graph increment](extended-graph.md) defines canonical integer-only
adjacency, shortest-hop FIFO BFS and lexicographically smallest ready-ID
ordering. Edge deduplication is independent of numeric sparse coefficient
policies. Work admission, error precedence and manual owners are explicit.
All eight library tests and four application groups/183 cases pass, including
a 4,570-case independent model and separate 65,536-node workloads. This finite
native Linux x86_64 increment is accepted. The preceding
[bounded owned-input increment](stdlib-owned-input.md) composes canonical Read
with retained byte/probe failures, actual-call budgets and reserve-before-read
growth. Validated Vec/String transfers preserve backing without copying; reader
and cleanup ownership remain explicit. All six library tests, including the
17,542-case model, and all 111 real-program cases pass. Selected old stream/
String regressions pass separately. This finite native Linux x86_64 increment
is accepted. The preceding
[checked Base64 increment](stdlib-base64.md) replaces fallback/sentinel calls
with four Result/View APIs and explicit standard/URL-safe, padded/unpadded
profiles. Full preflight, indexed errors, same-base aliases and manual backing
are explicit. All five library tests pass, including the 48,995-case model
and guarded/physical boundaries; three selected migrated WebSocket tests and
all 194 binary-CLI cases pass separately. This finite native Linux x86_64
increment is accepted.
The preceding
[native checked-varint consolidation](stdlib-varint.md) supplies sixteen
u32/u64/i32/i64 functions in core::varint with View-relative positions,
typed Result/Decoded and explicit errors. Three signed/two-word codecs retire
without aliases; unrelated wide arithmetic remains. Native admission/direct
and independent wire/physical-boundary gates pass, as do both migrated frames
and the 150-case CLI. This finite native Linux x86_64 increment is accepted.
The preceding
[shared random-source budget increment](stdlib-random-budget.md) adds a
borrowed Source64 adapter that composes one draw allowance across existing
samplers, fills and shuffles. Rejected/failed draws charge before delegation;
source duration/internal host calls and manual owners remain separate.
Malformed shuffle/choose Views reject before source or element access. Native
admission/direct/model/owner gates, the 98-case sampling program and one
selected existing contract regression pass. This finite native Linux x86_64
increment is accepted.
The preceding
[checked slice-selection increment](stdlib-slice-selection.md) specifies
comparator/natural nth-element selection, strict metadata/rank admission and
an aliased one-element result. Whole-value permutation, outside guards,
explicit bounded median-of-medians frames and manual owners are part of the
contract. Native admission/direct gates and one selected ordering regression
pass, as do the 11,976-case independent model, owner/scale gates and four
real select-value groups/101 cases. All six new library gates are accepted on
the finite native Linux x86_64 profile. Earlier ordering receipts do not
establish these functions. The preceding
[shared Seek increment](stdlib-seek.md) defines portable offset arithmetic,
Seek-only helpers and canonical providers for bounded memory cursors,
opt-in File and buffered streams. Read-ahead reconciliation, flush progress,
reader faults and host offset limits are explicit. Portable admission/direct/
model gates, native File gates, the 86-case reverse-records program and selected
stream/FileOps/buffered regressions pass. Three scripted buffered gates also
pass. This finite native Linux x86_64 increment is accepted.
Earlier receipts do not establish these additions.
The preceding
[bounded delimiter-I/O increment](stdlib-delimited-io.md) adds a standalone
BufRead protocol and read/skip helpers with byte/call caps and separate
copied/consumed failure progress. SliceReader and the allocating buffered
reader share the canonical protocol; fill/consume have no duplicate aliases.
Native admission/direct contracts, the 18,000-case model and four real record-
selection groups/91 cases pass. This finite native Linux x86_64 increment is accepted.
Four selected buffered regressions (including the copy sample) and one
selected stream regression pass separately.
The preceding
[checked storage-layout increment](stdlib-layout.md) defines eight arithmetic
APIs for sizes, alignment, padded arrays and explicit record composition.
Public-field revalidation, deterministic error precedence and the 64-bit
`MAX_SIZE` profile are fixed. Direct contracts, the 18,878-case independent
model, three selected arena regressions and the 58-case record-storage program
pass. This finite native Linux x86_64 increment is accepted. The arena consumer
shares relative-offset padding while retaining its
own allocation, alignment and zero-size policies. This does not infer native
type layout or complete memory/owner consolidation. The preceding
[Unix stream/socket-pair increment](stdlib-unix-streams.md) specifies local
AF_UNIX owners, borrowed pathname/abstract addresses and the existing staged
stream/readiness contracts. One-attempt connect, exact pair publication,
manual descriptor/path cleanup and explicit failure behavior are fixed;
source is frozen and pair/direct/address gates pass. The real request
application passes four groups/84 cases; all six new library tests pass across
separate receipts. Three selected IP tests and one real TCP-application test
also pass. This finite native Linux x86_64 increment is accepted. A narrow
generic Result-chain dependency retains an executable typed-local control.
Earlier IP socket receipts do not cover the added surface or replace the
selected current regressions.
The preceding
[eager outcome-composition increment](stdlib-outcome-composition.md) widens
Option/Result selection across payload or error types and adds Result
flattening and both transpose directions. All four specialized methods pass
native admission; broader contracts and the 2,180-case independent model
also pass. One selected existing Result-method regression passes separately.
Shallow copying, eager operands, original error identity and manual cleanup
remain explicit. All five new library tests and four optional-sum application
groups/98 cases pass, with three selected old regressions and CPU inventory
separate. This finite native Linux x86_64 increment is accepted. The preceding
[native numeric byte-order increment](stdlib-native-endian.md) adds 24
concrete u64/signed/IEEE-float functions to `core::endian`, bringing its public
surface to 36 functions. Complete logical-field admission, exact fallback
and float encodings, explicit byte order and caller backing remain part of
the contract. Two direct native tests pass with all 24 additions, 58 literal
vectors and four separate physical-overclaim traps. The independent
16,032-case model and two memory/scale gates also pass. The record-repacking
application passes four groups/96 cases, including a 65,536-record frame.
This finite Linux x86_64 increment is accepted; static inventory covers all
36 names separately from runtime evidence.
Historical twelve-function endian and existing float receipts retain their
source/API scope. The preceding
[advisory-locking increment](stdlib-file-locks.md) adds one-attempt borrowed
File lock/unlock and an explicit cooperative file-patch mode. Open-description
lifetime, duplicate sharing, failed-conversion uncertainty and manual cleanup
are explicit; Blocking supplies no deadline and Nonblocking reports contention.
Two native policy/fault tests, a 1,287-program/24,244-step independent model
and four process tests pass. Four new locked file-patch groups pass 49 cases.
This finite native Linux x86_64/local-filesystem increment is accepted.
One selected positional contract
and all four ordinary file-patch groups/82 cases pass as current regressions;
they do not establish locking behavior. Earlier positional and application
receipts do not establish this increment. The preceding
[positional-I/O increment](stdlib-positional-io.md) adds explicit-offset
ReadAt/WriteAt contracts, attempt-bounded exact/all helpers and staged File
adapters. Complete logical/positional spans are admitted before callbacks;
confirmed progress and failures are explicit. Native operations preserve
the shared cursor and reject direct I/O and append-mode positional writes.
Two portable contract tests pass, including one native no-service fixture
and two capability rejections. The 11,012-case independent model and five
native-driver tests also pass, including 30 fault schedules/24 reached
injections. The real file-patch application passes all four groups/82 process
cases. Selected old stream/FileOps regressions pass separately, and a focused
amended native contract checks full-span admission before staging. This
finite native Linux x86_64 increment is accepted. Earlier stream and file
receipts do not establish these additions. The preceding
[slice-ordering increment](stdlib-slice-ordering.md) adds seven checked View
algorithms with per-call comparison policies and heterogeneous keys. One
canonical `core::ordering::Comparator<L,R>` also serves iterator extrema;
raw Ord APIs share the same allocation-free engines through Natural. All six
new library gates pass, including 2,808 independent cases/44,928 actions,
actual nested String owners and 32,768-record comparison-count coverage.
The CSV application passes four groups/122 process cases, and three selected
iterator migration regressions pass separately. This finite increment is
accepted on native Linux x86_64 CPU output from the GPU compiler.
The preceding
[iterator reduction/bounded-fold increment](stdlib-iterator-folds.md) adds
eight consumers using canonical Iterator/DoubleEndedIterator and Folder/
TryFolder traits. Quotas, actual EOF observation, successful progress and
consumed-item errors are explicit; callbacks retain their resource policy.
All seven new library tests and four application groups pass, including
10,696 model cases/37,104 state commands, 24 selected allocation denials and
87 byte-summary process cases. Two dependency checks and two selected old
regressions retain separate scopes. This finite native Linux x86_64 increment
is accepted; prior iterator receipts remain historical. The preceding
[sparse conjugate-gradient increment](extended-sparse-cg.md) specifies a
solver for symmetric positive-definite CSR systems, with optional Jacobi
preconditioning, fresh residual checks after every update and explicit
converged/iteration-limited results. Full requested work admission, numerical
breakdown and manual owner cleanup are part of the contract. All six new
library gates pass, including a 1,918-case independent model, 27 reached
allocation denials and a 65,536-row manufactured system. The graph-diffusion
application passes all four registered gates and 154 process cases. This
finite native Linux x86_64 increment is accepted; previous sparse receipts
do not cover this module. The preceding
[sparse-product increment](extended-sparse-product.md) defines canonical
CSR-times-CSR multiplication with ordered finite binary64 accumulation,
reusable column scratch, exact nonzero output reservation and explicit
work/cap admission. All six new library gates pass, including the independent
2,194-case model, 16 reached allocation denials and the 65,536-row analytic
product. The real weighted-path application passes four registered gates
with 122 process cases across separate original/amended-model receipts.
This finite native Linux x86_64 increment is accepted. Earlier foundation
receipts do not cover the new API. The preceding
[canonical CSR increment](extended-sparse.md) adds allocation-free borrowed
validation/lookup/matvec, independent sparse owners and sparse/dense arithmetic.
Stored-zero rules, ordered binary64 arithmetic, work admission and manual
backing/cleanup are explicit. Caller-output matvec can publish a completed-row
prefix on numerical failure; owned operations release partial results.
All six registered library gates pass, including a 3,886-case independent
model, 33 reached operation-allocation denials and a 65,536-row analytic
scale case. The graph application passes all four registered gates and 113
process cases. This finite increment is accepted on native Linux x86_64.
It is a foundation for further sparse work, with no compiler or native
mathematics implementation change. The preceding
[exact-size iterator increment](stdlib-exact-size-iterators.md) adds an
explicit `remaining_count() -> u64` contract for selected finite leaves,
metadata-preserving adapters and collection cursors. Queries do no pulls,
callbacks, item reads, allocation, cleanup or host I/O. Zip, Chain,
callback-dependent traversal and checked-index Enumerate are excluded for
their documented alias, range or cardinality limits. All four library gates
and four real byte-sampling application gates pass on native Linux x86_64;
the independent library model covers 10,714 cases/35,922 steps and the
application covers 95 process cases. A selected unchanged reverse model also
passes. This finite increment is accepted; no unchecked memory trust or
automatic ownership follows. The preceding
[weighted-statistics](extended-weighted-statistics.md) and
[higher-moment](extended-higher-statistics.md) increment implements portable
binary64 summaries with named estimator conventions and atomic updates.
All eleven new registered tests and both ordinary-statistics regressions pass
on the finite Linux x86_64 profile, including three independent numerical
models and the real [sample-moments CSV program](extended-sample-moments.md).
The statistical modules allocate no memory and call no host math service;
the program uses existing CSV, owned buffers and host streams. Finite-state
limits, gradual underflow for weighted summaries and explicit higher-moment
Underflow remain part of the contracts. This selected increment is accepted;
the full numerical/library scope remains open. The preceding
[reverse-iteration increment](stdlib-iterators.md#double-ended-traversal)
implements paired front/back traits and a borrowed Rev adapter. All four
registered reverse tests pass on native Linux x86_64, covering pure contracts,
7,740 model commands, collection ownership and exact trait-bound rejection.
The real timeline-tail program passes four more registered tests with 71
process cases. Fusion, callback order, source lifetimes and cleanup remain
explicit contracts; this supplies no automatic ownership or device-runtime
claim. The preceding WebSocket server increment
adds a [borrowed server handshake and caller policy pause](extended-websocket-upgrade.md#server-api-and-policy-boundary),
a [real one-client TCP/TLS echo service](extended-websocket-echo.md) and
[bounded HTTP encoder preflight](extended-http.md#executable-evidence).
Separate raw server/client contract processes pass six/eleven scenario functions;
all eight echo groups and one real Lanius-client integration pass. Three focused
HTTP Rust runtime tests also pass. The two new server/echo Rust drivers have
build admission only. Native evidence remains Linux x86_64/glibc/OpenSSL 3;
automatic lifetime enforcement, full failure campaigns and the full library
scope remain open. The preceding connected WebSocket increment
adds a [borrowed client handshake](extended-websocket-upgrade.md),
[bounded frame stream](extended-websocket-stream.md) and a real
[one-message TCP/verified-TLS client](extended-websocket-once.md). A raw scripted
contract executable passes eleven scenario functions in one process. The final
client passes separate plain, rejection, CLI, I/O and TLS groups on Linux
x86_64/glibc/OpenSSL 3. Explicit manual ownership, coalesced-byte preservation,
per-layer quotas and caller deadline/entropy policy remain part of the
contract. Both new Rust drivers build; direct runtime receipts remain separate
from unrun Rust libtests. The preceding
[wire-upgrade increment](extended-websocket.md#current-upgrade-execution)
adds portable response validation/encoding, a narrow OpenSSL-backed Accept
helper and an offline stdin-to-101-response tool. Its wire/provider/tool receipts
retain their separate native profiles. The preceding
[URL-client increment](library-url-client-plan.md) implements owned HTTP(S) URL
planning, one ordered TCP selector and separate plain/verified-TLS facades over
the canonical drivers. Direct URL semantics/owners, socket adoption, connected
plain/DNS/TLS groups and connector boundary/failure groups pass on Linux
x86_64/glibc; HTTPS uses OpenSSL 3. The real fetch program passes its separate
functional groups. These finite receipts do not establish full wrapper/application
allocation-failure coverage, every clock/TLS schedule or another target. All five
new Rust drivers build; native Rust-libtest execution remains unrun. The
preceding accepted [completion increment](library-completion-plan.md) implements canonical prefix
parsing, portable completion, literal Bash-word decoding and reply framing.
Portable contracts/models and selected parser regressions pass; native KV query
semantics, owner/reached-OOM and output-failure groups also pass. The Bash 5.2/
bash-completion 2.11 adapter passes real function, PTY, quote-boundary and
watchdog checks. This selected increment is accepted on its finite profile.
The preceding accepted
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

**Owned delimiter and line input.**

The [owned-record contract](stdlib-owned-delimited.md) adds BufRead-only
collection with delimiter-inclusive byte caps and separate fill/consume calls.
EOF, byte/quota rejection, reserve-before-copy and copy-before-consume progress
are explicit. Terminal LF/EOF precedes UTF-8 validation and zero-copy String
adoption; failed consume can leave retained but unacknowledged bytes. A first
BufRead-only admission, direct contracts, a 15,724-case model and resource
gates pass across eight registered library tests. All 131 application cases
and two selected legacy-consumer migrations pass, alongside two selected older
admission regressions. The documented standalone build/examples pass separately.
The finite native Linux x86_64 increment is accepted.
The executable old line helper still has unbounded overlong-record draining;
its remaining consumers and the full library goal stay open.

**Directed adjacency and dependency ordering.**

The [graph contract](extended-graph.md) separates simple directed edges from
numeric CSR: duplicate edges collapse, isolated nodes remain and self-loops
remain real edges. One canonical validation boundary admits exact size-based
work estimates before allocation/traversal. FIFO discovery with sorted neighbors
fixes BFS parents; a Min heap gives the lexicographically smallest topological
order or explicit Cycle. Query absence, Bounds and Closed stay distinct.
All eight library tests pass, including the 4,570-case independent model,
seven reached allocation failures and separate 65,536-node workloads. The
[dependency-order program](extended-dependency-order.md) passes all four
groups/183 cases. The finite native Linux x86_64 increment is accepted.
Existing sparse and collection receipts retain their original scope.

**Bounded owned input.**

The [collection contract](stdlib-owned-input.md) defines Read-only byte/text
collection with an actual EOF observation, byte-cap probe retention and one
shared call allowance. Capacity is reserved before each ordinary read; failures
return the admitted byte owner and precise progress. UTF-8 validation follows
EOF, then transfers Vec backing into String without copying. The bounded
[input-statistics program](stdlib-input-stats.md) composes these helpers and
passes four groups/111 native cases. Public owner transfers require inactive
aliases and manual cleanup. All six library tests
pass, including pointer/capacity-preserving String transfer, a 17,542-case model,
geometric growth and seven reached allocation failures. Selected existing
stream/String regressions pass separately. Earlier alloc::io/String receipts
retain their historical scope.

**Checked Base64 profiles.**

The [checked codec](stdlib-base64.md) fixes alphabet/padding policy per Profile,
reports input-relative errors and preflights complete writes. Disjoint and
same-selected-base/same-stride Views share one engine; other overlap and live
physical backing remain caller obligations. Three WebSocket consumers select
Standard and inspect Results before staged copies; OpenSSL retains the digest.
The [binary conversion program](stdlib-base64-bytes.md) composes bounded input,
exact output reservation and explicit publication/cleanup. All five library
tests pass, including the 48,995-case model and both boundary gates. Three
selected wire/transport/OpenSSL tests and all 194 CLI cases pass separately
on native Linux x86_64. Older
standard-padded sentinel and broad WebSocket receipts retain their source scope.

**Checked native varints.**

The [varint guide](stdlib-varint.md) defines one shortest base-128/ZigZag
codec for native 32/64-bit signed/unsigned values. Metadata admission precedes
capacity/truncation, writers preflight complete capacity, and readers preserve
strict final-byte/canonicality precedence without partial values. Old status
and two-word codec modules are retired, with frame consumers migrated directly.
Native admission/direct tests, both exact frame sums and four CLI groups/150
cases pass. All five library tests are accepted, including the 61,144-case
independent model and guarded/physical-boundary execution. The exhaustive
continuation-first two-byte domain is distributed across profiles, not a
Cartesian repetition across every type/layout. Historical codec receipts keep
their original API/source scope; the accepted profile is native Linux x86_64
CPU output, with broader library/target/lifetime work open.

**Shared random-source budgets.**

The [draw-budget guide](stdlib-random-budget.md) specifies one borrowed adapter,
shared/copy/nesting semantics, exact errors and fill-prefix/shuffle-suffix
progress. Existing unlimited sampling remains an intentional policy. Exhaustion
returns DrawLimit without a biased fallback; quota counts Source64 calls,
not host calls, time or memory. All five new library tests pass, including the
7,130-case/57,040-action independent model and actual nested-owner/stride
checks with 41 exact releases and seven no-host-call phases. The real
[sampling program](stdlib-sample-integers.md) passes four groups/98 native cases.
One selected existing randomness contract passes separately; historical receipts
keep their API/source scope. This finite native Linux x86_64 increment is accepted.

**Checked slice selection.**

The [selection guide](stdlib-slice-selection.md) specifies two View functions
with one shared Comparator/Natural engine. Selection preserves a whole-value
permutation and returns a one-slot alias at the admitted relative nth position;
before/after partitions remain internally unordered. Deterministic groups of
five use sixteen explicit frame slots, with at most fourteen active frames for
the i32 domain. Native admission passes one test/6.93s: both functions,
17-element ranks, actual returned aliases and untouched outside guards, with
only process entry/exit in the full syscall trace. Direct contracts and three
marked capability rejections pass two tests/7.25s. One selected existing
checked-ordering test passes in 7.11s, two filtered. The real select-value
program passes four groups/101 native cases in 8.60s, including three reached
owner-allocation denials and actual EOF/last-read controls. Owner/scale gates
pass two tests/14.53s: 57 exact owner releases/five pure phases, plus 180
selections at three sizes through both APIs with all-host-call-free phases
and two reused backing releases. The independent sorted-reference model
passes one test/8.71s with 11,976 cases, three families, two backing forms and
three record policies (source lengths at most 40; larger scale evidence is
separate). An oracle-only native-byte-stride assumption was corrected without
producer/production changes. This finite native Linux x86_64 increment is
accepted. No new compiler dependency is introduced. No prior
ordering receipt is extended to these APIs.

**Shared Seek.**

The [Seek guide](stdlib-seek.md) specifies u64 positions with signed-i64
relative arithmetic and exact Start acknowledgement. Fixed memory cursors
reject beyond-length positions; the File extension uses Linux signed-i64
offsets, with Data/Hole remaining a separate low-level API. Buffered reader
Current reconciles read-ahead through query/absolute seek; inner errors clear
unread publication and fault it, while arithmetic rejection preserves bytes.
Buffered writers flush before seeking and preserve confirmed flush effects
on failure. Portable admission passes one test/6.30s; direct contracts and one
missing-bound rejection pass two tests/4.74s. The independent model passes one
test/5.01s with 17,620 cases, four families and four backing combinations.
One selected stream regression passes two fixtures in 11.00s. The real File/
pipe gate passes within a mixed 7.62s command whose fault test fails its tool-
warning harness. Its final fault-only test passes in 6.19s: 18 schedules,
five genuine controls and 13 reached injections. A selected old FileOps
regression passes in 7.65s. The real reverse-records program passes four
groups/86 cases in 8.00s. Buffered import now executes after private enum-
projection helpers replaced rejected Reader-body spellings; public generic
bounds/state behavior are unchanged. Three buffered tests pass in 9.95s,
covering nine reader/twelve writer phases, nesting/handoff and four reached
constructor denials with all-host-call-free pure phases and exact releases.
Four selected existing buffered tests pass separately in 10.57s, with one
writer-only test filtered. This finite native Linux x86_64 increment is
accepted; historical buffered receipts retain their API/source scope. The
full library, lifetime and target scope remains open.

**Bounded delimiter I/O.**

The [delimiter guide](stdlib-delimited-io.md) specifies BufRead-only helper
bounds, arbitrary byte delimiters, explicit Delimiter/Eof/Limit endings and
fill-plus-consume call budgets. Provider metadata is checked before EOF or
consume-budget decisions. Copy-before-consume can expose more destination
bytes than acknowledged logical progress; errors and limits imply no rollback
or automatic retry. SliceReader and buffered Reader implement the same
protocol with explicit borrowed-view lifetimes and manual ownership. One
small admission test passes in 7.24s. Four buffered regressions pass in 9.81s,
including the real copy sample and four reached constructor OOM sites; one
writer-only test was filtered. One stream regression passes two native
fixtures in 11.59s with three tests filtered. Direct contracts pass two tests
in 7.56s: six pure scenarios and two missing-BufRead rejections, with admission
filtered. Its trace is empty for selected memory/read/write/close services,
without an all-syscall claim. The independent model passes 18,000 cases,
four stride combinations and two invocations/case in 5.64s after a fixture-only
syntax correction. The real [record selector](stdlib-select-records.md) passes
four groups/91 cases in 8.51s, including five reached allocation denials and
real output-prefix/EOF failures. This finite increment is accepted on native
Linux x86_64 CPU output from the GPU compiler. Earlier receipts retain their
scope; provider effects, lifetimes and the broader library goal stay open.

**Checked storage layouts.**

The [layout guide](stdlib-layout.md) specifies eight allocation-free functions
with checked size/padding/composition and public-field revalidation. Arrays
include the last element's stride padding; extend reports its offset without
implicit tail padding. Zero size and high alignments are arithmetic values,
separate from native allocator backing and its alignment/zero-size limits.
Direct contracts pass one test/4.68s with only process-entry/exit syscalls;
three selected arena regressions pass in 11.98s with four others filtered.
The real [record-storage program](stdlib-layout-records.md) passes three
groups/58 cases in 7.32s, including count 65,536, byte readback, three reached
allocation denials and prepublication arena release. The independent library
model passes 18,878 cases across all eight APIs and direct/mutated inputs in
5.46s. This finite native Linux x86_64 increment is accepted; no new compiler
dependency is introduced. Earlier memory/arena receipts do not establish this
increment. Native layout inference, over-aligned allocation, automatic
lifetimes and broader memory consolidation remain separate work.

**Unix streams and socket pairs.**

The [Unix-stream guide](stdlib-unix-streams.md) records three constructors,
19 inherent owner methods and Read/Write/flush. Borrowed pathname names admit
1..107 non-NUL bytes, while Linux abstract names admit 0..107 arbitrary bytes
with significant NULs. Address validation/copying uses stack storage; stream
transfers share the existing descriptor engine, with no library allocation.
Pairs publish two independently owned connected endpoints together; copies,
duplicates, shutdown and retire-before-close preserve explicit ownership.
Connect makes one host attempt and never interprets Unix EAGAIN as IP pending
connection success. Source `44f6739d…` has 25 added public entries (60 total).
One registered real-pair admission passes in 7.30s with bidirectional binary
bytes, offset views, sentinels and explicit close. The real
[framed request program](stdlib-unix-request.md) passes four groups/84 cases:
model 24/8.49s and CLI 19, I/O 24, rejection 17/21.50s, including two real
five-second deadlines. The direct contract test passes in 8.11s with generic
Read/Write through typed Result locals; the original immediate generic
unwrap call failed compilation. The address test passes 90 probes in 6.90s:
52 independent peers, 36 boundary/lifetime cases and two real backlog cases.
Bounds/no-host and descriptor-lifecycle gates pass in the first mixed 13.15s
command, which also has a fault-harness failure. The final fault-only gate
passes in 8.40s with 63 schedules/13 genuine baselines/50 reached injections;
three skipped-close descriptors remain until process exit, with no invented
kernel-close claim. Exact warning/hex-result parser fixes leave production
unchanged. All six new library tests pass across separate receipts. A
socket-free immediate generic unwrap reproduction fails with LNC0027 while
its typed-local control executes;
the explicit ignored positive-test command is not a green two-test gate.
The [dependency ledger](library-dependencies.md) preserves that narrow boundary.
Three selected IP regressions pass in 10.93s, covering
ownership/ordinary transport, full datagrams and absolute-deadline retry;
old Internet connect-EAGAIN/malformed-accept groups were filtered and retain
historical scope. One selected real TCP-application test passes in 8.86s with
six IPv4/IPv6 exchanges at lengths 0, 257 and 1,048,576; three other tests were
filtered. This finite increment is accepted on native Linux x86_64 CPU output
from the GPU compiler. Address queries, Unix datagrams, seqpacket, credentials,
ancillary descriptor passing, broader targets and automatic lifetime/proof
work remain open.

**Eager outcome composition.**

The [composition guide](stdlib-outcome-composition.md) specifies type-changing
Option `and`, Result `and`/`or`, nested flattening and both optional/fallible
transpose directions. Result `and` retains one error type; Result `or` retains
one success type. Both transpose functions and receiver extensions live in
Option's existing conversion home, avoiding a reverse Result import. All
operands are evaluated before selection; shallow copying creates no cleanup
authority for selected or discarded resource owners.

Specialized-method admission passes one native test in 4.87s. The full
contract tables pass one test in 6.81s, and the independent model passes one
test in 6.94s with 2,180 cases across nine operations, free/method flavors,
exact payload bits and preserved caller inputs. One existing Result-method
test passes nine payload combinations in 9.64s, separately from the new
surface. One owner/memory test passes in 7.28s with six records/twelve actual
backings, seven zero-host-call pure phases and twelve exact releases.
The real [optional-sum application](stdlib-optional-sum.md) passes four groups
with 98 process cases across model 33/7.26s and CLI 17, rejection 30, I/O
18/8.02s. Five selected OOM sites, a real ten-byte output prefix followed by
EFBIG, required-EOF failure before publication and bounded interruption
controls retain their finite scopes. The selected Option regression passes
one test/three old fixtures in 6.86s. Six focused new typed-call rejections
pass one test in 7.71s; eight old Result type rejections pass a separate test
in 6.72s. CPU surface inventory passes one test in 0.01s with runtime tests
filtered; it establishes coverage bookkeeping. All five new library tests
and four application groups pass. This selected increment is accepted.
Evidence
is selected native Linux x86_64 CPU output from the GPU compiler, without a
device-runtime, automatic-ownership or general generic-completeness claim.
Earlier Option/Result receipts retain their historical source/API scope.

**Native numeric byte order.**

The [24 new endian functions](stdlib-native-endian.md) complete multibyte
native u64, i16/i32/i64 and f32/f64 fields alongside the existing u16/u32 and
represented-WideU64 family. Reads return the exact caller fallback and writes
return false before backing access on invalid complete logical bounds. Valid
writes select only the field; physical backing/lifetime remain caller duties.

Native u64 composes u32 packing; signed wrappers retain two's-complement bits.
Float wrappers use existing exact bit-transfer APIs without arithmetic,
preserving zero signs and NaN payload/signaling encodings as a target contract.
The module allocates no heap storage and uses no host service or implicit
machine byte order. Two new native tests pass in 8.33s with all 24 additions,
58 literal vectors, exact IEEE/fallback bits, no memory services in the direct
contract and four separate overclaim traps (101). The selected old endian
runtime passes one test/seven fixtures in 8.48s; UTF-16 passes one test/two
fixtures in 5.82s. The independent model passes 16,032 cases in 6.96s,
checking read words and encoded write bytes independently without Python
floats. Two memory tests pass in 7.73s: 672 rejected-access calls, three real
backing forms, selected signaling-NaN generic transport, zero host calls
inside traced pure phases and one exact owner release per fixture.
The 32,768-record workload makes 196,608 writes and 196,608 reads;
its instrumented whole lifecycle is separate from isolated throughput.
The [record-repacking application](stdlib-repack-records.md) passes all four
groups/96 cases across model27/7.80s and CLI23+rejection30+I/O16/7.62s. It
preserves per-field integer/IEEE bytes in all four conversion pairs, validates
high-bit counts before narrowing and executes a 65,536-record frame. Four
selected allocation denials and exact output-prefix/EOF failures retain their
finite owner/I/O scopes. The static 36-function call inventory passes one CPU
test; it is bookkeeping separate from runtime acceptance. This selected
increment is accepted on native Linux x86_64 CPU output from the GPU compiler;
earlier twelve-function and float evidence retains its scope. The whole
library goal, broader targets, automatic lifetimes and formal proofs remain open.

**Advisory file locks.**

The [whole-file lock contract](stdlib-file-locks.md) borrows a live File for
one Linux flock call with explicit Shared/Exclusive and Blocking/Nonblocking
choices. Only exact-zero success is accepted; errors retain the existing
Interrupted/WouldBlock/Host mapping. No implicit retry, allocation, seek,
sync, unlock or close is introduced. Blocking can wait indefinitely.

The lock belongs to the open description shared by duplicates, with no
reference-counted acquisitions or single-handle ownership guard. Callers
coordinate all aliases and explicit unlock/close. Failed conversion must not
be assumed to preserve the old lock. The local-filesystem contract coordinates
cooperating processes; pathname replacement, writers ignoring the protocol,
remote NFS/SMB semantics and durability retain separate limits.

The real [file-patch application](stdlib-file-patch.md) adds leading `--lock`
through its existing preflight/positional/cleanup path, acquiring nonblocking
Exclusive before reading and attempting unlock then close after acknowledged
acquisition. Primary patch status and secondary cleanup errors stay explicit.
The selected existing positional contract passes in 6.74s against FileOps
`9ca5ca58`; all four ordinary file-patch groups pass in 7.73s with 82 cases
against app `b2a6984c`. These are current regressions of the same ordinary
corpus. A new native policy test passes in the mixed first command (6.86s),
whose fault test failed a tool-warning harness. The final fault-only test
passes in 5.45s with 16 schedules/14 reached injections/two controls, including
an exact-zero check on a 4,294,967,296 result. The independent model passes
in 5.76s: 1,287 programs, 24,244 steps and four owner slots. Explicit unlock
normalizes 949 WouldBlock results, including 138 failed conversions, so later
predictions do not assume retention of a failed conversion's old mode.

All four process tests pass across blocking1/5.97s and lifetime3/5.37s,
with six native peer lifecycles and three actual syscall-73 waits observed
before controlling-host release. The locked application passes all four
groups/49 new cases across model15/7.73s and bounds15+faults15+protection4/7.62s.
Host probes check exclusion during actual positional reads/writes and release
before close. The 82 ordinary regression cases remain separate. This selected
increment is accepted; earlier receipts preserve their source/API scope.
No compiler/ABI/proof change or new compiler dependency is introduced. Manual
ownership, remote-filesystem semantics and blocking cancellation/deadlines
remain explicit limits; the whole library goal remains open.

**Positional I/O.**

The [portable positional family](stdlib-positional-io.md) uses explicit
`u64` byte positions within the signed-64-bit file-length domain. It validates
whole spans and nonnegative attempt budgets before dispatch. Empty helpers
make no callback; short transfers advance both array/file coordinates.
Interrupted calls spend attempts, and every failure retains only confirmed
progress. A call quota is separate from callback duration or a host deadline.

The `std::file_ops` File adapter stages at most 1024 bytes through stack
storage and makes one pread64/pwrite64 transfer after status validation.
Read bytes publish only after a valid count. It leaves the shared cursor
unchanged, rejects O_DIRECT and rejects O_APPEND for nonempty writes.
Manual owner/backing and descriptor/status stability remain caller duties;
matching/replacement, locking, crash durability and cleanup are not implicit.
Two portable tests pass in 7.01s: one native no-service contract fixture and
two exact capability rejections. A selected old stream regression passes in
11.34s with two native fixtures. The independent portable model passes in
4.38s with 11,012 cases, 6,836 provider calls and 652 failures after progress.
Five native-driver tests pass in 13.11s: four fixture groups plus one CPU
trace-parser check. Native observations include both byte strides, offsets
above 4 GiB, shared duplicate-cursor preservation, status policies and
30 fault schedules/24 reached injections. The actual O_DIRECT rejection
branch executes. A focused amended native-contract test passes in 7.74s,
checking both full 1025-byte spans at MAX−1024 before any flag or transfer
call. This reruns one of the five native-driver identities; earlier receipts
keep their original fixture scope. The real [file-patch application](stdlib-file-patch.md)
passes its 24-case model in 7.18s and CLI35/preservation6/I/O17 in 7.57s:
four registered tests and 82 unique process cases across disjoint commands.
One selected existing FileOps regression passes in 7.12s against the final
module. Native admission uses the retained
[typed-local parser idiom](../tests/fixtures/stdlib_compiler_state/filesystem_imports/README.md),
with no compiler repair claim. The selected native profile is Linux x86_64
CPU output from the GPU compiler; portable core contracts have no host
dependency. This selected increment is accepted. Historical receipts retain
their scope; broader targets, automatic ownership, formal proofs and the
whole standard/extended library remain open.

**Comparator-driven slice ordering.**

The [seven checked View APIs](stdlib-slice-ordering.md) provide in-place
unstable sorting, sortedness, heterogeneous lower/upper bounds, deterministic
first/last duplicate searches and Less-prefix partitioning. Every call rejects
negative/overflowing logical metadata before reads, mutation or callbacks.
Indices are view-relative; valid empty calls make no comparison. Shared
iterative heapsort/search engines preserve the raw Ord family's existing
signatures and nonpositive-length behavior through `Natural<T>`.

`core::ordering::Comparator<L,R>` replaces the old iterator-only trait with
no alias. Iterator min/max retain their representative/tie policies with
`Comparator<T,T>` bounds. Comparators borrow shallow values and context;
manual backing, stable policy, nonreentrancy and explicit cleanup remain
caller obligations. Algorithms neither allocate nor clone/destroy owners.

All six new library tests pass on native Linux x86_64 CPU output from the GPU
compiler: three contracts (8.64s), two owner/scale gates (12.20s) and one
independent model (6.59s). Contracts cover all seven APIs and five rejected
capability compositions. The independent model observes 2,808 cases and
44,928 actions across two descending-stride compound-record backings and six
policies, checking whole-record permutation and untouched guards. Actual
nested String owners have 29 exact releases; seven pure phases invoke no
mapping/release services. A 32,768-record gate checks asymptotic comparison
allowances and two exact backing releases; its 267ms whole instrumented
lifecycle is not isolated sorting throughput or a compiler speed ratio.

The retained [same-receiver compiler dependency](../tests/fixtures/stdlib_foundation/slice_ordering_dependency/README.md)
has two passing checks (2.92s): an import-free reproduction reports LNC0027
for distinct comparison-trait applications, and separate receiver types
compile and execute. Current fixtures share one policy across those role
receivers; the generic library signatures remain unchanged. The real
[sort-rows CSV program](stdlib-sort-rows.md) passed all four registered tests
and 122 process cases: model37/12.78s, then CLI39/rejection33/I/O13 in 9.65s.
At that freeze it preserved visible source-row ties through an explicit
secondary key while the library sort remained unstable. The separate
[stable-sort migration](stdlib-stable-sort.md) has its own current receipts.
Three selected current iterator tests pass
in 16.23s: 1,280 four-action schedules, 320 extrema and 180 position cases,
owner cleanup and exact capability rejections. Two unrelated tests were
filtered; the historical lookahead application and trap were not rerun.
This selected finite increment is accepted. Historical slice/iterator/fold
evidence retains its original source scope; no device execution, formal proof
or automatic ownership follows.

**Allocation-backed stable sorting.**

The new [alloc::slice family](stdlib-stable-sort.md) uses existing View and
Comparator/Natural contracts with one pre-reserved typed workspace. Bounds and
storage errors precede input reads, callbacks and mutation; scratch has no
nested cleanup authority. Completed stable merges preserve equivalent-key
source order and whole shallow values. Core unstable sorts are unchanged.
All eight library tests pass, including the independent 5,946-case model,
owner/guard/scale gates and four marked capability rejections. Migrated
sort_rows passes four groups/123 cases; standalone build/examples also pass
without adding cases. This finite native Linux x86_64 increment is accepted.

**Iterator sequence comparisons.**

The [eight sequence consumers](stdlib-iterator-sequences.md) compare actual
remaining sources with left-before-right pulls, immediate decisive returns and
no count or identity shortcuts. Equality uses PartialEq, total order Ord and
partial order the existing four-variant PartialOrdering. Natural sortedness
uses PartialOrd; custom sortedness is a bool adjacency policy. Owners remain
manual, including values discarded by result-only consumers. All eight library
tests pass, including the 11,502-case model and owner/guard/scale gates. All 119
program cases and three selected migrated-consumer regressions pass separately,
alongside the standalone build/examples. This finite native Linux x86_64
increment is accepted; the full library goal remains open.

**Iterator reductions and bounded folds.**

The [eight new fold consumers](stdlib-iterator-folds.md) cover reduction
without a synthetic initial value, reverse accumulation and resumable bounded
folds in either direction. Reverse calls require explicit Iterator and
DoubleEndedIterator bounds for the same item type. Callback argument order
is always accumulator first.

`FoldProgress` reports successful callback count and an observed EOF flag.
Zero quotas touch neither source nor folder; reaching quota makes no extra
EOF or metadata query. A fallible callback has already consumed its current
item when `FoldFailure` reports earlier successful applications. Recovery
must use actual owners carried in the callback error. The consumer layer
adds no allocation, clone, destruction or source retirement; source/callback
work and manual ownership remain separate obligations. All seven new library
tests pass on native Linux x86_64 CPU output from the GPU compiler: three
contract tests (9.13s), three owner/recovery tests (7.62s) and one independent
state model (9.10s). All eight APIs execute without allocation services under
pure callbacks; two negative groups reject eight invalid bound compositions.
Actual nested String-owner recovery includes 24 selected setup/callback
growth denials with full address/size cleanup. The model observes 10,696 cases
and 37,104 state commands over four source forms in one native process,
including exact progress/errors, polls, traces and absent metadata queries.

Two selected old consumer/reverse regressions separately pass in
7.26s/10.96s. Two dependency tests (4.39s) establish one
[record-field inference diagnostic](../tests/fixtures/stdlib_foundation/iterator_fold_dependency/README.md)
and one executing typed-local control, with no compiler repair claim.
The real [byte-summary program](stdlib-byte-summary.md) passes model 40
in 9.92s, then CLI32/bounds1/I/O14 in 9.33s: four groups and 87 unique native
process cases. Earlier exact-size/reverse receipts keep their source scope;
the new increment supplies no automatic ownership, arbitrary generic or
device-execution claim.

**Sparse conjugate-gradient systems.**

The [CG contract](extended-sparse-cg.md) adds `ext::sparse_cg::solve` with
`None`/`Jacobi` preconditioning, an independent solution vector and explicit
`Stop::Converged` or `Stop::IterationLimit`. It verifies exact numerical
symmetry and Jacobi's positive diagonals; positive definiteness remains a
caller requirement. Ordinary binary64 dot products can overflow or break down
even for a mathematically valid SPD system.

Convergence uses the freshly recomputed `b-Ax` initially and after every
completed update, checked before the iteration limit. Recursive/fresh
disagreement can restart from the current iterate. The full requested
`setup + max_iterations*step` allowance is admitted before payload reads,
including immediately converged systems. No allocation occurs inside the
iteration loop; scratch/error cleanup and borrowed backing remain explicit.
All six new library gates pass on native Linux x86_64. Four contract groups
are accepted across the mixed first command's three passes and a corrected
admission-only rerun. The 27 reached workspace allocation denials have
matched explicit releases by full address/size. The independent model passes
1,918 cases across two backing forms using exact Fraction Gaussian references
and independently checked fresh residuals/stopping. An executed scalar
recursive-zero/fresh-one case verifies refusal or a residual-replacement
restart. The 65,536-row/196,606-entry manufactured system converges within
20 requested Jacobi steps under a 90,833,350 work allowance, with a separate
band-residual check after original backing is destroyed. Its whole-process
lifecycle timing is separate from isolated kernel throughput. The
[graph-diffusion program](extended-graph-diffuse.md) composes CSR assembly
with the solver and publishes only converged staged CSV. All four application
tests pass in 17.42s: model 36, rejection 48, CLI 55 and I/O 15, totaling 154
process cases. All six new library and four application gates are accepted
on this finite profile. Older sparse receipt scopes are unchanged.

**Sparse matrix products.**

The [sparse product contract](extended-sparse-product.md) supplies a sparse
`a.rows`-by-`b.cols` result when `a.cols==b.rows`. Full canonical input
validation includes unused right-hand rows. Accumulation traverses increasing
left inner columns and then each selected right row; sorted touched columns
provide canonical output without reordering sums. Explicit zeros participate,
computed zeros are omitted, and nonfinite intermediates fail atomically.
The output entry cap counts actual rounded nonzeros after cancellation.

Scratch storage is proportional to `b.cols` and reused across rows/passes;
structurally empty products need only output offsets. Work admission uses the
documented overflow-safe dominant-phase formula before scratch allocation or
scalar multiplication. Physical backing, input immutability and owner cleanup
remain manual. The independent model passes 2,194 cases in 7.45s across two
backing forms with exact CSR/finite-bit comparisons and bounded exact-Fraction
checks. The 65,536-row analytic gate passes in 8.38s: 196,606 input entries,
327,674 output entries and 589,814 structural products. Its whole native
lifecycle timing does not isolate kernel throughput. Four contract/denial
gates pass in 13.11s, covering allocation-free admission rejection and 16
reached operation-allocation errors with full address/size releases. All six
new library tests pass on native Linux x86_64. Two selected foundation semantic
regressions separately pass in 11.70s on the current module; other foundation
receipts retain their old source scope. The real
[signed weighted-path application](extended-sparse-paths.md) passes all four
groups: model 34, rejection 37, CLI 36 and I/O 15, totaling 122 unique process
cases. The first four-test command passes in 20.45s; its earlier 33-case model
is superseded by the separately accepted 34-case model in 14.73s, including
the rounded-value left-association check. The overlapping models are not
summed as distinct cases. All six new library and four application gates are
accepted on this finite target profile.
Device execution and formal proofs remain unclaimed.

**Canonical sparse rows and dense composition.**

The [sparse family](extended-sparse.md) separates borrowed finite CSR admission
from three-buffer owners and owned operations. Canonical rows have sorted
unique columns and count explicitly stored zeros in `nnz`. Copy/clone/
transpose preserve signed zeros; COO construction coalesces duplicates in
original input order, and computed zero entries are omitted. Operations
reject nonfinite arithmetic rather than silently substituting a zero result.

Addition, subtraction, scalar/axis scaling, owned matvec, dense conversion
and CSR-times-dense product have explicit shape/cap/work checks. Work units
are dominant phase estimates, not cumulative instruction/time budgets.
Every required factor/dense input is validated even if numerically unused.
The [graph-walk program](extended-graph-walk.md) assembles and normalizes sparse
transitions, supplies dangling self-loops, transposes and repeatedly calls
owned matvec; it is a finite walk with no PageRank/convergence claim.

All six registered library gates pass on native Linux x86_64: two semantic
tests, two allocation-denial tests, one independent numerical model and one
analytic scale test. The model covers 3,886 cases across 17 modes and two
backing forms using exact finite-bit comparisons, with separate Fraction
checks on bounded dyadic arithmetic. The 33 reached operation-allocation
failures have matched pre-exit releases; this excludes clone input setup
denials and does not establish every failure schedule or formal leak freedom.
The 65,536-row tridiagonal has 196,606 entries and exercises assembly,
transpose, addition, vector/dense products and rejection of a 4,294,967,296-cell
dense conversion. Its whole-process lifecycle timing is not an isolated
kernel/compiler benchmark. The real graph application passes all four
registered tests in 16.31s: model 32, rejection 33, CLI 38 and I/O 10, totaling
113 process cases. Its module-qualified slice calls work around the retained
[item-import priority dependency](../tests/fixtures/stdlib_compiler_state/item_import_priority/README.md).
All ten selected runtime gates are accepted on this finite target profile.
No broad target, uniform accuracy or formal-proof claim follows.
Those receipts retain the foundation source hashes in its guide. The separate
sparse product has its own accepted runtime evidence. The selected CG solver
has its own accepted increment; other iterative/direct solvers,
factorizations and additional formats remain future work.

**Exact remaining iterator counts.**

The [exact-size protocol](stdlib-exact-size-iterators.md) requires a matching
explicit Iterator bound and counts the actual remaining `Some` values. The
selected leaves include Empty/Once, full i32 ranges, canonical slice/chunk/
window cursors and collection cursors with existing constant-time remainder
metadata. Rev/Map/Take/Skip/StepBy/Peekable propagate the contract under their
source/callback bounds. Take/Skip/StepBy/Peekable remain forward-only; exact
size does not add a reverse method. StepBy distinguishes its first immediate
output from later skip-before-output blocks. Peekable includes one occupied
cache slot without filling it, and retains its cache recovery/owner policy.

Zip has no exact trait because its two borrowed sources can share progress;
the minimum of their counts need not equal future pair count. Chain can
exceed `u64` even with two valid source counts. Borrowed hash/tree cursors do
not gain a traversal scan or new count fields. Existing valid-state,
backing/lifetime, nonreentrancy and owner rules remain required. Counts are
snapshots for safe checked planning, with no authority for unchecked writes.
All four library gates pass across two receipts. Three nonmodel gates pass
in 11.82s in `exact-size-runtime-accepted.log`, whose model attempt fails on
a fixture visibility error. The corrected isolated model passes in 8.44s in
`exact-size-model-visibility-fixed.log`: 10,714 cases/35,922 steps/18 modes,
with counts derived by draining independent sequence/deque copies. The pure
contract's memory-syscall trace is empty, collection backings have matched
full-address/size releases, and five unsupported bounds reject with LNC0008.
These are four accepted distinct gates, without a combined all-pass claim.

The real [sample-bytes program](stdlib-sample-bytes.md) uses optional Rev,
Skip, StepBy and Take, then reserves from the final exact count while retaining
checked appends and an independent byte cap. Four registered tests pass in
9.44s, covering model37/limits3/CLI39/I/O16: 95 process cases, including two
reached allocation denials. Receipt is `sample-bytes-runtime-first.log`.
The unchanged old reverse model separately passes one selected test in 7.27s
with 7,740 commands, in `exact-size-reverse-regression.log`; no other old-suite
rerun follows. Logs are under `target/stdlib-work/`. Core source is
`be05d6c2…`, current pure contract `43e59a04…` and app `f2dc4738…`.
The narrow generic Option receiver-resolution dependency has an executed
typed-local control in the exact-size guide. No compiler production changes,
other targets, formal proofs or automatic lifetime/destruction are claimed.

**Weighted second moments and unweighted third/fourth moments.**

[Weighted statistics](extended-weighted-statistics.md) separates population and
reliability variance/covariance/stddev. Nonnegative finite real weights have a
positive-observation count, compensated total weight, stable positive-term
correction denominator and effective count. Zero weight validates coordinates
then reports no change. Paired summaries add correlation and simple linear
fit. [Higher statistics](extended-higher-statistics.md) composes ordinary
Moments with centered M3/M4 and explicitly named population/adjusted shape
queries. Both families publish whole scalar/merge/batch updates or an indexed
error. Higher moments reject lost positive M4 for a nonconstant sample;
ordinary/weighted second moments retain their stated gradual-underflow limits.

The shared statistics-scaling module is implementation support, with bounded
mantissa products and one final power-of-two scale. It supplies no arbitrary
precision or exact-rounding contract.

| Surface | Current finite executable scope |
| --- | --- |
| Scaling support | Two registered tests pass in 7.31s; independent Fraction references cover 1,926 cases, including 1,122 exact-bit cases; largest observed distance is two ULPs |
| Weighted statistics | All three registered gates pass: the initial model/contract/CPU-control run takes 13.07s; the strengthened current paired-contract test separately passes in 6.03s, with an empty mmap/mremap/munmap/brk trace |
| Weighted numerical model | 1,908 exact-input Fraction/220-digit Decimal cases cover ordered merge trees, paired fits, scaled/imbalanced/subnormal weights and explicit finite error allowances |
| Higher statistics | Both registered runtime tests pass in 9.54s: 1,212 model cases across 51 datasets/eight modes/two backing forms, plus final Underflow and atomic-failure contracts with zero mapping calls |
| [Sample-moments program](extended-sample-moments.md) | Four registered runtime tests pass in 9.87s and 66 process cases: model26/rejection30/CLI8/I/O2 |
| Ordinary-statistics regression | Both original runtime tests pass in 12.06s after the shared Underflow enum extension; ordinary algorithms and gradual-underflow behavior are unchanged |

The focused paired rerun replaces the earlier contract receipt; it is not a
twelfth distinct new test. Direct and registered numerical/application runs
overlap the same cases. One weighted gate checks the CPU oracle separately
from runtime execution. Sources are statistics `7f83f1e8…`, support
`775960e8…`, weighted `d3cea094…` and higher `3f224ad3…`; the strengthened
paired contract is `add50150…`. Final receipts under `target/stdlib-work/` are
`statistics-extension-runtime-final.log`,
`weighted-statistics-paired-contracts-final.log` and
`statistics-original-regression.log`.

Both tested `f64` backing forms use descending descriptors; this supplies no
positive packed-stride claim. The selected profile is accepted on native
Linux x86_64 CPU output from the GPU compiler. Weighted higher-order and
multivariate higher moments, broader numerical error bounds, formal proofs,
automatic borrowed lifetime enforcement and other host/device targets remain
open. The program's explicit storage and host-I/O layer remains separate
from the allocation-free statistical modules.

**Double-ended iteration and newest matching timeline records.**

The [paired iterator protocol](stdlib-iterators.md#double-ended-traversal)
consumes one shared non-crossing remainder. None from either end permanently
exhausts both directions. Generic callers name `Iterator<T>` and
`DoubleEndedIterator<T>` explicitly. Borrowed Rev swaps direction without eager
pulls, allocation, item cache, implicit cloning or cleanup. Selected leaves and
Map/Filter/FilterMap/Chain expose reverse pulls with their source/callback
bounds. Take/Skip/Zip/Enumerate remain forward-only and compose after Rev.
Stateful callbacks run in actual pull order; reverse support supplies no
exact-size promise.

| Surface | Current finite executable scope |
| --- | --- |
| Reverse protocol | All four registered Rust tests pass across two disjoint commands: model one in 9.40s and the other three in 11.74s |
| Pure and independent semantics | Five primary plus four extra scenario functions in two raw processes make no mmap/munmap calls; one independent VecDeque model checks 7,740 mixed-end commands |
| Owners and bounds | Four collection scenarios preserve borrowed aliases, explicit transfer/recovery and seven full-address/size matched backing releases; two invalid Rev bounds reject with LNC0008 |
| Selected existing callers | Old forward contracts, slice-view and tree-map controls compile/execute after the canonical method move; the tree control retains transitive trait visibility |
| [Timeline-tail program](stdlib-timeline-tail.md) | All four registered runtime tests pass in 9.15s, covering 71 process cases: model25/rejection24/CLI20/I/O2; earlier direct runs cover the same cases |

Core source is `c2db69bc…`; contract/extra/collection producers are
`5c682a05…`/`9f6ac75a…`/`bea024ff…`. App source/ELF are
`6579274d…`/`aca6fc83…`. Final logs are `reverse-model-rust-first.log`,
`reverse-contracts-rust-formatted.log` and `timeline-tail-rust-final.log` under
`target/stdlib-work/`. All selected reverse/app acceptance is executable;
formal proofs, automatic lifetimes/destruction, other reverse adapter families,
new allocation-failure campaigns and other host/device targets remain open.

**Borrowed WebSocket server and bounded echo service.**

[`websocket_upgrade::Server<T>`](extended-websocket-upgrade.md#server-api-and-policy-boundary)
receives and validates one HTTP upgrade head, then pauses at Request without
response writes. Caller policy inspects borrowed target/Origin/protocol/key
metadata and computes Accept through an established provider. Explicit accept
copies one canonical response; partial writes and inner flush precede Ready.
Conversion creates the server framing role over the same exclusively borrowed
transport. Captured bytes after the request head are rejected. Destruction
frees storage without closing the caller's transport. This extends the module;
the original 15,585-byte client prefix is unchanged.

The [echo service](extended-websocket-echo.md) listens once on a numeric IPv4/IPv6
endpoint, publishes the bound endpoint and handles one client. It checks the
exact `/echo` target and an optional exact Origin before 101, with canonical
400/403/404 rejections. It echoes one completed message and mirrors a normal
Close exchange. TLS uses configured OpenSSL credentials and explicitly
unauthenticated clients; Origin does not authenticate a peer. One cooperative
five-second deadline includes credentials, listen/accept, upgrade, frames and
cleanup. Shared HTTP-server Protocol adoption and concurrent scheduling are
separate integration work.

The [shared HTTP encoder](extended-http.md) now checks bounded serialized size
and field syntax before reserving one exact head-plus-body output capacity.
The canonical parser remains the final start-line/head authority. This does
not promise allocation-free rejection for every malformed input.

| Surface | Current finite executable scope |
| --- | --- |
| Server contract | Six scenario functions in one raw process: policy pause/copying, partial I/O, blocked flush, exact response caps, retryable acceptance and typed/sticky failures; converted framing uses Role::Server |
| Current client regression | Original eleven scenario functions pass in one raw process against the appended server module and changed HTTP encoder; old full client-app groups were not rerun |
| HTTP encoder | Three actual Rust runtime tests pass in 12.56s after a 2.13s build, including fifteen exact-capacity valid outputs, selected allocation-free preflight rejections and denial of the one reached output allocation |
| Echo plain/handshake/rejection/CLI | Separate direct groups pass eleven, twelve, ten and fourteen cases respectively |
| Echo TLS/credentials/deadline | Separate direct groups pass four, three and one cases respectively; TLS covers versions 1.2/1.3 and local close-notify, and bad credentials fail before listening |
| Echo readiness output | One separate closed-stdout case returns status 5 while the listener is owned; this does not establish leak freedom |
| Real integration | One additional native Lanius one-message client completes an exchange with this server |
| Driver admission | The final server/echo Rust-driver rebuild passes `--no-run` in 1.43s after adding the I/O case; this is separate from the three executed HTTP Rust tests |

Current sources are upgrade `cae29596…`, HTTP `5d495716…`, server fixture
`44292f11…` and echo app `dcdef14c…`. Raw server/client executable identities
are `79996579…`/`cb811239…`; echo/current integration-client ELFs are
`44d1b314…`/`798f00e9…`. Logs under `target/stdlib-work/` are
`websocket-server-contracts-{compile,native}-first.log`,
`websocket-transport-current-{compile,native}-first.log`,
`http-encoder-preflight-module-first.log`,
`websocket-echo-plain-native-first.log`,
`websocket-echo-{handshake,rejection,cli,tls,credentials,deadline}-native-corrected-oracle.log`,
`websocket-echo-io-native-first.log`,
`websocket-echo-integration-native-first.log` and
`websocket-server-driver-build-io.log`. The app guide records the corrected
duplicate-Origin and TLS shutdown oracle expectations and precise prior scope.

These finite passes establish the fresh borrowed server transport and one-client
example. Persistent/concurrent service, existing HTTP-server/scheduler adoption,
ws/wss URL policy, application authentication, allocation-failure/leak campaigns,
all generic/TLS schedules, formal proofs, automatic destruction/borrow checking
and other targets remain open. Blocking host/credential calls cannot be
interrupted by the cooperative deadline. Sensitive operations remain in OpenSSL.

**Borrowed WebSocket upgrade and frame transport.**

[`websocket_upgrade::Client<T>`](extended-websocket-upgrade.md) owns immutable
request/expected-Accept copies and retained response bytes while exclusively
borrowing the caller's transport. Each handshake step performs at most one
inner I/O attempt. The canonical HTTP cursor stops at the response head;
transactional `into_stream` copies every coalesced frame byte into the
[frame stream](extended-websocket-stream.md) before retiring handshake storage.
A failed conversion leaves the ready client usable. These allocation-backed
adapters import no socket, TLS, clock or entropy service of their own.

The frame stream preserves partial read/write progress, counts actual inner
read/write/flush attempts and requires inner flush before publishing a sent
frame or local Close. WouldBlock preserves the pending suffix/phase; terminal
I/O/quota failures are sticky. Destruction releases adapter storage without
flushing, closing the caller transport or sending protocol Close. Borrowed
payload views and the exclusive transport lifetime remain manual preconditions.

The [websocket-once client](extended-websocket-once.md) supplies the native
policy: explicit numeric endpoint, separate HTTP authority/target and verified
DNS TLS identity, fresh OS entropy for nonce/masking keys, one cooperative
network deadline, bounded messages/controls and successful Close/transport
cleanup before stdout publication. It parses no ws/wss URL and performs no DNS
lookup, reconnect or replay. OpenSSL owns TLS and the protocol Accept digest.

| Surface | Current finite executable scope |
| --- | --- |
| Generic adapters | One raw x86_64 contract process executes eleven scenario functions with finite fault/quota loops: split/prefetched frames, both roles, partial I/O, malformed/EOF/sticky errors, exact limits, source mutation and failed/successful conversion |
| Real plain client | Nine direct cases: binary/empty/text messages, fragments/Ping/Pong, coalesced frames, extended lengths and masked Close exchange |
| Real rejection and CLI | Separate groups: twelve protocol/no-publication cases and seventeen argument/input/no-network-on-rejection cases |
| Real I/O | Three cases: closed stdout reader, stdin failure and the original deadline while waiting for Close |
| Real TLS client | Five cases: TLS 1.2/1.3, isolated default trust, wrong DNS identity and untrusted CA; application exchange follows authentication |
| Driver admission | Both new Rust drivers build with `--no-run` in 2.00s; these direct executable receipts are not runtime-libtest passes |

Accepted sources are stream `be16005d…`, upgrade `c8f4a42d…`, scripted producer
`da71889b…` and final application `0ae21ee1…`. Raw/app executable hashes are
`6d7a17ee…`/`1e946119…`. Logs under `target/stdlib-work/` are
`websocket-transport-contracts-{compile,native}-quota-correction.log`,
`websocket-once-plain-native-empty-upload.log`,
`websocket-once-{rejection,cli,io,tls}-native-borrowed-owner.log` and
`websocket-transport-driver-build-first.log`. Earlier app `5055e3ed…` had an
unaccepted TLS owner-lifetime failure; the final app uses borrowed wrappers with
branch-scoped owners and has the current five-group receipts. The generic
modules did not change for that repair.

Target evidence is CPU execution on Linux x86_64. The combined app links
libssl.so.3, libcrypto.so.3 and libc.so.6 in both modes; its successful TLS
profile supplies no device execution claim. Allocation-failure injection,
source/fd leak campaigns, every generic transport/TLS schedule, broader server
orchestration, ws/wss URL policy, origin/authentication policy and other host
platforms remain open. Cooperative deadlines cannot interrupt blocking host
calls. Formal proofs, borrow checking and automatic destruction remain future
language/runtime work; the documented transfer/error contracts can survive
those changes.

**WebSocket HTTP/1 upgrade.**

The [portable wire module](extended-websocket.md) validates HTTP/1.1 101
responses against the original request and a caller-computed expected Accept.
It checks singleton Upgrade/Accept, Connection tokens, one offered
case-sensitive protocol selection and rejection of negotiated extensions.
Returned `remaining` borrows all post-head bytes. The encoder stages one owned
101 head; explicit Vec destruction remains required. Neither pure operation
implements a digest or transfers a transport owner.

The separate [OpenSSL helper](extended-openssl-websocket.md) computes the RFC
Accept value using `EVP_Q_digest`, with packed input, 64-byte native scratch,
a full-width size cell and output-atomic errors. OpenSSL performs the digest;
the helper requires libcrypto without libssl and exposes provider failures.
The [offline tool](extended-websocket-upgrade-program.md) reads through EOF,
rejects trailing request bytes and writes a fully staged 101 response, with
optional offered-protocol selection. It supplies no connected service.

| Surface | Current finite executable scope |
| --- | --- |
| Response wire | A direct pure contract program exits zero: 34 malformed responses plus valid/OWS/selection, two layouts, trailing-frame preservation, encoder bounds/caps and caller-field checks |
| Native Accept | 310 direct cases across two layouts and overlapping input/output; 24 injected cases separately check provider failure, wrong/full-width returned digest size and atomic errors |
| Offline tool | Separate direct functional22, rejection30, CLI15 and I/O4 groups; no combined distinct-case count or full application allocation-failure campaign is claimed |
| Driver admission | Both new Rust drivers build with `--no-run` in 2.09s; no runtime-libtest pass follows |

The wire guide records exact source/executable identities and logs. Historical
frame/request suites retain their earlier source scope and were not rerun.
The borrowed client and server compositions now have their separate
acceptance above. Shared HTTP-server/scheduler adoption, broader origin/routing/
authentication policy, formal proofs, automatic ownership and other host/device
targets remain open; nonce/mask entropy and deadlines are explicit policies in
the one-message client rather than effects of the pure wire API.

**URL-based HTTP and HTTPS.**

The [connected-client guide](extended-url-client.md) defines five boundaries:
allocation-free DNS byte admission, allocator-backed owned URL planning,
synchronous resolver/TCP selection, plain HTTP and explicit OpenSSL HTTPS.
Request preparation precedes lookup; the canonical driver adopts the selected
socket generation. The first proven TCP connection ends fallback. TLS identity
and Host retain the original URL name, and handshake/HTTP failure cannot replay
onto a spare endpoint. Manual owner transfer/destruction, primary versus
secondary cleanup errors, real leaf-call quotas and blocking NSS qualifications
are explicit.

| Surface | Current finite executable scope |
| --- | --- |
| [URL/helper](extended-http-url.md) | Public contracts, 70 model records on two backing layouts and 16 ownership/failure cases, including four reached allocation denials |
| Socket adoption | Public smoke, one connected same-generation case and eight failure cases, with one reached close EIO; these plain-adoption failures do not establish every TLS setup path |
| Connected exchange | Separate direct groups: two plain numeric HTTP cases, one controlled ordered four-address DNS fallback, eight TLS cases across TLS 1.2/1.3; exact Host/target/binary wire, original identity, no reconnect/replay and live pre-exit source/descriptor cleanup |
| Connector | Twelve admission and eight failure/cleanup cases, separately: deadlines/caps/family before attempt, ordered fallback cap/exhaustion, reserved close credit, native EAI/system errors and reached close EIO |
| [Real fetch](extended-fetch-url.md) | Separate functional groups of 24 HTTP, 33 CLI/preflight and four HTTPS cases; application source-owner/OOM campaign remains unclaimed |
| Driver registration | All five new Rust drivers pass combined build admission in 4.24s; these direct executable receipts are not passing native Rust libtests |

Current source hashes are helper `d7fae972…`, URL `24472542…`, connector
`bd3a3f65…`, plain `58f4989b…` and TLS `06a6ebfa…`. The URL guide records its
comment-only difference from the executed parser source. The connected guide
owns exact receipt paths, native executable identities and remaining finite
coverage gaps. The plain module links/runs without SSL/crypto; the combined
fetch program intentionally links both. GPU compilation supplies CPU output
here; no user-program GPU execution follows. A
[minimal None-name collision](../tests/fixtures/compiler_dependencies/url_none_inference/README.md)
has an executable module-qualified constructor control and is retained as a
name-resolution dependency. Automatic ownership, formal proofs, asynchronous
NSS, pooling/keepalive and broader connected WebSocket policies remain open;
the generic borrowed client handoff has its separate acceptance above.

**Accepted command completion.**

[Portable completion and the Bash adapter](extended-cli-complete.md) separate
three allocation-free modules from host behavior. `ext::cli_complete` reuses
canonical prefix parsing and command scopes; a Context retains no mutable
option scratch. `ext::bash_words` admits a literal word profile without
expansion. `ext::cli_bash` preflights complete reply frames into caller storage.
Only the separate Bash adapter enumerates filenames or applies Readline
insertion/quoting policy. Other shells are outside this selected increment.

| Surface | Current finite scope |
| --- | --- |
| Portable completion | The direct contract and public prefix-parser smoke pass full syscall observation with only launch/exit and no allocation attempt. One Rust model test passes 67 cases in 6.76s, with one other test filtered out. |
| Canonical parser regressions | Both hierarchy tests pass in 9.91s; one selected flat-parser test passes, with seven filtered out. |
| Literal decoder and reply encoder | The final direct contract executable passes with no host/allocation calls. A direct native model checks 389 records in one process: 270 decoder and 119 reply records. These are not two current Rust-libtest passes. |
| Native KV query | Eighteen direct query cases and three no-file-access traces pass on completion source `9a83795a...`. |
| Query owners and output | Sixteen allocation cases pass, including 13 reached OOMs and three baselines. Twelve output cases pass: three baselines and nine fault/recovery cases. Full traces verify pre-exit releases, not live ACK checkpoints. |
| Existing response workflow | The 55-case response group passes again on source `9a83795a...`, including 18 source OOMs. It is separate from query counts and the historical response-source receipt. |
| Bash function and terminal insertion | Final adapter `f7934bc9...` passes 51 function cases under two option profiles, 26 real PTY cases and two additional fresh-cwd quote-transition cases with exact executed argv. |
| Host deadline guard | Two controls pass on watchdog source `8a1fc69f...`, unchanged by final insertion edits. Both held shells show producer/watchdog/sleep children gone before exit. |

Sources are flat parser `b47aae72...`, routing `5dae9842...`, completion
`f863a063...`, literal words `2b086426...` and reply framing `b6036015...`.
The final host adapter is `f7934bc9...`.
Receipts under `target/stdlib-work/` include `completion-core-contracts-no-host`,
`completion-core-model-first.log`, `completion-hierarchy-regressions-first.log`,
`completion-flat-parser-regression-first.log`,
`completion-bash-contracts-final-no-host`, `completion-bash-model-native-first.log`,
`completion-kv-query-diagnostic-retry.log`,
`completion-kv-query-{allocations,output}-first.log`,
`completion-kv-response-regression-argument-retry.log`,
`completion-bash-pty-quote-retry{19-boundary,20,21-function}.log` and
`completion-bash-pty-quote-retry14-deadline.log`. The first response regression
invocation used an incorrect harness argument order and failed before native launch; it
adds no cases. Three Bash/shell/resource Rust drivers have separate combined
`--no-run` admission in 3.56s. The final shell driver separately builds in 1.75s
(`completion-shell-final-driver-build-first.log`); neither build executes native
Rust tests. Pure no-allocation traces do not prove OOM recovery. The current native target is Linux x86_64 CPU output
from the GPU compiler; user-program GPU execution is not established.
The accepted response checkpoint `68189363` and source `789143f6...` retain
their separate historical scope below. This completes the selected CLI increment.
Other shells, arbitrary Bash expansions, host glob memory/time bounds and the
full library goal remain open. The URL-based client now has its separate finite
acceptance above; existing numeric clients and URI utilities retain their
own scopes. The [dependency ledger](library-dependencies.md) remains
separate from accepted finite API evidence.

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
| [Response-checkpoint KV application](extended-kv.md#historical-response-application-receipts) | The response group passes 55 overlapping process cases, including all 18 source allocation denials in its nested-help baseline, one post-database OOM and the published/unsynced status 6 case. The latter cases are included in 55. |

Portable sources are tokenizer `a997585c...` and expansion `35b6ee83...`;
the provider is `461037b8...`. The response-checkpoint application is
`789143f6...` with artifact-aware oracle `057bb27a...`. Receipts under `target/stdlib-work/` include
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
target; no user-program GPU execution follows. Completion has its separate
implementation/acceptance status above; richer application policy and the
broader library goal remain open. Fixed-base lookup
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
Targets remain native Linux x86_64 CPU output from the GPU compiler. Completion
has its separate current scope above; richer application validation and the
full library goal remain open. Response preprocessing has its separate acceptance scope above; no
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
iteration and hashing without copying. Its cursors already use the shared
iterator protocol. The [bidirectional extension](stdlib-bidirectional-text.md)
adds line traversal and backward scalar/word pulls; its runtime acceptance is
established by seven new library gates. The line-summary application separately
passes four groups/102 native cases.
The [byte stream APIs](stdlib-streams.md) provide shared reader/writer
contracts, owned byte buffers and native descriptor adapters.
The [generic hash map](stdlib-hash-collections.md) provides hashed lookup,
explicit allocation errors and returned displaced keys/values. The new
[scoped HashMap/TreeMap value update](stdlib-map-updates.md) preserves the stored
key while restoring the callback's latest value descriptor. All seven new
library gates and four word-concordance groups/103 native cases pass.
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
have earlier normalizer, generated round-trip and allocation-failure receipts
scoped to their recorded sources. The current JSON streaming normalizer's
acceptance status is recorded separately above.
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
