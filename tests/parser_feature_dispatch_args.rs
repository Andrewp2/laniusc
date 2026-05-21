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

const FEATURE_TYPE_ARGS: u32 = 0x0000_0001;
const FEATURE_ENUMS: u32 = 0x0000_0004;
const FEATURE_MATCHES: u32 = 0x0000_0008;
const FEATURE_STRUCTS: u32 = 0x0000_0010;
const INVALID: u32 = u32::MAX;

#[test]
fn parser_tree_feature_dispatch_args_are_gpu_feature_gated() {
    common::block_on_gpu_with_timeout("parser feature dispatch args", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_parser_shader(&root, "tree_feature_dispatch_args");
        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.parser.tree_feature_dispatch_args",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create parser feature dispatch pass");
        let (probe_spv, probe_reflection) = compile_indirect_probe_shader(&root);
        let probe_pass = make_pass_data(
            device,
            "tests.parser.feature_indirect_probe",
            "main",
            leak_bytes(probe_spv),
            leak_bytes(probe_reflection),
        )
        .expect("create parser feature indirect probe pass");

        let disabled = run_feature_dispatch_case(device, queue, &pass, &probe_pass, 4096, 0, 0);
        assert_eq!(disabled.enum_args, [0, 0, 0]);
        assert_eq!(disabled.match_args, [0, 0, 0]);
        assert_eq!(disabled.struct_args, [0, 0, 0]);
        assert_eq!(disabled.indirect_probe_count, 0);

        let active = run_feature_dispatch_case(
            device,
            queue,
            &pass,
            &probe_pass,
            4096,
            0,
            FEATURE_ENUMS | FEATURE_STRUCTS,
        );
        assert_eq!(active.enum_args, [16, 1, 1]);
        assert_eq!(active.match_args, [0, 0, 0]);
        assert_eq!(active.struct_args, [16, 1, 1]);
        assert_eq!(active.indirect_probe_count, 2);

        let ll1_limited = run_feature_dispatch_case(
            device,
            queue,
            &pass,
            &probe_pass,
            4096 | (300 << 16),
            1,
            FEATURE_MATCHES,
        );
        assert_eq!(ll1_limited.enum_args, [0, 0, 0]);
        assert_eq!(ll1_limited.match_args, [2, 1, 1]);
        assert_eq!(ll1_limited.struct_args, [0, 0, 0]);
        assert_eq!(ll1_limited.indirect_probe_count, 1);
    });
}

