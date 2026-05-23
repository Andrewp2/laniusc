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

const RADIX_BUCKETS: usize = 257;

#[test]
fn name_radix_bucket_prefix_and_bases_respect_gpu_max_name_length() {
    common::block_on_gpu_with_timeout("type checker name radix active-byte guards", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (prefix_spv, prefix_reflection) =
            compile_shader(&root, "type_check_names_radix_00b_bucket_prefix_active");
        let (bases_spv, bases_reflection) =
            compile_shader(&root, "type_check_names_radix_00c_bucket_bases_active");
        let (lexeme_spv, lexeme_reflection) =
            compile_shader(&root, "type_check_names_01_scatter_lexemes");
        let (byte_dispatch_spv, byte_dispatch_reflection) =
            compile_shader(&root, "type_check_names_radix_byte_dispatch_args");
        let (scatter_spv, scatter_reflection) =
            compile_shader(&root, "type_check_names_radix_01_scatter");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();

        let prefix_pass = make_pass_data(
            device,
            "tests.type_checker.name_radix.bucket_prefix_active",
            "main",
            leak_bytes(prefix_spv),
            leak_bytes(prefix_reflection),
        )
        .expect("create name radix bucket-prefix pass");
        let bases_pass = make_pass_data(
            device,
            "tests.type_checker.name_radix.bucket_bases_active",
            "main",
            leak_bytes(bases_spv),
            leak_bytes(bases_reflection),
        )
        .expect("create name radix bucket-bases pass");
        let lexeme_pass = make_pass_data(
            device,
            "tests.type_checker.name_radix.scatter_lexemes",
            "main",
            leak_bytes(lexeme_spv),
            leak_bytes(lexeme_reflection),
        )
        .expect("create name lexeme scatter pass");
        let byte_dispatch_pass = make_pass_data(
            device,
            "tests.type_checker.name_radix.byte_dispatch_args",
            "main",
            leak_bytes(byte_dispatch_spv),
            leak_bytes(byte_dispatch_reflection),
        )
        .expect("create name radix byte-dispatch pass");
        let scatter_pass = make_pass_data(
            device,
            "tests.type_checker.name_radix.scatter",
            "main",
            leak_bytes(scatter_spv),
            leak_bytes(scatter_reflection),
        )
        .expect("create name radix scatter pass");

        assert_lexeme_scatter_initializes_both_order_buffers(device, queue, &lexeme_pass);
        assert_byte_dispatch_args_disable_inactive_radix_offsets(
            device,
            queue,
            &byte_dispatch_pass,
        );
        assert_byte_dispatch_args_cover_large_name_counts(device, queue, &byte_dispatch_pass);
        assert_prefix_inactive_leaves_records_untouched(device, queue, &prefix_pass);
        assert_prefix_active_uses_histogram_records(device, queue, &prefix_pass);
        assert_prefix_active_covers_more_than_2048_name_blocks(device, queue, &prefix_pass);
        assert_bases_inactive_leaves_records_untouched(device, queue, &bases_pass);
        assert_bases_active_uses_bucket_total_records(device, queue, &bases_pass);
        assert_scatter_inactive_leaves_output_order_untouched(device, queue, &scatter_pass);
    });
}

