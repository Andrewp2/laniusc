//! Independent formatted-byte, chunk, retry and nested-buffer execution models.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
    time::{Duration, Instant},
};
fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/format_write")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("format write {name}: {error}"));
    assert!(common::x86_jumps::is_x86_64_executable(&bytes));
    let executable = common::TempArtifact::new("laniusc_format_write", name, None);
    executable.write_bytes(bytes);
    std::fs::set_permissions(executable.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    executable
}
fn invoke(name: &str, input: Option<&[u8]>) -> (Output, String) {
    let executable = executable(name);
    let trace = common::TempArtifact::new("laniusc_format_write", "trace", None);
    let input_file = common::TempArtifact::new("laniusc_format_write", "input", None);
    let mut command = Command::new("strace");
    command
        .args(["-qq", "-o"])
        .arg(trace.path())
        .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
        .arg(executable.path());
    if let Some(bytes) = input {
        input_file.write_bytes(bytes);
        command.stdin(std::fs::File::open(input_file.path()).unwrap());
    }
    let output = common::process_output_with_timeout(name, &mut command, Duration::from_secs(20));
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    (output, std::fs::read_to_string(trace.path()).unwrap())
}
fn words(bytes: &[u8]) -> Vec<u64> {
    assert_eq!(bytes.len() % 8, 0);
    bytes
        .chunks_exact(8)
        .map(|bytes| u64::from_le_bytes(bytes.try_into().unwrap()))
        .collect()
}
fn scientific(value: String) -> String {
    let (mantissa, exponent) = value.split_once('e').unwrap();
    let exponent: i32 = exponent.parse().unwrap();
    format!("{mantissa}e{exponent:+03}")
}
fn formatted(case: u64) -> Vec<u8> {
    let result = match case {
        0 => String::new(),
        1 => i64::MIN.to_string(),
        2 => i64::MAX.to_string(),
        3 => u64::MAX.to_string(),
        4 => format!("{:+023}", 0),
        5 => format!("{:+023}", i64::MIN),
        6 => format!("{:#018x}", u64::MAX),
        // Lanius specifies 0X for alternate uppercase hex; Rust uses 0x.
        7 => format!("{:#018X}", u64::MAX).replacen("0x", "0X", 1),
        8 => format!("{:#070b}", u64::MAX),
        9 => format!("{:#024o}", u64::MAX),
        10 => format!("{}e\u{301}é{}", "🙂".repeat(3), "🙂".repeat(3)),
        11..=13 => format!(
            "{}{}",
            ['\0', 'é', '🙂'][(case - 11) as usize],
            "🌍".repeat(3)
        ),
        14 => format!("🙂🙂true{}", "🙂".repeat(3)),
        15 => format!("🙂🙂fals{}", "🙂".repeat(3)),
        16 => "{value}|{0}|{value}|{0}".to_owned(),
        17 => format!("{}é", " ".repeat(256)),
        18 => format!("{:+014.2}", f64::from_bits(4_613_205_983_301_625_446)),
        19 => format!("{:+014.2}", -0.0_f64),
        20 => format!("{:+014.2}", f64::MAX),
        21 => format!("{:+014.2}", f32::from_bits(1_036_831_949)),
        22 => scientific(format!("{:.3e}", f64::from_bits(1))),
        23 => scientific(format!("{:.3e}", f64::MAX)),
        24 => scientific(format!("{:.3e}", f32::MAX)),
        25 => "1.2346e+05".to_owned(),
        26 => "1e-05".to_owned(),
        27 => "5e-324".to_owned(),
        28 => "0.1".to_owned(),
        29 => "+NAN".to_owned(),
        30 => "+INF".to_owned(),
        31 => "-INF".to_owned(),
        32 => "{-1}:-1:-1".to_owned(),
        33 => "A\0é🙂".to_owned(),
        34 => "1.0000000000000002".to_owned(),
        35 => char::from_u32(0x10ffff).unwrap().to_string(),
        _ => unreachable!(),
    };
    result.into_bytes()
}
fn reference(command: [u64; 5]) -> Vec<u64> {
    let [case, capacity, _packed, script, budget] = command;
    let bytes = formatted(case);
    let capacity = capacity as usize;
    let mut output = Vec::new();
    let mut completed = 0;
    let mut calls = 0;
    let mut limited = false;
    'chunks: for chunk in bytes.chunks(capacity) {
        let mut sent = 0;
        while sent < chunk.len() {
            if calls == budget {
                limited = true;
                break 'chunks;
            }
            let interrupted = script == 3 && calls % 2 == 0;
            let offered = chunk.len() - sent;
            let accepted = if interrupted {
                0
            } else {
                offered.min(match script {
                    0 => offered,
                    1 => 1,
                    2 => [1, 3, 2][calls as usize % 3],
                    3 => 2,
                    _ => unreachable!(),
                })
            };
            output.extend([
                1,
                (3 + sent) as u64,
                offered as u64,
                u64::from(interrupted),
                accepted as u64,
            ]);
            output.extend(chunk[sent..].iter().map(|&byte| byte as u64));
            calls += 1;
            sent += accepted;
            completed += accepted;
        }
    }
    output.extend([
        0,
        u64::from(limited),
        completed as u64,
        calls,
        0,
        completed as u64,
    ]);
    output.extend(bytes[..completed].iter().map(|&byte| byte as u64));
    output
}

