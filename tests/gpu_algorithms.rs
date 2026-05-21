mod common;

use std::{
    collections::HashMap,
    env,
    fs,
    path::{Path, PathBuf},
    process::Command,
    sync::mpsc,
};

use laniusc::gpu::{
    device,
    passes_core::{bind_group, make_pass_data},
};
use wgpu::util::DeviceExt;

const TEST_COUNT: usize = 256;
const SORTED_COUNT: usize = 64;
const QUERY_COUNT: usize = 32;
const COMPACT_COUNT: usize = 170;
const SCATTER_PAIR_BASE: usize = TEST_COUNT + 1;
const SCATTER_RESERVATION_CAPACITY: usize = 64;
const SCATTER_RESERVATION_BASE: usize = SCATTER_PAIR_BASE + (COMPACT_COUNT + 1) * 2;
const SCATTER_STORE_WORDS: usize = SCATTER_RESERVATION_BASE + 1 + SCATTER_RESERVATION_CAPACITY;
const STABLE_BUCKET_COUNT: usize = 8;
const SUMMARY_WORDS: usize = 4;
const INTERVAL_WORDS: usize = 121;
const INVALID: u32 = 0xffff_ffff;

#[test]
fn generic_gpu_algorithms_match_cpu_oracles() {
    common::block_on_gpu_with_timeout("generic GPU algorithm helper validation", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_validation_shader(&root);

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.gpu_algorithms.validate",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create algorithm validation pass");

        let inputs = AlgorithmInputs::new();
        let expected = ExpectedOutputs::from_inputs(&inputs);

        let buffers = AlgorithmBuffers::new(device, &inputs);
        let bindings = buffers.bindings();
        let resources = bindings
            .iter()
            .map(|(name, resource)| ((*name).to_string(), resource.clone()))
            .collect::<HashMap<_, _>>();
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.gpu_algorithms.validate.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
        .expect("create algorithm validation bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.gpu_algorithms.validate.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.gpu_algorithms.validate.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        copy_to_readback(
            &mut encoder,
            &buffers.segmented_out,
            &buffers.segmented_readback,
        );
        copy_to_readback(&mut encoder, &buffers.rank_out, &buffers.rank_readback);
        copy_to_readback(
            &mut encoder,
            &buffers.radix_byte_out,
            &buffers.radix_byte_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.radix_field_out,
            &buffers.radix_field_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.query1_begin_out,
            &buffers.query1_begin_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.query1_end_out,
            &buffers.query1_end_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.query2_row_out,
            &buffers.query2_row_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.query4_row_out,
            &buffers.query4_row_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.scan_step_out,
            &buffers.scan_step_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.scan_seed_out,
            &buffers.scan_seed_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.flat_summary_step_out,
            &buffers.flat_summary_step_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.flat_summary_seed_out,
            &buffers.flat_summary_seed_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.scatter_store_out,
            &buffers.scatter_store_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.stable_scatter_out,
            &buffers.stable_scatter_readback,
        );
        copy_to_readback(
            &mut encoder,
            &buffers.interval_out,
            &buffers.interval_readback,
        );
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &buffers.segmented_readback, TEST_COUNT),
            expected.segmented,
            "segmented scan output should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.rank_readback, TEST_COUNT),
            expected.rank,
            "local same-key rank output should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.radix_byte_readback, TEST_COUNT),
            expected.radix_byte,
            "radix byte output should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.radix_field_readback, TEST_COUNT),
            expected.radix_field,
            "radix field output should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.query1_begin_readback, QUERY_COUNT),
            expected.query1_begin,
            "equal_range_query begin should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.query1_end_readback, QUERY_COUNT),
            expected.query1_end,
            "equal_range_query end should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.query2_row_readback, QUERY_COUNT),
            expected.query2_row,
            "find_equal_query for pair keys should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.query4_row_readback, QUERY_COUNT),
            expected.query4_row,
            "find_equal_query for quad keys should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.scan_step_readback, TEST_COUNT),
            expected.scan_step,
            "parallel_scan_step_value nonzero step should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.scan_seed_readback, TEST_COUNT),
            expected.scan_seed,
            "parallel_scan_step_value seed step should match CPU oracle"
        );
        assert_eq!(
            read_u32s(
                device,
                &buffers.flat_summary_step_readback,
                TEST_COUNT * SUMMARY_WORDS
            ),
            expected.flat_summary_step,
            "parallel_scan_step_u32x4_flat nonzero step should match CPU oracle"
        );
        assert_eq!(
            read_u32s(
                device,
                &buffers.flat_summary_seed_readback,
                TEST_COUNT * SUMMARY_WORDS
            ),
            expected.flat_summary_seed,
            "parallel_scan_step_u32x4_flat seed step should match CPU oracle"
        );
        assert_eq!(
            read_u32s(device, &buffers.scatter_store_readback, SCATTER_STORE_WORDS),
            expected.scatter_store,
            "scatter helpers should write direct stores, compact sink stores, and atomic reservations"
        );
        assert_eq!(
            read_u32s(device, &buffers.stable_scatter_readback, TEST_COUNT),
            expected.stable_scatter,
            "stable radix scatter helper should preserve per-bucket order"
        );
        assert_eq!(
            read_u32s(device, &buffers.interval_readback, INTERVAL_WORDS),
            expected.interval,
            "interval, packed-key, bitset, status, row-major, and index helpers should match CPU oracle"
        );
    });
}

