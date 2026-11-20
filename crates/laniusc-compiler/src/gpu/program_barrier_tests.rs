//! Step programs on the physical GPU (shaders/shared/collectives/step_program.slang,
//! shaders/tests/probe_program_barrier.slang). The test prints the time per
//! step for each case: run it with `--nocapture` to see them.

use std::time::Instant;

use super::{
    buffers::{readback_bytes, storage_rw_for_array, uniform_from_val},
    device,
    passes_core::{self, make_pass_data_from_shader_key, map_readback_blocking},
};

const KERNEL: &str = "tests/probe_program_barrier";
const LANES: u32 = 256;
const SLOT: u32 = 3;
const SYNC_WORDS: usize = 4;

#[derive(encase::ShaderType)]
struct Params {
    groups: u32,
    rounds: u32,
    rows_per_lane: u32,
    slot: u32,
}

struct Outcome {
    arrivals: u32,
    failed: u32,
    finished_groups: u32,
    wrong_cells: u32,
    micros: f64,
}

fn run(groups: u32, rounds: u32, rows_per_lane: u32) -> Outcome {
    let gpu = device::global();
    let (device, queue) = (&gpu.device, &gpu.queue);
    let pass = make_pass_data_from_shader_key(device, KERNEL, "main", KERNEL).unwrap();
    let params = uniform_from_val(
        device,
        "program_barrier.params",
        &Params {
            groups,
            rounds,
            rows_per_lane,
            slot: SLOT,
        },
    );
    let sync_words = (SLOT as usize + 1) * SYNC_WORDS;
    let sync = storage_rw_for_array::<u32>(device, "program_barrier.sync", sync_words);
    let wrong_cells = storage_rw_for_array::<u32>(device, "program_barrier.wrong_cells", 4);
    let cells = storage_rw_for_array::<u32>(
        device,
        "program_barrier.cells",
        (groups * LANES * 2 * rows_per_lane) as usize,
    );
    let entries = [
        ("gParams", params.as_entire_binding()),
        ("step_program_sync", sync.as_entire_binding()),
        ("cells", cells.as_entire_binding()),
        ("wrong_cells", wrong_cells.as_entire_binding()),
    ];
    passes_core::bind_group::validate_exact_binding_names(&pass, 0, &entries).unwrap();
    let group = passes_core::bind_group::create_bind_group_from_bindings(
        device,
        Some(KERNEL),
        &pass,
        0,
        &entries,
    )
    .unwrap();
    let sync_bytes = (sync_words * 4) as u64;
    let readback = readback_bytes(
        device,
        "program_barrier.readback",
        sync_words * 4 + 4,
        sync_words + 1,
    );
    let mut outcome = Outcome {
        arrivals: 0,
        failed: 0,
        finished_groups: 0,
        wrong_cells: 0,
        micros: f64::MAX,
    };
    for _ in 0..5 {
        let mut encoder =
            device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
        encoder.clear_buffer(&sync, 0, None);
        encoder.clear_buffer(&cells, 0, None);
        encoder.clear_buffer(&wrong_cells, 0, None);
        {
            let mut compute = passes_core::begin_counted_compute_pass(
                &mut encoder,
                &wgpu::ComputePassDescriptor {
                    label: Some(KERNEL),
                    timestamp_writes: None,
                },
            );
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, Some(&group), &[]);
            passes_core::record_compute_dispatch();
            compute.dispatch_workgroups(groups, 1, 1);
        }
        sync.copy_to(&mut encoder, 0, &readback, 0, sync_bytes);
        wrong_cells.copy_to(&mut encoder, 0, &readback, sync_bytes, 4);
        let started = Instant::now();
        queue.submit(Some(encoder.finish()));
        let slice = readback.slice(..);
        map_readback_blocking(device, &slice, "program_barrier".into()).unwrap();
        outcome.micros = outcome.micros.min(started.elapsed().as_secs_f64() * 1e6);
        let mapped = slice.get_mapped_range();
        let words: Vec<u32> = mapped
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        drop(mapped);
        readback.unmap();
        let slot = &words[SLOT as usize * SYNC_WORDS..];
        outcome.arrivals = slot[0];
        outcome.failed = slot[1];
        outcome.finished_groups = slot[3];
        outcome.wrong_cells = words[sync_words];
    }
    outcome
}

