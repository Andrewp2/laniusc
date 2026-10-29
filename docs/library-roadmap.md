# Standard and extended libraries

The goal is a complete, usable standard library and a broad extended library,
with Lanius interfaces and explicit native bindings for host and third-party
services. This document tracks the whole scope. Completing the first
milestone does not complete the goal.

## Dependency layers

| Layer | Owns | May depend on |
| --- | --- | --- |
| `core` | Values, borrowed views, algorithms, codecs | Compiler intrinsics with explicit target contracts |
| `alloc` | Allocators and owned portable data structures | `core`, allocator bindings |
| `std` | Application interfaces and host services | `core`, `alloc`, explicit host bindings |
| `ext` | Larger optional libraries | The layers above and declared extended-library dependencies |

Allocation-backed collections use `alloc` with explicit failure contracts.
The earlier map, set, byte-vector and UTF-8 owners have been removed after
migrating their consumers. The protected `std::vec` remains heap backing and
retains active formal vector specification/template contracts. The heap
migration has a separately recorded compiler dependency. The mini compiler
and extractor now use `List`; the
[dependency ledger](library-dependencies.md) records why vector retirement
still requires coordination. Do not add
forwarding modules solely to preserve internal paths. Extended modules can use
an additional source root in this repository;
package distribution is a separate deliverable.

## Standard library scope

