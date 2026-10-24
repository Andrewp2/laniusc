//! Prevalidated CSV rows streamed through tiny format scratch and a buffered writer.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output, Stdio},
};

const MAX_INPUT: usize = 1_048_576;

fn executable() -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/library/format_report.lani");
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("format_report application", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("format_report: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_format_report", "executable", None);
    file.write_bytes(bytes); // Existing unchanged strict ELF/jump checker.
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}

fn calls<'a>(events: &'a str, name: &str) -> Vec<&'a str> {
    let prefix = format!("{name}(");
    events
        .lines()
        .filter(|line| line.starts_with(&prefix))
        .collect()
}
fn result<'a>(line: &'a str, name: &str) -> (&'a str, &'a str) {
    let body = line.strip_prefix(name).unwrap().strip_prefix('(').unwrap();
    let (arguments, value) = body
        .rsplit_once('=')
        .unwrap_or_else(|| panic!("missing result: {line}"));
    (
        arguments.trim_end().strip_suffix(')').unwrap(),
        value.trim(),
    )
}

#[derive(Debug)]
struct Memory {
    attempts: usize,
    successful: usize,
    failures: Vec<usize>,
}
fn memory(events: &str) -> Memory {
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut report = Memory {
        attempts: 0,
        successful: 0,
        failures: Vec::new(),
    };
    let mut released = Vec::new();
    let mut publishing = false;
    for line in events.lines() {
        if line.starts_with("write(") {
            publishing = true;
        }
        if line.starts_with("mmap(") {
            assert!(!publishing, "publication must not allocate: {events}");
            let (arguments, value) = result(line, "mmap");
            let mut fields = arguments.split(',').map(str::trim);
            assert_eq!(fields.next(), Some("NULL"), "{events}");
            let length: usize = fields.next().unwrap().parse().unwrap();
            assert!(length > 0, "{events}");
            report.attempts += 1;
            let address = value.split_whitespace().next().unwrap();
            if let Some(address) = address.strip_prefix("0x") {
                assert!(!value.contains("INJECTED"), "{events}");
                let address = u64::from_str_radix(address, 16).unwrap();
                assert!(
                    live.insert(address, (report.successful, length)).is_none(),
                    "duplicate live mapping: {events}"
                );
                report.successful += 1;
            } else {
                assert_eq!(address, "-1", "{events}");
                assert!(
                    value.contains("ENOMEM") && value.contains("INJECTED"),
                    "{events}"
                );
                report.failures.push(report.attempts);
            }
        } else if line.starts_with("munmap(") {
            let (arguments, value) = result(line, "munmap");
            assert_eq!(value, "0", "{events}");
            let (address, length) = arguments.split_once(',').unwrap();
            let address =
                u64::from_str_radix(address.trim().strip_prefix("0x").unwrap(), 16).unwrap();
            let (identity, owned_length) = live
                .remove(&address)
                .unwrap_or_else(|| panic!("unknown/double release: {events}"));
            assert_eq!(
                length.trim().parse::<usize>().unwrap(),
                owned_length,
                "{events}"
            );
            released.push(identity);
        } else if line.starts_with("mremap(") {
            panic!("typed owner relocation must not mremap: {events}");
        }
    }
    assert!(live.is_empty(), "unreleased owners {live:?}: {events}");
    assert_eq!(released.len(), report.successful, "{events}");
    report
}

