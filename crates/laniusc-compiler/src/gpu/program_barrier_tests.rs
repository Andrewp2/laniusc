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
    for (groups, rows_per_lane, rounds) in [
        (1u32, 1u32, 2000u32),
        (1, 16, 500),
        (1, 256, 100),
        (8, 1, 2000),
        (64, 1, 2000),
        (64, 4, 500),
        (64, 32, 200),
    ] {
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
    ] {
        let params = uniform_from_val(device, label, &ScanParams { groups, rows, in_place });
        let count = rows as usize;
        let input = storage_rw_for_array::<u32>(device, label, count.max(1));
        let prefix = storage_rw_for_array::<u32>(device, label, count.max(1));
        let total = storage_rw_for_array::<u32>(device, label, 1);
        let sums = storage_rw_for_array::<u32>(device, label, groups as usize);
        let sync = storage_rw_for_array::<u32>(device, label, SYNC_WORDS);
        let data: Vec<u32> = (0..rows).map(|row| row.wrapping_mul(269) % 19).collect();
        if !data.is_empty() {
            let bytes: Vec<u8> = data.iter().flat_map(|value| value.to_le_bytes()).collect();
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
        sync.copy_to(&mut encoder, 0, &readback, 0, (SYNC_WORDS * 4) as u64);
        total.copy_to(&mut encoder, 0, &readback, (SYNC_WORDS * 4) as u64, 4);
        if count != 0 {
            let scanned = if in_place == 0 { &prefix } else { &input };
            scanned.copy_to(&mut encoder, 0, &readback, header_bytes as u64, (count * 4) as u64);
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
        for (row, (value, actual)) in data.into_iter().zip(&output[SYNC_WORDS + 1..]).enumerate() {
            assert_eq!(*actual, expected, "groups {groups}, rows {rows}, row {row}");
            expected = expected.wrapping_add(value);
        }
        assert_eq!(output[SYNC_WORDS], expected, "groups {groups}, rows {rows}");
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
    for (groups, rows, digits) in [(1, 0, 1), (1, 801, 1), (1, 1219, 2), (64, 18_125, 3)] {
        let params = uniform_from_val(device, label, &SortParams { groups, rows, digits });
        let count = rows as usize;
        let data: Vec<u32> = (0..rows)
            .map(|row| ((row.wrapping_mul(269) % 713) << 8) | (if row % 13 == 0 { 255 } else { row % 11 }))
            .collect();
        let mut expected: Vec<u32> = (0..rows).collect();
        let mask = (1u32 << (digits * 8)) - 1;
        expected.sort_by_key(|row| data[*row as usize] & mask);
        let keys = storage_rw_for_array::<u32>(device, label, count.max(1));
        if !data.is_empty() {
            let bytes: Vec<u8> = data.iter().flat_map(|value| value.to_le_bytes()).collect();
            keys.write(queue, 0, &bytes);
        }
        let order = storage_rw_for_array::<u32>(device, label, count.max(1));
        let temporary = storage_rw_for_array::<u32>(device, label, count.max(1));
        let histogram = storage_rw_for_array::<u32>(device, label, count.max(1).div_ceil(256) * 256);
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
