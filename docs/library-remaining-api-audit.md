# Remaining standard-library API audit

Audit date: 2026-10-23. Baseline: `d20fface`, followed by the scoped memory
metadata and path-comment corrections below. This is a source and caller audit
of the remaining `core`, `alloc` and `std` interfaces. It supplements the
[roadmap](library-roadmap.md), [foundation evidence](stdlib-foundation.md) and
[compiler dependencies](library-dependencies.md); it does not certify every
public function through a new execution run.

The audit traced implementations, native bindings, production callers,
diagnostic strings, formal extraction and existing tests. Constant returns
were inspected in context. A capability probe, status constructor or
mathematical identity is not evidence of fabricated execution. Concurrent
socket, numeric-consumer, Unicode, settings and distribution work has separate
owners and is excluded from completion claims here.

### Subsequent corrections

The original tables below retain their audited baseline. Since that snapshot,
[numeric consumer consolidation](stdlib-numeric-migration.md) removed seven
redundant helper modules, and [checked sample migration](stdlib-checked-sample-migration.md)
is moving ordinary vector/output callers off silent-failure and statusless
operations. The protected `std::vec` identity and extractor are unchanged.
[File options](stdlib-file-operations.md), [directory walking](stdlib-directory.md),
[sockets](stdlib-sockets.md) and [signal dispositions](stdlib-signals.md) now
execute over Linux service 14. The broad library network capability is true;
the old direct catalog service 5 remains unavailable. `core::target` reports
library families and `core::runtime` reports direct bindings, with native
metadata execution checking their documented difference.

## Corrections completed in this audit

| Correction | Evidence and scope |
| --- | --- |
| Remove obsolete raw-memory service metadata from `core::mem` | The baseline `mem.lani:8–18,32–73` assigned allocator service ID 1 to an unavailable raw-memory service, beside working compiler-provided raw views and sizing operations. There was no raw-memory host declaration or diagnostic-catalog entry. Removed the three `RawMemory*` types, five `RAW_MEMORY_*` constants and eleven `raw_memory_*` helpers. Value helpers, their runtime-free contract and every memory intrinsic wrapper remain. |
| Retire an impossible typecheck-only contract | The former `tests/stdlib_runtime_contract.rs:2953` test required unavailable raw-memory status to equal the now-available allocator status, and required allocator binding to remain unavailable. It only typechecked its embedded program. Removed this obsolete test and raw-memory references in the value-helper import check. |
| Update the live memory execution fixture | `tests/fixtures/stdlib_foundation/core_mem_metadata.lani` now checks only the retained value-helper contract. The existing memory execution target also exercises values, pointers, typed views, mutation, generic layouts and sizing. Its public-call inventory now covers the eleven remaining functions. |
| Correct counted-path comments | `std/file_binary.lani:1` and `std/file_hex.lani:1` no longer claim that host calls ignore path lengths or require NUL-terminated storage. `runtime_path_ops.s:7–32` copies the supplied count, rejects embedded NUL and counts above 4,095, then appends its own terminator. No file operation changed. |

No compiler, native runtime, diagnostic catalog, formal source or `std::vec`
identity changed. A repository search finds no remaining live consumer of the
removed memory names. Historical descriptions of the earlier contract remain
historical evidence.

## Remaining failure and ownership work

### 1. Migrate application uses of the legacy vector

`stdlib/std/vec.lani` executes real allocation and mutation. Its failure and
ownership interface is still weaker than the canonical `alloc::vec` interface:

| Legacy operation | Actual behavior | Canonical destination |
| --- | --- | --- |
| `try_reserve` at line 57, `try_push` at 123, `try_insert` at 228, `try_resize` at 289 | Invalid or failed requests return the original owner without an error value. Callers must infer success from counts or capacity. A negative `reserve` request also returns unchanged. | `alloc::vec` reports `Bounds`, `InvalidCapacity`, `CapacityOverflow` or `AllocationFailed` through `Result`. |
| `try_set` at line 209 | Both successful replacement and invalid index return the same owner with unchanged length and capacity. The file header's suggestion to compare those fields cannot detect this operation's success. The displaced element is not returned. | `Vec.set` returns the displaced `T` or an explicit error (`alloc/vec.lani:140`). |
| `try_pop`, `try_remove`, `try_swap_remove` at lines 220,251,265 | Remove shallow values without returning them. A resource-owning element must be retrieved separately before removal. | `pop`, `remove`, `swap_remove` return the removed value (`alloc/vec.lani:145–165`). |
| `try_clone` at line 356 | Allocation failure returns a new empty vector. The caller must compare its length with the nonempty source to detect failure. | `try_clone` returns `Result<Vec<T>, Error>` (`alloc/vec.lani:190`). |
| `destroy` at line 373 | Frees storage through a copied owner without resetting the caller's value. Keeping only the newest owner and avoiding stale copies is a caller convention. | Borrowed-owner mutation synchronizes the active owner, with explicit shallow ownership rules. Language-enforced moves and deep destruction remain separate work. |