struct Run {
    output: Output,
    events: String,
    memory: Memory,
}
fn run(
    executable: &common::TempArtifact,
    input: &[u8],
    args: &[&str],
    injections: &[&str],
    closed_stdout: bool,
) -> Run {
    let data = common::TempArtifact::new("laniusc_format_report", "stdin", None);
    data.write_bytes(input);
    let trace = common::TempArtifact::new("laniusc_format_report", "trace", None);
    let mut command = Command::new("timeout");
    command
        .args(["--kill-after=1s", "5s", "strace", "-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=rt_sigaction,read,write,mmap,mremap,munmap",
            "-e",
            "signal=none",
        ]);
    for injection in injections {
        command.arg("-e").arg(format!("inject={injection}"));
    }
    command
        .arg(executable.path())
        .args(args)
        .stdin(Stdio::from(fs::File::open(data.path()).unwrap()));
    if closed_stdout {
        let (reader, writer) = std::io::pipe().unwrap();
        drop(reader);
        command.stdout(writer);
    }
    // output preserves the actual closed pipe; the external timeout bounds it.
    let output = command.output().expect("bounded format_report native case");
    let events = fs::read_to_string(trace.path()).unwrap();
    for injection in injections {
        let syscall = injection.split(':').next().unwrap();
        let reached = calls(&events, syscall)
            .into_iter()
            .filter(|line| line.contains("INJECTED"))
            .collect::<Vec<_>>();
        if injection.ends_with('+') {
            assert!(
                !reached.is_empty() && reached.len() <= 4096,
                "unreached/unbounded {injection}: {events}"
            );
        } else {
            assert_eq!(reached.len(), 1, "unreached/repeated {injection}: {events}");
        }
        if let Some(tail) = injection.split("error=").nth(1) {
            assert!(
                reached[0].contains(tail.split(':').next().unwrap()),
                "{events}"
            );
        }
        if let Some(tail) = injection.split("retval=").nth(1) {
            assert_eq!(
                result(reached[0], syscall)
                    .1
                    .split_whitespace()
                    .next()
                    .unwrap(),
                tail.split(':').next().unwrap(),
                "{events}"
            );
        }
    }
    if injections.is_empty() {
        assert!(!events.contains("INJECTED"), "{events}");
    }
    let memory = memory(&events);
    Run {
        output,
        events,
        memory,
    }
}

fn checked(run: &Run, status: i32, stdout: &[u8], signal_ok: bool) {
    assert_eq!(
        run.output.status.code(),
        Some(status),
        "{:?}\n{}",
        run.output,
        run.events
    );
    assert_eq!(run.output.stdout, stdout, "{}", run.events);
    assert!(
        run.output.stderr.is_empty(),
        "{:?}\n{}",
        run.output,
        run.events
    );
    let actions = calls(&run.events, "rt_sigaction");
    assert_eq!(actions.len(), 1, "{}", run.events);
    assert!(
        actions[0].contains("SIGPIPE") && actions[0].contains("SIG_IGN"),
        "{}",
        run.events
    );
    if signal_ok {
        assert_eq!(result(actions[0], "rt_sigaction").1, "0", "{}", run.events);
    } else {
        assert!(
            actions[0].contains("EINTR") && actions[0].contains("INJECTED"),
            "{}",
            run.events
        );
    }
    let action = run
        .events
        .lines()
        .position(|line| line.starts_with("rt_sigaction("))
        .unwrap();
    if let Some(next) = run.events.lines().position(|line| {
        line.starts_with("mmap(") || line.starts_with("read(") || line.starts_with("write(")
    }) {
        assert!(action < next, "{}", run.events);
    }
    for read in calls(&run.events, "read") {
        assert!(read.starts_with("read(0,"), "{}", run.events);
    }
    for write in calls(&run.events, "write") {
        assert!(write.starts_with("write(1,"), "{}", run.events);
        let request: usize = result(write, "write")
            .0
            .rsplit_once(',')
            .unwrap()
            .1
            .trim()
            .parse()
            .unwrap();
        assert!(
            (1..=17).contains(&request),
            "buffered host request: {}",
            run.events
        );
    }
    if status == 0 || !calls(&run.events, "write").is_empty() {
        let reads = calls(&run.events, "read");
        assert_eq!(
            result(reads.last().unwrap(), "read").1,
            "0",
            "publication requires EOF: {}",
            run.events
        );
    }
    if matches!(status, 2 | 4 | 5) {
        assert!(calls(&run.events, "write").is_empty(), "{}", run.events);
    }
}
fn profile(run: &Run, attempts: usize, failed: Option<usize>) {
    assert_eq!(run.memory.attempts, attempts, "{}", run.events);
    if let Some(ordinal) = failed {
        assert_eq!(run.memory.failures, [ordinal], "{}", run.events);
        assert_eq!(run.memory.successful, attempts - 1, "{}", run.events);
    } else {
        assert!(run.memory.failures.is_empty(), "{}", run.events);
        assert_eq!(run.memory.successful, attempts, "{}", run.events);
    }
}

