#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, process::Command};

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
    let exe = common::TempArtifact::new("laniusc_parse", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn parse_contracts_execute_atomic_locations_limits_and_exact_numbers_without_allocation() {
    let exe = executable("tests/fixtures/extended/parse_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_parse", "trace", None);
    let output = common::short_process_output_with_timeout(
        "parse contracts",
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
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}

#[derive(Debug)]
struct Case {
    source: Vec<u8>,
    max_scan: i32,
    work: u64,
    actions: Vec<(u8, i32)>,
}

// This model uses Rust's UTF-8 decoder and recomputes locations from prefixes.
// It has no cached line state, checkpoints contain only a byte index, and its
// scanners select prefixes using char_indices rather than cursor mutation.
fn location(source: &str, offset: usize) -> [i32; 3] {
    let mut line = 1;
    let mut column = 1;
    let mut previous_cr = false;
    for ch in source[..offset].chars() {
        match ch {
            '\r' => {
                line += 1;
                column = 1;
            }
            '\n' => {
                line += i32::from(!previous_cr);
                column = 1;
            }
            _ => column += 1,
        }
        previous_cr = ch == '\r';
    }
    [offset as i32, line, column]
}

fn is_identifier_start(ch: char) -> bool {
    ch.is_ascii_alphabetic() || ch == '_'
}
fn is_space(ch: char) -> bool {
    matches!(ch, '\t'..='\r' | ' ')
}

fn number_end(source: &str, decimal: bool) -> Result<usize, usize> {
    let bytes = source.as_bytes();
    let mut at = usize::from(matches!(bytes.first(), Some(b'+' | b'-')));
    let digits = |at: &mut usize| {
        let start = *at;
        while bytes.get(*at).is_some_and(u8::is_ascii_digit) {
            *at += 1;
        }
        *at > start
    };
    if !digits(&mut at) {
        return Err(at);
    }
    if decimal && bytes.get(at) == Some(&b'.') {
        at += 1;
        if !digits(&mut at) {
            return Err(at);
        }
    }
    if decimal && matches!(bytes.get(at), Some(b'e' | b'E')) {
        at += 1;
        at += usize::from(matches!(bytes.get(at), Some(b'+' | b'-')));
        if !digits(&mut at) {
            return Err(at);
        }
    }
    Ok(at)
}

fn integer_overflow_offset(token: &str) -> Option<usize> {
    let negative = token.starts_with('-');
    let limit = if negative {
        1u128 << 63
    } else {
        (1u128 << 63) - 1
    };
    let mut value = 0u128;
    for (index, byte) in token.bytes().enumerate() {
        if matches!(byte, b'+' | b'-') {
            continue;
        }
        value = value * 10 + u128::from(byte - b'0');
        if value > limit {
            return Some(index);
        }
    }
    None
}

fn reference(case: &Case) -> Vec<[i32; 12]> {
    if case.max_scan < 0 {
        assert!(case.actions.is_empty());
        return vec![[1, 0, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0]];
    }
    let source = match std::str::from_utf8(&case.source) {
        Ok(source) => source,
        Err(error) => {
            assert!(case.actions.is_empty());
            let prefix = std::str::from_utf8(&case.source[..error.valid_up_to()]).unwrap();
            let at = location(prefix, prefix.len());
            return vec![[2, at[0], at[1], at[2], 0, 0, 0, 0, 0, 0, 0, 0]];
        }
    };
    if case.work < source.len() as u64 {
        assert!(case.actions.is_empty());
        let mut spent = 0u64;
        let failed = source
            .char_indices()
            .find_map(|(index, ch)| {
                spent += ch.len_utf8() as u64;
                (spent > case.work).then_some(index)
            })
            .unwrap();
        let at = location(source, failed);
        return vec![[8, at[0], at[1], at[2], 0, 0, 0, 0, 0, 0, 0, 0]];
    }
    let mut work_left = case.work - source.len() as u64;
    let maximum = case.max_scan as usize;
    let mut position = 0;
    let mut checkpoint = 0;
    let mut results = Vec::new();
    for &(mode, argument) in &case.actions {
        let start = position;
        let tail = &source[start..];
        let mut failure = None;
        let mut end = start;
        let mut value = 0i64;
        let mut span = false;
        match mode {
            0 | 1 => {
                value = tail.chars().next().map_or(u32::MAX, |ch| ch as u32) as i64;
                if mode == 0 {
                    if let Some(ch) = tail.chars().next() {
                        if ch.len_utf8() > maximum {
                            failure = Some((7, start));
                        } else {
                            end += ch.len_utf8();
                        }
                    }
                }
            }
            2 => {
                let expected = argument as u8;
                if expected > 127 {
                    failure = Some((1, start));
                } else if let Some(ch) = tail.chars().next() {
                    if ch.len_utf8() > maximum {
                        failure = Some((7, start));
                    } else if ch as u32 != u32::from(expected) {
                        failure = Some((4, start));
                    } else {
                        end += 1;
                        span = true;
                    }
                } else {
                    failure = Some((3, start));
                }
            }
            3..=5 | 12 => {
                if mode == 12 && char::from_u32(argument as u32).is_none() {
                    failure = Some((1, start));
                } else {
                    let accepted = tail
                        .char_indices()
                        .take_while(|&(index, ch)| match mode {
                            3 => is_space(ch),
                            4 if index == 0 => is_identifier_start(ch),
                            4 => is_identifier_start(ch) || ch.is_ascii_digit(),
                            5 => ch.is_ascii_digit(),
                            12 => ch as u32 != argument as u32,
                            _ => unreachable!(),
                        })
                        .map(|(index, ch)| index + ch.len_utf8())
                        .last()
                        .unwrap_or(0);
                    end += accepted;
                    if accepted > maximum {
                        let boundary = tail
                            .char_indices()
                            .map(|(index, _)| index)
                            .find(|&index| {
                                tail[index..].chars().next().unwrap().len_utf8()
                                    > maximum.saturating_sub(index)
                            })
                            .unwrap();
                        failure = Some((7, start + boundary));
                    } else if accepted == 0 && matches!(mode, 4 | 5) {
                        failure = Some((if tail.is_empty() { 3 } else { 4 }, start));
                    } else {
                        span = true;
                    }
                }
            }
            6..=8 => {
                let scanned = number_end(tail, mode == 7);
                let extent = match scanned {
                    Ok(end) | Err(end) => end,
                };
                if extent > maximum {
                    failure = Some((7, start + maximum));
                } else {
                    match scanned {
                        Err(at) => failure = Some((5, start + at)),
                        Ok(length) if mode == 8 => {
                            let token = &tail[..length];
                            if let Some(offset) = integer_overflow_offset(token) {
                                failure = Some((6, start + offset));
                            } else {
                                value = token.parse().unwrap();
                                end += length;
                            }
                        }
                        Ok(length) => {
                            end += length;
                            span = true;
                        }
                    }
                }
            }
            9 => {
                checkpoint = start;
                value = checkpoint as i64;
            }
            10 => {
                end = checkpoint;
                value = checkpoint as i64;
            }
            11 => {
                if argument < 0 {
                    failure = Some((1, start));
                } else {
                    let wanted = argument as usize;
                    for (index, ch) in tail.char_indices() {
                        if index >= wanted {
                            break;
                        }
                        if index + ch.len_utf8() > maximum {
                            failure = Some((7, start + index));
                            break;
                        }
                        if index + ch.len_utf8() > wanted {
                            failure = Some((1, start + index));
                            break;
                        }
                        end = start + index + ch.len_utf8();
                    }
                    if failure.is_none() && wanted > tail.len() {
                        failure = Some((3, source.len()));
                    }
                    if failure.is_none() {
                        end = start + wanted;
                        span = true;
                    }
                }
            }
            13 => {
                let tag = if argument == 1 { "" } else { "ab\r\nλ" };
                for expected in tag.chars() {
                    let index = end - start;
                    let Some(actual) = source[end..].chars().next() else {
                        failure = Some((3, end));
                        break;
                    };
                    if index + actual.len_utf8() > maximum {
                        failure = Some((7, end));
                        break;
                    }
                    if actual != expected {
                        failure = Some((4, end));
                        break;
                    }
                    end += actual.len_utf8();
                }
                if failure.is_none() {
                    span = true;
                }
            }
            14 => failure = Some((9, start)),
            _ => unreachable!(),
        }
        // Calculate inspected source prefixes independently of cached state.
        // A terminating lookahead costs work even though it is left untouched.
        let mut costs = Vec::new();
        let through = match mode {
            0 | 1 => Some(start),
            2 if argument as u8 <= 127 => Some(start),
            3..=5 | 12 if !matches!(failure, Some((1, _))) => {
                Some(failure.map_or(end, |(_, at)| at))
            }
            6..=8 => Some(match number_end(tail, mode == 7) {
                Ok(length) | Err(length) => start + length.min(maximum),
            }),
            11 if argument >= 0 => {
                if let Some((_, at)) = failure {
                    Some(at)
                } else if end > start {
                    Some(end - 1)
                } else {
                    None
                }
            }
            _ => None,
        };
        if let Some(through) = through {
            costs.extend(
                source[start..]
                    .char_indices()
                    .take_while(|(index, _)| start + index <= through)
                    .map(|(index, ch)| (start + index, ch.len_utf8() as u64)),
            );
        }
        if mode == 13 {
            let tag = if argument == 1 { "" } else { "ab\r\nλ" };
            let mut at = start;
            let mut tag_index = 0;
            while tag_index < tag.len() {
                let Some(actual) = source[at..].chars().next() else {
                    break;
                };
                costs.push((at, actual.len_utf8() as u64));
                if at - start + actual.len_utf8() > maximum
                    || actual.len_utf8() > tag.len() - tag_index
                {
                    break;
                }
                let encoded = actual.to_string();
                let mut differs = false;
                for &byte in encoded.as_bytes() {
                    costs.push((at, 1));
                    if byte != tag.as_bytes()[tag_index] {
                        differs = true;
                        break;
                    }
                    tag_index += 1;
                }
                if differs {
                    break;
                }
                at += actual.len_utf8();
            }
        }
        if mode == 8 && !matches!(failure, Some((5 | 7, _))) {
            costs.push((start, number_end(tail, false).unwrap() as u64));
        }
        for (at, cost) in costs {
            if cost > work_left {
                work_left = 0;
                failure = Some((8, at));
                break;
            }
            work_left -= cost;
        }
        let mut record = [0; 12];
        record[9] = -1;
        record[10] = -1;
        if let Some((code, at)) = failure {
            record[0] = code;
            record[1..4].copy_from_slice(&location(source, at));
            value = 0;
        } else {
            position = end;
            if span {
                value = (end - start) as i64;
                record[9] = start as i32;
                record[10] = end as i32;
                record[11] = source.as_bytes()[start..end]
                    .iter()
                    .fold(0u32, |hash, byte| {
                        hash.wrapping_mul(31).wrapping_add(u32::from(*byte))
                    }) as i32;
            }
        }
        record[4..7].copy_from_slice(&location(source, position));
        record[7] = value as i32;
        record[8] = (value >> 32) as i32;
        results.push(record);
    }
    results
}

#[test]
fn parse_operation_sequences_match_independent_utf8_prefix_model_without_allocation() {
    let exe = executable("tests/fixtures/extended/parse_model.lani");
    let mut cases = Vec::new();
    for source in [
        "",
        "abc_123!",
        " \t\n\r\n\u{b}\u{c}x",
        "ab\r\nλ\0🙂z",
        "αβ a\u{a0}b",
        "\r\r\n\n\rZ",
        "+001.25e-2!",
        "1e+!",
        "-9223372036854775808",
        "+9223372036854775808",
        "9999999999999999999999999999999999999999",
        ".3",
        "000",
        "\0a\0",
    ] {
        for max_scan in [0, 1, 3, 8, 1024] {
            let mut actions = vec![(9, 0)];
            for action in [
                (0, 0),
                (1, 0),
                (2, b'a' as i32),
                (2, 200),
                (3, 0),
                (4, 0),
                (5, 0),
                (6, 0),
                (7, 0),
                (8, 0),
                (11, -1),
                (11, 0),
                (11, 1),
                (11, 4),
                (11, 999),
                (12, 0),
                (12, 'λ' as i32),
                (12, -1),
                (13, 0),
                (13, 1),
                (14, 0),
            ] {
                actions.push(action);
                actions.push((10, 0));
            }
            // Traverse every scalar, placing checkpoints on both sides of CRLF
            // and multibyte scalars, then mix failed and successful operations.
            for (index, ch) in source.chars().enumerate() {
                if index % 2 == 0 {
                    actions.push((9, 0));
                }
                actions.extend([(1, 0), (2, b'?' as i32), (0, 0), (10, 0), (0, 0)]);
                if ch == '\r' {
                    actions.extend([(9, 0), (0, 0), (10, 0)]);
                }
            }
            actions.extend([(0, 0), (1, 0), (3, 0), (4, 0), (8, 0)]);
            cases.push(Case {
                source: source.as_bytes().to_vec(),
                max_scan,
                work: 1_000_000,
                actions,
            });
        }
    }
    // Generated strings deliberately bias toward token boundaries, Unicode,
    // CRLF splits, embedded NUL, sign/exponent errors and checkpoint rewinds.
    let mut seed = 0x8765_4321u32;
    let mut next = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    let alphabet = [
        'a', 'Z', '_', '1', '9', ' ', '\r', '\n', '\0', 'λ', '🙂', '\u{a0}', '+', '-', '.', 'e',
        '!',
    ];
    for index in 0..48 {
        let source: String = (0..(next() % 33))
            .map(|_| alphabet[next() as usize % alphabet.len()])
            .collect();
        let mut actions = Vec::new();
        for _ in 0..64 {
            let mode = (next() % 15) as u8;
            let argument = match mode {
                2 => [0, 10, 13, 32, 97, 200][next() as usize % 6],
                11 => (next() % 9) as i32 - 1,
                12 => [0, 10, 955, 33][next() as usize % 4],
                13 => (next() % 2) as i32,
                _ => 0,
            };
            actions.push((mode, argument));
        }
        cases.push(Case {
            source: source.into_bytes(),
            max_scan: [1, 3, 16, 1024][index % 4],
            work: 1_000_000,
            actions,
        });
    }
    for bytes in [
        vec![0x80],
        vec![0xc0, 0x80],
        vec![b'a', 13, 10, 0xe2, 0x82],
        vec![b'a', 0, 0xed, 0xa0, 0x80],
        vec![0xf4, 0x90, 0x80, 0x80],
        vec![0xe2, b'x', 0x80],
    ] {
        cases.push(Case {
            source: bytes,
            max_scan: 1024,
            work: 1_000_000,
            actions: Vec::new(),
        });
    }
    cases.push(Case {
        source: b"abc".to_vec(),
        max_scan: -1,
        work: 1_000_000,
        actions: Vec::new(),
    });
    for source in [
        "",
        "abc!",
        "λ\r\n🙂ab",
        "+123456789!",
        "ab\r\nλ",
        "9223372036854775808",
    ] {
        for extra in 0..24 {
            cases.push(Case {
                source: source.as_bytes().to_vec(),
                max_scan: 1024,
                work: source.len() as u64 + extra,
                actions: vec![
                    (9, 0),
                    (4, 0),
                    (10, 0),
                    (1, 0),
                    (0, 0),
                    (13, 0),
                    (10, 0),
                    (8, 0),
                    (10, 0),
                    (12, 0),
                    (10, 0),
                    (7, 0),
                    (10, 0),
                    (11, 2),
                    (0, 0),
                ],
            });
        }
    }
    for work in 0..7 {
        cases.push(Case {
            source: "λ🙂".as_bytes().to_vec(),
            max_scan: 1024,
            work,
            actions: Vec::new(),
        });
    }
    let mut request = Vec::new();
    for case in &cases {
        for header in [
            case.source.len() as i32,
            case.max_scan,
            case.work as i32,
            case.actions.len() as i32,
        ] {
            request.extend_from_slice(&header.to_le_bytes());
        }
        request.extend_from_slice(&case.source);
        for &(mode, argument) in &case.actions {
            request.push(mode);
            request.extend_from_slice(&argument.to_le_bytes());
        }
    }
    assert!(request.len() < 131072);
    let input = common::TempArtifact::new("laniusc_parse", "input", None);
    input.write_bytes(&request);
    let trace = common::TempArtifact::new("laniusc_parse", "model_trace", None);
    let output = common::process_output_with_timeout(
        "parse model batch",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path())
            .stdin(std::fs::File::open(input.path()).unwrap()),
        std::time::Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    let mut bytes = output.stdout.chunks_exact(48);
    let mut commands = 0;
    for (case_index, case) in cases.iter().enumerate() {
        for (action, expected) in reference(case).iter().enumerate() {
            let record = bytes
                .next()
                .unwrap_or_else(|| panic!("missing case {case_index} action {action}"));
            let actual: Vec<i32> = record
                .chunks_exact(4)
                .map(|word| i32::from_le_bytes(word.try_into().unwrap()))
                .collect();
            assert_eq!(
                actual,
                expected,
                "case {case_index} action {action} {:?}: {case:?}",
                case.actions.get(action)
            );
            commands += 1;
        }
    }
    assert!(bytes.next().is_none() && bytes.remainder().is_empty());
    assert!(commands > 8000);
}
