//! Focused native heap cursor integration through the GPU compiler.
#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::{BTreeMap, VecDeque},
    os::unix::fs::PermissionsExt,
    path::PathBuf,
    process::Command,
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root
        .join("tests/fixtures/stdlib_foundation/heap_iterators")
        .join(name);
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_heap_iterator", name, None);
    // Preserve the common strict x86 jump checks before publishing the ELF.
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

struct Words(std::vec::IntoIter<u64>);
impl Words {
    fn new(bytes: &[u8]) -> Self {
        assert_eq!(bytes.len() % 8, 0, "partial fixture output word");
        Self(
            bytes
                .chunks_exact(8)
                .map(|chunk| u64::from_le_bytes(chunk.try_into().unwrap()))
                .collect::<Vec<_>>()
                .into_iter(),
        )
    }
    fn word(&mut self) -> u64 {
        self.0.next().expect("complete fixture response")
    }
    fn item<const N: usize>(&mut self) -> Option<[u64; N]> {
        match self.word() {
            0 => None,
            1 => Some(std::array::from_fn(|_| self.word())),
            tag => panic!("invalid item tag {tag}"),
        }
    }
    fn list<const N: usize>(&mut self) -> Vec<[u64; N]> {
        let mut items = Vec::new();
        while let Some(item) = self.item() {
            items.push(item);
            assert!(items.len() <= 6, "a fixture heap has at most six entries");
        }
        items
    }
}

fn payload(index: u64) -> [u64; 7] {
    let identity = index.min(4);
    let priority: i64 = match identity {
        0 | 2 => -4_294_967_299,
        3 => 4_294_967_297,
        _ => 7,
    };
    [
        priority as u64,
        u64::MAX - identity,
        identity,
        128 + identity,
        0,
        255 - identity,
        if identity == 2 {
            0 // None
        } else if identity % 2 == 0 {
            2 // Some(true)
        } else {
            1 // Some(false)
        },
    ]
}

#[test]
fn heap_cursors_and_adapters_match_independent_multisets() {
    let exe = executable("contracts.lani");
    let output = common::process_output_with_timeout(
        "heap iterator multisets and cursor composition",
        &mut Command::new(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    let mut words = Words::new(&output.stdout);
    for direction in 0..2_u64 {
        for length in 0..=6_u64 {
            for quota in [0, 2, 8_u64] {
                let case = format!("direction={direction}, length={length}, quota={quota}");
                assert_eq!(words.word(), direction, "{case}: initial order");
                assert_eq!(words.word(), length, "{case}: initial length");
                assert_eq!(words.word(), quota, "{case}: selected quota");
                let peek = words.item::<7>();
                let mut expected: Vec<_> = (0..length).map(payload).collect();
                if let Some(item) = peek {
                    assert!(expected.contains(&item), "{case}: peek is a stored entry");
                    let expected_priority = if direction == 0 {
                        expected.iter().map(|entry| entry[0] as i64).min()
                    } else {
                        expected.iter().map(|entry| entry[0] as i64).max()
                    };
                    assert_eq!(Some(item[0] as i64), expected_priority, "{case}: priority");
                } else {
                    assert_eq!(length, 0, "{case}: only an empty heap has no peek");
                }

                // Heap array order is unspecified. Require the complete input
                // multiset, including equal entries and all compound fields.
                let observed = words.list::<7>();
                let mut sorted = observed.clone();
                sorted.sort_unstable();
                expected.sort_unstable();
                assert_eq!(sorted, expected, "{case}: complete item multiset");

                // A fresh cursor must traverse the same unchanged storage.
                // Use the observed sequence solely to check positions and
                // adapter consumption, without choosing a heap layout.
                let mut remaining: VecDeque<_> = observed.iter().copied().collect();
                assert_eq!(words.item::<7>(), remaining.pop_back(), "{case}: back");
                assert_eq!(words.item::<7>(), remaining.pop_front(), "{case}: front");
                let count = remaining.len().min(quota as usize);
                let prefix: Vec<_> = remaining.drain(..count).collect();
                assert_eq!(words.list::<7>(), prefix, "{case}: generic Take");
                let mapped: Vec<_> = remaining.iter().map(|item| [item[2], item[1]]).collect();
                assert_eq!(words.list::<2>(), mapped, "{case}: generic Map");
                assert_eq!(words.word(), remaining.len() as u64, "{case}: mapper calls");
                assert_eq!(
                    words.item::<7>(),
                    observed.first().copied(),
                    "{case}: copy retains an independent front"
                );
                assert_eq!(words.word(), length.saturating_sub(1), "{case}: copy range");
                assert_eq!(words.word(), direction, "{case}: unchanged heap order");
                assert_eq!(words.word(), length, "{case}: unchanged heap length");
                assert_eq!(words.item::<7>(), peek, "{case}: unchanged complete peek");
            }
        }
    }
    assert_eq!(words.0.next(), None, "no trailing fixture output");
}

#[test]
fn heap_iterator_string_aliases_release_only_explicit_owners() {
    let exe = executable("owned_items.lani");
    let trace = common::TempArtifact::new("laniusc_heap_iterator", "owner_trace", None);
    let output = common::process_output_with_timeout(
        "heap iterator String aliases and explicit owner releases",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args(["-e", "trace=mmap,munmap"])
            .arg(exe.path()),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    let events = std::fs::read_to_string(trace.path()).unwrap();
    let mut allocated = Vec::new();
    let mut live = BTreeMap::new();
    let mut released = Vec::new();
    for line in events.lines() {
        if let Some(args) = line.strip_prefix("mmap(") {
            let size: usize = args.split(", ").nth(1).unwrap().parse().unwrap();
            let address = line.rsplit_once(" = ").unwrap().1.to_owned();
            assert!(
                address.starts_with("0x"),
                "allocation must succeed: {events}"
            );
            assert!(live.insert(address.clone(), size).is_none(), "{events}");
            allocated.push(address);
        } else if let Some(args) = line.strip_prefix("munmap(") {
            let (fields, result) = args.split_once(')').unwrap();
            let (address, size) = fields.split_once(',').unwrap();
            let size: usize = size.trim().parse().unwrap();
            assert_eq!(
                live.remove(address.trim()),
                Some(size),
                "each explicit owner releases its matching address and size once: {events}"
            );
            assert_eq!(result.trim(), "= 0", "{events}");
            released.push(address.trim().to_owned());
        } else {
            panic!("unexpected memory trace: {events}");
        }
    }
    assert_eq!(
        allocated.len(),
        2,
        "only String and heap storage allocate: {events}"
    );
    assert!(
        live.is_empty(),
        "all explicit owners must be released: {events}"
    );
    assert_eq!(
        released,
        [allocated[1].clone(), allocated[0].clone()],
        "heap storage is released before its externally owned String aliases: {events}"
    );
}
