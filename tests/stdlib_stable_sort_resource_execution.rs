//! Stable sorting: nested owner authority, reached scratch OOM, guarded access and scale.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Stdio},
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!(
        "tests/fixtures/stdlib_foundation/stable_sort_resources/{name}.lani"
    ));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout("stable sort resources", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("stable sort {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_stable_sort", name, None);
    executable.write_bytes(bytes);
    fs::set_permissions(executable.path(), fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn result(line: &str) -> &str {
    line.rsplit_once('=').unwrap().1.trim()
}
fn arguments(line: &str) -> &str {
    line.split_once('(').unwrap().1.rsplit_once(')').unwrap().0
}
fn address(value: &str) -> u64 {
    u64::from_str_radix(value.trim().strip_prefix("0x").unwrap(), 16).unwrap()
}

#[derive(Debug, Default)]
struct Sort {
    requested: usize,
    successful: bool,
    released: bool,
    pointer: Option<u64>,
    attempts: usize,
}
#[derive(Debug, Default)]
struct Effects {
    setup: Vec<usize>,
    sorts: Vec<Sort>,
    releases: Vec<usize>,
    phases: usize,
    protections: usize,
}
fn effects(events: &str, stderr: &[u8], configured: bool) -> Effects {
    let mut state = Effects::default();
    let mut live = BTreeMap::<u64, (usize, usize)>::new();
    let mut active: Option<Sort> = None;
    let mut pure = false;
    let mut done = false;
    let mut entries = 0;
    let mut exits = 0;
    let mut reads = 0;
    let mut allocations = 0;
    let mut markers = Vec::new();
    let mut protected = BTreeSet::new();
    for line in events.lines() {
        if line.starts_with("write(2,") {
            assert!(!done && result(line) == "1", "{events}");
            let marker = [b'C', b'F', b'P', b'p', b'D']
                .into_iter()
                .find(|byte| line.contains(&format!("\"{}\", 1)", char::from(*byte))))
                .unwrap_or_else(|| panic!("unexpected marker: {line}"));
            markers.push(marker);
            match marker {
                b'C' => {
                    assert!(!pure && active.is_none(), "{events}");
                    active = Some(Sort::default());
                }
                b'F' => {
                    assert!(!pure, "{events}");
                    let sort = active.take().unwrap();
                    assert_eq!(
                        sort.attempts, 1,
                        "one reservation attempt per nontrivial sort: {events}"
                    );
                    assert_eq!(
                        sort.successful, sort.released,
                        "workspace retired before return: {events}"
                    );
                    state.sorts.push(sort);
                }
                b'P' => {
                    assert!(!pure && active.is_none(), "{events}");
                    pure = true;
                }
                b'p' => {
                    assert!(pure && active.is_none(), "{events}");
                    pure = false;
                    state.phases += 1;
                }
                b'D' => {
                    assert!(!pure && active.is_none() && live.is_empty(), "{events}");
                    done = true;
                }
                _ => unreachable!(),
            }
            continue;
        }
        assert!(
            !pure,
            "pure admission/observation reached a host service: {line}"
        );
        if line.starts_with("exit(0)") || line.starts_with("exit_group(0)") {
            assert!(done, "{events}");
            exits += 1;
            continue;
        }
        assert!(!done, "only process exit follows D: {events}");
        if let Some(sort) = active.as_ref() {
            assert!(
                sort.attempts == 0 || sort.successful && !sort.released,
                "no effect after failed reservation or workspace release before return: {line}"
            );
            assert!(
                line.starts_with("mmap(") || line.starts_with("munmap("),
                "sort/callback host service: {line}"
            );
        }
        if line.starts_with("execve(") {
            assert!(
                active.is_none() && entries == 0 && live.is_empty(),
                "{events}"
            );
            assert_eq!(result(line), "0", "{events}");
            entries += 1;
        } else if line.starts_with("read(0,") {
            assert!(
                configured && active.is_none() && allocations == 0 && reads == 0,
                "{events}"
            );
            assert!(
                arguments(line).ends_with(", 1") && result(line) == "1",
                "{events}"
            );
            reads += 1;
        } else if line.starts_with("mmap(") {
            let fields: Vec<_> = arguments(line).split(',').map(str::trim).collect();
            assert_eq!(fields[0], "NULL", "{events}");
            let size: usize = fields[1].parse().unwrap();
            assert!(size > 0, "{events}");
            let pointer = result(line).split_whitespace().next().unwrap();
            if let Some(sort) = active.as_mut() {
                sort.attempts += 1;
                assert_eq!(sort.attempts, 1, "{events}");
                sort.requested = size;
            }
            if pointer.starts_with("0x") {
                assert!(!line.contains("INJECTED"), "{events}");
                let pointer = address(pointer);
                assert!(
                    live.insert(pointer, (allocations, size)).is_none(),
                    "unique active owner: {events}"
                );
                allocations += 1;
                if let Some(sort) = active.as_mut() {
                    sort.successful = true;
                    sort.pointer = Some(pointer);
                } else {
                    assert!(
                        state.sorts.is_empty(),
                        "setup allocation only before first sort: {events}"
                    );
                    state.setup.push(size);
                }
            } else {
                assert!(
                    active.is_some()
                        && result(line).starts_with("-1 ENOMEM")
                        && line.contains("INJECTED"),
                    "reached scratch ENOMEM only: {events}"
                );
            }
        } else if line.starts_with("munmap(") {
            let (pointer, size) = arguments(line).split_once(',').unwrap();
            let pointer = address(pointer);
            let size: usize = size.trim().parse().unwrap();
            let (identity, extent) = live
                .remove(&pointer)
                .unwrap_or_else(|| panic!("unknown/double release: {events}"));
            assert_eq!(size, extent, "exact owner extent: {events}");
            assert_eq!(result(line), "0", "{events}");
            state.releases.push(identity);
            if let Some(sort) = active.as_mut() {
                assert_eq!(
                    sort.pointer,
                    Some(pointer),
                    "only workspace retires within sort: {events}"
                );
                assert!(!sort.released, "{events}");
                sort.released = true;
            }
        } else if line.starts_with("mprotect(") {
            assert!(active.is_none() && state.sorts.is_empty(), "{events}");
            let fields: Vec<_> = arguments(line).split(',').map(str::trim).collect();
            let base = live.iter().find(|(_, (_, size))| *size == 12288).unwrap().0;
            let protected_address = address(fields[0]);
            assert!(
                protected_address == *base || protected_address == *base + 8192,
                "{events}"
            );
            assert!(
                protected.insert(protected_address),
                "distinct lower/upper guard pages: {events}"
            );
            assert_eq!(&fields[1..], &["4096", "PROT_NONE"], "{events}");
            assert_eq!(result(line), "0", "{events}");
            state.protections += 1;
        } else if line.starts_with("write(1,") {
            assert!(active.is_none(), "observe only completed sorts: {events}");
            let requested: usize = arguments(line)
                .rsplit_once(',')
                .unwrap()
                .1
                .trim()
                .parse()
                .unwrap();
            assert!(
                requested > 0 && requested <= 65536 * 4,
                "bounded exact report: {events}"
            );
            let used: usize = result(line).parse().unwrap();
            assert!(used > 0 && used <= requested, "{events}");
        } else {
            panic!("unexpected host service: {line}");
        }
    }
    assert!(
        done && !pure && active.is_none() && live.is_empty(),
        "{events}"
    );
    assert_eq!(
        (entries, exits, reads),
        (1, 1, usize::from(configured)),
        "{events}"
    );
    assert_eq!(state.releases.len(), allocations, "{events}");
    assert_eq!(stderr, markers, "{events}");
    state
}
fn run(
    executable: &common::TempArtifact,
    mode: Option<u8>,
    failure: Option<usize>,
) -> (Vec<u8>, Effects) {
    let trace = common::TempArtifact::new("laniusc_stable_sort", "trace", None);
    let input = common::TempArtifact::new("laniusc_stable_sort", "configuration", None);
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
    command.arg(executable.path());
    if let Some(mode) = mode {
        input.write_bytes([mode]);
        command.stdin(Stdio::from(fs::File::open(input.path()).unwrap()));
    }
    let output = common::process_output_with_timeout(
        "stable sort finite native lifecycle",
        &mut command,
        Duration::from_secs(75),
    );
    let events = fs::read_to_string(trace.path()).unwrap();
    assert_eq!(
        output.status.code(),
        Some(0),
        "mode={mode:?} fault={failure:?}: {output:?}\n{events}"
    );
    assert_eq!(
        events
            .lines()
            .filter(|line| line.contains("INJECTED"))
            .count(),
        usize::from(failure.is_some()),
        "{events}"
    );
    let effects = effects(&events, &output.stderr, mode.is_some());
    (output.stdout, effects)
}
fn words(bytes: &[u8]) -> [i32; 4] {
    assert_eq!(bytes.len(), 16);
    std::array::from_fn(|index| {
        i32::from_le_bytes(bytes[index * 4..index * 4 + 4].try_into().unwrap())
    })
}
fn check_request(sort: &Sort, header: [i32; 4], success: bool) {
    let [size, length, _, _] = header;
    assert!(size > 0 && length >= 2);
    assert_eq!(sort.requested, size as usize * length as usize);
    assert_eq!(sort.successful, success);
    assert_eq!(sort.released, success);
}
fn owner_observations(output: &[u8], effects: &Effects, mode: u8) {
    let headers: Vec<_> = output.chunks_exact(16).map(words).collect();
    assert_eq!(output.len(), if mode == 0 { 64 } else { 80 });
    let stages = if mode == 0 {
        vec![0, 1, 2, 3]
    } else {
        vec![0, 4, 1, 2, 3]
    };
    assert_eq!(effects.setup.len(), 57);
    assert_eq!(effects.phases, if mode == 0 { 5 } else { 6 });
    assert_eq!(effects.protections, 0);
    let record_size = headers[0][0] as usize;
    assert_eq!(effects.setup[0], 14 * record_size);
    assert_eq!(effects.sorts.len(), stages.len());
    assert_eq!(
        effects.releases.last(),
        Some(&0),
        "outer record owner retires last"
    );
    for (index, (&stage, header)) in stages.iter().zip(headers).enumerate() {
        assert_eq!(header, [record_size as i32, 12, stage, i32::from(mode)]);
        check_request(&effects.sorts[index], header, mode == 0 || index != 0);
    }
    assert_eq!(effects.releases.len(), 61);
}
#[test]
fn stable_sort_preserves_nested_owner_identity_stability_and_exact_workspace_lifecycle() {
    let executable = executable("owners");
    let (output, effects) = run(&executable, Some(0), None);
    owner_observations(&output, &effects, 0);
    eprintln!("stable-sort-owners nested=56 outer=1 scratch=4 successful-maps=61 pure-phases=5");
}
#[test]
fn stable_sort_reached_workspace_failures_and_honest_guarded_ranges() {
    let owners = executable("owners");
    let (output, effects) = run(&owners, Some(1), Some(58));
    owner_observations(&output, &effects, 1);
    let guarded = executable("guards");
    let (output, effects) = run(&guarded, Some(0), None);
    assert_eq!(effects.setup, [12288]);
    assert_eq!(effects.protections, 2);
    assert_eq!(effects.phases, 25);
    assert_eq!(effects.sorts.len(), 24);
    assert_eq!(effects.releases.len(), 25);
    assert_eq!(output.len(), 24 * 16);
    let mut seen = BTreeSet::new();
    for (header, sort) in output.chunks_exact(16).map(words).zip(&effects.sorts) {
        let [size, length, layout, mode] = header;
        assert!([2, 3, 7, 8, 9, 17].contains(&length));
        assert!((0..4).contains(&layout));
        assert_eq!(mode, 0);
        assert!(seen.insert((length, layout)));
        if layout <= 1 {
            assert_eq!(size, 4);
        }
        if layout == 2 {
            assert_eq!(size, 1);
        }
        check_request(sort, header, true);
    }
    let (output, effects) = run(&guarded, Some(1), Some(2));
    assert_eq!(effects.setup, [12288]);
    assert_eq!(effects.protections, 2);
    assert_eq!(effects.phases, 3);
    assert_eq!(effects.sorts.len(), 2);
    assert_eq!(effects.releases.len(), 2);
    assert_eq!(output.len(), 32);
    assert_eq!(words(&output[..16]), [4, 2, 4, 1]);
    assert_eq!(words(&output[16..]), [4, 2, 5, 0]);
    check_request(&effects.sorts[0], words(&output[..16]), false);
    check_request(&effects.sorts[1], words(&output[16..]), true);
    eprintln!(
        "stable-sort-resources reached-ENOMEM=2 guarded-cases=24 lengths=6 layouts=4 protected-pages=2"
    );
}
fn key(index: usize, size: usize, family: usize) -> i32 {
    match family {
        0 => index as i32,
        1 => (size - 1 - index) as i32,
        2 => (index % 8) as i32,
        3 => index.min(size - 1 - index) as i32,
        4 => ((index * 37) % 97) as i32,
        5 => ((index * 40503 + 17) % size) as i32,
        _ => unreachable!(),
    }
}
#[test]
fn stable_sort_large_outputs_match_independent_stable_order_and_logarithmic_work_bound() {
    let executable = executable("scale");
    let (output, effects) = run(&executable, None, None);
    assert_eq!(effects.setup.len(), 2);
    assert_eq!(effects.sorts.len(), 36);
    assert_eq!(effects.phases, 36);
    assert_eq!(effects.releases.len(), 38);
    assert_eq!(effects.protections, 0);
    let mut input = output.as_slice();
    let mut seen = BTreeSet::new();
    let mut maximum = [0.0_f64; 2];
    for sort in &effects.sorts {
        assert!(input.len() >= 32);
        let request = words(&input[..16]);
        let [size, family, mode, calls] = words(&input[16..32]);
        assert_eq!(&request[1..], &[size, family, mode]);
        assert!([257, 4096, 65536].contains(&size));
        assert!((0..6).contains(&family) && (0..2).contains(&mode));
        assert!(seen.insert((size, family, mode)));
        check_request(sort, request, true);
        assert_eq!(effects.setup, [65538 * request[0] as usize, 65538 * 4]);
        let count = size as usize;
        let levels = usize::BITS - (count - 1).leading_zeros();
        let ceiling = count * levels as usize * if mode == 0 { 1 } else { 2 };
        assert!(calls > 0 && calls as usize <= ceiling);
        maximum[mode as usize] =
            maximum[mode as usize].max(calls as f64 / (count * levels as usize) as f64);
        let end = 32 + count * 4;
        assert!(input.len() >= end);
        let actual: Vec<i32> = input[32..end]
            .chunks_exact(4)
            .map(|word| i32::from_le_bytes(word.try_into().unwrap()))
            .collect();
        let mut expected: Vec<_> = (1..=size).collect();
        expected.sort_by_key(|id| key((*id - 1) as usize, count, family as usize));
        assert_eq!(
            actual, expected,
            "complete stable representative sequence size={size} family={family} API={mode}"
        );
        input = &input[end..];
    }
    assert!(input.is_empty());
    assert_eq!(seen.len(), 36);
    eprintln!(
        "stable-sort-scale cases=36 sizes=257,4096,65536 families=6 APIs=2 scratch=36 max-custom-per-nlog={} max-natural-lt-per-nlog={}",
        maximum[0], maximum[1]
    );
}
