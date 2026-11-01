//! Real File Seek positioning, shared cursors and selected one-attempt faults.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeSet,
    fs,
    os::unix::fs::PermissionsExt,
    path::{Path, PathBuf},
    process::{Command, Output, Stdio},
    time::Duration,
};

struct Directory(common::TempArtifact);
impl Directory {
    fn new() -> Self {
        let path = common::TempArtifact::new("laniusc_file_seek", "directory", None);
        fs::create_dir(path.path()).unwrap();
        Self(path)
    }
    fn path(&self) -> &Path {
        self.0.path()
    }
}
impl Drop for Directory {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(self.path());
    }
}

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!(
        "tests/fixtures/stdlib_foundation/file_seek/{name}.lani"
    ));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("File Seek", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("File Seek {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_file_seek", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn calls<'a>(events: &'a str, name: &str) -> Vec<&'a str> {
    let prefix = format!("{name}(");
    events
        .lines()
        .filter(|line| line.starts_with(&prefix))
        .collect()
}
fn result(line: &str) -> i64 {
    let token = line
        .rsplit_once('=')
        .unwrap()
        .1
        .trim()
        .split_whitespace()
        .next()
        .unwrap();
    match token.parse::<i64>() {
        Ok(value) => value,
        // strace may print raw negative register bits as an unsigned decimal.
        // Parsing u64 first admits the exact register domain before the bit
        // reinterpretation; malformed or larger-than-u64 text still rejects.
        Err(signed_error) => {
            token
                .parse::<u64>()
                .map(|bits| bits as i64)
                .unwrap_or_else(|unsigned_error| {
                    panic!("invalid 64-bit result ({signed_error}; {unsigned_error}): {line}")
                })
        }
    }
}
fn first_argument(line: &str) -> i64 {
    line.split_once('(')
        .unwrap()
        .1
        .split([',', ')'])
        .next()
        .unwrap()
        .trim()
        .parse()
        .unwrap()
}
fn seek_arguments(line: &str) -> (i64, &str) {
    let arguments = line
        .strip_prefix("lseek(")
        .unwrap()
        .split_once(')')
        .unwrap()
        .0;
    let mut fields = arguments.split(',');
    fields.next().unwrap();
    (
        fields.next().unwrap().trim().parse().unwrap(),
        fields.next().unwrap().trim(),
    )
}

// strace diagnoses hypothetical 32-bit personalities while preserving the
// actual x86_64 result. Only these exact scheduled diagnostics are allowed;
// the selected native trace must independently retain the complete result.
fn wide_injection(injection: Option<&str>) -> Option<(&'static [u8], i64)> {
    match injection {
        Some("lseek:retval=4294967303:when=1")=>Some((b"strace: Injected return value 4294967303 will be clipped to 7 in compat personality\n",4294967303)),
        Some("lseek:retval=9223372036854775807:when=1")=>Some((b"strace: Inadvertent injection of error 1 is possible in compat personality for retval=9223372036854775807\n",i64::MAX)),
        Some("lseek:retval=-4096:when=1")=>Some((b"strace: Injected return value 18446744073709547520 will be clipped to 4294963200 in compat personality\n",-4096)),
        _=>None,
    }
}

