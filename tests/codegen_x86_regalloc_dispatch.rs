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

const INVALID: u32 = 0xffff_ffff;
const FUNC_META_WORDS: usize = 8;
const TOKEN_WORDS: usize = 8;
const CHUNK_COUNT: usize = 8;
const ROWS_PER_CHUNK: u32 = 16;
const HIR_FN: u32 = 3;
const HIR_PARAM: u32 = 4;
const HIR_STMT: u32 = 7;
const HIR_IF_STMT: u32 = 10;
const HIR_CALL_EXPR: u32 = 19;
const HIR_NAME_EXPR: u32 = 22;
const HIR_LITERAL_EXPR: u32 = 23;
const HIR_ARRAY_EXPR: u32 = 24;
const HIR_ENUM_ITEM: u32 = 26;
const HIR_STRUCT_ITEM: u32 = 27;
const HIR_FOR_STMT: u32 = 30;
const HIR_MATCH_EXPR: u32 = 34;
const STMT_RECORD_KIND_RETURN: u32 = 2;
const STMT_RECORD_KIND_IF: u32 = 3;
const STMT_RECORD_KIND_ASSIGN: u32 = 5;
const STMT_RECORD_KIND_FOR: u32 = 7;
const HIR_EXPR_NAME: u32 = 2;
const HIR_EXPR_INT: u32 = 3;
const ENTRYPOINT_MAIN: u32 = 1;
const X86_FEATURE_ENUM: u32 = 1 << 0;
const X86_FEATURE_MATCH: u32 = 1 << 1;
const X86_FEATURE_AGGREGATE: u32 = 1 << 2;
const X86_FEATURE_CALL: u32 = 1 << 3;
const X86_NODE_INST_EXPR_VALUE: u32 = 1;
const X86_VINST_IMM_I32: u32 = 1;
const X86_VINST_PARAM: u32 = 2;
const X86_VINST_BINARY: u32 = 4;
const X86_VINST_CALL_MIXED: u32 = 20;
const X86_OP_SHL_I32: u32 = 11;
const X86_ARG_SCALAR: u32 = 1;
const X86_INST_V_MOV_R32_IMM32: u32 = 50;
const X86_INST_V_RETURN_R32: u32 = 55;
const X86_INST_V_FOR_ARRAY_BRANCH: u32 = 68;
const X86_INST_V_CALL_MIXED_DIRECT: u32 = 71;
const X86_INST_V_MATCH_TAG_BRANCH: u32 = 77;
const X86_INST_V_ENTRY_STACK_JMP: u32 = 64;
const X86_INST_V_EXIT_ZERO: u32 = 65;
const X86_INST_V_STORE_LOCAL_IMM32: u32 = 67;
const X86_INST_V_STORE_RET_PTR_IMM32: u32 = 75;
const X86_AGG_SOURCE_LOCAL: u32 = 1;
const X86_REG_EAX: u32 = 0;
const X86_REG_ESI: u32 = 6;
const X86_REG_EDI: u32 = 7;
const X86_REG_R8D: u32 = 8;
const X86_REG_R10D: u32 = 10;
const X86_NODE_INST_RANGE_KIND_SHIFT: u32 = 28;
const X86_LOCATION_META_PARAM_DECL: u32 = 0xd000_0000;

#[test]
fn x86_feature_counts_consumes_hir_kind_records() {
    common::block_on_gpu_with_timeout("x86 feature counts consume HIR records", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let artifacts = compile_shader(&root, "x86_feature_counts");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.x86.feature_counts",
            "main",
            leak_bytes(artifacts.0),
            leak_bytes(artifacts.1),
        )
        .expect("create feature-counts pass");

        let params = input_uniform(device, "tests.x86.feature_counts.params", &[64, 0, 0, 15]);
        let hir_status = storage_buffer(
            device,
            "tests.x86.feature_counts.hir_status",
            &[0, 0, INVALID, 0, 0, 14],
        );
        let hir_kind = storage_buffer(
            device,
            "tests.x86.feature_counts.hir_kind",
            &[
                HIR_PARAM,
                HIR_CALL_EXPR,
                HIR_STMT,
                HIR_STMT,
                HIR_IF_STMT,
                HIR_NAME_EXPR,
                HIR_FOR_STMT,
                HIR_LITERAL_EXPR,
                HIR_NAME_EXPR,
                HIR_ENUM_ITEM,
                HIR_MATCH_EXPR,
                HIR_ARRAY_EXPR,
                HIR_STRUCT_ITEM,
                HIR_CALL_EXPR,
                HIR_ENUM_ITEM,
            ],
        );
        let mut hir_stmt_record_words = vec![INVALID; 15 * 4];
        hir_stmt_record_words[2 * 4] = STMT_RECORD_KIND_RETURN;
        hir_stmt_record_words[3 * 4] = STMT_RECORD_KIND_ASSIGN;
        hir_stmt_record_words[3 * 4 + 3] = 2;
        hir_stmt_record_words[4 * 4] = STMT_RECORD_KIND_IF;
        hir_stmt_record_words[4 * 4 + 1] = 5;
        hir_stmt_record_words[6 * 4] = STMT_RECORD_KIND_FOR;
        hir_stmt_record_words[6 * 4 + 3] = 8;
        let hir_stmt_record = storage_buffer(
            device,
            "tests.x86.feature_counts.hir_stmt_record",
            &hir_stmt_record_words,
        );
        let mut hir_expr_record_words = vec![INVALID; 15 * 4];
        hir_expr_record_words[5 * 4] = HIR_EXPR_NAME;
        hir_expr_record_words[7 * 4] = HIR_EXPR_INT;
        hir_expr_record_words[8 * 4] = HIR_EXPR_NAME;
        let hir_expr_record = storage_buffer(
            device,
            "tests.x86.feature_counts.hir_expr_record",
            &hir_expr_record_words,
        );
        let hir_token_pos = storage_buffer(
            device,
            "tests.x86.feature_counts.hir_token_pos",
            &[
                10, 11, 12, 13, 14, 15, 16, 17, INVALID, INVALID, INVALID, INVALID, INVALID, 30,
                INVALID,
            ],
        );
        let parent = storage_buffer(
            device,
            "tests.x86.feature_counts.parent",
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, 4, INVALID, 6, 6, INVALID, INVALID,
                INVALID, INVALID, INVALID, INVALID,
            ],
        );
        let first_child = storage_buffer(
            device,
            "tests.x86.feature_counts.first_child",
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 7, INVALID, INVALID, INVALID,
                INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
        );
        let mut enclosing_fn_words = vec![0; 64];
        for token in 10..=18 {
            enclosing_fn_words[token] = 1;
        }
        let enclosing_fn = storage_buffer(
            device,
            "tests.x86.feature_counts.enclosing_fn",
            &enclosing_fn_words,
        );
        let feature_record = storage_buffer(
            device,
            "tests.x86.feature_counts.record",
            &[0, 0, 0, 0, 0, 0, 0, 0],
        );
        let readback = readback_buffer(device, "tests.x86.feature_counts.readback", 8);
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.feature_counts.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                ("hir_status", hir_status.as_entire_binding()),
                ("hir_kind", hir_kind.as_entire_binding()),
                ("hir_stmt_record", hir_stmt_record.as_entire_binding()),
                ("hir_expr_record", hir_expr_record.as_entire_binding()),
                ("hir_token_pos", hir_token_pos.as_entire_binding()),
                ("parent", parent.as_entire_binding()),
                ("first_child", first_child.as_entire_binding()),
                ("enclosing_fn", enclosing_fn.as_entire_binding()),
                ("x86_feature_record", feature_record.as_entire_binding()),
            ]),
        )
        .expect("create feature-counts bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.feature_counts.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.feature_counts.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&feature_record, 0, &readback, 0, 32);
        queue.submit(Some(encoder.finish()));

        let words = read_u32s(device, &readback, 8);
        assert_eq!(
            words[0],
            X86_FEATURE_ENUM | X86_FEATURE_MATCH | X86_FEATURE_AGGREGATE | X86_FEATURE_CALL,
            "feature mask must be derived from active HIR kind rows"
        );
        assert_eq!(words[1], 1, "inactive enum row must not be counted");
        assert_eq!(words[2], 1, "match expressions should be counted");
        assert_eq!(words[3], 2, "aggregate HIR shapes should be counted");
        assert_eq!(
            words[4], 16,
            "scalar instruction estimate must consume stmt, expr, token-position, function-context, parent, and first-child records"
        );
        assert_eq!(words[5], 2, "call expressions should be counted");
        assert_eq!(words[6], 1, "param nodes should be counted");
        assert_eq!(words[7], 0, "reserved feature words stay zero");
    });
}

#[test]
fn x86_regalloc_dispatch_uses_function_span_not_global_instruction_count() {
    common::block_on_gpu_with_timeout(
        "x86 regalloc dispatch args use function spans",
        async move {
            let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
            let span_max_artifacts = compile_shader(&root, "x86_virtual_func_span_max");
            let dispatch_artifacts = compile_shader(&root, "x86_virtual_regalloc_dispatch_args");

            let gpu = device::global();
            let device = gpu.device.as_ref();
            let queue = gpu.queue.as_ref();
            let span_max_pass = make_pass_data(
                device,
                "tests.x86.virtual_func_span_max",
                "main",
                leak_bytes(span_max_artifacts.0),
                leak_bytes(span_max_artifacts.1),
            )
            .expect("create virtual_func_span_max pass");
            let dispatch_pass = make_pass_data(
                device,
                "tests.x86.virtual_regalloc_dispatch_args",
                "main",
                leak_bytes(dispatch_artifacts.0),
                leak_bytes(dispatch_artifacts.1),
            )
            .expect("create virtual_regalloc_dispatch_args pass");

            let params = input_uniform(
                device,
                "tests.x86.params",
                &[
                    TOKEN_WORDS as u32,
                    0,
                    0,
                    0,
                    128,
                    0,
                    ROWS_PER_CHUNK,
                    CHUNK_COUNT as u32,
                    4,
                ],
            );
            let func_meta = storage_buffer(
                device,
                "tests.x86.func_meta",
                &[3, 0, INVALID, 0, INVALID, 0, 0, 0],
            );
            let func_slot_by_index =
                storage_buffer(device, "tests.x86.func_slot_by_index", &[1, 2, 3, INVALID]);
            let first_rows = storage_buffer(
                device,
                "tests.x86.func_first_virtual_row",
                &[INVALID, 0, 40, 100, INVALID, INVALID, INVALID, INVALID],
            );
            let last_rows = storage_buffer(
                device,
                "tests.x86.func_last_virtual_row",
                &[0, 3, 75, 107, 0, 0, 0, 0],
            );
            let first_row_status = storage_buffer(
                device,
                "tests.x86.func_first_virtual_row_status",
                &[1, 0, INVALID, 128],
            );
            let virtual_inst_status = storage_buffer(
                device,
                "tests.x86.virtual_inst_status",
                &[1, 0, INVALID, 128],
            );
            let dispatch_args = storage_buffer(
                device,
                "tests.x86.active_virtual_regalloc_dispatch_args",
                &[99; CHUNK_COUNT * 3],
            );
            let func_meta_readback = readback_buffer(device, "tests.x86.func_meta.readback", 8);
            let dispatch_readback =
                readback_buffer(device, "tests.x86.dispatch_args.readback", CHUNK_COUNT * 3);

            let span_bind_group = bind_group::create_bind_group_from_reflection(
                device,
                Some("tests.x86.virtual_func_span_max.bind_group"),
                &span_max_pass.bind_group_layouts[0],
                &span_max_pass.reflection,
                0,
                &binding_map(&[
                    ("gParams", params.as_entire_binding()),
                    (
                        "x86_func_slot_by_index",
                        func_slot_by_index.as_entire_binding(),
                    ),
                    ("x86_func_first_virtual_row", first_rows.as_entire_binding()),
                    ("x86_func_last_virtual_row", last_rows.as_entire_binding()),
                    (
                        "x86_func_first_virtual_row_status",
                        first_row_status.as_entire_binding(),
                    ),
                    ("x86_func_meta", func_meta.as_entire_binding()),
                ]),
            )
            .expect("create span max bind group");
            let dispatch_bind_group = bind_group::create_bind_group_from_reflection(
                device,
                Some("tests.x86.virtual_regalloc_dispatch_args.bind_group"),
                &dispatch_pass.bind_group_layouts[0],
                &dispatch_pass.reflection,
                0,
                &binding_map(&[
                    ("gParams", params.as_entire_binding()),
                    (
                        "x86_virtual_inst_status",
                        virtual_inst_status.as_entire_binding(),
                    ),
                    ("x86_func_meta", func_meta.as_entire_binding()),
                    (
                        "active_virtual_regalloc_dispatch_args",
                        dispatch_args.as_entire_binding(),
                    ),
                ]),
            )
            .expect("create regalloc dispatch bind group");

            let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("tests.x86.regalloc_dispatch.encoder"),
            });
            {
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("tests.x86.virtual_func_span_max.pass"),
                    timestamp_writes: None,
                });
                pass.set_pipeline(&span_max_pass.pipeline);
                pass.set_bind_group(0, &span_bind_group, &[]);
                pass.dispatch_workgroups(1, 1, 1);
            }
            {
                let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("tests.x86.virtual_regalloc_dispatch_args.pass"),
                    timestamp_writes: None,
                });
                pass.set_pipeline(&dispatch_pass.pipeline);
                pass.set_bind_group(0, &dispatch_bind_group, &[]);
                pass.dispatch_workgroups(1, 1, 1);
            }
            encoder.copy_buffer_to_buffer(&func_meta, 0, &func_meta_readback, 0, 8 * 4);
            encoder.copy_buffer_to_buffer(
                &dispatch_args,
                0,
                &dispatch_readback,
                0,
                (CHUNK_COUNT * 3 * 4) as u64,
            );
            queue.submit(Some(encoder.finish()));

            let func_meta_words = read_u32s(device, &func_meta_readback, FUNC_META_WORDS);
            assert_eq!(
                func_meta_words[5], 36,
                "function-span reduction should record the largest per-function virtual row span"
            );
            assert_eq!(
                func_meta_words[6], 3,
                "dispatch-args pass should publish the active regalloc chunk count"
            );
            assert_eq!(
                func_meta_words[7], CHUNK_COUNT as u32,
                "dispatch-args pass should publish the host-recorded regalloc chunk count"
            );

            let dispatch_words = read_u32s(device, &dispatch_readback, CHUNK_COUNT * 3);
            assert_eq!(&dispatch_words[0..9], &[1, 1, 1, 1, 1, 1, 1, 1, 1]);
            assert_eq!(
                &dispatch_words[9..],
                &[0; 15],
                "chunks beyond max function span should be zero-dispatched even when global inst_count is larger"
            );
        },
    );
}

