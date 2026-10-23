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
    let exe = common::TempArtifact::new("laniusc_narrow_integers", name, None);
    exe.write_bytes(&bytes);
    std::fs::set_permissions(exe.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    exe
}

#[test]
fn narrow_integer_strict_conveniences_ascii_and_boundaries_execute() {
    assert_eq!(usize::BITS, 64);
    assert_eq!(isize::BITS, 64);
    let exe = fixture("narrow_integer_contracts");
    let output = common::short_process_output_with_timeout(
        "narrow integer boundaries",
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
    let (module_low, module_high, module_width, module_signed) = integer_range(c.kind as usize);
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

// Rust primitive operations independently specify each source width.
macro_rules! primitive_reference {
    ($c:expr, $t:ty, $signed:ident) => {{
        let c = $c;
        let a = c.a as $t;
        let b = c.b as $t;
        let n = c.amount;
        match c.op {
            0 => Some(a.wrapping_add(b) as u64),
            1 => Some(a.wrapping_sub(b) as u64),
            2 => Some(a.wrapping_mul(b) as u64),
            3 => a.checked_add(b).map(|v| v as u64),
            4 => a.checked_sub(b).map(|v| v as u64),
            5 => a.checked_mul(b).map(|v| v as u64),
            6 => Some(a.saturating_add(b) as u64),
            7 => Some(a.saturating_sub(b) as u64),
            8 => Some(a.saturating_mul(b) as u64),
            9 => a.checked_div(b).map(|v| v as u64),
            10 => a.checked_rem(b).map(|v| v as u64),
            11 => a.checked_div_euclid(b).map(|v| v as u64),
            12 => a.checked_rem_euclid(b).map(|v| v as u64),
            13 => a.checked_neg().map(|v| v as u64),
            14 => Some(a.wrapping_neg() as u64),
            16 => a.checked_pow(n).map(|v| v as u64),
            17 => Some(a.wrapping_pow(n) as u64),
            18 => Some(a.saturating_pow(n) as u64),
            19 => a.checked_shl(n).map(|v| v as u64),
            20 => a.checked_shr(n).map(|v| v as u64),
            21 => Some(a.wrapping_shl(n) as u64),
            22 => Some(a.wrapping_shr(n) as u64),
            23 => Some(a.rotate_left(n) as u64),
            24 => Some(a.rotate_right(n) as u64),
            25 => Some(a.reverse_bits() as u64),
            26 => Some(a.swap_bytes() as u64),
            27 => Some(a.count_ones() as u64),
            28 => Some(a.count_zeros() as u64),
            29 => Some(a.leading_zeros() as u64),
            30 => Some(a.trailing_zeros() as u64),
            31 => Some(a.leading_ones() as u64),
            32 => Some(a.trailing_ones() as u64),
            39 => Some(a.abs_diff(b) as u64),
            40 => Some(a.min(b) as u64),
            41 => Some(a.max(b) as u64),
            48 => Some(a.wrapping_div(b) as u64),
            49 => Some(a.wrapping_rem(b) as u64),
            50 => Some(a.saturating_div(b) as u64),
            42 => Some(u64::from(a % 2 == 0)),
            43 => Some(u64::from(
                b != 0 && ((<$t>::MIN != 0 && b == (-(1_i64) as $t)) || a % b == 0),
            )),
            44 => i32::try_from(a).ok().map(|v| v as u64),
            45 => u32::try_from(a).ok().map(|v| v as u64),
            46 => <$t>::try_from(c.a as i64).ok().map(|v| v as u64),
            47 => <$t>::try_from(c.a).ok().map(|v| v as u64),
            _ => extra_primitive_reference!(c, a, $t, $signed),
        }
    }};
}
macro_rules! extra_primitive_reference {
    ($c:expr, $a:expr, $t:ty, signed) => {{
        let a = $a;
        match $c.op {
            15 => Some(a.saturating_neg() as u64),
            33 => {
                if a <= 1 {
                    Some(1)
                } else {
                    (a as u64)
                        .checked_next_power_of_two()
                        .filter(|v| *v <= <$t>::MAX as u64)
                }
            }
            34 => a.checked_abs().map(|v| v as u64),
            35 => Some(a.wrapping_abs() as u64),
            36 => Some(a.saturating_abs() as u64),
            37 => Some(a.signum() as u64),
            38 => Some(a.unsigned_abs() as u64),
            51 => Some(u64::from(a > 0 && (a as u64).is_power_of_two())),
            _ => panic!("unknown signed operation {:?}", $c),
        }
    }};
    ($c:expr, $a:expr, $t:ty, unsigned) => {{
        let a = $a;
        match $c.op {
            33 => a.checked_next_power_of_two().map(|v| v as u64),
            51 => Some(u64::from(a.is_power_of_two())),
            _ => panic!("unknown unsigned operation {:?}", $c),
        }
    }};
}

fn reference(c: Case) -> Option<u64> {
    if (52..112).contains(&c.op) {
        return conversion(c);
    }
    if c.op >= 112 {
        let (low, high, width, signed) = integer_range(c.kind as usize);
        let a = cast_numeric(c.a, width, signed);
        let b = cast_numeric(c.b, width, signed);
        let mut x = a.abs();
        let mut y = b.abs();
        while y != 0 {
            let r = x % y;
            x = y;
            y = r;
        }
        let answer = match c.op {
            112 => Some(x),
            113 => {
                if a == 0 || b == 0 {
                    Some(0)
                } else {
                    let lcm = a.abs() / x * b.abs();
                    (lcm <= high).then_some(lcm)
                }
            }
            114 => {
                if b == 0 {
                    None
                } else {
                    let up = ((a + b - 1) / b) * b;
                    (up <= high).then_some(up)
                }
            }
            115 => (b != 0).then(|| a / b * b),
            116 => Some(i128::from(b != 0 && a % b == 0)),
            117 => Some((a - b).abs().min(high)),
            118 | 119 => {
                let bound = cast_numeric(u64::from(c.amount), width, signed);
                if b > bound {
                    if c.op == 119 { Some(3) } else { None }
                } else {
                    Some(a.clamp(b, bound))
                }
            }
            _ => panic!("unknown operation {c:?}"),
        };
        debug_assert!(answer.is_none_or(|v| v >= low && v <= high) || c.op == 112);
        return answer.map(|v| v as u64);
    }
    match c.kind {
        0 => primitive_reference!(c, i8, signed),
        1 => primitive_reference!(c, u8, unsigned),
        2 => primitive_reference!(c, i16, signed),
        3 => primitive_reference!(c, u16, unsigned),
        4 => primitive_reference!(c, i32, signed),
        5 => primitive_reference!(c, u32, unsigned),
        _ => panic!("invalid kind {c:?}"),
    }
}

#[test]
fn all_widths_match_rust_primitives_i128_and_python_models() {
    const SEED: u64 = 0x8320_2026_f15e_cafe;
    let mut seed = SEED;
    let mut random = || {
        seed ^= seed << 13;
        seed ^= seed >> 7;
        seed ^= seed << 17;
        seed
    };
    let mut edges = vec![
        0,
        1,
        2,
        3,
        u64::MAX,
        u64::MAX - 1,
        u64::MAX - 2,
        1 << 63,
        (1 << 63) - 1,
    ];
    for width in [8, 16, 32] {
        for boundary in [(1_u64 << (width - 1)), 1_u64 << width] {
            for delta in [-2_i64, -1, 0, 1, 2] {
                edges.push(boundary.wrapping_add_signed(delta));
            }
        }
        let third = ((1_u64 << (width - 1)) - 1) / 3;
        for value in [third, third + 1] {
            edges.push(value);
            edges.push(0_u64.wrapping_sub(value));
        }
    }
    edges.sort_unstable();
    edges.dedup();
    let shifts = [0, 1, 2, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, u32::MAX];
    let mut cases = Vec::new();
    let mut push = |c: Case| {
        if c.kind % 2 == 1 && [15, 34, 35, 36, 37, 38, 117].contains(&c.op) {
            return;
        }
        if c.kind % 2 == 0 && [114, 115, 116].contains(&c.op) {
            return;
        }
        let (_, _, width, signed) = integer_range(c.kind as usize);
        if (48..=50).contains(&c.op) && cast_numeric(c.b, width, signed) == 0 {
            return;
        }
        cases.push(c);
    };
    for kind in 0..6 {
        for op in 0..120 {
            for index in 0..80 {
                let a = edges.get(index).copied().unwrap_or_else(&mut random);
                let b = if index < edges.len() {
                    edges[(index * 11 + 7) % edges.len()]
                } else {
                    random()
                };
                push(Case {
                    kind,
                    op,
                    a,
                    b,
                    amount: shifts[index % shifts.len()],
                });
            }
        }
        for op in [
            0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 39, 43, 48, 49, 50, 112, 113, 114, 115, 116,
            117,
        ] {
            for &a in &edges {
                for &b in &edges {
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
    // All 65,536 input pairs for each checked byte arithmetic operation.
    // This catches narrowing, signed extension, and every byte overflow boundary.
    for kind in 0..2 {
        for op in [3, 4, 5] {
            for a in 0..256 {
                for b in 0..256 {
                    push(Case {
                        kind,
                        op,
                        a,
                        b,
                        amount: 0,
                    });
                }
            }
        }
    }
    assert!(cases.len() < 1_000_000);
    let count = cases.len();
    let mut input = (count as u32).to_le_bytes().to_vec();
    for c in &cases {
        input.extend_from_slice(&[c.kind, c.op, 0, 0]);
        input.extend_from_slice(&c.a.to_le_bytes());
        input.extend_from_slice(&c.b.to_le_bytes());
        input.extend_from_slice(&c.amount.to_le_bytes());
    }
    let exe = fixture("narrow_integer_model");
    let file = common::TempArtifact::new("laniusc_narrow_integers", "reference_input", None);
    file.write_bytes(&input);
    let output = common::process_output_with_timeout(
        "narrow integer model seed=0x83202026f15ecafe",
        Command::new(exe.path()).stdin(Stdio::from(std::fs::File::open(file.path()).unwrap())),
        std::time::Duration::from_secs(10),
    );
    assert_eq!(output.status.code(), Some(0), "{output:?}");
    assert!(output.stderr.is_empty(), "{output:?}");
    assert_eq!(output.stdout.len(), count * 12);
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
        .join("tests/fixtures/stdlib_foundation/narrow_integer_oracle.py");
    let independent = common::process_output_with_timeout(
        "Python arbitrary precision narrow integer oracle",
        Command::new("python3").arg(oracle).arg(exe.path()),
        std::time::Duration::from_secs(10),
    );
    assert!(independent.status.success(), "{independent:?}");
    assert!(independent.stderr.is_empty(), "{independent:?}");
    println!(
        "{count} narrow cases match Rust primitives/i128; {}",
        String::from_utf8_lossy(&independent.stdout).trim()
    );
}

#[test]
fn explicit_strict_preconditions_trap_in_all_six_modules() {
    let exe = fixture("narrow_integer_panics");
    let input = common::TempArtifact::new("laniusc_narrow_integers", "panic_input", None);
    let mut count = 0;
    for kind in 0_i32..6 {
        for op in 0_i32..if kind % 2 == 0 { 16 } else { 14 } {
            input.write_bytes(&[kind.to_le_bytes(), op.to_le_bytes()].concat());
            let output = common::signal_process_output_with_timeout(
                "narrow integer precondition",
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
    println!("{count} strict narrow preconditions trap with SIGILL");
}