struct AlgorithmInputs {
    values: Vec<u32>,
    segment_heads: Vec<u32>,
    rank_keys: Vec<u32>,
    key_steps: Vec<u32>,
    sorted1: Vec<u32>,
    query1: Vec<u32>,
    sorted2_a: Vec<u32>,
    sorted2_b: Vec<u32>,
    query2_a: Vec<u32>,
    query2_b: Vec<u32>,
    sorted4_a: Vec<u32>,
    sorted4_b: Vec<u32>,
    sorted4_c: Vec<u32>,
    sorted4_d: Vec<u32>,
    query4_a: Vec<u32>,
    query4_b: Vec<u32>,
    query4_c: Vec<u32>,
    query4_d: Vec<u32>,
    flat_summary_in: Vec<u32>,
    stable_bucket_base: Vec<u32>,
    stable_block_bucket_prefix: Vec<u32>,
}

impl AlgorithmInputs {
    fn new() -> Self {
        let values = (0..TEST_COUNT)
            .map(|i| ((i as u32 * 17 + 5) % 11) + 1)
            .collect::<Vec<_>>();
        let mut segment_heads = (0..TEST_COUNT)
            .map(|i| {
                let x = i as u32;
                u32::from(i == 0 || x % 13 == 0 || (x * 7 + 3) % 29 == 0)
            })
            .collect::<Vec<_>>();
        segment_heads[0] = 1;
        let rank_keys = (0..TEST_COUNT)
            .map(|i| ((i as u32 * 19 + 7) % 9) + 1)
            .collect::<Vec<_>>();
        let key_steps = (0..TEST_COUNT)
            .map(|i| (i as u32 * 5) % 16)
            .collect::<Vec<_>>();

        let sorted1 = (0..SORTED_COUNT)
            .map(|i| ((i as u32) / 3) * 2)
            .collect::<Vec<_>>();
        let query1 = (0..QUERY_COUNT)
            .map(|i| ((i as u32 * 5) % 48) / 2)
            .collect::<Vec<_>>();

        let sorted2_a = (0..SORTED_COUNT)
            .map(|i| (i as u32) / 8)
            .collect::<Vec<_>>();
        let sorted2_b = (0..SORTED_COUNT)
            .map(|i| ((i as u32) % 8) * 2)
            .collect::<Vec<_>>();
        let query2_a = (0..QUERY_COUNT)
            .map(|i| (i as u32 * 3) % 10)
            .collect::<Vec<_>>();
        let query2_b = (0..QUERY_COUNT)
            .map(|i| ((i as u32 * 5) % 10) * 2)
            .collect::<Vec<_>>();

        let sorted4_a = (0..SORTED_COUNT)
            .map(|i| (i as u32) / 16)
            .collect::<Vec<_>>();
        let sorted4_b = (0..SORTED_COUNT)
            .map(|i| ((i as u32) / 8) % 2)
            .collect::<Vec<_>>();
        let sorted4_c = (0..SORTED_COUNT)
            .map(|i| ((i as u32) / 4) % 2)
            .collect::<Vec<_>>();
        let sorted4_d = (0..SORTED_COUNT)
            .map(|i| (i as u32) % 4)
            .collect::<Vec<_>>();
        let query4_a = (0..QUERY_COUNT)
            .map(|i| (i as u32 * 3) % 5)
            .collect::<Vec<_>>();
        let query4_b = (0..QUERY_COUNT)
            .map(|i| (i as u32 * 5) % 3)
            .collect::<Vec<_>>();
        let query4_c = (0..QUERY_COUNT)
            .map(|i| (i as u32 * 7) % 3)
            .collect::<Vec<_>>();
        let query4_d = (0..QUERY_COUNT)
            .map(|i| (i as u32 * 11) % 6)
            .collect::<Vec<_>>();
        let flat_summary_in = (0..TEST_COUNT)
            .flat_map(|i| {
                let i = i as u32;
                [
                    (i % 7) + 1,
                    ((i * 3) % 11) + 2,
                    (i * 5) % 37,
                    INVALID - ((i * 17) % 2048),
                ]
            })
            .collect::<Vec<_>>();
        let stable_bucket_base = stable_bucket_bases(&values);
        let stable_block_bucket_prefix = vec![0; STABLE_BUCKET_COUNT];
        Self {
            values,
            segment_heads,
            rank_keys,
            key_steps,
            sorted1,
            query1,
            sorted2_a,
            sorted2_b,
            query2_a,
            query2_b,
            sorted4_a,
            sorted4_b,
            sorted4_c,
            sorted4_d,
            query4_a,
            query4_b,
            query4_c,
            query4_d,
            flat_summary_in,
            stable_bucket_base,
            stable_block_bucket_prefix,
        }
    }
}