#[test]
fn x86_node_tree_projection_keeps_parent_and_subtree_end_only() {
    common::block_on_gpu_with_timeout("x86 compact node tree projection", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let artifacts = compile_shader(&root, "x86_node_tree_info");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.x86.node_tree_info",
            "main",
            leak_bytes(artifacts.0),
            leak_bytes(artifacts.1),
        )
        .expect("create node_tree_info pass");

        let params = input_uniform(device, "tests.x86.node_tree_info.params", &[0, 0, 0, 5]);
        let hir_status = storage_buffer(
            device,
            "tests.x86.node_tree_info.hir_status",
            &[0, 0, INVALID, 0, 0, 5],
        );
        let parent = storage_buffer(
            device,
            "tests.x86.node_tree_info.parent",
            &[INVALID, 0, 0, 2, 2],
        );
        let subtree_end = storage_buffer(
            device,
            "tests.x86.node_tree_info.subtree_end",
            &[5, 2, 5, 4, 5],
        );
        let node_tree_status = storage_buffer(
            device,
            "tests.x86.node_tree_info.node_tree_status",
            &[1, 0, INVALID, 0],
        );
        let status_readback =
            readback_buffer(device, "tests.x86.node_tree_info.status.readback", 4);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.node_tree_info.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                ("hir_status", hir_status.as_entire_binding()),
                ("parent", parent.as_entire_binding()),
                ("subtree_end", subtree_end.as_entire_binding()),
                ("x86_node_tree_status", node_tree_status.as_entire_binding()),
            ]),
        )
        .expect("create node_tree_info bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.node_tree_info.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.node_tree_info.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&node_tree_status, 0, &status_readback, 0, 4 * 4);
        queue.submit(Some(encoder.finish()));

        let status = read_u32s(device, &status_readback, 4);
        assert_eq!(&status[0..4], &[1, 0, INVALID, 5]);
    });
}

#[test]
fn x86_func_discover_consumes_hir_function_records_without_slot_append() {
    common::block_on_gpu_with_timeout("x86 function discovery records", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let artifacts = compile_shader(&root, "x86_func_discover");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.x86.func_discover",
            "main",
            leak_bytes(artifacts.0),
            leak_bytes(artifacts.1),
        )
        .expect("create func_discover pass");

        let params = input_uniform(
            device,
            "tests.x86.func_discover.params",
            &[12, 0, 0, 6, 0, 0, ROWS_PER_CHUNK, 1, 2],
        );
        let hir_status = storage_buffer(
            device,
            "tests.x86.func_discover.hir_status",
            &[0, 0, INVALID, 0, 0, 6],
        );
        let hir_kind = storage_buffer(
            device,
            "tests.x86.func_discover.hir_kind",
            &[HIR_FN, 0, HIR_FN, HIR_FN, 0, 0],
        );
        let node_tree_status =
            storage_buffer(device, "tests.x86.func_discover.node_tree_status", &[1, 0]);
        let decl_token = storage_buffer(
            device,
            "tests.x86.func_discover.decl_token",
            &[0, INVALID, 4, 8, INVALID, INVALID],
        );
        let name_token = storage_buffer(
            device,
            "tests.x86.func_discover.name_token",
            &[1, INVALID, 5, 9, INVALID, INVALID],
        );
        let token_pos = storage_buffer(
            device,
            "tests.x86.func_discover.token_pos",
            &[0, INVALID, 4, 8, INVALID, INVALID],
        );
        let entrypoint_tag = storage_buffer(
            device,
            "tests.x86.func_discover.entrypoint_tag",
            &[0, 0, ENTRYPOINT_MAIN, 0, 0, 0],
        );
        let func_meta = storage_buffer(
            device,
            "tests.x86.func_discover.func_meta",
            &[0, 0, INVALID, 0, INVALID, 0, 0, 0],
        );
        let node_func = storage_buffer(device, "tests.x86.func_discover.node_func", &[INVALID; 6]);
        let decl_node = storage_buffer(
            device,
            "tests.x86.func_discover.decl_node_by_token",
            &[INVALID; 12],
        );
        let func_slot_by_node = storage_buffer(
            device,
            "tests.x86.func_discover.func_slot_by_node",
            &[INVALID; 6],
        );
        let meta_readback = readback_buffer(device, "tests.x86.func_discover.meta.readback", 8);
        let node_func_readback =
            readback_buffer(device, "tests.x86.func_discover.node_func.readback", 6);
        let decl_readback = readback_buffer(device, "tests.x86.func_discover.decl.readback", 12);
        let slot_by_node_readback =
            readback_buffer(device, "tests.x86.func_discover.slot_by_node.readback", 6);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.func_discover.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                ("hir_status", hir_status.as_entire_binding()),
                ("hir_kind", hir_kind.as_entire_binding()),
                ("x86_node_tree_status", node_tree_status.as_entire_binding()),
                ("hir_node_decl_token", decl_token.as_entire_binding()),
                ("hir_node_name_token", name_token.as_entire_binding()),
                ("hir_token_pos", token_pos.as_entire_binding()),
                ("fn_entrypoint_tag", entrypoint_tag.as_entire_binding()),
                ("x86_func_meta", func_meta.as_entire_binding()),
                ("x86_node_func", node_func.as_entire_binding()),
                ("x86_decl_node_by_token", decl_node.as_entire_binding()),
                (
                    "x86_func_slot_by_node",
                    func_slot_by_node.as_entire_binding(),
                ),
            ]),
        )
        .expect("create func_discover bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.func_discover.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.func_discover.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&func_meta, 0, &meta_readback, 0, 8 * 4);
        encoder.copy_buffer_to_buffer(&node_func, 0, &node_func_readback, 0, 6 * 4);
        encoder.copy_buffer_to_buffer(&decl_node, 0, &decl_readback, 0, 12 * 4);
        encoder.copy_buffer_to_buffer(&func_slot_by_node, 0, &slot_by_node_readback, 0, 6 * 4);
        queue.submit(Some(encoder.finish()));

        let meta = read_u32s(device, &meta_readback, 8);
        assert_eq!(
            meta[0], 0,
            "function count is owned by the later prefix-scan scatter pass"
        );
        assert_eq!(
            meta[1], 1,
            "main-entry count should come from entrypoint tags"
        );
        assert_eq!(
            meta[2], INVALID,
            "compact main slot is owned by the later function-slot scatter pass"
        );
        assert_eq!(
            meta[4], 2,
            "main node should come from the tagged HIR function"
        );

        assert_eq!(
            read_u32s(device, &node_func_readback, 6),
            vec![0, INVALID, 2, 3, INVALID, INVALID]
        );
        let decls = read_u32s(device, &decl_readback, 12);
        assert_eq!(decls[0], 0);
        assert_eq!(decls[1], 0);
        assert_eq!(decls[4], 2);
        assert_eq!(decls[5], 2);
        assert_eq!(decls[8], 3);
        assert_eq!(decls[9], 3);

        assert_eq!(
            read_u32s(device, &slot_by_node_readback, 6),
            vec![0, INVALID, 4, 8, INVALID, INVALID],
            "function discovery keeps provisional function keys until the scan scatter compacts them"
        );
    });
}

