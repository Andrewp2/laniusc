# Civil dates and RFC 3339

`core::calendar` provides Gregorian dates, local times, numeric UTC offsets,
checked date arithmetic, conversions to `core::time::SystemTime`, and timestamp
parsing and formatting. All production code is portable Lanius, with no heap
allocation or host services. The executable evidence is **x86_64 Linux using
the GPU compiler**; these tests do not establish execution on other targets.

## Values and constructors

Values copy and need no destruction. Use checked constructors and preserve their
fields. Field privacy is not enforced by the language. Date queries and date
arithmetic require valid dates; timestamp construction, formatting, and system
time conversion revalidate their component fields.

| Type | Fields and meaning |
| --- | --- |
| `Date` | `year: i32`, `month: i32`, `day: i32` |
| `TimeOfDay` | `hour: i32`, `minute: i32`, `second: i32`, `nanos: u32` |
| `LocalDateTime` | `date: Date`, `time: TimeOfDay` |
| `UtcOffset` | `minutes: i32`, `known: bool`; minutes are local time minus UTC |
| `OffsetDateTime` | `local: LocalDateTime`, `offset: UtcOffset` |
| `IsoWeek` | `year: i64`, `week: i32`, `weekday: i32` |
| `ParsedDateTime` | `value: OffsetDateTime`, `fraction_digits: i32` |

The calendar applies Gregorian rules in every year, including before 1582.
The full `i32` year range is supported. Astronomical year 0 means 1 BCE; year -1
means 2 BCE. Civil computations use `i64` intermediates, including before year 0.

| Function | Result and validation |
| --- | --- |
| `is_leap_year(year)` | `bool`; divisible by 4, except centuries not divisible by 400 |
| `days_in_month(year, month)` | `Result<i32, Error>`; month must be 1–12 |
| `date(year, month, day)` | `Result<Date, Error>`; checks the actual month length |
| `minimum_date()`, `maximum_date()` | First day of `i32::MIN`, last day of `i32::MAX` |
| `time_of_day(hour, minute, second, nanos)` | `Result<TimeOfDay, Error>`; hours 0–23, minutes 0–59, seconds 0–60, nanos below one billion |
| `local_date_time(date, time)` | `Result<LocalDateTime, Error>`; checks both components |
| `utc()` | Known zero offset |
| `unknown_offset()` | Unknown offset with zero minutes; preserved as `-00:00` |
| `utc_offset(minutes)` | `Result<UtcOffset, Error>`; known offset from -1439 through 1439 minutes |
| `offset_date_time(local, offset)` | `Result<OffsetDateTime, Error>`; validates local fields and offset |

Unknown offsets must have zero minutes. There are no named zones, daylight
saving rules, locale settings, automatic clock reads, or historical calendar
cutovers in this module.

## Date coordinates and arithmetic

`Date.day_number()` returns `i64` days since 1970-01-01. Adjacent civil dates
differ by one, including across year 0. `date_from_day_number(i64)` returns
`Overflow` outside the native year range. `Date.weekday()` returns Monday as 1
through Sunday as 7. `Date.ordinal()` returns January 1 as 1; the final day is
365 or 366. `date_from_ordinal(year, ordinal)` validates that year's range.

