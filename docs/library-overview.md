# Standard and extended library overview

The full library goal remains open. The current
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
[migrated CLI](extended-kv.md#current-application-receipts) now have finite native
acceptance on the profile below. The accepted TempFile prerequisite and server
evidence retain their checkpoint scope. The
[remaining-work audit](library-roadmap.md#remaining-work-beyond-atomic-files)
keeps the broader standard and extended library work visible.

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

The migrated `kv_tool` passes round trips 33 and publication 31: **64 process
invocations across two groups**, including 13 reached source-allocation failures
and 15 I/O controls in the publication group. Its new arities omit SCRATCH and
anchor mutation load/publication to one parent/leaf, with NoReplace init and
Replace updates. Published-but-unsynced, unconfirmed visibility and retained
cleanup remain explicit outcomes, including when stderr delivery fails.
The current receipts are `kv-tool-atomic-syntax-retry-compile.log`,
`kv-tool-atomic-roundtrips-first.log` and `kv-tool-atomic-publication-first.log`.
The first compile failure was unsupported application match-arm syntax; the
correction required no compiler change. Eleven CPU binding controls and two
Rust driver `--no-run` admissions remain separate from native oracle execution;
no Rust libtest execution is claimed. Portable Store/snapshot tests retain
their prior scope, and earlier caller-scratch CLI receipts remain historical.

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
passes its bounded writer and final check for the frozen archive, AtomicFile/KV,
TempFile/FileOps and server surfaces: 250 pages, 249 modules and 8,197 public
declaration markers. Source inventory evidence does not establish runtime
support or library completion.

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

[Regex splitting and replacement](extended-regex-text.md) reuse the existing
matcher and capture cursor, with borrowed fields, owned literal/template
output and explicit search/output bounds. Six native groups cover independent
reference cases, Unicode and empty-match tables, every reached allocation
failure and a binary stdin/stdout rewrite program. Search work is a
conservative reservation of per-search VM allowances, not a total CPU or I/O
budget.

[Reusable lexical scanning](extended-lexer.md) selects the longest anchored
regex span at each position, with declaration-order ties, borrowed UTF-8
tokens and explicit progress, call and work limits. It shares the canonical
regex engine and validates each input once. Five native groups pass through
separate receipts, including 576 independent model cases, 63 edge tables and
all 120 allocation failures reached by the focused fixtures. Probes still
allocate matcher scratch, and competing patterns can rescan input; this is
not an allocation-free or whole-input linear-time claim.
The [CSV-rules lexer program](extended-lex-scan.md) emits staged token spans or
per-kind counts through bounded native I/O. Its five groups pass, including
124 grammar inputs in both modes, all 60 allocation-failure positions across
the two output modes, injected I/O failures and a measured 4,096-token run.

The [CSV report application](csv-report.md) combines streams, UTF-8 text,
checked decimal parsing, generic collections, CSV and JSON to validate and
group records with executable failure coverage.
