# Convert binary Base64 streams

`sample_programs/library/base64_bytes.lani` converts binary stdin using one of
four explicit checked Base64 profiles. Its complete CLI is
`base64_bytes encode|decode PROFILE`, or sole `--help` / `-h`.

## Build and use

With the compiler binary built, run from the repository root. The standalone
compiler invocation and both examples below have been executed successfully.

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --emit x86_64 \
  sample_programs/library/base64_bytes.lani -o target/stdlib-work/base64_bytes
printf 'foo' | target/stdlib-work/base64_bytes encode standard
printf 'Zm9v' | target/stdlib-work/base64_bytes decode standard
```

These examples produce `Zm9v` and `foo`, respectively, without a newline.
Input and output are binary; no text normalization, header, wrapping or line
terminator is added. Empty input succeeds with empty output.

## Profiles and admission

| PROFILE | Alphabet | Padding |
| --- | --- | --- |
| `standard` | Standard `+` and `/` | Required when a partial final group needs it |
| `standard-unpadded` | Standard `+` and `/` | Forbidden |
| `url` | URL-safe `-` and `_` | Required when a partial final group needs it |
| `url-unpadded` | URL-safe `-` and `_` | Forbidden |

Profile and mode names are exact and case-sensitive. Extra arguments, missing
arguments or a help flag combined with other operands are errors. Capture
admits at most two arguments and 64 total bytes, excluding trailing NULs.

Decoding is strict. Whitespace, the other alphabet, missing or unexpected
padding, impossible lengths and nonzero unused tail bits are rejected. There
is no permissive or MIME mode. Padded input must have length divisible by four;
unpadded input may have remainder zero, two or three. Correctly padded and
unpadded encodings have distinct profile names; padding is never optional
within a profile.

The application delegates length calculation, full validation and conversion
to `core::base64::encoded_len`, `decoded_len`, `encode_into` and `decode_into`.
It implements no separate Base64 codec. Each output reservation is based on
the checked required count, and the conversion must return that exact count.

## Storage, I/O and publication

CLI parsing produces plain mode/profile Options. Argument storage is destroyed
before help output or data allocation. Data mode creates one `Vec<u8>` with
capacity 1,048,576 and initializes that complete logical length with
`try_resize`. A separate used count tracks received bytes. Reads overwrite only
the initialized prefix; no push, growth or direct owner-field mutation occurs.
Even empty stdin obtains this fixed input reservation before its first read.

At most 1 MiB of input is admitted. Every actual read attempt, including an
Interrupted retry and the EOF read, spends one of 8192 attempts. When the used
count reaches the byte cap, a separate one-byte caller-backed probe must return
EOF. An extra byte returns 2; an EOF-probe host error returns 3. Reaching a cap
does not substitute for observing EOF.

After EOF, the public checked length operation runs on the used prefix. Invalid
decode input is rejected before any output allocation. Valid input gets a
separate output vector reserved and initialized to exactly the checked result
length. A zero result needs no output backing. Both vectors are disjoint and
live through conversion; their slices retain their native storage stride.
The complete input vector is destroyed before any stdout write. Output remains
owned through publication and is then explicitly destroyed on success or
failure. Every earlier failure releases all acquired owners before reporting.

| Resource | Bound |
| --- | ---: |
| Captured arguments / total bytes | 2 / 64 |
| Input bytes / fixed input capacity | 1,048,576 |
| Extra input-cap EOF probe storage | 1 logical byte |
| Read attempts, including Interrupted and EOF | 8192 |
| Output bytes / output capacity | Exact required count, at most 1,398,104 |
| Data or help stdout attempts, including Interrupted | 2048 total |
| Diagnostic stderr attempts | At most 8 |

The existing native Descriptor performs at most 1024 host bytes per transfer
using its own packed caller-backed staging. Thus the maximum encoded result
fits 1366 ordinary transfers within the output budget. The 2048-attempt counter
spans the complete chosen result, including every retry and partial transfer.
Output advances only by confirmed positive counts. Zero, invalid counts,
other errors or attempt exhaustion stop; there is no replay or rollback of a
confirmed output prefix. These attempt bounds do not impose a wall-clock
timeout on host reads or writes. Standard descriptors are borrowed and never
closed.

All input admission and conversion finish before publication. Invalid CLI,
input limits, malformed input, input I/O or conversion/allocation failure
publish no data. Output failure may leave a prefix of the complete converted
result.

## Exit statuses

| Exit | Meaning |
| ---: | --- |
| 0 | Complete conversion output, or help written |
| 2 | Invalid CLI, malformed Base64, input cap or read-attempt exhaustion |
| 3 | Input I/O or argument-capture host failure |
| 4 | Argument, input or output allocation failure |
| 5 | Data/help stdout or SIGPIPE-policy failure |
| 6 | Unexpected checked length, codec, storage or internal contract failure |

SIGPIPE is ignored before argument capture. Setup failure returns 5 silently.
Other errors attempt the exact 31-byte line
`base64_bytes: operation failed\n`, after owner cleanup, with at most eight
stderr attempts. Diagnostic failure preserves the primary status. Successful
runs have no stderr output. Help is exactly 570 bytes.

## Target and acceptance

All four registered groups passed on the first runtime attempt, totaling 194
distinct native cases. The receipt is
`target/stdlib-work/checked-base64-bytes-first.log`: four tests passed, none
filtered, in 8.85s after a 1.73s driver build.

| Accepted group | Cases | Evidence directory |
| --- | ---: | --- |
| Model | 100 | `/tmp/base64-bytes-model-k2vfzdz6` |
| Rejection | 56 | `/tmp/base64-bytes-rejection-9jhnkbb5` |
| CLI | 20 | `/tmp/base64-bytes-cli-ujcf57bj` |
| I/O | 18 | `/tmp/base64-bytes-io-6h0z30y1` |

The driver compiled through the GPU compiler, required an actual little-endian
ELF64 x86-64 executable and applied the shared strict jump gate before native
Linux x86_64 CPU execution. Existing allocator, argument, signal and Descriptor
services supplied host operations. GPU-device execution and other backends
remain unverified. The standalone build command above also succeeded, and its
two documented examples returned the exact bytes with status 0 and empty stderr.
These smoke checks overlap the registered cases and add no new case count.

Executed application source SHA-256:
`5f09b0e7c408fcd7854c4c76536b433383b2558e5215516bb09b5a11e3447799`.
Oracle SHA-256:
`675fd54af4d0ca50aeda366c5304eaa8c9513860f3b96775b85048be869063c6`.
Checked Base64 module SHA-256:
`c5eb1fc4ee603adb8f681695a3dd22885008b76d37fb70d78ce013d95b1837e8`.

The independent test-only oracle uses Python's standard Base64 byte operations,
anchored by seven literal RFC vectors. Separate alphabet, length and padding
checks admit the selected profile; re-encoding the decoded value must reproduce
the input to enforce canonical unused bits. Expected wire/plain bytes are
independently constructed, rather than tested only through application
roundtrips. Models cover every profile, all 256 byte values, tail cases,
1023/1024/1025-byte boundaries, decoding across reads and both maximum raw and
maximum encoded input. Rejections include whitespace/control/non-ASCII bytes,
opposite alphabets, padding shape, nonzero tail bits and over-cap input in both
modes. CLI cases check exact spelling/arity/help, capture bounds, non-UTF8 names
and validation before stdin.

The 4097-byte baseline trace observes two argument mappings (80 and 9 requested
bytes), both released before the fixed 1 MiB input reservation. Actual input and
EOF precede the exact 5464-byte output reservation. Input is released before
the first stdout write; output is released after the complete result. Selected
full traces match successful mapping releases by address and requested length,
including the four reached ENOMEM sites covering both argument owners, input
and output. Each allocation failure returns 4 with empty stdout and releases
every acquired mapping before reporting. Empty input obtains the fixed input
backing without output backing or stdout writes. A noncanonical decode obtains
no output reservation. No borrowed descriptor closes or other allocation
services appear in those traces.

Actual directory stdin returns 3; closed data/help stdout produces EPIPE and
returns 5. Read and write EINTR retries preserve the exact expected output.
A later read EIO and EIO on the required EOF read after all 4097 bytes publish
nothing. The output fault case completes a real first 1024-byte write, then
receives EIO on the next write: stdout contains exactly that converted prefix,
status is 5, and output backing is released before the diagnostic. No successful
transfer count is fabricated or extra application segmentation introduced.
Injected signal setup failure returns 5 silently.

Separate compact summaries observe exactly 8192 interrupted reads returning 2,
and 2048 interrupted output writes followed by one successful diagnostic,
returning 5. Those summaries establish attempt bounds, not complete release
ledgers; the selected full traces provide the separate cleanup observations.
Argument-capture host failure, positive kernel short writes and internal-error
injection were not reached. These finite cases do not establish exhaustive
failure safety, automatic lifetime enforcement, general alias safety, leak
freedom or formal correctness.

The fixture guide is `tests/fixtures/stdlib_execution/base64_bytes/README.md`;
the registered driver is `tests/stdlib_base64_bytes_execution.rs`. With a warm
build and configured GPU, reproduce the registered acceptance using:

```sh
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  env CARGO_TARGET_DIR=target/stdlib-build LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=70000 \
  cargo test --test stdlib_base64_bytes_execution -- --nocapture --test-threads=1
```

Production is entirely Lanius and introduces no compiler, ABI or host service.
It adds no Rust/Python library implementation, JSON transport, Wasm dependency
or cryptographic primitive. See the [checked Base64 plan](library-checked-base64-plan.md)
for the separate codec contract and module acceptance requirements.
