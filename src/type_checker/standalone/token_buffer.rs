use super::super::*;

mod core_bind_groups;
mod empty_hir;
mod generic_params;
mod passes;
mod status;

use core_bind_groups::CoreBindGroups;
use empty_hir::EmptyHirBuffers;
use generic_params::{
    create_standalone_generic_param_bind_groups,
    record_standalone_generic_param_passes,
};
use passes::TokenTypeCheckPasses;
use status::finish_with_status;

pub fn check_token_buffer_with_hir_on_gpu(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    source_len: u32,
    token_capacity: u32,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    source_buf: &wgpu::Buffer,
    hir_node_capacity: u32,
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_token_file_id_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
) -> Result<(), GpuTypeCheckError> {
    let params = TypeCheckParams {
        n_tokens: token_capacity,
        source_len,
        n_hir_nodes: hir_node_capacity,
        n_source_files: 1,
    };
    let params_buf = uniform_from_val(device, "type_check.tokens.params", &params);
    let status_buf = storage_u32_rw(
        device,
        "type_check.tokens.status",
        4,
        wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
    );
    let visible_decl_buf = storage_u32_rw(
        device,
        "type_check.tokens.visible_decl",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let visible_type_buf = storage_u32_rw(
        device,
        "type_check.tokens.visible_type",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let name_capacity = token_capacity.saturating_add(LANGUAGE_SYMBOL_COUNT).max(1);
    let hir_value_decl_name_present_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_value_decl_name_present",
        name_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_scan_capacity = hir_node_capacity.max(1);
    let hir_visible_decl_capacity = token_capacity.max(1);
    let hir_decl_scan_n_blocks = hir_visible_decl_scan_capacity.div_ceil(256).max(1);
    let hir_decl_record_n_blocks = hir_visible_decl_capacity.div_ceil(256).max(1);
    let hir_decl_scan_params = NameScanParams {
        n_items: hir_node_capacity,
        n_blocks: hir_decl_scan_n_blocks,
        scan_step: 0,
    };
    let hir_decl_scan_steps = make_name_scan_steps(device, hir_decl_scan_params);
    let hir_decl_tree_leaf_count = hir_visible_decl_capacity
        .div_ceil(HIR_VISIBLE_DECL_ROW_BLOCK_SIZE)
        .max(1);
    let hir_decl_tree_leaf_base = hir_decl_tree_leaf_count.next_power_of_two().max(1);
    let hir_decl_tree_len = hir_decl_tree_leaf_base.saturating_mul(2).max(2) as usize;
    let hir_active_count_buf = storage_ro_from_u32s(
        device,
        "type_check.tokens.hir_active_count",
        &[hir_node_capacity],
    );
    let hir_semantic_dense_node_identity: Vec<u32> = (0..hir_visible_decl_scan_capacity).collect();
    let hir_semantic_dense_node_buf = storage_ro_from_u32s(
        device,
        "type_check.tokens.hir_semantic_dense_node.identity",
        &hir_semantic_dense_node_identity,
    );
    let hir_visible_decl_flag_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_flag",
        hir_visible_decl_scan_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_prefix_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_prefix",
        hir_visible_decl_scan_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_scan_local_prefix_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_scan_local_prefix",
        hir_visible_decl_scan_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_scan_block_sum_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_scan_block_sum",
        hir_decl_scan_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_scan_prefix_a_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_scan_prefix_a",
        hir_decl_scan_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_scan_prefix_b_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_scan_prefix_b",
        hir_decl_scan_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_count_out_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_count_out",
        1,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_owner_fn_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_owner_fn",
        hir_visible_decl_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_name_id_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_name_id",
        hir_visible_decl_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_token",
        hir_visible_decl_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_scope_end_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_scope_end",
        hir_visible_decl_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_node_buf = storage_u32_fill_rw(
        device,
        "type_check.tokens.hir_visible_decl_node",
        hir_visible_decl_capacity as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_key_order_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_key_order",
        hir_visible_decl_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_key_order_tmp_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_key_order_tmp",
        hir_visible_decl_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_key_radix_dispatch_args_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_key_radix_dispatch_args",
        3,
        wgpu::BufferUsages::INDIRECT,
    );
    let hir_visible_decl_key_radix_histogram_len =
        (hir_decl_record_n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
    let hir_visible_decl_key_radix_block_histogram_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_key_radix_block_histogram",
        hir_visible_decl_key_radix_histogram_len,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_key_radix_block_bucket_prefix_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_key_radix_block_bucket_prefix",
        hir_visible_decl_key_radix_histogram_len,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_key_radix_bucket_total_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_key_radix_bucket_total",
        NAME_RADIX_BUCKETS as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_key_radix_bucket_base_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_key_radix_bucket_base",
        NAME_RADIX_BUCKETS as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_key_order_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_field_key_order",
        hir_visible_decl_scan_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_key_order_tmp_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_field_key_order_tmp",
        hir_visible_decl_scan_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_key_radix_dispatch_args_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_field_key_radix_dispatch_args",
        3,
        wgpu::BufferUsages::INDIRECT,
    );
    let struct_field_key_radix_histogram_len =
        (hir_decl_scan_n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
    let struct_field_key_radix_block_histogram_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_field_key_radix_block_histogram",
        struct_field_key_radix_histogram_len,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_key_radix_block_bucket_prefix_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_field_key_radix_block_bucket_prefix",
        struct_field_key_radix_histogram_len,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_key_radix_bucket_total_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_field_key_radix_bucket_total",
        NAME_RADIX_BUCKETS as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_field_key_radix_bucket_base_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_field_key_radix_bucket_base",
        NAME_RADIX_BUCKETS as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_visible_decl_scope_tree_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_visible_decl_scope_tree",
        hir_decl_tree_len,
        wgpu::BufferUsages::empty(),
    );
    let generic_decl_owner_by_node_a_buf = storage_u32_rw(
        device,
        "type_check.tokens.generic_decl_owner_by_node_a",
        hir_visible_decl_scan_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let generic_decl_owner_by_node_b_buf = storage_u32_rw(
        device,
        "type_check.tokens.generic_decl_owner_by_node_b",
        hir_visible_decl_scan_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let generic_decl_parent_jump_a_buf = storage_u32_rw(
        device,
        "type_check.tokens.generic_decl_parent_jump_a",
        hir_visible_decl_scan_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let generic_decl_parent_jump_b_buf = storage_u32_rw(
        device,
        "type_check.tokens.generic_decl_parent_jump_b",
        hir_visible_decl_scan_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let token_file_id_buf = storage_ro_from_u32s(
        device,
        "type_check.tokens.default_token_file_id",
        &vec![0u32; token_capacity.max(1) as usize],
    );
    let name_id_by_token_buf = storage_u32_fill_rw(
        device,
        "type_check.tokens.name_id_by_token_unavailable",
        token_capacity as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let language_name_id_buf = storage_u32_fill_rw(
        device,
        "type_check.tokens.language_name_id_unavailable",
        LANGUAGE_SYMBOL_COUNT as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let language_decl_symbol_slot_buf = storage_ro_from_u32s(
        device,
        "type_check.tokens.language_decl_symbol_slot",
        LANGUAGE_DECL_SYMBOL_SLOTS,
    );
    let language_decl_kind_buf = storage_ro_from_u32s(
        device,
        "type_check.tokens.language_decl_kind",
        LANGUAGE_DECL_KINDS,
    );
    let language_decl_tag_buf = storage_ro_from_u32s(
        device,
        "type_check.tokens.language_decl_tag",
        LANGUAGE_DECL_TAGS,
    );
    let language_decl_name_id_buf = storage_u32_fill_rw(
        device,
        "type_check.tokens.language_decl_name_id_unavailable",
        LANGUAGE_DECL_COUNT as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let language_type_code_by_name_id_buf = storage_u32_rw(
        device,
        "type_check.tokens.language_type_code_by_name_id",
        name_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let language_entrypoint_tag_by_name_id_buf = storage_u32_rw(
        device,
        "type_check.tokens.language_entrypoint_tag_by_name_id",
        name_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let language_intrinsic_tag_by_name_id_buf = storage_u32_rw(
        device,
        "type_check.tokens.language_intrinsic_tag_by_name_id",
        name_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_id_by_file_id_buf = storage_u32_fill_rw(
        device,
        "type_check.tokens.module_id_by_file_id_implicit_root",
        1,
        0,
        wgpu::BufferUsages::empty(),
    );
    let module_count_out_buf = storage_u32_fill_rw(
        device,
        "type_check.tokens.module_count_out_implicit_root",
        1,
        1,
        wgpu::BufferUsages::empty(),
    );
    let module_type_path_type_buf = storage_u32_rw(
        device,
        "type_check.tokens.module_type_path_type",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_type_path_status_buf = storage_u32_rw(
        device,
        "type_check.tokens.module_type_path_status",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_value_path_status_buf = storage_u32_fill_rw(
        device,
        "type_check.tokens.module_value_path_status",
        token_capacity as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let scope_end_buf = storage_u32_rw(
        device,
        "type_check.tokens.scope_end",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let loop_n_blocks = token_capacity.div_ceil(256).max(1);
    let fn_n_blocks = token_capacity.div_ceil(256).max(1);
    let loop_params_value = LoopDepthParams {
        n_tokens: token_capacity,
        n_hir_nodes: hir_node_capacity,
        n_blocks: loop_n_blocks,
        scan_step: 0,
    };
    let fn_params_value = FnContextParams {
        n_tokens: token_capacity,
        n_hir_nodes: hir_node_capacity,
        n_blocks: fn_n_blocks,
        scan_step: 0,
    };
    let loop_params_buf = uniform_from_val(
        device,
        "type_check.tokens.loop_depth.params",
        &loop_params_value,
    );
    let loop_scan_steps = make_loop_depth_scan_steps(device, loop_params_value);
    let fn_params_buf = uniform_from_val(
        device,
        "type_check.tokens.fn_context.params",
        &fn_params_value,
    );
    let fn_scan_steps = make_fn_context_scan_steps(device, fn_params_value);
    let loop_delta_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_delta",
        token_capacity as usize + 1,
        wgpu::BufferUsages::empty(),
    );
    let loop_depth_inblock_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_depth_inblock",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let loop_block_sum_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_block_sum",
        loop_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let loop_prefix_a_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_prefix_a",
        loop_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let loop_prefix_b_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_prefix_b",
        loop_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let loop_block_prefix_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_block_prefix",
        loop_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let loop_depth_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_depth",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let enclosing_fn_buf = storage_u32_rw(
        device,
        "type_check.tokens.enclosing_fn",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let enclosing_fn_end_buf = storage_u32_rw(
        device,
        "type_check.tokens.enclosing_fn_end",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_event_value_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_event_value",
        token_capacity as usize + 1,
        wgpu::BufferUsages::empty(),
    );
    let fn_event_end_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_event_end",
        token_capacity as usize + 1,
        wgpu::BufferUsages::empty(),
    );
    let fn_event_index_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_event_index",
        token_capacity as usize + 1,
        wgpu::BufferUsages::empty(),
    );
    let fn_event_inblock_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_event_inblock",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_block_sum_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_block_sum",
        fn_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_prefix_a_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_prefix_a",
        fn_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_prefix_b_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_prefix_b",
        fn_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_block_prefix_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_block_prefix",
        fn_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let call_fn_index_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_fn_index",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let call_intrinsic_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_intrinsic_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_entrypoint_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_entrypoint_tag",
        token_capacity.max(hir_node_capacity) as usize,
        wgpu::BufferUsages::empty(),
    );
    let call_return_type_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_return_type",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let call_return_type_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_return_type_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let call_param_count_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_param_count",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let call_param_type_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_param_type",
        (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
        wgpu::BufferUsages::empty(),
    );
    let call_param_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_param_ref_tag",
        (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
        wgpu::BufferUsages::empty(),
    );
    let call_param_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_param_ref_payload",
        (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
        wgpu::BufferUsages::empty(),
    );
    let call_arg_record_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_arg_record",
        (token_capacity as usize).max(1) * 4,
        wgpu::BufferUsages::empty(),
    );
    let call_arg_node_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_arg_node",
        (hir_node_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
        wgpu::BufferUsages::empty(),
    );
    let function_lookup_capacity = token_capacity.saturating_mul(2).max(1) as usize;
    let function_lookup_key_buf = storage_u32_rw(
        device,
        "type_check.tokens.function_lookup_key",
        function_lookup_capacity,
        wgpu::BufferUsages::empty(),
    );
    let function_lookup_fn_buf = storage_u32_rw(
        device,
        "type_check.tokens.function_lookup_fn",
        function_lookup_capacity,
        wgpu::BufferUsages::empty(),
    );
    let method_decl_receiver_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_decl_receiver_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_decl_receiver_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_decl_receiver_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_method_impl_node_buf = storage_u32_fill_rw(
        device,
        "type_check.tokens.hir_method_impl_node",
        hir_node_capacity.max(1) as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let hir_method_owner_node_buf = storage_u32_fill_rw(
        device,
        "type_check.tokens.hir_method_owner_node",
        hir_node_capacity.max(1) as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let hir_method_name_token_buf = storage_u32_fill_rw(
        device,
        "type_check.tokens.hir_method_name_token",
        hir_node_capacity.max(1) as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let hir_method_first_param_token_buf = storage_u32_fill_rw(
        device,
        "type_check.tokens.hir_method_first_param_token",
        hir_node_capacity.max(1) as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let hir_method_receiver_mode_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_method_receiver_mode",
        hir_node_capacity.max(1) as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_method_visibility_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_method_visibility",
        hir_node_capacity.max(1) as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_method_signature_flags_buf = storage_u32_rw(
        device,
        "type_check.tokens.hir_method_signature_flags",
        hir_node_capacity.max(1) as usize,
        wgpu::BufferUsages::empty(),
    );
    let hir_method_impl_receiver_type_node_buf = storage_u32_fill_rw(
        device,
        "type_check.tokens.hir_method_impl_receiver_type_node",
        hir_node_capacity.max(1) as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let method_decl_module_id_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_decl_module_id",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_decl_impl_node_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_decl_impl_node",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_decl_name_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_decl_name_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_decl_name_id_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_decl_name_id",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_decl_param_offset_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_decl_param_offset",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_decl_receiver_mode_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_decl_receiver_mode",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_decl_visibility_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_decl_visibility",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_key_to_fn_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_key_to_fn_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_key_order_tmp_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_key_order_tmp",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_key_status_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_key_status",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_key_duplicate_of_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_key_duplicate_of",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_key_radix_histogram_len =
        (token_capacity.div_ceil(256).max(1) as usize) * NAME_RADIX_BUCKETS as usize;
    let method_key_radix_block_histogram_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_key_radix_block_histogram",
        method_key_radix_histogram_len,
        wgpu::BufferUsages::empty(),
    );
    let method_key_radix_block_bucket_prefix_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_key_radix_block_bucket_prefix",
        method_key_radix_histogram_len,
        wgpu::BufferUsages::empty(),
    );
    let method_key_radix_bucket_total_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_key_radix_bucket_total",
        NAME_RADIX_BUCKETS as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_key_radix_bucket_base_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_key_radix_bucket_base",
        NAME_RADIX_BUCKETS as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_call_receiver_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_call_receiver_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_call_receiver_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_call_receiver_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_call_name_id_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_call_name_id",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_call_site_module_id_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_call_site_module_id",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_expr_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_expr_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_expr_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_expr_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_kind_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_kind",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_head_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_head_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_decl_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_decl_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_arg_start_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_arg_start",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_arg_count_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_arg_count",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_decl_generic_param_count_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_decl_generic_param_count",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_decl_generic_param_count_by_node_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_decl_generic_param_count_by_node",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_decl_const_param_count_by_node_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_decl_const_param_count_by_node",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_decl_first_generic_param_row_by_node_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_decl_first_generic_param_row_by_node",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_decl_first_const_param_row_by_node_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_decl_first_const_param_row_by_node",
        hir_node_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_decl_hir_node_by_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_decl_hir_node_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_generic_param_slot_by_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_generic_param_slot_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_const_param_slot_by_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_const_param_slot_by_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_arg_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_arg_ref_tag",
        (token_capacity as usize).max(1) * TYPE_INSTANCE_ARG_REF_STRIDE,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_arg_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_arg_ref_payload",
        (token_capacity as usize).max(1) * TYPE_INSTANCE_ARG_REF_STRIDE,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_elem_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_elem_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_elem_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_elem_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_len_kind_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_len_kind",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_len_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_len_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_state_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_state",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_return_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_return_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_return_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_return_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_type_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.decl_type_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_type_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.decl_type_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let member_result_context_instance_buf = storage_u32_rw(
        device,
        "type_check.tokens.member_result_context_instance",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let member_result_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.member_result_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let member_result_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.member_result_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let member_result_field_ordinal_buf = storage_u32_rw(
        device,
        "type_check.tokens.member_result_field_ordinal",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_init_field_expected_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_init_field_expected_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_init_field_expected_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_init_field_expected_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_init_field_context_instance_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_init_field_context_instance",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_init_field_ordinal_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_init_field_ordinal",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_init_field_ordinal_by_node_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_init_field_ordinal_by_node",
        hir_node_capacity.max(1) as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_lit_context_decl_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_lit_context_decl_token",
        hir_node_capacity.max(1) as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_lit_context_instance_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_lit_context_instance",
        hir_node_capacity.max(1) as usize,
        wgpu::BufferUsages::empty(),
    );
    queue.write_buffer(&status_buf, 0, &status_init_bytes());
    let status_readback = readback_u32s(device, "rb.type_check.tokens.status", 4);

    let passes = TokenTypeCheckPasses::load(device, hir_node_capacity)?;
    let mut resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
    resources.insert("gParams".into(), params_buf.as_entire_binding());
    resources.insert("token_words".into(), token_buf.as_entire_binding());
    resources.insert("token_count".into(), token_count_buf.as_entire_binding());
    resources.insert(
        "token_file_id".into(),
        token_file_id_buf.as_entire_binding(),
    );
    resources.insert(
        "name_id_by_token".into(),
        name_id_by_token_buf.as_entire_binding(),
    );
    resources.insert(
        "language_name_id".into(),
        language_name_id_buf.as_entire_binding(),
    );
    resources.insert(
        "language_decl_symbol_slot".into(),
        language_decl_symbol_slot_buf.as_entire_binding(),
    );
    resources.insert(
        "language_decl_kind".into(),
        language_decl_kind_buf.as_entire_binding(),
    );
    resources.insert(
        "language_decl_tag".into(),
        language_decl_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "language_decl_name_id".into(),
        language_decl_name_id_buf.as_entire_binding(),
    );
    resources.insert(
        "language_type_code_by_name_id".into(),
        language_type_code_by_name_id_buf.as_entire_binding(),
    );
    resources.insert(
        "language_entrypoint_tag_by_name_id".into(),
        language_entrypoint_tag_by_name_id_buf.as_entire_binding(),
    );
    resources.insert(
        "language_intrinsic_tag_by_name_id".into(),
        language_intrinsic_tag_by_name_id_buf.as_entire_binding(),
    );
    resources.insert(
        "module_id_by_file_id".into(),
        module_id_by_file_id_buf.as_entire_binding(),
    );
    resources.insert(
        "module_count_out".into(),
        module_count_out_buf.as_entire_binding(),
    );
    resources.insert("source_bytes".into(), source_buf.as_entire_binding());
    resources.insert("hir_kind".into(), hir_kind_buf.as_entire_binding());
    resources.insert(
        "hir_token_pos".into(),
        hir_token_pos_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_token_end".into(),
        hir_token_end_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_token_file_id".into(),
        hir_token_file_id_buf.as_entire_binding(),
    );
    resources.insert("hir_status".into(), hir_status_buf.as_entire_binding());
    resources.insert("status".into(), status_buf.as_entire_binding());
    resources.insert("visible_decl".into(), visible_decl_buf.as_entire_binding());
    resources.insert("visible_type".into(), visible_type_buf.as_entire_binding());
    let empty_hir_buffers = EmptyHirBuffers::new(device, hir_node_capacity);
    empty_hir_buffers.insert_resources(&mut resources);
    resources.insert(
        "hir_value_decl_name_present".into(),
        hir_value_decl_name_present_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_visible_decl_flag".into(),
        hir_visible_decl_flag_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_visible_decl_prefix".into(),
        hir_visible_decl_prefix_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_visible_decl_count_out".into(),
        hir_visible_decl_count_out_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_semantic_dense_node".into(),
        hir_semantic_dense_node_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_semantic_count".into(),
        hir_active_count_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_active_count".into(),
        hir_active_count_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_visible_decl_owner_fn".into(),
        hir_visible_decl_owner_fn_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_visible_decl_name_id".into(),
        hir_visible_decl_name_id_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_visible_decl_token".into(),
        hir_visible_decl_token_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_visible_decl_scope_end".into(),
        hir_visible_decl_scope_end_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_visible_decl_node".into(),
        hir_visible_decl_node_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_visible_decl_key_order".into(),
        hir_visible_decl_key_order_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_flag".into(),
        hir_visible_decl_flag_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_prefix".into(),
        hir_visible_decl_prefix_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_scan_local_prefix".into(),
        hir_visible_decl_scan_local_prefix_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_scan_block_sum".into(),
        hir_visible_decl_scan_block_sum_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_scan_prefix_a".into(),
        hir_visible_decl_scan_prefix_a_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_scan_prefix_b".into(),
        hir_visible_decl_scan_prefix_b_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_decl_owner_by_node_a".into(),
        generic_decl_owner_by_node_a_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_decl_owner_by_node_b".into(),
        generic_decl_owner_by_node_b_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_decl_parent_jump_a".into(),
        generic_decl_parent_jump_a_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_decl_parent_jump_b".into(),
        generic_decl_parent_jump_b_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_decl_owner_by_node".into(),
        generic_decl_owner_by_node_a_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_count_out".into(),
        hir_visible_decl_count_out_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_owner_node".into(),
        hir_visible_decl_owner_fn_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_name_id".into(),
        hir_visible_decl_name_id_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_token".into(),
        hir_visible_decl_token_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_node".into(),
        hir_visible_decl_scope_end_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_kind".into(),
        type_instance_head_token_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_key_order".into(),
        hir_visible_decl_key_order_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_key_order_tmp".into(),
        hir_visible_decl_key_order_tmp_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_key_radix_dispatch_args".into(),
        hir_visible_decl_key_radix_dispatch_args_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_key_radix_block_histogram".into(),
        hir_visible_decl_key_radix_block_histogram_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_key_radix_block_bucket_prefix".into(),
        hir_visible_decl_key_radix_block_bucket_prefix_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_key_radix_bucket_total".into(),
        hir_visible_decl_key_radix_bucket_total_buf.as_entire_binding(),
    );
    resources.insert(
        "generic_param_key_radix_bucket_base".into(),
        hir_visible_decl_key_radix_bucket_base_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_field_key_order".into(),
        struct_field_key_order_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_field_key_order_tmp".into(),
        struct_field_key_order_tmp_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_field_key_radix_dispatch_args".into(),
        struct_field_key_radix_dispatch_args_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_field_key_radix_block_histogram".into(),
        struct_field_key_radix_block_histogram_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_field_key_radix_block_bucket_prefix".into(),
        struct_field_key_radix_block_bucket_prefix_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_field_key_radix_bucket_total".into(),
        struct_field_key_radix_bucket_total_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_field_key_radix_bucket_base".into(),
        struct_field_key_radix_bucket_base_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_visible_decl_scope_tree".into(),
        hir_visible_decl_scope_tree_buf.as_entire_binding(),
    );
    resources.insert(
        "module_type_path_type".into(),
        module_type_path_type_buf.as_entire_binding(),
    );
    resources.insert(
        "module_type_path_status".into(),
        module_type_path_status_buf.as_entire_binding(),
    );
    resources.insert(
        "module_value_path_status".into(),
        module_value_path_status_buf.as_entire_binding(),
    );
    resources.insert("scope_end".into(), scope_end_buf.as_entire_binding());
    resources.insert("loop_depth".into(), loop_depth_buf.as_entire_binding());
    resources.insert("enclosing_fn".into(), enclosing_fn_buf.as_entire_binding());
    resources.insert(
        "enclosing_fn_end".into(),
        enclosing_fn_end_buf.as_entire_binding(),
    );
    resources.insert("fn_event_end".into(), fn_event_end_buf.as_entire_binding());
    resources.insert(
        "call_fn_index".into(),
        call_fn_index_buf.as_entire_binding(),
    );
    resources.insert(
        "call_intrinsic_tag".into(),
        call_intrinsic_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "fn_entrypoint_tag".into(),
        fn_entrypoint_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "call_return_type".into(),
        call_return_type_buf.as_entire_binding(),
    );
    resources.insert(
        "call_return_type_token".into(),
        call_return_type_token_buf.as_entire_binding(),
    );
    resources.insert(
        "call_param_count".into(),
        call_param_count_buf.as_entire_binding(),
    );
    resources.insert(
        "call_param_type".into(),
        call_param_type_buf.as_entire_binding(),
    );
    resources.insert(
        "call_param_ref_tag".into(),
        call_param_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "call_param_ref_payload".into(),
        call_param_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "call_arg_record".into(),
        call_arg_record_buf.as_entire_binding(),
    );
    resources.insert(
        "call_arg_node".into(),
        call_arg_node_buf.as_entire_binding(),
    );
    resources.insert(
        "function_lookup_key".into(),
        function_lookup_key_buf.as_entire_binding(),
    );
    resources.insert(
        "function_lookup_fn".into(),
        function_lookup_fn_buf.as_entire_binding(),
    );
    resources.insert(
        "method_decl_receiver_ref_tag".into(),
        method_decl_receiver_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "method_decl_receiver_ref_payload".into(),
        method_decl_receiver_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_method_owner_node".into(),
        hir_method_owner_node_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_method_impl_node".into(),
        hir_method_impl_node_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_method_name_token".into(),
        hir_method_name_token_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_method_first_param_token".into(),
        hir_method_first_param_token_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_method_receiver_mode".into(),
        hir_method_receiver_mode_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_method_visibility".into(),
        hir_method_visibility_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_method_signature_flags".into(),
        hir_method_signature_flags_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_method_impl_receiver_type_node".into(),
        hir_method_impl_receiver_type_node_buf.as_entire_binding(),
    );
    resources.insert(
        "method_decl_module_id".into(),
        method_decl_module_id_buf.as_entire_binding(),
    );
    resources.insert(
        "method_decl_impl_node".into(),
        method_decl_impl_node_buf.as_entire_binding(),
    );
    resources.insert(
        "method_decl_name_token".into(),
        method_decl_name_token_buf.as_entire_binding(),
    );
    resources.insert(
        "method_decl_name_id".into(),
        method_decl_name_id_buf.as_entire_binding(),
    );
    resources.insert(
        "method_decl_param_offset".into(),
        method_decl_param_offset_buf.as_entire_binding(),
    );
    resources.insert(
        "method_decl_receiver_mode".into(),
        method_decl_receiver_mode_buf.as_entire_binding(),
    );
    resources.insert(
        "method_decl_visibility".into(),
        method_decl_visibility_buf.as_entire_binding(),
    );
    resources.insert(
        "method_key_to_fn_token".into(),
        method_key_to_fn_token_buf.as_entire_binding(),
    );
    resources.insert(
        "sorted_method_key_order".into(),
        method_key_to_fn_token_buf.as_entire_binding(),
    );
    resources.insert(
        "method_key_status".into(),
        method_key_status_buf.as_entire_binding(),
    );
    resources.insert(
        "method_key_duplicate_of".into(),
        method_key_duplicate_of_buf.as_entire_binding(),
    );
    resources.insert(
        "method_call_receiver_ref_tag".into(),
        method_call_receiver_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "method_call_receiver_ref_payload".into(),
        method_call_receiver_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "method_call_name_id".into(),
        method_call_name_id_buf.as_entire_binding(),
    );
    resources.insert(
        "method_call_site_module_id".into(),
        method_call_site_module_id_buf.as_entire_binding(),
    );
    resources.insert(
        "type_expr_ref_tag".into(),
        type_expr_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "type_expr_ref_payload".into(),
        type_expr_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_kind".into(),
        type_instance_kind_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_head_token".into(),
        type_instance_head_token_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_decl_token".into(),
        type_instance_decl_token_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_arg_start".into(),
        type_instance_arg_start_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_arg_count".into(),
        type_instance_arg_count_buf.as_entire_binding(),
    );
    resources.insert(
        "type_decl_generic_param_count".into(),
        type_decl_generic_param_count_buf.as_entire_binding(),
    );
    resources.insert(
        "type_decl_generic_param_count_by_node".into(),
        type_decl_generic_param_count_by_node_buf.as_entire_binding(),
    );
    resources.insert(
        "type_decl_const_param_count_by_node".into(),
        type_decl_const_param_count_by_node_buf.as_entire_binding(),
    );
    resources.insert(
        "type_decl_first_generic_param_row_by_node".into(),
        type_decl_first_generic_param_row_by_node_buf.as_entire_binding(),
    );
    resources.insert(
        "type_decl_first_const_param_row_by_node".into(),
        type_decl_first_const_param_row_by_node_buf.as_entire_binding(),
    );
    resources.insert(
        "type_decl_hir_node_by_token".into(),
        type_decl_hir_node_by_token_buf.as_entire_binding(),
    );
    resources.insert(
        "type_generic_param_slot_by_token".into(),
        type_generic_param_slot_by_token_buf.as_entire_binding(),
    );
    resources.insert(
        "type_const_param_slot_by_token".into(),
        type_const_param_slot_by_token_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_arg_ref_tag".into(),
        type_instance_arg_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_arg_ref_payload".into(),
        type_instance_arg_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_elem_ref_tag".into(),
        type_instance_elem_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_elem_ref_payload".into(),
        type_instance_elem_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_len_kind".into(),
        type_instance_len_kind_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_len_payload".into(),
        type_instance_len_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_state".into(),
        type_instance_state_buf.as_entire_binding(),
    );
    resources.insert(
        "fn_return_ref_tag".into(),
        fn_return_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "fn_return_ref_payload".into(),
        fn_return_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "decl_type_ref_tag".into(),
        decl_type_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "decl_type_ref_payload".into(),
        decl_type_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "member_result_context_instance".into(),
        member_result_context_instance_buf.as_entire_binding(),
    );
    resources.insert(
        "member_result_ref_tag".into(),
        member_result_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "member_result_ref_payload".into(),
        member_result_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "member_result_field_ordinal".into(),
        member_result_field_ordinal_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_init_field_expected_ref_tag".into(),
        struct_init_field_expected_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_init_field_expected_ref_payload".into(),
        struct_init_field_expected_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_init_field_context_instance".into(),
        struct_init_field_context_instance_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_init_field_ordinal".into(),
        struct_init_field_ordinal_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_init_field_ordinal_by_node".into(),
        struct_init_field_ordinal_by_node_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_lit_context_decl_token".into(),
        struct_lit_context_decl_token_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_lit_context_instance".into(),
        struct_lit_context_instance_buf.as_entire_binding(),
    );
    let type_instances_clear_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_clear"),
        &passes.type_instances_clear.bind_group_layouts[0],
        &passes.type_instances_clear.reflection,
        0,
        &resources,
    )?;
    let generic_param_bind_groups = create_standalone_generic_param_bind_groups(
        device,
        &passes,
        &resources,
        token_capacity,
        hir_node_capacity,
        &hir_decl_scan_steps,
        &hir_visible_decl_key_radix_dispatch_args_buf,
        &struct_field_key_radix_dispatch_args_buf,
    )?;
    let type_instances_collect_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_collect"),
        &passes.type_instances_collect.bind_group_layouts[0],
        &passes.type_instances_collect.reflection,
        0,
        &resources,
    )?;
    let type_instances_collect_named_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_collect_named"),
        &passes.type_instances_collect_named.bind_group_layouts[0],
        &passes.type_instances_collect_named.reflection,
        0,
        &resources,
    )?;
    let type_instances_collect_aggregate_refs_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_collect_aggregate_refs"),
            &passes
                .type_instances_collect_aggregate_refs
                .bind_group_layouts[0],
            &passes.type_instances_collect_aggregate_refs.reflection,
            0,
            &resources,
        )?;
    let type_instances_collect_aggregate_details_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_collect_aggregate_details"),
            &passes
                .type_instances_collect_aggregate_details
                .bind_group_layouts[0],
            &passes.type_instances_collect_aggregate_details.reflection,
            0,
            &resources,
        )?;
    let type_instances_collect_named_arg_refs_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_collect_named_arg_refs"),
            &passes
                .type_instances_collect_named_arg_refs
                .bind_group_layouts[0],
            &passes.type_instances_collect_named_arg_refs.reflection,
            0,
            &resources,
        )?;
    let type_instances_decl_refs_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_decl_refs"),
        &passes.type_instances_decl_refs.bind_group_layouts[0],
        &passes.type_instances_decl_refs.reflection,
        0,
        &resources,
    )?;
    let type_instances_member_receivers_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_member_receivers"),
        &passes.type_instances_member_receivers.bind_group_layouts[0],
        &passes.type_instances_member_receivers.reflection,
        0,
        &resources,
    )?;
    let type_instances_member_results_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_member_results"),
        &passes.type_instances_member_results.bind_group_layouts[0],
        &passes.type_instances_member_results.reflection,
        0,
        &resources,
    )?;
    let type_instances_member_substitute_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_member_substitute"),
            &passes.type_instances_member_substitute.bind_group_layouts[0],
            &passes.type_instances_member_substitute.reflection,
            0,
            &resources,
        )?;
    let type_instances_struct_init_clear_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_struct_init_clear"),
            &passes.type_instances_struct_init_clear.bind_group_layouts[0],
            &passes.type_instances_struct_init_clear.reflection,
            0,
            &resources,
        )?;
    let type_instances_struct_init_contexts_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_struct_init_contexts"),
            &passes
                .type_instances_struct_init_contexts
                .bind_group_layouts[0],
            &passes.type_instances_struct_init_contexts.reflection,
            0,
            &resources,
        )?;
    let type_instances_struct_init_fields_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_struct_init_fields"),
            &passes.type_instances_struct_init_fields.bind_group_layouts[0],
            &passes.type_instances_struct_init_fields.reflection,
            0,
            &resources,
        )?;
    let type_instances_struct_init_substitute_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_struct_init_substitute"),
            &passes
                .type_instances_struct_init_substitute
                .bind_group_layouts[0],
            &passes.type_instances_struct_init_substitute.reflection,
            0,
            &resources,
        )?;
    let type_instances_array_return_refs_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_array_return_refs"),
            &passes.type_instances_array_return_refs.bind_group_layouts[0],
            &passes.type_instances_array_return_refs.reflection,
            0,
            &resources,
        )?;
    let type_instances_array_literal_return_refs_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_array_literal_return_refs"),
            &passes
                .type_instances_array_literal_return_refs
                .bind_group_layouts[0],
            &passes.type_instances_array_literal_return_refs.reflection,
            0,
            &resources,
        )?;
    let type_instances_enum_ctors_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_enum_ctors"),
        &passes.type_instances_enum_ctors.bind_group_layouts[0],
        &passes.type_instances_enum_ctors.reflection,
        0,
        &resources,
    )?;
    let type_instances_array_index_results_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_array_index_results"),
            &passes.type_instances_array_index_results.bind_group_layouts[0],
            &passes.type_instances_array_index_results.reflection,
            0,
            &resources,
        )?;
    let type_instances_validate_aggregate_access_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_validate_aggregate_access"),
            &passes
                .type_instances_validate_aggregate_access
                .bind_group_layouts[0],
            &passes.type_instances_validate_aggregate_access.reflection,
            0,
            &resources,
        )?;
    let conditions_hir_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_conditions_hir"),
        &passes.conditions_hir.bind_group_layouts[0],
        &passes.conditions_hir.reflection,
        0,
        &resources,
    )?;
    let calls_clear_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_clear"),
        &passes.calls_clear.bind_group_layouts[0],
        &passes.calls_clear.reflection,
        0,
        &resources,
    )?;
    let calls_return_refs_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_return_refs"),
        &passes.calls_return_refs.bind_group_layouts[0],
        &passes.calls_return_refs.reflection,
        0,
        &resources,
    )?;
    let calls_entrypoints_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_entrypoints"),
        &passes.calls_entrypoints.bind_group_layouts[0],
        &passes.calls_entrypoints.reflection,
        0,
        &resources,
    )?;
    let calls_functions_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_functions"),
        &passes.calls_functions.bind_group_layouts[0],
        &passes.calls_functions.reflection,
        0,
        &resources,
    )?;
    let calls_param_types_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_param_types"),
        &passes.calls_param_types.bind_group_layouts[0],
        &passes.calls_param_types.reflection,
        0,
        &resources,
    )?;
    let calls_intrinsics_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_intrinsics"),
        &passes.calls_intrinsics.bind_group_layouts[0],
        &passes.calls_intrinsics.reflection,
        0,
        &resources,
    )?;
    let calls_clear_hir_call_args_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_clear_hir_call_args"),
        &passes.calls_clear_hir_call_args.bind_group_layouts[0],
        &passes.calls_clear_hir_call_args.reflection,
        0,
        &resources,
    )?;
    let calls_pack_hir_call_args_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_pack_hir_call_args"),
        &passes.calls_pack_hir_call_args.bind_group_layouts[0],
        &passes.calls_pack_hir_call_args.reflection,
        0,
        &resources,
    )?;
    let calls_resolve_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_resolve"),
        &passes.calls_resolve.bind_group_layouts[0],
        &passes.calls_resolve.reflection,
        0,
        &resources,
    )?;
    let calls_infer_array_generics_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_infer_array_generics"),
        &passes.calls_infer_array_generics.bind_group_layouts[0],
        &passes.calls_infer_array_generics.reflection,
        0,
        &resources,
    )?;
    let calls_validate_array_results_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_validate_array_results"),
        &passes.calls_validate_array_results.bind_group_layouts[0],
        &passes.calls_validate_array_results.reflection,
        0,
        &resources,
    )?;
    let calls_erase_generic_params_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_erase_generic_params"),
        &passes.calls_erase_generic_params.bind_group_layouts[0],
        &passes.calls_erase_generic_params.reflection,
        0,
        &resources,
    )?;
    let calls_bind_groups = CallBindGroups {
        clear: calls_clear_bind_group,
        return_refs: calls_return_refs_bind_group,
        entrypoints: calls_entrypoints_bind_group,
        functions: calls_functions_bind_group,
        param_types: calls_param_types_bind_group,
        intrinsics: calls_intrinsics_bind_group,
        clear_hir_call_args: calls_clear_hir_call_args_bind_group,
        pack_hir_call_args: calls_pack_hir_call_args_bind_group,
        resolve: calls_resolve_bind_group,
        infer_array_generics: calls_infer_array_generics_bind_group,
        validate_array_results: calls_validate_array_results_bind_group,
        erase_generic_params: calls_erase_generic_params_bind_group,
    };
    let language_names_clear_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_language_names_clear"),
        &passes.language_names_clear.bind_group_layouts[0],
        &passes.language_names_clear.reflection,
        0,
        &resources,
    )?;
    let language_names_mark_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_language_names_mark"),
        &passes.language_names_mark.bind_group_layouts[0],
        &passes.language_names_mark.reflection,
        0,
        &resources,
    )?;
    let language_type_codes_clear_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_language_type_codes_clear"),
        &passes.language_type_codes_clear.bind_group_layouts[0],
        &passes.language_type_codes_clear.reflection,
        0,
        &resources,
    )?;
    let language_decls_materialize_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_language_decls_materialize"),
        &passes.language_decls_materialize.bind_group_layouts[0],
        &passes.language_decls_materialize.reflection,
        0,
        &resources,
    )?;
    let language_name_bind_groups = LanguageNameBindGroups {
        clear: language_names_clear_bind_group,
        mark: language_names_mark_bind_group,
        type_codes_clear: language_type_codes_clear_bind_group,
        decls_materialize: language_decls_materialize_bind_group,
    };
    let methods_clear_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_clear"),
        &passes.methods_clear.bind_group_layouts[0],
        &passes.methods_clear.reflection,
        0,
        &resources,
    )?;
    let methods_collect_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_collect"),
        &passes.methods_collect.bind_group_layouts[0],
        &passes.methods_collect.reflection,
        0,
        &resources,
    )?;
    let methods_attach_metadata_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_attach_metadata"),
        &passes.methods_attach_metadata.bind_group_layouts[0],
        &passes.methods_attach_metadata.reflection,
        0,
        &resources,
    )?;
    let methods_bind_self_receivers_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_bind_self_receivers"),
        &passes.methods_bind_self_receivers.bind_group_layouts[0],
        &passes.methods_bind_self_receivers.reflection,
        0,
        &resources,
    )?;
    let method_key_bind_groups = create_method_key_bind_groups_from_passes(
        device,
        "type_check_methods",
        passes.methods_seed_key_order,
        passes.methods_sort_keys,
        passes.names_radix_bucket_prefix,
        passes.names_radix_bucket_bases,
        passes.methods_sort_keys_scatter,
        passes.methods_validate_keys,
        token_capacity,
        token_capacity.div_ceil(256).max(1),
        token_count_buf,
        &module_count_out_buf,
        &method_decl_impl_node_buf,
        &method_decl_receiver_ref_tag_buf,
        &method_decl_receiver_ref_payload_buf,
        &method_decl_module_id_buf,
        &method_decl_name_token_buf,
        &method_decl_name_id_buf,
        &method_decl_visibility_buf,
        &module_type_path_type_buf,
        &type_instance_decl_token_buf,
        &type_instance_arg_start_buf,
        &type_instance_arg_count_buf,
        &type_instance_arg_ref_tag_buf,
        &type_instance_arg_ref_payload_buf,
        &method_key_to_fn_token_buf,
        &method_key_order_tmp_buf,
        &method_key_status_buf,
        &method_key_duplicate_of_buf,
        &method_key_radix_block_histogram_buf,
        &method_key_radix_block_bucket_prefix_buf,
        &method_key_radix_bucket_total_buf,
        &method_key_radix_bucket_base_buf,
        &status_buf,
    )?;
    let methods_mark_call_keys_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_mark_call_keys"),
        &passes.methods_mark_call_keys.bind_group_layouts[0],
        &passes.methods_mark_call_keys.reflection,
        0,
        &resources,
    )?;
    let methods_mark_call_return_keys_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_mark_call_return_keys"),
        &passes.methods_mark_call_return_keys.bind_group_layouts[0],
        &passes.methods_mark_call_return_keys.reflection,
        0,
        &resources,
    )?;
    let methods_resolve_table_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_resolve_table"),
        &passes.methods_resolve_table.bind_group_layouts[0],
        &passes.methods_resolve_table.reflection,
        0,
        &resources,
    )?;
    let methods_resolve_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_resolve"),
        &passes.methods_resolve.bind_group_layouts[0],
        &passes.methods_resolve.reflection,
        0,
        &resources,
    )?;
    let methods_bind_groups = MethodBindGroups {
        clear: methods_clear_bind_group,
        collect: methods_collect_bind_group,
        attach_metadata: methods_attach_metadata_bind_group,
        bind_self_receivers: methods_bind_self_receivers_bind_group,
        keys: method_key_bind_groups,
        mark_call_keys: methods_mark_call_keys_bind_group,
        mark_call_return_keys: methods_mark_call_return_keys_bind_group,
        resolve_table: methods_resolve_table_bind_group,
        resolve: methods_resolve_bind_group,
    };
    let core_bind_groups = CoreBindGroups::create(device, &passes, &resources)?;
    let loop_bind_groups = create_loop_depth_bind_groups(
        device,
        &loop_params_buf,
        &loop_scan_steps,
        token_buf,
        token_count_buf,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        &loop_delta_buf,
        &loop_depth_inblock_buf,
        &loop_block_sum_buf,
        &loop_prefix_a_buf,
        &loop_prefix_b_buf,
        &loop_block_prefix_buf,
        &loop_depth_buf,
    )?;
    let fn_context_bind_groups = create_fn_context_bind_groups(
        device,
        &fn_params_buf,
        &fn_scan_steps,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        &enclosing_fn_buf,
        &enclosing_fn_end_buf,
        &fn_event_value_buf,
        &fn_event_end_buf,
        &fn_event_index_buf,
        &fn_event_inblock_buf,
        &fn_block_sum_buf,
        &fn_prefix_a_buf,
        &fn_prefix_b_buf,
        &fn_block_prefix_buf,
    )?;
    let visible_bind_groups = create_standalone_visible_bind_groups(
        device,
        &resources,
        hir_node_capacity,
        hir_decl_scan_n_blocks,
        hir_visible_decl_capacity,
        hir_decl_record_n_blocks,
        hir_decl_tree_leaf_base,
        &hir_decl_scan_steps,
        &hir_active_count_buf,
        &hir_active_count_buf,
        &hir_visible_decl_flag_buf,
        &hir_visible_decl_prefix_buf,
        &hir_visible_decl_scan_local_prefix_buf,
        &hir_visible_decl_scan_block_sum_buf,
        &hir_visible_decl_scan_prefix_a_buf,
        &hir_visible_decl_scan_prefix_b_buf,
        &hir_visible_decl_count_out_buf,
        &hir_visible_decl_owner_fn_buf,
        &hir_visible_decl_name_id_buf,
        &hir_visible_decl_token_buf,
        &hir_visible_decl_scope_end_buf,
        &hir_visible_decl_key_order_buf,
        &hir_visible_decl_key_order_tmp_buf,
        &hir_visible_decl_key_radix_dispatch_args_buf,
        &hir_visible_decl_key_radix_block_histogram_buf,
        &hir_visible_decl_key_radix_block_bucket_prefix_buf,
        &hir_visible_decl_key_radix_bucket_total_buf,
        &hir_visible_decl_key_radix_bucket_base_buf,
        &hir_visible_decl_scope_tree_buf,
    )?;

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("type_check.tokens.encoder"),
    });
    let n_work = token_capacity.max(hir_node_capacity).max(512);
    record_loop_depth_bind_groups(
        device,
        &mut encoder,
        token_capacity,
        hir_node_capacity,
        loop_n_blocks,
        &loop_bind_groups,
    )?;
    record_fn_context_bind_groups(
        device,
        &mut encoder,
        token_capacity,
        hir_node_capacity,
        fn_n_blocks,
        &fn_context_bind_groups,
    )?;
    record_compute(
        &mut encoder,
        passes.language_names_clear,
        &language_name_bind_groups.clear,
        "type_check.language_names.clear",
        LANGUAGE_SYMBOL_COUNT,
    )?;
    record_compute(
        &mut encoder,
        passes.language_names_mark,
        &language_name_bind_groups.mark,
        "type_check.language_names.mark",
        token_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.language_type_codes_clear,
        &language_name_bind_groups.type_codes_clear,
        "type_check.language_type_codes.clear",
        name_capacity,
    )?;
    record_compute(
        &mut encoder,
        passes.language_decls_materialize,
        &language_name_bind_groups.decls_materialize,
        "type_check.language_decls.materialize",
        LANGUAGE_DECL_COUNT,
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_clear,
        &type_instances_clear_bind_group,
        "type_check.type_instances_clear.pass",
        token_capacity.max(hir_node_capacity),
    )?;
    record_standalone_generic_param_passes(
        &mut encoder,
        &passes,
        &generic_param_bind_groups,
        hir_node_capacity,
        hir_decl_scan_n_blocks,
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_collect,
        &type_instances_collect_bind_group,
        "type_check.type_instances_collect.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_collect_named,
        &type_instances_collect_named_bind_group,
        "type_check.type_instances_collect_named.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_collect_aggregate_refs,
        &type_instances_collect_aggregate_refs_bind_group,
        "type_check.type_instances_collect_aggregate_refs.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_collect_aggregate_details,
        &type_instances_collect_aggregate_details_bind_group,
        "type_check.type_instances_collect_aggregate_details.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_collect_named_arg_refs,
        &type_instances_collect_named_arg_refs_bind_group,
        "type_check.type_instances_collect_named_arg_refs.pass",
        hir_node_capacity.max(1),
    )?;
    record_call_bind_groups(
        device,
        &mut encoder,
        token_capacity,
        n_work,
        &calls_bind_groups,
    )?;
    record_visible_bind_groups(
        device,
        &mut encoder,
        token_capacity,
        hir_node_capacity,
        &visible_bind_groups,
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_decl_refs,
        &type_instances_decl_refs_bind_group,
        "type_check.type_instances_decl_refs.pass",
        hir_node_capacity.max(1),
    )?;
    let method_lookup_work = token_capacity.max(1);
    record_compute(
        &mut encoder,
        passes.methods_clear,
        &methods_bind_groups.clear,
        "type_check.methods.decls.clear",
        method_lookup_work,
    )?;
    record_compute(
        &mut encoder,
        passes.methods_collect,
        &methods_bind_groups.collect,
        "type_check.methods.decls.collect",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.methods_attach_metadata,
        &methods_bind_groups.attach_metadata,
        "type_check.methods.decls.attach_metadata",
        method_lookup_work,
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_member_receivers,
        &type_instances_member_receivers_bind_group,
        "type_check.type_instances_member_receivers.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_member_results,
        &type_instances_member_results_bind_group,
        "type_check.type_instances_member_results.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_member_substitute,
        &type_instances_member_substitute_bind_group,
        "type_check.type_instances_member_substitute.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_struct_init_clear,
        &type_instances_struct_init_clear_bind_group,
        "type_check.type_instances_struct_init_clear.pass",
        token_capacity.max(hir_node_capacity),
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_struct_init_contexts,
        &type_instances_struct_init_contexts_bind_group,
        "type_check.type_instances_struct_init_contexts.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_struct_init_fields,
        &type_instances_struct_init_fields_bind_group,
        "type_check.type_instances_struct_init_fields.pass",
        n_work,
    )?;
    record_method_bind_groups(
        device,
        &mut encoder,
        token_capacity,
        hir_node_capacity,
        n_work,
        &methods_bind_groups,
    )?;
    record_compute(
        &mut encoder,
        passes.scope,
        &core_bind_groups.scope,
        "type_check.scope.pass",
        n_work,
    )?;
    record_compute(
        &mut encoder,
        passes.methods_resolve,
        &methods_bind_groups.resolve,
        "type_check.methods.resolve",
        token_capacity.max(hir_node_capacity).max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_array_index_results,
        &type_instances_array_index_results_bind_group,
        "type_check.type_instances_array_index_results.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_array_return_refs,
        &type_instances_array_return_refs_bind_group,
        "type_check.type_instances_array_return_refs.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_array_literal_return_refs,
        &type_instances_array_literal_return_refs_bind_group,
        "type_check.type_instances_array_literal_return_refs.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_enum_ctors,
        &type_instances_enum_ctors_bind_group,
        "type_check.type_instances_enum_ctors.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_struct_init_substitute,
        &type_instances_struct_init_substitute_bind_group,
        "type_check.type_instances_struct_init_substitute.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        passes.type_instances_validate_aggregate_access,
        &type_instances_validate_aggregate_access_bind_group,
        "type_check.type_instances_validate_aggregate_access.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.conditions_hir,
        &conditions_hir_bind_group,
        "type_check.conditions_hir.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        passes.tokens,
        &core_bind_groups.tokens,
        "type_check.tokens.pass",
        n_work,
    )?;
    record_compute(
        &mut encoder,
        passes.control,
        &core_bind_groups.control,
        "type_check.control.pass",
        n_work,
    )?;
    finish_with_status(device, queue, encoder, &status_buf, &status_readback)
}
