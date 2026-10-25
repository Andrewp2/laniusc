# Byte paths and owned path buffers

`core::path` provides borrowed Unix paths and lexical queries. `alloc::path`
provides owned `PathBuf` values and fallible edits. `std::file::open` accepts a
borrowed Path, including `buffer.as_path()`. All implementations are Lanius.

The tested execution target is **x86_64 Linux**. These programs are compiled by
the GPU compiler and execute on the CPU. No GPU-kernel or other-platform
execution claim is made. The core algorithms require no allocation or host calls;
PathBuf requires the allocator. Filesystem operations have separate host limits
and errors, documented in [stdlib-files.md](stdlib-files.md).

## Borrowed paths

Construct with `from_bytes(bytes, count)`, `from_bytes_range(bytes, start, count)`
or `from_view(View<u8>)`. All return `Result<Path, Error>`. Negative or overflowing
logical ranges return `Bounds`; `Nul(index)` identifies the first NUL relative to
the selected range. Bytes need not be UTF-8. Empty paths are valid values.

The physical range must exist, and the backing storage must remain alive and
unchanged. Initial physical counts, view immutability and lifetimes are still
caller obligations. The compiler does not enforce these contracts. Constructing
Path or View records directly does not validate them.

Only `/` separates components. Backslash is a filename byte. There is no drive
letter, UNC-prefix, case-folding, Unicode-normalization or filesystem lookup.
`as_bytes` preserves the original offset and byte stride; `as_text` explicitly
validates UTF-8 and returns the text module's error on invalid input.

| API | Behavior |
| --- | --- |
| `byte_len`, `is_empty`, `byte_at`, `as_bytes` | Raw spelling; out-of-range byte lookup returns `None` |
| `is_absolute`, `is_relative` | Absolute iff the first byte is `/`; empty is relative |
| `has_trailing_separator` | Whether the raw spelling ends in `/` |
| `components` | Both-ended cursor over Root, Current, Parent and Normal components |
| `parent` | Remove the final component; root and empty have no parent; a lone relative component has an empty parent |
| `file_name` | Final Normal component, or `None` for root, empty, current or parent |
| `file_stem`, `extension` | Split the filename at its last dot after byte zero; absence is `None`; `a.` has an empty extension; `.a` has no extension |
| `ancestors` | Original spelling, then successive parents; includes the empty relative ancestor and stays exhausted |
| `starts_with`, `ends_with`, `strip_prefix` | Compare whole components; a partial filename never matches; strip returns `None` on mismatch |
| `compare`, `equals`, Eq, Ord, Hash | Component comparison and consistent hashing; no filesystem identity claim |

