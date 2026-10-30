# Library compiler and runtime dependencies

This list records boundaries encountered while building the libraries. A row
does not mean unrelated library work is blocked.

The [TOML streaming serializer](extended-toml-streaming.md) uses existing
Document links, byte/scalar operations, Read and the owned collector. Its
[normalizer](extended-toml-normalize.md) uses the existing Copier with fixed
scratch. Borrowed sizing/emission and direct caller-buffer output need no
output allocation. Stable immutable Document backing, cursor/destination
separation and explicit cleanup remain manual obligations. All five library
groups and four normalizer groups/64 native cases pass on Linux x86_64 CPU
output from the GPU compiler; no other-host, device, automatic-lifetime or
proof claim follows. The 2W serializer budget is distinct from parser budgets,
allocator work and transport-call quotas. A fixture's chained generic Read
result rejected with LNC0027; adding a Result import and an explicitly typed
intermediate admits its assertions. Because both changed, the
[inference/import cause remains unresolved](../tests/fixtures/extended_library/toml_streaming/README.md#initial-contract-compile-failure).
There was no production or compiler repair for that fixture failure.

The [literal text replacement increment](stdlib-text-replacement.md) uses
existing Text search, UTF-8 boundaries, Iterator, Pair and Vec allocation. The
borrowed cursor adds no allocator or host dependency; owned results use one
checked exact reservation. Source/needle/replacement overlap is allowed, with
immutable valid backing retained through both passes. All five library groups
and four [stdin/stdout consumer](stdlib-literal-rewrite.md) groups/94 cases pass,
including reached allocation failures and exact cleanup. No compiler repair
was needed. Evidence is Linux x86_64 CPU output from the GPU compiler. Enforced
lifetimes/destruction, other hosts, user-device execution and formal proof
remain separate; this increment does not resolve older compiler reductions.

The [resumable encoder](extended-streaming-deflate.md) uses existing integer,
checksum and View contracts with fixed caller storage; its
[file consumer](extended-compress-file.md) composes existing File/AtomicFile
services. No host codec or new compiler capability is required by the design.
All five library groups and five application groups/99 native cases pass on
Linux x86_64 CPU output. No compiler repair was needed.
Workspace/encoder/I/O disjointness, stable
backing and the call-local final-input promise remain manual obligations.
Other hosts, device execution, enforced cleanup and formal proof remain separate.

The [vector-transfer increment](stdlib-vec-transfer.md) uses the existing
`alloc::vec` allocator and capacity-dependent typed storage. Four direct
methods add no trait or host-service dependency. Exclusive owner descriptors,
independent append backing, stable borrowed resources and exactly-once nested
cleanup remain manual obligations. All eight library groups pass on Linux
x86_64 CPU output from the GPU compiler, as do all four row-moving application
groups/133 cases. Five selected existing groups and standalone examples pass
separately. No compiler repair was needed: initial fixture/CLI syntax or typing
errors and an unsupported test-observer pointer cast were corrected locally.
This increment does not migrate protected `std::vec`, alter layouts or supply
enforced ownership, other-host/device support or formal proofs. The mini compiler and extractor
use `List`; protected heap backing and active formal vector contracts remain
separate migration boundaries.

The [image-resize increment](extended-image-resize.md) uses existing image
views, integer arithmetic and alloc storage. Nearest, Bilinear and Area have
explicit sampling and alpha contracts; tiled exact Area workspace is bounded
independently of full raster dimensions. Source backing remains immutable and
alive through the call, and one active result owner retains manual cleanup
authority. All seven library groups and four PNG-tool groups/102 cases pass,
including reached output/scratch failures, bounded scale shapes and exact
models. Selected existing regressions and standalone build/examples pass
separately. No new compiler dependency was encountered, and the increment
requires no compiler/ABI repair, new host service or native image library.
Evidence is Linux x86_64 CPU output from the GPU compiler. Other hosts,
user-device execution, automatic lifetime enforcement and formal proofs remain
separate. Existing PNG compiler reductions below keep their original scope
and do not establish a resize blocker.

The [ordered form-byte increment](extended-form.md) belongs in the extended
format layer. Borrowed parsing, component conversion and serialization use only
existing core View/Iterator/Read contracts; owned forms and output use existing
alloc Vec/String/collector facilities. URI query selection and HTTP transport
remain separate, and strict ext::percent semantics are unchanged. The byte
profile precedes WHATWG's UTF-8 replacement step; checked Text conversion is
explicit. Append may relocate storage on error, so aliases and cleanup remain
manual obligations even when logical contents are preserved. All nine library
gates and four application groups/86 native cases pass on Linux x86_64 CPU
output from the GPU compiler. Other hosts, device programs, enforced lifetimes
and proofs remain separate. The initial independent-model fixture and its
[reduced original](../tests/fixtures/extended_form_model/compiler_dependency/README.md)
reject with LNC0047 in imported nested error matching before native execution.
An explicitly typed helper control executes, and the same factorization admits
the complete unchanged 607-case corpus. The narrow compiler dependency remains.
The helper workaround changes only fixture reporting; it includes no compiler
or ABI repair. The evidence establishes no general nested-match limitation.

The [scoped map-value increment](stdlib-map-updates.md) reuses the existing
HashMap/TreeMap lookup and storage engines plus Mapper and Pair. Map-owned
lookup/reinstall work adds no allocation or host binding; user key operations
and mapper callbacks retain their own costs/effects and have no wall-time bound.
A separate Result error still reinstalls the returned V.
Stored key identity is preserved, and callback access through map aliases is
forbidden. Lifetimes, exclusive value authority and nested cleanup remain
manual; no panic recovery or compiler-enforced ownership is supplied. All seven
new library gates pass on Linux x86_64 CPU output, including the independent
model and reached callback-allocation failures. Four word-concordance groups/
103 native cases, three selected old regressions and standalone build/examples
also pass. Other hosts, GPU device execution and formal proofs remain separate. No compiler or ABI repair is part of this
increment. Existing generic shorthand reductions below retain their scope.

The [stream-encoding increment](library-stream-encoding-plan.md) composes the
existing Read/Write contracts through a [resumable copier](stdlib-resumable-copy.md)
and [borrowed JSON reader](extended-json-streaming.md). Portable transfer and
borrowed encoding add no allocation or host service; providers retain their
own effects. Owned encode uses the existing bounded collector and allocator.
Endpoint/scratch exclusivity and stable immutable Document backing remain
manual obligations. All ten new library gates and four normalizer groups/100
native cases pass on the initial Linux x86_64 CPU profile, with three selected
old regressions separate. No device, proof or enforced-lifetime claim follows.
The first core admission failed before runtime from an ordinary unqualified
Eof ambiguity; explicit variant qualification is a source correction, not a
compiler dependency. The older imported copy-helper reduction below retains
its own source scope and is not resolved merely by sharing the new engine.

The [generic slice-segmentation increment](stdlib-slice-segmentation.md) uses
existing View, Iterator and Mapper contracts. Factory metadata validation is
independent of predicate capability; Mapper bounds are enforced by iteration.
Library traversal adds no allocator/host dependency, while callbacks keep their
own effects and costs. Physical backing, stable borrowed predicate/context and
manual cleanup remain caller obligations. All eight new library gates pass,
including a 5,496-case independent model and exact owner/resource checks, as do
four record-summary groups/94 native cases on Linux x86_64 CPU output. No reverse, ExactSize,
device-execution, enforced lifetime or proof claim is added.
The initial model fixture hit `LNC0027` when one receiver implemented both
unary and Pair Mapper applications, before native execution. The
[existing same-receiver reduction](../tests/fixtures/stdlib_foundation/slice_ordering_dependency/README.md)
already pairs that diagnostic shape with an executing split-receiver control.
The accepted model uses distinct borrowed wrapper receivers sharing the same
policy context, without specializing these public generic APIs or changing the
compiler. The nested resource retry corrected only a test-ledger size
assumption to the existing 24-byte Vec layout; production sources were unchanged.

The [bidirectional Text increment](stdlib-bidirectional-text.md) extends
existing Iterator/DoubleEndedIterator and UTF-8 contracts. Forward Text scalar
and word cursors already use the shared iterator protocol. New borrowed line
and backward traversal require no allocator or host binding. All seven new
library gates and all four line-summary groups/102 native cases pass. The
canonical Unicode-report stdin regression and standalone build/examples also
pass. The chained generic Option expression below remains a compiler dependency
with an executing typed-match control; no compiler or ABI repair was made.
Caller-proven Text validity, immutable physical backing and lifetimes remain
mandatory; this increment supplies no ExactSize or
automatic ownership guarantee. Generic slice segmentation now has the separate
current increment above, not an established compiler blocker. Native Linux x86_64 CPU
output is the initial target; other hosts, device execution and proofs remain
separate.

The [resumable decompression increment](extended-streaming-inflate.md) uses
existing View, allocation and Linux file/AtomicFile contracts. Borrowed decoding
adds no host service or native codec dependency; owned decoding adds explicit
fixed workspace allocation before later format validation. System zlib is a
test oracle only. All seven new library gates pass on native Linux x86_64 CPU
output from the GPU compiler, as do all seven atomic-file application groups
with 98 native cases.
Other targets, user-program GPU execution, language-enforced backing lifetimes
and formal verification remain separate. No compiler or ABI repair is part of
this increment.

The native Linux boundary now includes an explicit six-word
[syscall binding](stdlib-linux.md), added in `3fa72ac2`. Lanius implementations
of [socket ownership and TCP/UDP](stdlib-sockets.md),
[file options/metadata/seek/sync/duplication](stdlib-file-operations.md),
[directory iteration/walking](stdlib-directory.md) and
[Default/Ignore signal dispositions](stdlib-signals.md) execute over that boundary.
The [staged HTTP/1 server and local service](extended-http-server.md), accepted
at `493d4e87`, compose these operations with explicit deadlines, quotas and
manual connection ownership.
This does not bind the older `std::net` service declarations or supply threads
or callbacks. Client TLS with peer verification now uses a separate OpenSSL binding. The
[native integration prerequisite proposal](library-native-integration-prerequisites.md)
separates checked entries, concurrent memory ordering and static/dynamic foreign
ABI support; thread local storage is conditional on the chosen
worker/foreign-library profile. Cryptographic operations and authenticated TLS
require an established external library through a checked native binding;
there is no in-house crypto or TLS stack. The
[native C profile](library-native-c.md), [OpenSSL digests](extended-openssl-digest.md)
and [client TLS with peer verification](extended-openssl-tls.md) now execute. The TLS gates
cover 34 cases across four groups for explicit trust/identity, binary transfers,
authenticated closure/truncation and stable retries. Sessions borrow connected
nonblocking descriptors; caller deadlines, SIGPIPE policy and manual cleanup
remain explicit. The [TLS stream/HTTPS application](extended-https-fetch.md)
also executes: 62 cases across four groups cover stream progress,
verification/HTTP failures, limits and binary framing on Linux x86_64. It uses
numeric endpoints, explicit trust/identity, deadlines and manual owner cleanup.
[Server TLS](extended-openssl-tls-server.md) also passes six native groups and
53 cases; mandatory client trust/identity rejection still passes after the
shared session gained an explicit role. That initial server profile does not
authenticate clients. [Mutual TLS](extended-openssl-mutual-tls.md) now provides required
client-chain verification through its separately documented native receipts.
Broader certificate and application authorization policies remain work.
C `f32`/`f64` calls also pass
exact IEEE transport, independent SSE/GPR banks, mixed 32-parameter stack/alignment and imported generic replay
gates. An owned [SQLite adapter](extended-sqlite.md) and its
[persistent binary key/value application](extended-sqlite-kv.md) execute on
Linux x86_64/glibc with system SQLite. Typed values, transaction models, real
persistence/locking, native errors and
[staging allocation failures](extended-sqlite-allocation.md) pass focused gates;
their guides record the exact coverage and measured bulk workload. Native
entry/package builds now spool original/replay section payloads and execute a
6 MiB source pack above the resident aggregate threshold. Source snapshots and
global metadata still grow; explicit descriptor CLI modes remain unsupported.
Callbacks, variadics, aggregates and foreign thread entry remain separate compiler contracts. The
[API conventions](library-api-conventions.md#cryptography-and-tls-boundary)
record this boundary.
The [host prerequisite audit](library-host-prerequisites.md) distinguishes the
historical missing operations from the remaining code-entry/memory-model work.
Current [memory/view contracts](stdlib-memory.md) and
[process-context contracts](stdlib-process-context.md) document raw backing,
startup bytes, checked copies and manual owner lifetimes over these interfaces.
[Opt-in deep HashMap cloning](stdlib-clone-hash-map.md) also passes all four
focused native groups, including independent nested owners, typed rollback,
changed-key rejection and every reached allocation failure.
[Recursive deque cloning](stdlib-clone-deque.md) also passes four native groups,
including ring-order models, nested allocation failures and owned-error cleanup.
[Opt-in deep heap cloning](stdlib-clone-binary-heap.md) also passes all five
native groups, including priority models and nested/owned-error failure cleanup.
[Opt-in deep ordered-map cloning](stdlib-clone-tree-map.md) also passes all
five native groups after the two general compiler corrections recorded below.
Its contract group passes in 9.83 seconds and the other four active groups in
13.47 seconds; the manual diagnostic probe is ignored. These receipts do not
revalidate the unrelated generic replay failures in this list.
[Opt-in deep HashSet](stdlib-clone-hash-set.md) and
[TreeSet](stdlib-clone-tree-set.md) cloning also execute through the existing
shared map engines. Their three and five focused native groups pass with
typed errors, independent owners, bounded models and allocation-failure cleanup.
These additions require no compiler or ABI changes.

The 2026-10-23 bitset/calendar integration, finite decimal, statistics and matrix
milestone executes over the existing interfaces without additional compiler or
host bindings. Its numerical limits and ownership preconditions are documented
in the module guides linked from the [roadmap](library-roadmap.md). Physical
slice counts and manual ownership below still apply. Its earlier socket and
directory prerequisites are now supplied by the Linux boundary; threads and
the listed generic compositions remain dependencies for other library work.

The subsequent formatting/parsing milestone also executes over existing
interfaces. Inline containers use borrowed free functions where symbolic const
method lookup fails. Typed owned formatting executes; a general owned Display
helper remains outside production because its minimal consumer fails despite
larger passing contexts. The rows below preserve those distinctions.

The native integer, source development workflow, geometry, media, terminal and
HTTP wire additions also use existing language/host interfaces. Native-width
controls formerly cited as blockers now execute; the new numeric guide records
independent arithmetic/conversion and trap evidence. PNG header and earlier
benchmark source shapes have preserved failure/control snapshots below; their
current borrowed/factored implementations execute. These observations do not
establish general aggregate or callback failures. Thread and database integration
remain outside these portable implementations; current native filesystem and
socket support is described above.

The next numeric, protocol, time-zone, storage and signal additions also execute
over existing interfaces. Generic owned sets now use one shared map engine
through a nongeneric owner-state boundary. This removes the library blocker;
it does not repair the earlier nested generic receiver shape. The
[foundation admission probes](../tests/fixtures/stdlib_compiler_state/foundation_admission/README.md)
preserve exact base/compiler hashes, the successful state-factoring control and
historical static-iterator/stream-forwarding failures. The selected imported
and nested Read/Write contract is now
[accepted](compiler-implementation-applications.md), with separate buffered
and [Take/Chain](stdlib-io-adapters.md) runtime receipts. Those results do not
revalidate the original static-iterator witness or unrelated chained-result
expressions below. Selective source distribution uses the compiler's existing
package resolver.

| Dependency | Evidence | Affected APIs | Status |
| --- | --- | --- | --- |
| Imported nested form-error payload match | [Minimal original, executing typed-helper control and complete-source reconstruction](../tests/fixtures/extended_form_model/compiler_dependency/README.md); `target/stdlib-work/form-nested-{original,helper-build,helper-runtime}.log` | Test reporting extracts a u64 Capacity payload from `ext::form_owned::Error::Format(ext::form::Error)` using nested matches | The complete initial producer rejects LNC0047 before execution (0/1 in 4.62s, build 1.83s). The minimal original also rejects at 7:77 with exit 1. Moving only the inner match into an explicitly typed helper compiles and executes all six assertions with exit 0 and empty output. The revised full model passes 607 cases in 9.02s (build 0.22s), with its corpus/oracle/driver unchanged. This is a scoped compiler-admission dependency, distinct from the older nested Result/LNC0005 source; no production runtime failure, compiler repair or general root cause is claimed. |
| Chained generic Iterator result followed by an Option query | [Reduced chained expression and executing typed-match control](../tests/fixtures/stdlib_compiler_state/text_option_chain/README.md); `target/stdlib-work/text-option-chain-dependency.log` | `source.next().is_none()` inside a helper bounded by canonical `Iterator<T>` | The typed `Option<T>` local/direct-match control executes with strict ELF/jump checks and a complete no-host-effects trace. The corresponding chained expression rejects with LNC0027 at line 7. Both sources import the same modules and use the same empty slice-cursor instantiation. The explicitly run ignored positive-expected test therefore reports 0 passed / 1 failed in 4.79s, after a separate 1.69s Rust build; it is not an accepted behavior gate. Original Text fixtures also failed at next/next_back chains; typed helpers preserve their pulls and all four ordinary direct groups now pass. No compiler/ABI or production Text repair was made, and no general Option/iterator failure or compiler root cause is established. |
| Enum payload projections in a complete imported Seek method | [Import-only entry, captured module variants and executable controls](../tests/fixtures/stdlib_foundation/buffered_seek/README.md) | The original inline Start/Current payload matches in the borrowed buffered Reader method; the current public generic Seek implementation executes | After correcting unsupported block-arm syntax, the captured complete scalar-match source reports LNC0005 at its wildcard fallback. Renaming payload binders or using typed zero locals still rejects. Standalone literal/typed fallbacks and local/imported nested-bound controls all execute, so no general wildcard, literal or generic-bound restriction is established. Factoring only two private enum projections into ordinary exhaustive-match helpers admits the actual module; all three buffered behavior tests pass in 9.95s and the real reverse-records application passes four tests/86 cases in 8.00s. Generic bounds, query/arithmetic/fault/flush contracts and test assertions are retained. The original forms and exact reconstruction patches remain compiler follow-up evidence; no compiler repair or proven internal cause is claimed. The initial unsupported block-arm form produced a misleading LNC0008 Iterator label, recorded separately from the later projection failure. |
| Name resolution in a native response-provider test composition | [Two failed complete sources, successful scalar controls and active fixture](../tests/fixtures/stdlib_compiler_state/response_none_match/README.md) | An unnecessary second extraction of the same imported `Failure<files::Error>.cause` in one test consumer; public response APIs and the KV application execute | Both preserved full sources fail with LNC0005 at the wildcard arm's visible `None()` item or typed `absent` local. Both smaller Option<i32> controls compile and execute, so no general None/wildcard restriction is established. A fixture rewrite consolidates the duplicate matches into one Provider-arm report helper, preserves the diagnostic fields and runtime assertions, and passes 39 direct native file-provider cases. This broader rewrite does not isolate the responsible expression or compiler pass. Production library/compiler code is unchanged; further reduction remains open. |
| Nested Result/local-error payload patterns during target generation | [Minimal pair, full consumer and reverse patch](../tests/fixtures/stdlib_compiler_state/cli_help_nested_error/README.md) | Two help-test assertions matching `Err(Error::OutputTooSmall(required))` and `Err(Error::UnknownCommandId(id))`; library APIs themselves execute | The CLI/help consumer and a standalone source importing only core Result fail with generic LNC0057 before producing an ELF. Changing only the two assertions to extract a typed Error before its inner match compiles and executes both exact payload checks. The standalone error enum is local, with no CLI implementation, routing, metadata or host services. Compiler CLI is `e8ad0014...`; the responsible internal pass is unestablished. Production CLI/help implementations are unchanged. The failed source, minimal control and exact reconstruction patch are retained; no compiler repair or general nested-pattern restriction is claimed. |
| Record arguments at a zero-sized nominal return boundary | [Standalone reproduction and scalar-return control](../tests/fixtures/stdlib_compiler_state/replacement_zst_return/README.md) | The test-only `(Progress, Unit, Unit) -> Unit` helper used to inspect a replacement failure; other call shapes require separate evidence | Both import-free, non-generic sources compile with CLI `e8ad0014...`. The Unit-return form traps at its `2/1` record-field assertions; changing only the return to u64 preserves those assertions and exits zero. Earlier diagnostic calls show corrupted argument fields. Direct public ReplacementFailure construction/projection, Result enclosure and a generic Result-returning constructor all execute with the original Unit item/error types. The production replacement helper is unchanged; its complete zero-sized runtime fixture passes when it projects the failure locally instead of adding the unnecessary Unit-return call. The minimal call-boundary dependency remains unrepaired, with no compiler/IR/ABI change or general zero-sized layout failure claimed. |
| Comparison/cast guard parsed as a generic application | [Ten-line standalone reproduction and executable local-widening control](../tests/fixtures/stdlib_compiler_state/filesystem_imports/README.md) | The original `read_link_at_into` returned-count guard and any importing module | The import-free condition `received<0 \|\| received>(requested as i64)` fails before native emission with parser code 4/detail 3 and LNC0016 at the logical-or token. In the complete imported module the host fallback instead labels an unrelated existing Iterator bound; that diagnostic does not establish a generic-bound limitation. Widening the i32 request into an i64 local before the guard preserves comparison/error/copy behavior and admits the complete FileOps module. The small control compiles and exits zero. Production uses that independently reviewed equivalent expression; the ambiguous source form remains a compiler dependency, with no compiler repair claimed. |
| Generic nested Option payload extracted by `?` | [Scalar and multiword minimal pairs, commands and hashes](../tests/fixtures/stdlib_compiler_state/try_generic_flatten/README.md) | Rewriting generic `Option.flatten` from an explicit match to `return value?` | Reproduced after rebasing onto `origin/lang` `0d2e4a07`. All four minimal sources compile; both try forms receive SIGSEGV and both match controls exit 0 with the same payload/absence checks. The full existing Option/Result fixture also fails with the rewrite and passes with only the original option module restored. Production flatten retains its match. The separately migrated decimal/path/arithmetic/file APIs have focused native receipts; no compiler IR, ABI or proof repair is claimed. |
| Question-mark propagation in the complete regex module | [Versioned module patch, unused-import entry and six passing small controls](../tests/fixtures/stdlib_compiler_state/regex_workspace_admission/README.md) | Ten proposed propagation expressions in the reusable regex implementation | The original module fails LNC0057 with SSA-dominance reason 17 even when its import is unused. Replacing all ten expressions with equivalent explicit checks admits the module; independently reviewed APIs, VM behavior, error order and ownership are unchanged. Every small control passes, and subset replacements still fail, so neither a single causal expression nor a general aggregate/propagation restriction is established. Production uses the accepted explicit checks. The versioned patch reconstructs the exact failed module in a temporary source root; no compiler repair is included. |
| Resolved: a defined empty enum was treated as missing layout | [Empty-enum contract and reductions](compiler-empty-enum-layout.md); [scalar and structural clone gate](stdlib-clone-values.md) | True empty `Infallible` errors, scalar cloning and nested Option/Result/Pair/Vec clone results | Three GPU producers now preserve the existing one-word enum discriminant for an exact checked zero-variant enum. Local source-token lookup, complete retained payloads or an admitted recipe establish completeness; unknown metadata still rejects. All six paired reductions, explicit eight-byte size assertions, five clone groups, four inhabited structural controls and the neighboring zero-sized regression pass. Existing materializer/recipe rejection and recovery tests also pass. The compact materializer remains below its enforced instruction budget. No fake variant, call-site width fallback, host layout computation, IR/ABI change or proof edit was introduced. This closes these reproduced failures, not the unrelated entries below. |
| Resolved: public nominal replay lacked its local layout declaration | [TreeMap clone execution and reductions](stdlib-clone-tree-map.md); `tree-clone-layout-dump-run.log`, `clone-tree-map-contracts-fixed.log`, `clone-tree-map-failures-current.log` under `target/stdlib-work/` | Native layout derivation when a portable public nominal returns to its defining source unit during generic replay | The original direct String clone failed LNC0047 detail 6. Its `Vec<Entry<String,String>>` replay root lacked both a width witness and a source-local token, while Entry already had a complete six-word layout. Explicit local annotations did not repair it. The native-width producer function `local_nominal_owner` now resolves an absent raw token through the completed canonical ID, whose existing exact unit/declaration identity mapping supplies the local token. Existing token/HIR-kind checks and checked field/variant layout derivation remain authoritative; no Vec-specific width, host layout calculation or cross-source raw token transport was added. The direct probe and all five production groups now execute. Other missing-layout reproductions remain unvalidated. |
| Resolved: constructor field count widened a checked zero-sized payload | [TreeMap clone zero-sized contract](../tests/fixtures/stdlib_foundation/clone_tree_map/zero_sized.lani); the same two accepted execution logs above | Native copies of aggregate constructors whose zero-sized fields make field count exceed machine-word width | `Node<Unit,Unit>` has six fields but occupies five checked words because its Entry payload is empty. The x86 `x86_aggregate_value_word_count` helper incorrectly took the maximum of that width and the six syntactic fields. A six-qword indexed copy then started eight bytes before its 40-byte allocation; retained native code and GDB confirmed the mismatch. The helper now preserves the checked value width, including zero. Constructor storage, copies and native size agree without an IR, ABI or artifact-version change. The previously crashing unchanged zero-sized fixture passes within the 9.83-second contract group. The independent `compiler_generic_types_execution::zero_sized_compositions_preserve_neighbors_and_array_bounds` regression also passes in 4.11 seconds (`target/stdlib-work/generic-zero-size-constructor-regression.log`), covering generic empty members/arrays, neighboring values, effects, nominal distinctions and four bounds traps. |
| Resolved: array repetition/copy target capacity | [Independent nonzero-repeat fixture](../tests/fixtures/stdlib_foundation/dependencies/nonzero_array_repeat_target_capacity.lani) and [focused compiler driver](../tests/compiler_array_repeat_context_execution.rs) | Native lowering of fixed-array repetition and local copies | The minimal fixture originally failed LNC0057 with required target capacity 49,273 versus 36,864 available (flags `0x2`). Host orchestration now grows from measured demand with bounded monotonic full-graph retries; the large fixture and a subsequent tiny program pass using the same compiler. Shaders, IR records/opcodes, ABI and proofs are unchanged. |
| Imported owning-cursor finish result in a generic cleanup helper | [Minimal caller, original helper and caller-projection control](../tests/fixtures/stdlib_compiler_state/owning_string_application/README.md) | Original `destroy_vec_iter<String>` calling `try_finish().is_none()` without a caller finish-result projection | Reproduced on 2026-10-24 at `f867a596`: the 18-line caller fails LNC0047 detail 6. A caller that explicitly projects `IntoIterError::Remaining` compiles; a typed Option local inside the helper still fails. Production helpers drain, recover an empty typed collection and release it through its canonical owner. Helper-only Vec/Deque String callers and the 126-case streaming application execute. This is a retained compiler dependency, with no compiler or ABI repair claimed. |
| Raw native arguments lost high `usize` bits | [Assembly/table oracle, full-width probes and bounded native controls](stdlib-raw-host-width.md); `raw_host_width_admission.lani` | Allocation sizes, raw stdio counts, startup-copy bounds, environment key identity and clock/cwd capacities | Repaired in the native thunks. Six focused tests verify full-word transport with injected errors, finite guarded copies, supported/rejected alignment and owner preservation. Large successful backing allocation is not claimed; initial allocation does not use MAP_32BIT. Declared i32 indices/results and wrapper error policies retain their domains. |
| Runtime emission stopped at 2,048 bytes | [Runtime tail contract and per-ELF byte oracle](stdlib-raw-host-width.md); `x86_runtime_dispatch_tests.rs` | Relocated assertion and Linux syscall bridge after runtime growth to 2,095 bytes | Repaired with a private GPU dispatch-argument producer over the final checked runtime length. Fresh native ELFs match all 2,095 literal bytes and execute both formerly missing tail entries; the retained old ELF fails at byte 2,048. Invalid status/range resets indirect work rather than retaining an earlier dispatch. No public IR, ABI record or proof change. |
| Formatter split a negative exponent | [Retained input, corrupted output, diagnostic and current lexical closeout](../tests/fixtures/stdlib_compiler_state/format_negative_exponent/README.md) | Formatting source containing signed decimal exponents | Repaired by retaining the complete decimal mantissa/exponent lexeme. Seventeen formatter and seventeen CLI CPU checks cover independent token-kind/spelling preservation, adjacent subtraction/radix/range controls, comments/strings, idempotence and file/stdin checks. The original native input already executes; no GPU rerun was needed. `fmt --check` remains a canonical-format comparison, not syntax validation or repair of previously corrupted text. |
| Required trait-bound result identity and caller scope | [Repair contract, focused evidence and historical admission notes](compiler-trait-result-contract.md), recorded at `f96b73c1` | Required members returning symbolic/nested compound results such as `Result<T,E>` | Resolved by `972f0564`: receiving annotations cannot replace the selected bound's arguments, and accepted compound results retain caller scope through projection. Seven serial compilation jobs include three native executions, incompatible-result rejections and ordinary-call/compiler-reuse controls. This closes the selected local-source-pack contract, not general imported implementation forwarding, iterator/stream composition or automatic ownership. Production clone acceptance is separate. |
| Empty unit definition omitted from native output | [Body ownership, executable returns and focused regressions](compiler-unit-body-contract.md) | Empty free, inherent and trait implementation methods, including explicit clone destruction | Repaired in `45561975`: actual admitted unit/entry bodies publish an existing bare return at fallthrough; bodyless required declarations remain contracts. The focused driver passes six compilation jobs/four native executions, nested empty blocks, borrowed mutation and rejection/reuse controls. Natural empty clone destructors and zero-sized elements also execute. No new public IR, resource, pass or ABI record. |
| Concrete ABI hid unresolved static trait selection | [Captured required-member identity and deferred-body repair](compiler-unit-body-contract.md) | Generic helpers whose static bound member has concrete argument/result layouts | Repaired in `45561975` for the reproduced local requirement path. Original generic bodies remain deferred until concrete replay selects the implementation; the missing symbol was the correctly bodyless trait declaration. Emitting that declaration or preserving unrelated inlined helpers would not supply the selection. Generic implementation-environment export below remains separate. |
| Nested match with a wildcard arm | `tests/fixtures/stdlib_foundation/repro_nested_error_match.lani`: x86 compilation reports LNC0005 at `false` inside the inner wildcard arm on base `441e66f9` | Direct nested matching of `Result<_, Error>` | Reproduced 2026-10-22. A separately typed error-matching helper compiles and executes; String tests use helpers. |
| Payload wildcard followed by a fallback arm | `tests/fixtures/stdlib_foundation/repro_payload_wildcard.lani`: `return match (error) { LimitExceeded(_) -> true, _ -> false };` reports LNC0005 even without nesting | Matching payload-bearing error variants | Reproduced 2026-10-22. Binding the payload and assigning the match to a typed local executes in the CSV contract fixture. |
| Historical mixed-record wildcard projection | Original actual-record reproduction/control are recoverable from Git snapshot `fff279e4` at `tests/fixtures/extended/signature/match_material_records_{wildcard,explicit}.lani`; [retained small integer control](../tests/fixtures/stdlib_compiler_state/enum_wildcard_spacing/explicit.lani) | Typed Option projections from record-enum payloads inside family branches | Reproduced 2026-10-25: original source `858be637` failed LNC0005 at `core::option::None()` before ELF generation (3.55 s); paired exhaustive source `954a2baa` executed (6.71 s). The originals imported the removed crypto stack and are not retained as library/compiler fixtures. Small spaced/unspaced integer controls passed; they do not reproduce the actual-record failure or establish a general wildcard, whitespace or panic bug. No compiler, IR, ABI or proof repair is claimed. |
| Array repeat count typing and syntax | Earlier `repro_byte_repeat_count.lani` and `repro_named_repeat_count.lani`; [exact copy-fixture failure/control](../tests/fixtures/stdlib_compiler_state/byte_array_repeat_count/README.md) | Large initialized byte buffers; named array repetition counts | Literal count typing is repaired in `e59a9183`: the checker uses the existing HIR count role rather than the element context. Native tests cover u8 counts 255/256/4100, signed/boolean/nested arrays, and the original 84-case descriptor fixture. Fourteen rejection cases retain element and extent validation. Named/qualified count syntax still requires a literal and reports LNC0016; the formatter's literal scratch requirement remains explicit. See [fix and performance evidence](compiler-array-repeat-context.md). |
| Generic iterator result reassignment lost its concrete layout | [Frozen source and observed markers](../tests/fixtures/stdlib_compiler_state/iterator_selection_assignment/README.md); [context contracts and repair](compiler-iterator-assignment-context.md) | Compound results assigned through generic bound members | Repaired by decoding the parser's statement flag in the shared assignment context reader and requiring receiving constraints to preserve accepted type arguments. The unchanged native reducer and exact incompatible-destination rejection pass; 960 selection model commands and neighboring assignment, trait and inference gates pass. The compiler guide records the separate initially accepted invalid program and both fixes. No IR, ABI, extractor, runtime or proof change. |
| Nested generic stream helper loaded as stdlib | `tests/fixtures/stdlib_foundation/stream_copy_dependency/README.md` preserves a copy implementation that forwards writes through a generic helper; compilation reports LNC0047, detail 6 | Some compositions of imported generic helpers and nominal result payloads | Reproduced 2026-10-22. The same sources loaded as user modules compile. That historical production copy owned its short-write loop directly and passed native tests. The current [Copier engine](stdlib-resumable-copy.md) shares blocking/resumable transfer, with separate acceptance; this migration neither revalidates nor establishes a repair of the exact retained forwarding reduction. |
| Nested generic set wrapper forwarding to a generic map | `tests/fixtures/stdlib_compiler_state/owned_sets/README.md` retains minimized HashMap and TreeMap wrappers, exact diagnostics/hashes and direct-map controls | Earlier nested receiver composition, rather than current production sets | Revalidated 2026-10-23 at `8cb1af7b`: both nested wrappers with Unit payload fail LNC0047; both direct map controls execute. At base `5174a14d`, shared nongeneric owner-state admission executes. Production [owned sets](stdlib-owned-sets.md) use that boundary and pass generic-key, model, ownership, algebra and allocation-failure tests. The compiler failure remains a source-shape dependency, not a blocker of these APIs. |
| Imported method lookup with symbolic const capacity | `tests/fixtures/stdlib_compiler_state/fixed_capacity/symbolic-const-method.lani` fails LNC0027; fixed-capacity method and symbolic-capacity borrowed free-function controls execute | Methods on `Vec<T, N>` inside a caller with symbolic N, including acquiring `.borrow()` there | Reproduced 2026-10-23. Inline Vec/Set retain generic element/capacity parameters and expose canonical borrowed free APIs. Acquire references at concrete call sites, then forward them through generic borrowed parameters. Original symbolic-N record consumers execute after the coherent API migration; no per-type overloads or compatibility aliases were introduced. |
| Generic owned Display and imported Result composition | [Preserved prototypes, consumers, source hashes and observations](../tests/fixtures/stdlib_compiler_state/format_result/README.md) use stdlib classification over the final formatting sources | Proposed generic Display-to-String helper; one imported `unwrap_err` composition inside it | Reproduced 2026-10-23 at base `8cb1af7b`. A primitive-only consumer with direct `T::format` and explicitly typed Result fails LNC0047; a larger historical consumer exits zero. In a separate same-consumer comparison, replacing only `unwrap_err` with a direct match changes LNC0047 to native exit zero. Root cause is unestablished; this does not imply all Result predicates fail. The generic owned helper is excluded from production. Caller-backed Display and typed `alloc::format` outputs execute. |
| Imported PNG header source compositions | [Original modules, commands, source hashes and controls](../tests/fixtures/stdlib_compiler_state/png_header/README.md) preserve the imported user-module classification | Earlier internal Result-return and by-value reconstruction helpers | The full Result<Header,Error> parser fails LNC0006; the later by-value Header reconstruction compiles but loses transparency behavior in its exact test. Small 4/8/11-field Result/value controls all exit zero, so no field-count limit is established. Current caller-owned parsing and borrowed internal Header helpers execute the complete color/depth/interlace matrix. No production PNG API is blocked and no compiler implementation changed. |
| Earlier native benchmark delegation shape | [Exact old prototype and unused-clock implementation failure/control pair](../tests/fixtures/stdlib_compiler_state/development/README.md) | Earlier `bench::native<W>` forwarding into `measure<NativeClock,W>` | The retained prototype fails LNC0047 without an otherwise unused source clock impl; the paired control executes the same work. Current native measurement uses concrete clock reads around shared work/count/duration logic, with a native-only execution gate. Direct measure with NativeClock also compiles against the factored library. This is a retained source-shape observation, not a general clock/callback restriction or a blocker of the working workflow. |
| Generic counted view built through a nested Result factory | [Earlier Vec factory capture](../tests/fixtures/stdlib_foundation/vec_view_dependency/README.md); [current minimal iterator capture](../tests/fixtures/stdlib_compiler_state/iterator_view_result/README.md) | Some generic compositions of slice views and Result helpers | The Vec reproduction dates to 2026-10-22. Under compiler `59612b34`, a two-element SliceIter constructor also reports LNC0047 detail 6: View<i32> has no retained native width when crossing Result helpers, while SliceIter<i32> already has width 5. The inherent slice control executes. Production Vec builds View metadata directly; core::iter centralizes validation through direct metadata plus checked from_view. All five iterator groups pass with that construction. The exact original sources, failure/debug logs and control remain preserved; this is no compiler-fix claim. After canonical cursor integration, use the [paired-module reproduction](../tests/fixtures/stdlib_compiler_state/iterator_view_result/CURRENT_REPRODUCTION.md) to restore both historical iterator and slice modules; original manifests remain unchanged. |
| Inferring a nested generic allocation factory | `tests/fixtures/stdlib_foundation/vec_inference_dependency/README.md`: `let v: Vec<u64> = unwrap(with_capacity(1))` fails LNC0006 | Inference through some nested generic calls | Reproduced 2026-10-23. An explicit `with_capacity<u64>` argument or a typed intermediate `Result<Vec<u64>, Error>` compiles and executes allocation, store, read and destruction. The random batch fixture uses the typed form; the generic APIs remain executable. |
| Binary heap backed by the new borrowed-owner Vec | [Exact candidate and current failure/control](../tests/fixtures/stdlib_foundation/vec_heap_dependency/README.md) | Migrating BinaryHeap from std::vec to alloc::vec | Rechecked on 2026-10-24 with compiler `59612b34` and stdlib `ec795253`: the unchanged ten-line candidate entry still fails LNC0047 with an incomplete native replay layout (4.58 s); the same entry against the production heap passes strict ELF checking and native assertions (4.48 s). The missing argument/cause remains unknown. The working heap keeps its earlier vector; formal std::vec identity and production code are unchanged. |
| Formal standard-vector identity | [VecTemplate](../formal/Lanius/Std/VecTemplate.lean), [VecPrograms](../formal/Lanius/Std/VecPrograms.lean) and [VecSpec](../formal/Lanius/Std/VecSpec.lean) retain the active `std::vec` template, program-instance and specification contract | Removing the legacy std::vec module | The mini compiler, extractor and mini differential-test sources now use `List`; there is no live extractor mapping from `std::vec::Vec`. Retirement still requires coordinated migration of the active formal vector contract. This documentation correction changes no formal source and does not revalidate the separate heap replay failure. |
| Earlier bound member call to an imported generic implementation | [Historical Pull/Cursor capture](../tests/fixtures/stdlib_foundation/iterator_dependency/README.md); [current shared iterator admission](stdlib-iterators.md) | Original imported Pull/Cursor source shape; broader collection/text integration | The old reproduction reports LNC0027 on 2026-10-22 and has not been rerun. The selected current Iterator<T> protocol, checked slice/full-domain i32 cursors, borrowed take/chain and bounded consumption execute under compiler `59612b34`: seven compile jobs include five checked native executables, 6,602 sequence/state cases and two exact-bound rejections. Later [collection/Text/bitset integration](stdlib-collection-iterators.md) and [Text split integration](stdlib-text-split-iterators.md) already execute through that protocol; the [bidirectional Text increment](stdlib-bidirectional-text.md) has its own current receipts. Those later results do not revalidate the original Pull/Cursor reproduction. |
| Blanket implementation forwarding of comparison members | `tests/fixtures/stdlib_compiler_state/comparison/blanket-partial.lani` and its isolated `blanket-root` report LNC0027 when a generic bound dispatches through `impl<T> Forwarded<T> for T where T: Eq<T>` | Automatically deriving partial comparison from total comparison via blanket forwarding | Reproduced 2026-10-23. Standard library primitive and nominal types implement partial comparison explicitly; user types must supply those implementations when using partial membership/ranges. The lawful total Eq/Ord contract is not relaxed. See [comparison contracts](stdlib-comparison.md). |
| Direct match on an associated generic comparison result | `tests/fixtures/stdlib_compiler_state/comparison/generic-partial-cmp-match.lani` reports LNC0006 when matching `T::partial_cmp(a,b)` directly | Generic consumers of PartialOrd.partial_cmp | Reproduced 2026-10-23 with unqualified and qualified variant patterns. The adjacent `generic-partial-cmp-match-control.lani` stores the call result in a typed PartialOrdering local and executes correctly. This is distinct from the parser's nested wildcard-match limitation. |
| CLI match-result binding in a larger import composition | `tests/fixtures/stdlib_compiler_state/cli_match_shadow/README.md` retains the full original/control, isolated user modules and source hashes; original reports LNC0005 for `at` after a match with payload bindings named `at` | One error-location extraction in the streaming regex-search application | Reproduced 2026-10-23 in the full source. Renaming only the outer local to `location` compiles and executes native help/search and focused functional/differential cases. Both tiny reductions compile, so the root cause is unestablished and this is not a claimed general shadowing failure. Compiler/runtime sources are unchanged. |
| Generic record extraction through Vec.at | `tests/fixtures/stdlib_compiler_state/comparison/generic-record-vec-at.lani` compiles but the emitted x86_64 executable receives SIGSEGV | Some generic consumers extracting record elements through alloc::vec::Vec.at | Reproduced 2026-10-23. The adjacent `generic-record-vec-slice-control.lani` changes only extraction to a typed as_slice/index access and exits 0. Concrete TotalF32/TotalF64 at/get calls execute; generic sort/search/membership and collection-key behavior execute through the supported extraction. The failing composition remains outside executable claims. |
| Generic stream adapter through an imported helper | [Historical failure and controls](../tests/fixtures/stdlib_compiler_state/foundation_admission/stream_forward_current/README.md); [accepted implementation-application contract](compiler-implementation-applications.md) | Imported and nested Read/Write implementation applications | Resolved for the selected contract: seven compilation jobs/four native executions cover nested forwarding, short progress, interruption, errors, aliases, flush and source-local bound rejection. An actual two-body library cache hit equals fresh replay. A separate full-u64/generic-layout/static-member application executes. Forty-five CPU checks and two focused GPU gates cover authority, transport, layouts and scratch reuse. [Buffered adapters](stdlib-buffered.md) separately pass five compilation jobs/eighteen native executions, including nesting, allocation failures and real closed-pipe errors. Unrelated iterator and comparison reproductions have not been revalidated here. |
| Chained return-only Vec constructor inference | [Exact captured fixture and diagnostic](../tests/fixtures/stdlib_compiler_state/buffered_constructor_chain/README.md) | `let target: Vec<u8> = alloc::vec::with_capacity(7).unwrap()` | Captured under compiler `59612b34`: `LNC0006`, unknown result versus generic parameter 0. A typed `Result<Vec<u8>, alloc::vec::Error>` local before `unwrap()` executes in the same nested buffered-adapter fixture. This is a call-result inference dependency; no concrete replacement for the generic adapters is used. The original shape has not been rerun or declared fixed. |
| Immediate unwrap on a generic Write result | [Socket-free reproduction and receipt](../tests/fixtures/stdlib_foundation/unix_stream/generic_result_chain/README.md); [typed-local native control](../tests/fixtures/stdlib_foundation/unix_stream/generic_result_chain/typed_local.lani) | `sink.write(bytes,0,1).unwrap()` inside a helper bounded by `W: core::io::Write` | The explicit ignored positive-test run in `unix-stream-generic-result-chain-control.log` takes 4.67s and has one chained test failure (`LNC0027` at chained.lani:14) plus one passing native typed-local control. This is not a green two-test gate. The reduction has no sockets or host I/O; introducing only a typed `Result<i32,core::io::Error>` local preserves the generic call, returned count and observed memory effect. The amended full Unix direct contract passes in 8.11s with generic Read/Write and typed Result locals. No compiler repair, concrete-type specialization or broad generic failure is established. |
| Nested static trait result in a generic record field | [Exact captured source closure and diagnostic](../tests/fixtures/stdlib_compiler_state/implementation_application_static_result/README.md) | `W::echo(source.payload())` used directly as a generic record field | The captured source reports `LNC0006` for an unknown result. Explicit symbolic `T` locals around the same generic calls execute with full-width constants and different record layouts. The original expression has not been rerun or declared fixed. |
| Generic Option method extraction inside a Pair initializer | [Minimal direct/typed control and exact module reconstruction](../tests/fixtures/stdlib_compiler_state/iterator_comparison_pair/README.md) | `Pair<T,U> { first: first.unwrap(), second: second.unwrap() }` in a generic function | The direct CLI probe exits 1 with LNC0006 at direct.lani:7, unknown type versus generic parameter 0; the control changes extraction to typed T/U locals with explicit free `core::option::unwrap<T/U>`, compiles and exits 0 natively with no output. Logs are `iterator-comparison-pair-direct-cli.log`, `iterator-comparison-pair-typed-cli.log` and `iterator-comparison-pair-typed-native.{stdout,stderr}` under `target/stdlib-work/`. The same correction preserves all eight sequence API signatures and traversal effects; their full-module native admission passes in 6.48s. The original failed module is recoverable through the retained patch. No compiler repair, root cause or general generic Option/Pair restriction is claimed. |
| Generic indexed value inside a Pair initializer | [Standalone reduction and typed-local control](../tests/fixtures/stdlib_vec_edit_dependency/README.md) | `Pair<T,T> { first: values[index], second: item }` in a generic function | With preserved compiler `1c2718d4`, the inline reduction exits 1 with LNC0006 in 3.969s: the indexed expression is unknown where T is expected. Giving only that expression a typed T local compiles in 3.382s and the generated native ELF exits 0 with no output. The owned vector editing APIs use the typed local and execute without compiler changes or concrete-type specialization. This records the tested expression shape, not a compiler root cause or general generic restriction. |
| Generic forwarding of record formatting | `tests/fixtures/stdlib_foundation/log_write_dependency/README.md`: a combined generic record preparation/write facade compiles but fails at runtime; a smaller forwarding case produces an incorrect result | One-call generic logging facade and affected compositions of record formatting | Reproduced 2026-10-23. Concrete-writer and separate preparation/delivery controls execute. Production `ext::log` exposes explicit Filtered/Encoded preparation outcomes; `core::io::write_all` handles delivery at the caller. The failing facade is outside the production source root. |
| Deadline factory after a generic clock read | `tests/fixtures/stdlib_foundation/clock_wait_dependency/README.md`: a small clock trait read followed by `core::time::deadline_after` fails LNC0047 | Some compositions of imported nominal time results inside generic functions | Reproduced 2026-10-23. Separately typed Instant addition and Deadline construction execute, as does a generic factory forwarder without the clock read. Production clock APIs retain generic injected/native clocks and one shared wait loop, using the successful construction. |
| Slice and string length access | Language symbols contain data-pointer and slice-stride intrinsics but no length projection; existing `repro_string_length.lani` is a known gap | Count-free slice APIs, construction from `str`, native str conversion | Needs an explicit checked projection; no pointer reinterpretation or NUL scan substitutes for it. Counted borrowed Text and generic slice View values execute without accessing slice metadata. Their initial physical backing count remains a caller precondition. |
| Immutable views and ownership | Slices are writable; container handles copy and destruction is explicit | Safe borrowed String bytes, automatic destruction, deep-owned containers | Public lifetime and read-only conventions are documented; not compiler-enforced. |
| Pointer address/alignment projection | `tests/fixtures/stdlib_foundation/arena_dependency/pointer_cast.lani` reports LNC0072, cannot cast `ptr` as `usize` | Arbitrary over-aligned arena layouts | Reproduced 2026-10-23. Current raw arenas explicitly support alignments 1, 2, 4 and 8, covering current native typed layouts. Larger powers return `UnsupportedAlignment`; no assumed host page alignment is used. |
| Nominal allocation result inside an imported generic copy | `tests/fixtures/stdlib_foundation/arena_dependency/README.md`: the 32-line Block-return provider reports LNC0047; a pointer-return provider compiles and executes with the same caller | Some compositions of generic typed storage with nominal allocation-result helpers | Reproduced 2026-10-23. This source-shape difference does not establish the compiler root cause. Production arena uses one primitive internal allocation boundary and wraps raw Blocks separately; generic typed APIs, a standalone byte-copy control, broad native layouts and the real word-count consumer all execute. |
| Direct generic View record from a native array | [Inferred path literal/control](../tests/fixtures/stdlib_foundation/path_view_dependency/README.md) and [explicit schema literal/control](../tests/fixtures/extended_library/schema_view_dependency.README.md) retain historical diagnostics/output and current source/ELF hashes | Earlier direct View record constructions, including invalid-metadata tests | Repaired by `678bf559`. All four exact unchanged forms compile and execute at `10be2529`: path literal/control return the expected Bounds result; schema literal/control both print `-1,2`. The native-array record field retains its accepted slice descriptor instead of shifting following fields. This closes these source forms without claiming arbitrary inferred expressions work. |
| Complete host services | Old `std::net` and `std::thread` bindings remain unavailable; service 14 is executable | Threads, native callbacks and broader C ABI profiles, additional database integrations and higher-level protocol orchestration | Owned sockets and extended filesystem operations execute as Lanius code over `std::linux`; SQLite executes through the selected Linux x86_64/glibc C profile. `core::target::HAS_NETWORK` describes those working library APIs; `core::runtime::HAS_NETWORK` describes the still-unbound old direct service 5. Client TLS with peer verification executes through OpenSSL 3 with borrowed nonblocking sockets, explicit identity/trust and caller polling/deadline/SIGPIPE policy. [Server TLS](extended-openssl-tls-server.md) and [required mutual TLS](extended-openssl-mutual-tls.md) have separately documented native receipts. Callbacks, threads and broader host-service completeness remain open. |
| Historical directory extern without a binding | `tests/fixtures/stdlib_foundation/filesystem_operations_directory_dependency.lani` declares an unrecognized directory-read extern and reports LNC0017 | The unsupported spelling retained as compiler evidence | Superseded as a library blocker by `std::directory` over the explicit Linux syscall binding. The old arbitrary extern remains unsupported; its failure is excluded from passing API claims. |
| Earlier extended-filesystem prerequisite | Basic `std::file::open` still uses its three original modes | Distinguishing old fixed-mode opens from current file options | Resolved for the selected native profile by `std::file_ops` and `std::directory`, with nine focused execution groups and independent review. Existing fixed-mode opens still follow symlinks and omit close-on-exec; configurable opens default to close-on-exec. Paths remain bounded to 4,095 bytes. |
| Native array converted inside a View record initializer | [Historical four-way source/output and current descriptor-layout regressions](../tests/fixtures/stdlib_compiler_state/settings_array_view/README.md) | Outer array-to-slice adjustment in imported/local record fields | Resolved by retaining the accepted mode4 descriptor adjustment and using its width during aggregate construction. The unchanged Text case now prints 6/6/6/6. Reordered generic records, sentinels, aliasing, positive/negative strides, nested arrays and zero-size/empty elements execute; incompatible element/extent types reject. No target/IR/ABI representation changed. Historical corruption remains preserved separately. |
| Historical heap view through a nested Result factory | [Pinned original heap, minimal failures and successful controls](../tests/fixtures/stdlib_compiler_state/checked_sample_heap/README.md) | Earlier BinaryHeap<i64>::as_view and its caller compositions | Resolved for production as_view by constructing directly from owner-proven initialized storage, without changing its signature/backing. Empty/i64/mixed-record views and existing generic/self-extension controls execute. The original nested-factory shape remains diagnostic evidence; this does not repair unrelated generic replay boundaries. top_scores uses a coherent checked reserve/pop drain. |
| Inferred forged Text constructor in sentence admission | [Twenty-two-line source](../tests/fixtures/extended/unicode_sentences_forged_repro.lani) | A test-only inferred aggregate initializer | The original inferred constructor admission failed on unsupported target LIR opcode 31. Explicitly typed helper construction validates the intended negative/overflow metadata cases in the passing sentence contracts. Kept separate from the four-way View initializer bug; a common cause has not been established. |

## Build setup

Use an absolute `CARGO_TARGET_DIR`. A relative value can put shader artifacts
under the shader crate while the compiler reads relative to its invocation
directory. The initial build reproduced this as LNC0057 during lexer
initialization. Rebuilding with an absolute target directory fixed the artifact
location without changing compiler source.

The library execution gate is documented in [stdlib-string.md](stdlib-string.md).
Compiler reproductions are separate from executable support claims.