struct ExpectedOutputs {
    segmented: Vec<u32>,
    rank: Vec<u32>,
    radix_byte: Vec<u32>,
    radix_field: Vec<u32>,
    query1_begin: Vec<u32>,
    query1_end: Vec<u32>,
    query2_row: Vec<u32>,
    query4_row: Vec<u32>,
    scan_step: Vec<u32>,
    scan_seed: Vec<u32>,
    flat_summary_step: Vec<u32>,
    flat_summary_seed: Vec<u32>,
    scatter_store: Vec<u32>,
    stable_scatter: Vec<u32>,
    interval: Vec<u32>,
}

impl ExpectedOutputs {
    fn from_inputs(inputs: &AlgorithmInputs) -> Self {
        let mut running = 0u32;
        let segmented = inputs
            .values
            .iter()
            .zip(&inputs.segment_heads)
            .map(|(&value, &head)| {
                if head != 0 {
                    running = value;
                } else {
                    running += value;
                }
                running
            })
            .collect::<Vec<_>>();

        let rank = inputs
            .rank_keys
            .iter()
            .enumerate()
            .map(|(i, &key)| {
                inputs.rank_keys[..i]
                    .iter()
                    .filter(|&&prev| prev == key)
                    .count() as u32
            })
            .collect::<Vec<_>>();

        let radix_byte = inputs
            .values
            .iter()
            .zip(&inputs.key_steps)
            .map(|(&value, &step)| (value >> ((step & 3) * 8)) & 0xff)
            .collect::<Vec<_>>();
        let radix_field = inputs
            .key_steps
            .iter()
            .map(|&step| (step / 4).min(3))
            .collect::<Vec<_>>();

        let (query1_begin, query1_end) = inputs
            .query1
            .iter()
            .map(|&key| equal_range_1(&inputs.sorted1, key))
            .unzip();
        let query2_row = (0..QUERY_COUNT)
            .map(|i| {
                find_pair(
                    &inputs.sorted2_a,
                    &inputs.sorted2_b,
                    inputs.query2_a[i],
                    inputs.query2_b[i],
                )
            })
            .collect::<Vec<_>>();

        let query4_row = (0..QUERY_COUNT)
            .map(|i| {
                find_quad(
                    &inputs.sorted4_a,
                    &inputs.sorted4_b,
                    &inputs.sorted4_c,
                    &inputs.sorted4_d,
                    [
                        inputs.query4_a[i],
                        inputs.query4_b[i],
                        inputs.query4_c[i],
                        inputs.query4_d[i],
                    ],
                )
            })
            .collect::<Vec<_>>();
        let scan_step = (0..TEST_COUNT)
            .map(|i| {
                let left = if i >= 7 { inputs.values[i - 7] } else { 0 };
                left + inputs.values[i]
            })
            .collect::<Vec<_>>();
        let scan_seed = inputs.key_steps.clone();
        let flat_summary_step = (0..TEST_COUNT)
            .flat_map(|i| {
                let row = summary_row(&inputs.flat_summary_in, i);
                if i >= 5 {
                    combine_sum_sum_max_min(summary_row(&inputs.flat_summary_in, i - 5), row)
                } else {
                    row
                }
            })
            .collect::<Vec<_>>();
        let flat_summary_seed = (0..TEST_COUNT)
            .flat_map(summary_seed_row)
            .collect::<Vec<_>>();
        let mut scatter_store = inputs
            .values
            .iter()
            .map(|value| value + 17)
            .chain(std::iter::once(0))
            .collect::<Vec<_>>();
        scatter_store.resize(SCATTER_STORE_WORDS, 0);
        for (i, value) in inputs.values.iter().copied().enumerate() {
            if compact_pair_flag(i) == 0 {
                continue;
            }
            let dst = compact_pair_prefix(i);
            let base = SCATTER_PAIR_BASE + dst * 2;
            scatter_store[base] = value + 101;
            scatter_store[base + 1] = (value * 3) + i as u32;
        }
        scatter_store[SCATTER_RESERVATION_BASE] = TEST_COUNT as u32;
        for slot in 0..SCATTER_RESERVATION_CAPACITY {
            scatter_store[SCATTER_RESERVATION_BASE + 1 + slot] = 1;
        }
        let stable_scatter = stable_bucket_sorted_values(&inputs.values);
        let interval = vec![
            1, 1, 0, 1, 0, 1, 0, 17, 0x2345, 0xabcd, 1, 0, 1, 3, 31, 0, 1, 3, 0, 12, 44, 31, 99,
            307, 0xd4, 0xa1, 0x44332211, 0x44aa2211, 0x02070106, 0xff, 0x1f, 0xf, 0xffff0050, 0xe4,
            2, 0xe400, 3, 9, 0, 77, 5, 0, 123, 22, 0, 321, 19, 88, 0, 654, 33, 77, 1, 0, 9, 11, 4,
            7, 3, 7, 5, 9, 5, 8, 2, 8, 12, 11, 12, 3, 0xf, 3, 0xb, 0x8, 0xb, 1, 0, 0, 5, 1, 0, 1,
            83, 103, 300, 98, 83, 300, 100, 11, 112, 214, 315, 417, 518, 8, 6, 95, 46, 0, 1, 2, 0,
            0, 25, 6, 1, 0, 1, 1, 1, 2, 42, 0, 700, 1, 1, 4, 777, 700, 778,
        ];
        Self {
            segmented,
            rank,
            radix_byte,
            radix_field,
            query1_begin,
            query1_end,
            query2_row,
            query4_row,
            scan_step,
            scan_seed,
            flat_summary_step,
            flat_summary_seed,
            scatter_store,
            stable_scatter,
            interval,
        }
    }
}

