# sample-counts

`sample_programs/library/sample_counts.lani` reads discrete sampling jobs from
stdin. It emits integer samples, measured moments/exceedances, and theoretical
probability masses and survival tails. This lets a simulation compare observed
event counts with the model's predicted threshold risk.

```sh
target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  sample_programs/library/sample_counts.lani -o /tmp/sample-counts
printf 'family,trials,parameter,samples,threshold\nbinomial,100,.03,4000,4\npoisson,0,10,4000,12\n' \
  | /tmp/sample-counts --seed 17 > counts.csv
```

## Input and limits

The required header is `family,trials,parameter,samples,threshold`.

| Family | trials | parameter | count convention |
| --- | --- | --- | --- |
| `bernoulli` | 0 placeholder | success probability p | 0 or 1 |
| `binomial` | full u32 count | success probability p | successes |
| `geometric` | 0 placeholder | success probability p | failures before first success |
| `poisson` | 0 placeholder | mean in [0,1e9] | events |

Parameter/count domains follow [the discrete library](extended-discrete-distributions.md).
Samples is a positive unsigned decimal integer. Threshold is an exact signed
i64 decimal integer. The predicted/observed event is count > threshold.
Bernoulli/binomial thresholds may span i64; nonnegative geometric/Poisson
thresholds above 2^53-1 fail with the library's count-range error. Parameters
use the existing checked binary64 decimal parser; invalid/nonfinite values
fail. CSV quoting and LF/CRLF are supported, without trimming numeric fields.

There are no file operands. Repeated/unknown options fail. `--seed`/`-s`
accepts any u64, defaults to 0, and seeds one generator for the entire run.
One cumulative draw/work budget serves all rows; changing jobs does not reset
the stream. Identical inputs/options/seed reproduce this implementation's output.

| Option | Default | Maximum |
| --- | ---: | ---: |
| `--max-input-bytes` | 1048576 | 67108864 |
| `--max-jobs` | 128 | 4096 |
| `--max-samples` | 100000 cumulative | 1000000 |
| `--max-output-bytes` | 8388608 | 67108864 |
| `--max-draws` | 10000000 | u64::MAX |
| `--max-work` | 268435456 | u64::MAX |
| `--help`, `-h` | off | must appear alone |

Records have five fields, each at most 128 decoded bytes; each decoded record
is at most 640 bytes. The raw input has its separate byte limit. Work reserves
1000000 units per job for the bounded decimal parse,
512 per sample for formatting/moments, and 2048 per summary, plus the library's
actual policy charges for sampling and predicted tails. These are policy
units, not instruction counts. Byte/record/sample limits apply independently;
high settings do not promise that the other remaining budgets suffice.

## Output, staging and process policy

Output columns are:

```text
kind,job,index,value,samples,mean,variance,threshold,exceedances,pmf,log_pmf,survival,log_survival,draws,work
```

A `sample` row fills job, zero-based index and exact integer value. A
`summary` row follows each job with sample count, mean, population variance,
threshold, observed exceedances, theoretical mass/log-mass at the threshold,
survival/log-survival, and cumulative draw/work counts. Moments use the actual
samples. Library counts convert exactly to binary64 before moment updates.
Theoretical log zero is output as -infinity; it is a valid result, even though
nonfinite input parameters are rejected.

The entire run is staged before stdout starts. A later invalid job, numerical
error, resource limit or allocation failure publishes no CSV prefix. All
owned argument/input/table/output buffers are released on every return path.
Once writing starts, an I/O error may leave a visible prefix. Interrupted and
positive short writes retry through `core::io::write_all`.

The process installs `std::signal`'s SIGPIPE ignore disposition before argument
access or allocation. Real closed stdout or diagnostic stderr pipes therefore
return I/O status 5 after cleanup. Signal setup failure returns 5 immediately
without allocating or attempting a diagnostic under an unknown disposition.

Exit statuses are 0 success/help, 2 invalid input/parameters or numerical
failure, 3 resource limit, 4 allocation failure and 5 I/O failure. Diagnostics
include the status, stage and input row. Stages are 0 arguments, 1 input/CSV,
2 job validation/prediction, 3 sampling/statistics and 4 output. Diagnostic
write failure also returns 5.

Focused native tests check actual CSV sample values and independent moments,
exceedances and predicted probabilities; seed origin/reproducibility; full-u32
trial parsing; endpoint thresholds; malformed input and resource categories.
Allocation denials, interrupted/failed/short I/O, real closed pipes, signal
setup failure and an allocation ledger exercise cleanup. Tests require Linux
x86_64, Python 3, mpmath and `strace`; production calls no test service.
