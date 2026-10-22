mod common;
use laniusc_compiler::compiler::{compile_entry_to_x86_64_with_source_roots, EntrySourceRoots};

fn executable() -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("sample_programs/csv_report.lani");
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout("CSV report", move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .expect("compile the CSV report application");
    let exe = common::TempArtifact::new("laniusc_report", "report", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(exe: &common::TempArtifact, input: &[u8]) -> std::process::Output {
    let file = common::TempArtifact::new("laniusc_report", "input", None);
    file.write_bytes(input);
    common::short_process_output_with_timeout(
        "CSV report execution",
        std::process::Command::new(exe.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(file.path()).unwrap(),
        )),
    )
}
fn generated_report() -> (Vec<u8>, serde_json::Value) {
    let mut csv = String::from("group,value\r\n");
    let mut groups: Vec<(String, i32, usize)> = Vec::new();
    let mut positions = std::collections::BTreeMap::<String, usize>::new();
    let names = [
        "",
        "fruit",
        "é🙂",
        "a,b",
        "a\"b",
        "multi\nline",
        " spaced ",
        "\\",
    ];
    let mut seed = 0x7e90_1234_u32;
    for row in 0..4096 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        let name = format!("{}{}", names[(seed >> 8) as usize % names.len()], seed % 8);
        let value = ((seed >> 8) % 2001) as i32 - 1000;
        csv.push_str(&format!("\"{}\",", name.replace('"', "\"\"")));
        if row % 3 == 0 && value >= 0 {
            csv.push('+');
        }
        csv.push_str(&value.to_string());
        csv.push_str(if row % 2 == 0 { "\n" } else { "\r\n" });
        if let Some(&position) = positions.get(&name) {
            groups[position].1 = groups[position].1.checked_add(value).unwrap();
            groups[position].2 += 1;
        } else {
            positions.insert(name.clone(), groups.len());
            groups.push((name, value, 1));
        }
    }
    let values: Vec<_> = groups.into_iter().map(|(name, total, count)| {
        serde_json::json!({"group": name, "total": total, "count": count})
    }).collect();
    (csv.into_bytes(), serde_json::Value::Array(values))
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn csv_report_groups_validates_and_emits_json() {
    let exe = executable();
    for (input, expected) in [
        ("group,value\n", serde_json::json!([])),
        (
            "group,value\nfruit,12\nveg,-3\nfruit,+005\n",
            serde_json::json!([{"group":"fruit","total":17,"count":2},{"group":"veg","total":-3,"count":1}]),
        ),
        (
            "group,value\n,0\n,-0\n",
            serde_json::json!([{"group":"","total":0,"count":2}]),
        ),
        (
            "group,value\nmin,-2147483648\nmax,2147483647",
            serde_json::json!([{"group":"min","total":-2147483648_i64,"count":1},{"group":"max","total":2147483647,"count":1}]),
        ),
    ] {
        let output = run(&exe, input.as_bytes());
        assert_eq!(output.status.code(), Some(0), "{input:?}: {output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(&output.stdout).unwrap(),
            expected
        );
    }
    for input in [
        "",
        "group,value,extra\n",
        "group,wrong\na,1",
        "GROUP,value\na,1",
        "group,value\na",
        "group,value\na,1,extra",
        "group,value\n\"unclosed,1",
        "group,value\na,",
        "group,value\na, 1",
        "group,value\na,1.0",
        "group,value\na,1e2",
        "group,value\na,NaN",
        "group,value\na,2147483648",
        "group,value\na,-2147483649",
        "group,value\na,2147483647\na,1",
        "group,value\na,-2147483648\na,-1",
        "group,value\na,+",
    ] {
        let output = run(&exe, input.as_bytes());
        assert_eq!(output.status.code(), Some(2), "{input:?}: {output:?}");
        assert!(output.stdout.is_empty(), "{input:?}: {output:?}");
        assert!(!output.stderr.is_empty(), "{input:?}: {output:?}");
    }
    let output = run(&exe, b"group,value\n\xff,1\n");
    assert_eq!(output.status.code(), Some(2), "{output:?}");
    assert!(output.stdout.is_empty());

    let (input, expected) = generated_report();
    let output = run(&exe, &input);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(
        serde_json::from_slice::<serde_json::Value>(&output.stdout).unwrap(),
        expected
    );
}

fn assert_freed(trace: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut allocations = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                let address = result.split_whitespace().next().unwrap().to_owned();
                assert!(live.insert(address), "duplicate live allocation: {line}");
                allocations += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            let address = tail.split(',').next().unwrap();
            assert!(line.ends_with(" = 0"), "deallocation failed: {line}");
            assert!(live.remove(address), "unknown/double deallocation: {line}");
        }
    }
    assert!(live.is_empty(), "allocations leaked: {live:?}\n{trace}");
    allocations
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn csv_report_releases_resources_on_allocation_input_and_io_failures() {
    let exe = executable();
    let input = common::TempArtifact::new("laniusc_report", "fault_input", None);
    let trace = common::TempArtifact::new("laniusc_report", "trace", None);
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
        // Syscall tracing of 4,096 records exceeds the ordinary 500 ms bound.
        let output = common::process_output_with_timeout(
            "CSV report fault",
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
    input.write_bytes(b"group,value\na,1\nb,2\nc,3\nd,4\ne,5\na,-1\nb,+7\n");
    let (baseline, allocations) = traced(None);
    assert_eq!(baseline.status.code(), Some(0), "{baseline:?}");
    assert!(allocations > 30, "must exercise all ownership layers");
    for when in 1..=allocations {
        let injection = format!("inject=mmap:error=ENOMEM:when={when}+");
        let (output, _) = traced(Some(&injection));
        assert_eq!(
            output.status.code(),
            Some(4),
            "allocation {when}: {output:?}"
        );
        assert!(output.stdout.is_empty(), "allocation {when}: {output:?}");
        assert_eq!(output.stderr, b"allocation failed\n", "allocation {when}");
    }
    for invalid in [
        "wrong,value\na,1\n",
        "group,value\na,1\nb,not-a-number\n",
        "group,value\na,1\na,2147483647\n",
        "group,value\na,1\n\"unfinished",
    ] {
        input.write_bytes(invalid.as_bytes());
        let (output, _) = traced(None);
        assert_eq!(output.status.code(), Some(2), "{invalid:?}: {output:?}");
        assert!(output.stdout.is_empty());
    }
    let (large, expected) = generated_report();
    input.write_bytes(&large);
    for injection in [
        "inject=read:error=EINTR:when=2",
        "inject=write:error=EINTR:when=2",
    ] {
        let (output, _) = traced(Some(injection));
        assert_eq!(output.status.code(), Some(0), "{injection}: {output:?}");
        assert_eq!(
            serde_json::from_slice::<serde_json::Value>(&output.stdout).unwrap(),
            expected
        );
    }
    let (normal, _) = traced(None);
    for injection in [
        "inject=read:error=EIO:when=2",
        "inject=read:error=EAGAIN:when=2",
        "inject=write:error=EIO:when=2",
        "inject=write:retval=0:when=1",
    ] {
        let (output, _) = traced(Some(injection));
        assert_eq!(output.status.code(), Some(3), "{injection}: {output:?}");
        if injection == "inject=write:error=EIO:when=2" {
            assert_eq!(
                output.stdout,
                normal.stdout[..1024],
                "partial output is explicit"
            );
        } else {
            assert!(output.stdout.is_empty(), "{injection}: {output:?}");
        }
    }
}
