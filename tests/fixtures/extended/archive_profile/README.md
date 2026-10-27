# Archive metadata profile fixtures

`probe.lani` consumes independently assembled archives and calls the real
`ext::archive_profile` functions. `tests/extended_archive_profile_execution.rs`
constructs classic ZIP and ustar records using CPU byte encoders, independent
of the Lanius archive writers. No CRC/DEFLATE implementation is added: ZIP
fixtures use empty payloads, the known CRC of one zero byte, and the fixed
two-byte empty DEFLATE stream where needed.

All four native groups passed in 5.95 seconds on x86_64 Linux, recorded in
`target/stdlib-work/archive-profile-grammar-retry.log`. The separately accepted
driver build took 1.29 seconds (`archive-profile-driver-build.log`); it adds no
runtime classifications. Production and probe remain frozen at SHA-256:

- Production: `daadf0cd6fa70bec7474ef8efadff1b5f24f33f8690c0395ed0dbf25df48df91`.
- Probe source: `f34634342d57b45ef0ad94c05876bcbc5758f224bda7e19822cb92f065dcf3b3`.

The first gate, `target/stdlib-work/archive-profile-first.log`, stopped in
parsing before native execution: Lanius requires `else { if ... }`, rather than
`else if`. The source/probe spelling was corrected without changing masks,
extra shapes or expected results. The Rust fixture driver was unchanged. Those
four pre-native failures in 4.51 seconds add no runtime cases.

| Rust filter | Passed classifications | Boundary |
| --- | ---: | --- |
| `tar_profile_uses_canonical_kinds_and_never_directory_size_as_data` | 18 | Every accepted TAR kind including NUL regular; directory hint, kind versus spelling, direct invalid views/data. |
| `zip_profile_checks_creator_types_attribute_bits_and_zero_size_directories` | 84 | Both creators, low producer-version byte, every one-hot DOS bit, Unix modes/reserved fields, positive directory hint, directory decoded size and separate path policy. |
| `zip_profile_allowlists_and_validates_both_extra_header_shapes` | 108 | All four allowed IDs independently in both headers, all timestamp flag combinations, UID widths, Unicode alternatives/UTF-8/version errors, unsupported/duplicate fields and maximum extras. |
| `profile_public_entries_check_bounds_and_support_strided_metadata` | 12 | Post-parse direct Entry mutations: invalid views, raw version/size fields, extra caps and actual strided stack extras. |

These are **222 accepted classifications** batched into four native probe
invocations, not 222 processes. The first two groups additionally traced
selected filesystem lookup/mutation/metadata syscalls and observed none from
the probe. No fixture performed filesystem extraction; other target profiles
and GPU-kernel execution remain untested here.

Each input record is `format:u8, mutation:u8, reserved:u16(0), length:u32`, then
archive bytes; integer headers are little endian. Format 1 selects TAR, 2 ZIP.
One output byte reports File 0, Directory 1, or profile errors 10–16 in public
enum order. Canonical parse failure is 98, never an expected profile rejection.
Every unmutated fixture must first pass the full canonical parser (TAR through
its complete footer); entries are borrowed only while the input owner lives.

Mutations are labelled test-only direct-entry controls after successful parse;
they do not claim that the canonical parser emits invalid fields. The profile
retains logical View/size/cap checks for such public Entry values. The input
buffer is bounded at 1 MiB and explicitly destroyed. Test process timeouts are
20 seconds after compilation. No fixture performs filesystem extraction.
