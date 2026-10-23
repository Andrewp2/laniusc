# Collection consumer migration

The repository now uses `alloc::hash_map`, `alloc::tree_map`, `alloc::hash_set`,
`alloc::tree_set`, `alloc::vec`, and `alloc::string` for the consumers of the removed `std::map`, `std::set`, `std::vec_u8`, and
`std::utf8_vec` modules. Their fallible edits return explicit `Result` errors.
The old owner-returning APIs could return an unchanged owner or an empty result
when allocation failed, making failure look like success. They have no aliases.

The removed finite specializations are `std::map_bool_u32`,
`std::map_i8_u32`, `std::map_u8_u32`, `std::set_bool`, `std::set_i8`, and
`std::set_u8`. The caller audit found only repository examples and tests for
these ten modules, plus the old text module's dependency on its byte vector.
No production library or formal source imports them. There is no external
compatibility commitment to maintain.

## Consumer choices

| Consumers | Current representation and contract |
| --- | --- |
| `unsigned_frequency_report` | `HashMap<u32, u32>`; checked insertion also replaces existing counts |
| `unicode_frequency_report` | Checked hash map for counts and checked vector for first-seen keys; report order stays deterministic |
| `wide_unsigned_frequency_report`, `wide_signed_frequency_report` | Checked tree map plus a checked vector for first-seen order; wide records provide `Eq` and `Ord` |
| `unique_unsigned_total`, `unique_unicode_count` | Checked `HashSet<u32>` / `HashSet<char>` membership |
| `wide_unsigned_distinct_sum`, `wide_signed_distinct_sum` | Checked `TreeSet<WideU64>` / `TreeSet<WideI64>` membership; sums update only after successful first insertion |
| `count_digit_bytes` | Two checked scalar counters; the Boolean domain needs no container |
| `count_distinct_bytes` | Caller-owned 256-element Boolean table |
| `byte_frequency_report`, `signed_byte_frequency_report` | Caller-owned 256-element count table; ascending scans preserve smallest-key tie breaking |
| `vector_byte_checksum` | Checked packed `alloc::vec::Vec<u8>` |
| `utf8_owned_line`, `utf8_text_report` | Checked packed `alloc::string::String`, with borrowed `[u8]` output views |
| `alloc_string_edits` fixture | Checked vector and hash map of borrowed string handles; replacement returns the old entry |
| `comparison_collections` fixture | Vector, tree map, and hash map test lawful total float keys; redundant legacy set checks are removed |
| `collection_byte_histogram` fixture | Checked hash map and iterator retain distinct counts and saturating weighted sum coverage |

A hash map does not promise insertion order. The Unicode and wide frequency
programs own a separate order vector because first-seen output is part of those programs'
behavior. If either owner cannot grow, both are destroyed and the program
returns an error before printing a partial report. The byte-domain programs
need no allocation and still reject I/O errors and overflowing counters.

Container copies remain shallow. The string-key fixture keeps its original
string owners alive while the containers borrow their handles, then destroys
the containers before destroying those strings. Map replacement returns the
previous entry; callers must account for any resources nested in that entry.

## Verification and retired tests

`tests/stdlib_legacy_collection_migration_execution.rs` compiles native x86_64
Linux programs with the GPU compiler and explicit `stdlib` and `extended`
source roots. It checks:

- All 15 migrated examples, plus the histogram and affected string/comparison
  fixtures, against their visible results.
- Empty input, repeated keys, all 256 byte values, signed-byte ordering and tie
  breaking, NUL, multibyte Unicode, malformed UTF-8, and 64-bit boundary values.
- First-seen frequency order, distinct-value identity, and wrapping wide sums.
- Every reached allocation in representative successful workloads: deny that
  `mmap` and all later allocations, require a documented nonzero error, and
  require no report output.
- Successful, invalid-input, output-failure, and allocation-failure cleanup:
  every successful allocation must have one successful `munmap` with the same
  address and size. The bounded byte examples must make zero allocations.

The old module-specific fixtures and tests are removed with their APIs. Public
function call counts were source-shape checks. The old insertion-order map and
set-algebra model suites tested contracts of deleted types. Their retention
would require keeping the unwanted APIs. The working owners retain their own
runtime suites: `stdlib_hash_map_execution` covers collisions, a 1,024-step
reference model, generic payloads, replacement, clone and allocation failure;
`stdlib_alloc_vec_execution`, `stdlib_string_execution`, and
`stdlib_text_execution` cover typed storage, edits, UTF-8 validation, aliases,
and failure preservation. Core borrowed UTF-8 tests remain in
`stdlib_utf8_bytes_execution`. The new suite adds the migrated application
contracts and cleanup checks across both owners in each report.

## Remaining boundary

[Generic owned sets](stdlib-owned-sets.md) now provide checked membership,
representative retention/replacement, clone and all four algebra operations.
They share the existing map storage engines through a nongeneric owner-state
boundary. Their independent model and allocation-failure tests establish these
new contracts; the removed legacy suites are not their evidence. The earlier
nested generic wrapper failure remains recorded as a compiler source-shape
dependency, without blocking these working APIs.
Wide integer records implement `Eq` and `Ord` but do not implement `Hash`, so
those consumers use the checked tree set rather than adding an implicit hash
policy at the call site.

`std::vec` remains because the formal extractor recognizes that module identity
and `alloc::binary_heap` still has a documented compiler dependency on it.
The retained vector's failure contract and general generic adapter composition
remain separate work. This migration does not change compiler, runtime, ABI,
IR, shaders, or proofs.