fn assert_lexeme_scatter_initializes_both_order_buffers(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
) {
    const LANGUAGE_SYMBOL_COUNT: usize = 19;
    let name_count = 1 + LANGUAGE_SYMBOL_COUNT;
    let params = uniform_words(device, "tests.name_radix.lexeme_scatter.params", &[1, 3, 0]);
    let token_words = storage_buffer(
        device,
        "tests.name_radix.lexeme_scatter.token_words",
        &[0, 0, 3, 0],
    );
    let token_count = storage_buffer(device, "tests.name_radix.lexeme_scatter.token_count", &[1]);
    let name_lexeme_flag = storage_buffer(device, "tests.name_radix.lexeme_scatter.flag", &[1]);
    let name_lexeme_kind = storage_buffer(device, "tests.name_radix.lexeme_scatter.kind", &[1]);
    let name_lexeme_prefix = storage_buffer(device, "tests.name_radix.lexeme_scatter.prefix", &[0]);
    let language_symbol_start = storage_buffer(
        device,
        "tests.name_radix.lexeme_scatter.language_start",
        &vec![0; LANGUAGE_SYMBOL_COUNT],
    );
    let language_symbol_len = storage_buffer(
        device,
        "tests.name_radix.lexeme_scatter.language_len",
        &vec![1; LANGUAGE_SYMBOL_COUNT],
    );
    let name_spans = storage_buffer(
        device,
        "tests.name_radix.lexeme_scatter.name_spans",
        &vec![0; name_count * 4],
    );
    let order_in = storage_buffer(
        device,
        "tests.name_radix.lexeme_scatter.order_in",
        &vec![99; name_count],
    );
    let order_tmp = storage_buffer(
        device,
        "tests.name_radix.lexeme_scatter.order_tmp",
        &vec![77; name_count],
    );
    let name_id_by_token = storage_buffer(
        device,
        "tests.name_radix.lexeme_scatter.name_id_by_token",
        &[0],
    );
    let name_count_out = storage_buffer(
        device,
        "tests.name_radix.lexeme_scatter.name_count_out",
        &[0],
    );
    let name_max_len = storage_buffer(device, "tests.name_radix.lexeme_scatter.name_max_len", &[0]);
    let status = storage_buffer(
        device,
        "tests.name_radix.lexeme_scatter.status",
        &[1, 0, 0, 0],
    );
    let order_in_readback = readback_buffer(
        device,
        "tests.name_radix.lexeme_scatter.order_in_readback",
        name_count,
    );
    let order_tmp_readback = readback_buffer(
        device,
        "tests.name_radix.lexeme_scatter.order_tmp_readback",
        name_count,
    );
    let count_readback =
        readback_buffer(device, "tests.name_radix.lexeme_scatter.count_readback", 1);

    let resources = HashMap::from([
        ("gParams".to_string(), params.as_entire_binding()),
        ("token_words".to_string(), token_words.as_entire_binding()),
        ("token_count".to_string(), token_count.as_entire_binding()),
        (
            "name_lexeme_flag".to_string(),
            name_lexeme_flag.as_entire_binding(),
        ),
        (
            "name_lexeme_kind".to_string(),
            name_lexeme_kind.as_entire_binding(),
        ),
        (
            "name_lexeme_prefix".to_string(),
            name_lexeme_prefix.as_entire_binding(),
        ),
        (
            "language_symbol_start".to_string(),
            language_symbol_start.as_entire_binding(),
        ),
        (
            "language_symbol_len".to_string(),
            language_symbol_len.as_entire_binding(),
        ),
        ("name_spans".to_string(), name_spans.as_entire_binding()),
        ("name_order_in".to_string(), order_in.as_entire_binding()),
        ("name_order_tmp".to_string(), order_tmp.as_entire_binding()),
        (
            "name_id_by_token".to_string(),
            name_id_by_token.as_entire_binding(),
        ),
        (
            "name_count_out".to_string(),
            name_count_out.as_entire_binding(),
        ),
        (
            "name_max_len_out".to_string(),
            name_max_len.as_entire_binding(),
        ),
        ("status".to_string(), status.as_entire_binding()),
    ]);
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("tests.type_checker.name_radix.scatter_lexemes.bind_group"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )
    .expect("create lexeme-scatter bind group");

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("tests.type_checker.name_radix.scatter_lexemes.encoder"),
    });
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tests.type_checker.name_radix.scatter_lexemes.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(1, 1, 1);
    }
    encoder.copy_buffer_to_buffer(&order_in, 0, &order_in_readback, 0, (name_count * 4) as u64);
    encoder.copy_buffer_to_buffer(
        &order_tmp,
        0,
        &order_tmp_readback,
        0,
        (name_count * 4) as u64,
    );
    encoder.copy_buffer_to_buffer(&name_count_out, 0, &count_readback, 0, 4);
    queue.submit(Some(encoder.finish()));

    let expected_order = (0..name_count as u32).collect::<Vec<_>>();
    assert_eq!(
        read_u32s(device, &order_in_readback, name_count),
        expected_order,
        "lexeme scatter must initialize canonical order buffer"
    );
    assert_eq!(
        read_u32s(device, &order_tmp_readback, name_count),
        expected_order,
        "lexeme scatter must initialize ping-pong order buffer before inactive radix no-ops"
    );
    assert_eq!(
        read_u32s(device, &count_readback, 1),
        vec![name_count as u32],
        "lexeme scatter should publish compact name count"
    );
}

