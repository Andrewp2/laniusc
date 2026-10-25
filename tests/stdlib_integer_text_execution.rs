mod common;
use laniusc_compiler::compiler::{compile_entry_to_x86_64_with_source_roots, EntrySourceRoots};

fn executable(name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let file = common::TempArtifact::new("laniusc_integer_text", name, None);
    file.write_bytes(&bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn decimal_native_bounds_text_views_and_packed_storage_execute() {
    let exe = executable("core_decimal_native");
    let output = common::short_process_output_with_timeout(
        "native decimal contracts",
        &mut std::process::Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let exe = executable("decimal_format_bounds");
    let output = common::short_process_output_with_timeout(
        "decimal physical bounds",
        &mut std::process::Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(101), "{output:?}");
}

fn canonical(kind: u8, bits: u64) -> String {
    match kind {
        0 => (bits as u8).to_string(),
        1 => (bits as u16).to_string(),
        2 => (bits as u32).to_string(),
        3 => (bits as i8).to_string(),
        4 => (bits as i16).to_string(),
        5 => (bits as i32).to_string(),
        6 | 8 => bits.to_string(),
        7 | 9 => (bits as i64).to_string(),
        _ => unreachable!(),
    }
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn all_integer_formatters_match_native_values_and_preserve_buffer_canaries() {
    let exe = executable("decimal_format_input");
    let input = common::TempArtifact::new("laniusc_integer_text", "input", None);
    let check = |kind: u8, bits: u64, offset: i32, capacity: i32| {
        let spelling = canonical(kind, bits);
        let mut source = vec![kind];
        source.extend_from_slice(&bits.to_le_bytes());
        source.extend_from_slice(&[(offset + 1) as u8, (capacity + 1) as u8]);
        input.write_bytes(&source);
        let output = common::short_process_output_with_timeout(
            "integer format",
            std::process::Command::new(exe.path()).stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
        );
        assert_eq!(
            output.status.code(),
            Some(0),
            "kind={kind} value={spelling} offset={offset} capacity={capacity}: {output:?}"
        );
        assert!(output.stderr.is_empty(), "{output:?}");
        let mut destination = [211; 32];
        let (status, metric) = if offset < 0 || capacity < 0 {
            (1, 0)
        } else if capacity < spelling.len() as i32 {
            (2, spelling.len() as u8)
        } else {
            destination[offset as usize..offset as usize + spelling.len()]
                .copy_from_slice(spelling.as_bytes());
            (0, spelling.len() as u8)
        };
        let mut expected = vec![status, metric, spelling.len() as u8];
        expected.extend_from_slice(spelling.as_bytes());
        expected.extend_from_slice(&[201, 202]);
        expected.extend_from_slice(&destination);
        assert_eq!(
            output.stdout, expected,
            "kind={kind} value={spelling} offset={offset} capacity={capacity}"
        );
    };
    let mut values = vec![
        0,
        1,
        9,
        10,
        99,
        100,
        u64::MAX,
        i64::MIN as u64,
        i64::MAX as u64,
    ];
    for boundary in [7, 8, 15, 16, 31, 32, 63] {
        let n = 1_u64 << boundary;
        values.extend([n - 1, n, n + 1]);
    }
    let mut power = 1_u64;
    for _ in 1..=19 {
        power *= 10;
        values.extend([power - 1, power, power + 1]);
    }
    let mut seed = 0xdec1_64ba_2026_u64;
    for _ in 0..32 {
        seed = seed
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        values.push(seed);
    }
    for kind in 0..10 {
        let mut spellings = std::collections::BTreeSet::new();
        for &bits in &values {
            let spelling = canonical(kind, bits);
            if !spellings.insert(spelling.clone()) {
                continue;
            }
            let length = spelling.len() as i32;
            for (offset, capacity) in [
                (0, 32),
                (2, length),
                (32 - length, length),
                (3, length - 1),
                (32, 0),
                (-1, 20),
                (0, -1),
            ] {
                check(kind, bits, offset, capacity);
            }
        }
    }
}

fn assert_freed(trace: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut allocations = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(
                    live.insert(result.split_whitespace().next().unwrap().to_owned()),
                    "{line}"
                );
                allocations += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{line}"
            );
        }
    }
    assert!(live.is_empty(), "leaked {live:?}\n{trace}");
    allocations
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn integer_string_construction_and_appends_preserve_owners_under_allocation_failure() {
    let exe = executable("decimal_string_failure");
    let trace = common::TempArtifact::new("laniusc_integer_text", "allocation_trace", None);
    let run = |when: Option<usize>| {
        let mut command = std::process::Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(when) = when {
            command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={when}+")]);
        }
        command.arg(exe.path());
        let output = common::process_output_with_timeout(
            "integer string fault",
            &mut command,
            std::time::Duration::from_secs(5),
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if when.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        let count = assert_freed(&events);
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "{output:?}"
        );
        (output.status.code(), count)
    };
    let (status, count) = run(None);
    assert_eq!(status, Some(0));
    assert!(count > 0);
    for when in 1..=count {
        let (status, _) = run(Some(when));
        assert_eq!(status, Some(77), "allocation {when}");
    }
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn native_integer_writers_return_host_errors_and_preserve_the_written_prefix() {
    let exe = executable("decimal_native_write_failure");
    let trace = common::TempArtifact::new("laniusc_integer_text", "write_trace", None);
    let expected = b"-9223372036854775808\n18446744073709551615\n";
    let baseline = common::short_process_output_with_timeout(
        "integer writers",
        &mut std::process::Command::new(exe.path()),
    );
    assert_eq!(baseline.status.code(), Some(0), "{baseline:?}");
    assert_eq!(baseline.stdout, expected);
    for (when, fault, status) in [
        (4, "error=EIO", 5),
        (25, "error=EIO", 5),
        (4, "error=EINTR", 4),
        (25, "retval=0", 1),
    ] {
        let mut command = std::process::Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", &format!("inject=write:{fault}:when={when}")])
            .arg(exe.path());
        let output = common::process_output_with_timeout(
            "integer writer fault",
            &mut command,
            std::time::Duration::from_secs(5),
        );
        assert!(std::fs::read_to_string(trace.path())
            .unwrap()
            .contains("INJECTED"));
        assert_eq!(
            output.status.code(),
            Some(status),
            "{when} {fault}: {output:?}"
        );
        assert_eq!(output.stdout, &expected[..when - 1], "{when} {fault}");
        assert!(output.stderr.is_empty());
    }
}
