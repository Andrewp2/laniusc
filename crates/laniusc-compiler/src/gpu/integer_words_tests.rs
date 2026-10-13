//! Differential execution of production u32-limb helpers on a physical GPU.
//! The oracle uses native Rust integer operations, never the limb algorithms.
//! This checks helper semantics; native process exits and parser token ownership
//! are covered by compiler execution tests, not by this probe.

use super::{
    buffers::{readback_bytes, storage_ro_from_u32s, storage_rw_for_array, uniform_from_val},
    device,
    passes_core::{self, make_pass_data_from_shader_key, map_readback_blocking},
};

const SEED: u64 = 0x64da_1024_00ff_1357;
const OUTPUT_WORDS: usize = 27;
const SCALARS: [(u32, u32, bool); 10] = [
    (11, 8, true),
    (13, 8, false),
    (12, 16, true),
    (14, 16, false),
    (3, 32, true),
    (4, 32, false),
    (9, 64, true),
    (10, 64, false),
    (16, 64, true),
    (17, 64, false),
];
const FIELDS: [&str; OUTPUT_WORDS] = [
    "bits",
    "signed",
    "add.lo",
    "add.hi",
    "subtract.lo",
    "subtract.hi",
    "multiply.lo",
    "multiply.hi",
    "negate.lo",
    "negate.hi",
    "shl.lo",
    "shl.hi",
    "logical_shr.lo",
    "logical_shr.hi",
    "arithmetic_shr.lo",
    "arithmetic_shr.hi",
    "divide.status",
    "quotient.lo",
    "quotient.hi",
    "remainder.lo",
    "remainder.hi",
    "signed_less",
    "unsigned_less",
    "positive_magnitude_fits",
    "negative_magnitude_fits",
    "sign_extend.lo",
    "sign_extend.hi",
];

#[derive(encase::ShaderType)]
struct Params {
    query_count: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

struct Case {
    label: String,
    input: [u32; 8],
    expected: [u32; OUTPUT_WORDS],
}
#[derive(Default)]
struct Fixture {
    cases: Vec<Case>,
    decimal_bytes: Vec<u32>,
}

fn put(row: &mut [u32; OUTPUT_WORDS], field: usize, value: u64) {
    row[field] = value as u32;
    row[field + 1] = (value >> 32) as u32;
}

fn arithmetic_oracle(
    bits: u32,
    signed: bool,
    left: u64,
    right: u64,
    shift: u32,
) -> [u32; OUTPUT_WORDS] {
    let mut row = [0; OUTPUT_WORDS];
    row[0] = bits;
    row[1] = u32::from(signed);
    macro_rules! native_width {
        ($unsigned:ty, $signed:ty) => {{
            let a = left as $unsigned;
            let b = right as $unsigned;
            let sa = a as $signed;
            let sb = b as $signed;
            put(&mut row, 2, a.wrapping_add(b) as u64);
            put(&mut row, 4, a.wrapping_sub(b) as u64);
            put(&mut row, 6, a.wrapping_mul(b) as u64);
            put(&mut row, 8, a.wrapping_neg() as u64);
            put(&mut row, 10, a.checked_shl(shift).unwrap_or(0) as u64);
            put(&mut row, 12, a.checked_shr(shift).unwrap_or(0) as u64);
            put(
                &mut row,
                14,
                sa.checked_shr(shift).unwrap_or(0) as $unsigned as u64,
            );
            if b == 0 {
                row[16] = 103;
            } else if signed {
                if let (Some(quotient), Some(remainder)) = (sa.checked_div(sb), sa.checked_rem(sb))
                {
                    put(&mut row, 17, quotient as $unsigned as u64);
                    put(&mut row, 19, remainder as $unsigned as u64);
                } else {
                    row[16] = 104;
                }
            } else {
                put(&mut row, 17, (a / b) as u64);
                put(&mut row, 19, (a % b) as u64);
            }
            row[21] = u32::from(sa < sb);
            row[22] = u32::from(a < b);
            row[23] = u32::from(if signed {
                left <= <$signed>::MAX as u64
            } else {
                left <= <$unsigned>::MAX as u64
            });
            row[24] = u32::from(if signed {
                left <= (<$signed>::MAX as u64) + 1
            } else {
                left == 0
            });
            put(&mut row, 25, sa as i64 as u64);
        }};
    }
    match bits {
        8 => native_width!(u8, i8),
        16 => native_width!(u16, i16),
        32 => native_width!(u32, i32),
        64 => native_width!(u64, i64),
        _ => panic!("unsupported oracle width {bits}"),
    }
    row
}

impl Fixture {
    fn arithmetic(
        &mut self,
        scalar: u32,
        bits: u32,
        signed: bool,
        left: u64,
        right: u64,
        shift: u32,
    ) {
        self.cases.push(Case {
            label: format!("scalar={scalar} bits={bits} signed={signed} a={left:#018x} b={right:#018x} shift={shift}"),
            input: [0, scalar, left as u32, (left >> 32) as u32,
                right as u32, (right >> 32) as u32, shift, 0],
            expected: arithmetic_oracle(bits, signed, left, right, shift),
        });
    }