#[test]
fn x86_param_instruction_records_use_hir_param_records_without_reverse_tail() {
    common::block_on_gpu_with_timeout("x86 param instruction metadata records", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let counts_artifacts = compile_shader(&root, "x86_node_inst_counts");
        let locations_artifacts = compile_shader(&root, "x86_node_inst_locations");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let counts_pass = make_pass_data(
            device,
            "tests.x86.param_records.counts",
            "main",
            leak_bytes(counts_artifacts.0),
            leak_bytes(counts_artifacts.1),
        )
        .expect("create node-inst-counts pass");
        let locations_pass = make_pass_data(
            device,
            "tests.x86.param_records.locations",
            "main",
            leak_bytes(locations_artifacts.0),
            leak_bytes(locations_artifacts.1),
        )
        .expect("create node-inst-locations pass");

        let params = input_uniform(device, "tests.x86.param_records.params", &[12, 0, 0, 4]);
        let location_params = input_uniform(
            device,
            "tests.x86.param_records.location_params",
            &[12, 0, 0, 4, 16],
        );
        let hir_status = storage_buffer(
            device,
            "tests.x86.param_records.hir_status",
            &[0, 0, INVALID, 0, 0, 4],
        );
        let hir_kind = storage_buffer(
            device,
            "tests.x86.param_records.hir_kind",
            &[0, HIR_PARAM, 0, 0],
        );
        let hir_stmt_record = storage_buffer(
            device,
            "tests.x86.param_records.stmt_record",
            &[INVALID; 16],
        );
        let hir_expr_record = storage_buffer(
            device,
            "tests.x86.param_records.expr_record",
            &[INVALID; 16],
        );
        let hir_param_record = storage_buffer(
            device,
            "tests.x86.param_records.hir_param_record",
            &[
                INVALID, INVALID, INVALID, INVALID, 3, 0, 7, 1, INVALID, INVALID, INVALID, INVALID,
                INVALID, INVALID, INVALID, INVALID,
            ],
        );
        let expr_resolved = storage_buffer(
            device,
            "tests.x86.param_records.expr_resolved",
            &[INVALID; 4],
        );
        let node_func = storage_buffer(
            device,
            "tests.x86.param_records.node_func",
            &[INVALID, 3, INVALID, INVALID],
        );
        let visible_decl = storage_buffer(
            device,
            "tests.x86.param_records.visible_decl",
            &[INVALID; 12],
        );
        let mut decl_layout_words = vec![INVALID; 12 * 4];
        decl_layout_words[7 * 4] = 42;
        decl_layout_words[7 * 4 + 1] = 1;
        decl_layout_words[7 * 4 + 2] = 0;
        let decl_layout = storage_buffer(
            device,
            "tests.x86.param_records.decl_layout",
            &decl_layout_words,
        );
        let decl_layout_status = storage_buffer(
            device,
            "tests.x86.param_records.decl_layout_status",
            &[1, 0, INVALID, 0],
        );
        let mut param_reg_words = vec![INVALID; 12 * 5];
        param_reg_words[7 * 5] = 3;
        param_reg_words[7 * 5 + 1] = 1;
        param_reg_words[7 * 5 + 2] = 0;
        param_reg_words[7 * 5 + 3] = 4;
        param_reg_words[7 * 5 + 4] = 7;
        let param_reg = storage_buffer(
            device,
            "tests.x86.param_records.param_reg",
            &param_reg_words,
        );
        let tree_parent = storage_buffer(
            device,
            "tests.x86.param_records.tree_parent",
            &[INVALID, 0, INVALID, INVALID],
        );
        let tree_subtree_end = storage_buffer(
            device,
            "tests.x86.param_records.tree_subtree_end",
            &[4, 2, INVALID, INVALID],
        );
        let node_tree_status = storage_buffer(
            device,
            "tests.x86.param_records.node_tree_status",
            &[1, 0, INVALID, 0],
        );
        let enclosing_return = storage_buffer(
            device,
            "tests.x86.param_records.enclosing_return",
            &[INVALID; 4],
        );
        let match_return = storage_buffer(
            device,
            "tests.x86.param_records.match_return",
            &[INVALID; 4],
        );
        let call_record = storage_buffer(
            device,
            "tests.x86.param_records.call_record",
            &[INVALID; 16],
        );
        let call_callee_owner =
            storage_buffer(device, "tests.x86.param_records.call_callee_owner", &[0; 4]);
        let ok_status = storage_buffer(device, "tests.x86.param_records.ok_status", &[1, 0]);
        let intrinsic_record =
            storage_buffer(device, "tests.x86.param_records.intrinsic_record", &[0; 12]);
        let enum_value_record = storage_buffer(
            device,
            "tests.x86.param_records.enum_value_record",
            &[INVALID; 8],
        );
        let feature_record = input_uniform(
            device,
            "tests.x86.param_records.feature_record",
            &[0, 0, 0, 0],
        );
        let match_record = storage_buffer(
            device,
            "tests.x86.param_records.match_record",
            &[INVALID; 16],
        );
        let match_pattern_owner = storage_buffer(
            device,
            "tests.x86.param_records.match_pattern_owner",
            &[INVALID; 4],
        );
        let match_result_owner = storage_buffer(
            device,
            "tests.x86.param_records.match_result_owner",
            &[INVALID; 4],
        );
        let struct_access = storage_buffer(
            device,
            "tests.x86.param_records.struct_access",
            &[INVALID; 36],
        );
        let struct_store = storage_buffer(
            device,
            "tests.x86.param_records.struct_store",
            &[INVALID; 16],
        );
        let count_info =
            storage_buffer(device, "tests.x86.param_records.count_info", &[INVALID; 4]);
        let count_payload = storage_buffer(
            device,
            "tests.x86.param_records.count_payload",
            &[INVALID; 4],
        );
        let count_status = storage_buffer(
            device,
            "tests.x86.param_records.count_status",
            &[1, 0, INVALID, 0],
        );
        let count_info_readback =
            readback_buffer(device, "tests.x86.param_records.count_info.readback", 4);
        let count_payload_readback =
            readback_buffer(device, "tests.x86.param_records.count_payload.readback", 4);

        let counts_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.param_records.counts.bind_group"),
            &counts_pass.bind_group_layouts[0],
            &counts_pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                ("hir_status", hir_status.as_entire_binding()),
                ("hir_kind", hir_kind.as_entire_binding()),
                ("hir_stmt_record", hir_stmt_record.as_entire_binding()),
                ("hir_expr_record", hir_expr_record.as_entire_binding()),
                ("hir_param_record", hir_param_record.as_entire_binding()),
                ("x86_expr_resolved_node", expr_resolved.as_entire_binding()),
                ("x86_node_func", node_func.as_entire_binding()),
                ("visible_decl", visible_decl.as_entire_binding()),
                ("x86_decl_layout_record", decl_layout.as_entire_binding()),
                (
                    "x86_decl_layout_status",
                    decl_layout_status.as_entire_binding(),
                ),
                ("x86_param_reg_record", param_reg.as_entire_binding()),
                ("x86_tree_parent", tree_parent.as_entire_binding()),
                ("x86_tree_subtree_end", tree_subtree_end.as_entire_binding()),
                ("x86_node_tree_status", node_tree_status.as_entire_binding()),
                (
                    "x86_enclosing_return_node",
                    enclosing_return.as_entire_binding(),
                ),
                ("x86_match_return_node", match_return.as_entire_binding()),
                ("x86_call_record", call_record.as_entire_binding()),
                (
                    "x86_call_callee_owner_call",
                    call_callee_owner.as_entire_binding(),
                ),
                ("call_record_status", ok_status.as_entire_binding()),
                (
                    "x86_intrinsic_call_record",
                    intrinsic_record.as_entire_binding(),
                ),
                ("x86_intrinsic_call_status", ok_status.as_entire_binding()),
                (
                    "x86_enum_value_record",
                    enum_value_record.as_entire_binding(),
                ),
                ("x86_enum_record_status", ok_status.as_entire_binding()),
                ("gX86Features", feature_record.as_entire_binding()),
                ("x86_match_record", match_record.as_entire_binding()),
                (
                    "x86_match_pattern_node_owner",
                    match_pattern_owner.as_entire_binding(),
                ),
                (
                    "x86_match_result_value_owner",
                    match_result_owner.as_entire_binding(),
                ),
                (
                    "x86_struct_access_record",
                    struct_access.as_entire_binding(),
                ),
                ("x86_struct_store_record", struct_store.as_entire_binding()),
                ("x86_struct_record_status", ok_status.as_entire_binding()),
                ("x86_node_inst_count_info", count_info.as_entire_binding()),
                (
                    "x86_node_inst_count_payload",
                    count_payload.as_entire_binding(),
                ),
                (
                    "x86_node_inst_count_status",
                    count_status.as_entire_binding(),
                ),
            ]),
        )
        .expect("create node-inst-counts bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.param_records.counts.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.param_records.counts.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&counts_pass.pipeline);
            compute.set_bind_group(0, &counts_bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&count_info, 0, &count_info_readback, 0, 4 * 4);
        encoder.copy_buffer_to_buffer(&count_payload, 0, &count_payload_readback, 0, 4 * 4);
        queue.submit(Some(encoder.finish()));

        let counts = read_u32s(device, &count_info_readback, 4);
        let payload = read_u32s(device, &count_payload_readback, 4);
        assert_eq!(
            counts[1] & 0x0fff_ffff,
            2,
            "scalar param count must come from HIR param records plus param-reg records"
        );
        assert_eq!(
            counts[1] >> X86_NODE_INST_RANGE_KIND_SHIFT,
            X86_NODE_INST_EXPR_VALUE,
            "scalar params should produce expression-value instruction rows"
        );
        assert_eq!(
            payload[1], 0,
            "compact count payload should come from the two-word x86 tree parent"
        );

        let range_start = storage_buffer(
            device,
            "tests.x86.param_records.range_start",
            &[INVALID, 2, INVALID, INVALID],
        );
        let range_info = storage_buffer(
            device,
            "tests.x86.param_records.range_info",
            &[
                INVALID,
                (X86_NODE_INST_EXPR_VALUE << X86_NODE_INST_RANGE_KIND_SHIFT) | 2,
                INVALID,
                INVALID,
            ],
        );
        let range_status = storage_buffer(
            device,
            "tests.x86.param_records.range_status",
            &[1, 0, INVALID, 4],
        );
        let same_end_rank =
            storage_buffer(device, "tests.x86.param_records.same_end_rank", &[0; 4]);
        let same_end_bucket_count = storage_buffer(
            device,
            "tests.x86.param_records.same_end_bucket_count",
            &[0; 4],
        );
        let expr_semantic_type = storage_buffer(
            device,
            "tests.x86.param_records.expr_semantic_type",
            &[0; 4],
        );
        let location_record = storage_buffer(
            device,
            "tests.x86.param_records.location_record",
            &[INVALID; 16],
        );
        let location_status = storage_buffer(
            device,
            "tests.x86.param_records.location_status",
            &[0, 0, INVALID, 0],
        );
        let gen_flag = storage_buffer(device, "tests.x86.param_records.gen_flag", &[0; 5]);
        let location_readback =
            readback_buffer(device, "tests.x86.param_records.location.readback", 16);
        let gen_flag_readback =
            readback_buffer(device, "tests.x86.param_records.gen_flag.readback", 5);

        let locations_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.param_records.locations.bind_group"),
            &locations_pass.bind_group_layouts[0],
            &locations_pass.reflection,
            0,
            &binding_map(&[
                ("gParams", location_params.as_entire_binding()),
                ("hir_status", hir_status.as_entire_binding()),
                ("hir_kind", hir_kind.as_entire_binding()),
                ("hir_param_record", hir_param_record.as_entire_binding()),
                ("hir_stmt_record", hir_stmt_record.as_entire_binding()),
                ("hir_expr_record", hir_expr_record.as_entire_binding()),
                ("x86_expr_resolved_node", expr_resolved.as_entire_binding()),
                (
                    "x86_expr_semantic_type",
                    expr_semantic_type.as_entire_binding(),
                ),
                ("gX86Features", feature_record.as_entire_binding()),
                ("x86_match_record", match_record.as_entire_binding()),
                ("x86_tree_parent", tree_parent.as_entire_binding()),
                ("x86_tree_subtree_end", tree_subtree_end.as_entire_binding()),
                ("x86_node_inst_range_start", range_start.as_entire_binding()),
                ("x86_node_inst_range_info", range_info.as_entire_binding()),
                (
                    "x86_node_inst_same_end_rank",
                    same_end_rank.as_entire_binding(),
                ),
                (
                    "x86_node_inst_same_end_bucket_count",
                    same_end_bucket_count.as_entire_binding(),
                ),
                (
                    "x86_node_inst_range_status",
                    range_status.as_entire_binding(),
                ),
                (
                    "x86_node_inst_location_record",
                    location_record.as_entire_binding(),
                ),
                (
                    "x86_node_inst_location_status",
                    location_status.as_entire_binding(),
                ),
                ("x86_node_inst_gen_flag", gen_flag.as_entire_binding()),
            ]),
        )
        .expect("create node-inst-locations bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.param_records.locations.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.param_records.locations.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&locations_pass.pipeline);
            compute.set_bind_group(0, &locations_bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&location_record, 0, &location_readback, 0, 16 * 4);
        encoder.copy_buffer_to_buffer(&gen_flag, 0, &gen_flag_readback, 0, 5 * 4);
        queue.submit(Some(encoder.finish()));

        let locations = read_u32s(device, &location_readback, 16);
        assert_eq!(
            &locations[4..8],
            &[2, 3, INVALID, X86_LOCATION_META_PARAM_DECL | 7]
        );
        assert_eq!(
            read_u32s(device, &gen_flag_readback, 5)[1],
            1,
            "param metadata must not suppress generation for the param node"
        );
    });
}