struct AlgorithmBuffers {
    values: wgpu::Buffer,
    segment_heads: wgpu::Buffer,
    rank_keys: wgpu::Buffer,
    key_steps: wgpu::Buffer,
    sorted1: wgpu::Buffer,
    query1: wgpu::Buffer,
    sorted2_a: wgpu::Buffer,
    sorted2_b: wgpu::Buffer,
    query2_a: wgpu::Buffer,
    query2_b: wgpu::Buffer,
    sorted4_a: wgpu::Buffer,
    sorted4_b: wgpu::Buffer,
    sorted4_c: wgpu::Buffer,
    sorted4_d: wgpu::Buffer,
    query4_a: wgpu::Buffer,
    query4_b: wgpu::Buffer,
    query4_c: wgpu::Buffer,
    query4_d: wgpu::Buffer,
    flat_summary_in: wgpu::Buffer,
    stable_bucket_base: wgpu::Buffer,
    stable_block_bucket_prefix: wgpu::Buffer,
    segmented_out: wgpu::Buffer,
    rank_out: wgpu::Buffer,
    radix_byte_out: wgpu::Buffer,
    radix_field_out: wgpu::Buffer,
    query1_begin_out: wgpu::Buffer,
    query1_end_out: wgpu::Buffer,
    query2_row_out: wgpu::Buffer,
    query4_row_out: wgpu::Buffer,
    scan_step_out: wgpu::Buffer,
    scan_seed_out: wgpu::Buffer,
    flat_summary_step_out: wgpu::Buffer,
    flat_summary_seed_out: wgpu::Buffer,
    scatter_store_out: wgpu::Buffer,
    stable_scatter_out: wgpu::Buffer,
    interval_out: wgpu::Buffer,
    segmented_readback: wgpu::Buffer,
    rank_readback: wgpu::Buffer,
    radix_byte_readback: wgpu::Buffer,
    radix_field_readback: wgpu::Buffer,
    query1_begin_readback: wgpu::Buffer,
    query1_end_readback: wgpu::Buffer,
    query2_row_readback: wgpu::Buffer,
    query4_row_readback: wgpu::Buffer,
    scan_step_readback: wgpu::Buffer,
    scan_seed_readback: wgpu::Buffer,
    flat_summary_step_readback: wgpu::Buffer,
    flat_summary_seed_readback: wgpu::Buffer,
    scatter_store_readback: wgpu::Buffer,
    stable_scatter_readback: wgpu::Buffer,
    interval_readback: wgpu::Buffer,
}

