//! Forked workers, libatomic words, futex synchronization and bounded MPMC
//! channels: exact stress invariants plus two sample programs.
#![cfg(all(target_os = "linux", target_arch = "x86_64", target_env = "gnu"))]
mod common;

use std::{
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    time::Duration,
};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn native(relative: &'static str, stem: &str) -> common::TempArtifact {
    let entry = root().join(relative);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root().join("stdlib")),
        user_roots: Vec::new(),
    };
    let options = laniusc_compiler::compiler::NativeLinkOptions {
        libraries: vec!["atomic".into()],
        ..Default::default()
    };
    let bytes = common::run_gpu_codegen_with_timeout(relative, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_native_link(
                &entry, &roots, &options,
            ),
        )
    })
    .unwrap_or_else(|error| panic!("{relative}: {error}"));
    let file = common::TempArtifact::new("laniusc_concurrency", stem, None);
    fs::write(file.path(), bytes).unwrap();
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}

fn run(file: &common::TempArtifact, input: Option<PathBuf>) -> String {
    let mut command = Command::new(file.path());
    match input {
        Some(path) => command.stdin(fs::File::open(path).unwrap()),
        None => command.stdin(Stdio::null()),
    };
    let output = common::process_output_with_timeout("concurrency program", &mut command, Duration::from_secs(60));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    String::from_utf8(output.stdout).unwrap()
}

#[test]
fn workers_keep_exact_atomic_lock_once_barrier_and_channel_invariants() {
    let stress = native("tests/fixtures/stdlib_execution/concurrency/stress.lani", "stress");
    let expected = "atomic-fetch-add 8 1600000\n\
                    mutex-increments 8 400000\n\
                    lazy-init-runs-seen 1 16\n\
                    barrier-rounds-leaders 200 200\n\
                    channel-mpmc-producers-consumers 6 4\n\
                    channel-mpmc-capacity-received 64 120000\n\
                    channel-fifo-violations-consumer-ends 0 4\n\
                    channel-mpmc-producers-consumers 16 8\n\
                    channel-mpmc-capacity-received 1 80000\n\
                    channel-fifo-violations-consumer-ends 0 8\n\
                    channel-mpmc-producers-consumers 1 12\n\
                    channel-mpmc-capacity-received 7 50000\n\
                    channel-fifo-violations-consumer-ends 0 12\n\
                    channel-edge-cases 12 0\n";
    for _ in 0..3 {
        assert_eq!(run(&stress, None), expected);
    }
}

#[test]
fn channel_pipeline_disconnects_stage_by_stage() {
    let pipeline = native("sample_programs/library/channel_pipeline.lani", "pipeline");
    let sum: u128 = (1..=200000u128).map(|v| v * v).sum::<u128>() % 1_000_000_000;
    assert_eq!(run(&pipeline, None), format!("200000 {sum}\n"));
}

#[test]
fn parallel_word_count_matches_a_sequential_oracle() {
    let program = native("sample_programs/library/parallel_word_count.lani", "word_count");
    let mut state: u64 = 7;
    let pieces: [&[u8]; 9] = [b"alpha", b"be", b"c", b"\t", b"\n", b"  ", b"\xc3\xa9", b"zz\r\n", b"\x0b"];
    for size in [0usize, 1, 65535, 65536, 65537, 3_000_000] {
        let mut input = Vec::with_capacity(size + 8);
        while input.len() < size {
            state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            input.extend_from_slice(pieces[(state >> 33) as usize % pieces.len()]);
        }
        input.truncate(size);
        let space = |b: u8| b == b' ' || (9..=13).contains(&b);
        let lines = input.iter().filter(|&&b| b == b'\n').count();
        let words = (0..input.len()).filter(|&i| !space(input[i]) && (i == 0 || space(input[i - 1]))).count();
        let path = common::TempArtifact::new("laniusc_concurrency", "word_count_input", Some("txt"));
        fs::write(path.path(), &input).unwrap();
        assert_eq!(run(&program, Some(path.path().to_path_buf())), format!("{lines} {words} {}\n", input.len()), "size {size}");
    }
}