#[test]
fn x86_func_slot_scan_scatters_hir_order_slots_without_atomics() {
    common::block_on_gpu_with_timeout("x86 function-slot scan scatter", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let flags_artifacts = compile_shader(&root, "x86_func_slot_flags");
        let scan_local_artifacts = compile_shader(&root, "x86_node_inst_scan_local");
        let scan_blocks_artifacts = compile_shader(&root, "x86_node_inst_scan_blocks");
        let scatter_artifacts = compile_shader(&root, "x86_func_slot_scatter");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let flags_pass = make_pass_data(
            device,
            "tests.x86.func_slot_flags",
            "main",
            leak_bytes(flags_artifacts.0),
            leak_bytes(flags_artifacts.1),
        )
        .expect("create func_slot_flags pass");
        let scan_local_pass = make_pass_data(
            device,
            "tests.x86.func_slot_scan_local",
            "main",
            leak_bytes(scan_local_artifacts.0),
            leak_bytes(scan_local_artifacts.1),
        )
        .expect("create func slot scan-local pass");
        let scan_blocks_pass = make_pass_data(
            device,
            "tests.x86.func_slot_scan_blocks",
            "main",
            leak_bytes(scan_blocks_artifacts.0),
            leak_bytes(scan_blocks_artifacts.1),
        )
        .expect("create func slot scan-blocks pass");
        let scatter_pass = make_pass_data(
            device,
            "tests.x86.func_slot_scatter",
            "main",
            leak_bytes(scatter_artifacts.0),
            leak_bytes(scatter_artifacts.1),
        )
        .expect("create func_slot_scatter pass");

        let params = input_uniform(
            device,
            "tests.x86.func_slot_scan.params",
            &[12, 0, 0, 6, 0, 0, ROWS_PER_CHUNK, 1, 2],
        );
        let scan_params = scan_uniform_array(
            device,
            "tests.x86.func_slot_scan.scan_params",
            &[[7, 1, 0, 0]],
        );
        let hir_status = storage_buffer(
            device,
            "tests.x86.func_slot_scan.hir_status",
            &[0, 0, INVALID, 0, 0, 6],
        );
        let hir_kind = storage_buffer(
            device,
            "tests.x86.func_slot_scan.hir_kind",
            &[HIR_FN, 0, HIR_FN, HIR_FN, 0, 0],
        );
        let flags = storage_buffer(device, "tests.x86.func_slot_scan.flags", &[99; 7]);
        let local_prefix =
            storage_buffer(device, "tests.x86.func_slot_scan.local_prefix", &[99; 7]);
        let block_sum = storage_buffer(device, "tests.x86.func_slot_scan.block_sum", &[0]);
        let block_prefix_a = storage_buffer(device, "tests.x86.func_slot_scan.prefix_a", &[0]);
        let block_prefix_b = storage_buffer(device, "tests.x86.func_slot_scan.prefix_b", &[0]);
        let func_slot_by_node = storage_buffer(
            device,
            "tests.x86.func_slot_scan.slot_by_node",
            &[0, INVALID, 4, 8, INVALID, INVALID, INVALID],
        );
        let func_meta = storage_buffer(
            device,
            "tests.x86.func_slot_scan.func_meta",
            &[0, 0, INVALID, 0, INVALID, 0, 0, 0],
        );
        let func_slot_by_index = storage_buffer(
            device,
            "tests.x86.func_slot_scan.slot_by_index",
            &[INVALID; 2],
        );
        let flags_readback = readback_buffer(device, "tests.x86.func_slot_scan.flags.readback", 7);
        let meta_readback = readback_buffer(device, "tests.x86.func_slot_scan.meta.readback", 8);
        let slot_readback = readback_buffer(device, "tests.x86.func_slot_scan.slots.readback", 2);

        let flags_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.func_slot_flags.bind_group"),
            &flags_pass.bind_group_layouts[0],
            &flags_pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                ("hir_status", hir_status.as_entire_binding()),
                ("hir_kind", hir_kind.as_entire_binding()),
                ("x86_func_slot_flags", flags.as_entire_binding()),
            ]),
        )
        .expect("create func slot flags bind group");
        let scan_local_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.func_slot_scan_local.bind_group"),
            &scan_local_pass.bind_group_layouts[0],
            &scan_local_pass.reflection,
            0,
            &binding_map(&[
                ("gScan", dynamic_uniform_binding(&scan_params, 0)),
                ("x86_node_inst_scan_input", flags.as_entire_binding()),
                (
                    "x86_node_inst_scan_local_prefix",
                    local_prefix.as_entire_binding(),
                ),
                (
                    "x86_node_inst_scan_block_sum",
                    block_sum.as_entire_binding(),
                ),
            ]),
        )
        .expect("create func slot scan-local bind group");
        let scan_blocks_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.func_slot_scan_blocks.bind_group"),
            &scan_blocks_pass.bind_group_layouts[0],
            &scan_blocks_pass.reflection,
            0,
            &binding_map(&[
                (
                    "gNodeInstBlockScan",
                    dynamic_uniform_binding(&scan_params, 0),
                ),
                (
                    "x86_node_inst_scan_block_sum",
                    block_sum.as_entire_binding(),
                ),
                (
                    "x86_node_inst_scan_block_prefix_in",
                    block_prefix_b.as_entire_binding(),
                ),
                (
                    "x86_node_inst_scan_block_prefix_out",
                    block_prefix_a.as_entire_binding(),
                ),
            ]),
        )
        .expect("create func slot scan-blocks bind group");
        let scatter_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.func_slot_scatter.bind_group"),
            &scatter_pass.bind_group_layouts[0],
            &scatter_pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                ("hir_status", hir_status.as_entire_binding()),
                ("x86_func_slot_flags", flags.as_entire_binding()),
                (
                    "x86_func_slot_by_node",
                    func_slot_by_node.as_entire_binding(),
                ),
                (
                    "x86_func_slot_scan_local_prefix",
                    local_prefix.as_entire_binding(),
                ),
                (
                    "x86_func_slot_scan_block_prefix",
                    block_prefix_a.as_entire_binding(),
                ),
                ("x86_func_meta", func_meta.as_entire_binding()),
                (
                    "x86_func_slot_by_index",
                    func_slot_by_index.as_entire_binding(),
                ),
            ]),
        )
        .expect("create func slot scatter bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.func_slot_scan.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.func_slot_scan.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&flags_pass.pipeline);
            compute.set_bind_group(0, &flags_bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
            compute.set_pipeline(&scan_local_pass.pipeline);
            compute.set_bind_group(0, &scan_local_bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
            compute.set_pipeline(&scan_blocks_pass.pipeline);
            compute.set_bind_group(0, &scan_blocks_bind_group, &[dynamic_uniform_offset(0)]);
            compute.dispatch_workgroups(1, 1, 1);
            compute.set_pipeline(&scatter_pass.pipeline);
            compute.set_bind_group(0, &scatter_bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&flags, 0, &flags_readback, 0, 7 * 4);
        encoder.copy_buffer_to_buffer(&func_meta, 0, &meta_readback, 0, 8 * 4);
        encoder.copy_buffer_to_buffer(&func_slot_by_index, 0, &slot_readback, 0, 2 * 4);
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &flags_readback, 7),
            vec![1, 0, 1, 1, 0, 0, 0],
            "function flags should mirror HIR_FN records plus a zero sentinel"
        );
        let meta = read_u32s(device, &meta_readback, 8);
        assert_eq!(
            meta[0], 3,
            "function count should be the scan total, independent of slot capacity"
        );
        assert_eq!(
            read_u32s(device, &slot_readback, 2),
            vec![0, 1],
            "capped function slots should use compact HIR-order ordinals"
        );
    });
}

#[test]
fn x86_virtual_spans_fixed_barrier_consumes_liveness_and_next_barrier_records() {
    common::block_on_gpu_with_timeout("x86 virtual spans fixed barrier records", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let artifacts = compile_shader(&root, "x86_virtual_spans_fixed_barrier");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.x86.virtual_spans_fixed_barrier",
            "main",
            leak_bytes(artifacts.0),
            leak_bytes(artifacts.1),
        )
        .expect("create virtual_spans_fixed_barrier pass");

        let params = input_uniform(device, "tests.x86.spans_barrier.params", &[0, 0, 0, 4, 8]);
        let virtual_inst_record = storage_buffer(
            device,
            "tests.x86.spans_barrier.virtual_inst_record",
            &[
                0,
                0,
                X86_VINST_BINARY,
                0,
                0,
                0,
                X86_VINST_BINARY,
                1,
                0,
                0,
                X86_VINST_CALL_MIXED,
                2,
                INVALID,
                0,
                0,
                INVALID,
            ],
        );
        let virtual_inst_status = storage_buffer(
            device,
            "tests.x86.spans_barrier.virtual_inst_status",
            &[1, 0, INVALID, 4],
        );
        let live_start = storage_buffer(
            device,
            "tests.x86.spans_barrier.live_start",
            &[0, 1, 2, INVALID],
        );
        let live_end = storage_buffer(
            device,
            "tests.x86.spans_barrier.live_end",
            &[3, 2, 2, INVALID],
        );
        let liveness_status = storage_buffer(
            device,
            "tests.x86.spans_barrier.liveness_status",
            &[1, 0, INVALID, 4],
        );
        let next_call_a = storage_buffer(
            device,
            "tests.x86.spans_barrier.next_call_a",
            &[2, 2, 2, INVALID],
        );
        let next_call_b =
            storage_buffer(device, "tests.x86.spans_barrier.next_call_b", &[INVALID; 4]);
        let next_call_status = storage_buffer(
            device,
            "tests.x86.spans_barrier.next_call_status",
            &[1, 0, INVALID, 4],
        );
        let spans = storage_buffer(device, "tests.x86.spans_barrier.out", &[99; 4]);
        let readback = readback_buffer(device, "tests.x86.spans_barrier.readback", 4);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.virtual_spans_fixed_barrier.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_status",
                    virtual_inst_status.as_entire_binding(),
                ),
                ("x86_virtual_live_start", live_start.as_entire_binding()),
                ("x86_virtual_live_end", live_end.as_entire_binding()),
                (
                    "x86_virtual_liveness_status",
                    liveness_status.as_entire_binding(),
                ),
                ("x86_virtual_next_call_a", next_call_a.as_entire_binding()),
                ("x86_virtual_next_call_b", next_call_b.as_entire_binding()),
                (
                    "x86_virtual_next_call_status",
                    next_call_status.as_entire_binding(),
                ),
                ("x86_virtual_spans_fixed_barrier", spans.as_entire_binding()),
            ]),
        )
        .expect("create virtual_spans_fixed_barrier bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.virtual_spans_fixed_barrier.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.virtual_spans_fixed_barrier.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&spans, 0, &readback, 0, 4 * 4);
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &readback, 4),
            vec![1, 0, 0, 0],
            "fixed-barrier span records should be derived from virtual liveness and next-barrier rows"
        );
    });
}

#[test]
fn x86_virtual_value_def_flags_writes_full_scanned_domain() {
    common::block_on_gpu_with_timeout("x86 virtual value-def flags scanned domain", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let artifacts = compile_shader(&root, "x86_virtual_value_def_flags");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.x86.virtual_value_def_flags",
            "main",
            leak_bytes(artifacts.0),
            leak_bytes(artifacts.1),
        )
        .expect("create virtual_value_def_flags pass");

        let params = input_uniform(device, "tests.x86.value_def_flags.params", &[0, 0, 0, 4, 6]);
        let virtual_inst_record = storage_buffer(
            device,
            "tests.x86.value_def_flags.virtual_inst_record",
            &[
                0,
                0,
                X86_VINST_IMM_I32,
                0,
                INVALID,
                0,
                0,
                INVALID,
                0,
                0,
                X86_VINST_BINARY,
                2,
                0,
                0,
                0,
                3,
                INVALID,
                0,
                0,
                INVALID,
                INVALID,
                0,
                0,
                INVALID,
            ],
        );
        let virtual_inst_status = storage_buffer(
            device,
            "tests.x86.value_def_flags.virtual_inst_status",
            &[1, 0, INVALID, 4],
        );
        let flags = storage_buffer(device, "tests.x86.value_def_flags.out", &[99; 6]);
        let readback = readback_buffer(device, "tests.x86.value_def_flags.readback", 6);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.virtual_value_def_flags.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_status",
                    virtual_inst_status.as_entire_binding(),
                ),
                ("x86_virtual_value_def_flag", flags.as_entire_binding()),
            ]),
        )
        .expect("create virtual_value_def_flags bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.virtual_value_def_flags.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.virtual_value_def_flags.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&flags, 0, &readback, 0, 6 * 4);
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &readback, 6),
            vec![1, 0, 1, 0, 0, 0],
            "value-def flag pass should write both virtual rows and selected tail rows so scan input does not require a capacity clear"
        );
    });
}

