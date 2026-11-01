# Shared draw-budget sampling application fixture

The test-only reference uses integer arithmetic for xoshiro256++ 1.0 and four
successive SplitMix64 seed words. Its transition is independently expressed
from the authors' public-domain [xoshiro256++](https://prng.di.unimi.it/xoshiro256plusplus.c)
and [SplitMix64](https://prng.di.unimi.it/splitmix.c) sources. Before every native
group, it checks the six initial states and first four raw outputs against
the checked-in [author-generated vectors](../../stdlib_foundation/random_vectors.md).
No production implementation is imported, and normal tests need no network,
C compiler or vector regeneration. This is deterministic, non-cryptographic
sampling, without a statistical or security guarantee.

The independent bounded sampler rejects raw words below `2^64 mod BOUND`, then
reduces accepted words modulo BOUND. One counter spans the complete request,
including rejected draws. Exhaustion produces no output; there is no modulo
fallback. BOUND one and COUNT zero need no draws. The oracle checks exact
decimal-plus-LF bytes, including full-width unsigned results.

CLI is exactly `sample_integers SEED BOUND COUNT DRAW_LIMIT` or sole help.
Each numeric token is strict unsigned ASCII decimal of 1..20 bytes, with
leading zeros allowed; captured arguments total at most 80 bytes. Seeds and
draw limits span all u64, BOUND is 1..u64::MAX, and COUNT is 0..4096. No stdin
is read. All requested samples must succeed before stdout publication.

| Group | Cases | Scope |
| --- | ---: | --- |
| model | 32 | Six author seeds, BOUND one/two/u64::MAX/rejection-heavy, no-draw paths, maximum count with small and full-width bounds, powers of two, odd bounds and u64::MAX draw limit |
| budget | 19 | Success on the exact last allowed draw and failure one draw earlier across seeds/counts, zero budget and a counter shared across samples |
| cli | 36 | Arity/help, per-field empty/sign/length/overflow checks, malformed/non-ASCII values, zero bound, count cap and exact 80-byte leading-zero arguments |
| io | 11 | Traced baseline, three reached argv/value ENOMEM faults, actual closed data/help stdout, write EINTR/EIO, signal failure, 128-attempt output cap and cleanup after draw exhaustion |

Full traces require both argv owners released before the single sample Vec
reserve, no later allocation, no stdin read and no borrowed descriptor close.
The sample owner stays live while natural fixed-size batches are formatted and
written, then is explicitly released on success or failure. Mapping releases
match address and requested length, allowing actual address reuse between
owners. Diagnostics may appear only after all tracked owners are released.
COUNT zero has no sample backing and no stdout write; help releases argv
owners before publication. The selected three ENOMEM sites must be reached at
matching baseline ordinals/arguments, return 4 and publish nothing.

Actual EPIPE and injected EIO return 5; one write EINTR must retry to exact
output. No successful transfer count is fabricated or extra writes introduced
for testing. One total data-write budget spans all 1024-byte formatting batches;
128 attempts cover the admitted 4096 full-width lines in failure-free execution.
Help has its own 128-attempt budget and diagnostics eight. The compact bounded
interruption summary requires 128 write errors plus one successful diagnostic;
it observes attempts, not a full allocation-release ledger. Separate full
traces establish selected cleanup observations, including draw-limit failure
before any output. These finite observations imply no automatic lifetime or
leak-freedom guarantee and are not an exhaustive fault campaign.

The Rust driver compiles once per libtest process, requires an actual
little-endian ELF64 x86-64 executable and applies the shared strict jump gate.
The standalone oracle also rejects non-ELF targets. Native children have
15-second deadlines and registered groups 85-second deadlines. Commands,
exact output/status and selected syscall evidence are retained.

```sh
python3 -B tests/fixtures/stdlib_execution/sample_integers/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/sample_integers/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sample_integers/oracle.py budget PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sample_integers/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/sample_integers/oracle.py io PATH_TO_ELF
```

## Acceptance

All four registered tests passed in 7.59 seconds: **98 distinct native Linux
x86_64 cases**, with no failures or filtered tests. The GPU compiler produced
the strict-admitted ELF64 program; it executed on the CPU. Receipt:
`target/stdlib-work/random-budget-sample-app-first.log`.

| Group | Cases | Evidence |
| --- | ---: | --- |
| model | 32 | `/tmp/sample-integers-model-dvyvqmn3` |
| budget | 19 | `/tmp/sample-integers-budget-q91gu3sp` |
| cli | 36 | `/tmp/sample-integers-cli-rnjhpls7` |
| io | 11 | `/tmp/sample-integers-io-5_kel5dc` |

Accepted identities (SHA-256):

- Application: `f63a73509e8ed44cd3df749dd4234ba4b0baf71ba1f843835fb65da506eb2e63`.
- Oracle: `74ae03a7ca17c1b37351e90ac49f85fafa0378f70416e3381fe9321b98dc4dde`.
- Random library: `7f1bf3857137cd610a23d69a3d6d3e0bdfb4df62d5d4e0fc160f811460cdf09b`.

The inspected baseline releases both argv mappings before its one 2048-byte
sample reserve, writes 5234 exact reference bytes, then releases the sample
mapping. The allocator actually reuses an earlier argv address; the ledger
tracks the new allocation correctly. All three selected ENOMEM sites were
reached at mmap ordinals 1, 2 and 3, each returning 4 with empty stdout and
matching releases for every mapping successfully obtained in those traces.
The draw-exhaustion trace releases its sample storage before the diagnostic,
with no stdout. No traced case reads stdin or closes a borrowed descriptor.

The 4096-sample full-width case publishes 83580 exact decimal bytes and succeeds;
COUNT zero publishes nothing, and BOUND one succeeds with a zero draw limit.
The budget group checks exact last-draw success and one-draw-short exhaustion,
including after earlier completed samples, without publishing those prefixes.
These are deterministic sequence/consumption observations, not statistical
evidence of uniformity.

Actual closed data/help stdout produces EPIPE and status 5. Injected EIO also
returns 5 with no stdout; EINTR retries to all 5234 correct baseline bytes.
Full traces match the selected explicit cleanup paths, and signal policy
failure returns 5 silently. The compact attempt receipt has 129 writes:
128 injected EINTR errors and one successful diagnostic, with status 5.
That summary establishes the output-attempt bound, without a full release ledger.

The argument-host-failure status-3 branch and positive short-write handling
were not exercised. There is no confirmed output-prefix or partial-output
claim. No successful transfer counts were fabricated. Eight CPU control
families passed before admission, including the author anchors, exact shared
budget thresholds, corpus counts and a deliberately missing observed release.
GPU device execution, formal verification, automatic lifetime guarantees and
exhaustive faults remain unclaimed. Driver hashes are omitted because root
applied whitespace formatting after the runtime gates; production and oracle
identities are unchanged.
