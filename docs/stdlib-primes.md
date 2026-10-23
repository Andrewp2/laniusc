# Prime sieve program

`sample_programs/library/primes.lani` is a real Eratosthenes sieve using
[`alloc::bitset`](stdlib-bitset-owned.md), CLI parsing, integer parsing and
formatting, counted byte views and checked native stream writes. All program
behavior is implemented in Lanius.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc \
  --stdlib-root stdlib --source-root extended \
  sample_programs/library/primes.lani -o target/stdlib-work/primes
target/stdlib-work/primes 1000000
# 78498
target/stdlib-work/primes --list 20
# 2, 3, 5, 7, 11, 13, 17, 19, one per line
```

## Interface and failure behavior

```text
primes [-l|--list] [--max-output-bytes N] LIMIT
```

`LIMIT` is an inclusive unsigned decimal bound from 0 through 20,000,000.
There must be exactly one operand. The default output is the decimal prime
count followed by LF. `--list`/`-l` instead writes each prime followed by LF;
bounds 0 and 1 produce an empty listing. `--help`/`-h` prints usage without
requiring an operand. Options may appear before or after the operand; `--`
ends option parsing. Repeated flags are harmless and the last supplied output
limit wins. Invalid options, operands or option values still fail when help
is requested. There is no stdin input.

`--max-output-bytes` defaults to 16,777,216 and accepts 0 through 67,108,864.
The program measures the entire result before its first stdout write. An
output limit failure therefore produces no stdout, including when a listing
would fit initially but exceed the limit later. Listing measurement and
delivery each traverse the unchanged bitset with an allocation-free cursor.
Each number is formatted into a fixed stack buffer; there is no allocation
per prime or output-sized staging buffer.

Argument capture allows at most 16 tokens and 4,096 total argument bytes after
the program name. All allocated argument and bitset owners are released on
normal completion and returned failures. I/O errors can leave a written
prefix; interrupted writes are retried and positive short writes resume at
the first unreported byte. Failure diagnostics go to stderr with LF.

| Exit | Meaning |
| --- | --- |
| 0 | Successful count, listing or help |
| 2 | Invalid arguments, argument limits or output limit |
| 3 | Host argument-read/write failure, including a failed diagnostic write |
| 4 | Argument or bitset allocation failure |

The sieve begins marking at `p*p`, because smaller multiples already have a
smaller prime factor; the loop condition uses `p <= LIMIT/p` to avoid square
overflow. This follows the [NIST description of Eratosthenes' sieve](https://xlinux.nist.gov/dads/HTML/sieve.html).
It retains one bit per candidate, rounded into native typed `u32` words.
Current native typed words occupy eight-byte slots, so physical storage is
larger than an external packed `u32` representation. This is a whole-range
sieve; segmented sieving and arbitrary-size inputs are separate algorithms.

## Executable evidence

`tests/stdlib_primes_execution.rs` compiles the real program with the GPU
compiler and executes the resulting x86_64 Linux ELF. Three test groups pass:

- Trial-division comparison for small, generated, word-boundary and square
  inputs, including a complete listing through 10,000; exact output capacity
  and one-byte-short limits; raw invalid arguments, help and argument caps.
- Large counts at 1,000,000 and the supported maximum 20,000,000, checking
  78,498 and 1,270,607 primes respectively.
- Individual failure of every observed baseline allocation and stdout write,
  with mapping-release checks; interrupted, zero and positive short writes;
  `/dev/full`, failed diagnostics and a check that successful execution never
  reads stdin.

An observed native run took 413.142 ms at one million and 7,443.822 ms at
twenty million. These timings include process setup and output, exclude
compilation, and are observations under uncontrolled desktop activity. They
do not compare against an optimized sieve or establish user GPU execution.

```sh
timeout --kill-after=2s 100s env \
  CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 \
  CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 \
  LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 \
  cargo test --test stdlib_primes_execution -- --test-threads=1 --nocapture
```

The verified target is x86_64 Linux output from GPU compilation. No Wasm,
user-kernel execution or other host ABI support is claimed.
