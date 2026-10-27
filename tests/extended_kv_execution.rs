#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    os::unix::fs::PermissionsExt,
    process::{Command, Output},
    sync::OnceLock,
    time::Duration,
};
fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(if name == "kv_tool" {
        "sample_programs/library/kv_tool.lani".to_string()
    } else {
        format!("tests/fixtures/extended/{name}.lani")
    });
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|e| panic!("{name}: {e}"));
    let exe = common::TempArtifact::new("laniusc_kv", name, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn model() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("kv_model"))
}
fn cli() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| executable("kv_tool"))
}
fn checked(o: &Output) {
    assert_eq!(o.status.code(), Some(0), "{o:?}");
    assert!(o.stderr.is_empty(), "{o:?}");
}
#[derive(Clone, Debug)]
struct Op {
    mode: u8,
    key: Vec<u8>,
    value: Vec<u8>,
    limits: [i32; 5],
    work: u64,
}
fn op(mode: u8, key: Vec<u8>, value: Vec<u8>) -> Op {
    Op {
        mode,
        key,
        value,
        limits: [65536, 65536, 16777216, 67108864, 68157440],
        work: 536870912,
    }
}
fn frame(ops: &[Op]) -> Vec<u8> {
    let mut b = vec![];
    for o in ops {
        b.push(o.mode);
        for n in o.limits {
            b.extend(n.to_le_bytes());
        }
        b.extend(o.work.to_le_bytes());
        b.extend((o.key.len() as u32).to_le_bytes());
        b.extend((o.value.len() as u32).to_le_bytes());
        b.extend(&o.key);
        b.extend(&o.value);
    }
    assert!(b.len() < 1048576);
    b
}
#[derive(Debug, PartialEq, Eq)]
struct Row {
    code: i32,
    detail: i32,
    bytes: Vec<u8>,
}
fn get32(b: &[u8], p: &mut usize) -> i32 {
    let n = i32::from_le_bytes(b[*p..*p + 4].try_into().unwrap());
    *p += 4;
    n
}
fn parse(b: &[u8]) -> Vec<Row> {
    let mut p = 0;
    let mut rows = vec![];
    while p < b.len() {
        let code = get32(b, &mut p);
        let detail = get32(b, &mut p);
        let n = get32(b, &mut p) as usize;
        assert!(n <= b.len() - p);
        rows.push(Row {
            code,
            detail,
            bytes: b[p..p + n].to_vec(),
        });
        p += n;
    }
    rows
}
fn run(ops: &[Op]) -> Vec<Row> {
    let input = common::TempArtifact::new("laniusc_kv", "input", None);
    input.write_bytes(frame(ops));
    let o = common::process_output_with_timeout(
        "KV model",
        Command::new(model().path()).stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(20),
    );
    checked(&o);
    let rows = parse(&o.stdout);
    assert_eq!(rows.len(), ops.len());
    rows
}
fn packed(map: &BTreeMap<Vec<u8>, Vec<u8>>) -> Vec<u8> {
    let mut b = (map.len() as u32).to_le_bytes().to_vec();
    for (k, v) in map {
        b.extend((k.len() as u32).to_le_bytes());
        b.extend((v.len() as u32).to_le_bytes());
        b.extend(k);
        b.extend(v);
    }
    b
}
fn oracle(mode: &str, items: &[Vec<u8>]) -> Vec<Vec<u8>> {
    let mut input = vec![];
    for item in items {
        input.extend((item.len() as u32).to_le_bytes());
        input.extend(item);
    }
    let file = common::TempArtifact::new("laniusc_kv", "oracle", None);
    file.write_bytes(input);
    let o = common::process_output_with_timeout(
        "KV snapshot oracle",
        Command::new("python3")
            .arg("tests/fixtures/extended/kv_oracle.py")
            .arg(mode)
            .stdin(std::fs::File::open(file.path()).unwrap()),
        Duration::from_secs(10),
    );
    checked(&o);
    let mut p = 0;
    let mut out = vec![];
    while p < o.stdout.len() {
        let n = get32(&o.stdout, &mut p) as usize;
        out.push(o.stdout[p..p + n].to_vec());
        p += n;
    }
    assert_eq!(out.len(), items.len());
    out
}
fn snapshot(map: &BTreeMap<Vec<u8>, Vec<u8>>) -> Vec<u8> {
    oracle("encode", &[packed(map)]).remove(0)
}
fn crc(b: &[u8]) -> u32 {
    let mut c = u32::MAX;
    for &v in b {
        c ^= v as u32;
        for _ in 0..8 {
            c = (c >> 1) ^ if c & 1 != 0 { 0xedb88320 } else { 0 };
        }
    }
    !c
}
fn checksum(b: &mut [u8]) {
    let at = b.len() - 4;
    let n = crc(&b[..at]);
    b[at..].copy_from_slice(&n.to_le_bytes());
}
fn raw_snapshot(entries: &[(Vec<u8>, Vec<u8>)]) -> Vec<u8> {
    let mut body = vec![];
    for (k, v) in entries {
        body.extend((k.len() as u32).to_le_bytes());
        body.extend((v.len() as u32).to_le_bytes());
        body.extend(k);
        body.extend(v);
    }
    let mut b = b"LANIKV\r\n".to_vec();
    for n in [1, entries.len() as u32, body.len() as u32, 0] {
        b.extend(n.to_le_bytes());
    }
    b.extend(body);
    b.extend(crc(&b).to_le_bytes());
    b
}
#[test]
fn ownership_native_views_aliases_and_replacement_outcomes_execute() {
    let exe = executable("kv_contracts");
    let o = common::process_output_with_timeout(
        "KV contracts",
        &mut Command::new(exe.path()),
        Duration::from_secs(10),
    );
    checked(&o);
    assert!(o.stdout.is_empty());
}
#[test]
fn generated_mutation_sequences_match_btree_model_and_independent_canonical_snapshots() {
    let mut state = BTreeMap::new();
    let mut seed = 0x6217u32;
    let mut commands = vec![];
    let mut expected = vec![];
    let mut snapshots = vec![];
    let mut snapshot_rows = vec![];
    for step in 0..700 {
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        let id = (seed >> 16) % 43;
        let key = if id == 0 {
            vec![]
        } else {
            let mut k = vec![0, 255];
            k.extend(vec![b'a'; (id % 13) as usize]);
            k.extend(id.to_le_bytes());
            k
        };
        seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
        let mode = if step < 43 { 0 } else { (seed >> 24) % 3 };
        let (detail, bytes) = match mode {
            0 => {
                let value: Vec<u8> = (0..(seed % 137))
                    .map(|i| ((seed >> 8) + i * 73) as u8)
                    .collect();
                let prior = state.insert(key.clone(), value.clone());
                commands.push(op(0, key, value));
                (if prior.is_some() { 2 } else { 1 }, vec![])
            }
            1 => {
                let found = state.remove(&key).is_some();
                commands.push(op(1, key, vec![]));
                (i32::from(found), vec![])
            }
            _ => {
                let value = state.get(&key);
                commands.push(op(2, key, vec![]));
                (
                    i32::from(value.is_some()),
                    value.cloned().unwrap_or_default(),
                )
            }
        };
        expected.push(Row {
            code: 0,
            detail,
            bytes,
        });
        if step % 11 == 0 {
            commands.push(op(3, vec![], vec![]));
            snapshot_rows.push(expected.len());
            snapshots.push(packed(&state));
            expected.push(Row {
                code: 0,
                detail: state.len() as i32,
                bytes: vec![],
            });
        }
    }
    for (index, bytes) in snapshot_rows.into_iter().zip(oracle("encode", &snapshots)) {
        expected[index].bytes = bytes;
    }
    let rows = run(&commands);
    for (i, (actual, want)) in rows.into_iter().zip(expected).enumerate() {
        assert_eq!(actual, want, "operation {i}: {:?}", commands[i]);
    }
    let mut big = BTreeMap::new();
    for i in 0..2048u32 {
        big.insert(i.to_be_bytes().to_vec(), vec![(i % 251) as u8; 257]);
    }
    let input = snapshot(&big);
    let rows = run(&[
        op(4, vec![], input.clone()),
        op(3, vec![], vec![]),
        op(2, 1024u32.to_be_bytes().to_vec(), vec![]),
    ]);
    assert_eq!(rows[0].code, 0);
    assert_eq!(rows[0].detail, 2048);
    assert_eq!(rows[1].bytes, input);
    assert_eq!(rows[2].bytes, big[&1024u32.to_be_bytes().to_vec()]);
    assert_eq!(
        oracle("decode", &[rows[1].bytes.clone()]),
        vec![packed(&big)]
    );
}
#[test]
fn corruption_truncations_duplicate_order_and_declared_sizes_are_rejected_atomically() {
    let initial = BTreeMap::from([(vec![99], vec![77])]);
    let saved = snapshot(&initial);
    let base = raw_snapshot(&[(vec![1], vec![2, 3]), (vec![4], vec![])]);
    let mut bad = vec![];
    for n in 0..base.len() {
        bad.push((base[..n].to_vec(), None));
    }
    for (at, value, code) in [(0, 0, 11), (8, 2, 12), (20, 1, 13)] {
        let mut b = base.clone();
        b[at] = value;
        checksum(&mut b);
        bad.push((b, Some(code)));
    }
    let mut b = base.clone();
    let n = b.len() - 1;
    b[n] ^= 1;
    bad.push((b, Some(14)));
    for (n, code) in [(0, 17), (1000, 10)] {
        let mut b = base.clone();
        b[16..20].copy_from_slice(&(n as u32).to_le_bytes());
        checksum(&mut b);
        bad.push((b, Some(code)));
    }
    let mut b = base.clone();
    b.push(0);
    bad.push((b, Some(17)));
    let mut b = base.clone();
    b[12..16].copy_from_slice(&3u32.to_le_bytes());
    checksum(&mut b);
    bad.push((b, Some(10)));
    for (at, n, code) in [(24, u32::MAX, 3), (28, u32::MAX, 4), (24, 100, 10)] {
        let mut b = base.clone();
        b[at..at + 4].copy_from_slice(&n.to_le_bytes());
        checksum(&mut b);
        bad.push((b, Some(code)));
    }
    bad.push((
        raw_snapshot(&[(vec![1], vec![]), (vec![1], vec![3])]),
        Some(16),
    ));
    bad.push((
        raw_snapshot(&[(vec![2], vec![]), (vec![1], vec![3])]),
        Some(15),
    ));
    let mut commands = vec![op(4, vec![], saved.clone())];
    for (b, _) in &bad {
        commands.push(op(4, vec![], b.clone()));
        commands.push(op(3, vec![], vec![]));
    }
    let rows = run(&commands);
    assert_eq!(rows[0].code, 0);
    for (i, (_, code)) in bad.iter().enumerate() {
        let row = &rows[1 + i * 2];
        if let Some(code) = code {
            assert_eq!(row.code, *code, "corruption {i}");
        } else {
            assert_ne!(row.code, 0, "prefix {i}");
        }
        assert!(row.bytes.is_empty());
        assert_eq!(
            rows[2 + i * 2].bytes,
            saved,
            "state changed on corruption {i}"
        );
    }
}
#[test]
fn exact_limits_work_and_resource_rejections_preserve_previous_state() {
    let initial = BTreeMap::from([(vec![1, 2], vec![3, 4, 5])]);
    let saved = snapshot(&initial);
    assert_eq!(saved.len(), 41);
    let exact = [1, 2, 3, 5, 41];
    let mut commands = vec![op(4, vec![], saved.clone())];
    let mut codes = vec![0];
    for index in 0..5 {
        let mut c = op(4, vec![], saved.clone());
        c.limits = exact;
        c.limits[index] -= 1;
        commands.push(c);
        codes.push(index as i32 + 2);
    }
    for index in 0..5 {
        let mut c = op(0, vec![1, 2], vec![3, 4, 5]);
        c.limits[index] = -1;
        commands.push(c);
        codes.push(1);
    }
    for work in [123, 124] {
        let mut c = op(3, vec![], vec![]);
        c.limits = exact;
        c.work = work;
        commands.push(c);
        codes.push(if work == 123 { 7 } else { 0 });
    }
    for work in [2, 3] {
        let mut c = op(2, vec![1, 2], vec![]);
        c.work = work;
        commands.push(c);
        codes.push(if work == 2 { 7 } else { 0 });
    }
    for work in [13, 14] {
        let mut c = op(0, vec![1, 2], vec![3, 4, 5]);
        c.limits = exact;
        c.work = work;
        commands.push(c);
        codes.push(if work == 13 { 7 } else { 0 });
    }
    let mut c = op(4, vec![], saved.clone());
    c.limits = exact;
    c.work = 124;
    commands.push(c);
    codes.push(0);
    let mut impossible = raw_snapshot(&[]);
    impossible[12..16].copy_from_slice(&(i32::MAX as u32).to_le_bytes());
    checksum(&mut impossible);
    let mut c = op(4, vec![], impossible);
    c.limits[0] = i32::MAX;
    commands.push(c);
    codes.push(9);
    commands.push(op(3, vec![], vec![]));
    codes.push(0);
    let rows = run(&commands);
    for (i, (row, code)) in rows.iter().zip(codes).enumerate() {
        assert_eq!(row.code, code, "limit command {i}: {:?}", commands[i]);
        if code != 0 {
            assert!(row.bytes.is_empty());
        }
    }
    assert_eq!(rows.last().unwrap().bytes, saved);
}
fn freed(events: &str) -> usize {
    let mut live = std::collections::BTreeSet::new();
    let mut n = 0;
    for line in events.lines() {
        if line.starts_with("mmap(") {
            let a = line.rsplit(" = ").next().unwrap();
            if a.starts_with("0x") {
                assert!(
                    live.insert(a.split_whitespace().next().unwrap().to_owned()),
                    "{events}"
                );
                n += 1;
            }
        } else if let Some(t) = line.strip_prefix("munmap(") {
            assert!(
                line.ends_with(" = 0") && live.remove(t.split(',').next().unwrap()),
                "{events}"
            );
        }
    }
    assert!(live.is_empty(), "leaked: {events}");
    n
}
#[test]
fn allocation_denial_on_mutation_decode_and_serialization_releases_owners_and_preserves_committed_state()
 {
    let initial = BTreeMap::from([(vec![1], vec![10, 11]), (vec![2], vec![20, 21])]);
    let saved = snapshot(&initial);
    let incoming = snapshot(&BTreeMap::from([(vec![99], vec![4; 1024])]));
    for action in [
        op(0, vec![1], vec![3; 700]),
        op(1, vec![1], vec![]),
        op(4, vec![], incoming),
        op(3, vec![], vec![]),
    ] {
        let commands = vec![op(4, vec![], saved.clone()), action, op(3, vec![], vec![])];
        let input = common::TempArtifact::new("laniusc_kv", "fault", None);
        input.write_bytes(frame(&commands));
        let trace = common::TempArtifact::new("laniusc_kv", "trace", None);
        let traced = |fail: Option<usize>| {
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
                "KV allocation denial",
                &mut cmd,
                Duration::from_secs(10),
            );
            checked(&o);
            let n = freed(&std::fs::read_to_string(trace.path()).unwrap());
            (parse(&o.stdout), n)
        };
        let (rows, n) = traced(None);
        assert!(rows.iter().all(|r| r.code == 0));
        assert!(n >= 3);
        for fail in 1..=n {
            let (rows, _) = traced(Some(fail));
            assert!(
                rows.iter().all(|r| r.code == 0 || r.code == 8),
                "failure {fail}: {rows:?}"
            );
            assert!(rows.iter().any(|r| r.code == 8));
            if rows[0].code == 0 && rows[1].code == 8 {
                assert_eq!(
                    rows[2].bytes, saved,
                    "mutation changed on failed allocation {fail}"
                );
            }
            for r in rows {
                if r.code != 0 {
                    assert!(r.bytes.is_empty());
                }
            }
        }
    }
}
fn application_group(group: &str) {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let output = common::process_output_with_timeout(
        format!("kv-tool {group}"),
        Command::new("python3")
            .arg(root.join("tests/fixtures/extended/kv_publication/oracle.py"))
            .arg(cli().path())
            .arg(group),
        Duration::from_secs(80),
    );
    checked(&output);
    let summary = String::from_utf8(output.stdout).unwrap();
    assert!(
        summary.starts_with(&format!("kv-application-{group} cases=")),
        "{summary}"
    );
    eprint!("{summary}");
}
#[test]
fn native_file_cli_round_trips_binary_values_and_replaces_only_validated_complete_snapshots() {
    application_group("roundtrips");
}
#[test]
fn native_cli_atomic_publication_races_faults_and_reached_allocations_report_visibility() {
    application_group("publication");
}
#[test]
fn native_cli_hierarchy_help_and_raw_path_routing_have_no_premature_file_effects() {
    application_group("hierarchy");
}
