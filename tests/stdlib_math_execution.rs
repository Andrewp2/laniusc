#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::fs::PermissionsExt,
    process::{Command, Stdio},
    sync::OnceLock,
    time::Duration,
};
fn executable() -> &'static common::TempArtifact {
    static EXE: OnceLock<common::TempArtifact> = OnceLock::new();
    EXE.get_or_init(|| {
        let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let entry = root.join("tests/fixtures/stdlib_foundation/math_model.lani");
        let stdlib = root.join("stdlib");
        let bytes = common::run_gpu_codegen_with_timeout("binary64 elementary math", move || {
            pollster::block_on(
                laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
            )
        })
        .unwrap();
        let exe = common::TempArtifact::new("laniusc_math", "model", None);
        exe.write_bytes(bytes);
        std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
        exe
    })
}
fn evaluate(cases: &[(i32, i32, u64, u64)]) -> Vec<(u64, u64)> {
    let mut bytes = (cases.len() as u32).to_le_bytes().to_vec();
    for &(op, n, x, y) in cases {
        bytes.extend(op.to_le_bytes());
        bytes.extend(n.to_le_bytes());
        bytes.extend(x.to_le_bytes());
        bytes.extend(y.to_le_bytes());
    }
    let input = common::TempArtifact::new("laniusc_math", "input", None);
    input.write_bytes(bytes);
    let output = common::process_output_with_timeout(
        "elementary math IEEE cases",
        Command::new(executable().path())
            .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())),
        Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout.len(), cases.len() * 16);
    output
        .stdout
        .chunks_exact(16)
        .map(|r| {
            (
                u64::from_le_bytes(r[..8].try_into().unwrap()),
                u64::from_le_bytes(r[8..].try_into().unwrap()),
            )
        })
        .collect()
}
#[test]
fn ieee_domains_signed_zero_infinities_nan_overflow_and_subnormals() {
    let z = 0f64.to_bits();
    let nz = (-0f64).to_bits();
    let inf = f64::INFINITY.to_bits();
    let ni = f64::NEG_INFINITY.to_bits();
    let nan = 0x7ff0000000000123u64;
    let qnan = nan | 0x0008000000000000;
    let one = 1f64.to_bits();
    let none = (-1f64).to_bits();
    let pi = std::f64::consts::PI.to_bits();
    let half = std::f64::consts::FRAC_PI_2.to_bits();
    let quarter = std::f64::consts::FRAC_PI_4.to_bits();
    let sign = 1u64 << 63;
    let mut cases = Vec::new();
    let mut expected = Vec::new();
    let mut add = |op, n, x, y, want, second| {
        cases.push((op, n, x, y));
        expected.push((want, second));
    };
    for input in [z, nz] {
        add(0, 0, input, z, input, z);
        add(1, 0, input, z, one, z);
        add(2, 0, input, z, input, one);
        add(3, 0, input, z, one, z);
        add(4, 0, input, z, input, z);
        add(6, 0, input, z, input, z);
        add(7, 0, input, z, input, z);
        add(5, 0, input, z, ni, z);
    }
    add(3, 0, inf, z, inf, z);
    add(3, 0, ni, z, z, z);
    add(4, 0, inf, z, inf, z);
    add(4, 0, ni, z, none, z);
    add(5, 0, inf, z, inf, z);
    add(6, 0, inf, z, inf, z);
    add(6, 0, none, z, ni, z);
    add(7, 0, inf, z, half, z);
    add(7, 0, ni, z, half | sign, z);
    for op in 0..10 {
        if op != 8 && op != 9 {
            add(op, 0, nan, z, qnan, if op == 2 { qnan } else { z });
        }
    }
    for (y, x, want) in [
        (z, z, z),
        (nz, z, nz),
        (z, nz, pi),
        (nz, nz, pi | sign),
        (z, one, z),
        (nz, one, nz),
        (z, none, pi),
        (nz, none, pi | sign),
        (one, z, half),
        (none, z, half | sign),
        (inf, inf, quarter),
        (ni, inf, quarter | sign),
        (inf, ni, (3.0 * std::f64::consts::FRAC_PI_4).to_bits()),
        (ni, ni, (3.0 * std::f64::consts::FRAC_PI_4).to_bits() | sign),
        (one, inf, z),
        (none, inf, nz),
    ] {
        add(8, 0, y, x, want, z);
    }
    for (x, y, want) in [
        (nan, z, one),
        (one, nan, one),
        (none, inf, one),
        (none, ni, one),
        (nz, 3f64.to_bits(), nz),
        (nz, (-3f64).to_bits(), ni),
        (nz, 0.5f64.to_bits(), z),
        (ni, 3f64.to_bits(), ni),
        (ni, (-3f64).to_bits(), nz),
        (ni, 0.5f64.to_bits(), inf),
        (2f64.to_bits(), 1024f64.to_bits(), inf),
        (2f64.to_bits(), (-1074f64).to_bits(), 1),
        (2f64.to_bits(), (-1075f64).to_bits(), z),
    ] {
        add(9, 0, x, y, want, z);
    }
    for (x, n, want) in [
        (one, -1074, 1),
        (one, -1075, z),
        (1, 1074, one),
        (nz, i32::MAX, nz),
        (inf, i32::MIN, inf),
        (none, i32::MIN, nz),
        (none, i32::MAX, ni),
        (f64::MAX.to_bits(), 1, inf),
        (f64::MIN_POSITIVE.to_bits(), -1, 0x0008000000000000),
    ] {
        add(10, n, x, z, want, z);
    }
    add(8, 0, nan, one, qnan, z);
    add(8, 0, one, nan, qnan, z);
    add(9, 0, nan, one, qnan, z);
    add(9, 0, 2f64.to_bits(), nan, qnan, z);
    let got = evaluate(&cases);
    for (i, (actual, want)) in got.iter().zip(&expected).enumerate() {
        assert_eq!(actual, want, "IEEE case {i}: {:?}", cases[i]);
    }
    let domain = [
        (0, 0, inf, z),
        (1, 0, ni, z),
        (5, 0, none, z),
        (6, 0, (-2f64).to_bits(), z),
        (9, 0, (-2f64).to_bits(), 0.5f64.to_bits()),
    ];
    for (i, (a, _)) in evaluate(&domain).iter().enumerate() {
        assert!(f64::from_bits(*a).is_nan(), "domain case {i}");
    }
}
#[test]
fn elementary_functions_match_high_precision_general_range_reference() {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let oracle = root.join("tests/fixtures/stdlib_foundation/math_oracle.py");
    let result = common::process_output_with_timeout(
        "binary64 math high precision oracle",
        Command::new("python3").arg(oracle).arg(executable().path()),
        Duration::from_secs(80),
    );
    assert!(result.status.success(), "{result:?}");
    assert!(result.stderr.is_empty(), "{result:?}");
    println!("{}", String::from_utf8_lossy(&result.stdout));
}
