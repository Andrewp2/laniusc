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
        let compact_expr_scalar_type_a =
            typecheck_graph.u32_buffer("compact_expr_scalar_type.a")?;
        let compact_expr_scalar_type_b =
            typecheck_graph.u32_buffer("compact_expr_scalar_type.b")?;
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
        let generic_param_count_out = typecheck_graph.u32_buffer("generic_param_count_out")?;
        let generic_param_owner_token = typecheck_graph.u32_buffer("generic_param_owner_token")?;
        let generic_param_name_id = typecheck_graph.u32_buffer("generic_param_name_id")?;
        let generic_param_token = typecheck_graph.u32_buffer("generic_param_token")?;
        let generic_param_kind = typecheck_graph.u32_buffer("generic_param_kind")?;
        let generic_param_key_order = typecheck_graph.u32_buffer("generic_param_key_order")?;
        let generic_param_key_order_tmp =
            typecheck_graph.optional_buffer::<u32>("generic_param_key_order_tmp")?;
        let generic_param_slot_order = typecheck_graph.u32_buffer("generic_param_slot_order")?;
        let generic_param_slot_order_tmp =
            typecheck_graph.optional_buffer::<u32>("generic_param_slot_order_tmp")?;
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
        let enclosing_fn = typecheck_graph.u32_buffer("enclosing_fn")?;
        let call_fn_index = typecheck_graph.u32_buffer("call_fn_index")?;
        let backend_call_fn_index = typecheck_graph.u32_buffer("backend_call_fn_index")?;
        let call_dependency_decl = typed_storage_u32_fill_rw(
            device,
            "type_check.resident.call_dependency_decl",
            token_capacity as usize,
            u32::MAX,
            wgpu::BufferUsages::empty(),
        );
        let call_intrinsic_tag = typecheck_graph.u32_buffer("call_intrinsic_tag")?;
        let call_return_type = typecheck_graph.u32_buffer("call_return_type")?;
        let call_return_type_token = typecheck_graph.u32_buffer("call_return_type_token")?;
        let call_param_count = typecheck_graph.u32_buffer("call_param_count")?;
        let call_generic_slot_type = typecheck_graph.u32_buffer("call_generic_slot_type")?;
        let call_generic_slot_ordinal = typecheck_graph.u32_buffer("call_generic_slot_ordinal")?;
        let call_arg_row_node = typecheck_graph.u32_buffer("call_arg_row_node")?;
        let call_arg_row_call_node = typecheck_graph.u32_buffer("call_arg_row_call_node")?;
        let call_arg_row_ordinal = typecheck_graph.u32_buffer("call_arg_row_ordinal")?;
        let call_arg_row_start = typecheck_graph.u32_buffer("call_arg_row_start")?;
        let call_arg_row_count = typecheck_graph.u32_buffer("call_arg_row_count")?;
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
        let method_call_name_id = typecheck_graph.u32_buffer("method_call_name_id")?;
        let type_expr_ref_tag = typecheck_graph.u32_buffer("type_expr_ref_tag")?;
        let type_expr_ref_payload = typecheck_graph.u32_buffer("type_expr_ref_payload")?;
        let type_instance_kind = typecheck_graph.u32_buffer("type_instance_kind")?;
        let type_decl_generic_param_count =
            typecheck_graph.u32_buffer("type_decl_generic_param_count")?;
        let type_decl_generic_param_count_by_owner_token =
            typecheck_graph.u32_buffer("type_decl_generic_param_count_by_owner_token")?;
        let type_decl_hir_node_by_token =
            typecheck_graph.u32_buffer("type_decl_hir_node_by_token")?;
        let type_generic_param_slot_by_token =
            typecheck_graph.u32_buffer("type_generic_param_slot_by_token")?;
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
        let type_instance_arg_start = typecheck_graph.u32_buffer("type_instance_arg_start")?;
        let type_instance_arg_count = typecheck_graph.u32_buffer("type_instance_arg_count")?;
        let type_instance_arg_ref_tag = typecheck_graph.u32_buffer("type_instance_arg_ref_tag")?;
        let type_instance_arg_ref_payload =
            typecheck_graph.u32_buffer("type_instance_arg_ref_payload")?;
        let type_instance_arg_row_start =
            typecheck_graph.u32_buffer("type_instance_arg_row_start")?;
        let type_instance_arg_row_count_out =
            typecheck_graph.u32_buffer("type_instance_arg_row_count_out")?;
        let type_instance_arg_row_ref_tag =
            typecheck_graph.u32_buffer("type_instance_arg_row_ref_tag")?;
        let type_instance_arg_row_ref_payload =
            typecheck_graph.u32_buffer("type_instance_arg_row_ref_payload")?;
        let type_semantic_buffers = Box::new(TypeSemanticBuffers {
            row_by_token: typecheck_graph.u32_buffer("type_semantic_row_by_token")?,
            scan_input: typecheck_graph.u32_buffer("type_semantic_scan_input")?,
            prefix: typecheck_graph.u32_buffer("type_semantic_prefix")?,
            count_out: typecheck_graph.u32_buffer("type_semantic_count_out")?,
            row_by_ordinal: typecheck_graph.u32_buffer("type_semantic_row_by_ordinal")?,
        });
        let aggregate_compare_count_out =
            typecheck_graph.u32_buffer("aggregate_compare_count_out")?;
        let aggregate_compare_dispatch_args =
            typecheck_graph.u32_buffer("aggregate_compare_dispatch_args")?;
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
            scan_input: typecheck_graph.u32_buffer("type_subtree_compare_scan_input")?,
            prefix: typecheck_graph.u32_buffer("type_subtree_compare_prefix")?,
            count_out: typecheck_graph.u32_buffer("type_subtree_compare_count_out")?,
            left_root: typecheck_graph.u32_buffer("type_subtree_compare_left_root")?,
            right_root: typecheck_graph.u32_buffer("type_subtree_compare_right_root")?,
            error_token: typecheck_graph.u32_buffer("type_subtree_compare_error_token")?,
            error_detail: typecheck_graph.u32_buffer("type_subtree_compare_error_detail")?,
            dispatch_args: typecheck_graph.u32_buffer("type_subtree_compare_dispatch_args")?,
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
        let type_instance_state = typecheck_graph.u32_buffer("type_instance_state")?;
        let predicate_capacity_u32 = predicate_capacity;
        let predicate_key_radix_n_blocks = predicate_capacity_u32.div_ceil(256).max(1);
        let predicate_syntax_token = typecheck_graph.u32_buffer("predicate_syntax_token")?;
        let fn_return_ref_tag = typecheck_graph.u32_buffer("fn_return_ref_tag")?;
        let fn_return_ref_payload = typecheck_graph.u32_buffer("fn_return_ref_payload")?;
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
        let method_token_dispatch_args =
            typecheck_graph.u32_buffer("method_token_dispatch_args")?;
        let method_hir_dispatch_args = typecheck_graph.u32_buffer("method_hir_dispatch_args")?;
        let method_compact_dispatch_args =
            typecheck_graph.u32_buffer("method_compact_dispatch_args")?;
        let method_token_hir_dispatch_args =
            typecheck_graph.u32_buffer("method_token_hir_dispatch_args")?;
        allocation_stamp!("buffers");
        let empty_hir = EmptyHirBindings::new(device, uses_hir_items, hir_node_capacity);
        let graph_bindings = typecheck_graph.bindings()?;
        let mut resources = ResourceMap::new();
        typecheck_graph.register_bindings(&graph_bindings, &mut resources);
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
        if let Some(hir_items) = hir_items {
            register_hir_item_resources(&mut resources, hir_items);
        } else {
            register_empty_hir_resources(&mut resources, &empty_hir, &hir_active_count);
        }
        resources.buffer("status", &self.status_buf);
        resources.buffer("visible_decl", &visible_decl);
        resources.buffer("visible_type", &visible_type);
        resources.buffer("hir_value_decl_name_present", &hir_value_decl_name_present);
        resources.buffer("module_type_path_type", &module_type_path_type);
        resources.buffer("module_type_path_status", &module_type_path_status);
        resources.buffer("module_value_path_status", &module_value_path_status);
        resources.buffer("call_dependency_decl", &call_dependency_decl);
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
        resources.buffer("type_instance_decl_token", &type_instance_decl_token);
        resources.buffer(
            "type_instance_external_canonical",
            &type_instance_external_canonical,
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
        resources.buffer("decl_type_ref_tag", &decl_type_ref_tag);
        resources.buffer("decl_type_ref_payload", &decl_type_ref_payload);
        allocation_stamp!("resources");
        let hir_active_dispatch = reflected_bind_group_from_resources(
            device,
            "type_check_resident_hir_active_dispatch_args",
            &passes.kernel("type_checker/hir_active_dispatch_args"),
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
        let name_bind_groups = create_name_bind_groups(
            passes,
            device,
            source_len,
            name_capacity,
            name_n_blocks,
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
                    hir_status_buf,
                    hir_kind_buf,
                    hir_token_pos_buf,
                    hir_token_end_buf,
                    status_buf: &self.status_buf,
                    hir_active_count_buf: &hir_active_count,
                    hir_active_dispatch_args: &hir_active_dispatch_args,
                    hir_items,
                    name_id_by_token: &name_id_by_token,
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
                    visible_decl: &visible_decl,
                    visible_type: &visible_type,
                    enclosing_fn: &enclosing_fn,
                    call_fn_index: &call_fn_index,
                    call_dependency_decl: &call_dependency_decl,
                    call_return_type: &call_return_type,
                    call_return_type_token: &call_return_type_token,
                    call_generic_slot_type: &call_generic_slot_type,
                    call_generic_slot_ordinal: &call_generic_slot_ordinal,
                    method_call_name_id: &method_call_name_id,
                    call_param_count: &call_param_count,
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
                    type_instance_arg_row_start: &type_instance_arg_row_start,
                    type_instance_arg_row_count_out: &type_instance_arg_row_count_out,
                    type_instance_arg_row_ref_tag: &type_instance_arg_row_ref_tag,
                    type_instance_arg_row_ref_payload: &type_instance_arg_row_ref_payload,
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
                &resources,
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
            &passes.kernel("type_checker/semantic/artifact/00_calls"),
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::SEMANTIC_CALLS_PROJECT_PASS,
            &resources,
        )?;
        let semantic_artifact_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.project",
            &passes.kernel("type_checker/semantic/artifact/00_project"),
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::SEMANTIC_ARTIFACT_PROJECT_PASS,
            &resources,
        )?;
        resources.buffer("compact_expr_scalar_type_out", &compact_expr_scalar_type_a);
        let compact_expr_scalar_type_init = reflected_bind_group_from_resources(
            device,
            "type_check.expression_types.init",
            &passes.kernel("type_checker/semantic/expression_types/00_init"),
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
                    &passes.kernel("type_checker/semantic/expression_types/01_step"),
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
            &passes.kernel("type_checker/semantic/artifact/01_expression_refs"),
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::SEMANTIC_EXPRESSION_REFS_PROJECT_PASS,
            &resources,
        )?;
        let semantic_struct_literal_refs_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.struct_literal_refs",
            &passes.kernel("type_checker/semantic/artifact/01a_struct_literal_refs"),
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::SEMANTIC_STRUCT_LITERAL_REFS_PROJECT_PASS,
            &resources,
        )?;
        let semantic_array_index_refs_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.array_index_refs",
            &passes.kernel("type_checker/semantic/artifact/01b_array_index_refs"),
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
            &passes.kernel("type_checker/conditions/compact_expr"),
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::CONDITIONS_COMPACT_EXPR_PASS,
            &resources,
        )?;
        let conditions_compact_stmt = reflected_bind_group_from_resources(
            device,
            "type_check.conditions.compact_stmt",
            &passes.kernel("type_checker/conditions/compact_stmt"),
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::CONDITIONS_COMPACT_STMT_PASS,
            &resources,
        )?;
        let conditions_compact_aggregate_requests = reflected_bind_group_from_resources(
            device,
            "type_check.conditions.compact_aggregate_requests",
            &passes.kernel("type_checker/conditions/compact_aggregate_requests"),
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::CONDITIONS_COMPACT_AGGREGATE_REQUESTS_PASS,
            &resources,
        )?;
        let conditions_compact_calls = resources.reflected_bind_group_with_overrides(
            device,
            "type_check.conditions.compact_calls",
            &passes.kernel("type_checker/conditions/compact_calls"),
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
            &passes.kernel("type_checker/conditions/compact_types"),
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::CONDITIONS_COMPACT_TYPES_PASS,
            &resources,
        )?;
        let conditions_compact_methods = reflected_bind_group_from_resources(
            device,
            "type_check.conditions.compact_methods",
            &passes.kernel("type_checker/conditions/compact_methods"),
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::CONDITIONS_COMPACT_METHODS_PASS,
            &resources,
        )?;
        let semantic_predicate_diagnostics_clear = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.predicate_diagnostics.clear",
            &passes.kernel("type_checker/semantic/artifact/00_predicate_diagnostics_clear"),
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::PREDICATE_DIAGNOSTICS_CLEAR_PASS,
            &resources,
        )?;
        let semantic_predicate_diagnostics_claim = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.predicate_diagnostics.claim",
            &passes.kernel("type_checker/semantic/artifact/01_predicate_diagnostics_claim"),
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::PREDICATE_DIAGNOSTICS_CLAIM_PASS,
            &resources,
        )?;
        let semantic_predicate_diagnostics_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.predicate_diagnostics",
            &passes.kernel("type_checker/semantic/artifact/02_predicate_diagnostics"),
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::PREDICATE_DIAGNOSTICS_PROJECT_PASS,
            &resources,
        )?;
        let conditions_compact_predicates = reflected_bind_group_from_resources(
            device,
            "type_check.conditions.compact_predicates",
            &passes.kernel("type_checker/conditions/compact_predicates"),
            &resources,
        )?;
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::CONDITIONS_COMPACT_PREDICATES_PASS,
            &resources,
        )?;
        let conditions_compact_names = bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.conditions.compact_names"),
            &passes.kernel("type_checker/conditions/compact_names"),
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
            passes,
            &resources,
            compiler_graph::AGGREGATE_SCAN_RESOURCES,
        )?;
        let aggregate_compare_dispatch = bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.conditions.aggregate_compare_dispatch"),
            &passes.kernel("type_checker/count/dispatch_args"),
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
            &passes.kernel("type_checker/conditions/aggregate_args"),
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
            passes,
            &resources,
            compiler_graph::TYPE_SUBTREE_SCAN_RESOURCES,
        )?);
        let type_subtree_compare_dispatch = Box::new(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.conditions.type_subtree_compare_dispatch"),
            &passes.kernel("type_checker/count/dispatch_args"),
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
            &passes.kernel("type_checker/conditions/type_subtree"),
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
        if let Some(buffer) = generic_param_key_order_tmp.as_ref() {
            resources.buffer("generic_param_key_order_tmp", buffer);
        }
        if let Some(buffer) = generic_param_slot_order_tmp.as_ref() {
            resources.buffer("generic_param_slot_order_tmp", buffer);
        }
        let mut generic_param_slot_radix_buffers = Vec::new();
        for name in [
            "generic_param_slot_radix_block_histogram",
            "generic_param_slot_radix_block_bucket_prefix",
            "generic_param_slot_radix_bucket_total",
            "generic_param_slot_radix_bucket_base",
        ] {
            if let Some(buffer) = typecheck_graph.optional_buffer::<u32>(name)? {
                generic_param_slot_radix_buffers.push((name, buffer));
            }
        }
        for (name, buffer) in &generic_param_slot_radix_buffers {
            resources.buffer(*name, buffer);
        }
        typecheck_graph.validate_registered_pass_bindings(
            compiler_graph::TYPE_INSTANCE_ARG_ROW_CLEAR_PASS,
            &resources,
        )?;
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
        let predicates = if module_path.is_some() {
            hir_items.expect("predicate collection requires HIR item buffers");
            Some(create_predicate_bind_groups(
                device,
                passes,
                token_capacity,
                predicate_capacity_u32,
                predicate_key_radix_n_blocks,
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
            &passes.kernel("type_checker/returns/00_clear"),
            &resources,
        )?;
        let returns_mark = reflected_bind_group_from_resources(
            device,
            "type_check_resident_returns_mark",
            &passes.kernel("type_checker/returns/01_mark"),
            &resources,
        )?;
        let returns_mark_if = reflected_bind_group_from_resources(
            device,
            "type_check_resident_returns_mark_if",
            &passes.kernel("type_checker/returns/02_mark_if"),
            &resources,
        )?;
        let returns_validate = reflected_bind_group_from_resources(
            device,
            "type_check_resident_returns_validate",
            &passes.kernel("type_checker/returns/03_validate"),
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
            &passes.kernel("type_checker/scope/hir"),
            &resources,
        )?;
        typecheck_graph
            .validate_registered_pass_bindings(compiler_graph::SCOPE_HIR_PASS, &resources)?;
        let if_depth_bind_groups = create_if_depth_bind_groups(
            passes,
            device,
            &resources,
            &if_depth_params,
            if_depth_n_blocks,
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
        let fn_context_bind_groups =
            create_fn_context_bind_groups(passes, device, &resources, &fn_params, fn_n_blocks)?;
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
            if_depth_n_blocks,
            fn_n_blocks,
            language_symbol_bytes,
            name_order_in,
            name_order_tmp,
            name_id_by_token,
            module_path,
            visible_decl,
            visible_type,
            token_active_dispatch_args,
            hir_active_dispatch_args,
            token_hir_active_dispatch_args,
            hir_active_dispatch,
            semantic_features,
            type_instance_decl_token,
            type_instance_external_canonical,
            type_subtree_compare_buffers,
            name_bind_groups,
            language_name_bind_groups,
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