#[test]
fn x86_regalloc_records_call_live_save_mask_from_virtual_liveness() {
    common::block_on_gpu_with_timeout("x86 regalloc call-live save mask", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let regalloc_artifacts = compile_shader(&root, "x86_virtual_regalloc");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.x86.virtual_regalloc",
            "main",
            leak_bytes(regalloc_artifacts.0),
            leak_bytes(regalloc_artifacts.1),
        )
        .expect("create virtual_regalloc pass");

        let params = input_uniform(
            device,
            "tests.x86.regalloc.params",
            &[TOKEN_WORDS as u32, 0, 0, 4, 4, 0, 8, 1, 1],
        );
        let regalloc_params = scan_uniform_array(
            device,
            "tests.x86.regalloc.dynamic_params",
            &[[0, 1, 1, 0], [1, 1, 0, 0], [2, 1, 0, 0]],
        );
        let func_meta = storage_buffer(
            device,
            "tests.x86.regalloc.func_meta",
            &[1, 0, INVALID, 0, INVALID, 3, 0, 0],
        );
        let func_slot_by_index =
            storage_buffer(device, "tests.x86.regalloc.func_slot_by_index", &[0]);
        let virtual_inst_record = storage_buffer(
            device,
            "tests.x86.regalloc.virtual_inst_record",
            &[
                0,
                0,
                X86_VINST_BINARY,
                0,
                0,
                0,
                X86_VINST_CALL_MIXED,
                1,
                0,
                0,
                X86_VINST_BINARY,
                2,
                INVALID,
                0,
                0,
                INVALID,
            ],
        );
        let virtual_inst_args =
            storage_buffer(device, "tests.x86.regalloc.virtual_inst_args", &[0; 16]);
        let live_start =
            storage_buffer(device, "tests.x86.regalloc.live_start", &[0, 1, 2, INVALID]);
        let live_end = storage_buffer(device, "tests.x86.regalloc.live_end", &[2, 1, 2, INVALID]);
        let liveness_status = storage_buffer(
            device,
            "tests.x86.regalloc.liveness_status",
            &[1, 0, INVALID, 3],
        );
        let next_call_status = storage_buffer(
            device,
            "tests.x86.regalloc.next_call_status",
            &[1, 0, INVALID, 3],
        );
        let param_mask = storage_buffer(device, "tests.x86.regalloc.param_mask", &[0; 4]);
        let param_mask_status = storage_buffer(
            device,
            "tests.x86.regalloc.param_mask_status",
            &[1, 0, INVALID, 3],
        );
        let first_row = storage_buffer(
            device,
            "tests.x86.regalloc.first_row",
            &[
                0, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
        );
        let last_row = storage_buffer(
            device,
            "tests.x86.regalloc.last_row",
            &[2, 0, 0, 0, 0, 0, 0, 0],
        );
        let first_row_status = storage_buffer(
            device,
            "tests.x86.regalloc.first_row_status",
            &[1, 0, INVALID, 3],
        );
        let value_defs = regalloc_value_defs(
            device,
            "tests.x86.regalloc",
            &[0, 1, 2, INVALID],
            3,
            &[0, 0, 0, INVALID],
        );
        let active_end = storage_buffer(device, "tests.x86.regalloc.active_end", &[INVALID; 14]);
        let param_rank_mask = storage_buffer(device, "tests.x86.regalloc.param_rank_mask", &[0; 1]);
        let phys_reg = storage_buffer(device, "tests.x86.regalloc.phys_reg", &[INVALID; 4]);
        let call_live_mask =
            storage_buffer(device, "tests.x86.regalloc.call_live_mask", &[1, 0, 0, 0]);
        let regalloc_status =
            storage_buffer(device, "tests.x86.regalloc.status", &[0, 0, INVALID, 0]);
        let mask_readback =
            readback_buffer(device, "tests.x86.regalloc.call_live_mask.readback", 4);
        let status_readback = readback_buffer(device, "tests.x86.regalloc.status.readback", 4);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.virtual_regalloc.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                ("gRegalloc", dynamic_uniform_binding(&regalloc_params, 0)),
                ("x86_func_meta", func_meta.as_entire_binding()),
                (
                    "x86_func_slot_by_index",
                    func_slot_by_index.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_args",
                    virtual_inst_args.as_entire_binding(),
                ),
                ("x86_virtual_live_start", live_start.as_entire_binding()),
                ("x86_virtual_live_end", live_end.as_entire_binding()),
                (
                    "x86_virtual_liveness_status",
                    liveness_status.as_entire_binding(),
                ),
                (
                    "x86_virtual_next_call_status",
                    next_call_status.as_entire_binding(),
                ),
                ("x86_func_param_reg_mask", param_mask.as_entire_binding()),
                (
                    "x86_func_param_reg_mask_status",
                    param_mask_status.as_entire_binding(),
                ),
                ("x86_func_first_virtual_row", first_row.as_entire_binding()),
                ("x86_func_last_virtual_row", last_row.as_entire_binding()),
                (
                    "x86_func_first_virtual_row_status",
                    first_row_status.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_row",
                    value_defs.row.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_scan_local_prefix",
                    value_defs.scan_local_prefix.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_scan_block_prefix",
                    value_defs.scan_block_prefix.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_status",
                    value_defs.status.as_entire_binding(),
                ),
                (
                    "x86_virtual_func_slot",
                    value_defs.func_slot.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_active_end",
                    active_end.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_param_rank_mask",
                    param_rank_mask.as_entire_binding(),
                ),
                ("x86_virtual_phys_reg", phys_reg.as_entire_binding()),
                (
                    "x86_virtual_call_live_reg_mask",
                    call_live_mask.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_status",
                    regalloc_status.as_entire_binding(),
                ),
            ]),
        )
        .expect("create regalloc bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.regalloc_call_live_mask.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.regalloc_call_live_mask.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            for step in 0..3 {
                compute.set_bind_group(0, &bind_group, &[dynamic_uniform_offset(step)]);
                compute.dispatch_workgroups(1, 1, 1);
            }
        }
        encoder.copy_buffer_to_buffer(&call_live_mask, 0, &mask_readback, 0, 4 * 4);
        encoder.copy_buffer_to_buffer(&regalloc_status, 0, &status_readback, 0, 4 * 4);
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &status_readback, 4),
            vec![1, 0, INVALID, 3]
        );
        assert_eq!(
            read_u32s(device, &mask_readback, 4)[1],
            1u32 << 6,
            "value live across call should require saving the allocated R10 caller register"
        );
    });
}

#[test]
fn x86_regalloc_allocates_value_defs_across_function_row_span() {
    common::block_on_gpu_with_timeout("x86 regalloc compact value-def rows", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let regalloc_artifacts = compile_shader(&root, "x86_virtual_regalloc");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.x86.virtual_regalloc.value_def_rows",
            "main",
            leak_bytes(regalloc_artifacts.0),
            leak_bytes(regalloc_artifacts.1),
        )
        .expect("create virtual_regalloc pass");

        let params = input_uniform(
            device,
            "tests.x86.regalloc_value_def_rows.params",
            &[TOKEN_WORDS as u32, 0, 0, 1, 4, 0, 8, 1, 1],
        );
        let regalloc_params = scan_uniform_array(
            device,
            "tests.x86.regalloc_value_def_rows.dynamic_params",
            &[[0, 1, 1, 0], [1, 1, 0, 0], [2, 1, 0, 0]],
        );
        let func_meta = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.func_meta",
            &[1, 0, INVALID, 0, INVALID, 3, 0, 0],
        );
        let func_slot_by_index = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.func_slot_by_index",
            &[0],
        );
        let virtual_inst_record = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.virtual_inst_record",
            &[
                0,
                0,
                X86_VINST_IMM_I32,
                0,
                0,
                0,
                X86_VINST_IMM_I32,
                1,
                0,
                0,
                X86_VINST_BINARY,
                2,
                INVALID,
                0,
                0,
                INVALID,
            ],
        );
        let virtual_inst_args = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.virtual_inst_args",
            &[5, 0, 0, 0, 8, 0, 0, 0, 1, 0, 1, 0, 0, 0, 0, 0],
        );
        let live_start = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.live_start",
            &[0, 1, 2, INVALID],
        );
        let live_end = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.live_end",
            &[2, 2, 2, INVALID],
        );
        let liveness_status = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.liveness_status",
            &[1, 0, INVALID, 3],
        );
        let next_call_status = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.next_call_status",
            &[1, 0, INVALID, 3],
        );
        let param_mask = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.param_mask",
            &[0; 4],
        );
        let param_mask_status = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.param_mask_status",
            &[1, 0, INVALID, 3],
        );
        let first_row = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.first_row",
            &[
                0, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
        );
        let last_row = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.last_row",
            &[2, 0, 0, 0, 0, 0, 0, 0],
        );
        let first_row_status = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.first_row_status",
            &[1, 0, INVALID, 3],
        );
        let value_defs = regalloc_value_defs(
            device,
            "tests.x86.regalloc_value_def_rows",
            &[0, 1, 2, INVALID],
            3,
            &[0, 0, 0, INVALID],
        );
        let active_end = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.active_end",
            &[INVALID; 14],
        );
        let param_rank_mask = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.param_rank_mask",
            &[0; 1],
        );
        let phys_reg = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.phys_reg",
            &[INVALID; 4],
        );
        let call_live_mask = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.call_live_mask",
            &[0; 4],
        );
        let regalloc_status = storage_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.status",
            &[0, 0, INVALID, 0],
        );
        let phys_readback =
            readback_buffer(device, "tests.x86.regalloc_value_def_rows.phys.readback", 4);
        let status_readback = readback_buffer(
            device,
            "tests.x86.regalloc_value_def_rows.status.readback",
            4,
        );

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.virtual_regalloc.value_def_rows.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                ("gRegalloc", dynamic_uniform_binding(&regalloc_params, 0)),
                ("x86_func_meta", func_meta.as_entire_binding()),
                (
                    "x86_func_slot_by_index",
                    func_slot_by_index.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_args",
                    virtual_inst_args.as_entire_binding(),
                ),
                ("x86_virtual_live_start", live_start.as_entire_binding()),
                ("x86_virtual_live_end", live_end.as_entire_binding()),
                (
                    "x86_virtual_liveness_status",
                    liveness_status.as_entire_binding(),
                ),
                (
                    "x86_virtual_next_call_status",
                    next_call_status.as_entire_binding(),
                ),
                ("x86_func_param_reg_mask", param_mask.as_entire_binding()),
                (
                    "x86_func_param_reg_mask_status",
                    param_mask_status.as_entire_binding(),
                ),
                ("x86_func_first_virtual_row", first_row.as_entire_binding()),
                ("x86_func_last_virtual_row", last_row.as_entire_binding()),
                (
                    "x86_func_first_virtual_row_status",
                    first_row_status.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_row",
                    value_defs.row.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_scan_local_prefix",
                    value_defs.scan_local_prefix.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_scan_block_prefix",
                    value_defs.scan_block_prefix.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_status",
                    value_defs.status.as_entire_binding(),
                ),
                (
                    "x86_virtual_func_slot",
                    value_defs.func_slot.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_active_end",
                    active_end.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_param_rank_mask",
                    param_rank_mask.as_entire_binding(),
                ),
                ("x86_virtual_phys_reg", phys_reg.as_entire_binding()),
                (
                    "x86_virtual_call_live_reg_mask",
                    call_live_mask.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_status",
                    regalloc_status.as_entire_binding(),
                ),
            ]),
        )
        .expect("create row-span regalloc bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.regalloc_value_def_rows.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.regalloc_value_def_rows.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            for step in 0..3 {
                compute.set_bind_group(0, &bind_group, &[dynamic_uniform_offset(step)]);
                compute.dispatch_workgroups(1, 1, 1);
            }
        }
        encoder.copy_buffer_to_buffer(&phys_reg, 0, &phys_readback, 0, 4 * 4);
        encoder.copy_buffer_to_buffer(&regalloc_status, 0, &status_readback, 0, 4 * 4);
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &status_readback, 4),
            vec![1, 0, INVALID, 3]
        );
        assert_eq!(
            &read_u32s(device, &phys_readback, 4)[..3],
            &[X86_REG_EAX, X86_REG_R10D, X86_REG_R8D],
            "regalloc should allocate every value-def row in the HIR-derived function span"
        );
    });
}

