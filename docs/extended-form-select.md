# Bounded form selection

`sample_programs/library/form_select.lani` reads a raw URL-encoded form from
stdin and writes every field whose decoded name equals its single argument.
Duplicate matches retain their input order. Output is canonical form encoding,
without a final newline; no matches produce empty output. All errors are quiet.

## Build and examples

From the repository root with the compiler binary built:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/form_select.lani \
  -o target/stdlib-work/form_select
```

```sh
printf '%s' 'tag=red&name=Jo+Smith&tag=blue+sky&tag=a%2Bb' | \
  timeout --kill-after=2s 10s target/stdlib-work/form_select tag
```

Exact output: `tag=red&tag=blue+sky&tag=a%2Bb` (30 bytes, no newline).

```sh
printf '%s' 'x=%ff%00&x=%2b&x=%zz&ignored=1' | \
  timeout --kill-after=2s 10s target/stdlib-work/form_select x
```

Exact output: `x=%FF%00&x=%2B&x=%25zz` (22 bytes, no newline). Malformed `%zz`
is literal decoded data; canonical output escapes its percent sign.

The standalone compile succeeded, and both examples returned 0 with empty
stderr and these exact bytes. Receipts are
`target/stdlib-work/form-select-cli-build.log` and
`target/stdlib-work/form-select-cli-examples.log`.

## Byte semantics and arguments

The argument is a literal decoded key. It is not percent-decoded: argument
`a+b` selects a plus in the decoded name, while argument `a b` selects a space.
Exactly one argument is required. Empty and non-UTF-8 keys are accepted;
`--help`, `--` and other option-like strings are ordinary keys. Host argv cannot
contain NUL, so this CLI cannot select a name containing a decoded NUL.

Input splits on `&`, ignores empty segments, and splits each remaining segment
at its first `=`. A missing `=` means an empty value. Original `+` becomes
space, valid percent escapes decode once, and malformed percent sequences stay
literal. Names and values remain bytes: NUL and invalid UTF-8 are supported.
There is no URI mode, leading-question-mark removal, semicolon separator,
newline normalization, or special `_charset` behavior.

Canonical output leaves ASCII letters, digits and `*-._` literal, writes space
as `+`, and encodes every other byte as uppercase `%HH`. Every pair includes
`=`, and pairs are separated by `&`. An empty name/value pair therefore emits
`=`. The [form module guide](extended-form.md) describes the reusable APIs.

## Limits and exit status

| Bound | Value |
| --- | ---: |
| Argument count | Exactly 1 |
| Argument bytes, excluding its terminal NUL | 4,096 |
| Input bytes | 1,048,576 |
| Direct stdin read attempts | 16,384 |
| Parsed nonempty segments | 65,536 |
| Decoded bytes per name/value | 1,048,576 |
| Total decoded bytes | 1,048,576 |
| Selected canonical output bytes | 1,048,576 |
| Total copy-provider attempts | 131,072 |
| Copy scratch | 1,024 bytes |
| New bytes per copy step | 4,096 |

Input at the byte cap receives an actual one-byte EOF/excess probe. Read
attempts include EOF, the probe and Interrupted. Full form admission and
decoding complete before matching, so excessive pairs fail even when the key
would have no matches. Exact selected-output admission finishes before stdout;
unselected fields do not spend that output cap. Byte escaping can triple data
size, making the output cap independently reachable. Decoding never expands
input, so the separate decoded/component caps cannot reject an otherwise
admitted input here; their exact boundaries are still exercised.

The copy budget counts both in-memory encoding reads and stdout writes,
including Interrupted and EOF. It persists across resumptions. ReadLimit
resumes with a fresh new-read quota; success requires the copier to observe a
real EOF. Call budgets do not bound blocking duration inside providers.

| Status | Meaning |
| --- | --- |
| 0 | Complete selected output, including no matches |
| 2 | Invalid argument count/size, form/output limits, or exhausted read/copy budget |
| 3 | I/O failure, WouldBlock, invalid provider progress, or failed SIGPIPE setup |
| 4 | Allocation failure |

Argument rejection precedes input collection. SIGPIPE is ignored first; a
closed stdout pipe produces status 3 for nonempty output. Empty output never
writes stdout and can succeed with the same closed pipe. Setup failure is
silent status 3, including when stderr is a closed pipe.

Failures before output admission leave stdout empty. Later write failures or
copy-budget exhaustion can leave the confirmed output prefix. There are no
stderr diagnostics; callers inspect status. Standard descriptors are borrowed
and never closed by the program.

## Storage and ownership

The argument snapshot owns the raw key. Bounded `alloc::io::read_to_end` grows
one input byte buffer. `ext::form_owned::parse` independently owns packed
decoded bytes and spans, after validating the whole form. One `Vec<Pair>`
collects views into matching decoded fields, with no copied selected bytes.

One borrowed `ext::form::Encoding` feeds one generic `core::io::Copier` through
fixed scratch. Neither output preflight nor transfer allocates. There is no
whole-output String or per-field copier. Original input and argument owners
remain live until selection and output finish. Cleanup ends all borrowed uses,
then destroys selected descriptors, the Form, input and arguments in that
order, on ordinary success and failure paths.

## Verification

`tests/stdlib_form_select_execution.rs` compiles the real program. Its fixture
uses Python byte splitting, `unquote_to_bytes` and `quote_from_bytes` with the
form safe-set adjustment to compare complete outputs. The focused corpus
contains 32 model cases, five argument rejections and ten boundary cases. Its
I/O group derives allocation-failure ordinals from one real baseline and
checks reached failures, exact cleanup, confirmed prefixes and attempt limits.
Host-only corpus and invalid-ledger controls pass. The model, argument and
boundary gates passed all 47 native cases in one command: 10.08 seconds for
the three tests, with a separate 1.81-second build. The allocation/I/O gate
passed 39 cases in 20.98 seconds, with a separate 0.20-second build, including
20 reached allocation failures. All four gates passed 86 native application
cases. The accepted standalone examples above and library resource tests
are separate evidence.

Logs are `target/stdlib-work/form-select-model-admission-limits.log` and
`target/stdlib-work/form-select-io.log`. The first log has combined timings
for its three groups, with no separate per-group measurements.

The ledger tracks complete allocation addresses and extents. Independent
decoded/selected sizes bind packed Form owners and each selected-descriptor
growth allocation. Every stdout attempt requires the exact current owners,
input and argument storage to remain live; allocation during publication is
rejected. All observed mappings must retire exactly once, with input after
Form/selection and arguments last. Observed effects are limited to nine traced
syscalls: `read`, `write`, `mmap`, `munmap`, `mremap`, `brk`, `openat`, `close`
and `rt_sigaction`. Direct library tests cover their separate borrowed scopes.

Receipt details and frozen hashes belong in the fixture README. Execution
acceptance is Linux x86_64 CPU output from the GPU compiler; GPU compilation
does not establish program execution on a GPU. Other targets have no
application acceptance claim here.
