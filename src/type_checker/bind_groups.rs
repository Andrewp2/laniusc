use super::*;

impl GpuTypeChecker {
    #[allow(clippy::too_many_arguments)]
    pub(super) fn create_bind_groups(
        &self,
        device: &wgpu::Device,
        source_len: u32,
        source_file_capacity: u32,
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
        external_scratch: Option<GpuTypeCheckExternalScratchBuffers<'_>>,
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
        let name_capacity = token_capacity.saturating_add(LANGUAGE_SYMBOL_COUNT).max(1);
        let token_scan_n_blocks = token_capacity.div_ceil(256).max(1);
        let name_n_blocks = name_capacity.div_ceil(256).max(1);
        let hir_value_decl_name_present = storage_u32_rw(
            device,
            "type_check.resident.hir_value_decl_name_present",
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
        let hir_visible_decl_count_out = storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_owner_fn = storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_owner_fn",
            hir_visible_decl_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_name_id = storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_name_id",
            hir_visible_decl_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_token = storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_token",
            hir_visible_decl_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_scope_end = storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_scope_end",
            hir_visible_decl_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_key_order = storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_order",
            hir_visible_decl_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_key_order_tmp = storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_order_tmp",
            hir_visible_decl_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_key_radix_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let hir_visible_decl_key_radix_histogram_len =
            (hir_decl_record_n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
        let hir_visible_decl_key_radix_block_histogram = storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_radix_block_histogram",
            hir_visible_decl_key_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_key_radix_block_bucket_prefix = storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_radix_block_bucket_prefix",
            hir_visible_decl_key_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_key_radix_bucket_total = storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_radix_bucket_total",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_key_radix_bucket_base = storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_radix_bucket_base",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_scope_tree = storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_scope_tree",
            hir_decl_tree_len,
            wgpu::BufferUsages::empty(),
        );
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
            name_capacity as usize,
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
        let name_max_len = storage_u32_rw(
            device,
            "type_check.resident.name_max_len",
            1,
            wgpu::BufferUsages::COPY_DST,
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
        let language_type_code_by_name_id = storage_u32_rw(
            device,
            "type_check.resident.language_type_code_by_name_id",
            name_capacity as usize,
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
        let radix_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.radix_dispatch_args",
            (1 + 3 * NAME_RADIX_MAX_BYTES as usize) * 3,
            wgpu::BufferUsages::INDIRECT,
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
        let fn_entrypoint_tag_len = token_capacity.max(hir_node_capacity) as usize;
        let fn_entrypoint_tag = if let Some(scratch) = external_scratch
            .map(|scratch| scratch.fn_entrypoint_tag)
            .filter(|buffer| buffer.size() >= (fn_entrypoint_tag_len.max(1) * 4) as u64)
        {
            alias_storage_buffer(scratch)
        } else {
            storage_u32_rw(
                device,
                "type_check.resident.fn_entrypoint_tag",
                fn_entrypoint_tag_len,
                wgpu::BufferUsages::empty(),
            )
        };
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
        let scratch_or_storage_u32 =
            |label: &str, count: usize, scratch: Option<&wgpu::Buffer>| -> wgpu::Buffer {
                if let Some(buffer) =
                    scratch.filter(|buffer| buffer.size() >= (count.max(1) * 4) as u64)
                {
                    alias_storage_buffer(buffer)
                } else {
                    storage_u32_rw(device, label, count, wgpu::BufferUsages::empty())
                }
            };
        let call_param_count = scratch_or_storage_u32(
            "type_check.resident.call_param_count",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.call_param_count),
        );
        let call_param_type = scratch_or_storage_u32(
            "type_check.resident.call_param_type",
            (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
            external_scratch.map(|scratch| scratch.call_param_type),
        );
        let call_param_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.call_param_ref_tag",
            (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
            wgpu::BufferUsages::empty(),
        );
        let call_param_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.call_param_ref_payload",
            (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_record = scratch_or_storage_u32(
            "type_check.resident.call_arg_record",
            (token_capacity as usize).max(1) * 4,
            external_scratch.map(|scratch| scratch.call_arg_record),
        );
        // Resident consumers use parser-owned HIR argument records directly;
        // keep this as a one-word compatibility buffer for old resource maps.
        let call_arg_node = storage_u32_rw(
            device,
            "type_check.resident.call_arg_node",
            call_arg_node_capacity_words(),
            wgpu::BufferUsages::empty(),
        );
        let function_lookup_capacity = token_capacity.saturating_mul(2).max(1) as usize;
        let function_lookup_key = scratch_or_storage_u32(
            "type_check.resident.function_lookup_key",
            function_lookup_capacity,
            external_scratch.map(|scratch| scratch.function_lookup_key),
        );
        let function_lookup_fn = scratch_or_storage_u32(
            "type_check.resident.function_lookup_fn",
            function_lookup_capacity,
            external_scratch.map(|scratch| scratch.function_lookup_fn),
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
        let method_decl_module_id = scratch_or_storage_u32(
            "type_check.resident.method_decl_module_id",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_module_id),
        );
        let method_decl_impl_node = scratch_or_storage_u32(
            "type_check.resident.method_decl_impl_node",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_impl_node),
        );
        let method_decl_name_token = scratch_or_storage_u32(
            "type_check.resident.method_decl_name_token",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_name_token),
        );
        let method_decl_name_id = scratch_or_storage_u32(
            "type_check.resident.method_decl_name_id",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_name_id),
        );
        let method_decl_param_offset = scratch_or_storage_u32(
            "type_check.resident.method_decl_param_offset",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_param_offset),
        );
        let method_decl_receiver_mode = scratch_or_storage_u32(
            "type_check.resident.method_decl_receiver_mode",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_receiver_mode),
        );
        let method_decl_visibility = scratch_or_storage_u32(
            "type_check.resident.method_decl_visibility",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_visibility),
        );
        let method_module_id_by_file_id_implicit_root = storage_u32_fill_rw(
            device,
            "type_check.resident.method_module_id_by_file_id_implicit_root",
            source_file_capacity.max(1) as usize,
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
        let method_key_to_fn_token = scratch_or_storage_u32(
            "type_check.resident.method_key_to_fn_token",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_key_to_fn_token),
        );
        // Method key sorting starts after call resolution has consumed the
        // function lookup table, so reuse the two lookup rows as method-key
        // scratch instead of keeping additional token-sized buffers resident.
        let method_key_order_tmp = alias_storage_buffer(&function_lookup_key);
        let method_key_status = scratch_or_storage_u32(
            "type_check.resident.method_key_status",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_key_status),
        );
        let method_key_duplicate_of = alias_storage_buffer(&function_lookup_fn);
        let method_key_radix_histogram_len =
            (name_n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
        let method_key_radix_block_histogram = scratch_or_storage_u32(
            "type_check.resident.method_key_radix_block_histogram",
            method_key_radix_histogram_len,
            external_scratch.map(|scratch| scratch.method_key_radix_block_histogram),
        );
        let method_key_radix_block_bucket_prefix = scratch_or_storage_u32(
            "type_check.resident.method_key_radix_block_bucket_prefix",
            method_key_radix_histogram_len,
            external_scratch.map(|scratch| scratch.method_key_radix_block_bucket_prefix),
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
        let method_call_receiver_ref_tag = scratch_or_storage_u32(
            "type_check.resident.method_call_receiver_ref_tag",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_call_receiver_ref_tag),
        );
        let method_call_receiver_ref_payload = scratch_or_storage_u32(
            "type_check.resident.method_call_receiver_ref_payload",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_call_receiver_ref_payload),
        );
        let method_call_name_id = scratch_or_storage_u32(
            "type_check.resident.method_call_name_id",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_call_name_id),
        );
        let method_call_site_module_id = scratch_or_storage_u32(
            "type_check.resident.method_call_site_module_id",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_call_site_module_id),
        );
        let type_expr_ref_tag = scratch_or_storage_u32(
            "type_check.resident.type_expr_ref_tag",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_expr_ref_tag),
        );
        let type_expr_ref_payload = scratch_or_storage_u32(
            "type_check.resident.type_expr_ref_payload",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_expr_ref_payload),
        );
        // Type-instance rows are populated after the name-radix pipeline and
        // remain live for later typecheck/codegen consumers. Reuse name scratch
        // that is not retained as module-path declaration metadata.
        let type_instance_kind = alias_storage_buffer(&name_scan_local_prefix);
        let type_instance_head_token = scratch_or_storage_u32(
            "type_check.resident.type_instance_head_token",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_head_token),
        );
        let type_decl_generic_param_count = scratch_or_storage_u32(
            "type_check.resident.type_decl_generic_param_count",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_decl_generic_param_count),
        );
        let type_decl_generic_param_count_by_node = if let Some(scratch) = external_scratch {
            // Type-instance generic-param counts are HIR-keyed scratch. Parser
            // HIR type workspaces are dead after parser HIR construction and
            // are not part of the typecheck input surface consumed here.
            alias_storage_buffer(scratch.type_decl_generic_param_count_by_node)
        } else {
            storage_u32_rw(
                device,
                "type_check.resident.type_decl_generic_param_count_by_node",
                hir_node_capacity as usize,
                wgpu::BufferUsages::empty(),
            )
        };
        // Const-generic declaration counts are consumed before the calls
        // pipeline clears and publishes function entrypoint tags.
        let type_decl_const_param_count_by_node = alias_storage_buffer(&fn_entrypoint_tag);
        let type_decl_hir_node_by_token = alias_storage_buffer(&name_spans);
        let type_generic_param_slot_by_token = scratch_or_storage_u32(
            "type_check.resident.type_generic_param_slot_by_token",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_generic_param_slot_by_token),
        );
        let type_const_param_slot_by_token = scratch_or_storage_u32(
            "type_check.resident.type_const_param_slot_by_token",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_const_param_slot_by_token),
        );
        let type_instance_decl_token = alias_storage_buffer(&radix_block_histogram);
        let type_instance_arg_start = scratch_or_storage_u32(
            "type_check.resident.type_instance_arg_start",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_arg_start),
        );
        let type_instance_arg_count = scratch_or_storage_u32(
            "type_check.resident.type_instance_arg_count",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_arg_count),
        );
        let type_instance_arg_ref_tag = if let Some(scratch) = external_scratch {
            // Token-strided type-instance argument tags are rebuilt by
            // typecheck. Parser list-rank scratch is dead after HIR list
            // construction and has resident tree capacity.
            alias_storage_buffer(scratch.type_instance_arg_ref_tag)
        } else {
            storage_u32_rw(
                device,
                "type_check.resident.type_instance_arg_ref_tag",
                (token_capacity as usize).max(1) * TYPE_INSTANCE_ARG_REF_STRIDE,
                wgpu::BufferUsages::empty(),
            )
        };
        let type_instance_arg_ref_payload = if let Some(scratch) = external_scratch {
            // The parser list1 workspace is dead after HIR list construction.
            // Reuse that tree-capacity row for token-keyed type-instance
            // argument payloads; resident projected tree capacity is larger
            // than the fixed four-argument-per-token table used here.
            alias_storage_buffer(scratch.type_instance_arg_ref_payload)
        } else {
            storage_u32_rw(
                device,
                "type_check.resident.type_instance_arg_ref_payload",
                (token_capacity as usize).max(1) * TYPE_INSTANCE_ARG_REF_STRIDE,
                wgpu::BufferUsages::empty(),
            )
        };
        let type_instance_elem_ref_tag = scratch_or_storage_u32(
            "type_check.resident.type_instance_elem_ref_tag",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_elem_ref_tag),
        );
        let type_instance_elem_ref_payload = scratch_or_storage_u32(
            "type_check.resident.type_instance_elem_ref_payload",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_elem_ref_payload),
        );
        let type_instance_len_kind = scratch_or_storage_u32(
            "type_check.resident.type_instance_len_kind",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_len_kind),
        );
        let type_instance_len_payload = scratch_or_storage_u32(
            "type_check.resident.type_instance_len_payload",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_len_payload),
        );
        let type_instance_state = scratch_or_storage_u32(
            "type_check.resident.type_instance_state",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_state),
        );
        let predicate_capacity = hir_node_capacity.max(1) as usize;
        let predicate_owner_node = storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_owner_node",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_subject_token = storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_subject_token",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_bound_token = storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_bound_token",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_bound_arg_count = storage_u32_rw(
            device,
            "type_check.resident.predicate_bound_arg_count",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_bound_first_arg_token = storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_bound_first_arg_token",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_bound_second_arg_token = storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_bound_second_arg_token",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_status = storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_status",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        // Function return refs are populated after the name-radix pipeline has
        // assigned stable name ids. Reuse dead name-dedup scratch for these
        // token-indexed rows rather than borrowing parser rows that later
        // typecheck passes may still consume.
        let fn_return_ref_tag = alias_storage_buffer(&run_head_mask);
        let fn_return_ref_payload = alias_storage_buffer(&adjacent_equal_mask);
        let decl_type_ref_tag = alias_storage_buffer(&radix_block_bucket_prefix);
        let decl_type_ref_payload = alias_storage_buffer(&run_head_prefix);
        let member_result_context_instance = alias_storage_buffer(&sorted_name_id);
        let member_result_ref_tag = alias_storage_buffer(&name_id_by_input);
        let member_result_ref_payload = scratch_or_storage_u32(
            "type_check.resident.member_result_ref_payload",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.member_result_ref_payload),
        );
        let member_result_field_ordinal = scratch_or_storage_u32(
            "type_check.resident.member_result_field_ordinal",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.member_result_field_ordinal),
        );
        let struct_init_field_expected_ref_tag = scratch_or_storage_u32(
            "type_check.resident.struct_init_field_expected_ref_tag",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.struct_init_field_expected_ref_tag),
        );
        let struct_init_field_expected_ref_payload = scratch_or_storage_u32(
            "type_check.resident.struct_init_field_expected_ref_payload",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.struct_init_field_expected_ref_payload),
        );
        let struct_init_field_context_instance = scratch_or_storage_u32(
            "type_check.resident.struct_init_field_context_instance",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.struct_init_field_context_instance),
        );
        let struct_init_field_ordinal = scratch_or_storage_u32(
            "type_check.resident.struct_init_field_ordinal",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.struct_init_field_ordinal),
        );
        let struct_init_field_ordinal_by_node = if let Some(scratch) = external_scratch {
            // Parser list-workspace scratch is dead once HIR records have been
            // constructed. Reuse it for the HIR-keyed struct-init ordinal table
            // and, earlier, for module/path record-family flags.
            alias_storage_buffer(scratch.record_family_flag)
        } else {
            storage_u32_rw(
                device,
                "type_check.resident.struct_init_field_ordinal_by_node",
                hir_node_capacity.max(1) as usize,
                wgpu::BufferUsages::empty(),
            )
        };
        let token_active_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.token_active_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let hir_active_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.hir_active_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let token_hir_active_dispatch_args = storage_u32_rw(
            device,
            "type_check.resident.token_hir_active_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let hir_active_count = storage_u32_rw(
            device,
            "type_check.resident.hir_active_count",
            1,
            wgpu::BufferUsages::empty(),
        );
        let empty_hir_len = if uses_hir_items {
            1
        } else {
            hir_node_capacity.max(1) as usize
        };
        let invalid_node = vec![u32::MAX; empty_hir_len];
        let zero_node = vec![0u32; empty_hir_len];
        let identity_node: Vec<u32> = if uses_hir_items {
            vec![0]
        } else {
            (0..empty_hir_len as u32).collect()
        };
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
        let hir_semantic_dense_node_identity = storage_ro_from_u32s(
            device,
            "type_check.resident.hir_semantic_dense_node.identity",
            &identity_node,
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
        resources.insert(
            "token_active_dispatch_args".into(),
            token_active_dispatch_args.as_entire_binding(),
        );
        resources.insert(
            "hir_active_dispatch_args".into(),
            hir_active_dispatch_args.as_entire_binding(),
        );
        resources.insert(
            "token_hir_active_dispatch_args".into(),
            token_hir_active_dispatch_args.as_entire_binding(),
        );
        resources.insert(
            "hir_active_count".into(),
            hir_active_count.as_entire_binding(),
        );
        if let Some(hir_items) = hir_items {
            resources.insert("node_kind".into(), hir_items.node_kind.as_entire_binding());
            resources.insert("parent".into(), hir_items.parent.as_entire_binding());
            resources.insert("parent_record".into(), hir_items.parent.as_entire_binding());
            resources.insert(
                "first_child".into(),
                hir_items.first_child.as_entire_binding(),
            );
            resources.insert(
                "next_sibling".into(),
                hir_items.next_sibling.as_entire_binding(),
            );
            resources.insert(
                "subtree_end".into(),
                hir_items.subtree_end.as_entire_binding(),
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
                "hir_type_path_leaf_node".into(),
                hir_items.type_path_leaf_node.as_entire_binding(),
            );
            resources.insert(
                "hir_type_arg_start".into(),
                hir_items.type_arg_start.as_entire_binding(),
            );
            resources.insert(
                "hir_type_arg_count".into(),
                hir_items.type_arg_count.as_entire_binding(),
            );
            resources.insert(
                "hir_type_arg_next".into(),
                hir_items.type_arg_next.as_entire_binding(),
            );
            resources.insert(
                "hir_type_alias_target_node".into(),
                hir_items.type_alias_target_node.as_entire_binding(),
            );
            resources.insert(
                "hir_fn_return_type_node".into(),
                hir_items.fn_return_type_node.as_entire_binding(),
            );
            resources.insert(
                "hir_param_record".into(),
                hir_items.param_record.as_entire_binding(),
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
                "hir_array_lit_first_element".into(),
                hir_items.array_lit_first_element.as_entire_binding(),
            );
            resources.insert(
                "hir_array_lit_element_count".into(),
                hir_items.array_lit_element_count.as_entire_binding(),
            );
            resources.insert(
                "hir_array_element_next".into(),
                hir_items.array_element_next.as_entire_binding(),
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
                "hir_variant_parent_enum".into(),
                hir_items.variant_parent_enum.as_entire_binding(),
            );
            resources.insert(
                "hir_variant_payload_start".into(),
                hir_items.variant_payload_start.as_entire_binding(),
            );
            resources.insert(
                "hir_variant_payload_count".into(),
                hir_items.variant_payload_count.as_entire_binding(),
            );
            resources.insert(
                "hir_match_arm_result_node".into(),
                hir_items.match_arm_result_node.as_entire_binding(),
            );
            resources.insert(
                "hir_match_payload_owner_arm".into(),
                hir_items.match_payload_owner_arm.as_entire_binding(),
            );
            resources.insert(
                "hir_match_payload_match_node".into(),
                hir_items.match_payload_match_node.as_entire_binding(),
            );
            resources.insert(
                "hir_match_payload_ordinal".into(),
                hir_items.match_payload_ordinal.as_entire_binding(),
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
            resources.insert(
                "hir_semantic_dense_node".into(),
                hir_items.semantic_dense_node.as_entire_binding(),
            );
            resources.insert(
                "hir_semantic_count".into(),
                hir_items.semantic_count.as_entire_binding(),
            );
        } else {
            resources.insert("node_kind".into(), node_kind_empty.as_entire_binding());
            resources.insert("parent".into(), parent_empty.as_entire_binding());
            resources.insert("parent_record".into(), parent_empty.as_entire_binding());
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
            resources.insert(
                "hir_type_path_leaf_node".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_type_arg_start".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_type_arg_count".into(),
                node_kind_empty.as_entire_binding(),
            );
            resources.insert("hir_type_arg_next".into(), parent_empty.as_entire_binding());
            resources.insert(
                "hir_type_alias_target_node".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_fn_return_type_node".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert("hir_param_record".into(), parent_empty.as_entire_binding());
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
                "hir_array_lit_first_element".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_array_lit_element_count".into(),
                node_kind_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_array_element_next".into(),
                parent_empty.as_entire_binding(),
            );
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
                "hir_variant_parent_enum".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_variant_payload_start".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_variant_payload_count".into(),
                node_kind_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_match_arm_result_node".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_match_payload_owner_arm".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_match_payload_match_node".into(),
                parent_empty.as_entire_binding(),
            );
            resources.insert(
                "hir_match_payload_ordinal".into(),
                parent_empty.as_entire_binding(),
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
            resources.insert(
                "hir_semantic_dense_node".into(),
                hir_semantic_dense_node_identity.as_entire_binding(),
            );
            resources.insert(
                "hir_semantic_count".into(),
                hir_active_count.as_entire_binding(),
            );
        }
        resources.insert("status".into(), self.status_buf.as_entire_binding());
        resources.insert("visible_decl".into(), visible_decl.as_entire_binding());
        resources.insert("visible_type".into(), visible_type.as_entire_binding());
        resources.insert(
            "hir_value_decl_name_present".into(),
            hir_value_decl_name_present.as_entire_binding(),
        );
        resources.insert(
            "hir_visible_decl_count_out".into(),
            hir_visible_decl_count_out.as_entire_binding(),
        );
        resources.insert(
            "hir_visible_decl_owner_fn".into(),
            hir_visible_decl_owner_fn.as_entire_binding(),
        );
        resources.insert(
            "hir_visible_decl_name_id".into(),
            hir_visible_decl_name_id.as_entire_binding(),
        );
        resources.insert(
            "hir_visible_decl_token".into(),
            hir_visible_decl_token.as_entire_binding(),
        );
        resources.insert(
            "hir_visible_decl_scope_end".into(),
            hir_visible_decl_scope_end.as_entire_binding(),
        );
        resources.insert(
            "hir_visible_decl_key_order".into(),
            hir_visible_decl_key_order.as_entire_binding(),
        );
        resources.insert(
            "hir_visible_decl_scope_tree".into(),
            hir_visible_decl_scope_tree.as_entire_binding(),
        );
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
            "call_param_ref_tag".into(),
            call_param_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "call_param_ref_payload".into(),
            call_param_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "call_arg_record".into(),
            call_arg_record.as_entire_binding(),
        );
        resources.insert("call_arg_node".into(), call_arg_node.as_entire_binding());
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
            "language_type_code_by_name_id".into(),
            language_type_code_by_name_id.as_entire_binding(),
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
            "type_decl_generic_param_count_by_node".into(),
            type_decl_generic_param_count_by_node.as_entire_binding(),
        );
        resources.insert(
            "type_decl_const_param_count_by_node".into(),
            type_decl_const_param_count_by_node.as_entire_binding(),
        );
        resources.insert(
            "type_decl_hir_node_by_token".into(),
            type_decl_hir_node_by_token.as_entire_binding(),
        );
        resources.insert(
            "type_generic_param_slot_by_token".into(),
            type_generic_param_slot_by_token.as_entire_binding(),
        );
        resources.insert(
            "type_const_param_slot_by_token".into(),
            type_const_param_slot_by_token.as_entire_binding(),
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
            "predicate_owner_node".into(),
            predicate_owner_node.as_entire_binding(),
        );
        resources.insert(
            "predicate_subject_token".into(),
            predicate_subject_token.as_entire_binding(),
        );
        resources.insert(
            "predicate_bound_token".into(),
            predicate_bound_token.as_entire_binding(),
        );
        resources.insert(
            "predicate_bound_arg_count".into(),
            predicate_bound_arg_count.as_entire_binding(),
        );
        resources.insert(
            "predicate_bound_first_arg_token".into(),
            predicate_bound_first_arg_token.as_entire_binding(),
        );
        resources.insert(
            "predicate_bound_second_arg_token".into(),
            predicate_bound_second_arg_token.as_entire_binding(),
        );
        resources.insert(
            "predicate_status".into(),
            predicate_status.as_entire_binding(),
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
        resources.insert(
            "struct_init_field_ordinal_by_node".into(),
            struct_init_field_ordinal_by_node.as_entire_binding(),
        );
        let hir_active_dispatch = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_hir_active_dispatch_args"),
            &passes.hir_active_dispatch_args.bind_group_layouts[0],
            &passes.hir_active_dispatch_args.reflection,
            0,
            &resources,
        )?;
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
        let type_instances_generic_param_use_slots = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_generic_param_use_slots"),
            &passes
                .type_instances_generic_param_use_slots
                .bind_group_layouts[0],
            &passes.type_instances_generic_param_use_slots.reflection,
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
        let calls_infer_array_generics = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_infer_array_generics"),
            &passes.calls_infer_array_generics.bind_group_layouts[0],
            &passes.calls_infer_array_generics.reflection,
            0,
            &resources,
        )?;
        let calls_validate_array_results = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_validate_array_results"),
            &passes.calls_validate_array_results.bind_group_layouts[0],
            &passes.calls_validate_array_results.reflection,
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
            infer_array_generics: calls_infer_array_generics,
            validate_array_results: calls_validate_array_results,
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
        let language_type_codes_clear = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_language_type_codes_clear"),
            &passes.language_type_codes_clear.bind_group_layouts[0],
            &passes.language_type_codes_clear.reflection,
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
            type_codes_clear: language_type_codes_clear,
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
            &name_max_len,
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
            &radix_dispatch_args,
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
                source_file_capacity,
                token_capacity,
                hir_node_capacity,
                token_buf,
                token_count_buf,
                hir_status_buf,
                hir_kind_buf,
                hir_token_pos_buf,
                hir_token_end_buf,
                &self.status_buf,
                &hir_active_count,
                hir_items,
                &name_id_by_token,
                &language_name_id,
                &name_lexeme_flag,
                &name_lexeme_kind,
                &name_lexeme_prefix,
                &name_order_in,
                &name_order_tmp,
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
                &enclosing_fn,
                &call_fn_index,
                &call_return_type,
                &call_return_type_token,
                &call_param_count,
                &call_param_type,
                &call_param_ref_tag,
                &call_param_ref_payload,
                &call_arg_record,
                &call_arg_node,
                &type_expr_ref_tag,
                &type_expr_ref_payload,
                &type_instance_kind,
                &type_instance_decl_token,
                &type_instance_arg_start,
                &type_instance_arg_count,
                &type_instance_arg_ref_tag,
                &type_instance_arg_ref_payload,
                &type_decl_generic_param_count,
                &type_generic_param_slot_by_token,
                &type_instance_state,
                &decl_type_ref_tag,
                &decl_type_ref_payload,
                &fn_return_ref_tag,
                &fn_return_ref_payload,
                &fn_entrypoint_tag,
                &struct_init_field_ordinal_by_node,
                external_scratch,
            )?)
        } else {
            None
        };
        let predicates = if let Some(module_path) = &module_path {
            let hir_items = hir_items.expect("predicate collection requires HIR item buffers");
            let predicate_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gParams".into(), self.params_buf.as_entire_binding()),
                ("hir_status".into(), hir_status_buf.as_entire_binding()),
                ("node_kind".into(), hir_items.node_kind.as_entire_binding()),
                ("parent".into(), hir_items.parent.as_entire_binding()),
                (
                    "first_child".into(),
                    hir_items.first_child.as_entire_binding(),
                ),
                (
                    "subtree_end".into(),
                    hir_items.subtree_end.as_entire_binding(),
                ),
                (
                    "hir_token_pos".into(),
                    hir_token_pos_buf.as_entire_binding(),
                ),
                (
                    "hir_type_len_value".into(),
                    hir_items.type_len_value.as_entire_binding(),
                ),
                ("hir_item_kind".into(), hir_items.kind.as_entire_binding()),
                (
                    "name_id_by_token".into(),
                    name_id_by_token.as_entire_binding(),
                ),
                (
                    "type_decl_generic_param_count_by_node".into(),
                    type_decl_generic_param_count_by_node.as_entire_binding(),
                ),
                (
                    "language_type_code_by_name_id".into(),
                    language_type_code_by_name_id.as_entire_binding(),
                ),
                (
                    "decl_count_out".into(),
                    module_path.decl_count_out.as_entire_binding(),
                ),
                (
                    "decl_name_id".into(),
                    module_path.decl_name_id.as_entire_binding(),
                ),
                (
                    "decl_kind".into(),
                    module_path.decl_kind.as_entire_binding(),
                ),
                (
                    "decl_namespace".into(),
                    module_path.decl_namespace.as_entire_binding(),
                ),
                (
                    "decl_hir_node".into(),
                    module_path.decl_hir_node.as_entire_binding(),
                ),
                (
                    "module_count_out".into(),
                    module_path.module_count_out.as_entire_binding(),
                ),
                (
                    "sorted_module_key_order".into(),
                    module_path.module_key_to_module_id.as_entire_binding(),
                ),
                (
                    "module_key_segment_count".into(),
                    module_path.module_key_segment_count.as_entire_binding(),
                ),
                (
                    "module_key_segment_base".into(),
                    module_path.module_key_segment_base.as_entire_binding(),
                ),
                (
                    "module_key_segment_name_id".into(),
                    module_path.module_key_segment_name_id.as_entire_binding(),
                ),
                (
                    "decl_type_key_count_out".into(),
                    module_path.decl_type_key_count_out.as_entire_binding(),
                ),
                (
                    "decl_type_key_to_decl_id".into(),
                    module_path.decl_type_key_to_decl_id.as_entire_binding(),
                ),
                (
                    "decl_module_id".into(),
                    module_path.decl_module_id.as_entire_binding(),
                ),
                (
                    "predicate_owner_node".into(),
                    predicate_owner_node.as_entire_binding(),
                ),
                (
                    "predicate_subject_token".into(),
                    predicate_subject_token.as_entire_binding(),
                ),
                (
                    "predicate_bound_token".into(),
                    predicate_bound_token.as_entire_binding(),
                ),
                (
                    "predicate_bound_arg_count".into(),
                    predicate_bound_arg_count.as_entire_binding(),
                ),
                (
                    "predicate_bound_first_arg_token".into(),
                    predicate_bound_first_arg_token.as_entire_binding(),
                ),
                (
                    "predicate_bound_second_arg_token".into(),
                    predicate_bound_second_arg_token.as_entire_binding(),
                ),
                (
                    "predicate_status".into(),
                    predicate_status.as_entire_binding(),
                ),
            ]);
            Some(PredicateBindGroups {
                collect: bind_group::create_bind_group_from_reflection(
                    device,
                    Some("type_check_resident_predicates_collect"),
                    &passes.predicates_collect.bind_group_layouts[0],
                    &passes.predicates_collect.reflection,
                    0,
                    &predicate_resources,
                )?,
                obligations: bind_group::create_bind_group_from_reflection(
                    device,
                    Some("type_check_resident_predicates_obligations"),
                    &passes.predicates_obligations.bind_group_layouts[0],
                    &passes.predicates_obligations.reflection,
                    0,
                    &resources,
                )?,
            })
        } else {
            None
        };
        let (
            hir_visible_decl_flag,
            hir_visible_decl_prefix,
            hir_visible_decl_scan_local_prefix,
            hir_visible_decl_scan_block_sum,
            hir_visible_decl_scan_prefix_a,
            hir_visible_decl_scan_prefix_b,
        ) = if let Some(module_path) = &module_path {
            // Module/path record scans have finished before resident visible
            // declaration scans run, so the HIR-sized flag/prefix scratch can
            // reuse those buffers instead of allocating another scan family.
            (
                alias_storage_buffer(&module_path.module_record_flag),
                alias_storage_buffer(&module_path.module_record_prefix),
                alias_storage_buffer(&module_path.record_scan_local_prefix),
                alias_storage_buffer(&module_path.record_scan_block_sum),
                alias_storage_buffer(&module_path.record_scan_prefix_a),
                alias_storage_buffer(&module_path.record_scan_prefix_b),
            )
        } else {
            (
                storage_u32_rw(
                    device,
                    "type_check.resident.hir_visible_decl_flag",
                    hir_visible_decl_scan_capacity as usize,
                    wgpu::BufferUsages::empty(),
                ),
                storage_u32_rw(
                    device,
                    "type_check.resident.hir_visible_decl_prefix",
                    hir_visible_decl_scan_capacity as usize,
                    wgpu::BufferUsages::empty(),
                ),
                storage_u32_rw(
                    device,
                    "type_check.resident.hir_visible_decl_scan_local_prefix",
                    hir_visible_decl_scan_capacity as usize,
                    wgpu::BufferUsages::empty(),
                ),
                storage_u32_rw(
                    device,
                    "type_check.resident.hir_visible_decl_scan_block_sum",
                    hir_decl_scan_n_blocks as usize,
                    wgpu::BufferUsages::empty(),
                ),
                storage_u32_rw(
                    device,
                    "type_check.resident.hir_visible_decl_scan_prefix_a",
                    hir_decl_scan_n_blocks as usize,
                    wgpu::BufferUsages::empty(),
                ),
                storage_u32_rw(
                    device,
                    "type_check.resident.hir_visible_decl_scan_prefix_b",
                    hir_decl_scan_n_blocks as usize,
                    wgpu::BufferUsages::empty(),
                ),
            )
        };
        resources.insert(
            "hir_visible_decl_flag".into(),
            hir_visible_decl_flag.as_entire_binding(),
        );
        resources.insert(
            "hir_visible_decl_prefix".into(),
            hir_visible_decl_prefix.as_entire_binding(),
        );
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
            token_count_buf,
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
        let scope_hir = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_scope_hir"),
            &passes.scope_hir.bind_group_layouts[0],
            &passes.scope_hir.reflection,
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
        let visible_bind_groups = create_visible_bind_groups_with_passes(
            passes,
            device,
            &resources,
            hir_node_capacity,
            hir_decl_scan_n_blocks,
            hir_visible_decl_capacity,
            hir_decl_record_n_blocks,
            hir_decl_tree_leaf_base,
            &hir_decl_scan_steps,
            &hir_active_count,
            hir_items
                .map(|items| items.semantic_count)
                .unwrap_or(&hir_active_count),
            &hir_visible_decl_flag,
            &hir_visible_decl_prefix,
            &hir_visible_decl_scan_local_prefix,
            &hir_visible_decl_scan_block_sum,
            &hir_visible_decl_scan_prefix_a,
            &hir_visible_decl_scan_prefix_b,
            &hir_visible_decl_count_out,
            &hir_visible_decl_owner_fn,
            &hir_visible_decl_name_id,
            &hir_visible_decl_token,
            &hir_visible_decl_scope_end,
            &hir_visible_decl_key_order,
            &hir_visible_decl_key_order_tmp,
            &hir_visible_decl_key_radix_dispatch_args,
            &hir_visible_decl_key_radix_block_histogram,
            &hir_visible_decl_key_radix_block_bucket_prefix,
            &hir_visible_decl_key_radix_bucket_total,
            &hir_visible_decl_key_radix_bucket_base,
            &hir_visible_decl_scope_tree,
        )?;
        drop(resources);

        Ok(ResidentTypeCheckBindGroups {
            source_len,
            source_file_capacity,
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
            language_type_code_by_name_id,
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
            hir_value_decl_name_present,
            hir_visible_decl_flag,
            hir_visible_decl_prefix,
            hir_visible_decl_scan_local_prefix,
            hir_visible_decl_scan_block_sum,
            hir_visible_decl_scan_prefix_a,
            hir_visible_decl_scan_prefix_b,
            hir_visible_decl_count_out,
            hir_visible_decl_owner_fn,
            hir_visible_decl_name_id,
            hir_visible_decl_token,
            hir_visible_decl_scope_end,
            hir_visible_decl_key_order,
            hir_visible_decl_key_order_tmp,
            hir_visible_decl_key_radix_dispatch_args,
            hir_visible_decl_key_radix_block_histogram,
            hir_visible_decl_key_radix_block_bucket_prefix,
            hir_visible_decl_key_radix_bucket_total,
            hir_visible_decl_key_radix_bucket_base,
            hir_visible_decl_scope_tree,
            token_active_dispatch_args,
            hir_active_dispatch_args,
            token_hir_active_dispatch_args,
            hir_active_count,
            hir_active_dispatch,
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
            call_param_ref_tag,
            call_param_ref_payload,
            call_arg_record,
            call_arg_node,
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
            type_decl_generic_param_count_by_node,
            type_decl_const_param_count_by_node,
            type_decl_hir_node_by_token,
            type_generic_param_slot_by_token,
            type_const_param_slot_by_token,
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
            predicate_owner_node,
            predicate_subject_token,
            predicate_bound_token,
            predicate_bound_arg_count,
            predicate_bound_first_arg_token,
            predicate_bound_second_arg_token,
            predicate_status,
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
            struct_init_field_ordinal_by_node,
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
            predicates,
            type_instances_clear,
            type_instances_decl_generic_params,
            type_instances_generic_param_use_slots,
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
            scope_hir,
        })
    }
}