impl AlgorithmBuffers {
    fn new(device: &wgpu::Device, inputs: &AlgorithmInputs) -> Self {
        Self {
            values: input_buffer(device, "values", &inputs.values),
            segment_heads: input_buffer(device, "segment_heads", &inputs.segment_heads),
            rank_keys: input_buffer(device, "rank_keys", &inputs.rank_keys),
            key_steps: input_buffer(device, "key_steps", &inputs.key_steps),
            sorted1: input_buffer(device, "sorted1", &inputs.sorted1),
            query1: input_buffer(device, "query1", &inputs.query1),
            sorted2_a: input_buffer(device, "sorted2_a", &inputs.sorted2_a),
            sorted2_b: input_buffer(device, "sorted2_b", &inputs.sorted2_b),
            query2_a: input_buffer(device, "query2_a", &inputs.query2_a),
            query2_b: input_buffer(device, "query2_b", &inputs.query2_b),
            sorted4_a: input_buffer(device, "sorted4_a", &inputs.sorted4_a),
            sorted4_b: input_buffer(device, "sorted4_b", &inputs.sorted4_b),
            sorted4_c: input_buffer(device, "sorted4_c", &inputs.sorted4_c),
            sorted4_d: input_buffer(device, "sorted4_d", &inputs.sorted4_d),
            query4_a: input_buffer(device, "query4_a", &inputs.query4_a),
            query4_b: input_buffer(device, "query4_b", &inputs.query4_b),
            query4_c: input_buffer(device, "query4_c", &inputs.query4_c),
            query4_d: input_buffer(device, "query4_d", &inputs.query4_d),
            flat_summary_in: input_buffer(device, "flat_summary_in", &inputs.flat_summary_in),
            stable_bucket_base: input_buffer(
                device,
                "stable_bucket_base",
                &inputs.stable_bucket_base,
            ),
            stable_block_bucket_prefix: input_buffer(
                device,
                "stable_block_bucket_prefix",
                &inputs.stable_block_bucket_prefix,
            ),
            segmented_out: output_buffer(device, "segmented_out", TEST_COUNT),
            rank_out: output_buffer(device, "rank_out", TEST_COUNT),
            radix_byte_out: output_buffer(device, "radix_byte_out", TEST_COUNT),
            radix_field_out: output_buffer(device, "radix_field_out", TEST_COUNT),
            query1_begin_out: output_buffer(device, "query1_begin_out", QUERY_COUNT),
            query1_end_out: output_buffer(device, "query1_end_out", QUERY_COUNT),
            query2_row_out: output_buffer(device, "query2_row_out", QUERY_COUNT),
            query4_row_out: output_buffer(device, "query4_row_out", QUERY_COUNT),
            scan_step_out: output_buffer(device, "scan_step_out", TEST_COUNT),
            scan_seed_out: output_buffer(device, "scan_seed_out", TEST_COUNT),
            flat_summary_step_out: output_buffer(
                device,
                "flat_summary_step_out",
                TEST_COUNT * SUMMARY_WORDS,
            ),
            flat_summary_seed_out: output_buffer(
                device,
                "flat_summary_seed_out",
                TEST_COUNT * SUMMARY_WORDS,
            ),
            scatter_store_out: output_buffer(device, "scatter_store_out", SCATTER_STORE_WORDS),
            stable_scatter_out: output_buffer(device, "stable_scatter_out", TEST_COUNT),
            interval_out: output_buffer(device, "interval_out", INTERVAL_WORDS),
            segmented_readback: readback_buffer(device, "segmented_readback", TEST_COUNT),
            rank_readback: readback_buffer(device, "rank_readback", TEST_COUNT),
            radix_byte_readback: readback_buffer(device, "radix_byte_readback", TEST_COUNT),
            radix_field_readback: readback_buffer(device, "radix_field_readback", TEST_COUNT),
            query1_begin_readback: readback_buffer(device, "query1_begin_readback", QUERY_COUNT),
            query1_end_readback: readback_buffer(device, "query1_end_readback", QUERY_COUNT),
            query2_row_readback: readback_buffer(device, "query2_row_readback", QUERY_COUNT),
            query4_row_readback: readback_buffer(device, "query4_row_readback", QUERY_COUNT),
            scan_step_readback: readback_buffer(device, "scan_step_readback", TEST_COUNT),
            scan_seed_readback: readback_buffer(device, "scan_seed_readback", TEST_COUNT),
            flat_summary_step_readback: readback_buffer(
                device,
                "flat_summary_step_readback",
                TEST_COUNT * SUMMARY_WORDS,
            ),
            flat_summary_seed_readback: readback_buffer(
                device,
                "flat_summary_seed_readback",
                TEST_COUNT * SUMMARY_WORDS,
            ),
            scatter_store_readback: readback_buffer(
                device,
                "scatter_store_readback",
                SCATTER_STORE_WORDS,
            ),
            stable_scatter_readback: readback_buffer(device, "stable_scatter_readback", TEST_COUNT),
            interval_readback: readback_buffer(device, "interval_readback", INTERVAL_WORDS),
        }
    }

