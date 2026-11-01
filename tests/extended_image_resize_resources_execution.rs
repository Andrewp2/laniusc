//! Exact image-resize owner effects, reached failures and bounded-work scale shapes.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    time::{Duration, Instant},
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/extended_image_resize_resources")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![
            root.join("extended"),
            root.join("tests/fixtures/extended_image_resize_resources"),
        ],
    };
    let bytes = common::run_gpu_codegen_with_timeout("image resize resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("image resize resource {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let file = common::TempArtifact::new("laniusc_image_resize_resources", name, None);
    file.write_bytes(bytes); // The shared writer validates every x86 jump.
    fs::set_permissions(file.path(), fs::Permissions::from_mode(0o700)).unwrap();
    file
}
fn result(line: &str) -> &str {
    line.rsplit_once('=').unwrap().1.trim()
}
fn arguments(line: &str) -> &str {
    line.rsplit_once('=')
        .unwrap()
        .0
        .trim_end()
        .strip_suffix(')')
        .unwrap()
        .split_once('(')
        .unwrap()
        .1
}
fn address(value: &str) -> u64 {
    u64::from_str_radix(value.trim().strip_prefix("0x").unwrap(), 16).unwrap()
}
#[derive(Clone, Debug, PartialEq, Eq)]
enum Action {
    Allocate {
        ordinal: usize,
        size: usize,
        success: bool,
    },
    Release {
        ordinal: usize,
        size: usize,
    },
}
#[derive(Debug, Default)]
struct Operation {
    actions: Vec<Action>,
    attempts: Vec<(usize, usize, bool)>,
    live_at_entry: Vec<(usize, usize)>,
    live_at_return: Vec<(usize, usize)>,
}
#[derive(Debug, Default)]
struct Cycle {
    setup: Vec<Action>,
    backing: Vec<(usize, usize)>,
    operations: Vec<Operation>,
    phases: usize,
    cleanup_phases: Vec<Vec<(usize, usize)>>,
    cleanup_order: Vec<usize>,
}
#[derive(Debug, Default)]
struct Effects {
    cycles: Vec<Cycle>,
    allocations: usize,
    releases: usize,
    output: usize,
}
fn owners(live: &BTreeMap<u64, (usize, usize)>) -> Vec<(usize, usize)> {
    let mut owners = live.values().copied().collect::<Vec<_>>();
    owners.sort_unstable();
    owners
}
fn effects(events: &str, stderr: &[u8], configured: bool) -> Effects {
    let mut effects = Effects::default();
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut cycle: Option<Cycle> = None;
    let mut operation: Option<Operation> = None;
    let mut pure: Option<Vec<(usize, usize)>> = None;
    let (mut sealed, mut cleanup, mut done) = (false, false, false);
    let (mut entries, mut exits, mut reads, mut ordinal) = (0, 0, 0, 0);
    let mut markers = Vec::new();
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert!(!done, "{events}");
            assert_eq!(result(line), "1", "{events}");
            let marker = *b"ASPpCFRED"
                .iter()
                .find(|byte| line.contains(&format!("\"{}\", 1)", char::from(**byte))))
                .unwrap_or_else(|| panic!("unexpected marker: {line}"));
            markers.push(marker);
            match marker {
                b'A' => {
                    assert!(
                        cycle.is_none() && operation.is_none() && pure.is_none() && live.is_empty(),
                        "{events}"
                    );
                    cycle = Some(Cycle::default());
                    sealed = false;
                    cleanup = false;
                }
                b'S' => {
                    assert!(
                        !sealed && !cleanup && operation.is_none() && pure.is_none(),
                        "{events}"
                    );
                    let current = cycle.as_mut().unwrap();
                    assert!(
                        !live.is_empty(),
                        "the witness has real live owners: {events}"
                    );
                    current.backing = owners(&live);
                    sealed = true;
                }
                b'P' => {
                    assert!(
                        sealed && cycle.is_some() && operation.is_none() && pure.is_none(),
                        "{events}"
                    );
                    pure = Some(owners(&live));
                }
                b'p' => {
                    let before = pure.take().unwrap();
                    assert_eq!(
                        before,
                        owners(&live),
                        "all owner identities/extents survive the pure phase"
                    );
                    let current = cycle.as_mut().unwrap();
                    current.phases += 1;
                    if cleanup {
                        current.cleanup_phases.push(before);
                    }
                }
                b'C' => {
                    assert!(
                        sealed
                            && !cleanup
                            && cycle.is_some()
                            && operation.is_none()
                            && pure.is_none(),
                        "{events}"
                    );
                    operation = Some(Operation {
                        live_at_entry: owners(&live),
                        ..Operation::default()
                    });
                }
                b'F' => {
                    assert!(sealed && !cleanup && pure.is_none(), "{events}");
                    let mut completed = operation.take().unwrap();
                    completed.live_at_return = owners(&live);
                    cycle.as_mut().unwrap().operations.push(completed);
                }
                b'R' => {
                    assert!(
                        sealed && !cleanup && operation.is_none() && pure.is_none(),
                        "{events}"
                    );
                    cleanup = true;
                }
                b'E' => {
                    assert!(
                        sealed
                            && cleanup
                            && operation.is_none()
                            && pure.is_none()
                            && live.is_empty(),
                        "caller retires every actual owner before E: {events}"
                    );
                    effects.cycles.push(cycle.take().unwrap());
                    sealed = false;
                    cleanup = false;
                }
                b'D' => {
                    assert!(
                        cycle.is_none() && operation.is_none() && pure.is_none() && live.is_empty(),
                        "{events}"
                    );
                    done = true;
                }
                _ => unreachable!(),
            }
            continue;
        }
        assert!(
            pure.is_none(),
            "borrowed operation performed a host effect: {line}"
        );
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done && live.is_empty(), "{events}");
            exits += 1;
            continue;
        }
        assert!(!done, "only exit follows complete retirement: {events}");
        if line.starts_with("execve(") {
            assert!(cycle.is_none() && entries == 0, "{events}");
            assert_eq!(result(line), "0", "{events}");
            entries += 1;
        } else if line.starts_with("read(0,") {
            assert!(
                configured && reads == 0 && ordinal == 0 && cycle.is_none(),
                "{events}"
            );
            assert_eq!(result(line), "1", "{events}");
            assert!(arguments(line).ends_with(", 1"), "{events}");
            reads += 1;
        } else if line.starts_with("mmap(") {
            assert!(
                cycle.is_some() && !cleanup && (!sealed || operation.is_some()),
                "only setup and marked owned operations may allocate: {events}"
            );
            let fields = arguments(line)
                .split(',')
                .map(str::trim)
                .collect::<Vec<_>>();
            assert_eq!(fields.len(), 6, "{events}");
            assert_eq!(fields[0], "NULL", "{events}");
            assert_eq!(
                &fields[2..],
                &[
                    "PROT_READ|PROT_WRITE",
                    "MAP_PRIVATE|MAP_ANONYMOUS",
                    "-1",
                    "0"
                ],
                "{events}"
            );
            let size: usize = fields[1].parse().unwrap();
            assert!(size > 0, "{events}");
            ordinal += 1;
            let returned = result(line);
            let pointer = returned.split_whitespace().next().unwrap();
            let success = pointer.starts_with("0x");
            if success {
                assert!(!returned.contains("INJECTED"), "{events}");
                let pointer = address(pointer);
                let end = pointer.checked_add(size as u64).unwrap();
                assert!(
                    live.iter()
                        .all(|(&start, &(_, length))| end <= start
                            || pointer >= start + length as u64),
                    "distinct live extents cannot overlap: {events}"
                );
                assert!(live.insert(pointer, (ordinal, size)).is_none(), "{events}");
                effects.allocations += 1;
            } else {
                assert!(
                    operation.is_some()
                        && pointer == "-1"
                        && returned.contains("ENOMEM")
                        && returned.contains("INJECTED"),
                    "only a reached owned-operation denial is admitted: {events}"
                );
            }
            let action = Action::Allocate {
                ordinal,
                size,
                success,
            };
            if let Some(operation) = operation.as_mut() {
                operation.attempts.push((ordinal, size, success));
                operation.actions.push(action);
            } else {
                assert!(success, "{events}");
                cycle.as_mut().unwrap().setup.push(action);
            }
        } else if line.starts_with("munmap(") {
            assert!(
                cycle.is_some() && (!sealed || operation.is_some() || cleanup),
                "borrowed state never releases backing: {events}"
            );
            let (pointer, length) = arguments(line).split_once(',').unwrap();
            let size: usize = length.trim().parse().unwrap();
            let (allocation, actual) = live.remove(&address(pointer)).unwrap_or_else(|| {
                panic!("release of unknown/already retired address: {line}\n{events}")
            });
            assert_eq!(size, actual, "exact live release extent: {events}");
            assert_eq!(result(line), "0", "{events}");
            effects.releases += 1;
            let action = Action::Release {
                ordinal: allocation,
                size,
            };
            if let Some(operation) = operation.as_mut() {
                assert!(
                    !cycle
                        .as_ref()
                        .unwrap()
                        .backing
                        .contains(&(allocation, size)),
                    "resize cannot retire its borrowed source: {events}"
                );
                operation.actions.push(action);
            } else if !sealed {
                cycle.as_mut().unwrap().setup.push(action);
            } else {
                assert!(cleanup, "{events}");
                cycle.as_mut().unwrap().cleanup_order.push(allocation);
            }
        } else if line.starts_with("write(1,") {
            assert!(
                sealed && cleanup && operation.is_none() && cycle.is_some(),
                "publication follows explicit source retirement: {events}"
            );
            let &(ordinal, size, success) = cycle
                .as_ref()
                .unwrap()
                .operations
                .last()
                .unwrap()
                .attempts
                .first()
                .unwrap();
            assert!(
                success,
                "publication uses the successful retry when present: {events}"
            );
            assert_eq!(
                owners(&live),
                [(ordinal, size)],
                "only the independent result may remain at every output write: {events}"
            );
            let requested: usize = arguments(line)
                .rsplit_once(',')
                .unwrap()
                .1
                .trim()
                .parse()
                .unwrap();
            let used: usize = result(line).parse().unwrap();
            assert!(used > 0 && used <= requested, "{events}");
            effects.output += used;
        } else {
            panic!("unexpected host service: {line}");
        }
    }
    assert!(
        done && cycle.is_none() && operation.is_none() && pure.is_none() && live.is_empty(),
        "{events}"
    );
    assert_eq!(
        (entries, exits, reads),
        (1, 1, usize::from(configured)),
        "{events}"
    );
    assert_eq!(
        effects.allocations, effects.releases,
        "cleanup observed before exit: {events}"
    );
    assert_eq!(stderr, markers, "native marker and syscall evidence agree");
    effects
}
fn run(
    executable: &common::TempArtifact,
    mode: Option<u8>,
    failure: Option<usize>,
) -> (Vec<u8>, Effects, Duration) {
    let input = common::TempArtifact::new("laniusc_image_resize_resources", "input", None);
    input.write_bytes([mode.unwrap_or(0)]);
    let trace = common::TempArtifact::new("laniusc_image_resize_resources", "trace", None);
    let mut command = Command::new("strace");
    command
        .args(["--kill-on-exit", "-qq", "-s", "64", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=all", "-e", "signal=none"]);
    if let Some(ordinal) = failure {
        command
            .arg("-e")
            .arg(format!("inject=mmap:error=ENOMEM:when={ordinal}"));
    }
    command
        .arg(executable.path())
        .stdin(Stdio::from(fs::File::open(input.path()).unwrap()));
    let native_start = Instant::now();
    let output = common::process_output_with_timeout(
        "image resize finite owner lifecycle",
        &mut command,
        Duration::from_secs(15),
    );
    let elapsed = native_start.elapsed();
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(
        output.status.code(),
        Some(0),
        "mode={mode:?} denial={failure:?}: {output:?}\n{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.contains("INJECTED"))
            .count(),
        usize::from(failure.is_some()),
        "every configured fault must be reached: {events}"
    );
    let observed = effects(&events, &output.stderr, mode.is_some());
    assert_eq!(observed.output, output.stdout.len());
    (output.stdout, observed, elapsed)
}

#[derive(Clone, Copy, Debug)]
struct Shape {
    sw: usize,
    sh: usize,
    dw: usize,
    dh: usize,
}
impl Shape {
    fn source_bytes(self) -> usize {
        (self.sw * 4 + 5) * self.sh + 7
    }
    fn output_bytes(self) -> usize {
        self.dw * self.dh * 4
    }
    fn workspace(self) -> usize {
        fn gcd(mut a: usize, mut b: usize) -> usize {
            while b != 0 {
                (a, b) = (b, a % b);
            }
            a
        }
        let ix = self.sw + self.dw - gcd(self.sw, self.dw);
        let iy = self.sh + self.dh - gcd(self.sh, self.dh);
        let horizontal = self.sh as u64 * ix as u64 + self.dw as u64 * iy as u64;
        let vertical = self.sw as u64 * iy as u64 + self.dh as u64 * ix as u64;
        let inner = if vertical < horizontal || (vertical == horizontal && self.dh < self.dw) {
            self.dh
        } else {
            self.dw
        };
        // ResizeSum has four u64 native words (32 bytes). Source allocates
        // exactly two rows of min(256, selected inner output dimension).
        2 * inner.min(256) * 4 * 8
    }
}
fn resource_shape(identity: bool) -> Shape {
    Shape {
        sw: 7,
        sh: 5,
        dw: if identity { 7 } else { 11 },
        dh: if identity { 5 } else { 9 },
    }
}
const SCALE: [Shape; 5] = [
    Shape {
        sw: 1024,
        sh: 768,
        dw: 512,
        dh: 384,
    },
    Shape {
        sw: 517,
        sh: 3,
        dw: 257,
        dh: 5,
    },
    Shape {
        sw: 3,
        sh: 517,
        dw: 5,
        dh: 257,
    },
    Shape {
        sw: 65_536,
        sh: 1,
        dw: 1,
        dh: 65_536,
    },
    Shape {
        sw: 1,
        sh: 65_536,
        dw: 65_536,
        dh: 1,
    },
];
fn resource_pixel(x: usize, y: usize) -> [u8; 4] {
    [
        ((37 * x + 19 * y + 17) % 256) as u8,
        ((11 * x + 53 * y + 29) % 256) as u8,
        ((67 * x + 7 * y + 3) % 256) as u8,
        [0, 1, 64, 128, 255][(x + 2 * y) % 5],
    ]
}
// A small independent two-dimensional reference: visit every source pixel,
// using overlap/triangular weight definitions, never the separable traversal.
fn small_expected(case: usize) -> Vec<u8> {
    let shape = resource_shape(case >= 3);
    let mut output = Vec::new();
    for y in 0..shape.dh {
        for x in 0..shape.dw {
            if case >= 3 {
                output.extend(resource_pixel(x, y));
                continue;
            }
            if case == 1 {
                output.extend(resource_pixel(
                    (2 * x + 1) * shape.sw / (2 * shape.dw),
                    (2 * y + 1) * shape.sh / (2 * shape.dh),
                ));
                continue;
            }
            let weight = |d: usize, s: usize, t: usize, i: usize| -> u64 {
                if case == 0 {
                    ((d + 1) * s)
                        .min((i + 1) * t)
                        .saturating_sub((d * s).max(i * t)) as u64
                } else {
                    let position = ((2 * d + 1) as i64 * s as i64 - t as i64)
                        .clamp(0, ((s - 1) * 2 * t) as i64);
                    (2 * t as i64 - (position - (i * 2 * t) as i64).abs()).max(0) as u64
                }
            };
            let (mut denominator, mut alpha, mut colors) = (0_u64, 0_u64, [0_u64; 3]);
            for sy in 0..shape.sh {
                for sx in 0..shape.sw {
                    let w = weight(x, shape.sw, shape.dw, sx) * weight(y, shape.sh, shape.dh, sy);
                    let pixel = resource_pixel(sx, sy);
                    denominator += w;
                    alpha += w * u64::from(pixel[3]);
                    for c in 0..3 {
                        colors[c] += w * u64::from(pixel[3]) * u64::from(pixel[c]);
                    }
                }
            }
            if alpha == 0 {
                output.extend([0; 4]);
            } else {
                for c in colors {
                    output.push(((c + alpha / 2) / alpha) as u8);
                }
                output.push(((alpha + denominator / 2) / denominator) as u8);
            }
        }
    }
    output
}
fn scale_expected(case: usize) -> Vec<u8> {
    let shape = SCALE[case];
    let mut output = Vec::with_capacity(shape.output_bytes());
    for y in 0..shape.dh {
        for x in 0..shape.dw {
            let pixel = match case {
                0 => {
                    let alpha = [0, 1, 128, 255][(x + y) % 4];
                    if alpha == 0 {
                        [0; 4]
                    } else {
                        [
                            ((x * 17 + y * 23 + 11) % 256) as u8,
                            ((x * 31 + y * 7 + 19) % 256) as u8,
                            ((x * 5 + y * 47 + 29) % 256) as u8,
                            alpha,
                        ]
                    }
                }
                1 | 2 => {
                    // Opaque half-plane steps: integrate each independent channel
                    // with one clamped interval, rather than traversing pixels.
                    let boundaries = if case == 1 { (258, 1) } else { (1, 258) };
                    let left = (boundaries.0 * shape.dw)
                        .saturating_sub(x * shape.sw)
                        .min(shape.sw);
                    let top = (boundaries.1 * shape.dh)
                        .saturating_sub(y * shape.sh)
                        .min(shape.sh);
                    [
                        ((255 * left + shape.sw / 2) / shape.sw) as u8,
                        ((255 * top + shape.sh / 2) / shape.sh) as u8,
                        17,
                        255,
                    ]
                }
                // The thin source repeats 256 colors, with only odd indices
                // opaque. Exact average RGB is (128,127,128); alpha is 127.5.
                3 | 4 => [128, 127, 128, 128],
                _ => unreachable!(),
            };
            output.extend(pixel);
        }
    }
    output
}
fn successful_cycle(cycle: &Cycle, operation: &Operation, shape: Shape, scratch: Option<usize>) {
    assert_eq!(cycle.backing.len(), 1);
    let source = cycle.backing[0];
    assert_eq!(source.1, shape.source_bytes());
    assert_eq!(
        cycle.setup,
        [Action::Allocate {
            ordinal: source.0,
            size: source.1,
            success: true
        }]
    );
    assert_eq!(operation.live_at_entry, cycle.backing);
    assert_eq!(
        operation.attempts.len(),
        if scratch.is_some() { 2 } else { 1 }
    );
    assert!(operation.attempts.iter().all(|&(_, _, success)| success));
    let result = operation.attempts[0];
    assert_eq!(result.1, shape.output_bytes());
    let output_owner = (result.0, result.1);
    let mut expected = vec![Action::Allocate {
        ordinal: result.0,
        size: result.1,
        success: true,
    }];
    if let Some(size) = scratch {
        assert!(
            size > 0 && size <= 512 * 32,
            "at most 512 logical Sum values"
        );
        let workspace = operation.attempts[1];
        assert_eq!(workspace.1, size);
        expected.push(Action::Allocate {
            ordinal: workspace.0,
            size,
            success: true,
        });
        expected.push(Action::Release {
            ordinal: workspace.0,
            size,
        });
    }
    assert_eq!(
        operation.actions, expected,
        "result first; bounded scratch retires before publication; no intermediate raster"
    );
    assert_eq!(operation.live_at_return, [source, output_owner]);
    assert_eq!(
        cycle.cleanup_phases,
        [vec![output_owner]],
        "only the independent result survives source destruction"
    );
    assert_eq!(cycle.cleanup_order, [source.0, result.0]);
}

fn publication_ledger_negative_controls() {
    // Host-only controls execute the same complete trace parser. The accepted
    // trace has two distinct addresses above 32 bits and explicit retirement.
    let valid = concat!(
        "execve(\"fixture\", [\"fixture\"], []) = 0\n",
        "write(2, \"A\", 1) = 1\n",
        "mmap(NULL, 172, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x100000000\n",
        "write(2, \"S\", 1) = 1\n",
        "write(2, \"C\", 1) = 1\n",
        "mmap(NULL, 396, PROT_READ|PROT_WRITE, MAP_PRIVATE|MAP_ANONYMOUS, -1, 0) = 0x200000000\n",
        "write(2, \"F\", 1) = 1\n",
        "write(2, \"R\", 1) = 1\n",
        "munmap(0x100000000, 172) = 0\n",
        "write(1, \"abcd\", 4) = 4\n",
        "munmap(0x200000000, 396) = 0\n",
        "write(2, \"E\", 1) = 1\n",
        "write(2, \"D\", 1) = 1\n",
        "exit(0) = ?\n",
    );
    let accepted = effects(valid, b"ASCFRED", false);
    assert_eq!(
        (accepted.allocations, accepted.releases, accepted.output),
        (2, 2, 4)
    );
    let early = valid.replace(
        "write(2, \"R\", 1) = 1\nmunmap(0x100000000, 172) = 0\nwrite(1, \"abcd\", 4) = 4",
        "write(1, \"abcd\", 4) = 4\nwrite(2, \"R\", 1) = 1\nmunmap(0x100000000, 172) = 0",
    );
    let wrong_owner = valid
        .replace("munmap(0x100000000, 172)", "SWAP")
        .replace("munmap(0x200000000, 396)", "munmap(0x100000000, 172)")
        .replace("SWAP", "munmap(0x200000000, 396)");
    for (name, mutated) in [
        ("publication before source retirement", early),
        ("retirement of output instead of source", wrong_owner),
    ] {
        assert_ne!(mutated, valid);
        assert!(
            std::panic::catch_unwind(|| effects(&mutated, b"ASCFRED", false)).is_err(),
            "the ledger must reject {name}"
        );
    }
}

#[test]
fn resize_preserves_borrowed_source_and_recovers_reached_result_and_scratch_failures() {
    publication_ledger_negative_controls();
    let compile_start = Instant::now();
    let executable = executable("owners.lani");
    let compile = compile_start.elapsed();
    let (output, baseline, native) = run(&executable, Some(0), None);
    let expected: Vec<_> = (0..6).flat_map(small_expected).collect();
    assert_eq!(output, expected);
    assert_eq!(baseline.cycles.len(), 6);
    assert_eq!((baseline.allocations, baseline.releases), (13, 13));
    for (case, cycle) in baseline.cycles.iter().enumerate() {
        assert_eq!(cycle.operations.len(), 1);
        assert_eq!(cycle.phases, 3);
        successful_cycle(
            cycle,
            &cycle.operations[0],
            resource_shape(case >= 3),
            if case == 0 { Some(704) } else { None },
        );
    }
    let original = &baseline.cycles[0];
    let successful = &original.operations[0];
    assert_eq!(resource_shape(false).workspace(), 704);
    eprintln!(
        "resize owners baseline-cycles=6 nearest/bilinear/identity-scratch=0 exact-maps=13 exact-releases=13 native-seconds={:.6} compile-seconds={:.6}",
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
    for site in [0, 1] {
        let (ordinal, size, _) = successful.attempts[site];
        let (output, failed, elapsed) = run(&executable, Some(1), Some(ordinal));
        assert_eq!(output, small_expected(0));
        assert_eq!(failed.cycles.len(), 1);
        let cycle = &failed.cycles[0];
        assert_eq!(cycle.setup, original.setup);
        assert_eq!(cycle.backing, original.backing);
        assert_eq!(cycle.operations.len(), 2);
        assert_eq!(cycle.phases, 4);
        let denied = &cycle.operations[0];
        assert_eq!(denied.live_at_entry, cycle.backing);
        assert_eq!(denied.live_at_return, cycle.backing);
        assert_eq!(denied.attempts.len(), site + 1);
        let boundary = successful.actions.iter().position(|action| matches!(action, Action::Allocate { ordinal: current, .. } if *current == ordinal)).unwrap();
        assert_eq!(
            denied.actions[..boundary],
            successful.actions[..boundary],
            "complete normalized prefix before selected reached denial"
        );
        assert_eq!(
            denied.actions[boundary],
            Action::Allocate {
                ordinal,
                size,
                success: false
            }
        );
        let cleanup = if site == 0 {
            vec![]
        } else {
            vec![Action::Release {
                ordinal: successful.attempts[0].0,
                size: resource_shape(false).output_bytes(),
            }]
        };
        assert_eq!(
            denied.actions[boundary + 1..],
            cleanup,
            "failed scratch reservation releases partial output before Err"
        );
        successful_cycle(
            cycle,
            &cycle.operations[1],
            resource_shape(false),
            Some(704),
        );
        assert_eq!((failed.allocations, failed.releases), (3 + site, 3 + site));
        eprintln!(
            "resize reached-denial={ordinal} site={site} source-preserved=true same-process-recovery=true exact-maps={} exact-releases={} native-seconds={:.6}",
            failed.allocations,
            failed.releases,
            elapsed.as_secs_f64()
        );
    }
}

#[test]
fn resize_area_scale_matches_analytic_pixels_with_bounded_workspace_in_both_orientations() {
    let compile_start = Instant::now();
    let executable = executable("scale.lani");
    let compile = compile_start.elapsed();
    let (output, observed, native) = run(&executable, None, None);
    assert_eq!(observed.cycles.len(), SCALE.len());
    assert_eq!((observed.allocations, observed.releases), (15, 15));
    let expected: Vec<_> = (0..SCALE.len()).flat_map(scale_expected).collect();
    assert_eq!(
        output, expected,
        "every RGBA byte in ordinary, both tile orientations and both thin image directions"
    );
    let mut total_source = 0;
    let mut total_output = 0;
    for ((case, shape), cycle) in SCALE.iter().copied().enumerate().zip(&observed.cycles) {
        assert_eq!(cycle.operations.len(), 1);
        assert_eq!(cycle.phases, 3);
        successful_cycle(cycle, &cycle.operations[0], shape, Some(shape.workspace()));
        assert_eq!(shape.workspace(), if case < 3 { 16384 } else { 64 });
        total_source += shape.sw * shape.sh;
        total_output += shape.dw * shape.dh;
        eprintln!(
            "resize scale case={case} source={}x{} output={}x{} scratch-bytes={} full-output-bytes={}",
            shape.sw,
            shape.sh,
            shape.dw,
            shape.dh,
            shape.workspace(),
            shape.output_bytes()
        );
    }
    eprintln!(
        "resize scale source-pixels={total_source} output-pixels={total_output} output-bytes={} exact-maps=15 exact-releases=15 native-seconds={:.6} compile-seconds={:.6}",
        output.len(),
        native.as_secs_f64(),
        compile.as_secs_f64()
    );
}