#[derive(Clone)]
struct Row {
    name: String,
    quantity: String,
    price: String,
}
fn row(name: &str, quantity: &str, price: &str) -> Row {
    Row {
        name: name.into(),
        quantity: quantity.into(),
        price: price.into(),
    }
}
fn csv_field(value: &str) -> String {
    format!("\"{}\"", value.replace('"', "\"\""))
}
fn input(rows: &[Row]) -> Vec<u8> {
    let mut input = String::from("name,quantity,unit_price\n");
    for row in rows {
        input.push_str(&format!(
            "{},{},{}\n",
            csv_field(&row.name),
            csv_field(&row.quantity),
            csv_field(&row.price)
        ));
    }
    input.into_bytes()
}
fn reference(rows: &[Row]) -> (i32, Vec<u8>) {
    if rows.len() > 256 {
        return (7, Vec::new());
    }
    let mut output = String::from("name\tquantity\tunit_price\tamount\n");
    for row in rows {
        if row.name.len() > 256 || row.quantity.len() > 128 || row.price.len() > 128 {
            return (7, Vec::new());
        }
        if row.name.is_empty() || row.name.bytes().any(|byte| byte < 32 || byte == 127) {
            return (2, Vec::new());
        }
        let Ok(quantity) = row.quantity.parse::<i64>() else {
            return (2, Vec::new());
        };
        let Ok(price) = row.price.parse::<f64>() else {
            return (2, Vec::new());
        };
        if !price.is_finite() {
            return (2, Vec::new());
        }
        let amount = (quantity as f64) * price;
        if !amount.is_finite() {
            return (5, Vec::new());
        }
        output.push_str(&format!(
            "{:<16}\t{:>20}\t{:>12.2}\t{:>12.2}\n",
            row.name, quantity, price, amount
        ));
    }
    output.push_str(&format!("rows={}\n", rows.len()));
    if output.len() > 65_536 {
        (7, Vec::new())
    } else {
        (0, output.into_bytes())
    }
}
fn no_publication(run: &Run) {
    assert!(calls(&run.events, "write").is_empty(), "{}", run.events);
}
fn request(line: &str) -> usize {
    result(line, "write")
        .0
        .rsplit_once(',')
        .unwrap()
        .1
        .trim()
        .parse()
        .unwrap()
}