These behaviors are mostly documented legacy policies, rather than missing
function bodies. They remain a poor application boundary because callers can
accidentally treat unchanged or empty output as successful work.

At the baseline, sixteen sample programs imported this module: the four
`sorted_*_median` programs, `top_scores`, `unicode_sort_unique`,
`unicode_text_report`, `vector_edit_checksum`, `vector_halfword_checksum`,
`vector_signed_byte_sum`, `vector_signed_halfword_sum`, `vector_square_sum`,
`vector_true_count`, `vector_unsigned_checksum`, `wide_signed_sum` and
`wide_unsigned_sum`. Concurrent numeric migration is already changing the
four sorted programs. Recheck the remaining import list before assigning
sample edits. No extended-library production consumer was found.

`alloc::binary_heap` is the sole other standard-library consumer. Its reserve,
clone and shrink operations check the legacy result and return explicit errors
(`alloc/binary_heap.lani:97–102,189–198`). It is not another silently successful
implementation. Its public `from_vec`, `take_vec` and `take_sorted_vec` still
expose the legacy owner. The attempted `alloc::vec` migration and compiler
failure are preserved in `vec_heap_dependency/README.md`.

**Removal constraint:** `formal/tools/extract.py:146` maps the exact type path
`std::vec::Vec`; `formal/lani/mini/compiler.lani:17–109` uses `new`, `len`,
`push`, `at` and the type throughout its compiler model. Generated programs in
`formal/tools/mini_difftest.py` also use it. Preserve this path and the verified
compiler's source context until a coordinated extraction/proof migration is
approved. Migrate ordinary applications independently. Do not add aliases or
delete compiler regression fixtures merely to make searches empty.

### 2. Retire statusless integer output from application paths

`std::io::print_i32` (`stdlib/std/io.lani:296`) calls the void `print` primitive.
The native routine formats digits and LF, makes one stdout write, and returns
without checking or retrying the syscall (`runtime_abi.slang:204–223`). It does
write output, but callers cannot observe short writes or host errors. Calling
it executable is accurate; using it for output whose delivery determines
application success hides failures.

The remaining calls at audit time are:

- `sample_programs/result_reading_total.lani:30,31`;
- `random_fill.lani:19`, `vector_edit_checksum.lani:35`;
- `host_runtime_files.lani:37`, `stdio_flush.lani:7`;
- `vector_square_sum.lani:28`;
- `stdio_print_i32.lani:6,7` (the second call is imported without qualification).

That is nine calls in seven files. Coordinate edits with the numeric/sample
owner. Move application output to existing checked formatting/writers and
propagate delivery failures. `core::io::write_all` with `std::stream` provides
the shared full-write/retry contract; the existing `std::io_decimal` writers
also check each host result. Deleting the wrapper and its metadata requires
the host-ABI owner to update the catalog guidance. The compiler primitive is
outside this correction's scope.

`std::io::write_line`, `println` and `eprintln` (`io.lani:273–293`) are a related
consolidation target: they write text once and still attempt LF after a short
text write. They return the observed aggregate count and document this policy.
They do not promise full delivery or return fabricated success. Applications
that require complete output should use counted data and full writers. The
missing `str`/slice length projection prevents inventing a safe count-free
replacement; a NUL scan is not a substitute.

## Unavailable interfaces and safe removal boundaries

The following modules honestly report unavailable support. Their constant
`*_operation_ok()` or `test_status_passed()` helpers construct status values;
they do not execute an operation. Removing duplicate status/probe interfaces
is useful consolidation, but does not implement the missing services.

