# Archive extraction metadata profile

`ext::archive_profile` classifies parsed TAR and ZIP entries as File or
Directory for content-only extraction. It allocates nothing, performs no host
I/O and changes no archive bytes. Four focused groups passed on native x86_64
Linux: **222 classifications in four probe processes**. This module alone does
not extract an archive or certify a destination path.

```lanius
pub enum Kind { File, Directory }
pub enum Error {
    UnsupportedCreator, UnsupportedType, ContradictoryType,
    UnsupportedExtra, MalformedExtra, DirectoryData, Bounds
}
pub fn tar_kind(entry: ext::tar::Entry) -> Result<Kind,Error>;
pub fn zip_kind(entry: ext::zip::Entry) -> Result<Kind,Error>;
```

Consume the canonical parser first. Logical View bounds are checked before
reading metadata; physical backing must remain valid and unchanged. The
extraction planner must separately validate/copy the raw destination path,
bound total work and decide filesystem ownership. No successful classification
certifies payload integrity: use the existing ZIP extraction checks for length,
DEFLATE and CRC, including zero-decoded-byte directories.

## TAR

Only canonical Regular and Directory kinds are supported. Links, devices,
FIFO and Contiguous are UnsupportedType. Classification uses kind rather than
filename spelling; a Regular name ending in `/` is still File here and will be
rejected by the separate path policy. Directory data must be empty. Its size
field remains an ignored hint in the existing ustar reader, never a request to
read or allocate data. Permissions, owners, timestamps and device metadata are
ignored.

## ZIP types

The raw `Entry.version_made_by` must fit u16. Only creator hosts DOS 0 and Unix 3
are supported; the software version in its low byte is informational. APPNOTE
makes the attribute representation depend on that creator. See
[PKWARE APPNOTE 6.3.10, sections 4.4.2 and 4.4.15](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT).

| Creator | Allowed external-attribute mask | Type policy |
| --- | --- | --- |
| DOS 0 | `0x00000037` | Accept read-only, hidden, system, directory and archive bits; reject every other or high bit. |
| Unix 3 | `0xffff0037` | Same low DOS hints; interpret the high word as Unix mode. Ignore its permissions; require type zero, regular `0x8000` or directory `0x4000`. Reject other types. |

A terminal `/` supplies directory form. A set DOS directory bit must agree;
a clear bit makes no regular-file assertion, including all-zero attributes.
An explicit Unix regular/directory type must agree with name form. An empty
name is ContradictoryType. Directories require zero uncompressed size; an
encoded empty DEFLATE stream can have nonzero compressed size.

The Unix high-word convention follows the originating implementation's
[Info-ZIP `unix.c` attribute adapter](https://raw.githubusercontent.com/madler/unzip/master/unix/unix.c).
The selected DOS bits correspond to the ordinary
[Microsoft file-attribute constants](https://learn.microsoft.com/en-us/windows/win32/fileio/file-attribute-constants).
This is an explicit restricted profile, not a claim to support every creator's
attribute convention. It never applies archive permission bits to a host file.

## Ignored extra fields

Both local and central extras are checked independently, each capped at the
canonical 65,535 bytes. Framing must fit exactly. A four-bit seen mask rejects
duplicate allowed IDs within one header in linear time; the same ID may appear
once in each header. Unknown IDs or versions are UnsupportedExtra; truncated
framing, invalid shapes, reserved timestamp flags or invalid UTF-8 are
MalformedExtra.

| ID | Accepted shape after the four-byte field header |
| --- | --- |
| `0x5455` timestamp | Flags only in bits 0–2. Local length is `1 + 4*popcount(flags)`; central length is `1 + 4*(flags & 1)`. Central access/creation flags refer to local metadata, not additional central timestamps. |
| `0x7875` UID/GID | Version 1, positive one-byte UID and GID lengths, and exactly `3 + uid_length + gid_length` bytes. Values remain opaque; widths up to 255 are accepted. |
| `0x7075` Unicode path | Version 1, four opaque CRC bytes, then valid UTF-8; total length at least five. |
| `0x6375` Unicode comment | Same shape as Unicode path. |

Timestamp/UID layouts follow the originating
[Info-ZIP extra-field reference](https://raw.githubusercontent.com/madler/unzip/master/proginfo/extrafld.txt).
These are discarded metadata, with no cross-header value reconciliation or
restoration. The small allowlist excludes old Unix IDs `0x5855`/`0x7855`, NTFS
timestamps `0x000a` and all other IDs. It explicitly excludes type/link/device
extensions `0x000d` and `0x756e`.

Unicode alternatives never replace the canonical name or comment. Their CRC
bytes are deliberately opaque: no CRC calculation or alternate-name selection
occurs, even for matching CRC or alternative text such as `../other/`.
The UTF-8/version framing follows
[APPNOTE sections 4.6.8–4.6.9](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT).

The canonical TAR/ZIP byte APIs retain their existing acceptance. This stricter
adapter can reject an entry they preserve. Filesystem path policy, total-work
charging, safe publication and cleanup belong to the separate
[extraction workflow](library-archive-extraction-plan.md).

## Executable acceptance

The [fixture guide](../tests/fixtures/extended/archive_profile/README.md) lists
the accepted groups: TAR kinds (18), ZIP creator/attribute policy (84),
local/central extra shapes (108) and direct-entry bounds/strided metadata (12).
`target/stdlib-work/archive-profile-grammar-retry.log` records all four tests
passing in 5.95 seconds. Archives are independently assembled in the Rust
driver; the probe first consumes the canonical parser, so parser rejection
cannot masquerade as a profile error. The TAR and ZIP type groups also
observed no selected filesystem lookup/mutation/metadata calls under strace.

The frozen production SHA-256 is
`daadf0cd6fa70bec7474ef8efadff1b5f24f33f8690c0395ed0dbf25df48df91`;
the probe source SHA-256 is
`f34634342d57b45ef0ad94c05876bcbc5758f224bda7e19822cb92f065dcf3b3`.
The test-driver build passed separately in 1.29 seconds, recorded in
`archive-profile-driver-build.log`; that build adds no runtime cases.

The first gate, `archive-profile-first.log`, rejected unsupported `else if`
spelling before any native execution. Its four test failures in 4.51 seconds
are not runtime failures or accepted cases. Production/probe branches were
rewritten using supported syntax; masks, extra shapes and the Rust driver's
expected decisions stayed unchanged for the successful retry.

These finite host receipts do not establish filesystem extraction, all archive
variants, GPU-kernel execution or other target acceptance.
