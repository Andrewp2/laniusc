//! Physical-GPU differential coverage for exact decimal conversion.
//! Rust's native parsers and fixed IEEE bit vectors are independent oracles;
//! this test contains no decimal-to-binary conversion algorithm.

use super::{
    buffers::{readback_bytes, storage_ro_from_u32s, storage_rw_for_array, uniform_from_val},
    device,
    passes_core::{self, make_pass_data_from_shader_key, map_readback_blocking},
};

const SEED: u64 = 0xdec1_0a17_7680_0053;
const WORKSPACE_WORDS: usize = 768;
const WORKSPACE_STRIDE: usize = WORKSPACE_WORDS + 2;
const GUARD: u32 = 0xa53c_d719;
const OK: u32 = 0;
const INVALID_SYNTAX: u32 = 1;
const OVERFLOW: u32 = 2;
const INVALID_SCALAR: u32 = 3;
const INVALID_SPAN: u32 = 4;
const INVALID_WORKSPACE: u32 = 5;

#[derive(encase::ShaderType)]
struct Params {
    query_count: u32,
    source_len: u32,
    workspace_words: u32,
    workspace_stride: u32,
}

struct Case {
    label: String,
    query: [u32; 8],
    expected: [u32; 4], // status, low bits, high bits, consumed
}
#[derive(Default)]
struct Fixture {
    source: Vec<u8>,
    cases: Vec<Case>,
}

fn expected_bits(status: u32, bits: u64, consumed: u32) -> [u32; 4] {
    [status, bits as u32, (bits >> 32) as u32, consumed]
}

fn oracle(text: &str, scalar: u32, negative: bool) -> [u32; 4] {
    // Only the known-valid corpus reaches this oracle. Separator removal is
    // guarded so an accidental malformed fixture cannot be made valid here.
    let bytes = text.as_bytes();
    for (index, &byte) in bytes.iter().enumerate() {
        if byte == b'_' {
            assert!(index > 0 && index + 1 < bytes.len());
            assert!(bytes[index - 1].is_ascii_digit() && bytes[index + 1].is_ascii_digit());
        }
    }
    let normalized = text.replace('_', "");
    let (finite, bits) = match scalar {
        5 => {
            let value = normalized.parse::<f32>().expect("valid f32 fixture");
            let value = if negative { -value } else { value };
            (value.is_finite(), u64::from(value.to_bits()))
        }
        15 => {
            let value = normalized.parse::<f64>().expect("valid f64 fixture");
            let value = if negative { -value } else { value };
            (value.is_finite(), value.to_bits())
        }
        _ => panic!("invalid oracle scalar {scalar}"),
    };
    expected_bits(
        if finite { OK } else { OVERFLOW },
        if finite { bits } else { 0 },
        text.len() as u32,
    )
}

impl Fixture {
    fn push(&mut self, text: &str, scalar: u32, negative: bool, expected: [u32; 4]) {
        // Cover all four token byte alignments. Nondecimal fences expose a
        // decoder that scans past the supplied span instead of its full length.
        let alignment = self.cases.len() % 4;
        self.source.push(0xa5);
        while self.source.len() % 4 != alignment {
            self.source.push(0xa5);
        }
        let start = self.source.len() as u32;
        self.source.extend_from_slice(text.as_bytes());
        self.source.push(0xa5);
        self.cases.push(Case {
            label: format!("scalar={scalar} negative={negative} token={text:?}"),
            query: [
                scalar,
                u32::from(negative),
                start,
                text.len() as u32,
                0,
                0,
                0,
                0,
            ],
            expected,
        });
    }
    fn valid(&mut self, text: &str) {
        for scalar in [5, 15] {
            for negative in [false, true] {
                self.push(text, scalar, negative, oracle(text, scalar, negative));
            }
        }
    }
    fn fixed(&mut self, text: &str, scalar: u32, magnitude_bits: u64) {
        for negative in [false, true] {
            let sign = if scalar == 5 { 1u64 << 31 } else { 1u64 << 63 };
            let bits = magnitude_bits | if negative { sign } else { 0 };
            let expected = expected_bits(OK, bits, text.len() as u32);
            assert_eq!(
                oracle(text, scalar, negative),
                expected,
                "fixed vector {text}"
            );
            self.push(text, scalar, negative, expected);
        }
    }
}

fn next_random(state: &mut u64) -> u64 {
    *state ^= *state << 13;
    *state ^= *state >> 7;
    *state ^= *state << 17;
    *state
}