fn assert_byte_dispatch_args_disable_inactive_radix_offsets(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
) {
    const NAME_RADIX_MAX_BYTES: usize = 64;
    const DISPATCH_WORDS: usize = (1 + NAME_RADIX_MAX_BYTES * 3) * 3;
    let params = uniform_words(
        device,
        "tests.name_radix.byte_dispatch.params",
        &[4, 0, 1, 0],
    );
    let name_count = storage_buffer(device, "tests.name_radix.byte_dispatch.name_count", &[4]);
    let name_max_len = storage_buffer(device, "tests.name_radix.byte_dispatch.name_max_len", &[3]);
    let dispatch_args = storage_buffer(
        device,
        "tests.name_radix.byte_dispatch.args",
        &vec![99; DISPATCH_WORDS],
    );
    let readback = readback_buffer(
        device,
        "tests.name_radix.byte_dispatch.readback",
        DISPATCH_WORDS,
    );
    let resources = HashMap::from([
        ("gParams".to_string(), params.as_entire_binding()),
        ("name_count_in".to_string(), name_count.as_entire_binding()),
        (
            "name_max_len_in".to_string(),
            name_max_len.as_entire_binding(),
        ),
        (
            "radix_dispatch_args".to_string(),
            dispatch_args.as_entire_binding(),
        ),
    ]);
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("tests.type_checker.name_radix.byte_dispatch.bind_group"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )
    .expect("create byte-dispatch bind group");

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("tests.type_checker.name_radix.byte_dispatch.encoder"),
    });
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tests.type_checker.name_radix.byte_dispatch.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(1, 1, 1);
    }
    encoder.copy_buffer_to_buffer(&dispatch_args, 0, &readback, 0, (DISPATCH_WORDS * 4) as u64);
    queue.submit(Some(encoder.finish()));

    let args = read_u32s(device, &readback, DISPATCH_WORDS);
    assert_eq!(
        &args[0..3],
        &[1, 1, 1],
        "slot zero remains the compact-name dispatch for downstream passes"
    );
    let inactive_histogram_base = 3;
    let inactive_prefix_base = (1 + NAME_RADIX_MAX_BYTES) * 3;
    let inactive_bases_base = (1 + NAME_RADIX_MAX_BYTES * 2) * 3;
    assert_eq!(
        &args[inactive_histogram_base..inactive_histogram_base + 3],
        &[0, 0, 0]
    );
    assert_eq!(
        &args[inactive_prefix_base..inactive_prefix_base + 3],
        &[0, 0, 0]
    );
    assert_eq!(
        &args[inactive_bases_base..inactive_bases_base + 3],
        &[0, 0, 0]
    );

    let first_active = 1 + (NAME_RADIX_MAX_BYTES - 3);
    let active_base = first_active * 3;
    let active_prefix_base = (1 + NAME_RADIX_MAX_BYTES + (NAME_RADIX_MAX_BYTES - 3)) * 3;
    let active_bases_base = (1 + NAME_RADIX_MAX_BYTES * 2 + (NAME_RADIX_MAX_BYTES - 3)) * 3;
    assert_eq!(
        &args[active_base..active_base + 3],
        &[1, 1, 1],
        "byte offset two should dispatch for a max name length of three"
    );
    assert_eq!(
        &args[active_prefix_base..active_prefix_base + 3],
        &[RADIX_BUCKETS as u32, 1, 1],
        "active byte prefix pass should dispatch one workgroup per radix bucket"
    );
    assert_eq!(
        &args[active_bases_base..active_bases_base + 3],
        &[1, 1, 1],
        "active byte bases pass should dispatch one workgroup"
    );
}

