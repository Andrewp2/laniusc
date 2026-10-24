# sample-distribution

`sample_programs/library/sample_distribution.lani` reads bounded CSV sampling
jobs from stdin, generates deterministic samples with `core::random`, computes
population moments with `ext::statistics`, and stages complete CSV before
writing stdout. Parsing, sampling, statistics and formatting are Lanius.

```sh
target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  sample_programs/library/sample_distribution.lani -o /tmp/sample-distribution
printf 'family,first,second,count\nnormal,0,1,100\ngamma,2,3,100\n' \
  | /tmp/sample-distribution --seed 17 > samples.csv
```

The header is required and must be `family,first,second,count`. Each subsequent
record is one job. Family names are `normal`, `exponential`, `gamma`, `beta`.
Parameters follow [the distribution API](extended-distributions.md): mean/
deviation, rate/zero, shape/scale, or alpha/beta. Exponential's second field
must be zero. Count is a positive unsigned decimal integer. Parameters use the
existing checked binary64 decimal parser; nonfinite/invalid parameters fail.
CSV quoting and LF/CRLF are handled by `ext::csv`; whitespace is not stripped
from numeric fields.

There are no file operands. Repeated or unknown options fail. `--seed`/`-s`
accepts every u64 value and defaults to 0. One generator and one cumulative
draw/work budget serve all jobs in row order; jobs do not reset the stream.
Identical input/options/seed produce identical output under this implementation.
This is deterministic simulation, not secure randomness.

| Option | Default | Maximum |
| --- | ---: | ---: |
| `--max-input-bytes` | 1048576 | 67108864 |
| `--max-jobs` | 128 | 4096 |
| `--max-samples` | 100000 cumulative | 1000000 |
| `--max-output-bytes` | 8388608 | 67108864 |
| `--max-draws` | 10000000 | u64::MAX |
| `--max-work` | 268435456 | u64::MAX |
| `--help`, `-h` | off | must appear alone |

CSV records have four fields; each field is at most 128 bytes and each record
at most 512 bytes. Input is fully staged under the input bound and parsed into
owned records. Output uses one buffer with the declared output capacity.
Limits apply independently; choosing high sample/job limits does not promise
they fit the remaining work, draw or output budget.

Work charges reserve 2000000 units per job for the two bounded decimal parses,
512 per sample for moment/format work, 1024 per summary, plus the library's
sampling charges. These are policy units, not instruction counts. CSV parsing
and input staging have independent explicit byte/record limits.

## Output and errors

Output columns are `kind,job,index,value,count,mean,variance,draws,work`.
Job numbers begin at 1; sample indices begin at 0. A `sample` row fills job,
index and value. A `summary` row follows each job and fills count, mean,
population variance, and cumulative draw/work counters. Variance divides by
count; it is zero for one sample. Summary moments are computed from the
actual emitted binary64 samples. No distribution density/CDF is calculated
by this program.

The entire run must succeed before stdout starts. Invalid later jobs,
sampling overflow, moment overflow, resource limits, formatting failure or
allocation failure emit no CSV prefix. Every owned input/record/output buffer
is released on every return path. Once stdout writing begins, I/O failure may
leave a visible prefix. Interrupted and positive short writes retry through
`core::io::write_all`.

Before capturing arguments or allocating buffers, the process deliberately
ignores SIGPIPE through `std::signal`. A closed stdout or diagnostic stderr
pipe therefore returns the existing I/O status 5 and permits owned-buffer
cleanup. If installing this process-wide policy fails, the program returns
5 immediately, before argument access, allocation or diagnostic output.

Exit statuses: 0 success/help, 2 invalid arguments/CSV/parameters or numerical
failure, 3 resource limit, 4 allocation failure, 5 I/O failure. Diagnostics include
the status, stage and input row. Stages are 0 arguments, 1 input/CSV, 2 job
validation, 3 sampling/statistics, 4 output. A diagnostic-write failure returns 5.

Focused native tests parse 16000 actual sample rows numerically, recompute
summary moments independently, check seed reproducibility/stream origin and
parameter effects, and exercise malformed input/options and all resource
categories. They deny each allocation in a real multijob run and check a
mapping ledger, then inject read/write EINTR/EIO, a positive short write and
`/dev/full`. Tests require Linux x86_64, Python 3 and `strace`; production uses
none of those test services.
Separate narrow gates close real stdout/stderr pipe readers, verify status 5
and an empty allocation ledger, and inject signal setup errors before any
argument access or allocation.
