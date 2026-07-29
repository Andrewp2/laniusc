use super::*;

mod empty_hir_bindings;
mod module_path_resources;

use empty_hir_bindings::{
    EmptyHirBindings,
    register_empty_hir_resources,
    register_hir_item_resources,
};
use module_path_resources::register_module_path_resources;

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
        module_path_scratch: Option<GpuTypeCheckExternalScratchBuffers<'_>>,
        dependency_interfaces: Option<&GpuDependencyInterfaceState>,
    ) -> Result<ResidentTypeCheckState> {
        let allocation_timing =
            crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false);
        let allocation_start = std::time::Instant::now();
        let mut allocation_last = allocation_start;
        // The compiler currently routes its dead frontend workspace through
        // `module_path_scratch`, while standalone callers may provide the same
        // contract through `external_scratch`. The compiler also routes parser
        // scratch through `module_path_scratch`. Keep this contract deliberately
        // limited to the lookup rows: other fields in the larger scratch bundle
        // have overlapping durable lifetimes.
        // The compiler maps this field to dedicated expression-root scratch
        // whose parser lifetime has ended and which is not retained by module
        // path bind groups.
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
        if hir_node_capacity >= 0x0fff_ffff {
            anyhow::bail!(
                "compact HIR capacity {hir_node_capacity} exceeds scalar-type link encoding"
            );
        }
        let call_param_row_capacity = hir_items
            .map(|items| items.call_param_row_capacity)
            .unwrap_or(hir_node_capacity)
            .max(1);
        let call_arg_row_capacity = hir_items
            .map(|items| items.call_arg_row_capacity)
            .unwrap_or(hir_node_capacity)
            .max(1);
        let module_record_capacity = hir_items
            .map(|items| items.module_record_capacity)
            .unwrap_or(token_capacity)
            .max(1);
        let parser_feature_flags = hir_items
            .map(|items| items.parser_feature_flags)
            .unwrap_or(u32::MAX);
        let call_generic_claim_capacity =
            generic_claim_capacity_for_features(token_capacity, parser_feature_flags);
        let predicate_capacity =
            predicate_capacity_for_features(hir_node_capacity, parser_feature_flags);
        let typecheck_graph = compiler_graph::TypeCheckCompilerGraph::new(
            device,
            hir_node_capacity,
            token_capacity,
            source_file_capacity,
            module_record_capacity,
            call_param_row_capacity,
            call_arg_row_capacity,
            call_generic_claim_capacity,
            predicate_capacity,
            passes,
        )?;
        let call_graph = &typecheck_graph.calls;
        let hir_visible_decl_flag = typecheck_graph.u32_buffer("hir_visible_decl_flag")?;
        let hir_visible_decl_prefix = typecheck_graph.u32_buffer("hir_visible_decl_prefix")?;
        let hir_semantic_dispatch_args =
            typecheck_graph.u32_buffer("hir_semantic_dispatch_args")?;
        let hir_visible_decl_scan_local_prefix =
            typecheck_graph.u32_buffer("hir_visible_decl_scan_local_prefix")?;
        let hir_visible_decl_scan_block_sum =
            typecheck_graph.u32_buffer("hir_visible_decl_scan_block_sum")?;
        let hir_visible_decl_scan_prefix_a =
            typecheck_graph.u32_buffer("hir_visible_decl_scan_prefix_a")?;
        let hir_visible_decl_scan_prefix_b =
            typecheck_graph.u32_buffer("hir_visible_decl_scan_prefix_b")?;
        let hir_visible_decl_count_out =
            typecheck_graph.u32_buffer("hir_visible_decl_count_out")?;
        let hir_visible_decl_owner_fn = typecheck_graph.u32_buffer("hir_visible_decl_owner_fn")?;
        let hir_visible_decl_name_id = typecheck_graph.u32_buffer("hir_visible_decl_name_id")?;
        let hir_visible_decl_token = typecheck_graph.u32_buffer("hir_visible_decl_token")?;
        let hir_visible_decl_scope_end =
            typecheck_graph.u32_buffer("hir_visible_decl_scope_end")?;
        let hir_visible_decl_node = typecheck_graph.u32_buffer("hir_visible_decl_node")?;
        let hir_visible_decl_key_order =
            typecheck_graph.u32_buffer("hir_visible_decl_key_order")?;
        let hir_visible_decl_key_order_tmp =
            typecheck_graph.u32_buffer("hir_visible_decl_key_order_tmp")?;
        let hir_visible_decl_key_radix_dispatch_args =
            typecheck_graph.u32_buffer("hir_visible_decl_key_radix_dispatch_args")?;
        let hir_visible_decl_key_radix_block_histogram =
            typecheck_graph.u32_buffer("hir_visible_decl_key_radix_block_histogram")?;
        let hir_visible_decl_key_radix_block_bucket_prefix =
            typecheck_graph.u32_buffer("hir_visible_decl_key_radix_block_bucket_prefix")?;
        let hir_visible_decl_key_radix_bucket_total =
            typecheck_graph.u32_buffer("hir_visible_decl_key_radix_bucket_total")?;
        let hir_visible_decl_key_radix_bucket_base =
            typecheck_graph.u32_buffer("hir_visible_decl_key_radix_bucket_base")?;
        let hir_visible_decl_scope_tree =
            typecheck_graph.u32_buffer("hir_visible_decl_scope_tree")?;
        let predicate_method_contract_key_order =
            typecheck_graph.predicate_method_contract_key_order.clone();
        let predicate_method_contract_key_order_tmp = typecheck_graph
            .predicate_method_contract_key_order_tmp
            .clone();
        let predicate_method_param_key_order =
            typecheck_graph.predicate_method_param_key_order.clone();
        let predicate_method_param_key_order_tmp =
            typecheck_graph.predicate_method_param_key_order_tmp.clone();
        let predicate_owner_key_order = typecheck_graph.predicate_owner_key_order.clone();
        let predicate_owner_key_order_tmp = typecheck_graph.predicate_owner_key_order_tmp.clone();
        let predicate_impl_key_order = typecheck_graph.predicate_impl_key_order.clone();
        let predicate_impl_key_order_tmp = typecheck_graph.predicate_impl_key_order_tmp.clone();
        let predicate_key_radix_block_histogram =
            typecheck_graph.predicate_key_radix_block_histogram.clone();
        let predicate_key_radix_block_bucket_prefix = typecheck_graph
            .predicate_key_radix_block_bucket_prefix
            .clone();
        let predicate_key_radix_bucket_total =
            typecheck_graph.predicate_key_radix_bucket_total.clone();
        let predicate_key_radix_bucket_base =
            typecheck_graph.predicate_key_radix_bucket_base.clone();
        let predicate_obligation_count_by_call =
            typecheck_graph.predicate_obligation_count_by_call.clone();
        let predicate_obligation_prefix_by_call =
            typecheck_graph.predicate_obligation_prefix_by_call.clone();
        let predicate_obligation_scan_local_prefix = typecheck_graph
            .predicate_obligation_scan_local_prefix
            .clone();
        let predicate_obligation_scan_block_sum =
            typecheck_graph.predicate_obligation_scan_block_sum.clone();
        let predicate_obligation_scan_prefix_a =
            typecheck_graph.predicate_obligation_scan_prefix_a.clone();
        let predicate_obligation_scan_prefix_b =
            typecheck_graph.predicate_obligation_scan_prefix_b.clone();
        let predicate_obligation_pair_total =
            typecheck_graph.predicate_obligation_pair_total.clone();
        let predicate_obligation_pair_dispatch_args = typecheck_graph
            .predicate_obligation_pair_dispatch_args
            .clone();
        let compact_expr_scalar_type_a = typecheck_graph.scalar_a.clone();
        let compact_expr_scalar_type_b = typecheck_graph.scalar_b.clone();
        let call_generic_return_arg_node = typecheck_graph.call_generic_return_arg_node.clone();
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
        let name_n_blocks = name_capacity.div_ceil(256).max(1);
        let hir_value_decl_name_present = typed_storage_u32_rw(
            device,
            "type_check.resident.hir_value_decl_name_present",
            name_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_visible_decl_capacity = token_capacity.max(1);
        let hir_decl_record_n_blocks = hir_visible_decl_capacity.div_ceil(256).max(1);
        let hir_decl_tree_leaf_count = hir_visible_decl_capacity
            .div_ceil(HIR_VISIBLE_DECL_ROW_BLOCK_SIZE)
            .max(1);
        let hir_decl_tree_leaf_base = hir_decl_tree_leaf_count.next_power_of_two().max(1);
        let generic_param_count_out = typecheck_graph.generic_param_count_out.clone();
        let generic_param_owner_token = typecheck_graph.generic_param_owner_token.clone();
        let generic_param_name_id = typecheck_graph.generic_param_name_id.clone();
        let generic_param_token = typecheck_graph.generic_param_token.clone();
        let generic_param_node = typecheck_graph.generic_param_node.clone();
        let generic_param_kind = typecheck_graph.generic_param_kind.clone();
        let generic_param_key_order = typecheck_graph.generic_param_key_order.clone();
        let generic_param_key_order_tmp = typecheck_graph.generic_param_key_order_tmp.clone();
        let generic_param_slot_order = typecheck_graph.generic_param_slot_order.clone();
        let generic_param_slot_order_tmp = typecheck_graph.generic_param_slot_order_tmp.clone();
        let struct_field_key_order = typecheck_graph.struct_field_key_order.clone();
        let struct_field_key_order_tmp = typecheck_graph.struct_field_key_order_tmp.clone();
        let struct_field_key_radix_dispatch_args =
            typecheck_graph.struct_field_key_radix_dispatch_args.clone();
        let struct_field_key_radix_block_histogram = typecheck_graph
            .struct_field_key_radix_block_histogram
            .clone();
        let struct_field_key_radix_block_bucket_prefix = typecheck_graph
            .struct_field_key_radix_block_bucket_prefix
            .clone();
        let struct_field_key_radix_bucket_total =
            typecheck_graph.struct_field_key_radix_bucket_total.clone();
        let struct_field_key_radix_bucket_base =
            typecheck_graph.struct_field_key_radix_bucket_base.clone();
        let generic_decl_owner_by_node_a = typecheck_graph.generic_decl_owner_by_node_a.clone();
        let generic_decl_owner_by_node_b = typecheck_graph.generic_decl_owner_by_node_b.clone();
        let predicate_bound_list_by_node_a = typecheck_graph.predicate_bound_list_by_node_a.clone();
        let predicate_bound_list_by_node_b = typecheck_graph.predicate_bound_list_by_node_b.clone();
        let generic_decl_parent_jump_a = typecheck_graph.generic_decl_parent_jump_a.clone();
        let generic_decl_parent_jump_b = typecheck_graph.generic_decl_parent_jump_b.clone();
        let name_lexeme_flag = typecheck_graph.u32_buffer("name_lexeme_flag")?;
        let name_lexeme_kind = typecheck_graph.u32_buffer("name_lexeme_kind")?;
        let name_lexeme_prefix = typecheck_graph.u32_buffer("name_lexeme_prefix")?;
        let name_scan_local_prefix = typecheck_graph.u32_buffer("name_scan_local_prefix")?;
        let name_scan_block_sum = typecheck_graph.u32_buffer("name_scan_block_sum")?;
        let name_scan_prefix_a = typecheck_graph.u32_buffer("name_scan_prefix_a")?;
        let name_scan_prefix_b = typecheck_graph.u32_buffer("name_scan_prefix_b")?;
        let name_scan_total = typecheck_graph.u32_buffer("name_scan_total")?;
        let name_max_len = typecheck_graph.u32_buffer("name_max_len")?;
        let name_spans = typecheck_graph.u32_buffer("name_spans")?;
        let name_order_in = typecheck_graph.u32_buffer("name_hash_lo")?;
        let name_order_tmp = typecheck_graph.u32_buffer("name_hash_hi")?;
        let decl_name_token = typecheck_graph.u32_buffer("decl_name_token")?;
        let decl_id_by_name_token = typecheck_graph.u32_buffer("decl_id_by_name_token")?;
        let decl_kind = typecheck_graph.u32_buffer("decl_kind")?;
        let module_record_family_bits = typecheck_graph.u32_buffer("module_record_family_bits")?;
        let module_record_family_flag = typecheck_graph.u32_buffer("module_record_family_flag")?;
        let module_record_prefix = typecheck_graph.u32_buffer("module_record_prefix")?;
        let module_record_scan_workspace = typecheck_graph
            .prefix_scan_workspace(compiler_graph::MODULE_RECORD_SCAN_RESOURCES.workspace())?;
        let module_value_scan_workspace =
            typecheck_graph.prefix_scan_workspace(compiler_graph::MODULE_VALUE_SCAN_WORKSPACE)?;
        let decl_type_key_prefix = typecheck_graph.u32_buffer("decl_type_key_prefix")?;
        let decl_value_key_prefix = typecheck_graph.u32_buffer("decl_value_key_prefix")?;
        let decl_type_key_count_out = typecheck_graph.u32_buffer("decl_type_key_count_out")?;
        let decl_value_key_count_out = typecheck_graph.u32_buffer("decl_value_key_count_out")?;
        let decl_status = typecheck_graph.u32_buffer("decl_status")?;
        let import_visible_type_count = typecheck_graph.u32_buffer("import_visible_type_count")?;
        let import_visible_value_count =
            typecheck_graph.u32_buffer("import_visible_value_count")?;
        let import_visible_type_prefix =
            typecheck_graph.u32_buffer("import_visible_type_prefix")?;
        let import_visible_value_prefix =
            typecheck_graph.u32_buffer("import_visible_value_prefix")?;
        let import_visible_type_count_out =
            typecheck_graph.u32_buffer("import_visible_type_count_out")?;
        let import_visible_value_count_out =
            typecheck_graph.u32_buffer("import_visible_value_count_out")?;
        let module_path_key_radix_block_histogram =
            typecheck_graph.u32_buffer("module_path_key_radix_block_histogram")?;
        let module_path_key_radix_block_bucket_prefix =
            typecheck_graph.u32_buffer("module_path_key_radix_block_bucket_prefix")?;
        let module_path_key_radix_bucket_total =
            typecheck_graph.u32_buffer("module_path_key_radix_bucket_total")?;
        let module_path_key_radix_bucket_base =
            typecheck_graph.u32_buffer("module_path_key_radix_bucket_base")?;
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
        let radix_block_histogram = typecheck_graph.u32_buffer("name_hash_table_a")?;
        let radix_block_bucket_prefix = typecheck_graph.u32_buffer("name_hash_table_b")?;
        let sorted_name_id = typecheck_graph.u32_buffer("sorted_name_id")?;
        let name_id_by_input = typecheck_graph.u32_buffer("name_id_by_input")?;
        let unique_name_count = typecheck_graph.u32_buffer("unique_name_count")?;
        let if_depth_n_blocks = token_capacity.div_ceil(256).max(1);
        let fn_n_blocks = token_capacity.div_ceil(256).max(1);
        let if_depth_params_value = IfDepthParams {
            n_tokens: token_capacity,
            n_hir_nodes: hir_node_capacity,
            n_blocks: if_depth_n_blocks,
            scan_step: 0,
        };
        let fn_params_value = FnContextParams {
            n_tokens: token_capacity,
            n_hir_nodes: hir_node_capacity,
            n_blocks: fn_n_blocks,
            scan_step: 0,
        };
        let if_depth_params = uniform_from_val(
            device,
            "type_check.resident.if_depth.params",
            &if_depth_params_value,
        );
        let fn_params = uniform_from_val(
            device,
            "type_check.resident.fn_context.params",
            &fn_params_value,
        );
        let if_delta = typecheck_graph.if_delta.clone();
        let if_depth_inblock = typecheck_graph.if_depth_inblock.clone();
        let if_block_sum = typecheck_graph.if_block_sum.clone();
        let if_prefix_a = typecheck_graph.if_prefix_a.clone();
        let if_prefix_b = typecheck_graph.if_prefix_b.clone();
        let if_block_prefix = typecheck_graph.if_block_prefix.clone();
        let if_depth = typecheck_graph.if_depth.clone();
        let enclosing_fn = typecheck_graph.enclosing_fn.clone();
        let enclosing_fn_end = typecheck_graph.enclosing_fn_end.clone();
        let fn_event_value = typecheck_graph.fn_event_value.clone();
        let fn_event_end = typecheck_graph.fn_event_end.clone();
        let fn_event_index = typecheck_graph.fn_event_index.clone();
        let fn_event_inblock = typecheck_graph.fn_event_inblock.clone();
        let fn_block_sum = typecheck_graph.fn_block_sum.clone();
        let fn_prefix_a = typecheck_graph.fn_prefix_a.clone();
        let fn_prefix_b = typecheck_graph.fn_prefix_b.clone();
        let fn_block_prefix = typecheck_graph.fn_block_prefix.clone();
        let call_fn_index = typecheck_graph.call_fn_index.clone();
        let fn_start_token_by_decl_token = call_graph.fn_start_token_by_decl_token.clone();
        let backend_call_fn_index = call_graph.backend_call_fn_index.clone();
        let call_dependency_decl = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_dependency_decl",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_intrinsic_tag = call_graph.call_intrinsic_tag.clone();
        let fn_entrypoint_tag = typecheck_graph.fn_entrypoint_tag.clone();
        let call_return_type = typecheck_graph.call_return_type.clone();
        let call_return_type_token = typecheck_graph.call_return_type_token.clone();
        let return_fn_flags = typecheck_graph.return_fn_flags.clone();
        let return_block_flags = typecheck_graph.return_block_flags.clone();
        let call_param_count = call_graph.call_param_count.clone();
        let call_param_type = call_graph.call_param_type.clone();
        let call_param_ref_tag = call_graph.call_param_ref_tag.clone();
        let call_param_ref_payload = call_graph.call_param_ref_payload.clone();
        let call_generic_slot_type = call_graph.call_generic_slot_type.clone();
        let call_generic_slot_ordinal = call_graph.call_generic_slot_ordinal.clone();
        let call_const_slot_len = call_graph.call_const_slot_len.clone();
        let call_param_row_count_out = call_graph.call_param_row_count_out.clone();
        let call_param_row_flag = call_graph.call_param_row_flag.clone();
        let call_param_row_node_type = call_graph.call_param_row_node_type.clone();
        let call_param_row_node_ref_tag = call_graph.call_param_row_node_ref_tag.clone();
        let call_param_row_node_ref_payload = call_graph.call_param_row_node_ref_payload.clone();
        let call_param_row_node = call_graph.call_param_row_node.clone();
        let call_param_row_fn_token = call_graph.call_param_row_fn_token.clone();
        let call_param_row_ordinal = call_graph.call_param_row_ordinal.clone();
        let call_param_row_type = call_graph.call_param_row_type.clone();
        let call_param_row_ref_tag = call_graph.call_param_row_ref_tag.clone();
        let call_param_row_ref_payload = call_graph.call_param_row_ref_payload.clone();
        let call_param_row_start = call_graph.call_param_row_start.clone();
        let call_param_row_count = call_graph.call_param_row_count.clone();
        let call_param_row_scan_local_prefix =
            typecheck_graph.call_param_row_scan_local_prefix.clone();
        let call_param_row_scan_block_sum = typecheck_graph.call_param_row_scan_block_sum.clone();
        let call_param_row_scan_prefix_a = typecheck_graph.call_param_row_scan_prefix_a.clone();
        let call_param_row_scan_prefix_b = typecheck_graph.call_param_row_scan_prefix_b.clone();
        let call_arg_record = call_graph.call_arg_record.clone();
        let call_arg_row_count_out = typecheck_graph.call_arg_row_count_out.clone();
        let call_arg_row_scan_input = typecheck_graph.call_arg_row_scan_input.clone();
        let call_arg_row_prefix = typecheck_graph.call_arg_row_prefix.clone();
        let call_arg_row_scan_local_prefix = typecheck_graph.call_arg_row_scan_local_prefix.clone();
        let call_arg_row_node = call_graph.call_arg_row_node.clone();
        let call_arg_row_call_node = call_graph.call_arg_row_call_node.clone();
        let call_arg_row_ordinal = call_graph.call_arg_row_ordinal.clone();
        let call_arg_row_start = call_graph.call_arg_row_start.clone();
        let call_arg_row_count = call_graph.call_arg_row_count.clone();
        let call_arg_param_row = typecheck_graph.call_arg_param_row.clone();
        let call_generic_claim_count_out =
            Box::new(typecheck_graph.generic_claim_count_out.clone());
        let call_generic_claim_scan_input =
            Box::new(typecheck_graph.generic_claim_scan_input.clone());
        let call_generic_claim_prefix = Box::new(typecheck_graph.generic_claim_prefix.clone());
        let call_generic_claim_callee = Box::new(typecheck_graph.generic_claim_callee.clone());
        let call_generic_claim_slot = Box::new(typecheck_graph.generic_claim_slot.clone());
        let call_generic_claim_type = Box::new(typecheck_graph.generic_claim_type.clone());
        let call_generic_claim_ref_tag = Box::new(typecheck_graph.generic_claim_ref_tag.clone());
        let call_generic_claim_ref_payload =
            Box::new(typecheck_graph.generic_claim_ref_payload.clone());
        let call_generic_claim_arg_row = Box::new(typecheck_graph.generic_claim_arg_row.clone());
        let call_generic_claim_order = Box::new(typecheck_graph.generic_claim_order.clone());
        let call_generic_claim_order_tmp =
            Box::new(typecheck_graph.generic_claim_order_tmp.clone());
        let call_generic_claim_radix_dispatch_args =
            typecheck_graph.generic_claim_radix_dispatch_args.clone();
        let call_generic_claim_radix_block_histogram =
            typecheck_graph.generic_claim_radix_block_histogram.clone();
        let call_generic_claim_radix_block_bucket_prefix = typecheck_graph
            .generic_claim_radix_block_bucket_prefix
            .clone();
        let call_generic_claim_radix_bucket_total =
            typecheck_graph.generic_claim_radix_bucket_total.clone();
        let call_generic_claim_radix_bucket_base =
            typecheck_graph.generic_claim_radix_bucket_base.clone();
        let call_const_claim_callee = typecheck_graph.const_claim_callee.clone();
        let call_const_claim_slot = typecheck_graph.const_claim_slot.clone();
        let call_const_claim_len = typecheck_graph.const_claim_len.clone();
        let call_const_claim_order = typecheck_graph.const_claim_order.clone();
        let call_const_claim_order_tmp = typecheck_graph.const_claim_order_tmp.clone();
        let call_const_claim_radix_dispatch_args =
            typecheck_graph.const_claim_radix_dispatch_args.clone();
        let call_const_claim_radix_block_histogram =
            typecheck_graph.const_claim_radix_block_histogram.clone();
        let call_const_claim_radix_block_bucket_prefix = typecheck_graph
            .const_claim_radix_block_bucket_prefix
            .clone();
        let call_const_claim_radix_bucket_total =
            typecheck_graph.const_claim_radix_bucket_total.clone();
        let call_const_claim_radix_bucket_base =
            typecheck_graph.const_claim_radix_bucket_base.clone();
        let call_required_generic_count_out = typecheck_graph.required_generic_count_out.clone();
        let call_required_generic_scan_input = typecheck_graph.required_generic_scan_input.clone();
        let call_required_generic_prefix = typecheck_graph.required_generic_prefix.clone();
        let call_required_generic_scan_local_prefix =
            typecheck_graph.required_generic_scan_local_prefix.clone();
        let call_required_generic_scan_block_sum =
            typecheck_graph.required_generic_scan_block_sum.clone();
        let call_required_generic_scan_prefix_a =
            typecheck_graph.required_generic_scan_prefix_a.clone();
        let call_required_generic_scan_prefix_b =
            typecheck_graph.required_generic_scan_prefix_b.clone();
        let call_required_generic_dispatch_args =
            typecheck_graph.required_generic_dispatch_args.clone();
        let call_has_array_arg = typecheck_graph.call_has_array_arg.clone();
        let call_result_instance = typecheck_graph.call_result_instance.clone();
        let call_arg_row_scan_block_sum = typecheck_graph.call_arg_row_scan_block_sum.clone();
        let call_arg_row_scan_prefix_a = typecheck_graph.call_arg_row_scan_prefix_a.clone();
        let call_arg_row_scan_prefix_b = typecheck_graph.call_arg_row_scan_prefix_b.clone();
        let call_generic_claim_scan_local_prefix =
            typecheck_graph.generic_claim_scan_local_prefix.clone();
        let call_generic_claim_scan_block_sum =
            typecheck_graph.generic_claim_scan_block_sum.clone();
        let call_generic_claim_scan_prefix_a = typecheck_graph.generic_claim_scan_prefix_a.clone();
        let call_generic_claim_scan_prefix_b = typecheck_graph.generic_claim_scan_prefix_b.clone();
        let function_lookup_key = call_graph.function_lookup_key.clone();
        let function_lookup_fn = call_graph.function_lookup_fn.clone();
        let method_decl_receiver_ref_tag = typecheck_graph.method_decl_receiver_ref_tag.clone();
        let method_decl_receiver_ref_payload =
            typecheck_graph.method_decl_receiver_ref_payload.clone();
        let method_decl_module_id = typecheck_graph.method_decl_module_id.clone();
        let method_decl_method_row = typecheck_graph.method_decl_method_row.clone();
        let method_decl_name_token = typecheck_graph.method_decl_name_token.clone();
        let method_decl_name_id = typecheck_graph.method_decl_name_id.clone();
        let method_decl_param_offset = typecheck_graph.method_decl_param_offset.clone();
        let method_decl_receiver_mode = typecheck_graph.method_decl_receiver_mode.clone();
        let method_decl_visibility = typecheck_graph.method_decl_visibility.clone();
        let method_decl_signature_flags = typecheck_graph.method_decl_signature_flags.clone();
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
        let method_key_to_fn_token = typecheck_graph.method_key_to_fn_token.clone();
        let method_key_order_tmp = typecheck_graph.method_key_order_tmp.clone();
        let method_key_status = typecheck_graph.method_key_status.clone();
        let method_key_duplicate_of = typecheck_graph.method_key_duplicate_of.clone();
        let method_key_radix_block_histogram =
            typecheck_graph.method_key_radix_block_histogram.clone();
        let method_key_radix_block_bucket_prefix =
            typecheck_graph.method_key_radix_block_bucket_prefix.clone();
        let method_key_radix_bucket_total = typecheck_graph.method_key_radix_bucket_total.clone();
        let method_key_radix_bucket_base = typecheck_graph.method_key_radix_bucket_base.clone();
        let method_call_receiver_ref_tag = typecheck_graph.method_call_receiver_ref_tag.clone();
        let method_call_receiver_ref_payload =
            typecheck_graph.method_call_receiver_ref_payload.clone();
        let method_call_name_id = typecheck_graph.method_call_name_id.clone();
        let method_call_site_module_id = typecheck_graph.method_call_site_module_id.clone();
        let type_expr_ref_tag = typecheck_graph.type_expr_ref_tag.clone();
        let type_expr_ref_payload = typecheck_graph.type_expr_ref_payload.clone();
        let type_instance_kind = typecheck_graph.type_instance_kind.clone();
        let type_instance_head_token = typecheck_graph.type_instance_head_token.clone();
        let type_decl_generic_param_count = typecheck_graph.type_decl_generic_param_count.clone();
        let type_decl_generic_param_count_by_owner_token = typecheck_graph
            .type_decl_generic_param_count_by_owner_token
            .clone();
        let type_decl_const_param_count_by_owner_token = typecheck_graph
            .type_decl_const_param_count_by_owner_token
            .clone();
        let type_decl_hir_node_by_token = typecheck_graph.type_decl_hir_node_by_token.clone();
        let type_generic_param_slot_by_token =
            typecheck_graph.type_generic_param_slot_by_token.clone();
        let type_const_param_slot_by_token = typecheck_graph.type_const_param_slot_by_token.clone();
        // Local and imported named instances share this identity discriminator.
        // It must survive name-radix scratch reuse and be reset independently:
        // an imported canonical id and a stale local declaration token are
        // mutually exclusive representations of the same instance.
        let type_instance_decl_token = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.type_instance_decl_token",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_external_canonical = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.type_instance_external_canonical",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_start = typecheck_graph.type_instance_arg_start.clone();
        let type_instance_arg_count = typecheck_graph.type_instance_arg_count.clone();
        let type_instance_arg_ref_tag = typecheck_graph.type_instance_arg_ref_tag.clone();
        let type_instance_arg_ref_payload = typecheck_graph.type_instance_arg_ref_payload.clone();
        let type_instance_arg_hash = typecheck_graph.type_instance_arg_hash.clone();
        let type_instance_arg_row_start = typecheck_graph.type_instance_arg_row_start.clone();
        let type_instance_arg_row_count_out =
            typecheck_graph.type_instance_arg_row_count_out.clone();
        let type_instance_arg_row_ref_tag = typecheck_graph.type_instance_arg_row_ref_tag.clone();
        let type_instance_arg_row_ref_payload =
            typecheck_graph.type_instance_arg_row_ref_payload.clone();
        let type_instance_arg_row_scan_local_prefix = typecheck_graph
            .type_instance_arg_row_scan_local_prefix
            .clone();
        let type_instance_arg_row_scan_block_sum =
            typecheck_graph.type_instance_arg_row_scan_block_sum.clone();
        let type_instance_arg_row_scan_prefix_a =
            typecheck_graph.type_instance_arg_row_scan_prefix_a.clone();
        let type_instance_arg_row_scan_prefix_b =
            typecheck_graph.type_instance_arg_row_scan_prefix_b.clone();
        let type_semantic_buffers = Box::new(TypeSemanticBuffers {
            row_by_token: typecheck_graph.type_semantic_row_by_token.clone(),
            scan_input: typecheck_graph.type_semantic_scan_input.clone(),
            prefix: typecheck_graph.type_semantic_prefix.clone(),
            count_out: typecheck_graph.type_semantic_count_out.clone(),
            row_by_ordinal: typecheck_graph.type_semantic_row_by_ordinal.clone(),
        });
        let aggregate_compare_scan_input = typecheck_graph.aggregate_compare_scan_input.clone();
        let aggregate_compare_prefix = typecheck_graph.aggregate_compare_prefix.clone();
        let aggregate_compare_count_out = typecheck_graph.aggregate_compare_count_out.clone();
        let aggregate_compare_expected_instance =
            typecheck_graph.aggregate_compare_expected_instance.clone();
        let aggregate_compare_actual_instance =
            typecheck_graph.aggregate_compare_actual_instance.clone();
        let aggregate_compare_error_token = typecheck_graph.aggregate_compare_error_token.clone();
        let aggregate_compare_error_detail = typecheck_graph.aggregate_compare_error_detail.clone();
        let aggregate_compare_scan_local_prefix =
            typecheck_graph.aggregate_compare_scan_local_prefix.clone();
        let aggregate_compare_scan_block_sum =
            typecheck_graph.aggregate_compare_scan_block_sum.clone();
        let aggregate_compare_scan_prefix_a =
            typecheck_graph.aggregate_compare_scan_prefix_a.clone();
        let aggregate_compare_scan_prefix_b =
            typecheck_graph.aggregate_compare_scan_prefix_b.clone();
        let aggregate_compare_dispatch_args =
            typecheck_graph.aggregate_compare_dispatch_args.clone();
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
        let type_subtree_compare_buffers = Box::new(TypeSubtreeCompareBuffers {
            scan_input: typecheck_graph.type_subtree_compare_scan_input.clone(),
            prefix: typecheck_graph.type_subtree_compare_prefix.clone(),
            count_out: typecheck_graph.type_subtree_compare_count_out.clone(),
            left_root: typecheck_graph.type_subtree_compare_left_root.clone(),
            right_root: typecheck_graph.type_subtree_compare_right_root.clone(),
            error_token: typecheck_graph.type_subtree_compare_error_token.clone(),
            error_detail: typecheck_graph.type_subtree_compare_error_detail.clone(),
            dispatch_args: typecheck_graph.type_subtree_compare_dispatch_args.clone(),
            dispatch_params: uniform_from_val(
                device,
                "type_check.resident.type_subtree_compare_dispatch.params",
                &CountDispatchParams {
                    capacity: hir_node_capacity.max(1),
                    multiplier: 1,
                    reserved0: 0,
                    reserved1: 0,
                },
            ),
        });
        let type_instance_elem_ref_tag = typecheck_graph.type_instance_elem_ref_tag.clone();
        let type_instance_elem_ref_payload = typecheck_graph.type_instance_elem_ref_payload.clone();
        let type_instance_len_kind = typecheck_graph.type_instance_len_kind.clone();
        let type_instance_len_payload = typecheck_graph.type_instance_len_payload.clone();
        let type_instance_state = typecheck_graph.type_instance_state.clone();
        let predicate_capacity_u32 = predicate_capacity;
        let predicate_key_radix_n_blocks = predicate_capacity_u32.div_ceil(256).max(1);
        let predicate_owner_node = typecheck_graph.predicate_owner_node.clone();
        let predicate_subject_token = typecheck_graph.predicate_subject_token.clone();
        let predicate_bound_token = typecheck_graph.predicate_bound_token.clone();
        let predicate_bound_decl_id = typecheck_graph.predicate_bound_decl_id.clone();
        let predicate_bound_arg_count = typecheck_graph.predicate_bound_arg_count.clone();
        let predicate_bound_first_arg_token =
            typecheck_graph.predicate_bound_first_arg_token.clone();
        let predicate_bound_second_arg_token =
            typecheck_graph.predicate_bound_second_arg_token.clone();
        let predicate_status = typecheck_graph.predicate_status.clone();
        let predicate_syntax_token = typecheck_graph.predicate_syntax_token.clone();
        let predicate_method_contract_owner_hir =
            typecheck_graph.predicate_method_contract_owner_hir.clone();
        let predicate_method_contract_name_token =
            typecheck_graph.predicate_method_contract_name_token.clone();
        let predicate_method_contract_name_id =
            typecheck_graph.predicate_method_contract_name_id.clone();
        let predicate_method_contract_param_count = typecheck_graph
            .predicate_method_contract_param_count
            .clone();
        let predicate_method_contract_return_type_node = typecheck_graph
            .predicate_method_contract_return_type_node
            .clone();
        let predicate_method_contract_visibility =
            typecheck_graph.predicate_method_contract_visibility.clone();
        let predicate_method_contract_status =
            typecheck_graph.predicate_method_contract_status.clone();
        let predicate_method_contract_param_type_node = typecheck_graph
            .predicate_method_contract_param_type_node
            .clone();
        let predicate_method_contract_owner_range_first = typecheck_graph
            .predicate_method_contract_owner_range_first
            .clone();
        let predicate_method_contract_owner_range_count = typecheck_graph
            .predicate_method_contract_owner_range_count
            .clone();
        let predicate_method_validation_owner_node = typecheck_graph
            .predicate_method_validation_owner_node
            .clone();
        let predicate_method_validation_peer_node = typecheck_graph
            .predicate_method_validation_peer_node
            .clone();
        let predicate_method_validation_status =
            typecheck_graph.predicate_method_validation_status.clone();
        let predicate_method_validation_detail_token = typecheck_graph
            .predicate_method_validation_detail_token
            .clone();
        let predicate_method_validation_first_error_row = typecheck_graph
            .predicate_method_validation_first_error_row
            .clone();
        let fn_return_ref_tag = call_graph.fn_return_ref_tag.clone();
        let fn_return_ref_payload = call_graph.fn_return_ref_payload.clone();
        // Declaration refs survive name/type-instance construction and feed
        // late semantic projection. They cannot alias radix rows that later
        // type-family sorts overwrite; the compiler graph may recolor them
        // only after that complete producer/consumer interval is registered.
        let decl_type_ref_tag = typed_storage_u32_rw(
            device,
            "type_check.resident.decl_type_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let decl_type_ref_payload = typed_storage_u32_rw(
            device,
            "type_check.resident.decl_type_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let member_capacity = member_capacity_for_features(
            token_capacity,
            hir_items
                .map(|items| items.parser_feature_flags)
                .unwrap_or(u32::MAX),
        ) as usize;
        let member_result_context_instance = typecheck_graph
            .member_result_context_instance
            .alias::<u32>(member_capacity);
        let member_result_ref_tag = typecheck_graph
            .member_result_ref_tag
            .alias::<u32>(member_capacity);
        let member_result_ref_payload = typecheck_graph
            .member_result_ref_payload
            .alias::<u32>(member_capacity);
        let member_result_field_ordinal = typecheck_graph
            .member_result_field_ordinal
            .alias::<u32>(member_capacity);
        let member_result_field_node = typecheck_graph
            .member_result_field_node
            .alias::<u32>(member_capacity);
        let member_next_node = typecheck_graph.member_next_node.clone();
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
        let struct_init_field_expected_ref_tag = typecheck_graph
            .struct_init_field_expected_ref_tag
            .alias::<u32>(struct_token_capacity);
        let struct_init_field_expected_ref_payload = typecheck_graph
            .struct_init_field_expected_ref_payload
            .alias::<u32>(struct_token_capacity);
        let struct_init_field_context_instance = typecheck_graph
            .struct_init_field_context_instance
            .alias::<u32>(struct_token_capacity);
        let struct_init_field_ordinal = typecheck_graph
            .struct_init_field_ordinal
            .alias::<u32>(struct_token_capacity);
        let struct_init_field_ordinal_by_node = typecheck_graph
            .struct_init_field_ordinal_by_node
            .alias::<u32>(hir_node_capacity.max(1) as usize);
        let struct_init_field_decl_node_by_node = typecheck_graph
            .struct_init_field_decl_node_by_node
            .alias::<u32>(struct_hir_capacity);
        let struct_init_field_ordinal_by_row = typecheck_graph
            .struct_init_field_ordinal_by_row
            .alias::<u32>(struct_hir_capacity);
        let struct_init_field_decl_token_by_row = typecheck_graph
            .struct_init_field_decl_token_by_row
            .alias::<u32>(struct_hir_capacity);
        let struct_lit_context_decl_token = typecheck_graph
            .struct_lit_context_decl_token
            .alias::<u32>(struct_hir_capacity);
        let struct_lit_context_instance = typecheck_graph
            .struct_lit_context_instance
            .alias::<u32>(struct_hir_capacity);
        let array_element_struct_literal_node = typecheck_graph
            .array_element_struct_literal_node
            .alias::<u32>(struct_hir_capacity);
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
        let semantic_feature_flags = typecheck_graph.u32_buffer("semantic_feature_flags")?;
        let method_token_dispatch_args =
            typecheck_graph.u32_buffer("method_token_dispatch_args")?;
        let method_hir_dispatch_args = typecheck_graph.u32_buffer("method_hir_dispatch_args")?;
        let method_compact_dispatch_args =
            typecheck_graph.u32_buffer("method_compact_dispatch_args")?;
        let method_token_hir_dispatch_args =
            typecheck_graph.u32_buffer("method_token_hir_dispatch_args")?;
        let method_radix_prefix_dispatch_args =
            typecheck_graph.u32_buffer("method_radix_prefix_dispatch_args")?;
        let method_radix_bases_dispatch_args =
            typecheck_graph.u32_buffer("method_radix_bases_dispatch_args")?;
        let predicate_token_dispatch_args =
            typecheck_graph.u32_buffer("predicate_token_dispatch_args")?;
        let predicate_hir_dispatch_args =
            typecheck_graph.u32_buffer("predicate_hir_dispatch_args")?;
        let predicate_radix_prefix_dispatch_args =
            typecheck_graph.u32_buffer("predicate_radix_prefix_dispatch_args")?;
        let predicate_radix_bases_dispatch_args =
            typecheck_graph.u32_buffer("predicate_radix_bases_dispatch_args")?;
        let predicate_single_dispatch_args =
            typecheck_graph.u32_buffer("predicate_single_dispatch_args")?;
        let match_hir_dispatch_args = typecheck_graph.u32_buffer("match_hir_dispatch_args")?;
        let semantic_value_decl_by_hir = typecheck_graph.semantic_value_decl_by_hir.clone();
        let semantic_value_type_by_hir = typecheck_graph.semantic_value_type_by_hir.clone();
        let semantic_param_type_by_row = typecheck_graph.semantic_param_type_by_row.clone();
        let semantic_enclosing_fn_by_hir = typecheck_graph.semantic_enclosing_fn_by_hir.clone();
        let semantic_function_return_type_by_hir =
            typecheck_graph.semantic_function_return_type_by_hir.clone();
        let semantic_function_entrypoint_by_hir =
            typecheck_graph.semantic_function_entrypoint_by_hir.clone();
        let semantic_function_host_service_by_hir = typecheck_graph
            .semantic_function_host_service_by_hir
            .clone();
        let semantic_control_depth_by_hir = typecheck_graph.semantic_control_depth_by_hir.clone();
        let semantic_calls_by_hir = typecheck_graph.semantic_calls_by_hir.clone();
        let semantic_expr_ref_tag_by_hir = typecheck_graph.semantic_expr_ref_tag_by_hir.clone();
        let semantic_expr_ref_payload_by_hir =
            typecheck_graph.semantic_expr_ref_payload_by_hir.clone();
        let semantic_array_length_by_hir = typecheck_graph.semantic_array_length_by_hir.clone();
        let semantic_member_field_ordinal_by_hir =
            typecheck_graph.semantic_member_field_ordinal_by_hir.clone();
        let compact_predicate_diagnostic_facts =
            typecheck_graph.compact_predicate_diagnostic_facts.clone();
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
        resources.buffer(
            "compact_predicate_diagnostic_facts",
            &compact_predicate_diagnostic_facts,
        );
        resources.buffer("method_token_dispatch_args", &method_token_dispatch_args);
        resources.buffer("method_hir_dispatch_args", &method_hir_dispatch_args);
        resources.buffer(
            "method_compact_dispatch_args",
            &method_compact_dispatch_args,
        );
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
        resources.buffer("semantic_value_decl_by_hir", &semantic_value_decl_by_hir);
        resources.buffer("semantic_value_type_by_hir", &semantic_value_type_by_hir);
        resources.buffer("semantic_param_type_by_row", &semantic_param_type_by_row);
        resources.buffer(
            "semantic_enclosing_fn_by_hir",
            &semantic_enclosing_fn_by_hir,
        );
        resources.buffer(
            "semantic_function_return_type_by_hir",
            &semantic_function_return_type_by_hir,
        );
        resources.buffer(
            "semantic_function_entrypoint_by_hir",
            &semantic_function_entrypoint_by_hir,
        );
        resources.buffer(
            "semantic_function_host_service_by_hir",
            &semantic_function_host_service_by_hir,
        );
        resources.buffer(
            "semantic_control_depth_by_hir",
            &semantic_control_depth_by_hir,
        );
        resources.buffer("semantic_calls_by_hir", &semantic_calls_by_hir);
        resources.buffer(
            "semantic_expr_ref_tag_by_hir",
            &semantic_expr_ref_tag_by_hir,
        );
        resources.buffer(
            "semantic_expr_ref_payload_by_hir",
            &semantic_expr_ref_payload_by_hir,
        );
        resources.buffer(
            "semantic_array_length_by_hir",
            &semantic_array_length_by_hir,
        );
        resources.buffer(
            "semantic_member_field_ordinal_by_hir",
            &semantic_member_field_ordinal_by_hir,
        );
        resources.buffer("hir_value_decl_name_present", &hir_value_decl_name_present);
        resources.buffer("hir_visible_decl_count_out", &hir_visible_decl_count_out);
        resources.buffer("hir_visible_decl_owner_fn", &hir_visible_decl_owner_fn);
        resources.buffer("hir_visible_decl_name_id", &hir_visible_decl_name_id);
        resources.buffer("hir_visible_decl_token", &hir_visible_decl_token);
        resources.buffer("hir_visible_decl_scope_end", &hir_visible_decl_scope_end);
        resources.buffer("hir_visible_decl_node", &hir_visible_decl_node);
        resources.buffer("hir_visible_decl_key_order", &hir_visible_decl_key_order);
        resources.buffer(
            "hir_visible_decl_key_order_tmp",
            &hir_visible_decl_key_order_tmp,
        );
        resources.buffer(
            "hir_visible_decl_key_radix_dispatch_args",
            &hir_visible_decl_key_radix_dispatch_args,
        );
        resources.buffer(
            "hir_visible_decl_key_radix_block_histogram",
            &hir_visible_decl_key_radix_block_histogram,
        );
        resources.buffer(
            "hir_visible_decl_key_radix_block_bucket_prefix",
            &hir_visible_decl_key_radix_block_bucket_prefix,
        );
        resources.buffer(
            "hir_visible_decl_key_radix_bucket_total",
            &hir_visible_decl_key_radix_bucket_total,
        );
        resources.buffer(
            "hir_visible_decl_key_radix_bucket_base",
            &hir_visible_decl_key_radix_bucket_base,
        );
        resources.buffer("hir_visible_decl_scope_tree", &hir_visible_decl_scope_tree);
        resources.buffer("module_type_path_type", &module_type_path_type);
        resources.buffer("module_type_path_status", &module_type_path_status);
        resources.buffer("module_value_path_status", &module_value_path_status);
        resources.buffer("if_delta", &if_delta);
        resources.buffer("if_depth_inblock", &if_depth_inblock);
        resources.buffer("if_block_sum", &if_block_sum);
        resources.buffer("if_prefix_a", &if_prefix_a);
        resources.buffer("if_prefix_b", &if_prefix_b);
        resources.buffer("if_block_prefix", &if_block_prefix);
        resources.buffer("if_depth", &if_depth);
        resources.buffer("enclosing_fn", &enclosing_fn);
        resources.buffer("enclosing_fn_end", &enclosing_fn_end);
        resources.buffer("fn_event_value", &fn_event_value);
        resources.buffer("fn_event_end", &fn_event_end);
        resources.buffer("fn_event_index", &fn_event_index);
        resources.buffer("fn_event_inblock", &fn_event_inblock);
        resources.buffer("fn_block_sum", &fn_block_sum);
        resources.buffer("fn_prefix_a", &fn_prefix_a);
        resources.buffer("fn_prefix_b", &fn_prefix_b);
        resources.buffer("fn_block_prefix", &fn_block_prefix);
        resources.buffer("block_sum", &fn_block_sum);
        resources.buffer("block_prefix", &fn_block_prefix);
        resources.buffer("call_fn_index", &call_fn_index);
        resources.buffer(
            "fn_start_token_by_decl_token",
            &fn_start_token_by_decl_token,
        );
        resources.buffer("backend_call_fn_index", &backend_call_fn_index);
        resources.buffer("call_dependency_decl", &call_dependency_decl);
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
        resources.buffer(
            "call_generic_return_arg_node",
            &call_generic_return_arg_node,
        );
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
        resources.buffer(
            "call_generic_claim_count_out",
            &*call_generic_claim_count_out,
        );
        resources.buffer(
            "call_generic_claim_scan_input",
            &*call_generic_claim_scan_input,
        );
        resources.buffer("call_generic_claim_prefix", &*call_generic_claim_prefix);
        resources.buffer("call_generic_claim_callee", &*call_generic_claim_callee);
        resources.buffer("call_generic_claim_slot", &*call_generic_claim_slot);
        resources.buffer("call_generic_claim_type", &*call_generic_claim_type);
        resources.buffer("call_generic_claim_ref_tag", &*call_generic_claim_ref_tag);
        resources.buffer(
            "call_generic_claim_ref_payload",
            &*call_generic_claim_ref_payload,
        );
        resources.buffer("call_generic_claim_arg_row", &*call_generic_claim_arg_row);
        resources.buffer("call_generic_claim_order", &*call_generic_claim_order);
        resources.buffer(
            "call_generic_claim_order_tmp",
            &*call_generic_claim_order_tmp,
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
        resources.buffer("call_result_instance", &call_result_instance);
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
        resources.buffer("method_decl_method_row", &method_decl_method_row);
        resources.buffer("method_decl_name_token", &method_decl_name_token);
        resources.buffer("method_decl_name_id", &method_decl_name_id);
        resources.buffer("method_decl_param_offset", &method_decl_param_offset);
        resources.buffer("method_decl_receiver_mode", &method_decl_receiver_mode);
        resources.buffer("method_decl_visibility", &method_decl_visibility);
        resources.buffer("method_decl_signature_flags", &method_decl_signature_flags);
        resources.buffer("method_key_to_fn_token", &method_key_to_fn_token);
        resources.buffer("sorted_method_key_order", &method_key_to_fn_token);
        resources.buffer("method_key_order_tmp", &method_key_order_tmp);
        resources.buffer("method_key_status", &method_key_status);
        resources.buffer("method_key_duplicate_of", &method_key_duplicate_of);
        resources.buffer(
            "method_key_radix_block_histogram",
            &method_key_radix_block_histogram,
        );
        resources.buffer(
            "method_key_radix_block_bucket_prefix",
            &method_key_radix_block_bucket_prefix,
        );
        resources.buffer(
            "method_key_radix_bucket_total",
            &method_key_radix_bucket_total,
        );
        resources.buffer(
            "method_key_radix_bucket_base",
            &method_key_radix_bucket_base,
        );
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
        resources.buffer("name_lexeme_flag", &name_lexeme_flag);
        resources.buffer("name_lexeme_kind", &name_lexeme_kind);
        resources.buffer("name_lexeme_prefix", &name_lexeme_prefix);
        resources.buffer("name_scan_local_prefix", &name_scan_local_prefix);
        resources.buffer("name_scan_block_sum", &name_scan_block_sum);
        resources.buffer("name_scan_prefix_a", &name_scan_prefix_a);
        resources.buffer("name_scan_prefix_b", &name_scan_prefix_b);
        resources.buffer("name_scan_total", &name_scan_total);
        resources.buffer("name_max_len", &name_max_len);
        resources.buffer("name_spans", &name_spans);
        resources.buffer("name_hash_lo", &name_order_in);
        resources.buffer("name_hash_hi", &name_order_tmp);
        resources.buffer("name_hash_table_a", &radix_block_histogram);
        resources.buffer("name_hash_table_b", &radix_block_bucket_prefix);
        resources.buffer("sorted_name_id", &sorted_name_id);
        resources.buffer("name_id_by_input", &name_id_by_input);
        resources.buffer("unique_name_count", &unique_name_count);
        resources.buffer("decl_name_token", &decl_name_token);
        resources.buffer("decl_id_by_name_token", &decl_id_by_name_token);
        resources.buffer("decl_kind", &decl_kind);
        resources.buffer("module_record_family_bits", &module_record_family_bits);
        resources.buffer("module_record_family_flag", &module_record_family_flag);
        resources.buffer("module_record_prefix", &module_record_prefix);
        resources.buffer(
            "module_record_scan_local_prefix",
            &module_record_scan_workspace.local_prefix,
        );
        resources.buffer(
            "module_record_scan_block_sum",
            &module_record_scan_workspace.block_sum,
        );
        resources.buffer(
            "module_record_scan_prefix_a",
            &module_record_scan_workspace.block_prefix,
        );
        resources.buffer(
            "module_record_scan_prefix_b",
            &module_record_scan_workspace.hierarchy,
        );
        resources.buffer(
            "module_value_scan_local_prefix",
            &module_value_scan_workspace.local_prefix,
        );
        resources.buffer(
            "module_value_scan_block_sum",
            &module_value_scan_workspace.block_sum,
        );
        resources.buffer(
            "module_value_scan_prefix_a",
            &module_value_scan_workspace.block_prefix,
        );
        resources.buffer(
            "module_value_scan_prefix_b",
            &module_value_scan_workspace.hierarchy,
        );
        resources.buffer(
            "module_path_key_radix_block_histogram",
            &module_path_key_radix_block_histogram,
        );
        resources.buffer(
            "module_path_key_radix_block_bucket_prefix",
            &module_path_key_radix_block_bucket_prefix,
        );
        resources.buffer(
            "module_path_key_radix_bucket_total",
            &module_path_key_radix_bucket_total,
        );
        resources.buffer(
            "module_path_key_radix_bucket_base",
            &module_path_key_radix_bucket_base,
        );
        resources.buffer("type_expr_ref_tag", &type_expr_ref_tag);
        resources.buffer("type_expr_ref_payload", &type_expr_ref_payload);
        resources.buffer("type_instance_kind", &type_instance_kind);
        resources.buffer("type_instance_head_token", &type_instance_head_token);
        resources.buffer(
            "type_decl_generic_param_count",
            &type_decl_generic_param_count,
        );
        resources.buffer(
            "type_decl_generic_param_count_by_owner_token",
            &type_decl_generic_param_count_by_owner_token,
        );
        resources.buffer(
            "type_decl_const_param_count_by_owner_token",
            &type_decl_const_param_count_by_owner_token,
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
        resources.buffer(
            "type_instance_external_canonical",
            &type_instance_external_canonical,
        );
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
            "type_semantic_row_by_token",
            &type_semantic_buffers.row_by_token,
        );
        resources.buffer(
            "type_semantic_scan_input",
            &type_semantic_buffers.scan_input,
        );
        resources.buffer("type_semantic_prefix", &type_semantic_buffers.prefix);
        resources.buffer("type_semantic_count_out", &type_semantic_buffers.count_out);
        resources.buffer(
            "type_semantic_row_by_ordinal",
            &type_semantic_buffers.row_by_ordinal,
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
        resources.buffer(
            "aggregate_compare_dispatch_args",
            &aggregate_compare_dispatch_args,
        );
        resources.buffer(
            "type_subtree_compare_scan_input",
            &type_subtree_compare_buffers.scan_input,
        );
        resources.buffer(
            "type_subtree_compare_prefix",
            &type_subtree_compare_buffers.prefix,
        );
        resources.buffer(
            "type_subtree_compare_count_out",
            &type_subtree_compare_buffers.count_out,
        );
        resources.buffer(
            "type_subtree_compare_left_root",
            &type_subtree_compare_buffers.left_root,
        );
        resources.buffer(
            "type_subtree_compare_right_root",
            &type_subtree_compare_buffers.right_root,
        );
        resources.buffer(
            "type_subtree_compare_error_token",
            &type_subtree_compare_buffers.error_token,
        );
        resources.buffer(
            "type_subtree_compare_error_detail",
            &type_subtree_compare_buffers.error_detail,
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
            "predicate_method_contract_owner_hir",
            &predicate_method_contract_owner_hir,
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
            "predicate_method_contract_param_type_node",
            &predicate_method_contract_param_type_node,
        );
        resources.buffer(
            "predicate_method_contract_key_order",
            &predicate_method_contract_key_order,
        );
        resources.buffer(
            "predicate_method_contract_key_order_tmp",
            &predicate_method_contract_key_order_tmp,
        );
        resources.buffer(
            "predicate_method_param_key_order",
            &predicate_method_param_key_order,
        );
        resources.buffer(
            "predicate_method_param_key_order_tmp",
            &predicate_method_param_key_order_tmp,
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
        resources.buffer(
            "predicate_owner_key_order_tmp",
            &predicate_owner_key_order_tmp,
        );
        resources.buffer("predicate_impl_key_order", &predicate_impl_key_order);
        resources.buffer(
            "predicate_impl_key_order_tmp",
            &predicate_impl_key_order_tmp,
        );
        resources.buffer(
            "predicate_key_radix_block_histogram",
            &predicate_key_radix_block_histogram,
        );
        resources.buffer(
            "predicate_key_radix_block_bucket_prefix",
            &predicate_key_radix_block_bucket_prefix,
        );
        resources.buffer(
            "predicate_key_radix_bucket_total",
            &predicate_key_radix_bucket_total,
        );
        resources.buffer(
            "predicate_key_radix_bucket_base",
            &predicate_key_radix_bucket_base,
        );
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
        resources.buffer(
            "predicate_obligation_scan_local_prefix",
            &predicate_obligation_scan_local_prefix,
        );
        resources.buffer(
            "predicate_obligation_scan_block_sum",
            &predicate_obligation_scan_block_sum,
        );
        resources.buffer(
            "predicate_obligation_scan_prefix_a",
            &predicate_obligation_scan_prefix_a,
        );
        resources.buffer(
            "predicate_obligation_scan_prefix_b",
            &predicate_obligation_scan_prefix_b,
        );
        resources.buffer(
            "predicate_obligation_pair_dispatch_args",
            &predicate_obligation_pair_dispatch_args,
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
        resources.buffer("member_next_node", &member_next_node);
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
            "struct_init_field_ordinal_by_row",
            &struct_init_field_ordinal_by_row,
        );
        resources.buffer(
            "struct_init_field_decl_token_by_row",
            &struct_init_field_decl_token_by_row,
        );
        resources.buffer(
            "struct_lit_context_decl_token",
            &struct_lit_context_decl_token,
        );
        resources.buffer("struct_lit_context_instance", &struct_lit_context_instance);
        resources.buffer(
            "array_element_struct_literal_node",
            &array_element_struct_literal_node,
        );
        resources.buffer("generic_decl_owner_by_node", &generic_decl_owner_by_node_a);
        resources.buffer("generic_param_count_out", &generic_param_count_out);
        resources.buffer("generic_param_owner_token", &generic_param_owner_token);
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
        let semantic_features = SemanticFeaturesOperation::new(
            device,
            &typecheck_graph,
            passes,
            &resources,
            &hir_active_dispatch_args,
        )?;
        typecheck_graph
            .validate_prefix_scan_bindings(compiler_graph::NAMES_SCAN.passes, &resources)?;
        let language_name_bind_groups =
            create_language_name_bind_groups(device, passes, &resources)?;
        let name_bind_groups = create_name_bind_groups_with_passes(
            passes,
            device,
            NameInput {
                params: &self.params_buf,
                source_len,
                cap: name_capacity,
                name_blocks: name_n_blocks,
                token_words: token_buf,
                token_count: token_count_buf,
                source_bytes: source_buf,
                status: &self.status_buf,
                lexemes: NameLexemeRows {
                    flag: &name_lexeme_flag,
                    kind: &name_lexeme_kind,
                    prefix: &name_lexeme_prefix,
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
                hash: NameHashRows {
                    table_a: &radix_block_histogram,
                    table_b: &radix_block_bucket_prefix,
                },
            },
            &resources,
        )?;
        for pass in [
            compiler_graph::LANGUAGE_NAMES_CLEAR_PASS,
            compiler_graph::NAMES_MARK_PASS,
            compiler_graph::LANGUAGE_TYPE_CODES_CLEAR_PASS,
            compiler_graph::LANGUAGE_DECLS_MATERIALIZE_PASS,
        ] {
            typecheck_graph.validate_registered_pass_bindings(pass, &resources)?;
        }
        typecheck_graph.validate_registered_pass_binding_aliases(
            compiler_graph::NAMES_SCATTER_PASS,
            &resources,
            &[
                ("name_order_in", "name_hash_lo"),
                ("name_order_tmp", "name_hash_hi"),
                ("name_count_out", "name_scan_total"),
                ("name_max_len_out", "name_max_len"),
            ],
        )?;
        for pass in [
            compiler_graph::NAMES_HASH_PREPARE_PASS,
            compiler_graph::NAMES_HASH_INSERT_PASS,
            compiler_graph::NAMES_HASH_ASSIGN_PASS,
        ] {
            typecheck_graph.validate_registered_pass_binding_aliases(
                pass,
                &resources,
                &[("name_count_in", "name_scan_total")],
            )?;
        }
        allocation_stamp!("core_and_name_bind_groups");
        let module_path = if let Some(hir_items) = hir_items {
            Some(create_module_path_state_with_passes(
                passes,
                device,
                ModulePathCreateInputs {
                    params: &self.params_buf,
                    source_len,
                    source_file_capacity,
                    token_capacity,
                    hir_node_capacity,
                    parser_hir_node_capacity,
                    token_buf,
                    token_count_buf,
                    token_file_id_buf,
                    source_buf,
                    hir_status_buf,
                    hir_kind_buf,
                    hir_token_pos_buf,
                    hir_token_end_buf,
                    status_buf: &self.status_buf,
                    hir_active_count_buf: &hir_active_count,
                    hir_active_dispatch_args: &hir_active_dispatch_args,
                    hir_items,
                    name_id_by_token: &name_id_by_token,
                    name_spans: &name_spans,
                    name_hash_lo: &name_order_in,
                    name_hash_hi: &name_order_tmp,
                    language_symbol_bytes: &language_symbol_bytes,
                    language_name_id: &language_name_id,
                    decl_name_token: &decl_name_token,
                    decl_id_by_name_token: &decl_id_by_name_token,
                    decl_kind: &decl_kind,
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
                    call_dependency_decl: &call_dependency_decl,
                    call_return_type: &call_return_type,
                    call_return_type_token: &call_return_type_token,
                    call_generic_slot_type: &call_generic_slot_type,
                    call_generic_slot_ordinal: &call_generic_slot_ordinal,
                    call_generic_claim_count_out: &call_generic_claim_count_out,
                    call_generic_claim_callee: &call_generic_claim_callee,
                    call_generic_claim_slot: &call_generic_claim_slot,
                    call_generic_claim_type: &call_generic_claim_type,
                    call_generic_claim_ref_tag: &call_generic_claim_ref_tag,
                    call_generic_claim_ref_payload: &call_generic_claim_ref_payload,
                    call_generic_claim_order: &call_generic_claim_order,
                    method_call_name_id: &method_call_name_id,
                    call_param_count: &call_param_count,
                    call_param_row_count_out: &call_param_row_count_out,
                    call_param_row_node: &call_param_row_node,
                    call_param_row_fn_token: &call_param_row_fn_token,
                    call_param_row_ordinal: &call_param_row_ordinal,
                    call_param_row_type: &call_param_row_type,
                    call_param_row_ref_tag: &call_param_row_ref_tag,
                    call_param_row_ref_payload: &call_param_row_ref_payload,
                    call_param_row_start: &call_param_row_start,
                    call_param_row_count: &call_param_row_count,
                    aggregate_compare_scan_input: &aggregate_compare_scan_input,
                    aggregate_compare_expected_instance: &aggregate_compare_expected_instance,
                    aggregate_compare_actual_instance: &aggregate_compare_actual_instance,
                    aggregate_compare_error_token: &aggregate_compare_error_token,
                    aggregate_compare_error_detail: &aggregate_compare_error_detail,
                    call_arg_row_node: &call_arg_row_node,
                    call_arg_row_call_node: &call_arg_row_call_node,
                    call_arg_row_ordinal: &call_arg_row_ordinal,
                    call_arg_row_start: &call_arg_row_start,
                    call_arg_row_count: &call_arg_row_count,
                    type_expr_ref_tag: &type_expr_ref_tag,
                    type_expr_ref_payload: &type_expr_ref_payload,
                    type_instance_kind: &type_instance_kind,
                    type_instance_decl_token: &type_instance_decl_token,
                    type_instance_external_canonical: &type_instance_external_canonical,
                    type_instance_arg_start: &type_instance_arg_start,
                    type_instance_arg_count: &type_instance_arg_count,
                    type_instance_arg_ref_tag: &type_instance_arg_ref_tag,
                    type_instance_arg_ref_payload: &type_instance_arg_ref_payload,
                    type_instance_arg_row_start: &type_instance_arg_row_start,
                    type_instance_arg_row_count_out: &type_instance_arg_row_count_out,
                    type_instance_arg_row_ref_tag: &type_instance_arg_row_ref_tag,
                    type_instance_arg_row_ref_payload: &type_instance_arg_row_ref_payload,
                    type_semantic_row_by_token: &type_semantic_buffers.row_by_token,
                    type_semantic_scan_input: &type_semantic_buffers.scan_input,
                    type_semantic_prefix: &type_semantic_buffers.prefix,
                    type_semantic_count_out: &type_semantic_buffers.count_out,
                    type_semantic_row_by_ordinal: &type_semantic_buffers.row_by_ordinal,
                    type_instance_elem_ref_tag: &type_instance_elem_ref_tag,
                    type_instance_elem_ref_payload: &type_instance_elem_ref_payload,
                    type_instance_len_kind: &type_instance_len_kind,
                    type_instance_len_payload: &type_instance_len_payload,
                    type_decl_generic_param_count: &type_decl_generic_param_count,
                    type_decl_generic_param_count_by_owner_token:
                        &type_decl_generic_param_count_by_owner_token,
                    type_generic_param_slot_by_token: &type_generic_param_slot_by_token,
                    type_decl_hir_node_by_token: &type_decl_hir_node_by_token,
                    generic_param_count_out: &generic_param_count_out,
                    generic_param_owner_token: &generic_param_owner_token,
                    generic_param_name_id: &generic_param_name_id,
                    generic_param_token: &generic_param_token,
                    generic_param_kind: &generic_param_kind,
                    generic_param_key_order: &generic_param_key_order,
                    generic_param_slot_order: &generic_param_slot_order,
                    type_instance_state: &type_instance_state,
                    decl_type_ref_tag: &decl_type_ref_tag,
                    decl_type_ref_payload: &decl_type_ref_payload,
                    fn_return_ref_tag: &fn_return_ref_tag,
                    fn_return_ref_payload: &fn_return_ref_payload,
                    module_record_family_bits: &module_record_family_bits,
                    module_record_family_flag: &module_record_family_flag,
                    module_record_prefix: &module_record_prefix,
                    module_record_scan_workspace: module_record_scan_workspace.as_ref(),
                    module_value_scan_workspace: module_value_scan_workspace.as_ref(),
                    decl_type_key_prefix: &decl_type_key_prefix,
                    decl_value_key_prefix: &decl_value_key_prefix,
                    decl_type_key_count_out: &decl_type_key_count_out,
                    decl_value_key_count_out: &decl_value_key_count_out,
                    decl_status: &decl_status,
                    import_visible_type_count: &import_visible_type_count,
                    import_visible_value_count: &import_visible_value_count,
                    import_visible_type_prefix: &import_visible_type_prefix,
                    import_visible_value_prefix: &import_visible_value_prefix,
                    import_visible_type_count_out: &import_visible_type_count_out,
                    import_visible_value_count_out: &import_visible_value_count_out,
                    module_path_key_radix_block_histogram: &module_path_key_radix_block_histogram,
                    module_path_key_radix_block_bucket_prefix:
                        &module_path_key_radix_block_bucket_prefix,
                    module_path_key_radix_bucket_total: &module_path_key_radix_bucket_total,
                    module_path_key_radix_bucket_base: &module_path_key_radix_bucket_base,
                    external_scratch: module_path_scratch,
                    dependency_interfaces,
                },
            )?)
        } else {
            None
        };
        allocation_stamp!("module_path");
        register_module_path_resources(&mut resources, module_path.as_ref());
        typecheck_graph.validate_module_prefix_scan_bindings(&resources)?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::MODULE_DECL_ROWS_MATERIALIZE_PASS,
            &resources,
        )?;
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
        let compact_hir_count = buffer_from_resources(&resources, "compact_hir_count")?;
        let compact_hir_core = buffer_from_resources(&resources, "compact_hir_core")?;
        let compact_hir_links = buffer_from_resources(&resources, "compact_hir_links")?;
        let compact_hir_payload = buffer_from_resources(&resources, "compact_hir_payload")?;
        let compact_hir_expr_parent = buffer_from_resources(&resources, "compact_hir_expr_parent")?;
        let token_words = buffer_from_resources(&resources, "token_words")?;
        let semantic_calls_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.calls",
            &passes.semantic_calls_project,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::SEMANTIC_CALLS_PROJECT_PASS,
            &resources,
        )?;
        let semantic_artifact_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.project",
            &passes.semantic_artifact_project,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::SEMANTIC_ARTIFACT_PROJECT_PASS,
            &resources,
        )?;
        resources.buffer("compact_expr_scalar_type_out", &typecheck_graph.scalar_a);
        let compact_expr_scalar_type_init = reflected_bind_group_from_resources(
            device,
            "type_check.expression_types.init",
            &passes.expression_types_init,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(compiler_graph::INIT_PASS, &resources)?;
        let compact_expr_scalar_type_step_count = typecheck_graph.step_count();
        let compact_expr_scalar_type_steps = (0..compact_expr_scalar_type_step_count)
            .map(|step| {
                let (input, output) = if step % 2 == 0 {
                    (&compact_expr_scalar_type_a, &compact_expr_scalar_type_b)
                } else {
                    (&compact_expr_scalar_type_b, &compact_expr_scalar_type_a)
                };
                resources.buffer("compact_expr_scalar_type_in", input);
                resources.buffer("compact_expr_scalar_type_out", output);
                let bind_group = reflected_bind_group_from_resources(
                    device,
                    "type_check.expression_types.step",
                    &passes.expression_types_step,
                    &resources,
                )?;
                typecheck_graph.validate_registered_pass_bindings(
                    typecheck_graph.step_pass_name(step),
                    &resources,
                )?;
                Ok(bind_group)
            })
            .collect::<Result<Vec<_>>>()?;
        let compact_expr_scalar_type = if compact_expr_scalar_type_steps.len() % 2 == 0 {
            compact_expr_scalar_type_a.clone()
        } else {
            compact_expr_scalar_type_b.clone()
        };
        resources.buffer("compact_expr_scalar_type", &compact_expr_scalar_type);
        let semantic_expression_refs_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.expression_refs",
            &passes.semantic_expression_refs_project,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::SEMANTIC_EXPRESSION_REFS_PROJECT_PASS,
            &resources,
        )?;
        let semantic_struct_literal_refs_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.struct_literal_refs",
            &passes.semantic_struct_literal_refs_project,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::SEMANTIC_STRUCT_LITERAL_REFS_PROJECT_PASS,
            &resources,
        )?;
        let semantic_array_index_refs_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.array_index_refs",
            &passes.semantic_array_index_refs_project,
            &resources,
        )?;
        if array_passes_required(parser_feature_flags) {
            typecheck_graph.validate_registered_pass_bindings(
                compiler_graph::SEMANTIC_ARRAY_INDEX_REFS_PROJECT_PASS,
                &resources,
            )?;
        }
        let conditions_compact_expr = reflected_bind_group_from_resources(
            device,
            "type_check.conditions.compact_expr",
            &passes.conditions_compact_expr,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::CONDITIONS_COMPACT_EXPR_PASS,
            &resources,
        )?;
        let conditions_compact_stmt = reflected_bind_group_from_resources(
            device,
            "type_check.conditions.compact_stmt",
            &passes.conditions_compact_stmt,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::CONDITIONS_COMPACT_STMT_PASS,
            &resources,
        )?;
        let conditions_compact_aggregate_requests = reflected_bind_group_from_resources(
            device,
            "type_check.conditions.compact_aggregate_requests",
            &passes.conditions_compact_aggregate_requests,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::CONDITIONS_COMPACT_AGGREGATE_REQUESTS_PASS,
            &resources,
        )?;
        let conditions_compact_calls = resources.reflected_bind_group_with_overrides(
            device,
            "type_check.conditions.compact_calls",
            &passes.conditions_compact_calls,
            &[("call_fn_index", backend_call_fn_index.as_entire_binding())],
        )?;
        typecheck_graph.validate_registered_pass_binding_aliases(
            compiler_graph::CONDITIONS_COMPACT_CALLS_PASS,
            &resources,
            &[("call_fn_index", "backend_call_fn_index")],
        )?;
        let conditions_compact_types = reflected_bind_group_from_resources(
            device,
            "type_check.conditions.compact_types",
            &passes.conditions_compact_types,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::CONDITIONS_COMPACT_TYPES_PASS,
            &resources,
        )?;
        let conditions_compact_methods = reflected_bind_group_from_resources(
            device,
            "type_check.conditions.compact_methods",
            &passes.conditions_compact_methods,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::CONDITIONS_COMPACT_METHODS_PASS,
            &resources,
        )?;
        let semantic_predicate_diagnostics_clear = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.predicate_diagnostics.clear",
            &passes.semantic_predicate_diagnostics_clear,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::PREDICATE_DIAGNOSTICS_CLEAR_PASS,
            &resources,
        )?;
        let semantic_predicate_diagnostics_claim = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.predicate_diagnostics.claim",
            &passes.semantic_predicate_diagnostics_claim,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::PREDICATE_DIAGNOSTICS_CLAIM_PASS,
            &resources,
        )?;
        let semantic_predicate_diagnostics_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.predicate_diagnostics",
            &passes.semantic_predicate_diagnostics_project,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::PREDICATE_DIAGNOSTICS_PROJECT_PASS,
            &resources,
        )?;
        let conditions_compact_predicates = reflected_bind_group_from_resources(
            device,
            "type_check.conditions.compact_predicates",
            &passes.conditions_compact_predicates,
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::CONDITIONS_COMPACT_PREDICATES_PASS,
            &resources,
        )?;
        let conditions_compact_names = bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.conditions.compact_names"),
            &passes.conditions_compact_names,
            0,
            &[
                ("gParams", self.params_buf.as_entire_binding()),
                ("compact_hir_count", compact_hir_count.as_entire_binding()),
                ("compact_hir_core", compact_hir_core.as_entire_binding()),
                ("compact_hir_links", compact_hir_links.as_entire_binding()),
                (
                    "compact_hir_payload",
                    compact_hir_payload.as_entire_binding(),
                ),
                (
                    "compact_hir_expr_parent",
                    compact_hir_expr_parent.as_entire_binding(),
                ),
                ("token_words", token_words.as_entire_binding()),
                (
                    "predicate_syntax_token",
                    predicate_syntax_token.as_entire_binding(),
                ),
                ("type_expr_ref_tag", type_expr_ref_tag.as_entire_binding()),
                (
                    "module_type_path_status",
                    module_type_path_status.as_entire_binding(),
                ),
                (
                    "module_value_path_status",
                    module_value_path_status.as_entire_binding(),
                ),
                (
                    "module_value_path_call_leaf",
                    module_value_path_call_leaf.as_entire_binding(),
                ),
                (
                    "module_value_path_associated_method_token",
                    module_value_path_associated_method_token.as_entire_binding(),
                ),
                ("visible_decl", visible_decl.as_entire_binding()),
                ("visible_type", visible_type.as_entire_binding()),
                ("call_fn_index", backend_call_fn_index.as_entire_binding()),
                ("call_return_type", call_return_type.as_entire_binding()),
                ("call_intrinsic_tag", call_intrinsic_tag.as_entire_binding()),
                (
                    "method_call_name_id",
                    method_call_name_id.as_entire_binding(),
                ),
                ("enclosing_fn", enclosing_fn.as_entire_binding()),
                ("status", self.status_buf.as_entire_binding()),
            ],
        )?;
        typecheck_graph.validate_registered_pass_binding_aliases(
            compiler_graph::CONDITIONS_COMPACT_NAMES_PASS,
            &resources,
            &[("call_fn_index", "backend_call_fn_index")],
        )?;
        let aggregate_compare_scan = PrefixScanOperation::from_resource_names(
            device,
            "type_check.conditions.aggregate_compare_scan",
            passes.into(),
            &resources,
            compiler_graph::AGGREGATE_SCAN_RESOURCES,
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
        for pass in [
            compiler_graph::CONDITIONS_AGGREGATE_ARGS_CALLS_PASS,
            compiler_graph::CONDITIONS_AGGREGATE_ARGS_FINAL_PASS,
        ] {
            typecheck_graph.validate_registered_pass_bindings(pass, &resources)?;
        }
        let type_subtree_compare_scan = Box::new(PrefixScanOperation::from_resource_names(
            device,
            "type_check.conditions.type_subtree_compare_scan",
            passes.into(),
            &resources,
            compiler_graph::TYPE_SUBTREE_SCAN_RESOURCES,
        )?);
        let type_subtree_compare_dispatch = Box::new(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.conditions.type_subtree_compare_dispatch"),
            &passes.count_dispatch_args,
            0,
            &[
                (
                    "gParams",
                    type_subtree_compare_buffers
                        .dispatch_params
                        .as_entire_binding(),
                ),
                (
                    "count_in",
                    type_subtree_compare_buffers.count_out.as_entire_binding(),
                ),
                (
                    "dispatch_args",
                    type_subtree_compare_buffers
                        .dispatch_args
                        .as_entire_binding(),
                ),
            ],
        )?);
        let conditions_type_subtree = Box::new(reflected_bind_group_from_resources(
            device,
            "type_check_resident_conditions_type_subtree",
            &passes.conditions_type_subtree,
            &resources,
        )?);
        let calls = create_call_bind_groups(
            device,
            &typecheck_graph,
            passes,
            &resources,
            &hir_active_dispatch_args,
            token_capacity,
            hir_node_capacity,
            call_param_row_capacity,
            call_generic_claim_capacity,
            &call_generic_claim_radix_dispatch_args,
            &call_const_claim_radix_dispatch_args,
            &call_required_generic_dispatch_args,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::REQUIRED_GENERIC_DISPATCH_PASS,
            &resources,
        )?;
        typecheck_graph
            .validate_prefix_scan_bindings(compiler_graph::GENERIC_CLAIM_SCAN.passes, &resources)?;
        typecheck_graph.validate_prefix_scan_bindings(
            compiler_graph::REQUIRED_GENERIC_SCAN.passes,
            &resources,
        )?;
        for passes in [
            compiler_graph::AGGREGATE_CALL_SCAN_PASSES,
            compiler_graph::AGGREGATE_FINAL_SCAN_PASSES,
            compiler_graph::TYPE_SUBTREE_CALL_SCAN_PASSES,
            compiler_graph::TYPE_SUBTREE_FINAL_SCAN_PASSES,
            compiler_graph::CALL_PARAM_ROW_SCAN.passes,
            compiler_graph::CALL_ARG_ROW_SCAN.passes,
        ] {
            typecheck_graph.validate_prefix_scan_bindings(passes, &resources)?;
        }
        allocation_stamp!("conditions_and_calls");
        resources.buffer("hir_visible_decl_flag", &hir_visible_decl_flag);
        resources.buffer("hir_visible_decl_prefix", &hir_visible_decl_prefix);
        resources.buffer("hir_semantic_dispatch_args", &hir_semantic_dispatch_args);
        resources.buffer(
            "hir_visible_decl_scan_local_prefix",
            &hir_visible_decl_scan_local_prefix,
        );
        resources.buffer(
            "hir_visible_decl_scan_block_sum",
            &hir_visible_decl_scan_block_sum,
        );
        resources.buffer(
            "hir_visible_decl_scan_prefix_a",
            &hir_visible_decl_scan_prefix_a,
        );
        resources.buffer(
            "hir_visible_decl_scan_prefix_b",
            &hir_visible_decl_scan_prefix_b,
        );
        for pass in compiler_graph::REGISTERED_VISIBLE_PASSES
            .into_iter()
            .chain(compiler_graph::VISIBLE_RADIX_SORT.passes.names())
        {
            if typecheck_graph.contains_pass(pass) {
                typecheck_graph.validate_registered_pass_bindings(pass, &resources)?;
            }
        }
        typecheck_graph
            .validate_prefix_scan_bindings(compiler_graph::VISIBLE_SCAN.passes, &resources)?;
        resources.buffer(
            "generic_decl_owner_by_node_a",
            &generic_decl_owner_by_node_a,
        );
        resources.buffer(
            "generic_decl_owner_by_node_b",
            &generic_decl_owner_by_node_b,
        );
        resources.buffer(
            "predicate_bound_list_by_node_a",
            &predicate_bound_list_by_node_a,
        );
        resources.buffer(
            "predicate_bound_list_by_node_b",
            &predicate_bound_list_by_node_b,
        );
        resources.buffer(
            "predicate_bound_list_by_node",
            &predicate_bound_list_by_node_a,
        );
        resources.buffer(
            "predicate_trait_impl_trait_type_node",
            &predicate_bound_list_by_node_b,
        );
        resources.buffer("generic_decl_parent_jump_a", &generic_decl_parent_jump_a);
        resources.buffer("generic_decl_parent_jump_b", &generic_decl_parent_jump_b);
        resources.buffer("generic_decl_owner_by_node", &generic_decl_owner_by_node_a);
        resources.buffer("generic_param_count_out", &generic_param_count_out);
        resources.buffer("generic_param_owner_token", &generic_param_owner_token);
        resources.buffer("generic_param_name_id", &generic_param_name_id);
        resources.buffer("generic_param_token", &generic_param_token);
        resources.buffer("generic_param_node", &generic_param_node);
        resources.buffer("generic_param_kind", &generic_param_kind);
        resources.buffer("generic_param_key_order", &generic_param_key_order);
        if let Some(buffer) = generic_param_key_order_tmp.as_ref() {
            resources.buffer("generic_param_key_order_tmp", buffer);
        }
        resources.buffer("generic_param_slot_order", &generic_param_slot_order);
        if let Some(buffer) = generic_param_slot_order_tmp.as_ref() {
            resources.buffer("generic_param_slot_order_tmp", buffer);
        }
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
        if let Some(buffer) = typecheck_graph
            .generic_param_slot_radix_block_histogram
            .as_ref()
        {
            resources.buffer("generic_param_slot_radix_block_histogram", buffer);
        }
        if let Some(buffer) = typecheck_graph
            .generic_param_slot_radix_block_bucket_prefix
            .as_ref()
        {
            resources.buffer("generic_param_slot_radix_block_bucket_prefix", buffer);
        }
        if let Some(buffer) = typecheck_graph
            .generic_param_slot_radix_bucket_total
            .as_ref()
        {
            resources.buffer("generic_param_slot_radix_bucket_total", buffer);
        }
        if let Some(buffer) = typecheck_graph
            .generic_param_slot_radix_bucket_base
            .as_ref()
        {
            resources.buffer("generic_param_slot_radix_bucket_base", buffer);
        }
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::TYPE_INSTANCE_ARG_ROW_CLEAR_PASS,
            &resources,
        )?;
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
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::TYPE_INSTANCES_MARK_GENERIC_PARAM_RECORDS_PASS,
            &resources,
        )?;
        if generic_decl_owner_step_count(hir_node_capacity) > 0 {
            typecheck_graph.validate_registered_pass_binding_aliases(
                compiler_graph::TYPE_INSTANCES_PROPAGATE_GENERIC_OWNER_A_TO_B_PASS,
                &resources,
                &[
                    (
                        "generic_decl_owner_by_node_in",
                        "generic_decl_owner_by_node_a",
                    ),
                    (
                        "predicate_bound_list_by_node_in",
                        "predicate_bound_list_by_node_a",
                    ),
                    ("generic_decl_parent_jump_in", "generic_decl_parent_jump_a"),
                    (
                        "generic_decl_owner_by_node_out",
                        "generic_decl_owner_by_node_b",
                    ),
                    (
                        "predicate_bound_list_by_node_out",
                        "predicate_bound_list_by_node_b",
                    ),
                    ("generic_decl_parent_jump_out", "generic_decl_parent_jump_b"),
                ],
            )?;
            typecheck_graph.validate_registered_pass_binding_aliases(
                compiler_graph::TYPE_INSTANCES_PROPAGATE_GENERIC_OWNER_B_TO_A_PASS,
                &resources,
                &[
                    (
                        "generic_decl_owner_by_node_in",
                        "generic_decl_owner_by_node_b",
                    ),
                    (
                        "predicate_bound_list_by_node_in",
                        "predicate_bound_list_by_node_b",
                    ),
                    ("generic_decl_parent_jump_in", "generic_decl_parent_jump_b"),
                    (
                        "generic_decl_owner_by_node_out",
                        "generic_decl_owner_by_node_a",
                    ),
                    (
                        "predicate_bound_list_by_node_out",
                        "predicate_bound_list_by_node_a",
                    ),
                    ("generic_decl_parent_jump_out", "generic_decl_parent_jump_a"),
                ],
            )?;
        }
        typecheck_graph.validate_registered_generic_param_bindings(&resources)?;
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
                    generic_param_count_by_node: &type_decl_generic_param_count_by_owner_token,
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
                        method_contract_owner_hir: &predicate_method_contract_owner_hir,
                        method_contract_name_token: &predicate_method_contract_name_token,
                        method_contract_name_id: &predicate_method_contract_name_id,
                        method_contract_param_count: &predicate_method_contract_param_count,
                        method_contract_return_type_node:
                            &predicate_method_contract_return_type_node,
                        method_contract_visibility: &predicate_method_contract_visibility,
                        method_contract_status: &predicate_method_contract_status,
                        method_contract_param_type_node: &predicate_method_contract_param_type_node,
                        method_contract_owner_range_first:
                            &predicate_method_contract_owner_range_first,
                        method_contract_owner_range_count:
                            &predicate_method_contract_owner_range_count,
                    },
                    obligation_rows: PredicateObligationRows {
                        pair_total: &predicate_obligation_pair_total,
                        pair_dispatch_args: &predicate_obligation_pair_dispatch_args,
                    },
                },
                &resources,
            )?)
        } else {
            None
        };
        if predicates.is_some() {
            for pass in compiler_graph::REGISTERED_PREDICATE_DIRECT_PASSES {
                typecheck_graph.validate_registered_pass_bindings(pass, &resources)?;
            }
            for pass in compiler_graph::REGISTERED_PREDICATE_LOGICAL_PASSES {
                typecheck_graph.validate_registered_pass_bindings(pass, &resources)?;
            }
            typecheck_graph.validate_prefix_scan_bindings(
                compiler_graph::PREDICATES_OBLIGATION_PAIR_SCAN.passes,
                &resources,
            )?;
        }
        allocation_stamp!("predicates");
        if struct_init_passes_required(parser_feature_flags) {
            for pass in [
                compiler_graph::TYPE_INSTANCES_STRUCT_INIT_CLEAR_PASS,
                compiler_graph::TYPE_INSTANCES_STRUCT_INIT_CONTEXTS_PASS,
                compiler_graph::TYPE_INSTANCES_STRUCT_INIT_FIELDS_PASS,
                compiler_graph::TYPE_INSTANCES_STRUCT_INIT_SUBSTITUTE_PASS,
            ] {
                typecheck_graph.validate_registered_pass_bindings(pass, &resources)?;
            }
        }
        if member_passes_required(parser_feature_flags) {
            for pass in [
                compiler_graph::TYPE_INSTANCES_MEMBER_RECEIVERS_PASS,
                compiler_graph::TYPE_INSTANCES_MEMBER_RECEIVERS_AFTER_ARRAY_PASS,
                compiler_graph::TYPE_INSTANCES_MEMBER_RESULTS_PASS,
                compiler_graph::TYPE_INSTANCES_MEMBER_RESULTS_AFTER_ARRAY_PASS,
                compiler_graph::TYPE_INSTANCES_MEMBER_SUBSTITUTE_PASS,
                compiler_graph::TYPE_INSTANCES_MEMBER_SUBSTITUTE_AFTER_ARRAY_PASS,
            ] {
                typecheck_graph.validate_registered_pass_bindings(pass, &resources)?;
            }
        }
        let type_instances = create_type_instance_bind_groups(
            device,
            passes,
            &resources,
            token_capacity,
            hir_node_capacity,
            &hir_visible_decl_key_radix_dispatch_args,
        )?;
        for passes in [
            compiler_graph::TYPE_INSTANCE_ARG_ROW_SCAN.passes,
            compiler_graph::TYPE_SEMANTIC_SCAN.passes,
        ] {
            typecheck_graph.validate_prefix_scan_bindings(passes, &resources)?;
        }
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
        for pass in [
            compiler_graph::METHOD_KEY_SEED_PASS,
            compiler_graph::METHOD_KEY_VALIDATION_PASS,
        ] {
            typecheck_graph.validate_registered_pass_bindings(pass, &resources)?;
        }

        let method_key_pipeline = MethodKeyPipeline::new(
            device,
            passes,
            &resources,
            "type_check_resident_methods",
            token_capacity,
            name_n_blocks,
        )?;
        let methods = create_method_bind_groups(
            device,
            &typecheck_graph,
            passes,
            &resources,
            method_key_pipeline,
            &token_active_dispatch_args,
            &method_token_dispatch_args,
            &method_compact_dispatch_args,
            &method_hir_dispatch_args,
            &method_token_hir_dispatch_args,
        )?;
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
        for pass in [
            compiler_graph::RETURNS_CLEAR_PASS,
            compiler_graph::RETURNS_MARK_PASS,
            compiler_graph::RETURNS_MARK_IF_PASS,
            compiler_graph::RETURNS_VALIDATE_PASS,
        ] {
            typecheck_graph.validate_registered_pass_bindings(pass, &resources)?;
        }
        let scope_hir = reflected_bind_group_from_resources(
            device,
            "type_check_resident_scope_hir",
            &passes.scope_hir,
            &resources,
        )?;
        typecheck_graph
            .validate_registered_pass_bindings(compiler_graph::SCOPE_HIR_PASS, &resources)?;
        let if_depth_bind_groups = create_if_depth_bind_groups_with_passes(
            passes,
            device,
            &if_depth_params,
            compact_hir_count,
            compact_hir_core,
            &if_delta,
            &if_depth_inblock,
            &if_block_sum,
            &if_prefix_a,
            &if_prefix_b,
            &if_block_prefix,
            &if_depth,
        )?;
        for pass in [
            compiler_graph::IF_DEPTH_CLEAR_PASS,
            compiler_graph::IF_DEPTH_MARK_PASS,
            compiler_graph::IF_DEPTH_LOCAL_PASS,
            compiler_graph::IF_DEPTH_SCAN_PASS,
            compiler_graph::IF_DEPTH_APPLY_PASS,
        ] {
            typecheck_graph.validate_registered_pass_bindings(pass, &resources)?;
        }
        let fn_context_bind_groups = create_fn_context_bind_groups_with_passes(
            passes,
            device,
            &resources,
            &fn_params,
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
        for pass in [
            compiler_graph::FN_CONTEXT_CLEAR_PASS,
            compiler_graph::FN_CONTEXT_MARK_PASS,
            compiler_graph::FN_CONTEXT_LOCAL_PASS,
            compiler_graph::FN_CONTEXT_SCAN_PASS,
            compiler_graph::FN_CONTEXT_APPLY_PASS,
        ] {
            typecheck_graph.validate_registered_pass_bindings(pass, &resources)?;
        }
        let visible_bind_groups = create_resident_visible_bind_groups(
            passes,
            device,
            &resources,
            VisibleShape {
                hir_nodes: hir_node_capacity,
                record_capacity: hir_visible_decl_capacity,
                record_blocks: hir_decl_record_n_blocks,
                leaf_base: hir_decl_tree_leaf_base,
            },
            VisibleRows {
                semantic_count: hir_items
                    .map(|items| &items.hir.count.buffer)
                    .unwrap_or(&hir_active_count),
                semantic_dispatch_args: &hir_semantic_dispatch_args,
                count_out: &hir_visible_decl_count_out,
                scope_end: &hir_visible_decl_scope_end,
                order: &hir_visible_decl_key_order,
                key_args: &hir_visible_decl_key_radix_dispatch_args,
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
                parser_feature_flags: hir_items
                    .map(|items| items.parser_feature_flags)
                    .unwrap_or(u32::MAX),
                input_fingerprint,
                uses_hir_items,
            },
            typecheck_graph,
            compact_expr_scalar_type,
            compact_expr_scalar_type_init,
            compact_expr_scalar_type_steps,
            name_capacity,
            name_n_blocks,
            if_depth_n_blocks,
            fn_n_blocks,
            language_symbol_bytes,
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
            token_active_dispatch_args,
            hir_active_dispatch_args,
            token_hir_active_dispatch_args,
            hir_active_count,
            hir_active_dispatch,
            semantic_features,
            call_dependency_decl,
            call_generic_claim_count_out,
            call_generic_claim_scan_input,
            call_generic_claim_prefix,
            call_generic_claim_callee,
            call_generic_claim_slot,
            call_generic_claim_type,
            call_generic_claim_ref_tag,
            call_generic_claim_ref_payload,
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
            call_generic_claim_scan_local_prefix,
            call_generic_claim_scan_block_sum,
            call_generic_claim_scan_prefix_a,
            call_generic_claim_scan_prefix_b,
            method_module_count_out_implicit_root,
            type_instance_decl_token,
            type_instance_external_canonical,
            type_semantic_buffers,
            aggregate_compare_dispatch_params,
            type_subtree_compare_buffers,
            decl_type_ref_tag,
            decl_type_ref_payload,
            name_bind_groups,
            language_name_bind_groups,
            if_depth_params,
            fn_params,
            if_depth_bind_groups,
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
            semantic_predicate_diagnostics_clear,
            semantic_predicate_diagnostics_claim,
            semantic_predicate_diagnostics_project,
            conditions_compact_expr,
            conditions_compact_stmt,
            conditions_compact_aggregate_requests,
            conditions_compact_calls,
            conditions_compact_types,
            conditions_compact_methods,
            conditions_compact_predicates,
            conditions_compact_names,
            semantic_expression_refs_project,
            semantic_struct_literal_refs_project,
            semantic_array_index_refs_project,
            semantic_calls_project,
            semantic_artifact_project,
            aggregate_compare_scan,
            aggregate_compare_dispatch,
            conditions_aggregate_args,
            type_subtree_compare_scan,
            type_subtree_compare_dispatch,
            conditions_type_subtree,
            scope_hir,
        })
    }
}