#[test]
fn struct_payloads_and_work_stealing_keep_exact_counts() {
    let steal = native("tests/fixtures/stdlib_execution/concurrency/steal.lani", "steal");
    let expected = "struct-channel-received 80000 80000\n\
                    struct-channel-torn-fifo-violations 0 0\n\
                    steal-tree-workers-tasks 1 524287\n\
                    steal-tree-leaves-once-overflow 262144 0\n\
                    steal-tree-workers-tasks 8 524287\n\
                    steal-tree-leaves-once-overflow 262144 0\n\
                    steal-seeded-tasks-sum-exact 20000 1\n";
    for _ in 0..3 {
        let mut command = Command::new(steal.path());
        command.stdin(Stdio::null());
        let output = common::process_output_with_timeout("work-stealing stress", &mut command, Duration::from_secs(60));
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(String::from_utf8(output.stdout).unwrap(), expected);
        // Scheduling-dependent steal counts go to stderr; the program itself
        // fails unless the 8-worker groups stole at least once.
        let stderr = String::from_utf8(output.stderr).unwrap();
        assert!(stderr.contains("steal-tree stolen 0 busy-workers 1\n"), "{stderr}");
        assert!(stderr.contains("steal-seeded stolen "), "{stderr}");
    }
}

#[test]
fn parallel_quicksort_sorts_a_permutation() {
    let program = native("sample_programs/library/parallel_quicksort.lani", "quicksort");
    let mut command = Command::new(program.path());
    command.stdin(Stdio::null());
    let output = common::process_output_with_timeout("parallel quicksort", &mut command, Duration::from_secs(60));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stdout, b"sorted 2000000\n");
    assert!(String::from_utf8(output.stderr).unwrap().starts_with("tasks "));
}

#[test]
fn parallel_slices_and_cancellation_keep_exact_counts() {
    let program = native("tests/fixtures/stdlib_execution/concurrency/parallel.lani", "parallel");
    let expected = "for-each-chunks-indices-once 245 1000003\n\
                    map-squares-exact 1000003 1000003\n\
                    reduce-sum-ok-ordered-hash-ok 1 1\n\
                    prefix-sum-exact 1000003 1000003\n\
                    merge-sort-sorted-stable 1 1\n\
                    merge-sort-rounds-checksum-ok 8 1\n\
                    failing-chunk-code-duplicates 7 0\n\
                    deadline-for-each-cancelled 1 1\n\
                    steal-cancel-by-worker-balanced-cancelled-workers 1 8\n\
                    steal-cancel-by-deadline-balanced-cancelled-workers 1 8\n\
                    join-until-timed-out-then-clean 1 1\n\
                    signal-all-sent-signal 1 9\n";
    for _ in 0..3 {
        let mut command = Command::new(program.path());
        command.stdin(Stdio::null());
        let output = common::process_output_with_timeout("parallel slices", &mut command, Duration::from_secs(60));
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert_eq!(String::from_utf8(output.stdout).unwrap(), expected);
    }
}

#[test]
fn parallel_grep_matches_fixed_string_grep() {
    let program = native("sample_programs/library/parallel_grep.lani", "grep");
    let mut state: u64 = 3;
    let mut input = Vec::new();
    for _ in 0..200_000 {
        state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
        let len = (state >> 58) as usize;
        for k in 0..len { input.push(b"abcz \t"[((state >> (k % 50)) % 6) as usize]); }
        input.push(b'\n');
    }
    input.extend_from_slice(b"tail ab");
    let path = common::TempArtifact::new("laniusc_concurrency", "grep_input", Some("txt"));
    fs::write(path.path(), &input).unwrap();
    for pattern in ["ab", "zz", "a b", "", "qqq"] {
        let lines: Vec<&[u8]> = input.split(|&b| b == b'\n').collect();
        let mut expected = Vec::new();
        for line in &lines {
            if pattern.is_empty() || line.windows(pattern.len()).any(|w| w == pattern.as_bytes()) {
                expected.extend_from_slice(line);
                expected.push(b'\n');
            }
        }
        let mut command = Command::new(program.path());
        command.arg(pattern).stdin(fs::File::open(path.path()).unwrap());
        let output = common::process_output_with_timeout("parallel grep", &mut command, Duration::from_secs(60));
        assert_eq!(output.status.code(), Some(if expected.is_empty() { 1 } else { 0 }), "{pattern:?}");
        assert_eq!(output.stdout, expected, "{pattern:?}");
    }
}