#[test]
fn parser_list_rank_compaction_uses_owner_link_records() {
    common::block_on_gpu_with_timeout("parser list rank compaction", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (prefix_spv, prefix_reflection) =
            compile_parser_shader(&root, "hir_list_rank_prefix_00_local");
        let (scatter_spv, scatter_reflection) =
            compile_parser_shader(&root, "hir_list_rank_compact_scatter");
        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let prefix_pass = make_pass_data(
            device,
            "tests.parser.hir_list_rank_prefix_00_local",
            "main",
            leak_bytes(prefix_spv),
            leak_bytes(prefix_reflection),
        )
        .expect("create list rank prefix pass");
        let scatter_pass = make_pass_data(
            device,
            "tests.parser.hir_list_rank_compact_scatter",
            "main",
            leak_bytes(scatter_spv),
            leak_bytes(scatter_reflection),
        )
        .expect("create list rank scatter pass");

        let params = uniform_words(device, "tests.parser.list_rank.params", &[8, 0]);
        let ll1_status = storage_words(
            device,
            "tests.parser.list_rank.ll1_status",
            &[0, 0, 0, 0, 0, 8],
            wgpu::BufferUsages::empty(),
        );
        let owner_a = storage_words(
            device,
            "tests.parser.list_rank.owner_a",
            &[
                INVALID, INVALID, 1, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            wgpu::BufferUsages::empty(),
        );
        let link_a = storage_words(
            device,
            "tests.parser.list_rank.link_a",
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 2, INVALID,
            ],
            wgpu::BufferUsages::empty(),
        );
        let rank_flag = storage_words(
            device,
            "tests.parser.list_rank.flag",
            &[0; 8],
            wgpu::BufferUsages::empty(),
        );
        let local_prefix = storage_words(
            device,
            "tests.parser.list_rank.local_prefix",
            &[0; 8],
            wgpu::BufferUsages::empty(),
        );
        let block_sum = storage_words(
            device,
            "tests.parser.list_rank.block_sum",
            &[0],
            wgpu::BufferUsages::empty(),
        );
        let rank_node = storage_words(
            device,
            "tests.parser.list_rank.rank_node",
            &[INVALID; 8],
            wgpu::BufferUsages::empty(),
        );
        let rank_count = storage_words(
            device,
            "tests.parser.list_rank.rank_count",
            &[0],
            wgpu::BufferUsages::empty(),
        );
        let dispatch_args = storage_words(
            device,
            "tests.parser.list_rank.dispatch_args",
            &[0; 3],
            wgpu::BufferUsages::INDIRECT,
        );
        let readback = readback_buffer(device, "tests.parser.list_rank.readback", 12);

        let prefix_resources = HashMap::from([
            ("gHirList".to_string(), params.as_entire_binding()),
            ("ll1_status".to_string(), ll1_status.as_entire_binding()),
            ("hir_list_owner_a".to_string(), owner_a.as_entire_binding()),
            ("hir_list_link_a".to_string(), link_a.as_entire_binding()),
            (
                "hir_list_rank_flag".to_string(),
                rank_flag.as_entire_binding(),
            ),
            (
                "hir_list_rank_local_prefix".to_string(),
                local_prefix.as_entire_binding(),
            ),
            (
                "hir_list_rank_block_sum".to_string(),
                block_sum.as_entire_binding(),
            ),
        ]);
        let prefix_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.parser.list_rank.prefix.bind_group"),
            &prefix_pass.bind_group_layouts[0],
            &prefix_pass.reflection,
            0,
            &prefix_resources,
        )
        .expect("create list rank prefix bind group");

        let scatter_resources = HashMap::from([
            ("gHirList".to_string(), params.as_entire_binding()),
            ("ll1_status".to_string(), ll1_status.as_entire_binding()),
            (
                "hir_list_rank_flag".to_string(),
                rank_flag.as_entire_binding(),
            ),
            (
                "hir_list_rank_local_prefix".to_string(),
                local_prefix.as_entire_binding(),
            ),
            (
                "hir_list_rank_block_prefix".to_string(),
                block_sum.as_entire_binding(),
            ),
            (
                "hir_list_rank_node".to_string(),
                rank_node.as_entire_binding(),
            ),
            (
                "hir_list_rank_count".to_string(),
                rank_count.as_entire_binding(),
            ),
            (
                "hir_list_rank_dispatch_args".to_string(),
                dispatch_args.as_entire_binding(),
            ),
        ]);
        let scatter_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.parser.list_rank.scatter.bind_group"),
            &scatter_pass.bind_group_layouts[0],
            &scatter_pass.reflection,
            0,
            &scatter_resources,
        )
        .expect("create list rank scatter bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.parser.list_rank.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.parser.list_rank.prefix.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&prefix_pass.pipeline);
            compute.set_bind_group(0, Some(&prefix_group), &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.parser.list_rank.scatter.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&scatter_pass.pipeline);
            compute.set_bind_group(0, Some(&scatter_group), &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&rank_node, 0, &readback, 0, 8 * 4);
        encoder.copy_buffer_to_buffer(&rank_count, 0, &readback, 8 * 4, 4);
        encoder.copy_buffer_to_buffer(&dispatch_args, 0, &readback, 9 * 4, 3 * 4);
        queue.submit(Some(encoder.finish()));

        let words = read_u32s(device, &readback, 12);
        assert_eq!(&words[0..2], &[2, 6]);
        assert_eq!(words[2], INVALID);
        assert_eq!(words[8], 2);
        assert_eq!(&words[9..12], &[1, 1, 1]);
    });
}

