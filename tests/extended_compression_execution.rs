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
    let exe = common::TempArtifact::new("laniusc_compression", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn checked(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
#[test]
fn container_contracts_execute_native_strides_selected_views_ownership_and_invalid_metadata() {
    let exe = executable("tests/fixtures/extended/compression_contracts.lani");
    let trace = common::TempArtifact::new("laniusc_compression", "contracts", None);
    let output = common::process_output_with_timeout(
        "compression contracts",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    checked(&output);
    assert!(output.stdout.is_empty());
    assert!(freed(&std::fs::read_to_string(trace.path()).unwrap()) >= 9);
}
#[derive(Clone, Debug)]
struct Case {
    encode: bool,
    format: u8,
    input: Vec<u8>,
    max_input: i32,
    max_output: i32,
    max_members: i32,
}
fn case(encode: bool, format: u8, input: Vec<u8>) -> Case {
    Case {
        encode,
        format,
        input,
        max_input: 2_000_000,
        max_output: 2_000_000,
        max_members: 1024,
    }
}
fn frame(cases: &[Case]) -> Vec<u8> {
    let mut bytes = Vec::new();
    for c in cases {
        bytes.extend([u8::from(c.encode), c.format]);
        for value in [
            c.max_input,
            c.max_output,
            c.max_members,
            c.input.len() as i32,
        ] {
            bytes.extend(value.to_le_bytes());
        }
        bytes.extend(&c.input);
    }
    bytes
}
fn parse(bytes: &[u8]) -> Vec<(i32, Vec<u8>)> {
    let mut rows = Vec::new();
    let mut at = 0;
    while at < bytes.len() {
        assert!(bytes.len() - at >= 8);
        let error = i32::from_le_bytes(bytes[at..at + 4].try_into().unwrap());
        let n = u32::from_le_bytes(bytes[at + 4..at + 8].try_into().unwrap()) as usize;
        at += 8;
        assert!(n <= bytes.len() - at);
        rows.push((error, bytes[at..at + n].to_vec()));
        at += n;
    }
    rows
}
fn run_cases(exe: &common::TempArtifact, cases: &[Case]) -> Vec<(i32, Vec<u8>)> {
    let mut all = Vec::new();
    let mut start = 0;
    while start < cases.len() {
        let mut end = start;
        let mut size = 0;
        while end < cases.len() && size + 18 + cases[end].input.len() < 230_000 {
            size += 18 + cases[end].input.len();
            end += 1;
        }
        assert!(end > start);
        let input = common::TempArtifact::new("laniusc_compression", "input", None);
        input.write_bytes(frame(&cases[start..end]));
        let output = common::process_output_with_timeout(
            "compression model",
            Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()),
            Duration::from_secs(15),
        );
        checked(&output);
        let rows = parse(&output.stdout);
        assert_eq!(rows.len(), end - start);
        all.extend(rows);
        start = end;
    }
    all
}
// Python is an independent test oracle only. Production compression is Lanius.
fn reference(inputs: &[(u8, i32, i32, Vec<u8>)], encode: bool) -> Vec<Vec<u8>> {
    let source = common::TempArtifact::new("laniusc_compression", "reference", None);
    let mut bytes = Vec::new();
    for (format, level, strategy, input) in inputs {
        bytes.push(*format);
        bytes.extend(level.to_le_bytes());
        bytes.extend(strategy.to_le_bytes());
        bytes.extend((input.len() as u32).to_le_bytes());
        bytes.extend(input);
    }
    source.write_bytes(bytes);
    let script = r#"import sys,struct,zlib
b=sys.stdin.buffer.read();i=0
while i<len(b):
 f=b[i];level,strategy,n=struct.unpack_from('<iiI',b,i+1);i+=13;raw=b[i:i+n];i+=n;bits=(-15,15,31)[f]
 if sys.argv[1]=='encode':
  c=zlib.compressobj(level,zlib.DEFLATED,bits,8,strategy);out=c.compress(raw)+c.flush()
 else:
  c=zlib.decompressobj(bits);out=c.decompress(raw)+c.flush();assert c.eof and not c.unused_data
 sys.stdout.buffer.write(struct.pack('<I',len(out))+out)
"#;
    let output = common::process_output_with_timeout(
        "Python zlib reference",
        Command::new("python3")
            .args(["-c", script, if encode { "encode" } else { "decode" }])
            .stdin(std::fs::File::open(source.path()).unwrap()),
        Duration::from_secs(10),
    );
    checked(&output);
    let mut rows = Vec::new();
    let mut at = 0;
    while at < output.stdout.len() {
        let n = u32::from_le_bytes(output.stdout[at..at + 4].try_into().unwrap()) as usize;
        at += 4;
        rows.push(output.stdout[at..at + n].to_vec());
        at += n;
    }
    assert_eq!(rows.len(), inputs.len());
    rows
}
fn corpus() -> Vec<Vec<u8>> {
    let mut inputs = vec![
        vec![],
        b"hello world\n".to_vec(),
        vec![0],
        vec![255],
        (0..=255).collect(),
        vec![97; 65_537],
        b"abcabc XYZ abcabc XYZ\n".repeat(1300),
    ];
    let mut seed = 0x738acf32u32;
    for n in [31, 255, 256, 257, 4097, 16_385, 65_535] {
        let mut v = Vec::new();
        for _ in 0..n {
            seed ^= seed << 13;
            seed ^= seed >> 17;
            seed ^= seed << 5;
            v.push((seed >> 8) as u8);
        }
        inputs.push(v);
    }
    inputs
}
#[test]
fn independent_zlib_streams_decode_stored_fixed_dynamic_blocks_and_binary_payloads() {
    let exe = executable("tests/fixtures/extended/compression_model.lani");
    let inputs = corpus();
    let mut refs = Vec::new();
    for format in 0..3 {
        for (i, input) in inputs.iter().enumerate() {
            for (level, strategy) in [(0, 0), (1, 0), (9, 0), (6, 4), (6, 2), (6, 3)] {
                if input.len() > 32_000 && i % 2 == 0 && level != 9 {
                    continue;
                }
                refs.push((format, level, strategy, input.clone()));
            }
        }
    }
    let streams = reference(&refs, true);
    let cases: Vec<_> = refs
        .iter()
        .zip(streams)
        .map(|((f, _, _, _), v)| case(false, *f, v))
        .collect();
    let rows = run_cases(&exe, &cases);
    for ((c, row), (_, level, strategy, input)) in cases.iter().zip(rows).zip(refs) {
        assert_eq!(
            row,
            (0, input),
            "format={} level={level} strategy={strategy} compressed={}",
            c.format,
            c.input.len()
        );
    }
}
#[test]
fn owned_encoders_are_deterministic_compress_repetition_and_interoperate_with_python() {
    let exe = executable("tests/fixtures/extended/compression_model.lani");
    let mut cases = Vec::new();
    for input in corpus() {
        for format in 0..3 {
            cases.push(case(true, format, input.clone()));
        }
    }
    let first = run_cases(&exe, &cases);
    assert_eq!(first, run_cases(&exe, &cases));
    let mut refs = Vec::new();
    for (c, (error, output)) in cases.iter().zip(&first) {
        assert_eq!(*error, 0, "{c:?}");
        if c.input.len() > 60_000 && c.input.iter().all(|b| *b == 97) {
            assert!(
                output.len() < 1000,
                "did not compress repetitive data: {}",
                output.len()
            );
        }
        if c.format == 2 {
            assert_eq!(&output[..10], &[31, 139, 8, 0, 0, 0, 0, 0, 0, 255]);
        }
        refs.push((c.format, 0, 0, output.clone()));
    }
    let decoded = reference(&refs, false);
    for (c, plain) in cases.iter().zip(decoded) {
        assert_eq!(plain, c.input);
    }
    let mut exact = Vec::new();
    for (c, (_, out)) in cases.iter().zip(first) {
        let mut yes = c.clone();
        yes.max_output = out.len() as i32;
        exact.push(yes.clone());
        yes.max_output -= 1;
        exact.push(yes);
    }
    let rows = run_cases(&exe, &exact);
    for pair in rows.chunks(2) {
        assert_eq!(pair[0].0, 0);
        assert_eq!(pair[1], (3, vec![]));
    }
}
fn gzip_member(data: &[u8], flags: u8) -> Vec<u8> {
    let encoded = reference(&[(0, 6, 0, data.to_vec())], true).remove(0);
    let mut header = vec![31, 139, 8, flags, 12, 34, 56, 78, 0, 3];
    if flags & 4 != 0 {
        header.extend([7, 0, b'L', b'N', 3, 0, 0, 255, 7]);
    }
    if flags & 8 != 0 {
        header.extend(b"name\xff.bin\0");
    }
    if flags & 16 != 0 {
        header.extend(b"comment\x80\n\0");
    }
    if flags & 2 != 0 {
        let crc = reference_crc(&header);
        header.extend((crc as u16).to_le_bytes());
    }
    header.extend(encoded);
    header.extend(reference_crc(data).to_le_bytes());
    header.extend((data.len() as u32).to_le_bytes());
    header
}
fn reference_crc(data: &[u8]) -> u32 {
    let mut crc = 0xffff_ffffu32;
    for b in data {
        crc ^= *b as u32;
        for _ in 0..8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0xedb8_8320
            } else {
                crc >> 1
            };
        }
    }
    crc ^ 0xffff_ffff
}
#[test]
fn gzip_optional_headers_concatenated_members_and_exact_cumulative_limits_execute() {
    let exe = executable("tests/fixtures/extended/compression_model.lani");
    let mut cases = Vec::new();
    let mut expected = Vec::new();
    for flags in 0..32 {
        cases.push(case(false, 2, gzip_member(b"payload\0\xff", flags)));
        expected.push((0, b"payload\0\xff".to_vec()));
    }
    let mut concat = Vec::new();
    let mut plain = Vec::new();
    for i in 0..11 {
        let data = vec![i as u8; if i % 3 == 0 { 0 } else { 271 + i * 33 }];
        concat.extend(gzip_member(&data, (i * 3) as u8 & 31));
        plain.extend(data);
    }
    let mut base = case(false, 2, concat.clone());
    base.max_input = concat.len() as i32;
    base.max_output = plain.len() as i32;
    base.max_members = 11;
    cases.push(base.clone());
    expected.push((0, plain));
    let mut c = base.clone();
    c.max_input -= 1;
    cases.push(c);
    expected.push((2, vec![]));
    let mut c = base.clone();
    c.max_output -= 1;
    cases.push(c);
    expected.push((3, vec![]));
    let mut c = base;
    c.max_members -= 1;
    cases.push(c);
    expected.push((4, vec![]));
    for format in 0..3 {
        let stream = reference(&[(format, 6, 0, vec![])], true).remove(0);
        let mut c = case(false, format, stream);
        c.max_output = 0;
        cases.push(c);
        expected.push((0, vec![]));
    }
    assert_eq!(run_cases(&exe, &cases), expected);
}
#[test]
fn malformed_headers_checksums_sizes_truncations_trailing_bytes_and_limits_fail_closed() {
    let exe = executable("tests/fixtures/extended/compression_model.lani");
    let mut cases = Vec::new();
    let mut expected = Vec::new();
    for format in 0..3 {
        let stream = reference(
            &[(format, 6, 0, b"small payload small payload".to_vec())],
            true,
        )
        .remove(0);
        for end in 0..stream.len() {
            cases.push(case(false, format, stream[..end].to_vec()));
            expected.push(None);
        }
        for junk in [vec![0], vec![31], vec![1, 2, 3], stream.clone()] {
            let mut bytes = stream.clone();
            bytes.extend(junk);
            cases.push(case(false, format, bytes));
            expected.push(
                if format == 2 && cases.last().unwrap().input.len() == stream.len() * 2 {
                    Some(0)
                } else {
                    None
                },
            );
        }
        if format != 0 {
            let mut b = stream.clone();
            let i = b.len() - if format == 1 { 1 } else { 8 };
            b[i] ^= 1;
            cases.push(case(false, format, b));
            expected.push(Some(12));
        }
        let mut c = case(false, format, stream.clone());
        c.max_members = 0;
        cases.push(c);
        expected.push(Some(4));
        let mut c = case(false, format, stream);
        c.max_input = -1;
        cases.push(c);
        expected.push(Some(1));
    }
    let zlib = reference(&[(1, 6, 0, b"hello".to_vec())], true).remove(0);
    for (at, value, code) in [(0, 0x79, 9), (0, 0x88, 10), (1, zlib[1] ^ 1, 8)] {
        let mut b = zlib.clone();
        b[at] = value;
        cases.push(case(false, 1, b));
        expected.push(Some(code));
    }
    let mut dictionary = vec![0x78, 0x20];
    while ((dictionary[0] as u16) * 256 + dictionary[1] as u16) % 31 != 0 {
        dictionary[1] += 1;
    }
    dictionary.extend([0, 0, 0, 1]);
    cases.push(case(false, 1, dictionary));
    expected.push(Some(11));
    let gzip = gzip_member(b"hello", 31);
    for (at, value, code) in [
        (0, 0, 8),
        (2, 7, 9),
        (3, 0xff, 8),
        (gzip.len() - 1, 1, 13),
        (gzip.len() - 8, 0, 12),
    ] {
        let mut b = gzip.clone();
        b[at] = value;
        cases.push(case(false, 2, b));
        expected.push(Some(code));
    }
    // Header CRC includes optional fields and is checked before decoding.
    let mut b = gzip.clone();
    b[10 + 2 + 7 + 10 + 10] ^= 1;
    cases.push(case(false, 2, b));
    expected.push(Some(12));
    let rows = run_cases(&exe, &cases);
    for ((c, (code, out)), expected) in cases.iter().zip(rows).zip(expected) {
        if let Some(want) = expected {
            assert_eq!(code, want, "{c:?}");
        } else {
            assert_ne!(code, 0, "{c:?}");
        }
        if code != 0 {
            assert!(out.is_empty());
        }
    }
}
#[test]
fn zlib_header_window_limits_are_enforced_independently_of_checksum_and_output_capacity() {
    let exe = executable("tests/fixtures/extended/compression_model.lani");
    fn set_window(bytes: &mut [u8], cinfo: u8, level: u8) {
        bytes[0] = (cinfo << 4) | 8;
        bytes[1] = level << 6;
        let rem = ((bytes[0] as u16) * 256 + bytes[1] as u16) % 31;
        if rem != 0 {
            bytes[1] += (31 - rem) as u8;
        }
    }
    let plain = b"abcabcabcabcabcabc".repeat(300);
    let small = reference(&[(1, 9, 0, plain.clone())], true).remove(0);
    let mut cases = Vec::new();
    for cinfo in 0..8 {
        for level in 0..4 {
            let mut stream = small.clone();
            set_window(&mut stream, cinfo, level);
            cases.push(case(false, 1, stream));
        }
    }
    for row in run_cases(&exe, &cases) {
        assert_eq!(row, (0, plain.clone()));
    }
    let mut seed = 17832u32;
    let mut prefix = Vec::new();
    for _ in 0..400 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        prefix.push((seed >> 24) as u8);
    }
    let distant = [prefix.clone(), prefix].concat();
    let mut stream = reference(&[(1, 9, 0, distant.clone())], true).remove(0);
    assert!(
        stream.len() < 650,
        "oracle must actually encode distant references"
    );
    assert_eq!(
        run_cases(&exe, &[case(false, 1, stream.clone())]),
        vec![(0, distant)]
    );
    set_window(&mut stream, 0, 2);
    assert_eq!(
        run_cases(&exe, &[case(false, 1, stream)]),
        vec![(15, vec![])]
    );
}
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut allocations = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let value = line.rsplit(" = ").next().unwrap();
            if value.starts_with("0x") {
                assert!(
                    live.insert(value.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                allocations += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "leaked: {events}");
    allocations
}
#[test]
fn every_observed_allocation_failure_frees_partial_outputs_and_no_result_escapes() {
    let exe = executable("tests/fixtures/extended/compression_model.lani");
    let source = b"one two three\0".repeat(3100);
    let zipped = gzip_member(&source, 31);
    let workloads = [
        case(true, 2, source.clone()),
        case(false, 2, zipped.clone()),
        {
            let mut c = case(false, 2, zipped);
            let last = c.input.len() - 8;
            c.input[last] ^= 1;
            c
        },
    ];
    for (workload_index, c) in workloads.into_iter().enumerate() {
        let input = common::TempArtifact::new("laniusc_compression", "failure-input", None);
        input.write_bytes(frame(std::slice::from_ref(&c)));
        let trace = common::TempArtifact::new("laniusc_compression", "trace", None);
        let run = |inject: Option<usize>| {
            let mut command = Command::new("strace");
            command
                .args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap"]);
            if let Some(n) = inject {
                command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={n}")]);
            }
            command
                .arg(exe.path())
                .stdin(std::fs::File::open(input.path()).unwrap());
            let output = common::process_output_with_timeout(
                "compression allocation failure",
                &mut command,
                Duration::from_secs(10),
            );
            checked(&output);
            let mut rows = parse(&output.stdout);
            assert_eq!(rows.len(), 1);
            let count = freed(&std::fs::read_to_string(trace.path()).unwrap());
            (rows.remove(0), count)
        };
        let (baseline, n) = run(None);
        assert_eq!(baseline.0, if workload_index == 2 { 12 } else { 0 });
        assert!(n > 0);
        for fail in 1..=n {
            let (actual, _) = run(Some(fail));
            assert_eq!(
                actual,
                (5, vec![]),
                "failure={fail}/{n} baseline={baseline:?}"
            );
        }
    }
}