#[test]
fn format_report_csv_preflight_streaming_and_exact_failure_cleanup() {
    let executable = executable();
    let mut native_cases = 0usize;
    let normal = vec![
        vec![],
        vec![row("apple", "2", "1.25")],
        vec![
            row("minimum", "-9223372036854775808", "0"),
            row("maximum", "9223372036854775807", "0.5"),
        ],
        vec![row("signed", "+0002", "-1.25"), row("zero", "-0", "-0.0")],
        vec![
            row("comma, quote\"", "-3", "+1.25e2"),
            row("é e\u{301} 🦀 漢字", "4", "0.125"),
        ],
        vec![
            row("round-even", "1", "0.125"),
            row("round-up", "1", "0.375"),
            row("binary", "1", "2.675"),
        ],
        vec![
            row("smallest", "1", "5e-324"),
            row("largest", "1", "1.7976931348623157e308"),
        ],
        vec![row("x".repeat(256).as_str(), "1", "1")],
        vec![row(
            "quantity-leading-zeroes",
            &format!("{}1", "0".repeat(127)),
            "1",
        )],
    ];
    for rows in normal {
        let data = input(&rows);
        let (status, expected) = reference(&rows);
        assert_eq!(status, 0);
        let observed = run(&executable, &data, &[], &[], false);
        native_cases += 1;
        checked(&observed, status, &expected, true);
    }
    let representative = vec![
        row("pear", "2", "1.25"),
        row("comma, quote\"é", "-3", "2.675"),
        row("limit", "9223372036854775807", "0.5"),
    ];
    let data = input(&representative);
    let expected = reference(&representative).1;
    let baseline = run(&executable, &data, &[], &[], false);
    native_cases += 1;
    checked(&baseline, 0, &expected, true);
    profile(&baseline, baseline.memory.attempts, None);
    let positions = baseline.memory.attempts;
    assert!(
        positions > 5,
        "must cover CSV, typed rows and writer owners: {}",
        baseline.events
    );
    for ordinal in 1..=positions {
        let injection = format!("mmap:error=ENOMEM:when={ordinal}");
        let observed = run(&executable, &data, &[], &[&injection], false);
        native_cases += 1;
        checked(&observed, 4, b"", true);
        profile(&observed, ordinal, Some(ordinal));
        if ordinal == 1 {
            assert!(calls(&observed.events, "read").is_empty());
        }
    }

    let invalid: &[(&[u8], i32)] = &[
        (b"", 2),
        (b"wrong,quantity,unit_price\na,1,2\n", 2),
        (b"name,quantity,unit_price\na,1\n", 2),
        (b"name,quantity,unit_price\na,1,2,3\n", 7),
        (b"name,quantity,unit_price\n\"bad,1,2\n", 2),
        (b"name,quantity,unit_price\n\xff,1,2\n", 2),
        (b"name,quantity,unit_price\na,9223372036854775808,1\n", 2),
        (b"name,quantity,unit_price\na,-9223372036854775809,1\n", 2),
        (b"name,quantity,unit_price\na,,1\n", 2),
        (b"name,quantity,unit_price\na, 1,1\n", 2),
        (b"name,quantity,unit_price\na,1,1 \n", 2),
        (b"name,quantity,unit_price\na,1,nan\n", 2),
        (b"name,quantity,unit_price\na,1,inf\n", 2),
        (b"name,quantity,unit_price\na,1,1e999\n", 2),
        (b"name,quantity,unit_price\na,2,1.7976931348623157e308\n", 5),
        (b"name,quantity,unit_price\n,1,1\n", 2),
        (b"name,quantity,unit_price\n\"multi\nline\",1,1\n", 2),
        (b"name,quantity,unit_price\n\"nul\0name\",1,1\n", 2),
        (b"name,quantity,unit_price\n\"tab\tname\",1,1\n", 2),
        (b"name,quantity,unit_price\na,1,2\nb,not-an-integer,2\n", 2),
    ];
    for &(data, status) in invalid {
        let observed = run(&executable, data, &[], &[], false);
        native_cases += 1;
        checked(&observed, status, b"", true);
        no_publication(&observed);
    }
    for rows in [
        vec![row(&"n".repeat(257), "1", "1")],
        vec![row("n", &"0".repeat(129), "1")],
        vec![row("n", "1", &"0".repeat(129))],
        (0..257)
            .map(|index| row(&format!("n{index}"), "1", "1"))
            .collect(),
    ] {
        let observed = run(&executable, &input(&rows), &[], &[], false);
        native_cases += 1;
        checked(&observed, 7, b"", true);
        no_publication(&observed);
    }
    for (size, status) in [(MAX_INPUT, 7), (MAX_INPUT + 1, 7)] {
        // At exact byte bound the CSV field cap rejects; one extra byte is
        // rejected by bounded copy after a whole successful host read.
        let observed = run(&executable, &vec![b'x'; size], &[], &[], false);
        native_cases += 1;
        checked(&observed, status, b"", true);
        no_publication(&observed);
        if size == MAX_INPUT {
            assert_eq!(
                result(calls(&observed.events, "read").last().unwrap(), "read").1,
                "0"
            );
        }
    }

    let large = (0..256)
        .map(|index| {
            row(
                &format!("item{index:03}"),
                &(index as i64 - 128).to_string(),
                "1.25",
            )
        })
        .collect::<Vec<_>>();
    let observed = run(&executable, &input(&large), &[], &[], false);
    native_cases += 1;
    checked(&observed, 0, &reference(&large).1, true);
    // Construct exactly 65,536 report bytes from the independent oracle by
    // adding name scalars; padding is already saturated at name width 16.
    let mut boundary = (0..256)
        .map(|_| row(&"x".repeat(16), "1", "1"))
        .collect::<Vec<_>>();
    let mut additional = 65_536 - reference(&boundary).1.len();
    for item in &mut boundary {
        let take = additional.min(240);
        item.name.push_str(&"x".repeat(take));
        additional -= take;
    }
    assert_eq!(additional, 0);
    let (status, boundary_expected) = reference(&boundary);
    assert_eq!(status, 0);
    assert_eq!(boundary_expected.len(), 65_536);
    let observed = run(&executable, &input(&boundary), &[], &[], false);
    native_cases += 1;
    checked(&observed, 0, &boundary_expected, true);
    let item = boundary
        .iter_mut()
        .find(|item| item.name.len() < 256)
        .unwrap();
    item.name.push('x');
    assert_eq!(reference(&boundary).0, 7);
    let observed = run(&executable, &input(&boundary), &[], &[], false);
    native_cases += 1;
    checked(&observed, 7, b"", true);
    no_publication(&observed);

    for (injection, status, reads) in [
        ("read:error=EIO:when=1", 3, 1),
        ("read:error=EIO:when=2", 3, 2),
        ("read:error=EAGAIN:when=1", 3, 1),
        ("read:retval=1025:when=1", 3, 1),
        ("read:error=EINTR:when=1", 0, 3),
    ] {
        let observed = run(&executable, &data, &[], &[injection], false);
        native_cases += 1;
        checked(
            &observed,
            status,
            if status == 0 { &expected } else { b"" },
            true,
        );
        if status == 0 {
            profile(&observed, positions, None);
        } else {
            profile(&observed, 1, None);
            no_publication(&observed);
        }
        assert_eq!(calls(&observed.events, "read").len(), reads);
    }
    let writes = calls(&baseline.events, "write");
    let write_count = writes.len();
    let last_request = request(writes.last().unwrap());
    assert_eq!(write_count, expected.len().div_ceil(17));
    assert_eq!(last_request, expected.len() % 17);
    assert!(last_request > 0 && last_request < 17);
    let finish_error = format!("write:error=EIO:when={write_count}");
    let finish_interrupt = format!("write:error=EINTR:when={write_count}");
    for (injection, status, output, extra) in [
        ("write:error=EIO:when=1", 3, b"".as_slice(), 0),
        ("write:error=EIO:when=2", 3, &expected[..17], 0),
        (
            finish_error.as_str(),
            3,
            &expected[..expected.len() - last_request],
            0,
        ),
        ("write:error=EAGAIN:when=1", 3, b"".as_slice(), 0),
        ("write:retval=0:when=1", 3, b"".as_slice(), 0),
        ("write:retval=18:when=1", 3, b"".as_slice(), 0),
        ("write:error=EINTR:when=1", 0, expected.as_slice(), 1),
        (finish_interrupt.as_str(), 0, expected.as_slice(), 1),
        ("write:retval=1:when=1", 0, &expected[1..], 1),
    ] {
        let observed = run(&executable, &data, &[], &[injection], false);
        native_cases += 1;
        checked(&observed, status, output, true);
        profile(&observed, positions, None);
        let seen = calls(&observed.events, "write");
        if status == 0 {
            assert_eq!(seen.len(), write_count + extra);
        }
        if injection.contains("retval=1:") {
            assert_eq!(request(seen[1]), 16);
        }
    }
    for (injection, output, count) in [
        (
            String::from("write:error=EINTR:when=1+"),
            b"".as_slice(),
            None,
        ),
        (
            format!("write:error=EINTR:when={write_count}+"),
            &expected[..expected.len() - last_request],
            Some(64),
        ),
    ] {
        let observed = run(&executable, &data, &[], &[&injection], false);
        native_cases += 1;
        checked(&observed, 7, output, true);
        profile(&observed, positions, None);
        let denied = calls(&observed.events, "write")
            .into_iter()
            .filter(|line| line.contains("INJECTED"))
            .count();
        if let Some(count) = count {
            assert_eq!(denied, count);
        } else {
            assert!(denied > 4000 && denied <= 4096);
        }
    }
    let observed = run(&executable, &data, &[], &[], true);
    native_cases += 1;
    checked(&observed, 3, b"", true);
    profile(&observed, positions, None);
    let writes = calls(&observed.events, "write");
    assert_eq!(writes.len(), 1);
    assert!(writes[0].contains("EPIPE"));
    let observed = run(
        &executable,
        &data,
        &[],
        &["rt_sigaction:error=EINTR:when=1"],
        false,
    );
    native_cases += 1;
    checked(&observed, 3, b"", false);
    profile(&observed, 0, None);
    no_publication(&observed);
    assert!(calls(&observed.events, "read").is_empty());
    let observed = run(&executable, &data, &["extra"], &[], false);
    native_cases += 1;
    checked(&observed, 2, b"", true);
    profile(&observed, 0, None);
    assert!(calls(&observed.events, "read").is_empty());
    assert_eq!(native_cases, 58 + positions);
    eprintln!("format_report: one strict ELF, {positions} observed representative allocation positions, {native_cases} native cases; separate256-row correctness and exact65536-byte output boundary");
}
