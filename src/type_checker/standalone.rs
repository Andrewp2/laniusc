use super::*;

pub async fn check_tokens_on_gpu(src: &str, tokens: &[Token]) -> Result<(), GpuTypeCheckError> {
    check_tokens_on_gpu_inner(src, tokens).await
}

async fn check_tokens_on_gpu_inner(src: &str, tokens: &[Token]) -> Result<(), GpuTypeCheckError> {
    let ctx = device::global();
    let device = &ctx.device;
    let queue = &ctx.queue;

    let token_bytes = token_bytes(tokens);
    let source_bytes = nonempty_bytes(src.as_bytes());

    let token_buf = storage_ro_from_bytes::<u32>(
        device,
        "type_check.tokens.tokens",
        &token_bytes,
        tokens.len(),
    );
    let token_count_buf = storage_ro_from_u32s(
        device,
        "type_check.tokens.token_count",
        &[tokens.len() as u32],
    );
    let source_buf = storage_ro_from_bytes::<u8>(
        device,
        "type_check.tokens.source",
        &source_bytes,
        source_bytes.len(),
    );
    let hir_kind_buf = storage_ro_from_u32s(device, "type_check.tokens.hir_kind.empty", &[0]);
    let hir_token_pos_buf =
        storage_ro_from_u32s(device, "type_check.tokens.hir_token_pos.empty", &[0]);
    let hir_token_end_buf =
        storage_ro_from_u32s(device, "type_check.tokens.hir_token_end.empty", &[0]);
    let hir_token_file_id_buf =
        storage_ro_from_u32s(device, "type_check.tokens.hir_token_file_id.empty", &[0]);
    let hir_status_buf = storage_ro_from_u32s(
        device,
        "type_check.tokens.hir_status.empty",
        &[0, 0, 0, 0, 0, 0],
    );
    check_token_buffer_with_hir_on_gpu(
        device,
        queue,
        src.len() as u32,
        tokens.len() as u32,
        &token_buf,
        &token_count_buf,
        &source_buf,
        0,
        &hir_kind_buf,
        &hir_token_pos_buf,
        &hir_token_end_buf,
        &hir_token_file_id_buf,
        &hir_status_buf,
    )
}