#[test]
fn x86_regalloc_consumes_function_param_register_masks() {
    common::block_on_gpu_with_timeout("x86 regalloc param register masks", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let regalloc_artifacts = compile_shader(&root, "x86_virtual_regalloc");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.x86.virtual_regalloc.param_mask",
            "main",
            leak_bytes(regalloc_artifacts.0),
            leak_bytes(regalloc_artifacts.1),
        )
        .expect("create virtual_regalloc pass");

        let params = input_uniform(
            device,
            "tests.x86.regalloc_param_mask.params",
            &[TOKEN_WORDS as u32, 0, 0, 4, 4, 0, 8, 1, 1],
        );
        let regalloc_params = scan_uniform_array(
            device,
            "tests.x86.regalloc_param_mask.dynamic_params",
            &[[0, 8, 1, 0]],
        );
        let func_meta = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.func_meta",
            &[1, 0, INVALID, 0, INVALID, 0, 0, 0],
        );
        let func_slot_by_index = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.func_slot_by_index",
            &[0],
        );
        let virtual_inst_record = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.virtual_inst_record",
            &[0, 0, X86_VINST_PARAM, 0],
        );
        let virtual_inst_args = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.virtual_inst_args",
            &[0, 0, X86_REG_EAX, 0],
        );
        let live_start = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.live_start",
            &[0, INVALID, INVALID, INVALID],
        );
        let live_end = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.live_end",
            &[0, INVALID, INVALID, INVALID],
        );
        let liveness_status = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.liveness_status",
            &[1, 0, INVALID, 1],
        );
        let next_call_status = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.next_call_status",
            &[1, 0, INVALID, 1],
        );
        let param_mask = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.param_mask",
            &[1u32 << X86_REG_EAX, 0, 0, 0],
        );
        let param_mask_status = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.param_mask_status",
            &[1, 0, INVALID, 1],
        );
        let first_row = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.first_row",
            &[
                0, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
        );
        let last_row = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.last_row",
            &[0, 0, 0, 0, 0, 0, 0, 0],
        );
        let first_row_status = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.first_row_status",
            &[1, 0, INVALID, 1],
        );
        let value_defs = regalloc_value_defs(
            device,
            "tests.x86.regalloc_param_mask",
            &[0, INVALID, INVALID, INVALID],
            1,
            &[0, INVALID, INVALID, INVALID],
        );
        let active_end = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.active_end",
            &[INVALID; 14],
        );
        let param_rank_mask = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.param_rank_mask",
            &[0; 1],
        );
        let phys_reg = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.phys_reg",
            &[INVALID; 4],
        );
        let call_live_mask = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.call_live_mask",
            &[0; 4],
        );
        let regalloc_status = storage_buffer(
            device,
            "tests.x86.regalloc_param_mask.status",
            &[0, 0, INVALID, 0],
        );
        let phys_readback =
            readback_buffer(device, "tests.x86.regalloc_param_mask.phys.readback", 4);
        let status_readback =
            readback_buffer(device, "tests.x86.regalloc_param_mask.status.readback", 4);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.virtual_regalloc.param_mask.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                ("gRegalloc", dynamic_uniform_binding(&regalloc_params, 0)),
                ("x86_func_meta", func_meta.as_entire_binding()),
                (
                    "x86_func_slot_by_index",
                    func_slot_by_index.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_args",
                    virtual_inst_args.as_entire_binding(),
                ),
                ("x86_virtual_live_start", live_start.as_entire_binding()),
                ("x86_virtual_live_end", live_end.as_entire_binding()),
                (
                    "x86_virtual_liveness_status",
                    liveness_status.as_entire_binding(),
                ),
                (
                    "x86_virtual_next_call_status",
                    next_call_status.as_entire_binding(),
                ),
                ("x86_func_param_reg_mask", param_mask.as_entire_binding()),
                (
                    "x86_func_param_reg_mask_status",
                    param_mask_status.as_entire_binding(),
                ),
                ("x86_func_first_virtual_row", first_row.as_entire_binding()),
                ("x86_func_last_virtual_row", last_row.as_entire_binding()),
                (
                    "x86_func_first_virtual_row_status",
                    first_row_status.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_row",
                    value_defs.row.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_scan_local_prefix",
                    value_defs.scan_local_prefix.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_scan_block_prefix",
                    value_defs.scan_block_prefix.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_status",
                    value_defs.status.as_entire_binding(),
                ),
                (
                    "x86_virtual_func_slot",
                    value_defs.func_slot.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_active_end",
                    active_end.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_param_rank_mask",
                    param_rank_mask.as_entire_binding(),
                ),
                ("x86_virtual_phys_reg", phys_reg.as_entire_binding()),
                (
                    "x86_virtual_call_live_reg_mask",
                    call_live_mask.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_status",
                    regalloc_status.as_entire_binding(),
                ),
            ]),
        )
        .expect("create regalloc param-mask bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.regalloc_param_mask.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.regalloc_param_mask.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[dynamic_uniform_offset(0)]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&phys_reg, 0, &phys_readback, 0, 4 * 4);
        encoder.copy_buffer_to_buffer(&regalloc_status, 0, &status_readback, 0, 4 * 4);
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &status_readback, 4),
            vec![1, 0, INVALID, 1]
        );
        assert_eq!(
            read_u32s(device, &phys_readback, 4)[0],
            X86_REG_R10D,
            "incoming EAX must stay unavailable until its PARAM row has copied the ABI value"
        );
    });
}

#[test]
fn x86_regalloc_keeps_continuation_records_dead_on_final_chunk() {
    common::block_on_gpu_with_timeout(
        "x86 regalloc final chunk continuation records",
        async move {
            let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
            let regalloc_artifacts = compile_shader(&root, "x86_virtual_regalloc");

            let gpu = device::global();
            let device = gpu.device.as_ref();
            let queue = gpu.queue.as_ref();
            let pass = make_pass_data(
                device,
                "tests.x86.virtual_regalloc.final_chunk",
                "main",
                leak_bytes(regalloc_artifacts.0),
                leak_bytes(regalloc_artifacts.1),
            )
            .expect("create virtual_regalloc pass");

            let params = input_uniform(
                device,
                "tests.x86.regalloc_final_chunk.params",
                &[TOKEN_WORDS as u32, 0, 0, 4, 4, 0, 8, 1, 1],
            );
            let regalloc_params = scan_uniform_array(
                device,
                "tests.x86.regalloc_final_chunk.dynamic_params",
                &[[2, 1, 1, 0]],
            );
            let func_meta = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.func_meta",
                &[1, 0, INVALID, 0, INVALID, 3, 0, 0],
            );
            let func_slot_by_index = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.func_slot_by_index",
                &[0],
            );
            let virtual_inst_record = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.virtual_inst_record",
                &[
                    0,
                    0,
                    X86_VINST_BINARY,
                    0,
                    0,
                    0,
                    X86_VINST_BINARY,
                    1,
                    0,
                    0,
                    X86_VINST_BINARY,
                    2,
                    INVALID,
                    0,
                    0,
                    INVALID,
                ],
            );
            let virtual_inst_args = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.virtual_inst_args",
                &[0; 16],
            );
            let live_start = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.live_start",
                &[0, 1, 2, INVALID],
            );
            let live_end = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.live_end",
                &[0, 1, 2, INVALID],
            );
            let liveness_status = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.liveness_status",
                &[1, 0, INVALID, 3],
            );
            let next_call_status = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.next_call_status",
                &[1, 0, INVALID, 3],
            );
            let param_mask =
                storage_buffer(device, "tests.x86.regalloc_final_chunk.param_mask", &[0; 4]);
            let param_mask_status = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.param_mask_status",
                &[1, 0, INVALID, 3],
            );
            let first_row = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.first_row",
                &[
                    0, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
                ],
            );
            let last_row = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.last_row",
                &[2, 0, 0, 0, 0, 0, 0, 0],
            );
            let first_row_status = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.first_row_status",
                &[1, 0, INVALID, 3],
            );
            let value_defs = regalloc_value_defs(
                device,
                "tests.x86.regalloc_final_chunk",
                &[0, 1, 2, INVALID],
                3,
                &[0, 0, 0, INVALID],
            );
            let active_end_seed = vec![INVALID; 14];
            let active_end = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.active_end",
                &active_end_seed,
            );
            let param_rank_mask = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.param_rank_mask",
                &[0; 1],
            );
            let phys_reg = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.phys_reg",
                &[INVALID; 4],
            );
            let call_live_mask = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.call_live_mask",
                &[0; 4],
            );
            let regalloc_status = storage_buffer(
                device,
                "tests.x86.regalloc_final_chunk.status",
                &[0, 0, INVALID, 0],
            );
            let active_end_readback = readback_buffer(
                device,
                "tests.x86.regalloc_final_chunk.active_end.readback",
                14,
            );
            let phys_readback =
                readback_buffer(device, "tests.x86.regalloc_final_chunk.phys.readback", 4);
            let status_readback =
                readback_buffer(device, "tests.x86.regalloc_final_chunk.status.readback", 4);

            let bind_group = bind_group::create_bind_group_from_reflection(
                device,
                Some("tests.x86.virtual_regalloc.final_chunk.bind_group"),
                &pass.bind_group_layouts[0],
                &pass.reflection,
                0,
                &binding_map(&[
                    ("gParams", params.as_entire_binding()),
                    ("gRegalloc", dynamic_uniform_binding(&regalloc_params, 0)),
                    ("x86_func_meta", func_meta.as_entire_binding()),
                    (
                        "x86_func_slot_by_index",
                        func_slot_by_index.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_inst_record",
                        virtual_inst_record.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_inst_args",
                        virtual_inst_args.as_entire_binding(),
                    ),
                    ("x86_virtual_live_start", live_start.as_entire_binding()),
                    ("x86_virtual_live_end", live_end.as_entire_binding()),
                    (
                        "x86_virtual_liveness_status",
                        liveness_status.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_next_call_status",
                        next_call_status.as_entire_binding(),
                    ),
                    ("x86_func_param_reg_mask", param_mask.as_entire_binding()),
                    (
                        "x86_func_param_reg_mask_status",
                        param_mask_status.as_entire_binding(),
                    ),
                    ("x86_func_first_virtual_row", first_row.as_entire_binding()),
                    ("x86_func_last_virtual_row", last_row.as_entire_binding()),
                    (
                        "x86_func_first_virtual_row_status",
                        first_row_status.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_value_def_row",
                        value_defs.row.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_value_def_scan_local_prefix",
                        value_defs.scan_local_prefix.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_value_def_scan_block_prefix",
                        value_defs.scan_block_prefix.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_value_def_status",
                        value_defs.status.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_func_slot",
                        value_defs.func_slot.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_regalloc_active_end",
                        active_end.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_regalloc_param_rank_mask",
                        param_rank_mask.as_entire_binding(),
                    ),
                    ("x86_virtual_phys_reg", phys_reg.as_entire_binding()),
                    (
                        "x86_virtual_call_live_reg_mask",
                        call_live_mask.as_entire_binding(),
                    ),
                    (
                        "x86_virtual_regalloc_status",
                        regalloc_status.as_entire_binding(),
                    ),
                ]),
            )
            .expect("create regalloc final-chunk bind group");

            let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("tests.x86.regalloc_final_chunk.encoder"),
            });
            {
                let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("tests.x86.regalloc_final_chunk.pass"),
                    timestamp_writes: None,
                });
                compute.set_pipeline(&pass.pipeline);
                compute.set_bind_group(0, &bind_group, &[dynamic_uniform_offset(0)]);
                compute.dispatch_workgroups(1, 1, 1);
            }
            encoder.copy_buffer_to_buffer(&active_end, 0, &active_end_readback, 0, 14 * 4);
            encoder.copy_buffer_to_buffer(&phys_reg, 0, &phys_readback, 0, 4 * 4);
            encoder.copy_buffer_to_buffer(&regalloc_status, 0, &status_readback, 0, 4 * 4);
            queue.submit(Some(encoder.finish()));

            assert_eq!(
                read_u32s(device, &status_readback, 4),
                vec![1, 0, INVALID, 3]
            );
            assert_eq!(
                &read_u32s(device, &phys_readback, 4)[..3],
                &[INVALID, INVALID, X86_REG_EAX],
                "final row-offset step should allocate from virtual liveness and function row records"
            );
            assert_eq!(
                read_u32s(device, &active_end_readback, 14),
                active_end_seed,
                "final chunk should not materialize continuation state no later chunk can consume"
            );
        },
    );
}