    fn bindings(&self) -> Vec<(&'static str, wgpu::BindingResource<'_>)> {
        vec![
            ("values", self.values.as_entire_binding()),
            ("segment_heads", self.segment_heads.as_entire_binding()),
            ("rank_keys", self.rank_keys.as_entire_binding()),
            ("key_steps", self.key_steps.as_entire_binding()),
            ("sorted1", self.sorted1.as_entire_binding()),
            ("query1", self.query1.as_entire_binding()),
            ("sorted2_a", self.sorted2_a.as_entire_binding()),
            ("sorted2_b", self.sorted2_b.as_entire_binding()),
            ("query2_a", self.query2_a.as_entire_binding()),
            ("query2_b", self.query2_b.as_entire_binding()),
            ("sorted4_a", self.sorted4_a.as_entire_binding()),
            ("sorted4_b", self.sorted4_b.as_entire_binding()),
            ("sorted4_c", self.sorted4_c.as_entire_binding()),
            ("sorted4_d", self.sorted4_d.as_entire_binding()),
            ("query4_a", self.query4_a.as_entire_binding()),
            ("query4_b", self.query4_b.as_entire_binding()),
            ("query4_c", self.query4_c.as_entire_binding()),
            ("query4_d", self.query4_d.as_entire_binding()),
            ("flat_summary_in", self.flat_summary_in.as_entire_binding()),
            (
                "stable_bucket_base_in",
                self.stable_bucket_base.as_entire_binding(),
            ),
            (
                "stable_block_bucket_prefix_in",
                self.stable_block_bucket_prefix.as_entire_binding(),
            ),
            ("segmented_out", self.segmented_out.as_entire_binding()),
            ("rank_out", self.rank_out.as_entire_binding()),
            ("radix_byte_out", self.radix_byte_out.as_entire_binding()),
            ("radix_field_out", self.radix_field_out.as_entire_binding()),
            (
                "query1_begin_out",
                self.query1_begin_out.as_entire_binding(),
            ),
            ("query1_end_out", self.query1_end_out.as_entire_binding()),
            ("query2_row_out", self.query2_row_out.as_entire_binding()),
            ("query4_row_out", self.query4_row_out.as_entire_binding()),
            ("scan_step_out", self.scan_step_out.as_entire_binding()),
            ("scan_seed_out", self.scan_seed_out.as_entire_binding()),
            (
                "flat_summary_step_out",
                self.flat_summary_step_out.as_entire_binding(),
            ),
            (
                "flat_summary_seed_out",
                self.flat_summary_seed_out.as_entire_binding(),
            ),
            (
                "scatter_store_out",
                self.scatter_store_out.as_entire_binding(),
            ),
            (
                "stable_scatter_out",
                self.stable_scatter_out.as_entire_binding(),
            ),
            ("interval_out", self.interval_out.as_entire_binding()),
        ]
    }
}

