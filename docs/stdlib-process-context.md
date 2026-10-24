# Process arguments, environment and current directory

These modules expose the current program's context and immediate exit:

| Module | Operational API | Other public functions |
| --- | --- | ---: |
| [`std::args`](../stdlib/std/args.lani) | `snapshot` and six `Arguments` methods | 0 |
| [`std::args_checked`](../stdlib/std/args_checked.lani) | Three checked argument helpers | 0 |
| [`std::env`](../stdlib/std/env.lani) | Six raw externs and `current_dir_len` | 53 metadata/result queries |
| [`std::env_checked`](../stdlib/std/env_checked.lani) | Three checked environment/directory helpers | 0 |
| [`std::process`](../stdlib/std/process.lani) | `argc`, `arg_len`, `arg_read`, `exit` | 44 metadata/result/exit-code helpers |

There are 24 operational functions/methods and 97 supporting queries. The
contracts below describe the native x86_64 Linux bindings and their source
wrappers. Launching, waiting for and signaling children belongs to
[`std::command`](stdlib-command.md); draining their pipes belongs to
[command capture](stdlib-command-capture.md).

## Bytes and retained startup state

Arguments and environment names/values are **bytes**, not validated UTF-8.
Non-UTF-8 bytes and empty arguments/values are preserved. Lengths exclude the
startup C strings' terminating NUL, and the copy operations do not copy or add
that NUL. They do not split options, remove quotes, expand variables, normalize
paths or interpret a locale. Use [UTF validation](stdlib-utf-codecs.md) or
[`core::text`](stdlib-text.md) when an application requires text.

The native runtime retains the original process startup stack for `argc`,
`argv` and `envp`. Argument and environment reads walk that state; they do not
consult a new libc argument/environment table on each call. Keep that retained
state valid and unchanged. The modules provide no argument or environment
mutation API, live-environment refresh, or synchronization with foreign code
that rewrites it. An owned argument snapshot copies the selected bytes into
separate storage.

Index zero is the caller-supplied `argv[0]`, conventionally the program name.
It is not an executable-path discovery API: a launcher may choose a different
name or an empty value. The runtime does not resolve it. Argument indices and
all returned argument/environment counts are `i32`.

Raw buffer APIs take `ptr` and `usize`. The caller supplies live readable key
storage and writable destination storage for every byte the operation may
access; a nonzero pointer does not establish its validity or ownership. Keep
storage alive through the call and prevent conflicting mutation. These APIs
do not create slices, track aliases or validate physical bounds. Use separate
output storage from the retained startup strings; there is no general
memmove-style overlapping-copy contract. Native value lookup finishes matching
the caller key before copying a value, but this guide makes no cross-target
key/output-overlap claim.

## Raw argument operations

| `std::process` function | Native behavior |
| --- | --- |
| `argc() -> i32` | Startup argument count, including index zero when present |
| `arg_len(index) -> i32` | Byte length excluding NUL; -1 for a negative or absent index |
| `arg_read(index, destination, capacity) -> i32` | Copies up to the lesser of capacity and argument byte length; returns bytes copied, or -1 for a negative/absent index |

A short raw read is successful prefix copying, not a truncation error. For a
valid index, capacity zero returns 0 without writing. An empty argument also
returns 0 without writing, including with a null destination. A nonempty copy
requires valid writable storage; the raw operation does not reject a null
pointer before attempting it. Invalid indices are rejected even at capacity 0.
The unused destination tail is unchanged, with no NUL terminator added.

### Checked exact argument copies

`std::args_checked` allocates nothing:

| Function | Contract |
| --- | --- |
| `argument_count_or(fallback)` | Startup count, or fallback when the host count is less than 1 |
| `argument_len_or(index, fallback)` | Nonnegative byte length, or fallback for a negative/absent index or negative host result |
| `read_exact_into(index, destination, capacity)` | True only when the complete argument was copied, with the rules below |

