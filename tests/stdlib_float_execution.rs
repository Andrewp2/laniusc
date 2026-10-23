#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::{fs::PermissionsExt, process::ExitStatusExt},
    process::{Command, Output},
    sync::OnceLock,
    time::Duration,
};
fn compile(path: &str) -> Vec<u8> {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(path);
    let stdlib = root.join("stdlib");
    common::run_gpu_codegen_with_timeout(path, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{path}: {error}"))
}
fn from_bytes(bytes: &[u8]) -> common::TempArtifact {
    let exe = common::TempArtifact::new("laniusc_float", "exe", None);
    exe.write_bytes(bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}
fn model() -> common::TempArtifact {
    static BYTES: OnceLock<Vec<u8>> = OnceLock::new();
    from_bytes(BYTES.get_or_init(|| compile("tests/fixtures/stdlib_foundation/float_model.lani")))
}
fn checked(output: &Output) {
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
}
#[derive(Clone, Copy, Debug)]
struct Case {
    width: u8,
    op: u8,
    a: u64,
    b: u64,
    c: u64,
    d: u64,
}
fn case(width: u8, op: u8, a: u64, b: u64, c: u64, d: u64) -> Case {
    Case {
        width,
        op,
        a,
        b,
        c,
        d,
    }
}
fn frame(cases: &[Case]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(cases.len() * 34);
    for c in cases {
        bytes.extend([c.width, c.op]);
        for bits in [c.a, c.b, c.c, c.d] {
            bytes.extend(bits.to_le_bytes());
        }
    }
    bytes
}
fn invoke(exe: &common::TempArtifact, cases: &[Case]) -> Vec<(u64, i32)> {
    let mut all = Vec::new();
    for chunk in cases.chunks(6000) {
        let input = common::TempArtifact::new("laniusc_float", "input", None);
        input.write_bytes(frame(chunk));
        let output = common::process_output_with_timeout(
            "float bitwise batch",
            Command::new(exe.path()).stdin(std::fs::File::open(input.path()).unwrap()),
            Duration::from_secs(15),
        );
        checked(&output);
        assert_eq!(output.stdout.len(), chunk.len() * 12);
        all.extend(output.stdout.chunks_exact(12).map(|b| {
            (
                u64::from_le_bytes(b[..8].try_into().unwrap()),
                i32::from_le_bytes(b[8..].try_into().unwrap()),
            )
        }));
    }
    all
}
macro_rules! reference {
    ($name:ident,$float:ty,$word:ty,$sign:expr,$inf:expr,$quiet:expr,$nan:expr) => {
        fn $name(c: Case) -> (u64, i32) {
            let bits = c.a as $word;
            let other = c.b as $word;
            let x = <$float>::from_bits(bits);
            let y = <$float>::from_bits(other);
            let low = <$float>::from_bits(c.b as $word);
            let high = <$float>::from_bits(c.c as $word);
            let fallback = <$float>::from_bits(c.d as $word);
            let magnitude = bits & !$sign;
            if c.op == 14 {
                return (
                    (match x.total_cmp(&y) {
                        std::cmp::Ordering::Less => 0,
                        std::cmp::Ordering::Equal => 1,
                        std::cmp::Ordering::Greater => 2,
                    }),
                    0,
                );
            }
            if c.op == 15 {
                return (
                    (match x.classify() {
                        std::num::FpCategory::Nan => 0,
                        std::num::FpCategory::Infinite => 1,
                        std::num::FpCategory::Zero => 2,
                        std::num::FpCategory::Subnormal => 3,
                        std::num::FpCategory::Normal => 4,
                    }),
                    0,
                );
            }
            if c.op == 16 {
                let mut flags = 0u64;
                for (condition, bit) in [
                    (x.is_nan(), 1),
                    (x.is_infinite(), 2),
                    (x.is_finite(), 4),
                    (x.is_normal(), 8),
                    (x.is_subnormal(), 16),
                    (x.is_sign_negative(), 32),
                    (x.is_sign_positive(), 64),
                    (x < 0.0, 128),
                    (x > 0.0, 256),
                    (x == 0.0, 512),
                    (x != 0.0, 1024),
                ] {
                    if condition {
                        flags |= bit;
                    }
                }
                return (flags, 0);
            }
            if c.op == 17 || c.op == 18 {
                if low.is_nan() || high.is_nan() || low > high {
                    return if c.op == 17 {
                        (0, 1)
                    } else {
                        (fallback.to_bits() as u64, 0)
                    };
                }
                return (
                    if x.is_nan() {
                        bits as u64
                    } else {
                        x.clamp(low, high).to_bits() as u64
                    },
                    0,
                );
            }
            if c.op == 19 {
                return (u64::from(x > low && x < high), 0);
            }
            if c.op == 20 {
                return (u64::from(x >= low && x <= high), 0);
            }
            let result: $word = match c.op {
                0 => bits,
                1 => bits & !$sign,
                2 => (bits & !$sign) | (other & $sign),
                3 => {
                    if x.is_nan() {
                        bits | $quiet
                    } else {
                        x.signum().to_bits()
                    }
                }
                4 => {
                    if x.is_nan() {
                        bits
                    } else {
                        x.next_up().to_bits()
                    }
                }
                5 => {
                    if x.is_nan() {
                        bits
                    } else {
                        x.next_down().to_bits()
                    }
                }
                6 => {
                    if x.is_nan() {
                        bits
                    } else {
                        x.trunc().to_bits()
                    }
                }
                7 => {
                    if x.is_nan() {
                        bits
                    } else {
                        x.floor().to_bits()
                    }
                }
                8 => {
                    if x.is_nan() {
                        bits
                    } else {
                        x.ceil().to_bits()
                    }
                }
                9 => {
                    if x.is_nan() {
                        bits
                    } else {
                        x.round().to_bits()
                    }
                }
                10 => {
                    if x.is_nan() {
                        bits
                    } else {
                        x.round_ties_even().to_bits()
                    }
                }
                11 => {
                    if x.is_nan() {
                        bits | $quiet
                    } else if x < 0.0 {
                        $nan
                    } else {
                        x.sqrt().to_bits()
                    }
                }
                12 | 13 => {
                    if x.is_nan() {
                        if y.is_nan() { bits | $quiet } else { other }
                    } else if y.is_nan() {
                        bits
                    } else if magnitude == 0 && (other & !$sign) == 0 {
                        if c.op == 12 {
                            bits | other
                        } else {
                            bits & other
                        }
                    } else if c.op == 12 {
                        x.min(y).to_bits()
                    } else {
                        x.max(y).to_bits()
                    }
                }
                21 => {
                    if x.is_nan() || x < 0.0 {
                        other
                    } else {
                        x.sqrt().to_bits()
                    }
                }
                22 => <$float>::to_bits(0.0),
                23 => <$float>::to_bits(1.0),
                24 => <$float>::EPSILON.to_bits(),
                25 => <$float>::MIN_POSITIVE.to_bits(),
                26 => <$float>::MAX.to_bits(),
                27 => <$float>::MIN.to_bits(),
                28 => $inf,
                29 => $inf | $sign,
                30 => $nan,
                _ => panic!("{c:?}"),
            };
            (result as u64, 0)
        }
    };
}
reference!(
    reference32,
    f32,
    u32,
    0x8000_0000u32,
    0x7f80_0000u32,
    0x0040_0000u32,
    0x7fc0_0000u32
);
reference!(
    reference64,
    f64,
    u64,
    0x8000_0000_0000_0000u64,
    0x7ff0_0000_0000_0000u64,
    0x0008_0000_0000_0000u64,
    0x7ff8_0000_0000_0000u64
);
fn expected(c: Case) -> (u64, i32) {
    if c.width == 32 {
        reference32(c)
    } else {
        reference64(c)
    }
}
fn check(exe: &common::TempArtifact, cases: &[Case]) {
    for (c, result) in cases.iter().zip(invoke(exe, cases)) {
        assert_eq!(
            result,
            expected(*c),
            "width={} op={} a={:016x} b={:016x} c={:016x} d={:016x}",
            c.width,
            c.op,
            c.a,
            c.b,
            c.c,
            c.d
        );
    }
}
fn edges(width: u8) -> Vec<u64> {
    if width == 32 {
        vec![
            0, 0x80000000, 1, 2, 0x007ffffe, 0x007fffff, 0x00800000, 0x00800001, 0x3effffff,
            0x3f000000, 0x3f000001, 0x3f7fffff, 0x3f800000, 0x3f800001, 0x3fc00000, 0x40000000,
            0x40200000, 0x4affffff, 0x4b000000, 0x7f7ffffe, 0x7f7fffff, 0x7f800000, 0xff800000,
            0x7f800001, 0x7fbfffff, 0x7fc00000, 0x7fffffff, 0xff800001, 0xffc12345, 0xffffffff,
        ]
    } else {
        vec![
            0,
            0x8000000000000000,
            1,
            2,
            0x000ffffffffffffe,
            0x000fffffffffffff,
            0x0010000000000000,
            0x0010000000000001,
            0x3fdfffffffffffff,
            0x3fe0000000000000,
            0x3fe0000000000001,
            0x3fefffffffffffff,
            0x3ff0000000000000,
            0x3ff0000000000001,
            0x3ff8000000000000,
            0x4000000000000000,
            0x4004000000000000,
            0x432fffffffffffff,
            0x4330000000000000,
            0x7feffffffffffffe,
            0x7fefffffffffffff,
            0x7ff0000000000000,
            0xfff0000000000000,
            0x7ff0000000000001,
            0x7ff7ffffffffffff,
            0x7ff8000000000000,
            0x7fffffffffffffff,
            0xfff0000000000001,
            0xfff8123456789abc,
            0xffffffffffffffff,
        ]
    }
}
fn next(state: &mut u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}
#[test]
fn exact_bits_classification_signs_neighbors_minmax_and_total_order_match_ieee_references() {
    let exe = model();
    let mut cases = Vec::new();
    for width in [32, 64] {
        let mut values = edges(width);
        let sign = 1u64 << (width - 1);
        values.extend(values.clone().into_iter().map(|v| v ^ sign));
        let mut seed = 0xa57c_159d_2932_7431;
        for _ in 0..3000 {
            let bits = next(&mut seed);
            values.push(if width == 32 {
                bits as u32 as u64
            } else {
                bits
            });
        }
        for (i, &a) in values.iter().enumerate() {
            let b = values[(i * 31 + 7) % values.len()];
            for op in [0, 1, 2, 3, 4, 5, 12, 13, 14, 15, 16] {
                cases.push(case(width, op, a, b, 0, 0));
            }
        }
        for a in edges(width) {
            for b in edges(width) {
                for op in [2, 12, 13, 14] {
                    cases.push(case(width, op, a, b, 0, 0));
                }
            }
        }
    }
    check(&exe, &cases);
}
#[test]
fn integral_rounding_matches_native_references_at_ties_boundaries_and_random_bit_patterns() {
    let exe = model();
    let mut cases = Vec::new();
    for width in [32, 64] {
        let mut values = edges(width);
        let mut seed = 0x678a_b93f_0123_4567;
        for _ in 0..5000 {
            let b = next(&mut seed);
            values.push(if width == 32 { b as u32 as u64 } else { b });
        }
        for n in -4096..4096 {
            let value = n as f64 * 0.5;
            let bits = if width == 32 {
                (value as f32).to_bits() as u64
            } else {
                value.to_bits()
            };
            values.extend([bits, bits.wrapping_sub(1), bits.wrapping_add(1)]);
        }
        for a in values {
            for op in [6, 7, 8, 9, 10] {
                cases.push(case(width, op, a, 0, 0, 0));
            }
        }
    }
    check(&exe, &cases);
}
#[test]
fn integer_square_root_is_correctly_rounded_across_all_exponents_and_random_significands() {
    let exe = model();
    let mut cases = Vec::new();
    for width in [32, 64] {
        let (fraction, exponents) = if width == 32 {
            (23, 256u64)
        } else {
            (52, 2048u64)
        };
        let mask = (1u64 << fraction) - 1;
        for exponent in 0..exponents {
            for mantissa in [0, 1, 2, mask / 2, mask - 1, mask] {
                cases.push(case(width, 11, (exponent << fraction) | mantissa, 0, 0, 0));
            }
        }
        let mut seed = 0x3256_1fda_2912_6721;
        for _ in 0..40000 {
            let b = next(&mut seed);
            cases.push(case(
                width,
                11,
                if width == 32 { b as u32 as u64 } else { b },
                0,
                0,
                0,
            ));
        }
        for a in edges(width) {
            cases.push(case(width, 11, a, 0, 0, 0));
        }
    }
    check(&exe, &cases);
}
#[test]
fn clamp_errors_fallbacks_ranges_sqrt_fallbacks_and_finite_constants_are_explicit() {
    let exe = model();
    let mut cases = Vec::new();
    for width in [32, 64] {
        let values = edges(width);
        for &a in &values {
            for &b in &values {
                cases.push(case(width, 21, a, b, 0, 0));
                for &c in &values {
                    for op in [17, 18, 19, 20] {
                        cases.push(case(width, op, a, b, c, values[27]));
                    }
                }
            }
        }
        for op in 22..=30 {
            cases.push(case(width, op, 0, 0, 0, 0));
        }
    }
    check(&exe, &cases);
}
#[test]
fn all_value_helpers_allocate_no_heap_storage_and_preserve_bit_transfers() {
    let exe = model();
    let mut cases = Vec::new();
    for width in [32, 64] {
        for a in edges(width) {
            for op in 0..=30 {
                cases.push(case(width, op, a, 0, 0, 0));
            }
        }
    }
    let input = common::TempArtifact::new("laniusc_float", "noalloc-input", None);
    input.write_bytes(frame(&cases));
    let trace = common::TempArtifact::new("laniusc_float", "noalloc-trace", None);
    let output = common::process_output_with_timeout(
        "allocation-free float utilities",
        Command::new("strace")
            .args(["-qq", "-o"])
            .arg(trace.path())
            .args([
                "-e",
                "trace=mmap,munmap",
                "-e",
                "inject=mmap:error=ENOMEM:when=1+",
            ])
            .arg(exe.path())
            .stdin(std::fs::File::open(input.path()).unwrap()),
        Duration::from_secs(15),
    );
    checked(&output);
    assert!(std::fs::read_to_string(trace.path()).unwrap().is_empty());
    assert_eq!(output.stdout.len(), cases.len() * 12);
    let exe = from_bytes(&compile("tests/fixtures/stdlib_foundation/float_bits.lani"));
    checked(&common::short_process_output_with_timeout(
        "native float bit edges",
        &mut Command::new(exe.path()),
    ));
}
#[test]
fn strict_clamp_panics_for_reversed_or_nan_bounds_on_both_widths() {
    let exe = from_bytes(&compile(
        "tests/fixtures/stdlib_foundation/float_clamp_panic.lani",
    ));
    for width in ["32", "64"] {
        for mode in ["0", "1", "2"] {
            let output = common::signal_process_output_with_timeout(
                "strict float clamp",
                Command::new(exe.path()).args([width, mode]),
            );
            assert_eq!(
                output.status.signal(),
                Some(4),
                "{width} {mode}: {output:?}"
            );
            assert!(output.stdout.is_empty() && output.stderr.is_empty());
        }
    }
}
#[test]
fn migrated_existing_f32_contract_program_executes() {
    let exe = from_bytes(&compile("tests/fixtures/stdlib_foundation/core_f32.lani"));
    checked(&common::short_process_output_with_timeout(
        "existing f32 contracts",
        &mut Command::new(exe.path()),
    ));
}