fn assert_byte_dispatch_args_cover_large_name_counts(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
) {
    const NAME_RADIX_MAX_BYTES: usize = 64;
    const DISPATCH_WORDS: usize = (1 + NAME_RADIX_MAX_BYTES * 3) * 3;
    const NAME_COUNT: u32 = 600_000;
    const NAME_BLOCKS: u32 = (NAME_COUNT + 255) / 256;
    let params = uniform_words(
        device,
        "tests.name_radix.byte_dispatch.large.params",
        &[NAME_COUNT, 0, NAME_BLOCKS, 0],
    );
    let name_count = storage_buffer(
        device,
        "tests.name_radix.byte_dispatch.large.name_count",
        &[NAME_COUNT],
    );
    let name_max_len = storage_buffer(
        device,
        "tests.name_radix.byte_dispatch.large.name_max_len",
        &[3],
    );
    let dispatch_args = storage_buffer(
        device,
        "tests.name_radix.byte_dispatch.large.args",
        &vec![99; DISPATCH_WORDS],
    );
    let readback = readback_buffer(
        device,
        "tests.name_radix.byte_dispatch.large.readback",
        DISPATCH_WORDS,
    );
    let resources = HashMap::from([
        ("gParams".to_string(), params.as_entire_binding()),
        ("name_count_in".to_string(), name_count.as_entire_binding()),
        (
            "name_max_len_in".to_string(),
            name_max_len.as_entire_binding(),
        ),
        (
            "radix_dispatch_args".to_string(),
            dispatch_args.as_entire_binding(),
        ),
    ]);
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("tests.type_checker.name_radix.byte_dispatch.large.bind_group"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )
    .expect("create large byte-dispatch bind group");

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("tests.type_checker.name_radix.byte_dispatch.large.encoder"),
    });
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tests.type_checker.name_radix.byte_dispatch.large.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(1, 1, 1);
    }
    encoder.copy_buffer_to_buffer(&dispatch_args, 0, &readback, 0, (DISPATCH_WORDS * 4) as u64);
    queue.submit(Some(encoder.finish()));

    let args = read_u32s(device, &readback, DISPATCH_WORDS);
    assert_eq!(
        &args[0..3],
        &[NAME_BLOCKS, 1, 1],
        "slot zero should cover name counts above the old 2048-block cap"
    );
    let first_active = 1 + (NAME_RADIX_MAX_BYTES - 3);
    let active_base = first_active * 3;
    assert_eq!(
        &args[active_base..active_base + 3],
        &[NAME_BLOCKS, 1, 1],
        "active radix byte passes should cover all compact name blocks"
    );
}

fn assert_prefix_inactive_leaves_records_untouched(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
) {
    let params = uniform_words(
        device,
        "tests.name_radix.prefix_inactive.params",
        &[4, 0, 1, 4],
    );
    let name_count = storage_buffer(device, "tests.name_radix.prefix_inactive.name_count", &[4]);
    let name_max_len = storage_buffer(
        device,
        "tests.name_radix.prefix_inactive.name_max_len",
        &[3],
    );
    let histogram = storage_buffer(
        device,
        "tests.name_radix.prefix_inactive.histogram",
        &vec![55; RADIX_BUCKETS],
    );
    let prefix = storage_buffer(
        device,
        "tests.name_radix.prefix_inactive.prefix",
        &vec![77; RADIX_BUCKETS],
    );
    let total = storage_buffer(
        device,
        "tests.name_radix.prefix_inactive.total",
        &vec![88; RADIX_BUCKETS],
    );
    let prefix_readback = readback_buffer(
        device,
        "tests.name_radix.prefix_inactive.prefix_readback",
        RADIX_BUCKETS,
    );
    let total_readback = readback_buffer(
        device,
        "tests.name_radix.prefix_inactive.total_readback",
        RADIX_BUCKETS,
    );

    dispatch_prefix_pass(
        device,
        queue,
        pass,
        PrefixBindings {
            params: &params,
            name_count: &name_count,
            name_max_len: &name_max_len,
            histogram: &histogram,
            prefix: &prefix,
            total: &total,
        },
        &[
            (&prefix, &prefix_readback, RADIX_BUCKETS),
            (&total, &total_readback, RADIX_BUCKETS),
        ],
    );

    assert_eq!(
        read_u32s(device, &prefix_readback, RADIX_BUCKETS),
        vec![77; RADIX_BUCKETS],
        "inactive radix byte offset must not rewrite bucket-prefix records"
    );
    assert_eq!(
        read_u32s(device, &total_readback, RADIX_BUCKETS),
        vec![88; RADIX_BUCKETS],
        "inactive radix byte offset must not rewrite bucket-total records"
    );
}

