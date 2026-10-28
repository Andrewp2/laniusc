//! Finite owned fold transactions, source remainders and reached mmap denials.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
    sync::OnceLock,
    time::Duration,
};

fn executable() -> &'static common::TempArtifact {
    static EXECUTABLE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXECUTABLE.get_or_init(|| {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("tests/fixtures/stdlib_foundation/iterator_folds/owners.lani");
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("iterator fold owners", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap_or_else(|error| panic!("iterator fold owners: {error}"));
        assert!(common::x86_jumps::is_x86_64_executable(&bytes));
        let artifact = common::TempArtifact::new("laniusc_fold_owners", "executable", None);
        artifact.write_bytes(bytes);
        fs::set_permissions(artifact.path(), fs::Permissions::from_mode(0o700)).unwrap();
        artifact
    })
}

fn run(mode: u8, denied: Option<usize>) -> (Output, String) {
    let input = common::TempArtifact::new("laniusc_fold_owners", "input", None);
    input.write_bytes([mode]);
    let trace = common::TempArtifact::new("laniusc_fold_owners", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,mremap,munmap,brk,write",
            "-e",
            "signal=none",
        ]);
    if let Some(index) = denied {
        command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={index}")]);
    }
    command
        .arg(executable().path())
        .stdin(fs::File::open(input.path()).unwrap());
    let output = common::process_output_with_timeout(
        "iterator fold owned lifecycle",
        &mut command,
        Duration::from_secs(10),
    );
    assert_eq!(
        output.status.code(),
        Some(if denied.is_some() { 4 } else { 0 }),
        "{output:?}"
    );
    assert!(output.stdout.is_empty(), "{output:?}");
    (output, fs::read_to_string(trace.path()).unwrap())
}

fn mappings(events: &str, expected_denials: usize) -> usize {
    let mut live = BTreeMap::<String, usize>::new();
    let mut attempts = 0;
    let mut denied = 0;
    let mut pure = false;
    let mut finished = false;
    for line in events.lines() {
        if line.starts_with("write(2, ") {
            assert!(line.ends_with(" = 1"), "{events}");
            if line.contains("\"P\", 1)") {
                assert!(!pure && !finished, "{events}");
                pure = true;
            } else if line.contains("\"p\", 1)") {
                assert!(pure && !finished, "{events}");
                pure = false;
            } else if line.contains("\"D\", 1)") {
                assert!(
                    !pure && !finished && live.is_empty(),
                    "explicit cleanup before exit: {events}"
                );
                finished = true;
            } else {
                assert!(
                    line.contains("\"G\", 1)") || line.contains("\"g\", 1)"),
                    "{events}"
                );
                assert!(!pure && !finished, "{events}");
            }
            continue;
        }
        assert!(
            !pure,
            "pure callbacks/folds must use no allocation or release service: {line}"
        );
        assert!(
            !finished,
            "no allocation service after cleanup checkpoint: {events}"
        );
        if let Some(arguments) = line.strip_prefix("mmap(") {
            attempts += 1;
            let size: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let result = line.rsplit_once(" = ").unwrap().1.trim();
            if result.starts_with("-1 ENOMEM") {
                assert!(line.contains("(INJECTED)"), "{events}");
                denied += 1;
            } else {
                let address = result.split_whitespace().next().unwrap();
                assert!(
                    address.starts_with("0x") && live.insert(address.to_owned(), size).is_none(),
                    "{events}"
                );
            }
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, size) = arguments.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            assert_eq!(
                live.remove(address.trim()),
                Some(size),
                "one exact live mapping: {events}"
            );
            assert_eq!(result.trim(), "= 0", "{events}");
        } else {
            panic!("unexpected allocation service or output: {line}");
        }
    }
    assert!(finished && !pure && live.is_empty(), "{events}");
    assert_eq!(denied, expected_denials, "reached mmap denials: {events}");
    attempts
}

#[test]
fn owned_accumulators_errors_and_cursor_remainders_cover_all_eight_fold_apis() {
    let (output, events) = run(0, None);
    assert_eq!(output.stderr, b"PpPpPpPpPpPpPpPpD");
    assert!(mappings(&events, 0) > 0);
}

fn growth(mode: u8) {
    let (output, events) = run(mode, None);
    assert_eq!(output.stderr, b"GgD");
    let count = mappings(&events, 0);
    assert_eq!(
        count, 12,
        "source backing + seven Strings + two growths in each accumulator buffer: {events}"
    );
    for index in 1..=count {
        let (output, events) = run(mode, Some(index));
        assert!(
            output.stderr == b"D" || output.stderr == b"GgD",
            "{output:?}"
        );
        assert_eq!(
            mappings(&events, 1),
            index,
            "stop after the reached allocation failure"
        );
    }
    eprintln!("fold-owner mode={mode} lifecycle=1 reached-oom={count}");
}

#[test]
fn forward_fold_growth_denials_return_actual_updated_accumulator_and_current_owner() {
    growth(1);
}

#[test]
fn reverse_fold_growth_denials_preserve_prefix_and_release_actual_updated_owners() {
    growth(2);
}
