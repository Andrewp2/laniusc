#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;

use std::{cmp::Ordering, os::unix::fs::PermissionsExt, path::Path, process::Command};

fn compile(path: &Path) -> Result<Vec<u8>, laniusc_compiler::compiler::CompileError> {
    let entry = path.to_path_buf();
    let stdlib = Path::new(env!("CARGO_MANIFEST_DIR")).join("stdlib");
    common::run_gpu_codegen_with_timeout("range overlap", move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
}

fn executable(relative: &str) -> common::TempArtifact {
    let path = Path::new(env!("CARGO_MANIFEST_DIR")).join(relative);
    let bytes = compile(&path).unwrap_or_else(|error| panic!("{relative}: {error}"));
    let exe = common::TempArtifact::new("laniusc_range_overlap", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

fn compare(kind: u32, a: u64, b: u64) -> Ordering {
    match kind {
        0 | 4 => (a as i32).cmp(&(b as i32)),
        1 => a.cmp(&b),
        2 => f32::from_bits(a as u32).total_cmp(&f32::from_bits(b as u32)),
        3 => f64::from_bits(a).total_cmp(&f64::from_bits(b)),
        _ => unreachable!(),
    }
}

// Enumerate actual shared members. Endpoints belong to this finite universe,
// so any nonempty total-order intersection has a greatest-start witness here.
// This does not copy production's four crossing inequalities.
fn common_members(kind: u32, endpoints: [u64; 4], universe: &[u64]) -> u32 {
    let [a, b, c, d] = endpoints;
    let member = |x, start, end, closed| {
        compare(kind, start, x) != Ordering::Greater
            && if closed {
                compare(kind, x, end) != Ordering::Greater
            } else {
                compare(kind, x, end) == Ordering::Less
            }
    };
    let half = universe
        .iter()
        .any(|&x| member(x, a, b, false) && member(x, c, d, false));
    let closed = universe
        .iter()
        .any(|&x| member(x, a, b, true) && member(x, c, d, true));
    u32::from(half) * 3 + u32::from(closed) * 12
}

#[test]
fn total_order_overlap_matches_enumerated_common_members_and_migrated_caller() {
    let exe = executable("tests/fixtures/stdlib_foundation/range_overlap/model.lani");
    let signed = [-3_i32, -2, -1, 0, 1, 2, 3, i32::MIN, i32::MAX]
        .map(|x| x as u32 as u64)
        .to_vec();
    let unsigned = vec![
        0,
        1,
        2,
        u32::MAX as u64,
        1 << 32,
        1 << 63,
        u64::MAX - 1,
        u64::MAX,
    ];
    let floats32 = vec![
        0xffc0_0002,
        0xffc0_0001,
        0xff80_0001,
        0xff80_0000,
        0xbf80_0000,
        0x8000_0001,
        0x8000_0000,
        0,
        1,
        0x3f80_0000,
        0x7f80_0000,
        0x7f80_0001,
        0x7fc0_0001,
        0x7fc0_0002,
    ];
    let floats64 = vec![
        0xfff8_0000_0000_0002,
        0xfff8_0000_0000_0001,
        0xfff0_0000_0000_0001,
        0xfff0_0000_0000_0000,
        0xbff0_0000_0000_0000,
        0x8000_0000_0000_0001,
        0x8000_0000_0000_0000,
        0,
        1,
        0x3ff0_0000_0000_0000,
        0x7ff0_0000_0000_0000,
        0x7ff0_0000_0000_0001,
        0x7ff8_0000_0000_0001,
        0x7ff8_0000_0000_0002,
    ];
    let record = vec![0, 1, 2, 3, 4];
    let mut cases = Vec::new();
    for (kind, universe) in [signed, unsigned, floats32, floats64, record]
        .into_iter()
        .enumerate()
    {
        for &a in &universe {
            for &b in &universe {
                for &c in &universe {
                    for &d in &universe {
                        let bounds = [a, b, c, d];
                        cases.push((
                            kind as u32,
                            bounds,
                            common_members(kind as u32, bounds, &universe),
                        ));
                    }
                }
            }
        }
    }
    for batch in cases.chunks(4096) {
        let mut packet = Vec::new();
        for &(kind, bounds, _) in batch {
            packet.extend(kind.to_le_bytes());
            for bits in bounds {
                packet.extend(bits.to_le_bytes());
            }
        }
        let input = common::TempArtifact::new("laniusc_range_overlap", "input", None);
        input.write_bytes(packet);
        let output = common::short_process_output_with_timeout(
            "total-order overlap model",
            Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()),
        );
        assert_eq!(output.status.code(), Some(0), "{output:?}");
        assert!(output.stderr.is_empty(), "{output:?}");
        assert_eq!(output.stdout.len(), batch.len() * 4);
        for (&(kind, bounds, expected), actual) in batch.iter().zip(output.stdout.chunks_exact(4)) {
            assert_eq!(
                u32::from_le_bytes(actual.try_into().unwrap()),
                expected,
                "kind {kind}, bounds {bounds:x?}"
            );
        }
    }
    println!(
        "{} bound quadruples, all four overlap forms, independent common-member enumeration",
        cases.len()
    );
    let caller = executable("tests/fixtures/stdlib_foundation/core_range.lani");
    let output = common::short_process_output_with_timeout(
        "migrated core range",
        &mut Command::new(caller.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
}

const PROBES: [&str; 4] = [
    "core::range::overlaps(left,right)",
    "left.overlaps(right)",
    "core::range::overlaps_inclusive(closed_left,closed_right)",
    "closed_left.overlaps(closed_right)",
];

fn reject(source: &str, label: &str) {
    let entry = common::TempArtifact::new("laniusc_range_overlap", "reject", Some("lani"));
    entry.write_str(source);
    let error = compile(entry.path()).expect_err(label);
    assert_eq!(
        error.to_public_diagnostic().code,
        "LNC0008",
        "{label}: {error:?}"
    );
}

#[test]
fn partial_order_membership_executes_and_all_overlap_forms_reject() {
    let exe = executable("tests/fixtures/stdlib_foundation/range_overlap/partial-membership.lani");
    let output = common::short_process_output_with_timeout(
        "partial-order membership",
        &mut Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stdout.is_empty() && output.stderr.is_empty());
    let control = include_str!("fixtures/stdlib_foundation/range_overlap/partial-membership.lani");
    for probe in PROBES {
        let source = control.replace(
            "// OVERLAP_PROBE",
            &format!("let rejected: bool = {probe};"),
        );
        reject(&source, probe);
    }
}

fn reject_float(width: &str) {
    for probe in PROBES {
        let source = format!(
            r#"module app::main;
import core::range;
fn main() -> i32 {{
    let zero: {width} = 0.0; let one: {width} = 1.0;
    let left: core::range::Range<{width}> = core::range::range(zero,one);
    let right: core::range::Range<{width}> = core::range::range(zero,one);
    let closed_left: core::range::RangeInclusive<{width}> = core::range::range_inclusive(zero,one);
    let closed_right: core::range::RangeInclusive<{width}> = core::range::range_inclusive(zero,one);
    let rejected: bool = {probe};
    return 0;
}}"#
        );
        reject(&source, &format!("{width}: {probe}"));
    }
}

#[test]
fn native_f32_overlap_requires_an_explicit_total_order() {
    reject_float("f32");
}

#[test]
fn native_f64_overlap_requires_an_explicit_total_order() {
    reject_float("f64");
}