#[test]
fn physical_gpu_step_program_orders_steps_across_workgroups() {
    device::global();
    let large_launch = device::is_rtx_3090_vulkan().then_some((
        super::operations::STEP_PROGRAM_MAX_GROUPS,
        8,
        500,
    ));
    for (groups, rows_per_lane, rounds) in [
        (1u32, 1u32, 2000u32),
        (1, 16, 500),
        (1, 256, 100),
        (8, 1, 2000),
        (64, 1, 2000),
        (64, 4, 500),
        (64, 32, 200),
    ].into_iter().chain(large_launch) {
        let empty = run(groups, 0, rows_per_lane).micros;
        let outcome = run(groups, rounds, rows_per_lane);
        println!(
            "groups {groups:3} rows per step {:7}: {:7.3} us per step",
            groups * LANES * rows_per_lane,
            (outcome.micros - empty) / f64::from(rounds),
        );
        assert_eq!(
            outcome.failed, 0,
            "a wait for the other groups ran out of spins"
        );
        assert_eq!(
            outcome.wrong_cells, 0,
            "a step did not see the step before it"
        );
        assert_eq!(outcome.finished_groups, groups);
        if groups > 1 {
            assert_eq!(outcome.arrivals, groups * rounds);
        }
    }
}

#[test]
fn physical_gpu_step_program_prefix_scan_matches_exclusive_host_sum() {
    #[derive(encase::ShaderType)]
    struct ScanParams {
        groups: u32,
        rows: u32,
        in_place: u32,
    }

    let gpu = device::global();
    let (device, queue) = (&gpu.device, &gpu.queue);
    let label = "tests/probe_program_scan";
    let pass = make_pass_data_from_shader_key(device, label, "main", label).unwrap();
    for (groups, rows, in_place) in [
        (1, 0, 0),
        (1, 4099, 1),
        (64, 0, 0),
        (64, 257, 0),
        (64, 131_075, 1),
        (64, 131_075, 2),
    ] {
        let params = uniform_from_val(device, label, &ScanParams { groups, rows, in_place });
        let count = rows as usize;
        let (stride, column, total_word) = if in_place == 2 { (3, 1, 1) } else { (1, 0, 0) };
        let input = storage_rw_for_array::<u32>(device, label, (count * stride).max(1));
        let prefix = storage_rw_for_array::<u32>(device, label, count.max(1));
        let total = storage_rw_for_array::<u32>(device, label, total_word + 1);
        let sums = storage_rw_for_array::<u32>(device, label, groups as usize);
        let sync = storage_rw_for_array::<u32>(device, label, SYNC_WORDS);
        let data: Vec<u32> = (0..rows).map(|row| row.wrapping_mul(0x9e3779b9)).collect();
        let sentinel = 0x2c9ae133u32;
        if !data.is_empty() {
            let mut words = vec![sentinel; count * stride];
            for (row, value) in data.iter().copied().enumerate() {
                words[row * stride + column] = value;
            }
            let bytes: Vec<u8> = words.iter().flat_map(|value| value.to_le_bytes()).collect();
            input.write(queue, 0, &bytes);
        }
        let entries = [
            ("gParams", params.as_entire_binding()),
            ("step_program_sync", sync.as_entire_binding()),
            ("input_words", input.as_entire_binding()),
            ("prefix", prefix.as_entire_binding()),
            ("total", total.as_entire_binding()),
            ("sums", sums.as_entire_binding()),
        ];
        passes_core::bind_group::validate_exact_binding_names(&pass, 0, &entries).unwrap();
        let bindings = passes_core::bind_group::create_bind_group_from_bindings(
            device, Some(label), &pass, 0, &entries,
        ).unwrap();
        let header_bytes = (SYNC_WORDS + 1) * 4;
        let size = header_bytes + count * stride * 4;
        let readback = readback_bytes(device, label, size, size);
        let mut encoder =
            device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) });
        sync.clear(&mut encoder, 0, None);
        {
            let mut compute = passes_core::begin_counted_compute_pass(
                &mut encoder,
                &wgpu::ComputePassDescriptor { label: Some(label), timestamp_writes: None },
            );
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, Some(&bindings), &[]);
            compute.dispatch_workgroups(groups, 1, 1);
        }
        sync.copy_to(&mut encoder, 0, &readback, 0, (SYNC_WORDS * 4) as u64);
        total.copy_to(&mut encoder, (total_word * 4) as u64, &readback, (SYNC_WORDS * 4) as u64, 4);
        if count != 0 {
            let scanned = if in_place == 0 { &prefix } else { &input };
            scanned.copy_to(&mut encoder, 0, &readback, header_bytes as u64, (count * stride * 4) as u64);
        }
        queue.submit(Some(encoder.finish()));
        let slice = readback.slice(..);
        map_readback_blocking(device, &slice, label.into()).unwrap();
        let mapped = slice.get_mapped_range();
        let output: Vec<u32> = mapped
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        drop(mapped);
        readback.unmap();
        assert_eq!(output[1], 0, "groups {groups}, rows {rows}");
        assert_eq!(output[3], groups, "groups {groups}, rows {rows}");
        let mut expected = 0u32;
        let scanned = output[SYNC_WORDS + 1..].chunks_exact(stride);
        for (row, (value, actual)) in data.into_iter().zip(scanned).enumerate() {
            assert_eq!(actual[column], expected, "groups {groups}, rows {rows}, row {row}");
            if stride == 3 {
                assert_eq!((actual[0], actual[2]), (sentinel, sentinel));
            }
            expected = expected.wrapping_add(value);
        }
        assert_eq!(output[SYNC_WORDS], expected, "groups {groups}, rows {rows}");
    }
}