#[test]
fn plain_slice_writer_consumer_executes_without_caller_error_projection() {
    let (output, trace) = invoke("plain.lani", None);
    assert!(output.stdout.is_empty(), "{output:?}");
    assert!(
        trace.is_empty(),
        "plain core formatting allocates nothing: {trace}"
    );
}

#[test]
fn streaming_bytes_offsets_retries_and_prefixes_match_independent_models_without_allocation() {
    let mut commands = Vec::new();
    for case in 0..36 {
        for capacity in [1, 2, 7, 64] {
            for packed in 0..2 {
                for script in [0, 1] {
                    commands.push([case, capacity, packed, script, u64::MAX]);
                }
            }
        }
    }
    for case in [0, 8, 10, 17, 18, 33] {
        for capacity in [1, 2, 7, 64] {
            for packed in 0..2 {
                for script in [2, 3] {
                    commands.push([case, capacity, packed, script, u64::MAX]);
                }
                for script in [0, 3] {
                    for budget in [0, 1, 3] {
                        commands.push([case, capacity, packed, script, budget]);
                    }
                }
            }
        }
    }
    let input: Vec<_> = commands
        .iter()
        .flatten()
        .copied()
        .flat_map(u64::to_le_bytes)
        .collect();
    let (output, trace) = invoke("model.lani", Some(&input));
    assert!(
        trace.is_empty(),
        "core streaming formatting must allocate nothing: {trace}"
    );
    let actual = words(&output.stdout);
    let mut start = 0;
    for &command in &commands {
        let expected = reference(command);
        let end = start + expected.len();
        assert_eq!(
            actual.get(start..end),
            Some(expected.as_slice()),
            "streaming format command {command:?}"
        );
        start = end;
    }
    assert_eq!(start, actual.len(), "no trailing writer events");
    eprintln!(
        "{} independent format/write commands in one native process",
        commands.len()
    );
}
fn read_view(words: &[u64], at: &mut usize) -> Vec<u8> {
    let count = words[*at] as usize;
    *at += 1;
    let result = words[*at..*at + count]
        .iter()
        .map(|&byte| u8::try_from(byte).unwrap())
        .collect();
    *at += count;
    result
}
#[test]
fn nested_buffered_writers_preserve_pending_partitions_and_only_explicitly_flush() {
    let (output, trace) = invoke("nested.lani", None);
    let words = words(&output.stdout);
    let expected = format!("{}é🙂漢{}", "🙂".repeat(4), "🙂".repeat(5)).into_bytes();
    let mut at = 0;
    for _layout in 0..2 {
        assert_eq!(words[at], expected.len() as u64);
        assert_eq!(words[at + 1], 0, "format does not flush");
        at += 2;
        let mut partition = read_view(&words, &mut at);
        let inner = read_view(&words, &mut at);
        let outer = read_view(&words, &mut at);
        assert!(!outer.is_empty(), "last outer bytes remain buffered");
        partition.extend(inner);
        partition.extend(outer);
        assert_eq!(partition, expected);
        assert_eq!(
            &words[at..at + 2],
            &[1, 2],
            "only explicit nested finishes flush leaf"
        );
        at += 2;
        assert_eq!(read_view(&words, &mut at), expected);
    }
    assert_eq!(at, words.len());
    let mut live = BTreeMap::new();
    let mut allocated = 0;
    let mut events = Vec::new();
    for line in trace.lines() {
        if let Some(arguments) = line.strip_prefix("mmap(") {
            let length: usize = arguments.split(',').nth(1).unwrap().trim().parse().unwrap();
            let address = line.rsplit_once(" = ").unwrap().1.trim();
            assert!(address.starts_with("0x"));
            allocated += 1;
            assert!(live.insert(address, (length, allocated)).is_none());
            events.push((true, allocated));
        } else if let Some(arguments) = line.strip_prefix("munmap(") {
            let (arguments, result) = arguments.split_once(')').unwrap();
            let (address, length) = arguments.split_once(',').unwrap();
            assert_eq!(result.trim(), "= 0");
            let (expected_length, id) = live.remove(address.trim()).unwrap();
            assert_eq!(expected_length, length.trim().parse::<usize>().unwrap());
            events.push((false, id));
        } else {
            panic!("unexpected nested allocation event: {trace}");
        }
    }
    assert!(live.is_empty());
    assert_eq!(
        events,
        [
            (true, 1),
            (true, 2),
            (false, 2),
            (false, 1),
            (true, 3),
            (true, 4),
            (false, 4),
            (false, 3)
        ],
        "only two owned adapter buffers per layout: {trace}"
    );
}

