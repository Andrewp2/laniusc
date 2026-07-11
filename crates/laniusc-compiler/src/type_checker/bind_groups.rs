use super::*;

mod empty_hir_bindings;
mod visible_scratch;

use empty_hir_bindings::{
    EmptyHirBindings,
    register_empty_hir_resources,
    register_hir_item_resources,
};
use visible_scratch::ResidentVisibleScratch;

impl GpuTypeChecker {
    /// Allocates or wires all resident buffers and bind groups for one cache key.
    #[allow(clippy::too_many_arguments)]
    pub(super) fn create_resident_state(
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
        parser_hir_node_capacity: u32,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_token_file_id_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        hir_items: Option<GpuTypeCheckHirItemBuffers<'_>>,
        passes: &TypeCheckPasses,
        input_fingerprint: u64,
        uses_hir_items: bool,
        external_scratch: Option<GpuTypeCheckExternalScratchBuffers<'_>>,
        module_path_scratch: Option<GpuTypeCheckExternalScratchBuffers<'_>>,
    ) -> Result<ResidentTypeCheckState> {
        let allocation_timing =
            crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false);
        let allocation_start = std::time::Instant::now();
        let mut allocation_last = allocation_start;
        macro_rules! allocation_stamp {
            ($stage:literal) => {
                if allocation_timing {
                    let now = std::time::Instant::now();
                    eprintln!(
                        "[gpu_compile_host_timer] typecheck.resident.{}: {:.3}ms (total {:.3}ms)",
                        $stage,
                        now.duration_since(allocation_last).as_secs_f64() * 1000.0,
                        now.duration_since(allocation_start).as_secs_f64() * 1000.0,
                    );
                    allocation_last = now;
                }
            };
        }
        let visible_decl = typed_storage_u32_rw(
            device,
            "type_check.resident.visible_decl",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let visible_type = typed_storage_u32_rw(
            device,
            "type_check.resident.visible_type",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_type_path_type = typed_storage_u32_rw(
            device,
            "type_check.resident.module_type_path_type",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_type_path_status = typed_storage_u32_rw(
            device,
            "type_check.resident.module_type_path_status",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_status = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.module_value_path_status",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_expr_head = typed_storage_u32_rw(
            device,
            "type_check.resident.module_value_path_expr_head",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_call_head = typed_storage_u32_rw(
            device,
            "type_check.resident.module_value_path_call_head",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_call_open = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.module_value_path_call_open",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_call_path_id = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.module_value_path_call_path_id",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_call_leaf = typed_storage_u32_rw(
            device,
            "type_check.resident.module_value_path_call_leaf",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_associated_method_token = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.module_value_path_associated_method_token",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_associated_receiver_token = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.module_value_path_associated_receiver_token",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_const_head = typed_storage_u32_rw(
            device,
            "type_check.resident.module_value_path_const_head",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_value_path_const_end = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.module_value_path_const_end",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let name_capacity = token_capacity.saturating_add(LANGUAGE_SYMBOL_COUNT).max(1);
        let token_scan_n_blocks = token_capacity.div_ceil(256).max(1);
        let name_n_blocks = name_capacity.div_ceil(256).max(1);
        let hir_value_decl_name_present = typed_storage_u32_rw(
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
        let hir_visible_decl_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_owner_fn = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_owner_fn",
            hir_visible_decl_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_name_id = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_name_id",
            hir_visible_decl_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_token = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_token",
            hir_visible_decl_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_scope_end = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_scope_end",
            hir_visible_decl_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.hir_visible_decl_node",
            hir_visible_decl_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_key_order = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_order",
            hir_visible_decl_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_key_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_order_tmp",
            hir_visible_decl_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_key_radix_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let hir_visible_decl_key_radix_histogram_len =
            (hir_decl_record_n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
        let hir_visible_decl_key_radix_block_histogram = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_radix_block_histogram",
            hir_visible_decl_key_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_key_radix_block_bucket_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_radix_block_bucket_prefix",
            hir_visible_decl_key_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_key_radix_bucket_total = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_radix_bucket_total",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_key_radix_bucket_base = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_key_radix_bucket_base",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let generic_param_capacity = token_capacity.max(1);
        let generic_param_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_param_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let generic_param_owner_node = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_param_owner_node",
            generic_param_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let generic_param_name_id = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_param_name_id",
            generic_param_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let generic_param_token = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_param_token",
            generic_param_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let generic_param_node = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_param_node",
            generic_param_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let generic_param_kind = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_param_kind",
            generic_param_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let generic_param_key_order = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_param_key_order",
            generic_param_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let generic_param_key_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_param_key_order_tmp",
            generic_param_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let generic_param_slot_order = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_param_slot_order",
            generic_param_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let generic_param_slot_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_param_slot_order_tmp",
            generic_param_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_key_order = typed_storage_u32_rw(
            device,
            "type_check.resident.struct_field_key_order",
            hir_visible_decl_scan_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_key_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.struct_field_key_order_tmp",
            hir_visible_decl_scan_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_key_radix_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.struct_field_key_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let struct_field_key_radix_histogram_len =
            (hir_decl_scan_n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
        let struct_field_key_radix_block_histogram = typed_storage_u32_rw(
            device,
            "type_check.resident.struct_field_key_radix_block_histogram",
            struct_field_key_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_key_radix_block_bucket_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.struct_field_key_radix_block_bucket_prefix",
            struct_field_key_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_key_radix_bucket_total = typed_storage_u32_rw(
            device,
            "type_check.resident.struct_field_key_radix_bucket_total",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_key_radix_bucket_base = typed_storage_u32_rw(
            device,
            "type_check.resident.struct_field_key_radix_bucket_base",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_scope_tree = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_visible_decl_scope_tree",
            hir_decl_tree_len,
            wgpu::BufferUsages::empty(),
        );
        let generic_decl_owner_by_node_a = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_decl_owner_by_node_a",
            hir_visible_decl_scan_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let generic_decl_owner_by_node_b = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_decl_owner_by_node_b",
            hir_visible_decl_scan_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let generic_decl_parent_jump_a = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_decl_parent_jump_a",
            hir_visible_decl_scan_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let generic_decl_parent_jump_b = typed_storage_u32_rw(
            device,
            "type_check.resident.generic_decl_parent_jump_b",
            hir_visible_decl_scan_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_scan_params = NameScanParams {
            n_items: token_capacity,
            n_blocks: token_scan_n_blocks,
            scan_step: 0,
        };
        let name_scan_steps = make_name_scan_steps(device, name_scan_params);
        let name_lexeme_flag = typed_storage_u32_rw(
            device,
            "type_check.resident.name_lexeme_flag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_lexeme_kind = typed_storage_u32_rw(
            device,
            "type_check.resident.name_lexeme_kind",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_lexeme_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.name_lexeme_prefix",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_scan_local_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.name_scan_local_prefix",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_scan_block_sum = typed_storage_u32_rw(
            device,
            "type_check.resident.name_scan_block_sum",
            name_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_scan_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.resident.name_scan_prefix_a",
            name_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_scan_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.resident.name_scan_prefix_b",
            name_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_scan_total = typed_storage_u32_rw(
            device,
            "type_check.resident.name_scan_total",
            1,
            wgpu::BufferUsages::empty(),
        );
        let name_max_len = typed_storage_u32_rw(
            device,
            "type_check.resident.name_max_len",
            1,
            wgpu::BufferUsages::COPY_DST,
        );
        let name_spans = typed_storage_u32_rw(
            device,
            "type_check.resident.name_spans",
            (name_capacity as usize).max(1) * 4,
            wgpu::BufferUsages::empty(),
        );
        let name_order_in = typed_storage_u32_rw(
            device,
            "type_check.resident.name_order_in",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_order_tmp = typed_storage_u32_rw(
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
        let name_id_by_token = typed_storage_u32_rw(
            device,
            "type_check.resident.name_id_by_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let language_name_id = typed_storage_u32_rw(
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
        let language_decl_name_id = typed_storage_u32_rw(
            device,
            "type_check.resident.language_decl_name_id",
            LANGUAGE_DECL_COUNT as usize,
            wgpu::BufferUsages::empty(),
        );
        let language_type_code_by_name_id = typed_storage_u32_rw(
            device,
            "type_check.resident.language_type_code_by_name_id",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let language_entrypoint_tag_by_name_id = typed_storage_u32_rw(
            device,
            "type_check.resident.language_entrypoint_tag_by_name_id",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let language_intrinsic_tag_by_name_id = typed_storage_u32_rw(
            device,
            "type_check.resident.language_intrinsic_tag_by_name_id",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let radix_histogram_len = (name_n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
        let radix_block_histogram = typed_storage_u32_rw(
            device,
            "type_check.resident.radix_block_histogram",
            radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let radix_block_bucket_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.radix_block_bucket_prefix",
            radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let radix_bucket_total = typed_storage_u32_rw(
            device,
            "type_check.resident.radix_bucket_total",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let radix_bucket_base = typed_storage_u32_rw(
            device,
            "type_check.resident.radix_bucket_base",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let run_head_mask = typed_storage_u32_rw(
            device,
            "type_check.resident.run_head_mask",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let adjacent_equal_mask = typed_storage_u32_rw(
            device,
            "type_check.resident.adjacent_equal_mask",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let run_head_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.run_head_prefix",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let sorted_name_id = typed_storage_u32_rw(
            device,
            "type_check.resident.sorted_name_id",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let name_id_by_input = typed_storage_u32_rw(
            device,
            "type_check.resident.name_id_by_input",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let unique_name_count = typed_storage_u32_rw(
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
        let loop_delta = typed_storage_i32_rw(
            device,
            "type_check.resident.loop_delta",
            token_capacity as usize + 1,
            wgpu::BufferUsages::empty(),
        );
        let loop_depth_inblock = typed_storage_i32_rw(
            device,
            "type_check.resident.loop_depth_inblock",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_block_sum = typed_storage_i32_rw(
            device,
            "type_check.resident.loop_block_sum",
            loop_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_prefix_a = typed_storage_i32_rw(
            device,
            "type_check.resident.loop_prefix_a",
            loop_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_prefix_b = typed_storage_i32_rw(
            device,
            "type_check.resident.loop_prefix_b",
            loop_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_block_prefix = typed_storage_i32_rw(
            device,
            "type_check.resident.loop_block_prefix",
            loop_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_depth = typed_storage_i32_rw(
            device,
            "type_check.resident.loop_depth",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let enclosing_fn = typed_storage_u32_rw(
            device,
            "type_check.resident.enclosing_fn",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let enclosing_fn_end = typed_storage_u32_rw(
            device,
            "type_check.resident.enclosing_fn_end",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_event_value = typed_storage_u32_rw(
            device,
            "type_check.resident.fn_event_value",
            token_capacity as usize + 1,
            wgpu::BufferUsages::empty(),
        );
        let fn_event_end = typed_storage_u32_rw(
            device,
            "type_check.resident.fn_event_end",
            token_capacity as usize + 1,
            wgpu::BufferUsages::empty(),
        );
        let fn_event_index = typed_storage_u32_rw(
            device,
            "type_check.resident.fn_event_index",
            token_capacity as usize + 1,
            wgpu::BufferUsages::empty(),
        );
        let fn_event_inblock = typed_storage_u32_rw(
            device,
            "type_check.resident.fn_event_inblock",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_block_sum = typed_storage_u32_rw(
            device,
            "type_check.resident.fn_block_sum",
            fn_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.resident.fn_prefix_a",
            fn_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.resident.fn_prefix_b",
            fn_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_block_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.fn_block_prefix",
            fn_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_fn_index = typed_storage_u32_rw(
            device,
            "type_check.resident.call_fn_index",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_intrinsic_tag = typed_storage_u32_rw(
            device,
            "type_check.resident.call_intrinsic_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_entrypoint_tag_len = token_capacity.max(hir_node_capacity) as usize;
        let fn_entrypoint_tag = typed_reuse_storage_u32(
            device,
            "type_check.resident.fn_entrypoint_tag",
            fn_entrypoint_tag_len,
            external_scratch.map(|scratch| scratch.fn_entrypoint_tag),
        );
        let call_return_type = typed_storage_u32_rw(
            device,
            "type_check.resident.call_return_type",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_return_type_token = typed_storage_u32_rw(
            device,
            "type_check.resident.call_return_type_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let return_fn_flags = typed_storage_u32_rw(
            device,
            "type_check.resident.return_fn_flags",
            hir_node_capacity.max(1) as usize,
            wgpu::BufferUsages::empty(),
        );
        let return_block_flags = typed_storage_u32_rw(
            device,
            "type_check.resident.return_block_flags",
            hir_node_capacity.max(1) as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_count = typed_reuse_storage_u32(
            device,
            "type_check.resident.call_param_count",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.call_param_count),
        );
        let call_param_type = typed_reuse_storage_u32(
            device,
            "type_check.resident.call_param_type",
            (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
            external_scratch.map(|scratch| scratch.call_param_type),
        );
        let call_param_ref_tag = typed_storage_u32_rw(
            device,
            "type_check.resident.call_param_ref_tag",
            (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
            wgpu::BufferUsages::empty(),
        );
        let call_param_ref_payload = typed_storage_u32_rw(
            device,
            "type_check.resident.call_param_ref_payload",
            (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_slot_type = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_generic_slot_type",
            (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_slot_ordinal = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_generic_slot_ordinal",
            (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_const_slot_len = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_const_slot_len",
            (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_capacity = hir_items
            .map(|items| items.call_param_row_capacity)
            .unwrap_or(hir_node_capacity)
            .max(1);
        let call_param_hir_capacity = hir_node_capacity.max(1);
        let call_param_segment_scan_capacity = token_capacity.max(1);
        let call_param_segment_scan_n_blocks =
            call_param_segment_scan_capacity.div_ceil(256).max(1);
        let call_param_segment_scan_steps = make_name_scan_steps(
            device,
            NameScanParams {
                n_items: call_param_segment_scan_capacity,
                n_blocks: call_param_segment_scan_n_blocks,
                scan_step: 0,
            },
        );
        let call_param_row_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.call_param_row_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_flag = typed_storage_u32_rw(
            device,
            "type_check.resident.call_param_row_flag",
            call_param_hir_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_node_type = typed_storage_u32_rw(
            device,
            "type_check.resident.call_param_row_node_type",
            call_param_hir_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_node_ref_tag = typed_storage_u32_rw(
            device,
            "type_check.resident.call_param_row_node_ref_tag",
            call_param_hir_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_node_ref_payload = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_param_row_node_ref_payload",
            call_param_hir_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_param_row_node",
            call_param_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_fn_token = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_param_row_fn_token",
            call_param_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_ordinal = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_param_row_ordinal",
            call_param_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_type = typed_storage_u32_rw(
            device,
            "type_check.resident.call_param_row_type",
            call_param_row_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_ref_tag = typed_storage_u32_rw(
            device,
            "type_check.resident.call_param_row_ref_tag",
            call_param_row_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_ref_payload = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_param_row_ref_payload",
            call_param_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_start = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_param_row_start",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_count = typed_storage_u32_rw(
            device,
            "type_check.resident.call_param_row_count",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_scan_local_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.call_param_row_scan_local_prefix",
            call_param_segment_scan_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_scan_block_sum = typed_storage_u32_rw(
            device,
            "type_check.resident.call_param_row_scan_block_sum",
            call_param_segment_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_scan_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.resident.call_param_row_scan_prefix_a",
            call_param_segment_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_row_scan_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.resident.call_param_row_scan_prefix_b",
            call_param_segment_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_record = typed_reuse_storage_u32(
            device,
            "type_check.resident.call_arg_record",
            (token_capacity as usize).max(1) * 4,
            external_scratch.map(|scratch| scratch.call_arg_record),
        );
        let call_arg_row_capacity = hir_items
            .map(|items| items.call_arg_row_capacity)
            .unwrap_or(hir_node_capacity)
            .max(1);
        let call_arg_hir_capacity = hir_node_capacity.max(1);
        let call_arg_row_scan_n_blocks = call_arg_hir_capacity.div_ceil(256).max(1);
        let call_arg_row_scan_steps = make_name_scan_steps(
            device,
            NameScanParams {
                n_items: call_arg_hir_capacity,
                n_blocks: call_arg_row_scan_n_blocks,
                scan_step: 0,
            },
        );
        let call_arg_row_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.call_arg_row_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_row_scan_input = typed_storage_u32_rw(
            device,
            "type_check.resident.call_arg_row_scan_input",
            call_arg_hir_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_row_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.call_arg_row_prefix",
            call_arg_hir_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_row_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_arg_row_node",
            call_arg_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_row_call_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_arg_row_call_node",
            call_arg_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_row_ordinal = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_arg_row_ordinal",
            call_arg_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_row_start = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_arg_row_start",
            call_arg_hir_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_row_count = typed_storage_u32_rw(
            device,
            "type_check.resident.call_arg_row_count",
            call_arg_hir_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_param_row = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_arg_param_row",
            call_arg_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_param_row_tmp = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_arg_param_row_tmp",
            call_arg_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_match_jump_a = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_arg_match_jump_a",
            call_arg_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_match_jump_b = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_arg_match_jump_b",
            call_arg_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_param_match_jump_a = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_param_match_jump_a",
            call_param_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_param_match_jump_b = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_param_match_jump_b",
            call_param_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_capacity = generic_claim_capacity_for_features(
            token_capacity,
            hir_items
                .map(|items| items.parser_feature_flags)
                .unwrap_or(u32::MAX),
        );
        let call_generic_claim_radix_n_blocks = call_generic_claim_capacity.div_ceil(256).max(1);
        let call_generic_claim_scan_input = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_scan_input",
            call_arg_row_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_prefix",
            call_arg_row_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_callee = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_generic_claim_callee",
            call_generic_claim_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_slot = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_generic_claim_slot",
            call_generic_claim_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_type = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_type",
            call_generic_claim_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_arg_row = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_generic_claim_arg_row",
            call_generic_claim_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_order = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_order",
            call_generic_claim_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_order_tmp",
            call_generic_claim_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_radix_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let call_generic_claim_radix_histogram_len =
            (call_generic_claim_radix_n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
        let call_generic_claim_radix_block_histogram = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_radix_block_histogram",
            call_generic_claim_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_radix_block_bucket_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_radix_block_bucket_prefix",
            call_generic_claim_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_radix_bucket_total = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_radix_bucket_total",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_radix_bucket_base = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_radix_bucket_base",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_const_claim_callee = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_const_claim_callee",
            call_arg_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_const_claim_slot = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_const_claim_slot",
            call_arg_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_const_claim_len = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_const_claim_len",
            call_arg_row_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_const_claim_order = typed_storage_u32_rw(
            device,
            "type_check.resident.call_const_claim_order",
            call_arg_row_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_const_claim_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.call_const_claim_order_tmp",
            call_arg_row_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_const_claim_radix_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.call_const_claim_radix_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let call_const_claim_radix_block_histogram = typed_storage_u32_rw(
            device,
            "type_check.resident.call_const_claim_radix_block_histogram",
            call_generic_claim_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let call_const_claim_radix_block_bucket_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.call_const_claim_radix_block_bucket_prefix",
            call_generic_claim_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let call_const_claim_radix_bucket_total = typed_storage_u32_rw(
            device,
            "type_check.resident.call_const_claim_radix_bucket_total",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_const_claim_radix_bucket_base = typed_storage_u32_rw(
            device,
            "type_check.resident.call_const_claim_radix_bucket_base",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_required_generic_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.call_required_generic_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let call_required_generic_scan_input = typed_storage_u32_rw(
            device,
            "type_check.resident.call_required_generic_scan_input",
            hir_node_capacity.max(1) as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_required_generic_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.call_required_generic_prefix",
            hir_node_capacity.max(1) as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_required_generic_scan_local_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.call_required_generic_scan_local_prefix",
            hir_node_capacity.max(1) as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_required_generic_scan_block_sum = typed_storage_u32_rw(
            device,
            "type_check.resident.call_required_generic_scan_block_sum",
            call_arg_row_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_required_generic_scan_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.resident.call_required_generic_scan_prefix_a",
            call_arg_row_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_required_generic_scan_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.resident.call_required_generic_scan_prefix_b",
            call_arg_row_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_required_generic_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.call_required_generic_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let call_has_array_arg = typed_storage_u32_rw(
            device,
            "type_check.resident.call_has_array_arg",
            hir_node_capacity.max(1) as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_array_return_arg_instance = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_array_return_arg_instance",
            hir_node_capacity.max(1) as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_row_scan_local_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.call_arg_row_scan_local_prefix",
            call_arg_hir_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_row_scan_block_sum = typed_storage_u32_rw(
            device,
            "type_check.resident.call_arg_row_scan_block_sum",
            call_arg_row_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_row_scan_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.resident.call_arg_row_scan_prefix_a",
            call_arg_row_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_arg_row_scan_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.resident.call_arg_row_scan_prefix_b",
            call_arg_row_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_scan_local_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_scan_local_prefix",
            call_arg_row_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_scan_block_sum = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_scan_block_sum",
            call_arg_row_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_scan_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_scan_prefix_a",
            call_arg_row_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_generic_claim_scan_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.resident.call_generic_claim_scan_prefix_b",
            call_arg_row_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let function_lookup_capacity = token_capacity.saturating_mul(2).max(1) as usize;
        let function_lookup_key = typed_reuse_storage_u32(
            device,
            "type_check.resident.function_lookup_key",
            function_lookup_capacity,
            external_scratch.map(|scratch| scratch.function_lookup_key),
        );
        let function_lookup_fn = typed_reuse_storage_u32(
            device,
            "type_check.resident.function_lookup_fn",
            function_lookup_capacity,
            external_scratch.map(|scratch| scratch.function_lookup_fn),
        );
        let method_decl_receiver_ref_tag = typed_storage_u32_rw(
            device,
            "type_check.resident.method_decl_receiver_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_receiver_ref_payload = typed_storage_u32_rw(
            device,
            "type_check.resident.method_decl_receiver_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_module_id = typed_reuse_storage_u32(
            device,
            "type_check.resident.method_decl_module_id",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_module_id),
        );
        let method_decl_impl_node = typed_reuse_storage_u32(
            device,
            "type_check.resident.method_decl_impl_node",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_impl_node),
        );
        let method_decl_name_token = typed_reuse_storage_u32(
            device,
            "type_check.resident.method_decl_name_token",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_name_token),
        );
        let method_decl_name_id = typed_reuse_storage_u32(
            device,
            "type_check.resident.method_decl_name_id",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_name_id),
        );
        let method_decl_param_offset = typed_reuse_storage_u32(
            device,
            "type_check.resident.method_decl_param_offset",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_param_offset),
        );
        let method_decl_receiver_mode = typed_reuse_storage_u32(
            device,
            "type_check.resident.method_decl_receiver_mode",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_receiver_mode),
        );
        let method_decl_visibility = typed_reuse_storage_u32(
            device,
            "type_check.resident.method_decl_visibility",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_decl_visibility),
        );
        let method_module_id_by_file_id_implicit_root = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.method_module_id_by_file_id_implicit_root",
            source_file_capacity.max(1) as usize,
            0,
            wgpu::BufferUsages::empty(),
        );
        let method_module_count_out_implicit_root = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.method_module_count_out_implicit_root",
            1,
            1,
            wgpu::BufferUsages::empty(),
        );
        let method_key_to_fn_token = typed_reuse_storage_u32(
            device,
            "type_check.resident.method_key_to_fn_token",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_key_to_fn_token),
        );
        // Method key sorting starts after call resolution has consumed the
        // function lookup table, so reuse the two lookup rows as method-key
        // scratch instead of keeping additional token-sized buffers resident.
        let method_key_order_tmp =
            typed_alias_storage_u32(&function_lookup_key, function_lookup_capacity);
        let method_key_status = typed_reuse_storage_u32(
            device,
            "type_check.resident.method_key_status",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.method_key_status),
        );
        let method_key_duplicate_of =
            typed_alias_storage_u32(&function_lookup_fn, function_lookup_capacity);
        let method_key_radix_histogram_len =
            (name_n_blocks as usize).max(1) * NAME_RADIX_BUCKETS as usize;
        let method_key_radix_block_histogram = typed_reuse_storage_u32(
            device,
            "type_check.resident.method_key_radix_block_histogram",
            method_key_radix_histogram_len,
            external_scratch.map(|scratch| scratch.method_key_radix_block_histogram),
        );
        let method_key_radix_block_bucket_prefix = typed_reuse_storage_u32(
            device,
            "type_check.resident.method_key_radix_block_bucket_prefix",
            method_key_radix_histogram_len,
            external_scratch.map(|scratch| scratch.method_key_radix_block_bucket_prefix),
        );
        let method_key_radix_bucket_total = typed_storage_u32_rw(
            device,
            "type_check.resident.method_key_radix_bucket_total",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_key_radix_bucket_base = typed_storage_u32_rw(
            device,
            "type_check.resident.method_key_radix_bucket_base",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_call_receiver_ref_tag = typed_storage_u32_rw(
            device,
            "type_check.resident.method_call_receiver_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_call_receiver_ref_payload = typed_storage_u32_rw(
            device,
            "type_check.resident.method_call_receiver_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_call_name_id = typed_storage_u32_rw(
            device,
            "type_check.resident.method_call_name_id",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_call_site_module_id = typed_storage_u32_rw(
            device,
            "type_check.resident.method_call_site_module_id",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_expr_ref_tag = typed_reuse_storage_u32(
            device,
            "type_check.resident.type_expr_ref_tag",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_expr_ref_tag),
        );
        let type_expr_ref_payload = typed_reuse_storage_u32(
            device,
            "type_check.resident.type_expr_ref_payload",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_expr_ref_payload),
        );
        // Type-instance rows are populated after the name-radix pipeline and
        // remain live for later typecheck/codegen consumers. Reuse name scratch
        // that is not retained as module-path declaration metadata.
        let type_instance_kind =
            typed_alias_storage_u32(&name_scan_local_prefix, token_capacity as usize);
        let type_instance_head_token = typed_reuse_storage_u32(
            device,
            "type_check.resident.type_instance_head_token",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_head_token),
        );
        let type_decl_generic_param_count = typed_reuse_storage_u32(
            device,
            "type_check.resident.type_decl_generic_param_count",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_decl_generic_param_count),
        );
        let type_decl_generic_param_count_by_node = if let Some(scratch) = external_scratch {
            // Type-instance generic-param counts are HIR-keyed scratch. Parser
            // HIR type workspaces are dead after parser HIR construction and
            // are not part of the typecheck input surface consumed here.
            typed_alias_storage_u32(
                scratch.type_decl_generic_param_count_by_node,
                hir_node_capacity as usize,
            )
        } else {
            typed_storage_u32_rw(
                device,
                "type_check.resident.type_decl_generic_param_count_by_node",
                hir_node_capacity as usize,
                wgpu::BufferUsages::empty(),
            )
        };
        // Const-generic declaration counts are consumed before the calls
        // pipeline clears and publishes function entrypoint tags.
        let type_decl_const_param_count_by_node =
            typed_alias_storage_u32(&fn_entrypoint_tag, hir_node_capacity as usize);
        let type_decl_hir_node_by_token =
            typed_alias_storage_u32(&name_spans, token_capacity as usize);
        let type_generic_param_slot_by_token = typed_reuse_storage_u32(
            device,
            "type_check.resident.type_generic_param_slot_by_token",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_generic_param_slot_by_token),
        );
        let type_const_param_slot_by_token = typed_reuse_storage_u32(
            device,
            "type_check.resident.type_const_param_slot_by_token",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_const_param_slot_by_token),
        );
        let type_instance_decl_token =
            typed_alias_storage_u32(&radix_block_histogram, token_capacity as usize);
        let type_instance_arg_start = typed_reuse_storage_u32(
            device,
            "type_check.resident.type_instance_arg_start",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_arg_start),
        );
        let type_instance_arg_count = typed_reuse_storage_u32(
            device,
            "type_check.resident.type_instance_arg_count",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_arg_count),
        );
        let type_instance_arg_ref_tag = if let Some(scratch) = external_scratch {
            // Token-strided type-instance argument tags are rebuilt by
            // typecheck. Parser list-rank scratch is dead after HIR list
            // construction and has resident tree capacity.
            typed_alias_storage_u32(
                scratch.type_instance_arg_ref_tag,
                (token_capacity as usize).max(1) * TYPE_INSTANCE_ARG_REF_STRIDE,
            )
        } else {
            typed_storage_u32_rw(
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
            typed_alias_storage_u32(
                scratch.type_instance_arg_ref_payload,
                (token_capacity as usize).max(1) * TYPE_INSTANCE_ARG_REF_STRIDE,
            )
        } else {
            typed_storage_u32_rw(
                device,
                "type_check.resident.type_instance_arg_ref_payload",
                (token_capacity as usize).max(1) * TYPE_INSTANCE_ARG_REF_STRIDE,
                wgpu::BufferUsages::empty(),
            )
        };
        let type_instance_arg_hash = typed_storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_hash",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_row_scan_n_blocks = token_capacity.div_ceil(256).max(1);
        let type_instance_arg_row_start = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.type_instance_arg_row_start",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_row_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_row_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_row_ref_tag = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.type_instance_arg_row_ref_tag",
            hir_node_capacity.max(1) as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_row_ref_payload = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.type_instance_arg_row_ref_payload",
            hir_node_capacity.max(1) as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_row_scan_local_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_row_scan_local_prefix",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_row_scan_block_sum = typed_storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_row_scan_block_sum",
            type_instance_arg_row_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_row_scan_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_row_scan_prefix_a",
            type_instance_arg_row_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_row_scan_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_row_scan_prefix_b",
            type_instance_arg_row_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let aggregate_compare_capacity = aggregate_compare_capacity_for_features(
            hir_node_capacity,
            hir_items
                .map(|items| items.parser_feature_flags)
                .unwrap_or(u32::MAX),
        );
        let aggregate_compare_scan_n_blocks = aggregate_compare_capacity.div_ceil(256).max(1);
        let aggregate_compare_scan_steps = make_name_scan_steps(
            device,
            NameScanParams {
                n_items: aggregate_compare_capacity,
                n_blocks: aggregate_compare_scan_n_blocks,
                scan_step: 0,
            },
        );
        let aggregate_compare_scan_input = typed_storage_u32_rw(
            device,
            "type_check.resident.aggregate_compare_scan_input",
            aggregate_compare_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let aggregate_compare_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.aggregate_compare_prefix",
            aggregate_compare_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let aggregate_compare_count_out = typed_storage_u32_rw(
            device,
            "type_check.resident.aggregate_compare_count_out",
            1,
            wgpu::BufferUsages::empty(),
        );
        let aggregate_compare_expected_instance = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.aggregate_compare_expected_instance",
            aggregate_compare_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let aggregate_compare_actual_instance = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.aggregate_compare_actual_instance",
            aggregate_compare_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let aggregate_compare_error_token = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.aggregate_compare_error_token",
            aggregate_compare_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let aggregate_compare_error_detail = typed_storage_u32_rw(
            device,
            "type_check.resident.aggregate_compare_error_detail",
            aggregate_compare_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let aggregate_compare_scan_local_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.aggregate_compare_scan_local_prefix",
            aggregate_compare_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let aggregate_compare_scan_block_sum = typed_storage_u32_rw(
            device,
            "type_check.resident.aggregate_compare_scan_block_sum",
            aggregate_compare_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let aggregate_compare_scan_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.resident.aggregate_compare_scan_prefix_a",
            aggregate_compare_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let aggregate_compare_scan_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.resident.aggregate_compare_scan_prefix_b",
            aggregate_compare_scan_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let aggregate_compare_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.aggregate_compare_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let aggregate_compare_dispatch_params = uniform_from_val(
            device,
            "type_check.resident.aggregate_compare_dispatch.params",
            &CountDispatchParams {
                capacity: token_capacity.max(hir_node_capacity).max(1),
                multiplier: 1,
                reserved0: 0,
                reserved1: 0,
            },
        );
        let type_instance_elem_ref_tag = typed_reuse_storage_u32(
            device,
            "type_check.resident.type_instance_elem_ref_tag",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_elem_ref_tag),
        );
        let type_instance_elem_ref_payload = typed_reuse_storage_u32(
            device,
            "type_check.resident.type_instance_elem_ref_payload",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_elem_ref_payload),
        );
        let type_instance_len_kind = typed_reuse_storage_u32(
            device,
            "type_check.resident.type_instance_len_kind",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_len_kind),
        );
        let type_instance_len_payload = typed_reuse_storage_u32(
            device,
            "type_check.resident.type_instance_len_payload",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_len_payload),
        );
        let type_instance_state = typed_reuse_storage_u32(
            device,
            "type_check.resident.type_instance_state",
            token_capacity as usize,
            external_scratch.map(|scratch| scratch.type_instance_state),
        );
        let predicate_capacity_u32 = predicate_capacity_for_features(
            hir_node_capacity,
            hir_items
                .map(|items| items.parser_feature_flags)
                .unwrap_or(u32::MAX),
        );
        let predicate_capacity = predicate_capacity_u32 as usize;
        let predicate_key_radix_n_blocks = predicate_capacity_u32.div_ceil(256).max(1);
        let predicate_owner_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_owner_node",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_subject_token = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_subject_token",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_bound_token = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_bound_token",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_bound_decl_id = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_bound_decl_id",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_bound_arg_count = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_bound_arg_count",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_bound_first_arg_token = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_bound_first_arg_token",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_bound_second_arg_token = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_bound_second_arg_token",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_status = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_status",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_syntax_token = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_syntax_token",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_owner_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_contract_owner_node",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_name_token = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_contract_name_token",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_name_id = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_contract_name_id",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_param_count = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_method_contract_param_count",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_first_param_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_contract_first_param_node",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_return_type_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_contract_return_type_node",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_visibility = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_method_contract_visibility",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_status = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_contract_status",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_param_next_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_contract_param_next_node",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_param_type_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_contract_param_type_node",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_key_order = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_method_contract_key_order",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_key_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_method_contract_key_order_tmp",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_param_key_order = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_method_param_key_order",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_param_key_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_method_param_key_order_tmp",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_owner_range_first = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_contract_owner_range_first",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_contract_owner_range_count = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_method_contract_owner_range_count",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_validation_owner_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_validation_owner_node",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_validation_peer_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_validation_peer_node",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_validation_status = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_validation_status",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_validation_detail_token = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_validation_detail_token",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_method_validation_first_error_row = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.predicate_method_validation_first_error_row",
            predicate_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let predicate_owner_key_order = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_owner_key_order",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_owner_key_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_owner_key_order_tmp",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_impl_key_order = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_impl_key_order",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_impl_key_order_tmp = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_impl_key_order_tmp",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_key_radix_histogram_len =
            predicate_key_radix_n_blocks as usize * NAME_RADIX_BUCKETS as usize;
        let predicate_key_radix_block_histogram = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_key_radix_block_histogram",
            predicate_key_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let predicate_key_radix_block_bucket_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_key_radix_block_bucket_prefix",
            predicate_key_radix_histogram_len,
            wgpu::BufferUsages::empty(),
        );
        let predicate_key_radix_bucket_total = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_key_radix_bucket_total",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let predicate_key_radix_bucket_base = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_key_radix_bucket_base",
            NAME_RADIX_BUCKETS as usize,
            wgpu::BufferUsages::empty(),
        );
        let predicate_obligation_count_by_call = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_obligation_count_by_call",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_obligation_prefix_by_call = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_obligation_prefix_by_call",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_obligation_scan_local_prefix = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_obligation_scan_local_prefix",
            predicate_capacity,
            wgpu::BufferUsages::empty(),
        );
        let predicate_obligation_scan_block_sum = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_obligation_scan_block_sum",
            predicate_key_radix_n_blocks.max(1) as usize,
            wgpu::BufferUsages::empty(),
        );
        let predicate_obligation_scan_prefix_a = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_obligation_scan_prefix_a",
            predicate_key_radix_n_blocks.max(1) as usize,
            wgpu::BufferUsages::empty(),
        );
        let predicate_obligation_scan_prefix_b = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_obligation_scan_prefix_b",
            predicate_key_radix_n_blocks.max(1) as usize,
            wgpu::BufferUsages::empty(),
        );
        let predicate_obligation_pair_total = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_obligation_pair_total",
            1,
            wgpu::BufferUsages::empty(),
        );
        let predicate_obligation_pair_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.predicate_obligation_pair_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT | wgpu::BufferUsages::COPY_DST,
        );
        // Function return refs are populated after the name-radix pipeline has
        // assigned stable name ids. Reuse dead name-dedup scratch for these
        // token-indexed rows rather than borrowing parser rows that later
        // typecheck passes may still consume.
        let fn_return_ref_tag = typed_alias_storage_u32(&run_head_mask, token_capacity as usize);
        let fn_return_ref_payload =
            typed_alias_storage_u32(&adjacent_equal_mask, token_capacity as usize);
        let decl_type_ref_tag =
            typed_alias_storage_u32(&radix_block_bucket_prefix, token_capacity as usize);
        let decl_type_ref_payload =
            typed_alias_storage_u32(&run_head_prefix, token_capacity as usize);
        let member_result_context_instance =
            typed_alias_storage_u32(&sorted_name_id, token_capacity as usize);
        let member_result_ref_tag =
            typed_alias_storage_u32(&name_id_by_input, token_capacity as usize);
        let member_capacity = member_capacity_for_features(
            token_capacity,
            hir_items
                .map(|items| items.parser_feature_flags)
                .unwrap_or(u32::MAX),
        ) as usize;
        let member_result_ref_payload = typed_reuse_storage_u32(
            device,
            "type_check.resident.member_result_ref_payload",
            member_capacity,
            external_scratch.map(|scratch| scratch.member_result_ref_payload),
        );
        let member_result_field_ordinal = typed_reuse_storage_u32(
            device,
            "type_check.resident.member_result_field_ordinal",
            member_capacity,
            external_scratch.map(|scratch| scratch.member_result_field_ordinal),
        );
        let member_result_field_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.member_result_field_node",
            member_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let structs_enabled = hir_items
            .map(|items| {
                items.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_STRUCTS != 0
            })
            .unwrap_or(true);
        let struct_token_capacity = if structs_enabled {
            token_capacity.max(1)
        } else {
            1
        } as usize;
        let struct_hir_capacity = if structs_enabled {
            hir_node_capacity.max(1)
        } else {
            1
        } as usize;
        let struct_init_field_expected_ref_tag = typed_reuse_storage_u32(
            device,
            "type_check.resident.struct_init_field_expected_ref_tag",
            struct_token_capacity,
            external_scratch.map(|scratch| scratch.struct_init_field_expected_ref_tag),
        );
        let struct_init_field_expected_ref_payload = typed_reuse_storage_u32(
            device,
            "type_check.resident.struct_init_field_expected_ref_payload",
            struct_token_capacity,
            external_scratch.map(|scratch| scratch.struct_init_field_expected_ref_payload),
        );
        let struct_init_field_context_instance = typed_reuse_storage_u32(
            device,
            "type_check.resident.struct_init_field_context_instance",
            struct_token_capacity,
            external_scratch.map(|scratch| scratch.struct_init_field_context_instance),
        );
        let struct_init_field_ordinal = typed_reuse_storage_u32(
            device,
            "type_check.resident.struct_init_field_ordinal",
            struct_token_capacity,
            external_scratch.map(|scratch| scratch.struct_init_field_ordinal),
        );
        let record_family_flag_scratch = external_scratch
            .and_then(|scratch| scratch.record_family_flag)
            .or_else(|| module_path_scratch.and_then(|scratch| scratch.record_family_flag));
        let struct_init_field_ordinal_by_node =
            if let Some(record_family_flag) = record_family_flag_scratch {
                // Parser list-workspace scratch is dead once HIR records have been
                // constructed. Reuse it for the HIR-keyed struct-init ordinal table
                // and, earlier, for module/path record-family flags.
                typed_alias_storage_u32(record_family_flag, hir_node_capacity.max(1) as usize)
            } else {
                typed_storage_u32_rw(
                    device,
                    "type_check.resident.struct_init_field_ordinal_by_node",
                    hir_node_capacity.max(1) as usize,
                    wgpu::BufferUsages::empty(),
                )
            };
        let struct_init_field_decl_node_by_node = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.struct_init_field_decl_node_by_node",
            struct_hir_capacity,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let struct_lit_context_decl_token = typed_storage_u32_rw(
            device,
            "type_check.resident.struct_lit_context_decl_token",
            struct_hir_capacity,
            wgpu::BufferUsages::empty(),
        );
        let struct_lit_context_instance = typed_storage_u32_rw(
            device,
            "type_check.resident.struct_lit_context_instance",
            struct_hir_capacity,
            wgpu::BufferUsages::empty(),
        );
        let token_active_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.token_active_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let hir_active_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_active_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let token_hir_active_dispatch_args = typed_storage_u32_rw(
            device,
            "type_check.resident.token_hir_active_dispatch_args",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let hir_active_count = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_active_count",
            1,
            wgpu::BufferUsages::empty(),
        );
        let semantic_feature_flags = typed_storage_u32_rw(
            device,
            "type_check.resident.semantic_feature_flags",
            1,
            wgpu::BufferUsages::COPY_DST,
        );
        let semantic_indirect_args =
            |label| typed_storage_u32_rw(device, label, 3, wgpu::BufferUsages::INDIRECT);
        let method_token_dispatch_args =
            semantic_indirect_args("type_check.resident.method_token_dispatch_args");
        let method_hir_dispatch_args =
            semantic_indirect_args("type_check.resident.method_hir_dispatch_args");
        let method_token_hir_dispatch_args =
            semantic_indirect_args("type_check.resident.method_token_hir_dispatch_args");
        let method_radix_prefix_dispatch_args =
            semantic_indirect_args("type_check.resident.method_radix_prefix_dispatch_args");
        let method_radix_bases_dispatch_args =
            semantic_indirect_args("type_check.resident.method_radix_bases_dispatch_args");
        let predicate_token_dispatch_args =
            semantic_indirect_args("type_check.resident.predicate_token_dispatch_args");
        let predicate_hir_dispatch_args =
            semantic_indirect_args("type_check.resident.predicate_hir_dispatch_args");
        let predicate_radix_prefix_dispatch_args =
            semantic_indirect_args("type_check.resident.predicate_radix_prefix_dispatch_args");
        let predicate_radix_bases_dispatch_args =
            semantic_indirect_args("type_check.resident.predicate_radix_bases_dispatch_args");
        let predicate_single_dispatch_args =
            semantic_indirect_args("type_check.resident.predicate_single_dispatch_args");
        let match_hir_dispatch_args =
            semantic_indirect_args("type_check.resident.match_hir_dispatch_args");
        allocation_stamp!("buffers");
        let empty_hir = EmptyHirBindings::new(device, uses_hir_items, hir_node_capacity);
        let mut resources = ResourceMap::new();
        resources.buffer("gParams", &self.params_buf);
        resources.buffer("token_words", &token_buf);
        resources.buffer("token_count", &token_count_buf);
        resources.buffer("token_file_id", &token_file_id_buf);
        resources.buffer("source_bytes", &source_buf);
        resources.buffer("hir_kind", &hir_kind_buf);
        resources.buffer("hir_token_pos", &hir_token_pos_buf);
        resources.buffer("hir_token_end", &hir_token_end_buf);
        resources.buffer("hir_token_file_id", &hir_token_file_id_buf);
        resources.buffer("hir_status", &hir_status_buf);
        resources.buffer("token_active_dispatch_args", &token_active_dispatch_args);
        resources.buffer("hir_active_dispatch_args", &hir_active_dispatch_args);
        resources.buffer(
            "token_hir_active_dispatch_args",
            &token_hir_active_dispatch_args,
        );
        resources.buffer("hir_active_count", &hir_active_count);
        resources.buffer("semantic_feature_flags", &semantic_feature_flags);
        resources.buffer("method_token_dispatch_args", &method_token_dispatch_args);
        resources.buffer("method_hir_dispatch_args", &method_hir_dispatch_args);
        resources.buffer(
            "method_token_hir_dispatch_args",
            &method_token_hir_dispatch_args,
        );
        resources.buffer(
            "method_radix_prefix_dispatch_args",
            &method_radix_prefix_dispatch_args,
        );
        resources.buffer(
            "method_radix_bases_dispatch_args",
            &method_radix_bases_dispatch_args,
        );
        resources.buffer(
            "predicate_token_dispatch_args",
            &predicate_token_dispatch_args,
        );
        resources.buffer("predicate_hir_dispatch_args", &predicate_hir_dispatch_args);
        resources.buffer(
            "predicate_radix_prefix_dispatch_args",
            &predicate_radix_prefix_dispatch_args,
        );
        resources.buffer(
            "predicate_radix_bases_dispatch_args",
            &predicate_radix_bases_dispatch_args,
        );
        resources.buffer(
            "predicate_single_dispatch_args",
            &predicate_single_dispatch_args,
        );
        resources.buffer("match_hir_dispatch_args", &match_hir_dispatch_args);
        if let Some(hir_items) = hir_items {
            register_hir_item_resources(&mut resources, hir_items);
        } else {
            register_empty_hir_resources(&mut resources, &empty_hir, &hir_active_count);
        }
        resources.buffer("status", &self.status_buf);
        resources.buffer("visible_decl", &visible_decl);
        resources.buffer("visible_type", &visible_type);
        resources.buffer("hir_value_decl_name_present", &hir_value_decl_name_present);
        resources.buffer("hir_visible_decl_count_out", &hir_visible_decl_count_out);
        resources.buffer("hir_visible_decl_owner_fn", &hir_visible_decl_owner_fn);
        resources.buffer("hir_visible_decl_name_id", &hir_visible_decl_name_id);
        resources.buffer("hir_visible_decl_token", &hir_visible_decl_token);
        resources.buffer("hir_visible_decl_scope_end", &hir_visible_decl_scope_end);
        resources.buffer("hir_visible_decl_node", &hir_visible_decl_node);
        resources.buffer("hir_visible_decl_key_order", &hir_visible_decl_key_order);
        resources.buffer("hir_visible_decl_scope_tree", &hir_visible_decl_scope_tree);
        resources.buffer("module_type_path_type", &module_type_path_type);
        resources.buffer("module_type_path_status", &module_type_path_status);
        resources.buffer("module_value_path_status", &module_value_path_status);
        resources.buffer("loop_depth", &loop_depth);
        resources.buffer("enclosing_fn", &enclosing_fn);
        resources.buffer("enclosing_fn_end", &enclosing_fn_end);
        resources.buffer("fn_event_value", &fn_event_value);
        resources.buffer("fn_event_end", &fn_event_end);
        resources.buffer("fn_event_index", &fn_event_index);
        resources.buffer("fn_event_inblock", &fn_event_inblock);
        resources.buffer("block_sum", &fn_block_sum);
        resources.buffer("block_prefix", &fn_block_prefix);
        resources.buffer("call_fn_index", &call_fn_index);
        resources.buffer("call_intrinsic_tag", &call_intrinsic_tag);
        resources.buffer("fn_entrypoint_tag", &fn_entrypoint_tag);
        resources.buffer("call_return_type", &call_return_type);
        resources.buffer("call_return_type_token", &call_return_type_token);
        resources.buffer("return_fn_flags", &return_fn_flags);
        resources.buffer("return_block_flags", &return_block_flags);
        resources.buffer("call_param_count", &call_param_count);
        resources.buffer("call_param_type", &call_param_type);
        resources.buffer("call_param_ref_tag", &call_param_ref_tag);
        resources.buffer("call_param_ref_payload", &call_param_ref_payload);
        resources.buffer("call_generic_slot_type", &call_generic_slot_type);
        resources.buffer("call_generic_slot_ordinal", &call_generic_slot_ordinal);
        resources.buffer("call_const_slot_len", &call_const_slot_len);
        resources.buffer("call_param_row_count_out", &call_param_row_count_out);
        resources.buffer("call_param_row_flag", &call_param_row_flag);
        resources.buffer("call_param_row_node_type", &call_param_row_node_type);
        resources.buffer("call_param_row_node_ref_tag", &call_param_row_node_ref_tag);
        resources.buffer(
            "call_param_row_node_ref_payload",
            &call_param_row_node_ref_payload,
        );
        resources.buffer("call_param_row_node", &call_param_row_node);
        resources.buffer("call_param_row_fn_token", &call_param_row_fn_token);
        resources.buffer("call_param_row_ordinal", &call_param_row_ordinal);
        resources.buffer("call_param_row_type", &call_param_row_type);
        resources.buffer("call_param_row_ref_tag", &call_param_row_ref_tag);
        resources.buffer("call_param_row_ref_payload", &call_param_row_ref_payload);
        resources.buffer("call_param_row_start", &call_param_row_start);
        resources.buffer("call_param_row_count", &call_param_row_count);
        resources.buffer(
            "call_param_row_scan_local_prefix",
            &call_param_row_scan_local_prefix,
        );
        resources.buffer(
            "call_param_row_scan_block_sum",
            &call_param_row_scan_block_sum,
        );
        resources.buffer(
            "call_param_row_scan_prefix_a",
            &call_param_row_scan_prefix_a,
        );
        resources.buffer(
            "call_param_row_scan_prefix_b",
            &call_param_row_scan_prefix_b,
        );
        resources.buffer("call_arg_record", &call_arg_record);
        resources.buffer("call_arg_row_count_out", &call_arg_row_count_out);
        resources.buffer("call_arg_row_scan_input", &call_arg_row_scan_input);
        resources.buffer("call_arg_row_prefix", &call_arg_row_prefix);
        resources.buffer("call_arg_row_node", &call_arg_row_node);
        resources.buffer("call_arg_row_call_node", &call_arg_row_call_node);
        resources.buffer("call_arg_row_ordinal", &call_arg_row_ordinal);
        resources.buffer("call_arg_row_start", &call_arg_row_start);
        resources.buffer("call_arg_row_count", &call_arg_row_count);
        resources.buffer("call_arg_param_row", &call_arg_param_row);
        resources.buffer("call_arg_param_row_tmp", &call_arg_param_row_tmp);
        resources.buffer("call_arg_match_jump_a", &call_arg_match_jump_a);
        resources.buffer("call_arg_match_jump_b", &call_arg_match_jump_b);
        resources.buffer("call_param_match_jump_a", &call_param_match_jump_a);
        resources.buffer("call_param_match_jump_b", &call_param_match_jump_b);
        resources.buffer(
            "call_generic_claim_count_out",
            &call_generic_claim_count_out,
        );
        resources.buffer(
            "call_generic_claim_scan_input",
            &call_generic_claim_scan_input,
        );
        resources.buffer("call_generic_claim_prefix", &call_generic_claim_prefix);
        resources.buffer("call_generic_claim_callee", &call_generic_claim_callee);
        resources.buffer("call_generic_claim_slot", &call_generic_claim_slot);
        resources.buffer("call_generic_claim_type", &call_generic_claim_type);
        resources.buffer("call_generic_claim_arg_row", &call_generic_claim_arg_row);
        resources.buffer("call_generic_claim_order", &call_generic_claim_order);
        resources.buffer(
            "call_generic_claim_order_tmp",
            &call_generic_claim_order_tmp,
        );
        resources.buffer(
            "call_generic_claim_radix_dispatch_args",
            &call_generic_claim_radix_dispatch_args,
        );
        resources.buffer(
            "call_generic_claim_radix_block_histogram",
            &call_generic_claim_radix_block_histogram,
        );
        resources.buffer(
            "call_generic_claim_radix_block_bucket_prefix",
            &call_generic_claim_radix_block_bucket_prefix,
        );
        resources.buffer(
            "call_generic_claim_radix_bucket_total",
            &call_generic_claim_radix_bucket_total,
        );
        resources.buffer(
            "call_generic_claim_radix_bucket_base",
            &call_generic_claim_radix_bucket_base,
        );
        resources.buffer("call_const_claim_callee", &call_const_claim_callee);
        resources.buffer("call_const_claim_slot", &call_const_claim_slot);
        resources.buffer("call_const_claim_len", &call_const_claim_len);
        resources.buffer("call_const_claim_order", &call_const_claim_order);
        resources.buffer("call_const_claim_order_tmp", &call_const_claim_order_tmp);
        resources.buffer(
            "call_const_claim_radix_dispatch_args",
            &call_const_claim_radix_dispatch_args,
        );
        resources.buffer(
            "call_const_claim_radix_block_histogram",
            &call_const_claim_radix_block_histogram,
        );
        resources.buffer(
            "call_const_claim_radix_block_bucket_prefix",
            &call_const_claim_radix_block_bucket_prefix,
        );
        resources.buffer(
            "call_const_claim_radix_bucket_total",
            &call_const_claim_radix_bucket_total,
        );
        resources.buffer(
            "call_const_claim_radix_bucket_base",
            &call_const_claim_radix_bucket_base,
        );
        resources.buffer(
            "call_required_generic_count_out",
            &call_required_generic_count_out,
        );
        resources.buffer(
            "call_required_generic_scan_input",
            &call_required_generic_scan_input,
        );
        resources.buffer(
            "call_required_generic_prefix",
            &call_required_generic_prefix,
        );
        resources.buffer(
            "call_required_generic_scan_local_prefix",
            &call_required_generic_scan_local_prefix,
        );
        resources.buffer(
            "call_required_generic_scan_block_sum",
            &call_required_generic_scan_block_sum,
        );
        resources.buffer(
            "call_required_generic_scan_prefix_a",
            &call_required_generic_scan_prefix_a,
        );
        resources.buffer(
            "call_required_generic_scan_prefix_b",
            &call_required_generic_scan_prefix_b,
        );
        resources.buffer(
            "call_required_generic_dispatch_args",
            &call_required_generic_dispatch_args,
        );
        resources.buffer("call_has_array_arg", &call_has_array_arg);
        resources.buffer(
            "call_array_return_arg_instance",
            &call_array_return_arg_instance,
        );
        resources.buffer(
            "call_arg_row_scan_local_prefix",
            &call_arg_row_scan_local_prefix,
        );
        resources.buffer("call_arg_row_scan_block_sum", &call_arg_row_scan_block_sum);
        resources.buffer("call_arg_row_scan_prefix_a", &call_arg_row_scan_prefix_a);
        resources.buffer("call_arg_row_scan_prefix_b", &call_arg_row_scan_prefix_b);
        resources.buffer(
            "call_generic_claim_scan_local_prefix",
            &call_generic_claim_scan_local_prefix,
        );
        resources.buffer(
            "call_generic_claim_scan_block_sum",
            &call_generic_claim_scan_block_sum,
        );
        resources.buffer(
            "call_generic_claim_scan_prefix_a",
            &call_generic_claim_scan_prefix_a,
        );
        resources.buffer(
            "call_generic_claim_scan_prefix_b",
            &call_generic_claim_scan_prefix_b,
        );
        resources.buffer("function_lookup_key", &function_lookup_key);
        resources.buffer("function_lookup_fn", &function_lookup_fn);
        resources.buffer(
            "method_decl_receiver_ref_tag",
            &method_decl_receiver_ref_tag,
        );
        resources.buffer(
            "method_decl_receiver_ref_payload",
            &method_decl_receiver_ref_payload,
        );
        resources.buffer("method_decl_module_id", &method_decl_module_id);
        resources.buffer("method_decl_impl_node", &method_decl_impl_node);
        resources.buffer("method_decl_name_token", &method_decl_name_token);
        resources.buffer("method_decl_name_id", &method_decl_name_id);
        resources.buffer("method_decl_param_offset", &method_decl_param_offset);
        resources.buffer("method_decl_receiver_mode", &method_decl_receiver_mode);
        resources.buffer("method_decl_visibility", &method_decl_visibility);
        resources.buffer("method_key_to_fn_token", &method_key_to_fn_token);
        resources.buffer("sorted_method_key_order", &method_key_to_fn_token);
        resources.buffer("method_key_status", &method_key_status);
        resources.buffer("method_key_duplicate_of", &method_key_duplicate_of);
        resources.buffer(
            "method_call_receiver_ref_tag",
            &method_call_receiver_ref_tag,
        );
        resources.buffer(
            "method_call_receiver_ref_payload",
            &method_call_receiver_ref_payload,
        );
        resources.buffer("method_call_name_id", &method_call_name_id);
        resources.buffer("method_call_site_module_id", &method_call_site_module_id);
        resources.buffer("name_id_by_token", &name_id_by_token);
        resources.buffer("language_name_id", &language_name_id);
        resources.buffer("language_decl_symbol_slot", &language_decl_symbol_slot);
        resources.buffer("language_decl_kind", &language_decl_kind);
        resources.buffer("language_decl_tag", &language_decl_tag);
        resources.buffer("language_decl_name_id", &language_decl_name_id);
        resources.buffer(
            "language_type_code_by_name_id",
            &language_type_code_by_name_id,
        );
        resources.buffer(
            "language_entrypoint_tag_by_name_id",
            &language_entrypoint_tag_by_name_id,
        );
        resources.buffer(
            "language_intrinsic_tag_by_name_id",
            &language_intrinsic_tag_by_name_id,
        );
        resources.buffer("language_symbol_bytes", &language_symbol_bytes);
        resources.buffer("language_symbol_start", &language_symbol_start);
        resources.buffer("language_symbol_len", &language_symbol_len);
        resources.buffer("type_expr_ref_tag", &type_expr_ref_tag);
        resources.buffer("type_expr_ref_payload", &type_expr_ref_payload);
        resources.buffer("type_instance_kind", &type_instance_kind);
        resources.buffer("type_instance_head_token", &type_instance_head_token);
        resources.buffer(
            "type_decl_generic_param_count",
            &type_decl_generic_param_count,
        );
        resources.buffer(
            "type_decl_generic_param_count_by_node",
            &type_decl_generic_param_count_by_node,
        );
        resources.buffer(
            "type_decl_const_param_count_by_node",
            &type_decl_const_param_count_by_node,
        );
        resources.buffer("type_decl_hir_node_by_token", &type_decl_hir_node_by_token);
        resources.buffer(
            "type_generic_param_slot_by_token",
            &type_generic_param_slot_by_token,
        );
        resources.buffer(
            "type_const_param_slot_by_token",
            &type_const_param_slot_by_token,
        );
        resources.buffer("type_instance_decl_token", &type_instance_decl_token);
        resources.buffer("type_instance_arg_start", &type_instance_arg_start);
        resources.buffer("type_instance_arg_count", &type_instance_arg_count);
        resources.buffer("type_instance_arg_ref_tag", &type_instance_arg_ref_tag);
        resources.buffer(
            "type_instance_arg_ref_payload",
            &type_instance_arg_ref_payload,
        );
        resources.buffer("type_instance_arg_hash", &type_instance_arg_hash);
        resources.buffer("type_instance_arg_row_start", &type_instance_arg_row_start);
        resources.buffer(
            "type_instance_arg_row_count_out",
            &type_instance_arg_row_count_out,
        );
        resources.buffer(
            "type_instance_arg_row_ref_tag",
            &type_instance_arg_row_ref_tag,
        );
        resources.buffer(
            "type_instance_arg_row_ref_payload",
            &type_instance_arg_row_ref_payload,
        );
        resources.buffer(
            "type_instance_arg_row_scan_local_prefix",
            &type_instance_arg_row_scan_local_prefix,
        );
        resources.buffer(
            "type_instance_arg_row_scan_block_sum",
            &type_instance_arg_row_scan_block_sum,
        );
        resources.buffer(
            "type_instance_arg_row_scan_prefix_a",
            &type_instance_arg_row_scan_prefix_a,
        );
        resources.buffer(
            "type_instance_arg_row_scan_prefix_b",
            &type_instance_arg_row_scan_prefix_b,
        );
        resources.buffer(
            "aggregate_compare_scan_input",
            &aggregate_compare_scan_input,
        );
        resources.buffer("aggregate_compare_prefix", &aggregate_compare_prefix);
        resources.buffer("aggregate_compare_count_out", &aggregate_compare_count_out);
        resources.buffer(
            "aggregate_compare_expected_instance",
            &aggregate_compare_expected_instance,
        );
        resources.buffer(
            "aggregate_compare_actual_instance",
            &aggregate_compare_actual_instance,
        );
        resources.buffer(
            "aggregate_compare_error_token",
            &aggregate_compare_error_token,
        );
        resources.buffer(
            "aggregate_compare_error_detail",
            &aggregate_compare_error_detail,
        );
        resources.buffer(
            "aggregate_compare_scan_local_prefix",
            &aggregate_compare_scan_local_prefix,
        );
        resources.buffer(
            "aggregate_compare_scan_block_sum",
            &aggregate_compare_scan_block_sum,
        );
        resources.buffer(
            "aggregate_compare_scan_prefix_a",
            &aggregate_compare_scan_prefix_a,
        );
        resources.buffer(
            "aggregate_compare_scan_prefix_b",
            &aggregate_compare_scan_prefix_b,
        );
        resources.buffer("type_instance_elem_ref_tag", &type_instance_elem_ref_tag);
        resources.buffer(
            "type_instance_elem_ref_payload",
            &type_instance_elem_ref_payload,
        );
        resources.buffer("type_instance_len_kind", &type_instance_len_kind);
        resources.buffer("type_instance_len_payload", &type_instance_len_payload);
        resources.buffer("type_instance_state", &type_instance_state);
        resources.buffer("predicate_owner_node", &predicate_owner_node);
        resources.buffer("predicate_subject_token", &predicate_subject_token);
        resources.buffer("predicate_bound_token", &predicate_bound_token);
        resources.buffer("predicate_bound_decl_id", &predicate_bound_decl_id);
        resources.buffer("predicate_bound_arg_count", &predicate_bound_arg_count);
        resources.buffer(
            "predicate_bound_first_arg_token",
            &predicate_bound_first_arg_token,
        );
        resources.buffer(
            "predicate_bound_second_arg_token",
            &predicate_bound_second_arg_token,
        );
        resources.buffer("predicate_status", &predicate_status);
        resources.buffer("predicate_syntax_token", &predicate_syntax_token);
        resources.buffer(
            "predicate_method_contract_owner_node",
            &predicate_method_contract_owner_node,
        );
        resources.buffer(
            "predicate_method_contract_name_token",
            &predicate_method_contract_name_token,
        );
        resources.buffer(
            "predicate_method_contract_name_id",
            &predicate_method_contract_name_id,
        );
        resources.buffer(
            "predicate_method_contract_param_count",
            &predicate_method_contract_param_count,
        );
        resources.buffer(
            "predicate_method_contract_first_param_node",
            &predicate_method_contract_first_param_node,
        );
        resources.buffer(
            "predicate_method_contract_return_type_node",
            &predicate_method_contract_return_type_node,
        );
        resources.buffer(
            "predicate_method_contract_visibility",
            &predicate_method_contract_visibility,
        );
        resources.buffer(
            "predicate_method_contract_status",
            &predicate_method_contract_status,
        );
        resources.buffer(
            "predicate_method_contract_param_next_node",
            &predicate_method_contract_param_next_node,
        );
        resources.buffer(
            "predicate_method_contract_param_type_node",
            &predicate_method_contract_param_type_node,
        );
        resources.buffer(
            "predicate_method_contract_key_order",
            &predicate_method_contract_key_order,
        );
        resources.buffer(
            "predicate_method_param_key_order",
            &predicate_method_param_key_order,
        );
        resources.buffer(
            "predicate_method_contract_owner_range_first",
            &predicate_method_contract_owner_range_first,
        );
        resources.buffer(
            "predicate_method_contract_owner_range_count",
            &predicate_method_contract_owner_range_count,
        );
        resources.buffer(
            "predicate_method_validation_owner_node",
            &predicate_method_validation_owner_node,
        );
        resources.buffer(
            "predicate_method_validation_peer_node",
            &predicate_method_validation_peer_node,
        );
        resources.buffer(
            "predicate_method_validation_status",
            &predicate_method_validation_status,
        );
        resources.buffer(
            "predicate_method_validation_detail_token",
            &predicate_method_validation_detail_token,
        );
        resources.buffer(
            "predicate_method_validation_first_error_row",
            &predicate_method_validation_first_error_row,
        );
        resources.buffer("predicate_owner_key_order", &predicate_owner_key_order);
        resources.buffer("predicate_impl_key_order", &predicate_impl_key_order);
        resources.buffer(
            "predicate_obligation_count_by_call",
            &predicate_obligation_count_by_call,
        );
        resources.buffer(
            "predicate_obligation_prefix_by_call",
            &predicate_obligation_prefix_by_call,
        );
        resources.buffer(
            "predicate_obligation_pair_total",
            &predicate_obligation_pair_total,
        );
        resources.buffer("fn_return_ref_tag", &fn_return_ref_tag);
        resources.buffer("fn_return_ref_payload", &fn_return_ref_payload);
        resources.buffer("decl_type_ref_tag", &decl_type_ref_tag);
        resources.buffer("decl_type_ref_payload", &decl_type_ref_payload);
        resources.buffer(
            "member_result_context_instance",
            &member_result_context_instance,
        );
        resources.buffer("member_result_ref_tag", &member_result_ref_tag);
        resources.buffer("member_result_ref_payload", &member_result_ref_payload);
        resources.buffer("member_result_field_ordinal", &member_result_field_ordinal);
        resources.buffer("member_result_field_node", &member_result_field_node);
        resources.buffer(
            "struct_init_field_expected_ref_tag",
            &struct_init_field_expected_ref_tag,
        );
        resources.buffer(
            "struct_init_field_expected_ref_payload",
            &struct_init_field_expected_ref_payload,
        );
        resources.buffer(
            "struct_init_field_context_instance",
            &struct_init_field_context_instance,
        );
        resources.buffer("struct_init_field_ordinal", &struct_init_field_ordinal);
        resources.buffer(
            "struct_init_field_ordinal_by_node",
            &struct_init_field_ordinal_by_node,
        );
        resources.buffer(
            "struct_init_field_decl_node_by_node",
            &struct_init_field_decl_node_by_node,
        );
        resources.buffer(
            "struct_lit_context_decl_token",
            &struct_lit_context_decl_token,
        );
        resources.buffer("struct_lit_context_instance", &struct_lit_context_instance);
        resources.buffer("generic_decl_owner_by_node", &generic_decl_owner_by_node_a);
        resources.buffer("generic_param_count_out", &generic_param_count_out);
        resources.buffer("generic_param_owner_node", &generic_param_owner_node);
        resources.buffer("generic_param_name_id", &generic_param_name_id);
        resources.buffer("generic_param_token", &generic_param_token);
        resources.buffer("generic_param_kind", &generic_param_kind);
        resources.buffer("generic_param_key_order", &generic_param_key_order);
        allocation_stamp!("resources");
        let hir_active_dispatch = reflected_bind_group_from_resources(
            device,
            "type_check_resident_hir_active_dispatch_args",
            &passes.hir_active_dispatch_args,
            &resources,
        )?;
        let semantic_features_collect = reflected_bind_group_from_resources(
            device,
            "type_check_resident_semantic_features_collect",
            &passes.semantic_features_collect,
            &resources,
        )?;
        let semantic_features_dispatch_args = reflected_bind_group_from_resources(
            device,
            "type_check_resident_semantic_features_dispatch_args",
            &passes.semantic_features_dispatch_args,
            &resources,
        )?;
        let language_name_bind_groups =
            create_language_name_bind_groups(device, passes, &resources)?;
        let name_bind_groups = create_name_bind_groups_with_passes(
            passes,
            device,
            NameInput {
                params: &self.params_buf,
                source_len,
                cap: name_capacity,
                token_blocks: token_scan_n_blocks,
                name_blocks: name_n_blocks,
                steps: &name_scan_steps,
                token_words: token_buf,
                token_count: token_count_buf,
                source_bytes: source_buf,
                status: &self.status_buf,
                lexemes: NameLexemeRows {
                    flag: &name_lexeme_flag,
                    kind: &name_lexeme_kind,
                    prefix: &name_lexeme_prefix,
                },
                scan: ScanRows {
                    local_prefix: &name_scan_local_prefix,
                    block_sum: &name_scan_block_sum,
                    prefix_a: &name_scan_prefix_a,
                    prefix_b: &name_scan_prefix_b,
                },
                total: &name_scan_total,
                max_len: &name_max_len,
                spans: &name_spans,
                order_in: &name_order_in,
                order_tmp: &name_order_tmp,
                symbols: SymbolRows {
                    bytes: &language_symbol_bytes,
                    start: &language_symbol_start,
                    len: &language_symbol_len,
                },
                ids: NameIdRows {
                    by_token: &name_id_by_token,
                    language: &language_name_id,
                    sorted: &sorted_name_id,
                    by_input: &name_id_by_input,
                    unique_count: &unique_name_count,
                },
                radix: RadixRows {
                    histogram: &radix_block_histogram,
                    bucket_prefix: &radix_block_bucket_prefix,
                    bucket_total: &radix_bucket_total,
                    bucket_base: &radix_bucket_base,
                },
            },
        )?;
        allocation_stamp!("core_and_name_bind_groups");
        let module_path = if let Some(hir_items) = hir_items {
            Some(create_module_path_state_with_passes(
                passes,
                device,
                ModulePathCreateInputs {
                    params: &self.params_buf,
                    source_file_capacity,
                    token_capacity,
                    hir_node_capacity,
                    parser_hir_node_capacity,
                    token_buf,
                    token_count_buf,
                    hir_status_buf,
                    hir_kind_buf,
                    hir_token_pos_buf,
                    hir_token_end_buf,
                    status_buf: &self.status_buf,
                    hir_active_count_buf: &hir_active_count,
                    hir_items,
                    name_id_by_token: &name_id_by_token,
                    language_name_id: &language_name_id,
                    decl_name_token_scratch: &name_lexeme_flag,
                    decl_id_by_name_token_scratch: &name_lexeme_kind,
                    decl_kind_scratch: &name_lexeme_prefix,
                    decl_hir_node_scratch: &name_order_in,
                    decl_parent_type_decl_scratch: &name_order_tmp,
                    module_type_path_type: &module_type_path_type,
                    module_type_path_status: &module_type_path_status,
                    module_value_path_expr_head: &module_value_path_expr_head,
                    module_value_path_call_head: &module_value_path_call_head,
                    module_value_path_call_open: &module_value_path_call_open,
                    module_value_path_call_path_id: &module_value_path_call_path_id,
                    module_value_path_call_leaf: &module_value_path_call_leaf,
                    module_value_path_associated_method_token:
                        &module_value_path_associated_method_token,
                    module_value_path_associated_receiver_token:
                        &module_value_path_associated_receiver_token,
                    module_value_path_const_head: &module_value_path_const_head,
                    module_value_path_const_end: &module_value_path_const_end,
                    module_value_path_status: &module_value_path_status,
                    predicate_syntax_token: &predicate_syntax_token,
                    visible_decl: &visible_decl,
                    visible_type: &visible_type,
                    enclosing_fn: &enclosing_fn,
                    call_fn_index: &call_fn_index,
                    call_return_type: &call_return_type,
                    call_return_type_token: &call_return_type_token,
                    call_generic_slot_type: &call_generic_slot_type,
                    call_generic_slot_ordinal: &call_generic_slot_ordinal,
                    method_call_name_id: &method_call_name_id,
                    call_param_count: &call_param_count,
                    call_arg_record: &call_arg_record,
                    call_arg_row_node: &call_arg_row_node,
                    call_arg_row_call_node: &call_arg_row_call_node,
                    call_arg_row_ordinal: &call_arg_row_ordinal,
                    call_arg_row_start: &call_arg_row_start,
                    call_arg_row_count: &call_arg_row_count,
                    type_expr_ref_tag: &type_expr_ref_tag,
                    type_expr_ref_payload: &type_expr_ref_payload,
                    type_instance_kind: &type_instance_kind,
                    type_instance_decl_token: &type_instance_decl_token,
                    type_instance_arg_start: &type_instance_arg_start,
                    type_instance_arg_count: &type_instance_arg_count,
                    type_instance_arg_ref_tag: &type_instance_arg_ref_tag,
                    type_instance_arg_ref_payload: &type_instance_arg_ref_payload,
                    type_decl_generic_param_count: &type_decl_generic_param_count,
                    type_generic_param_slot_by_token: &type_generic_param_slot_by_token,
                    type_instance_state: &type_instance_state,
                    decl_type_ref_tag: &decl_type_ref_tag,
                    decl_type_ref_payload: &decl_type_ref_payload,
                    fn_return_ref_tag: &fn_return_ref_tag,
                    fn_return_ref_payload: &fn_return_ref_payload,
                    record_family_bits_scratch: &fn_entrypoint_tag,
                    record_family_flag_scratch: &struct_init_field_ordinal_by_node,
                    external_scratch: module_path_scratch,
                },
            )?)
        } else {
            None
        };
        allocation_stamp!("module_path");
        if let Some(module_path) = module_path.as_ref() {
            resources.buffer(
                "module_table_count_out",
                &module_path.module_table_count_out,
            );
            resources.buffer("module_id_by_file_id", &module_path.module_id_by_file_id);
            resources.buffer("path_count_out", &module_path.path_count_out);
            resources.buffer("path_kind", &module_path.path_kind);
            resources.buffer("path_segment_count", &module_path.path_segment_count);
            resources.buffer("path_segment_base", &module_path.path_segment_base);
            resources.buffer("path_segment_name_id", &module_path.path_segment_name_id);
            resources.buffer("path_segment_token", &module_path.path_segment_token);
            resources.buffer("path_owner_hir", &module_path.path_owner_hir);
            resources.buffer("path_owner_token", &module_path.path_owner_token);
            resources.buffer("path_id_by_owner_hir", &module_path.path_id_by_owner_hir);
            resources.buffer(
                "path_id_by_owner_token",
                &module_path.path_id_by_owner_token,
            );
            resources.buffer("path_owner_module_id", &module_path.path_owner_module_id);
            resources.buffer("resolved_type_decl", &module_path.resolved_type_decl);
            resources.buffer("resolved_value_decl", &module_path.resolved_value_decl);
            resources.buffer("resolved_value_status", &module_path.resolved_value_status);
            resources.buffer("decl_token_start", &module_path.decl_token_start);
            resources.buffer(
                "decl_type_key_count_out",
                &module_path.decl_type_key_count_out,
            );
            resources.buffer(
                "decl_type_key_to_decl_id",
                &module_path.decl_type_key_to_decl_id,
            );
            resources.buffer(
                "decl_value_key_count_out",
                &module_path.decl_value_key_count_out,
            );
            resources.buffer(
                "decl_value_key_to_decl_id",
                &module_path.decl_value_key_to_decl_id,
            );
            resources.buffer("decl_module_id", &module_path.decl_module_id);
            resources.buffer("decl_name_id", &module_path.decl_name_id);
            resources.buffer("decl_name_token", &module_path.decl_name_token);
            resources.buffer("decl_kind", &module_path.decl_kind);
            resources.buffer(
                "import_visible_type_count_out",
                &module_path.import_visible_type_count_out,
            );
            resources.buffer(
                "import_visible_type_key_module_id",
                &module_path.import_visible_type_key_module_id,
            );
            resources.buffer(
                "import_visible_type_key_name_id",
                &module_path.import_visible_type_key_name_id,
            );
            resources.buffer(
                "import_visible_type_key_to_decl_id",
                &module_path.import_visible_type_key_to_decl_id,
            );
            resources.buffer(
                "import_visible_type_status",
                &module_path.import_visible_type_status,
            );
            resources.buffer(
                "import_visible_value_count_out",
                &module_path.import_visible_value_count_out,
            );
            resources.buffer(
                "import_visible_value_key_module_id",
                &module_path.import_visible_value_key_module_id,
            );
            resources.buffer(
                "import_visible_value_key_name_id",
                &module_path.import_visible_value_key_name_id,
            );
            resources.buffer(
                "import_visible_value_key_to_decl_id",
                &module_path.import_visible_value_key_to_decl_id,
            );
            resources.buffer(
                "import_visible_value_status",
                &module_path.import_visible_value_status,
            );
        } else {
            resources.add(
                "module_table_count_out",
                resources["hir_active_count"].clone(),
            );
            resources.add("module_id_by_file_id", resources["visible_decl"].clone());
            resources.add("path_count_out", resources["hir_active_count"].clone());
            resources.add("path_kind", resources["parent"].clone());
            resources.add("path_segment_count", resources["parent"].clone());
            resources.add("path_segment_base", resources["parent"].clone());
            resources.add("path_segment_name_id", resources["parent"].clone());
            resources.add("path_segment_token", resources["parent"].clone());
            resources.add("path_owner_hir", resources["parent"].clone());
            resources.add("path_owner_token", resources["parent"].clone());
            resources.add("path_id_by_owner_hir", resources["parent"].clone());
            resources.add("path_id_by_owner_token", resources["parent"].clone());
            resources.add(
                "path_owner_module_id",
                resources["module_value_path_status"].clone(),
            );
            resources.add("resolved_type_decl", resources["visible_decl"].clone());
            resources.add("resolved_value_decl", resources["visible_decl"].clone());
            resources.add("resolved_value_status", resources["visible_decl"].clone());
            resources.add("decl_token_start", resources["visible_decl"].clone());
            resources.add(
                "decl_type_key_count_out",
                resources["hir_active_count"].clone(),
            );
            resources.add(
                "decl_type_key_to_decl_id",
                resources["visible_decl"].clone(),
            );
            resources.add(
                "decl_value_key_count_out",
                resources["hir_active_count"].clone(),
            );
            resources.add(
                "decl_value_key_to_decl_id",
                resources["visible_decl"].clone(),
            );
            resources.add("decl_module_id", resources["visible_decl"].clone());
            resources.add("decl_name_id", resources["visible_decl"].clone());
            resources.add("decl_name_token", resources["visible_decl"].clone());
            resources.add("decl_kind", resources["visible_decl"].clone());
            resources.add(
                "import_visible_type_count_out",
                resources["hir_active_count"].clone(),
            );
            resources.add(
                "import_visible_type_key_module_id",
                resources["visible_decl"].clone(),
            );
            resources.add(
                "import_visible_type_key_name_id",
                resources["visible_decl"].clone(),
            );
            resources.add(
                "import_visible_type_key_to_decl_id",
                resources["visible_decl"].clone(),
            );
            resources.add(
                "import_visible_type_status",
                resources["visible_decl"].clone(),
            );
            resources.add(
                "import_visible_value_count_out",
                resources["hir_active_count"].clone(),
            );
            resources.add(
                "import_visible_value_key_module_id",
                resources["visible_decl"].clone(),
            );
            resources.add(
                "import_visible_value_key_name_id",
                resources["visible_decl"].clone(),
            );
            resources.add(
                "import_visible_value_key_to_decl_id",
                resources["visible_decl"].clone(),
            );
            resources.add(
                "import_visible_value_status",
                resources["visible_decl"].clone(),
            );
        }
        resources.buffer("module_value_path_call_open", &module_value_path_call_open);
        resources.buffer(
            "module_value_path_call_path_id",
            &module_value_path_call_path_id,
        );
        resources.buffer("module_value_path_call_leaf", &module_value_path_call_leaf);
        resources.buffer(
            "module_value_path_associated_method_token",
            &module_value_path_associated_method_token,
        );
        resources.buffer(
            "module_value_path_associated_receiver_token",
            &module_value_path_associated_receiver_token,
        );
        let conditions_hir = reflected_bind_group_from_resources(
            device,
            "type_check_resident_conditions_hir",
            &passes.conditions_hir,
            &resources,
        )?;
        let aggregate_compare_scan = create_counted_u32_scan_bind_groups_with_passes(
            passes,
            device,
            "type_check.conditions.aggregate_compare_scan",
            &aggregate_compare_scan_steps,
            &hir_active_count,
            &aggregate_compare_scan_input,
            &aggregate_compare_prefix,
            &aggregate_compare_count_out,
            &aggregate_compare_scan_local_prefix,
            &aggregate_compare_scan_block_sum,
            &aggregate_compare_scan_prefix_a,
            &aggregate_compare_scan_prefix_b,
        )?;
        let aggregate_compare_dispatch = bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.conditions.aggregate_compare_dispatch"),
            &passes.count_dispatch_args,
            0,
            &[
                (
                    "gParams",
                    aggregate_compare_dispatch_params.as_entire_binding(),
                ),
                ("count_in", aggregate_compare_count_out.as_entire_binding()),
                (
                    "dispatch_args",
                    aggregate_compare_dispatch_args.as_entire_binding(),
                ),
            ],
        )?;
        let conditions_aggregate_args = reflected_bind_group_from_resources(
            device,
            "type_check_resident_conditions_aggregate_args",
            &passes.conditions_aggregate_args,
            &resources,
        )?;
        let calls = create_call_bind_groups(
            device,
            passes,
            &resources,
            token_capacity,
            call_arg_row_capacity,
            call_generic_claim_capacity,
            &call_generic_claim_radix_dispatch_args,
            &call_const_claim_radix_dispatch_args,
            &call_required_generic_dispatch_args,
            CompactCallRowScanInput {
                scan_steps: &call_param_segment_scan_steps,
                scan_count: token_count_buf,
                scan_input: &call_param_count,
                scan_output_prefix: &call_param_row_start,
                scan_total: &call_param_row_count_out,
                scan_local_prefix: &call_param_row_scan_local_prefix,
                scan_block_sum: &call_param_row_scan_block_sum,
                scan_prefix_a: &call_param_row_scan_prefix_a,
                scan_prefix_b: &call_param_row_scan_prefix_b,
                n_blocks: call_param_segment_scan_n_blocks,
            },
            CompactCallRowScanInput {
                scan_steps: &call_arg_row_scan_steps,
                scan_count: &hir_active_count,
                scan_input: &call_arg_row_scan_input,
                scan_output_prefix: &call_arg_row_prefix,
                scan_total: &call_arg_row_count_out,
                scan_local_prefix: &call_arg_row_scan_local_prefix,
                scan_block_sum: &call_arg_row_scan_block_sum,
                scan_prefix_a: &call_arg_row_scan_prefix_a,
                scan_prefix_b: &call_arg_row_scan_prefix_b,
                n_blocks: call_arg_row_scan_n_blocks,
            },
            CompactCallRowScanInput {
                scan_steps: &call_arg_row_scan_steps,
                scan_count: &call_arg_row_count_out,
                scan_input: &call_generic_claim_scan_input,
                scan_output_prefix: &call_generic_claim_prefix,
                scan_total: &call_generic_claim_count_out,
                scan_local_prefix: &call_generic_claim_scan_local_prefix,
                scan_block_sum: &call_generic_claim_scan_block_sum,
                scan_prefix_a: &call_generic_claim_scan_prefix_a,
                scan_prefix_b: &call_generic_claim_scan_prefix_b,
                n_blocks: call_arg_row_scan_n_blocks,
            },
            CompactCallRowScanInput {
                scan_steps: &call_arg_row_scan_steps,
                scan_count: &hir_active_count,
                scan_input: &call_required_generic_scan_input,
                scan_output_prefix: &call_required_generic_prefix,
                scan_total: &call_required_generic_count_out,
                scan_local_prefix: &call_required_generic_scan_local_prefix,
                scan_block_sum: &call_required_generic_scan_block_sum,
                scan_prefix_a: &call_required_generic_scan_prefix_a,
                scan_prefix_b: &call_required_generic_scan_prefix_b,
                n_blocks: call_arg_row_scan_n_blocks,
            },
        )?;
        allocation_stamp!("conditions_and_calls");
        let visible_scratch = ResidentVisibleScratch::new(
            device,
            module_path.as_ref(),
            hir_visible_decl_scan_capacity,
            hir_decl_scan_n_blocks,
        );
        visible_scratch.register_resources(&mut resources);
        resources.buffer("generic_param_flag", &visible_scratch.flag);
        resources.buffer("generic_param_prefix", &visible_scratch.prefix);
        resources.buffer(
            "generic_param_scan_local_prefix",
            &visible_scratch.scan_local_prefix,
        );
        resources.buffer(
            "generic_param_scan_block_sum",
            &visible_scratch.scan_block_sum,
        );
        resources.buffer(
            "generic_param_scan_prefix_a",
            &visible_scratch.scan_prefix_a,
        );
        resources.buffer(
            "generic_param_scan_prefix_b",
            &visible_scratch.scan_prefix_b,
        );
        resources.buffer(
            "generic_decl_owner_by_node_a",
            &generic_decl_owner_by_node_a,
        );
        resources.buffer(
            "generic_decl_owner_by_node_b",
            &generic_decl_owner_by_node_b,
        );
        resources.buffer("generic_decl_parent_jump_a", &generic_decl_parent_jump_a);
        resources.buffer("generic_decl_parent_jump_b", &generic_decl_parent_jump_b);
        resources.buffer("generic_decl_owner_by_node", &generic_decl_owner_by_node_a);
        resources.buffer("generic_param_count_out", &generic_param_count_out);
        resources.buffer("generic_param_owner_node", &generic_param_owner_node);
        resources.buffer("generic_param_name_id", &generic_param_name_id);
        resources.buffer("generic_param_token", &generic_param_token);
        resources.buffer("generic_param_node", &generic_param_node);
        resources.buffer("generic_param_kind", &generic_param_kind);
        resources.buffer("generic_param_key_order", &generic_param_key_order);
        resources.buffer("generic_param_key_order_tmp", &generic_param_key_order_tmp);
        resources.buffer("generic_param_slot_order", &generic_param_slot_order);
        resources.buffer(
            "generic_param_slot_order_tmp",
            &generic_param_slot_order_tmp,
        );
        resources.buffer(
            "generic_param_key_radix_dispatch_args",
            &hir_visible_decl_key_radix_dispatch_args,
        );
        resources.buffer(
            "generic_param_key_radix_block_histogram",
            &hir_visible_decl_key_radix_block_histogram,
        );
        resources.buffer(
            "generic_param_key_radix_block_bucket_prefix",
            &hir_visible_decl_key_radix_block_bucket_prefix,
        );
        resources.buffer(
            "generic_param_key_radix_bucket_total",
            &hir_visible_decl_key_radix_bucket_total,
        );
        resources.buffer(
            "generic_param_key_radix_bucket_base",
            &hir_visible_decl_key_radix_bucket_base,
        );
        resources.buffer("struct_field_key_order", &struct_field_key_order);
        resources.buffer("struct_field_key_order_tmp", &struct_field_key_order_tmp);
        resources.buffer(
            "struct_field_key_radix_dispatch_args",
            &struct_field_key_radix_dispatch_args,
        );
        resources.buffer(
            "struct_field_key_radix_block_histogram",
            &struct_field_key_radix_block_histogram,
        );
        resources.buffer(
            "struct_field_key_radix_block_bucket_prefix",
            &struct_field_key_radix_block_bucket_prefix,
        );
        resources.buffer(
            "struct_field_key_radix_bucket_total",
            &struct_field_key_radix_bucket_total,
        );
        resources.buffer(
            "struct_field_key_radix_bucket_base",
            &struct_field_key_radix_bucket_base,
        );
        let predicates = if let Some(module_path) = &module_path {
            Some(create_predicate_bind_groups(
                device,
                passes,
                PredicateInput {
                    token_capacity,
                    predicate_capacity: predicate_capacity_u32,
                    predicate_blocks: predicate_key_radix_n_blocks,
                    params: &self.params_buf,
                    hir_active_count: &hir_active_count,
                    hir_status: hir_status_buf,
                    hir_token_pos: hir_token_pos_buf,
                    hir_items: hir_items.expect("predicate collection requires HIR item buffers"),
                    module_path,
                    name_id_by_token: &name_id_by_token,
                    generic_param_count_by_node: &type_decl_generic_param_count_by_node,
                    generic_param_slot_by_token: &type_generic_param_slot_by_token,
                    type_expr_ref_tag: &type_expr_ref_tag,
                    type_expr_ref_payload: &type_expr_ref_payload,
                    type_code_by_name: &language_type_code_by_name_id,
                    rows: PredicateRows {
                        owner_node: &predicate_owner_node,
                        subject_token: &predicate_subject_token,
                        bound_token: &predicate_bound_token,
                        bound_decl_id: &predicate_bound_decl_id,
                        bound_arg_count: &predicate_bound_arg_count,
                        first_arg_token: &predicate_bound_first_arg_token,
                        second_arg_token: &predicate_bound_second_arg_token,
                        status: &predicate_status,
                        owner_order: &predicate_owner_key_order,
                        owner_order_tmp: &predicate_owner_key_order_tmp,
                        impl_order: &predicate_impl_key_order,
                        impl_order_tmp: &predicate_impl_key_order_tmp,
                        method_contract_order: &predicate_method_contract_key_order,
                        method_contract_order_tmp: &predicate_method_contract_key_order_tmp,
                        method_param_order: &predicate_method_param_key_order,
                        method_param_order_tmp: &predicate_method_param_key_order_tmp,
                        radix: RadixRows {
                            histogram: &predicate_key_radix_block_histogram,
                            bucket_prefix: &predicate_key_radix_block_bucket_prefix,
                            bucket_total: &predicate_key_radix_bucket_total,
                            bucket_base: &predicate_key_radix_bucket_base,
                        },
                        method_contract_owner_node: &predicate_method_contract_owner_node,
                        method_contract_name_token: &predicate_method_contract_name_token,
                        method_contract_name_id: &predicate_method_contract_name_id,
                        method_contract_param_count: &predicate_method_contract_param_count,
                        method_contract_first_param_node:
                            &predicate_method_contract_first_param_node,
                        method_contract_return_type_node:
                            &predicate_method_contract_return_type_node,
                        method_contract_visibility: &predicate_method_contract_visibility,
                        method_contract_status: &predicate_method_contract_status,
                        method_contract_param_next_node: &predicate_method_contract_param_next_node,
                        method_contract_param_type_node: &predicate_method_contract_param_type_node,
                        method_contract_owner_range_first:
                            &predicate_method_contract_owner_range_first,
                        method_contract_owner_range_count:
                            &predicate_method_contract_owner_range_count,
                    },
                    obligation_rows: PredicateObligationRows {
                        count_by_call: &predicate_obligation_count_by_call,
                        prefix_by_call: &predicate_obligation_prefix_by_call,
                        pair_total: &predicate_obligation_pair_total,
                        scan: ScanRows {
                            local_prefix: &predicate_obligation_scan_local_prefix,
                            block_sum: &predicate_obligation_scan_block_sum,
                            prefix_a: &predicate_obligation_scan_prefix_a,
                            prefix_b: &predicate_obligation_scan_prefix_b,
                        },
                        pair_dispatch_args: &predicate_obligation_pair_dispatch_args,
                    },
                },
                &resources,
            )?)
        } else {
            None
        };
        allocation_stamp!("predicates");
        let type_instances = create_type_instance_bind_groups(
            device,
            passes,
            &resources,
            token_capacity,
            hir_node_capacity,
            &hir_visible_decl_key_radix_dispatch_args,
            &struct_field_key_radix_dispatch_args,
            hir_decl_scan_n_blocks,
            &hir_decl_scan_steps,
        )?;
        allocation_stamp!("type_instances");
        let method_module_id_by_file_id = module_path
            .as_ref()
            .map(|module_path| &module_path.module_id_by_file_id)
            .unwrap_or(&method_module_id_by_file_id_implicit_root);
        let method_module_count_out = module_path
            .as_ref()
            .map(|module_path| &module_path.module_count_out)
            .unwrap_or(&method_module_count_out_implicit_root);
        resources.buffer("module_id_by_file_id", method_module_id_by_file_id);
        resources.buffer("module_count_out", method_module_count_out);

        let method_key_bind_groups = create_method_key_bind_groups(
            device,
            passes,
            MethodKeyInput {
                label: "type_check_resident_methods",
                cap: token_capacity,
                blocks: name_n_blocks,
                token_count: token_count_buf,
                module_count: method_module_count_out,
                decl: MethodDeclRows {
                    impl_node: &method_decl_impl_node,
                    recv_tag: &method_decl_receiver_ref_tag,
                    recv_payload: &method_decl_receiver_ref_payload,
                    module_id: &method_decl_module_id,
                    name_token: &method_decl_name_token,
                    name_id: &method_decl_name_id,
                    visibility: &method_decl_visibility,
                },
                module_type_path_type: &module_type_path_type,
                type_instance_decl_token: &type_instance_decl_token,
                type_instance_arg_start: &type_instance_arg_start,
                type_instance_arg_count: &type_instance_arg_count,
                type_instance_arg_ref_tag: &type_instance_arg_ref_tag,
                type_instance_arg_ref_payload: &type_instance_arg_ref_payload,
                type_instance_arg_hash: &type_instance_arg_hash,
                type_instance_arg_row_start: &type_instance_arg_row_start,
                type_instance_arg_row_count_out: &type_instance_arg_row_count_out,
                type_instance_arg_row_ref_tag: &type_instance_arg_row_ref_tag,
                type_instance_arg_row_ref_payload: &type_instance_arg_row_ref_payload,
                keys: MethodKeyRows {
                    to_fn_token: &method_key_to_fn_token,
                    order_tmp: &method_key_order_tmp,
                    status: &method_key_status,
                    duplicate_of: &method_key_duplicate_of,
                },
                radix: RadixRows {
                    histogram: &method_key_radix_block_histogram,
                    bucket_prefix: &method_key_radix_block_bucket_prefix,
                    bucket_total: &method_key_radix_bucket_total,
                    bucket_base: &method_key_radix_bucket_base,
                },
                status: &self.status_buf,
            },
        )?;
        let methods =
            create_method_bind_groups(device, passes, &resources, method_key_bind_groups)?;
        allocation_stamp!("methods");

        let returns_clear = reflected_bind_group_from_resources(
            device,
            "type_check_resident_returns_clear",
            &passes.returns_clear,
            &resources,
        )?;
        let returns_mark = reflected_bind_group_from_resources(
            device,
            "type_check_resident_returns_mark",
            &passes.returns_mark,
            &resources,
        )?;
        let returns_mark_if = reflected_bind_group_from_resources(
            device,
            "type_check_resident_returns_mark_if",
            &passes.returns_mark_if,
            &resources,
        )?;
        let returns_validate = reflected_bind_group_from_resources(
            device,
            "type_check_resident_returns_validate",
            &passes.returns_validate,
            &resources,
        )?;
        let control = reflected_bind_group_from_resources(
            device,
            "type_check_resident_control",
            &passes.control_hir,
            &resources,
        )?;
        let scope_hir = reflected_bind_group_from_resources(
            device,
            "type_check_resident_scope_hir",
            &passes.scope_hir,
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
        let visible_bind_groups = create_resident_visible_bind_groups(
            passes,
            device,
            &resources,
            VisibleShape {
                hir_nodes: hir_node_capacity,
                scan_blocks: hir_decl_scan_n_blocks,
                record_capacity: hir_visible_decl_capacity,
                record_blocks: hir_decl_record_n_blocks,
                leaf_base: hir_decl_tree_leaf_base,
            },
            &hir_decl_scan_steps,
            VisibleRows {
                active_count: &hir_active_count,
                semantic_count: hir_items
                    .map(|items| items.semantic_count)
                    .unwrap_or(&hir_active_count),
                flag: &visible_scratch.flag,
                prefix: &visible_scratch.prefix,
                scan: visible_scratch.scan_rows(),
                count_out: &hir_visible_decl_count_out,
                owner_fn: &hir_visible_decl_owner_fn,
                name_id: &hir_visible_decl_name_id,
                token: &hir_visible_decl_token,
                scope_end: &hir_visible_decl_scope_end,
                order: &hir_visible_decl_key_order,
                order_tmp: &hir_visible_decl_key_order_tmp,
                key_args: &hir_visible_decl_key_radix_dispatch_args,
                key_radix: RadixRows {
                    histogram: &hir_visible_decl_key_radix_block_histogram,
                    bucket_prefix: &hir_visible_decl_key_radix_block_bucket_prefix,
                    bucket_total: &hir_visible_decl_key_radix_bucket_total,
                    bucket_base: &hir_visible_decl_key_radix_bucket_base,
                },
                scope_tree: &hir_visible_decl_scope_tree,
            },
        )?;
        allocation_stamp!("control_and_visible");
        let _ = allocation_last;
        drop(resources);

        Ok(ResidentTypeCheckState {
            cache_key: ResidentTypeCheckCacheKey {
                source_file_capacity,
                token_capacity,
                hir_node_capacity,
                parser_hir_node_capacity,
                module_record_capacity: hir_items
                    .map(|items| items.module_record_capacity)
                    .unwrap_or(token_capacity)
                    .max(1),
                call_param_row_capacity,
                call_arg_row_capacity,
                input_fingerprint,
                uses_hir_items,
            },
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
            language_entrypoint_tag_by_name_id,
            language_intrinsic_tag_by_name_id,
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
            module_value_path_call_path_id,
            module_value_path_call_leaf,
            module_value_path_associated_method_token,
            module_value_path_associated_receiver_token,
            module_value_path_const_head,
            module_value_path_const_end,
            module_value_path_status,
            visible_decl,
            visible_type,
            hir_value_decl_name_present,
            hir_visible_decl_flag: visible_scratch.flag,
            hir_visible_decl_prefix: visible_scratch.prefix,
            hir_visible_decl_scan_local_prefix: visible_scratch.scan_local_prefix,
            hir_visible_decl_scan_block_sum: visible_scratch.scan_block_sum,
            hir_visible_decl_scan_prefix_a: visible_scratch.scan_prefix_a,
            hir_visible_decl_scan_prefix_b: visible_scratch.scan_prefix_b,
            hir_visible_decl_count_out,
            hir_visible_decl_owner_fn,
            hir_visible_decl_name_id,
            hir_visible_decl_token,
            hir_visible_decl_scope_end,
            hir_visible_decl_node,
            hir_visible_decl_key_order,
            hir_visible_decl_key_order_tmp,
            hir_visible_decl_key_radix_dispatch_args,
            hir_visible_decl_key_radix_block_histogram,
            hir_visible_decl_key_radix_block_bucket_prefix,
            hir_visible_decl_key_radix_bucket_total,
            hir_visible_decl_key_radix_bucket_base,
            hir_visible_decl_scope_tree,
            generic_param_count_out,
            generic_param_owner_node,
            generic_param_name_id,
            generic_param_token,
            generic_param_node,
            generic_param_kind,
            generic_param_key_order,
            generic_param_key_order_tmp,
            generic_param_slot_order,
            generic_param_slot_order_tmp,
            generic_decl_owner_by_node_a,
            generic_decl_owner_by_node_b,
            generic_decl_parent_jump_a,
            generic_decl_parent_jump_b,
            token_active_dispatch_args,
            hir_active_dispatch_args,
            token_hir_active_dispatch_args,
            hir_active_count,
            hir_active_dispatch,
            semantic_feature_flags,
            method_token_dispatch_args,
            method_hir_dispatch_args,
            method_token_hir_dispatch_args,
            method_radix_prefix_dispatch_args,
            method_radix_bases_dispatch_args,
            predicate_token_dispatch_args,
            predicate_hir_dispatch_args,
            predicate_radix_prefix_dispatch_args,
            predicate_radix_bases_dispatch_args,
            predicate_single_dispatch_args,
            match_hir_dispatch_args,
            semantic_features_collect,
            semantic_features_dispatch_args,
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
            return_fn_flags,
            return_block_flags,
            call_param_count,
            call_param_type,
            call_param_ref_tag,
            call_param_ref_payload,
            call_generic_slot_type,
            call_generic_slot_ordinal,
            call_const_slot_len,
            call_param_row_count_out,
            call_param_row_flag,
            call_param_row_node_type,
            call_param_row_node_ref_tag,
            call_param_row_node_ref_payload,
            call_param_row_node,
            call_param_row_fn_token,
            call_param_row_ordinal,
            call_param_row_type,
            call_param_row_ref_tag,
            call_param_row_ref_payload,
            call_param_row_start,
            call_param_row_count,
            call_param_row_scan_local_prefix,
            call_param_row_scan_block_sum,
            call_param_row_scan_prefix_a,
            call_param_row_scan_prefix_b,
            call_arg_record,
            call_arg_row_count_out,
            call_arg_row_scan_input,
            call_arg_row_prefix,
            call_arg_row_node,
            call_arg_row_call_node,
            call_arg_row_ordinal,
            call_arg_row_start,
            call_arg_row_count,
            call_arg_param_row,
            call_arg_param_row_tmp,
            call_arg_match_jump_a,
            call_arg_match_jump_b,
            call_param_match_jump_a,
            call_param_match_jump_b,
            call_generic_claim_count_out,
            call_generic_claim_scan_input,
            call_generic_claim_prefix,
            call_generic_claim_callee,
            call_generic_claim_slot,
            call_generic_claim_type,
            call_generic_claim_arg_row,
            call_generic_claim_order,
            call_generic_claim_order_tmp,
            call_generic_claim_radix_dispatch_args,
            call_generic_claim_radix_block_histogram,
            call_generic_claim_radix_block_bucket_prefix,
            call_generic_claim_radix_bucket_total,
            call_generic_claim_radix_bucket_base,
            call_const_claim_callee,
            call_const_claim_slot,
            call_const_claim_len,
            call_const_claim_order,
            call_const_claim_order_tmp,
            call_const_claim_radix_dispatch_args,
            call_const_claim_radix_block_histogram,
            call_const_claim_radix_block_bucket_prefix,
            call_const_claim_radix_bucket_total,
            call_const_claim_radix_bucket_base,
            call_required_generic_count_out,
            call_required_generic_scan_input,
            call_required_generic_prefix,
            call_required_generic_scan_local_prefix,
            call_required_generic_scan_block_sum,
            call_required_generic_scan_prefix_a,
            call_required_generic_scan_prefix_b,
            call_required_generic_dispatch_args,
            call_has_array_arg,
            call_array_return_arg_instance,
            call_arg_row_scan_local_prefix,
            call_arg_row_scan_block_sum,
            call_arg_row_scan_prefix_a,
            call_arg_row_scan_prefix_b,
            call_generic_claim_scan_local_prefix,
            call_generic_claim_scan_block_sum,
            call_generic_claim_scan_prefix_a,
            call_generic_claim_scan_prefix_b,
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
            struct_field_key_order,
            struct_field_key_order_tmp,
            struct_field_key_radix_dispatch_args,
            struct_field_key_radix_block_histogram,
            struct_field_key_radix_block_bucket_prefix,
            struct_field_key_radix_bucket_total,
            struct_field_key_radix_bucket_base,
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
            type_instance_arg_hash,
            type_instance_arg_row_start,
            type_instance_arg_row_count_out,
            type_instance_arg_row_ref_tag,
            type_instance_arg_row_ref_payload,
            type_instance_arg_row_scan_local_prefix,
            type_instance_arg_row_scan_block_sum,
            type_instance_arg_row_scan_prefix_a,
            type_instance_arg_row_scan_prefix_b,
            aggregate_compare_scan_input,
            aggregate_compare_prefix,
            aggregate_compare_count_out,
            aggregate_compare_expected_instance,
            aggregate_compare_actual_instance,
            aggregate_compare_error_token,
            aggregate_compare_error_detail,
            aggregate_compare_scan_local_prefix,
            aggregate_compare_scan_block_sum,
            aggregate_compare_scan_prefix_a,
            aggregate_compare_scan_prefix_b,
            aggregate_compare_dispatch_args,
            aggregate_compare_dispatch_params,
            type_instance_elem_ref_tag,
            type_instance_elem_ref_payload,
            type_instance_len_kind,
            type_instance_len_payload,
            type_instance_state,
            predicate_owner_node,
            predicate_subject_token,
            predicate_bound_token,
            predicate_bound_decl_id,
            predicate_bound_arg_count,
            predicate_bound_first_arg_token,
            predicate_bound_second_arg_token,
            predicate_status,
            predicate_syntax_token,
            predicate_method_contract_owner_node,
            predicate_method_contract_name_token,
            predicate_method_contract_name_id,
            predicate_method_contract_param_count,
            predicate_method_contract_first_param_node,
            predicate_method_contract_return_type_node,
            predicate_method_contract_visibility,
            predicate_method_contract_status,
            predicate_method_contract_param_next_node,
            predicate_method_contract_param_type_node,
            predicate_method_contract_key_order,
            predicate_method_contract_key_order_tmp,
            predicate_method_param_key_order,
            predicate_method_param_key_order_tmp,
            predicate_method_contract_owner_range_first,
            predicate_method_contract_owner_range_count,
            predicate_method_validation_owner_node,
            predicate_method_validation_peer_node,
            predicate_method_validation_status,
            predicate_method_validation_detail_token,
            predicate_method_validation_first_error_row,
            predicate_owner_key_order,
            predicate_owner_key_order_tmp,
            predicate_impl_key_order,
            predicate_impl_key_order_tmp,
            predicate_key_radix_block_histogram,
            predicate_key_radix_block_bucket_prefix,
            predicate_key_radix_bucket_total,
            predicate_key_radix_bucket_base,
            predicate_obligation_count_by_call,
            predicate_obligation_prefix_by_call,
            predicate_obligation_scan_local_prefix,
            predicate_obligation_scan_block_sum,
            predicate_obligation_scan_prefix_a,
            predicate_obligation_scan_prefix_b,
            predicate_obligation_pair_total,
            predicate_obligation_pair_dispatch_args,
            fn_return_ref_tag,
            fn_return_ref_payload,
            decl_type_ref_tag,
            decl_type_ref_payload,
            member_result_context_instance,
            member_result_ref_tag,
            member_result_ref_payload,
            member_result_field_ordinal,
            member_result_field_node,
            struct_init_field_expected_ref_tag,
            struct_init_field_expected_ref_payload,
            struct_init_field_context_instance,
            struct_init_field_ordinal,
            struct_init_field_ordinal_by_node,
            struct_init_field_decl_node_by_node,
            struct_lit_context_decl_token,
            struct_lit_context_instance,
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
            type_instances,
            returns_clear,
            returns_mark,
            returns_mark_if,
            returns_validate,
            conditions_hir,
            aggregate_compare_scan,
            aggregate_compare_scan_n_blocks,
            aggregate_compare_dispatch,
            conditions_aggregate_args,
            control,
            scope_hir,
        })
    }
}