| Surface | Current executable content | Retention requirement |
| --- | --- | --- |
| `std::net` | TCP/UDP declarations at `net.lani:276–305`; binding flag false at line 16. Numeric addresses and prefixes execute separately in `core::net`. | Diagnostic service ID 5 and each declared API are named in the compiler catalog. Parent owns native socket admission and contracts. |
| `std::thread` | Unbound spawn/join/yield/current-ID declarations at `thread.lani:148–154`; false flag at 16. No working thread or synchronization implementation follows from those declarations. | Service ID 8 and all four API names are catalog entries. |
| `std::gpu` | Five unbound buffer/dispatch declarations at `gpu.lani:197–205`; false flag at 17. Compiler use of a GPU is a different capability. | Service ID 10 and the buffer/dispatch API names are catalog entries. |
| `std::host` | Descriptor metadata only (`host.lani:1–3`), with no executable host operation. | Service ID 7 names this module and its minimum probes. |
| `core::panic` hook metadata | `panic` and `unreachable` really trap at `panic.lani:5–10`. Hook support is false at line 21; there is no hook-installation operation. | Service ID 6 names the hook metadata. Preserve the actual trap functions. |
| `test::harness` | Descriptor and status metadata only (`harness.lani:1–3`). No registration/discovery/execution operation exists here. `test::suite`, `check`, `property` and `bench` execute explicit source workflows independently. | Service ID 13 names the module and probes. Removing this module requires catalog/test migration, not replacing the working source runner. |

The compiler's service catalog (`compiler/diagnostics.rs:915–1070`) names this
minimum set for every row: its module path, `*_HAS_RUNTIME_BINDING` constant,
`*_service_status()` and binding requirement probe. The relevant binding
probes are `network_requires_runtime_binding`,
`panic_hook_requires_runtime_binding`, `host_services_require_runtime_binding`,
`thread_requires_runtime_binding`, `gpu_requires_runtime_binding` and
`test_harness_requires_runtime_binding`. The API catalog at lines 1484–1692
also names operation-specific executable/binding probes and declarations.

There were no production Lanius callers of these metadata families outside
their defining modules. Their consumers are diagnostic strings, runtime
contract tests, module-import tests and public-call inventories. No formal
extraction dependency was found. Rust's own `std::thread` uses are unrelated.

**Next removal proposal:** retain the catalog-named surface until its owner
approves a coordinated replacement. Then remove redundant synonymous probes
and unused status constructors together with internal tests that merely
exercise their spelling. One precise candidate is
`std::host::host_services_requires_runtime_binding` (`host.lani:53`): it only
forwards to the singular `host_services_require_runtime_binding` used by the
catalog. Its external callers are the same typecheck contract, not production
programs. Do not preserve the redundant name as an alias. Whole-module removal
of `std::host` or `test::harness` needs catalog changes and is not approved by
this audit.

## Target metadata still needs operation-level scope

`core::target:1–23` describes a fixed native x86_64 Linux support snapshot.
`core::runtime:19–62` mirrors thirteen service descriptors. Neither probes the
running host or establishes universal target support.

| Aggregate claim | Actual narrower scope / next correction |
| --- | --- |
| Clock is available | `std::time:19–25` binds timespec reads, Unix seconds and i32 millisecond sleep, but explicitly leaves i64 clock-result and sleep declarations unbound. Native integer support alone does not bind them. Prefer `std::clock`'s typed results and retain exact per-operation support metadata. |
| Filesystem is available | Basic open/read/write/close and counted-path mutations execute. Seek/stat/directory enumeration/fsync/dup and configurable-open flags remain distinct prerequisites. Parent owns their admission; the filesystem and dependency guides record the limits. |
| Process is available | Arguments and exit execute. This flag does not supply subprocess creation, waiting, pipes or cancellation. |
| Runtime services are contract-only / blocked | `HAS_RUNTIME_SERVICES=false` and `runtime_services_are_contract_only()` mean the complete service set is not bound. Several individual services are executable. Prefer per-service rows over treating this aggregate as a statement that all services fail. |
| GPU / test harness unavailable | These mean user GPU host services and compiler/runtime registration/discovery. They do not deny compiler GPU execution or the working explicit source-test workflow. |

The next metadata deliverable is a single operation-level support inventory
that keeps source probes, diagnostics and native binding evidence consistent.
Preserve honest false values until the corresponding operation really binds;
adding declarations or changing a boolean cannot complete that work.

## Intentional identities and no-buffer flushes

