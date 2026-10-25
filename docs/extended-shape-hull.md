# Shape hull CSV consumer

`sample_programs/library/shape_hull.lani` is a native command-line consumer of `ext::geometry`, `ext::cli`, `ext::csv`, `core::decimal`, `core::fmt`, and descriptor I/O. It reads standard input and writes standard output. It performs parsing, hull construction, area/bounds calculation and complete bounded output formatting before publishing any result.

```sh
laniusc --stdlib-root stdlib --source-root extended sample_programs/library/shape_hull.lani -o shape-hull
printf '0,0\n4,0\n4,4\n0,4\n2,2\n' | ./shape-hull
```

Input has exactly two CSV fields per record, `x,y`, with no header. Coordinates are strict base-10 signed `i32` integers; whitespace, decimals, exponents, nonfinite names and out-of-range values are errors. Quoted fields, LF/CRLF line endings and a final unterminated record follow the CSV decoder's dialect. Each decoded field is limited to 32 bytes and each decoded record to 64 bytes. Duplicate points and empty input are accepted. The decoder caps fields at two; a third field returns `resource-limit stage=csv`.

Output is deterministic UTF-8 CSV with LF endings:

```csv
kind,x,y,value
minimum,0,0,
maximum,4,4,
area2,,,32
vertex,0,0,
vertex,4,0,
vertex,4,4,
vertex,0,4,
```

`minimum` and `maximum` give closed axis-aligned bounds. `area2` is the exact nonnegative signed twice-area of the counterclockwise hull; divide by two for ordinary area. This integer preserves half-unit areas. `vertex` rows omit the closing duplicate and collinear edge interior points. Empty input produces the header and `area2,,,0` only. One distinct point gives one vertex; collinear input gives its two extreme endpoints.

The hull accepts the entire `i32` coordinate domain. Area is explicitly bounded by the library's `i64` result: a valid hull whose exact twice-area exceeds `i64` produces `area-overflow stage=area` and no stdout. This is a result representation limit, not a coordinate restriction.

Options may use separate or `=` values:

| Option | Default | Meaning |
| --- | --- | --- |
| `--max-points N` | 1,048,576 | Maximum input records, including duplicates. |
| `--max-input-bytes N` | 16,777,216 | Maximum bytes read, including CSV syntax. |
| `--max-output-bytes N` | 16,777,216 | Maximum complete formatted output bytes. |
| `--max-work N` | 100,000,000 | Deterministic input-byte and geometry work budget. |
| `-h`, `--help` | | Print usage. |

Byte/point limits must fit nonnegative `i32`; work fits `u64`. Repeated options, operands, unknown options and malformed numbers fail at `stage=arguments`. The work charge is input bytes plus `hull_work_bound(input_records) + 4*input_records`. This explicitly bounds sort/scan and linear result passes; it is an algorithmic work unit rather than an instruction or elapsed-time count. Output bytes are independently bounded. Limits at exactly the necessary counts are accepted.

Diagnostics go to stderr as `shape-hull: REASON stage=STAGE`, optionally with zero-based `row=N`. Stages are `arguments`, `input`, `csv`, `coordinate`, `hull`, `area`, `output`. Reasons distinguish malformed arguments, I/O, CSV, coordinates, resource limits, area overflow and allocation failure. Exit codes are `0` success, `2` input/resource/numerical errors, `3` I/O failure, and `4` allocation failure. Interrupted reads/writes are retried through descriptor I/O. A write failure can leave a prefix on stdout after publication starts; prior input or analysis errors emit no stdout.

The decoder, input points, hull, output bytes and argument snapshot each have one active owner. All success and failure paths release them. Tests deny every observed allocation in successful executions, reconcile native `mmap`/`munmap` events, inject read/write errors, exercise `/dev/full`, compare deterministic shuffled inputs against Python integer models, and include a 12,004-record streaming/sorting case.
