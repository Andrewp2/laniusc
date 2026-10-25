#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, process::Command, time::Duration};

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
    let exe = common::TempArtifact::new("laniusc_percent", "executable", None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn percent_contracts_execute_native_strides_bounds_atomicity_aliasing_and_sizing_without_allocation()
 {
    let exe = executable("tests/fixtures/extended/percent_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_percent", "trace", None);
    let output = common::short_process_output_with_timeout(
        "percent contracts",
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

fn reference_encode(source: &[u8]) -> Vec<u8> {
    let mut out = Vec::new();
    for &byte in source {
        if byte.is_ascii_alphanumeric() || b"-._~".contains(&byte) {
            out.push(byte);
        } else {
            out.extend_from_slice(format!("%{byte:02X}").as_bytes());
        }
    }
    out
}

fn reference_decode(source: &[u8]) -> Result<Vec<u8>, usize> {
    let mut out = Vec::new();
    let mut index = 0;
    while index < source.len() {
        if source[index] == b'%' {
            let Some(pair) = source.get(index + 1..index + 3) else {
                return Err(index);
            };
            let Some(high) = (pair[0] as char).to_digit(16) else {
                return Err(index);
            };
            let Some(low) = (pair[1] as char).to_digit(16) else {
                return Err(index);
            };
            out.push((high * 16 + low) as u8);
            index += 3;
        } else {
            out.push(source[index]);
            index += 1;
        }
    }
    Ok(out)
}

#[derive(Debug)]
struct Case {
    decode: bool,
    input: Vec<u8>,
    capacity: usize,
    in_place: bool,
}

fn case(cases: &mut Vec<Case>, decode: bool, input: &[u8], capacity: usize, in_place: bool) {
    assert!(input.len() <= 4096 && capacity <= 12288);
    cases.push(Case {
        decode,
        input: input.to_vec(),
        capacity,
        in_place,
    });
}

fn expected(case: &Case) -> (i32, i32, Vec<u8>) {
    let converted = if case.decode {
        reference_decode(&case.input)
    } else {
        Ok(reference_encode(&case.input))
    };
    match converted {
        Err(index) => (4, index as i32, Vec::new()),
        Ok(bytes) if bytes.len() > case.capacity => (3, bytes.len() as i32, Vec::new()),
        Ok(bytes) => (0, 0, bytes),
    }
}

#[test]
fn percent_matches_reference_for_all_bytes_generated_roundtrips_and_every_invalid_hex_byte() {
    let exe = executable("tests/fixtures/extended/percent_model.lani");
    let mut cases = Vec::new();
    let all_bytes: Vec<_> = (0..=255).collect();
    let all_encoded = reference_encode(&all_bytes);
    for in_place in [false, true] {
        case(&mut cases, false, &all_bytes, all_encoded.len(), in_place);
        case(&mut cases, true, &all_encoded, all_bytes.len(), in_place);
        let lower = all_encoded
            .iter()
            .map(u8::to_ascii_lowercase)
            .collect::<Vec<_>>();
        // Lowercasing literal ASCII letters changes those data bytes. The
        // reference checks that behavior as well as accepting lowercase hex.
        case(&mut cases, true, &lower, all_bytes.len(), in_place);
        for input in [
            b"".as_slice(),
            b"AZaz09-._~",
            b"a b+c/d?e#f%g",
            b"\0\xff",
            b"%252F",
            b"+%2B%20",
        ] {
            let encoded = reference_encode(input);
            case(&mut cases, false, input, encoded.len(), in_place);
            case(&mut cases, true, &encoded, input.len(), in_place);
        }
        for input in [
            b"%".as_slice(),
            b"%0",
            b"a%20z%0",
            b"abc%GG",
            b"%20%0g",
            b"%0%",
            b"%%0",
        ] {
            case(&mut cases, true, input, 0, in_place);
        }
    }
    // Every byte, including NUL/high bytes, is checked in each hex position.
    for byte in 0..=255 {
        case(
            &mut cases,
            true,
            &[b'x', b'%', byte, b'0'],
            16,
            byte % 2 == 0,
        );
        case(
            &mut cases,
            true,
            &[b'x', b'%', b'0', byte],
            16,
            byte % 2 != 0,
        );
    }
    let mut seed = 0x980c_31a7_u32;
    let mut next = || {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        seed
    };
    for index in 0..96 {
        let length = (next() % 73) as usize;
        let bytes: Vec<u8> = (0..length)
            .map(|_| {
                let value = (next() >> 16) as u8;
                if index % 3 == 0 {
                    b"aZ9-._~"[(value as usize) % 7]
                } else {
                    value
                }
            })
            .collect();
        let encoded = reference_encode(&bytes);
        for in_place in [false, true] {
            let encode_capacity = if index % 4 == 0 && !encoded.is_empty() {
                encoded.len() - 1
            } else {
                encoded.len() + 1
            };
            let decode_capacity = if index % 4 == 1 && !bytes.is_empty() {
                bytes.len() - 1
            } else {
                bytes.len() + 1
            };
            case(&mut cases, false, &bytes, encode_capacity, in_place);
            case(&mut cases, true, &encoded, decode_capacity, in_place);
        }
    }
    let mut request = Vec::new();
    for case in &cases {
        request.push(u8::from(case.decode));
        request.extend_from_slice(&(case.input.len() as u16).to_le_bytes());
        request.extend_from_slice(&(case.capacity as u16).to_le_bytes());
        request.push(u8::from(case.in_place));
        request.extend_from_slice(&case.input);
    }
    assert!(request.len() < 65536, "batch fixture limit");
    let input = common::TempArtifact::new("laniusc_percent", "input", None);
    input.write_bytes(&request);
    let trace = common::TempArtifact::new("laniusc_percent", "model_trace", None);
    let output = common::process_output_with_timeout(
        "percent reference batch",
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
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    let mut position = 0;
    for (index, case) in cases.iter().enumerate() {
        let (code, detail, expected_bytes) = expected(case);
        let header = output
            .stdout
            .get(position..position + 12)
            .unwrap_or_else(|| panic!("case {index} {case:?}: missing header"));
        let actual_code = i32::from_le_bytes(header[..4].try_into().unwrap());
        let actual_detail = i32::from_le_bytes(header[4..8].try_into().unwrap());
        let actual_length = i32::from_le_bytes(header[8..12].try_into().unwrap());
        assert_eq!(
            (actual_code, actual_detail, actual_length),
            (code, detail, expected_bytes.len() as i32),
            "case {index}: {case:?}"
        );
        position += 12;
        assert_eq!(
            output.stdout.get(position..position + expected_bytes.len()),
            Some(expected_bytes.as_slice()),
            "case {index}: {case:?}"
        );
        position += expected_bytes.len();
    }
    assert_eq!(position, output.stdout.len());
}
