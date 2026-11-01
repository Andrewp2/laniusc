//! Live borrowed text owners, fixed report staging, and explicit final cleanup.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    time::Duration,
};

fn fixture(name: &str) -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_text_bidirectional/resources")
        .join(name)
}
fn executable(entry: PathBuf, name: &str) -> common::TempArtifact {
    let stdlib = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("bidirectional text resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("bidirectional text resource {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_text_bidirectional_resources", name, None);
    file.write_bytes(bytes); // The shared writer validates every x86 jump.
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn result(line: &str) -> &str {
    line.rsplit_once('=').unwrap().1.trim()
}
fn arguments(line: &str) -> &str {
    line.rsplit_once('=')
        .unwrap()
        .0
        .trim_end()
        .strip_suffix(')')
        .unwrap()
        .split_once('(')
        .unwrap()
        .1
}
fn address(value: &str) -> u64 {
    u64::from_str_radix(value.trim().strip_prefix("0x").unwrap(), 16).unwrap()
}
#[derive(Clone, Debug, PartialEq, Eq)]
enum Event {
    Entry,
    Read(usize),
    Marker(u8),
    Allocate(usize),
    Release(usize),
    Output {
        requested: usize,
        written: Option<usize>,
    },
    Exit,
}
#[derive(Debug)]
struct OutputWrite {
    ordinal: usize,
    event: usize,
    requested: usize,
    written: Option<usize>,
}
#[derive(Debug, Default)]
struct Effects {
    events: Vec<Event>,
    reports: Vec<Vec<OutputWrite>>,
    phases: usize,
    allocations: Vec<usize>,
    releases: Vec<usize>,
    denied: usize,
}
fn effects(events: &str, stderr: &[u8], reporting: bool) -> Effects {
    let mut observed = Effects::default();
    let mut live = BTreeMap::<u64, usize>::new();
    let mut markers = Vec::new();
    let mut cycle = 0;
    let (mut entries, mut exits, mut reads, mut writes) = (0, 0, 0, 0);
    let (mut active, mut started, mut pure, mut report, mut cleanup, mut done) =
        (false, false, false, false, false, false);
    for line in events.lines() {
        if line.starts_with("write(2,") {
            writes += 1;
            assert_eq!(result(line), "1", "{events}");
            assert!(!done, "{events}");
            let marker = *b"APpRrCED"
                .iter()
                .find(|byte| line.contains(&format!("\"{}\", 1)", char::from(**byte))))
                .unwrap_or_else(|| panic!("unexpected marker: {line}"));
            markers.push(marker);
            observed.events.push(Event::Marker(marker));
            match marker {
                b'A' => {
                    assert!(!active && !pure && !report && live.is_empty(), "{events}");
                    assert!(cycle < 2, "{events}");
                    active = true;
                    started = false;
                    cleanup = false;
                }
                b'P' => {
                    assert!(
                        active && !pure && !report && !cleanup && live.len() == 1,
                        "{events}"
                    );
                    pure = true;
                    started = true;
                }
                b'p' => {
                    assert!(pure && live.len() == 1, "{events}");
                    pure = false;
                    observed.phases += 1;
                }
                b'R' => {
                    assert!(
                        reporting
                            && active
                            && started
                            && !pure
                            && !report
                            && !cleanup
                            && live.len() == 1,
                        "{events}"
                    );
                    report = true;
                    observed.reports.push(Vec::new());
                }
                b'r' => {
                    assert!(report && live.len() == 1, "{events}");
                    report = false;
                }
                b'C' => {
                    assert!(
                        active && started && !pure && !report && !cleanup && live.len() == 1,
                        "{events}"
                    );
                    cleanup = true;
                }
                b'E' => {
                    assert!(
                        active && cleanup && !pure && !report && live.is_empty(),
                        "explicit cleanup precedes E: {events}"
                    );
                    active = false;
                    cycle += 1;
                }
                b'D' => {
                    assert!(!active && cycle == 2 && live.is_empty(), "{events}");
                    done = true;
                }
                _ => unreachable!(),
            }
            continue;
        }
        assert!(
            !pure,
            "borrowed construction/traversal/preservation reached host work: {line}"
        );
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done && live.is_empty(), "{events}");
            exits += 1;
            observed.events.push(Event::Exit);
            continue;
        }
        assert!(
            !done,
            "only exit follows complete owner retirement: {events}"
        );
        if line.starts_with("execve(") {
            assert!(!active && entries == 0, "{events}");
            assert_eq!(result(line), "0", "{events}");
            entries += 1;
            observed.events.push(Event::Entry);
        } else if line.starts_with("read(0,") {
            assert!(
                reporting && !active && cycle == 0 && reads == 0,
                "one initial configuration byte: {events}"
            );
            assert!(arguments(line).ends_with(", 1"), "{events}");
            assert_eq!(result(line), "1", "{events}");
            reads += 1;
            observed.events.push(Event::Read(1));
        } else if line.starts_with("mmap(") {
            assert!(
                active && !started && !report && !cleanup && live.is_empty(),
                "only initial source reservation allocates: {events}"
            );
            let fields: Vec<_> = arguments(line).split(',').map(str::trim).collect();
            assert_eq!(fields.len(), 6, "{events}");
            assert_eq!(fields[0], "NULL", "{events}");
            assert_eq!(
                &fields[2..],
                &[
                    "PROT_READ|PROT_WRITE",
                    "MAP_PRIVATE|MAP_ANONYMOUS",
                    "-1",
                    "0"
                ],
                "{events}"
            );
            let length: usize = fields[1].parse().unwrap();
            assert_eq!(
                length,
                [4096, 262144][cycle],
                "source backing has exact requested extent: {events}"
            );
            let returned = result(line);
            assert!(!returned.contains("INJECTED"), "{events}");
            let pointer = address(returned);
            assert!(live.insert(pointer, length).is_none(), "{events}");
            observed.allocations.push(length);
            observed.events.push(Event::Allocate(length));
        } else if line.starts_with("munmap(") {
            assert!(
                active && cleanup && !report,
                "only explicit caller cleanup releases: {events}"
            );
            let (pointer, length) = arguments(line).split_once(',').unwrap();
            let length: usize = length.trim().parse().unwrap();
            let actual = live
                .remove(&address(pointer))
                .unwrap_or_else(|| panic!("unknown or duplicate release: {line}"));
            assert_eq!(
                length, actual,
                "exact live address/extent release: {events}"
            );
            assert_eq!(result(line), "0", "{events}");
            observed.releases.push(length);
            observed.events.push(Event::Release(length));
        } else if line.starts_with("write(1,") {
            writes += 1;
            assert!(
                active && started && !cleanup && live.len() == 1 && report == reporting,
                "{events}"
            );
            let requested: usize = arguments(line)
                .rsplit_once(',')
                .unwrap()
                .1
                .trim()
                .parse()
                .unwrap();
            assert!(requested > 0, "{events}");
            let value = result(line);
            let written = if value.starts_with("-1 ") {
                assert!(
                    reporting && value.contains("EIO") && value.contains("INJECTED"),
                    "{events}"
                );
                observed.denied += 1;
                None
            } else {
                let used: usize = value.parse().unwrap();
                assert!(used > 0 && used <= requested, "{events}");
                Some(used)
            };
            if reporting {
                assert!(requested <= 4096, "fixed report output staging: {events}");
                observed.reports.last_mut().unwrap().push(OutputWrite {
                    ordinal: writes,
                    event: observed.events.len(),
                    requested,
                    written,
                });
            }
            observed.events.push(Event::Output { requested, written });
        } else {
            panic!("unexpected host service: {line}");
        }
    }
    assert!(
        done && !active && !pure && !report && live.is_empty(),
        "{events}"
    );
    assert_eq!(
        (entries, exits, reads),
        (1, 1, usize::from(reporting)),
        "{events}"
    );
    assert_eq!(observed.allocations, [4096, 262144]);
    assert_eq!(observed.releases, observed.allocations);
    assert_eq!(stderr, markers, "native marker bytes agree with full trace");
    observed
}
fn run(
    executable: &common::TempArtifact,
    reporting: bool,
    denial: Option<usize>,
) -> (Vec<u8>, Effects) {
    let input = common::TempArtifact::new("laniusc_text_bidirectional_resources", "mode", None);
    input.write_bytes([u8::from(denial.is_some())]);
    let trace = common::TempArtifact::new("laniusc_text_bidirectional_resources", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"]);
    if let Some(ordinal) = denial {
        command
            .arg("-e")
            .arg(format!("inject=write:error=EIO:when={ordinal}"));
    }
    command
        .arg(executable.path())
        .stdin(Stdio::from(fs::File::open(input.path()).unwrap()));
    let output = common::process_output_with_timeout(
        "bidirectional text owner/report lifecycle",
        &mut command,
        Duration::from_secs(25),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(
        output.status.code(),
        Some(0),
        "denial={denial:?}: {output:?}\n{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.contains("INJECTED"))
            .count(),
        usize::from(denial.is_some()),
        "reached fault: {events}"
    );
    let observed = effects(&events, &output.stderr, reporting);
    assert_eq!(observed.denied, usize::from(denial.is_some()));
    (output.stdout, observed)
}
const PATTERN: &str = "Aé€🙂\0 \tB\r\nC\n\nD\rE\u{b}F\u{c}G \u{10ffff}\n";
fn source(blocks: usize) -> String {
    assert_eq!(PATTERN.len(), 32);
    assert_eq!(PATTERN.chars().count(), 23);
    PATTERN.repeat(blocks)
}
fn report(blocks: usize) -> Vec<u8> {
    let source = source(blocks);
    let mut output = format!("{} {}\n", source.len(), source.chars().count()).into_bytes();
    output.extend(source.chars().rev().collect::<String>().into_bytes());
    output
}
#[test]
fn borrowed_text_cursors_preserve_live_owners_without_resource_effects_at_two_sizes() {
    let executable = executable(fixture("owners.lani"), "owners");
    let (output, observed) = run(&executable, false, None);
    let mut expected = source(128).into_bytes();
    expected.extend(source(8192).into_bytes());
    assert_eq!(
        output, expected,
        "all source bytes survive constructor/early stop/copy/full mixed traversal"
    );
    assert_eq!(observed.phases, 8);
    assert!(observed.reports.is_empty());
    eprintln!(
        "borrowed-text-owners bytes=4096,262144 pure-phases=8 complete-scalar-word-line-checks=true exact-maps=2 exact-explicit-releases=2"
    );
}
#[test]
fn unicode_report_borrows_unchanged_input_uses_fixed_staging_and_recovers_write_failure() {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let application =
        fs::read_to_string(root.join("sample_programs/unicode_text_report.lani")).unwrap();
    let entry = "fn main() -> i32 {";
    assert_eq!(
        application.matches(entry).count(),
        1,
        "one canonical entry point"
    );
    let mut instrumented =
        application.replacen(entry, "fn captured_application_main() -> i32 {", 1);
    instrumented.push('\n');
    instrumented.push_str(&fs::read_to_string(fixture("report_harness.lani")).unwrap());
    let source = common::TempArtifact::new(
        "laniusc_text_bidirectional_resources",
        "report_source",
        Some("lani"),
    );
    source.write_bytes(instrumented);
    let executable = executable(source.path().to_path_buf(), "report");
    let (output, baseline) = run(&executable, true, None);
    let mut expected = report(128);
    expected.extend(report(8192));
    assert_eq!(
        output, expected,
        "complete canonical-report headers and reversed scalar bytes"
    );
    assert_eq!(baseline.phases, 4);
    assert_eq!(baseline.reports.len(), 2);
    for (writes, blocks) in baseline.reports.iter().zip([128, 8192]) {
        assert!(
            writes.len() >= 2,
            "header and actual payload writes are observed"
        );
        if blocks == 8192 {
            assert!(
                writes.len() > 2,
                "large workload crosses the fixed staging boundary"
            );
        }
        assert_eq!(
            writes
                .iter()
                .map(|write| write.written.unwrap())
                .sum::<usize>(),
            report(blocks).len()
        );
    }
    // Select an actual first payload write from the successful trace. The
    // harness expects status 3, checks unchanged input, explicitly cleans up,
    // then successfully reports the second owner in the same process.
    let selected = &baseline.reports[0][1];
    let (output, failed) = run(&executable, true, Some(selected.ordinal));
    let mut expected = format!("{} {}\n", 128 * 32, 128 * 23).into_bytes();
    expected.extend(report(8192));
    assert_eq!(
        output, expected,
        "failed payload emits no bytes; subsequent report is complete"
    );
    assert_eq!(
        &failed.events[..selected.event],
        &baseline.events[..selected.event],
        "complete normalized effect prefix before reached payload denial"
    );
    assert_eq!(
        failed.events[selected.event],
        Event::Output {
            requested: selected.requested,
            written: None
        }
    );
    assert_eq!(failed.phases, 4);
    assert_eq!(failed.reports.len(), 2);
    assert_eq!(failed.reports[0].len(), 2);
    assert_eq!(
        failed.reports[1]
            .iter()
            .map(|write| write.written.unwrap())
            .sum::<usize>(),
        report(8192).len()
    );
    eprintln!(
        "unicode-report-borrow bytes=4096,262144 staging-max=4096 pure-preservation-phases=4 report-allocation-release-effects=0 exact-maps=2 exact-explicit-releases=2 reached-EIO-write={} same-process-recovery=true",
        selected.ordinal
    );
}