fn separated_digits(text: &str) -> String {
    // Generate a lexically valid variant; do not implement numeric parsing.
    let bytes = text.as_bytes();
    let mut result = String::new();
    for (index, &byte) in bytes.iter().enumerate() {
        if index != 0 && byte.is_ascii_digit() && bytes[index - 1].is_ascii_digit() {
            result.push('_');
        }
        result.push(char::from(byte));
    }
    result
}

fn fixture() -> Fixture {
    let mut f = Fixture::default();
    // Fixed bits follow IEEE binary32/binary64 nearest-even representation.
    for (scalar, text, bits) in [
        (5, "0.0", 0),
        (15, "0.0", 0),
        (5, "1.0", 0x3f80_0000),
        (15, "1.0", 0x3ff0_0000_0000_0000),
        (5, ".5", 0x3f00_0000),
        (15, ".5", 0x3fe0_0000_0000_0000),
        (5, "16777217", 0x4b80_0000),
        (5, "16777219", 0x4b80_0002),
        (15, "9007199254740993", 0x4340_0000_0000_0000),
        (5, "1.000000059604644775390625", 0x3f80_0000),
        (5, "1.000000178813934326171875", 0x3f80_0002),
        (
            15,
            "1.00000000000000011102230246251565404236316680908203125",
            0x3ff0_0000_0000_0000,
        ),
        (
            15,
            "1.00000000000000033306690738754696212708950042724609375",
            0x3ff0_0000_0000_0002,
        ),
        (5, "1.401298464324817e-45", 1),
        (5, "7.006492321624085e-46", 0),
        (5, "7.006492321624086e-46", 1),
        (5, "1.1754942106924411e-38", 0x007f_ffff),
        (5, "1.1754943508222875e-38", 0x0080_0000),
        (5, "3.4028234663852886e38", 0x7f7f_ffff),
        (15, "4.9406564584124654e-324", 1),
        (15, "2.4703282292062327e-324", 0),
        (15, "2.4703282292062328e-324", 1),
        (15, "2.225073858507201e-308", 0x000f_ffff_ffff_ffff),
        (15, "2.2250738585072014e-308", 0x0010_0000_0000_0000),
        (15, "1.7976931348623157e308", 0x7fef_ffff_ffff_ffff),
    ] {
        f.fixed(text, scalar, bits);
    }
    // A tail after digit 768 decides above/below a tie. These also catch a
    // binary64 intermediate incorrectly rounding a binary32 literal twice.
    for (scalar, halfway, below_prefix, even_bits, above_bits) in [
        (
            5,
            "1.000000059604644775390625",
            "1.000000059604644775390624",
            0x3f80_0000,
            0x3f80_0001,
        ),
        (
            15,
            "1.00000000000000011102230246251565404236316680908203125",
            "1.00000000000000011102230246251565404236316680908203124",
            0x3ff0_0000_0000_0000,
            0x3ff0_0000_0000_0001,
        ),
    ] {
        f.fixed(&format!("{halfway}{}", "0".repeat(820)), scalar, even_bits);
        f.fixed(
            &format!("{halfway}{}1", "0".repeat(820)),
            scalar,
            above_bits,
        );
        f.fixed(
            &format!("{below_prefix}{}", "9".repeat(820)),
            scalar,
            even_bits,
        );
    }
    for text in [
        "0",
        "1",
        "1.",
        ".0",
        "1.e2",
        "1E+2",
        "1e-2",
        "00.00100",
        "1_2_3.4_5e+0_2",
        ".1_2e-0_3",
        "0_0.0_0e9_9_9_9_9",
        "0e99999999999999999999999999",
        "0e-99999999999999999999999999",
        "1e99999999999999999999999999",
        "1e-99999999999999999999999999",
        "3.4028235677973366e38",
        "3.4028235677973367e38",
        "1.7976931348623158e308",
        "1.7976931348623159e308",
        "1e-400",
        "1e400",
        "2.2250738585072011e-308",
        "2.2250738585072012e-308",
        "9.999999999999999999999999999999999999999e-39",
    ] {
        f.valid(text);
    }
    f.valid(&format!("{}1.{}25e+0", "0".repeat(850), "0".repeat(850)));
    f.valid(&format!("0.{}1", "0".repeat(850)));
    f.valid(&format!("1{}e-850", "0".repeat(850)));
    f.valid(&format!("1.0e+{}2", "0".repeat(850)));
    // Cancellation must precede decimal-position saturation at +/-4096.
    f.valid(&format!("1{}e-5000", "0".repeat(5000)));
    f.valid(&format!("0.{}1e5001", "0".repeat(5000)));
    f.valid(&format!("1{}e-5001", "0".repeat(5000)));
    let mut state = SEED;
    let exponents = [
        -400, -325, -324, -323, -309, -308, -307, -46, -45, -44, -39, -38, -37, -1, 0, 1, 37, 38,
        39, 307, 308, 309, 400,
    ];
    for index in 0..128 {
        let integer = next_random(&mut state);
        let fraction = next_random(&mut state);
        let exponent = exponents[index % exponents.len()];
        let text = format!("{integer}.{fraction:020}e{exponent:+}");
        f.valid(&text);
        if index % 8 == 0 {
            f.valid(&separated_digits(&text));
        }
    }
    // Syntax failures must consume the entire bounded token and return zero
    // bits, including a malformed tail after an already-overflowing prefix.
    for text in [
        "",
        ".",
        "+1.0",
        "-1.0",
        "NaN",
        "inf",
        "Infinity",
        "0x1.0",
        "0b1.0",
        "1e",
        "1e+",
        "1e-",
        "1ee2",
        "1e+-2",
        "1.2.3",
        "1 2",
        " 1.0",
        "1.0 ",
        "_1.0",
        "1_.0",
        "1._0",
        "1__0.0",
        "1.0_",
        ".1_",
        "1.0e_2",
        "1.0e+_2",
        "1.0e2_",
        "1.0e2__3",
        "1.0x",
        "1e99999999999999999999999999x",
        "1.0\0",
    ] {
        for scalar in [5, 15] {
            f.push(
                text,
                scalar,
                false,
                expected_bits(INVALID_SYNTAX, 0, text.len() as u32),
            );
        }
    }
    for scalar in [0, 1, 2, 3, 9, 14, 16, 17, 18, u32::MAX] {
        f.push("1.25", scalar, false, expected_bits(INVALID_SCALAR, 0, 0));
    }
    // Isolate each argument failure, preserving otherwise valid arguments.
    for (start, len) in [(u32::MAX, 1), (u32::MAX - 1, 4), (0, u32::MAX)] {
        f.push("1.25", 15, false, expected_bits(INVALID_SPAN, 0, 0));
        let query = &mut f.cases.last_mut().unwrap().query;
        query[2] = start;
        query[3] = len;
    }
    // The logical source extent itself cannot exceed the actual binding.
    f.push("1.25", 15, false, expected_bits(INVALID_SPAN, 0, 0));
    let query = &mut f.cases.last_mut().unwrap().query;
    query[6] = u32::MAX;
    query[7] = 1;
    for workspace_base in [u32::MAX, u32::MAX - WORKSPACE_WORDS as u32 + 1] {
        f.push("1.25", 15, false, expected_bits(INVALID_WORKSPACE, 0, 0));
        let query = &mut f.cases.last_mut().unwrap().query;
        query[4] = 1;
        query[5] = workspace_base;
    }
    f.push("1.25", 15, false, expected_bits(INVALID_WORKSPACE, 0, 0));
    let too_late = f.cases.len() * WORKSPACE_STRIDE - WORKSPACE_WORDS + 1;
    let query = &mut f.cases.last_mut().unwrap().query;
    query[4] = 1;
    query[5] = too_late as u32;
    assert!(f.cases.iter().any(|case| case.expected[0] == OVERFLOW));
    assert!(f
        .cases
        .iter()
        .any(|case| case.expected[1..3] == [0, 0x8000_0000]));
    f
}

