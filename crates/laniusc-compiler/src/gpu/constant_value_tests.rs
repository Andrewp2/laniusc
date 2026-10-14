//! Execute shared atom admission and count conversion on a physical GPU.
//! Native u128 arithmetic supplies the oracle, independently of u32 limb code.
use super::{
    buffers::{readback_bytes, storage_ro_from_u32s, storage_rw_for_array, uniform_from_val},
    device,
    passes_core::{self, make_pass_data_from_shader_key, map_readback_blocking},
};
use crate::constant_value::CheckedConstantValue;

const SEED: u64 = 0x6c61_6e69_7573_0031;
const OUTPUT_WORDS: usize = 16;
const INTEGER_SCALARS: [(u32, u32, bool); 10] = [
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
#[derive(encase::ShaderType)]
struct Params {
    query_count: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}
struct Case {
    input: [u32; 6],
    expected: [u32; OUTPUT_WORDS],
}

fn integer(scalar: u32) -> Option<(u32, bool)> {
    INTEGER_SCALARS
        .iter()
        .find(|row| row.0 == scalar)
        .map(|row| (row.1, row.2))
}
fn valid(scalar: u32, raw: u64) -> bool {
    match scalar {
        2 => raw <= 1,
        6 => u32::try_from(raw).ok().and_then(char::from_u32).is_some(),
        5 => u32::try_from(raw).is_ok(),
        15 => true,
        _ => integer(scalar).is_some_and(|(bits, _)| u128::from(raw) < (1u128 << bits)),
    }
}
fn magnitude(scalar: u32, raw: u64, negative: bool) -> Option<[u32; 3]> {
    let (bits, signed) = integer(scalar)?;
    let limit = if signed {
        (1u128 << (bits - 1)) - u128::from(!negative)
    } else if negative {
        0
    } else {
        (1u128 << bits) - 1
    };
    if u128::from(raw) > limit {
        return None;
    }
    let word = if negative { raw.wrapping_neg() } else { raw };
    let mask = ((1u128 << bits) - 1) as u64;
    let value = word & mask;
    Some([scalar, value as u32, (value >> 32) as u32])
}
fn case(scalar: u32, raw: u64, other_scalar: u32, other: u64) -> Case {
    let input = [
        scalar,
        raw as u32,
        (raw >> 32) as u32,
        other_scalar,
        other as u32,
        (other >> 32) as u32,
    ];
    let mut expected = [0; OUTPUT_WORDS];
    expected[0] = u32::from(valid(scalar, raw));
    if valid(scalar, raw)
        && u32::try_from(raw).is_ok()
        && integer(scalar).is_some_and(|(bits, signed)| !signed || raw & (1u64 << (bits - 1)) == 0)
    {
        expected[1] = 1;
        expected[2] = raw as u32;
    }
    for (offset, value) in [
        (3, magnitude(scalar, raw, false)),
        (7, magnitude(scalar, raw, true)),
        (12, magnitude(scalar, raw as u32 as u64, false)),
    ] {
        if let Some(value) = value {
            expected[offset] = 1;
            expected[offset + 1..offset + 4].copy_from_slice(&value);
        }
    }
    expected[11] = u32::from(
        valid(scalar, raw) && valid(other_scalar, other) && scalar == other_scalar && raw == other,
    );
    Case { input, expected }
}
fn fixture() -> Vec<Case> {
    let mut cases = Vec::new();
    let mut state = SEED;
    for (scalar, bits, _) in INTEGER_SCALARS {
        let sign = 1u64 << (bits - 1);
        let max = ((1u128 << bits) - 1) as u64;
        let mut values = vec![
            0,
            1,
            2,
            sign - 1,
            sign,
            sign + 1,
            max,
            u32::MAX as u64,
            1u64 << 32,
            u64::MAX,
        ];
        if bits < 64 {
            values.push(max + 1);
        }
        for _ in 0..64 {
            state ^= state << 13;
            state ^= state >> 7;
            state ^= state << 17;
            values.push(state);
            values.push(state & max);
        }
        for raw in values {
            cases.push(case(scalar, raw, scalar, raw));
            cases.push(case(scalar, raw, scalar, raw ^ (1u64 << 32)));
            cases.push(case(scalar, raw, if scalar == 4 { 3 } else { 4 }, raw));
        }
    }
    for scalar in [0, 1, 2, 5, 6, 7, 8, 15, 18, u32::MAX] {
        for raw in [
            0,
            1,
            2,
            0x7f,
            0xd7ff,
            0xd800,
            0xdfff,
            0xe000,
            0x10ffff,
            0x110000,
            0x80000000,
            0x7fc00001,
            0x7fc00002,
            u32::MAX as u64,
            1u64 << 32,
            0x8000000000000000,
            0x7ff8000000000001,
            u64::MAX,
        ] {
            cases.push(case(scalar, raw, scalar, raw));
            cases.push(case(scalar, raw, scalar, raw ^ 1));
        }
    }
    cases
}

#[test]
fn physical_gpu_typed_constant_atoms_preserve_complete_values_and_checked_counts() {
    assert!(
        !super::env::env_bool_truthy("LANIUS_ALLOW_SOFTWARE_ADAPTER", false),
        "this regression requires a physical GPU"
    );
    let cases = fixture();
    // The portable host validator must accept the same wire domain as the GPU.
    for (index, case) in cases.iter().enumerate() {
        let actual =
            CheckedConstantValue::from_words(case.input[0], [case.input[1], case.input[2]]);
        assert_eq!(
            actual.is_some(),
            case.expected[0] != 0,
            "host admission case {index}"
        );
        assert_eq!(
            actual.and_then(CheckedConstantValue::count),
            (case.expected[1] != 0).then_some(case.expected[2]),
            "host count case {index}"
        );
    }
    let gpu = device::global();
    let params_value = Params {
        query_count: cases.len() as u32,
        reserved0: 0,
        reserved1: 0,
        reserved2: 0,
    };
    let query_words = cases.iter().flat_map(|case| case.input).collect::<Vec<_>>();
    let params = uniform_from_val(&gpu.device, "constant_probe.params", &params_value);
    let queries = storage_ro_from_u32s(&gpu.device, "constant_probe.queries", &query_words);
    let word_count = cases.len() * OUTPUT_WORDS;
    let results = storage_rw_for_array::<u32>(&gpu.device, "constant_probe.results", word_count);
    let pass = make_pass_data_from_shader_key(
        &gpu.device,
        "test.constant_value",
        "main",
        "tests/constant_value_probe",
    )
    .unwrap();
    let entries = [
        ("gParams", params.as_entire_binding()),
        ("queries", queries.as_entire_binding()),
        ("results", results.as_entire_binding()),
    ];
    passes_core::bind_group::validate_exact_binding_names(&pass, 0, &entries).unwrap();
    let group = passes_core::bind_group::create_bind_group_from_bindings(
        &gpu.device,
        Some("constant_probe.group"),
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
        "constant_probe.readback",
        byte_count,
        word_count,
    );
    let mut encoder = gpu
        .device
        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("constant_probe.encoder"),
        });
    {
        let mut compute = passes_core::begin_counted_compute_pass(
            &mut encoder,
            &wgpu::ComputePassDescriptor {
                label: Some("constant_probe.compute"),
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
    results.copy_to(&mut encoder, 0, &readback, 0, byte_count as u64);
    gpu.queue.submit(Some(encoder.finish()));
    let slice = readback.slice(..);
    map_readback_blocking(&gpu.device, &slice, "constant_probe.readback").unwrap();
    let mapped = slice.get_mapped_range();
    let words = mapped
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect::<Vec<_>>();
    drop(mapped);
    readback.unmap();
    assert_eq!(words.len(), word_count);
    for (index, (case, row)) in cases
        .iter()
        .zip(words.chunks_exact(OUTPUT_WORDS))
        .enumerate()
    {
        assert_eq!(
            row, case.expected,
            "seed={SEED:#018x} case={index} input={:?}",
            case.input
        );
    }
    eprintln!(
        "typed constant atom probe: {} cases, one dispatch, seed={SEED:#018x}",
        cases.len()
    );
}
