// Focused native admission for the unified raw slice cursor protocol.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/slice_iterator_integration")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_slice_iterator", name, None);
    exe.write_bytes(bytes); // Unchanged common strict x86 jump checker.
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[test]
fn slice_cursors_compose_with_generic_views_native_stride_and_fixed_containers() {
    let exe = executable("contracts.lani");
    let trace = common::TempArtifact::new("laniusc_slice_iterator", "allocation_trace", None);
    let output = common::process_output_with_timeout(
        "raw slice cursor contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    assert!(
        events.is_empty(),
        "cursor and adapter mechanics allocate nothing: {events}"
    );
}

#[derive(Default)]
struct Models {
    input: Vec<u8>,
    expected: Vec<u8>,
    ends: Vec<usize>,
}
impl Models {
    fn word(&mut self, value: u64) {
        self.expected.extend_from_slice(&value.to_le_bytes());
    }
    fn case(&mut self, length: u64, width: u64, quota: u64) {
        for value in [length, width, quota] {
            self.input.extend_from_slice(&value.to_le_bytes());
        }
        let values: Vec<i32> = (10..10 + length as i32).collect();
        let chunks: Vec<_> = values.chunks(width as usize).collect();
        let windows: Vec<_> = values.windows(width as usize).collect();
        let taken = chunks.len().min(quota as usize);
        for view in chunks[..taken].iter().chain(&windows) {
            self.word(1);
            self.word(view.len() as u64);
            self.word(*view.first().unwrap() as u64);
            self.word(*view.last().unwrap() as u64);
            self.word(view.iter().map(|value| i64::from(*value)).sum::<i64>() as u64);
        }
        self.word(0);
        self.word((chunks.len() - taken) as u64);
        self.word(0); // The chained windows are fully consumed.
        self.word(quota - taken as u64);
        self.word((taken + windows.len()) as u64);
        self.ends.push(self.expected.len());
    }
}

#[test]
fn chunk_window_adapters_match_small_partition_models() {
    let mut models = Models::default();
    for length in 0..=6 {
        for width in [1, 2, 3, 4, 7, i32::MAX as u64] {
            for quota in [0, 1, 5] {
                models.case(length, width, quota);
            }
        }
    }
    let exe = executable("model.lani");
    let input = common::TempArtifact::new("laniusc_slice_iterator", "model_input", None);
    input.write_bytes(&models.input);
    let output = common::process_output_with_timeout(
        "chunk and window adapter models",
        Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(20),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    if output.stdout != models.expected {
        let first = output
            .stdout
            .iter()
            .zip(&models.expected)
            .position(|(a, b)| a != b)
            .unwrap_or(output.stdout.len().min(models.expected.len()));
        let case = models.ends.partition_point(|end| *end <= first);
        panic!(
            "case {case}, first different byte {first}; actual length {}, expected {}",
            output.stdout.len(),
            models.expected.len()
        );
    }
    eprintln!(
        "{} partition/window commands passed in one native process",
        models.ends.len()
    );
}