| Family | Required contents | Executable state and remaining work |
| --- | --- | --- |
| Fundamental values | Option, Result, ordering, comparison, hashing, cloning, explicit errors | Generic Option/Result execute; partial equality/order are distinct from total equality/order, with explicit total float keys. Explicit TryClone/Destroy protocols, String implementations and opt-in exact scalar/Option/Result/Pair compositions execute with typed errors and manual memory-owner release. True empty Infallible errors retain the existing enum tag layout; nested owners and typed rollback pass executable tests. Some generic forwarding and record extraction compositions remain compiler dependencies; automatic ownership and implicit derive/move/drop remain |
| Numbers | Every primitive width, checked/wrapping/saturating arithmetic, conversions, bit operations, floating-point utilities | Canonical primitive-width arithmetic, bits and conversion policies execute; seven obsolete number/byte helper modules are removed and their ordinary consumers migrated. Pointer widths explicitly describe x86_64. Binary32/binary64 bit, rounding, square-root, decimal and precision-formatting APIs execute, as do full-range binary64 elementary functions with documented accuracy evidence. Native floats use partial comparison with explicit total keys. Represented two-word values remain an explicit separate API |
| Borrowed data | Arrays, slices, ranges, searching, sorting, partitioning, copying | Generic algorithms and counted View values execute, including subviews, checked mutations and cursors. Seven [comparator-driven View algorithms](stdlib-slice-ordering.md) pass all six new library gates, including heterogeneous first/last searches, independent order/permutation models and owner/scale observations. The real sort-rows program passes four gates/122 process cases, and three selected iterator migration regressions pass separately. One canonical ordering trait and shared Natural engines preserve raw Ord policies. Initial physical counts still require compiler length projection; manual backing and comparator/owner effects remain explicit |
| Iteration | Explicit iterator protocol, ranges, slices, collections, text, adapters, consumers | The [eight reduction/reverse-fold/bounded-fold consumers](stdlib-iterator-folds.md) pass all seven new library tests and four byte-summary groups/87 native process cases, with selected regressions and compiler dependency checks separate; prior receipts below retain their API/source scope. [Double-ended traversal and borrowed Rev](stdlib-iterators.md#double-ended-traversal) now share one non-crossing remainder with permanent either-end exhaustion and explicit dual trait bounds. Four registered reverse tests pass, including 7740 model commands, no-allocation pure contracts, seven matched owner releases and two bound rejections; the real timeline-tail program passes four registered tests/71 cases. Selected leaves and Map/Filter/FilterMap/Chain support reverse; other listed adapters retain their forward bounds. Manual lifetimes, callback pull order and cleanup remain explicit; reverse support alone gives no exact-size or automatic ownership claim. The separate [exact-size protocol](stdlib-exact-size-iterators.md) now passes four registered library gates and a real sample-bytes application with four gates/95 process cases; selected finite leaves/adapters retain explicit alias/count bounds. The shared fused Iterator<T> protocol executes for canonical slice/chunk/window cursors, full-domain i32 ranges, fixed-capacity Vec/Set, owned Vec/deque/heap/hash/tree map/set cursors, bitsets, Text bytes/scalars and text splits. Borrowed take/chain/map/zip/filter/filter_map/skip/take_while/skip_while, checked u64 enumeration, searches, boolean consumers and ordinary/fallible left folds execute with explicit effects and shallow cleanup. Recoverable one-item lookahead, relative/MAX position search and ordinary/custom extrema execute with explicit first-minimum/last-maximum tie policies. Bounded fallible transfer collects into fixed/owned Vec, deque, hash/tree maps and sets, and Min/Max heaps, returning rejected items and accepted-prefix progress. Map/set sinks reject duplicates while preserving stored representatives. Separate native models cover cursor state, selection/copy/callback order, short circuits, transfer recovery and source resumption; owner traces check allocation behavior. Range-dot, window-report, column-sum/extrema, word-sort and identifier-index programs exercise composition and errors. Owning Vec/deque/hash/tree map/set and heap cursors transfer cleanup authority, retain exhausted backing until explicit finish, and recover valid remaining collections in O(1), with explicit nested cleanup. Hash traversal is unordered; tree and heap priority pulls use O(log n) removal. The unique-word application now publishes through the TreeSet owning cursor. Scan/TryScan and TryFlatten/TryFlatMap share the canonical protocol with explicit inner retirement, updated-owner recovery and fused errors. Their accepted historical freeze has two direct public smokes, three semantic/model Rust gates, four fallible flatten_sum tests and four direct owner groups (156 overlapping group cases/132 reached OOM runs). Ordinary Flatten/FlatMap now use the same engine with real empty Infallible retirement: a direct public smoke, two semantic/model Rust gates, three negative-bound tests, eight direct live-owner cases and the migrated ordinary flatten_sum groups pass. The current application has 219 overlapping direct group cases, separate from the older Rust-test receipt. Replacement sinks now have two semantic Rust gates, five negative-bound tests, five direct owner groups (219 overlapping cases/183 reached OOMs) and four direct latest-values groups (248 overlapping cases) accepted; direct oracle groups are not Rust-libtest receipts. Further adapters/consumers, other owning cursor families and language for-loop integration remain |
| Text | Borrowed UTF-8, owned String, Unicode scalars, byte boundaries, search, split, trim, join, parse, formatting | Packed String, borrowed Text, scalar/word iteration, join/repeat, integer/float conversion, caller-buffer Display, runtime format strings and owned formatting execute. Alignment counts scalars and numeric precision rounds exact binary values. Optional extended modules provide Unicode 17 full casing, normalization, default word/grapheme boundaries and an explicit terminal width policy. Runtime formats also render to generic byte writers through bounded caller scratch, with preflight validation, exact accepted-prefix failures and a direct-call limit. Richer format controls and collation remain |
| Memory | Allocation contracts, layout, owned buffers, arenas, explicit destruction and clone behavior | Allocator bindings, raw views and stable chunked arenas with generic typed allocations execute. [Fallible View cloning](stdlib-clone.md) constructs independent String/user-record memory owners and releases completed destination elements on error. Layout consolidation, compiler-enforced lifetimes and automatic destruction remain |
| Collections | Vec, deque, hash map/set, ordered map/set, heap, bitset, fixed-capacity containers | Borrowed-owner alloc Vec, deque and bitset, inline generic Vec/Eq Set, hash/tree maps and sets, and min/max heaps execute. Owned sets include representative ownership and all four fallible algebra operations through shared map engines. Explicit TryClone/Destroy View cloning now composes through nested Vec types with independent owners, typed error layers and recursive cleanup. Opt-in deep HashMap cloning executes with independent nested owners and typed key/value failure cleanup; opt-in recursive deque cloning also executes with logical ring and owned-error rollback coverage. Opt-in deep heap cloning also executes with Min/Max priority and nested/owned-error failure coverage. Opt-in deep TreeMap cloning also executes with sorted staging, independent nested owners, typed key/value rollback and empty/zero-sized coverage. Existing inherent collection clone methods retain shallow entry/key/value copies. Silent-failure legacy map/set/text owners are retired. Opt-in deep HashSet and TreeSet cloning also execute with typed rollback and representative-preserving models. The protected std::vec/heap migration, additional owner compositions and automatic ownership remain |
| I/O | Reader/writer contracts, buffers, exact/all operations, cursors, positional access, stdin/stdout/stderr, errors | Shared traits, cursors, owned sinks, descriptor/file adapters and reusable multi-descriptor readiness execute. The [positional-I/O family](stdlib-positional-io.md) now has portable ReadAt/WriteAt, attempt-bounded exact/all helpers and staged File adapters accepted on the finite native profile, with a separate 11012-case portable model and real file-patch application (four groups/82 process cases). One selected old FileOps regression passes separately; a focused amended native-contract rerun checks full-span rejection before staging, without adding a new test identity. Whole spans, confirmed-prefix errors, unchanged shared cursors and append/direct restrictions are explicit. Polling preserves old publication on errors and uses explicit observed deadlines. Imported/nested generic Read/Write transport passes native contracts and checked cache reuse. Fixed-capacity buffered adapters execute with read-ahead/pending handoff, explicit finish/discard, partial-I/O and allocation failures, nested composition and a binary-copy application. Runtime writer formatting shares these contracts and leaves flush/finish explicit |
| Files and paths | File handles, metadata, directories, walking, lexical paths, filesystem operations | Owned files and paths, lexical operations, checked mutations, configurable/relative opens, seek/resize, metadata, sync, duplication, raw directory iteration and bounded anchored walking execute on native Linux. The [advisory whole-file locking increment](stdlib-file-locks.md) passes seven new library tests and four locked file-patch groups/49 cases on its finite local Linux profile, with explicit duplicate/conversion/manual-cleanup limits. Bounded copying checks descriptor capabilities and inode aliases before truncation, preserves progress on error and tests actual EOF even for zero-size pseudo-files. Real copy and directory-report applications check output and cleanup. Named TempFile ownership and descriptor-relative Replace/NoReplace/removal pass five native groups on the documented Linux/ext4 profile. AtomicFile's bounded publication/recovery owner passes 66 process invocations across four groups. The current anchored hierarchy kv_tool passes 130 overlapping cases across three direct groups; its earlier no-SCRATCH 64-case receipt retains its historical source scope. Checked descriptor-relative directory creation/removal now passes namespace24/bounds19/faults12 invocations across three groups. These finite receipts preserve visibility/durability/cleanup distinctions without locking or universal crash guarantees. Checked link/readlink and descriptor/path permissions pass five groups totaling 139 accepted group cases; mktemp_dir passes 48 process invocations. TempDir passes all four groups totaling 46 accepted group cases. Automatic owner destruction and broader platform support remain |
| Processes and environment | Arguments, environment, working directory, subprocesses, pipes, exit status | Raw-byte snapshots, explicit argv/environment/PATH/cwd, fork/exec, redirected files, owned pipes, cached waits and child signaling execute on the documented single-threaded Linux profile. Bounded concurrent stdin/stdout/stderr capture preserves partial progress, startup certainty and child ownership across errors. Explicit new groups, anchored signaling and non-reaping observation pass five focused API groups; a TERM/grace/KILL supervisor passes five groups and 53 cases, across separate receipts. Group escape/containment and concurrent spawn policy remain |
| Time and randomness | Duration, instant, system time, deadlines, deterministic generators, OS entropy | Typed nanosecond arithmetic, calendars, native clocks, deadline waits, deterministic generators, sampling/shuffle and checked OS entropy execute. Optional TZif/POSIX zones provide conversion and ambiguity candidates; four continuous and four discrete distributions have bounded generic sampling and explicit numerical domains. Additional clocks and distribution families remain |
| Networking | Addresses, sockets, TCP, UDP, resolution, deadlines, explicit host errors | The [URL-client composition](extended-url-client.md) now executes with owned URL policy, ordered resolution/TCP selection, selected-socket adoption and separate plain/OpenSSL HTTPS facades. Two plain, one DNS and eight TLS cases pass as separate direct groups; connector admission12/failures8 and real-fetch functional24/33/4 retain separate scopes. Native NSS is still synchronous, manual owners remain explicit and full wrapper/application OOM coverage is unclaimed. Numeric IPv4/IPv6 and CIDR values, owned TCP/UDP, polling, deadlines, options and half-close execute via the Linux boundary. System hostname/service resolution delegates to libc with explicit hints and owned ordered results on Linux x86_64/glibc; all four library groups and five CLI groups pass across separate receipts. Blocking NSS memory/time are outside local byte/result caps. Optional DNS transport queries explicit numeric servers with correlated UDP/TCP fallback; bounded cleartext HTTP/1 client and staged server connections use explicit transport, deadlines and resource limits. At checkpoint 480432e8, resumable Prepared/Exchange passed all five direct groups (83 cases), one-thread/poll batches passed all seven groups, and fetch-many passed all five application groups across separate receipts. The current shared Protocol passes direct state/ownership execution; refactored plain synchronous/direct clients pass 188/83 cases, generic plain batches pass eight groups/103 cases and HTTPS batches pass six groups/108 cases through separate native receipts. The migrated HTTPS fetch and mutual-TLS application groups pass 63 and 101 cases respectively. The current fetch-many passes all five integration groups in 24.18 seconds; the nested-pattern compiler reduction is confirmed alongside an executable explicit-match control. Excluded buffered/prepared-context receipts retain their older scope. Older receipts do not cover the revised boundaries. Manual owners and one common deadline are explicit. Real TCP/DNS/fetch/local-service programs exercise transfers. Checked native C calls, OpenSSL digests and client TLS with peer verification execute. Client TLS requires explicit peer trust/identity, borrowed nonblocking sockets and caller deadlines/SIGPIPE policy; the preceding TLS stream/HTTPS application passed 62 cases across four groups with numeric endpoints, explicit trust/identity, deadlines and manual cleanup. Server TLS and a bounded HTTPS service execute through OpenSSL. Earlier client credential/required fresh client-chain verification receipts cover 107 cases across six groups; earlier prepared-context/mutual-TLS HTTPS modes cover another 109 cases across four groups. Unauthenticated public service remains an explicit policy. Application identity/authorization, broader certificate APIs, asynchronous resolution/NSS resource policy, interface discovery, complete concurrent-server acceptance, keepalive and broader client policies remain; old std::net declarations remain unbound |
| Native libraries | Checked C signatures, ordinary ELF linking, process startup and explicit library owners | The Linux x86_64/glibc profile executes integer/pointer/f32/f64/void calls with up to 32 total parameters, independent SSE/GPR banks, ordinary ELF objects and CRT startup. OpenSSL EVP digest contexts and a binary stdin hashing program execute with dynamic libcrypto.so.3. SQLite database/prepared-statement owners and a persistent binary key/value program execute with system SQLite, including typed values, transactions, real persistence/locking, native and staging-allocation failures, and a measured bulk workload. Native entry/package builds spool original/replay payloads and execute above the resident aggregate threshold; source snapshots/global metadata still grow and descriptor CLI modes remain unsupported. OpenSSL client TLS with peer verification executes with 34 cases across four groups. Server TLS also has 53 historical focused cases; mutual TLS adds 107 cases across six groups using shared native credential loading and explicit required-peer policy. The current independent retry/context-retention revision passes nine duplex groups/36 cases and three selected legacy retry groups/10 cases through separate current receipts. Callbacks, variadics, aggregate C layouts, foreign thread entry, standalone encryption/signature and broader certificate-trust APIs remain |
| Concurrency | Threads, joining, synchronization, atomics, channels, cancellation | At checkpoint 480432e8, bounded cleartext HTTP batches passed seven library groups and five application groups across separate native receipts, including queued admission after consecutive begin failures. The current generic scheduler and verified HTTPS adapter use the same one-thread/poll architecture. Plain batches pass eight groups/103 cases and HTTPS passes six groups/108 cases across separate receipts, including the causal wait-retirement regression. The current server scheduler has 17 scripted actual-Server profiles and four real plain/TLS causal passes, with the separately listed plain/HTTPS/mutual-TLS application groups and scale observations; a separate actual plain-driver gate passes two poll-fault cases and one calibration, with no increase to the scripted count. This does not supply worker execution or synchronization. Current thread declarations remain unbound; [concurrency admission dependencies](library-concurrency-dependencies.md) isolate callback/worker-entry, checked Boolean transport, ownership and ordering prerequisites |
| Development | Assertions, test runner, property helpers, benchmarks, diagnostics, API docs | Nontrapping checks, explicit source suites, filters, seeded properties, injected/native-clock benchmarks and a bounded native compiler/run driver execute. Selective, relocatable source bundles use the existing package resolver and verify inventory hashes. A generated declaration reference links signatures, bounds, source locations and reviewed contract guides. Automatic compiler discovery/runtime registration, binary SDK distribution and complete semantic API documentation remain |

## Extended library scope

Each entry needs a public API, executable implementation, examples, failure
tests, target support, and relevant performance evidence.

| Family | Deliverables |
| --- | --- |
| Data formats | JSON, CSV, TOML, binary serialization, schema/validation utilities |
| Text and parsing | Unicode properties and normalization, regex, lexers, parser utilities, diff and patch |
| Files and packaging | Globs, directory walking utilities, compression, archives |
| Network protocols | The [borrowed WebSocket server upgrade](extended-websocket-upgrade.md#server-api-and-policy-boundary) now pauses for caller policy before staging/flush and server-role conversion; a real [one-client echo service](extended-websocket-echo.md) passes eight separate native groups plus one Lanius-client integration. Six server and eleven current-client scripted scenario functions pass in separate raw processes; the shared bounded HTTP encoder passes three actual Rust runtime tests. Persistent/concurrent service and existing HTTP-server/scheduler adoption remain open. A [borrowed WebSocket client upgrade](extended-websocket-upgrade.md) and [frame stream](extended-websocket-stream.md) preserve coalesced bytes and partial I/O over the same caller-owned transport. One raw contract process executes eleven scenario functions; the real [one-message client](extended-websocket-once.md) passes separate plain9/rejection12/CLI17/I/O3/TLS5 groups on Linux x86_64/OpenSSL 3. Manual ownership, entropy/deadline policy, quotas and explicit cleanup remain required; broader server orchestration, ws/wss URLs and failure/target coverage remain open. [WebSocket upgrade responses](extended-websocket.md#http-upgrade-response-syntax) validate/encode portable 101 wire data using externally computed Accept; the separate OpenSSL helper and offline response tool retain their finite native provider/error and functional acceptance. [URL-based HTTP/HTTPS](extended-url-client.md) now composes strict owned URL policy, one ordered connector and the canonical clients with finite native exchange, boundary/failure and real-program functional acceptance. Original URL identity/Host, exact selected-socket transfer and no post-selection replay are explicit; remaining source-OOM and broader schedule coverage is documented. HTTP client/server, WebSocket request/frame processing, DNS and client TLS with peer verification through OpenSSL; TLS stream/HTTPS executes with numeric endpoints and explicit trust/deadlines/manual ownership; server TLS, required mutual TLS and bounded health/echo HTTPS modes execute; one-thread/poll cleartext batches and their CSV-to-ZIP application have separately accepted historical receipts; the current resumable HTTPS batches pass 108 connected cases, plain batches pass 103, and migrated HTTPS/mutual-TLS applications pass 63/101 cases through separate receipts; the current fetch-many also passes all five groups, and a minimal nested-pattern limitation plus executable explicit-match control are confirmed; excluded buffered/prepared-context receipts retain older scope; current server source has finite direct/scheduler/plain-and-TLS application passes but full concurrent-server acceptance, application authorization and broader orchestration remain open |
| Storage | Database interfaces; executable [SQLite integration](extended-sqlite.md), [persistent binary key/value application](extended-sqlite-kv.md) and key-value snapshots; broader database/storage interfaces remain |
| Security | Native-library cryptographic digests, encryption, signatures, certificate trust and TLS; OpenSSL EVP digests, verified client/server TLS and mutual TLS execute with explicit trust and manual owners; standalone encryption/signature APIs, application identity/authorization and broader certificate policy remain open |
| Mathematics | Big integers, decimal arithmetic, statistics, linear algebra, geometry |
| Application utilities | CLI option parsing, command hierarchies, caller-buffer generated help, bounded response-file preprocessing, canonical prefix parsing and portable completion, literal Bash-word decoding, reply framing, logging, configuration, tables and progress reporting; the Bash 5.2/bash-completion 2.11 adapter has finite function/PTY acceptance; richer application validation and other shell adapters remain |
| Media | Image codecs, pixel operations, audio codecs and signal utilities |

The [compiled byte-glob module](extended-glob.md) and its streaming path-filter
application execute on x86_64 Linux, including recursive components, explicit
work limits, raw byte paths and allocation/I/O failures. [Raw directory iteration
and anchored walking](stdlib-directory.md) now execute separately, with a
filtered directory-report program and explicit traversal budgets.

[Checked filesystem mutations](stdlib-filesystem.md) provide allocation-free
creation/removal of one directory, file unlinking and renaming over existing
host bindings. These operations retain Linux errors and do not recursively
traverse paths.

[Borrowed URI parsing](extended-uri.md), [component percent coding](extended-percent.md)
and a [component-extraction application](extended-uri-component.md) execute on
x86_64 Linux. Parsing validates generic RFC 3986 syntax while preserving encoded
spelling; decoding is an explicit later operation.
[Owned URI resolution and recomposition](extended-uri-resolve.md), including
RFC dot-segment removal, execute with a [command-line resolver](extended-uri-resolve-program.md).
The [owned HTTP(S) URL profile](extended-http-url.md) and its [connected-client composition](extended-url-client.md) now have separate finite native acceptance; other scheme/protocol policies remain work.

[Raw DEFLATE encoding](extended-deflate.md), [raw decoding](extended-inflate.md)
and [owned zlib/gzip containers](extended-compression.md) execute with a
[binary stdin/stdout application](extended-compress-bytes.md). The decoder
accepts stored, fixed and dynamic trees; the fast encoder selects fixed Huffman
LZ77 or smaller stored blocks. Gzip headers, concatenation and checksums are
validated. [Adler-32](stdlib-adler32.md) provides the portable zlib checksum.
Preset dictionaries and resumable codec state remain separate work.
Native and compiler performance is recorded in
[compression performance](extended-compression-performance.md).

[POSIX ustar archives](extended-tar.md) and
[classic single-disk ZIP archives](extended-zip.md) provide executable archive
profiles: metadata, member data, multi-member writing and explicit format,
capacity, checksum and resource failures. Binary
[TAR/gzip](extended-tar-bytes.md) and [ZIP](extended-zip-bytes.md) applications
exercise creation, listing and exact member reads; ZIP also exposes complete
payload verification. Those codec APIs perform no filesystem extraction. The
new [namespace planner](extended-archive-plan.md),
[metadata profile](extended-archive-profile.md) and
[complete source owner](extended-archive-source.md) now have finite native
acceptance. The shared [materializer](extended-archive-extraction.md) and
[unpack CLI](extended-unpack.md) are implemented; 74 CLI process invocations
pass across libtest-driven and retained-ELF receipts; direct Run's 11 Python
oracle groups pass 100 process invocations separately. GNU/PAX TAR
extensions, ZIP64, encrypted and multi-disk ZIP remain unsupported and report
explicit errors. [Archive compilation evidence](extended-archive-performance.md)
and the application docs record target support and scale measurements.

[CBOR wire events](extended-cbor.md) provide binary serialization for all major
types, full-width integer arguments, exact float bits, tags, arbitrary map keys
and definite/indefinite structures. The iterative codec uses caller scratch,
strict UTF-8 and explicit resource bounds. A [ZIP manifest program](extended-zip-manifest.md)
checks all archive payloads, then emits CBOR with exact raw byte names.
CBOR application schemas and tag-specific semantics remain separate work.
The [foundation compilation measurements](library-foundation-performance.md)
record executable import workloads for arenas, network values, CBOR, floating
conversion, exact decimal numbers and JSON validation.

[JSON validation](extended-schema.md) implements a documented JSON Schema
2020-12 profile with exact numbers, structural equality, local references,
combinators, objects, arrays and Unicode scalar lengths. Unsupported keywords,
dialects and reference forms fail explicitly. The
[json-check program](extended-json-check.md) validates a file-supplied schema
against stdin, with resource, allocation and I/O failure evidence.
[Borrowed decimal numbers](stdlib-decimal-number.md) retain arbitrary coefficient
and exponent precision for comparison/integer/divisibility behavior.
[Owned unsigned integers](extended-big-uint.md) and
[signed integers](extended-big-int.md) supply arbitrary precision arithmetic,
radix conversion, division, shifts, bitwise operations, powers and GCD, with
explicit limits, ownership and allocation failures. A
[streaming calculator](extended-bigcalc.md) executes twenty operations across
multiple radices. [Owned finite decimals](extended-decimal.md) add arbitrary
precision coefficients, quantum-preserving exact arithmetic, explicit rounding,
precision-limited division, conversions and lawful numeric keys. A
[CSV ledger](extended-decimal-ledger.md) calculates rounded line subtotals,
taxes and running totals without binary floating point. Signed decimal zeros,
NaNs/infinities, transcendental decimal functions, additional number-theory
algorithms remain separate work.

[Statistics](extended-statistics.md) provides checked streaming moments,
covariance/correlation, simple linear fits, compensated sums, scaled norms and
all nine standard sample-quantile formulas.
[Weighted second moments](extended-weighted-statistics.md) and
[unweighted third/fourth moments](extended-higher-statistics.md) now have separate
modules and explicit population/reliability or population/adjusted estimator
names. Their focused native contracts/models execute, and the real
[sample-moments CSV program](extended-sample-moments.md) passes 66 process
cases across four registered tests.
[Linear algebra](extended-linalg.md)
provides counted strided matrices, owned matrices, products, pivoted LU and
Householder QR least squares, with explicit numerical and resource limits.
The [numerical CSV analyzer](extended-data-analyze.md) combines both libraries
for summaries and optional multiple regression. These are binary64 APIs;
weighted higher-order moments and advanced decompositions remain work.
The [canonical CSR foundation](extended-sparse.md) has borrowed kernels,
independent owners and sparse/dense arithmetic. All six library runtime gates
and four graph-application gates pass on the finite Linux x86_64 profile.
The separate [sparse-product increment](extended-sparse-product.md) defines
CSR-times-CSR multiplication in Lanius. All six new library and four real
application gates pass on the finite Linux x86_64 profile. The separate
[CG solver](extended-sparse-cg.md) passes all six new library and four real
application gates. Other iterative/direct solvers, sparse factorizations and
additional formats remain separate. The [graph-walk application](extended-graph-walk.md)
composes actual CSR construction/transpose/matvec with its own finite policy.
[Normal, exponential, gamma and beta distributions](extended-distributions.md)
add densities, paired tails and bounded generic sampling, with a
[CSV sampling program](extended-sample-distribution.md). Their ordinary and
large-shape accuracy profiles are explicit.
[Bernoulli, binomial, geometric and Poisson laws](extended-discrete-distributions.md)
add masses, paired/log tails and bounded generic sampling, with a
[count simulation program](extended-sample-counts.md). Only Bernoulli claims
an exact dyadic law; the other samplers have explicit finite-grid numerical
contracts, and ordinary/large evaluator accuracy profiles remain separate.
Geometry, elementary functions and signal algorithms
are documented below.

[Owned bitsets and counted views](stdlib-bitset-owned.md) add checked bit/range
edits, searches, shifts, set algebra, cursors and explicit allocation failures.
The [prime sieve](stdlib-primes.md) exercises them through twenty million
candidates. Calendar values also supply lawful comparison/hash traits for
generic ranges, sorting and collection keys; civil ordering and offset
representation equality have separate documented contracts.

[Unicode 17.0.0 properties](stdlib-unicode.md) cover the full code point range
for the documented property set and simple/default/Turkic scalar mappings.
[NFC/NFD/NFKC/NFKD normalization](extended-unicode-normalize.md) and
[default extended grapheme segmentation](extended-unicode-graphemes.md)
execute with static generated tables and official conformance corpora. A
[text-normalization program](extended-text-normalize.md) handles bounded UTF-8
stdin and optional scalar/grapheme statistics, including binary NUL and
allocation/I/O failures. [Default word boundaries](extended-unicode-words.md)
and [full root/Turkic/Lithuanian casing](extended-unicode-case.md) now execute,
including original-input context and default title boundaries. A
[casing program](extended-text-case.md) exposes lower/upper/title/fold over
bounded UTF-8. [Default sentence boundaries](extended-unicode-sentences.md) and
[default line opportunities](extended-unicode-lines.md) now pass the complete
versioned official corpora. [Sentence reporting](extended-text-sentences.md) and
[greedy terminal wrapping](extended-text-wrap.md) exercise them in real programs.
Locale-sensitive collation, dictionary segmentation and shaping remain work.

[Regular expressions](extended-regex.md) execute a documented UTF-8 dialect
using ordered Pike matching, with captures, greedy/lazy repetition, scalar
classes and Unicode 17 properties. Unsupported syntax fails explicitly. A
[streaming search program](extended-text-grep.md) compiles once and processes
bounded UTF-8 records with counts, numbering and inversion. Wider regex syntax
and additional replacement interfaces remain.
[Bounded splitting and replacement](extended-regex-text.md) now provide
borrowed fields, independent literal/numeric-template output and conservative
aggregate VM allowances through the existing matcher. The new lazy Search
workspace integration passes all seven current groups across separate receipts,
including lazy-admission, 288 model cases, 89 tables, all 41 reached library and
25 CLI OOM positions, exact CLI output and four I/O schedules. Prior six-group
receipts retain their older lifecycle/allocation scope.
[Reusable lexical scanning](extended-lexer.md) now shares the regex engine's
anchored longest-prefix mode. It validates each input once, returns borrowed
tokens, chooses the earlier rule for equal longest spans and rejects
nonprogress, unmatched input and exhausted caps explicitly. Nonempty cursors now
own one reusable two-slot workspace sized to the largest actual rule program;
empty input needs none. All six current groups pass owner/admission/contracts,
576 model cases, 63 explicit tables and all 30 reached OOM positions. The older
120-OOM receipt describes the per-probe implementation. Competing patterns can
rescan suffixes, so input, search-call and reserved-work limits remain explicit.
The [CSV-rules lexer application](extended-lex-scan.md) composes CSV decoding,
compiled rules, borrowed tokens, hash counters and staged bounded output. Its
five current native groups pass both modes over 124 independent grammar inputs,
boundary/admission/I/O controls and all 30 reached allocation positions per mode.
The 4,096-token observation records 32 verified source requests, 8,895 total
requested bytes and 6,868 peak live requested bytes with balanced releases.
Its 79.624585ms traced harness time includes setup and verification; no isolated
application throughput or compiler-speed claim follows. The retained
[generic Read context dependency](library-context-inference-dependencies.md)
has a rejected unannotated reduction and an executed explicitly typed control.
[Text parsing cursors](extended-parse.md)
provide checked locations, spans, checkpoints and atomic bounded scanners.
The [integer expression calculator](extended-expr-calc.md) combines them with
inline stacks, checked arithmetic and runtime formatting.

[Shortest line edit scripts](extended-diff.md) and
[strict unified patches](extended-patch.md) compare arbitrary bytes and apply
changes exactly in memory, with explicit trace/work limits, conflicts and owner
cleanup. The [file comparison and patch program](extended-text-patch.md) emits,
applies and checks single-file patches through real files and stdin/stdout.
Filesystem patch orchestration and additional diff granularities remain.

[Runtime format strings and owned formatting](stdlib-format-strings.md) add
typed positional/named arguments, scalar fill/alignment/truncation, signed radix
controls and exact [float precision formatting](stdlib-float-precision.md).
Unsupported syntax fails explicitly. [Inline collections](stdlib-fixed-capacity.md)
now use explicit Full/Bounds/absence outcomes, return displaced elements and
use lawful full equality for sets. Borrowed free functions preserve symbolic
element and capacity parameters. Imported method lookup with symbolic capacity
has a reduced compiler dependency and successful controls. [Owned sets](stdlib-owned-sets.md)
now execute through shared map owner-state boundaries; the older nested wrapper
failure is preserved separately from the production support claim.
A general Display-to-owned-String helper also remains excluded after a minimal
compiler failure; typed owned formatting executes independently. The
[dependency record](library-dependencies.md) preserves the exact contexts.

[Native 64-bit and pointer-sized integers](stdlib-native-integers.md) provide
checked, wrapping and saturating arithmetic, division, shifts, bits and all
integer-width conversion policies. Native tests compare 84,100 cases with each
independent Rust/i128 and Python bigint reference and check 54 strict traps.
The [source test workflow](stdlib-development.md) adds explicit suites,
nontrapping checks, deterministic properties and actual benchmark measurement.
It does not claim compiler discovery or trap recovery. The repository's
stdlib-heavy workload generator now uses the same borrowed collection APIs;
default, string-heavy and directed record mixes execute against its model.

[Collection consumer migration](stdlib-legacy-collections.md) removes ten
silent-failure owner/specialization modules and moves fifteen programs to
checked alloc owners or bounded storage. The [standard library entry guide](../stdlib/README.md)
and [extended module index](../extended/README.md) expose current module paths.

[Exact planar geometry](extended-geometry.md) handles full-i32 predicates,
segments, rings and hulls, with finite floating vector/affine utilities. A
[CSV hull program](extended-shape-hull.md) exercises exact topology and area.
[Terminal width policy](extended-terminal.md), [tables](extended-table.md) and
[progress rendering](extended-progress.md) supply bounded Unicode-aware output;
a [CSV table program](extended-csv-table.md) integrates them. Width is an explicit
policy rather than a universal terminal measurement.

[Image buffers](extended-image.md) and [PNG codecs](extended-png.md) provide
checked RGBA operations, all standard input color/depth combinations, Adam7,
filters, CRC/order validation and RGBA8 encoding. A
[PNG transformation program](extended-image-tool.md) exercises crop, rotation
and flips. [Finite audio](extended-audio.md) and [WAVE codecs](extended-wave.md)
provide PCM/IEEE/extensible conversion, exact mean/DC/mono behavior, scaled RMS
and checked signal operations through a [WAVE program](extended-wave-tool.md).
[Signal processing](extended-signal.md) adds checked complex values, radix-2
FFT/inverse, windows, convolution and spectral bins. The
[WAVE spectrum program](extended-wave-spectrum.md) combines downmixing, optional
FIR smoothing and windowed FFT into CSV. Color management, other image/audio
formats, playback and additional signal algorithms remain work.

[HTTP/1 wire processing](extended-http.md) implements requests/responses,
framing, chunk extensions/trailers, exact boundaries and checked writers. Its
[offline message program](extended-http-message.md) validates and decodes real
wire bytes. An [allocation-free incremental cursor](extended-http-cursor.md)
finds boundaries without retaining views into growing storage. The
[connected HTTP/1.1 client and fetch program](extended-http-client.md) compose
it with numeric-address sockets, owned responses, one deadline and explicit
byte/work/I/O limits. Canonical parsing validates each selected response;
informational responses and early final replies retain exact association and
progress. The shared client exposes Prepared staging and resumable Exchange
steps with explicit readiness and bounded network quanta. At `480432e8`,
all five direct [Exchange groups](extended-http-exchange-testing.md) passed
83 cases across separate receipts, alongside all six synchronous regression
groups (188 cases).
[HTTP batches](extended-http-batch.md) reuse that engine with one thread and a
reusable PollSet, input-order partial outcomes, one common deadline and manual
response transfer. Logical pending/wire/body retention caps are separate from
allocator capacity and peak RSS; scheduler operations and reserved protocol
work are explicit. All seven batch groups and all five
[fetch-many CSV-to-ZIP application](extended-fetch-many.md) groups passed
across separate native receipts at that checkpoint, including queued admission
after consecutive begin failures without a blocking poll on remaining peers.
The current Protocol state/ownership group passes separately with 247 explicitly balanced mappings and no network calls; revised synchronous/direct clients pass 188/83 cases and plain batches pass eight groups/103 cases through separate receipts.
The [resumable HTTPS client](extended-https-client.md) and
[HTTPS batch adapter](extended-https-batch.md) pass six connected native groups
and 108 cases across separate receipts. The migrated HTTPS fetch and mutual-TLS
application groups pass 63 and 101 cases respectively, with prepared-context
streams excluded. Fetch-many also passes all five current integration groups;
minimal compiler controls confirm the remaining nested-pattern dependency.
Historical HTTP/TLS receipts do not
cover the current revisions. Worker-thread orchestration remains separate work, as recorded by the
[concurrency admission audit](library-concurrency-dependencies.md).
A [staged HTTP/1 server connection](extended-http-server.md), accepted
at `493d4e87`, handles one request and one closing final response per connection,
with immutable published head/body views, explicit 100 Continue, checked Date
and response staging, one deadline, quotas and half-close/drain cleanup. Its
real local health/echo service accepts numeric IPv4/IPv6 endpoints and bounded
sequential connections. Independent peers and injected resource/host failures
exercise framing, early rejection, binary bodies and owner cleanup. A separate
[HTTPS service](extended-https-server.md) now composes the same codec with
OpenSSL server TLS, shared buffered streams, bounded acceptance and one absolute
deadline per connection slot. Those are historical sequential-service receipts.
The [current resumable-server increment](library-server-concurrency-plan.md)
implements shared protocol ownership, explicit application decisions and one
bounded HTTP/HTTPS scheduler. Current direct plain cases, the synchronous
facade, direct HTTPS cases, scripted scheduler controls and four real plain/TLS
concurrency cases have finite native passes; the [current-work checkpoint](#current-work)
records their separate scopes and remaining gates. Complete concurrent-server
acceptance, redirect policy, connection pooling, keepalive, upgrades/tunnels
and HTTP/2 remain work. The separate [URL client](extended-url-client.md) now
performs explicit ordered system resolution and selected-socket adoption for
one HTTP or verified HTTPS exchange; it adds no server orchestration.

[DNS wire processing](extended-dns.md) validates binary names, compression,
QUERY sections, common RDATA and EDNS, with bounded complete message writing.
[WebSocket processing](extended-websocket.md) provides RFC 6455 request/response
processing, role masking, fragmented UTF-8, control/close state and frame
generation. Response validation preserves a borrowed post-head frame view;
response generation accepts an externally computed Accept. A separate
[OpenSSL helper](extended-openssl-websocket.md) supplies the digest through
libcrypto, and the [offline upgrade tool](extended-websocket-upgrade-program.md)
produces a checked 101 head from an EOF-terminated request. Current response/
provider/tool receipts are separate from historical frame/request tests.
The [generic client-upgrade layer](extended-websocket-upgrade.md) now owns
request/response storage and copies the coalesced frame prefix transactionally
into a [borrowed frame stream](extended-websocket-stream.md). The caller retains
and exclusively assigns the same transport; destroying either adapter never
closes it. The [one-message client](extended-websocket-once.md) supplies real
numeric TCP/verified DNS TLS, OS entropy, one cooperative deadline and Close/
cleanup policy before output. A raw scripted contract executable and separate
plain9/rejection12/CLI17/I/O3/TLS5 direct app groups pass on Linux x86_64.
The appended [borrowed server state machine](extended-websocket-upgrade.md#server-api-and-policy-boundary)
now validates a request before a no-write caller policy pause. Explicit accept
stages a canonical response; inner flush precedes Ready and Role::Server
conversion. Captured request-tail bytes are rejected. Six server scenarios and
the original eleven client scenarios pass in separate current raw processes.
The real [echo service](extended-websocket-echo.md) adds numeric IPv4/IPv6 listen,
optional exact Origin and route policy, OpenSSL server credentials, one-client
lifetime and a cooperative deadline. Eight direct groups and one real Lanius
client integration pass. The [HTTP encoder](extended-http.md) adds bounded size/
field preflight and exact output reservation; all three focused Rust runtime
tests pass. Existing HTTP-server Protocol/scheduler adoption, persistent/
concurrent service, ws/wss URL policy, automatic ownership, arbitrary schedules
and allocation-failure proofs remain separate work. Offline wire/provider
receipts retain their earlier scopes.
The [owned socket API](stdlib-sockets.md) and [TCP exchange program](stdlib-tcp-exchange.md)
provide executable numeric-address TCP/UDP transport independently.
[DNS transport](extended-dns-client.md) now adds explicit-server queries, fresh
connected UDP attempts, fixed retry windows, full-question correlation and one
framed TCP fallback, with a real DNS query program. Independent loopback peers,
late-success deadline tests and allocation/host faults verify the implemented
profile. This supplies neither system resolver/NSS policy nor DNS authentication.

The separate [system hostname/service resolver](stdlib-resolve.md) now delegates
to libc `getaddrinfo` with explicit family, TCP/UDP, ASCII and mapping policies.
It preserves native ordering and duplicate addresses in an owned vector and
fails without partial publication on a result cap or unsupported native shape.
All four [native library groups](stdlib-resolve-testing.md) pass, including an
80-case independent libc matrix, malformed/error lists, exact result limits and
all four reached wrapper allocation failures. The
[resolve-host application](stdlib-resolve-host.md) adds staged numeric output
and passes all five groups, including real/scripted I/O and all seven reached
allocation failures. Acceptance combines separate receipts; the guides retain
the mixed invocations and corrected harness retries. NSS lookup remains
synchronous: local limits do not impose a
native allocation quota or deadline. Asynchronous resolution, interface policy
and authenticated DNS remain separate work.

[Explicit child groups](stdlib-command-groups.md) use the existing Linux
boundary for group creation, confirmation and signaling. An owned unreaped
leader anchors the original group; non-reaping observation preserves it while
capture drains descendant-held pipes, and final reaping revokes it. The
[run-group application](stdlib-run-group.md) adds observed run/grace/reap
deadlines and explicit TERM/KILL escalation, including a positive-leader
fallback. All five API groups and five application groups pass across separate
receipts; the supervisor covers 53 cases, including all nine reached pre-spawn
allocation failures. The guides retain the startup/fault harness correction
and focused retry, without claiming one combined passing suite run. Group escape,
outside reapers, arbitrary concurrent spawn and process-tree containment remain
outside this initial ownership contract.

[Byte key/value storage](extended-kv.md) provides atomic owned mutations and
canonical CRC-checked snapshots. Its file program uses
[AtomicFile](stdlib-atomic-files.md) to publish complete snapshots through one
anchored parent/leaf, with NoReplace init and Replace updates. The current
command-hierarchy migration passes three direct groups totaling 130 overlapping
cases, including reached allocation/I/O faults and explicit Published-unsynced,
unconfirmed visibility and retained-cleanup outcomes. Final traces observe every
syscall. The older 64-case AtomicFile CLI and caller-scratch receipts retain
their historical source scope. This finite local-filesystem
profile supplies neither locking nor concurrent transactions or universal
power-loss guarantees. A separate native
[SQLite adapter](extended-sqlite.md) and
[persistent binary key/value application](extended-sqlite-kv.md) now execute on
Linux x86_64/glibc, including real database files, transactions, write locks and
explicit native failure recovery. Their
[staging allocation gate](extended-sqlite-allocation.md) verifies all four
reached packing failures and exact mapping release.
[Persistent indexed ZIP snapshots](extended-archive-index.md) now compose
ZIP and SQLite: the archive-index program imports, lists, gets and exports exact
saved bytes. Its seven native groups cover binary names/keys, duplicate names,
independent snapshot owners, complete CRC preflight, pinned catalog validation,
explicit uncertain transaction outcomes, limits and allocation/native faults.
The separate content-only filesystem extractor is now implemented and executes
through finite unpack CLI and direct materializer receipts. Broader archive
formats remain work.

[Narrow primitive integers](stdlib-narrow-integers.md) now match the canonical
native-width policy families, with exhaustive byte arithmetic and independent
big-integer references. [Elementary binary64 functions](stdlib-math.md) include
full-range argument reduction and explicit IEEE behavior, checked against
high-precision independent references. These are Lanius implementations, with
licensed algorithm provenance retained in source.

[TOML 1.1.0](extended-toml.md) supplies owned typed documents and deterministic
encoding, with the complete versioned official valid/invalid corpus and resource
failure evidence. A [normalizer/checker](extended-toml-normalize.md) preserves
types, exact temporal fractions, negative zero and unknown offsets. Configuration
overlays include a [common typed settings facade](extended-settings.md) over
JSON, TOML and explicit/environment bindings. It preserves exact JSON numbers,
TOML types, shallow replacement and provenance without copying the input trees.
[Calendar values](stdlib-calendar.md) provide checked Gregorian day/ordinal/ISO
week arithmetic, RFC 3339 parsing/formatting and explicit SystemTime conversion.
[TZif time zones](extended-timezone.md) add historical offsets, supported POSIX
future rules and complete local-time ambiguity candidates with an inspection
and conversion program. Leap-bearing files and overlapping annual rule streams
fail explicitly; certified leap-second placement needs separate data/services.

[Selective source distribution](library-distribution.md) copies only the package
resolver's reachable closure, retains notices and verifies a sorted hash
inventory. Relocation tests delete the original source package and execute the
bundled calculator. Binary SDK installation, registry publishing and complete
semantic API documentation remain open. The
[generated declaration reference](library-api-reference.md) now inventories all
standard/extended source modules with deterministic source links and reviewed
guide mappings. Its unregistered-guide list makes documentation gaps visible;
it performs no compilation or execution verification.

For external formats and algorithms, use their primary specifications and
published conformance vectors. Choose exact versions and formats when starting
each family. Host and third-party integrations need explicit dependency and
availability contracts; do not substitute success-shaped placeholders.

## Delivery sequence

1. **Text and data foundation.** Packed byte buffers, owned UTF-8 strings,
   text operations, parsing, formatting, writer/reader contracts, hash maps,
   CSV and JSON. Acceptance application: read CSV, validate and group records,
   then emit JSON, including malformed-input and I/O failure cases.
2. **Everyday programs.** Iterators, remaining collections, files and paths,
   arguments, configuration, logging, clocks and randomness. Acceptance
   application: a directory report with filters and structured output.
3. **Connected programs.** Runtime bindings for sockets, processes and threads;
   HTTP, URLs, cancellation and synchronization. Native C ABI/linking support
   precedes established-library TLS and database bindings. Acceptance applications:
   the [bounded concurrent downloader](extended-fetch-many.md) and a local HTTP
   service. Downloaders and resumable verified HTTPS now use single-threaded
   poll scheduling. The [concurrent server increment](library-server-concurrency-plan.md)
   extends the connected-service workflow; it does not complete the separate
   [thread/atomic admission prerequisites](library-concurrency-dependencies.md).
4. **Storage and packaging.** Database integration, key-value storage,
   compression, archives, binary serialization and schemas. Acceptance
   application: a persistent indexed archive with checked round trips.
5. **Text, mathematical and media libraries.** Complete the remaining extended
   families with representative applications and their conformance suites.
6. **Distribution and completion audit.** Document installation and imports,
   verify selective dependencies, target support and compile-time scaling,
   and audit every row above against executable evidence.

Families can proceed independently once their dependencies have working
contracts. A compiler defect should have a minimal reproduction and an affected
API list; unrelated library work can continue.

[Checked C ABI calls and native linking](library-native-c.md) now execute on
Linux x86_64/glibc. [OpenSSL EVP digest contexts](extended-openssl-digest.md)
and the [binary stdin hashing program](extended-openssl-hash.md) use that profile
for SHA-256, SHA-512, SHA3-256 and SHA3-512. Native libraries perform all
sensitive operations; no Lanius, Rust or Python production implementation of
the cryptographic algorithms is introduced. C `f32`/`f64` calls now execute
with independent SSE/GPR register banks, exact IEEE transport and mixed
32-parameter stack/alignment coverage. An owned
[SQLite adapter](extended-sqlite.md) and
[persistent binary key/value program](extended-sqlite-kv.md) execute through
system SQLite, with typed values, transaction models, persistent files, native
locks and failure cleanup. Their guides record the completed gates and the
measured 32,768-insert/indexed-read workload.
[Client TLS with peer verification](extended-openssl-tls.md) now executes through OpenSSL 3,
with 34 cases across four groups for trust/identity, binary transfer,
closure/truncation and stable retries. [Server TLS](extended-openssl-tls-server.md)
also passes six groups and 53 cases, including explicit unauthenticated-client
policy, credential loading and native/allocation failure cleanup. Mandatory
client trust/identity rejection still passes after introducing session roles.
[Mutual TLS](extended-openssl-mutual-tls.md) now adds 107 cases across six
groups: client credentials, required fresh client-chain verification, purpose,
trust, stable retries and native/allocation cleanup. Required servers disable
resumption; certificate verification does not assign application principals or
permissions. Standalone encryption and signature APIs, and certificate trust
APIs outside TLS remain work. The
[TLS stream/HTTPS application](extended-https-fetch.md) also executes 62 cases
across four groups on Linux x86_64, using numeric endpoints, explicit trust and
identity, deadline/resource limits and manual owner cleanup. The
[prepared-context connector and mutual-TLS HTTPS modes](extended-https-mutual-tls.md)
add 109 process cases across four groups, including real client/server pairs
and failures before HTTP publication. The
[remaining native prerequisites](library-native-integration-prerequisites.md)
include callbacks and foreign threads. The separate
[concurrency admission audit](library-concurrency-dependencies.md) records
working direct/native scalar controls and the remaining checked Boolean,
callback/worker entry, owner-transfer and memory-order contracts; it does not
establish executable threads or compare-exchange. Native entry/package linking now spools
opaque sections and executes above one resident unit, while source snapshots
and global metadata remain resident. TCP/UDP,
OS entropy and noncryptographic CRC/Adler/FNV are also available.

## Completion requirements

- Public APIs perform their documented work. Unsupported operations fail
  explicitly and are excluded from executable support claims.
- Bounds, overflow, invalid encoding, allocation failure, partial I/O and
  resource lifetime have documented behavior and runtime tests.
- Tests import the real modules, compile Lanius programs, and execute them.
  Type checking alone is insufficient. Collection tests compare operation
  sequences with a reference model; format tests include malformed inputs.
- Every family has a real application using several of its modules.
- Target support is recorded per module. The initial executable target is
  x86_64 Linux; Wasm claims need separate execution evidence. Running the
  compiler on a GPU does not establish user-program GPU execution.
- Measure relevant operations and representative large-library compile
  workloads with the repository's performance tools. Keep each command below
  two minutes and avoid unrelated GPU test reruns.
- Portable algorithms and library interfaces use Lanius. Host and third-party
  services use explicit native bindings with executable ABI/linking contracts.
  Rust/Python may drive tests; JSON transport, subprocess serialization and Wasm
  bridges do not establish native library integration.

## Remaining work beyond atomic files

This audit preserves the full scope above. TempFile and finite AtomicFile/KV
acceptance, the current archive increment and server receipts do not complete
other families.
The following are source/status gaps already identified by the roadmap, rather
than a request to replace implementation work with more tests.

| Area | Current evidence | Remaining work |
| --- | --- | --- |
| Values, memory and collections | Explicit TryClone/Destroy and manual owners execute; public borrowed views still rely on valid backing/lifetimes. The protected `std::vec` remains heap backing and under active formal vector specification/template contracts; the mini compiler and extractor use `List`. See the [dependency ledger](library-dependencies.md). | Finish layout/manual-owner consolidation and remaining generic compositions; coordinate protected migration, over-aligned allocation and language lifetime/destruction support with compiler work. Revalidate old reductions before calling them solved or currently blocking. |
| Iteration | Shared forward/reverse iteration, scan/nested traversal and bounded transfer retain their accepted finite scopes. The separate exact-size protocol passes four library gates with 10714 model cases/35922 steps and a 95-case byte application; it retains explicit finite/alias bounds and no unchecked-memory authority. DoubleEndedIterator/Rev now pass four registered gates with an independent mixed-end model, selected owning leaves and exact bound rejection; timeline-tail passes four runtime tests/71 cases. Ordinary Flatten/FlatMap now pass semantic/shape, negative-bound, eight live-owner cases and the migrated flatten_sum groups through the same nested engine. Replacement sinks/helper pass semantic/shape, negative-bound, strict-owner/reached-OOM and real-application gates with pre/postcommit recovery. | Further adapters/consumers remain, with explicit cleanup through the canonical protocol. Preserve manual borrowed lifetimes, nonreentrancy and finite work/target limits; the separate zero-sized function-return dependency remains in the compiler ledger. |
| Threads and synchronization | `std::thread` declares runtime externs but marks service 8 unbound; no working source atomic/mutex/channel library is present. The checked C profile has no function-pointer entry or C Boolean result. | Checked worker entry, runtime context/lifetime and memory-order admission precede usable thread/join/atomic/synchronization/channel APIs. Poll scheduling is not worker execution. See the [concurrency dependencies](library-concurrency-dependencies.md). |
| Files, paths and processes | FileOps, directory walking, process groups, TempFile and anchored rename/unlink execute on their documented Linux profiles. AtomicFile/KV has finite local-Linux publication/failure/recovery receipts; descriptor-relative directory creation/removal passes 55 process invocations. Checked link/readlink and permissions pass 139 accepted group cases; mktemp_dir passes 48 process invocations. TempDir passes 46 accepted group cases across four groups. | Automatic owner destruction, concurrent spawn, group escape/containment and other platform bindings retain separate contracts. Preserve each receipt's overlap and finite target scope. Single-name publication does not supply locking or multi-file transactions. |
| Connected protocols | HTTP/HTTPS and DNS transports execute. The URL facade adds strict owned HTTP(S) planning, ordered NSS/TCP selection and exact socket adoption, with separate plain2/DNS1/TLS8, connector admission12/failures8 and real-fetch functional24/33/4 direct groups. NSS remains synchronous. WebSocket adds portable response validation/encoding, OpenSSL Accept, an offline tool and generic borrowed client/frame adapters with transactional coalesced-byte handoff. Eleven scripted scenario functions run in one raw process; separate real-client plain9/rejection12/CLI17/I/O3/TLS5 groups pass. The caller retains the socket/TLS owner and explicitly closes it. The appended server policy-pause adapter passes six scenarios and a real one-client echo server passes separate plain11/handshake12/rejection10/CLI14/TLS4/credentials3/deadline1 groups, one separate readiness-stdout failure and one integration; the changed HTTP encoder passes three actual Rust runtime tests. | Full URL/WebSocket wrapper/application source-OOM acceptance, leak campaigns, arbitrary clock/TLS/generic-transport schedules, asynchronous NSS, broader orchestration, keepalive/pooling, existing HTTP-server/scheduler upgrade adoption, persistent/concurrent WebSocket service and ws/wss URL policy remain. Borrowed client/server handoffs are executable on the finite profile; automatic lifetime/cleanup enforcement remains language work. Do not infer mixed invalid/valid mutual-TLS concurrency from sequential matrices. |
| Native services and security | Scalar C calls, OpenSSL digests/TLS and SQLite execute. The native type enum admits neither C Boolean nor callback/aggregate/variadic forms. | Admit needed foreign-entry/layout contracts separately. Encryption, signatures and broader certificate/trust/application-authorization interfaces still need established native libraries; no sensitive cryptographic algorithm should be implemented here. |
| Formats, archives and storage | JSON/CSV/TOML/CBOR, the supported schema profile, compression, TAR/ZIP payload codecs, SQLite and indexed snapshots execute. Shared extraction Plan/Profile/Prepared have finite native receipts. The content-only materializer passes 100 direct process invocations across 11 Python groups; the unpack CLI passes 74 through separate libtest-driven/retained-ELF receipts. | Resumable codec/dictionary profiles, broader archive formats, schema vocabulary/reference/output coverage and wider storage interfaces remain. Per-file NoReplace publication is not a directory transaction, hostile namespace sandbox or concurrent database transaction. |
| Text and parsing | Unicode 17 default algorithms, regex/lexer and parsing utilities execute. Fixed Workspace and canonical Search serve span/full-capture probes; all 23 selected workspace/base-regex/lexer/regex-text/lex-scan tests pass across separate receipts. The new 4,096-token observation records 32 verified source requests and exact owner cleanup. | Locale collation/dictionary segmentation/shaping, richer formatting and further matching interfaces remain. The prior 36,887-allocation observation retains its historical implementation/accounting scope; no compiler-speed or universal throughput ratio follows. No second matcher is introduced. |
| Mathematics | Big integers, finite decimals, ordinary/weighted second-order and unweighted higher statistics, dense LU/QR, distributions and geometry execute with explicit numerical profiles. The canonical CSR foundation passes six library gates including a 3,886-case model, 33 reached operation-allocation denials and the 65,536-row analytic scale case; the real graph application passes four more gates/113 process cases. The separate sparse product passes all six new library gates, including a 2,194-case model and 16 reached allocation denials; its weighted-path application passes four groups/122 unique process cases across separate original/amended-model receipts. The CG solver passes six library and four graph-diffusion gates/154 application process cases, including a 1,918-case independent model and 27 reached workspace allocation denials. The weighted/higher increment passes eleven registered gates and both ordinary-statistics regressions, including independent Fraction/Decimal models and the 66-case CSV application. | Additional number theory, decimal exceptional/transcendental behavior, weighted higher-order and multivariate higher statistics, other iterative/direct solvers, sparse/advanced decompositions and further distributions remain. Preserve finite-domain and accuracy limits. |
| Application and media utilities | CLI parsing, command hierarchy and generated help execute. Response tokenization/owned expansion pass portable semantics and public composition; native provider/resource groups pass 70 overlapping cases and current KV responses pass 55. Earlier hierarchy/roundtrip/publication groups retain source `f07fd52f...` scope. Portable completion, literal Bash words and reply frames pass finite semantics/pure contracts; the Bash adapter passes function/PTY/watchdog gates, and native queries pass owner/OOM/output groups. Settings, logging, terminal tables/progress, PNG, WAVE and FFT retain their profiles. | Other shell adapters, richer application/configuration validation, color management, additional media formats/playback and signal algorithms remain. |
| Distribution and semantic documentation | Selective source bundles and the generated declaration inventory execute. At `f70d9a37`, 35 inventoried modules have no registered contract guide: 18 core and 17 std. | Installation/binary SDK and registry distribution, automatic test discovery/registration and complete semantic API documentation remain. Those 35 are guide-link gaps, not 35 proven missing implementations. Each API still needs executable/contract-only/unsupported classification where relevant. |
| Targets | Current receipts establish native Linux x86_64 profiles; GPU compilation does not establish user-program GPU execution, and `std::gpu` is explicitly unbound. | Keep per-module target/dependency evidence accurate; broader host targets and user GPU services require real runtime support and execution before claims expand. |

### Accepted command completion

The [completion contract](extended-cli-complete.md) and
[plan](library-completion-plan.md) reuse canonical prefix parsing and command
routing. `ext::cli_complete` borrows immutable schema/arguments, releases the
scratch lease before returning Context and writes whole-prefix suggestions
atomically into caller output. `ext::bash_words` decodes only the documented
literal shell-word profile. `ext::cli_bash` measures/encodes NUL-record replies;
the Bash adapter separately owns host enumeration and Readline insertion.

Current finite native Linux x86_64 receipts accept the direct portable contract
and direct public prefix-parser smoke under no-host observation, one Rust
67-case core model test in 6.76s (one test
filtered out), both hierarchy regressions in 9.91s and one selected flat test.
The final direct literal-decoder/reply contract also passes no-host observation;
a separate direct native process checks 389 model records (270/119). Native KV
queries pass 18 cases plus three no-file traces on source `9a83795a...`.
Query owner/output groups pass separately: 16 allocation cases (13 reached
OOMs and three baselines) and 12 output cases (three baselines and nine
fault/recovery cases). Full traces check pre-exit release, without live ACK.
The existing response campaign also passes 55 cases/18 source OOMs on the current
completion application. Final adapter `f7934bc9...` passes 51 function cases
across two option profiles, 26 real PTY cases and two fresh-cwd leading-quote
transition cases. Its unchanged watchdog on source `8a1fc69f...` separately
passes both failed/missing-sleep controls; held shells show producer, watchdog
and sleep children gone before exit. Exact argv, suffixes, byte names and
frame/status rejection are checked. Receipts are
`completion-bash-pty-quote-retry{19-boundary,20,21-function}.log` and
`completion-bash-pty-quote-retry14-deadline.log` under `target/stdlib-work/`.
Combined shell/resource Rust-driver build admission is 3.56s; the final shell
driver separately builds in 1.75s. These build receipts execute no native Rust
tests, and the direct shell groups are not Rust-libtest passes. No-allocation
observations establish zero attempted allocations, not OOM recovery.

The selected CLI increment is accepted on native Linux x86_64, Bash 5.2 and
bash-completion 2.11. Other shells and arbitrary expansion syntax are outside
this profile; host glob enumeration time/memory are not bounded by Lanius caps.
The accepted response checkpoint `68189363` and application
`789143f6...` remain separate; their historical 55-case database/response
receipt is not added to the current 55-case rerun. The module guide owns current
source identities and receipt paths. The full library goal remains open. The
[URL-client increment](extended-url-client.md) now has its own finite executable
receipts; these completion and historical numeric/URI receipts do not establish
that workflow by themselves. Compiler/runtime and
other family dependencies remain in the [dependency ledger](library-dependencies.md).

### Accepted response files

The [response-file contract](extended-cli-response.md) and
[plan](library-response-files-plan.md) add three distinct modules: pure
`ext::response` grammar/mapping, owned `ext::cli_response` expansion over a
generic provider and explicit `ext::cli_response_files` loading from a borrowed
directory. Stable final argv feeds both existing parsers. No option lexer is
duplicated; expansion retains captured failure diagnostics and transfers
provider errors to the caller.

Two portable semantic Rust tests pass together in 8.93s after a separate 3.37s
build (`response-semantics-first.log`): 96 native records contain 17 grammar,
ten syntax and 69 expansion/limit cases. Separate pure contracts exercise
raw mappings, logical bounds, canaries and actual signed strides. Tokenizer,
owned-expansion and native-provider public smokes compile and exit zero.
Full traces of the tokenizer smoke and pure contracts contain only launch and
final raw exit under mmap denial; no allocation attempt occurs, so this is
not OOM-recovery evidence.

Response-checkpoint [KV source](extended-kv.md#historical-response-application-receipts)
`789143f6...`
passes its focused response group: 55 process cases, including all 18 source
allocation denials from the nested-help baseline, a post-database OOM and the
published/unsynced status 6 case. Those cases are included in 55. Artifact-aware
oracle `057bb27a...` retains the earlier failed observation separately.
Earlier hierarchy source `f07fd52f...` and its 130 cases were not rerun and are
not added to this receipt. Current resource/KV Rust drivers have a separate
combined `--no-run` build in 2.09s
(`response-resource-kv-drivers-build-first.log`), without a current native
Rust-test execution claim.

Two direct native oracle groups now pass: provider 39 and resources 31,
including all 29 reached source OOM positions and two resource baselines.
These 70 overlapping group cases are not two current Rust-libtest passes.
Actual live ACK checkpoints check descriptor generations and source maps;
owned provider errors remain usable after Expansion destruction. Receipts are
`response-files-provider-native-first.log` and
`response-files-resources-native-first.log`. Final probes are `f8a564cb...`
and `5b28229c...`; oracle `a472...` has 39 CPU controls and complete phase/syscall
observation after two review gaps were corrected before native acceptance.
Those CPU controls are separate from executable case counts.

Source identities and exact public smoke/semantic receipts are in the module
guide. The selected increment is accepted on finite native Linux x86_64 CPU
output from the GPU compiler.
Fixed-base lookup is not containment, cycles are bounded by explicit limits,
and storage limits are not an exact heap/RSS cap. Completion has its separate
current status above; broader application policy and the full standard/extended
library goal remain open.

### Accepted command hierarchy and help

The [command contract](extended-cli-commands.md) and
[plan](library-cli-commands-plan.md) add routing and deterministic measured help
through the canonical option lexer. The modules use borrowed schema/arguments,
exclusive caller scratch and caller output, with whole-schema admission and
unchanged output on help failure. They allocate no storage and access no host
service.
Application arity/default/conflict/help policy remains explicit.

Two semantic Rust tests pass together in 10.10s after a separate 0.39s build:
30 schema mutations, six literal help goldens and 28 model sequences in one
native model process. Both actual public smokes and the final contract program
exit zero under full syscall observation and mmap denial, with no allocation
attempt. This establishes no OOM-recovery path. One selected old flat-parser
test passes in 6.04s after a separate 2.32s build; seven were filtered out.

Historical [hierarchy KV application](extended-kv.md#historical-hierarchy-application-receipts) source
`f07fd52f...` passes three direct groups: hierarchy66, roundtrips33 and
publication31, including 13 reached source OOMs and 15 I/O faults. The total is
130 overlapping cases, not three current Rust-libtest passes. All syscalls are
observed in `cli-commands-kv-{hierarchy,roundtrips,publication}-all-syscalls.log`;
earlier selected-call observations repeat those cases and do not add 130.
The registered KV driver builds with `--no-run` in 51.67s separately.

Flat parser `9f11981f...`, command routing `6eb4db7a...` and help
`a7198a2a...` retain the selected native Linux x86_64 CPU profile emitted by the
GPU compiler. A minimal nested-error-pattern dependency has a typed-match
executable control and does not block the APIs. Response preprocessing has its
separate accepted scope above. The completion increment is also accepted on
its finite profile; richer application validation and the full library goal
remain open.

### Accepted ordinary nested iteration

The [ordinary contract](stdlib-infallible-nested.md) and
[plan](library-infallible-nested-plan.md) add `Flatten` and `FlatMap` with plain
items and ordinary mapping. The real empty `Infallible` error specializes the
existing retirement protocol; the shared engine and earlier bodies are
unchanged. Construction remains lazy, retirement precedes another outer pull,
and explicit take/finish preserves actual updated-inner recovery. Owning
inners require real retirement, with manual backing and yielded-value lifetimes.

Core source `5034fbac...` has direct public compile/native admission. Two
semantic Rust tests pass together in 9.38s after a separate 1.76s build:
24 model schedules in one native process plus optional/Result/wide, actual
positive/negative-stride, zero-sized and Scan/Take composition. Three negative
Rust tests pass in 4.77s after a separate 1.80s build; their source-local
LNC0008 rejections establish no native behavior.

All eight direct strict-owner cases pass: Vec/physically wrapped Deque ×
Flatten/FlatMap × full/early-take-resume. Four live ACK checkpoints check exact
owner partitions, held output and pre-exit mappings/descriptors. No source
allocation attempt is permitted after setup, including callbacks and recovery.
This is not a Rust-libtest receipt or an OOM campaign. The owner receipt is
`infallible-nested-owners-lifecycle-first.log`, with probe/ELF/oracle prefixes
`0a8aa0d4...`/`530cbe74...`/`7f7c77c8...`; 25 CPU controls are separate.

Current [flatten_sum](stdlib-flatten-sum.md#current-ordinary-adapter-receipts),
source `65cfcdfc...`, passes all four direct oracle groups: models138,
bounds54, allocations11 (baseline plus ten reached OOMs) and faults16.
These total 219 overlapping group cases, not four current Rust-libtest passes.
Logs under `target/stdlib-work/` use
`infallible-flatten-sum-{models,bounds,allocations,faults}-first.log`;
semantic/negative logs are `infallible-nested-model-shapes-first.log` and
`infallible-nested-bounds-first.log`. Nine semantic CPU controls are separate;
unchanged app oracle controls were not rerun.

The selected increment is accepted for native Linux x86_64 CPU output from the
GPU compiler. Earlier fallible-adapter receipts and the older application
timing retain their historical source scope. No current app timing, user GPU
execution or compiler-speed ratio follows. Further iterator work and the full
library goal remain open.

### Accepted replacement sinks

The [replacement contract](stdlib-replacement-sinks.md) and
[plan](library-replacement-sinks-plan.md) freeze complete old/new owner recovery
and exact committed/replaced counts. Five production sources are unchanged
from their admission freeze, with no prior body or compiler implementation
change. Model53 scenarios pass one Rust test in 9.73s; wide/optional/Unit shapes
and all four duplicate policies pass the other in 9.49s. Five negative-bound
Rust tests pass in 5.67s, without implying native behavior.

Five direct strict-owner groups pass 219 overlapping cases and 183 individually
reached OOMs, including recovery in every facade: lifecycle20, HashMap63,
TreeMap57, HashSet41, TreeSet38. Four lifecycle denials are intentionally
unreached no-growth controls, not faults. Four direct
[latest-values groups](stdlib-latest-values.md) pass 248 overlapping cases:
models136, strengthened bounds61, allocations34 (baseline plus33 OOMs), faults17.
These retained-ELF oracle groups are not five/four passing Rust libtests; their
registered drivers build together in 3.42s with `--no-run`. CPU controls number
18 semantic/45 resource/26 app separately. Module/fixture guides own full logs,
source identities, causal-order corrections and strict ledger mechanics.

The separate import-free `(Progress,Unit,Unit)->Unit` call traps after successful
compilation while its u64-return control executes; actual public Failure/Result
Unit storage and caller-local projection pass. The
[reproduction](../tests/fixtures/stdlib_compiler_state/replacement_zst_return/README.md)
and dependency ledger retain that compiler boundary without a production shim.
One 4,096-row/512-key app observation is 0.087919031s untraced, including launch,
input validation, owners/maps/history/staging/output capture, with independent
checking outside the timer. It adds no finite case, measured allocation/RSS or
compiler/general ratio. This finite native Linux x86_64 increment is accepted;
further iterator work and the full library goal remain open.

### Accepted scan and nested iteration

The [nested-iteration contract](stdlib-nested-iteration.md) defines borrowed
stateful Scan/TryScan and general TryFlatten/TryFlatMap through one nested
engine. Exhausted inners transfer to a caller retirement policy; failure
returns the actual updated inner plus an error, which is emitted once before
fusion. Active take/finish and outer resumption preserve manual cleanup duties.
Sources, callbacks and borrowed yielded values retain explicit lifetimes.

Both actual public stdlib smoke programs compile and execute directly. Three
semantic/payload Rust tests pass in 9.31s
(`nested-public-models-shapes-first.log`): 360 nested/672 scan binary command
scenarios and executable nested/wide/array/strided/zero-sized payload checks.
Their two registered smoke libtests were filtered out; this is not an all-five
libtest receipt. All four [earlier fallible flatten_sum tests](stdlib-flatten-sum.md#historical-fallible-adapter-receipts) pass 219
process group cases: models138/bounds54 in 8.51s and allocations11/faults16 in
8.23s, with setup/baseline overlap. Allocation scope is a baseline and all ten
reached source OOMs. Eighteen model and eighteen app CPU controls are separate.

This historical freeze is core `7256a394...`, app `946043fe...`; the ordinary
application migration has separate current receipts above. All four direct strict
owner groups pass against one retained ELF: lifecycle14/OOM0, flatten30/OOM28,
Vec56/OOM52 and Deque56/OOM52. These total 156 group cases with overlapping
baselines and 132 individually reached OOM runs; they are not four passing
Rust libtests or 132 distinct allocation sites. Logs are
`nested-owners-lifecycle-lazy-count-retry.log`,
`nested-owners-flatten-oom-first.log`, `nested-owners-flatmap-vec-oom-first.log`
and `nested-owners-flatmap-deque-oom-first.log`. The accepted probe/ELF/oracle
prefixes are `e92ee3b8...`/`3d99ec69...`/`eb37f142...`; 41 CPU controls are
separate. Strict source ledgers and live acknowledged mapping checkpoints
verify actual partial-inner recovery, owned-error/output lifetime, retirement
order and explicit release.

Initial fixture admission corrected a where-subject unsupported by the grammar
and explicit generic cursor locals. Oracle lazy/eager counts were then
corrected with the emitted ELF unchanged, preserving exact fault binding and
all ledger assertions. These fixture/oracle changes needed no production or
compiler source change. This selected increment is accepted. A separate
historical 65,536-value/3,072-row untraced application observation (2,048 empty rows) takes
0.157614975s including launch/I/O/parsing/traversal/formatting/capture, with
validation outside the timer. It adds no finite case, compiler benchmark or
general ratio. The reference records current acceptance separately from source
inventory. The full library goal and further iterator work remain open.

### Accepted filesystem increment

The [selected filesystem increment](library-filesystem-completion-plan.md)
implements [links and permissions](stdlib-filesystem-links.md),
[owned temporary directories](stdlib-temp-directories.md) and a
[real temporary-directory program](stdlib-mktemp-dir.md). Public interfaces and
production source are frozen. All five FileOps groups now pass: links28,
readlink19, permissions12, bounds45 and faults35, totaling 139 accepted group
cases. The first 34 faults repeat in the successful fault-only retry; this is
not cumulative process counting. All four application tests pass 48 process
invocations: normal5, arguments13, allocation4 and faults26, with overlapping
calibration/setup calls. All four TempDir groups pass: owner 9, admission/
entropy 19, creation faults 8 and cleanup faults 10, totaling 46 accepted group
cases across three commands. Earlier cases repeat during the harness retries,
so this is not cumulative process counting. These are 13 selected passing Rust
tests across separate invocations, not one clean combined run.

TempDir removes only its own empty name, retains anchors and backing when
removal fails, and supports explicit keep/retry. The checked link/readlink and
permission primitives have no heap allocation, implicit retry or fallback.
Their initial target is native Linux x86_64, not filesystem operations inside
a GPU kernel. Automatic destruction, hostile-namespace guarantees and broader
platform support remain separate work. The earlier finite filesystem receipts
below retain their own source scope. Current source is FileOps `21269e34...`,
TempDir `56898b00...` and application `118f9a78...`. A minimal comparison/cast
parser reproduction prompted only an equivalent widening-cast local; no
compiler source changed. The first primitive fault run stopped before its last
child because strace rejected an oversized poke argument. The successful retry
uses a 16-byte known prefix/full-count control, while real readlink cases still
compare all output bytes. Skipped native-close injections prove logical
retirement, not physical close success. These native Linux x86_64/ext4 `/tmp`
receipts complete the selected increment, while the full standard and extended
library goal remains open. TempDir owner 9 is accepted within the mixed 6.88s
`filesystem-temp-dir-native-first.log`; creation 8/cleanup 10 within the mixed
7.66s `filesystem-temp-dir-callback-retry.log`; admission/entropy 19 in the
6.07s `filesystem-temp-dir-single-entropy-rule-retry.log`. The mixed commands
contain other harness failures, so their times do not isolate the passing
groups. A shadowed callback and duplicate getrandom injection rule required
oracle-only corrections; the final admission retry binds a single first-draw
rule and observes real subsequent entropy. Separate CPU controls number 40 for
link primitives, 45 for TempDir and 16 for the application. Generated references
record this source/API freeze separately from runtime acceptance.

### Accepted bounded archive workflow

The [bounded extraction increment](library-archive-extraction-plan.md) is now
implemented over the canonical TAR/ZIP readers and AtomicFile. Its checked
directory primitives, raw ZIP creator metadata, shared namespace planner,
content-only profile and complete metadata-source owner have finite native
receipts. The [unpack program](extended-unpack.md) passes 69 initial
libtest-driven process invocations plus five retained-ELF input-fault invocations.
Direct [Run](extended-archive-extraction.md) ownership, fault, retained-publication
and allocation gates now pass 100 process invocations across 11 Python groups,
including two allocation calibrations and 14 reached ENOMEM cases. These reuse
one CLI-compiled native ELF; the Rust driver has build admission, not a passing
direct libtest rerun. This completes the selected finite archive increment,
while the whole library scope above remains open.

The contract remains cooperative/stable namespace, explicit bounds and manual
ownership, per-file NoReplace publication, partial-output reporting and retained
cleanup/name duties. It supplies no archive-wide transaction, rollback or
hostile-directory containment. The codec engines remain separate byte APIs.

Threads/native entry retain compiler/runtime prerequisites. The
[reusable regex/lexer workspace increment](library-regex-workspace-plan.md) is
now implemented, sharing the existing matcher and returning spans without
discarded Match owners. Its fixed-capacity/owner, consumer and real-application
gates pass across the selected finite receipts. This completes that increment;
the rest of the family scope above stays open.

## Current work

- Branch: `codex/stdlib`; the full library goal remains open.
- Accepted [native numeric byte order](stdlib-native-endian.md) implements 24 concrete
  u64/i16/i32/i64/f32/f64 functions, bringing `core::endian` to 36. The raw
  caller-length/fallback/boolean contract remains explicit: full field bounds
  precede access, rejected writes do not mutate, valid operations retain
  native slice stride, and physical backing/lifetime remain manual.
  Native u64 composes existing u32 packing, signed fields preserve
  two's-complement bits and float fields use existing exact bit transfers.
  IEEE corner and fallback encodings need new executable evidence; existing
  float receipts and historical endian12 do not cover these additions.
  Direct native/trap coverage passes two tests in 8.33s: all 24 additions,
  58 literal vectors across orders/layouts and four physical-overclaim exits101.
  The selected old endian runtime passes one test/seven fixtures in 8.48s,
  and UTF-16 consumer one test/two fixtures passes in 5.82s. The independent
  model passes 16,032 cases in 6.96s (10,624 admitted/5,408 rejected), checking
  independent read bits/write bytes. Two memory tests pass in 7.73s, covering
  672 rejected accesses, three real backing forms, exact fits/selected NaN
  generic transport and no host calls in pure phases. The 32,768-record scale
  workload has 196,608 writes and 196,608 reads with one exact backing release;
  lifecycle times are not isolated performance ratios. The
  [record-repacking application](stdlib-repack-records.md) passes four
  groups/96 cases across model27/7.80s and CLI23+rejection30+I/O16/7.62s,
  including all conversion pairs, high-bit count admission before narrowing,
  a 65,536-record frame and four selected allocation denials. Static inventory
  separately passes one CPU test for all 36 names; it is not runtime evidence.
  The selected increment is accepted on native Linux x86_64 CPU output from
  the GPU compiler.
  Broader target support and
  the whole library goal remain open; Unix-domain IPC is separate future work.
- Accepted [advisory file locking](stdlib-file-locks.md) adds Shared/Exclusive
  and Blocking/Nonblocking modes mapped to one
  borrowed File flock attempt; only exact-zero success is acknowledged.
  Duplicates share the open-description lock, repeated acquisition is not
  reference counted and failed conversion has no old-mode retention promise.
  Explicit alias coordination and unlock/close remain manual. No allocation,
  retry, implicit cleanup, deadline or durability is added. The file-patch
  `--lock` mode reuses existing validation/positional/cleanup work and acquires
  nonblocking Exclusive before reading. The selected existing positional
  native contract passes in 6.74s, and all four ordinary file-patch groups
  pass 82 cases in 7.73s against the revised sources. Those current regressions
  do not establish locking or add a distinct new application corpus.
  The new native policy test passes in the first mixed command (6.86s),
  whose fault test failed a tool-warning harness. The final fault-only test
  passes in 5.45s with 16 schedules/14 reached injections/two controls,
  including the full-width 4,294,967,296 exact-zero guard. The independent
  state model passes in 5.76s with 1,287 programs/24,244 steps/four owner slots,
  normalizing 949 WouldBlock results (138 failed conversions) with explicit
  unlock before later predictions. All four process tests pass across
  blocking1/5.97s and lifetime3/5.37s: six native peer lifecycles, three
  observed kernel waits and explicit release handshakes. The locked
  application passes four groups/49 new cases across model15/7.73s and
  bounds15+faults15+protection4/7.62s, with actual host probes during payload
  I/O and release before close. Ordinary82 remains a separate regression
  corpus. This finite Linux x86_64/local-filesystem increment is accepted.
  No compiler/ABI/proof edit or new compiler dependency is introduced.
  NFS/SMB, automatic ownership and blocking deadlines/cancellation retain
  separate limits; earlier receipts and the whole library goal keep their scope.
- Accepted [positional I/O](stdlib-positional-io.md) adds ReadAt/WriteAt and
  attempt-bounded exact/all helpers that
  admit complete array/position spans before callbacks, preserve confirmed
  progress and make no EOF probe after completion. The signed-64-bit exclusive
  end bounds file positions; empty operations and negative budgets have
  explicit behavior. File adapters preserve the shared cursor, stage at most
  1024 bytes, check flags before transfer and reject O_DIRECT / write O_APPEND.
  Manual owner/backing and stable descriptor/status state remain required.
  Two portable tests pass in 7.01s: one no-service native contract and two
  capability rejections. One selected old stream regression passes in 11.34s
  with two native fixtures. The independent model passes in 4.38s with
  11,012 cases/6,836 calls/652 failures after progress. Native-driver gates
  pass five tests in 13.11s: four fixture groups and one CPU trace-parser
  check, including 30 fault schedules/24 reached injections, both byte
  strides, offsets above 4 GiB and shared-cursor preservation. The O_DIRECT
  rejection branch is actually exercised. The real
  [file-patch program](stdlib-file-patch.md) passes four groups/82 process
  cases across model24/7.18s and CLI35+preservation6+I/O17/7.57s.
  One selected existing FileOps regression passes in 7.12s against the final
  module. A focused amended native-contract rerun passes in 7.74s, rejecting
  physically backed 1025-byte spans at MAX−1024 before status/transfer in both
  directions. This updates one existing test's fixture scope; the original
  five-test receipt retains its earlier contract fixture.
  Native guards use the
  [existing typed-local parser idiom](../tests/fixtures/stdlib_compiler_state/filesystem_imports/README.md),
  with no compiler repair claim. The selected native target is Linux x86_64
  CPU output from the GPU compiler; earlier file/stream receipts retain their
  source/API scope. The finite selected increment is accepted; the whole
  library goal, broader targets and automatic ownership remain open.
- Accepted [comparator-driven slice ordering](stdlib-slice-ordering.md) implements
  seven checked View APIs under one canonical
  `core::ordering::Comparator<L,R>`. Metadata errors precede all reads,
  mutations and callbacks; empty views are no-touch. Sort is allocation-free,
  iterative and unstable; heterogeneous bounds and deterministic first/last
  searches use view-relative indices. Partition preserves whole shallow
  values while grouping Less elements. Raw Ord APIs share these engines
  through Natural and preserve their previous policies. Iterator min/max
  migrate directly to `Comparator<T,T>`, without an old trait alias.
  All six new library gates pass: contracts3/8.64s, owners+scale2/12.20s and
  model1/6.59s. The independent model checks 2,808 cases/44,928 actions across
  two descending-stride backings and six policies. Owner observations include
  29 exact releases and seven phases with no memory services; the 32,768-record
  gate checks comparison allowances and two exact releases. Its whole native
  lifecycle timing is not isolated sort throughput or a compiler ratio.
  The [comparison receiver dependency](../tests/fixtures/stdlib_foundation/slice_ordering_dependency/README.md)
  has two passing checks/2.92s: one local-trait LNC0027 reproduction and one
  executing split-receiver control. Public operand bounds remain general;
  current fixtures use distinct role receivers sharing one policy.
  The real [sort-rows program](stdlib-sort-rows.md) passes all four registered
  groups/122 process cases: model37 in 12.78s, then CLI39/rejection33/I/O13
  in 9.65s. Text/numeric policies use an explicit original-row tie-breaker;
  stable visible ties do not change the library's unstable-sort contract.
  Three selected migrated iterator tests pass in 16.23s, including the
  1,280-schedule/320-extrema/180-position model, owner cleanup and exact-bound
  groups; two unrelated tests were filtered. No old application/trap or full
  lookahead rerun is claimed. Native Linux x86_64 CPU output is the accepted
  target; broader targets, automatic ownership and proofs remain open.
  Earlier slice/iterator/fold receipts retain their source scope.
- Accepted [iterator reduction and bounded-fold increment](stdlib-iterator-folds.md):
  eight consumers reuse Folder/TryFolder with explicit matching source bounds.
  Reduction has no synthetic identity; reverse calls consume the back with
  accumulator-first callbacks. Bounded progress counts successful callbacks,
  zero quotas make no source/folder calls, and quota exhaustion performs no
  extra EOF or count query. Callback errors consume the failing item and
  transfer actual recovery values through E without rollback or implicit
  destruction. All three new contract gates pass in 9.13s, executing all
  eight APIs with no allocation services and rejecting eight invalid-bound
  compositions. Three owner/recovery tests pass in 7.62s with actual nested
  String owners, correct front/back remainders and 24 selected reached mmap
  denials across setup/callback growth. The independent model passes in
  9.10s: 10,696 cases, 37,104 state commands, four source forms, one native
  process. All seven new library gates are accepted.
  Two selected old consumer/reverse contract gates pass in 7.26s/10.96s,
  without a broader historical-suite claim. An explicitly typed local error
  avoids the [reduced record-field inference dependency](../tests/fixtures/stdlib_foundation/iterator_fold_dependency/README.md).
  Its two registered checks pass in 4.39s, establishing one diagnostic and
  one native control. The real [byte-summary program](stdlib-byte-summary.md)
  passes its 40-case model in 9.92s and remaining CLI32/bounds1/I/O14 groups
  in 9.33s: four groups and 87 unique native process cases. This finite
  native Linux x86_64 increment is accepted; earlier exact-size/reverse/fold
  receipts retain their source/API scope. No compiler repair, arbitrary
  generic-composition, automatic ownership or device-runtime claim follows.
- Accepted [sparse CG solver](extended-sparse-cg.md): the fixed contract
  supplies None/Jacobi preconditioning, exact numerical symmetry checks,
  fresh residual verification on every update, explicit iteration limits and
  residual-replacement restarts. Positive definiteness remains a caller
  requirement. Full requested work is admitted before payload, and workspace
  cleanup is explicit with no iteration-loop allocation. All six new library
  gates pass: four contract/denial groups across separate mixed-command and
  admission-only receipts, the 1,918-case independent model (6.78s) and the
  65,536-row manufactured system (14.08s). Workspace denial groups reach 27
  operation failures with full address/size release checks; the model verifies
  the recursive-zero/fresh-one refusal/restart case. The large system uses
  196,606 entries, cap 20 and work allowance 90,833,350, with independent
  residual/value checks after input destruction. Whole-lifecycle timing is
  not isolated kernel throughput. The real
  [graph-diffusion program](extended-graph-diffuse.md) assembles a symmetric
  system and publishes only converged output. Its four registered tests pass
  in 17.42s with 154 process cases: model 36, rejection 48, CLI 55 and I/O 15.
  All six new library and four application gates are accepted on the finite
  native Linux x86_64 profile.
  No old regression groups were rerun, and earlier sparse receipts retain
  their own API/source scope.
- Accepted [sparse matrix product](extended-sparse-product.md): the contract
  adds `ext::sparse_ops::matmul` returning independent canonical CSR, with
  complete input validation, increasing-inner-column accumulation and
  computed-zero omission. Reusable column scratch, actual output nonzero
  caps, explicit finite-intermediate failures and the overflow-safe work
  formula are documented. The implementation's 2,194-case independent model
  passes in 7.45s and the 65,536-row analytic scale gate passes in 8.38s,
  computing 327,674 output entries from 196,606 inputs. Four contract/denial
  gates pass in 13.11s, including allocation-free rejections and 16 reached
  allocation failures with explicit address/size releases. All six new
  library gates pass; two selected foundation semantic regressions pass in
  11.70s on the current module. The real
  [sparse-paths program](extended-sparse-paths.md) passes all four groups with
  122 unique process cases: model 34, rejection 37, CLI 36 and I/O 15. The
  first four-test run passes in 20.45s; the amended model separately passes
  in 14.73s and replaces the earlier 33-case model. Counts do not add those
  overlapping model runs. All six new library and four application gates are
  accepted on native Linux x86_64. Other foundation receipts retain their
  older API/source scope.
- Accepted [sparse CSR foundation](extended-sparse.md): allocation-free
  descriptors/validation/row/get/prefix matvec, independent three-vector
  owners, ordered COO coalescing, clone/transpose, sparse add/sub/scales and
  dense conversion/product are implemented in Lanius. Explicit zeros survive
  copy/clone/transpose; computed zeros are omitted without an epsilon rule.
  Work admission uses documented independent phase estimates and checks caps
  before corresponding array scans/allocation. Owned results are atomic,
  while caller-output matvec reports complete published row prefixes.
  All six library gates pass: two semantic tests (11.01s), two allocation-denial
  tests (9.92s), the 3,886-case independent model (8.15s) and the analytic
  65,536-row/196,606-entry scale gate (9.10s). Reached operation allocation
  denials total 33, excluding clone input-owner setup failures, with full
  address/size release checks. The model checks exact finite bits across 17
  modes and two backing forms; bounded dyadic cases also use exact Fractions.
  The large gate exercises real sparse assembly/products and rejects the
  4,294,967,296-cell dense conversion. Whole native process lifecycle timing
  is not an isolated kernel/compiler performance ratio. The real
  [graph-walk program](extended-graph-walk.md) passes all four registered
  tests in 16.31s with 113 process cases (32 model, 33 rejection, 38 CLI, 10
  I/O). All ten selected runtime gates are accepted on native Linux x86_64.
  Module-qualified slice calls avoid the retained
  [item-import priority limitation](../tests/fixtures/stdlib_compiler_state/item_import_priority/README.md),
  whose qualified control compiles and executes; no compiler production code
  changed.
  Sparse/sparse multiplication has its own current product increment.
  Sparse factorization/solvers, other formats, formal proofs, automatic
  ownership and other host/device targets remain outside this foundation.
- Accepted [exact-size iterator increment](stdlib-exact-size-iterators.md):
  `ExactSizeIterator<T>` supplies an observational `u64` remaining count under
  a matching explicit Iterator bound. Selected finite core leaves and
  collection cursors use existing remainder metadata; Rev/Map/Take/Skip/
  StepBy/Peekable derive counts without source pulls, callbacks or item reads.
  StepBy has distinct first/later formulas, and Peekable retains the existing
  active-cache and source-resumption policy. Zip is excluded because borrowed
  sources can alias; Chain because counts may sum beyond `u64`. No infinite,
  callback-dependent, nested or checked-index Enumerate implementation is
  added. Exact counts grant no unchecked memory authority. All four library
  gates pass across two receipts: three nonmodel gates in 11.82s, followed
  by the corrected isolated model in 8.44s. The former log also records a
  model fixture visibility failure; it is not an all-pass combined command.
  The independent sequence/deque model covers 10,714 cases and 35,922 steps
  across 18 modes. Current pure contracts have an empty memory-service trace;
  collection backings match releases by full address/size; five unsupported
  capabilities reject with LNC0008. The narrow chained generic Option
  receiver-resolution reduction has a compiled/executed typed-local control;
  no compiler production code changed.
  [Sample-bytes](stdlib-sample-bytes.md) composes optional Rev, Skip, StepBy
  and Take, reserves using exact count and retains checked pushes plus an
  independent byte cap. All four application tests pass in 9.44s, covering
  95 cases: model37/limits3/CLI39/I/O16, including two reached allocation
  denials. The unchanged old reverse model passes one selected test in
  7.27s/7,740 commands; no broader old-suite rerun is claimed. Source is
  core `be05d6c2…`, contract `43e59a04…`, model `719f6d7f…` and app
  `f2dc4738…`. Final receipts are `exact-size-runtime-accepted.log`,
  `exact-size-model-visibility-fixed.log`, `sample-bytes-runtime-first.log`
  and `exact-size-reverse-regression.log` under `target/stdlib-work/`.
  This accepts the finite native Linux x86_64 increment. Automatic lifetimes,
  destruction, unchecked count trust, formal proofs and user-program GPU or
  other host execution remain outside it.
- Accepted [weighted](extended-weighted-statistics.md) and
  [higher-statistics](extended-higher-statistics.md) increment: portable Lanius
  summaries use explicit population/reliability or population/adjusted
  estimators, atomic indexed batches and no allocation/host math. Weighted
  zero mass validates coordinates before returning no change; a compensated
  positive recurrence maintains the reliability correction denominator.
  Higher moments compose ordinary Moments and reject a nonconstant update
  whose positive M4 is lost to underflow. The shared statistics error enum
  adds that higher-only Underflow variant; ordinary moment operations remain
  unchanged. The scaling helper is reference support. All eleven new
  registered tests pass: higher2 in 9.54s, application4 in 9.87s, scaling2 in
  7.31s and weighted3 in 13.07s, with the strengthened current weighted
  contract separately passing in 6.03s. That focused rerun replaces the older
  contract receipt without adding another distinct test. One weighted test
  checks CPU oracle controls separately from executable Lanius behavior.
  Independent models cover 1,926 scaling, 1,908 weighted and 1,212 higher cases;
  both tested `f64` backing forms use descending descriptors, with no positive
  packed-stride claim. Final contracts check zero-weight validation, paired
  shape/count/overflow rollback, Underflow, atomic batches and no allocation.
  The [sample-moments CSV program](extended-sample-moments.md) passes 66 cases:
  model26/rejection30/CLI8/I/O2. Direct and registered runs overlap the same
  cases. Both original statistics regression tests pass in 12.06s. Sources are
  statistics `7f83f1e8…`, support `775960e8…`, weighted `d3cea094…` and higher
  `3f224ad3…`; final paired contract is `add50150…`. Final logs are
  `statistics-extension-runtime-final.log`,
  `weighted-statistics-paired-contracts-final.log` and
  `statistics-original-regression.log` under `target/stdlib-work/`.
  This accepts the finite native Linux x86_64 increment. Weighted higher-order
  and multivariate higher moments, broader accuracy bounds, automatic borrowed
  lifetimes, formal proofs and other host/device targets remain open. The
  statistical modules remain allocation-free; the program composes existing
  owned storage and host stdin/stdout.
- Accepted [reverse-iteration increment](stdlib-iterators.md#double-ended-traversal):
  `DoubleEndedIterator<T>` and borrowed Rev consume one non-crossing remainder,
  with permanent either-end exhaustion and explicit forward/backward bounds.
  Empty/Once, RangeI32, slice and selected borrowed/owning collection leaves,
  plus Map/Filter/FilterMap/Chain, implement reverse traversal. Forward-only
  Take/Skip/Zip/Enumerate compose after Rev. Source/callback/backing lifetimes,
  nonreentrancy and shallow/manual cleanup remain explicit. All four registered
  reverse tests pass in two disjoint commands: one model gate in 9.40s checks
  7,740 VecDeque-reference commands; the remaining three pass in 11.74s,
  covering primary/extra pure contracts without allocations, four collection
  scenarios with seven matched backing releases, and two LNC0008 bound
  rejections. Selected old forward/slice/tree controls also execute after
  canonical trait-only next/next_back migration. No same-named inherent
  backward method remains; the narrow compiler reduction is retained.
  [Timeline-tail](stdlib-timeline-tail.md) final source `6579274d…`/ELF
  `aca6fc83…` passes all four registered tests in 9.15s and 71 process cases
  (25/24/20/2), using real rev/filter/take/enumerate and canonical CSV output.
  Direct earlier runs cover those same cases. This accepts the finite native
  Linux x86_64 increment; other reverse adapters, automatic
  lifetimes/destruction, proofs and other targets remain open.
- Current WebSocket server/HTTP encoder increment: appended
  [Server<T>](extended-websocket-upgrade.md#server-api-and-policy-boundary) receives
  a validated request, pauses without writes for caller policy and only then
  stages/flushes a canonical 101 response before server-role framing. Captured
  tail bytes are rejected and the caller retains the exclusive transport owner.
  Six server scenario functions pass in one raw process. The unchanged eleven
  client scenario functions pass separately against current module `cae29596…`
  and HTTP `5d495716…`; the original client source prefix is byte-identical.
  The [HTTP encoder](extended-http.md#executable-evidence) passes three actual
  Rust runtime tests in 12.56s after a 2.13s build, including exact-capacity
  output, selected allocation-free preflight rejection and the sole output
  allocation denial. It retains the canonical parser as final wire authority.
  The [one-client echo service](extended-websocket-echo.md) `dcdef14c…` passes
  separate plain11/handshake12/rejection10/CLI14/TLS4/credentials3/deadline1 direct
  groups; a separate closed-readiness-stdout case returns status 5 with the
  listener owned, without a leak claim. One real Lanius-client integration passes. App ELF is
  `44d1b314…`, current integration-client ELF `798f00e9…`. New server/echo Rust
  drivers have a final 1.43s build-only rebuild after adding that I/O case,
  with no runtime-libtest pass claim. The app has explicit
  route/optional Origin policy, unauthenticated TLS clients, configured OpenSSL
  credentials and one cooperative deadline. Persistent/concurrent service,
  existing HTTP-server/scheduler adoption, authentication, ws/wss URLs, full
  allocation-failure/leak campaigns, arbitrary schedules/targets, automatic
  ownership and formal proofs remain open.
- Preceding borrowed WebSocket client transport increment: the
  [client handshake](extended-websocket-upgrade.md) and
  [frame stream](extended-websocket-stream.md) have one raw Linux x86_64 contract
  receipt executing eleven scenario functions in one process, with finite
  split/prefetch/partial-I/O/fault/quota/conversion loops. Sources
  `c8f4a42d…`/`be16005d…` perform no direct socket/TLS/clock/entropy operation,
  but own allocator-backed storage and exclusively borrow a caller transport.
  Final [one-message app](extended-websocket-once.md) `0ae21ee1…` passes separate
  plain9/rejection12/CLI17/I/O3/TLS5 direct groups; app ELF `1e946119…` links
  libssl.so.3/libcrypto.so.3/libc.so.6. The app supplies fresh OS entropy,
  verified DNS TLS and deadline/Close/cleanup policy. Earlier app `5055e3ed…`
  had an unaccepted TLS owner-lifetime failure; branch-scoped owners and
  borrowed wrappers fix it without changing the generic modules or compiler.
  Both new Rust drivers build in 2.00s, with no runtime-libtest pass claim.
  Source/fd leak or OOM campaigns, every transport/schedule, broader server
  orchestration, ws/wss URLs, authentication/origin policy, formal proofs,
  automatic ownership and other targets remain open.
- Preceding [WebSocket wire-upgrade increment](extended-websocket.md#current-upgrade-execution):
  portable response validation/encoding consumes an externally computed canonical
  expected Accept; the separate [native helper](extended-openssl-websocket.md)
  delegates digest computation to OpenSSL 3 libcrypto. The direct contract
  producer passes valid cases, 34 malformed responses, layouts, trailing frame
  and encoder boundaries. Native Accept passes 310 cases across two layouts and
  overlap plus 24 injected provider/size/atomicity cases. The real
  [offline tool](extended-websocket-upgrade-program.md) passes separate
  functional22/rejection30/CLI15/I/O4 direct groups. Both Rust drivers build in
  2.09s without runtime-libtest execution. Old frame/request receipts remain
  historical; those suites were not rerun. The borrowed client/frame transfer
  now has separate acceptance above. Shared HTTP-server/scheduler adoption, broader application
  admission policy, automatic ownership, allocation-failure coverage, proofs
  and other targets remain open.
- Accepted [command completion](extended-cli-complete.md): canonical prefix
  parsing and three portable modules pass contract/model checks; selected
  parser regressions, native query owner/OOM/output groups, actual Bash
  function/PTY/quote-boundary and watchdog gates pass on the documented profile.
  Direct and Rust receipts remain separate. The full goal remains open.
- Preceding [URL-client increment](library-url-client-plan.md): all five modules
  are implemented over canonical URI, resolver and HTTP/HTTPS foundations.
  Public URL contracts, 70 records on two layouts and 16 owner/failure cases
  pass. Adoption has a public smoke, one connected and eight failure cases.
  Separate connected direct groups pass plain2, DNS1 and TLS8; connector groups
  pass admission12 and failures8. The real fetch has separate HTTP24,
  CLI/preflight33 and TLS4 functional groups. No overlapping counts are summed
  into a distinct-case total. All five Rust drivers build in 4.24s, with runtime
  libtests deliberately unrun. The [guide](extended-url-client.md) records exact
  manual ownership, quota, fallback, identity, cleanup and target boundaries.
  Full wrapper/application source-OOM acceptance, arbitrary post-leaf clock
  faults, other targets and broader client policies remain open; the shared
  native resource authority is test infrastructure, not a memory-safety proof.
- Accepted [response-file preprocessing](library-response-files-plan.md):
  portable semantics and all three public smokes pass. Direct native provider
  and resource groups pass 39/31 cases, with all 29 reached source OOMs and
  live-owner checks. These are separate from two portable Rust tests. Current KV response
  group passes 55 cases, including 18 reached source OOMs, one post-database
  OOM and status 6 within that count. Current resource/KV drivers have build
  admission only; their direct native receipts do not become Rust-libtest passes.
- Accepted [command hierarchy and help](library-cli-commands-plan.md): two
  semantic Rust tests, both public smokes and a pure contract executable pass,
  including full syscall observation with no allocation attempt. One selected
  flat-parser regression passes; its other seven tests were filtered out.
  Historical hierarchy KV source `f07fd52f...` passes three direct all-syscall
  groups totaling 130 overlapping cases, not three native Rust tests or current
  response-source reruns. Its then-new registered driver had build admission.
  Completion has its separate current scope above; richer application validation remains open.
- Accepted [ordinary nested-iteration increment](library-infallible-nested-plan.md):
  core `5034fbac...` adds Flatten/FlatMap through the existing shared engine and
  true empty Infallible retirement. One direct public smoke, two semantic Rust
  gates, three negative-bound Rust tests and eight direct live-owner cases pass.
  The model covers 24 schedules in one native process. Current flatten_sum
  `65cfcdfc...` passes four direct oracle groups totaling 219 overlapping cases,
  including ten reached application OOMs; this is not a four-Rust-libtest
  receipt. Manual lifetimes, explicit recovery and outer-work bounds remain.
- Accepted [replacement-sink increment](library-replacement-sinks-plan.md):
  frozen five-file implementation, two direct admissions, two semantic/shape
  Rust gates, five negative-bound tests, five direct strict-owner groups
  (219 overlapping cases/183 reached OOMs) and four latest-values groups
  (248 overlapping cases). Registered app/owner drivers have build admission,
  not native libtest receipts. The separate zero-sized return-call compiler
  dependency remains; no public payload is padded or API narrowed. The full
  library goal remains open.
- Accepted [scan and nested-iteration increment](library-nested-iteration-plan.md):
  production core source `7256a394...` implements the four canonical adapters
  and explicit value-transfer retirement/recovery. Two direct public smokes
  execute; three semantic/model Rust tests pass in 9.31s (360 nested/672 scan
  binary commands plus generic payload checks). All four
  [historical fallible flatten_sum tests](stdlib-flatten-sum.md#historical-fallible-adapter-receipts), app `946043fe...`, pass 219 process
  group cases across 8.51s/8.23s commands, including ten reached source OOMs.
  All four direct strict-owner groups pass on a retained ELF: 156 overlapping
  group cases and 132 individually reached OOM runs. This is separate from Rust
  libtest execution. Fixture where/local-cursor and oracle count corrections
  changed no production or compiler code. The selected increment is accepted;
  further iteration work and the complete library goal remain open.
- Accepted [filesystem increment](library-filesystem-completion-plan.md):
  [FileOps link/readlink and permissions](stdlib-filesystem-links.md),
  [TempDir](stdlib-temp-directories.md) and the
  [`mktemp_dir` program](stdlib-mktemp-dir.md) are implemented. FileOps passes
  links28/readlink19/permissions12/bounds45/faults35 accepted group cases;
  application normal5/arguments13/allocations4/faults26 pass 48 process
  invocations in two commands (7.64s/7.32s). TempDir owner 9, admission/entropy 19,
  creation faults 8 and cleanup faults 10 pass (46 accepted group cases).
  FileOps source is `21269e34...`, TempDir
  `56898b00...`, application `118f9a78...`. Checked primitives have one-attempt,
  allocation-free contracts;
  the manual directory owner preserves nonempty/removal recovery and never
  deletes recursively. All 13 selected Rust tests are accepted across separate
  commands, with harness failures and repeated cases retained in the receipts.
  The reference writer/check pass: 251 pages, 250 modules and 8,259 public
  declaration markers; only the index, FileOps and new TempDir page change.
  Earlier TempFile/AtomicFile/archive receipts retain their original scope.
- Current [reusable regex storage](library-regex-workspace-plan.md) uses one
  fixed nine-vector Workspace, a canonical owning Search cursor, span-only
  lexer probes and lazy regex-text Search admission. Production is frozen at
  Regex `4520d1fc...`, Lexer `9eddce44...`, regex-text `bc9f87b7...` and lex-scan
  `7454037c...`. Current native receipts: one strict Workspace contract fixture
  in 6.12s, a constructor baseline plus nine reached OOM processes, 839 reuse/
  span model scenarios in 6.99s, and three lexer owner/admission/contracts tests
  in 12.79s. The constructor's 9.19s command also contains a pre-native failed
  model attempt; it is not a constructor-only duration. Two model fixture
  admission errors were corrected with exhaustive error-offset arms, without
  changing production behavior. All six lexer tests pass across separate
  12.79s/11.88s commands, including 576 models, 63 tables and all 30 reached OOMs.
  All seven regex-text tests pass across 12.70s/11.36s/10.89s commands: lazy
  storage/admission, 288 models, 89 tables, direct contracts, all 41 library and
  25 CLI reached OOMs, 24 exact/rejected/help CLI cases and four I/O schedules.
  The same-pattern lazy fixture records nine allocations/416 requested bytes
  for span storage versus nine/928 for captures. Both ordinary Regex/input
  regressions pass in 10.50s; their older allocation subprobe uses legacy
  accounting and is separate from the strict new workspace ledger. All five
  lex-scan gates pass across 13.63s/16.66s commands: 124 grammar inputs in both
  modes, boundaries, admission/nonpublication, scripted I/O, 30 reached OOMs per
  mode and exact 4,096-token output/cost. The latter records 32 verified source
  mmap requests, 8,895 total requested source bytes and 6,868 peak live requested
  bytes with balanced releases. Its 79.624585ms traced harness time includes
  setup and verification; it is not an isolated application or compiler-speed
  measurement. These are 23 selected Rust tests across separate commands, plus
  separate 24/30/11 CPU controls; they do not complete the full library goal.
  The durable module-level
  [lowering reproduction](../tests/fixtures/stdlib_compiler_state/regex_workspace_admission/README.md)
  preserves the original question-mark module beside six passing reductions
  and equivalent explicit guards. It does not establish a single failing
  operator or make ordinary propagation unavailable.
- Rebased onto `origin/lang` `0d2e4a07`. The initial
  [language-feature cleanup](library-language-adoption.md) adopts item imports,
  local inference and selected propagation paths in six library modules plus
  range-dot. Focused native library gates and all 67 application cases pass;
  package-lock item imports, relocated source bundles and reference generation
  also pass. Public type/signature contracts are unchanged. A generic nested
  Option `?` path compiles but crashes in both minimal reductions; match controls
  execute, so production flatten retains its explicit match. Further cleanup
  remains gradual and runtime-gated. Archive extraction retains its preceding
  accepted finite native scope below.
- [Content-only archive extraction](library-archive-extraction-plan.md) now has
  frozen production interfaces: `archive_plan`, `archive_profile`,
  `archive_source` and `archive_extract`, plus checked `create_dir_at`/
  `remove_dir_at` and raw ZIP `version_made_by` metadata. Primitives pass 55
  process invocations; ZIP metadata passes one eight-record/two-view Rust
  control; Plan passes direct contracts/76 modeled namespaces and a separate
  allocation baseline plus three reached failures; Profile passes 222 authored
  cases across four groups. Source passes TAR26/ZIP26/limits58/allocation10
  process invocations (120 including repeated baselines and eight reached OOM),
  with pre-exit mapping/fd ownership checks. The CLI passes trees7/arguments27/
  bounds30/report5 through four Rust tests, then five direct retained-ELF input
  fault cases. The added fifth libtest has build admission only. Direct Run
  passes 11 Python groups/100 process invocations on one CLI-compiled ELF:
  success12/existing8/partial3/bounds25/allocations8+8/namespace9/sync5/writes8/
  close-rename6/recovery8. The allocation groups include two calibrations and
  14 reached ENOMEM cases; counts overlap baseline contexts. Production remains
  `cf1347d5...`, probe ELF `268b8bed...`. The direct Rust driver built in 1.26s;
  the earlier three libtests failed before native fixture admission, and no
  passing direct libtest rerun is claimed. Logs under `target/stdlib-work/` are
  `archive-materializer-tree-single-owner-retry.log`,
  `archive-materializer-bounds-first.log`,
  `archive-materializer-allocations-first.log`,
  `archive-materializer-namespace-sync-fcntl-retry.log`,
  `archive-materializer-write-close-first.log` and
  `archive-materializer-recovery-first.log`. Dedicated guides hold full
  source/ELF identities and earlier pre-native import/syntax corrections.
  These native Linux x86_64/kernel7.0.0-38/ext4-under-`/tmp` receipts accept the
  selected bounded workflow, not GPU-kernel filesystem services or the full
  standard/extended library goal.
  The [reference writer/check](library-api-reference.md#current-generation-receipt)
  pass at the archive freeze: 250 pages, 249 modules and 8,197 public declaration
  markers. Four new archive pages, ZIP, FileOps and the index are regenerated;
  26 focused generator tests pass in 3.129s. Protected human file hashes match
  before/after. This is source inventory/tooling evidence, not runtime coverage.
  A separate same-ELF observation unpacks 273 ZIP entries (256 small files,
  16 directories and one 2 MiB compressed payload): 71,261 input bytes and
  2,129,920 decoded bytes in 1.653438s untraced, including startup/read/fsync/
  reports. Exact result validation is outside the timer. This one sample adds
  no finite-case count or compiler/throughput ratio; receipt:
  `archive-unpack-observation-first.log`.
- [AtomicFile publication](stdlib-atomic-files.md) and the earlier
  [`kv_tool` migration](extended-kv.md#historical-atomic-publication-application-receipts) pass their
  selected native gates on Linux x86_64, kernel `7.0.0-38-generic`, ext4 under
  `/tmp`. AtomicFile owner nine, bounds 25, publication six and faults 26 total
  66 process invocations across four groups, including baselines. The preliminary
  smoke case overlaps, adding no distinct behavior. The critical publication
  case observes Published bytes plus a live retained directory anchor before
  allowing explicit sync retry, which performs no second rename. The bounds
  retry corrects only the fixture's owned-fd payload selector, with unchanged
  product/probe source and the same compiled ELF; 36 CPU controls pass separately.
  Receipts are `atomic-file-owner-group-first.log`,
  `atomic-file-bounds-selector-retry.log`, `atomic-file-publication-first.log`
  and `atomic-file-faults-first.log` under `target/stdlib-work/`.
  That historical application removes caller-supplied SCRATCH operands, anchors
  load/publication to one parent/leaf, uses NoReplace for init and Replace for
  updates, and preserves publication/cleanup outcomes even if stderr fails.
  Round trips 33 and publication 31 total 64 process invocations across two
  groups; publication includes 13 reached source OOM and 15 I/O controls.
  Receipts are `kv-tool-atomic-syntax-retry-compile.log`,
  `kv-tool-atomic-roundtrips-first.log` and `kv-tool-atomic-publication-first.log`.
  The first compile failure needed only an application match-arm syntax change;
  no compiler change was made. Eleven KV CPU binding controls and two Rust
  driver `--no-run` admissions are separate from actual direct native oracles;
  no libtest execution is claimed. The portable Store API/snapshot format are
  unchanged. Its 64 cases and older scratch-path CLI receipts are not added to
  the current hierarchy application's 130-case receipt above. Namespace authority remains
  exclusive/cooperative, without locking, network-filesystem semantics or
  universal power-loss guarantees. The [archive increment](library-archive-extraction-plan.md)
  now composes that foundation within its accepted finite native profile.
- Accepted temporary-file prerequisite checkpoint:
  [`std::temp_file`](stdlib-temp-files.md) and
  [descriptor-relative removal/rename](stdlib-file-operations.md#descriptor-relative-name-mutations)
  pass owner eight, collision six, validation 18, fault 19 and primitive 27
  process invocations across five separate native groups. The total 78 includes
  repeated baselines; the preliminary basic-owner and bounds receipts overlap
  and do not establish 80 distinct cases. The fault group is its baseline,
  one reached 37-byte dynamic source OOM and 17 other cases. Independent source
  runtime/FD-generation ledgers and applicable pre-exit owner observations pass;
  26 CPU controls and Cargo `--no-run` driver admission are separate receipts.
  Target evidence is native Linux x86_64, kernel `7.0.0-38-generic`, ext4 under
  `/tmp`. The manual TempFile owner retains its own directory anchor, uses
  exclusive no-follow/CLOEXEC creation and bounded OS entropy, and preserves
  name/anchor recovery after failed removal. Keep disarms deletion on the same
  owner without I/O; close retires its descriptor once. Namespace authority is
  exclusive/cooperative, with no hostile-name or crash-durability claim. No new
  runtime binding or cryptographic implementation is introduced. The separately
  accepted AtomicFile/KV layer above now completes the next phase of the
  [approved plan](library-atomic-files-plan.md) within its finite local profile.
- Current increment, implemented with partial native acceptance:
  [resumable concurrent HTTP/HTTPS servers](library-server-concurrency-plan.md)
  place request/response state and explicit application decisions in one
  `http_server::Protocol`, with plain and
  [OpenSSL server drivers](extended-https-server-exchange.md) and one bounded
  `server_poll` scheduler. Handlers must stage borrowed response storage
  synchronously through a reply sink; reports must retain valid typed errors,
  not expired request views. The finite service counts every accepted
  socket, caps active handshakes/transfers/drains, preserves per-connection
  deadlines under one service deadline, and exposes explicit stop/drain/abort
  controls. The [shared Protocol/plain-driver contract](library-server-contract.md)
  is frozen; integration acceptance is in progress. The
  [scheduler guide](extended-server-poll.md) describes its typed owner and
  reporting surface. Native Linux x86_64/glibc evidence now covers 50 distinct
  direct plain cases (four steps, 11 decisions, four drain, six lifecycle,
  23 faults and two additive abort cases). Stronger typed OOM diagnostics pass
  the same 23 fault cases across 15 reached allocation sites; two invalid-count
  reruns repeat lifecycle cases and do not increase the coverage total. The
  current synchronous facade passes three cases in 10.72 seconds. Direct HTTPS
  passes 34 cases across seven groups and separate receipts: six verified steps (12.87 seconds),
  two closure cases, four preparation/abort cleanup cases (12.11 seconds) and
  four normal-close cases (11.40 seconds), including reached close EIO faults,
  six constructor/quota cases (11.07 seconds) and four constructor-allocation
  cases (10.88 seconds). Three dynamic source allocation failures are reached;
  this is not native OpenSSL heap accounting or fault injection. Eight paired
  TLS 1.2/1.3 teardown cases also pass in 21.05 seconds
  (`https-server-exchange-teardown-first.log`), covering missing-alert timeout,
  a cut actual native record, drain-cap overflow and authenticated empty input,
  with pre-exit native/source/descriptor checks and sticky fatal replay. The
  accompanying 31 CPU ledger controls are not extra native cases. Rare WANT
  schedules and post-native-call clock failures retain finite coverage gaps.
  Seventeen scripted profiles execute the actual Server across separate
  receipts: the previous seven owner/publication/refill/reservation profiles,
  three owned E/A profiles in 13.60 seconds
  (`server-poll-owned-errors-current.log`) and seven active-cap/cancellation
  profiles in 13.42 seconds (`server-poll-active-limits-api-retry.log`).
  A separate no-Destroy native control passes both thin serve_until helpers
  and empty-report transfer in 21.84 seconds
  (`server-poll-nondestroy-runtime-first.log`). Its empty-report scope is
  separate from the populated owned-error receipt above.
  Actual plain and TLS 1.3 programs each pass two causal cases: held setup with
  queued refill, and a held 4 MiB response reader. The plain observations are
  0.060573/5.149525 traced seconds; TLS is 0.158297/6.473137. All four enforce
  two-owner/three-socket caps, and both readers require real EAGAIN, complete
  binary responses and explicit authenticated closure where applicable. Their
  initial/resumed ordinary receive capacities are 131,072. The earlier
  artificial-buffer timeout investigations remain in the
  [fixture guide](../tests/fixtures/extended/server_concurrency/README.md).
  The current HTTPS application separately passes 30 matrix, 23 failure and
  49 limit cases (102 total across three invocations). Current mutual-TLS modes
  pass 35 matrix, 34 failure and 32 limit cases (101), pairing the previously
  accepted fetch executable with the current serve executable. Receipts are
  `https-serve-shared-scheduler-{matrix-expect-policy-retry,failures-first,limits-first}.log`
  and `https-mutual-shared-server-{matrix-first,failures-first,limits-first}.log`
  under `target/stdlib-work/`; these Python logs supply no wall-time claim.
  Fresh plain application groups also pass: matrix 30, quota one, limits 16,
  boundaries 25 and faults 41, in `http-serve-current-{matrix,quota-first,limits-first,boundaries-first,faults-first}.log`.
  This is 113 process-case invocations across separate groups, not distinct
  coverage: the standalone quota case repeats within faults. The fault group
  reaches 23 source-allocation positions plus 18 other cases; its expected count
  follows the observed allocation count rather than a fixed historical total.
  A separate actual plain-driver poll-fault gate passes two reached cases and
  one calibration (`server-poll-marked-poll-faults-format-retry.log`), reusing
  the compiled ELF. After positive partial-head progress and receive EAGAIN,
  injected EINTR requires a fresh publication, no stale-hint read and successful
  recovery. Reached EIO publishes shared PollIo(5), cleans up the live owner and
  preserves the caller-owned listener. These are not two more scripted profiles:
  the scripted count remains 17. The first compile/native attempt failed after
  15.03 seconds only because the Python close witness compared string alignment;
  structured fd/result/frame checks correct that witness, with no production
  change. The accepted Python-only retry records no elapsed-time claim. Mixed
  invalid/valid mutual-TLS admission under concurrency remains uncovered by the
  separate sequential application matrices. The
  [declaration reference](library-api-reference.md#current-generation-receipt)
  passes at the AtomicFile/KV, TempFile/FileOps and server interface freeze
  (246 pages, 245 modules, 8,119 markers), with current finite receipt metadata.
  This supplies no runtime acceptance. Earlier sequential HTTP/HTTPS receipts retain
  their separate scope. Both application guides document explicit 100 Continue
  even when HTTPS body bytes are already buffered. The separate lower-layer
  OpenSSL shutdown experiment passes 12 cases across TLS 1.2/1.3; it does not
  substitute for direct-driver or concurrent-application gates.
  The separate [scale observation](../tests/fixtures/extended/server_concurrency/README.md#separate-scale-observation)
  passes both modes: 64 native echo connections, eight-client demand and checked
  64 KiB binary bodies (4,194,304 bytes total per mode), with actual active/socket
  peaks four/five and all 64 acceptance-order reports validated. Plain makes
  1,224 verified source allocations and peaks at 1,165,325 requested source bytes
  in 3.346761 traced seconds; TLS makes 1,419 and peaks at 1,352,377 bytes in
  4.226492 traced seconds. Receipts are `http-serve-concurrent-scale-first.log`
  and `https-serve-concurrent-scale-first.log`. Compilation, credential/site
  setup and final trace audit are excluded from wall time; native startup,
  client/network/handshake/closure work and tracing are included. Native/OpenSSL
  heaps, RSS and the separate bootstrap mapping remain outside the source ledger.
  These are finite observations, with no throughput or compiler-speedup claim.
- Accepted client checkpoint `75ab38d1`, all selected transport/integration gates accepted:
  [HTTP Protocol](extended-http-client.md) centralizes request staging,
  framing, decoding and response ownership independently of transport.
  [Generic batch scheduling](extended-http-batch.md) supplies one preparation,
  admission, refill, polling, accounting and cleanup engine with typed driver
  errors. The [HTTPS driver](extended-https-client.md) and
  [HTTPS batch adapter](extended-https-batch.md) compose this boundary with
  OpenSSL peer verification, context retention and stable independent
  read/write retry state. A production-shaped control compiles and exits zero
  using the actual public generic traits and Report destruction with two
  error types, including nested owned payloads
  (`target/stdlib-work/resumable-transport-production-shape-first.log` and
  `resumable-transport-production-shape-native.log`). This control does not
  execute the scheduler. All nine raw OpenSSL duplex groups pass 36 cases through
  separate receipts: four causal, two notification and four synthetic
  rare-WANT cases in 6.43 s
  (`target/stdlib-work/openssl-tls-duplex-initial-groups-first.log`), plus
  20 backpressure, buffered-input, independent-owner, shutdown and fatal-error
  cases in 6.20 s (`openssl-tls-duplex-five-edge-groups-first.log`); and a
  baseline plus all five reached source-allocation failures in 7.36 s
  (`openssl-tls-duplex-source-allocations-first.log`). That last group also
  checks nine resource-ledger rejection controls. These source-owner checks
  do not cover native OpenSSL malloc failures. Selected legacy client/server/
  mutual-TLS retry guards separately pass 3, 1 and 6 cases in 6.48, 6.26 and
  7.01 s (`openssl-tls-client-duplex-guards-regression.log`,
  `openssl-tls-server-duplex-guards-regression.log` and
  `openssl-mutual-tls-duplex-guards-regression.log`). These are selected groups,
  not complete reruns of all historical native TLS suites.
  [Connected HTTPS gates](extended-https-batch-testing.md) compile the actual
  adapter and pass all six groups, covering 108 cases across three receipts:
  five verified overlap/ownership and four framing cases in 11.01 s
  (`target/stdlib-work/https-batch-initial-two-groups-first.log`); 11 peer-policy,
  six transport and 16 quota/cancellation cases in 14.04 s
  (`https-batch-policy-transport-limits-first.log`); and 66 resource/direct
  cases in 37.52 s (`https-batch-resource-direct-typed-retry.log`). The final
  group fails each of 42 reached source allocations individually, including
  16 after networking began, and adds 24 fault/recovery controls including six
  direct-step/abort invocations. Its first resource invocation stopped during
  direct-fixture compilation with nested-pattern `AssignMismatch`, before
  Python cases ran; explicit typed matches preserve the assertions and the
  passing retry needs no production/compiler patch. The failing form remains
  recorded separately. The [direct Protocol group](extended-http-protocol-testing.md)
  passes in 7.94 s (`target/stdlib-work/http-protocol-direct-contracts-first.log`)
  with 247 successful mappings explicitly released and no network/poll/close
  calls. This is a finite state/ownership contract run, not 247 allocation
  denials or proof of native transport behavior.
  The refactored plain client passes six synchronous groups (188 cases) in
  27.70 s (`http-client-shared-protocol-sync-regressions-first.log`), including
  each of the 13 and 22 reached allocation positions on two workloads. Its
  direct Exchange passes all five groups (83 cases) across a three-case
  7.93-second run (`http-protocol-extraction-steps-first.log`) and four remaining
  groups/80 cases in 9.90 s
  (`http-exchange-shared-protocol-remaining-regressions-first.log`), including
  the separate 12- and 14-position allocation sweeps. Production source did
  not change between the first and remaining direct-group runs.
  The generic plain batch passes its seven original groups (102 cases) in
  13.00 s (`http-batch-shared-protocol-generic-regressions-first.log`) and the
  new causal wait-retirement group (one case) in 10.07 s
  (`http-batch-wait-retirement-coherent-limits-retry.log`): eight groups and
  103 cases through two receipts, with cleanup checked before process exit.
  The migrated [HTTPS fetch application](extended-https-fetch.md) passes its
  three existing application groups: 18 matrix, 14 failure and 26 limit cases
  in 11.12 s (`target/stdlib-work/https-fetch-shared-exchange-app-first.log`).
  Its new empty-body/large-output group passes five cases in 8.92 s
  (`https-fetch-empty-zero-limits-mebibyte-first.log`), including an exact
  1,048,576-byte binary response. Thus all four current application groups
  pass 63 cases across two receipts; the separate buffered-stream group is
  excluded, and this is not one whole-suite invocation.
  Its [mutual-TLS application regressions](extended-https-mutual-tls.md) pass
  35 matrix, 34 failure and 32 limit cases in 18.14 s
  (`https-mutual-tls-shared-fetch-app-first.log`). That 101-case receipt
  excludes the prepared-context stream group. The current
  [fetch-many integration](extended-fetch-many.md) passes all five groups in
  24.18 s (`target/stdlib-work/fetch-many-generic-batch-current-regressions-first.log`):
  16 matrix, 31 failure, 66 limit, 61 resource and 19 real-I/O cases, plus one
  scripted harness covering 38 production helper scenarios. Resources include
  all 59 reached allocation failures. Its traced 64-job control transfers
  65,536 body bytes into a 72,861-byte ZIP, peaks at four sockets, makes 1,133
  source allocations and reaches 350,928 simultaneously live requested bytes
  in 0.235 s. These finite traced measurements are not RSS or throughput
  guarantees. Historical full native TLS matrices and excluded buffered/
  prepared-context stream groups retain their distinct older scope; the
  selected current groups do not constitute one whole-suite invocation.
  The [nested-pattern compiler dependency](../tests/fixtures/extended/https_batch/compiler_admission/README.md)
  now has a confirmed 14-line reduction with no HTTP/TLS imports: the CLI
  rejects `nested_io.lani` at 6:59 with `LNC0006`. Its explicit two-match
  `typed_io.lani` control compiles to a validated x86_64 ELF and exits zero
  after all four assertions. This reproduces an unresolved admission
  limitation without changing compiler or production library behavior.
  Review also corrected a generic scheduler path that could block on siblings
  after `before_wait` retired another owner, delaying queued admission. The
  first dedicated regression compiled but failed after 10.29 s before its
  report with premature protocol EOF. Review classified a fixture budget
  mismatch: its one-million work allowance was below canonical validation's
  default precharge of 26,476,544 units. The fixture now selects coherent
  head/line/header/trailer caps while preserving its work allowance, causal
  dependencies and required outcomes. The corrected fixture passes its
  10.07-second runtime retry above; the first failed attempt is not acceptance
  evidence and required no change to production accounting or behavioral
  assertions.
  The
  [regression fixture](../tests/fixtures/extended/http_batch_wait_retirement/README.md)
  records the causal dependency, diagnostic evidence and budget correction.
  The generic contract requires
  `before_wait` returning `Ok(true)` to preserve the previously observed
  Interest and valid descriptor identity until poll registration. Borrowed
  error payloads must outlive the returned Report/Failure and any taken
  outcome through their final use/destruction, which can follow run return.
  Historical receipts below do
  not accept the new Protocol, generic/error or TLS retry contracts. Worker
  threads, native callback entry and broader library coverage remain open;
  the [concurrency audit](library-concurrency-dependencies.md) records the
  separate compiler/runtime dependencies.
- Accepted checkpoint `480432e8`:
  [resumable HTTP and batch scheduling](extended-http-batch.md) shared one
  canonical request/framing engine. All five direct
  [Exchange groups](extended-http-exchange-testing.md) pass 83 cases across
  separate receipts: 3 + 20 + 2 in a mixed 9.35 s invocation, and the remaining
  10 + 48 in an 8.58 s retry, including both reached-allocation sweeps (12 and
  14 positions). The synchronous client separately passes six groups and 188
  cases in 26.85 s after refactoring
  (`target/stdlib-work/http-exchange-client-regressions-current.log`).
  All seven batch groups are accepted through separate receipts: 16
  contract cases in 9.84 s; 10 matrix and 14 fault cases plus 36 reached OOM
  positions (38 resource processes) in a mixed 13.79 s run; and five overlap
  plus 18 limit cases in the corrected-source 9.62 s retry. The final one-case
  consecutive-begin-failures regression passes in 8.54 s
  (`target/stdlib-work/http-batch-consecutive-begin-failures.log`): exact EIO
  injections on socket attempts three/four, no positive-time poll before the
  fifth valid queued socket, ordered Complete/Complete/Failed/Failed/Complete
  outcomes and checked owner/descriptor cleanup. The
  [fetch-many](extended-fetch-many.md) app
  passes all five groups across two accepted receipts: final matrix 16,
  failures 31 and resources 61 (59 reached OOM positions) in 15.63 s
  (`target/stdlib-work/fetch-many-matrix-failures-resources-final.log`), plus
  limits 66 and I/O 19 with 38 internal production-helper scenarios in 18.81 s
  (`target/stdlib-work/fetch-many-failures-limits-io-first.log`). Its traced
  64-job control decodes 65,536 bytes into a 72,861-byte ZIP, peaks at four
  sockets, makes 1,133 allocations and reaches 349,680 simultaneously live
  requested bytes in 0.245 s. This is finite traced process evidence, with no
  RSS or throughput claim. Public ZIP name validation shares the writer policy
  and passes the existing ZIP contract in 6.79 s. These native Linux x86-64 CPU
  programs are built by the GPU compiler and use one-thread/poll cleartext
  numeric connections, manual owners, a common deadline and logical retention
  caps. These receipts cover that preceding concrete scheduler and transport;
  the current generic/Protocol revision requires new gates. Resumable TLS and
  threads remain in scope; the
  [concurrency prerequisites](library-concurrency-dependencies.md) preserve
  separate executable controls and unresolved compiler/runtime admissions.
- Earlier [anchored longest-prefix matching and reusable lexers](extended-lexer.md)
  passed five native groups through separate receipts: full-context model cases,
  assertion/capture/error tables, construction/input caps and exact owner
  cleanup at all 120 allocation failures reached by the fixtures. Ordinary
  regex matching retains its prior semantics; both existing groups pass again
  in 9.70 s. The [CSV-rules lexer program](extended-lex-scan.md) passes all five
  groups: its 124-input/two-mode matrix in 8.40 s, error/scripted-I/O/resource
  groups in 14.16 s, and both 30-position OOM campaigns plus I/O faults in
  8.36 s. The 4,096-token run made 36,887 allocations with balanced releases;
  these allocation counts belong to the prior per-probe implementation. Fixture
  and harness corrections preserve exact syntax-error offsets and bounded
  failure-path allocation cleanup. The app uses explicit I/O result types;
  the reduced inference failure remains documented, with no compiler changes.
- Earlier [regex split/replacement adapters and stdin rewrite CLI](extended-regex-text.md)
  passed six focused groups through separate GPU-compile/native receipts. That
  implementation used Matches for captures and empty-match progress. Tests
  cover 288 independent nonempty reference cases across checked axes and three
  layouts, 89 explicit edge tables, all 77 reached library allocation failures,
  24 CLI cases, all 43 reached CLI allocation failures and four I/O schedules.
  Output owners and borrowed fields have explicit manual lifetimes; aggregate
  search work reserves VM allowances rather than counting all CPU work.
- [Reusable CSV construction and bounded stream writing](extended-csv-write.md)
  execute through the shared canonical encoder, with complete preflight,
  accepted-prefix errors and explicit output/write-attempt limits. All five
  groups pass via separate receipts, including six staged-growth allocation
  failures and 4,096 allocation-free record reuses. The
  [column rewrite program](extended-csv-rewrite.md) also passes five groups:
  62 independent output cases, 88 limit cases, 11 real I/O cases, scripted
  production-helper scenarios and allocation/resource controls. Its 4,096-row
  run retains the one-row allocation count and peak storage. The
  [compiler dependencies](library-context-inference-dependencies.md) preserve
  failing unannotated result contexts and nested/literal matching beside
  passing controls; no compiler source changed in this batch.
- Previously accepted client TLS profile: [ext::openssl_tls](extended-openssl-tls.md) uses
  OpenSSL 3 `libssl`/`libcrypto` for all TLS and sensitive operations. Fifteen
  verified transfer/identity cases pass in 18.56 s; seven closure/truncation
  and three stable-retry cases pass in a shared 18.01 s run whose separate
  legacy verification fixture initially failed. After correcting the test
  peer's fatal-alert flush and establishing a real TLS 1.1 CPU control, all
  nine verification-rejection cases pass independently in 16.73 s. Production
  TLS source is unchanged across those gates. The guide records each receipt,
  mandatory trust/identity, borrowed nonblocking sockets, manual ownership,
  caller deadlines and SIGPIPE policy. This covers 34 cases across four groups,
  with no single all-green suite receipt claimed. The
  [TLS stream/HTTPS application](extended-https-fetch.md) passes all four groups
  in 14.44 s: 4 stream, 14 verification/HTTP-failure, 26 limit and 18 binary/
  framing cases, recorded in `target/stdlib-work/https-fetch-execution-current.log`.
  Numeric endpoints, explicit trust/identity, deadlines and manual ownership
  remain the supported scope. Server TLS and the HTTPS service have separate
  passing gates below; mutual TLS has since advanced in its separate gates.
  The full security family remains open.
- Accepted [opt-in deep HashMap cloning](stdlib-clone-hash-map.md): four native
  groups pass on Linux x86_64 through the GPU compiler. The independent nested
  owner contract passes in 7.46 s; the remaining three groups pass in 11.71 s,
  including 14 reached allocation failures, 18 owned key/value errors, six
  identity changes, two defensive cleanup cases, collisions/tombstones and
  empty/zero-sized paths. Ordinary inherent methods retain their shallow
  policy. [Recursive deque cloning](stdlib-clone-deque.md) also passes four
  native groups: contracts in 7.80 s and three model/failure groups in 12.28 s,
  covering 379 logical cases, 13 nested allocation failures, six owned-error
  paths and 33 owned-error allocation failures. [Deep heap cloning](stdlib-clone-binary-heap.md)
  passes all five native groups: contracts in 5.96 s and four model/failure
  groups in 12.01 s, including Min/Max priorities, empty/zero-sized values,
  13 typed allocation failures, 16 owned-error paths and all 96 reached
  owned-error allocations. [Deep TreeMap cloning](stdlib-clone-tree-map.md)
  passes all five active native groups: the contract group in 9.83 s and four
  prerequisite/construction/failure groups in 13.47 s, with the manual probe
  ignored. Coverage includes sorted staging, independent String/Vec owners,
  transfer/reset, empty/zero-sized values, 15 reached clone-allocation failures,
  12 owned key/value errors and three changed-key cases. Two general compiler
  fixes restore local nominal layout through canonical identity and preserve
  checked aggregate widths when fields are zero-sized. The
  [dependency record](library-dependencies.md) describes the exact mechanisms;
  unrelated generic replay reproductions have not been revalidated.
- Accepted [OpenSSL server TLS](extended-openssl-tls-server.md): six groups
  pass 53 cases in 5.98 s, covering credentials and encrypted passphrases
  without prompting, context references, stable retries, closure/truncation,
  12 native fault boundaries and all six reached staging allocations.
  The existing mandatory client trust/identity/protocol gate still passes
  nine cases in 5.98 s. [Shared TLS streams and HTTPS service](extended-https-server.md)
  pass all four server groups: 28 verified exchange cases in 7.17 s and
  78 limit/failure/stream cases in 10.87 s. The existing HTTPS client passes
  all 62 cases again in 13.90 s after the shared ownership change. The service
  uses numeric endpoints, one absolute deadline per sequential connection slot,
  the canonical HTTP codec and an explicit unauthenticated-client TLS policy.
  Mutual TLS has since advanced in separate library and application gates;
  keepalive and concurrent scheduling remain work.
- Accepted [mutual TLS](extended-openssl-mutual-tls.md): six library groups
  execute 107 cases across separate receipts. Native OpenSSL verifies client
  chains/purpose/possession, required servers disable resumption and both roles
  check peer presence after native completion. Shared credential loading
  supports explicit passphrases without prompting. The existing nine-case
  client rejection group and all 53 server cases still pass. The
  [prepared client connector and HTTPS credential modes](extended-https-mutual-tls.md)
  execute 109 process cases across four groups: eight borrowed-context cases
  in 6.21 s and the other 101 cases in 15.23 s. TLS 1.3 local completion is not
  treated as proof that the remote endpoint accepted a client certificate.
  All cryptographic operations use OpenSSL; application principals,
  authorization and broader security interfaces remain work.
- Accepted [scalar and structural cloning](stdlib-clone-values.md): all five
  groups pass in 19.37 s, covering fourteen scalar types, exact IEEE bit
  transport, nested Option/Result/Pair/String/Vec owners, active-only callbacks,
  minimal bounds, 18 callback scenarios, 14 owned errors, all 45 reached
  allocation failures and four actual-call rejections. The
  [empty-enum layout repair](compiler-empty-enum-layout.md) aligns three GPU
  producers with the existing one-word enum tag ABI. The six paired reductions
  and separate raw-stride assertions pass, and four inhabited structural
  controls pass; no separate callee-layout fallback was introduced.
- Accepted deep set ownership: [HashSet](stdlib-clone-hash-set.md) passes
  three native groups in 15.05 s, including 557 sequence/failure/identity cases,
  six owned errors and all 39 reached allocation failures. [TreeSet](stdlib-clone-tree-set.md)
  passes its contract group in 9.61 s and four model/failure/selection groups
  in 10.73 s, including a 512-state ordered model, observable O(n log n)
  construction, nine reached allocation failures and owned-error rollback.
  Both preserve independent String owners and reuse the existing shared map
  engines. Ordinary set methods retain their shallow ownership policy.
- Accepted [persistent indexed ZIP snapshots](extended-archive-index.md):
  the 56-case ownership/binary-name matrix passes in 8.27 s; six remaining
  groups pass in 17.16 s, including 30 corruption cases, 40 limit cases,
  nine native recovery cases, all 29 import and 23 read allocation positions,
  and scripted short I/O. The 1,024-entry workload expands to 8 MiB and saves
  an 8,005,812-byte ZIP: import takes 1.385 s, and count/list/seven gets/export
  take 4.422 s in this one measured run. These are application process times,
  including decompression, validation and native persistence, rather than
  isolated SQLite lookup timings. Dedicated schema, ordinal/raw-byte names,
  all-entry import CRC checks and uncertain transaction recovery are explicit.
- Accepted native object storage: original and generic replay section bytes
  spool privately, exact original admission facts remain intact, and ELF export
  streams one payload at a time. A two-file 6 MiB source pack executes in one
  group in 3.86 s, including private C calls through imported generics, direct
  file output and output-limit preservation. Eighteen exporter/linker CPU tests
  pass in 0.94 s; three storage, two atomic-output and two new facts/metadata
  tests also pass. The combined host build takes 35.42 s. The
  [native guide](library-native-c.md) records receipts and response/diagnostic/
  output limits. Source snapshots and global metadata still grow with the
  program; explicit source-pack descriptor CLI modes remain unsupported.
- Accepted SQLite milestone: the owned [adapter](extended-sqlite.md) and
  [persistent binary key/value application](extended-sqlite-kv.md) execute on
  Linux x86_64/glibc through system SQLite. Lanius supplies interface, staging,
  limits, errors and explicit cleanup. Four ordinary library groups pass in
  14.92 s, including 558 typed-value cases and 640 model commands; all 21 native
  failure modes pass in one group in 9.03 s. The
  [staging allocation gate](extended-sqlite-allocation.md) passes one group in
  8.60 s: baseline plus failures at all four reached path/SQL/text/blob staging
  requests, with retries and mapping/native-owner ledgers. Five application
  groups pass in 17.54 s, covering 99 oracle cases plus scripted stream checks.
  The compiled bulk run performs 32,768 inserts and 32,768 indexed selects in
  51.798074 ms, excluding GPU compilation, with SQLite reporting a 545,848-byte
  allocation high-water mark. Independent aggregate/index checksums match. The
  linked guides record receipts and the metric's limits; the full library goal
  remains open.
- Current accepted C ABI extension: `f32`/C `float` and `f64`/C `double`
  transport through independent SSE8/GPR6 banks, with up to 32 total scalar
  parameters. The native float gate passes one group in 8.03 s, covering exact
  IEEE bits including NaN payloads, mixed register/stack arguments and alignment,
  imported generic replay and live SSE clobbers. Four declaration-contract
  groups pass in 9.77 s, and the eight existing integer/pointer execution groups
  pass in 10.55 s. Two native C semantic-interface CPU tests pass in 0.00 s after
  a 42.45 s test build, checking binding identity/signature round-trip and forged
  or unsupported profile rejection. The compiler build completed in 46.71 s. The
  [native C guide](library-native-c.md) records receipts. Existing scalar IDs
  and ABI metadata represent the extension without an artifact version change.
- Earlier accepted native milestone: [checked C declarations and native linking](library-native-c.md)
  execute on Linux x86_64/glibc, including scalar normalization, register/stack
  arguments through 32 parameters, imported generic replay and CRT startup.
  [OpenSSL EVP digests](extended-openssl-digest.md) and the
  [hashing program](extended-openssl-hash.md) execute with dynamic `libcrypto.so.3`.
  The four focused gates pass 3 declaration groups, 8 native-call groups,
  4 digest groups covering 2,124 cases plus 12 failure modes, and 3 application
  groups. Semantic interface v17 and x86 object v4 require rebuilt artifacts.
  File-backed native linking, callbacks, foreign thread entry, TLS, encryption,
  signatures, certificate trust and SQLite wrappers remained open at that
  checkpoint; the SQLite, client TLS and native storage milestones above supply
  their later execution evidence.
  The full library goal remains open.
- Raw [DER](extended-der.md) and [X.509 structure parsing](extended-x509.md)
  remain useful schema inspection tools. The
  [certificate inspector](extended-certificate-info.md) reports schema metadata without a cryptographic fingerprint or trust decision.
- [Bounded nonblocking entropy](stdlib-entropy-bounded.md) retains one charged
  getrandom attempt per read, explicit partial progress and shared attempt
  budgets. Socket, polling and clock contracts remain separate.
- Previous milestone: runtime formatting to generic byte writers, using the
  existing parser/renderer, bounded scratch, complete preflight before output,
  exact confirmed failure progress and explicit call budgets. Independent
  models, preflight/failure/nested-buffering gates and the real
  [CSV report](stdlib-format-report.md) execute on native x86_64 Linux. The
  preceding owning Vec/Deque cursors transfer cleanup authority and recover
  original storage; their compiler replay dependency remains recorded. The
  complete library goal still includes the remaining families and prerequisites
  listed above.
- Earlier host/integration milestone: the explicit native Linux syscall boundary, owned TCP/UDP
  sockets and signal dispositions; configurable files, metadata, raw directory
  iteration and bounded walking; reusable descriptor readiness and explicit-server
  DNS transport; complete default Unicode sentence/line boundaries and terminal
  wrapping; typed settings and four continuous plus four discrete distributions.
  Real programs, independent models/conformance corpora,
  allocation/descriptor/I/O failure checks and source reviews are recorded per
  guide. Numeric helper consolidation removes seven obsolete modules.
  Subprocesses and a real command runner now pass focused native lifecycle and
  fault gates; startup EOF is explicitly Unconfirmed and ambiguous outcomes
  retain a child owner. Concurrent pipe capture adds byte/work/deadline limits
  and retained failure progress; nonblocking waits make one host attempt.
  Incremental HTTP framing, a connected cleartext client and staged server
  connections now compose owned socket transport, strict final parsing and
  checked binary body publication. The bounded local health/echo service was
  accepted at `493d4e87`; server keepalive/concurrent scheduling and TLS remain.
  Range overlap requires total ordering, with partial-order membership retained.
  Raw host thunks preserve native-width sizes/counts/capacities and validate
  allocator alignments. A private length-derived GPU dispatch emits every
  runtime byte, including the relocated syscall and assertion tail.
  Seventeen ordinary collection/output samples now use
  checked APIs and real closed-pipe cleanup. The heap view boundary constructs
  directly from initialized owner state; original failed source is preserved.
  These APIs execute as x86_64 Linux programs produced by the GPU compiler;
  user GPU kernels and other targets were unverified. Threads, TLS, SQLite,
  generic adapter composition and final distribution/reference work remained
  open at that checkpoint.
  A generated declaration reference covers the current source inventory;
  semantic guide gaps stay explicit. Native thread-entry, memory-ordering and
  remaining foreign-call prerequisites have a separate [boundary guide](library-native-integration-prerequisites.md).
- Preceding milestone: canonical narrow integers, full-range binary64 elementary
  functions, generic owned hash/tree sets, TZif time zones, DNS and WebSocket
  request/frame processing, byte key/value snapshots, signal processing and selective
  source distribution. Five new native programs and four migrated set consumers
  exercise real behavior. Independent models, malformed-input/resource cases,
  allocation/I/O faults and independent source reviews are recorded per guide.
  Supported execution remains x86_64 Linux output from GPU compilation. The
  [host prerequisite audit](library-host-prerequisites.md) names missing services;
  sockets/processes/threads, SQLite, generic adapter composition and final
  distribution/reference/completion work remained open at that checkpoint.
- Preceding milestone: native 64-bit/pointer integers; Lanius source test/property/
  benchmark workflow; legacy collection/text consumer migration; exact geometry;
  terminal tables/progress; PNG/image and WAVE/audio utilities; HTTP/1 wire codec.
  Six real applications integrate these families. Independent reviews found
  and corrected PNG unknown-chunk handling, HTTP 205/CONNECT rules, exact audio
  cancellation and Runner failure-state latching. All target claims remain
  native x86_64 Linux; the whole roadmap, host/database services and distribution
  were still incomplete at that checkpoint; current support is recorded above.
- Preceding formatting/parsing milestone: exact float precision, typed runtime
  format strings and owned String/byte results, inline Vec/Eq Set with explicit
  outcomes and symbolic-capacity borrowed APIs, checked parsing cursors,
  shortest line scripts and strict unified patches. The expression calculator
  and file comparison/patch application exercise these modules with reference,
  resource, allocation and I/O failure evidence. The original nested owned set
  wrappers remain preserved as compiler reproductions; current production sets
  use the shared map boundary described above. A generic
  owned Display convenience also remains outside production: primitive-only
  callers expose a context-sensitive native-layout compiler failure.
- Preceding collections/mathematics milestone: owned/counted bitsets with a
  prime sieve, calendar comparison/hash and collection integration, arbitrary
  precision finite decimals with a CSV ledger, statistics and matrix algorithms
  with a numerical CSV analysis/regression program. Independent models,
  numerical edge cases, aliasing, allocation/I/O failures and measured native
  workloads are recorded in the guides above. The whole scope remains open.
- Preceding configuration/text milestone: TOML 1.1 documents and normalization,
  UTF-8 regular-expression search and a streaming grep program, Gregorian/RFC
  3339 calendar values, and complete Unicode 17 default word boundaries and
  full casing with a command-line converter. Each module/application guide
  names its executable target, contracts, limits and tests. These additions do
  not complete the whole scope above; no compiler/runtime implementation is
  supplied as a library substitute.
- Preceding numeric/text milestone: complete basic BigUint/BigInt arithmetic and
  a calculator; Unicode 17 property/scalar mappings, all four normalization
  forms, default extended grapheme clusters and a normalization program.
  [Comparison contracts](stdlib-comparison.md) reject native float keys/sorts
  and provide bit-preserving total wrappers. New source and data generators
  are committed with executable model/conformance/failure evidence; no compiler,
  runtime, ABI, shader, extractor or proof implementation changed. This is
  progress toward the full scope above, not whole-library completion.
- Scope and API conventions: recorded in this document and
  [library-api-conventions.md](library-api-conventions.md).
- Packed owned UTF-8 string: the first implementation and three executable
  test groups pass on x86_64 Linux, including allocation fault injection and a
  text-processing program. See [stdlib-string.md](stdlib-string.md) for exact
  coverage and remaining String operations.
- Compiler and runtime prerequisites: [library-dependencies.md](library-dependencies.md).
- Floating values: [`core::f32` and `core::f64`](stdlib-floats.md) execute exact
  encoding transfer, classification, signs, neighboring values, total comparison,
  integral rounding and correctly rounded square root. Strict clamping traps
  for invalid bounds; checked and explicit-fallback forms are available.
  [`core::float_decimal`](stdlib-float-decimal.md) parses both widths with exact
  nearest-even rounding and formats shortest round-trip decimal using caller
  scratch. `core::fmt` exposes both widths through Display and atomic appends.
  The [streaming normalizer](stdlib-float-normalize.md) exercises conversion,
  square root, generic formatting, bounded byte records and native streams.
  Native bitwise, halfway, exponent, allocation and I/O tests pass. Elementary
  functions, lawful partial/total float comparison and typed owned formatting
  have since advanced as described above; generic owned Display composition
  and numeric consumer consolidation remain.
- Exact decimal validation: [`core::decimal_number`](stdlib-decimal-number.md)
  implements strict JSON-number parsing, exact comparisons/integer queries and
  divisibility with counted work. Two runtime groups compare 2,525 reference
  pairs, including 8,192-digit inputs; independent review checked 832 additional
  native pairs. [`ext::schema`](extended-schema.md) compiles a supported
  JSON Schema profile into indexes borrowing the immutable JSON owner, then
  validates with caller scratch and no allocation. Its broader vocabulary,
  external schema registries and standard output formats remain explicit future
  work. The full standard/extended library goal remains open.
- Arenas: [`alloc::arena`](stdlib-arena.md) provides stable chunked storage,
  explicit retained/chunk limits, reset/reuse, clear, destruction and generic
  typed value/slice copies using the existing native layout contract. Tests
  exercise all primitive widths, nested records/enums, zero-sized values,
  modeled allocation sequences, allocation failures and large reuse batches.
  The [streaming word-count application](stdlib-arena-words.md) stores each
  distinct byte key once and retains stable views in a generic ordered map.
  Current supported alignment is 1, 2, 4 or 8; over-aligned layouts need a
  pointer/alignment operation recorded in the dependency inventory.
- Network values: [`core::net`](stdlib-net.md) executes strict address/socket
  parsing, RFC 5952 formatting, wire octets, full-width comparison/hashing and
  every CIDR prefix width. The [address filter](stdlib-address-filter.md) uses
  these values with native streams and explicit resource limits. URI parsing
  now reuses these IP parsers; all six existing URI runtime groups pass.
  Numeric TCP/UDP sockets now execute through [`std::socket`](stdlib-sockets.md).
  The separate [system resolver](stdlib-resolve.md) now supplies synchronous
  libc/NSS lookup with owned ordered results; all four library groups and five
  resolver CLI groups pass through separate receipts. Asynchronous lookup,
  native NSS memory/time policy and interface discovery remain open.
- Paths: [`core::path` and `alloc::path`](stdlib-paths.md) separate borrowed Unix
  paths and owned buffers from host filesystem services. Component cursors,
  names/extensions, ancestors, prefixes, comparison/hash, joins, atomic edits
  and explicit lexical normalization execute. Tests cover 633 reference pairs,
  4,014 modeled edits, aliased inputs, allocation/write failures, large batches
  and a raw-byte path-joining program. Existing mixed-separator/Windows byte
  rules moved to `core::path_rules` with callers. Direct malformed View-record
  construction has a preserved compiler reproduction and a
  [descriptor-adjustment repair](library-dependencies.md). Host metadata,
  directory walking and the [directory-report application](stdlib-directory.md)
  now execute.
- Time: [`core::time` and `std::clock`](stdlib-time.md) execute normalized
  durations, full-width signed Unix timestamps, monotonic instants, deadlines
  and generic waits with injected or native clocks. Five test groups cover 400
  wide-reference arithmetic cases, simulated interrupts/reversals/long waits,
  native timespec/status fault injection, collection integration, large batches
  and a scheduled JSON-record program. Relative waits preserve the original
  deadline, round up to milliseconds and split requests at the native i32 limit.
  A generic Deadline-factory composition has a reduced compiler reproduction
  and two successful controls; shipped APIs retain their generic interface.
  Other clocks, cancellation and legacy migration remain; optional TZif zones
  now execute as described above.
- Randomness: [`core::random` and `std::entropy`](stdlib-randomness.md) execute
  xoshiro256++ generation, seed/state restoration, jumps, unbiased integer
  sampling, fixed-grid floats, byte filling, generic choice/shuffle and checked
  host entropy. Six focused groups compare author-derived vectors, modeled
  sequences, generic payloads, large batches, injected host/allocation failures
  and a binary-safe line-shuffling program. Generation and sampling allocate
  nothing; shuffle uses the caller's storage. Native timing for 1,048,576 raw
  draws is about 46 ms, including a checksum. A nested allocation factory needs
  an explicit type, with failing reproduction and two executable controls.
  Additional distributions and legacy randomness consolidation remain; this
  milestone does not complete the time/randomness family.
- Owned vector: [`alloc::vec`](stdlib-vec.md) provides explicit allocation and
  bounds errors, removed-value transfer, atomic self-extension, shallow clone,
  resizing, sorting and counted views. Four execution groups include 6,000
  modeled edits, generic payloads, zero-sized entries, allocation failures and
  checked-index panics. String, streams, CSV/JSON and three reporting/text
  programs use it. The old vector remains for the verified compiler, legacy
  consumers and the heap migration's separate compiler dependency.
- Owned deque: [`alloc::deque`](stdlib-deque.md) replaces the old std module and
  its unchanged-owner failure convention. It executes both-end edits, rotations,
  borrowed views/cursors, alias-safe extension, split and clone. A 6,000-command
  model, generic payloads, allocation denial and ten migrated programs pass on
  x86_64 Linux. Large FIFO workloads perform 262,144 pop/push pairs at 4,096 and
  65,536 entries with one allocation each and no further allocation attempts.
- Ordered map: [`alloc::tree_map`](stdlib-tree-map.md) executes generic lookup,
  replacement/removal, bounds, ranges, both-ended cursors, clone and linear
  construction from sorted entries. Eight test groups cover a 6,000-command
  reference model, allocation failures, generic payloads, 32,768-key adversarial
  insertion orders and a sorted word-count program. Building from 65,536 sorted
  entries uses 65,535 key comparisons and about 32 ms whole-program CPU time,
  versus 1,966,082 comparisons and 312 ms for repeated insertion. The old
  insertion-ordered linear map has since been removed with its consumers
  migrated. Ordered sets now share this tree engine.
- CLI and host arguments: [`ext::cli` and `std::args`](extended-cli.md) execute
  borrowed option parsing and owned raw-byte argument snapshots. Eight test
  groups cover schema errors, 96 generated command lines, allocation failures,
  32,768-argument lists and a streaming file-checksum application with injected
  I/O errors. Parsing makes no allocations after capture; two snapshot
  allocations suffice at both 4,096 and 32,768 arguments. Those original
  flat-parser/checksum receipts retain their source scope. The separately
  accepted [hierarchy and generated help](extended-cli-commands.md) now address
  routing and usage output through caller storage. Optional
  [response preprocessing](extended-cli-response.md) now has portable semantic,
  native provider/resource and current KV application receipts. Completion remains open.
  Logging executes as documented below.
- Configuration: [`ext::config`](extended-config.md) executes strict JSON object
  sources, bounded file loading, typed borrowed queries and explicit shallow
  overlays with source indices. The checksum application combines configuration
  files and CLI overrides. Eight groups cover generated layers, numeric limits,
  every observed allocation failure and host errors. JSON now also exposes
  borrowed text/key queries and exact i64/u64 conversion of decimal/exponent
  forms. [Typed settings](extended-settings.md) now provide JSON/TOML layers and
  explicit environment bindings. Configuration-specific validation and discovery
  policy remain separate.
- Formatting and logging: [`core::fmt`](stdlib-formatting.md) composes integers
  in bases 2–36, Text, scalars, booleans and custom Display implementations into
  caller-backed buffers with measurement and sticky append errors.
  [`ext::log`](extended-log.md) filters and prepares complete typed JSON records
  before any output. The checksum application combines both with configuration
  and CLI settings. Seven groups cover 746 integer reference cases, 67 quoted
  text round trips, record bounds, every observed application allocation/I/O
  failure and allocation-free batches of 8,192 records. Four existing checksum
  groups still pass. A combined generic log-and-write facade exposes a runtime
  compiler defect; it is outside production imports with a reproduction and
  controls. Preparing records and then calling write_all executes.
- Extended CSV: parsing, independent field copies and canonical encoding execute
  on x86_64 Linux, including generated tables, borrowed field views and allocation fault injection.
  See [extended-csv.md](extended-csv.md). Incremental decoding shares the same
  parser; [reusable row construction and bounded stream writing](extended-csv-write.md)
  now execute through the same canonical byte cursor. The
  [column rewrite application](extended-csv-rewrite.md) composes those pieces
  with explicit global input/output/work/call bounds and manual cleanup.
- Shared I/O: portable Read/Write traits, exact/all/copy operations, slice
  cursors, owned byte buffers and native descriptor adapters have execution
  coverage. CSV uses these streams. See [stdlib-streams.md](stdlib-streams.md).
- Extended JSON: iterative parsing/building/encoding, exact number text,
  queries and independent string copies execute on x86_64 Linux, including
  generated trees, limits and allocation fault injection. See
  [extended-json.md](extended-json.md).
- Integer text conversion: [decimal](stdlib-decimal.md) parsing, indexed digit
  access and checked buffer formatting execute for all ten native integer types,
  including i64/u64/isize/usize. Bounds, overflow and insufficient capacity have
  explicit errors. Text methods, owned String construction/appends and native
  output use these conversions; the window-report example now writes i64 sums
  directly. Reference cases and allocation/I/O faults pass on x86_64 Linux.
  With 4,096 samples and width 64, paired native application runtime falls from
  2,539 to 131 ms versus the previous two-word sum output.
- Hash map: [`alloc::hash_map`](stdlib-hash-collections.md) executes generic
  lookup, replacement/removal, reserve, shrink, clone and iteration, including
  collision models and allocation failures. String and all integer widths
  implement hashing. Production HashSet now shares this engine through its
  owner-state boundary; the earlier nested wrapper is retained separately as
  a compiler reproduction.
- Binary heap: [`alloc::binary_heap`](stdlib-binary-heap.md) executes min/max
  queues, linear bulk construction, root replacement, allocation-safe reserve,
  shrink, clone, aliased extension and sorted ownership transfer. Five test
  groups cover generic payloads, 12,000 modeled operations, zero-sized values,
  allocation failures and a top-scores program. For 65,536 records, bulk
  construction uses 131,040 comparisons and about 24 ms native runtime versus
  917,522 comparisons and 117 ms for repeated insertion, with one allocation
  in each path. This does not establish GPU user-program execution.
- CSV-to-JSON integration: the [report application](csv-report.md) validates
  schemas and integers, groups records, checks totals and emits JSON. Native
  tests cover generated records, all allocation failures and partial I/O.
  It now uses the hash map; paired measurements improve the 1,024-group case
  from about 694 ms to 307 ms. The report now uses incremental input and
  packed reusable record buffers.
- Borrowed text: [core::text::Text](stdlib-text.md) executes validation, checked
  subviews, comparison/search, scalar and split iteration, hashing and decimal
  parsing without copying. String and CSV expose borrowed views. The report
  copies each distinct group name once, and reads other fields directly. Paired
  native measurements show 232→175 ms for 4,096 records/64 groups and
  303→269 ms for 4,096 records/1,024 groups before the streaming migration.
- Streaming CSV: one decoder handles complete tables and chunked input,
  including split UTF-8/quotes/CRLF, explicit EOF, sticky errors, resource limits
  and owned record transfer. A syscall-traced 4,096-record run allocates nothing
  after warm-up. The grouping report now retains only current-record buffers
  and group data during input. Paired native runtime falls from 173 to 26 ms
  for 4,096 records/64 groups; peak live allocation request sizes fall from
  779 KB to 99 KB. See [extended-csv.md](extended-csv.md) and [csv-report.md](csv-report.md).
- Borrowed slices: [View and cursors](stdlib-slice-views.md) execute with checked
  logical bounds, overlapping copies, chunks/windows and iteration from either
  end. A 6,388-command model checks stateful behavior. The window-report example
  combines parsing and owned vectors with borrowed windows and exact statistics,
  including allocation and I/O failure coverage. Initial counts still require
  valid physical backing. Shared generic iteration now has separate execution
  evidence through the module below; the older reproductions remain historical.
- [Buffered I/O composition](stdlib-buffered.md) now has its own runtime
  admission: five compiled programs and eighteen native executions cover
  nested readers/writers, confirmed partial progress, every constructor
  allocation failure and actual EPIPE failures during copying and final flush.
  The fixed-capacity buffers require explicit cleanup and preserve their
  confirmed unread/pending ranges on errors; no automatic ownership is implied.
- [Shared iteration](stdlib-iterators.md) now executes through one fused
  protocol, slice and finite i32 range cursors, borrowed take/chain and bounded
  consumption. Seven compilation jobs produce five checked native executables
  and two intended bound rejections. Native models cover 6,602 cases, including
  copy/interleaving semantics and full-domain range skips without enumerating
  billions of items. A nested View-result layout failure remains captured;
  the library uses one direct metadata construction and checked validation path.
  The [range-statistics application](stdlib-range-stats.md) walks the real range
  and take implementations, with one compilation serving 41 native cases:
  full endpoints, million-item quotas, strict arguments and exact cleanup on
  allocation, signal-policy and output errors.
- [Collection, Text and bitset cursors](stdlib-collection-iterators.md) now
  implement that protocol. Three native executables check 408 collection model
  commands, allocation-free byte/scalar/bit views and shallow String ownership.
  Vec and Text byte factories retain their original native-stride views.
- [Mapping, pairing and checked enumeration](stdlib-iterator-adapters.md) now
  compose through the same protocol. Three checked native executables cover
  compound callback results, 1,008 call-order model commands, explicit shallow
  cleanup and an index-overflow trap; three intended rejections check exact
  item bounds. The [range-dot application](stdlib-range-dot.md) adds 67 native
  cases for real zip/take/map/enumerate composition, million-pair inputs,
  checked prefix arithmetic and allocation/output failures.
- [Canonical slice cursors](stdlib-cursor-integration.md) now share one forward
  protocol and backward state across checked factories, borrowed owners and
  fixed-capacity helpers. Two focused native gates include 126 independent
  chunk/window model commands; the migrated window-report program passes 30
  native cases. [Text splits](stdlib-text-split-iterators.md) add two native
  gates with 1,042 model records. [Heap iteration](stdlib-heap-iterators.md)
  adds two accepted native gates with 42 multiset/adapter records and explicit
  String-owner cleanup. No compiler or ABI changes were needed.
- [Selection, searches and folds](stdlib-iterator-selection.md) add five lazy
  adapters plus six consumers using exact typed callbacks. Independent native
  models check 960 selection/copy commands and 714 consumer commands. The
  [column-sum program](stdlib-column-sum.md) validates a selected text column
  and sums checked prefixes before publication. Its focused cases include
  input bounds, malformed values, allocation failures and actual EPIPE.
  A [shared assignment context repair](compiler-iterator-assignment-context.md)
  retains compound call results and preserves previously accepted type facts.
- [Fallible collection](stdlib-iterator-transfer.md) adds a typed sink protocol
  and bounded transfer into fixed vectors, owned vectors and deques. Errors
  retain the accepted prefix and return the rejected item for recovery. Native
  evidence covers 236 independent scenarios with 2,124 stateful actions, all
  eight observed Vec/deque growth-denial positions, compound items/errors and
  exact shallow cleanup. The [word sorter](stdlib-sort-words.md) adds 51 native
  cases, including all 12 observed allocation-failure positions. Further
  collection policies, owning cursor families and automatic destruction remain.
- [Map, set and heap collection](stdlib-iterator-collection-sinks.md) extends
  that protocol to five owned collection types. Unique-key rejection preserves
  old representatives and returns incoming items; heap collection preserves
  Min/Max order and multiplicity. Independent native models cover 640 scenarios
  and 5,760 bounded transfers; all 18 observed growth-denial positions recover.
  Typed String-owner checks, full-capacity duplicates and six exact trait-bound
  rejections pass. The [identifier index](stdlib-index-words.md) adds 65 native
  cases with original word positions, duplicate errors and exact cleanup.
  Further ownership-aware collection policies, other owning cursor families
  and automatic destruction remain work.
- [Owning Vec and Deque cursors](stdlib-owning-iterators.md) now transfer
  storage and item cleanup authority, share front/back traversal, reject an
  early finish without mutation and recover the remainder with its original
  allocation. Independent models cover 352 scenarios and 1,056 recovery rounds.
  Typed and helper-only callers check explicit nested destruction, including
  zero-sized values; every observed destination-growth and source-reuse failure
  recovers. The [streaming word deduplicator](stdlib-unique-words.md) reuses its
  batch allocation across 126 native cases, including 79 allocation denials.
  A reduced finish-result replay dependency remains recorded; helpers use
  canonical empty-owner recovery and destruction. No compiler source changed.
- [Owning hash map/set](stdlib-owning-hash.md),
  [ordered map/set](stdlib-owning-tree.md) and [heap](stdlib-owning-heap.md)
  cursors now transfer cleanup authority and recover their canonical remaining
  collection in O(1). Exhaustion retains backing until explicit finish or
  cleanup; deep helpers release only remaining owners with minimal Destroy
  bounds. Independent native models cover 5,368 hash cases, 192 paired ordered
  steps and 32 snapshots per engine, and 144 priority cases. Address/length
  ledgers check actual owner release. Tree and heap pulls use their existing
  O(log n) removal engines. The word deduplicator now publishes through the
  TreeSet owning cursor and still passes its 126 native cases. Explicit types
  avoid a [reproduced hash insertion context dependency](library-context-inference-dependencies.md);
  the original expression remains a compiler dependency.
- [Streaming runtime formatting](stdlib-format-write.md) now writes through
  generic byte writers using bounded scratch and the existing format grammar.
  Complete preflight precedes output; failures preserve confirmed progress and
  direct call budgets bound Interrupted retries. Native byte/progress models
  cover 960 commands, with independent preflight/error and nested-buffer gates.
  The [CSV report](stdlib-format-report.md) passes 81 native cases, including
  23 representative allocation denials and exact output limits.
- [Iterator lookahead and reductions](stdlib-iterator-lookahead.md) now execute
  with an explicit recoverable cache, nested optional items, relative/MAX
  position search and first-minimum/last-maximum tie policies. Four library
  groups pass in the initial 15.67 s run, including 1,280 cache schedules,
  320 extrema models, 180 position models, exact owner releases and a checked
  overflow-order witness. The [column extrema program](stdlib-column-extrema.md)
  passes its separate 24-case group in 6.51 s after correcting two strace
  harness mistakes; all four reached allocation failures and real output
  injections are checked. No production source changed during those retries.
- Next foundation work: further iterator adapters and consumers, additional
  streaming interfaces, protected Vec/heap migration and numeric/manual
  ownership consolidation. Owned hash/tree sets now execute, and silent-failure
  legacy map/set owners have been removed with their consumers migrated.
  Completing the integration application does not complete the first phase.
- [Nested Vec memory owners](stdlib-nested-clone.md) now use explicit generic
  TryClone/Destroy implementations and the existing clone engine at each level.
  Six native executables cover three levels, aliases, empty/ZST values, owner
  transfer, ten allocation-failure positions and eight owned-error index/stage
  cases. Four source-local rejections cover missing imports/prerequisites and
  contradictory error types. Ordinary shallow collection methods retain their
  policy; other owned collections and automatic lifetime safety remain work.
- Text composition: [join, repeat and word splitting](stdlib-text-composition.md)
  execute with atomic, alias-safe appends, checked sizes and one-allocation
  construction. An executable whitespace normalizer combines borrowed words,
  owned strings, vectors, streams and decimal argument parsing. Generated models,
  capacity overflow and every observed allocation failure are covered.
  For 65,536 parts, paired native runtime is 75.73 ms for join versus 116.36 ms
  for repeated appends; whole-program allocation calls fall from 19 to 2.
  The earlier generic buffered-stream routing failure remains preserved in the
  compiler dependency list. Implementation-application transport and buffered
  adapters now pass separate native gates. Shared slice/range iteration has
  since passed its own admission, followed by collection, Text scalar/byte and
  bitset integration. Split cursors, selection, folds and bounded collection
  have since advanced as recorded above; further adapters and consumers remain.
- Owned files: [File and Path](stdlib-files.md) execute read/create/append,
  generic stream operations, explicit close and ownership transfer on x86_64
  Linux. Tests check binary and non-UTF-8 data, descriptor reuse, path bounds,
  all acquisition/transfer/close failure paths and absence of heap allocation.
  The file-concatenation application closes inputs on errors and preserves bytes.
  Buffered I/O, owned paths and filesystem extensions have since advanced as
  recorded above; automatic owner destruction and other target bindings remain.
- The older [execution audit](stdlib-foundation.md) remains historical evidence;
  its top-level checkpoints do not establish this branch's current behavior.