#[test]
fn single_mib_field_streams_in_constant_space_with_exact_hash_and_call_count() {
    // Hash the independent expected byte sequence without storing the output.
    let expected = std::iter::once(b'x')
        .chain(std::iter::repeat_n(b' ', 1_048_575))
        .fold(14_695_981_039_346_656_037_u64, |hash, byte| {
            (hash ^ u64::from(byte)).wrapping_mul(1_099_511_628_211)
        })
        .to_string();
    let executable = executable("scale.lani");
    let trace = common::TempArtifact::new("laniusc_format_write", "scale_trace", None);
    for run in 0..3 {
        let mut command = if run == 0 {
            let mut command = Command::new("strace");
            command
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,mremap,munmap,brk", "-e", "signal=none"])
                .arg(executable.path());
            command
        } else {
            Command::new(executable.path())
        };
        command.arg(&expected);
        let start = Instant::now();
        let output = common::process_output_with_timeout(
            "1 MiB streaming format scale",
            &mut command,
            Duration::from_secs(20),
        );
        let elapsed = start.elapsed();
        assert_eq!(output.status.code(), Some(0), "run {run}: {output:?}");
        assert!(
            output.stdout.is_empty() && output.stderr.is_empty(),
            "run {run}: {output:?}"
        );
        if run == 0 {
            let events = std::fs::read_to_string(trace.path()).unwrap();
            assert!(
                events.is_empty(),
                "1 MiB formatting must allocate nothing: {events}"
            );
        }
        eprintln!(
            "1 MiB streaming format run {}: {:.3} ms wall; process startup and FNV-1a hashing included{}; not isolated formatter throughput",
            run + 1,
            elapsed.as_secs_f64() * 1_000.0,
            if run == 0 { ", strace included" } else { "" }
        );
    }
}