These reviewed bodies require no replacement implementation:

| Body | Reason |
| --- | --- |
| `std::io::flush_stdout/flush_stderr` at `io.lani:253–260` | Writes cross the host boundary synchronously; this layer has no userspace output buffer to drain. Zero does not claim fsync or durability. |
| `std::stream::Descriptor.flush`, `std::file::File.flush` at `stream.lani:83`, `file.lani:107` | The adapters have no pending buffer. File flush also rejects a closed owner. Their comments explicitly exclude durable synchronization. |
| `core::io::SliceWriter.flush`, `alloc::io::Buffer.flush` at `core/io.lani:206`, `alloc/io.lani:83` | Bytes already reside in the memory sink. There is no deferred host write. |
| `mem::identity/first/second`, borrow helpers, full-range membership, fixed-four-element `is_empty=false` | These are value identities, borrowed references, or consequences of the represented mathematical/container type. |
| `Hash<u32>` returning its input | A lawful identity hash for the full u32 value, not skipped hashing work. |
| Explicit `_or` fallbacks and Boolean checked host helpers | They intentionally collapse detailed errors, with comments describing invalid input, host failure and possible partial prefixes. They execute the underlying work. Do not count every fallback return as a stub. |

`std::file::write_text_once` (`file.lani:114`) performs one write and closes the
handle, returning the count or error. Its name and contract say “once”; it is
not a full-write implementation. `copy_distinct_with_buffer` at line 294
explicitly requires distinct files even through aliases, pending metadata
support for checking identity.

The raw `std::random::secure_u32` is also not a silent zero fallback: the current
native routine (`runtime_abi.slang:535–549`) traps when getrandom fails or reads
fewer than four bytes. `std::entropy` supplies recoverable `Result` errors and
completed-prefix accounting. Preserve this distinction when consolidating old
random helpers.

## Lower-priority consolidation after caller migration

- `core::array_i32`, `array_i32_4`, `array_u8_4` and `u32_cells` contain real
  operations. At baseline, their remaining callers were tests rather than
  standard/extended production modules. Migrate tests to generic slice/View
  or canonical primitive operations before deleting redundant specializations;
  retain any compiler regression's exact source context separately.
- Old `std::io_*`, `file_*`, `args_checked`, `env_checked`, `time_checked`,
  `time_wide` and `random_wide` modules are mostly executable convenience or
  representation layers with explicit Boolean/fallback policies. Consolidate
  through `core::io`, `std::stream/file`, `std::args`, `std::clock`,
  `std::entropy` and canonical formatting. Check each module's real callers
  before removal; represented-width migration belongs to the numeric owner.
- Free `core::bitset` fallback wrappers already call the checked BitView
  implementation. Their live sample caller is being migrated independently.
  Remove the old entry points only after that consumer and its tests move.
- Generic clone/destruction, layout/alignment contracts, shared iterator
  dispatch/adapters and buffered I/O remain substantive library work. The
  dependency guide identifies exact compiler limits. Shallow collection copies
  and unbuffered flushes do not implement those missing features.

## Next ownership assignments

1. **Collection/sample owner:** finish plain application migration to
   `alloc::vec`, with allocation and removed-value handling. Preserve formal
   identity and the heap migration reproduction.
2. **Host-ABI owner:** coordinate checked integer output and catalog cleanup;
   extend per-operation target evidence as bindings become executable.
3. **Metadata cleanup owner, after approval:** remove uncited probe synonyms
   and status-constructor clutter, updating internal import tests in the same
   change. Whole-facade deletion requires diagnostic-catalog coordination.
4. **Portable library owner:** add buffered adapters and complete reusable
   iteration/ownership surfaces, preserving real compiler blockers and working
   controls rather than supplying placeholder methods.

The first scoped correction above is complete independently of these next
assignments. The whole standard-library goal remains open.

## Verification of the scoped correction

Both affected Rust test targets compiled with the established
`target/stdlib-build` directory. The existing
`memory_helpers_and_slice_intrinsics_execute_on_x86` group passed in 11.03 s,
executing its seven memory fixtures under the shared GPU lock. The CPU-only
public-call inventory check also passed. The unchanged negative-length and
out-of-bounds trap group was not rerun because no intrinsic implementation or
argument check changed. A source search confirms that removed names have no
remaining live callers, and `git diff --check` passes for the changed files.