fn ownership(events: &str, expected: usize, pure_phase: bool) {
    let mut live = BTreeSet::new();
    let mut acquired = 0;
    let mut retired = 0;
    let mut pure = false;
    let mut phases = 0;
    let mut done = false;
    let mut entries = 0;
    let mut exits = 0;
    for line in events.lines() {
        if pure_phase && line.starts_with("write(2,") {
            assert_eq!(result(line), 1, "{events}");
            if line.contains("\"P\", 1)") {
                assert!(!pure && !done, "{events}");
                pure = true;
            } else if line.contains("\"p\", 1)") {
                assert!(pure && !done, "{events}");
                pure = false;
                phases += 1;
            } else {
                assert!(
                    line.contains("\"D\", 1)") && !pure && !done && live.is_empty(),
                    "{events}"
                );
                done = true;
            }
            continue;
        }
        assert!(!pure, "closed/high-target admission reached host: {line}");
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            exits += 1;
            continue;
        }
        assert!(!done, "only exit follows completion: {events}");
        if line.starts_with("execve(") {
            assert_eq!(result(line), 0, "{events}");
            entries += 1;
            continue;
        }
        let permitted = [
            "openat(", "fcntl(", "lseek(", "read(", "write(", "close(", "pipe2(",
        ];
        assert!(
            permitted.iter().any(|prefix| line.starts_with(prefix)),
            "unexpected host/allocation/sync call: {line}"
        );
        if line.starts_with("close(") {
            assert!(
                live.remove(&first_argument(line)),
                "close exactly one real acquired descriptor: {events}"
            );
            assert_eq!(result(line), 0, "{events}");
            retired += 1;
        } else if line.starts_with("pipe2(") {
            assert_eq!(result(line), 0, "{events}");
            assert!(line.contains("O_CLOEXEC"), "{events}");
            let pair = line.split_once('[').unwrap().1.split_once(']').unwrap().0;
            let handles: Vec<i64> = pair
                .split(',')
                .map(|word| word.trim().parse().unwrap())
                .collect();
            assert_eq!(handles.len(), 2, "{events}");
            for handle in handles {
                assert!(handle >= 3 && live.insert(handle), "{events}");
                acquired += 1;
            }
        } else if line.starts_with("openat(")
            || (line.starts_with("fcntl(") && line.contains("F_DUPFD_CLOEXEC"))
        {
            let handle = result(line);
            assert!(handle >= 3 && live.insert(handle), "{events}");
            acquired += 1;
        } else {
            let handle = first_argument(line);
            assert!(
                handle <= 2 || live.contains(&handle),
                "operation on unowned descriptor: {events}"
            );
        }
    }
    assert!(
        live.is_empty() && !pure,
        "unreleased actual descriptor: {events}"
    );
    assert_eq!(
        (acquired, retired, entries, exits),
        (expected, expected, 1, 1),
        "{events}"
    );
    assert_eq!(phases, usize::from(pure_phase), "{events}");
    assert_eq!(done, pure_phase, "{events}");
}