fn assert_prefix_active_uses_histogram_records(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
) {
    let params = uniform_words(
        device,
        "tests.name_radix.prefix_active.params",
        &[5, 0, 1, 2],
    );
    let name_count = storage_buffer(device, "tests.name_radix.prefix_active.name_count", &[5]);
    let name_max_len = storage_buffer(device, "tests.name_radix.prefix_active.name_max_len", &[3]);
    let mut histogram_words = vec![0; RADIX_BUCKETS];
    histogram_words[5] = 2;
    histogram_words[7] = 3;
    let histogram = storage_buffer(
        device,
        "tests.name_radix.prefix_active.histogram",
        &histogram_words,
    );
    let prefix = storage_buffer(
        device,
        "tests.name_radix.prefix_active.prefix",
        &vec![77; RADIX_BUCKETS],
    );
    let total = storage_buffer(
        device,
        "tests.name_radix.prefix_active.total",
        &vec![88; RADIX_BUCKETS],
    );
    let prefix_readback = readback_buffer(
        device,
        "tests.name_radix.prefix_active.prefix_readback",
        RADIX_BUCKETS,
    );
    let total_readback = readback_buffer(
        device,
        "tests.name_radix.prefix_active.total_readback",
        RADIX_BUCKETS,
    );

    dispatch_prefix_pass(
        device,
        queue,
        pass,
        PrefixBindings {
            params: &params,
            name_count: &name_count,
            name_max_len: &name_max_len,
            histogram: &histogram,
            prefix: &prefix,
            total: &total,
        },
        &[
            (&prefix, &prefix_readback, RADIX_BUCKETS),
            (&total, &total_readback, RADIX_BUCKETS),
        ],
    );

    let prefixes = read_u32s(device, &prefix_readback, RADIX_BUCKETS);
    let totals = read_u32s(device, &total_readback, RADIX_BUCKETS);
    assert_eq!(prefixes[5], 0, "single active block has zero prefix");
    assert_eq!(prefixes[7], 0, "single active block has zero prefix");
    assert_eq!(
        totals[5], 2,
        "active pass must total bucket 5 from histogram records"
    );
    assert_eq!(
        totals[7], 3,
        "active pass must total bucket 7 from histogram records"
    );
    assert_eq!(totals[0], 0, "active pass must clear empty bucket totals");
}

