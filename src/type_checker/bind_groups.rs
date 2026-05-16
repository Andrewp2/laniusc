use super::*;

impl GpuTypeChecker {
    #[allow(clippy::too_many_arguments)]
    pub(super) fn create_bind_groups(
        &self,
        device: &wgpu::Device,
        source_len: u32,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        hir_node_capacity: u32,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_token_file_id_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        hir_items: Option<GpuTypeCheckHirItemBuffers<'_>>,
        passes: &TypeCheckPasses,
        pass: &PassData,
        control_pass: &PassData,
        scope_pass: &PassData,
        input_fingerprint: u64,
        uses_hir_control: bool,
        uses_hir_items: bool,
    ) -> Result<ResidentTypeCheckBindGroups> {
        let visible_decl = storage_u32_rw(
            device,
            "type_check.resident.visible_decl",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let visible_type = storage_u32_rw(
            device,
            "type_check.resident.visible_type",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_type_path_type = storage_u32_rw(
            device,
            "type_check.resident.module_type_path_type",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_type_path_status = storage_u32_rw(
            device,
            "type_check.resident.module_type_path_status",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_status = storage_u32_fill_rw(
            device,
            "type_check.resident.module_value_path_status",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_expr_head = storage_u32_rw(
            device,
            "type_check.resident.module_value_path_expr_head",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_call_head = storage_u32_rw(
            device,
            "type_check.resident.module_value_path_call_head",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_call_open = storage_u32_fill_rw(
            device,
            "type_check.resident.module_value_path_call_open",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_const_head = storage_u32_rw(
            device,
            "type_check.resident.module_value_path_const_head",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_const_end = storage_u32_fill_rw(
            device,
            "type_check.resident.module_value_path_const_end",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let scope_end = storage_u32_rw(
            device,
            "type_check.resident.scope_end",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_capacity = token_capacity.saturating_add(LANGUAGE_SYMBOL_COUNT).max(1);
        let token_scan_n_blocks = token_capacity.div_ceil(256).max(1);
        let name_n_blocks = name_capacity.div_ceil(256).max(1);
        let name_scan_params = NameScanParams {
            n_items: token_capacity,
            n_blocks: token_scan_n_blocks,
            scan_step: 0,
        };
        let name_scan_steps = make_name_scan_steps(device, name_scan_params);
        let name_lexeme_flag = storage_u32_rw(
            device,
            "type_check.resident.name_lexeme_flag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_lexeme_kind = storage_u32_rw(
            device,
            "type_check.resident.name_lexeme_kind",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_lexeme_prefix = storage_u32_rw(
            device,
            "type_check.resident.name_lexeme_prefix",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_scan_local_prefix = storage_u32_rw(
            device,
            "type_check.resident.name_scan_local_prefix",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_scan_block_sum = storage_u32_rw(
            device,
            "type_check.resident.name_scan_block_sum",
            name_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_scan_prefix_a = storage_u32_rw(
            device,
            "type_check.resident.name_scan_prefix_a",
            name_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_scan_prefix_b = storage_u32_rw(
            device,
            "type_check.resident.name_scan_prefix_b",
            name_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_scan_total = storage_u32_rw(
            device,
            "type_check.resident.name_scan_total",
            1,
            wgpu::BufferUsages::empty(),
        );
        let name_spans = storage_u32_rw(
            device,
            "type_check.resident.name_spans",
            (name_capacity as usize).max(1) * 4,
            wgpu::BufferUsages::empty(),
        );
        let name_order_in = storage_u32_rw(
            device,
            "type_check.resident.name_order_in",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_order_tmp = storage_u32_rw(
            device,
            "type_check.resident.name_order_tmp",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let language_symbol_bytes = storage_ro_from_bytes::<u8>(
            device,
            "type_check.resident.language_symbol_bytes",
            LANGUAGE_SYMBOL_BYTES,
            LANGUAGE_SYMBOL_BYTES.len(),
        );
        let language_symbol_start = storage_ro_from_u32s(
            device,
            "type_check.resident.language_symbol_start",
            LANGUAGE_SYMBOL_STARTS,
        );
        let language_symbol_len = storage_ro_from_u32s(
            device,
            "type_check.resident.language_symbol_len",
            LANGUAGE_SYMBOL_LENS,
        );
        let name_id_by_token = storage_u32_rw(
            device,
            "type_check.resident.name_id_by_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let language_name_id = storage_u32_rw(
            device,
            "type_check.resident.language_name_id",
            LANGUAGE_SYMBOL_COUNT as usize,
            wgpu::BufferUsages::empty(),
        );
        let language_decl_symbol_slot = storage_ro_from_u32s(
            device,
            "type_check.resident.language_decl_symbol_slot",
            LANGUAGE_DECL_SYMBOL_SLOTS,
        );
        let language_decl_kind = storage_ro_from_u32s(
            device,
            "type_check.resident.language_decl_kind",
            LANGUAGE_DECL_KINDS,
        );
        let language_decl_tag = storage_ro_from_u32s(
            device,
            "type_check.resident.language_decl_tag",
            LANGUAGE_DECL_TAGS,
        );
        let language_decl_name_id = storage_u32_rw(
            device,
            "type_check.resident.language_decl_name_id",
            LANGUAGE_DECL_COUNT as usize,
            wgpu::BufferUsages::empty(),
        );
        let radix_histogram_len = (name_n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
        let radix_block_histogram = storage_u32_rw(
            device,
            "type_check.resident.radix_block_histogram",
            radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let radix_block_bucket_prefix = storage_u32_rw(
            device,
            "type_check.resident.radix_block_bucket_prefix",
            radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let radix_bucket_total = storage_u32_rw(
            device,
            "type_check.resident.radix_bucket_total",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let radix_bucket_base = storage_u32_rw(
            device,
            "type_check.resident.radix_bucket_base",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let run_head_mask = storage_u32_rw(
            device,
            "type_check.resident.run_head_mask",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let adjacent_equal_mask = storage_u32_rw(
            device,
            "type_check.resident.adjacent_equal_mask",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let run_head_prefix = storage_u32_rw(
            device,
            "type_check.resident.run_head_prefix",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let sorted_name_id = storage_u32_rw(
            device,
            "type_check.resident.sorted_name_id",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_id_by_input = storage_u32_rw(
            device,
            "type_check.resident.name_id_by_input",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let unique_name_count = storage_u32_rw(
            device,
            "type_check.resident.unique_name_count",
            1,
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
        let loop_params = uniform_from_val(
            device,
            "type_check.resident.loop_depth.params",
            &loop_params_value,
        );
        let loop_scan_steps = make_loop_depth_scan_steps(device, loop_params_value);
        let fn_params = uniform_from_val(
            device,
            "type_check.resident.fn_context.params",
            &fn_params_value,
        );
        let fn_scan_steps = make_fn_context_scan_steps(device, fn_params_value);
        let loop_delta = storage_i32_rw(
            device,
            "type_check.resident.loop_delta",
            token_capacity as usize + 1,
            wgpu::BufferUsages::empty(),
        );
        let loop_depth_inblock = storage_i32_rw(
            device,
            "type_check.resident.loop_depth_inblock",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_block_sum = storage_i32_rw(
            device,
            "type_check.resident.loop_block_sum",
            loop_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_prefix_a = storage_i32_rw(
            device,
            "type_check.resident.loop_prefix_a",
            loop_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_prefix_b = storage_i32_rw(
            device,
            "type_check.resident.loop_prefix_b",
            loop_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_block_prefix = storage_i32_rw(
            device,
            "type_check.resident.loop_block_prefix",
            loop_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_depth = storage_i32_rw(
            device,
            "type_check.resident.loop_depth",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let enclosing_fn = storage_u32_rw(
            device,
            "type_check.resident.enclosing_fn",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let enclosing_fn_end = storage_u32_rw(
            device,
            "type_check.resident.enclosing_fn_end",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_event_value = storage_u32_rw(
            device,
            "type_check.resident.fn_event_value",
            token_capacity as usize + 1,
            wgpu::BufferUsages::empty(),
        );
        let fn_event_end = storage_u32_rw(
            device,
            "type_check.resident.fn_event_end",
            token_capacity as usize + 1,
            wgpu::BufferUsages::empty(),
        );
        let fn_event_index = storage_u32_rw(
            device,
            "type_check.resident.fn_event_index",
            token_capacity as usize + 1,
            wgpu::BufferUsages::empty(),
        );
        let fn_event_inblock = storage_u32_rw(
            device,
            "type_check.resident.fn_event_inblock",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_block_sum = storage_u32_rw(
            device,
            "type_check.resident.fn_block_sum",
            fn_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_prefix_a = storage_u32_rw(
            device,
            "type_check.resident.fn_prefix_a",
            fn_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_prefix_b = storage_u32_rw(
            device,
            "type_check.resident.fn_prefix_b",
            fn_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_block_prefix = storage_u32_rw(
            device,
            "type_check.resident.fn_block_prefix",
            fn_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_fn_index = storage_u32_rw(
            device,
            "type_check.resident.call_fn_index",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_intrinsic_tag = storage_u32_rw(
            device,
            "type_check.resident.call_intrinsic_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_entrypoint_tag = storage_u32_rw(
            device,
            "type_check.resident.fn_entrypoint_tag",
            token_capacity.max(hir_node_capacity) as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_return_type = storage_u32_rw(
            device,
            "type_check.resident.call_return_type",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_return_type_token = storage_u32_rw(
            device,
            "type_check.resident.call_return_type_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_count = storage_u32_rw(
            device,
            "type_check.resident.call_param_count",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_type = storage_u32_rw(
            device,
            "type_check.resident.call_param_type",
            (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_record = storage_u32_rw(
            device,
            "type_check.resident.call_arg_record",
            (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE * 4,
            wgpu::BufferUsages::empty(),
        );
        let function_lookup_capacity = token_capacity.saturating_mul(2).max(1) as usize;
        let function_lookup_key = storage_u32_rw(
            device,
            "type_check.resident.function_lookup_key",
            function_lookup_capacity,
            wgpu::BufferUsages::empty(),
        );
        let function_lookup_fn = storage_u32_rw(
            device,
            "type_check.resident.function_lookup_fn",
            function_lookup_capacity,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_receiver_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.method_decl_receiver_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_receiver_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.method_decl_receiver_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_module_id = storage_u32_rw(
            device,
            "type_check.resident.method_decl_module_id",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_impl_node = storage_u32_rw(
            device,
            "type_check.resident.method_decl_impl_node",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_name_token = storage_u32_rw(
            device,
            "type_check.resident.method_decl_name_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_name_id = storage_u32_rw(
            device,
            "type_check.resident.method_decl_name_id",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_param_offset = storage_u32_rw(
            device,
            "type_check.resident.method_decl_param_offset",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_receiver_mode = storage_u32_rw(
            device,
            "type_check.resident.method_decl_receiver_mode",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_visibility = storage_u32_rw(
            device,
            "type_check.resident.method_decl_visibility",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_module_id_by_file_id_implicit_root = storage_u32_fill_rw(
            device,
            "type_check.resident.method_module_id_by_file_id_implicit_root",
            hir_node_capacity as usize,
            0,
            wgpu::BufferUsages::empty(),
        );
        let method_module_count_out_implicit_root = storage_u32_fill_rw(
            device,
            "type_check.resident.method_module_count_out_implicit_root",
            1,
            1,
            wgpu::BufferUsages::empty(),
        );
        let method_key_to_fn_token = storage_u32_rw(
            device,
            "type_check.resident.method_key_to_fn_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_key_order_tmp = storage_u32_rw(
            device,
            "type_check.resident.method_key_order_tmp",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_key_status = storage_u32_rw(
            device,
            "type_check.resident.method_key_status",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_key_duplicate_of = storage_u32_rw(
            device,
            "type_check.resident.method_key_duplicate_of",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_key_radix_histogram_len =
            (name_n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
        let method_key_radix_block_histogram = storage_u32_rw(
            device,
            "type_check.resident.method_key_radix_block_histogram",
            method_key_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let method_key_radix_block_bucket_prefix = storage_u32_rw(
            device,
            "type_check.resident.method_key_radix_block_bucket_prefix",
            method_key_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let method_key_radix_bucket_total = storage_u32_rw(
            device,
            "type_check.resident.method_key_radix_bucket_total",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_key_radix_bucket_base = storage_u32_rw(
            device,
            "type_check.resident.method_key_radix_bucket_base",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_call_receiver_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.method_call_receiver_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_call_receiver_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.method_call_receiver_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_call_name_id = storage_u32_rw(
            device,
            "type_check.resident.method_call_name_id",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_call_site_module_id = storage_u32_rw(
            device,
            "type_check.resident.method_call_site_module_id",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_expr_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.type_expr_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_expr_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.type_expr_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_kind = storage_u32_rw(
            device,
            "type_check.resident.type_instance_kind",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_head_token = storage_u32_rw(
            device,
            "type_check.resident.type_instance_head_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_decl_generic_param_count = storage_u32_rw(
            device,
            "type_check.resident.type_decl_generic_param_count",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_decl_token = storage_u32_rw(
            device,
            "type_check.resident.type_instance_decl_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_start = storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_start",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_count = storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_count",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_ref_tag",
            (token_capacity as usize).max(1) * TYPE_INSTANCE_ARG_REF_STRIDE,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_ref_payload",
            (token_capacity as usize).max(1) * TYPE_INSTANCE_ARG_REF_STRIDE,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_elem_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.type_instance_elem_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_elem_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.type_instance_elem_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_len_kind = storage_u32_rw(
            device,
            "type_check.resident.type_instance_len_kind",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_len_payload = storage_u32_rw(
            device,
            "type_check.resident.type_instance_len_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_state = storage_u32_rw(
            device,
            "type_check.resident.type_instance_state",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_return_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.fn_return_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_return_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.fn_return_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let decl_type_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.decl_type_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let decl_type_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.decl_type_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let member_result_context_instance = storage_u32_rw(
            device,
            "type_check.resident.member_result_context_instance",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let member_result_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.member_result_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let member_result_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.member_result_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let member_result_field_ordinal = storage_u32_rw(
            device,
            "type_check.resident.member_result_field_ordinal",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_init_field_expected_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.struct_init_field_expected_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_init_field_expected_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.struct_init_field_expected_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_init_field_context_instance = storage_u32_rw(
            device,
            "type_check.resident.struct_init_field_context_instance",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_init_field_ordinal = storage_u32_rw(
            device,
            "type_check.resident.struct_init_field_ordinal",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let empty_hir_len = hir_node_capacity.max(1) as usize;
        let invalid_node = vec![u32::MAX; empty_hir_len];
        let zero_node = vec![0u32; empty_hir_len];
        let node_kind_empty =
            storage_ro_from_u32s(device, "type_check.resident.node_kind.empty", &zero_node);
        let parent_empty =
            storage_ro_from_u32s(device, "type_check.resident.parent.empty", &invalid_node);
        let first_child_empty = storage_ro_from_u32s(
            device,
            "type_check.resident.first_child.empty",
            &invalid_node,
        );
        let next_sibling_empty = storage_ro_from_u32s(
            device,
            "type_check.resident.next_sibling.empty",
            &invalid_node,
        );
        let mut resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
        resources.insert("gParams".into(), self.params_buf.as_entire_binding());
        resources.insert("token_words".into(), token_buf.as_entire_binding());
        resources.insert("token_count".into(), token_count_buf.as_entire_binding());
        resources.insert(
            "token_file_id".into(),
            token_file_id_buf.as_entire_binding(),
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
        if let Some(hir_items) = hir_items {
            resources.insert("node_kind".into(), hir_items.node_kind.as_entire_binding());
            resources.insert("parent".into(), hir_items.parent.as_entire_binding());
            resources.insert(
                "first_child".into(),
                hir_items.first_child.as_entire_binding(),
            );
            resources.insert(
                "next_sibling".into(),
                hir_items.next_sibling.as_entire_binding(),
            );
            resources.insert("hir_item_kind".into(), hir_items.kind.as_entire_binding());
            resources.insert(
                "hir_item_name_token".into(),
                hir_items.name_token.as_entire_binding(),
            );
            resources.insert(
                "hir_type_form".into(),
                hir_items.type_form.as_entire_binding(),
            );
            resources.insert(
                "hir_type_value_node".into(),
                hir_items.type_value_node.as_entire_binding(),
            );
            resources.insert(
                "hir_type_len_token".into(),
                hir_items.type_len_token.as_entire_binding(),
            );
            resources.insert(
                "hir_type_len_value".into(),
                hir_items.type_len_value.as_entire_binding(),
            );
            resources.insert(
                "hir_param_record".into(),
                hir_items.param_record.as_entire_binding(),
            );
            resources.insert(
                "hir_expr_form".into(),
                hir_items.expr_form.as_entire_binding(),
            );
            resources.insert(
                "hir_expr_left_node".into(),
                hir_items.expr_left_node.as_entire_binding(),
            );
            resources.insert(
                "hir_expr_right_node".into(),
                hir_items.expr_right_node.as_entire_binding(),
            );
            resources.insert(
                "hir_expr_value_token".into(),
                hir_items.expr_value_token.as_entire_binding(),
            );
            resources.insert(
                "hir_expr_record".into(),
                hir_items.expr_record.as_entire_binding(),
            );
            resources.insert(
                "hir_expr_int_value".into(),
                hir_items.expr_int_value.as_entire_binding(),
            );
            resources.insert(
                "hir_member_receiver_node".into(),
                hir_items.member_receiver_node.as_entire_binding(),
            );
            resources.insert(
                "hir_member_receiver_token".into(),
                hir_items.member_receiver_token.as_entire_binding(),
            );
            resources.insert(
                "hir_member_name_token".into(),
                hir_items.member_name_token.as_entire_binding(),
            );
            resources.insert(
                "hir_stmt_record".into(),
                hir_items.stmt_record.as_entire_binding(),
            );
            resources.insert(
                "hir_call_callee_node".into(),
                hir_items.call_callee_node.as_entire_binding(),
            );
            resources.insert(
                "hir_call_arg_start".into(),
                hir_items.call_arg_start.as_entire_binding(),
            );
            resources.insert(
                "hir_call_arg_end".into(),
                hir_items.call_arg_end.as_entire_binding(),
            );
            resources.insert(
                "hir_call_arg_count".into(),
                hir_items.call_arg_count.as_entire_binding(),
            );
            resources.insert(
                "hir_call_arg_parent_call".into(),
                hir_items.call_arg_parent_call.as_entire_binding(),
            );
            resources.insert(
                "hir_call_arg_ordinal".into(),
                hir_items.call_arg_ordinal.as_entire_binding(),
            );
            resources.insert(
                "hir_variant_payload_count".into(),
                hir_items.variant_payload_count.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_field_parent_struct".into(),
                hir_items.struct_field_parent_struct.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_field_ordinal".into(),
                hir_items.struct_field_ordinal.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_field_type_node".into(),
                hir_items.struct_field_type_node.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_decl_field_start".into(),
                hir_items.struct_decl_field_start.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_decl_field_count".into(),
                hir_items.struct_decl_field_count.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_lit_head_node".into(),
                hir_items.struct_lit_head_node.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_lit_field_start".into(),
                hir_items.struct_lit_field_start.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_lit_field_count".into(),
                hir_items.struct_lit_field_count.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_lit_field_parent_lit".into(),
                hir_items.struct_lit_field_parent_lit.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_lit_field_value_node".into(),
                hir_items.struct_lit_field_value_node.as_entire_binding(),
            );
        } else {
            resources.insert("node_kind".into(), node_kind_empty.as_entire_binding());
            resources.insert("parent".into(), parent_empty.as_entire_binding());
            resources.insert("first_child".into(), first_child_empty.as_entire_binding());
            resources.insert(
                "next_sibling".into(),
                next_sibling_empty.as_entire_binding(),
            );
            resources.insert("hir_item_kind".into(), node_kind_empty.as_entire_binding());
            resources.insert(
                "hir_item_name_token".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert("hir_type_form".into(), node_kind_empty.as_entire_binding());
            resources.insert(
                "hir_type_value_node".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_type_len_token".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_type_len_value".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert("hir_param_record".into(), parent_empty.as_entire_binding());
            resources.insert("hir_expr_form".into(), node_kind_empty.as_entire_binding());
            resources.insert(
                "hir_expr_left_node".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_expr_right_node".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_expr_value_token".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert("hir_expr_record".into(), parent_empty.as_entire_binding());
            resources.insert(
                "hir_expr_int_value".into(),
                node_kind_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_member_receiver_node".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_member_receiver_token".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_member_name_token".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert("hir_stmt_record".into(), parent_empty.as_entire_binding());
            resources.insert(
                "hir_call_callee_node".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_call_arg_start".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert("hir_call_arg_end".into(), parent_empty.as_entire_binding());
            resources.insert(
                "hir_call_arg_count".into(),
                node_kind_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_call_arg_parent_call".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_call_arg_ordinal".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_variant_payload_count".into(),
                node_kind_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_field_parent_struct".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_field_ordinal".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_field_type_node".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_decl_field_start".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_decl_field_count".into(),
                node_kind_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_lit_head_node".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_lit_field_start".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_lit_field_count".into(),
                node_kind_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_lit_field_parent_lit".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_struct_lit_field_value_node".into(),
                parent_empty.as_entire_binding(),
            );
        }
        resources.insert("status".into(), self.status_buf.as_entire_binding());
        resources.insert("visible_decl".into(), visible_decl.as_entire_binding());
        resources.insert("visible_type".into(), visible_type.as_entire_binding());
        resources.insert(
            "module_type_path_type".into(),
            module_type_path_type.as_entire_binding(),
        );
        resources.insert(
            "module_type_path_status".into(),
            module_type_path_status.as_entire_binding(),
        );
        resources.insert(
            "module_value_path_status".into(),
            module_value_path_status.as_entire_binding(),
        );
        resources.insert("scope_end".into(), scope_end.as_entire_binding());
        resources.insert("loop_depth".into(), loop_depth.as_entire_binding());
        resources.insert("enclosing_fn".into(), enclosing_fn.as_entire_binding());
        resources.insert(
            "enclosing_fn_end".into(),
            enclosing_fn_end.as_entire_binding(),
        );
        resources.insert("fn_event_value".into(), fn_event_value.as_entire_binding());
        resources.insert("fn_event_end".into(), fn_event_end.as_entire_binding());
        resources.insert("fn_event_index".into(), fn_event_index.as_entire_binding());
        resources.insert(
            "fn_event_inblock".into(),
            fn_event_inblock.as_entire_binding(),
        );
        resources.insert("block_sum".into(), fn_block_sum.as_entire_binding());
        resources.insert("block_prefix".into(), fn_block_prefix.as_entire_binding());
        resources.insert("call_fn_index".into(), call_fn_index.as_entire_binding());
        resources.insert(
            "call_intrinsic_tag".into(),
            call_intrinsic_tag.as_entire_binding(),
        );
        resources.insert(
            "fn_entrypoint_tag".into(),
            fn_entrypoint_tag.as_entire_binding(),
        );
        resources.insert(
            "call_return_type".into(),
            call_return_type.as_entire_binding(),
        );
        resources.insert(
            "call_return_type_token".into(),
            call_return_type_token.as_entire_binding(),
        );
        resources.insert(
            "call_param_count".into(),
            call_param_count.as_entire_binding(),
        );
        resources.insert(
            "call_param_type".into(),
            call_param_type.as_entire_binding(),
        );
        resources.insert(
            "call_arg_record".into(),
            call_arg_record.as_entire_binding(),
        );
        resources.insert(
            "function_lookup_key".into(),
            function_lookup_key.as_entire_binding(),
        );
        resources.insert(
            "function_lookup_fn".into(),
            function_lookup_fn.as_entire_binding(),
        );
        resources.insert(
            "method_decl_receiver_ref_tag".into(),
            method_decl_receiver_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "method_decl_receiver_ref_payload".into(),
            method_decl_receiver_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "method_decl_module_id".into(),
            method_decl_module_id.as_entire_binding(),
        );
        resources.insert(
            "method_decl_impl_node".into(),
            method_decl_impl_node.as_entire_binding(),
        );
        resources.insert(
            "method_decl_name_token".into(),
            method_decl_name_token.as_entire_binding(),
        );
        resources.insert(
            "method_decl_name_id".into(),
            method_decl_name_id.as_entire_binding(),
        );
        resources.insert(
            "method_decl_param_offset".into(),
            method_decl_param_offset.as_entire_binding(),
        );
        resources.insert(
            "method_decl_receiver_mode".into(),
            method_decl_receiver_mode.as_entire_binding(),
        );
        resources.insert(
            "method_decl_visibility".into(),
            method_decl_visibility.as_entire_binding(),
        );
        resources.insert(
            "method_key_to_fn_token".into(),
            method_key_to_fn_token.as_entire_binding(),
        );
        resources.insert(
            "sorted_method_key_order".into(),
            method_key_to_fn_token.as_entire_binding(),
        );
        resources.insert(
            "method_key_status".into(),
            method_key_status.as_entire_binding(),
        );
        resources.insert(
            "method_key_duplicate_of".into(),
            method_key_duplicate_of.as_entire_binding(),
        );
        resources.insert(
            "method_call_receiver_ref_tag".into(),
            method_call_receiver_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "method_call_receiver_ref_payload".into(),
            method_call_receiver_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "method_call_name_id".into(),
            method_call_name_id.as_entire_binding(),
        );
        resources.insert(
            "method_call_site_module_id".into(),
            method_call_site_module_id.as_entire_binding(),
        );
        resources.insert(
            "name_id_by_token".into(),
            name_id_by_token.as_entire_binding(),
        );
        resources.insert(
            "language_name_id".into(),
            language_name_id.as_entire_binding(),
        );
        resources.insert(
            "language_decl_symbol_slot".into(),
            language_decl_symbol_slot.as_entire_binding(),
        );
        resources.insert(
            "language_decl_kind".into(),
            language_decl_kind.as_entire_binding(),
        );
        resources.insert(
            "language_decl_tag".into(),
            language_decl_tag.as_entire_binding(),
        );
        resources.insert(
            "language_decl_name_id".into(),
            language_decl_name_id.as_entire_binding(),
        );
        resources.insert(
            "language_symbol_bytes".into(),
            language_symbol_bytes.as_entire_binding(),
        );
        resources.insert(
            "language_symbol_start".into(),
            language_symbol_start.as_entire_binding(),
        );
        resources.insert(
            "language_symbol_len".into(),
            language_symbol_len.as_entire_binding(),
        );
        resources.insert(
            "type_expr_ref_tag".into(),
            type_expr_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "type_expr_ref_payload".into(),
            type_expr_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "type_instance_kind".into(),
            type_instance_kind.as_entire_binding(),
        );
        resources.insert(
            "type_instance_head_token".into(),
            type_instance_head_token.as_entire_binding(),
        );
        resources.insert(
            "type_decl_generic_param_count".into(),
            type_decl_generic_param_count.as_entire_binding(),
        );
        resources.insert(
            "type_instance_decl_token".into(),
            type_instance_decl_token.as_entire_binding(),
        );
        resources.insert(
            "type_instance_arg_start".into(),
            type_instance_arg_start.as_entire_binding(),
        );
        resources.insert(
            "type_instance_arg_count".into(),
            type_instance_arg_count.as_entire_binding(),
        );
        resources.insert(
            "type_instance_arg_ref_tag".into(),
            type_instance_arg_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "type_instance_arg_ref_payload".into(),
            type_instance_arg_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "type_instance_elem_ref_tag".into(),
            type_instance_elem_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "type_instance_elem_ref_payload".into(),
            type_instance_elem_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "type_instance_len_kind".into(),
            type_instance_len_kind.as_entire_binding(),
        );
        resources.insert(
            "type_instance_len_payload".into(),
            type_instance_len_payload.as_entire_binding(),
        );
        resources.insert(
            "type_instance_state".into(),
            type_instance_state.as_entire_binding(),
        );
        resources.insert(
            "fn_return_ref_tag".into(),
            fn_return_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "fn_return_ref_payload".into(),
            fn_return_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "decl_type_ref_tag".into(),
            decl_type_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "decl_type_ref_payload".into(),
            decl_type_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "member_result_context_instance".into(),
            member_result_context_instance.as_entire_binding(),
        );
        resources.insert(
            "member_result_ref_tag".into(),
            member_result_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "member_result_ref_payload".into(),
            member_result_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "member_result_field_ordinal".into(),
            member_result_field_ordinal.as_entire_binding(),
        );
        resources.insert(
            "struct_init_field_expected_ref_tag".into(),
            struct_init_field_expected_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "struct_init_field_expected_ref_payload".into(),
            struct_init_field_expected_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "struct_init_field_context_instance".into(),
            struct_init_field_context_instance.as_entire_binding(),
        );
        resources.insert(
            "struct_init_field_ordinal".into(),
            struct_init_field_ordinal.as_entire_binding(),
        );
        let type_instances_clear = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_clear"),
            &passes.type_instances_clear.bind_group_layouts[0],
            &passes.type_instances_clear.reflection,
            0,
            &resources,
        )?;
        let type_instances_decl_generic_params = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_decl_generic_params"),
            &passes.type_instances_decl_generic_params.bind_group_layouts[0],
            &passes.type_instances_decl_generic_params.reflection,
            0,
            &resources,
        )?;
        let type_instances_collect = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_collect"),
            &passes.type_instances_collect.bind_group_layouts[0],
            &passes.type_instances_collect.reflection,
            0,
            &resources,
        )?;
        let type_instances_collect_named = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_collect_named"),
            &passes.type_instances_collect_named.bind_group_layouts[0],
            &passes.type_instances_collect_named.reflection,
            0,
            &resources,
        )?;
        let type_instances_collect_aggregate_refs = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_collect_aggregate_refs"),
            &passes
                .type_instances_collect_aggregate_refs
                .bind_group_layouts[0],
            &passes.type_instances_collect_aggregate_refs.reflection,
            0,
            &resources,
        )?;
        let type_instances_collect_aggregate_details =
            bind_group::create_bind_group_from_reflection(
                device,
                Some("type_check_resident_type_instances_collect_aggregate_details"),
                &passes
                    .type_instances_collect_aggregate_details
                    .bind_group_layouts[0],
                &passes.type_instances_collect_aggregate_details.reflection,
                0,
                &resources,
            )?;
        let type_instances_collect_named_arg_refs = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_collect_named_arg_refs"),
            &passes
                .type_instances_collect_named_arg_refs
                .bind_group_layouts[0],
            &passes.type_instances_collect_named_arg_refs.reflection,
            0,
            &resources,
        )?;
        let type_instances_decl_refs = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_decl_refs"),
            &passes.type_instances_decl_refs.bind_group_layouts[0],
            &passes.type_instances_decl_refs.reflection,
            0,
            &resources,
        )?;
        let type_instances_member_receivers = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_member_receivers"),
            &passes.type_instances_member_receivers.bind_group_layouts[0],
            &passes.type_instances_member_receivers.reflection,
            0,
            &resources,
        )?;
        let type_instances_member_results = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_member_results"),
            &passes.type_instances_member_results.bind_group_layouts[0],
            &passes.type_instances_member_results.reflection,
            0,
            &resources,
        )?;
        let type_instances_member_substitute = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_member_substitute"),
            &passes.type_instances_member_substitute.bind_group_layouts[0],
            &passes.type_instances_member_substitute.reflection,
            0,
            &resources,
        )?;
        let type_instances_struct_init_clear = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_struct_init_clear"),
            &passes.type_instances_struct_init_clear.bind_group_layouts[0],
            &passes.type_instances_struct_init_clear.reflection,
            0,
            &resources,
        )?;
        let type_instances_struct_init_fields = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_struct_init_fields"),
            &passes.type_instances_struct_init_fields.bind_group_layouts[0],
            &passes.type_instances_struct_init_fields.reflection,
            0,
            &resources,
        )?;
        let type_instances_struct_init_substitute = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_struct_init_substitute"),
            &passes
                .type_instances_struct_init_substitute
                .bind_group_layouts[0],
            &passes.type_instances_struct_init_substitute.reflection,
            0,
            &resources,
        )?;
        let type_instances_array_return_refs = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_array_return_refs"),
            &passes.type_instances_array_return_refs.bind_group_layouts[0],
            &passes.type_instances_array_return_refs.reflection,
            0,
            &resources,
        )?;
        let type_instances_array_literal_return_refs =
            bind_group::create_bind_group_from_reflection(
                device,
                Some("type_check_resident_type_instances_array_literal_return_refs"),
                &passes
                    .type_instances_array_literal_return_refs
                    .bind_group_layouts[0],
                &passes.type_instances_array_literal_return_refs.reflection,
                0,
                &resources,
            )?;
        let type_instances_enum_ctors = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_enum_ctors"),
            &passes.type_instances_enum_ctors.bind_group_layouts[0],
            &passes.type_instances_enum_ctors.reflection,
            0,
            &resources,
        )?;
        let type_instances_array_index_results = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_array_index_results"),
            &passes.type_instances_array_index_results.bind_group_layouts[0],
            &passes.type_instances_array_index_results.reflection,
            0,
            &resources,
        )?;
        let type_instances_validate_aggregate_access =
            bind_group::create_bind_group_from_reflection(
                device,
                Some("type_check_resident_type_instances_validate_aggregate_access"),
                &passes
                    .type_instances_validate_aggregate_access
                    .bind_group_layouts[0],
                &passes.type_instances_validate_aggregate_access.reflection,
                0,
                &resources,
            )?;
        let conditions_hir = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_conditions_hir"),
            &passes.conditions_hir.bind_group_layouts[0],
            &passes.conditions_hir.reflection,
            0,
            &resources,
        )?;
        let calls_clear = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_clear"),
            &passes.calls_clear.bind_group_layouts[0],
            &passes.calls_clear.reflection,
            0,
            &resources,
        )?;
        let calls_return_refs = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_return_refs"),
            &passes.calls_return_refs.bind_group_layouts[0],
            &passes.calls_return_refs.reflection,
            0,
            &resources,
        )?;
        let calls_entrypoints = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_entrypoints"),
            &passes.calls_entrypoints.bind_group_layouts[0],
            &passes.calls_entrypoints.reflection,
            0,
            &resources,
        )?;
        let calls_functions = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_functions"),
            &passes.calls_functions.bind_group_layouts[0],
            &passes.calls_functions.reflection,
            0,
            &resources,
        )?;
        let calls_param_types = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_param_types"),
            &passes.calls_param_types.bind_group_layouts[0],
            &passes.calls_param_types.reflection,
            0,
            &resources,
        )?;
        let calls_intrinsics = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_intrinsics"),
            &passes.calls_intrinsics.bind_group_layouts[0],
            &passes.calls_intrinsics.reflection,
            0,
            &resources,
        )?;
        let calls_clear_hir_call_args = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_clear_hir_call_args"),
            &passes.calls_clear_hir_call_args.bind_group_layouts[0],
            &passes.calls_clear_hir_call_args.reflection,
            0,
            &resources,
        )?;
        let calls_pack_hir_call_args = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_pack_hir_call_args"),
            &passes.calls_pack_hir_call_args.bind_group_layouts[0],
            &passes.calls_pack_hir_call_args.reflection,
            0,
            &resources,
        )?;
        let calls_resolve = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_resolve"),
            &passes.calls_resolve.bind_group_layouts[0],
            &passes.calls_resolve.reflection,
            0,
            &resources,
        )?;
        let calls_erase_generic_params = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_erase_generic_params"),
            &passes.calls_erase_generic_params.bind_group_layouts[0],
            &passes.calls_erase_generic_params.reflection,
            0,
            &resources,
        )?;
        let calls = CallBindGroups {
            clear: calls_clear,
            return_refs: calls_return_refs,
            entrypoints: calls_entrypoints,
            functions: calls_functions,
            param_types: calls_param_types,
            intrinsics: calls_intrinsics,
            clear_hir_call_args: calls_clear_hir_call_args,
            pack_hir_call_args: calls_pack_hir_call_args,
            resolve: calls_resolve,
            erase_generic_params: calls_erase_generic_params,
        };
        let language_names_clear = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_language_names_clear"),
            &passes.language_names_clear.bind_group_layouts[0],
            &passes.language_names_clear.reflection,
            0,
            &resources,
        )?;
        let language_names_mark = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_language_names_mark"),
            &passes.language_names_mark.bind_group_layouts[0],
            &passes.language_names_mark.reflection,
            0,
            &resources,
        )?;
        let language_decls_materialize = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_language_decls_materialize"),
            &passes.language_decls_materialize.bind_group_layouts[0],
            &passes.language_decls_materialize.reflection,
            0,
            &resources,
        )?;
        let language_name_bind_groups = LanguageNameBindGroups {
            clear: language_names_clear,
            mark: language_names_mark,
            decls_materialize: language_decls_materialize,
        };
        let name_bind_groups = create_name_bind_groups_with_passes(
            passes,
            device,
            &self.params_buf,
            source_len,
            name_capacity,
            token_scan_n_blocks,
            name_n_blocks,
            &name_scan_steps,
            token_buf,
            token_count_buf,
            source_buf,
            &self.status_buf,
            &name_lexeme_flag,
            &name_lexeme_kind,
            &name_lexeme_prefix,
            &name_scan_local_prefix,
            &name_scan_block_sum,
            &name_scan_prefix_a,
            &name_scan_prefix_b,
            &name_scan_total,
            &name_spans,
            &name_order_in,
            &name_order_tmp,
            &language_symbol_bytes,
            &language_symbol_start,
            &language_symbol_len,
            &name_id_by_token,
            &language_name_id,
            &radix_block_histogram,
            &radix_block_bucket_prefix,
            &radix_bucket_total,
            &radix_bucket_base,
            &run_head_mask,
            &adjacent_equal_mask,
            &run_head_prefix,
            &sorted_name_id,
            &name_id_by_input,
            &unique_name_count,
        )?;
        let module_path = if let Some(hir_items) = hir_items {
            Some(create_module_path_state_with_passes(
                passes,
                device,
                &self.params_buf,
                token_capacity,
                hir_node_capacity,
                token_buf,
                token_count_buf,
                hir_status_buf,
                hir_kind_buf,
                hir_token_pos_buf,
                hir_token_end_buf,
                &self.status_buf,
                hir_items,
                &name_id_by_token,
                &language_name_id,
                &module_type_path_type,
                &module_type_path_status,
                &module_value_path_expr_head,
                &module_value_path_call_head,
                &module_value_path_call_open,
                &module_value_path_const_head,
                &module_value_path_const_end,
                &module_value_path_status,
                &visible_decl,
                &visible_type,
                &call_fn_index,
                &call_return_type,
                &call_return_type_token,
                &call_param_count,
                &call_param_type,
                &call_arg_record,
                &type_expr_ref_tag,
                &type_expr_ref_payload,
                &type_instance_kind,
                &type_instance_decl_token,
                &type_instance_arg_start,
                &type_instance_arg_count,
                &type_instance_arg_ref_tag,
                &type_instance_arg_ref_payload,
                &type_decl_generic_param_count,
                &type_instance_state,
            )?)
        } else {
            None
        };
        let method_module_id_by_file_id = module_path
            .as_ref()
            .map(|module_path| &module_path.module_id_by_file_id)
            .unwrap_or(&method_module_id_by_file_id_implicit_root);
        let method_module_count_out = module_path
            .as_ref()
            .map(|module_path| &module_path.module_count_out)
            .unwrap_or(&method_module_count_out_implicit_root);
        resources.insert(
            "module_id_by_file_id".into(),
            method_module_id_by_file_id.as_entire_binding(),
        );
        resources.insert(
            "module_count_out".into(),
            method_module_count_out.as_entire_binding(),
        );

        let methods_clear = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_methods_clear"),
            &passes.methods_clear.bind_group_layouts[0],
            &passes.methods_clear.reflection,
            0,
            &resources,
        )?;
        let methods_collect = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_methods_collect"),
            &passes.methods_collect.bind_group_layouts[0],
            &passes.methods_collect.reflection,
            0,
            &resources,
        )?;
        let methods_attach_metadata = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_methods_attach_metadata"),
            &passes.methods_attach_metadata.bind_group_layouts[0],
            &passes.methods_attach_metadata.reflection,
            0,
            &resources,
        )?;
        let methods_bind_self_receivers = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_methods_bind_self_receivers"),
            &passes.methods_bind_self_receivers.bind_group_layouts[0],
            &passes.methods_bind_self_receivers.reflection,
            0,
            &resources,
        )?;
        let method_key_bind_groups = create_method_key_bind_groups_with_passes(
            device,
            "type_check_resident_methods",
            &passes.methods_seed_key_order,
            &passes.methods_sort_keys,
            &passes.names_radix_bucket_prefix,
            &passes.names_radix_bucket_bases,
            &passes.methods_sort_keys_scatter,
            &passes.methods_validate_keys,
            token_capacity,
            name_n_blocks,
            method_module_count_out,
            &method_decl_impl_node,
            &method_decl_receiver_ref_tag,
            &method_decl_receiver_ref_payload,
            &method_decl_module_id,
            &method_decl_name_token,
            &method_decl_name_id,
            &method_decl_visibility,
            &module_type_path_type,
            &type_instance_decl_token,
            &method_key_to_fn_token,
            &method_key_order_tmp,
            &method_key_status,
            &method_key_duplicate_of,
            &method_key_radix_block_histogram,
            &method_key_radix_block_bucket_prefix,
            &method_key_radix_bucket_total,
            &method_key_radix_bucket_base,
            &self.status_buf,
        )?;
        let methods_mark_call_keys = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_methods_mark_call_keys"),
            &passes.methods_mark_call_keys.bind_group_layouts[0],
            &passes.methods_mark_call_keys.reflection,
            0,
            &resources,
        )?;
        let methods_mark_call_return_keys = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_methods_mark_call_return_keys"),
            &passes.methods_mark_call_return_keys.bind_group_layouts[0],
            &passes.methods_mark_call_return_keys.reflection,
            0,
            &resources,
        )?;
        let methods_resolve_table = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_methods_resolve_table"),
            &passes.methods_resolve_table.bind_group_layouts[0],
            &passes.methods_resolve_table.reflection,
            0,
            &resources,
        )?;
        let methods_resolve = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_methods_resolve"),
            &passes.methods_resolve.bind_group_layouts[0],
            &passes.methods_resolve.reflection,
            0,
            &resources,
        )?;
        let methods = MethodBindGroups {
            clear: methods_clear,
            collect: methods_collect,
            attach_metadata: methods_attach_metadata,
            bind_self_receivers: methods_bind_self_receivers,
            keys: method_key_bind_groups,
            mark_call_keys: methods_mark_call_keys,
            mark_call_return_keys: methods_mark_call_return_keys,
            resolve_table: methods_resolve_table,
            resolve: methods_resolve,
        };

        let tokens = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_tokens"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )?;
        let control = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_control"),
            &control_pass.bind_group_layouts[0],
            &control_pass.reflection,
            0,
            &resources,
        )?;
        let scope = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_scope"),
            &scope_pass.bind_group_layouts[0],
            &scope_pass.reflection,
            0,
            &resources,
        )?;
        let loop_bind_groups = create_loop_depth_bind_groups_with_passes(
            passes,
            device,
            &loop_params,
            &loop_scan_steps,
            token_buf,
            token_count_buf,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_status_buf,
            &loop_delta,
            &loop_depth_inblock,
            &loop_block_sum,
            &loop_prefix_a,
            &loop_prefix_b,
            &loop_block_prefix,
            &loop_depth,
        )?;
        let fn_context_bind_groups = create_fn_context_bind_groups_with_passes(
            passes,
            device,
            &fn_params,
            &fn_scan_steps,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_status_buf,
            &enclosing_fn,
            &enclosing_fn_end,
            &fn_event_value,
            &fn_event_end,
            &fn_event_index,
            &fn_event_inblock,
            &fn_block_sum,
            &fn_prefix_a,
            &fn_prefix_b,
            &fn_block_prefix,
        )?;
        let visible_bind_groups =
            create_visible_bind_groups_with_passes(passes, device, &resources)?;
        drop(resources);

        Ok(ResidentTypeCheckBindGroups {
            source_len,
            token_capacity,
            hir_node_capacity,
            input_fingerprint,
            uses_hir_control,
            uses_hir_items,
            name_capacity,
            name_n_blocks,
            loop_n_blocks,
            fn_n_blocks,
            name_lexeme_flag,
            name_lexeme_kind,
            name_lexeme_prefix,
            name_scan_local_prefix,
            name_scan_block_sum,
            name_scan_prefix_a,
            name_scan_prefix_b,
            name_scan_total,
            name_spans,
            name_order_in,
            name_order_tmp,
            name_id_by_token,
            language_name_id,
            language_decl_symbol_slot,
            language_decl_kind,
            language_decl_tag,
            language_decl_name_id,
            radix_block_histogram,
            radix_block_bucket_prefix,
            radix_bucket_total,
            radix_bucket_base,
            run_head_mask,
            adjacent_equal_mask,
            run_head_prefix,
            sorted_name_id,
            name_id_by_input,
            unique_name_count,
            module_path,
            method_module_id_by_file_id_implicit_root,
            module_type_path_type,
            module_type_path_status,
            module_value_path_expr_head,
            module_value_path_call_head,
            module_value_path_call_open,
            module_value_path_const_head,
            module_value_path_const_end,
            module_value_path_status,
            visible_decl,
            visible_type,
            scope_end,
            loop_delta,
            loop_depth_inblock,
            loop_block_sum,
            loop_prefix_a,
            loop_prefix_b,
            loop_block_prefix,
            loop_depth,
            enclosing_fn,
            enclosing_fn_end,
            fn_event_value,
            fn_event_end,
            fn_event_index,
            fn_event_inblock,
            fn_block_sum,
            fn_prefix_a,
            fn_prefix_b,
            fn_block_prefix,
            call_fn_index,
            call_intrinsic_tag,
            fn_entrypoint_tag,
            call_return_type,
            call_return_type_token,
            call_param_count,
            call_param_type,
            call_arg_record,
            function_lookup_key,
            function_lookup_fn,
            method_decl_receiver_ref_tag,
            method_decl_receiver_ref_payload,
            method_decl_module_id,
            method_decl_impl_node,
            method_decl_name_token,
            method_decl_name_id,
            method_decl_param_offset,
            method_decl_receiver_mode,
            method_decl_visibility,
            method_module_count_out_implicit_root,
            method_key_to_fn_token,
            method_key_order_tmp,
            method_key_status,
            method_key_duplicate_of,
            method_key_radix_block_histogram,
            method_key_radix_block_bucket_prefix,
            method_key_radix_bucket_total,
            method_key_radix_bucket_base,
            method_call_receiver_ref_tag,
            method_call_receiver_ref_payload,
            method_call_name_id,
            method_call_site_module_id,
            type_expr_ref_tag,
            type_expr_ref_payload,
            type_instance_kind,
            type_instance_head_token,
            type_decl_generic_param_count,
            type_instance_decl_token,
            type_instance_arg_start,
            type_instance_arg_count,
            type_instance_arg_ref_tag,
            type_instance_arg_ref_payload,
            type_instance_elem_ref_tag,
            type_instance_elem_ref_payload,
            type_instance_len_kind,
            type_instance_len_payload,
            type_instance_state,
            fn_return_ref_tag,
            fn_return_ref_payload,
            decl_type_ref_tag,
            decl_type_ref_payload,
            member_result_context_instance,
            member_result_ref_tag,
            member_result_ref_payload,
            member_result_field_ordinal,
            struct_init_field_expected_ref_tag,
            struct_init_field_expected_ref_payload,
            struct_init_field_context_instance,
            struct_init_field_ordinal,
            name_scan_steps,
            name_bind_groups,
            language_name_bind_groups,
            loop_params,
            loop_scan_steps,
            fn_params,
            fn_scan_steps,
            loop_bind_groups,
            fn_context_bind_groups,
            visible_bind_groups,
            calls,
            methods,
            type_instances_clear,
            type_instances_decl_generic_params,
            type_instances_collect,
            type_instances_collect_named,
            type_instances_collect_aggregate_refs,
            type_instances_collect_aggregate_details,
            type_instances_collect_named_arg_refs,
            type_instances_decl_refs,
            type_instances_member_receivers,
            type_instances_member_results,
            type_instances_member_substitute,
            type_instances_struct_init_clear,
            type_instances_struct_init_fields,
            type_instances_struct_init_substitute,
            type_instances_array_return_refs,
            type_instances_array_literal_return_refs,
            type_instances_enum_ctors,
            type_instances_array_index_results,
            type_instances_validate_aggregate_access,
            conditions_hir,
            tokens,
            control,
            scope,
        })
    }
}
