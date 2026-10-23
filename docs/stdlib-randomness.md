# Random generation and OS entropy

`core::random` provides deterministic **non-cryptographic** generation and generic
sampling. `std::entropy` obtains bytes from the operating system and preserves
host errors. Seeding a deterministic generator from the OS does not make that
generator suitable for secrets; use the entropy source directly for those.

Both modules execute on **x86_64 Linux using the GPU compiler**. The core module
uses portable Lanius operations and no allocation or host services. Other targets,
including GPU execution of user programs, have not been established by these
tests. The entropy module requires the existing Linux getrandom binding.

## Deterministic generator

`from_seed(seed: u64)` constructs `Xoshiro256PlusPlus` using xoshiro256++ 1.0.
Four successive SplitMix64 outputs, starting with the supplied seed as its
cursor, initialize the four state words. Every seed, including zero, is valid.
The transition, seed expansion and fixed jump polynomials follow the authors'
public-domain [xoshiro256++](https://prng.di.unimi.it/xoshiro256plusplus.c) and
[SplitMix64](https://prng.di.unimi.it/splitmix.c) implementations.

| API | Behavior |
| --- | --- |
| `from_state(State)` | Return `Result<Xoshiro256PlusPlus, Error>`; reject the all-zero state |
| `borrow()` | Borrow the mutable generator for generic sampling |
| `snapshot()` | Copy the four u64 state words without advancing |
| `next_u64()` | Advance once and return the complete output word |
| `next_u32()` | Advance once and return its upper 32 bits |
| `jump()` | Advance the state by 2^128 generator steps |
| `long_jump()` | Advance the state by 2^192 generator steps |

All arithmetic in the transition wraps modulo 2^64. A copied generator has an
independent copy of the state; advancing it does not advance the original.
State restoration resumes the sequence exactly. Use factories and keep the
state nonzero: direct field writes can violate the invariant, and the language
does not enforce field privacy. There is no shared global generator or implicit
seed. Borrowing does not provide synchronization for concurrent access.

This algorithm name, version and seed mapping identify the sequence. Replacing
the algorithm requires a new explicit choice rather than silently changing
reproducible output. Arbitrary-distance jumps and encoded state files are not
provided. The fixed jumps take 256 transition steps each and allocate nothing.

## Generic sampling

`Source64` defines `draw(&self) -> Result<u64, Error>`. Both the deterministic
generator and `std::entropy::OsRandom` implement it. Applications can supply
their own source, including scripted sources for tests. Each successful draw
must supply a uniform 64-bit word for the uniformity claims below to hold.

| Function | Result and consumption |
| --- | --- |
| `below(source, bound)` | `[0, bound)`; zero bound is InvalidBound, one returns zero without a draw |
| `inclusive_u64(source, low, high)` | Both endpoints included; reversed bounds are InvalidRange |
| `inclusive_i64(source, low, high)` | Signed counterpart, including i64::MIN and i64::MAX |
| `boolean(source)` | One draw; use the highest bit |
| `unit_f32(source)` | One draw; highest 24 bits divided by 2^24 |
| `unit_f64(source)` | One draw; highest 53 bits divided by 2^53 |
| `fill(source, bytes, offset, count)` | Fill count bytes; return the byte count or Failure |
| `shuffle(source, View<T>)` | Mutate a permutation in place; return completed suffix steps or Failure |
| `choose(source, View<T>)` | `Result<Option<T>, Error>`; empty input returns None without drawing |

The scalar functions return `Result<value, Error>`. Singleton intervals and
singleton choice consume no random word. Full-width integer intervals consume
one word. Other integer ranges use rejection sampling: discard words below
`2^64 mod bound`, then reduce modulo bound. This removes modulo bias. A draw can
be rejected repeatedly; there is no fixed retry cap. An unsuitable custom source
can therefore run indefinitely. Source errors propagate immediately, including
after rejected words. Source state and host reads are never rolled back.

Floating results occupy fixed equally spaced grids in `[0, 1)`; one is never
returned. This is not a distribution over every representable floating value.
The signed sampler maps signed order to unsigned order by flipping the sign bit,
then uses the same bounded sampler. Negative-to-positive and full-width ranges
do not overflow a signed subtraction.

### Bytes, permutations and ownership

`fill` emits a word's bytes in little-endian order. It consumes `ceil(count / 8)`
words on success and discards unused bytes of the final word. Two short fills
can therefore consume a different sequence from one combined fill. A failed draw
does not write any bytes for that word. Earlier complete word prefixes remain;
`Failure.completed` counts those bytes. Zero count succeeds without drawing.

Negative offsets/counts and an overflowing `offset + count` return Bounds before
accessing the source or destination. The caller must physically back the claimed
range: the compiler still lacks slice-length projection. Indexed stores honor
the byte slice's stride, including native arrays and packed storage.

Shuffle uses descending Fisher–Yates steps, choosing a position in the remaining
prefix and swapping it with that prefix's last element. The expected number of
draws is O(n), and storage is O(1). It touches only the selected view. Empty and
singleton views require no draw. On success it returns `max(n - 1, 0)`, counting
self-swaps. On error, completed suffix steps remain a permutation; the failed
step performs no swap. `Failure.completed` counts steps, not random draws.

`choose` returns a shallow copy of the selected T. It neither clones an owned
resource nor transfers ownership out of the view. Keep the backing owner alive,
and follow the element's ownership contract. Shuffling moves existing values
without destroying or duplicating their nested resources. The source must not
alias or mutate the destination storage during sampling. Views must satisfy
their documented backing and lifetime preconditions.

## OS entropy

`std::entropy::fill(bytes, offset, count)` returns the number of bytes copied or
`core::random::Failure { cause, completed }`. It uses packed stack staging to
support both native strided arrays and packed byte buffers. Requests are at most
256 bytes, use flags zero, retry EINTR and continue after short reads.
The Linux [getrandom contract](https://man7.org/linux/man-pages/man2/getrandom.2.html)
allows waiting for initialization; this API has no nonblocking or cancellation
option. It allocates no memory and opens no file descriptor.

| Error | Meaning |
| --- | --- |
| `Bounds` | Invalid signed offset/count or overflowing sum; no host call |
| `Host(errno)` | Positive Linux error number, preserving the cause |
| `NoProgress` | A nonempty request returned zero |
| `InvalidCount` | The host reported more bytes than requested |
| `ZeroState` | Seeding a generator produced four zero state words |

Each successful host read is copied before the next request. Failure reports
the exact copied prefix; bytes after it remain unchanged. A zero-length fill
returns zero without contacting the host. Physical backing remains the caller's
precondition, as for the core fill function.

`secure_u64()` fills eight bytes and decodes them little endian. All u64 values,
including zero, are valid successful results. `os_random()` returns an OsRandom
handle whose Source64 draw calls secure_u64. The generic samplers can use this
handle directly and preserve its errors.

`seeded()` fills 32 bytes, decodes four little-endian words and validates the
state. It returns a non-cryptographic Xoshiro256PlusPlus generator or an error.
It never substitutes a fixed seed, and an all-zero state returns ZeroState
without retrying. The internal partial bytes of secure_u64/seeded are discarded
on failure; their return type carries the error without a progress count.

## Example: shuffle lines

[`sample_programs/shuffle_lines.lani`](../sample_programs/shuffle_lines.lani)
combines CLI parsing, owned byte input, borrowed row views, a vector, sampling,
entropy and partial-write handling. It shuffles LF-delimited byte records from
stdin and emits a selected prefix. With the compiler already built:

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc sample_programs/shuffle_lines.lani --stdlib-root stdlib --source-root extended -o target/stdlib-work/shuffle-lines
printf 'red\ngreen\nblue\n' | timeout 5s target/stdlib-work/shuffle-lines --seed 42 --count 2
```

- `-s/--seed U64`: reproducible seed; without it, acquire 32 OS bytes once.
- `-n/--count N`: nonnegative output count, capped at the number of input rows.
- `--max-bytes N`, `--max-lines N`: defaults 1,048,576 and 65,536.
- `-h/--help`: print usage after validating all arguments; operands are rejected.

Repeated options use the last value. Every output record ends with LF. Empty
input has zero records; a final input LF does not add a record. CR, NUL and invalid
UTF-8 bytes remain part of their record. An unterminated final record is retained.
For a fixed seed, changing the count selects a prefix of the same permutation.
Zero output count and inputs with fewer than two rows require no entropy.

The application reads and validates all input even when count is zero. It keeps
one input owner and a vector of borrowed row views; owners are destroyed on
success and error. Exit status is 2 for arguments/limits, 3 for I/O/entropy and
4 for allocation failure. Input limits can consume a read chunk beyond the
accepted limit; output failure can leave a written prefix. There is no streaming
or reservoir-sampling claim.

## Execution evidence

`tests/randomness_execution.rs` compiles the real Lanius modules and runs native
executables. Its six groups cover:

- Author-derived vectors for six seeds, raw draws, jump/long-jump and state
  restoration; [vector provenance](../tests/fixtures/stdlib_foundation/random_vectors.md).
- 80 deterministic runs with 19,456 raw/mixed outputs and final state comparisons.
  Mixed sampling includes a rejection-heavy bound, signed ranges, floats and bytes.
- Scripted rejected draws and failures, exact error/progress values, integer and
  float endpoints, untouched guards, all six three-element permutations, records,
  zero-sized elements and nested `Option<bool>` values.
- Large batches at 0, 1, 4,096, 65,536 and 1,048,576 elements, compared with a model
  including final state. No allocation is permitted for generation/sampling;
  shuffle gets only its fixture's initial vector allocation, which is released.
- Native and packed entropy destinations, exact comparison with kernel-traced
  bytes, short/zero/impossible reads, EINTR, errno preservation, partial progress,
  all-zero state rejection and absence of host calls for empty/invalid operations.
- 96 fixed and 64 generated binary-record application cases, limits, allocation
  failures, every observed input/output/entropy failure, retries and cleanup.

All six groups passed on 2026-10-23 in 16.11 seconds. Run the focused suite from
the repository root:

```sh
timeout --kill-after=2s 100s env CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 cargo test --locked --test randomness_execution -- --nocapture
```

Native performance on a Ryzen 9 5950X, pinned to CPU 8, on 2026-10-23:

| Workload | Small batch: median CPU time | Large batch: median CPU time |
| --- | --- | --- |
| Direct u64 draws | 65,536: 3.152 ms | 1,048,576: 45.565 ms |
| Sampling below 2^63 + 1 | 65,536: 13.394 ms | 1,048,576: 198.914 ms |
| Shuffle u64 values | 4,096: 1.138 ms | 65,536: 14.220 ms |

These are whole native-process times for `random_batch.lani`, including a checksum,
final state output, and vector construction/destruction in shuffle mode. Each
size had one warm-up and nine alternating measured runs, seed
`1311768467463790320`. Mode 0 generates words, mode 1 samples the stated bound,
and mode 2 shuffles. The executable accepts seed, mode and count as its arguments.
Compiler startup, GPU compilation and strace are excluded. The sampling workload
rejects about half its draws. Its large-batch observations ranged from 181.547
to 235.032 ms; these timings are evidence for this machine, not performance gates
or a comparison with another compiler.

## Existing API audit and remaining work

| Existing surface | Classification and boundary |
| --- | --- |
| `std::random::fill_secure_bytes` | Executable native binding; raw pointer/count, partial count or negative errno |
| `std::random::secure_u32` | Executable native binding; traps on a short read or host error |
| `std::random` capability helpers | Metadata about the binding, not a live probe of host success |
| `std::random_checked` | Executable legacy helpers; bool/fallback failures discard cause and progress |
| `std::random_wide` | Executable legacy two-word values; Option discards the error cause |
| New `core::random`, `std::entropy` | Executable functions with explicit errors; no contract-only or silent no-op entries |

The new native-width APIs are the application-facing direction. Consolidating
old checked/two-word consumers remains work; raw external declarations retain
their compiler-bound identity. No compatibility forwarding modules were added.
Additional distributions, weighted selection, reservoir sampling and other
targets remain unimplemented.

The batch fixture exposed a separate
[nested factory inference limitation](../tests/fixtures/stdlib_foundation/vec_inference_dependency/README.md).
An explicit generic argument or a typed intermediate Result executes correctly.
It does not require reducing the randomness API. Slice backing and manual
ownership prerequisites remain in [library-dependencies.md](library-dependencies.md).