`read_exact_into` first rejects a negative index or capacity greater than
`i32::MAX`, queries the argument length, rejects a negative result or too little
capacity, and rejects a null destination for nonempty data. These rejections
write nothing. An empty argument succeeds with a null buffer and zero capacity.
For nonempty data it requests exactly the measured byte count, even if capacity
is larger, and requires the returned count to match. A host short read returns
false and may leave a copied prefix; there is no rollback, retry, partial-count
result or NUL termination. A fallback may equal a legitimate count or length.

## Owned `Arguments` snapshots

`std::args::snapshot(first, maximum_count, maximum_bytes)` returns
`Result<Arguments, Error>` for startup indices `[first, argc)`. Indexing the
returned owner starts at zero. Use `first = 1` to omit the conventional program
name, or 0 to retain it. `first == argc` selects no arguments and succeeds
with zero limits. Unlike `argument_count_or`, snapshot only rejects a negative
host count; its empty-selection handling does not require the count to be 1.

Both limits are nonnegative `i32` values. The count limit includes selected
empty arguments; the byte limit sums their byte lengths, excluding every
terminating NUL. Neither includes the allocation for the entry table or
allocator overhead. There is no separate per-argument limit, work ledger or
deadline. The table is additionally bounded so
`count * size_of<View<u8>>() <= i32::MAX`; aggregate byte additions are checked
against `maximum_bytes` by subtraction before increasing the total.

| `std::args::Error` | Condition |
| --- | --- |
| `Bounds` | Negative `first` or limit, or `first > argc` |
| `CountLimit` | Selected count exceeds its limit or representable table backing |
| `ByteLimit` | Sum of selected argument bytes exceeds its limit |
| `AllocationFailed` | Entry-table reservation or byte-storage allocation fails |
| `HostRead(index)` | An argument length/copy is invalid or inconsistent; payload is its original startup index |

`HostRead(-1)` denotes a negative host argument count or a final aggregate
size mismatch. Checks proceed through negative parameters, host argument
count, `first <= argc`, selected-count limits and aggregate bytes, then
allocation and copying. A successfully constructed snapshot uses an entry
`Vec<View<u8>>` and one packed byte allocation when its byte total is nonzero.
The packed bytes contain no separators or trailing NULs. Selecting only empty
arguments can still allocate the entry table; selecting no arguments needs
neither allocation.

Lengths are measured before allocation and again during copying. A later
negative length, growth beyond the measured total, unequal copy count or final
total mismatch destroys acquired storage before returning `HostRead`. This is
an inconsistency check, not an atomic view of concurrently changing startup
memory; same-length byte changes cannot all be detected. Keep the source
unchanged during capture. No partially built owner escapes on an error.

| `Arguments` method | Contract |
| --- | --- |
| `len()` | Selected argument count |
| `is_empty()` | Whether that count is zero; nonzero count of empty strings is not empty |
| `byte_len()` | Sum of stored bytes, excluding NULs |
| `get(index)` | `Some(View<u8>)` for a valid selected index, `None` otherwise, including negative indices |
| `as_view()` | Borrowed view of all argument views |
| `destroy()` | Releases table and byte storage, and resets this owner record to empty |

Keep one active owner. Copying `Arguments` aliases its allocations; it does not
clone them. All argument views, their subviews and `as_view()` borrow the owner
and become invalid after destruction. Repeated `destroy()` on the same reset
record is harmless; destroying an earlier shallow copy is not safe. There is
no automatic destructor. Treat public owner fields as internal invariants;
forging or mutating them is outside the snapshot contract.

Capture uses work proportional to selected argument count and bytes, with
multiple length scans and copying. Allocation failures are recoverable and
release earlier allocations; quota rejection happens before either owner is
allocated. See [owned vector contracts](stdlib-vec.md) for the table's storage.

## Environment lookup and enumeration

