#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    sync::OnceLock,
    time::{Duration, Instant},
};
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("sample_programs/library/image_tool.lani");
        let roots = laniusc_compiler::compiler::EntrySourceRoots {
            stdlib_root: Some(root.join("stdlib")),
            user_roots: vec![root.join("extended")],
        };
        let bytes = common::run_gpu_codegen_with_timeout("image-tool", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(
                    &entry, &roots,
                ),
            )
        })
        .unwrap_or_else(|e| panic!("image-tool: {e}"));
        let exe = common::TempArtifact::new("laniusc_image_tool", "exe", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}
fn run(command: &mut Command, timeout: u64) -> Output {
    common::process_output_with_timeout("image-tool", command, Duration::from_secs(timeout))
}
fn input(bytes: &[u8]) -> common::TempArtifact {
    let source = common::TempArtifact::new("laniusc_image_tool", "input", None);
    source.write_bytes(bytes);
    source
}
fn checked(o: &Output, status: i32) {
    assert_eq!(o.status.code(), Some(status), "{o:?}");
    if status == 0 {
        assert!(o.stderr.is_empty(), "{o:?}");
    }
}
fn oracle(mode: &str, args: &[&str], bytes: &[u8]) -> Output {
    let source = input(bytes);
    run(
        Command::new("python3")
            .arg("tests/fixtures/extended/image_tool_oracle.py")
            .arg(mode)
            .args(args)
            .stdin(std::fs::File::open(source.path()).unwrap()),
        75,
    )
}
fn python_suite(mode: &str, expected_cases: usize) {
    let exe = executable();
    let before = Instant::now();
    let output = run(
        Command::new("python3")
            .arg("tests/fixtures/extended/image_tool_oracle.py")
            .arg(mode)
            .arg(exe.path()),
        75,
    );
    checked(&output, 0);
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.contains(&format!("cases={expected_cases} ")),
        "{summary}"
    );
    eprintln!(
        "{summary}native test wall_ms={}",
        before.elapsed().as_millis()
    );
}
#[test]
fn image_tool_pixels_match_pillow_after_crop_clockwise_rotation_and_each_flip() {
    python_suite("matrix", 209);
}
#[test]
fn image_tool_cli_scalar_caps_snapshot_limits_and_exact_byte_boundaries_execute() {
    python_suite("arguments", 109);
}
#[test]
fn image_tool_info_and_transform_reject_late_png_errors_before_stdout() {
    python_suite("malformed", 28);
}
#[test]
fn image_tool_large_and_thin_images_execute_with_native_time_separate_from_compilation() {
    python_suite("scale", 3);
}
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let tail = line.rsplit(" = ").next().unwrap();
            if tail.starts_with("0x") {
                assert!(
                    live.insert(tail.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "leaked: {events}");
    count
}
fn generated() -> Vec<u8> {
    let output = oracle("generate", &["32", "19", "1019"], &[]);
    checked(&output, 0);
    output.stdout
}
const TRANSFORM: &[&str] = &[
    "transform",
    "--crop",
    "2,1,27,17",
    "--rotate",
    "270",
    "--flip-x",
    "--flip-y",
];
#[test]
fn image_tool_every_reached_allocation_failure_releases_owners_and_stages_output() {
    let good = generated();
    let bad = oracle("late-filter", &[], &[]);
    checked(&bad, 0);
    let exe = executable();
    let mut attempts = 0;
    for (label, bytes, args, baseline_status) in [
        ("transform", good.as_slice(), TRANSFORM, 0),
        ("info", good.as_slice(), &["info"][..], 0),
        ("late-filter", bad.stdout.as_slice(), &["info"][..], 2),
    ] {
        let source = input(bytes);
        let trace = common::TempArtifact::new("laniusc_image_tool", "allocation-trace", None);
        let execute = |at: Option<usize>, status| {
            let mut command = Command::new("strace");
            command
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap,open,openat,socket,connect"]);
            if let Some(at) = at {
                command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={at}")]);
            }
            command
                .arg(exe.path())
                .args(args)
                .stdin(std::fs::File::open(source.path()).unwrap());
            let output = run(&mut command, 30);
            checked(&output, status);
            if status != 0 {
                assert!(output.stdout.is_empty(), "{label} {output:?}");
            }
            if status == 4 {
                assert!(
                    output
                        .stderr
                        .starts_with(b"image-tool: allocation-failure stage="),
                    "{label} {output:?}"
                );
            }
            let events = std::fs::read_to_string(trace.path()).unwrap();
            assert!(
                !events.contains("socket(")
                    && !events.contains("connect(")
                    && !events.contains("open("),
                "{events}"
            );
            let n = freed(&events);
            (n, output)
        };
        let (count, baseline) = execute(None, baseline_status);
        assert!(count > 0);
        if baseline_status == 0 && label == "transform" {
            let decoded = oracle("decode", &[], &baseline.stdout);
            checked(&decoded, 0);
            assert_eq!(
                &decoded.stdout[..8],
                &[17u32.to_le_bytes(), 27u32.to_le_bytes()].concat()
            );
        }
        for at in 1..=count {
            execute(Some(at), 4);
            attempts += 1;
        }
        eprintln!("image-tool {label}: {count} allocation failure positions");
    }
    eprintln!("image-tool allocation fault cases={attempts}");
}
#[test]
fn image_tool_io_failures_interruptions_short_writes_and_failed_diagnostics_cleanup() {
    let good = generated();
    let source = input(&good);
    let exe = executable();
    let trace = common::TempArtifact::new("laniusc_image_tool", "io-trace", None);
    let execute = |injections: &[&str], status, args: &[&str]| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,read,write"]);
        for injection in injections {
            command.args(["-e", injection]);
        }
        let output = run(
            command
                .arg(exe.path())
                .args(args)
                .stdin(std::fs::File::open(source.path()).unwrap()),
            30,
        );
        checked(&output, status);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        freed(&events);
        output
    };
    let baseline = execute(&[], 0, TRANSFORM);
    for injection in [
        "inject=read:error=EINTR:when=1",
        "inject=write:error=EINTR:when=1",
    ] {
        let output = execute(&[injection], 0, TRANSFORM);
        assert_eq!(output.stdout, baseline.stdout);
    }
    let output = execute(&["inject=read:error=EIO:when=1"], 5, TRANSFORM);
    assert!(output.stdout.is_empty());
    assert_eq!(output.stderr, b"image-tool: io-failure stage=input\n");
    let output = execute(&["inject=write:error=EIO:when=1"], 5, TRANSFORM);
    assert!(output.stdout.is_empty());
    assert_eq!(output.stderr, b"image-tool: io-failure stage=output\n");
    let output = execute(&["inject=write:retval=0:when=1"], 5, TRANSFORM);
    assert!(output.stdout.is_empty());
    assert_eq!(output.stderr, b"image-tool: io-failure stage=output\n");
    let output = execute(&["inject=write:error=EIO:when=1+"], 5, &["--bad"]);
    assert!(output.stdout.is_empty());
    assert!(output.stderr.is_empty());
    // strace retval injection skips a syscall. Its positive return models bytes
    // accepted by the host: the remaining observed stream must be the suffix.
    let output = execute(&["inject=write:retval=7:when=1"], 0, TRANSFORM);
    assert_eq!(output.stdout, baseline.stdout[7..]);
    let output = run(
        Command::new("sh")
            .args(["-c", "exec \"$@\" > /dev/full", "image-tool-full-stdout"])
            .arg(exe.path())
            .args(TRANSFORM)
            .stdin(std::fs::File::open(source.path()).unwrap()),
        30,
    );
    checked(&output, 5);
    assert_eq!(output.stderr, b"image-tool: io-failure stage=output\n");
    let output = run(
        Command::new("sh")
            .args(["-c", "exec \"$@\" 2>/dev/full", "image-tool-full-stderr"])
            .arg(exe.path())
            .arg("--bad"),
        30,
    );
    assert_eq!(output.status.code(), Some(5));
    assert!(output.stdout.is_empty());
}