fn assert_prefix_active_covers_more_than_2048_name_blocks(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
) {
    const ACTIVE_BLOCKS: usize = 2050;
    const BUCKET: usize = 7;
    const NAME_COUNT: u32 = (ACTIVE_BLOCKS as u32) * 256;
    let params = uniform_words(
        device,
        "tests.name_radix.prefix_large.params",
        &[NAME_COUNT, 0, ACTIVE_BLOCKS as u32, 0],
    );
    let name_count = storage_buffer(
        device,
        "tests.name_radix.prefix_large.name_count",
        &[NAME_COUNT],
    );
    let name_max_len = storage_buffer(device, "tests.name_radix.prefix_large.name_max_len", &[1]);
    let mut histogram_words = vec![0; ACTIVE_BLOCKS * RADIX_BUCKETS];
    for block in 0..ACTIVE_BLOCKS {
        histogram_words[block * RADIX_BUCKETS + BUCKET] = 1;
    }
    let histogram = storage_buffer(
        device,
        "tests.name_radix.prefix_large.histogram",
        &histogram_words,
    );
    let prefix = storage_buffer(
        device,
        "tests.name_radix.prefix_large.prefix",
        &vec![77; ACTIVE_BLOCKS * RADIX_BUCKETS],
    );
    let total = storage_buffer(
        device,
        "tests.name_radix.prefix_large.total",
        &vec![88; RADIX_BUCKETS],
    );
    let prefix_readback = readback_buffer(
        device,
        "tests.name_radix.prefix_large.prefix_readback",
        ACTIVE_BLOCKS * RADIX_BUCKETS,
    );
    let total_readback = readback_buffer(
        device,
        "tests.name_radix.prefix_large.total_readback",
        RADIX_BUCKETS,
    );

    dispatch_prefix_pass(
        device,
        queue,
        pass,
        PrefixBindings {
            params: &params,
            name_count: &name_count,
            name_max_len: &name_max_len,
            histogram: &histogram,
            prefix: &prefix,
            total: &total,
        },
        &[
            (&prefix, &prefix_readback, ACTIVE_BLOCKS * RADIX_BUCKETS),
            (&total, &total_readback, RADIX_BUCKETS),
        ],
    );

    let prefixes = read_u32s(device, &prefix_readback, ACTIVE_BLOCKS * RADIX_BUCKETS);
    let totals = read_u32s(device, &total_readback, RADIX_BUCKETS);
    assert_eq!(
        prefixes[2048 * RADIX_BUCKETS + BUCKET],
        2048,
        "bucket-prefix pass must consume histogram records past the old 2048-block ceiling"
    );
    assert_eq!(
        prefixes[2049 * RADIX_BUCKETS + BUCKET],
        2049,
        "bucket-prefix pass must preserve per-block prefixes for every active name block"
    );
    assert_eq!(
        totals[BUCKET], ACTIVE_BLOCKS as u32,
        "bucket total should include all active compact-name histogram blocks"
    );
}

fn assert_bases_inactive_leaves_records_untouched(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
) {
    let params = uniform_words(
        device,
        "tests.name_radix.bases_inactive.params",
        &[0, 0, 1, 5],
    );
    let name_max_len = storage_buffer(device, "tests.name_radix.bases_inactive.name_max_len", &[2]);
    let mut totals = vec![0; RADIX_BUCKETS];
    totals[0] = 2;
    totals[1] = 3;
    let total = storage_buffer(device, "tests.name_radix.bases_inactive.total", &totals);
    let bases = storage_buffer(
        device,
        "tests.name_radix.bases_inactive.bases",
        &vec![99; RADIX_BUCKETS],
    );
    let bases_readback = readback_buffer(
        device,
        "tests.name_radix.bases_inactive.bases_readback",
        RADIX_BUCKETS,
    );

    dispatch_bases_pass(
        device,
        queue,
        pass,
        BasesBindings {
            params: &params,
            name_max_len: &name_max_len,
            total: &total,
            bases: &bases,
        },
        &bases_readback,
    );

    assert_eq!(
        read_u32s(device, &bases_readback, RADIX_BUCKETS),
        vec![99; RADIX_BUCKETS],
        "inactive radix byte offset must not rewrite bucket-base records"
    );
}

