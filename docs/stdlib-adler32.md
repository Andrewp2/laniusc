# Adler-32 checksums

`core::adler32` implements the byte checksum defined in
[RFC 1950 sections 2.2 and 8.2](https://www.rfc-editor.org/rfc/rfc1950.html#section-2.2).
It is used by the [zlib container](extended-compression.md). The implementation
is Lanius, has no host dependency and allocates nothing.

| API | Behavior |
| --- | --- |
| `INITIAL: u32 = 1` | State for an empty input |
| `MODULUS: u32 = 65521` | Reduction modulus |
| `valid_state(state: u32) -> bool` | Both 16-bit sums are below the modulus |
| `update_byte(state: u32, value: u8)` | Checked single-byte update |
| `update(state: u32, bytes: View<u8>)` | Checked update over a borrowed byte view |
| `checksum(bytes: View<u8>)` | Update starting from `INITIAL` |

The three fallible functions return `Result<u32, Error>`. There is no final XOR
or separate finish step: the returned state is already the checksum. Empty
input returns the unchanged valid state. Starting with 1, `Wikipedia` produces
`0x11e60398`. Updating a state with A and then B equals updating it with their
concatenation. Serialization byte order is the container caller's responsibility.

The low 16 bits hold the first sum and the high 16 bits hold the second. Bulk
update reduces them after at most 5,552 bytes. From the maximum valid initial
sums and all bytes equal to 255, the unreduced second sum is at most
4,294,690,200, which fits `u32`; one more byte can exceed that type. Single-byte
updates reduce both sums immediately. Work is linear in input bytes and uses
constant local storage.

`Error::Bounds` means a negative logical start/length or an overflowing logical
end. `Error::InvalidState` means either 16-bit sum is outside its canonical
range. Update validates metadata before state, and neither failure reads input.
Arbitrary noncanonical `u32` states are rejected rather than normalized.

Views can select nonzero offsets from packed buffers or native strided arrays.
Backing storage must cover the claimed elements and remain alive and unchanged
for the call. Metadata checks cannot verify physical lengths or pointers; the
language does not enforce these lifetime and read-only contracts. No bytes are
modified and no view is retained.

## Executable evidence

`tests/stdlib_adler32_execution.rs` has two native execution groups:

- A direct contract fixture covers constants, a known checksum, zero bytes,
  native strides, offset windows, invalid states and metadata, split updates,
  and repeated maximum byte values across the 5,552-byte reduction boundary.
  Its process runs with every allocation denied and makes no allocation or
  deallocation syscall. The maximum-state addition passed separately in 4.07s.
- Sixty whole-input/split-update cases compare against Python's zlib, using
  initial states 0, 1 and `0xfff0fff0`, every byte, patterned and all-255 inputs,
  reduction boundaries and data through 1 MiB. Python supplies reference
  checksums only; the production library is Lanius.

Both groups passed together in 7.98s before the added maximum-state fixture
case. Execution is verified on **x86_64 Linux**. GPU-kernel execution and other
targets have not been established. Container/application runtime performance
is recorded in [compression performance](extended-compression-performance.md).

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --locked --test stdlib_adler32_execution -- --nocapture
```
