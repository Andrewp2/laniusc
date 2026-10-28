# CSV timeline application tests

`oracle.py` independently models input-order retention, newest-first reversal,
exact level filtering, count limiting and one-based output ranks using Python
lists and the standard `csv` reader/writer. It compares exact canonical quoted
CSV bytes, including Unicode, quotes, commas and embedded line breaks.

| Group | Cases | Contract |
| --- | ---: | --- |
| model | 25 | Normal selection, absent/case-sensitive levels, zero/one/default counts, empty messages, CSV escaping, exact 32+8192 decoded record boundary, 4096 events, exactly 1 MiB input, ten seeded models |
| rejection | 24 | Header/schema, malformed CSV, invalid UTF-8 including unselected records, unsupported NUL/TAB, field/event/input caps, full validation with count zero and no published prefix |
| cli | 20 | Invalid operands/options/count/level, all duplicate options including repeated long/clustered help, both help forms; help does not read stdin |
| io | 2 | Actual stdin directory read failure and closed stdout reader |

The default CLI with empty input in the CLI group is an input rejection, not an
argument-parser rejection. All process runs have a 15-second timeout; the Rust
driver uses an 80-second group timeout. There is no resource tracing or leak
checker. Python implements only the independent test model.

```sh
python3 -B tests/fixtures/stdlib_execution/timeline_tail/oracle.py controls
python3 -B tests/fixtures/stdlib_execution/timeline_tail/oracle.py model PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/timeline_tail/oracle.py rejection PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/timeline_tail/oracle.py cli PATH_TO_ELF
python3 -B tests/fixtures/stdlib_execution/timeline_tail/oracle.py io PATH_TO_ELF
```

## Accepted native results

The application compiled and directly passed all four groups on Linux x86_64
on 2026-10-28. Receipts under `target/stdlib-work/`:

| Gate | Result | Receipt |
| --- | --- | --- |
| Compile | Exit 0 | `timeline-tail-compile-final.log` |
| Model | 25 cases pass | `timeline-tail-model-native-final.log` |
| Rejection | 24 cases pass | `timeline-tail-rejection-native-final.log` |
| CLI | 20 cases pass | `timeline-tail-cli-native-final.log` |
| I/O | 2 cases pass | `timeline-tail-io-native-final.log` |

Evidence directories: `/tmp/timeline-tail-model-2hrlz1ce`,
`/tmp/timeline-tail-rejection-7sucamb4`, `/tmp/timeline-tail-cli-akqmmy7m`,
`/tmp/timeline-tail-io-v_8ea5t8`.
Executed application source SHA-256:
`6579274d6f177f9fce0c6a1435d7f1a6ceaaa43f6e57716e55789a715aef6daf`.
Retained direct-run ELF (`target/stdlib-work/timeline-tail`) SHA-256:
`aca6fc83e962e950808a5c9abd8a08d3424cdde993c0cd07bdbd5df4556fb264`.
Final oracle SHA-256:
`233d98e206fc4231717d4ba24ba72e13d5af1243f845a9f8ba2341990889281c`.
These are 71 finite direct native cases. Separately, the registered Rust driver
compiled its own executable, passed the shared strict ELF checker and passed
all four tests with the same 25/24/20/2 cases in 9.15 seconds. Receipt:
`target/stdlib-work/timeline-tail-rust-final.log` (Cargo compilation: 1.72
seconds). This registered executable is distinct from the retained direct-run
ELF whose hash is recorded above; no matching binary hash is assumed.
Registered evidence directories: `/tmp/timeline-tail-model-fbthb4h_`,
`/tmp/timeline-tail-rejection-t7wilv7c`, `/tmp/timeline-tail-cli-hox786i4`,
`/tmp/timeline-tail-io-klen8rgv`.
The four CPU controls validate the independent oracle only.

The first native model attempt stopped at `seeded-0`: its positive generator
included TAB, which the established CSV dialect rejects even inside quotes.
The generator now uses a space-containing message in that positive slot, and
an explicit quoted-TAB rejection checks the actual dialect. Application and
library code were unchanged; the complete corrected model group then passed.

Independent review then found that repeated help options were accepted despite
the documented duplicate-option rule. The application now rejects both
`--help --help` and `-hh`; two CLI cases cover that repair. The final source's
rebuild and complete four-group rerun passed all 71 cases as recorded above.