fn assert_bases_active_uses_bucket_total_records(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
) {
    let params = uniform_words(
        device,
        "tests.name_radix.bases_active.params",
        &[0, 0, 1, 5],
    );
    let name_max_len = storage_buffer(device, "tests.name_radix.bases_active.name_max_len", &[6]);
    let mut totals = vec![0; RADIX_BUCKETS];
    totals[0] = 2;
    totals[1] = 3;
    totals[2] = 4;
    let total = storage_buffer(device, "tests.name_radix.bases_active.total", &totals);
    let bases = storage_buffer(
        device,
        "tests.name_radix.bases_active.bases",
        &vec![99; RADIX_BUCKETS],
    );
    let bases_readback = readback_buffer(
        device,
        "tests.name_radix.bases_active.bases_readback",
        RADIX_BUCKETS,
    );

    dispatch_bases_pass(
        device,
        queue,
        pass,
        BasesBindings {
            params: &params,
            name_max_len: &name_max_len,
            total: &total,
            bases: &bases,
        },
        &bases_readback,
    );

    let bases = read_u32s(device, &bases_readback, RADIX_BUCKETS);
    assert_eq!(bases[0], 0, "bucket 0 base is zero");
    assert_eq!(bases[1], 2, "bucket 1 base is prefix of prior totals");
    assert_eq!(bases[2], 5, "bucket 2 base is prefix of prior totals");
    assert_eq!(bases[3], 9, "bucket 3 base includes bucket 2 total");
}

fn assert_scatter_inactive_leaves_output_order_untouched(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
) {
    let params = uniform_words(
        device,
        "tests.name_radix.scatter_inactive.params",
        &[4, 0, 1, 4],
    );
    let name_spans = storage_buffer(
        device,
        "tests.name_radix.scatter_inactive.name_spans",
        &vec![0; 16],
    );
    let name_count = storage_buffer(device, "tests.name_radix.scatter_inactive.name_count", &[4]);
    let name_max_len = storage_buffer(
        device,
        "tests.name_radix.scatter_inactive.name_max_len",
        &[3],
    );
    let order_in = storage_buffer(
        device,
        "tests.name_radix.scatter_inactive.order_in",
        &[0, 1, 2, 3],
    );
    let bucket_base = storage_buffer(
        device,
        "tests.name_radix.scatter_inactive.bucket_base",
        &vec![0; RADIX_BUCKETS],
    );
    let block_bucket_prefix = storage_buffer(
        device,
        "tests.name_radix.scatter_inactive.block_bucket_prefix",
        &vec![0; RADIX_BUCKETS],
    );
    let source_bytes = storage_buffer(device, "tests.name_radix.scatter_inactive.source", &[0]);
    let language_symbol_bytes =
        storage_buffer(device, "tests.name_radix.scatter_inactive.language", &[0]);
    let order_out = storage_buffer(
        device,
        "tests.name_radix.scatter_inactive.order_out",
        &vec![99; 4],
    );
    let readback = readback_buffer(
        device,
        "tests.name_radix.scatter_inactive.order_out_readback",
        4,
    );

    let resources = HashMap::from([
        ("gParams".to_string(), params.as_entire_binding()),
        ("name_spans".to_string(), name_spans.as_entire_binding()),
        ("name_count_in".to_string(), name_count.as_entire_binding()),
        (
            "name_max_len_in".to_string(),
            name_max_len.as_entire_binding(),
        ),
        ("name_order_in".to_string(), order_in.as_entire_binding()),
        (
            "radix_bucket_base".to_string(),
            bucket_base.as_entire_binding(),
        ),
        (
            "radix_block_bucket_prefix".to_string(),
            block_bucket_prefix.as_entire_binding(),
        ),
        ("source_bytes".to_string(), source_bytes.as_entire_binding()),
        (
            "language_symbol_bytes".to_string(),
            language_symbol_bytes.as_entire_binding(),
        ),
        ("name_order_out".to_string(), order_out.as_entire_binding()),
    ]);
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("tests.type_checker.name_radix.scatter_inactive.bind_group"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )
    .expect("create inactive scatter bind group");

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("tests.type_checker.name_radix.scatter_inactive.encoder"),
    });
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tests.type_checker.name_radix.scatter_inactive.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(1, 1, 1);
    }
    encoder.copy_buffer_to_buffer(&order_out, 0, &readback, 0, 16);
    queue.submit(Some(encoder.finish()));

    assert_eq!(
        read_u32s(device, &readback, 4),
        vec![99; 4],
        "inactive radix scatter should not perform ping-pong copies"
    );
}

struct PrefixBindings<'a> {
    params: &'a wgpu::Buffer,
    name_count: &'a wgpu::Buffer,
    name_max_len: &'a wgpu::Buffer,
    histogram: &'a wgpu::Buffer,
    prefix: &'a wgpu::Buffer,
    total: &'a wgpu::Buffer,
}

