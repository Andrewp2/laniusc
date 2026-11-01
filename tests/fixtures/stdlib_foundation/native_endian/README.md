# Native numeric endian contracts

Both new runtime gates passed: **2 tests in 8.33 seconds**, recorded in
`target/stdlib-work/native-endian-contracts-final.log`. The executable target
is Linux x86_64 CPU output from the GPU compiler; device execution, other
targets and formal correctness are unclaimed.

`contracts.lani` directly executes every one of the 24 new public functions.
The fixed literal vectors contain six u64, six i16, six i32, seven i64,
seventeen binary32 and sixteen binary64 cases. Both endian orders run over
negative-stride fixed bytes and packed positive-stride bytes, at offset three
and the exact logical endpoint. Read expectations come from literal bytes;
writes independently compare every destination byte and surrounding sentinel.
This prevents a symmetric read/write mistake from passing as a roundtrip.

Signed cases include both extrema, minus one and asymmetric full-width values.
IEEE cases compare `to_bits` results, with no float equality or arithmetic:
both zero signs, signed subnormals, minimum normal, finite extrema, infinities,
and positive/negative quiet and signaling NaN payloads. Rejected float reads
must preserve the signaling-NaN fallback bits too.

Invalid logical lengths/offsets run over a null zero-length physical view and
must return fallback/false without access. Width-specific backed rejections
leave all sixteen sentinel bytes unchanged; eight-byte cases include a range
where the first u32 would fit, testing full-field admission before publishing
any prefix. Near-i32-MAX metadata must not wrap into admission.

Four distinct physical-overclaim fixtures retain valid logical ranges over
too-short actual arrays: u64 read, i64 write, binary32 read and binary64 write.
They expect native bounds exit 101. Physical overclaims violate caller
preconditions and carry no rollback promise; these are not logical rejection
tests.

The driver requires genuine x86_64 ELF output and shared jump checks. The pure
contract process must leave an empty mmap/mremap/munmap/brk trace. The old
static inventory test counts the union of its original executing producer and
this new producer, covering 36 public functions; inventory is not runtime
evidence on its own. Its separate static run passed. Existing runtime fixtures
remain unchanged, and their runtime regression is outside this receipt.

## Executed scope

The accepted run compiled and executed one pure direct-contract process and
four physical-overclaim processes. All 58 base vectors ran in both orders on
both byte layouts; all 24 additions had valid read/write cases as well as
logical rejection checks. The direct process left an empty memory-service
trace. Each physical-overclaim process exited with the expected bounds status
101, separately from logical rejection and without a rollback claim.

The initial command in `native-endian-contracts-first.log` stopped at a Rust
driver compilation error before native execution: the shared command helper
needed a mutable borrow. Root corrected only that command argument and ran
the accepted gates. No production or Lanius fixture change was needed.

Accepted Lanius source hashes (SHA-256):

| Source | Hash |
| --- | --- |
| `contracts.lani` | `2b31becf04d73dbba0f300d9e7fad8a467069b204ed2d89907bf70399da39cf8` |
| `read_u64_physical_bounds.lani` | `089f1e887a69109a5d4c2b6ac93e92c56d7f7b468ab33ebc8bff1236683031bf` |
| `write_i64_physical_bounds.lani` | `1b3b265ee20db4670eb86e843c7b936ee21292c8a974ff5b022da4cfc278d735` |
| `read_f32_physical_bounds.lani` | `5b599278240c397d6e8db7ee06e463c647c6d1a75f975b6408f1619eab80636f` |
| `write_f64_physical_bounds.lani` | `6458878a58a670c9cf8363401f77e4ce277e8e9891075096220587cf025dec03` |
| `stdlib/core/endian.lani` | `3f00b73670d1b388bd3a91efd01bd02077f7b116efdd945dd13a8bb4e165cb3a` |

The separate inventory receipt is
`target/stdlib-work/native-endian-static-inventory.log`: one static test passed
in 0.00 seconds, with the existing runtime test filtered out. It checks 36
actual public declarations against calls in the original and new producers;
it adds no runtime coverage to the two accepted native gates above.

Focused selectors (all accepted within their stated scopes):

```text
cargo test --test stdlib_native_endian_execution native_endian_literal_vectors_preserve_signed_and_ieee_bits_without_memory_services -- --exact
cargo test --test stdlib_native_endian_execution native_endian_valid_logical_extents_over_short_physical_backing_trap -- --exact
cargo test --test stdlib_endian_execution every_public_endian_function_has_a_runtime_case -- --exact
```