#[test]
fn parser_type_arg_rank_step_consumes_compact_rank_nodes() {
    common::block_on_gpu_with_timeout("parser type-arg rank compact nodes", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_parser_shader(&root, "hir_type_arg_rank_step");
        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.parser.hir_type_arg_rank_step.compact",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create type-arg rank step pass");

        let params = uniform_words(device, "tests.parser.type_arg_rank.params", &[8, 0]);
        let ll1_status = storage_words(
            device,
            "tests.parser.type_arg_rank.ll1_status",
            &[0, 0, 0, 0, 0, 8],
            wgpu::BufferUsages::empty(),
        );
        let token_feature_flags = storage_words(
            device,
            "tests.parser.type_arg_rank.feature_flags",
            &[FEATURE_TYPE_ARGS],
            wgpu::BufferUsages::empty(),
        );
        let rank_node = storage_words(
            device,
            "tests.parser.type_arg_rank.rank_node",
            &[2, 6, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
            wgpu::BufferUsages::empty(),
        );
        let owner_in = storage_words(
            device,
            "tests.parser.type_arg_rank.owner_in",
            &[
                INVALID, INVALID, 1, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            wgpu::BufferUsages::empty(),
        );
        let link_in = storage_words(
            device,
            "tests.parser.type_arg_rank.link_in",
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 2, INVALID,
            ],
            wgpu::BufferUsages::empty(),
        );
        let rank_in = storage_words(
            device,
            "tests.parser.type_arg_rank.rank_in",
            &[0, 0, 0, 0, 0, 0, 1, 0],
            wgpu::BufferUsages::empty(),
        );

        let sentinel = 0xaaaa_aaaau32;
        let owner_out = storage_words(
            device,
            "tests.parser.type_arg_rank.owner_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let link_out = storage_words(
            device,
            "tests.parser.type_arg_rank.link_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let rank_out = storage_words(
            device,
            "tests.parser.type_arg_rank.rank_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let readback = readback_buffer(device, "tests.parser.type_arg_rank.readback", 24);

        let resources = HashMap::from([
            ("gHirType".to_string(), params.as_entire_binding()),
            ("ll1_status".to_string(), ll1_status.as_entire_binding()),
            (
                "token_feature_flags".to_string(),
                token_feature_flags.as_entire_binding(),
            ),
            (
                "hir_list_rank_node".to_string(),
                rank_node.as_entire_binding(),
            ),
            (
                "hir_type_arg_owner_in".to_string(),
                owner_in.as_entire_binding(),
            ),
            (
                "hir_type_arg_link_in".to_string(),
                link_in.as_entire_binding(),
            ),
            (
                "hir_type_arg_rank_in".to_string(),
                rank_in.as_entire_binding(),
            ),
            (
                "hir_type_arg_owner_out".to_string(),
                owner_out.as_entire_binding(),
            ),
            (
                "hir_type_arg_link_out".to_string(),
                link_out.as_entire_binding(),
            ),
            (
                "hir_type_arg_rank_out".to_string(),
                rank_out.as_entire_binding(),
            ),
        ]);
        let group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.parser.type_arg_rank.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
        .expect("create type-arg rank bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.parser.type_arg_rank.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.parser.type_arg_rank.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, Some(&group), &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&owner_out, 0, &readback, 0, 8 * 4);
        encoder.copy_buffer_to_buffer(&link_out, 0, &readback, 8 * 4, 8 * 4);
        encoder.copy_buffer_to_buffer(&rank_out, 0, &readback, 16 * 4, 8 * 4);
        queue.submit(Some(encoder.finish()));

        let words = read_u32s(device, &readback, 24);
        let owner_out = &words[0..8];
        let link_out = &words[8..16];
        let rank_out = &words[16..24];
        assert_eq!(owner_out[2], 1);
        assert_eq!(link_out[2], INVALID);
        assert_eq!(rank_out[2], 0);
        assert_eq!(owner_out[6], 1);
        assert_eq!(link_out[6], INVALID);
        assert_eq!(rank_out[6], 1);
        assert_eq!(
            owner_out[3], sentinel,
            "unlisted tree nodes must not be processed by type-arg rank"
        );
    });
}

#[test]
fn parser_struct_rank_step_consumes_compact_rank_nodes() {
    common::block_on_gpu_with_timeout("parser struct rank compact nodes", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_parser_shader(&root, "hir_struct_field_rank_step");
        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.parser.hir_struct_field_rank_step.compact",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create struct rank step pass");

        let params = uniform_words(device, "tests.parser.struct_rank.params", &[8, 0]);
        let ll1_status = storage_words(
            device,
            "tests.parser.struct_rank.ll1_status",
            &[0, 0, 0, 0, 0, 8],
            wgpu::BufferUsages::empty(),
        );
        let token_feature_flags = storage_words(
            device,
            "tests.parser.struct_rank.feature_flags",
            &[FEATURE_STRUCTS],
            wgpu::BufferUsages::empty(),
        );
        let rank_node = storage_words(
            device,
            "tests.parser.struct_rank.rank_node",
            &[2, 6, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
            wgpu::BufferUsages::empty(),
        );
        let field_owner_in = storage_words(
            device,
            "tests.parser.struct_rank.field_owner_in",
            &[
                INVALID, INVALID, 1, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            wgpu::BufferUsages::empty(),
        );
        let field_link_in = storage_words(
            device,
            "tests.parser.struct_rank.field_link_in",
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 2, INVALID,
            ],
            wgpu::BufferUsages::empty(),
        );
        let field_rank_in = storage_words(
            device,
            "tests.parser.struct_rank.field_rank_in",
            &[0, 0, 0, 0, 0, 0, 1, 0],
            wgpu::BufferUsages::empty(),
        );
        let invalid_words = [INVALID; 8];
        let zero_words = [0; 8];
        let lit_owner_in = storage_words(
            device,
            "tests.parser.struct_rank.lit_owner_in",
            &invalid_words,
            wgpu::BufferUsages::empty(),
        );
        let lit_link_in = storage_words(
            device,
            "tests.parser.struct_rank.lit_link_in",
            &invalid_words,
            wgpu::BufferUsages::empty(),
        );
        let lit_rank_in = storage_words(
            device,
            "tests.parser.struct_rank.lit_rank_in",
            &zero_words,
            wgpu::BufferUsages::empty(),
        );

        let sentinel = 0xaaaa_aaaau32;
        let field_owner_out = storage_words(
            device,
            "tests.parser.struct_rank.field_owner_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let field_link_out = storage_words(
            device,
            "tests.parser.struct_rank.field_link_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let field_rank_out = storage_words(
            device,
            "tests.parser.struct_rank.field_rank_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let lit_owner_out = storage_words(
            device,
            "tests.parser.struct_rank.lit_owner_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let lit_link_out = storage_words(
            device,
            "tests.parser.struct_rank.lit_link_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let lit_rank_out = storage_words(
            device,
            "tests.parser.struct_rank.lit_rank_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let readback = readback_buffer(device, "tests.parser.struct_rank.readback", 24);

        let resources = HashMap::from([
            ("gHirStruct".to_string(), params.as_entire_binding()),
            ("ll1_status".to_string(), ll1_status.as_entire_binding()),
            (
                "token_feature_flags".to_string(),
                token_feature_flags.as_entire_binding(),
            ),
            (
                "hir_struct_rank_node".to_string(),
                rank_node.as_entire_binding(),
            ),
            (
                "hir_struct_field_owner_in".to_string(),
                field_owner_in.as_entire_binding(),
            ),
            (
                "hir_struct_field_link_in".to_string(),
                field_link_in.as_entire_binding(),
            ),
            (
                "hir_struct_field_rank_in".to_string(),
                field_rank_in.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_owner_in".to_string(),
                lit_owner_in.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_link_in".to_string(),
                lit_link_in.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_rank_in".to_string(),
                lit_rank_in.as_entire_binding(),
            ),
            (
                "hir_struct_field_owner_out".to_string(),
                field_owner_out.as_entire_binding(),
            ),
            (
                "hir_struct_field_link_out".to_string(),
                field_link_out.as_entire_binding(),
            ),
            (
                "hir_struct_field_rank_out".to_string(),
                field_rank_out.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_owner_out".to_string(),
                lit_owner_out.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_link_out".to_string(),
                lit_link_out.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_rank_out".to_string(),
                lit_rank_out.as_entire_binding(),
            ),
        ]);
        let group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.parser.struct_rank.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
        .expect("create struct rank bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.parser.struct_rank.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.parser.struct_rank.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, Some(&group), &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&field_owner_out, 0, &readback, 0, 8 * 4);
        encoder.copy_buffer_to_buffer(&field_link_out, 0, &readback, 8 * 4, 8 * 4);
        encoder.copy_buffer_to_buffer(&field_rank_out, 0, &readback, 16 * 4, 8 * 4);
        queue.submit(Some(encoder.finish()));

        let words = read_u32s(device, &readback, 24);
        let owner_out = &words[0..8];
        let link_out = &words[8..16];
        let rank_out = &words[16..24];
        assert_eq!(owner_out[2], 1);
        assert_eq!(link_out[2], INVALID);
        assert_eq!(rank_out[2], 0);
        assert_eq!(owner_out[6], 1);
        assert_eq!(link_out[6], INVALID);
        assert_eq!(rank_out[6], 1);
        assert_eq!(
            owner_out[3], sentinel,
            "unlisted tree nodes must not be processed by struct rank"
        );
    });
}

#[test]
fn parser_enum_rank_step_consumes_compact_rank_nodes() {
    common::block_on_gpu_with_timeout("parser enum rank compact nodes", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_parser_shader(&root, "hir_enum_variant_rank_step");
        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.parser.hir_enum_variant_rank_step.compact",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create enum rank step pass");

        let params = uniform_words(device, "tests.parser.enum_rank.params", &[8, 0]);
        let ll1_status = storage_words(
            device,
            "tests.parser.enum_rank.ll1_status",
            &[0, 0, 0, 0, 0, 8],
            wgpu::BufferUsages::empty(),
        );
        let token_feature_flags = storage_words(
            device,
            "tests.parser.enum_rank.feature_flags",
            &[FEATURE_ENUMS],
            wgpu::BufferUsages::empty(),
        );
        let rank_node = storage_words(
            device,
            "tests.parser.enum_rank.rank_node",
            &[2, 6, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
            wgpu::BufferUsages::empty(),
        );
        let invalid_words = [INVALID; 8];
        let zero_words = [0; 8];
        let variant_owner_in = storage_words(
            device,
            "tests.parser.enum_rank.variant_owner_in",
            &[
                INVALID, INVALID, 1, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            wgpu::BufferUsages::empty(),
        );
        let variant_link_in = storage_words(
            device,
            "tests.parser.enum_rank.variant_link_in",
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 2, INVALID,
            ],
            wgpu::BufferUsages::empty(),
        );
        let variant_rank_in = storage_words(
            device,
            "tests.parser.enum_rank.variant_rank_in",
            &[0, 0, 0, 0, 0, 0, 1, 0],
            wgpu::BufferUsages::empty(),
        );
        let payload_owner_in = storage_words(
            device,
            "tests.parser.enum_rank.payload_owner_in",
            &invalid_words,
            wgpu::BufferUsages::empty(),
        );
        let payload_link_in = storage_words(
            device,
            "tests.parser.enum_rank.payload_link_in",
            &invalid_words,
            wgpu::BufferUsages::empty(),
        );
        let payload_rank_in = storage_words(
            device,
            "tests.parser.enum_rank.payload_rank_in",
            &zero_words,
            wgpu::BufferUsages::empty(),
        );

        let sentinel = 0xaaaa_aaaau32;
        let variant_owner_out = storage_words(
            device,
            "tests.parser.enum_rank.variant_owner_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let variant_link_out = storage_words(
            device,
            "tests.parser.enum_rank.variant_link_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let variant_rank_out = storage_words(
            device,
            "tests.parser.enum_rank.variant_rank_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let payload_owner_out = storage_words(
            device,
            "tests.parser.enum_rank.payload_owner_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let payload_link_out = storage_words(
            device,
            "tests.parser.enum_rank.payload_link_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let payload_rank_out = storage_words(
            device,
            "tests.parser.enum_rank.payload_rank_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let readback = readback_buffer(device, "tests.parser.enum_rank.readback", 24);

        let resources = HashMap::from([
            ("gHirEnum".to_string(), params.as_entire_binding()),
            ("ll1_status".to_string(), ll1_status.as_entire_binding()),
            (
                "token_feature_flags".to_string(),
                token_feature_flags.as_entire_binding(),
            ),
            (
                "hir_enum_rank_node".to_string(),
                rank_node.as_entire_binding(),
            ),
            (
                "hir_variant_owner_in".to_string(),
                variant_owner_in.as_entire_binding(),
            ),
            (
                "hir_variant_link_in".to_string(),
                variant_link_in.as_entire_binding(),
            ),
            (
                "hir_variant_rank_in".to_string(),
                variant_rank_in.as_entire_binding(),
            ),
            (
                "hir_variant_payload_owner_in".to_string(),
                payload_owner_in.as_entire_binding(),
            ),
            (
                "hir_variant_payload_link_in".to_string(),
                payload_link_in.as_entire_binding(),
            ),
            (
                "hir_variant_payload_rank_in".to_string(),
                payload_rank_in.as_entire_binding(),
            ),
            (
                "hir_variant_owner_out".to_string(),
                variant_owner_out.as_entire_binding(),
            ),
            (
                "hir_variant_link_out".to_string(),
                variant_link_out.as_entire_binding(),
            ),
            (
                "hir_variant_rank_out".to_string(),
                variant_rank_out.as_entire_binding(),
            ),
            (
                "hir_variant_payload_owner_out".to_string(),
                payload_owner_out.as_entire_binding(),
            ),
            (
                "hir_variant_payload_link_out".to_string(),
                payload_link_out.as_entire_binding(),
            ),
            (
                "hir_variant_payload_rank_out".to_string(),
                payload_rank_out.as_entire_binding(),
            ),
        ]);
        let group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.parser.enum_rank.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
        .expect("create enum rank bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.parser.enum_rank.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.parser.enum_rank.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, Some(&group), &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&variant_owner_out, 0, &readback, 0, 8 * 4);
        encoder.copy_buffer_to_buffer(&variant_link_out, 0, &readback, 8 * 4, 8 * 4);
        encoder.copy_buffer_to_buffer(&variant_rank_out, 0, &readback, 16 * 4, 8 * 4);
        queue.submit(Some(encoder.finish()));

        let words = read_u32s(device, &readback, 24);
        let owner_out = &words[0..8];
        let link_out = &words[8..16];
        let rank_out = &words[16..24];
        assert_eq!(owner_out[2], 1);
        assert_eq!(link_out[2], INVALID);
        assert_eq!(rank_out[2], 0);
        assert_eq!(owner_out[6], 1);
        assert_eq!(link_out[6], INVALID);
        assert_eq!(rank_out[6], 1);
        assert_eq!(
            owner_out[3], sentinel,
            "unlisted tree nodes must not be processed by enum rank"
        );
    });
}

#[test]
fn parser_match_rank_step_consumes_compact_rank_nodes() {
    common::block_on_gpu_with_timeout("parser match rank compact nodes", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let (spv, reflection) = compile_parser_shader(&root, "hir_match_arm_rank_step");
        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.parser.hir_match_arm_rank_step.compact",
            "main",
            leak_bytes(spv),
            leak_bytes(reflection),
        )
        .expect("create match rank step pass");

        let params = uniform_words(device, "tests.parser.match_rank.params", &[8, 0]);
        let ll1_status = storage_words(
            device,
            "tests.parser.match_rank.ll1_status",
            &[0, 0, 0, 0, 0, 8],
            wgpu::BufferUsages::empty(),
        );
        let token_feature_flags = storage_words(
            device,
            "tests.parser.match_rank.feature_flags",
            &[FEATURE_MATCHES],
            wgpu::BufferUsages::empty(),
        );
        let rank_node = storage_words(
            device,
            "tests.parser.match_rank.rank_node",
            &[2, 6, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
            wgpu::BufferUsages::empty(),
        );
        let invalid_words = [INVALID; 8];
        let zero_words = [0; 8];
        let arm_owner_in = storage_words(
            device,
            "tests.parser.match_rank.arm_owner_in",
            &[
                INVALID, INVALID, 1, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            wgpu::BufferUsages::empty(),
        );
        let arm_link_in = storage_words(
            device,
            "tests.parser.match_rank.arm_link_in",
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 2, INVALID,
            ],
            wgpu::BufferUsages::empty(),
        );
        let arm_rank_in = storage_words(
            device,
            "tests.parser.match_rank.arm_rank_in",
            &[0, 0, 0, 0, 0, 0, 1, 0],
            wgpu::BufferUsages::empty(),
        );
        let payload_owner_in = storage_words(
            device,
            "tests.parser.match_rank.payload_owner_in",
            &invalid_words,
            wgpu::BufferUsages::empty(),
        );
        let payload_link_in = storage_words(
            device,
            "tests.parser.match_rank.payload_link_in",
            &invalid_words,
            wgpu::BufferUsages::empty(),
        );
        let payload_rank_in = storage_words(
            device,
            "tests.parser.match_rank.payload_rank_in",
            &zero_words,
            wgpu::BufferUsages::empty(),
        );

        let sentinel = 0xaaaa_aaaau32;
        let arm_owner_out = storage_words(
            device,
            "tests.parser.match_rank.arm_owner_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let arm_link_out = storage_words(
            device,
            "tests.parser.match_rank.arm_link_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let arm_rank_out = storage_words(
            device,
            "tests.parser.match_rank.arm_rank_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let payload_owner_out = storage_words(
            device,
            "tests.parser.match_rank.payload_owner_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let payload_link_out = storage_words(
            device,
            "tests.parser.match_rank.payload_link_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let payload_rank_out = storage_words(
            device,
            "tests.parser.match_rank.payload_rank_out",
            &[sentinel; 8],
            wgpu::BufferUsages::empty(),
        );
        let readback = readback_buffer(device, "tests.parser.match_rank.readback", 24);

        let resources = HashMap::from([
            ("gHirMatch".to_string(), params.as_entire_binding()),
            ("ll1_status".to_string(), ll1_status.as_entire_binding()),
            (
                "token_feature_flags".to_string(),
                token_feature_flags.as_entire_binding(),
            ),
            (
                "hir_match_rank_node".to_string(),
                rank_node.as_entire_binding(),
            ),
            (
                "hir_match_arm_owner_in".to_string(),
                arm_owner_in.as_entire_binding(),
            ),
            (
                "hir_match_arm_link_in".to_string(),
                arm_link_in.as_entire_binding(),
            ),
            (
                "hir_match_arm_rank_in".to_string(),
                arm_rank_in.as_entire_binding(),
            ),
            (
                "hir_match_payload_owner_in".to_string(),
                payload_owner_in.as_entire_binding(),
            ),
            (
                "hir_match_payload_link_in".to_string(),
                payload_link_in.as_entire_binding(),
            ),
            (
                "hir_match_payload_rank_in".to_string(),
                payload_rank_in.as_entire_binding(),
            ),
            (
                "hir_match_arm_owner_out".to_string(),
                arm_owner_out.as_entire_binding(),
            ),
            (
                "hir_match_arm_link_out".to_string(),
                arm_link_out.as_entire_binding(),
            ),
            (
                "hir_match_arm_rank_out".to_string(),
                arm_rank_out.as_entire_binding(),
            ),
            (
                "hir_match_payload_owner_out".to_string(),
                payload_owner_out.as_entire_binding(),
            ),
            (
                "hir_match_payload_link_out".to_string(),
                payload_link_out.as_entire_binding(),
            ),
            (
                "hir_match_payload_rank_out".to_string(),
                payload_rank_out.as_entire_binding(),
            ),
        ]);
        let group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.parser.match_rank.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
        .expect("create match rank bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.parser.match_rank.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.parser.match_rank.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, Some(&group), &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&arm_owner_out, 0, &readback, 0, 8 * 4);
        encoder.copy_buffer_to_buffer(&arm_link_out, 0, &readback, 8 * 4, 8 * 4);
        encoder.copy_buffer_to_buffer(&arm_rank_out, 0, &readback, 16 * 4, 8 * 4);
        queue.submit(Some(encoder.finish()));

        let words = read_u32s(device, &readback, 24);
        let owner_out = &words[0..8];
        let link_out = &words[8..16];
        let rank_out = &words[16..24];
        assert_eq!(owner_out[2], 1);
        assert_eq!(link_out[2], INVALID);
        assert_eq!(rank_out[2], 0);
        assert_eq!(owner_out[6], 1);
        assert_eq!(link_out[6], INVALID);
        assert_eq!(rank_out[6], 1);
        assert_eq!(
            owner_out[3], sentinel,
            "unlisted tree nodes must not be processed by match rank"
        );
    });
}

#[derive(Debug)]
struct FeatureDispatchOutput {
    enum_args: [u32; 3],
    match_args: [u32; 3],
    struct_args: [u32; 3],
    indirect_probe_count: u32,
}

fn run_feature_dispatch_case(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    pass: &laniusc::gpu::passes_core::PassData,
    probe_pass: &laniusc::gpu::passes_core::PassData,
    n_and_active: u32,
    uses_ll1: u32,
    feature_flags: u32,
) -> FeatureDispatchOutput {
    let n = n_and_active & 0xffff;
    let active_count = n_and_active >> 16;
    let params = uniform_words(
        device,
        "tests.parser.feature.params",
        &[n, uses_ll1, 16, 17, 0],
    );
    let ll1_status = storage_words(
        device,
        "tests.parser.feature.ll1_status",
        &[0, 0, 0, 0, 0, active_count],
        wgpu::BufferUsages::empty(),
    );
    let token_feature_flags = storage_words(
        device,
        "tests.parser.feature.token_feature_flags",
        &[feature_flags],
        wgpu::BufferUsages::empty(),
    );
    let enum_args = storage_words(
        device,
        "tests.parser.feature.enum_args",
        &[0xffff_ffff; 3],
        wgpu::BufferUsages::INDIRECT,
    );
    let match_args = storage_words(
        device,
        "tests.parser.feature.match_args",
        &[0xffff_ffff; 3],
        wgpu::BufferUsages::INDIRECT,
    );
    let struct_args = storage_words(
        device,
        "tests.parser.feature.struct_args",
        &[0xffff_ffff; 3],
        wgpu::BufferUsages::INDIRECT,
    );
    let readback = readback_buffer(device, "tests.parser.feature.readback", 9);
    let probe_out = storage_words(
        device,
        "tests.parser.feature.probe_out",
        &[0],
        wgpu::BufferUsages::empty(),
    );
    let probe_readback = readback_buffer(device, "tests.parser.feature.probe_readback", 1);

    let resources = HashMap::from([
        ("gTree".to_string(), params.as_entire_binding()),
        ("ll1_status".to_string(), ll1_status.as_entire_binding()),
        (
            "token_feature_flags".to_string(),
            token_feature_flags.as_entire_binding(),
        ),
        (
            "tree_enum_dispatch_args".to_string(),
            enum_args.as_entire_binding(),
        ),
        (
            "tree_match_dispatch_args".to_string(),
            match_args.as_entire_binding(),
        ),
        (
            "tree_struct_dispatch_args".to_string(),
            struct_args.as_entire_binding(),
        ),
    ]);
    let group = bind_group::create_bind_group_from_reflection(
        device,
        Some("tests.parser.feature.bind_group"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )
    .expect("create parser feature dispatch bind group");
    let probe_resources = HashMap::from([("probe_out".to_string(), probe_out.as_entire_binding())]);
    let probe_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("tests.parser.feature.probe_bind_group"),
        &probe_pass.bind_group_layouts[0],
        &probe_pass.reflection,
        0,
        &probe_resources,
    )
    .expect("create parser feature probe bind group");

    let scope = device.push_error_scope(wgpu::ErrorFilter::Validation);
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("tests.parser.feature.encoder"),
    });
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tests.parser.feature.write_args"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(&group), &[]);
        compute.dispatch_workgroups(1, 1, 1);
    }
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("tests.parser.feature.zero_indirect_probe"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&probe_pass.pipeline);
        compute.set_bind_group(0, Some(&probe_group), &[]);
        compute.dispatch_workgroups_indirect(&enum_args, 0);
        compute.dispatch_workgroups_indirect(&match_args, 0);
        compute.dispatch_workgroups_indirect(&struct_args, 0);
    }
    encoder.copy_buffer_to_buffer(&enum_args, 0, &readback, 0, 12);
    encoder.copy_buffer_to_buffer(&match_args, 0, &readback, 12, 12);
    encoder.copy_buffer_to_buffer(&struct_args, 0, &readback, 24, 12);
    encoder.copy_buffer_to_buffer(&probe_out, 0, &probe_readback, 0, 4);
    queue.submit(Some(encoder.finish()));
    device
        .poll(wgpu::PollType::wait_indefinitely())
        .expect("poll parser feature dispatch");
    let validation = pollster::block_on(scope.pop());
    assert!(
        validation.is_none(),
        "zero-sized indirect feature dispatch should validate: {validation:?}"
    );

    let words = read_u32s(device, &readback, 9);
    let probe_words = read_u32s(device, &probe_readback, 1);
    FeatureDispatchOutput {
        enum_args: words[0..3].try_into().unwrap(),
        match_args: words[3..6].try_into().unwrap(),
        struct_args: words[6..9].try_into().unwrap(),
        indirect_probe_count: probe_words[0],
    }
}