| `std::env` raw function | Native behavior |
| --- | --- |
| `var_count()` | Number of retained startup environment entries, not distinct names |
| `var_key_len(index)` | Name length before the first `=` or NUL; -1 for negative/absent index |
| `var_key_read(index, destination, capacity)` | Copies at most capacity name bytes, stopping before `=` or NUL; returns copied count, or -1 for negative/absent index |
| `var_len(key, key_len)` | Length of the first exactly matching entry's value, excluding NUL; -1 when no match exists |
| `var_read(key, key_len, destination, capacity)` | Copies at most capacity bytes of that first value, excluding NUL; returns copied count, or -1 when absent |

Lookup compares exact, case-sensitive name bytes and requires `=` immediately
after the complete supplied key. It does not match a prefix of a longer name,
apply a shell identifier rule or decode UTF-8. The first matching startup entry
wins when names repeat, including when that first value is empty. Enumeration
preserves entry order and duplicates; it is not sorted or deduplicated. No
index-based value reader is provided, so enumerating duplicate names then
looking each up by name returns the first value each time, not each duplicate's
distinct original value.

An existing empty value has length/read result 0. A missing name gives -1;
zero output capacity for a present nonempty value gives a successful raw read
of 0 bytes. Name/value copies never add NULs. Raw enumeration also counts
malformed startup entries: a string without `=` still has an enumerable name
but cannot match a lookup requiring that separator; an empty name can yield
key length 0. The raw calls are not key validators and do not uniformly reject
null pointers or zero lengths. Use nonempty backed keys or the checked wrapper
instead of relying on malformed-entry edge cases.

### Checked exact environment copies

`std::env_checked::var_read_exact_into(key, key_len, destination, capacity)`
rejects a null key, zero key length, key length or capacity above `i32::MAX`,
missing name, insufficient capacity, or null destination for a nonempty value.
All these rejections happen before a copy. An existing empty value succeeds
with a null destination and zero capacity. A nonempty value is copied using
exactly the previously measured length. True means the returned count matched;
false after a host short read may leave a prefix. No terminator is added and
no retry or partial-count result is supplied. The key need not have a NUL after
its counted bytes; the wrapper does not promise shell-name validation.

`var_key_read_exact_into(index, destination, capacity)` rejects a negative or
absent index, capacity above `i32::MAX`, measured key length <= 0, insufficient
capacity or a null destination. Thus it deliberately rejects enumerable empty
names. It requests exactly the measured nonempty key and returns true only
for an equal copied count. Its preflight failures write nothing, but a short
host copy can leave a prefix.