fn run(
    executable: &common::TempArtifact,
    directory: &Directory,
    mode: Option<u8>,
    injection: Option<&str>,
) -> (Output, String) {
    let trace = common::TempArtifact::new("laniusc_file_seek", "trace", None);
    let input = common::TempArtifact::new("laniusc_file_seek", "mode", None);
    input.write_bytes([mode.unwrap_or(0)]);
    let mut command = Command::new("strace");
    command
        .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"]);
    if let Some(injection) = injection {
        command.arg("-e").arg(format!("inject={injection}"));
    }
    command.arg(executable.path()).current_dir(directory.path());
    if mode.is_some() {
        command.stdin(fs::File::open(input.path()).unwrap());
    } else {
        command.stdin(Stdio::null());
    }
    let output = common::process_output_with_timeout(
        "File Seek native lifecycle",
        &mut command,
        Duration::from_secs(8),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(output.status.code(), Some(0), "{output:?}\n{events}");
    assert_eq!(
        events
            .lines()
            .filter(|line| line.contains("INJECTED"))
            .count(),
        usize::from(injection.is_some()),
        "selected call must be reached once: {injection:?}\n{events}"
    );
    (output, events)
}

#[test]
fn file_seek_executes_shared_binary_cursors_full_width_offsets_and_unseekable_errors() {
    let executable = executable("contracts");
    let directory = Directory::new();
    let input = directory.path().join("input");
    fs::write(&input, (0..16).collect::<Vec<u8>>()).unwrap();
    let (output, events) = run(&executable, &directory, None, None);
    assert!(output.stdout.is_empty());
    assert_eq!(output.stderr, b"PpD");
    ownership(&events, 5, true);
    let expected = [
        (2, "SEEK_SET"),
        (0, "SEEK_CUR"),
        (-2, "SEEK_CUR"),
        (0, "SEEK_CUR"),
        (-2, "SEEK_END"),
        (0, "SEEK_CUR"),
        (4294967311, "SEEK_SET"),
        (0, "SEEK_CUR"),
        (-4294967296, "SEEK_CUR"),
        (4294967296, "SEEK_END"),
        (-16, "SEEK_END"),
        (i64::MIN, "SEEK_CUR"),
        (i64::MIN, "SEEK_END"),
        (0, "SEEK_CUR"),
        (0, "SEEK_SET"),
        (0, "SEEK_SET"),
        (0, "SEEK_CUR"),
        (0, "SEEK_SET"),
        (i64::MIN, "SEEK_CUR"),
    ];
    let actual: Vec<_> = calls(&events, "lseek")
        .into_iter()
        .map(seek_arguments)
        .collect();
    assert_eq!(
        actual, expected,
        "one requested lseek; no retry/hidden seek: {events}"
    );
    assert_eq!(
        calls(&events, "fcntl").len(),
        1,
        "only explicit duplicate: {events}"
    );
    assert_eq!(calls(&events, "pipe2").len(), 1, "{events}");
    assert!(
        events.contains("ESPIPE") && events.contains("EINVAL"),
        "genuine host errors: {events}"
    );
    assert_eq!(
        fs::metadata(&input).unwrap().len(),
        18,
        "seeking beyond EOF must not extend length; append must use old EOF"
    );
    let mut expected = (0..16).collect::<Vec<u8>>();
    expected[3..5].copy_from_slice(&[0, 255]);
    expected.extend_from_slice(&[0, 255]);
    assert_eq!(
        fs::read(&input).unwrap(),
        expected,
        "exact actual file writes, including O_APPEND"
    );
}

#[test]
fn file_seek_selected_faults_preserve_full_width_acknowledgements_and_one_attempt() {
    let executable = executable("fault");
    let directory = Directory::new();
    let input = directory.path().join("input");
    let seed = (0..16).collect::<Vec<u8>>();
    fs::write(&input, &seed).unwrap();
    // mode, selected first seek injection, error/result, actual separate query.
    let cases = [
        (0, None, 0, 7, 7),
        (0, Some("lseek:error=EINTR:when=1"), 1, 0, 0),
        (0, Some("lseek:error=EAGAIN:when=1"), 2, 0, 0),
        (0, Some("lseek:error=EIO:when=1"), 1005, 0, 0),
        (0, Some("lseek:error=ESPIPE:when=1"), 1029, 0, 0),
        (0, Some("lseek:retval=0:when=1"), 4, 0, 0),
        (0, Some("lseek:retval=8:when=1"), 4, 0, 0),
        (0, Some("lseek:retval=4294967303:when=1"), 4, 0, 0),
        (0, Some("lseek:retval=9223372036854775807:when=1"), 4, 0, 0),
        (0, Some("lseek:retval=-4096:when=1"), 4, 0, 0),
        (1, None, 0, 4294967311, 4294967311),
        (1, Some("lseek:error=EINTR:when=1"), 1, 0, 0),
        (1, Some("lseek:retval=-4096:when=1"), 4, 0, 0),
        (2, None, 0, 13, 13),
        (2, Some("lseek:error=EIO:when=1"), 1005, 0, 0),
        (2, Some("lseek:retval=-4096:when=1"), 4, 0, 0),
        (3, None, 1022, 0, 0),
        (4, None, 1022, 0, 0),
    ];
    assert_eq!(cases.len(), 18);
    for (mode, injection, code, reported, actual) in cases {
        let (output, events) = run(&executable, &directory, Some(mode), injection);
        let wide = wide_injection(injection);
        assert!(
            output.stderr.is_empty()
                || wide.is_some_and(|(warning, _)| output.stderr.as_slice() == warning),
            "unexpected tool stderr: {output:?}\n{events}"
        );
        assert_eq!(output.stdout.len(), 24, "{output:?}");
        let words: Vec<i64> = output
            .stdout
            .chunks_exact(8)
            .map(|word| i64::from_le_bytes(word.try_into().unwrap()))
            .collect();
        assert_eq!(
            words,
            [code, reported, actual],
            "mode={mode} {injection:?}\n{events}"
        );
        ownership(&events, 1, false);
        let seeks = calls(&events, "lseek");
        assert_eq!(
            seeks.len(),
            2,
            "one selected call and one explicit position query: {events}"
        );
        let selected = match mode {
            0 => (7, "SEEK_SET"),
            1 => (4294967311, "SEEK_CUR"),
            2 => (-3, "SEEK_END"),
            3 => (i64::MIN, "SEEK_CUR"),
            4 => (i64::MIN, "SEEK_END"),
            _ => unreachable!(),
        };
        assert_eq!(
            seek_arguments(seeks[0]),
            selected,
            "full-width input: {events}"
        );
        assert_eq!(seek_arguments(seeks[1]), (0, "SEEK_CUR"), "{events}");
        if injection.is_some() {
            assert!(
                seeks[0].contains("INJECTED") && !seeks[1].contains("INJECTED"),
                "{events}"
            );
        }
        if let Some((_, expected)) = wide {
            assert_eq!(
                result(seeks[0]),
                expected,
                "actual x86_64 injected result must retain every bit despite the tool's compat diagnostic: {events}"
            );
            assert_eq!(code, 4, "wide malformed results must be InvalidCount");
        }
        assert_eq!(fs::metadata(&input).unwrap().len(), 16);
        assert_eq!(
            fs::read(&input).unwrap(),
            seed,
            "seek never writes file content"
        );
    }
    eprintln!("file-seek schedules=18 genuine=5 reached-injections=13");
}