fn compile_parser_shader(root: &Path, stem: &str) -> (Vec<u8>, Vec<u8>) {
    let shader = root.join("shaders/parser").join(format!("{stem}.slang"));
    let spv = common::TempArtifact::new("laniusc_parser_feature", stem, Some("spv"));
    let reflection =
        common::TempArtifact::new("laniusc_parser_feature", stem, Some("reflect.json"));
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
        .arg(root.join("shaders/parser"))
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

fn compile_indirect_probe_shader(root: &Path) -> (Vec<u8>, Vec<u8>) {
    let shader =
        common::TempArtifact::new("laniusc_parser_feature", "indirect_probe", Some("slang"));
    shader.write_str(
        r#"
RWStructuredBuffer<uint> probe_out;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x == 0u)
        InterlockedAdd(probe_out[0u], 1u);
}
"#,
    );
    let spv = common::TempArtifact::new("laniusc_parser_feature", "indirect_probe", Some("spv"));
    let reflection = common::TempArtifact::new(
        "laniusc_parser_feature",
        "indirect_probe",
        Some("reflect.json"),
    );
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
        .arg("-o")
        .arg(spv.path())
        .arg(shader.path())
        .output()
        .unwrap_or_else(|err| panic!("run slangc for {}: {err}", shader.path().display()));
    common::assert_command_success("compile indirect probe", &output);
    (
        fs::read(spv.path()).unwrap_or_else(|err| panic!("read {}: {err}", spv.path().display())),
        fs::read(reflection.path())
            .unwrap_or_else(|err| panic!("read {}: {err}", reflection.path().display())),
    )
}

fn uniform_words(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    let mut bytes = vec![0u8; 32.max(words.len() * 4)];
    bytes[..words.len() * 4].copy_from_slice(&u32_bytes(words));
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &bytes,
        usage: wgpu::BufferUsages::UNIFORM,
    })
}

fn storage_words(
    device: &wgpu::Device,
    label: &str,
    words: &[u32],
    extra_usage: wgpu::BufferUsages,
) -> wgpu::Buffer {
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &u32_bytes(words),
        usage: wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_DST
            | wgpu::BufferUsages::COPY_SRC
            | extra_usage,
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

fn u32_bytes(words: &[u32]) -> Vec<u8> {
    words.iter().flat_map(|word| word.to_le_bytes()).collect()
}

fn leak_bytes(bytes: Vec<u8>) -> &'static [u8] {
    Box::leak(bytes.into_boxed_slice())
}