fn dispatch_prefix_pass(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
    buffers: PrefixBindings<'_>,
    readbacks: &[(&wgpu::Buffer, &wgpu::Buffer, usize)],
) {
    let resources = HashMap::from([
        ("gParams".to_string(), buffers.params.as_entire_binding()),
        (
            "name_count_in".to_string(),
            buffers.name_count.as_entire_binding(),
        ),
        (
            "name_max_len_in".to_string(),
            buffers.name_max_len.as_entire_binding(),
        ),
        (
            "radix_block_histogram".to_string(),
            buffers.histogram.as_entire_binding(),
        ),
        (
            "radix_block_bucket_prefix".to_string(),
            buffers.prefix.as_entire_binding(),
        ),
        (
            "radix_bucket_total".to_string(),
            buffers.total.as_entire_binding(),
        ),
    ]);
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("tests.type_checker.name_radix.bucket_prefix.bind_group"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )
    .expect("create bucket-prefix bind group");

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("tests.type_checker.name_radix.bucket_prefix.encoder"),
    });
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tests.type_checker.name_radix.bucket_prefix.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(RADIX_BUCKETS as u32, 1, 1);
    }
    for (source, readback, count) in readbacks {
        encoder.copy_buffer_to_buffer(source, 0, readback, 0, (*count * 4) as u64);
    }
    queue.submit(Some(encoder.finish()));
}

struct BasesBindings<'a> {
    params: &'a wgpu::Buffer,
    name_max_len: &'a wgpu::Buffer,
    total: &'a wgpu::Buffer,
    bases: &'a wgpu::Buffer,
}

fn dispatch_bases_pass(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
    buffers: BasesBindings<'_>,
    readback: &wgpu::Buffer,
) {
    let resources = HashMap::from([
        ("gParams".to_string(), buffers.params.as_entire_binding()),
        (
            "name_max_len_in".to_string(),
            buffers.name_max_len.as_entire_binding(),
        ),
        (
            "radix_bucket_total".to_string(),
            buffers.total.as_entire_binding(),
        ),
        (
            "radix_bucket_base".to_string(),
            buffers.bases.as_entire_binding(),
        ),
    ]);
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("tests.type_checker.name_radix.bucket_bases.bind_group"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )
    .expect("create bucket-bases bind group");

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("tests.type_checker.name_radix.bucket_bases.encoder"),
    });
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tests.type_checker.name_radix.bucket_bases.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, &bind_group, &[]);
        compute.dispatch_workgroups(1, 1, 1);
    }
    encoder.copy_buffer_to_buffer(buffers.bases, 0, readback, 0, 4 * RADIX_BUCKETS as u64);
    queue.submit(Some(encoder.finish()));
}

fn compile_shader(root: &Path, stem: &str) -> (Vec<u8>, Vec<u8>) {
    let shader = root
        .join("shaders/type_checker")
        .join(format!("{stem}.slang"));
    let spv = common::TempArtifact::new("laniusc_name_radix", stem, Some("spv"));
    let reflection = common::TempArtifact::new("laniusc_name_radix", stem, Some("reflect.json"));
    let output = Command::new(slangc_command())
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
    common::assert_command_success(format!("compile {stem}"), &output);
    (
        fs::read(spv.path()).unwrap_or_else(|err| panic!("read {}: {err}", spv.path().display())),
        fs::read(reflection.path())
            .unwrap_or_else(|err| panic!("read {}: {err}", reflection.path().display())),
    )
}

fn slangc_command() -> PathBuf {
    env::var_os("SLANGC")
        .map(PathBuf::from)
        .unwrap_or_else(|| PathBuf::from("slangc"))
}

fn uniform_words(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &u32_bytes(words),
        usage: wgpu::BufferUsages::UNIFORM,
    })
}

fn storage_buffer(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &u32_bytes(words),
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_DST
            | wgpu::BufferUsages::COPY_SRC,
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
