# Exact decimal CSV ledger

`sample_programs/library/decimal_ledger.lani` is a bounded invoice and refund
report using `ext::decimal`, `ext::csv`, `ext::cli`, `std::args` and descriptor
streams. The production program is entirely Lanius. Financial arithmetic uses
owned arbitrary precision decimal coefficients and explicit decimal exponents.

```sh
timeout --kill-after=2s 100s target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended sample_programs/library/decimal_ledger.lani -o target/decimal_ledger
printf 'label,quantity,unit_price,tax_rate\nwidget,2.5,1.005,0.125\nrefund,-1,1.005,0.125\n' | timeout 20s target/decimal_ledger --header --scale 2 --round half-even
```

Input has exactly four columns, `label,quantity,unit_price,tax_rate`. Without
`--header`, every record is data. With `--header`, the first record must contain
those exact names; a missing header fails. Labels are decoded UTF-8 text, including
quoted commas, quotes and newlines. Decimal fields follow the finite decimal
provider's strict grammar, including optional sign, decimal point and signed
base-ten exponent. Spaces are data and are not trimmed. NaN, infinity, separators,
base prefixes and malformed numerals fail. Signed quantities support refunds;
negative prices or rates follow the same arithmetic rules.

For each record the application performs these operations:

1. Multiply quantity by unit price exactly, then rescale to the selected currency
   scale to obtain `subtotal`.
2. Multiply that rounded subtotal by tax rate exactly, then rescale to the same
   currency scale to obtain `tax`.
3. Add subtotal and tax exactly to obtain `total`, then add total to the running
   grand total. All derived fields retain the selected currency scale.

Tax rate is a multiplier: `0.0825` means 8.25 percent. These are explicit report
rules; different invoicing conventions can produce different totals.

Output is CSV with an unquoted header:

```text
kind,label,quantity,unit_price,tax_rate,subtotal,tax,total,running_total
```

Every data field is quoted; embedded quotes are doubled and records end with
CRLF. `kind=line` records preserve the original decoded label and the exact
quantity, unit price and rate spellings, including plus signs, leading or trailing
zeros and exponent notation. Derived numbers use plain decimal notation with the
requested fractional places. Zero has no negative sign. A final `kind=total`
record has seven empty fields between its kind and its `running_total`; this row
also exists for empty input. The `kind` field distinguishes the summary from any
user label. A header alone with `--header` is an empty ledger.

| Option | Default | Contract |
| --- | --- | --- |
| `-s N`, `--scale N` | 2 | Nonnegative fractional currency places, at most max-scale |
| `-r MODE`, `--round MODE` | half-even | Currency rounding policy |
| `--header` | off | Validate and consume the input header |
| `--max-rows N` | 10,000 | Data records, excluding an optional header |
| `--max-field N` | 65,536 | Decoded bytes in each of the four input fields |
| `--max-input N` | 16,777,216 | Total input bytes, including CSV quoting/separators |
| `--max-limbs N` | 4,096 | Decimal coefficient storage limit |
| `--max-digits N` | 10,000 | Decimal coefficient digits, including operation results |
| `--max-scale N` | 10,000 | Absolute decimal exponent bound |
| `--max-work N` | 100,000,000 | Decimal provider work allowance per operation |
| `--max-output N` | 16,777,216 | Entire encoded report, including header and final summary |
| `-h`, `--help` | off | Usage after validating the complete command line |

Rounding modes are `down` (toward zero), `up` (away from zero), `floor`, `ceiling`,
`half-up`, `half-down`, `half-even` and `unnecessary`. Half modes apply their named
rule to exact ties. `unnecessary` rejects any value whose rescaling would discard
nonzero digits; removal of trailing zeros is exact. Options accept only unsigned
decimal integers. Repeated options use the last value. Positional operands fail.
Argument snapshots permit 40 arguments and 8 KiB of bytes.

Rows and output counts fit signed 32-bit lengths. max-field and max-limbs are at
most 536,870,911, max-digits is in 1..1,000,000,000, and max-scale is at most
1,000,000,000. max-input and max-work fit unsigned 64-bit values. The four-column
width is fixed; decoded record bytes are bounded by four times max-field. Decimal
limits apply independently to every parse, arithmetic, rescale and format call.
The row and input bounds also bound the number of operations; max-work is not a
single cumulative report budget. CSV storage and the staged output vector can
reserve capacity above logical lengths as they grow.

The program stages the complete output, validates EOF, and formats the final
summary before the first stdout write. A late syntax, limit, arithmetic,
allocation or input failure therefore publishes no report. Peak storage includes
the complete bounded encoded output, one reusable decoded CSV record, decimal
operands/results and arithmetic scratch. Every manually owned value is destroyed
on all exit paths. Records and decimal values are shallow-copy handles, not
compiler-enforced unique owners; only the active owner is destroyed.

Exit 2 means invalid arguments, malformed CSV/decimal input, a header mismatch,
missing columns, or required rounding. Exit 3 means input/row/field limits
(including more than four columns), decimal size/scale or output limits. Exit 4 means decimal work exhausted, 5 means allocation failed, and 6 means
I/O failure. Diagnostics identify the category and, where available, one-based
record and field or zero-based argument and byte. CSV grammar, UTF-8 and field/row
limit errors preserve the parser's unsigned 64-bit raw input byte offset. A
cross-option scale conflict has no argument location. If stderr itself fails, the
status is 6. Reads retry EINTR; `write_all` retries interruptions and short writes
and rejects zero progress. A stdout failure may leave a prefix of the already
validated report on the descriptor.

`tests/extended_decimal_ledger_execution.rs` compiles the real sample through GPU
code generation and executes the native x86_64 Linux binary. An independent
Python `decimal` oracle exists only in the tests. It covers every rounding mode,
positive and negative ties, refunds, large coefficients, exact input spelling,
Unicode/quoted labels, empty input and headers. It checks late malformed input,
invalid UTF-8/control bytes, resource boundaries, and command-line errors with no
published report. Fault injection denies every observed allocation in one full
record/summary, injects read/write errors, interrupted calls, short/zero writes,
stderr failure and `/dev/full`, and checks release of every successful mapping.
A seeded 512-record batch compares the entire CSV and prints native elapsed time
including startup and excluding compilation. On 2026-10-23, one local run processed
17,597 input bytes into 53,050 output bytes in 173.70 ms. This is an observation,
not a throughput guarantee. The suite requires `python3` and
`strace`.

```sh
timeout --kill-after=2s 100s env CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 cargo test --locked --test extended_decimal_ledger_execution -- --nocapture
```

Execution evidence applies to native x86_64 Linux. GPU code generation does not
claim GPU kernel execution. The program introduces no compiler, runtime, ABI,
shader, IR or host decimal implementation.