pub fn check_token_buffer_on_gpu(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    source_len: u32,
    token_capacity: u32,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    source_buf: &wgpu::Buffer,
) -> Result<(), GpuTypeCheckError> {
    let empty = storage_ro_from_u32s(device, "type_check.tokens.hir_kind.empty", &[0]);
    let empty_pos = storage_ro_from_u32s(device, "type_check.tokens.hir_token_pos.empty", &[0]);
    let empty_end = storage_ro_from_u32s(device, "type_check.tokens.hir_token_end.empty", &[0]);
    let empty_file_id =
        storage_ro_from_u32s(device, "type_check.tokens.hir_token_file_id.empty", &[0]);
    let empty_status = storage_ro_from_u32s(
        device,
        "type_check.tokens.hir_status.empty",
        &[0, 0, 0, 0, 0, 0],
    );
    check_token_buffer_with_hir_on_gpu(
        device,
        queue,
        source_len,
        token_capacity,
        token_buf,
        token_count_buf,
        source_buf,
        0,
        &empty,
        &empty_pos,
        &empty_end,
        &empty_file_id,
        &empty_status,
    )
}

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
    let module_id_by_file_id_buf = storage_u32_fill_rw(
        device,
        "type_check.tokens.module_id_by_file_id_implicit_root",
        hir_node_capacity as usize,
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
    let call_arg_record_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_arg_record",
        (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE * 4,
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
    queue.write_buffer(&status_buf, 0, &status_init_bytes());
    let status_readback = readback_u32s(device, "rb.type_check.tokens.status", 4);

    let pass = type_check_tokens_pass(device)?;
    let control_pass = if hir_node_capacity > 0 {
        type_check_control_hir_pass(device)?
    } else {
        type_check_control_pass(device)?
    };
    let scope_pass = type_check_scope_pass(device)?;
    let language_names_clear_pass = type_check_language_names_clear_pass(device)?;
    let language_names_mark_pass = type_check_language_names_mark_pass(device)?;
    let language_decls_materialize_pass = type_check_language_decls_materialize_pass(device)?;
    let calls_clear_pass = type_check_calls_clear_pass(device)?;
    let calls_return_refs_pass = type_check_calls_return_refs_pass(device)?;
    let calls_entrypoints_pass = type_check_calls_entrypoints_pass(device)?;
    let calls_functions_pass = type_check_calls_functions_pass(device)?;
    let calls_param_types_pass = type_check_calls_param_types_pass(device)?;
    let calls_intrinsics_pass = type_check_calls_intrinsics_pass(device)?;
    let calls_clear_hir_call_args_pass = type_check_calls_clear_hir_call_args_pass(device)?;
    let calls_pack_hir_call_args_pass = type_check_calls_pack_hir_call_args_pass(device)?;
    let calls_resolve_pass = type_check_calls_resolve_pass(device)?;
    let calls_erase_generic_params_pass = type_check_calls_erase_generic_params_pass(device)?;
    let methods_clear_pass = type_check_methods_clear_pass(device)?;
    let methods_collect_pass = type_check_methods_collect_pass(device)?;
    let methods_attach_metadata_pass = type_check_methods_attach_metadata_pass(device)?;
    let methods_bind_self_receivers_pass = type_check_methods_bind_self_receivers_pass(device)?;
    let methods_seed_key_order_pass = type_check_methods_seed_key_order_pass(device)?;
    let methods_sort_keys_pass = type_check_methods_sort_keys_pass(device)?;
    let methods_sort_keys_scatter_pass = type_check_methods_sort_keys_scatter_pass(device)?;
    let methods_validate_keys_pass = type_check_methods_validate_keys_pass(device)?;
    let methods_mark_call_keys_pass = type_check_methods_mark_call_keys_pass(device)?;
    let methods_mark_call_return_keys_pass = type_check_methods_mark_call_return_keys_pass(device)?;
    let methods_resolve_table_pass = type_check_methods_resolve_table_pass(device)?;
    let methods_resolve_pass = type_check_methods_resolve_pass(device)?;
    let names_radix_bucket_prefix_pass = type_check_names_radix_bucket_prefix_pass(device)?;
    let names_radix_bucket_bases_pass = type_check_names_radix_bucket_bases_pass(device)?;
    let type_instances_clear_pass = type_check_type_instances_clear_pass(device)?;
    let type_instances_decl_generic_params_pass =
        type_check_type_instances_decl_generic_params_pass(device)?;
    let type_instances_collect_pass = type_check_type_instances_collect_pass(device)?;
    let type_instances_collect_named_pass = type_check_type_instances_collect_named_pass(device)?;
    let type_instances_collect_aggregate_refs_pass =
        type_check_type_instances_collect_aggregate_refs_pass(device)?;
    let type_instances_collect_aggregate_details_pass =
        type_check_type_instances_collect_aggregate_details_pass(device)?;
    let type_instances_collect_named_arg_refs_pass =
        type_check_type_instances_collect_named_arg_refs_pass(device)?;
    let type_instances_decl_refs_pass = type_check_type_instances_decl_refs_pass(device)?;
    let type_instances_member_receivers_pass =
        type_check_type_instances_member_receivers_pass(device)?;
    let type_instances_member_results_pass = type_check_type_instances_member_results_pass(device)?;
    let type_instances_member_substitute_pass =
        type_check_type_instances_member_substitute_pass(device)?;
    let type_instances_struct_init_clear_pass =
        type_check_type_instances_struct_init_clear_pass(device)?;
    let type_instances_struct_init_fields_pass =
        type_check_type_instances_struct_init_fields_pass(device)?;
    let type_instances_struct_init_substitute_pass =
        type_check_type_instances_struct_init_substitute_pass(device)?;
    let type_instances_array_return_refs_pass =
        type_check_type_instances_array_return_refs_pass(device)?;
    let type_instances_array_literal_return_refs_pass =
        type_check_type_instances_array_literal_return_refs_pass(device)?;
    let type_instances_enum_ctors_pass = type_check_type_instances_enum_ctors_pass(device)?;
    let type_instances_array_index_results_pass =
        type_check_type_instances_array_index_results_pass(device)?;
    let type_instances_validate_aggregate_access_pass =
        type_check_type_instances_validate_aggregate_access_pass(device)?;
    let conditions_hir_pass = type_check_conditions_hir_pass(device)?;
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
    let empty_hir_len = hir_node_capacity.max(1) as usize;
    let empty_zero_nodes = vec![0u32; empty_hir_len];
    let empty_invalid_nodes = vec![u32::MAX; empty_hir_len];
    let empty_node_kind = storage_ro_from_u32s(
        device,
        "type_check.tokens.node_kind.empty",
        &empty_zero_nodes,
    );
    let empty_parent = storage_ro_from_u32s(
        device,
        "type_check.tokens.parent.empty",
        &empty_invalid_nodes,
    );
    let empty_first_child = storage_ro_from_u32s(
        device,
        "type_check.tokens.first_child.empty",
        &empty_invalid_nodes,
    );
    let empty_next_sibling = storage_ro_from_u32s(
        device,
        "type_check.tokens.next_sibling.empty",
        &empty_invalid_nodes,
    );
    resources.insert("node_kind".into(), empty_node_kind.as_entire_binding());
    resources.insert("parent".into(), empty_parent.as_entire_binding());
    resources.insert("first_child".into(), empty_first_child.as_entire_binding());
    resources.insert(
        "next_sibling".into(),
        empty_next_sibling.as_entire_binding(),
    );
    resources.insert("hir_item_kind".into(), empty_node_kind.as_entire_binding());
    resources.insert(
        "hir_item_name_token".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert("hir_type_form".into(), empty_node_kind.as_entire_binding());
    resources.insert(
        "hir_type_value_node".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_type_len_token".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_type_len_value".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert("hir_param_record".into(), empty_parent.as_entire_binding());
    resources.insert("hir_expr_form".into(), empty_node_kind.as_entire_binding());
    resources.insert(
        "hir_expr_left_node".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_expr_right_node".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_expr_value_token".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert("hir_expr_record".into(), empty_parent.as_entire_binding());
    resources.insert(
        "hir_expr_int_value".into(),
        empty_node_kind.as_entire_binding(),
    );
    resources.insert(
        "hir_member_receiver_node".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_member_receiver_token".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_member_name_token".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert("hir_stmt_record".into(), empty_parent.as_entire_binding());
    resources.insert(
        "hir_call_callee_node".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_call_arg_start".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert("hir_call_arg_end".into(), empty_parent.as_entire_binding());
    resources.insert(
        "hir_call_arg_count".into(),
        empty_node_kind.as_entire_binding(),
    );
    resources.insert(
        "hir_call_arg_parent_call".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_call_arg_ordinal".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_variant_payload_count".into(),
        empty_node_kind.as_entire_binding(),
    );
    resources.insert(
        "hir_struct_field_parent_struct".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_struct_field_ordinal".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_struct_field_type_node".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_struct_decl_field_start".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_struct_decl_field_count".into(),
        empty_node_kind.as_entire_binding(),
    );
    resources.insert(
        "hir_struct_lit_head_node".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_struct_lit_field_start".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_struct_lit_field_count".into(),
        empty_node_kind.as_entire_binding(),
    );
    resources.insert(
        "hir_struct_lit_field_parent_lit".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert(
        "hir_struct_lit_field_value_node".into(),
        empty_parent.as_entire_binding(),
    );
    resources.insert("status".into(), status_buf.as_entire_binding());
    resources.insert("visible_decl".into(), visible_decl_buf.as_entire_binding());
    resources.insert("visible_type".into(), visible_type_buf.as_entire_binding());
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
        "call_arg_record".into(),
        call_arg_record_buf.as_entire_binding(),
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
    let type_instances_clear_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_clear"),
        &type_instances_clear_pass.bind_group_layouts[0],
        &type_instances_clear_pass.reflection,
        0,
        &resources,
    )?;
    let type_instances_decl_generic_params_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_decl_generic_params"),
            &type_instances_decl_generic_params_pass.bind_group_layouts[0],
            &type_instances_decl_generic_params_pass.reflection,
            0,
            &resources,
        )?;
    let type_instances_collect_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_collect"),
        &type_instances_collect_pass.bind_group_layouts[0],
        &type_instances_collect_pass.reflection,
        0,
        &resources,
    )?;
    let type_instances_collect_named_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_collect_named"),
        &type_instances_collect_named_pass.bind_group_layouts[0],
        &type_instances_collect_named_pass.reflection,
        0,
        &resources,
    )?;
    let type_instances_collect_aggregate_refs_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_collect_aggregate_refs"),
            &type_instances_collect_aggregate_refs_pass.bind_group_layouts[0],
            &type_instances_collect_aggregate_refs_pass.reflection,
            0,
            &resources,
        )?;
    let type_instances_collect_aggregate_details_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_collect_aggregate_details"),
            &type_instances_collect_aggregate_details_pass.bind_group_layouts[0],
            &type_instances_collect_aggregate_details_pass.reflection,
            0,
            &resources,
        )?;
    let type_instances_collect_named_arg_refs_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_collect_named_arg_refs"),
            &type_instances_collect_named_arg_refs_pass.bind_group_layouts[0],
            &type_instances_collect_named_arg_refs_pass.reflection,
            0,
            &resources,
        )?;
    let type_instances_decl_refs_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_decl_refs"),
        &type_instances_decl_refs_pass.bind_group_layouts[0],
        &type_instances_decl_refs_pass.reflection,
        0,
        &resources,
    )?;
    let type_instances_member_receivers_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_member_receivers"),
        &type_instances_member_receivers_pass.bind_group_layouts[0],
        &type_instances_member_receivers_pass.reflection,
        0,
        &resources,
    )?;
    let type_instances_member_results_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_member_results"),
        &type_instances_member_results_pass.bind_group_layouts[0],
        &type_instances_member_results_pass.reflection,
        0,
        &resources,
    )?;
    let type_instances_member_substitute_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_member_substitute"),
            &type_instances_member_substitute_pass.bind_group_layouts[0],
            &type_instances_member_substitute_pass.reflection,
            0,
            &resources,
        )?;
    let type_instances_struct_init_clear_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_struct_init_clear"),
            &type_instances_struct_init_clear_pass.bind_group_layouts[0],
            &type_instances_struct_init_clear_pass.reflection,
            0,
            &resources,
        )?;
    let type_instances_struct_init_fields_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_struct_init_fields"),
            &type_instances_struct_init_fields_pass.bind_group_layouts[0],
            &type_instances_struct_init_fields_pass.reflection,
            0,
            &resources,
        )?;
    let type_instances_struct_init_substitute_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_struct_init_substitute"),
            &type_instances_struct_init_substitute_pass.bind_group_layouts[0],
            &type_instances_struct_init_substitute_pass.reflection,
            0,
            &resources,
        )?;
    let type_instances_array_return_refs_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_array_return_refs"),
            &type_instances_array_return_refs_pass.bind_group_layouts[0],
            &type_instances_array_return_refs_pass.reflection,
            0,
            &resources,
        )?;
    let type_instances_array_literal_return_refs_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_array_literal_return_refs"),
            &type_instances_array_literal_return_refs_pass.bind_group_layouts[0],
            &type_instances_array_literal_return_refs_pass.reflection,
            0,
            &resources,
        )?;
    let type_instances_enum_ctors_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_enum_ctors"),
        &type_instances_enum_ctors_pass.bind_group_layouts[0],
        &type_instances_enum_ctors_pass.reflection,
        0,
        &resources,
    )?;
    let type_instances_array_index_results_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_array_index_results"),
            &type_instances_array_index_results_pass.bind_group_layouts[0],
            &type_instances_array_index_results_pass.reflection,
            0,
            &resources,
        )?;
    let type_instances_validate_aggregate_access_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_validate_aggregate_access"),
            &type_instances_validate_aggregate_access_pass.bind_group_layouts[0],
            &type_instances_validate_aggregate_access_pass.reflection,
            0,
            &resources,
        )?;
    let conditions_hir_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_conditions_hir"),
        &conditions_hir_pass.bind_group_layouts[0],
        &conditions_hir_pass.reflection,
        0,
        &resources,
    )?;
    let calls_clear_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_clear"),
        &calls_clear_pass.bind_group_layouts[0],
        &calls_clear_pass.reflection,
        0,
        &resources,
    )?;
    let calls_return_refs_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_return_refs"),
        &calls_return_refs_pass.bind_group_layouts[0],
        &calls_return_refs_pass.reflection,
        0,
        &resources,
    )?;
    let calls_entrypoints_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_entrypoints"),
        &calls_entrypoints_pass.bind_group_layouts[0],
        &calls_entrypoints_pass.reflection,
        0,
        &resources,
    )?;
    let calls_functions_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_functions"),
        &calls_functions_pass.bind_group_layouts[0],
        &calls_functions_pass.reflection,
        0,
        &resources,
    )?;
    let calls_param_types_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_param_types"),
        &calls_param_types_pass.bind_group_layouts[0],
        &calls_param_types_pass.reflection,
        0,
        &resources,
    )?;
    let calls_intrinsics_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_intrinsics"),
        &calls_intrinsics_pass.bind_group_layouts[0],
        &calls_intrinsics_pass.reflection,
        0,
        &resources,
    )?;
    let calls_clear_hir_call_args_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_clear_hir_call_args"),
        &calls_clear_hir_call_args_pass.bind_group_layouts[0],
        &calls_clear_hir_call_args_pass.reflection,
        0,
        &resources,
    )?;
    let calls_pack_hir_call_args_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_pack_hir_call_args"),
        &calls_pack_hir_call_args_pass.bind_group_layouts[0],
        &calls_pack_hir_call_args_pass.reflection,
        0,
        &resources,
    )?;
    let calls_resolve_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_resolve"),
        &calls_resolve_pass.bind_group_layouts[0],
        &calls_resolve_pass.reflection,
        0,
        &resources,
    )?;
    let calls_erase_generic_params_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_erase_generic_params"),
        &calls_erase_generic_params_pass.bind_group_layouts[0],
        &calls_erase_generic_params_pass.reflection,
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
        erase_generic_params: calls_erase_generic_params_bind_group,
    };
    let language_names_clear_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_language_names_clear"),
        &language_names_clear_pass.bind_group_layouts[0],
        &language_names_clear_pass.reflection,
        0,
        &resources,
    )?;
    let language_names_mark_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_language_names_mark"),
        &language_names_mark_pass.bind_group_layouts[0],
        &language_names_mark_pass.reflection,
        0,
        &resources,
    )?;
    let language_decls_materialize_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_language_decls_materialize"),
        &language_decls_materialize_pass.bind_group_layouts[0],
        &language_decls_materialize_pass.reflection,
        0,
        &resources,
    )?;
    let language_name_bind_groups = LanguageNameBindGroups {
        clear: language_names_clear_bind_group,
        mark: language_names_mark_bind_group,
        decls_materialize: language_decls_materialize_bind_group,
    };
    let methods_clear_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_clear"),
        &methods_clear_pass.bind_group_layouts[0],
        &methods_clear_pass.reflection,
        0,
        &resources,
    )?;
    let methods_collect_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_collect"),
        &methods_collect_pass.bind_group_layouts[0],
        &methods_collect_pass.reflection,
        0,
        &resources,
    )?;
    let methods_attach_metadata_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_attach_metadata"),
        &methods_attach_metadata_pass.bind_group_layouts[0],
        &methods_attach_metadata_pass.reflection,
        0,
        &resources,
    )?;
    let methods_bind_self_receivers_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_bind_self_receivers"),
        &methods_bind_self_receivers_pass.bind_group_layouts[0],
        &methods_bind_self_receivers_pass.reflection,
        0,
        &resources,
    )?;
    let method_key_bind_groups = create_method_key_bind_groups_with_passes(
        device,
        "type_check_methods",
        methods_seed_key_order_pass,
        methods_sort_keys_pass,
        names_radix_bucket_prefix_pass,
        names_radix_bucket_bases_pass,
        methods_sort_keys_scatter_pass,
        methods_validate_keys_pass,
        token_capacity,
        token_capacity.div_ceil(256).max(1),
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
        &methods_mark_call_keys_pass.bind_group_layouts[0],
        &methods_mark_call_keys_pass.reflection,
        0,
        &resources,
    )?;
    let methods_mark_call_return_keys_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_mark_call_return_keys"),
        &methods_mark_call_return_keys_pass.bind_group_layouts[0],
        &methods_mark_call_return_keys_pass.reflection,
        0,
        &resources,
    )?;
    let methods_resolve_table_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_resolve_table"),
        &methods_resolve_table_pass.bind_group_layouts[0],
        &methods_resolve_table_pass.reflection,
        0,
        &resources,
    )?;
    let methods_resolve_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_resolve"),
        &methods_resolve_pass.bind_group_layouts[0],
        &methods_resolve_pass.reflection,
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
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_tokens"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )?;
    let control_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_control"),
        &control_pass.bind_group_layouts[0],
        &control_pass.reflection,
        0,
        &resources,
    )?;
    let scope_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_scope"),
        &scope_pass.bind_group_layouts[0],
        &scope_pass.reflection,
        0,
        &resources,
    )?;
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
    let visible_bind_groups = create_visible_bind_groups(device, &resources)?;

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
        type_instances_clear_pass,
        &type_instances_clear_bind_group,
        "type_check.type_instances_clear.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        type_instances_decl_generic_params_pass,
        &type_instances_decl_generic_params_bind_group,
        "type_check.type_instances_decl_generic_params.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        type_instances_collect_pass,
        &type_instances_collect_bind_group,
        "type_check.type_instances_collect.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        type_instances_collect_named_pass,
        &type_instances_collect_named_bind_group,
        "type_check.type_instances_collect_named.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        type_instances_collect_aggregate_refs_pass,
        &type_instances_collect_aggregate_refs_bind_group,
        "type_check.type_instances_collect_aggregate_refs.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        type_instances_collect_aggregate_details_pass,
        &type_instances_collect_aggregate_details_bind_group,
        "type_check.type_instances_collect_aggregate_details.pass",
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
        type_instances_collect_named_arg_refs_pass,
        &type_instances_collect_named_arg_refs_bind_group,
        "type_check.type_instances_collect_named_arg_refs.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        type_instances_decl_refs_pass,
        &type_instances_decl_refs_bind_group,
        "type_check.type_instances_decl_refs.pass",
        hir_node_capacity.max(1),
    )?;
    let method_lookup_work = token_capacity.saturating_mul(2).max(n_work);
    record_compute(
        &mut encoder,
        methods_clear_pass,
        &methods_bind_groups.clear,
        "type_check.methods.decls.clear",
        method_lookup_work,
    )?;
    record_compute(
        &mut encoder,
        methods_collect_pass,
        &methods_bind_groups.collect,
        "type_check.methods.decls.collect",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        methods_attach_metadata_pass,
        &methods_bind_groups.attach_metadata,
        "type_check.methods.decls.attach_metadata",
        method_lookup_work,
    )?;
    record_compute(
        &mut encoder,
        type_instances_member_receivers_pass,
        &type_instances_member_receivers_bind_group,
        "type_check.type_instances_member_receivers.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        type_instances_member_results_pass,
        &type_instances_member_results_bind_group,
        "type_check.type_instances_member_results.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        type_instances_member_substitute_pass,
        &type_instances_member_substitute_bind_group,
        "type_check.type_instances_member_substitute.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        type_instances_struct_init_clear_pass,
        &type_instances_struct_init_clear_bind_group,
        "type_check.type_instances_struct_init_clear.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        type_instances_struct_init_fields_pass,
        &type_instances_struct_init_fields_bind_group,
        "type_check.type_instances_struct_init_fields.pass",
        n_work,
    )?;
    record_compute(
        &mut encoder,
        language_names_clear_pass,
        &language_name_bind_groups.clear,
        "type_check.language_names.clear",
        LANGUAGE_SYMBOL_COUNT,
    )?;
    record_compute(
        &mut encoder,
        language_names_mark_pass,
        &language_name_bind_groups.mark,
        "type_check.language_names.mark",
        token_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        language_decls_materialize_pass,
        &language_name_bind_groups.decls_materialize,
        "type_check.language_decls.materialize",
        LANGUAGE_DECL_COUNT,
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
        scope_pass,
        &scope_bind_group,
        "type_check.scope.pass",
        n_work,
    )?;
    record_compute(
        &mut encoder,
        methods_resolve_pass,
        &methods_bind_groups.resolve,
        "type_check.methods.resolve",
        token_capacity.max(hir_node_capacity).max(1),
    )?;
    record_compute(
        &mut encoder,
        type_instances_array_index_results_pass,
        &type_instances_array_index_results_bind_group,
        "type_check.type_instances_array_index_results.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        type_instances_array_return_refs_pass,
        &type_instances_array_return_refs_bind_group,
        "type_check.type_instances_array_return_refs.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        type_instances_array_literal_return_refs_pass,
        &type_instances_array_literal_return_refs_bind_group,
        "type_check.type_instances_array_literal_return_refs.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        type_instances_enum_ctors_pass,
        &type_instances_enum_ctors_bind_group,
        "type_check.type_instances_enum_ctors.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        type_instances_struct_init_substitute_pass,
        &type_instances_struct_init_substitute_bind_group,
        "type_check.type_instances_struct_init_substitute.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        type_instances_validate_aggregate_access_pass,
        &type_instances_validate_aggregate_access_bind_group,
        "type_check.type_instances_validate_aggregate_access.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        conditions_hir_pass,
        &conditions_hir_bind_group,
        "type_check.conditions_hir.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        &mut encoder,
        pass,
        &bind_group,
        "type_check.tokens.pass",
        n_work,
    )?;
    record_compute(
        &mut encoder,
        control_pass,
        &control_bind_group,
        "type_check.control.pass",
        n_work,
    )?;
    encoder.copy_buffer_to_buffer(&status_buf, 0, &status_readback, 0, 16);
    crate::gpu::passes_core::submit_with_progress(queue, "type_check.resident", encoder.finish());

    let slice = status_readback.slice(..);
    crate::gpu::passes_core::map_readback_for_progress(&slice, "type_check.resident.status");
    crate::gpu::passes_core::wait_for_map_progress(
        device,
        "type_check.resident.status",
        wgpu::PollType::Wait,
    );
    let mapped = slice.get_mapped_range();
    let words = read_status_words(&mapped)?;
    drop(mapped);
    status_readback.unmap();

    if words[0] != 0 {
        return Ok(());
    }
    Err(GpuTypeCheckError::Rejected {
        token: words[1],
        code: GpuTypeCheckCode::from_u32(words[2]),
        detail: words[3],
    })
}
