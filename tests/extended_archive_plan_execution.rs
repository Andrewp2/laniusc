//! Pure archive namespace planning against an independent byte-path model.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    collections::BTreeMap,
    fs,
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join("tests/fixtures/extended/archive_plan").join(name);
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
    let exe = common::TempArtifact::new("laniusc_archive_plan", name, None);
    exe.write_bytes(bytes);
    fs::set_permissions(exe.path(), fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
#[derive(Clone, Debug)]
struct Case {
    caps: [i32; 6],
    ops: Vec<(bool, i32, Vec<u8>)>,
}
fn case(ops: Vec<(bool, Vec<u8>)>) -> Case {
    Case {
        caps: [32, 96, 96, 32, 12, 4096],
        ops: ops
            .into_iter()
            .enumerate()
            .map(|(i, (d, p))| (d, i as i32, p))
            .collect(),
    }
}
#[derive(Clone, Debug, PartialEq, Eq)]
struct Failure {
    code: i64,
    ordinal: i64,
    offset: i64,
}
#[derive(Clone, Debug, PartialEq, Eq)]
struct Node {
    fields: [i64; 9],
    path: Vec<u8>,
    component: Vec<u8>,
}
#[derive(Default)]
struct Model {
    nodes: Vec<Node>,
    by_path: BTreeMap<Vec<u8>, usize>,
    entries: Vec<usize>,
    stored: usize,
    failure: Option<Failure>,
}
impl Model {
    fn add(
        &mut self,
        caps: &[i32; 6],
        directory: bool,
        ordinal: i32,
        input: &[u8],
    ) -> Result<usize, Failure> {
        if let Some(e) = &self.failure {
            return Err(e.clone());
        }
        let result = self.checked_add(caps, directory, ordinal, input);
        if let Err(e) = &result {
            self.failure = Some(e.clone());
        }
        result
    }
    fn checked_add(
        &mut self,
        c: &[i32; 6],
        directory: bool,
        ordinal: i32,
        input: &[u8],
    ) -> Result<usize, Failure> {
        let fail = |code, offset| Failure {
            code,
            ordinal: ordinal as i64,
            offset: offset as i64,
        };
        if ordinal != self.entries.len() as i32 {
            return Err(fail(13, -1));
        }
        if self.entries.len() == c[0] as usize {
            return Err(fail(6, -1));
        }
        let path = if directory && input.last() == Some(&b'/') {
            &input[..input.len() - 1]
        } else {
            input
        };
        if path.is_empty() {
            return Err(fail(3, 0));
        }
        if path.len() > c[2] as usize {
            return Err(fail(3, c[2]));
        }
        if path[0] == b'/' {
            return Err(fail(3, 0));
        }
        if path.get(1) == Some(&b':') {
            return Err(fail(3, 1));
        }
        if !directory && path.last() == Some(&b'/') {
            return Err(fail(3, path.len() as i32 - 1));
        }
        let mut parts = vec![];
        let mut start = 0;
        for (depth, component) in path.split(|b| *b == b'/').enumerate() {
            if let Some(at) = component.iter().position(|b| *b == 0 || *b == b'\\') {
                return Err(fail(3, (start + at) as i32));
            }
            if component.is_empty() {
                return Err(fail(4, start as i32));
            }
            if component.len() > c[3] as usize {
                return Err(fail(4, start as i32 + c[3]));
            }
            if component == b"." || component == b".." {
                return Err(fail(4, start as i32));
            }
            if depth == c[4] as usize {
                return Err(fail(5, start as i32));
            }
            let end = start + component.len();
            parts.push((path[..end].to_vec(), component.to_vec(), start));
            start = end + 1;
        }
        // The oracle uses complete byte-prefix identities, not the production
        // planner's parent/component table scan or its work algorithm.
        let mut added = 0;
        let mut stored = 0;
        for (position, (prefix, _, offset)) in parts.iter().enumerate() {
            let last = position + 1 == parts.len();
            if let Some(&id) = self.by_path.get(prefix) {
                let n = &self.nodes[id];
                if (!last && n.fields[1] == 0) || (last && (n.fields[1] != i64::from(directory))) {
                    return Err(fail(11, *offset as i32));
                }
                if last && n.fields[2] != 0 {
                    return Err(fail(10, *offset as i32));
                }
            } else {
                added += 1;
                stored += prefix.len();
                if self.nodes.len() + added > c[1] as usize {
                    return Err(fail(7, *offset as i32));
                }
                if self.stored + stored > c[5] as usize {
                    return Err(fail(8, *offset as i32));
                }
            }
        }
        let mut parent = -1;
        let mut target = 0;
        for (position, (prefix, component, _)) in parts.into_iter().enumerate() {
            let last = prefix.len() == path.len();
            let id = if let Some(&id) = self.by_path.get(&prefix) {
                if last {
                    self.nodes[id].fields[2] = 1;
                    self.nodes[id].fields[3] = ordinal as i64;
                }
                id
            } else {
                let id = self.nodes.len();
                let start = self.stored;
                self.stored += prefix.len();
                let fields = [
                    parent,
                    if last { i64::from(directory) } else { 1 },
                    i64::from(last),
                    if last { ordinal as i64 } else { -1 },
                    start as i64,
                    prefix.len() as i64,
                    (start + prefix.len() - component.len()) as i64,
                    component.len() as i64,
                    (position + 1) as i64,
                ];
                self.by_path.insert(prefix.clone(), id);
                self.nodes.push(Node {
                    fields,
                    path: prefix,
                    component,
                });
                id
            };
            parent = id as i64;
            target = id;
        }
        self.entries.push(target);
        Ok(target)
    }
}
fn push(out: &mut Vec<u8>, value: i64) {
    out.extend_from_slice(&(value as u64).to_le_bytes());
}
struct Decoder {
    bytes: Vec<u8>,
    at: usize,
}
impl Decoder {
    fn word(&mut self) -> i64 {
        let value = i64::from_le_bytes(self.bytes[self.at..self.at + 8].try_into().unwrap());
        self.at += 8;
        value
    }
    fn raw(&mut self, count: usize) -> Vec<u8> {
        let value = self.bytes[self.at..self.at + count].to_vec();
        self.at += count;
        value
    }
    fn row(&mut self, expected: Result<usize, Failure>, model: &Model, previous: &mut u64) {
        let code = self.word();
        let ordinal = self.word();
        let offset = self.word();
        let value = self.word();
        match expected {
            Ok(index) => assert_eq!((code, ordinal, offset, value), (0, -1, -1, index as i64)),
            Err(e) => assert_eq!(
                (code, ordinal, offset, value),
                (e.code, e.ordinal, e.offset, -1)
            ),
        }
        assert_eq!(self.word(), model.nodes.len() as i64);
        assert_eq!(self.word(), model.entries.len() as i64);
        let work = self.word() as u64;
        assert!(work >= *previous && work <= 1_000_000_000);
        if model.failure.is_some() && *previous != 0 {
            assert_eq!(work, *previous);
        }
        *previous = work;
    }
}
fn cases() -> Vec<Case> {
    let mut result = vec![
        case(vec![
            (false, b"a/b".to_vec()),
            (true, b"a/".to_vec()),
            (false, b"a/c".to_vec()),
            (true, b"empty/".to_vec()),
        ]),
        case(vec![
            (false, vec![255, b'/', 128]),
            (false, b"A".to_vec()),
            (false, b"a".to_vec()),
            (false, b"left/b:c".to_vec()),
        ]),
    ];
    for (a, b) in [(false, false), (false, true), (true, false), (true, true)] {
        result.push(case(vec![
            (a, b"d".to_vec()),
            (b, b"d".to_vec()),
            (false, b"after".to_vec()),
        ]));
    }
    result.push(case(vec![(false, b"a".to_vec()), (false, b"a/b".to_vec())]));
    result.push(case(vec![(false, b"a/b".to_vec()), (false, b"a".to_vec())]));
    for (dir, p) in [
        (false, b"".as_slice()),
        (false, b"/abs"),
        (false, b"a\\b"),
        (false, b"a\0b"),
        (false, b"C:x"),
        (false, b"a//b"),
        (false, b"./a"),
        (false, b"a/../b"),
        (true, b"d//"),
        (false, b"d/"),
        (true, b"."),
        (false, b".."),
    ] {
        result.push(case(vec![
            (false, b"kept".to_vec()),
            (dir, p.to_vec()),
            (false, b"after".to_vec()),
        ]));
    }
    for (field, value) in [(0, 0), (1, 1), (2, 2), (3, 0), (4, 1), (5, 3)] {
        let mut c = case(vec![(false, b"a/b".to_vec())]);
        c.caps[field] = value;
        result.push(c);
    }
    let mut exact = case(vec![(false, b"a/b".to_vec())]);
    exact.caps = [1, 2, 3, 1, 2, 4];
    result.push(exact);
    let mut wrong = case(vec![(false, b"a".to_vec())]);
    wrong.ops[0].1 = 1;
    result.push(wrong);
    // Reproducible varied valid trees and later conflicts; no timing/random OS oracle.
    let mut seed = 0x71a23d99u32;
    for _ in 0..48 {
        let mut ops = vec![];
        for _ in 0..20 {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            let mut path = vec![b'a' + ((seed >> 24) % 5) as u8];
            if seed & 3 != 0 {
                path.extend_from_slice(&[b'/', b'k' + ((seed >> 16) % 4) as u8]);
            }
            if seed & 12 == 12 {
                path.extend_from_slice(&[b'/', 128 + ((seed >> 8) % 8) as u8]);
            }
            let dir = seed & 16 != 0;
            if dir && seed & 32 != 0 {
                path.push(b'/');
            }
            ops.push((dir, path));
        }
        result.push(case(ops));
    }
    result
}
#[test]
fn namespace_model_paths_limits_and_sticky_failures_execute() {
    let contracts = executable("contracts.lani");
    let trace = common::TempArtifact::new("laniusc_archive_plan", "contracts-trace", None);
    let out = common::process_output_with_timeout(
        "archive planner contracts",
        Command::new("strace")
            .args(["-qq", "-i", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(contracts.path()),
        Duration::from_secs(15),
    );
    common::assert_command_success("archive planner contracts", &out);
    assert!(out.stdout.is_empty() && out.stderr.is_empty());
    ledger(&fs::read_to_string(trace.path()).unwrap());
    let model_exe = executable("model.lani");
    let cases = cases();
    let mut input = vec![];
    push(&mut input, cases.len() as i64);
    for c in &cases {
        for value in c.caps {
            push(&mut input, value as i64);
        }
        push(&mut input, 1_000_000_000);
        push(&mut input, c.ops.len() as i64);
        for (dir, ordinal, path) in &c.ops {
            push(&mut input, i64::from(*dir));
            push(&mut input, *ordinal as i64);
            push(&mut input, path.len() as i64);
            input.extend(path);
        }
    }
    let file = common::TempArtifact::new("laniusc_archive_plan", "input", None);
    file.write_bytes(input);
    let out = common::process_output_with_timeout(
        "archive planner independent namespace model",
        Command::new(model_exe.path()).stdin(fs::File::open(file.path()).unwrap()),
        Duration::from_secs(15),
    );
    common::assert_command_success("archive planner model", &out);
    assert!(out.stderr.is_empty());
    let mut wire = Decoder {
        bytes: out.stdout,
        at: 0,
    };
    for c in &cases {
        let mut model = Model::default();
        let mut work = 0;
        for (dir, ordinal, path) in &c.ops {
            let prior_failure = model.failure.is_some();
            let expected = model.add(&c.caps, *dir, *ordinal, path);
            // The first rejection may spend validation work; only subsequent
            // poisoned calls must leave the exact work count unchanged.
            let previous = work;
            let mut observed = if prior_failure { work } else { 0 };
            wire.row(expected, &model, &mut observed);
            assert!(observed >= previous);
            if prior_failure {
                assert_eq!(observed, previous);
            }
            work = observed;
        }
        let before_seal = work;
        let failed = model.failure.is_some();
        let sealed = model.failure.clone().map_or(Ok(model.entries.len()), Err);
        wire.row(sealed, &model, &mut work);
        if failed {
            assert_eq!(work, before_seal);
        }
        assert_eq!(wire.word(), model.nodes.len() as i64);
        for node in &model.nodes {
            let fields: [i64; 9] = std::array::from_fn(|_| wire.word());
            assert_eq!(fields, node.fields);
            assert_eq!(wire.raw(node.path.len()), node.path);
            assert_eq!(wire.raw(node.component.len()), node.component);
        }
        assert_eq!(wire.word(), model.entries.len() as i64);
        for entry in &model.entries {
            assert_eq!(wire.word(), *entry as i64);
        }
        assert_eq!(wire.word(), i64::from(model.failure.is_none()));
        assert!(wire.word() >= c.caps[5] as i64);
    }
    assert_eq!(wire.at, wire.bytes.len());
    eprintln!("archive-plan independent namespace cases={}", cases.len());
}
#[derive(Clone, Debug, PartialEq, Eq)]
struct Attempt {
    ip: String,
    args: String,
    size: usize,
    failed: bool,
}
fn ledger(events: &str) -> Vec<Attempt> {
    let mut live = BTreeMap::new();
    let mut attempts = vec![];
    for line in events.lines() {
        let (ip, call) = line
            .split_once("] ")
            .unwrap_or_else(|| panic!("missing exact syscall IP: {line}"));
        if let Some(body) = call.strip_prefix("mmap(") {
            let (args, result) = body.rsplit_once(" = ").unwrap();
            let args = args.trim_end().strip_suffix(')').unwrap();
            let size = args
                .split(',')
                .nth(1)
                .unwrap()
                .trim()
                .parse::<usize>()
                .unwrap();
            let failed = !result.starts_with("0x");
            attempts.push(Attempt {
                ip: ip.to_owned(),
                args: args.to_owned(),
                size,
                failed,
            });
            if failed {
                assert!(
                    result.starts_with("-1 ENOMEM ") && result.contains("INJECTED"),
                    "{line}"
                );
            } else {
                let address = result.split_whitespace().next().unwrap();
                assert!(live.insert(address.to_owned(), size).is_none(), "{line}");
            }
        } else if let Some(body) = call.strip_prefix("munmap(") {
            let (args, result) = body.rsplit_once(" = ").unwrap();
            assert_eq!(result, "0");
            let args = args.trim_end().strip_suffix(')').unwrap();
            let mut parts = args.split(',');
            let address = parts.next().unwrap().trim();
            let bytes = parts.next().unwrap().trim().parse::<usize>().unwrap();
            assert_eq!(live.remove(address), Some(bytes), "{line}");
        } else {
            panic!("unexpected mapping event: {line}");
        }
    }
    assert!(live.is_empty(), "live requested mappings: {live:?}");
    attempts
}
#[test]
fn reserved_storage_allocation_failures_release_partial_plans() {
    let exe = executable("allocations.lani");
    let trace = common::TempArtifact::new("laniusc_archive_plan", "allocation-trace", None);
    let run = |failure: Option<usize>| {
        let mut command = Command::new("strace");
        command
            .args(["-qq", "-i", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"]);
        if let Some(n) = failure {
            command.args(["-e", &format!("inject=mmap:error=ENOMEM:when={n}")]);
        }
        command.arg(exe.path());
        let out = common::process_output_with_timeout(
            "archive planner allocation owners",
            &mut command,
            Duration::from_secs(10),
        );
        assert!(out.stderr.is_empty(), "{out:?}");
        let events = ledger(&fs::read_to_string(trace.path()).unwrap());
        (out, events)
    };
    let (out, baseline) = run(None);
    common::assert_command_success("archive planner allocation baseline", &out);
    assert_eq!(
        baseline.len(),
        3,
        "three fixed-capacity owners; no growth during add/seal"
    );
    assert_eq!(out.stdout.len(), 8);
    let reserved = u64::from_le_bytes(out.stdout.try_into().unwrap());
    assert_eq!(
        reserved,
        baseline.iter().map(|a| a.size as u64).sum::<u64>()
    );
    assert_eq!(baseline[1].size, 96);
    assert_eq!(baseline[2].size, 3 * std::mem::size_of::<i32>());
    for n in 1..=baseline.len() {
        let (out, observed) = run(Some(n));
        assert_eq!(out.status.code(), Some(4));
        assert!(out.stdout.is_empty());
        assert_eq!(observed.len(), n);
        for (i, (actual, original)) in observed.iter().zip(&baseline).enumerate() {
            assert_eq!(
                (&actual.ip, &actual.args),
                (&original.ip, &original.args),
                "same source instruction/request prefix before reached failure{n}"
            );
            assert_eq!(actual.failed, i + 1 == n);
        }
    }
    eprintln!("archive-plan allocation cases=4 reached-source-oom=3");
}
