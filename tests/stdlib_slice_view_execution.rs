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
    let file = common::TempArtifact::new("laniusc_slice_view", name, None);
    file.write_bytes(&bytes);
    std::fs::set_permissions(file.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    file
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn borrowed_views_execute_with_native_strides_generic_payloads_and_cursor_forks() {
    let exe = executable("core_slice_view");
    let output = common::short_process_output_with_timeout(
        "slice view contracts",
        &mut std::process::Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert_eq!(output.stdout, b"world", "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn slice_view_overclaims_preserve_native_physical_bounds_checks() {
    let exe = executable("core_slice_view_bounds");
    let output = common::short_process_output_with_timeout(
        "slice view physical bounds",
        &mut std::process::Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(101), "{output:?}");
}

struct Model {
    values: [u8; 16],
    range: std::ops::Range<usize>,
    input: Vec<u8>,
    expected: Vec<u8>,
    reply_ends: Vec<usize>,
}
impl Model {
    fn new() -> Self {
        Self {
            values: std::array::from_fn(|i| i as u8),
            range: 0..16,
            input: vec![],
            expected: vec![],
            reply_ends: vec![],
        }
    }
    fn command(&mut self, op: u8, a: i32, b: i32, c: i32) {
        for n in [a, b, c] {
            assert!((-1..=254).contains(&n));
        }
        self.input
            .extend_from_slice(&[op, (a + 1) as u8, (b + 1) as u8, (c + 1) as u8]);
        let len = self.range.len() as i32;
        let (status, value) = match op {
            0 | 1 => {
                let parent = if op == 0 { 0..16 } else { self.range.clone() };
                if a >= 0 && b >= a && b <= parent.len() as i32 {
                    self.range = parent.start + a as usize..parent.start + b as usize;
                    (1, (b - a) as u8)
                } else {
                    (0, 255)
                }
            }
            2 if a >= 0 && a < len => {
                let old = std::mem::replace(
                    &mut self.values[self.range.start + a as usize],
                    (b + 1) as u8,
                );
                (1, old)
            }
            3 if a >= 0 && b >= a && b <= len && c >= 0 && c <= len - (b - a) => {
                self.values[self.range.clone()].copy_within(a as usize..b as usize, c as usize);
                (1, (b - a) as u8)
            }
            4 => {
                self.values[self.range.clone()].reverse();
                (1, (len / 2) as u8)
            }
            5 => {
                self.values[self.range.clone()].fill((b + 1) as u8);
                (1, len as u8)
            }
            6 if a >= 0 && a < len => (1, self.values[self.range.start + a as usize]),
            2 | 3 | 6 => (0, 255),
            _ => panic!("invalid operation {op}"),
        };
        self.expected
            .extend_from_slice(&[status, value, self.range.len() as u8]);
        self.expected.extend_from_slice(&self.values);
        let current = &self.values[self.range.clone()];
        let mut cursor = current.iter();
        let mut back = false;
        while cursor.len() > 0 {
            self.expected.push(*if back {
                cursor.next_back().unwrap()
            } else {
                cursor.next().unwrap()
            });
            back = !back;
        }
        if c <= 0 {
            self.expected.push(255);
        } else {
            let width = c as usize;
            self.expected.push(current.chunks(width).len() as u8);
            for chunk in current.chunks(width) {
                self.expected.push(chunk.len() as u8);
                self.expected.extend_from_slice(chunk);
            }
            self.expected.push(current.windows(width).len() as u8);
            for window in current.windows(width) {
                self.expected.push(window.len() as u8);
                self.expected.extend_from_slice(window);
            }
        }
        self.reply_ends.push(self.expected.len());
    }
}

#[test]
#[cfg(all(target_os = "linux", target_arch = "x86_64"))]
fn slice_mutations_subviews_chunks_and_windows_match_a_reference_model() {
    let exe = executable("slice_view_model");
    let mut model = Model::new();
    // Every subrange and every relevant window/chunk size, including empty,
    // exact, incomplete, oversized and invalid widths, at nonzero offsets.
    for start in 0..=16 {
        for end in start..=16 {
            for width in -1..=18 {
                model.command(0, start, end, width);
            }
        }
    }
    // Both overlap directions, identical ranges, zero length and rejected
    // copies. Snapshot-sensitive memmove semantics come from Rust's model.
    for start in -1..=6 {
        for end in -1..=6 {
            for destination in -1..=6 {
                model.command(0, 4, 9, 3);
                model.command(3, start, end, destination);
            }
        }
    }
    // Deterministic stateful mutations. Regular resets avoid spending most
    // of the run on an empty view; arbitrary byte values exercise the payload.
    let mut seed = 0x51ce_2026_u32;
    let mut next = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    for n in 0..2048 {
        if n % 8 == 0 {
            let start = (next() % 17) as i32;
            let end = start + (next() % (17 - start as u32)) as i32;
            model.command(0, start, end, (next() % 20) as i32 - 1);
        }
        let op = (next() % 7) as u8;
        let a = (next() % 20) as i32 - 1;
        let b = if op == 2 || op == 5 {
            (next() % 256) as i32 - 1
        } else {
            (next() % 20) as i32 - 1
        };
        model.command(op, a, b, (next() % 20) as i32 - 1);
    }
    let input = common::TempArtifact::new("laniusc_slice_view", "model_input", None);
    input.write_bytes(&model.input);
    let output = common::process_output_with_timeout(
        "slice view model",
        std::process::Command::new(exe.path()).stdin(std::process::Stdio::from(
            std::fs::File::open(input.path()).unwrap(),
        )),
        std::time::Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    if output.stdout != model.expected {
        let first = output
            .stdout
            .iter()
            .zip(&model.expected)
            .position(|(a, b)| a != b)
            .unwrap_or(output.stdout.len().min(model.expected.len()));
        let command = model.reply_ends.partition_point(|end| *end <= first);
        panic!("seed 0x51ce2026, command {command}, output byte {first}: actual {:?}, expected {:?}; actual bytes {}, expected bytes {}", output.stdout.get(first), model.expected.get(first), output.stdout.len(), model.expected.len());
    }
}