#[test]
fn physical_gpu_step_program_vector_scan_matches_exclusive_host_sum() {
    #[derive(encase::ShaderType)]
    struct ScanParams {
        groups: u32,
        rows: u32,
    }

    let gpu = device::global();
    let device = &gpu.device;
    let queue = &gpu.queue;
    let label = "tests/probe_program_vector_scan";
    let pass = make_pass_data_from_shader_key(device, label, "main", label).unwrap();
    for (groups, rows) in [(1, 0), (1, 4099), (64, 257), (64, 131_075)] {
        let count = rows as usize;
        let params = uniform_from_val(device, label, &ScanParams { groups, rows });
        let input = storage_rw_for_array::<u32>(device, label, 4 * count.max(1));
        let prefix = storage_rw_for_array::<u32>(device, label, 4 * count.max(1));
        let sums = storage_rw_for_array::<u32>(device, label, 4 * groups as usize);
        let total = storage_rw_for_array::<u32>(device, label, 6);
        let sync = storage_rw_for_array::<u32>(device, label, SYNC_WORDS);
        let data: Vec<[u32; 4]> = (0..rows).map(|row| [
            row.wrapping_mul(0x9e3779b9),
            row & 3,
            row.wrapping_mul(row),
            1,
        ]).collect();
        if count != 0 {
            let bytes: Vec<u8> = data.iter().flatten().flat_map(|value| value.to_le_bytes()).collect();
            input.write(queue, 0, &bytes);
        }
        let entries = [
            ("gParams", params.as_entire_binding()),
            ("step_program_sync", sync.as_entire_binding()),
            ("scan_input", input.as_entire_binding()),
            ("scan_prefix", prefix.as_entire_binding()),
            ("scan_sums", sums.as_entire_binding()),
            ("scan_total", total.as_entire_binding()),
        ];
        let bindings = passes_core::bind_group::create_bind_group_from_bindings(
            device, Some(label), &pass, 0, &entries,
        ).unwrap();
        let total_offset = (SYNC_WORDS * 4) as u64;
        let prefix_offset = total_offset + 6 * 4;
        let size = prefix_offset as usize + count * 16;
        let readback = readback_bytes(device, label, size, size);
        let mut encoder = device.create_command_encoder(&Default::default());
        {
            let mut compute = passes_core::begin_counted_compute_pass(
                &mut encoder,
                &wgpu::ComputePassDescriptor { label: Some(label), timestamp_writes: None },
            );
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, Some(&bindings), &[]);
            compute.dispatch_workgroups(groups, 1, 1);
        }
        sync.copy_to(&mut encoder, 0, &readback, 0, total_offset);
        total.copy_to(&mut encoder, 0, &readback, total_offset, 6 * 4);
        if count != 0 {
            prefix.copy_to(&mut encoder, 0, &readback, prefix_offset, count as u64 * 16);
        }
        queue.submit(Some(encoder.finish()));
        let slice = readback.slice(..);
        map_readback_blocking(device, &slice, label.into()).unwrap();
        let mapped = slice.get_mapped_range();
        let output: Vec<u32> = mapped.chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        assert_eq!(output[1], 0, "groups {groups}, rows {rows}");
        assert_eq!(output[3], groups, "groups {groups}, rows {rows}");
        let mut expected = [0u32; 4];
        for (row, (values, actual)) in data.into_iter()
            .zip(output[SYNC_WORDS + 6..].chunks_exact(4)).enumerate()
        {
            assert_eq!(actual, expected, "groups {groups}, rows {rows}, row {row}");
            for (sum, value) in expected.iter_mut().zip(values) {
                *sum = sum.wrapping_add(value);
            }
        }
        assert_eq!(output[SYNC_WORDS..SYNC_WORDS + 6], [0, expected[0], expected[1], expected[2], expected[3], 0]);
    }
}