fn compile_validation_shader(root: &Path) -> (Vec<u8>, Vec<u8>) {
    let slangc = slangc_command();
    let shader = root.join("tests/shaders/gpu_algorithms_validate.slang");
    let spv = common::TempArtifact::new("laniusc_gpu_algorithms", "validate", Some("spv"));
    let reflection =
        common::TempArtifact::new("laniusc_gpu_algorithms", "validate", Some("reflect.json"));
    let output = Command::new(&slangc)
        .arg("-target")
        .arg("spirv")
        .arg("-profile")
        .arg("glsl_450")
        .arg("-fvk-use-entrypoint-name")
        .arg("-reflection-json")
        .arg(reflection.path())
        .arg("-emit-spirv-directly")
        .arg("-O1")
        .arg("-I")
        .arg(root.join("shaders"))
        .arg("-I")
        .arg(root.join("shaders/type_checker"))
        .arg("-o")
        .arg(spv.path())
        .arg(&shader)
        .output()
        .unwrap_or_else(|err| panic!("run slangc for {}: {err}", shader.display()));
    common::assert_command_success("compile generic GPU algorithm validation shader", &output);
    (
        fs::read(spv.path()).unwrap_or_else(|err| panic!("read {}: {err}", spv.path().display())),
        fs::read(reflection.path())
            .unwrap_or_else(|err| panic!("read {}: {err}", reflection.path().display())),
    )
}

fn slangc_command() -> PathBuf {
    if let Some(path) = env::var_os("SLANGC") {
        return PathBuf::from(path);
    }
    PathBuf::from("slangc")
}

fn input_buffer(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &u32_bytes(words),
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
    })
}

fn output_buffer(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    })
}

fn readback_buffer(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}

fn copy_to_readback(encoder: &mut wgpu::CommandEncoder, src: &wgpu::Buffer, dst: &wgpu::Buffer) {
    encoder.copy_buffer_to_buffer(src, 0, dst, 0, dst.size());
}

