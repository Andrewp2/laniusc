// Focused native integration through the GPU compiler: three canonical ELFs.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::{Command, Output},
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/collection_iterators")
        .join(name);
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_collection_iterator", name, None);
    // The unchanged common helper validates every x86 jump before writing ELF.
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn successful(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}

struct Words {
    values: std::vec::IntoIter<u64>,
}
impl Words {
    fn new(bytes: &[u8]) -> Self {
        assert_eq!(bytes.len() % 8, 0, "partial output word");
        Self {
            values: bytes
                .chunks_exact(8)
                .map(|chunk| u64::from_le_bytes(chunk.try_into().unwrap()))
                .collect::<Vec<_>>()
                .into_iter(),
        }
    }
    fn word(&mut self) -> u64 {
        self.values.next().expect("complete model response")
    }
    fn item(&mut self, width: usize) -> Option<Vec<u64>> {
        match self.word() {
            0 => None,
            1 => Some((0..width).map(|_| self.word()).collect()),
            tag => panic!("invalid item tag {tag}"),
        }
    }
    fn list(&mut self, width: usize) -> Vec<Vec<u64>> {
        let mut result = Vec::new();
        while let Some(item) = self.item(width) {
            result.push(item);
            assert!(result.len() <= 6, "fixture source has at most six items");
        }
        result
    }
    fn progress(&mut self, remaining: usize) {
        assert_eq!(self.word(), remaining as u64, "bounded source consumption");
        assert_eq!(
            self.word(),
            1,
            "limit 16 must observe None for these sources"
        );
    }
}

fn scalar_item(value: u64) -> Vec<u64> {
    vec![value]
}
fn tree_item(key: u64) -> Vec<u64> {
    vec![key, u64::MAX - key]
}

#[test]
fn collection_cursors_match_small_independent_sequence_models() {
    let mut cases = Vec::new();
    for length in 0_u64..=6 {
        for quota in 0..=length + 1 {
            for rotation in 0..length.max(1) {
                cases.push([0, length, rotation, quota]);
            }
            for lower in 0..=length {
                cases.push([1, length, lower, quota]);
            }
            for op in 2..=4 {
                cases.push([op, length, 0, quota]);
            }
        }
    }
    let input_bytes: Vec<u8> = cases
        .iter()
        .flat_map(|record| record.iter().flat_map(|value| value.to_le_bytes()))
        .collect();
    let input = common::TempArtifact::new("laniusc_collection_iterator", "model_input", None);
    input.write_bytes(input_bytes);
    let exe = executable("collections.lani");
    let output = common::process_output_with_timeout(
        "collection iterator sequence models",
        Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(20),
    );
    successful(&output);
    let mut actual = Words::new(&output.stdout);
    for (case_index, [op, length, rotation, quota]) in cases.iter().copied().enumerate() {
        if op <= 1 {
            // Build the logical finite sequence independently of cursor fields,
            // ring segmentation and tree links, then apply the call schedule.
            let mut sequence: VecDeque<u64> = if op == 0 {
                (0..length).collect()
            } else {
                (rotation..length).collect()
            };
            if op == 0 && length > 0 {
                sequence.rotate_left(rotation as usize);
            }
            let item = if op == 0 { scalar_item } else { tree_item };
            assert_eq!(
                actual.item(if op == 0 { 1 } else { 2 }),
                sequence.pop_back().map(item),
                "case {case_index}: first back item"
            );
            let count = sequence.len().min(quota as usize);
            let selected: Vec<_> = sequence.drain(..count).map(item).collect();
            assert_eq!(
                actual.list(if op == 0 { 1 } else { 2 }),
                selected,
                "case {case_index}: borrowed Take"
            );
            assert_eq!(
                actual.item(if op == 0 { 1 } else { 2 }),
                sequence.pop_back().map(item),
                "case {case_index}: interleaved back item"
            );
            actual.progress(sequence.len());
            assert_eq!(
                actual.word(),
                u64::from(op == 1),
                "case {case_index}: terminal state"
            );
        } else {
            // Hash order is unspecified. Require a duplicate-free subset of
            // the live keys and exact complete coverage when the quota fits.
            let live: BTreeSet<u64> = (0..length).filter(|key| key % 2 == 0).collect();
            let prefix = actual.list(if op == 2 { 5 } else { 1 });
            assert_eq!(
                prefix.len(),
                live.len().min(quota as usize),
                "case {case_index}"
            );
            let mut observed = BTreeSet::new();
            let mut order = Vec::new();
            for entry in prefix {
                let key = if op == 2 {
                    let key = entry[0]
                        .checked_sub(1_u64 << 32)
                        .expect("wide key retained");
                    assert_eq!(
                        entry[1..],
                        [u64::MAX - key, key, key * 7, u64::from(key % 4 == 0)],
                        "case {case_index}: compound Entry payload"
                    );
                    key
                } else {
                    entry[0]
                };
                assert!(
                    live.contains(&key),
                    "case {case_index}: unexpected/tombstone key {key}"
                );
                assert!(
                    observed.insert(key),
                    "case {case_index}: duplicate key {key}"
                );
                order.push(key);
            }
            if op == 4 {
                assert_eq!(
                    order,
                    live.iter()
                        .copied()
                        .take(quota as usize)
                        .collect::<Vec<_>>(),
                    "case {case_index}: ordered set"
                );
            }
            if quota as usize >= live.len() {
                assert_eq!(
                    observed, live,
                    "case {case_index}: complete source coverage"
                );
            }
            actual.progress(live.len() - observed.len());
        }
    }
    assert_eq!(actual.values.next(), None, "no extra model output");
    eprintln!(
        "{} independent collection iterator cases passed",
        cases.len()
    );
}