#[test]
fn x86_select_records_only_clobbered_call_argument_save_masks() {
    common::block_on_gpu_with_timeout("x86 select call-argument save mask", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let select_artifacts = compile_shader(&root, "x86_select");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.x86.select",
            "main",
            leak_bytes(select_artifacts.0),
            leak_bytes(select_artifacts.1),
        )
        .expect("create x86_select pass");

        let params = input_uniform(
            device,
            "tests.x86.select.params",
            &[TOKEN_WORDS as u32, 0, 0, 4, 8, 0, ROWS_PER_CHUNK, 1, 1],
        );
        let call_info = 2 | (X86_ARG_SCALAR << 12) | (X86_ARG_SCALAR << 14);
        let virtual_inst_record = storage_buffer(
            device,
            "tests.x86.select.virtual_inst_record",
            &[
                0,
                0,
                X86_VINST_CALL_MIXED,
                0,
                0,
                0,
                X86_VINST_IMM_I32,
                1,
                0,
                0,
                X86_VINST_IMM_I32,
                2,
                INVALID,
                0,
                0,
                INVALID,
            ],
        );
        let virtual_inst_args = storage_buffer(
            device,
            "tests.x86.select.virtual_inst_args",
            &[
                4, 0, 3, call_info, 11, 0, 0, 0, 12, 0, 0, 0, 1, 2, INVALID, INVALID,
            ],
        );
        let virtual_inst_status = storage_buffer(
            device,
            "tests.x86.select.virtual_inst_status",
            &[1, 0, INVALID, 4],
        );
        let phys_reg = storage_buffer(
            device,
            "tests.x86.select.phys_reg",
            &[X86_REG_EAX, X86_REG_ESI, X86_REG_EDI, INVALID],
        );
        let call_live_mask = storage_buffer(device, "tests.x86.select.call_live_mask", &[0; 4]);
        let regalloc_status = storage_buffer(
            device,
            "tests.x86.select.regalloc_status",
            &[1, 0, INVALID, 4],
        );
        let first_row = storage_buffer(
            device,
            "tests.x86.select.first_row",
            &[
                0, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
        );
        let first_row_status = storage_buffer(
            device,
            "tests.x86.select.first_row_status",
            &[1, 0, INVALID, 4],
        );
        let decl_layout_status = storage_buffer(
            device,
            "tests.x86.select.decl_layout_status",
            &[1, 0, INVALID, 0],
        );
        let func_meta = storage_buffer(
            device,
            "tests.x86.select.func_meta",
            &[1, 0, 0, 0, 0, 0, 0, 0],
        );
        let virtual_func_slot = storage_buffer(
            device,
            "tests.x86.select.virtual_func_slot",
            &[0, 0, 0, INVALID],
        );
        let inst_kind = storage_buffer(device, "tests.x86.select.inst_kind", &[0; 8]);
        let inst_arg0 = storage_buffer(device, "tests.x86.select.inst_arg0", &[0; 8]);
        let inst_arg1 = storage_buffer(device, "tests.x86.select.inst_arg1", &[0; 8]);
        let inst_arg2 = storage_buffer(device, "tests.x86.select.inst_arg2", &[0; 8]);
        let select_status = storage_buffer(device, "tests.x86.select.status", &[0, 0, INVALID, 0]);
        let kind_readback = readback_buffer(device, "tests.x86.select.kind.readback", 8);
        let status_readback = readback_buffer(device, "tests.x86.select.status.readback", 4);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.select.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_args",
                    virtual_inst_args.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_status",
                    virtual_inst_status.as_entire_binding(),
                ),
                ("x86_virtual_phys_reg", phys_reg.as_entire_binding()),
                (
                    "x86_virtual_call_live_reg_mask",
                    call_live_mask.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_status",
                    regalloc_status.as_entire_binding(),
                ),
                ("x86_func_first_virtual_row", first_row.as_entire_binding()),
                (
                    "x86_func_first_virtual_row_status",
                    first_row_status.as_entire_binding(),
                ),
                (
                    "x86_decl_layout_status",
                    decl_layout_status.as_entire_binding(),
                ),
                ("x86_func_meta", func_meta.as_entire_binding()),
                (
                    "x86_virtual_func_slot",
                    virtual_func_slot.as_entire_binding(),
                ),
                ("x86_inst_kind", inst_kind.as_entire_binding()),
                ("x86_inst_arg0", inst_arg0.as_entire_binding()),
                ("x86_inst_arg1", inst_arg1.as_entire_binding()),
                ("x86_inst_arg2", inst_arg2.as_entire_binding()),
                ("select_status", select_status.as_entire_binding()),
            ]),
        )
        .expect("create select bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.select_call_save_mask.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.select_call_save_mask.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&inst_kind, 0, &kind_readback, 0, 8 * 4);
        encoder.copy_buffer_to_buffer(&select_status, 0, &status_readback, 0, 4 * 4);
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &status_readback, 4),
            vec![1, 0, INVALID, 6]
        );
        assert_eq!(
            read_u32s(device, &kind_readback, 8)[1],
            X86_INST_V_CALL_MIXED_DIRECT | ((1u32 << 3) << 8),
            "arg1 in EDI should be saved because arg0 setup clobbers EDI; arg0 in ESI should not be saved"
        );
    });
}

#[test]
fn x86_inst_size_uses_compact_stack_frame_adjustments_from_layout_records() {
    common::block_on_gpu_with_timeout("x86 compact stack frame sizes", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let size_artifacts = compile_shader(&root, "x86_inst_size");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.x86.inst_size",
            "main",
            leak_bytes(size_artifacts.0),
            leak_bytes(size_artifacts.1),
        )
        .expect("create x86_inst_size pass");

        let params = input_uniform(
            device,
            "tests.x86.inst_size.params",
            &[TOKEN_WORDS as u32, 0, 0, 4, 10],
        );
        let inst_kind = storage_buffer(
            device,
            "tests.x86.inst_size.kind",
            &[
                X86_INST_V_ENTRY_STACK_JMP,
                X86_INST_V_CALL_MIXED_DIRECT,
                X86_INST_V_EXIT_ZERO,
                X86_INST_V_MOV_R32_IMM32,
                X86_INST_V_RETURN_R32,
                X86_INST_V_FOR_ARRAY_BRANCH,
                X86_INST_V_MATCH_TAG_BRANCH,
                X86_INST_V_STORE_LOCAL_IMM32,
                X86_INST_V_STORE_RET_PTR_IMM32,
                0,
            ],
        );
        let inst_arg0 = storage_buffer(
            device,
            "tests.x86.inst_size.arg0",
            &[
                2,
                2,
                0,
                X86_REG_EAX,
                X86_REG_EDI,
                0,
                X86_AGG_SOURCE_LOCAL | (3 << 16),
                3,
                0,
                0,
            ],
        );
        let inst_arg1 = storage_buffer(
            device,
            "tests.x86.inst_size.arg1",
            &[16, 0, 0, 7, 0, 4, 0, 0, 1, 0],
        );
        let inst_arg2 = storage_buffer(device, "tests.x86.inst_size.arg2", &[0; 10]);
        let decl_layout_status = storage_buffer(
            device,
            "tests.x86.inst_size.decl_layout_status",
            &[1, 0, INVALID, 0],
        );
        let select_status = storage_buffer(
            device,
            "tests.x86.inst_size.select_status",
            &[1, 0, INVALID, 9],
        );
        let inst_size = storage_buffer(device, "tests.x86.inst_size.out", &[0; 10]);
        let size_status = storage_buffer(device, "tests.x86.inst_size.status", &[0, 0, INVALID, 0]);
        let size_readback = readback_buffer(device, "tests.x86.inst_size.out.readback", 10);
        let status_readback = readback_buffer(device, "tests.x86.inst_size.status.readback", 4);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.inst_size.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                ("x86_inst_kind", inst_kind.as_entire_binding()),
                ("x86_inst_arg0", inst_arg0.as_entire_binding()),
                ("x86_inst_arg1", inst_arg1.as_entire_binding()),
                ("x86_inst_arg2", inst_arg2.as_entire_binding()),
                (
                    "x86_decl_layout_status",
                    decl_layout_status.as_entire_binding(),
                ),
                ("select_status", select_status.as_entire_binding()),
                ("x86_inst_size", inst_size.as_entire_binding()),
                ("size_status", size_status.as_entire_binding()),
            ]),
        )
        .expect("create inst_size bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.inst_size_compact_stack.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.inst_size_compact_stack.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            compute.set_bind_group(0, &bind_group, &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&inst_size, 0, &size_readback, 0, 10 * 4);
        encoder.copy_buffer_to_buffer(&size_status, 0, &status_readback, 0, 4 * 4);
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &status_readback, 4),
            vec![1, 0, INVALID, 9]
        );
        assert_eq!(
            read_u32s(device, &size_readback, 10),
            vec![9, 13, 7, 3, 5, 11, 11, 5, 4, 0],
            "entry, call stack adjustment, return/exit syscalls, branch compares, small immediates, and zero stores should come from selected instruction and decl-layout records"
        );
    });
}

#[test]
fn x86_virtual_next_calls_uses_dynamic_scan_params_and_record_arrays() {
    common::block_on_gpu_with_timeout("x86 virtual next-call dynamic scan params", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let next_call_artifacts = compile_shader(&root, "x86_virtual_next_calls");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.x86.virtual_next_calls",
            "main",
            leak_bytes(next_call_artifacts.0),
            leak_bytes(next_call_artifacts.1),
        )
        .expect("create virtual_next_calls pass");

        let params = input_uniform(device, "tests.x86.next_calls.params", &[0, 0, 0, 12, 8]);
        let scan_params = scan_uniform_array(
            device,
            "tests.x86.next_calls.scan_params",
            &[[8, 0, 0, 8], [8, 0, 1, 8], [8, 0, 2, 8], [8, 0, 4, 8]],
        );
        let virtual_inst_record = storage_buffer(
            device,
            "tests.x86.next_calls.virtual_inst_record",
            &[
                0,
                0,
                0,
                0,
                1,
                0,
                X86_VINST_CALL_MIXED,
                1,
                2,
                0,
                0,
                2,
                3,
                0,
                X86_VINST_BINARY,
                3,
                4,
                0,
                0,
                4,
                5,
                0,
                X86_VINST_CALL_MIXED,
                5,
                6,
                0,
                0,
                6,
                INVALID,
                0,
                0,
                INVALID,
            ],
        );
        let virtual_inst_args = storage_buffer(
            device,
            "tests.x86.next_calls.virtual_inst_args",
            &[
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                X86_OP_SHL_I32,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
                0,
            ],
        );
        let virtual_inst_status = storage_buffer(
            device,
            "tests.x86.next_calls.virtual_inst_status",
            &[1, 0, INVALID, 7],
        );
        let virtual_func_slot = storage_buffer(
            device,
            "tests.x86.next_calls.virtual_func_slot",
            &[8, 8, 8, 8, 9, 9, 9, INVALID],
        );
        let next_call_a = storage_buffer(
            device,
            "tests.x86.next_calls.a",
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
        );
        let next_call_b = storage_buffer(
            device,
            "tests.x86.next_calls.b",
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
        );
        let next_call_status =
            storage_buffer(device, "tests.x86.next_calls.status", &[0, 0, INVALID, 0]);
        let final_readback = readback_buffer(device, "tests.x86.next_calls.final.readback", 8);
        let status_readback = readback_buffer(device, "tests.x86.next_calls.status.readback", 4);

        let even_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.virtual_next_calls.even.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                ("gNextCallScan", dynamic_uniform_binding(&scan_params, 0)),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_args",
                    virtual_inst_args.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_status",
                    virtual_inst_status.as_entire_binding(),
                ),
                (
                    "x86_virtual_func_slot",
                    virtual_func_slot.as_entire_binding(),
                ),
                ("x86_virtual_next_call_in", next_call_b.as_entire_binding()),
                ("x86_virtual_next_call_out", next_call_a.as_entire_binding()),
                (
                    "x86_virtual_next_call_status",
                    next_call_status.as_entire_binding(),
                ),
            ]),
        )
        .expect("create even next-call bind group");
        let odd_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.virtual_next_calls.odd.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                ("gNextCallScan", dynamic_uniform_binding(&scan_params, 0)),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_args",
                    virtual_inst_args.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_status",
                    virtual_inst_status.as_entire_binding(),
                ),
                (
                    "x86_virtual_func_slot",
                    virtual_func_slot.as_entire_binding(),
                ),
                ("x86_virtual_next_call_in", next_call_a.as_entire_binding()),
                ("x86_virtual_next_call_out", next_call_b.as_entire_binding()),
                (
                    "x86_virtual_next_call_status",
                    next_call_status.as_entire_binding(),
                ),
            ]),
        )
        .expect("create odd next-call bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.virtual_next_calls.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.virtual_next_calls.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            for step_i in 0..4 {
                let bind_group = if step_i % 2 == 0 {
                    &even_bind_group
                } else {
                    &odd_bind_group
                };
                compute.set_bind_group(0, bind_group, &[dynamic_uniform_offset(step_i)]);
                compute.dispatch_workgroups(1, 1, 1);
            }
        }
        encoder.copy_buffer_to_buffer(&next_call_b, 0, &final_readback, 0, 8 * 4);
        encoder.copy_buffer_to_buffer(&next_call_status, 0, &status_readback, 0, 4 * 4);
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &final_readback, 8),
            vec![1, 1, 3, 3, 5, 5, INVALID, INVALID],
            "suffix scan should stay inside function segments and use virtual instruction records"
        );
        assert_eq!(
            read_u32s(device, &status_readback, 4),
            vec![1, 0, INVALID, 7]
        );
    });
}