    fn decimal(&mut self, text: &str) {
        let start = self.decimal_bytes.len() as u32;
        self.decimal_bytes.extend(text.bytes().map(u32::from));
        let mut expected = [0; OUTPUT_WORDS];
        if let Ok(value) = text.parse::<u64>() {
            expected[0] = 1;
            put(&mut expected, 1, value);
        }
        self.cases.push(Case {
            label: format!("decimal {text:?}"),
            input: [1, 0, start, text.len() as u32, 0, 0, 0, 0],
            expected,
        });
    }

    fn append(&mut self, value: u64, digit: u32) {
        let mut expected = [0; OUTPUT_WORDS];
        if let Some(next) = (digit <= 9)
            .then(|| {
                value
                    .checked_mul(10)
                    .and_then(|value| value.checked_add(u64::from(digit)))
            })
            .flatten()
        {
            expected[0] = 1;
            put(&mut expected, 1, next);
        }
        self.cases.push(Case {
            label: format!("append value={value} digit={digit}"),
            input: [2, 0, value as u32, (value >> 32) as u32, 0, 0, digit, 0],
            expected,
        });
    }
}

fn next_random(state: &mut u64) -> u64 {
    // Fixture-only PRNG. The seed and every failing input are reported.
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}

fn fixture() -> Fixture {
    let mut f = Fixture::default();
    let mut state = SEED;
    for (scalar, bits, signed) in SCALARS {
        let maximum = u64::MAX >> (64 - bits);
        let sign_bit = 1u64 << (bits - 1);
        let mut boundaries = vec![
            0,
            1,
            2,
            3,
            9,
            10,
            sign_bit - 1,
            sign_bit,
            sign_bit + 1,
            maximum - 1,
            maximum,
            0xffff,
            0x1_0000,
            0xffff_ffff,
            0x1_0000_0000,
            0x7fff_ffff_ffff_ffff,
            0x8000_0000_0000_0000,
            u64::MAX,
        ];
        if bits < 64 {
            boundaries.push(maximum + 1);
        }
        boundaries.sort_unstable();
        boundaries.dedup();
        let shifts = [0, 1, 7, 8, 15, 16, 31, 32, 33, 63, 64, 65, u32::MAX];
        for (i, &a) in boundaries.iter().enumerate() {
            for (j, &b) in boundaries.iter().enumerate() {
                f.arithmetic(scalar, bits, signed, a, b, shifts[(i + j) % shifts.len()]);
            }
            for shift in shifts {
                f.arithmetic(scalar, bits, signed, a, 1, shift);
            }
        }
        for _ in 0..128 {
            let a = next_random(&mut state);
            let b = next_random(&mut state);
            let shift = (next_random(&mut state) % 66) as u32;
            f.arithmetic(scalar, bits, signed, a, b, shift);
        }
    }
    for text in [
        "0",
        "0000000000000000000000000000000000000000000000000000000000000000000000",
        "1",
        "127",
        "128",
        "255",
        "256",
        "32767",
        "32768",
        "65535",
        "65536",
        "2147483647",
        "2147483648",
        "4294967295",
        "4294967296",
        "9223372036854775807",
        "9223372036854775808",
        "18446744073709551615",
        "18446744073709551616",
        "00000000000000000000000000000018446744073709551615",
        "999999999999999999999999999999999999",
        "184467440737095516150",
        "1x",
        "9/",
        "1:",
    ] {
        f.decimal(text);
    }
    for _ in 0..128 {
        let value = next_random(&mut state);
        f.decimal(&value.to_string());
        f.decimal(&format!("0000000000000000000000000000000000000000{value}"));
        f.decimal(&format!("{value}00000000000000000000"));
    }
    for value in [
        0,
        1,
        u32::MAX as u64,
        0x1_0000_0000,
        u64::MAX / 10 - 1,
        u64::MAX / 10,
        u64::MAX / 10 + 1,
        u64::MAX,
    ] {
        for digit in [0, 1, 4, 5, 6, 9, 10, u32::MAX] {
            f.append(value, digit);
        }
    }
    // Noninteger and unknown identities must never admit an integer magnitude.
    for scalar in [0, 1, 2, 5, 6, 7, 8, 15, 18, 127, u32::MAX] {
        for value in [0u64, 1, u64::MAX] {
            f.cases.push(Case {
                label: format!("noninteger magnitude scalar={scalar} value={value}"),
                input: [3, scalar, value as u32, (value >> 32) as u32, 0, 0, 0, 0],
                expected: [0; OUTPUT_WORDS],
            });
        }
    }
    // These assertions prevent accidental corpus edits from dropping failures.
    assert!(f.cases.iter().any(|case| case.expected[16] == 103));
    for (scalar, _, signed) in SCALARS {
        if signed {
            assert!(f
                .cases
                .iter()
                .any(|case| case.input[1] == scalar && case.expected[16] == 104));
        }
    }
    f
}

#[test]
fn physical_gpu_integer_words_match_native_width_oracles() {
    assert!(
        !super::env::env_bool_truthy("LANIUS_ALLOW_SOFTWARE_ADAPTER", false),
        "this regression requires a physical GPU"
    );
    let f = fixture();
    let gpu = device::global();
    let params_value = Params {
        query_count: f.cases.len() as u32,
        reserved0: 0,
        reserved1: 0,
        reserved2: 0,
    };
    let query_words: Vec<u32> = f.cases.iter().flat_map(|case| case.input).collect();
    let params = uniform_from_val(&gpu.device, "integer_probe.params", &params_value);
    let queries = storage_ro_from_u32s(&gpu.device, "integer_probe.queries", &query_words);
    let decimal_bytes =
        storage_ro_from_u32s(&gpu.device, "integer_probe.decimal_bytes", &f.decimal_bytes);
    let word_count = f.cases.len() * OUTPUT_WORDS;
    let results = storage_rw_for_array::<u32>(&gpu.device, "integer_probe.results", word_count);
    let pass = make_pass_data_from_shader_key(
        &gpu.device,
        "test.integer_words",
        "main",
        "tests/integer_words_probe",
    )
    .unwrap();
    let entries = [
        ("gParams", params.as_entire_binding()),
        ("queries", queries.as_entire_binding()),
        ("decimal_bytes", decimal_bytes.as_entire_binding()),
        ("results", results.as_entire_binding()),
    ];
    passes_core::bind_group::validate_exact_binding_names(&pass, 0, &entries).unwrap();
    let group = passes_core::bind_group::create_bind_group_from_bindings(
        &gpu.device,
        Some("integer_probe.group"),
        &pass,
        0,
        &entries,
    )
    .unwrap();
    let (x, y, z) = passes_core::plan_workgroups(
        passes_core::DispatchDim::D1,
        passes_core::InputElements::Elements1D(params_value.query_count),
        pass.thread_group_size,
    )
    .unwrap();
    let byte_count = word_count * 4;
    let readback = readback_bytes(
        &gpu.device,
        "integer_probe.readback",
        byte_count,
        word_count,
    );
    let mut encoder = gpu
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("integer_probe.encoder"),
        });
    {
        let mut compute = passes_core::begin_counted_compute_pass(
            &mut encoder,
            &wgpu::ComputePassDescriptor {
                label: Some("integer_probe.compute"),
                timestamp_writes: None,
            },
        );
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(&group), &[]);
        passes_core::record_compute_dispatch();
        compute.dispatch_workgroups(x, y, z);
    }
    results.copy_to(&mut encoder, 0, &readback, 0, byte_count as u64);
    gpu.queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    map_readback_blocking(&gpu.device, &slice, "integer_probe.readback").unwrap();
    let mapped = slice.get_mapped_range();
    let words: Vec<_> = mapped
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect();
    drop(mapped);
    readback.unmap();
    assert_eq!(words.len(), word_count);
    for (index, (case, row)) in f
        .cases
        .iter()
        .zip(words.chunks_exact(OUTPUT_WORDS))
        .enumerate()
    {
        for field in 0..OUTPUT_WORDS {
            assert_eq!(
                row[field], case.expected[field],
                "seed={SEED:#018x} case={index} kind={} field={field} ({}) {}",
                case.input[0], FIELDS[field], case.label
            );
        }
    }
    eprintln!(
        "integer helper differential probe: {} cases, one dispatch, seed={SEED:#018x}",
        f.cases.len()
    );
}
