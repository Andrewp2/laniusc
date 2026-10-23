#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output, Stdio},
};
fn executable(path: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"));
    let exe = common::TempArtifact::new("laniusc_randomness", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn run(command: &mut Command) -> Output {
    common::short_process_output_with_timeout("randomness", command)
}
fn checked(output: &Output, status: i32) {
    assert_eq!(output.status.code(), Some(status), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
fn numbers(bytes: &[u8]) -> Vec<u64> {
    std::str::from_utf8(bytes)
        .unwrap()
        .split_whitespace()
        .map(|x| x.parse().unwrap())
        .collect()
}

// Parallel state transition instead of the implementation's in-place updates.
// Independently anchored against vectors generated with the authors' C sources.
#[derive(Clone)]
struct Reference([u64; 4]);
impl Reference {
    fn seed(mut seed: u64) -> Self {
        Self(std::array::from_fn(|_| {
            seed = seed.wrapping_add(0x9e3779b97f4a7c15);
            let mut z = seed;
            z = (z ^ (z >> 30)).wrapping_mul(0xbf58476d1ce4e5b9);
            z = (z ^ (z >> 27)).wrapping_mul(0x94d049bb133111eb);
            z ^ (z >> 31)
        }))
    }
    fn next(&mut self) -> u64 {
        let [a, b, c, d] = self.0;
        self.0 = [
            a ^ d ^ b,
            b ^ c ^ a,
            c ^ a ^ (b << 17),
            (d ^ b).rotate_left(45),
        ];
        a.wrapping_add(d).rotate_left(23).wrapping_add(a)
    }
    fn jump(&mut self, long: bool) {
        let polynomial = if long {
            [
                0x76e15d3efefdcbbf_u64,
                0xc5004e441c522fb3,
                0x77710069854ee241,
                0x39109bb02acbe635,
            ]
        } else {
            [
                0x180ec6d33cfd0aba_u64,
                0xd5a61266f0c9392c,
                0xa9582618e03fc9aa,
                0x39abdc4529b1661c,
            ]
        };
        let mut accumulated = [0; 4];
        for word in polynomial {
            for bit in 0..64 {
                if word & (1 << bit) != 0 {
                    for (dest, src) in accumulated.iter_mut().zip(self.0) {
                        *dest ^= src;
                    }
                }
                self.next();
            }
        }
        self.0 = accumulated;
    }
    fn below(&mut self, bound: u64) -> u64 {
        if bound == 1 {
            return 0;
        }
        let threshold = bound.wrapping_neg() % bound;
        loop {
            let value = self.next();
            if value >= threshold {
                return value % bound;
            }
        }
    }
    fn shuffle<T>(&mut self, values: &mut [T]) {
        for end in (1..values.len()).rev() {
            let selected = self.below(end as u64 + 1) as usize;
            values.swap(end, selected);
        }
    }
    fn mixed(&mut self, index: usize) -> u64 {
        match index % 7 {
            0 => self.below(3),
            1 => self.below((1 << 63) + 1),
            2 => (self.below(2001) as i64 - 1000) as u64,
            3 => self.next() >> 40,
            4 => self.next() >> 11,
            5 => self.next() >> 32,
            _ => {
                let bytes = [self.next().to_le_bytes(), self.next().to_le_bytes()].concat();
                bytes[..13].iter().fold(0xcbf29ce484222325_u64, |h, b| {
                    (h ^ u64::from(*b)).wrapping_mul(0x100000001b3)
                })
            }
        }
    }
}

#[test]
fn random_contracts_execute_generics_rejection_and_float_boundaries_without_allocation() {
    let exe = executable("tests/fixtures/stdlib_foundation/random_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_randomness", "portable_trace", None);
    let output = run(Command::new("strace")
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args([
            "-e",
            "trace=mmap,munmap,getrandom",
            "-e",
            "inject=mmap:error=ENOMEM:when=1+",
        ])
        .arg(exe.path()));
    checked(&output, 0);
    assert!(output.stdout.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}

#[test]
fn deterministic_sequences_and_jumps_match_author_vectors_and_state_models() {
    let exe = executable("tests/fixtures/stdlib_foundation/random_sequence.lani");
    for line in include_str!("fixtures/stdlib_foundation/random_vectors.txt").lines() {
        let row = numbers(line.as_bytes());
        assert_eq!(row.len(), 17);
        let seed = row[0];
        let output = run(Command::new(exe.path()).args([seed.to_string(), "5".into(), "0".into()]));
        checked(&output, 0);
        assert_eq!(
            numbers(&output.stdout),
            row[1..],
            "author vectors seed={seed}"
        );
        let mut reference = Reference::seed(seed);
        let mut expected = reference.0.to_vec();
        for _ in 0..4 {
            expected.push(reference.next());
        }
        reference.jump(false);
        for _ in 0..2 {
            expected.push(reference.next());
        }
        reference.jump(true);
        for _ in 0..2 {
            expected.push(reference.next());
        }
        expected.extend(reference.0);
        assert_eq!(expected, row[1..]);
    }
    let mut seeds = vec![0, 1, 42, 1 << 63, u64::MAX];
    let mut state = 0x72616e642026_u64;
    for _ in 0..11 {
        state = state
            .wrapping_mul(6364136223846793005)
            .wrapping_add(1442695040888963407);
        seeds.push(state);
    }
    for seed in seeds {
        for mode in 0..5 {
            let count = if mode == 0 || mode == 4 { 512 } else { 64 };
            let mut reference = Reference::seed(seed);
            if mode == 1 || mode == 3 {
                reference.jump(false);
            }
            if mode == 2 || mode == 3 {
                reference.jump(true);
            }
            if mode == 3 {
                reference.jump(false);
            }
            let mut expected = reference.0.to_vec();
            for i in 0..count {
                expected.push(if mode == 4 {
                    reference.mixed(i)
                } else {
                    reference.next()
                });
            }
            expected.extend(reference.0);
            let output = run(Command::new(exe.path()).args([
                seed.to_string(),
                mode.to_string(),
                count.to_string(),
            ]));
            checked(&output, 0);
            assert_eq!(
                numbers(&output.stdout),
                expected,
                "seed={seed}, mode={mode}"
            );
        }
    }
}

fn header(output: &Output) -> (i32, usize, &[u8]) {
    checked(output, 0);
    let newline = output.stdout.iter().position(|b| *b == b'\n').unwrap();
    let fields: Vec<i32> = std::str::from_utf8(&output.stdout[..newline])
        .unwrap()
        .split_whitespace()
        .map(|x| x.parse().unwrap())
        .collect();
    assert_eq!(fields.len(), 2);
    (fields[0], fields[1] as usize, &output.stdout[newline + 1..])
}
fn returned_entropy(events: &str) -> Vec<u8> {
    let mut bytes = Vec::new();
    for line in events.lines().filter(|line| line.starts_with("getrandom(")) {
        assert!(line.contains(", 0)"), "flags must be zero: {line}");
        if let Some(tail) = line.strip_prefix("getrandom(\"") {
            let encoded = tail.split('"').next().unwrap();
            assert_eq!(encoded.len() % 4, 0, "{line}");
            for chunk in encoded.as_bytes().chunks_exact(4) {
                assert_eq!(&chunk[..2], b"\\x");
                bytes.push(
                    u8::from_str_radix(std::str::from_utf8(&chunk[2..]).unwrap(), 16).unwrap(),
                );
            }
        }
    }
    bytes
}
#[test]
fn os_entropy_preserves_bytes_progress_errors_and_source_sampling() {
    let exe = executable("tests/fixtures/stdlib_host/entropy_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_randomness", "entropy_trace", None);
    let execute = |mode: &str, fault: Option<&str>, error: i32, count: usize| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-xx", "-s", "1024", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=getrandom,mmap,munmap"]);
        if let Some(injection) = fault {
            command
                .arg("-e")
                .arg(format!("inject=getrandom:{injection}"));
        }
        let output = run(command.arg(exe.path()).arg(mode));
        let (actual_error, actual_count, bytes) = header(&output);
        assert_eq!(
            (actual_error, actual_count),
            (error, count),
            "mode={mode}, fault={fault:?}"
        );
        let events = std::fs::read_to_string(trace.path()).unwrap();
        assert!(!events.contains("mmap("), "{events}");
        if mode == "0" || mode == "5" {
            assert_eq!(bytes.len(), count);
        }
        if fault.is_some() && mode != "4" {
            assert!(events.contains("INJECTED"), "{events}");
        }
        (output, events)
    };
    for mode in ["0", "5"] {
        let count = if mode == "0" { 600 } else { 17 };
        let (output, events) = execute(mode, None, 0, count);
        assert_eq!(header(&output).2, returned_entropy(&events));
    }
    for when in 1..=3 {
        let (_, events) = execute(
            "0",
            Some(&format!("error=EIO:when={when}")),
            5,
            (when - 1) * 256,
        );
        assert_eq!(
            events
                .lines()
                .filter(|s| s.starts_with("getrandom("))
                .count(),
            when
        );
    }
    for (fault, code, count) in [
        ("error=EAGAIN:when=1", 11, 0),
        ("error=ENOSYS:when=1", 38, 0),
        ("retval=0:when=1", 1000, 0),
        ("retval=0:when=2", 1000, 256),
        ("retval=257:when=1", 1001, 0),
        ("retval=257:when=2", 1001, 256),
    ] {
        execute("0", Some(fault), code, count);
    }
    for when in [1, 2] {
        let (output, events) = execute("0", Some(&format!("error=EINTR:when={when}")), 0, 600);
        assert_eq!(header(&output).2, returned_entropy(&events));
    }
    let (output, events) = execute("0", Some("retval=2:when=1"), 0, 600);
    assert_eq!(&header(&output).2[..2], &[0, 0]);
    assert_eq!(header(&output).2, returned_entropy(&events));
    for (mode, count) in [("1", 8), ("2", 32), ("3", 8)] {
        execute(mode, None, 0, count);
        execute(mode, Some("error=EIO:when=1"), 5, 0);
    }
    execute("1", Some("retval=8:when=1"), 0, 8);
    execute("1", Some("retval=9:when=1"), 1001, 0);
    execute("2", Some("retval=32:when=1"), 1003, 0);
    let (_, events) = execute("3", Some("retval=8:when=1"), 0, 8);
    assert!(
        events
            .lines()
            .filter(|s| s.starts_with("getrandom("))
            .count()
            >= 2
    );
    let (_, events) = execute("4", Some("error=EIO:when=1+"), 0, 0);
    assert!(
        events.is_empty(),
        "invalid/empty operations must not touch the host: {events}"
    );
}

fn input_lines(bytes: &[u8]) -> Vec<Vec<u8>> {
    if bytes.is_empty() {
        return Vec::new();
    }
    let mut result: Vec<_> = bytes.split(|b| *b == b'\n').map(<[u8]>::to_vec).collect();
    if bytes.ends_with(b"\n") {
        result.pop();
    }
    result
}
fn shuffled(bytes: &[u8], seed: u64, take: usize) -> Vec<u8> {
    let mut rows = input_lines(bytes);
    Reference::seed(seed).shuffle(&mut rows);
    let mut output = Vec::new();
    for row in rows.into_iter().take(take) {
        output.extend(row);
        output.push(b'\n');
    }
    output
}

#[test]
fn large_generation_sampling_and_shuffle_match_state_without_extra_allocations() {
    let exe = executable("tests/fixtures/stdlib_foundation/random_batch.lani");
    let trace = common::TempArtifact::new("laniusc_randomness", "batch_trace", None);
    let seed = 0x123456789abcdef0_u64;
    for mode in 0..3 {
        for count in [0, 1, 4096, 65536, 1048576] {
            let mut reference = Reference::seed(seed);
            let values: Vec<u64> = if mode == 2 {
                let mut values = (0..count).collect::<Vec<_>>();
                reference.shuffle(&mut values);
                values
            } else {
                (0..count)
                    .map(|_| {
                        if mode == 0 {
                            reference.next()
                        } else {
                            reference.below((1 << 63) + 1)
                        }
                    })
                    .collect()
            };
            let hash = values.into_iter().fold(0xcbf29ce484222325_u64, |h, value| {
                (h ^ value).wrapping_mul(0x100000001b3)
            });
            let mut expected = vec![hash];
            expected.extend(reference.0);
            let allocations = usize::from(mode == 2 && count != 0);
            let mut command = Command::new("strace");
            command
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap,getrandom", "-e"])
                .arg(format!(
                    "inject=mmap:error=ENOMEM:when={}+",
                    allocations + 1
                ))
                .arg(exe.path())
                .args([seed.to_string(), mode.to_string(), count.to_string()]);
            let output = common::process_output_with_timeout(
                "random batch",
                &mut command,
                std::time::Duration::from_secs(5),
            );
            checked(&output, 0);
            assert_eq!(
                numbers(&output.stdout),
                expected,
                "mode={mode}, count={count}"
            );
            let events = std::fs::read_to_string(trace.path()).unwrap();
            assert!(
                !events.contains("getrandom(") && !events.contains("INJECTED"),
                "{events}"
            );
            assert_eq!(released(&events), allocations);
        }
    }
}
#[test]
fn shuffle_program_matches_permutations_for_binary_records_and_limits() {
    let exe = executable("sample_programs/shuffle_lines.lani");
    let input = common::TempArtifact::new("laniusc_randomness", "lines", None);
    let invoke = |data: &[u8], args: &[String], status: i32, expected: &[u8]| {
        input.write_bytes(data);
        let output = run(Command::new(exe.path())
            .args(args)
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        checked(&output, status);
        assert_eq!(
            output.stdout,
            expected,
            "args={args:?}, input bytes={}",
            data.len()
        );
    };
    let cases = [
        b"".as_slice(),
        b"one",
        b"one\n",
        b"\n",
        b"\n\n",
        b"a\r\nb\r\n",
        b"\xff\0\na\n\0\n\r",
        "é\n🦅\nz\n".as_bytes(),
    ];
    for data in cases {
        for seed in [0, 1, 42, u64::MAX] {
            for take in [0, 1, 100] {
                let args = vec![
                    "--seed".into(),
                    seed.to_string(),
                    "--count".into(),
                    take.to_string(),
                ];
                invoke(data, &args, 0, &shuffled(data, seed, take));
            }
        }
    }
    let mut state = 0x5a17_2026_u64;
    for case in 0..64 {
        let mut data = Vec::new();
        let rows = (case * 17) % 97;
        for row in 0..rows {
            let length = (case + row * 13) % 65;
            for _ in 0..length {
                state = state.wrapping_mul(6364136223846793005).wrapping_add(1);
                let byte = (state >> 24) as u8;
                data.push(if byte == 10 { 11 } else { byte });
            }
            if row + 1 < rows || case % 2 == 0 {
                data.push(10);
            }
        }
        let seed = state;
        let take = case % (rows + 2);
        invoke(
            &data,
            &["-s".into(), seed.to_string(), "-n".into(), take.to_string()],
            0,
            &shuffled(&data, seed, take),
        );
    }
    invoke(
        b"a\nb\nc",
        &["-s0".into(), "-s42".into(), "-n1".into(), "-n3".into()],
        0,
        &shuffled(b"a\nb\nc", 42, 3),
    );
    for args in [
        vec!["--seed", "-1"],
        vec!["-s18446744073709551616"],
        vec!["-n2147483648"],
        vec!["--max-bytes", "-1"],
        vec!["--max-lines", "bad"],
        vec!["filename"],
        vec!["--unknown"],
        vec!["--help", "-n-1"],
    ] {
        invoke(
            b"",
            &args.into_iter().map(str::to_owned).collect::<Vec<_>>(),
            2,
            b"",
        );
    }
    invoke(
        b"a\nb",
        &["-s0".into(), "--max-bytes=3".into(), "--max-lines=2".into()],
        0,
        &shuffled(b"a\nb", 0, 2),
    );
    for args in [
        vec!["--max-bytes=2"],
        vec!["--max-lines=1"],
        vec!["--max-lines=0"],
        vec!["-n0", "--max-bytes=2"],
    ] {
        invoke(
            b"a\nb",
            &args.into_iter().map(str::to_owned).collect::<Vec<_>>(),
            2,
            b"",
        );
    }
    invoke(
        b"",
        &["--max-bytes=0".into(), "--max-lines=0".into()],
        0,
        b"",
    );
    invoke(&vec![b'x'; 1048577], &["-s0".into()], 2, b"");
    invoke(&vec![b'\n'; 65537], &["-s0".into()], 2, b"");
    invoke(
        b"ignored",
        &["--help".into()],
        0,
        b"Usage: shuffle-lines [-s SEED] [-n COUNT] [--max-bytes N] [--max-lines N]\n",
    );
}
fn released(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut count = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let value = line.rsplit(" = ").next().unwrap();
            if value.starts_with("0x") {
                assert!(
                    live.insert(value.split_whitespace().next().unwrap().to_owned()),
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
    assert!(live.is_empty(), "leaked allocations: {events}");
    count
}
#[test]
fn shuffle_program_uses_entropy_only_when_needed_and_cleans_up_every_failure() {
    let exe = executable("sample_programs/shuffle_lines.lani");
    let input = common::TempArtifact::new("laniusc_randomness", "fault_lines", None);
    let trace = common::TempArtifact::new("laniusc_randomness", "fault_trace", None);
    let data = b"first\nsecond\nthird\nfourth\nfifth\nsixth\nseventh\neighth\n";
    let invoke = |bytes: &[u8],
                  args: &[&str],
                  fault: Option<String>,
                  status: i32,
                  require_injected: bool| {
        input.write_bytes(bytes);
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap,getrandom,read,write"]);
        if let Some(ref fault) = fault {
            command.arg("-e").arg(format!("inject={fault}"));
        }
        let output = run(command
            .arg(exe.path())
            .args(args)
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())));
        checked(&output, status);
        let events = std::fs::read_to_string(trace.path()).unwrap();
        released(&events);
        if require_injected {
            assert!(events.contains("INJECTED"), "{fault:?}: {events}");
        }
        (output, events)
    };
    let (normal, baseline) = invoke(data, &[], None, 0, false);
    let mut expected = input_lines(data);
    let mut actual = input_lines(&normal.stdout);
    expected.sort();
    actual.sort();
    assert_eq!(actual, expected);
    assert_eq!(
        baseline
            .lines()
            .filter(|s| s.starts_with("getrandom("))
            .count(),
        1
    );
    for when in 1..=baseline.lines().filter(|s| s.starts_with("mmap(")).count() {
        let (output, _) = invoke(
            data,
            &[],
            Some(format!("mmap:error=ENOMEM:when={when}+")),
            4,
            true,
        );
        assert!(output.stdout.is_empty());
    }
    for call in ["getrandom", "read", "write"] {
        for when in 1..=baseline
            .lines()
            .filter(|s| s.starts_with(&format!("{call}(")))
            .count()
        {
            let (output, _) = invoke(
                data,
                &[],
                Some(format!("{call}:error=EIO:when={when}")),
                3,
                true,
            );
            if call != "write" {
                assert!(output.stdout.is_empty());
            }
        }
    }
    let (zero, _) = invoke(
        data,
        &[],
        Some("getrandom:retval=32:when=1".into()),
        3,
        true,
    );
    assert!(zero.stdout.is_empty());
    for bytes in [b"".as_slice(), b"one", b"\n"] {
        let (output, events) = invoke(
            bytes,
            &[],
            Some("getrandom:error=EIO:when=1+".into()),
            0,
            false,
        );
        assert_eq!(output.stdout, shuffled(bytes, 0, usize::MAX));
        assert!(!events.contains("getrandom("));
    }
    let (none, events) = invoke(
        data,
        &["-n0"],
        Some("getrandom:error=EIO:when=1+".into()),
        0,
        false,
    );
    assert!(none.stdout.is_empty() && !events.contains("getrandom("));
    let (deterministic, events) = invoke(
        data,
        &["-s42"],
        Some("getrandom:error=EIO:when=1+".into()),
        0,
        false,
    );
    assert_eq!(deterministic.stdout, shuffled(data, 42, usize::MAX));
    assert!(!events.contains("getrandom("));
    for fault in [
        "getrandom:error=EINTR:when=1",
        "read:error=EINTR:when=1",
        "write:error=EINTR:when=1",
    ] {
        let (output, _) = invoke(data, &[], Some(fault.into()), 0, true);
        let mut actual = input_lines(&output.stdout);
        actual.sort();
        assert_eq!(actual, expected);
    }
}
