#![cfg(all(target_os = "linux", target_arch = "x86_64"))]
mod common;
use std::{
    os::unix::{fs::PermissionsExt, process::ExitStatusExt},
    process::{Command, Stdio},
};

fn fixture(name: &str) -> common::TempArtifact {
    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let entry = root.join(format!("tests/fixtures/stdlib_foundation/{name}.lani"));
    let stdlib = root.join("stdlib");
    let bytes = common::run_gpu_codegen_with_timeout(name, move || {
        pollster::block_on(
            laniusc_compiler::compiler::compile_entry_to_x86_64_with_stdlib(&entry, &stdlib),
        )
    })
    .unwrap_or_else(|error| panic!("{name}: {error}"));
    let exe = common::TempArtifact::new("laniusc_native_integers", name, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn native_integer_boundaries_and_existing_i64_contracts_execute() {
    assert_eq!(usize::BITS, 64);
    assert_eq!(isize::BITS, 64);
    let exe = fixture("native_integer_contracts");
    let output = common::short_process_output_with_timeout(
        "native integer boundaries",
        &mut Command::new(exe.path()),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(
        output.stdout.is_empty() && output.stderr.is_empty(),
        "{output:?}"
    );
}

#[derive(Clone, Copy, Debug)]
struct Case {
    kind: u8,
    op: u8,
    a: u64,
    b: u64,
    amount: u32,
}

fn integer_range(index: usize) -> (i128, i128, u32, bool) {
    let bits = [8, 8, 16, 16, 32, 32, 64, 64, 64, 64][index];
    let signed = index % 2 == 0;
    if signed {
        (
            -(1i128 << (bits - 1)),
            (1i128 << (bits - 1)) - 1,
            bits,
            true,
        )
    } else {
        (0, (1i128 << bits) - 1, bits, false)
    }
}

fn cast_numeric(bits: u64, width: u32, signed: bool) -> i128 {
    let value = i128::from(bits) & ((1i128 << width) - 1);
    if signed && value & (1i128 << (width - 1)) != 0 {
        value - (1i128 << width)
    } else {
        value
    }
}

// Independent i128 range arithmetic covers every source/target conversion.
fn conversion(c: Case) -> Option<u64> {
    let operation = usize::from(c.op - 52);
    let to = operation < 30;
    let index = (operation % 30) / 3;
    let mode = operation % 3;
    let (module_low, module_high, module_width, module_signed) =
        integer_range(if c.kind % 2 == 0 { 6 } else { 7 });
    let (other_low, other_high, other_width, other_signed) = integer_range(index);
    let (number, low, high, width, signed) = if to {
        (
            cast_numeric(c.a, module_width, module_signed),
            other_low,
            other_high,
            other_width,
            other_signed,
        )
    } else {
        (
            cast_numeric(c.a, other_width, other_signed),
            module_low,
            module_high,
            module_width,
            module_signed,
        )
    };
    match mode {
        0 => {
            if number < low || number > high {
                None
            } else {
                Some(number as u64)
            }
        }
        1 => Some(number.clamp(low, high) as u64),
        _ => Some(cast_numeric(number as u64, width, signed) as u64),
    }
}

fn reference(c: Case) -> Option<u64> {
    if c.op >= 52 {
        return conversion(c);
    }
    let n = c.amount;
    if c.kind % 2 == 0 {
        let a = c.a as i64;
        let b = c.b as i64;
        let checked = match c.op {
            3 => a.checked_add(b),
            4 => a.checked_sub(b),
            5 => a.checked_mul(b),
            9 => a.checked_div(b),
            10 => a.checked_rem(b),
            11 => a.checked_div_euclid(b),
            12 => a.checked_rem_euclid(b),
            13 => a.checked_neg(),
            16 => a.checked_pow(n),
            19 => a.checked_shl(n),
            20 => a.checked_shr(n),
            33 => {
                if a <= 1 {
                    Some(1)
                } else {
                    (a as u64)
                        .checked_next_power_of_two()
                        .filter(|v| *v <= i64::MAX as u64)
                        .map(|v| v as i64)
                }
            }
            34 => a.checked_abs(),
            44 => i32::try_from(a).ok().map(i64::from),
            45 => u32::try_from(a).ok().map(i64::from),
            46 => Some(a),
            47 => i64::try_from(c.a).ok(),
            _ => {
                return Some(match c.op {
                    0 => a.wrapping_add(b) as u64,
                    1 => a.wrapping_sub(b) as u64,
                    2 => a.wrapping_mul(b) as u64,
                    6 => a.saturating_add(b) as u64,
                    7 => a.saturating_sub(b) as u64,
                    8 => a.saturating_mul(b) as u64,
                    14 => a.wrapping_neg() as u64,
                    15 => a.saturating_neg() as u64,
                    17 => a.wrapping_pow(n) as u64,
                    18 => a.saturating_pow(n) as u64,
                    21 => a.wrapping_shl(n) as u64,
                    22 => a.wrapping_shr(n) as u64,
                    23 => a.rotate_left(n) as u64,
                    24 => a.rotate_right(n) as u64,
                    25 => a.reverse_bits() as u64,
                    26 => a.swap_bytes() as u64,
                    27 => u64::from(a.count_ones()),
                    28 => u64::from(a.count_zeros()),
                    29 => u64::from(a.leading_zeros()),
                    30 => u64::from(a.trailing_zeros()),
                    31 => u64::from(a.leading_ones()),
                    32 => u64::from(a.trailing_ones()),
                    35 => a.wrapping_abs() as u64,
                    36 => a.saturating_abs() as u64,
                    37 => a.signum() as u64,
                    38 => a.unsigned_abs(),
                    39 => a.abs_diff(b),
                    40 => a.min(b) as u64,
                    41 => a.max(b) as u64,
                    42 => u64::from(a % 2 == 0),
                    43 => u64::from(b != 0 && (b == -1 || a % b == 0)),
                    48 => a.wrapping_div(b) as u64,
                    49 => a.wrapping_rem(b) as u64,
                    50 => a.saturating_div(b) as u64,
                    51 => u64::from(a > 0 && (a as u64).is_power_of_two()),
                    _ => panic!("unknown signed operation {c:?}"),
                });
            }
        };
        checked.map(|v| v as u64)
    } else {
        let a = c.a;
        let b = c.b;
        match c.op {
            0 => Some(a.wrapping_add(b)),
            1 => Some(a.wrapping_sub(b)),
            2 => Some(a.wrapping_mul(b)),
            3 => a.checked_add(b),
            4 => a.checked_sub(b),
            5 => a.checked_mul(b),
            6 => Some(a.saturating_add(b)),
            7 => Some(a.saturating_sub(b)),
            8 => Some(a.saturating_mul(b)),
            9 | 11 => a.checked_div(b),
            10 | 12 => a.checked_rem(b),
            13 => a.checked_neg(),
            14 => Some(a.wrapping_neg()),
            16 => a.checked_pow(n),
            17 => Some(a.wrapping_pow(n)),
            18 => Some(a.saturating_pow(n)),
            19 => a.checked_shl(n),
            20 => a.checked_shr(n),
            21 => Some(a.wrapping_shl(n)),
            22 => Some(a.wrapping_shr(n)),
            23 => Some(a.rotate_left(n)),
            24 => Some(a.rotate_right(n)),
            25 => Some(a.reverse_bits()),
            26 => Some(a.swap_bytes()),
            27 => Some(u64::from(a.count_ones())),
            28 => Some(u64::from(a.count_zeros())),
            29 => Some(u64::from(a.leading_zeros())),
            30 => Some(u64::from(a.trailing_zeros())),
            31 => Some(u64::from(a.leading_ones())),
            32 => Some(u64::from(a.trailing_ones())),
            33 => a.checked_next_power_of_two(),
            39 => Some(a.abs_diff(b)),
            40 => Some(a.min(b)),
            41 => Some(a.max(b)),
            42 => Some(u64::from(a % 2 == 0)),
            43 => Some(u64::from(b != 0 && a % b == 0)),
            44 => i32::try_from(a).ok().map(|v| v as u64),
            45 => u32::try_from(a).ok().map(u64::from),
            46 => u64::try_from(a as i64).ok(),
            47 => Some(a),
            48 | 50 => Some(a / b),
            49 => Some(a % b),
            51 => Some(u64::from(a.is_power_of_two())),
            _ => panic!("unknown unsigned operation {c:?}"),
        }
    }
}

#[test]
fn arithmetic_bits_and_all_integer_conversions_match_native_and_i128_models() {
    const SEED: u64 = 0x1640_2026_f15e_cafe;
    let mut seed = SEED;
    let mut random = || {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        seed
    };
    let edges = [
        0,
        1,
        2,
        3,
        63,
        64,
        127,
        128,
        255,
        256,
        32767,
        32768,
        65535,
        65536,
        (1 << 31) - 1,
        1 << 31,
        (1 << 32) - 1,
        1 << 32,
        (1 << 32) + 1,
        (1 << 62) - 1,
        1 << 62,
        (1 << 62) + 1,
        (1 << 63) - 2,
        (1 << 63) - 1,
        1 << 63,
        (1 << 63) + 1,
        u64::MAX - 1,
        u64::MAX,
    ];
    let shifts = [
        0,
        1,
        2,
        7,
        31,
        32,
        33,
        62,
        63,
        64,
        65,
        127,
        128,
        129,
        u32::MAX,
    ];
    let mut cases = Vec::new();
    let mut push = |c: Case| {
        if c.kind % 2 == 1 && [15, 34, 35, 36, 37, 38].contains(&c.op) {
            return;
        }
        if (48..=50).contains(&c.op) && c.b == 0 {
            return;
        }
        cases.push(c);
    };
    for kind in 0..4 {
        for op in 0..112 {
            for index in 0..64 {
                let a = if index < edges.len() {
                    edges[index]
                } else {
                    random()
                };
                let b = if index < edges.len() {
                    edges[(index * 11 + 7) % edges.len()]
                } else {
                    random()
                };
                let amount = shifts[index % shifts.len()];
                push(Case {
                    kind,
                    op,
                    a,
                    b,
                    amount,
                });
            }
        }
        // Every boundary pair for arithmetic, signedness and division paths.
        for op in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 39, 43, 48, 49, 50] {
            for a in edges {
                for b in edges {
                    push(Case {
                        kind,
                        op,
                        a,
                        b,
                        amount: 3,
                    });
                }
            }
        }
    }
    // Exercise the division-based signed multiplication guards immediately
    // around a non-power-of-two threshold, with all signs and both orders.
    for kind in [0, 2] {
        for small in [-3_i64, 3] {
            for large in [
                -3_074_457_345_618_258_602_i64,
                -3_074_457_345_618_258_603,
                3_074_457_345_618_258_602,
                3_074_457_345_618_258_603,
            ] {
                for (a, b) in [(small, large), (large, small)] {
                    for op in [2, 5, 8] {
                        push(Case {
                            kind,
                            op,
                            a: a as u64,
                            b: b as u64,
                            amount: 0,
                        });
                    }
                }
            }
        }
    }
    assert!(cases.len() < 100000);
    let case_count = cases.len();
    let mut input = (cases.len() as u32).to_le_bytes().to_vec();
    for c in &cases {
        input.extend_from_slice(&[c.kind, c.op, 0, 0]);
        input.extend_from_slice(&c.a.to_le_bytes());
        input.extend_from_slice(&c.b.to_le_bytes());
        input.extend_from_slice(&c.amount.to_le_bytes());
    }
    let exe = fixture("native_integer_model");
    let file = common::TempArtifact::new("laniusc_native_integers", "reference_input", None);
    file.write_bytes(&input);
    let output = common::process_output_with_timeout(
        "native integer model seed=0x16402026f15ecafe",
        Command::new(exe.path()).stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        std::time::Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout.len(), cases.len() * 12);
    for (index, (row, c)) in output.stdout.chunks_exact(12).zip(cases).enumerate() {
        let valid = u32::from_le_bytes(row[..4].try_into().unwrap());
        let bits = u64::from_le_bytes(row[4..].try_into().unwrap());
        let expected = reference(c);
        assert_eq!(
            (valid, bits),
            (u32::from(expected.is_some()), expected.unwrap_or(0)),
            "seed={SEED:#x} case={index} {c:?}"
        );
    }
    let oracle = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/stdlib_foundation/native_integer_oracle.py");
    let independent = common::process_output_with_timeout(
        "Python arbitrary precision native integer oracle",
        Command::new("python3").arg(oracle).arg(exe.path()),
        std::time::Duration::from_secs(10),
    );
    assert!(independent.status.success(), "{independent:?}");
    assert!(independent.stderr.is_empty(), "{independent:?}");
    println!(
        "{case_count} native cases match Rust primitives/i128; {}",
        String::from_utf8_lossy(&independent.stdout).trim()
    );
}

#[test]
fn explicit_strict_preconditions_trap_in_all_four_modules() {
    let exe = fixture("native_integer_panics");
    let input = common::TempArtifact::new("laniusc_native_integers", "panic_input", None);
    let mut count = 0;
    for kind in 0_i32..4 {
        for op in (0_i32..if kind % 2 == 0 { 14 } else { 9 }).chain([14, 15]) {
            input.write_bytes(&[kind.to_le_bytes(), op.to_le_bytes()].concat());
            let output = common::signal_process_output_with_timeout(
                "native integer precondition",
                Command::new(exe.path())
                    .stdin(Stdio::from(std::fs::File::open(input.path()).unwrap())),
            );
            assert_eq!(
                output.status.signal(),
                Some(4),
                "kind={kind} op={op}: {output:?}"
            );
            assert!(
                output.stdout.is_empty() && output.stderr.is_empty(),
                "kind={kind} op={op}: {output:?}"
            );
            count += 1;
        }
    }
    println!("{count} strict native preconditions trap with SIGILL");
}
