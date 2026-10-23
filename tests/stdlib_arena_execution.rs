#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    time::Duration,
};
fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_arena", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn fixture(name: &str) -> common::TempArtifact {
    executable(&format!(
        "tests/fixtures/stdlib_foundation/arena_{name}.lani"
    ))
}
fn checked(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let result = line.rsplit(" = ").next().unwrap();
            if result.starts_with("0x") {
                assert!(
                    live.insert(result.split_whitespace().next().unwrap().to_owned()),
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
#[test]
fn arena_contracts_execute_alignment_stability_lifecycle_zero_bytes_and_errors() {
    let exe = fixture("contracts");
    let trace = common::TempArtifact::new("laniusc_arena", "contracts", None);
    let output = common::process_output_with_timeout(
        "arena contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    checked(&output);
    assert!(output.stdout.is_empty());
    assert!(freed(&std::fs::read_to_string(trace.path()).unwrap()) >= 2);
}
#[test]
fn typed_arena_storage_executes_primitive_widths_nested_records_enums_and_zero_sizes() {
    let exe = fixture("types");
    let trace = common::TempArtifact::new("laniusc_arena", "types", None);
    let output = common::process_output_with_timeout(
        "arena types",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    checked(&output);
    assert!(output.stdout.is_empty());
    assert!(freed(&std::fs::read_to_string(trace.path()).unwrap()) > 0);
}
#[test]
fn zero_sized_and_empty_typed_requests_use_no_allocator_even_at_i32_max_count() {
    let exe = fixture("zero_sized");
    let trace = common::TempArtifact::new("laniusc_arena", "zero-sized", None);
    let output = common::process_output_with_timeout(
        "arena zero-size",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    checked(&output);
    assert!(output.stdout.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}
#[test]
fn standalone_typed_copy_executes_without_other_generic_instantiations() {
    let exe = executable("tests/fixtures/stdlib_foundation/arena_dependency/entry.lani");
    let output = common::short_process_output_with_timeout(
        "standalone arena generic copy",
        &mut Command::new(exe.path()),
    );
    checked(&output);
    assert!(output.stdout.is_empty());
}
#[derive(Clone, Copy, Debug)]
struct Op {
    action: u8,
    size: i32,
    align: i32,
}
#[derive(Debug)]
struct Model {
    chunk_size: u64,
    max_retained: u64,
    max_chunks: usize,
    chunks: Vec<(u64, u64)>,
    current: usize,
    retained: u64,
    used: u64,
    requested: u64,
    allocations: u64,
    live: bool,
}
impl Model {
    fn new(chunk_size: u64, max_retained: u64, max_chunks: usize) -> Self {
        Self {
            chunk_size,
            max_retained,
            max_chunks,
            chunks: vec![],
            current: 0,
            retained: 0,
            used: 0,
            requested: 0,
            allocations: 0,
            live: true,
        }
    }
    fn row(&self, code: i32) -> [i32; 6] {
        [
            code,
            self.retained as i32,
            self.chunks.len() as i32,
            self.used as i32,
            self.requested as i32,
            self.allocations as i32,
        ]
    }
    fn op(&mut self, op: Op) -> [i32; 6] {
        let code = match op.action {
            0 => self.allocate(op.size, op.align),
            1 => {
                if !self.live {
                    8
                } else {
                    for c in &mut self.chunks {
                        c.1 = 0;
                    }
                    self.current = 0;
                    self.used = 0;
                    self.requested = 0;
                    self.allocations = 0;
                    0
                }
            }
            2 => {
                if !self.live {
                    8
                } else {
                    self.clear();
                    0
                }
            }
            3 => {
                self.clear();
                self.live = false;
                0
            }
            _ => panic!(),
        };
        self.row(code)
    }
    fn clear(&mut self) {
        self.chunks.clear();
        self.current = 0;
        self.retained = 0;
        self.used = 0;
        self.requested = 0;
        self.allocations = 0;
    }
    fn allocate(&mut self, size: i32, align: i32) -> i32 {
        if !self.live {
            return 8;
        }
        let alignment = align as u64;
        if align <= 0 || !alignment.is_power_of_two() {
            return 2;
        }
        if alignment > 8 {
            return 9;
        }
        let size = size as u64;
        if size == 0 {
            self.allocations += 1;
            return 0;
        }
        if size > 2_147_483_647 - 32 {
            return 4;
        }
        for i in self.current..self.chunks.len() {
            let (capacity, used) = self.chunks[i];
            let padding = (alignment - used % alignment) % alignment;
            if padding <= capacity - used && size <= capacity - used - padding {
                self.chunks[i].1 += padding + size;
                self.current = i;
                self.used += padding + size;
                self.requested += size;
                self.allocations += 1;
                return 0;
            }
        }
        if self.chunks.len() == self.max_chunks {
            return 6;
        }
        let available = self.max_retained - self.retained;
        if available < 32 || size > available - 32 {
            return 5;
        }
        let capacity = self.chunk_size.max(size).min(available - 32);
        self.current = self.chunks.len();
        self.chunks.push((capacity, size));
        self.retained += 32 + capacity;
        self.used += size;
        self.requested += size;
        self.allocations += 1;
        0
    }
}
fn model_run(exe: &common::TempArtifact, config: (u32, u32, i32), ops: &[Op]) -> Vec<[i32; 6]> {
    let mut input = Vec::new();
    input.extend(config.0.to_le_bytes());
    input.extend(config.1.to_le_bytes());
    input.extend(config.2.to_le_bytes());
    for op in ops {
        input.push(op.action);
        input.extend(op.size.to_le_bytes());
        input.extend(op.align.to_le_bytes());
    }
    let file = common::TempArtifact::new("laniusc_arena", "model-input", None);
    file.write_bytes(input);
    let output = common::process_output_with_timeout(
        "arena model",
        Command::new(exe.path()).stdin(std::fs::File::open(file.path()).unwrap()),
        Duration::from_secs(10),
    );
    checked(&output);
    assert_eq!(output.stdout.len(), ops.len() * 24);
    output
        .stdout
        .chunks_exact(24)
        .map(|r| {
            std::array::from_fn(|i| i32::from_le_bytes(r[i * 4..i * 4 + 4].try_into().unwrap()))
        })
        .collect()
}
#[test]
fn generated_allocation_reset_clear_and_failure_sequences_match_resource_model() {
    let exe = fixture("model");
    for (case, config) in [
        (1, 1000, 8),
        (64, 512, 4),
        (255, 4096, 10),
        (4096, 8192, 1),
        (64, 0, 8),
        (64, 1000, 0),
        (128, 500, 3),
        (8, 1_000_000, 200),
    ]
    .into_iter()
    .enumerate()
    {
        let mut seed = 0x1672_9843u32.wrapping_add(case as u32 * 17);
        let mut next = || {
            seed ^= seed << 13;
            seed ^= seed >> 17;
            seed ^= seed << 5;
            seed
        };
        let mut ops = vec![
            Op {
                action: 0,
                size: 3,
                align: 1,
            },
            Op {
                action: 0,
                size: 1,
                align: 8,
            },
            Op {
                action: 1,
                size: 0,
                align: 0,
            },
            Op {
                action: 0,
                size: 1,
                align: 8,
            },
            Op {
                action: 2,
                size: 0,
                align: 0,
            },
        ];
        for _ in 0..1200 {
            let value = next();
            let action = if value % 37 == 0 {
                2
            } else if value % 13 == 0 {
                1
            } else {
                0
            };
            let sizes = [
                0,
                1,
                2,
                3,
                7,
                8,
                15,
                16,
                17,
                63,
                64,
                65,
                128,
                255,
                1024,
                i32::MAX,
                -1,
            ];
            let alignments = [1, 2, 4, 8, 16, 3, 0];
            ops.push(Op {
                action,
                size: sizes[next() as usize % sizes.len()],
                align: alignments[next() as usize % alignments.len()],
            });
        }
        ops.extend([
            Op {
                action: 3,
                size: 0,
                align: 0,
            },
            Op {
                action: 0,
                size: 3,
                align: 1,
            },
            Op {
                action: 1,
                size: 0,
                align: 0,
            },
            Op {
                action: 2,
                size: 0,
                align: 0,
            },
            Op {
                action: 3,
                size: 0,
                align: 0,
            },
        ]);
        let mut model = Model::new(config.0 as u64, config.1 as u64, config.2 as usize);
        let expected: Vec<_> = ops.iter().map(|o| model.op(*o)).collect();
        let rows = model_run(&exe, config, &ops);
        for (index, (actual, expected)) in rows.iter().zip(expected).enumerate() {
            assert_eq!(*actual, expected, "case={case} op={index} {:?}", ops[index]);
        }
    }
}
#[test]
fn every_observed_chunk_allocation_failure_preserves_stats_views_and_prior_contents() {
    let exe = fixture("failure");
    let trace = common::TempArtifact::new("laniusc_arena", "failure", None);
    let invoke = |fail: Option<usize>| {
        let mut c = Command::new("strace");
        c.args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(n) = fail {
            c.args(["-e", &format!("inject=mmap:error=ENOMEM:when={n}")]);
        }
        let output = common::process_output_with_timeout(
            "arena chunk failure",
            c.arg(exe.path()),
            Duration::from_secs(10),
        );
        checked(&output);
        let failures = std::str::from_utf8(&output.stdout)
            .unwrap()
            .parse::<i32>()
            .unwrap();
        let events = std::fs::read_to_string(trace.path()).unwrap();
        let count = freed(&events);
        (failures, count, events)
    };
    let (failures, count, _) = invoke(None);
    assert_eq!(failures, 0);
    assert!(count >= 10);
    for fail in 1..=count {
        let (failures, _, events) = invoke(Some(fail));
        assert_eq!(failures, 1, "fail={fail}/{count}: {events}");
    }
}
#[test]
fn large_batches_amortize_allocator_calls_and_reuse_chunks_after_reset() {
    let exe = fixture("batch");
    for count in [16_384, 262_144] {
        let trace = common::TempArtifact::new("laniusc_arena", "batch", None);
        let output = common::process_output_with_timeout(
            "arena large batch",
            Command::new("strace")
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap"])
                .arg(exe.path())
                .arg(count.to_string()),
            Duration::from_secs(20),
        );
        checked(&output);
        let chunks = std::str::from_utf8(&output.stdout)
            .unwrap()
            .parse::<usize>()
            .unwrap();
        assert!(chunks > 0 && chunks <= count as usize / 800 + 2);
        assert_eq!(
            freed(&std::fs::read_to_string(trace.path()).unwrap()),
            chunks
        );
    }
}