#[test]
fn x86_regalloc_consumes_row_ordered_value_def_records_with_hir_function_slots() {
    common::block_on_gpu_with_timeout("x86 regalloc compact value-def records", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let regalloc_artifacts = compile_shader(&root, "x86_virtual_regalloc");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.x86.virtual_regalloc.compact_value_defs",
            "main",
            leak_bytes(regalloc_artifacts.0),
            leak_bytes(regalloc_artifacts.1),
        )
        .expect("create virtual_regalloc pass");

        let params = input_uniform(
            device,
            "tests.x86.regalloc_compact_defs.params",
            &[TOKEN_WORDS as u32, 0, 0, 2, 4, 0, 8, 1, 2],
        );
        let regalloc_params = scan_uniform_array(
            device,
            "tests.x86.regalloc_compact_defs.dynamic_params",
            &[[0, 1, 1, 0], [1, 1, 0, 0], [2, 1, 0, 0]],
        );
        let func_meta = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.func_meta",
            &[2, 0, INVALID, 0, INVALID, 0, 0, 0],
        );
        let func_slot_by_index = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.func_slot_by_index",
            &[0, 1],
        );
        let virtual_inst_record = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.virtual_inst_record",
            &[
                0,
                0,
                X86_VINST_BINARY,
                0,
                1,
                0,
                X86_VINST_BINARY,
                1,
                0,
                0,
                X86_VINST_BINARY,
                2,
                1,
                0,
                X86_VINST_BINARY,
                3,
            ],
        );
        let virtual_inst_args = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.virtual_inst_args",
            &[0; 16],
        );
        let live_start = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.live_start",
            &[0, 1, 2, 2],
        );
        let live_end = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.live_end",
            &[2, 2, 2, 2],
        );
        let liveness_status = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.liveness_status",
            &[1, 0, INVALID, 4],
        );
        let next_call_status = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.next_call_status",
            &[1, 0, INVALID, 4],
        );
        let param_mask = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.param_mask",
            &[0; 2],
        );
        let param_mask_status = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.param_mask_status",
            &[1, 0, INVALID, 4],
        );
        let first_row = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.first_row",
            &[0, 1, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
        );
        let last_row = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.last_row",
            &[2, 3, 0, 0, 0, 0, 0, 0],
        );
        let first_row_status = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.first_row_status",
            &[1, 0, INVALID, 4],
        );
        let value_defs = regalloc_value_defs(
            device,
            "tests.x86.regalloc_compact_defs",
            &[0, 1, 2, 3],
            4,
            &[0, 1, 0, 1],
        );
        let active_end = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.active_end",
            &[INVALID; 28],
        );
        let param_rank_mask = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.param_rank_mask",
            &[0; 2],
        );
        let phys_reg = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.phys_reg",
            &[INVALID; 4],
        );
        let call_live_mask = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.call_live_mask",
            &[0; 4],
        );
        let regalloc_status = storage_buffer(
            device,
            "tests.x86.regalloc_compact_defs.status",
            &[0, 0, INVALID, 0],
        );
        let phys_readback =
            readback_buffer(device, "tests.x86.regalloc_compact_defs.phys.readback", 4);
        let status_readback =
            readback_buffer(device, "tests.x86.regalloc_compact_defs.status.readback", 4);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.virtual_regalloc.compact_value_defs.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                ("gParams", params.as_entire_binding()),
                ("gRegalloc", dynamic_uniform_binding(&regalloc_params, 0)),
                ("x86_func_meta", func_meta.as_entire_binding()),
                (
                    "x86_func_slot_by_index",
                    func_slot_by_index.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_record",
                    virtual_inst_record.as_entire_binding(),
                ),
                (
                    "x86_virtual_inst_args",
                    virtual_inst_args.as_entire_binding(),
                ),
                ("x86_virtual_live_start", live_start.as_entire_binding()),
                ("x86_virtual_live_end", live_end.as_entire_binding()),
                (
                    "x86_virtual_liveness_status",
                    liveness_status.as_entire_binding(),
                ),
                (
                    "x86_virtual_next_call_status",
                    next_call_status.as_entire_binding(),
                ),
                ("x86_func_param_reg_mask", param_mask.as_entire_binding()),
                (
                    "x86_func_param_reg_mask_status",
                    param_mask_status.as_entire_binding(),
                ),
                ("x86_func_first_virtual_row", first_row.as_entire_binding()),
                ("x86_func_last_virtual_row", last_row.as_entire_binding()),
                (
                    "x86_func_first_virtual_row_status",
                    first_row_status.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_row",
                    value_defs.row.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_scan_local_prefix",
                    value_defs.scan_local_prefix.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_scan_block_prefix",
                    value_defs.scan_block_prefix.as_entire_binding(),
                ),
                (
                    "x86_virtual_value_def_status",
                    value_defs.status.as_entire_binding(),
                ),
                (
                    "x86_virtual_func_slot",
                    value_defs.func_slot.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_active_end",
                    active_end.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_param_rank_mask",
                    param_rank_mask.as_entire_binding(),
                ),
                ("x86_virtual_phys_reg", phys_reg.as_entire_binding()),
                (
                    "x86_virtual_call_live_reg_mask",
                    call_live_mask.as_entire_binding(),
                ),
                (
                    "x86_virtual_regalloc_status",
                    regalloc_status.as_entire_binding(),
                ),
            ]),
        )
        .expect("create compact value-def regalloc bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.regalloc_compact_defs.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.regalloc_compact_defs.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            for step in 0..3 {
                compute.set_bind_group(0, &bind_group, &[dynamic_uniform_offset(step)]);
                compute.dispatch_workgroups(1, 1, 1);
            }
        }
        encoder.copy_buffer_to_buffer(&phys_reg, 0, &phys_readback, 0, 4 * 4);
        encoder.copy_buffer_to_buffer(&regalloc_status, 0, &status_readback, 0, 4 * 4);
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &status_readback, 4),
            vec![1, 0, INVALID, 4]
        );
        assert_eq!(
            read_u32s(device, &phys_readback, 4),
            vec![X86_REG_EAX, X86_REG_EAX, X86_REG_R10D, X86_REG_R10D],
            "regalloc should lower-bound by row, then filter compact value defs by HIR-derived function slot"
        );
    });
}

#[test]
fn x86_node_inst_scan_blocks_use_dynamic_scan_params_and_prefix_records() {
    common::block_on_gpu_with_timeout("x86 node-inst block scan dynamic params", async move {
        let root = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let scan_artifacts = compile_shader(&root, "x86_node_inst_scan_blocks");

        let gpu = device::global();
        let device = gpu.device.as_ref();
        let queue = gpu.queue.as_ref();
        let pass = make_pass_data(
            device,
            "tests.x86.node_inst_scan_blocks",
            "main",
            leak_bytes(scan_artifacts.0),
            leak_bytes(scan_artifacts.1),
        )
        .expect("create node_inst_scan_blocks pass");

        let scan_params = scan_uniform_array(
            device,
            "tests.x86.node_inst_scan_blocks.params",
            &[[4, 4, 0, 0], [4, 4, 1, 0], [4, 4, 2, 0]],
        );
        let block_sum = storage_buffer(
            device,
            "tests.x86.node_inst_scan_blocks.block_sum",
            &[2, 3, 5, 7],
        );
        let prefix_a = storage_buffer(
            device,
            "tests.x86.node_inst_scan_blocks.prefix_a",
            &[0, 0, 0, 0],
        );
        let prefix_b = storage_buffer(
            device,
            "tests.x86.node_inst_scan_blocks.prefix_b",
            &[0, 0, 0, 0],
        );
        let readback = readback_buffer(device, "tests.x86.node_inst_scan_blocks.readback", 4);

        let even_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.node_inst_scan_blocks.even.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                (
                    "gNodeInstBlockScan",
                    dynamic_uniform_binding(&scan_params, 0),
                ),
                (
                    "x86_node_inst_scan_block_sum",
                    block_sum.as_entire_binding(),
                ),
                (
                    "x86_node_inst_scan_block_prefix_in",
                    prefix_b.as_entire_binding(),
                ),
                (
                    "x86_node_inst_scan_block_prefix_out",
                    prefix_a.as_entire_binding(),
                ),
            ]),
        )
        .expect("create even node-inst scan bind group");
        let odd_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("tests.x86.node_inst_scan_blocks.odd.bind_group"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &binding_map(&[
                (
                    "gNodeInstBlockScan",
                    dynamic_uniform_binding(&scan_params, 0),
                ),
                (
                    "x86_node_inst_scan_block_sum",
                    block_sum.as_entire_binding(),
                ),
                (
                    "x86_node_inst_scan_block_prefix_in",
                    prefix_a.as_entire_binding(),
                ),
                (
                    "x86_node_inst_scan_block_prefix_out",
                    prefix_b.as_entire_binding(),
                ),
            ]),
        )
        .expect("create odd node-inst scan bind group");

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("tests.x86.node_inst_scan_blocks.encoder"),
        });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("tests.x86.node_inst_scan_blocks.pass"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&pass.pipeline);
            for step_i in 0..3 {
                let bind_group = if step_i % 2 == 0 {
                    &even_bind_group
                } else {
                    &odd_bind_group
                };
                compute.set_bind_group(0, bind_group, &[dynamic_uniform_offset(step_i)]);
                compute.dispatch_workgroups(1, 1, 1);
            }
        }
        encoder.copy_buffer_to_buffer(&prefix_a, 0, &readback, 0, 4 * 4);
        queue.submit(Some(encoder.finish()));

        assert_eq!(
            read_u32s(device, &readback, 4),
            vec![2, 5, 10, 17],
            "block-prefix scan should use dynamic scan params over prefix records"
        );
    });
}

fn binding_map<'a>(
    bindings: &[(&str, wgpu::BindingResource<'a>)],
) -> HashMap<String, wgpu::BindingResource<'a>> {
    bindings
        .iter()
        .map(|(name, resource)| ((*name).to_string(), resource.clone()))
        .collect()
}

struct RegallocValueDefs {
    row: wgpu::Buffer,
    scan_local_prefix: wgpu::Buffer,
    scan_block_prefix: wgpu::Buffer,
    status: wgpu::Buffer,
    func_slot: wgpu::Buffer,
}

fn regalloc_value_defs(
    device: &wgpu::Device,
    label: &str,
    value_rows: &[u32],
    total: u32,
    func_slot_words: &[u32],
) -> RegallocValueDefs {
    let mut flag_by_row = vec![0u32; value_rows.len().max(1)];
    for &row in value_rows.iter().take(total as usize) {
        if row != INVALID {
            let row = row as usize;
            if row < flag_by_row.len() {
                flag_by_row[row] = 1;
            }
        }
    }
    let mut scan_local_prefix = Vec::with_capacity(flag_by_row.len());
    let mut prefix = 0u32;
    for &flag in &flag_by_row {
        scan_local_prefix.push(prefix);
        prefix += flag;
    }
    RegallocValueDefs {
        row: storage_buffer(device, &format!("{label}.value_def_row"), value_rows),
        scan_local_prefix: storage_buffer(
            device,
            &format!("{label}.value_def_scan_local_prefix"),
            &scan_local_prefix,
        ),
        scan_block_prefix: storage_buffer(
            device,
            &format!("{label}.value_def_scan_block_prefix"),
            &[prefix],
        ),
        status: storage_buffer(
            device,
            &format!("{label}.value_def_status"),
            &[1, 0, INVALID, total],
        ),
        func_slot: storage_buffer(device, &format!("{label}.func_slot"), func_slot_words),
    }
}

fn compile_shader(root: &Path, stem: &str) -> (Vec<u8>, Vec<u8>) {
    let shader = root.join("shaders/codegen").join(format!("{stem}.slang"));
    let spv = common::TempArtifact::new("laniusc_x86_regalloc", stem, Some("spv"));
    let reflection = common::TempArtifact::new("laniusc_x86_regalloc", stem, Some("reflect.json"));
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
        .arg(root.join("shaders/codegen"))
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

fn input_uniform(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &u32_bytes(words),
        usage: wgpu::BufferUsages::UNIFORM,
    })
}

fn scan_uniform_array(device: &wgpu::Device, label: &str, records: &[[u32; 4]]) -> wgpu::Buffer {
    let mut bytes = vec![0u8; records.len().max(1) * 256];
    for (record_i, record) in records.iter().enumerate() {
        let offset = record_i * 256;
        bytes[offset..offset + 16].copy_from_slice(&u32_bytes(record));
    }
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &bytes,
        usage: wgpu::BufferUsages::UNIFORM,
    })
}

fn dynamic_uniform_binding(buffer: &wgpu::Buffer, _index: usize) -> wgpu::BindingResource<'_> {
    wgpu::BindingResource::Buffer(wgpu::BufferBinding {
        buffer,
        offset: 0,
        size: wgpu::BufferSize::new(16),
    })
}

fn dynamic_uniform_offset(index: usize) -> u32 {
    u32::try_from(index * 256).expect("dynamic uniform offset overflow")
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
