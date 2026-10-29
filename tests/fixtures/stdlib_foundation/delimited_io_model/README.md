# Buffered delimiter state model

This fixture checks `core::io::read_until` and `skip_until` against an
independent finite provider/state reference. Production remains Lanius;
Python and the binary adapter are test infrastructure only.

## Observed contract

The custom provider implements only `BufRead`. Its materialized source has
separate fetched and acknowledged positions: a fill can read ahead while
logical consumption remains unchanged. Separate fill and consume schedules
control chunk sizes, transient empty observations, interruptions, errors,
malformed logical View metadata and malformed consume acknowledgements.
Each helper is invoked twice on the same provider and destination to check
resumption, including after EOF and after copied-but-unacknowledged bytes.

The reference owns the provider transitions separately from helper progress.
It chooses prefixes from actual source bytes and finds delimiters with
Python byte-string operations. It compares complete source/destination
backings, both progress counters, ending/error/Host payloads, fetched and
acknowledged positions, cumulative call ordinals and the full direct-call
transcript after each invocation. Source and destination each have native
descending and packed ascending byte backings, in all four combinations.
Nonzero source Views and destination offsets preserve surrounding sentinels.

Malformed consume-count controls are deliberately nonconforming providers.
This fixture deterministically retains their unread bytes so their actual
state can be checked. The public helper does not promise rollback or safe
resumption after an arbitrary malformed acknowledgement. Conforming consume
errors retain unread data and acknowledge no new consumption.

## Finite corpus

There are **18,000 cases**, each with **two helper invocations**, seed
`0xde11a0261031`. Every case shape runs through both helpers and all four
source/destination stride combinations.

| Case family | Cases |
| --- | ---: |
| Short fill histories crossed with consume schedules and call budgets | 12,768 |
| Every fill failure/metadata control, including final-budget fills | 256 |
| Every consume failure/count control, including after prior progress | 272 |
| Empty through 16-byte sources and delimiter/cap positions | 1,088 |
| Transient EOF and filled-but-unconsumed resumption controls | 64 |
| Invalid destination spans, zero bounds and negative/exact call budgets | 320 |
| Full-width skip bounds and read-count narrowing boundaries | 32 |
| Seeded provider, byte, budget and resumption combinations | 3,200 |

Delimiter bytes include NUL and non-UTF-8 values. The corpus distinguishes
delimiter-at-cap from Limit, prevents an extra probe at a filled cap, checks
metadata before EOF or exhausted post-fill budget, retries only interrupted
fills, and checks every consume error without retry. Large skip limits reach
EOF through a finite source; no huge backing is constructed. Invalid read
spans are admitted logically before any provider/backing access. Every valid
nonempty destination span is physically backed.

CPU controls pass explicit literal progress, read-ahead, transient EOF,
metadata precedence, cap and admission cases. Seven intentional corruptions
of completed count, destination sentinel, transcript, read-ahead position,
acknowledged progress, error precedence and ending are rejected. The expected
corpus includes 2,792 copied-but-unacknowledged failure observations, 1,092
first-invocation read-ahead budget failures and 448 cases with progress after
an initial EOF observation. These are reference classifications of the corpus;
the native gate compares every case against the reference but does not emit
those three aggregate coverage counters separately.

## Protocol and acceptance

Each input packet has 45 little-endian `u64` words: a 13-word case header,
16 source-byte words and two eight-word provider schedules. The header keeps
both helper bounds/budgets, delimiter, backing policy and case identity.
Each invocation emits a 12-word result/provider header, both 32-byte backings
as words and all cumulative five-word direct-call records. Unused result
fields must be zero. The oracle checks exact output size and includes the
complete case and seed in any mismatch diagnostic.

The first compile stopped before execution with `LNC0016`: the fixture used
unsupported `else if` syntax. Its original source, SHA256 prefix `37b153ab`,
is retained at `target/stdlib-work/delimited-io-model-first-source.lani`.
An equivalent set of mutually exclusive `if` branches corrected the fixture.
No compiler or production library repair was needed.

The amended gate passed **1 registered test in 5.64s**, reporting all
**18,000 cases / 2 helpers / 4 stride combinations / 2 invocations** at seed
`0xde11a0261031` from the native process. The receipt is
`target/stdlib-work/delimited-io-model-amended.log`. This checks executable
values, effects, errors and resumption, beyond compilation.

The registered Rust test is
`independent_delimited_schedules_match_calls_progress_bytes_and_resumption`
in `stdlib_delimited_io_model_execution`. It checks executable ELF admission
before publication and uses shared strict x86 jump validation, one batched
native process, an 85-second outer timeout and a 70-second child timeout.
Accepted scope is finite Linux x86_64 CPU execution produced by the GPU
compiler. Actual SliceReader/allocating adapters, host effects and the real
record-selection program have separate gates. No direct GPU-device,
arbitrary-target, wall-clock deadline or formal verification claim is made.

Frozen tested identities (SHA256):

| Source | SHA256 |
| --- | --- |
| `stdlib/core/io.lani` | `d2d4d869cec351b29b1e2d026f4cfe684f06bda16bbc1738f2dae64252e287fb` |
| `stdlib/alloc/buffered.lani` | `025394873442bfe8b50254db4a4d50273a22a825cde83ff381578b2be0bd269d` |
| `model.lani` | `7ca5cc6c15b25a8dedf14f93ff2d1e3e79cdd1081383074f8196d1d382564465` |
| `oracle.py` | `ed00173520d7b223755e50e0dc0e0dc40852045381f46d19a3b419145b726878` |

```sh
python3 -B tests/fixtures/stdlib_foundation/delimited_io_model/oracle.py controls
cargo test --test stdlib_delimited_io_model_execution independent_delimited_schedules_match_calls_progress_bytes_and_resumption -- --nocapture
```