`Date.iso_week()` returns an ISO week year, week number, and Monday-based
weekday. `date_from_iso_week(year: i64, week: i32, weekday: i32)` checks whether
the requested week exists and whether the resulting civil date is representable.
The week year is `i64` so a date at a native year boundary can still describe
its adjoining ISO week year. The ISO week starts on Monday, and week 1 contains
January 4. The civil algorithms and ISO conversion follow the 400-year-era
derivation in [Howard Hinnant's date algorithms](https://howardhinnant.github.io/date_algorithms.html).

| Date method | Behavior |
| --- | --- |
| `compare(other)` | -1, 0, or 1, in civil order |
| `days_since(earlier)` | Exact signed `i64` day difference |
| `checked_add_days(i64)` | `Result<Date, Error>`; full-width deltas are checked before addition |
| `checked_sub_days(i64)` | Checked subtraction, including an `i64::MIN` argument |
| `checked_add_months(i64)` | Keeps the day number; rejects a nonexistent target day |
| `checked_add_years(i64)` | Keeps month and day; rejects a nonexistent target day |

Month and year addition never clamp. January 31 plus one month returns
`InvalidDay` when February cannot contain that date. February 29 plus one year
also returns `InvalidDay`; adding 400 years succeeds when the native range
allows it. Day arithmetic returns `Overflow` when the result exceeds that range.

## Comparison and collection keys

`Date`, `TimeOfDay`, and `LocalDateTime` implement `core::cmp::Eq`, `Ord`,
`PartialEq`, `PartialOrd`, and `core::hash::Hash`. Each exposes
`compare(other)`, returning -1, 0, or 1. The civil ordering is lexicographic:

- `Date`: year, month, day.
- `TimeOfDay`: hour, minute, second, nanoseconds.
- `LocalDateTime`: date, then time.

This orders all native years without narrowing a difference to `i32` or
flattening a date and time into overflowing nanoseconds. `partial_cmp` always
returns `Less`, `Equal`, or `Greater` for these types and agrees with the total
order. Equality compares every represented civil field, and equal values hash
equally. Hashes use noncryptographic 32-bit FNV-1a over component values.

Represented second 60 sorts after second 59 in its minute and before the next
minute. Thus `00:00:59.999999999 < 00:00:60 < 00:01:00`. This is the order of
civil syntax; it does not certify leap-second placement or elapsed duration.
The first instant of the next civil date sorts after every time on the prior
date, including represented `23:59:60.999999999`.

`UtcOffset` and `OffsetDateTime` implement `Eq`, `PartialEq`, and `Hash` with
**representation equality**. Unknown `-00:00` differs from known UTC. An offset
timestamp's identity contains its local date, all time fields, and both offset
fields. For example, `1970-01-01T00:00:00Z` and
`1970-01-01T01:00:00+01:00` are different hash-map keys, although their successful
`to_system_time()` conversions compare equal. Separately constructed known
zero offsets, including parsed `+00:00`, equal `utc()`.

Offset types expose no `Ord`, `PartialOrd`, or civil `compare` method. For
chronological comparison of known ordinary timestamps, explicitly convert both
with `to_system_time()` and compare the results, handling `UnknownOffset` and
`LeapSecond` errors. Representation equality remains useful for retaining the
supplied offset or preserving unknown-offset records.

These comparison and key contracts require constructor-valid values with their
fields preserved. The language does not enforce that precondition. Calendar
values own no resources, so storing them in a collection adds no separate key
destruction duty; release the collection's own allocation normally.

## Unix time conversion

`to_system_time(value)` and `value.to_system_time()` return
`Result<core::time::SystemTime, Error>`. The result subtracts the known numeric
offset from local civil seconds and preserves nanoseconds. Native dates fit
the signed `SystemTime` second range without flattening into nanoseconds.

`from_system_time(value, offset)` returns `Result<OffsetDateTime, Error>` at a
known offset. It checks signed-second overflow before applying the offset and
returns `Overflow` if the resulting civil date exceeds the native year range.
Negative fractional timestamps retain the `SystemTime` convention: `(-1, 1)`
is 1969-12-31T23:59:59.000000001Z.

`value.to_offset(offset)` preserves the instant while changing its local
representation. Conversion at either end of the date range can fail if the
new offset moves the local date beyond that range.

Unknown offsets return `UnknownOffset` from both conversion directions.
[RFC 3339 §4.3](https://www.rfc-editor.org/rfc/rfc3339.html#section-4.3) gives
`-00:00` distinct semantics from UTC. This API conservatively requires a known
offset before conversion; a caller that chooses UTC must explicitly construct
the timestamp with `utc()`.

`TimeOfDay.is_leap_second()` tests `second == 60`. Such values retain leap-second
syntax, but system conversion returns `LeapSecond`. The API has no leap-second
announcement table and never maps second 60 onto a POSIX second.

## Timestamp syntax and precision

`parse_rfc3339(input: core::slice::View<u8>)` returns
`Result<ParsedDateTime, ParseError>`. `ParseError` contains `kind: Error` and
`position: i32`, a byte index relative to the input view; a missing byte uses
the input length. Parsing consumes the complete view. It accepts lowercase
`t` and `z`, requires the `T` separator and numeric offset colon, and rejects
spaces, surrounding whitespace, suffixes, and hour 24. The timestamp grammar
comes from [RFC 3339 §§5.6–5.7](https://www.rfc-editor.org/rfc/rfc3339.html#section-5.6).

The timestamp boundary requires four year digits, 0000–9999. Fraction precision
is explicitly limited to 1–9 decimal digits after a dot; a tenth digit returns
`FractionPrecision`, including a zero digit. Nothing is rounded or truncated.
An absent fraction records zero digits. `ParsedDateTime.fraction_digits`
preserves the precision while the value stores exact nanoseconds.

Second 60 is accepted syntactically at any local minute, preserved, and formatted
unchanged. Parsing does **not** certify that an actual leap second occurred on
that date or at that offset. Applications requiring that certification must
check external leap-second data. Ordinary date and clock bounds are checked.

`measure_rfc3339(value, fraction_digits)` returns `Result<i32, Error>`.
`format_rfc3339(value, fraction_digits, output: View<u8>)` returns the written
byte count in the same result type. Formatting requires an explicit precision
from 0 through 9. `PrecisionLoss` means that precision cannot exactly express
the stored nanoseconds. Zero precision omits the dot; positive precision emits
exactly that many digits. Years outside 0000–9999 return `YearOutOfRange`.

Output uses uppercase `T` and `Z`, known zero offsets use `Z`, and unknown zero
offsets use `-00:00`. A parsed `+00:00` therefore formats as `Z`. Other numeric
offsets keep their signed minute value. Original letter case and spelling are
not retained; fractional precision and unknown-offset meaning are retained.

The required output size is 20 bytes for UTC or 25 for a numeric/unknown offset,
plus a dot and the chosen fraction digits when nonzero. Formatting checks all
fields, precision, and capacity before its first write. Every returned error
leaves the output unchanged. Success writes exactly that many bytes with no
NUL terminator and leaves later bytes alone. Input and output may be subviews;
their nonzero starts and underlying slice strides are honored.

Use views produced by checked `core::slice::view`, `view_range`, or `subview`
with a physically backed count. As with the slice module, an overstated count
or a manually forged view does not acquire a memory-safety guarantee.

## Errors and evidence

`Error` distinguishes invalid month, day, ordinal, week, weekday, hour, minute,
second, nanoseconds, and offset; arithmetic `Overflow`; `UnknownOffset`;
`LeapSecond`; `InvalidSyntax`; `FractionPrecision`; `PrecisionLoss`;
`YearOutOfRange`; and `BufferTooSmall`. Constructors and civil arithmetic return
`Result<T, Error>`; the parser adds a byte position. Formatting does not use
ordinary absence or truncated output to report failure.

`tests/stdlib_calendar_execution.rs` compiles and executes four Lanius fixtures:

- Every day of one 146,097-day Gregorian era, 10,000 generated dates across
  native years, and both native endpoints: day, ordinal, and ISO inverses,
  400-year periodicity, next-day weekdays, and exact Unix-time round trips.
- 400 boundary/generated dates compared with independent Python `datetime` and
  `calendar` results for serial days, weekdays, ordinals, ISO weeks, and Unix
  seconds at numeric offsets. Seed: `0xCA1E2026`.
- Another 1,160 dates across native years compared with a separate January-based
  scalar model using cumulative Gregorian leap counts, with Python `calendar`
  checking month lengths and weekdays. Seed: `0xCA1E5A17`.
- 160 generated timestamp cases compared with Python, including fraction
  precision and unknown offsets; seed `0x3339`. Leap-second examples, year 0,
  malformed fields, separators, offsets, fractions, and suffixes have explicit
  runtime cases.
- Checked arithmetic limits, constructor failures, all short output capacities,
  unchanged output on format errors, input/output subviews, native strided bytes
  and packed argument bytes. When `strace` is available, the contract fixture
  must execute without `brk`, `mmap`, or `mremap` calls.

`tests/stdlib_calendar_keys_execution.rs` separately executes:

- 5,000 generated triples across native years: equality, hash consistency,
  complement/reversal predicates, total/partial ordering agreement, and
  transitivity through generic trait consumers. Same-day time comparisons,
  nanosecond boundaries, represented second 60, year 0, and native endpoints
  have explicit cases.
- 656 boundary/generated pairs compared with Rust tuple ordering and equality.
  Seed: `0xCA1E0ADE20261023`.
- Generic `Vec` sorting and search, civil range membership, `TreeMap` iteration
  and bounded traversal, and `HashMap` lookup/replacement/removal with all three
  civil types. Offset maps retain unknown versus known zero offsets, different
  representations of the same instant, leap-second syntax, and nanoseconds as
  distinct keys.

Run from the repository root:

```sh
timeout --kill-after=2s 100s env CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 cargo test --test stdlib_calendar_execution -- --test-threads=1
timeout --kill-after=2s 100s env CARGO_TARGET_DIR="$PWD/target/stdlib-build" CARGO_INCREMENTAL=0 CARGO_PROFILE_DEV_DEBUG=0 CARGO_PROFILE_TEST_DEBUG=0 LANIUS_GPU_CODEGEN_TEST_TIMEOUT_MS=90000 cargo test --test stdlib_calendar_keys_execution -- --test-threads=1
```