fn traced(exe: &common::TempArtifact, name: &str) -> String {
    let trace = common::TempArtifact::new("laniusc_collection_iterator", name, None);
    let output = common::process_output_with_timeout(
        name,
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    successful(&output);
    assert!(output.stdout.is_empty(), "{output:?}");
    std::fs::read_to_string(trace.path()).unwrap()
}

#[test]
fn text_and_bitset_sources_preserve_views_stride_and_fused_state_without_allocations() {
    let exe = executable("views.lani");
    let events = traced(&exe, "views_memory_trace");
    assert!(
        events.is_empty(),
        "view iteration must allocate nothing: {events}"
    );
}

#[test]
fn vec_items_borrow_string_storage_and_release_each_owner_once() {
    let exe = executable("owned_items.lani");
    let events = traced(&exe, "owned_memory_trace");
    let mut mappings = Vec::new();
    let mut live = BTreeMap::new();
    let mut released = Vec::new();
    for line in events.lines() {
        if let Some(args) = line.strip_prefix("mmap(") {
            let size: usize = args.split(", ").nth(1).unwrap().parse().unwrap();
            let address = line.rsplit_once(" = ").unwrap().1.to_owned();
            assert!(
                address.starts_with("0x"),
                "source allocations must succeed: {events}"
            );
            assert!(live.insert(address.clone(), size).is_none(), "{events}");
            mappings.push(address);
        } else if let Some(args) = line.strip_prefix("munmap(") {
            let (fields, result) = args.split_once(')').unwrap();
            let (address, size) = fields.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            assert_eq!(
                live.remove(address.trim()),
                Some(size),
                "one matching owner release: {events}"
            );
            assert_eq!(result.trim(), "= 0", "{events}");
            released.push(address.trim().to_owned());
        } else {
            panic!("unexpected memory trace: {events}");
        }
    }
    assert_eq!(
        mappings.len(),
        2,
        "only the String and Vec may allocate: {events}"
    );
    assert!(
        live.is_empty(),
        "every owner allocation must be released: {events}"
    );
    assert_eq!(
        released,
        [mappings[1].clone(), mappings[0].clone()],
        "Vec storage is released before its borrowed String items: {events}"
    );
}