#[test]
fn physical_gpu_step_program_radix_sort_matches_stable_host_sort() {
    #[derive(encase::ShaderType)]
    struct SortParams {
        groups: u32,
        rows: u32,
        digits: u32,
    }

    let gpu = device::global();
    let (device, queue) = (&gpu.device, &gpu.queue);
    let label = "tests/probe_program_radix_sort";
    let pass = make_pass_data_from_shader_key(device, label, "main", label).unwrap();
    for (groups, rows, digits) in [
        (1, 0, 1),
        (1, 801, 1),
        (1, 1219, 2),
        (64, 18_125, 3),
        (64, 65_651, 4),
    ] {
        let params = uniform_from_val(device, label, &SortParams { groups, rows, digits });
        let count = rows as usize;
        let data: Vec<u32> = (0..rows)
            .map(|row| ((row.wrapping_mul(269) % 713) << 8) | (if row % 13 == 0 { 255 } else { row % 11 }))
            .collect();
        let mut expected: Vec<u32> = (0..rows).collect();
        let mask = u32::MAX >> ((4 - digits) * 8);
        expected.sort_by_key(|row| data[*row as usize] & mask);
        let keys = storage_rw_for_array::<u32>(device, label, count.max(1));
        if !data.is_empty() {
            let bytes: Vec<u8> = data.iter().flat_map(|value| value.to_le_bytes()).collect();
            keys.write(queue, 0, &bytes);
        }
        let order = storage_rw_for_array::<u32>(device, label, count.max(1));
        let temporary = storage_rw_for_array::<u32>(device, label, count.max(1));
        let histogram = storage_rw_for_array::<u32>(device, label, groups as usize * 256);
        let bucket_total = storage_rw_for_array::<u32>(device, label, 256);
        let sync = storage_rw_for_array::<u32>(device, label, SYNC_WORDS);
        let entries = [
            ("gParams", params.as_entire_binding()),
            ("step_program_sync", sync.as_entire_binding()),
            ("keys", keys.as_entire_binding()),
            ("order", order.as_entire_binding()),
            ("temporary", temporary.as_entire_binding()),
            ("histogram", histogram.as_entire_binding()),
            ("bucket_total", bucket_total.as_entire_binding()),
        ];
        passes_core::bind_group::validate_exact_binding_names(&pass, 0, &entries).unwrap();
        let bindings = passes_core::bind_group::create_bind_group_from_bindings(
            device, Some(label), &pass, 0, &entries,
        ).unwrap();
        let header_bytes = SYNC_WORDS * 4;
        let size = header_bytes + count * 4;
        let readback = readback_bytes(device, label, size, size);
        let mut encoder =
            device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) });
        sync.clear(&mut encoder, 0, None);
        {
            let mut compute = passes_core::begin_counted_compute_pass(
                &mut encoder,
                &wgpu::ComputePassDescriptor { label: Some(label), timestamp_writes: None },
            );
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, Some(&bindings), &[]);
            compute.dispatch_workgroups(groups, 1, 1);
        }
        sync.copy_to(&mut encoder, 0, &readback, 0, header_bytes as u64);
        if count != 0 {
            order.copy_to(&mut encoder, 0, &readback, header_bytes as u64, (count * 4) as u64);
        }
        queue.submit(Some(encoder.finish()));
        let slice = readback.slice(..);
        map_readback_blocking(device, &slice, label.into()).unwrap();
        let mapped = slice.get_mapped_range();
        let output: Vec<u32> = mapped
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        drop(mapped);
        readback.unmap();
        assert_eq!(output[1], 0, "groups {groups}, rows {rows}, digits {digits}");
        assert_eq!(output[3], groups, "groups {groups}, rows {rows}, digits {digits}");
        let mismatch = output[SYNC_WORDS..].iter().zip(&expected).position(|(a, b)| a != b);
        assert_eq!(mismatch, None, "groups {groups}, rows {rows}, digits {digits}");
    }
}

