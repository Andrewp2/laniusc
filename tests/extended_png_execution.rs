#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
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
    let exe = common::TempArtifact::new("laniusc_png", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn model() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("tests/fixtures/extended/png_model.lani"))
}
fn checked(o: &Output) {
    assert_eq!(o.status.code(), Some(0), "{o:?}");
    assert!(o.stderr.is_empty(), "{o:?}");
}
#[test]
fn png_native_byte_strides_offset_views_and_metadata_execute() {
    let exe = executable("tests/fixtures/extended/png_contracts.lani");
    let output = common::process_output_with_timeout(
        "PNG view contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(10),
    );
    checked(&output);
    assert!(output.stdout.is_empty());
}
#[derive(Clone, Debug)]
struct Case {
    mode: u8,
    input: Vec<u8>,
    width: i32,
    height: i32,
    limits: [i32; 5],
}
fn decode(input: Vec<u8>) -> Case {
    Case {
        mode: 0,
        input,
        width: 0,
        height: 0,
        limits: [2_000_000, 1_000_000, 4_000_000, 65536, 2_000_000],
    }
}
fn encode(width: i32, height: i32, input: Vec<u8>) -> Case {
    let mut c = decode(input);
    c.mode = 1;
    c.width = width;
    c.height = height;
    c
}
fn frame(cases: &[Case]) -> Vec<u8> {
    let mut b = vec![];
    for c in cases {
        b.push(c.mode);
        for n in c
            .limits
            .into_iter()
            .chain([c.width, c.height, c.input.len() as i32])
        {
            b.extend(n.to_le_bytes());
        }
        b.extend(&c.input);
    }
    b
}
#[derive(Debug, PartialEq, Eq)]
struct Row {
    code: i32,
    width: i32,
    height: i32,
    bytes: Vec<u8>,
}
fn take32(b: &[u8], p: &mut usize) -> i32 {
    let n = i32::from_le_bytes(b[*p..*p + 4].try_into().unwrap());
    *p += 4;
    n
}
fn parse(b: &[u8]) -> Vec<Row> {
    let mut p = 0;
    let mut out = vec![];
    while p < b.len() {
        let code = take32(b, &mut p);
        let width = take32(b, &mut p);
        let height = take32(b, &mut p);
        let n = take32(b, &mut p) as usize;
        assert!(n <= b.len() - p);
        out.push(Row {
            code,
            width,
            height,
            bytes: b[p..p + n].to_vec(),
        });
        p += n;
    }
    out
}
fn run(cases: &[Case]) -> Vec<Row> {
    if cases.len() > 1 && cases.iter().map(|c| c.input.len() + 33).sum::<usize>() > 900_000 {
        let middle = cases.len() / 2;
        let mut rows = run(&cases[..middle]);
        rows.extend(run(&cases[middle..]));
        return rows;
    }
    let input = common::TempArtifact::new("laniusc_png", "input", None);
    input.write_bytes(frame(cases));
    let o = common::process_output_with_timeout(
        "PNG model",
        Command::new(model().path()).stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(20),
    );
    checked(&o);
    let rows = parse(&o.stdout);
    assert_eq!(rows.len(), cases.len());
    rows
}
fn python(script: &str, args: &[&str], input: &[u8]) -> Vec<u8> {
    let source = common::TempArtifact::new("laniusc_png", "python-input", None);
    source.write_bytes(input);
    let o = common::process_output_with_timeout(
        "PNG oracle",
        Command::new("python3")
            .arg(script)
            .args(args)
            .stdin(std::fs::File::open(source.path()).unwrap()),
        Duration::from_secs(20),
    );
    checked(&o);
    o.stdout
}
fn oracle() -> Vec<(i32, i32, Vec<u8>, Vec<u8>)> {
    let b = python("tests/fixtures/extended/png_oracle.py", &["generate"], &[]);
    let mut p = 0;
    let mut rows = vec![];
    while p < b.len() {
        let w = take32(&b, &mut p);
        let h = take32(&b, &mut p);
        let n = take32(&b, &mut p) as usize;
        let m = take32(&b, &mut p) as usize;
        let png = b[p..p + n].to_vec();
        p += n;
        let rgba = b[p..p + m].to_vec();
        p += m;
        rows.push((w, h, png, rgba));
    }
    rows
}
fn crc(b: &[u8]) -> u32 {
    let mut c = u32::MAX;
    for &b in b {
        c ^= b as u32;
        for _ in 0..8 {
            c = (c >> 1) ^ if c & 1 != 0 { 0xedb88320 } else { 0 };
        }
    }
    !c
}
fn chunks(png: &[u8]) -> Vec<([u8; 4], Vec<u8>)> {
    let mut p = 8;
    let mut out = vec![];
    while p < png.len() {
        let n = u32::from_be_bytes(png[p..p + 4].try_into().unwrap()) as usize;
        out.push((
            png[p + 4..p + 8].try_into().unwrap(),
            png[p + 8..p + 8 + n].to_vec(),
        ));
        p += n + 12;
    }
    out
}
fn assemble(chunks: &[([u8; 4], Vec<u8>)]) -> Vec<u8> {
    let mut b = b"\x89PNG\r\n\x1a\n".to_vec();
    for (kind, data) in chunks {
        b.extend((data.len() as u32).to_be_bytes());
        let start = b.len();
        b.extend(kind);
        b.extend(data);
        b.extend(crc(&b[start..]).to_be_bytes());
    }
    b
}
fn zipped(raw: &[u8]) -> Vec<u8> {
    let source = common::TempArtifact::new("laniusc_png", "zip-input", None);
    source.write_bytes(raw);
    let o = common::process_output_with_timeout(
        "zlib oracle",
        Command::new("python3")
            .args([
                "-c",
                "import sys,zlib;sys.stdout.buffer.write(zlib.compress(sys.stdin.buffer.read()))",
            ])
            .stdin(std::fs::File::open(source.path()).unwrap()),
        Duration::from_secs(10),
    );
    checked(&o);
    o.stdout
}
fn simple(raw: &[u8]) -> Vec<u8> {
    let mut h = vec![];
    h.extend(2u32.to_be_bytes());
    h.extend(1u32.to_be_bytes());
    h.extend([8, 6, 0, 0, 0]);
    assemble(&[(*b"IHDR", h), (*b"IDAT", zipped(raw)), (*b"IEND", vec![])])
}
#[test]
fn every_standard_color_depth_filter_and_adam7_pass_matches_independent_samples() {
    let references = oracle();
    assert_eq!(references.len(), 600);
    let cases: Vec<_> = references.iter().map(|r| decode(r.2.clone())).collect();
    for (i, (row, (w, h, _, rgba))) in run(&cases).into_iter().zip(references).enumerate() {
        assert_eq!(
            row,
            Row {
                code: 0,
                width: w,
                height: h,
                bytes: rgba
            },
            "matrix case {i}"
        );
    }
}
#[test]
fn rgba_encoding_decodes_in_pillow_and_exact_output_caps_are_observed() {
    let mut seed = 123u32;
    let mut cases = vec![];
    for (w, h) in [(1, 1), (3, 7), (127, 129), (256, 256), (511, 511)] {
        let rgba = (0..w * h * 4)
            .map(|_| {
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                (seed >> 24) as u8
            })
            .collect();
        cases.push(encode(w, h, rgba));
    }
    let before = Instant::now();
    let rows = run(&cases);
    assert!(before.elapsed() < Duration::from_secs(20));
    for (c, row) in cases.iter().zip(rows) {
        assert_eq!(row.code, 0);
        let decoded = python(
            "tests/fixtures/extended/png_oracle.py",
            &["decode"],
            &row.bytes,
        );
        let mut want = vec![];
        want.extend(c.width.to_le_bytes());
        want.extend(c.height.to_le_bytes());
        want.extend(&c.input);
        assert_eq!(decoded, want);
        let mut exact = c.clone();
        exact.limits[4] = row.bytes.len() as i32;
        let mut short = exact.clone();
        short.limits[4] -= 1;
        let mut zero = exact.clone();
        zero.limits[4] = 0;
        let mut negative = exact.clone();
        negative.limits[4] = -1;
        let results = run(&[exact, short, zero, negative]);
        assert_eq!(results[0].bytes, row.bytes);
        assert_eq!(results[1].code, 6);
        assert_eq!(results[2].code, 6);
        assert_eq!(results[3].code, 1);
        assert_eq!(run(&[decode(row.bytes)])[0].bytes, c.input);
    }
}
#[test]
fn malformed_chunks_checksums_order_rows_and_limits_fail_without_publishing_pixels() {
    let good = simple(&[0, 1, 2, 3, 4, 5, 6, 7, 8]);
    let base = chunks(&good);
    let mut cases = vec![];
    let mut expected = vec![];
    let mut add = |bytes: Vec<u8>, code: i32| {
        cases.push(decode(bytes));
        expected.push(code);
    };
    for n in 0..good.len() {
        add(good[..n].to_vec(), -1);
    }
    for p in [0, 4, 7] {
        let mut b = good.clone();
        b[p] ^= 1;
        add(b, 9);
    }
    for p in [29, good.len() - 1, good.len() - 13] {
        let mut b = good.clone();
        b[p] ^= 1;
        add(b, 13);
    }
    let mut c = base.clone();
    c.insert(1, (*b"ABCD", vec![]));
    add(assemble(&c), 17);
    let mut c = base.clone();
    c.insert(1, (*b"abCD", vec![1]));
    add(assemble(&c), 0);
    let mut c = base.clone();
    c.insert(1, (*b"ab@D", vec![]));
    add(assemble(&c), 11);
    let mut c = base.clone();
    c.insert(1, (*b"abcd", vec![]));
    add(assemble(&c), 0);
    let mut c = base.clone();
    c.insert(1, (*b"Abcd", vec![]));
    add(assemble(&c), 17);
    let mut c = base.clone();
    c.insert(1, c[0].clone());
    add(assemble(&c), 12);
    let mut c = base.clone();
    c.insert(2, (*b"tEXt", vec![]));
    c.insert(3, c[1].clone());
    add(assemble(&c), 12);
    let mut c = base.clone();
    c[2].1.push(0);
    add(assemble(&c), 12);
    let mut c = base.clone();
    c.insert(0, (*b"tEXt", vec![]));
    add(assemble(&c), 12);
    let mut c = base.clone();
    c.remove(1);
    add(assemble(&c), 12);
    let mut b = good.clone();
    b.push(0);
    add(b, 20);
    let mut c = base.clone();
    c[0].1[0..4].fill(0);
    add(assemble(&c), 14);
    for (at, value) in [(8, 3), (9, 1), (10, 1), (11, 1), (12, 2)] {
        let mut c = base.clone();
        c[0].1[at] = value;
        add(assemble(&c), 14);
    }
    let mut c = base.clone();
    c[1].1.last_mut().map(|v| *v ^= 1);
    add(assemble(&c), 21);
    let mut c = base.clone();
    c[1].1.extend([0, 0, 99]);
    add(assemble(&c), 0); // PNG permits unused IDAT suffix.
    add(simple(&[5, 1, 2, 3, 4, 5, 6, 7, 8]), 19);
    add(simple(&[0, 1, 2, 3]), 18);
    add(simple(&[0, 1, 2, 3, 4, 5, 6, 7, 8, 9]), 18);
    for (i, row) in run(&cases).into_iter().enumerate() {
        if expected[i] < 0 {
            assert_ne!(row.code, 0, "prefix {i}");
        } else {
            assert_eq!(row.code, expected[i], "case {i}");
        }
        if row.code != 0 {
            assert_eq!(
                (row.width, row.height, row.bytes.len()),
                (0, 0, 0),
                "case {i}"
            );
        }
    }
    let mut bounded = vec![];
    let exact = [good.len() as i32, 2, 9, 3, 2_000_000];
    for index in 0..4 {
        let mut c = decode(good.clone());
        c.limits = exact;
        c.limits[index] -= 1;
        bounded.push(c);
    }
    for index in 0..4 {
        let mut c = decode(good.clone());
        c.limits[index] = -1;
        bounded.push(c);
    }
    let rows = run(&bounded);
    for (row, code) in rows.iter().zip([2, 3, 4, 5, 1, 1, 1, 1]) {
        assert_eq!(row.code, code);
        assert!(row.bytes.is_empty());
    }
    let mut c = decode(good);
    c.limits = exact;
    assert_eq!(run(&[c])[0].code, 0);
}
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut n = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let addr = line.rsplit(" = ").next().unwrap();
            if addr.starts_with("0x") {
                assert!(
                    live.insert(addr.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                n += 1;
            }
        } else if let Some(tail) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(tail.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "leaked: {events}");
    n
}
#[test]
fn palette_and_transparency_chunks_validate_sizes_presence_indexes_and_order() {
    let mut header = vec![];
    header.extend(2u32.to_be_bytes());
    header.extend(1u32.to_be_bytes());
    header.extend([1, 3, 0, 0, 0]);
    let base = vec![
        (*b"IHDR", header),
        (*b"PLTE", vec![1, 2, 3, 4, 5, 6]),
        (*b"tRNS", vec![0]),
        (*b"IDAT", zipped(&[0, 64])),
        (*b"IEND", vec![]),
    ];
    let mut cases = vec![decode(assemble(&base))];
    let mut codes = vec![0];
    let mut add = |chunks: Vec<([u8; 4], Vec<u8>)>, code| {
        cases.push(decode(assemble(&chunks)));
        codes.push(code);
    };
    let mut c = base.clone();
    c.remove(1);
    add(c, 16);
    let mut c = base.clone();
    c.remove(2);
    c.remove(1);
    add(c, 15);
    let mut c = base.clone();
    c[1].1.truncate(3);
    add(c, 15);
    let mut c = base.clone();
    c[1].1.push(7);
    add(c, 15);
    let mut c = base.clone();
    c[1].1.clear();
    add(c, 15);
    let mut c = base.clone();
    c[1].1.extend([7, 8, 9]);
    add(c, 15);
    let mut c = base.clone();
    c[2].1.extend([1, 2]);
    add(c, 16);
    let mut c = base.clone();
    c.insert(2, c[1].clone());
    add(c, 12);
    let mut c = base.clone();
    c.insert(3, c[2].clone());
    add(c, 12);
    let mut c = base.clone();
    c.swap(2, 3);
    add(c, 12);
    let mut c = base.clone();
    c.swap(1, 2);
    add(c, 16);
    let mut c = base.clone();
    c[0].1[9] = 0;
    add(c, 15);
    let mut c = chunks(&simple(&[0, 1, 2, 3, 4, 5, 6, 7, 8]));
    c.insert(1, (*b"tRNS", vec![0, 1]));
    add(c, 16);
    let mut c = base.clone();
    c[0].1[9] = 0;
    c.remove(1);
    c[1].1 = vec![0];
    add(c, 16);
    for (i, (row, code)) in run(&cases).into_iter().zip(codes).enumerate() {
        assert_eq!(row.code, code, "palette case {i}");
        if code != 0 {
            assert!(row.bytes.is_empty());
        }
    }
}
#[test]
fn allocation_denial_releases_every_temporary_on_decode_encode_and_late_filter_error() {
    let rgba: Vec<u8> = (0..4096).map(|i| (i * 37) as u8).collect();
    let png = run(&[encode(32, 32, rgba.clone())]).remove(0).bytes;
    let mut trailing = chunks(&simple(&[0, 1, 2, 3, 4, 5, 6, 7, 8]));
    trailing[1].1.extend([0, 0, 99]);
    for (workload, c) in [
        decode(png),
        encode(32, 32, rgba),
        decode(simple(&[5, 1, 2, 3, 4, 5, 6, 7, 8])),
        decode(assemble(&trailing)),
    ]
    .into_iter()
    .enumerate()
    {
        let input = common::TempArtifact::new("laniusc_png", "failure-input", None);
        input.write_bytes(frame(&[c]));
        let trace = common::TempArtifact::new("laniusc_png", "trace", None);
        let run_trace = |fail: Option<usize>| {
            let mut cmd = Command::new("strace");
            cmd.args(["-qq", "-o"])
                .arg(trace.path())
                .args(["-e", "trace=mmap,munmap"]);
            if let Some(n) = fail {
                cmd.args(["-e", &format!("inject=mmap:error=ENOMEM:when={n}")]);
            }
            cmd.arg(model().path())
                .stdin(std::fs::File::open(input.path()).unwrap());
            let o = common::process_output_with_timeout(
                "PNG allocation denial",
                &mut cmd,
                Duration::from_secs(10),
            );
            checked(&o);
            let rows = parse(&o.stdout);
            assert_eq!(rows.len(), 1);
            let n = freed(&std::fs::read_to_string(trace.path()).unwrap());
            (rows.into_iter().next().unwrap(), n)
        };
        let (baseline, n) = run_trace(None);
        assert_eq!(baseline.code, if workload == 2 { 19 } else { 0 });
        assert!(n > 0);
        for fail in 1..=n {
            let (row, _) = run_trace(Some(fail));
            assert_eq!(
                row,
                Row {
                    code: 7,
                    width: 0,
                    height: 0,
                    bytes: vec![]
                },
                "workload {workload} allocation {fail}/{n}"
            );
        }
    }
}
