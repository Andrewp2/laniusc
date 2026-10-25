#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{
    collections::{BTreeMap, BTreeSet},
    os::unix::fs::PermissionsExt,
    process::Command,
    time::Duration,
};

fn executable(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/extended_library/{name}.lani"));
    let roots = laniusc_compiler::compiler::EntrySourceRoots {
        stdlib_root: Some(root.join("stdlib")),
        user_roots: vec![root.join("extended")],
    };
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_source_roots(&entry, &roots),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_unicode_normalize", name, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn ucd(name: &str) -> String {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("data/unicode/17.0.0")
        .join(format!("{name}.gz"));
    let output =
        common::short_process_output_with_timeout(name, Command::new("gzip").arg("-dc").arg(path));
    assert!(output.status.success());
    String::from_utf8(output.stdout).unwrap()
}

#[test]
fn normalization_bounds_capacity_work_utf8_and_atomicity_without_allocation() {
    let exe = executable("unicode_normalize_contracts");
    let trace = common::TempArtifact::new("laniusc_unicode_normalize", "trace", None);
    let output = common::short_process_output_with_timeout(
        "normalization contracts",
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
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    let check = common::short_process_output_with_timeout(
        "normalization tables regenerate exactly",
        Command::new("python3")
            .arg("tools/unicode17/generate_normalization.py")
            .arg("--check")
            .current_dir(env!("CARGO_MANIFEST_DIR")),
    );
    assert!(check.status.success(), "{check:?}");
}

#[derive(Debug)]
enum Expected {
    Normalized(Vec<u8>, usize),
    Checked(bool),
    Error(u32, u64),
}
#[derive(Debug)]
struct Case {
    form: u8,
    input: Vec<u8>,
    scratch: u16,
    capacity: u16,
    limit: u64,
    expected: Expected,
}
impl Case {
    fn normalized(form: u8, input: &[u8], output: &[u8], scratch: usize) -> Self {
        Self {
            form,
            input: input.to_vec(),
            scratch: scratch.try_into().unwrap(),
            capacity: output.len().try_into().unwrap(),
            limit: 1_000_000,
            expected: Expected::Normalized(output.to_vec(), scratch),
        }
    }
    fn checked(form: u8, input: &[u8], expected: bool, scratch: usize) -> Self {
        Self {
            form,
            input: input.to_vec(),
            scratch: scratch.try_into().unwrap(),
            capacity: 0,
            limit: 1_000_000,
            expected: Expected::Checked(expected),
        }
    }
}

fn run_cases(exe: &common::TempArtifact, cases: &[Case]) {
    let mut request = Vec::new();
    for case in cases {
        assert!(case.input.len() <= 4096 && case.scratch <= 1024 && case.capacity <= 4096);
        request.push(case.form);
        request.push(u8::from(matches!(case.expected, Expected::Checked(_))));
        request.extend_from_slice(&(case.input.len() as u16).to_le_bytes());
        request.extend_from_slice(&case.scratch.to_le_bytes());
        request.extend_from_slice(&case.capacity.to_le_bytes());
        request.extend_from_slice(&case.limit.to_le_bytes());
        request.extend_from_slice(&case.input);
    }
    let input = common::TempArtifact::new("laniusc_unicode_normalize", "request", None);
    input.write_bytes(&request);
    let output = common::process_output_with_timeout(
        "normalization conformance batch",
        Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(90),
    );
    assert_eq!(
        output.status.code(),
        Some(0),
        "status: {:?}; stderr: {}",
        output.status,
        String::from_utf8_lossy(&output.stderr)
    );
    assert!(output.stderr.is_empty());
    let mut position = 0;
    for (index, case) in cases.iter().enumerate() {
        let header = output
            .stdout
            .get(position..position + 32)
            .unwrap_or_else(|| panic!("case {index}: missing header: {case:?}"));
        let u32_at = |at| u32::from_le_bytes(header[at..at + 4].try_into().unwrap());
        let code = u32_at(0);
        let detail = u64::from_le_bytes(header[4..12].try_into().unwrap());
        let length = u32_at(12) as usize;
        let scalars = u32_at(16) as usize;
        let scratch = u32_at(20) as usize;
        let work = u64::from_le_bytes(header[24..32].try_into().unwrap());
        position += 32;
        let actual = output.stdout.get(position..position + length).unwrap();
        match &case.expected {
            Expected::Normalized(bytes, required) => {
                assert_eq!(
                    (code, detail, scratch),
                    (0, 0, *required),
                    "case {index}: {case:?}"
                );
                assert_eq!(actual, bytes, "case {index}: {case:?}");
                assert_eq!(scalars, std::str::from_utf8(bytes).unwrap().chars().count());
                assert!(work <= case.limit);
            }
            Expected::Checked(value) => assert_eq!(
                (code, detail, length),
                (0, u64::from(*value), 0),
                "case {index}: {case:?}"
            ),
            Expected::Error(expected_code, expected_detail) => assert_eq!(
                (code, detail, length),
                (*expected_code, *expected_detail, 0),
                "case {index}: {case:?}"
            ),
        }
        position += length;
    }
    assert_eq!(position, output.stdout.len());
}

fn scalars(field: &str) -> Vec<u32> {
    field
        .split_whitespace()
        .map(|x| u32::from_str_radix(x, 16).unwrap())
        .collect()
}
fn bytes(values: &[u32]) -> Vec<u8> {
    values
        .iter()
        .map(|&x| char::from_u32(x).unwrap())
        .collect::<String>()
        .into_bytes()
}

#[test]
fn complete_unicode17_normalization_test_and_every_unlisted_scalar_conform() {
    let exe = executable("unicode_normalize_model");
    let source = ucd("NormalizationTest.txt");
    assert!(source.contains("NormalizationTest-17.0.0.txt"));
    let mut cases = Vec::new();
    let mut listed = BTreeSet::new();
    let mut part_one = false;
    let mut rows = 0;
    for raw in source.lines() {
        let line = raw.split('#').next().unwrap().trim();
        if line.starts_with('@') {
            part_one = line.starts_with("@Part1");
            continue;
        }
        if line.is_empty() {
            continue;
        }
        let columns: Vec<_> = line.split(';').take(5).map(scalars).collect();
        assert_eq!(columns.len(), 5);
        if part_one {
            assert_eq!(columns[0].len(), 1);
            listed.insert(columns[0][0]);
        }
        let encoded: Vec<_> = columns.iter().map(|x| bytes(x)).collect();
        for form in 0..4 {
            for input in 0..5 {
                let expected = match form {
                    0 => {
                        if input < 3 {
                            1
                        } else {
                            3
                        }
                    }
                    1 => {
                        if input < 3 {
                            2
                        } else {
                            4
                        }
                    }
                    2 => 3,
                    _ => 4,
                };
                let decomposition = if form < 2 && input < 3 { 2 } else { 4 };
                cases.push(Case::normalized(
                    form,
                    &encoded[input],
                    &encoded[expected],
                    columns[decomposition].len(),
                ));
                if rows % 37 == 0 {
                    cases.push(Case::checked(
                        form,
                        &encoded[input],
                        encoded[input] == encoded[expected],
                        columns[decomposition].len(),
                    ));
                }
            }
        }
        rows += 1;
    }
    assert!(rows > 19_000 && listed.len() > 10_000);
    // UAX #15 conformance also requires all scalars absent from Part 1 to
    // remain unchanged. NUL separates scalars so no cross-scalar composition
    // or canonical reordering can hide their individual result.
    let mut batch = Vec::new();
    for value in 0..=0x10FFFF {
        if char::from_u32(value).is_none() || listed.contains(&value) {
            continue;
        }
        batch.extend([value, 0]);
        if batch.len() == 1024 {
            let encoded = bytes(&batch);
            for form in 0..4 {
                cases.push(Case::normalized(form, &encoded, &encoded, batch.len()));
            }
            batch.clear();
        }
    }
    if !batch.is_empty() {
        let encoded = bytes(&batch);
        for form in 0..4 {
            cases.push(Case::normalized(form, &encoded, &encoded, batch.len()));
        }
    }
    run_cases(&exe, &cases);
}

struct Model {
    ccc: BTreeMap<u32, u8>,
    decomposition: BTreeMap<u32, (bool, Vec<u32>)>,
    composition: BTreeMap<(u32, u32), u32>,
}
impl Model {
    fn new() -> Self {
        let mut model = Self {
            ccc: BTreeMap::new(),
            decomposition: BTreeMap::new(),
            composition: BTreeMap::new(),
        };
        for line in ucd("UnicodeData.txt").lines() {
            let fields: Vec<_> = line.split(';').collect();
            let value = u32::from_str_radix(fields[0], 16).unwrap();
            let ccc = fields[3].parse().unwrap();
            if ccc != 0 {
                model.ccc.insert(value, ccc);
            }
            if !fields[5].is_empty() {
                let compatibility = fields[5].starts_with('<');
                let mapping = if compatibility {
                    fields[5].split_once(' ').unwrap().1
                } else {
                    fields[5]
                };
                model
                    .decomposition
                    .insert(value, (compatibility, scalars(mapping)));
            }
        }
        let mut exclusions = BTreeSet::new();
        for line in ucd("DerivedNormalizationProps.txt").lines() {
            let fields: Vec<_> = line
                .split('#')
                .next()
                .unwrap()
                .split(';')
                .map(str::trim)
                .collect();
            if fields.get(1) == Some(&"Full_Composition_Exclusion") {
                let range: Vec<_> = fields[0]
                    .split("..")
                    .map(|x| u32::from_str_radix(x, 16).unwrap())
                    .collect();
                exclusions.extend(range[0]..=*range.last().unwrap());
            }
        }
        for (&value, (compatibility, mapping)) in &model.decomposition {
            if !compatibility && !exclusions.contains(&value) {
                assert_eq!(mapping.len(), 2);
                assert!(
                    model
                        .composition
                        .insert((mapping[0], mapping[1]), value)
                        .is_none()
                );
            }
        }
        model
    }
    fn ccc(&self, value: u32) -> u8 {
        self.ccc.get(&value).copied().unwrap_or(0)
    }
    fn expand(&self, value: u32, compatibility: bool, output: &mut Vec<u32>) {
        if (0xAC00..0xD7A4).contains(&value) {
            let offset = value - 0xAC00;
            output.extend([0x1100 + offset / 588, 0x1161 + offset % 588 / 28]);
            if offset % 28 != 0 {
                output.push(0x11A7 + offset % 28);
            }
        } else if let Some((kind, mapping)) = self
            .decomposition
            .get(&value)
            .filter(|(kind, _)| compatibility || !kind)
        {
            let _ = kind;
            for &part in mapping {
                self.expand(part, compatibility, output);
            }
        } else {
            output.push(value);
        }
    }
    fn composite(&self, left: u32, right: u32) -> Option<u32> {
        if (0x1100..0x1113).contains(&left) && (0x1161..0x1176).contains(&right) {
            Some(0xAC00 + (left - 0x1100) * 588 + (right - 0x1161) * 28)
        } else if (0xAC00..0xD7A4).contains(&left)
            && (left - 0xAC00) % 28 == 0
            && (0x11A8..0x11C3).contains(&right)
        {
            Some(left + right - 0x11A7)
        } else {
            self.composition.get(&(left, right)).copied()
        }
    }
    fn normalized(&self, input: &[u32], form: u8) -> (Vec<u8>, usize) {
        let mut expanded = Vec::new();
        for &value in input {
            self.expand(value, form >= 2, &mut expanded);
        }
        let scratch = expanded.len();
        let mut start = 0;
        for end in 0..expanded.len() {
            if self.ccc(expanded[end]) == 0 {
                expanded[start..end].sort_by_key(|&x| self.ccc(x));
                start = end + 1;
            }
        }
        expanded[start..].sort_by_key(|&x| self.ccc(x));
        if form % 2 == 0 {
            let mut result = Vec::new();
            for value in expanded {
                let starter = result.iter().rposition(|&x| self.ccc(x) == 0);
                let candidate = starter.and_then(|at| {
                    if result[at + 1..]
                        .iter()
                        .any(|&x| self.ccc(x) >= self.ccc(value))
                    {
                        None
                    } else {
                        self.composite(result[at], value).map(|x| (at, x))
                    }
                });
                if let Some((at, composite)) = candidate {
                    result[at] = composite;
                } else {
                    result.push(value);
                }
            }
            expanded = result;
        }
        (bytes(&expanded), scratch)
    }
}

#[test]
fn all_mappings_hangul_generated_combining_sequences_and_errors_match_spec_model() {
    let exe = executable("unicode_normalize_model");
    let model = Model::new();
    let mut cases = Vec::new();
    let mut add = |input: &[u32], check: bool| {
        let encoded = bytes(input);
        for form in 0..4 {
            let (expected, scratch) = model.normalized(input, form);
            cases.push(Case::normalized(form, &encoded, &expected, scratch));
            if check {
                cases.push(Case::checked(form, &encoded, encoded == expected, scratch));
            }
        }
    };
    for &value in model.decomposition.keys() {
        add(&[value], true);
    }
    for value in 0xAC00..0xD7A4 {
        add(&[value], false);
    }
    for input in [
        vec![],
        vec![0, 0x378, 0xFDD0, 0xFFFF, 0x10FFFF, 0xE000],
        vec![0x1100, 0x301, 0x1161],
        vec![0xAC00, 0x11A8],
        vec![0x301, 0x300, 0x323],
        vec![0x61, 0x301, 0x300],
        vec![0x61, 0x323, 0x301],
        vec![0x9C7, 0x9BE],
        vec![0x1E0B, 0x323],
    ] {
        add(&input, true);
    }
    let marks: Vec<_> = model.ccc.keys().copied().collect();
    let mut seed = 0x7612_0B09_u32;
    for index in 0..1024 {
        let mut input = vec![if index % 3 == 0 { 0x41 } else { 0x1E69 }];
        for _ in 0..index % 19 {
            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
            input.push(marks[(seed as usize) % marks.len()]);
        }
        add(&input, true);
    }
    drop(add);
    for input in [
        vec![0xC0, 0x80],
        vec![0xED, 0xA0, 0x80],
        vec![0xF4, 0x90, 0x80, 0x80],
        vec![65, 0xE2, 0x82],
        vec![0x80],
    ] {
        cases.push(Case {
            form: 0,
            scratch: 32,
            capacity: 32,
            limit: 1000,
            expected: Expected::Error(2, u64::from(input[0] == 65)),
            input,
        });
    }
    cases.push(Case {
        form: 3,
        input: bytes(&[0xFDFA]),
        scratch: 17,
        capacity: 100,
        limit: 1000,
        expected: Expected::Error(4, 18),
    });
    cases.push(Case {
        form: 1,
        input: bytes(&[0xC5]),
        scratch: 2,
        capacity: 2,
        limit: 1000,
        expected: Expected::Error(5, 3),
    });
    cases.push(Case {
        form: 0,
        input: b"abc".to_vec(),
        scratch: 3,
        capacity: 3,
        limit: 0,
        expected: Expected::Error(6, 0),
    });
    run_cases(&exe, &cases);
}