#[test]
#[ignore = "GPU timing benchmark"]
fn benchmark_step_program_collectives() {
    use super::buffers::{LaniusBuffer, storage_ro_from_u32s_with_queue};
    use super::compiler_graph::{
        CompilerGraphBuilder, CompilerGraphWorkspace, CompilerPhase, PrefixScanGraphPasses,
        PrefixScanResources, PrefixScanSpec, RadixSortGraphPasses, RadixSortGraphStepPasses,
        ResourceDomain,
    };
    use super::kernels::KernelRegistry;
    use super::operations::{
        PrefixScanOperation, RadixDispatchDomain, RadixSortDefinition, RadixSortDispatch,
        RadixSortKernels, RadixSortOperation, RadixSortResources,
    };
    use super::resource_registry::ResourceMap;
    use super::timer::{GpuCompilerPhase, GpuTimer};

    #[derive(encase::ShaderType)]
    struct ProbeParams {
        groups: u32,
        rows: u32,
        mode: u32,
    }

    #[derive(encase::ShaderType)]
    struct SortParams {
        rows: u32,
        bits_per_field: u32,
        blocks: u32,
        digit: u32,
    }

    let gpu = device::global();
    let (device, queue) = (&gpu.device, &gpu.queue);
    let scan_key = "tests/probe_program_scan";
    let sort_key = "tests/probe_program_radix_sort";
    let histogram_key = "type_checker/visibility/sort_hir_decl_keys";
    let scatter_key = "type_checker/visibility/scatter_sorted_hir_decl_keys";
    let kernels = KernelRegistry::prepare(device, [
        scan_key,
        sort_key,
        histogram_key,
        scatter_key,
        "scan/words/scan_counted_word_blocks",
        "scan/words/apply_counted_word_carries",
        "radix/scan_radix_bucket_histograms",
    ]).unwrap();
    let scan = kernels.kernel(scan_key);
    let sort = kernels.kernel(sort_key);
    let graph = CompilerGraphBuilder::new().build().unwrap();
    let workspace = CompilerGraphWorkspace::new(device, "collective benchmark", &graph).unwrap();
    let allocations = workspace.allocations();
    let label = "collective benchmark";
    let groups = 64;
    let digits = 4;

    for rows in [4096u32, 65_536, 1_048_576, 4_194_304] {
        let blocks = rows.div_ceil(256);
        let storage = |words| storage_rw_for_array::<u32>(device, label, words);
        let upload = |words: &[u32]| storage_ro_from_u32s_with_queue(device, queue, label, words);
        let count = upload(&[rows]);
        let key_words: Vec<u32> = (0..rows)
            .map(|row| row.wrapping_mul(0x9e3779b9).rotate_left(11))
            .collect();
        let keys = upload(&key_words);
        let prefix = storage(rows as usize);
        let total = storage(1);
        let sums = storage(groups as usize);
        let order = storage(rows as usize);
        let temporary = storage(rows as usize);
        let histogram = storage(((blocks + groups) * 256) as usize);
        let bucket_prefix = storage((blocks * 256) as usize);
        let bucket_total = storage(256);
        let sync = storage(SYNC_WORDS);
        let probe_scan_params = uniform_from_val(
            device, label, &ProbeParams { groups, rows, mode: 0 },
        );
        let probe_sort_params = uniform_from_val(
            device, label, &ProbeParams { groups, rows, mode: digits },
        );
        let bind = |pass, entries: &[(&str, wgpu::BindingResource<'_>)]| {
            passes_core::bind_group::create_bind_group_from_bindings(
                device, Some(label), pass, 0, entries,
            ).unwrap()
        };
        let scan_bind = bind(scan, &[
            ("gParams", probe_scan_params.as_entire_binding()),
            ("step_program_sync", sync.as_entire_binding()),
            ("input_words", keys.as_entire_binding()),
            ("prefix", prefix.as_entire_binding()),
            ("total", total.as_entire_binding()),
            ("sums", sums.as_entire_binding()),
        ]);
        let sort_bind = bind(sort, &[
            ("gParams", probe_sort_params.as_entire_binding()),
            ("step_program_sync", sync.as_entire_binding()),
            ("keys", keys.as_entire_binding()),
            ("order", order.as_entire_binding()),
            ("temporary", temporary.as_entire_binding()),
            ("histogram", histogram.as_entire_binding()),
            ("bucket_total", bucket_total.as_entire_binding()),
        ]);
        let block_sums = storage(blocks as usize);
        let local_prefix = storage(rows as usize);
        let args = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: 12,
            usage: wgpu::BufferUsages::INDIRECT | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let args = LaniusBuffer::<u32>::new_labeled((args, 12), 3, label);
        let dispatch_bytes: Vec<u8> = [blocks, 1, 1].into_iter()
            .flat_map(u32::to_le_bytes)
            .collect();
        args.write(queue, 0, &dispatch_bytes);
        let mut resources = ResourceMap::new();
        resources.attach_graph(&graph, &allocations);
        resources.buffers([
            ("count", &count),
            ("input", &keys),
            ("prefix", &prefix),
            ("total", &total),
            ("dispatch", &args),
            ("local_prefix", &local_prefix),
            ("block_sums", &block_sums),
        ]);
        let dispatched_scan = PrefixScanOperation::from_spec(device, &kernels, &resources, PrefixScanSpec {
            phase: CompilerPhase::Optimization,
            dispatch_domain: ResourceDomain::OptimizationValues,
            passes: PrefixScanGraphPasses { local: "scan.local", apply: "scan.apply" },
            resources: PrefixScanResources {
                count: "count",
                input: "input",
                output_prefix: "prefix",
                total: "total",
                dispatch_args: "dispatch",
                local_prefix: "local_prefix",
                block_sum: "block_sums",
            },
        }).unwrap();

        // The visibility kernels encode a non-null name key as name_id + 1.
        let name_keys: Vec<u32> = key_words.into_iter()
            .map(|word| word.wrapping_sub(1))
            .collect();
        let name_keys = upload(&name_keys);
        let owner = storage(rows as usize);
        resources.buffers([
            ("hir_visible_decl_count_out", &count),
            ("hir_visible_decl_name_id", &name_keys),
            ("hir_visible_decl_owner_fn", &owner),
            ("order", &order),
            ("temporary", &temporary),
            ("histogram", &histogram),
            ("bucket_prefix", &bucket_prefix),
            ("bucket_total", &bucket_total),
        ]);
        let sort_passes = RadixSortGraphStepPasses {
            histogram: "sort.histogram", bucket_prefix: "sort.bucket_prefix", scatter: "sort.scatter",
        };
        let sort_definition = RadixSortDefinition {
            phase: CompilerPhase::Optimization,
            dispatch_domain: ResourceDomain::OptimizationValues,
            small_pass: "sort.small",
            passes: RadixSortGraphPasses {
                order_to_temporary: sort_passes, temporary_to_order: sort_passes,
            },
            kernels: RadixSortKernels::new(histogram_key, scatter_key),
            resources: RadixSortResources {
                count: "count", order: "order", temporary_order: "temporary",
                histogram: "histogram", bucket_prefix: "bucket_prefix", bucket_total: "bucket_total",
            },
            dispatch_args: "dispatch",
        };
        let dispatched_sort = RadixSortOperation::new(
            device, &kernels, &resources,
            sort_definition.plan(rows, 0, digits, RadixSortDispatch {
                small: RadixDispatchDomain::Direct(0),
                rows: RadixDispatchDomain::Direct(rows),
                bucket_prefix: RadixDispatchDomain::Direct(256 * 256),
            }),
            |digit| SortParams { rows, bits_per_field: 32, blocks, digit },
        ).unwrap();

        let record_probe = |encoder: &mut wgpu::CommandEncoder,
                            pass: &passes_core::PassData,
                            bind: &wgpu::BindGroup| {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor::default());
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, bind, &[]);
            compute.dispatch_workgroups(groups, 1, 1);
        };
        let mut timer = GpuTimer::new(device, queue, 80, GpuCompilerPhase::Optimization);
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor::default());
        for _ in 0..10 {
            timer.stamp(&mut encoder, "scan dispatched begin");
            dispatched_scan.record(&mut encoder).unwrap();
            timer.stamp(&mut encoder, "scan dispatched end");
            sync.clear(&mut encoder, 0, None);
            timer.stamp(&mut encoder, "scan program begin");
            record_probe(&mut encoder, scan, &scan_bind);
            timer.stamp(&mut encoder, "scan program end");
            timer.stamp(&mut encoder, "sort dispatched begin");
            dispatched_sort.record(&mut encoder).unwrap();
            timer.stamp(&mut encoder, "sort dispatched end");
            sync.clear(&mut encoder, 0, None);
            timer.stamp(&mut encoder, "sort program begin");
            record_probe(&mut encoder, sort, &sort_bind);
            timer.stamp(&mut encoder, "sort program end");
        }
        timer.resolve(&mut encoder);
        queue.submit(Some(encoder.finish()));
        let stamps = timer.try_read(device).unwrap();
        let median = |index: usize| {
            let mut times: Vec<f64> = stamps.chunks_exact(8).skip(1).map(|sample| {
                let ticks = sample[index + 1].ticks - sample[index].ticks;
                ticks as f64 * f64::from(timer.period_ns()) / 1000.0
            }).collect();
            times.sort_by(f64::total_cmp);
            times[times.len() / 2]
        };
        println!("{rows:8} rows, us: scan {:.2} / {:.2}, sort {:.2} / {:.2} (dispatches / program)",
            median(0), median(2), median(4), median(6));
    }
}
