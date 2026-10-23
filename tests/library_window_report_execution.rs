mod common;
use laniusc_compiler::compiler::{compile_entry_to_x86_64_with_source_roots, EntrySourceRoots};

fn executable() -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/window_report.lani");
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout("window report", move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .expect("compile the window report application");
    let exe = common::TempArtifact::new("laniusc_window", "report", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(exe: &common::TempArtifact, bytes: &[u8]) -> std::process::Output {
    let input = common::TempArtifact::new("laniusc_window", "input", None);
    input.write_bytes(bytes);
    common::process_output_with_timeout(
        "window report",
        std::process::Command::new(exe.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(input.path()).unwrap(),
        )),
        std::time::Duration::from_secs(5),
    )
}
fn reference(values: &[i32], width: usize) -> Vec<u8> {
    let mut text = String::from("start,min,max,sum\n");
    for (start, window) in values.windows(width).enumerate() {
        text.push_str(&format!(
            "{start},{},{},{}\n",
            window.iter().min().unwrap(),
            window.iter().max().unwrap(),
            window.iter().map(|v| i64::from(*v)).sum::<i64>()
        ));
    }
    text.into_bytes()
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn window_report_validates_input_and_computes_exact_statistics() {
    let exe = executable();
    for (input, values, width) in [
        ("3\n2\n-1\n7\n4\n", vec![2, -1, 7, 4], 3),
        ("1", vec![], 1),
        ("2\n", vec![], 2),
        ("3\n1\n2", vec![1, 2], 3),
        (" 2 \r\n +005 \r\n -7\r\n", vec![5, -7], 2),
        (
            "2\n2147483647\n2147483647\n-2147483648\n-2147483648",
            vec![i32::MAX, i32::MAX, i32::MIN, i32::MIN],
            2,
        ),
    ] {
        let output = run(&exe, input.as_bytes());
        assert_eq!(output.status.code(), Some(0), "{input:?}: {output:?}");
        assert_eq!(output.stdout, reference(&values, width), "{input:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
    }
    let mut seed = 0x71ad_2026_u32;
    let mut values = Vec::new();
    for _ in 0..4096 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        values.push(seed as i32);
    }
    for width in [1, 2, 3, 17, 64, 4095, 4096] {
        let input = format!(
            "{width}\n{}",
            values.iter().map(|v| format!("{v}\n")).collect::<String>()
        );
        let output = run(&exe, input.as_bytes());
        assert_eq!(output.status.code(), Some(0), "width={width}: {output:?}");
        assert_eq!(
            output.stdout,
            reference(&values, width),
            "seed=0x71ad2026 width={width}"
        );
        assert!(output.stderr.is_empty());
    }
    for input in [
        &b""[..],
        b"0\n1",
        b"-1\n1",
        b"4097\n1",
        b"x\n1",
        b"1\n\n",
        b"1\n1\n\n",
        b"1\n1.0",
        b"1\n2147483648",
        b"1\n-2147483649",
        b"1\n+",
        b"1\n\xff",
        b"1\n1\0",
        b"1\n   ",
        b"1\n1\nwrong",
    ] {
        let output = run(&exe, input);
        assert_eq!(output.status.code(), Some(2), "{input:?}: {output:?}");
        assert!(
            output.stdout.is_empty() && !output.stderr.is_empty(),
            "{output:?}"
        );
    }
    for input in [
        format!("1\n{}", "0\n".repeat(4097)).into_bytes(),
        vec![b' '; 1048577],
    ] {
        let output = run(&exe, &input);
        assert_eq!(output.status.code(), Some(2), "{output:?}");
        assert!(output.stdout.is_empty());
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
    assert!(live.is_empty(), "leaked: {live:?}\n{trace}");
    allocations
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn window_report_releases_owners_on_allocation_validation_and_io_failures() {
    let exe = executable();
    let input = common::TempArtifact::new("laniusc_window", "fault_input", None);
    let trace = common::TempArtifact::new("laniusc_window", "trace", None);
    let traced = |injection: Option<&str>| {
        let mut command = std::process::Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        if let Some(injection) = injection {
            command.args(["-e", injection]);
        }
        command.arg(exe.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(input.path()).unwrap(),
        ));
        let output = common::process_output_with_timeout(
            "window report fault",
            &mut command,
            std::time::Duration::from_secs(5),
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        if injection.is_some() {
            assert!(events.contains("INJECTED"), "{events}");
        }
        let allocations = assert_freed(&events);
        (output, allocations)
    };
    input.write_bytes(b"3\n1\n-2\n3\n4\n-5\n6\n7\n8\n9\n");
    let (baseline, allocations) = traced(None);
    assert_eq!(baseline.status.code(), Some(0), "{baseline:?}");
    assert!(allocations > 0);
    for when in 1..=allocations {
        let (output, _) = traced(Some(&format!("inject=mmap:error=ENOMEM:when={when}+")));
        assert_eq!(
            output.status.code(),
            Some(4),
            "allocation {when}: {output:?}"
        );
        assert!(output.stdout.is_empty(), "{output:?}");
        assert_eq!(output.stderr, b"allocation failed\n");
    }
    for invalid in ["0\n1", "3\n1\n2\nwrong", "3\n1\n2\n\n"] {
        input.write_bytes(invalid.as_bytes());
        let (output, _) = traced(None);
        assert_eq!(output.status.code(), Some(2), "{output:?}");
        assert!(output.stdout.is_empty());
    }
    input.write_bytes(b"2\n1\n2\n3\n");
    let (normal, _) = traced(None);
    let (interrupted, _) = traced(Some("inject=read:error=EINTR:when=1"));
    assert_eq!(interrupted.status.code(), Some(0), "{interrupted:?}");
    assert_eq!(interrupted.stdout, normal.stdout);
    for injection in [
        "inject=read:error=EIO:when=1",
        "inject=read:error=EAGAIN:when=2",
        "inject=write:error=EIO:when=2",
        "inject=write:retval=0:when=1",
    ] {
        let (output, _) = traced(Some(injection));
        assert_eq!(output.status.code(), Some(3), "{injection}: {output:?}");
        if injection == "inject=write:error=EIO:when=2" {
            assert_eq!(output.stdout, b"start,min,max,sum\n");
        } else {
            assert!(output.stdout.is_empty(), "{injection}: {output:?}");
        }
    }
}
