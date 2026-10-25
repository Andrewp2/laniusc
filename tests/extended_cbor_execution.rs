#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::Command,
    sync::OnceLock,
    time::{Duration, Instant},
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
    .unwrap_or_else(|e| panic!("{path}: {e}"));
    let exe = common::TempArtifact::new("laniusc_cbor", "executable", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn model() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("tests/fixtures/extended/cbor_model.lani"))
}
#[derive(Debug)]
struct Record {
    code: i32,
    offset: i32,
    digest: u32,
    bytes: Vec<u8>,
}
fn invoke(cases: &[Vec<u8>]) -> Vec<Record> {
    let input = common::TempArtifact::new("laniusc_cbor", "input", None);
    let mut packet = Vec::new();
    for case in cases {
        assert!(case.len() <= 262144);
        packet.extend_from_slice(&(case.len() as u32).to_le_bytes());
        packet.extend_from_slice(case);
    }
    input.write_bytes(packet);
    let result = common::process_output_with_timeout(
        "CBOR model",
        Command::new(model().path()).stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(20),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(result.stderr.is_empty(), "{result:?}");
    let mut source = result.stdout.as_slice();
    let mut records = Vec::new();
    while !source.is_empty() {
        assert!(source.len() >= 16);
        let code = i32::from_le_bytes(source[..4].try_into().unwrap());
        let offset = i32::from_le_bytes(source[4..8].try_into().unwrap());
        let size = u32::from_le_bytes(source[8..12].try_into().unwrap()) as usize;
        let digest = u32::from_le_bytes(source[12..16].try_into().unwrap());
        assert!(size <= source.len() - 16);
        records.push(Record {
            code,
            offset,
            digest,
            bytes: source[16..16 + size].to_vec(),
        });
        source = &source[16 + size..];
    }
    assert_eq!(records.len(), cases.len());
    records
}
fn hex(text: &str) -> Vec<u8> {
    let bytes: Vec<_> = text.bytes().filter(|b| !b.is_ascii_whitespace()).collect();
    assert_eq!(bytes.len() % 2, 0);
    bytes
        .chunks_exact(2)
        .map(|pair| u8::from_str_radix(std::str::from_utf8(pair).unwrap(), 16).unwrap())
        .collect()
}
#[test]
fn pure_contracts_execute_native_strides_selected_windows_guards_limits_and_no_allocation() {
    let exe = executable("tests/fixtures/extended/cbor_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_cbor", "trace", None);
    let result = common::process_output_with_timeout(
        "CBOR contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap,brk,open,openat,socket,connect",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path()),
        Duration::from_secs(5),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(
        result.stdout.is_empty() && result.stderr.is_empty(),
        "{result:?}"
    );
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}
#[test]
fn invalid_encoder_structure_utf8_limits_and_metadata_preserve_all_output() {
    let exe = executable("tests/fixtures/extended/cbor_failures.lani");
    let result = common::process_output_with_timeout(
        "CBOR encoder failures",
        &mut Command::new(exe.path()),
        Duration::from_secs(5),
    );
    assert_eq!(result.status.code(), Some(0), "{result:?}");
    assert!(
        result.stdout.is_empty() && result.stderr.is_empty(),
        "{result:?}"
    );
}
#[test]
fn rfc8949_appendix_a_and_nonpreferred_argument_heads_round_trip_exactly() {
    let vectors = [
        "00",
        "01",
        "0a",
        "17",
        "1818",
        "1819",
        "1864",
        "1903e8",
        "1a000f4240",
        "1b000000e8d4a51000",
        "1bffffffffffffffff",
        "c249010000000000000000",
        "3bffffffffffffffff",
        "c349010000000000000000",
        "20",
        "29",
        "3863",
        "3903e7",
        "f90000",
        "f98000",
        "f93c00",
        "fb3ff199999999999a",
        "f93e00",
        "f97bff",
        "fa47c35000",
        "fa7f7fffff",
        "fb7e37e43c8800759c",
        "f90001",
        "f90400",
        "f9c400",
        "fbc010666666666666",
        "f97c00",
        "f97e00",
        "f9fc00",
        "fa7f800000",
        "fa7fc00000",
        "faff800000",
        "fb7ff0000000000000",
        "fb7ff8000000000000",
        "fbfff0000000000000",
        "f4",
        "f5",
        "f6",
        "f7",
        "f0",
        "f8ff",
        "c074323031332d30332d32315432303a30343a30305a",
        "c11a514b67b0",
        "c1fb41d452d9ec200000",
        "d74401020304",
        "d818456449455446",
        "d82076687474703a2f2f7777772e6578616d706c652e636f6d",
        "40",
        "4401020304",
        "60",
        "6161",
        "6449455446",
        "62225c",
        "62c3bc",
        "63e6b0b4",
        "64f0908591",
        "80",
        "83010203",
        "8301820203820405",
        "98190102030405060708090a0b0c0d0e0f101112131415161718181819",
        "a0",
        "a201020304",
        "a26161016162820203",
        "826161a161626163",
        "a56161614161626142616361436164614461656145",
        "5f42010243030405ff",
        "7f657374726561646d696e67ff",
        "9fff",
        "9f018202039f0405ffff",
        "9f01820203820405ff",
        "83018202039f0405ff",
        "83019f0203ff820405",
        "9f0102030405060708090a0b0c0d0e0f101112131415161718181819ff",
        "bf61610161629f0203ffff",
        "826161bf61626163ff",
        "bf6346756ef563416d7421ff",
    ];
    let mut cases: Vec<_> = vectors.iter().map(|s| hex(s)).collect();
    let mut expected = cases.clone();
    for (source, target) in [
        ("1800", "00"),
        ("190018", "1818"),
        ("1a00010000", "1a00010000"),
        ("1b000000000000ffff", "19ffff"),
        ("5800", "40"),
        ("780161", "6161"),
        ("9800", "80"),
        ("b800", "a0"),
        ("d80000", "c000"),
        ("5f5800ff", "5f40ff"),
    ] {
        cases.push(hex(source));
        expected.push(hex(target));
    }
    for (index, ((input, expected), record)) in
        cases.iter().zip(expected).zip(invoke(&cases)).enumerate()
    {
        assert_eq!(record.code, 0, "RFC case {index}: {input:02x?} {record:?}");
        assert_eq!(record.offset, input.len() as i32);
        assert_eq!(record.bytes, expected, "RFC case {index}");
    }
}
#[test]
fn rfc8949_appendix_f_malformed_utf8_wrong_chunks_and_trailing_items_are_rejected() {
    let vectors = [
        "",
        "18",
        "19",
        "1a",
        "1b",
        "1901",
        "1a0102",
        "1b01020304050607",
        "38",
        "58",
        "78",
        "98",
        "9a01ff00",
        "b8",
        "d8",
        "f8",
        "f900",
        "fa0000",
        "fb000000",
        "41",
        "61",
        "5affffffff00",
        "5bffffffffffffffff010203",
        "7affffffff00",
        "7b7fffffffffffffff010203",
        "81",
        "818181818181818181",
        "8200",
        "a1",
        "a20102",
        "a100",
        "a2000000",
        "c0",
        "5f4100",
        "7f6100",
        "9f",
        "9f0102",
        "bf",
        "bf01020102",
        "819f",
        "9f8000",
        "9f9f9f9f9fffffffff",
        "9f819f819f9fffffff",
        "1c",
        "1d",
        "1e",
        "3c",
        "3d",
        "3e",
        "5c",
        "5d",
        "5e",
        "7c",
        "7d",
        "7e",
        "9c",
        "9d",
        "9e",
        "bc",
        "bd",
        "be",
        "dc",
        "dd",
        "de",
        "fc",
        "fd",
        "fe",
        "f800",
        "f801",
        "f818",
        "f81f",
        "5f00ff",
        "5f21ff",
        "5f6100ff",
        "5f80ff",
        "5fa0ff",
        "5fc000ff",
        "5fe0ff",
        "7f4100ff",
        "5f5f4100ffff",
        "7f7f6100ffff",
        "ff",
        "81ff",
        "8200ff",
        "a1ff",
        "a1ff00",
        "a100ff",
        "a20000ff",
        "9f81ff",
        "9f829f819f9fffffffffff",
        "bf00ff",
        "bf000000ff",
        "1f",
        "3f",
        "df",
        "61ff",
        "62c080",
        "63eda080",
        "64f4908080",
        "7f61c261a2ff",
        "0001",
        "8000",
        "c00000",
    ];
    let cases: Vec<_> = vectors.iter().map(|s| hex(s)).collect();
    for (input, record) in cases.iter().zip(invoke(&cases)) {
        assert_ne!(record.code, 0, "accepted {input:02x?}");
        assert!(record.bytes.is_empty());
        assert!(
            record.offset >= 0 && record.offset as usize <= input.len(),
            "{record:?}"
        );
    }
    for (input, code, offset) in [
        ("18", 9, 0),
        ("1c", 10, 0),
        ("f818", 11, 0),
        ("61ff", 12, 0),
        ("ff", 13, 0),
        ("5f00ff", 14, 1),
        ("bf00ff", 15, 2),
        ("0001", 16, 1),
        ("8100ff", 16, 2),
    ] {
        let record = invoke(&[hex(input)]).remove(0);
        assert_eq!(
            (record.code, record.offset),
            (code, offset),
            "{input} {record:?}"
        );
    }
}

#[derive(Clone, Debug)]
enum Value {
    Unsigned(u64),
    Negative(u64),
    Bytes(Vec<u8>),
    Text(Vec<u8>),
    Array(Vec<Value>, bool),
    Map(Vec<(Value, Value)>, bool),
    Tag(u64, Box<Value>),
    Simple(u8),
    F16(u16),
    F32(u32),
    F64(u64),
    Chunks(Vec<Vec<u8>>, bool),
}
fn head(target: &mut Vec<u8>, major: u8, value: u64, wide: bool) {
    let width = if wide {
        8
    } else if value < 24 {
        0
    } else if value <= 255 {
        1
    } else if value <= 65535 {
        2
    } else if value <= u32::MAX as u64 {
        4
    } else {
        8
    };
    if width == 0 {
        target.push(major * 32 + value as u8);
    } else {
        target.push(
            major * 32
                + match width {
                    1 => 24,
                    2 => 25,
                    4 => 26,
                    8 => 27,
                    _ => unreachable!(),
                },
        );
        target.extend_from_slice(&value.to_be_bytes()[8 - width..]);
    }
}
fn wire(value: &Value, wide: bool) -> Vec<u8> {
    let mut result = Vec::new();
    emit(value, wide, &mut result);
    result
}
// Compare logical event values independently of wire re-encoding, so matching
// decoder/encoder mistakes (for example reversed scalar byte order) cannot
// cancel out in the round trip assertion.
fn logical_digest(value: &Value) -> u32 {
    fn token(hash: &mut u32, kind: u8, arg: Option<u64>, bytes: &[u8]) {
        for byte in std::iter::once(kind)
            .chain(arg.into_iter().flat_map(u64::to_le_bytes))
            .chain(bytes.iter().copied())
        {
            *hash = (*hash ^ byte as u32).wrapping_mul(16777619);
        }
    }
    fn walk(value: &Value, hash: &mut u32) {
        match value {
            Value::Unsigned(n) => token(hash, 0, Some(*n), &[]),
            Value::Negative(n) => token(hash, 1, Some(*n), &[]),
            Value::Bytes(bytes) => token(hash, 2, Some(bytes.len() as u64), bytes),
            Value::Text(bytes) => token(hash, 3, Some(bytes.len() as u64), bytes),
            Value::Array(values, indefinite) => {
                token(
                    hash,
                    if *indefinite { 13 } else { 4 },
                    if *indefinite {
                        None
                    } else {
                        Some(values.len() as u64)
                    },
                    &[],
                );
                for value in values {
                    walk(value, hash)
                }
                token(hash, 15, None, &[])
            }
            Value::Map(values, indefinite) => {
                token(
                    hash,
                    if *indefinite { 14 } else { 5 },
                    if *indefinite {
                        None
                    } else {
                        Some(values.len() as u64)
                    },
                    &[],
                );
                for (key, value) in values {
                    walk(key, hash);
                    walk(value, hash)
                }
                token(hash, 15, None, &[])
            }
            Value::Tag(tag, value) => {
                token(hash, 6, Some(*tag), &[]);
                walk(value, hash);
                token(hash, 15, None, &[])
            }
            Value::Simple(n) => token(hash, 7, Some(*n as u64), &[]),
            Value::F16(bits) => token(hash, 8, Some(*bits as u64), &[]),
            Value::F32(bits) => token(hash, 9, Some(*bits as u64), &[]),
            Value::F64(bits) => token(hash, 10, Some(*bits), &[]),
            Value::Chunks(chunks, text) => {
                token(hash, if *text { 12 } else { 11 }, None, &[]);
                for chunk in chunks {
                    token(
                        hash,
                        if *text { 3 } else { 2 },
                        Some(chunk.len() as u64),
                        chunk,
                    )
                }
                token(hash, 15, None, &[])
            }
        }
    }
    let mut result = 2166136261;
    walk(value, &mut result);
    result
}
fn emit(value: &Value, wide: bool, target: &mut Vec<u8>) {
    match value {
        Value::Unsigned(n) => head(target, 0, *n, wide),
        Value::Negative(n) => head(target, 1, *n, wide),
        Value::Bytes(bytes) | Value::Text(bytes) => {
            head(
                target,
                if matches!(value, Value::Bytes(_)) {
                    2
                } else {
                    3
                },
                bytes.len() as u64,
                wide,
            );
            target.extend_from_slice(bytes);
        }
        Value::Array(values, indefinite) => {
            if *indefinite {
                target.push(0x9f)
            } else {
                head(target, 4, values.len() as u64, wide)
            };
            for value in values {
                emit(value, wide, target)
            }
            if *indefinite {
                target.push(255)
            }
        }
        Value::Map(values, indefinite) => {
            if *indefinite {
                target.push(0xbf)
            } else {
                head(target, 5, values.len() as u64, wide)
            };
            for (key, value) in values {
                emit(key, wide, target);
                emit(value, wide, target)
            }
            if *indefinite {
                target.push(255)
            }
        }
        Value::Tag(tag, value) => {
            head(target, 6, *tag, wide);
            emit(value, wide, target)
        }
        Value::Simple(n) => head(target, 7, *n as u64, false),
        Value::F16(bits) => {
            target.push(0xf9);
            target.extend_from_slice(&bits.to_be_bytes())
        }
        Value::F32(bits) => {
            target.push(0xfa);
            target.extend_from_slice(&bits.to_be_bytes())
        }
        Value::F64(bits) => {
            target.push(0xfb);
            target.extend_from_slice(&bits.to_be_bytes())
        }
        Value::Chunks(chunks, text) => {
            target.push(if *text { 0x7f } else { 0x5f });
            for chunk in chunks {
                head(target, if *text { 3 } else { 2 }, chunk.len() as u64, wide);
                target.extend_from_slice(chunk)
            }
            target.push(255)
        }
    }
}
fn next(state: &mut u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}
fn generated(state: &mut u64, depth: usize) -> Value {
    let select = next(state) % if depth == 0 { 9 } else { 13 };
    match select {
        0 => Value::Unsigned(next(state)),
        1 => Value::Negative(next(state)),
        2 => Value::Bytes((0..next(state) % 24).map(|_| next(state) as u8).collect()),
        3 => Value::Text(
            ["", "ascii\0", "é水𝄞", "line\n\t"]
                .get(next(state) as usize % 4)
                .unwrap()
                .as_bytes()
                .to_vec(),
        ),
        4 => Value::Simple(if next(state) % 2 == 0 {
            (next(state) % 24) as u8
        } else {
            (32 + next(state) % 224) as u8
        }),
        5 => Value::F16(next(state) as u16),
        6 => Value::F32(next(state) as u32),
        7 => Value::F64(next(state)),
        8 => Value::Chunks(vec![vec![], b"a\0b".to_vec(), vec![255]], false),
        9 => {
            let count = next(state) % 5;
            Value::Array(
                (0..count).map(|_| generated(state, depth - 1)).collect(),
                next(state) % 2 == 0,
            )
        }
        10 => {
            let count = next(state) % 4;
            Value::Map(
                (0..count)
                    .map(|_| (generated(state, depth - 1), generated(state, depth - 1)))
                    .collect(),
                next(state) % 2 == 0,
            )
        }
        11 => Value::Tag(next(state), Box::new(generated(state, depth - 1))),
        _ => Value::Chunks(
            vec![vec![], "é".as_bytes().to_vec(), "水𝄞".as_bytes().to_vec()],
            true,
        ),
    }
}
#[test]
fn generated_all_type_trees_arbitrary_map_keys_duplicates_and_every_float16_bit_pattern_round_trip()
{
    let boundaries = [
        0,
        1,
        23,
        24,
        255,
        256,
        65535,
        65536,
        u32::MAX as u64,
        u32::MAX as u64 + 1,
        i64::MAX as u64,
        i64::MAX as u64 + 1,
        u64::MAX,
    ];
    let mut values = Vec::new();
    values.extend(
        [
            0,
            1,
            0x007f_ffff,
            0x0080_0000,
            0x7f7f_ffff,
            0x7f80_0000,
            0x7f80_0001,
            0x7fc0_0001,
            0x8000_0000,
            0xff80_0000,
            0xffff_ffff,
        ]
        .map(Value::F32),
    );
    values.extend(
        [
            0,
            1,
            0x000f_ffff_ffff_ffff,
            0x0010_0000_0000_0000,
            0x7fef_ffff_ffff_ffff,
            0x7ff0_0000_0000_0000,
            0x7ff0_0000_0000_0001,
            0x7ff8_0000_0000_0001,
            0x8000_0000_0000_0000,
            0xfff0_0000_0000_0000,
            u64::MAX,
        ]
        .map(Value::F64),
    );
    for value in boundaries {
        values.extend([
            Value::Unsigned(value),
            Value::Negative(value),
            Value::Tag(value, Box::new(Value::Simple(22))),
        ]);
    }
    values.push(Value::Map(
        vec![
            (
                Value::Array(vec![Value::Unsigned(1)], false),
                Value::Bytes(vec![0, 255]),
            ),
            (Value::Text(b"same".to_vec()), Value::Unsigned(1)),
            (Value::Text(b"same".to_vec()), Value::Unsigned(2)),
            (Value::Map(vec![], true), Value::F64(u64::MAX)),
        ],
        false,
    ));
    let mut state = 0xdead_beef_cafe_1234;
    values.extend((0..768).map(|_| generated(&mut state, 6)));
    let cases: Vec<_> = values
        .iter()
        .enumerate()
        .map(|(index, value)| wire(value, index % 2 == 0))
        .collect();
    for ((value, input), record) in values.iter().zip(&cases).zip(invoke(&cases)) {
        assert_eq!(record.code, 0, "{value:?} input{input:02x?} {record:?}");
        assert_eq!(record.bytes, wire(value, false), "{value:?}");
        assert_eq!(
            record.digest,
            logical_digest(value),
            "logical events for {value:?}"
        );
    }
    let halves = Value::Array((0..=u16::MAX).map(Value::F16).collect(), false);
    let source = wire(&halves, false);
    let record = invoke(&[source.clone()]).remove(0);
    assert_eq!(record.code, 0, "{record:?}");
    assert_eq!(record.bytes, source);
    assert_eq!(record.digest, logical_digest(&halves));
}
#[test]
fn depth_limits_large_batches_and_full_u64_container_arguments_terminate_without_recursion_growth()
{
    let mut cases = Vec::new();
    for depth in [0, 1, 127, 128, 255, 256, 257, 512] {
        let mut source = vec![0x81; depth];
        source.push(0);
        cases.push(source);
    }
    for (index, record) in invoke(&cases).into_iter().enumerate() {
        if index <= 5 {
            assert_eq!(record.code, 0, "{record:?}");
            assert_eq!(record.bytes, cases[index]);
        } else {
            assert_eq!((record.code, record.offset), (5, 256));
        }
    }
    for source in [
        hex("9bffffffffffffffff"),
        hex("bbffffffffffffffff"),
        hex("dbffffffffffffffff"),
    ] {
        let record = invoke(&[source]).remove(0);
        assert_eq!(record.code, 9);
    }
    let value = Value::Array(
        (0..100000)
            .map(|i| Value::Unsigned((i % 24) as u64))
            .collect(),
        false,
    );
    let source = wire(&value, false);
    model();
    let start = Instant::now();
    let record = invoke(&[source.clone()]).remove(0);
    eprintln!(
        "100000 CBOR scalar items, {} wire bytes, native validation/read/encode: {:.3}ms",
        source.len(),
        start.elapsed().as_secs_f64() * 1000.0
    );
    assert_eq!(record.code, 0);
    assert_eq!(record.bytes, source);
}
