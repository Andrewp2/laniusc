# Rewrite literal text

`sample_programs/library/literal_rewrite.lani` is the consumer for
[literal Text matching and String replacement](stdlib-text-replacement.md).
It reads UTF-8 stdin, replaces literal matches and writes the complete result
to stdout. All four application groups/94 native cases and both standalone
examples pass on the Linux x86_64 profile.

## Build and use

From the repository root with the compiler binary built:

```sh
mkdir -p target/stdlib-work
timeout --kill-after=2s 100s flock -w 95 target/stdlib-work/library-gpu.lock \
  target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  --emit x86_64 sample_programs/library/literal_rewrite.lani \
  -o target/stdlib-work/literal_rewrite
printf 'ababa' | target/stdlib-work/literal_rewrite aba X
```

Expected stdout is exactly `Xba`, with no newline: the second overlapping `aba`
does not match. Empty needles and binary NUL within valid UTF-8 work together:

```sh
printf '\303\251\000x' | target/stdlib-work/literal_rewrite '' '|'
```

Expected stdout is eight bytes, hexadecimal `7c c3 a9 7c 00 7c 78 7c`.
The standalone build and both exact pipelines pass, with status 0 and empty
stderr. They produce the expected three and eight bytes, respectively.

## Arguments and text policy

```text
literal_rewrite [--count N] [--] NEEDLE REPLACEMENT
```

Exactly two UTF-8 operands are required. Both may be empty. A single optional
`--count N` or `--count=N` selects the first N matches; omission selects all.
N is 1–20 ASCII decimal digits in the full u64 range, including zero. Leading
zeroes are allowed; signs, spaces, overflow and duplicate counts reject.
Options may appear between operands. Use `--` before an operand beginning
with a dash. Sole `-h` or `--help` prints help without reading stdin; help mixed
with other arguments is invalid. The help text is exactly 1114 bytes.

The snapshot admits at most eight argument tokens and 8192 argument bytes,
excluding argv[0]. Argument admission finishes before stdin is read. The
needle is at most 256 bytes and the replacement at most 4096 bytes.

Matches are literal, leftmost and nonoverlapping in the original input.
An empty needle selects every scalar boundary, including both ends. Inserted
bytes are never searched. `$`, backslashes and other replacement characters
have no special meaning. NUL in stdin and original line endings survive where
they are not replaced. No normalization, case folding or newline is added.
Native argv cannot carry NUL; that host restriction does not limit stdin.

## Bounds and publication

| Resource | Maximum |
| --- | ---: |
| Input bytes | 262,144 |
| Output bytes | 1,048,576 |
| Stdin read attempts, including EOF/probe/retries | 4096 |
| Combined Copier reader and writer attempts | 4096 |
| Help write attempts | 64 |
| Diagnostic write attempts | 64 |

`alloc::io::read_to_string` collects through actual EOF before UTF-8 validation.
At exactly the input cap, a one-byte probe distinguishes EOF from excess input;
an extra byte is consumed and rejects the input. Invalid UTF-8 anywhere in the
admitted input rejects, including bytes after the last requested match or when
`--count 0` requests an independent copy.

Input admission and complete result construction finish before stdout starts.
The program uses the library's complete-result output check, so a shrinking
replacement is judged by its final size. Output is published through a
SliceReader and the canonical Copier with 1024-byte stack scratch. Its call
limit includes in-memory reads as well as stdout writes; it is not a limit of
4096 host writes. Read quota includes one extra byte to allow the real source
EOF observation.
With complete 1024-byte transfers, publication takes
`2 * ceil(output_bytes / 1024) + 1` direct provider calls, including EOF.

Interrupted calls consume attempts and retry. Positive short transfers retain
progress; WouldBlock and host failures stop without a readiness wait. Zero or
invalid-count writes fail. Output failure or call exhaustion may leave a
confirmed prefix; the program does not restart publication. There is no flush,
durability or file-publication guarantee.

## Ownership and status

Input and argument owners stay alive while replacement borrows their Text.
After construction, the input String and argument snapshot are destroyed
before the first payload write. The result alone owns the published bytes.
The copier is aborted before that String is destroyed, including on failure;
stdin/stdout/stderr descriptors remain borrowed.

Collection failures destroy any retained prefix. Preparation failures release
input and argument owners before reporting. Help releases its argument owner
before writing. Every ordinary payload outcome destroys the output owner
before reporting an error or returning success.

| Exit status | Meaning |
| --- | --- |
| `0` | Complete payload or help output |
| `2` | Invalid arguments/UTF-8, byte or call limit, or unexpected replacement error |
| `3` | Argument/input/output/help I/O failure, or SIGPIPE-ignore setup failure |
| `4` | Allocation failure |

Diagnostics use the `literal_rewrite:` prefix and distinguish argument, input,
replacement and publication failures. Output/help failures append
`; written=N`, where N is the confirmed stdout byte count. Diagnostics end in
LF and use their own 64-attempt budget. Diagnostic failure preserves the
original exit status. SIGPIPE-ignore setup failure returns 3 silently. Success
emits no stderr output.

## Execution evidence

The final native run passes all four groups in 9.91 seconds after a separate
0.19-second Rust build, recorded in
`target/stdlib-work/text-replacement-app-final.log`:

| Group | Native process cases |
| --- | ---: |
| Independent Unicode/literal model | 29 |
| Arguments and complete UTF-8 admission | 30 |
| Real input/output/count limits | 7 |
| I/O and allocation failures | 28 |
| Total | 94 |

The I/O group includes one baseline and 12 reached allocation denials. The
baseline has two argument allocations, nine collector capacities and one exact
result allocation. Exact release extents, source lifetimes during allocation
and result-only ownership before stdout are checked. Full outputs and confirmed
prefix diagnostics are compared byte-for-byte. Actual input EOF/excess probes
and independently reachable exact/excess 1 MiB output limits pass. Supported
finite EINTR schedules exhaust the combined Copier budget while allowing its
following diagnostic to succeed: status 2 and exact `written=0`/`written=1024`
messages are directly exercised.

The initial 9.71-second run (separate build 1.05 seconds) passed these same
94 cases with a weaker observer. Review added an explicit requirement that
argument owners remain live between input EOF and result allocation. The final
run uses that strengthened observer; the application was unchanged. The two
runs are not added together.

The [fixture guide](../tests/fixtures/stdlib_literal_rewrite/README.md) records
complete source identities and limitations. Its filter covers nine syscall
names, not every possible host effect. Argument-capture host-read failure,
defensive internal replacement errors, isolated help/diagnostic attempt
exhaustion and exhaustive error combinations are not claimed as executed.
The separate library owner-recovery denial is not an application case.

The tested source was SHA256
`e1a142eca57bc4266c0b28cca0e1f3a83db427c2e3cf041825d7f891c428e75d`;
the final observer is `2c0f7460…`. The standalone build exits 0 with an empty
success log in `target/stdlib-work/text-replacement-cli-build.log`. Both
printed examples pass under Bash `pipefail` with exact three/eight-byte stdout
and empty stderr, recorded in `text-replacement-cli-examples.log`. Those two
examples remain separate from the 94 native test cases.

Final whitespace checking removed only one extra trailing newline. The final
source is `513c569e58a1a929313fccb7d1fb6221bd48472b3bde619e9823926455adf2b2`;
all other bytes are identical to the tested source above.

Evidence is Linux x86_64 CPU execution of GPU-compiler output. Other hosts,
user-program GPU execution, automatic cleanup and formal proofs remain
separate. Literal matching retains its documented worst-case search bound;
these receipts establish no universal performance claim.