fn read_u32s(device: &wgpu::Device, buffer: &wgpu::Buffer, count: usize) -> Vec<u32> {
    let slice = buffer.slice(..);
    let (tx, rx) = mpsc::channel();
    slice.map_async(wgpu::MapMode::Read, move |result| {
        tx.send(result).expect("send map result");
    });
    device
        .poll(wgpu::PollType::wait_indefinitely())
        .expect("poll readback");
    rx.recv()
        .expect("receive map result")
        .expect("map readback");
    let data = slice.get_mapped_range();
    let words = data[..count * 4]
        .chunks_exact(4)
        .map(|bytes| u32::from_le_bytes(bytes.try_into().expect("u32 bytes")))
        .collect::<Vec<_>>();
    drop(data);
    buffer.unmap();
    words
}

fn leak_bytes(bytes: Vec<u8>) -> &'static [u8] {
    Box::leak(bytes.into_boxed_slice())
}

fn u32_bytes(words: &[u32]) -> Vec<u8> {
    let mut bytes = Vec::with_capacity(words.len() * 4);
    for word in words {
        bytes.extend_from_slice(&word.to_le_bytes());
    }
    bytes
}

fn equal_range_1(sorted: &[u32], key: u32) -> (u32, u32) {
    let begin = sorted.partition_point(|&value| value < key) as u32;
    let end = sorted.partition_point(|&value| value <= key) as u32;
    (begin, end)
}

fn find_pair(sorted_a: &[u32], sorted_b: &[u32], a: u32, b: u32) -> u32 {
    sorted_a
        .iter()
        .zip(sorted_b)
        .position(|(&row_a, &row_b)| row_a == a && row_b == b)
        .map(|row| row as u32)
        .unwrap_or(INVALID)
}

fn find_quad(
    sorted_a: &[u32],
    sorted_b: &[u32],
    sorted_c: &[u32],
    sorted_d: &[u32],
    key: [u32; 4],
) -> u32 {
    (0..sorted_a.len())
        .find(|&row| {
            sorted_a[row] == key[0]
                && sorted_b[row] == key[1]
                && sorted_c[row] == key[2]
                && sorted_d[row] == key[3]
        })
        .map(|row| row as u32)
        .unwrap_or(INVALID)
}

fn summary_row(words: &[u32], row: usize) -> [u32; SUMMARY_WORDS] {
    let base = row * SUMMARY_WORDS;
    [
        words[base],
        words[base + 1],
        words[base + 2],
        words[base + 3],
    ]
}

fn summary_seed_row(row: usize) -> [u32; SUMMARY_WORDS] {
    let i = row as u32;
    [
        i + 1,
        (i * 2) + 3,
        (i * 5) % 31,
        INVALID - ((i * 13) % 1024),
    ]
}

fn combine_sum_sum_max_min(left: [u32; SUMMARY_WORDS], right: [u32; SUMMARY_WORDS]) -> [u32; 4] {
    [
        left[0] + right[0],
        left[1] + right[1],
        left[2].max(right[2]),
        left[3].min(right[3]),
    ]
}

fn compact_pair_flag(i: usize) -> u32 {
    u32::from(i % 3 != 0)
}

fn compact_pair_prefix(i: usize) -> usize {
    i - ((i + 2) / 3)
}

fn stable_bucket_bases(values: &[u32]) -> Vec<u32> {
    let mut counts = vec![0u32; STABLE_BUCKET_COUNT];
    for &value in values {
        counts[(value as usize) & (STABLE_BUCKET_COUNT - 1)] += 1;
    }

    let mut bases = vec![0u32; STABLE_BUCKET_COUNT];
    let mut running = 0u32;
    for (base, count) in bases.iter_mut().zip(counts) {
        *base = running;
        running += count;
    }
    bases
}

fn stable_bucket_sorted_values(values: &[u32]) -> Vec<u32> {
    let bases = stable_bucket_bases(values);
    let mut offsets = vec![0usize; STABLE_BUCKET_COUNT];
    let mut sorted = vec![0u32; values.len()];
    for &value in values {
        let bucket = (value as usize) & (STABLE_BUCKET_COUNT - 1);
        let dst = bases[bucket] as usize + offsets[bucket];
        sorted[dst] = value;
        offsets[bucket] += 1;
    }
    sorted
}