Component parsing ignores repeated separators, interior `.` and trailing
separators. An initial relative `.` remains a Current component. Every `..`
remains a Parent component. These rules follow the Unix component model in
[Rust's Path documentation](https://doc.rust-lang.org/std/path/struct.Path.html).
Parent components cannot be resolved without changing some symlink-sensitive
paths; see [Linux path resolution](https://man7.org/linux/man-pages/man7/path_resolution.7.html).

`Components.next` and `next_back` can be mixed and stay exhausted after the final
component. `remaining()` returns the borrowed source window from the first
remaining component through the last. It trims ignored material at the ends and
preserves internal spelling. Root-only windows contain one slash. `parent` and
`strip_prefix` use this same window rule. For example, stripping `/a` from
`/a//./b//c/` returns `b//c`. This window contract is explicit; it does not promise
byte-for-byte agreement with another library's remainder representation.

Comparison orders component kinds Root < Current < Parent < Normal, then compares
unsigned bytes lexicographically within each component. Shorter equal prefixes
sort first. Thus `a//./b/` equals `a/b`, while `./a/b` and `a/x/../b` are distinct.
Hashing uses the same component stream. Borrowed and owned paths execute as keys
in `alloc::hash_map`.

## Owned paths

`new`, `with_capacity`, `from_path` and `join` construct owned buffers. Except for
the empty `new`, constructors return `Result<PathBuf, Error>`. `join(base, child)`
returns a new owner. An absolute child replaces the base.

Maintain one active owner. Copying a PathBuf record aliases its allocation;
`try_clone` creates an independent copy. Call `destroy` on every exit path. It
resets the same owner, so destroying that reset owner again is harmless. A stale
record copy is not a second owner. `borrow()` retains the owner for borrowed calls.

| Operation | Contract |
| --- | --- |
| `as_path`, `byte_len`, `is_empty`, `capacity` | Borrow or inspect the owner without allocation |
| `try_push(child)` | Append a relative path, inserting `/` if needed; replace with an absolute child; an empty child adds a trailing slash to a nonempty base when needed |
| `pop()` | Remove the last component using the parent-window rule; false for root or empty |
| `try_set_file_name(bytes)` | Replace the final Normal component, or append when there is none; reject empty, `.`, `..`, slash and NUL |
| `try_set_extension(bytes)` | Require a filename; empty removes the extension and dot; other dots are literal extension bytes; reject slash and NUL |
| `try_reserve(additional)` | Reserve relative to current byte length; negative is `Bounds` |
| `try_shrink_to_fit()` | Retain contents, reduce capacity to byte length; empty releases storage |
| `clear()` | Empty contents and retain capacity |
| `try_clone()` | Independent allocation and bytes |

Filename and extension replacement drop material after the filename, including
trailing separators and ignored dot components. Setting `.a`'s extension to `txt`
produces `.a.txt`. Setting `a.tar.gz`'s extension to empty produces `a.tar`.
Setting a filename on `a/..` appends to that path and preserves its parent component.

Recoverable failures are `Bounds`, `Nul(index)`, `InvalidName`, `NoFileName`,
`CapacityOverflow` and `AllocationFailed`. Successful edits return the resulting
byte length; reserve/shrink return capacity. Every failed edit leaves contents
and capacity unchanged. Sources may borrow initialized bytes of the same owner,
including when an edit grows or replaces storage. Successful edits can invalidate
borrowed views. Read-only and lifetime requirements remain manual contracts.

Relative appends grow geometrically. Replacement builds a new buffer before
releasing the original, including edits that fit in the old capacity. Removing
an extension, pop and clear can operate without allocation. Clone is linear in
bytes; normalization is linear in input bytes and uses one output allocation.

## Explicit lexical normalization

`alloc::path::normalize_lexically(Path)` returns a new PathBuf. It collapses all
leading/repeated slashes, removes dots, resolves Normal/Parent pairs, preserves
unresolved leading relative parents and clamps absolute parents at root. An
empty relative result becomes `.`. This deliberately uses one leading slash,
including for inputs beginning with exactly two slashes.

| Input | Result |
| --- | --- |
| empty or `a/..` | `.` |
| `./a//b/../c/` | `a/c` |
| `../../a/..` | `../..` |
| `//a/../../b` | `/b` |

This is not canonicalization, existence checking or a sandbox boundary. Resolving
`..` can change what a path denotes when symlinks are involved. Ordinary Path
parsing, comparison, joins and edits never resolve parent components implicitly.

## Application

`sample_programs/library/path_join.lani` combines path buffers, borrowed paths, `ext::cli`,
owned host arguments and checked stream output:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  sample_programs/library/path_join.lani --stdlib-root stdlib --source-root extended \
  -o target/stdlib-work/path-join
target/stdlib-work/path-join --lexical base file ../tail /absolute
```

The output is `base/file`, `tail`, `/absolute`, each followed by NUL. Omitting
`--lexical` preserves dot and parent components. `--` ends options so operands
can begin with a dash. Names may contain newlines or non-UTF-8 bytes. Argument
validation completes before output; the snapshot is bounded to 1,026 arguments
and 1 MiB of argument bytes. Exit codes are 2 for arguments/limits, 3 for host I/O
and 4 for allocation. A later allocation or write failure can leave an output
prefix; all owned buffers are released.

## Audit and execution evidence

The previous `std::path` mixed a borrowed Linux byte path with helpers that treat
both slash and backslash as separators. The borrowed type moved to `core::path`;
the existing scalar/header/Windows byte-rule helpers moved intact to
`core::path_rules`, with their callers. Those helpers have runtime coverage and
were executable, not contract-only declarations or no-op stubs. Their fallback
and mixed-separator semantics remain separate from the typed Unix Path API.
The old import path was removed with repository consumers; no alias was added.

`tests/path_execution.rs` covers:

- Allocation-free borrowed operations, explicit bounds/NUL/UTF-8 errors and a
  compiler-control fixture.
- 633 pairs of boundary/generated paths compared with the Rust Unix component
  parser and an independent stack normalization model. Traversal is forward,
  reverse and mixed, including each remaining window and ancestor.
- 4,014 edits checked after every operation, including self-appends and filename
  or extension bytes borrowed from the same owner.
- Every allocation in the selected edit and application sequences denied in
  turn, unchanged owners on failure, and complete allocation cleanup.
- Application raw-byte output, option validation, every observed write failing,
  interruption retry and zero-progress writes.
- Batches of 16,384 and 262,144 appends, geometric growth, and complete release.
- Borrowed and owned path keys in hash maps, including replacement ownership.

Run the seven focused execution groups from the repository root:

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test path_execution -- --nocapture
```

The target directory must be absolute so shader artifacts resolve correctly.
The large native workload has a 10-second process deadline; small processes use
the existing short timeout. Every outer command remains below two minutes.

The focused legacy path and owned-file suites also execute after migration.
Checksum CLI/configuration and configuration file-loading tests execute through
the migrated path type, including allocation and host failures.
Loader/type-check tests supplement this evidence; they do not establish runtime
support. Metadata, directory enumeration, walking, seek and durable file syncing
remain host-runtime dependencies. The direct malformed View construction case
is recorded in [library-dependencies.md](library-dependencies.md).

## Native workload measurements

On the Ryzen 9 5950X, pinned to CPU 8, five alternating measured runs after one
warm-up gave the following whole-process medians. Each run builds a path by
repeated appends, normalizes it, validates the result and releases both owners.
Compilation and tracing are excluded. These measurements describe this workload,
not a comparison against another language or compiler.

| Append operations | Normal names | Repeated `a/..` cancellation |
| --- | ---: | ---: |
| 16,384 | 26.551 ms | 28.576 ms |
| 262,144 | 414.993 ms | 450.605 ms |

The 262,144-case ranges were 389.985–495.543 ms and 443.180–542.809 ms respectively.
Separate syscall-traced runs verify at most 24 total allocation calls at either
size and complete release. The fixture is
`tests/fixtures/stdlib_foundation/path_batch.lani`; arguments are COUNT MODE,
where mode 0 appends normal names and mode 1 appends `a/..` groups.