fn decode_words(bytes: &[u8]) -> Vec<u32> {
    bytes
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect()
}

#[test]
fn physical_gpu_float_decimal_matches_native_rounding_and_bounds() {
    assert!(
        !super::env::env_bool_truthy("LANIUS_ALLOW_SOFTWARE_ADAPTER", false),
        "this regression requires a physical GPU"
    );
    let mut f = fixture();
    let source_len = f.source.len();
    while f.source.len() % 4 != 0 {
        f.source.push(0xa5);
    }
    let gpu = device::global();
    let params = uniform_from_val(
        &gpu.device,
        "float_probe.params",
        &Params {
            query_count: f.cases.len() as u32,
            source_len: source_len as u32,
            workspace_words: WORKSPACE_WORDS as u32,
            workspace_stride: WORKSPACE_STRIDE as u32,
        },
    );
    let query_words: Vec<u32> = f.cases.iter().flat_map(|case| case.query).collect();
    let queries = storage_ro_from_u32s(&gpu.device, "float_probe.queries", &query_words);
    let source = storage_ro_from_u32s(&gpu.device, "float_probe.source", &decode_words(&f.source));
    let workspace_count = f.cases.len() * WORKSPACE_STRIDE;
    let workspace =
        storage_rw_for_array::<u32>(&gpu.device, "float_probe.workspace", workspace_count);
    let guarded_bytes: Vec<u8> = (0..workspace_count)
        .flat_map(|_| GUARD.to_le_bytes())
        .collect();
    workspace.write(&gpu.queue, 0, &guarded_bytes);
    let result_count = f.cases.len() * 5;
    let results = storage_rw_for_array::<u32>(&gpu.device, "float_probe.results", result_count);
    let pass = make_pass_data_from_shader_key(
        &gpu.device,
        "test.float_decimal",
        "main",
        "tests/float_decimal_probe",
    )
    .unwrap();
    let entries = [
        ("gParams", params.as_entire_binding()),
        ("queries", queries.as_entire_binding()),
        ("source_bytes", source.as_entire_binding()),
        ("workspace", workspace.as_entire_binding()),
        ("results", results.as_entire_binding()),
    ];
    passes_core::bind_group::validate_exact_binding_names(&pass, 0, &entries).unwrap();
    let group = passes_core::bind_group::create_bind_group_from_bindings(
        &gpu.device,
        Some("float_probe.group"),
        &pass,
        0,
        &entries,
    )
    .unwrap();
    let (x, y, z) = passes_core::plan_workgroups(
        passes_core::DispatchDim::D1,
        passes_core::InputElements::Elements1D(f.cases.len() as u32),
        pass.thread_group_size,
    )
    .unwrap();
    let readback = readback_bytes(
        &gpu.device,
        "float_probe.readback",
        result_count * 4,
        result_count,
    );
    let workspace_readback = readback_bytes(
        &gpu.device,
        "float_probe.workspace_readback",
        workspace_count * 4,
        workspace_count,
    );
    let mut encoder = gpu
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("float_probe.encoder"),
        });
    {
        let mut compute = passes_core::begin_counted_compute_pass(
            &mut encoder,
            &wgpu::ComputePassDescriptor {
                label: Some("float_probe.compute"),
                timestamp_writes: None,
            },
        );
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(&group), &[]);
        passes_core::record_compute_dispatch();
        if !crate::gpu::passes_core::debug_operation_skipped() {
            compute.dispatch_workgroups(x, y, z);
        }
    }
    results.copy_to(&mut encoder, 0, &readback, 0, (result_count * 4) as u64);
    workspace.copy_to(
        &mut encoder,
        0,
        &workspace_readback,
        0,
        (workspace_count * 4) as u64,
    );
    gpu.queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    map_readback_blocking(&gpu.device, &slice, "float_probe.readback").unwrap();
    let mapped = slice.get_mapped_range();
    let words = decode_words(&mapped);
    drop(mapped);
    readback.unmap();
    let slice = workspace_readback.slice(..);
    map_readback_blocking(&gpu.device, &slice, "float_probe.workspace_readback").unwrap();
    let mapped = slice.get_mapped_range();
    let workspace_words = decode_words(&mapped);
    drop(mapped);
    workspace_readback.unmap();
    assert_eq!(words.len(), result_count);
    assert_eq!(workspace_words.len(), workspace_count);
    for (index, (case, row)) in f.cases.iter().zip(words.chunks_exact(5)).enumerate() {
        assert_eq!(
            row[4], WORKSPACE_WORDS as u32,
            "helper workspace contract changed"
        );
        assert_eq!(
            &row[..4],
            &case.expected,
            "seed={SEED:#018x} case={index} {} query={:?}",
            case.label,
            case.query
        );
        assert_eq!(
            workspace_words[index * WORKSPACE_STRIDE],
            GUARD,
            "workspace leading guard changed at case {index}: {}",
            case.label
        );
        assert_eq!(
            workspace_words[(index + 1) * WORKSPACE_STRIDE - 1],
            GUARD,
            "workspace trailing guard changed at case {index}: {}",
            case.label
        );
    }
    eprintln!(
        "float decimal probe: {} cases, one dispatch, seed={SEED:#018x}",
        f.cases.len()
    );
}
