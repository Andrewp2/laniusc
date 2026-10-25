mod common;

use laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib;

fn compile_fixture(name: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_stdlib(&entry, &stdlib))
    })
    .expect("compile portable calendar fixture")
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(bytes: &[u8], name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let executable = common::TempArtifact::new("laniusc_calendar", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn run(executable: &common::TempArtifact, arguments: &[String]) -> String {
    let output = common::short_process_output_with_timeout(
        "native calendar case",
        std::process::Command::new(executable.path()).args(arguments),
    );
    assert_eq!(output.status.code(), Some(0), "{arguments:?}: {output:?}");
    assert!(output.stderr.is_empty(), "{arguments:?}: {output:?}");
    String::from_utf8(output.stdout).unwrap()
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn python(source: &str) -> String {
    let output = common::short_process_output_with_timeout(
        "Python calendar reference",
        std::process::Command::new("python3").args(["-c", source]),
    );
    assert!(output.status.success(), "{output:?}");
    String::from_utf8(output.stdout).unwrap()
}

#[test]
fn civil_calendar_algebra_and_checked_boundaries_execute() {
    for name in ["calendar_contracts", "calendar_algebra"] {
        let bytes = compile_fixture(name);
        #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
        {
            let exe = executable(&bytes, name);
            let output = common::process_output_with_timeout(
                name,
                &mut std::process::Command::new(exe.path()),
                std::time::Duration::from_secs(10),
            );
            assert_eq!(output.status.code(), Some(0), "{output:?}");
            assert!(
                output.stdout.is_empty() && output.stderr.is_empty(),
                "{output:?}"
            );
            if name == "calendar_contracts"
                && std::process::Command::new("strace")
                    .arg("-V")
                    .output()
                    .is_ok()
            {
                let output = common::short_process_output_with_timeout(
                    "calendar requires no allocator syscalls",
                    std::process::Command::new("strace")
                        .args(["-qq", "-e", "trace=brk,mmap,mremap"])
                        .arg(exe.path()),
                );
                assert_eq!(output.status.code(), Some(0), "{output:?}");
                assert!(
                    output.stdout.is_empty() && output.stderr.is_empty(),
                    "{output:?}"
                );
            }
        }
        #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
        let _ = bytes;
    }
}

#[test]
fn calendar_matches_independent_python_datetime_and_calendar() {
    let bytes = compile_fixture("calendar_model");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let exe = executable(&bytes, "calendar_model");
        let oracle = python(
            r#"
import calendar, datetime, random
r = random.Random(0xCA1E2026)
dates = [(1,1,1), (9999,12,31), (1582,10,4), (1582,10,15),
         (1900,2,28), (2000,2,29), (1969,12,31), (1970,1,1),
         (1995,1,1), (1996,12,31), (2020,12,31), (2021,1,1)]
for _ in range(388):
    y, m = r.randint(1,9999), r.randint(1,12)
    last = calendar.monthrange(y,m)[1]
    dates.append((y,m,r.choice([1,last,r.randint(1,last)])))
epoch = datetime.date(1970,1,1)
for y,m,d in dates:
    h,mi,s = r.randrange(24),r.randrange(60),r.randrange(60)
    n = r.choice([0,1,999999999,r.randrange(1000000000)])
    offset = r.choice([-1439,-720,-1,0,1,330,1439,r.randrange(-1439,1440)])
    value = datetime.datetime(y,m,d,h,mi,s)
    day = value.date()
    iso = day.isocalendar()
    seconds = calendar.timegm(value.timetuple()) - offset*60
    print(y,m,d,h,mi,s,n,offset, (day-epoch).days,day.isoweekday(),
          day.timetuple().tm_yday,iso.year,iso.week,iso.weekday,seconds,n)

# Independent January-based scalar model, rather than the production
# March-based eras. Python calendar supplies month lengths for all integer years.
wide = random.Random(0xCA1E5A17)
def leap(y): return y%4 == 0 and (y%100 != 0 or y%400 == 0)
def prior_years(y):
    previous = y-1
    return 365*previous + previous//4 - previous//100 + previous//400
before_month = (0,31,59,90,120,151,181,212,243,273,304,334)
dates = []
for y in (-2147483648,-2147483647,-401,-400,-101,-100,-4,-1,0,1,
          4,100,400,2147483646,2147483647,2000):
    for m,d in ((1,1),(1,4),(2,28),(3,1),(6,30),(12,28),(12,31),(2,1),(9,30),(10,1)):
        dates.append((y,m,d))
for _ in range(1000):
    y,m = wide.randint(-2147483648,2147483647),wide.randint(1,12)
    dates.append((y,m,wide.randint(1,calendar.monthrange(y,m)[1])))
for y,m,d in dates:
    h,mi,s = wide.randrange(24),wide.randrange(60),wide.randrange(60)
    n,offset = wide.randrange(1000000000),wide.randint(-1439,1439)
    ordinal = before_month[m-1] + d + (leap(y) and m>2)
    absolute = prior_years(y)+ordinal-1
    serial,weekday = absolute-prior_years(1970),absolute%7+1
    assert weekday == calendar.weekday(y,m,d)+1
    iy,thursday = y,ordinal+4-weekday
    if thursday < 1:
        iy -= 1
        thursday += 365+leap(iy)
    elif thursday > 365+leap(y):
        iy += 1
        thursday -= 365+leap(y)
    week = (thursday-1)//7+1
    seconds = serial*86400+h*3600+mi*60+s-offset*60
    print(y,m,d,h,mi,s,n,offset,serial,weekday,ordinal,iy,week,weekday,seconds,n)
"#,
        );
        for row in oracle.lines() {
            let values: Vec<&str> = row.split_whitespace().collect();
            assert_eq!(values.len(), 16, "{row}");
            let arguments: Vec<String> = values[..8].iter().map(|s| s.to_string()).collect();
            let actual = run(&exe, &arguments);
            let actual: Vec<i64> = actual.lines().map(|s| s.parse().unwrap()).collect();
            let expected: Vec<i64> = values[8..].iter().map(|s| s.parse().unwrap()).collect();
            assert_eq!(actual, expected, "{arguments:?}");
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}

#[test]
fn rfc3339_roundtrips_precision_offsets_and_reports_malformed_input() {
    let bytes = compile_fixture("calendar_rfc3339_model");
    #[cfg(all(target_os = "linux", target_arch = "x86_64"))]
    {
        let exe = executable(&bytes, "calendar_rfc3339_model");
        let oracle = python(
            r#"
import calendar, datetime, random
r = random.Random(0x3339)
for _ in range(160):
    y,m = r.randrange(1,10000),r.randrange(1,13)
    d = r.randrange(1,calendar.monthrange(y,m)[1]+1)
    h,mi,s = r.randrange(24),r.randrange(60),r.randrange(60)
    precision = r.randrange(10)
    fraction = ''.join(str(r.randrange(10)) for _ in range(precision))
    nanos = int(fraction.ljust(9,'0')) if precision else 0
    minutes = r.choice([-1439,-1,0,1,330,1439,r.randrange(-1439,1440)])
    unknown = r.randrange(8) == 0
    if unknown: minutes = 0
    offset = ('-' if minutes < 0 or unknown else '+') + f'{abs(minutes)//60:02}:{abs(minutes)%60:02}'
    if minutes == 0 and not unknown and r.randrange(2): offset = 'Z'
    base = f'{y:04}-{m:02}-{d:02}T{h:02}:{mi:02}:{s:02}'
    text = base + ('.'+fraction if precision else '') + offset
    canonical = base + ('.'+fraction if precision else '') + ('Z' if minutes==0 and not unknown else offset)
    seconds = calendar.timegm(datetime.datetime(y,m,d,h,mi,s).timetuple()) - minutes*60
    if r.randrange(2): text = text.lower()
    print(text,precision,nanos,0 if unknown else 1,minutes,12 if unknown else 0,0 if unknown else seconds,canonical)
"#,
        );
        for row in oracle.lines() {
            let values: Vec<&str> = row.split_whitespace().collect();
            let actual = run(&exe, &[values[0].to_owned()]);
            let expected = format!("0\n{}\n", values[1..].join("\n"));
            assert_eq!(actual, expected, "{}", values[0]);
        }
        for (text, precision, nanos, known, offset, conversion, canonical) in [
            (
                "1990-12-31T23:59:60Z",
                0,
                0,
                1,
                0,
                13,
                "1990-12-31T23:59:60Z",
            ),
            (
                "1990-12-31T15:59:60-08:00",
                0,
                0,
                1,
                -480,
                13,
                "1990-12-31T15:59:60-08:00",
            ),
            (
                "2026-01-01T00:00:60.000000001-00:00",
                9,
                1,
                0,
                0,
                12,
                "2026-01-01T00:00:60.000000001-00:00",
            ),
        ] {
            assert_eq!(
                run(&exe, &[text.into()]),
                format!(
                    "0\n{precision}\n{nanos}\n{known}\n{offset}\n{conversion}\n0\n{canonical}\n"
                )
            );
        }
        assert_eq!(
            run(&exe, &["0000-01-01T00:00:00Z".into()]),
            "0\n0\n0\n1\n0\n0\n-62167219200\n0000-01-01T00:00:00Z\n"
        );
        for (text, code, position) in [
            ("", 14, 0),
            ("2020-01-01T00:00:00", 14, 19),
            ("2020-00-01T00:00:00Z", 1, 5),
            ("2020-13-01T00:00:00Z", 1, 5),
            ("1900-02-29T00:00:00Z", 2, 8),
            ("2020-04-31T00:00:00Z", 2, 8),
            ("2020-01-00T00:00:00Z", 2, 8),
            ("2020-01-01T24:00:00Z", 6, 11),
            ("2020-01-01T00:60:00Z", 7, 14),
            ("2020-01-01T00:00:61Z", 8, 17),
            ("2020-01-01T00:00:00.Z", 14, 20),
            ("2020-01-01T00:00:00.1234567890Z", 15, 29),
            ("2020-01-01T00:00:00.0000000000Z", 15, 29),
            ("2020-01-01T00:00:00+24:00", 10, 20),
            ("2020-01-01T00:00:00+00:60", 10, 23),
            ("2020-01-01T00:00:00+01:0", 14, 24),
            ("2020-01-01T00:00:00+0100", 14, 24),
            ("2020-01-01T00:00:00+01-00", 14, 22),
            ("2020-01-01T00:00:00Zx", 14, 20),
            ("2020-01-01 00:00:00Z", 14, 10),
            ("2020-01-01T00:00:00,1Z", 14, 19),
            ("+2020-01-01T00:00:00Z", 14, 0),
            ("10000-01-01T00:00:00Z", 14, 4),
            ("2020-01-01T00:00:00Z ", 14, 20),
            ("2020-01-01T00:00:00Z\n", 14, 20),
        ] {
            assert_eq!(
                run(&exe, &[text.into()]),
                format!("{code}\n{position}\n"),
                "{text:?}"
            );
        }
        let base = "2020-01-01T12:34:56Z";
        for position in 0..base.len() {
            let mut malformed = base.as_bytes().to_vec();
            malformed[position] = b'?';
            let malformed = String::from_utf8(malformed).unwrap();
            assert_eq!(
                run(&exe, &[malformed.clone()]),
                format!("14\n{position}\n"),
                "{malformed}"
            );
        }
    }
    #[cfg(not(all(target_os = "linux", target_arch = "x86_64")))]
    let _ = bytes;
}
