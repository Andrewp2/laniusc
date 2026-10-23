mod common;
use std::path::PathBuf;

use laniusc_compiler::compiler::{EntrySourceRoots, compile_entry_to_x86_64_with_source_roots};
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn executable(name: &str) -> common::TempArtifact {
    use std::os::unix::fs::PermissionsExt;
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(if name == "csv_table" {
        "sample_programs/library/csv_table.lani".to_owned()
    } else {
        format!("tests/fixtures/extended/{name}.lani")
    });
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_terminal", name, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn freed(trace: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(live.insert(result.split_whitespace().next().unwrap().to_owned()));
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(line.ends_with(" = 0"), "{line}");
            assert!(live.remove(tail.split(',').next().unwrap()), "{line}");
        }
    }
    assert!(live.is_empty(), "leaked allocations: {live:?}\n{trace}");
    count
}
fn run(exe: &common::TempArtifact, bytes: &[u8], args: &[&str]) -> std::process::Output {
    let input = common::TempArtifact::new("laniusc_csv_table", "stdin", None);
    input.write_bytes(bytes);
    common::short_process_output_with_timeout(
        "csv-table stdin",
        std::process::Command::new(exe.path())
            .args(args)
            .stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
    )
}
#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn csv_table_consumes_stdin_options_and_limits_before_any_table_output() {
    let exe = executable("csv_table");
    for (source, args, stdout, stderr) in [
        ("", vec![], "", ""),
        ("", vec!["--progress"], "", "[####################] 0/0\n"),
        (
            "name,city\nAlice,東京\n",
            vec!["--progress"],
            "+-------+------+\n| name  | city |\n| Alice | 東京 |\n+-------+------+\n",
            "[####################] 2/2\n",
        ),
        (
            "\"a,b\",\"c\"\"d\"\r\nx,z",
            vec!["--bare", "--right"],
            "a,b  c\"d\n  x    z\n",
            "",
        ),
        ("Ω,x\na,🙂", vec!["--wide", "--bare"], "Ω  x \na   🙂\n", ""),
    ] {
        let output = run(&exe, source.as_bytes(), &args);
        assert_eq!(output.status.code(), Some(0), "{source:?}: {output:?}");
        assert_eq!(output.stdout, stdout.as_bytes());
        assert_eq!(output.stderr, stderr.as_bytes());
    }
    let invalids: Vec<Vec<u8>> = vec![
        b"a,b\nc".to_vec(),
        b"\"a".to_vec(),
        b"\"a\nb\",c".to_vec(),
        b"\x1b[31m".to_vec(),
        b"a,\xff".to_vec(),
        "a\u{9b}31m".as_bytes().to_vec(),
        "a\u{202e}".as_bytes().to_vec(),
        "a".repeat(4097).into_bytes(),
        ",".repeat(64).into_bytes(),
        "a\n".repeat(1025).into_bytes(),
        vec![b'a'; 1048577],
    ];
    for source in invalids {
        let output = run(&exe, &source, &[]);
        assert_eq!(
            output.status.code(),
            Some(2),
            "len {}: {output:?}",
            source.len()
        );
        assert!(output.stdout.is_empty(), "{output:?}");
        assert_eq!(
            output.stderr,
            b"csv-table: invalid input or resource limit\n"
        );
    }
    for args in [vec!["--unknown"], vec!["operand"], vec!["--bare=yes"]] {
        let output = run(&exe, b"a", &args);
        assert_eq!(output.status.code(), Some(2), "{output:?}");
        assert!(output.stdout.is_empty());
    }
    let help = run(&exe, b"invalid CSV", &["--help"]);
    assert_eq!(help.status.code(), Some(0));
    assert_eq!(
        help.stdout,
        b"Usage: csv-table [--bare] [--right] [--wide] [--progress]\n"
    );
    let record = std::iter::repeat_n("a", 64).collect::<Vec<_>>().join(",") + "\n";
    let source = record.repeat(1024);
    let output = run(&exe, source.as_bytes(), &["--bare", "--progress"]);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    let line = std::iter::repeat_n("a", 64).collect::<Vec<_>>().join("  ") + "\n";
    assert_eq!(output.stdout, line.repeat(1024).as_bytes());
    assert_eq!(output.stderr, b"[####################] 1024/1024\n");
}
#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn csv_table_frees_every_owner_on_allocation_and_io_failure() {
    let exe = executable("csv_table");
    let input = common::TempArtifact::new("laniusc_csv_table", "fault_input", None);
    input.write_bytes(b"a,b\nc,d\n");
    let trace = common::TempArtifact::new("laniusc_csv_table", "trace", None);
    let command = |fault: Option<String>| {
        let mut cmd = std::process::Command::new("strace");
        cmd.args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        if let Some(fault) = fault {
            cmd.arg("-e").arg(fault);
        }
        cmd.arg(exe.path())
            .arg("--progress")
            .stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            ));
        cmd
    };
    let baseline = common::short_process_output_with_timeout(
        "csv-table allocation baseline",
        &mut command(None),
    );
    assert_eq!(baseline.status.code(), Some(0), "{baseline:?}");
    let count = freed(&std::fs::read_to_string(trace.path()).unwrap());
    assert!(
        count >= 10,
        "fixture must exercise nested CSV rows and table owners"
    );
    for when in 1..=count {
        let output = common::short_process_output_with_timeout(
            "csv-table allocation denial",
            &mut command(Some(format!("inject=mmap:error=ENOMEM:when={when}+"))),
        );
        assert_eq!(
            output.status.code(),
            Some(4),
            "allocation {when}: {output:?}"
        );
        assert!(output.stdout.is_empty());
        assert_eq!(output.stderr, b"csv-table: allocation failed\n");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(events.contains("INJECTED"));
        freed(&events);
    }
    for fault in [
        "inject=read:error=EIO:when=1",
        "inject=write:error=EIO:when=1",
        "inject=write:error=EIO:when=2",
    ] {
        let output = common::short_process_output_with_timeout(
            "csv-table I/O failure",
            &mut command(Some(fault.to_owned())),
        );
        assert_eq!(output.status.code(), Some(3), "{fault}: {output:?}");
        freed(&std::fs::read_to_string(trace.path()).unwrap());
    }
    for fault in [
        "inject=read:error=EINTR:when=1",
        "inject=write:error=EINTR:when=1",
    ] {
        let output = common::short_process_output_with_timeout(
            "csv-table interrupted I/O retry",
            &mut command(Some(fault.to_owned())),
        );
        assert_eq!(output.status.code(), Some(0), "{fault}: {output:?}");
        assert_eq!(output.stdout, baseline.stdout);
        assert_eq!(output.stderr, baseline.stderr);
        freed(&std::fs::read_to_string(trace.path()).unwrap());
    }
}
