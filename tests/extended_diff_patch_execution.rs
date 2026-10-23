mod common;
use laniusc_compiler::compiler::{compile_entry_to_x86_64_with_source_roots, EntrySourceRoots};
fn compile(path: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(compile_entry_to_x86_64_with_source_roots(&entry, &roots))
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"))
}
#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn shortest_byte_line_script_contracts() {
    let bytes = compile("tests/fixtures/extended/diff_contracts.lani");
    let output = common::run_x86_64_elf_output("diff contracts", "contracts", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn request(mode: u8, context: u8, before: &[u8], after: &[u8]) -> Vec<u8> {
    let mut bytes = vec![mode, context];
    bytes.extend_from_slice(&(before.len() as u32).to_le_bytes());
    bytes.extend_from_slice(before);
    bytes.extend_from_slice(after);
    bytes
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn run(executable: &std::path::Path, input: &[u8]) -> std::process::Output {
    let source = common::TempArtifact::new("laniusc_diff_patch", "request", None);
    source.write_bytes(input);
    common::short_process_output_with_timeout(
        "native diff/patch oracle",
        std::process::Command::new(executable).stdin(std::process::Stdio::from(
            std::fs::File::open(source.path()).unwrap(),
        )),
    )
}

fn minimum_edits(before: &[u8], after: &[u8]) -> usize {
    let old: Vec<_> = before.split_inclusive(|&b| b == b'\n').collect();
    let new: Vec<_> = after.split_inclusive(|&b| b == b'\n').collect();
    // Independent quadratic dynamic programming oracle; replacements cost two.
    let mut previous: Vec<usize> = (0..=new.len()).collect();
    for (i, a) in old.iter().enumerate() {
        let mut row = vec![i + 1; new.len() + 1];
        for (j, b) in new.iter().enumerate() {
            row[j + 1] = if a == b {
                previous[j]
            } else {
                1 + row[j].min(previous[j + 1])
            };
        }
        previous = row;
    }
    previous[new.len()]
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn native_scripts_are_minimal_and_patches_roundtrip_generated_bytes() {
    use std::os::unix::fs::PermissionsExt;
    let bytes = compile("tests/fixtures/extended/diff_oracle.lani");
    let executable = common::TempArtifact::new("laniusc_diff_patch", "oracle", None);
    executable.write_bytes(&bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    let dictionary: &[&[u8]] = &[
        b"a\n",
        b"b\n",
        b"a\n",
        b"\n",
        b"\0\xff\n",
        b"q\r\n",
        b"----\n",
        b"@@\n",
    ];
    let mut seed = 0x517c_4e21u32;
    for case in 0..220 {
        let mut generate = |length: usize| {
            let mut output = Vec::new();
            for _ in 0..length {
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                output.extend_from_slice(dictionary[(seed >> 16) as usize % dictionary.len()]);
            }
            output
        };
        let mut before = generate(case % 13);
        let mut after = generate(case * 7 % 15);
        if case % 3 == 0 && before.last() == Some(&b'\n') {
            before.pop();
        }
        if case % 5 == 0 && after.last() == Some(&b'\n') {
            after.pop();
        }
        if case % 11 == 0 {
            after = before.clone();
        }
        let context = (case % 5) as u8;
        let input = request(0, context, &before, &after);
        let diff = run(executable.path(), &input);
        assert_eq!(
            diff.status.code(),
            Some(0),
            "seed 0x517c4e21 case {case}: {diff:?}"
        );
        assert!(diff.stderr.is_empty(), "{diff:?}");
        let distance = u32::from_le_bytes(diff.stdout[..4].try_into().unwrap()) as usize;
        assert_eq!(
            distance,
            minimum_edits(&before, &after),
            "case {case}, {before:?}, {after:?}"
        );
        let patch = &diff.stdout[4..];
        let applied = run(executable.path(), &request(1, 0, &before, patch));
        assert_eq!(
            applied.status.code(),
            Some(0),
            "case {case}: {patch:?}, {applied:?}"
        );
        assert_eq!(applied.stdout, after, "case {case}");
        assert!(applied.stderr.is_empty(), "case {case}");
        if case % 20 == 0 {
            assert_eq!(run(executable.path(), &input).stdout, diff.stdout);
        }
    }
    // Preserve a large mostly equal input while retaining a bounded trace.
    let before: Vec<u8> = (0..25000)
        .flat_map(|i| format!("line {i:05}\n").into_bytes())
        .collect();
    let mut after = before.clone();
    after.splice(120000..120011, b"replacement\n".iter().copied());
    let diff = run(executable.path(), &request(0, 3, &before, &after));
    assert_eq!(diff.status.code(), Some(0), "{diff:?}");
    let applied = run(
        executable.path(),
        &request(1, 0, &before, &diff.stdout[4..]),
    );
    assert_eq!(applied.status.code(), Some(0), "{applied:?}");
    assert_eq!(applied.stdout, after);
    assert!(diff.stdout.len() < 300);

    // Python emits an independently formed unified patch. Complete lines avoid
    // difflib's deliberate absence of GNU no-newline markers.
    let old = common::TempArtifact::new("laniusc_diff_patch", "python_old", None);
    let new = common::TempArtifact::new("laniusc_diff_patch", "python_new", None);
    for (before, after) in [
        (b"a\nb\nc\n".as_slice(), b"a\nx\nc\nd\n".as_slice()),
        (b"".as_slice(), b"new\n".as_slice()),
        (b"gone\n".as_slice(), b"".as_slice()),
    ] {
        old.write_bytes(before);
        new.write_bytes(after);
        let patch = common::short_process_output_with_timeout("Python difflib oracle", std::process::Command::new("python3").args(["-c", "import difflib,pathlib,sys; a=pathlib.Path(sys.argv[1]).read_bytes().decode('latin1').splitlines(True); b=pathlib.Path(sys.argv[2]).read_bytes().decode('latin1').splitlines(True); sys.stdout.buffer.write(''.join(difflib.unified_diff(a,b,fromfile='before',tofile='after',n=1)).encode('latin1'))"]).arg(old.path()).arg(new.path()));
        assert!(patch.status.success(), "{patch:?}");
        let applied = run(executable.path(), &request(1, 0, before, &patch.stdout));
        assert_eq!(applied.status.code(), Some(0), "{applied:?}");
        assert_eq!(applied.stdout, after);
    }
    let valid = b"--- before\n+++ after\n@@ -1,2 +1,2 @@\n a\n-b\n+x\n@@ -5 +5 @@\n-e\n+y\n";
    let base = b"a\nb\nc\nd\ne\n";
    let mut conflict = base.to_vec();
    conflict[8] = b'z';
    let failed = run(executable.path(), &request(1, 0, &conflict, valid));
    assert_eq!(failed.status.code(), Some(3), "{failed:?}");
    assert!(failed.stdout.is_empty());
    for malformed in [
        b"--- a\n+++ b\n".as_slice(),
        b"--- a\n+++ b\n@@ -0 +1 @@\n-a\n+b\n",
        b"--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b",
        b"--- a\n+++ b\n@@ -1 +1 @@\n a\n",
        b"--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\ntrailing\n",
        b"--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\n\\ No newline at end of file\n\\ No newline at end of file\n",
        b"--- a\n+++ b\n@@ -2147483648 +1 @@\n-a\n+b\n",
        b"--- a\n+++ b\n@@ -1 +1 @@ context\n-a\n+b\n",
        b"diff --git a/a b/a\n--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\n",
        b"--- a\n+++ b\n@@ -1 +1 @@\n-a\n+b\n--- c\n+++ d\n@@ -1 +1 @@\n-c\n+d\n",
    ] {
        let failed = run(executable.path(), &request(1, 0, b"a\n", malformed));
        assert_eq!(failed.status.code(), Some(2), "{malformed:?}: {failed:?}");
        assert!(failed.stdout.is_empty(), "{failed:?}");
    }
    check_allocation_failures(executable.path(), &request(0, 1, b"a\nb\n", b"a\nx"));
    check_allocation_failures(executable.path(), &request(1, 0, base, valid));
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn allocations_freed(trace: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in trace.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(
                    live.insert(result.split_whitespace().next().unwrap().to_owned()),
                    "{trace}"
                );
                count += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(line.ends_with(" = 0"), "{trace}");
            assert!(live.remove(tail.split(',').next().unwrap()), "{trace}");
        }
    }
    assert!(live.is_empty(), "leaked allocations {live:?}: {trace}");
    count
}

#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn check_allocation_failures(executable: &std::path::Path, bytes: &[u8]) {
    let input = common::TempArtifact::new("laniusc_diff_patch", "fault_input", None);
    input.write_bytes(bytes);
    let trace = common::TempArtifact::new("laniusc_diff_patch", "trace", None);
    let traced = |fault: Option<usize>| {
        let mut command = std::process::Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(when) = fault {
            command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={when}")]);
        }
        common::short_process_output_with_timeout(
            "diff patch allocation sweep",
            command.arg(executable).stdin(std::process::Stdio::from(
                std::fs::File::open(input.path()).unwrap(),
            )),
        )
    };
    let success = traced(None);
    assert!(success.status.success(), "{success:?}");
    let count = allocations_freed(&std::fs::read_to_string(trace.path()).unwrap());
    assert!(count > 4, "expected to exercise library allocations");
    for when in 1..=count {
        let failed = traced(Some(when));
        assert_eq!(
            failed.status.code(),
            Some(4),
            "allocation {when}/{count}: {failed:?}"
        );
        assert!(failed.stdout.is_empty(), "allocation {when}: {failed:?}");
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(events.contains("INJECTED"), "{events}");
        allocations_freed(&events);
    }
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn strict_patch_direct_limits_and_aliased_storage() {
    let bytes = compile("tests/fixtures/extended/patch_contracts.lani");
    let output = common::run_x86_64_elf_output("patch contracts", "contracts", &bytes);
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}
