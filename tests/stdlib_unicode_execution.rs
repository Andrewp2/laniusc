#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{os::unix::fs::PermissionsExt, path::PathBuf, process::Command, time::Duration};

fn root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}
fn executable(fixture: &str) -> common::TempArtifact {
    let entry = root().join(format!("tests/fixtures/stdlib_foundation/{fixture}.lani"));
    let stdlib = root().join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(fixture, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{fixture}: {error}"));
    let exe = common::TempArtifact::new("laniusc_unicode", fixture, None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn data(name: &str) -> String {
    let output = common::process_output_with_timeout(
        "read independent UCD reference",
        Command::new("gzip")
            .args(["-cd", "--"])
            .arg(root().join(format!("data/unicode/17.0.0/{name}.gz"))),
        Duration::from_secs(5),
    );
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    String::from_utf8(output.stdout).unwrap()
}
const CATEGORIES: [&str; 30] = [
    "Cn", "Lu", "Ll", "Lt", "Lm", "Lo", "Mn", "Mc", "Me", "Nd", "Nl", "No", "Pc", "Pd", "Ps", "Pe",
    "Pi", "Pf", "Po", "Sm", "Sc", "Sk", "So", "Zs", "Zl", "Zp", "Cc", "Cf", "Cs", "Co",
];
const PROPERTIES: [&str; 9] = [
    "Alphabetic",
    "Lowercase",
    "Uppercase",
    "Cased",
    "Case_Ignorable",
    "White_Space",
    "XID_Start",
    "XID_Continue",
    "Default_Ignorable_Code_Point",
];
fn cp(text: &str) -> u32 {
    u32::from_str_radix(text, 16).unwrap()
}
fn scalar(value: usize) -> bool {
    !(0xd800..=0xdfff).contains(&value)
}
fn reference() -> Vec<[u32; 17]> {
    // Direct code point arrays are deliberately independent of the generator's
    // range compression, ASCII encoding, chunk dispatch, and binary search.
    let mut model: Vec<[u32; 17]> = (0..0x110000)
        .map(|value| {
            let mut row = [0; 17];
            row[3] = 10;
            if scalar(value) {
                row[4..8].fill(value as u32);
                row[8] = 1;
                row[9] = value as u32;
                row[12] = 1;
                row[13] = value as u32;
                row[16] = value as u32;
            }
            row
        })
        .collect();
    let mut first = None;
    for line in data("UnicodeData.txt").lines() {
        let columns: Vec<_> = line.split(';').collect();
        let value = cp(columns[0]) as usize;
        if columns[1].ends_with(", First>") {
            first = Some(value);
            continue;
        }
        let start = if columns[1].ends_with(", Last>") {
            first.take().expect("range start")
        } else {
            value
        };
        let category = CATEGORIES
            .iter()
            .position(|&category| category == columns[2])
            .unwrap() as u32;
        for (index, row) in model.iter_mut().enumerate().take(value + 1).skip(start) {
            row[0] = category;
            row[1] = columns[3].parse().unwrap();
            row[3] = if columns[6].is_empty() {
                10
            } else {
                columns[6].parse().unwrap()
            };
            if scalar(index) {
                row[4] = if columns[13].is_empty() {
                    index as u32
                } else {
                    cp(columns[13])
                };
                row[5] = if columns[12].is_empty() {
                    index as u32
                } else {
                    cp(columns[12])
                };
                row[6] = if columns[14].is_empty() {
                    row[5]
                } else {
                    cp(columns[14])
                };
            }
        }
    }
    assert!(first.is_none());
    for name in ["DerivedCoreProperties.txt", "PropList.txt"] {
        for line in data(name).lines() {
            let body = line.split('#').next().unwrap().trim();
            if body.is_empty() {
                continue;
            }
            let columns: Vec<_> = body.split(';').map(str::trim).collect();
            let Some(bit) = PROPERTIES
                .iter()
                .position(|&property| property == columns[1])
            else {
                continue;
            };
            let (start, end) = columns[0]
                .split_once("..")
                .unwrap_or((columns[0], columns[0]));
            for row in &mut model[cp(start) as usize..=cp(end) as usize] {
                row[2] |= 1 << bit;
            }
        }
    }
    let mut turkic = vec![];
    for line in data("CaseFolding.txt").lines() {
        let body = line.split('#').next().unwrap().trim();
        if body.is_empty() {
            continue;
        }
        let columns: Vec<_> = body.split(';').map(str::trim).collect();
        let value = cp(columns[0]) as usize;
        let mapping: Vec<_> = columns[2].split_whitespace().map(cp).collect();
        let row = &mut model[value];
        match columns[1] {
            "C" | "S" => {
                row[7] = mapping[0];
                row[16] = mapping[0];
            }
            "F" | "T" => {}
            status => panic!("unknown CaseFolding status {status}"),
        }
        if matches!(columns[1], "C" | "F") {
            row[8] = mapping.len() as u32;
            row[9..12].fill(0);
            row[9..9 + mapping.len()].copy_from_slice(&mapping);
            let copy = [row[8], row[9], row[10], row[11]];
            row[12..16].copy_from_slice(&copy);
        }
        if columns[1] == "T" {
            turkic.push((value, mapping));
        }
    }
    for (value, mapping) in turkic {
        let row = &mut model[value];
        row[12] = mapping.len() as u32;
        row[13..16].fill(0);
        row[13..13 + mapping.len()].copy_from_slice(&mapping);
        row[16] = mapping[0];
    }
    model
}

#[test]
fn every_codepoint_property_and_scalar_mapping_matches_unicode_17_data_exactly() {
    let model = reference();
    let exe = executable("unicode_model");
    // Batches bound runtime/output memory and identify the failing code point.
    for start in (0..0x110000).step_by(0x10000) {
        let end = start + 0x10000;
        let output = common::process_output_with_timeout(
            "native Unicode 17 exact differential",
            Command::new(exe.path()).args([start.to_string(), end.to_string()]),
            Duration::from_secs(30),
        );
        assert!(
            output.status.success(),
            "batch U+{start:06X}: {:?}",
            output.status
        );
        assert!(
            output.stderr.is_empty(),
            "batch U+{start:06X}: {:?}",
            output.stderr
        );
        assert_eq!(
            output.stdout.len(),
            (end - start) * 17 * 4,
            "batch U+{start:06X}"
        );
        for (offset, actual) in output.stdout.chunks_exact(68).enumerate() {
            let value = start + offset;
            for (field, bytes) in actual.chunks_exact(4).enumerate() {
                let actual = u32::from_le_bytes(bytes.try_into().unwrap());
                assert_eq!(actual, model[value][field], "U+{value:06X} field {field}");
            }
        }
    }
}

#[test]
fn invalid_inputs_output_atomicity_view_strides_and_no_allocation_execute() {
    let exe = executable("unicode_contracts");
    let trace = common::TempArtifact::new("laniusc_unicode", "trace", None);
    let output = common::process_output_with_timeout(
        "Unicode pure native contracts",
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
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
}

#[test]
fn generated_unicode_property_tables_reproduce_from_checked_in_official_data() {
    let output = common::process_output_with_timeout(
        "reproduce Unicode 17 tables",
        Command::new("python3")
            .arg(root().join("tools/unicode17/generate_properties.py"))
            .arg("--check"),
        Duration::from_secs(10),
    );
    assert!(output.status.success(), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
