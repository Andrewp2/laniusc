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

// std::par sorts, map, reduce and scan against a Rust model of the same modes
// (par_oracle.py runs the larger randomized sweep against Python).
#[test]
fn par_sorts_map_reduce_and_scan_match_a_model() {
    let program = native("tests/fixtures/stdlib_execution/concurrency/par_sort.lani", "par_sort");
    let mut state: u64 = 11;
    let mut shapes: Vec<Vec<i64>> = Vec::new();
    let random: Vec<i64> = (0..150_000)
        .map(|_| { state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407); state as i64 })
        .collect();
    shapes.push(random.clone());
    shapes.push(random.iter().map(|v| v.rem_euclid(5)).collect());
    shapes.push(vec![42; 70_001]);
    shapes.push((0..90_000).collect());
    shapes.push((0..90_000).rev().collect());
    shapes.push(vec![]);
    shapes.push(vec![-1]);
    for keys in &shapes {
        for (mode, workers) in [(0u32, 7u32), (1, 8), (2, 1), (3, 1), (4, 3), (5, 8), (6, 4), (7, 5), (8, 8), (9, 1)] {
            let mut input = Vec::new();
            for word in [mode, workers, keys.len() as u32] { input.extend_from_slice(&word.to_le_bytes()); }
            for key in keys { input.extend_from_slice(&key.to_le_bytes()); }
            let path = common::TempArtifact::new("laniusc_concurrency", "par_input", Some("bin"));
            fs::write(path.path(), &input).unwrap();
            let mut command = Command::new(program.path());
            command.stdin(fs::File::open(path.path()).unwrap());
            let output = common::process_output_with_timeout("par sort", &mut command, Duration::from_secs(60));
            assert_eq!(output.status.code(), Some(0), "mode {mode}");
            let mut expected = Vec::new();
            match mode {
                0 | 2 | 6 => {
                    let mut sorted = keys.clone();
                    sorted.sort();
                    for key in sorted { expected.extend_from_slice(&key.to_le_bytes()); }
                }
                1 | 3 => {
                    let mut order: Vec<u32> = (0..keys.len() as u32).collect();
                    order.sort_by_key(|&i| keys[i as usize]);
                    for &i in &order { expected.extend_from_slice(&keys[i as usize].to_le_bytes()); }
                    for &i in &order { expected.extend_from_slice(&i.to_le_bytes()); }
                }
                4 => for key in keys { expected.extend_from_slice(&((key >> 1) ^ 21845).to_le_bytes()); },
                7 | 9 => {
                    let mut acc = 0u64;
                    for &key in keys { acc = acc.wrapping_add(key as u64); expected.extend_from_slice(&acc.to_le_bytes()); }
                }
                8 => {
                    let (mut a, mut b) = (1u64, 0u64);
                    for &key in keys {
                        let (ka, kb) = ((key as u64) % 1_000_000_007, ((key as u64) >> 20) % 1_000_000_007);
                        (a, b) = (ka * a % 1_000_000_007, (ka * b + kb) % 1_000_000_007);
                        expected.extend_from_slice(&a.to_le_bytes());
                        expected.extend_from_slice(&b.to_le_bytes());
                    }
                }
                _ => {
                    let (mut sum, mut hash, mut scale) = (0u64, 0u64, 1u64);
                    for &key in keys {
                        let v = key as u64;
                        sum = sum.wrapping_add(v);
                        hash = (hash * 131 + v % 1_000_000_007) % 1_000_000_007;
                        scale = scale * 131 % 1_000_000_007;
                    }
                    for word in [sum, hash, scale] { expected.extend_from_slice(&word.to_le_bytes()); }
                }
            }
            assert!(output.stdout == expected, "mode {mode} workers {workers} n {}", keys.len());
        }
    }
}

// std::uring: the fixture's exact checks (backpressure, a 10,000-op stream,
// short reads, EOF, errors, links, accept/recv/send, transfer), then the cat
// and copy samples on block-boundary sizes, a pipe and a missing name
// (uring_oracle.py runs the larger comparison against GNU cat and cp).
#[test]
fn uring_checks_and_batched_cat_and_copy_are_exact() {
    let fixture = native("tests/fixtures/stdlib_execution/concurrency/uring.lani", "uring");
    let scratch = common::TempArtifact::new("laniusc_concurrency", "uring_dir", None);
    fs::create_dir_all(scratch.path()).unwrap();
    let mut command = Command::new(fixture.path());
    command.arg("checks").arg(scratch.path());
    let output = common::process_output_with_timeout("uring checks", &mut command, Duration::from_secs(60));
    let text = String::from_utf8(output.stdout).unwrap();
    assert_eq!(output.status.code(), Some(0), "{text}");
    assert!(!text.contains("FAIL"), "{text}");
    assert!(text.contains("stream.completed 10000\n") && text.contains("full.cq 16\n"), "{text}");

    let cat = native("sample_programs/library/uring_cat.lani", "uring_cat");
    let copy = native("sample_programs/library/uring_copy.lani", "uring_copy");
    let mut state: u64 = 5;
    let mut files = Vec::new();
    let mut expected = Vec::new();
    for (index, size) in [0usize, 1, 4095, 131071, 131072, 131073, 1048577, 2_000_003].into_iter().enumerate() {
        let bytes: Vec<u8> = (0..size).map(|_| {
            state = state.wrapping_mul(6364136223846793005).wrapping_add(1442695040888963407);
            (state >> 56) as u8
        }).collect();
        let path = scratch.path().join(format!("f{index}"));
        fs::write(&path, &bytes).unwrap();
        expected.extend_from_slice(&bytes);
        let target = scratch.path().join(format!("c{index}"));
        fs::write(&target, vec![b'x'; size + 100]).unwrap();
        let mut command = Command::new(copy.path());
        command.arg(&path).arg(&target);
        let output = common::process_output_with_timeout("uring copy", &mut command, Duration::from_secs(60));
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(fs::read(&target).unwrap() == bytes, "copy {size}");
        files.push(path);
    }
    let mut command = Command::new(cat.path());
    command.args(&files);
    let output = common::process_output_with_timeout("uring cat", &mut command, Duration::from_secs(60));
    assert_eq!(output.status.code(), Some(0), "{:?}", output.status);
    assert!(output.stdout == expected);
    // stdin through "-", and a missing name: skipped, exit 1, one diagnostic.
    let missing = scratch.path().join("missing");
    let mut command = Command::new(cat.path());
    command.arg(&files[2]).arg(&missing).arg("-").stdin(fs::File::open(&files[6]).unwrap());
    let output = common::process_output_with_timeout("uring cat", &mut command, Duration::from_secs(60));
    assert_eq!(output.status.code(), Some(1));
    assert!(output.stdout == [fs::read(&files[2]).unwrap(), fs::read(&files[6]).unwrap()].concat());
    assert_eq!(String::from_utf8(output.stderr).unwrap(), format!("uring_cat: {}: errno 2\n", missing.display()));
    fs::remove_dir_all(scratch.path()).unwrap();
}

// std::pthread: parallel sums against the serial sum, a Mutex-guarded
// counter, a bounded Condvar queue and 1,000 sequential spawn/join pairs.
#[test]
fn pthread_sum_counter_queue_and_join_are_exact() {
    let program = native("tests/fixtures/stdlib_execution/concurrency/threads.lani", "threads");
    let text = run(&program, None);
    assert!(!text.contains("FAIL"), "{text}");
    assert!(text.contains("counter 160000\n") && text.contains("join.pairs 1000\n") && text.contains("queue.taken 40000\n"), "{text}");
}
