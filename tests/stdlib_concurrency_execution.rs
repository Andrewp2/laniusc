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