Raw lookup and length operations scan the retained environment and finite
strings; a checked output-capacity limit is not a work limit for that scan.
Each indexed key operation walks from the start of the entry list, so complete
enumeration through repeated indexed calls can take quadratic entry visits.
There is no owned environment snapshot in these five modules. See
[`std::command::snapshot_environment`](stdlib-command.md#limits-and-environment-capture)
for its distinct ownership and duplicate-name policy.

## Current directory: live syscall and bounded length query

`std::env::current_dir_read(destination, capacity)` makes one native Linux
`getcwd` syscall. It is live process state, not startup `PWD` or a retained
startup directory. Capacity includes the terminating NUL. On success the
runtime returns the path byte count **excluding** NUL, while leaving that NUL
in the buffer. It does not validate UTF-8 or normalize paths. Capacity zero
returns -1 before a syscall; kernel failures, including insufficient space,
are collapsed to -1 without exposing errno or retrying EINTR. Raw pointer
validity still belongs to the caller.

`std::env_checked::current_dir_read_into(destination, capacity)` additionally
rejects a null destination, zero capacity or capacity above `i32::MAX`. It
returns -1 for those cases, a negative host result, or a host-reported count
that is not strictly below capacity. Otherwise it returns that NUL-exclusive
count. It neither independently checks the terminator nor adds one: it relies
on the host's directory-read contract. Failure after entering the host may
have changed the buffer; do not interpret it as a valid path.

`std::env::current_dir_len()` is not a nonallocating size probe. It allocates
4096 bytes aligned to 4, calls `current_dir_read` with that capacity, and frees
the scratch allocation before returning the count or -1. Null allocation also
returns -1. Thus a successful native result is at most 4095 bytes, and a longer
directory path is not discovered by growing the scratch. A later directory
read is another syscall and need not have the same length if the directory
changes. A caller sizing from this result must check addition of one for NUL
and still handle the later read's failure. Linux's underlying syscall and
library-wrapper distinctions are described in the
[getcwd manual](https://man7.org/linux/man-pages/man3/getcwd.3.html).

## Full-width raw arguments and checked limits

The current native bindings preserve every bit of raw `usize` copy capacities,
environment key lengths and directory capacities; they no longer truncate to
32 bits. Argument/environment copies still stop at their finite startup
string boundary, and result counters/indices remain `i32`. A capacity of
`2^32 + 1` does not become 1. Conversely, callers must not infer physically
huge output backing or unbounded result counts from this transport guarantee.

For environment lookup, the native matcher checks the environment name's NUL
or `=` before reading the next corresponding caller-key byte, and only accepts
`=` at exactly the complete supplied key length. A declared length of
`2^32 + 3` cannot alias a three-byte key or scan through its value. There is
still no general pointer validator. The checked source wrappers intentionally
retain the stricter `i32::MAX` admission cap described above. Exact guard-page,
canary and syscall-argument evidence is recorded in
[raw host widths](stdlib-raw-host-width.md).

## Exit and status metadata

`std::process::exit(code: i32)` uses native Linux syscall 60, `SYS_exit`. In the
supported single-threaded process profile it terminates execution; it does not
return through normal Lanius cleanup or run owner destructors, finalizers or
userspace output flushing. Release resources and check output before calling
it when those actions matter. Raw `SYS_exit` terminates the calling thread,
not an entire externally created thread group; it is not `exit_group`.
The observed parent exit status uses the low eight bits. These kernel semantics
are documented in the [Linux exit manual](https://man7.org/linux/man-pages/man2/_exit.2.html).

`EXIT_SUCCESS`/`exit_success_code()` are 0 and
`EXIT_FAILURE`/`exit_failure_code()` are 1. `exit_code_from_success` maps true
to 0 and false to 1. `exit_code_is_success` tests the full `i32` for zero;
`exit_code_is_failure` tests nonzero. These pure helpers do not predict low-byte
truncation: for example, a nonzero code divisible by 256 is classified as
failure by the helper even though a native parent can observe exit status 0.
The native exit fixture establishes code 7 and nonreturn, not an exhaustive
exit-code or multithreaded model.

`ProcessCapability` and `EnvCapability` alias `bool`. Each module's
`*RuntimeAbiVersion`, `*ServiceId` and `*ServiceStatus` aliases are `u32`;
`ExitCode`, `ProcessArgumentResult` and `EnvReadResult` are `i32`.
Process/environment service descriptors use ABI version 1, service IDs 11/12,
available status 2 and unavailable status 1. Their current binding constants
are true. `process_*` and `env_*` service queries, the process
`argc`/`arg_len`/`arg_read`/`process_exit`/`exit` capability-query families, the
environment variable/directory aggregate families, and each individual
environment operation's `*_is_executable`, `*_is_blocked`,
`*_is_known_but_unbound` and `*_requires_runtime_binding` are static source
metadata. They do not probe pointer validity, permissions, allocation,
environment presence or whether a future syscall will succeed. A known bound
service can return an operational error. See the
[operation inventory](library-host-operation-support.md).

`PROCESS_ARGUMENT_UNAVAILABLE`/`process_argument_unavailable()` and
`ENV_READ_UNAVAILABLE`/`env_read_unavailable()` are -1. The respective
`*_result_succeeded` helpers test `>= 0`, `*_result_failed` test `< 0`, and
`*_result_is_unavailable` test equality to -1. They do not mean a requested
copy completed in full. The `*_result_is_fail_closed` helpers additionally
require the corresponding service/family to be known but unbound, so return
false for these currently bound families even when supplied -1. They are not
ordinary operational-failure predicates. `*_host_abi_is_contract_only` and
`*_requires_runtime_binding` likewise return false in this bound source state.

## Existing evidence and remaining limits

This guide audits source and existing test assertions; no fresh GPU/native run
is claimed. The following drivers compile production modules and execute
native x86_64 programs on their supported hosts. Fault cases using `strace`
depend on its availability as specified by each driver.

| Existing test | Evidence represented |
| --- | --- |
| [`stdlib_host_execution.rs::std_args_read_exact_into_executes_on_x86`](../tests/stdlib_host_execution.rs), `std_args_checked.lani` | Arguments `alpha` and empty; counts, lengths, missing/negative/extreme indices, oversized/short/null buffers, unchanged preflight sentinels, exact non-NUL output |
| [`extended_cli_execution.rs`](../tests/extended_cli_execution.rs), snapshot tests and `args_snapshot{,_empty}.lani` | Raw `0xff` argument bytes, empty arguments, inclusion of argv[0], exact count/byte limits, views, same-record repeated destroy; entry-table/byte-allocation denial and complete mmap/munmap ledgers |
| `extended_cli_execution.rs::large_argument_lists_parse_without_allocating_after_snapshot` | 4,096 and 32,768 arguments captured, then parsed without another allocation; snapshot owners released |
| [`stdlib_env_execution.rs`](../tests/stdlib_env_execution.rs), `std_env_checked`, `std_env_keys_checked` | Present/empty/missing values; exact copies and preflight sentinels; cleared two-entry environment enumeration; short/null/oversized output and invalid-index cases |
| Directory tests in `stdlib_env_execution.rs` | Real temporary cwd bytes including NUL, insufficient capacity, injected getcwd EIO; normal fixed-scratch length query and injected mmap ENOMEM returning -1 |
| [`stdlib_raw_host_width_execution.rs`](../tests/stdlib_raw_host_width_execution.rs), `raw_host_width_copy` and fixed-buffer probes | Full-width raw capacities and key identity against short finite strings; canaries and a key beside an unreadable page; malformed no-`=` environment entry; getcwd argument transport under injected error, not successful huge buffers |
| [`codegen_x86.rs`](../tests/codegen_x86.rs), process argument/exit and environment source-pack tests | Nested-helper argument calls, bounded prefix copying, invalid indices, key enumeration/lookup, directory read and immediate exit code 7 |
| [`stdlib_foundation_execution.rs`](../tests/stdlib_foundation_execution.rs), `std_process_metadata`, `std_env_metadata` | Executable assertions for capability/status constants, result classifications and exit-code helpers; current directory length on the test host |
| [`stdlib_runtime_contract.rs`](../tests/stdlib_runtime_contract.rs) | Declaration/type admission and metadata spellings; these checks alone are not native execution evidence |

Duplicate-first lookup and preservation of malformed/empty-name enumeration
follow the native thunk source; the directed checked-copy tests do not
independently model every such environment. Snapshot `HostRead` handling is
source-audited; the snapshot tests inject allocation failure, not arbitrary
mid-capture startup mutations. No concurrent mutation, broad overlapping-copy,
arbitrary raw-pointer safety or long-path recovery claim follows from these
tests.

[`codegen_wasm.rs`](../tests/codegen_wasm.rs) also has selected process and
environment import tests with a supplied Node host. Those establish that host's
import calls and supplied values, not Linux startup-stack, full-width native
pointer, syscall or owned-snapshot behavior. Host implementations and target
support must be checked separately; static source metadata is not a universal
OS/runtime availability probe.
