# TZif time zones and timezone-tool

`ext::timezone` reads supplied TZif bytes and converts POSIX timestamps using
historical transitions and explicit POSIX future rules. It is an optional Lanius
library: add `--source-root extended` alongside `--stdlib-root stdlib`. Production
parsing, rule expansion, conversion and the example program are entirely Lanius.
The caller supplies a zone file; this module does not discover the host zone,
load the IANA database, resolve zone identifiers or update rules automatically.

## Time scale and supported input

The format source is [RFC 9636](https://www.rfc-editor.org/rfc/rfc9636.html),
especially §§3–4. The parser accepts TZif versions 1, 2, 3 and 4 on the **POSIX
Unix time scale**, with zero leap records in the authoritative data block.
Nonzero leap records return `UnsupportedLeapScale`, including version 4
truncation/expiration records. Such files use UNIX leap time and cannot safely
be interpreted as `core::time::SystemTime` seconds. A civil second of 60 returns
`LeapSecond`; nanoseconds must be below one billion.

For versions 2–4 the 64-bit block is authoritative. The legacy block's size and
physical bounds are checked, but its records are skipped rather than
interpreted. Both headers must identify the same version. Version 1 must end
at its data block; versions 2–4 must end at the footer's final newline.

Validation includes checked whole-block sizes before narrowing, nonzero type
and designation counts, strictly increasing signed transition times, type and
designation indices, NUL termination, the forbidden offset `i32::MIN`, Boolean
DST/standard/UT indicators and the UT-implies-standard rule. Reserved header
bytes are ignored. Offset seconds are preserved exactly, including historical
second offsets and unusual values outside the recommended range. Designation
strings may overlap or be empty. For legacy-reader tolerance, their nonzero
bytes are preserved without ASCII/UTF-8 validation or a numeric-name fallback;
callers must encode them safely for display. This deliberately differs from
RFC 9636 §4's recommended fallback for nonportable designation bytes.

The footer supports fixed offsets and explicit DST rules: alphabetic names or
`<alphanumeric+->` names of at least three bytes; signed offsets; `Jn`, `n` and
`Mm.w.d` dates; optional transition times; default transition time 02:00; and
default daylight offset one hour east of standard time. POSIX offsets count
westward, while returned `offset_seconds` counts eastward. Version 2 transition
hours are unsigned 0–24; versions 3–4 allow signed hours through 167, with
minutes/seconds 0–59. Explicit offset hours are 0–24 with optional minute and
second fields. A DST name without explicit rules returns `MissingRule` because
its host-selected default rules are not portable. Colon-prefixed zone names,
time-basis suffixes such as `u`, extra footer data and malformed grammar are
rejected. Nonempty footers must agree with the final explicit transition's
offset, DST flag and designation.

### Future rule expansion

Rule dates use the proleptic Gregorian calendar. Start times use the standard
offset; end times use the daylight offset, including negative DST. Signed hours
can move either event across its nominal day or year. Each query expands annual
events around the UTC year and selects the most recent event at or before the
requested second.

The annual event guard follows the primary
[IANA tzcode source, commit 42be76f9fd1e5e48f05d9d98076b4e1d482238d3,
`localtime.c` lines 1608–1649](https://github.com/eggert/tz/blob/42be76f9fd1e5e48f05d9d98076b4e1d482238d3/localtime.c#L1608):
reversed annual start/end order emits both events; ordinary order emits them
only when their positive separation is shorter than that year's length. If a
complete Gregorian 400-year cycle emits no events, DST is perpetual. This
handles the all-year cases described in RFC 9636 §3.3.1 and the signed-hour
extension in §3.3.2. A query with no nearby event searches up to 400 additional
years, covering skipped-year rules and Gregorian century boundaries.

Parsing also checks 401 annual pairs over a Gregorian cycle and its closing
boundary. `UnsupportedRule` rejects extended rules whose emitted pairs overlap
or tie across years. Their event stream would cease to be strictly
chronological; this module does not assign an additional ordering policy to
those cases. Ordinary northern/southern IANA rules, non-hour shifts, negative
DST, all-year rules and nonoverlapping year-spill rules remain supported.

Two synthetic controls make unusual behavior explicit. For
`AAA0BBB,365/167,364/166`, annual 1898 events end DST at 1899-01-06 21:00 UTC and
start it at 1899-01-07 23:00 UTC. Consequently 1899-01-07 12:00 UTC is standard
time. Python 3.12.3 `zoneinfo`'s footer evaluation and glibc 2.39's `TZ` evaluation
instead report DST there. Tests use an independently expanded explicit-transition
TZif file as the control for the pinned IANA event semantics. For
`AAA0BBB,0/0,365/1`, the annual guard emits events only in leap years; tests cover
the 2096–2104 gap. These policies are not claims that all TZ readers agree on
exotic rule strings.

The grammar's other primary source is
[POSIX.1-2024, Base Definitions §8.3](https://pubs.opengroup.org/onlinepubs/9799919799/basedefs/V1_chap08.html).

## API

```lanius
import ext::timezone;

let parsed = ext::timezone::parse(input_view,ext::timezone::default_limits());
// Handle Err before taking ownership.
let zone: ext::timezone::Zone = parsed.unwrap();
let value = zone.to_local(instant);
let matches = zone.candidates(civil);
// A successful candidates result owns a Vec, even when empty.
if (matches.is_ok()) { let values = matches.unwrap(); values.destroy(); }
zone.destroy();
```

| Operation | Result/meaning |
| --- | --- |
| `parse(View<u8>, Limits)` | Owned `Zone`, or a classified error |
| `zone.borrow()` | Borrow for functions taking `&Zone` |
| `version()`, `transition_count()`, `type_count()` | Parsed metadata |
| `footer()` | Borrowed raw TZ string, excluding newline delimiters |
| `type_at(index)` | Raw `Info`, including a `-00` placeholder if present |
| `transition_at(index)` | Raw `Transition { unix_seconds, info }` |
| `offset_at(unix_seconds)` | Applicable `Info` or a coverage/range/work error |
| `to_local(SystemTime)` | `Local { instant, civil, info }`; nanoseconds preserved |
| `candidates(LocalDateTime)` | Owned `Vec<Candidate>` in ascending UTC order |
| `resolve(civil, Resolution)` | `Candidate`, `Gap` or `Ambiguous` |
| `destroy()` | Release storage and clear metadata; repeat on this same owner is safe |

`Info` contains `offset_seconds: i32`, `is_dst: bool` and borrowed
`abbreviation: View<u8>`. `Candidate` contains `instant` and `info`.
`Resolution::Reject` accepts exactly one candidate, `Earliest` selects the first,
and `Latest` selects the last. There is no automatic gap shift or silent fold
choice. `candidates` returns an empty vector for a known gap and can return more
than two values for arbitrary transition tables. It checks every distinct
possible UTC instant obtained from all table and footer offsets, verifies the
active offset there, deduplicates and sorts. A synthetic four-way fold tests
this behavior independently of Python's two-valued `fold` interface.

Before the first explicit transition, type 0 applies. With no transitions, a
nonempty footer applies throughout; with no transitions and an empty footer,
type 0 is fixed throughout. With transitions and no footer, times at or after
the last transition return `Unspecified`. A selected `-00` designation also
returns `Unspecified`.

Local resolution additionally refuses a completeness claim if any unspecified
UTC interval intersects `naive_local_seconds ± 2147483647`. This covers every
representable TZif offset except the forbidden minimum. It is intentionally
conservative: a truncated table can make local resolution unavailable roughly
68 years beyond an unknown boundary even when one known candidate appears
plausible. A relevant active `-00` footer name is treated conservatively too; the ignored
standard name in a perpetual-DST rule cannot make coverage unknown.
UTC-to-local conversion only requires coverage at the requested instant.

`core::calendar` offsets have minute precision; this library shifts Unix
seconds itself and uses calendar UTC conversion, retaining second precision.
Civil output is limited to the calendar's `i32` years. Nonperpetual recurring DST queries
require UTC years from -2147483246 through 2147483645, leaving room for bounded
rule expansion; outside that range they return `YearRange`. Fixed offsets, perpetual DST and
historical `offset_at` queries can use the full `i64` seconds range. Offset
addition is checked (`Overflow`), and civil conversion beyond calendar bounds
returns `YearRange`.

### Ownership and limits

Parsing validates before allocating and then copies the selected input view.
The input can be released or changed after success. Input metadata must have
nonnegative `start` and `length` with a representable end; as with other manual
Lanius views, the caller supplies physically valid backing storage throughout
parsing. `Zone` owns one allocation. Owners copy shallowly: retain one active
owner, do not mutate its implementation fields, and destroy it once. Every
returned designation/footer view borrows that zone and becomes invalid when it
is destroyed. Destroying a candidate vector does not destroy its designation
bytes. Candidate errors release partial vector storage, and parsing failures
return no owner.

| `Limits` field | Default |
| --- | ---: |
| `max_input` | 4,194,304 bytes |
| `max_transitions` | 200,000 |
| `max_types` | 256 |
| `max_designations` | 65,536 bytes |
| `max_footer` | 4,096 bytes |
| `max_candidates` | 258 |
| `max_work` | 33,554,432 units per parse/query |

Limits are explicit, independently checked budgets, not a promise that every
combination below the other limits fits `max_work`. Work units are deterministic
algorithmic charges: input bytes, validation records and scanned name bytes;
two per expanded annual pair (802 for cycle validation); reserved name-scan
costs, binary-search comparisons, candidate attempts, deduplication comparisons
and insertion swaps. A query receives a fresh budget; no cumulative hidden
quota or dynamic allocation occurs during `offset_at`/`to_local`.

Errors distinguish invalid view/limits, resource limits, allocation failure,
truncation/magic/version/counts, transition order, type indices, offset,
indicators/designations, footer/invalid rules/missing rules/inconsistent footer,
unsupported leap scale/rule chronology, unknown coverage, invalid civil time,
leap seconds, year range, overflow, gaps, ambiguity and destroyed owners.

## Executable consumer

Build and run `sample_programs/library/timezone_tool.lani`:

```sh
target/stdlib-build/debug/laniusc --stdlib-root stdlib --source-root extended \
  sample_programs/library/timezone_tool.lani -o /tmp/timezone-tool
/tmp/timezone-tool info < /usr/share/zoneinfo/America/New_York
/tmp/timezone-tool at 1730611800 --nanos 123 < /usr/share/zoneinfo/America/New_York
/tmp/timezone-tool --nanos 123 at -- -3786825600 < /usr/share/zoneinfo/Europe/Dublin
/tmp/timezone-tool local 2024-11-03T01:30:00 --resolve all \
  < /usr/share/zoneinfo/America/New_York
```

The program reads one TZif file from stdin. `info` reports version, transition
and type counts, footer and all raw time types. `at SECONDS` emits one converted
CSV row. `local YYYY-MM-DDTHH:MM:SS[.NNNNNNNNN]` emits all candidates by default,
or selects `--resolve reject|earliest|latest`. CLI civil years are the RFC3339
four-digit range; the library has the broader range above. Negative Unix
operands require `--` after other options. `--nanos` applies only to `at`;
`--resolve` applies only to `local`. Duplicate options, extra operands and
inapplicable options are errors. `--help`/`-h` must appear alone.

Conversion CSV columns are `candidate,count,unix_seconds,nanos,year,month,day,
hour,minute,second,offset_seconds,is_dst,designation`. Candidate indices are
zero-based in the complete ordered set, including when a policy selects one
row. ASCII alphanumerics, `+` and `-` pass through in designation/footer fields;
every other byte becomes `\xhh`, keeping arbitrary source bytes safe in CSV.

The program combines `std::args`, `ext::cli`, `alloc::io`, `core::io`,
`core::fmt`, calendar/time and the new zone library. It validates arguments,
reads input with a bound, releases the input after copying, completes conversion
and formatting into an owned output buffer, then writes stdout. Parsing,
resolution, allocation and output-limit failures emit no stdout. An actual
write failure can leave a written prefix; interrupted and positive short
writes are handled by `core::io::write_all`.

| CLI budget option | Default | Maximum accepted |
| --- | ---: | ---: |
| `--max-input-bytes` | 4,194,304 | 67,108,864 |
| `--max-transitions` | 200,000 | 1,000,000 |
| `--max-candidates` | 258 | 65,536 |
| `--max-work` | 33,554,432 | 1,000,000,000 |
| `--max-output-bytes` | 1,048,576 | 16,777,216 |

Exit statuses are 0 success, 2 invalid arguments/data/time, gap, rejected fold,
unknown coverage or unsupported time scale/rule; 3 resource limit; 4 allocation
failure; and 5 I/O failure. Stderr identifies the reason and stage: 0 arguments,
1 input, 2 parsing, 3 conversion/formatting, 4 writing.

## Executed evidence and scope

`tests/extended_timezone_execution.rs` compiles and executes ownership contracts
and a binary model fixture against `timezone_oracle.py`. It covers 222 TZif
vectors and 7,291 queries: 12 installed IANA zones, historical and future dates
through year 9990, exact transition boundaries, seeded local times, gaps/folds,
negative/non-hour/southern DST, independent annual-transition controls,
four-way folds, malformed prefixes/counts/flags/footer grammar, leap rejection,
work/size/candidate limits, raw designations, i64 boundaries and a 30,000
transition workload. The model uses an offset input view and frees source bytes
before querying. The runtime contract fixture checks copied names, view bounds,
resolution, manual cleanup and destroyed-owner behavior.

`tests/extended_timezone_tool_execution.rs` compiles the actual program and runs
`timezone_tool_oracle.py`: historical/future CSV comparisons, all resolution
policies, argument limits and staged errors, plus every allocation in a
four-candidate run failing individually. Linux `strace` checks a mapping ledger
on success and late failures; EINTR/EIO, positive short writes and `/dev/full`
exercise cleanup and I/O behavior. These native execution tests require Linux
x86_64, Python 3 with `zoneinfo`, installed IANA files and `strace`; the production
library does not require Python, a host timezone API or a platform timezone
service. The recorded reference environment was Python 3.12.3 with tzdata 2026e.
