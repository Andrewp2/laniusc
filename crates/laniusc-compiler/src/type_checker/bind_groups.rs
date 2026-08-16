use super::*;

mod hir_resources;
mod module_path_resources;

use hir_resources::register_hir_resources;
use module_path_resources::register_module_path_resources;

impl GpuTypeChecker {
    /// Allocates or wires all resident buffers and bind groups for one cache key.
    #[allow(clippy::too_many_arguments)]
    pub(super) fn create_resident_workspace(
        &self,
        device: &wgpu::Device,
        allocation: ResidentTypeCheckCacheKey,
        token_buf: TrackedBufferView<'_>,
        token_count_buf: TrackedBufferView<'_>,
        token_file_id_buf: TrackedBufferView<'_>,
        source_buf: TrackedBufferView<'_>,
        hir_items: GpuTypeCheckHirItemBuffers<'_>,
        passes: &TypeCheckPasses,
        dependency_interfaces: Option<&GpuDependencyInterfaceState>,
    ) -> Result<ResidentTypeCheckWorkspace> {
        let source_len = allocation.source_byte_capacity;
        let source_file_capacity = allocation.source_file_capacity;
        let token_capacity = allocation.token_capacity;
        let hir_node_capacity = allocation.hir_node_capacity;
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
        if hir_node_capacity >= 0x0fff_ffff {
            anyhow::bail!(
                "compact HIR capacity {hir_node_capacity} exceeds scalar-type link encoding"
            );
        }
        let call_param_row_capacity = allocation.call_param_row_capacity;
        let call_arg_row_capacity = allocation.call_arg_row_capacity;
        let module_record_capacity = allocation.module_record_capacity;
        let parser_feature_flags = allocation.parser_feature_flags;
        let mut hir_items = hir_items;
        hir_items.call_param_row_capacity = call_param_row_capacity;
        hir_items.call_arg_row_capacity = call_arg_row_capacity;
        hir_items.module_record_capacity = module_record_capacity;
        hir_items.parser_feature_flags = parser_feature_flags;
        let call_generic_claim_capacity = generic_claim_capacity_for_job(
            token_capacity,
            parser_feature_flags,
            dependency_interfaces.is_some(),
        );
        let predicate_capacity =
            predicate_capacity_for_features(hir_node_capacity, parser_feature_flags);
        let dependency_capacity = compiler_graph::DependencyWorkspaceCapacity::for_job(
            token_capacity,
            dependency_interfaces,
        )?;
        // Preserve the complete dead frontend workspace across this phase.
        // `TypeCheckCompilerGraph` imports whichever ranges fit its own slots;
        // semantic lowering must still be able to reuse the remaining ranges.
        let upstream_workspace = hir_items
            .upstream_workspace
            .iter()
            .map(|buffer| buffer.alias::<u8>(buffer.byte_size as usize))
            .collect::<Vec<_>>();
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
            dependency_capacity,
            allocation.semantic_interface_required,
            passes,
            hir_items.upstream_workspace,
        )?;
        let compact_expr_scalar_type_a =
            typecheck_graph.u32_buffer("compact_expr_scalar_type.a")?;
        let visible_decl = typecheck_graph.u32_buffer("visible_decl")?;
        let visible_type = typecheck_graph.u32_buffer("visible_type")?;
        let module_type_path_type = typecheck_graph.u32_buffer("module_type_path_type")?;
        let module_type_path_status = typecheck_graph.u32_buffer("module_type_path_status")?;
        let module_value_path_status = typecheck_graph.u32_buffer("module_value_path_status")?;
        let module_value_path_expr_head =
            typecheck_graph.u32_buffer("module_value_path_expr_head")?;
        let module_value_path_call_head =
            typecheck_graph.u32_buffer("module_value_path_call_head")?;
        let module_value_path_call_open =
            typecheck_graph.u32_buffer("module_value_path_call_open")?;
        let module_value_path_call_path_id =
            typecheck_graph.u32_buffer("module_value_path_call_path_id")?;
        let module_value_path_call_leaf =
            typecheck_graph.u32_buffer("module_value_path_call_leaf")?;
        let module_value_path_associated_method_token =
            typecheck_graph.u32_buffer("module_value_path_associated_method_token")?;
        let module_value_path_associated_receiver_token =
            typecheck_graph.u32_buffer("module_value_path_associated_receiver_token")?;
        let module_value_path_const_head =
            typecheck_graph.u32_buffer("module_value_path_const_head")?;
        let module_value_path_const_end =
            typecheck_graph.u32_buffer("module_value_path_const_end")?;
        let name_capacity = token_capacity.saturating_add(LANGUAGE_SYMBOL_COUNT).max(1);
        let name_n_blocks = name_capacity.div_ceil(256).max(1);
        let hir_value_decl_name_present =
            typecheck_graph.u32_buffer("hir_value_decl_name_present")?;
        let hir_visible_decl_capacity = token_capacity.max(1);
        let hir_decl_record_n_blocks = hir_visible_decl_capacity.div_ceil(256).max(1);
        let hir_decl_tree_leaf_count = hir_visible_decl_capacity
            .div_ceil(HIR_VISIBLE_DECL_ROW_BLOCK_SIZE)
            .max(1);
        let hir_decl_tree_leaf_base = hir_decl_tree_leaf_count.next_power_of_two().max(1);
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
        let name_id_by_token = typecheck_graph.u32_buffer("name_id_by_token")?;
        let language_name_id = typecheck_graph.u32_buffer("language_name_id")?;
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
        let language_decl_name_id = typecheck_graph.u32_buffer("language_decl_name_id")?;
        let language_type_code_by_name_id =
            typecheck_graph.u32_buffer("language_type_code_by_name_id")?;
        let language_entrypoint_tag_by_name_id =
            typecheck_graph.u32_buffer("language_entrypoint_tag_by_name_id")?;
        let language_intrinsic_tag_by_name_id =
            typecheck_graph.u32_buffer("language_intrinsic_tag_by_name_id")?;
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
        let call_dependency_library_id =
            typecheck_graph.u32_buffer("call_dependency_library_id")?;
        let call_dependency_unit_id = typecheck_graph.u32_buffer("call_dependency_unit_id")?;
        let call_dependency_local_index =
            typecheck_graph.u32_buffer("call_dependency_local_index")?;
        let call_dependency_host_service =
            typecheck_graph.u32_buffer("call_dependency_host_service")?;
        let type_decl_generic_param_count_by_owner_token =
            typecheck_graph.u32_buffer("type_decl_generic_param_count_by_owner_token")?;
        // Local and imported named instances share this identity discriminator.
        // It must survive name-hash workspace reuse and be reset independently:
        // an imported canonical id and a stale local declaration token are
        // mutually exclusive representations of the same instance.
        let type_instance_decl_token = typecheck_graph.u32_buffer("type_instance_decl_token")?;
        let type_instance_aggregate_word_count =
            typecheck_graph.u32_buffer("type_instance_aggregate_word_count")?;
        let type_instance_arg_ref_tag = typecheck_graph.u32_buffer("type_instance_arg_ref_tag")?;
        let type_instance_arg_ref_payload =
            typecheck_graph.u32_buffer("type_instance_arg_ref_payload")?;
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
        // Declaration refs survive name/type-instance construction and feed
        // late semantic projection. They cannot alias radix rows that later
        // type-family sorts overwrite; the compiler graph may recolor them
        // only after that complete producer/consumer interval is registered.
        let decl_type_ref_tag = typecheck_graph.u32_buffer("decl_type_ref_tag")?;
        let decl_type_ref_payload = typecheck_graph.u32_buffer("decl_type_ref_payload")?;
        let token_active_dispatch_args =
            typecheck_graph.u32_buffer("token_active_dispatch_args")?;
        let hir_active_dispatch_args = typecheck_graph.u32_buffer("hir_active_dispatch_args")?;
        let token_hir_active_dispatch_args =
            typecheck_graph.u32_buffer("token_hir_active_dispatch_args")?;
        let hir_active_count = typecheck_graph.u32_buffer("hir_active_count")?;
        let method_token_dispatch_args =
            typecheck_graph.u32_buffer("method_token_dispatch_args")?;
        let method_hir_dispatch_args = typecheck_graph.u32_buffer("method_hir_dispatch_args")?;
        let method_compact_dispatch_args =
            typecheck_graph.u32_buffer("method_compact_dispatch_args")?;
        let method_token_hir_dispatch_args =
            typecheck_graph.u32_buffer("method_token_hir_dispatch_args")?;
        allocation_stamp!("buffers");
        let graph_bindings = typecheck_graph.bindings()?;
        let dependency_words_fallback = if dependency_interfaces.is_none() {
            Some(typecheck_graph.u32_buffer("external_type_library_id")?)
        } else {
            None
        };
        let mut resources = ResourceMap::new();
        typecheck_graph.register_bindings(&graph_bindings, &mut resources);
        resources.buffer("gParams", &self.params_buf);
        resources.buffer("token_words", token_buf);
        resources.buffer("token_count", token_count_buf);
        resources.buffer("token_file_id", token_file_id_buf);
        resources.buffer("source_bytes", source_buf);
        resources.buffer("token_active_dispatch_args", &token_active_dispatch_args);
        resources.buffer("hir_active_dispatch_args", &hir_active_dispatch_args);
        resources.buffer(
            "token_hir_active_dispatch_args",
            &token_hir_active_dispatch_args,
        );
        resources.buffer("hir_active_count", &hir_active_count);
        register_hir_resources(&mut resources, hir_items);
        resources.buffer("status", &self.status_buf);
        resources.buffer("visible_decl", &visible_decl);
        resources.buffer("visible_type", &visible_type);
        resources.buffer("hir_value_decl_name_present", &hir_value_decl_name_present);
        resources.buffer("module_type_path_type", &module_type_path_type);
        resources.buffer("module_type_path_status", &module_type_path_status);
        resources.buffer("module_value_path_expr_head", &module_value_path_expr_head);
        resources.buffer("module_value_path_call_head", &module_value_path_call_head);
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
        resources.buffer(
            "module_value_path_const_head",
            &module_value_path_const_head,
        );
        resources.buffer("module_value_path_const_end", &module_value_path_const_end);
        resources.buffer("module_value_path_status", &module_value_path_status);
        resources.buffer("call_dependency_library_id", &call_dependency_library_id);
        resources.buffer("call_dependency_unit_id", &call_dependency_unit_id);
        resources.buffer("call_dependency_local_index", &call_dependency_local_index);
        resources.buffer(
            "call_dependency_host_service",
            &call_dependency_host_service,
        );
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
            "type_instance_aggregate_word_count",
            &type_instance_aggregate_word_count,
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
        if let Some(dependencies) = dependency_interfaces {
            resources.buffer("dependency_words", &dependencies.words);
        } else if let Some(fallback) = &dependency_words_fallback {
            resources.buffer("dependency_words", fallback);
        }
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
        let language_name_bind_groups =
            create_language_name_bind_groups(device, passes, &resources)?;
        let name_bind_groups = create_name_bind_groups(
            passes,
            &typecheck_graph,
            device,
            source_len,
            name_capacity,
            name_n_blocks,
            &resources,
        )?;
        resources.validate_graph_passes([
            compiler_graph::LANGUAGE_NAMES_CLEAR_PASS,
            compiler_graph::LANGUAGE_TYPE_CODES_CLEAR_PASS,
            compiler_graph::LANGUAGE_DECLS_MATERIALIZE_PASS,
        ])?;
        for pass in [
            compiler_graph::NAMES_HASH_PREPARE_PASS,
            compiler_graph::NAMES_HASH_INSERT_PASS,
            compiler_graph::NAMES_HASH_ASSIGN_PASS,
        ] {
            resources.validate_graph_pass(pass, &[("name_count_in", "name_scan_total")])?;
        }
        allocation_stamp!("core_and_name_bind_groups");
        let module_path = create_module_path_state_with_passes(
            passes,
            &typecheck_graph,
            device,
            ModulePathCreateInputs {
                params: &self.params_buf,
                source_len,
                source_file_capacity,
                token_capacity,
                hir_node_capacity,
                hir_active_count_buf: &hir_active_count,
                hir_active_dispatch_args: &hir_active_dispatch_args,
                hir_items,
                decl_name_token: &decl_name_token,
                decl_id_by_name_token: &decl_id_by_name_token,
                decl_kind: &decl_kind,
                type_instance_arg_ref_tag: &type_instance_arg_ref_tag,
                type_instance_arg_ref_payload: &type_instance_arg_ref_payload,
                type_decl_generic_param_count_by_owner_token:
                    &type_decl_generic_param_count_by_owner_token,
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
                dependency_interfaces,
            },
            &resources,
        )?;
        allocation_stamp!("module_path");
        register_module_path_resources(&mut resources, &module_path)?;
        typecheck_graph.validate_module_pass_bindings(&resources)?;
        resources.validate_graph_pass(compiler_graph::MODULE_DECL_ROWS_MATERIALIZE_PASS, &[])?;
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
        let semantic_calls_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.calls",
            &passes.kernel("type_checker/semantic/artifact/00_calls"),
            &resources,
        )?;
        resources.validate_graph_pass(compiler_graph::SEMANTIC_CALLS_PROJECT_PASS, &[])?;
        resources.buffer("compact_expr_scalar_type_out", &compact_expr_scalar_type_a);
        let compact_expr_scalar_type_init = reflected_bind_group_from_resources(
            device,
            "type_check.expression_types.init",
            &passes.kernel("type_checker/semantic/expression_types/00_init"),
            &resources,
        )?;
        resources.validate_graph_pass(compiler_graph::INIT_PASS, &[])?;
        let compact_expr_scalar_type = compact_expr_scalar_type_a.clone();
        resources.buffer("compact_expr_scalar_type", &compact_expr_scalar_type);
        let semantic_artifact_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.project",
            &passes.kernel("type_checker/semantic/artifact/00_project"),
            &resources,
        )?;
        resources.validate_graph_pass(compiler_graph::SEMANTIC_ARTIFACT_PROJECT_PASS, &[])?;
        let semantic_local_const_literals_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.local_const_literals",
            &passes.kernel("type_checker/semantic/artifact/00a_local_const_literals"),
            &resources,
        )?;
        resources.validate_graph_pass(
            compiler_graph::SEMANTIC_LOCAL_CONST_LITERALS_PROJECT_PASS,
            &[],
        )?;
        let semantic_local_const_references_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.local_const_references",
            &passes.kernel("type_checker/semantic/artifact/00b_local_const_references"),
            &resources,
        )?;
        resources.validate_graph_pass(
            compiler_graph::SEMANTIC_LOCAL_CONST_REFERENCES_PROJECT_PASS,
            &[],
        )?;
        let semantic_expression_refs_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.expression_refs",
            &passes.kernel("type_checker/semantic/artifact/01_expression_refs"),
            &resources,
        )?;
        resources
            .validate_graph_pass(compiler_graph::SEMANTIC_EXPRESSION_REFS_PROJECT_PASS, &[])?;
        let semantic_struct_literal_refs_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.struct_literal_refs",
            &passes.kernel("type_checker/semantic/artifact/01a_struct_literal_refs"),
            &resources,
        )?;
        resources.validate_graph_pass(
            compiler_graph::SEMANTIC_STRUCT_LITERAL_REFS_PROJECT_PASS,
            &[],
        )?;
        let semantic_array_index_refs_project = reflected_bind_group_from_resources(
            device,
            "type_check.semantic_artifact.array_index_refs",
            &passes.kernel("type_checker/semantic/artifact/01b_array_index_refs"),
            &resources,
        )?;
        resources
            .validate_graph_pass(compiler_graph::SEMANTIC_ARRAY_INDEX_REFS_PROJECT_PASS, &[])?;
        let conditions_compact_expr = reflected_bind_group_from_resources(
            device,
            "type_check.conditions.compact_expr",
            &passes.kernel("type_checker/conditions/compact_expr"),
            &resources,
        )?;
        resources.validate_graph_pass(compiler_graph::CONDITIONS_COMPACT_EXPR_PASS, &[])?;
        let conditions_compact_stmt = reflected_bind_group_from_resources(
            device,
            "type_check.conditions.compact_stmt",
            &passes.kernel("type_checker/conditions/compact_stmt"),
            &resources,
        )?;
        resources.validate_graph_pass(compiler_graph::CONDITIONS_COMPACT_STMT_PASS, &[])?;
        let conditions_compact_aggregate_requests = reflected_bind_group_from_resources(
            device,
            "type_check.conditions.compact_aggregate_requests",
            &passes.kernel("type_checker/conditions/compact_aggregate_requests"),
            &resources,
        )?;
        resources.validate_graph_pass(
            compiler_graph::CONDITIONS_COMPACT_AGGREGATE_REQUESTS_PASS,
            &[],
        )?;
        let condition_finalization = ConditionFinalizationOperation::new(
            device,
            &typecheck_graph,
            &resources,
            passes,
            hir_node_capacity,
            &method_compact_dispatch_args,
        )?;
        let aggregate_compare_scan = PrefixScanOperation::from_resource_names(
            device,
            "type_check.conditions.aggregate_compare_scan",
            passes,
            &resources,
            compiler_graph::AGGREGATE_SCAN_RESOURCES,
        )?;
        let aggregate_compare_dispatch = resources.reflected_bind_group_with_overrides(
            device,
            "type_check.conditions.aggregate_compare_dispatch",
            &passes.kernel("type_checker/count/dispatch_args"),
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
        resources.validate_graph_passes([
            compiler_graph::CONDITIONS_AGGREGATE_ARGS_CALLS_PASS,
            compiler_graph::CONDITIONS_AGGREGATE_ARGS_FINAL_PASS,
        ])?;
        let type_subtree_compare_scan = Box::new(PrefixScanOperation::from_resource_names(
            device,
            "type_check.conditions.type_subtree_compare_scan",
            passes,
            &resources,
            compiler_graph::TYPE_SUBTREE_SCAN_RESOURCES,
        )?);
        let type_subtree_compare_dispatch = Box::new(
            resources.reflected_bind_group_with_overrides(
                device,
                "type_check.conditions.type_subtree_compare_dispatch",
                &passes.kernel("type_checker/count/dispatch_args"),
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
            )?,
        );
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
            call_arg_row_capacity,
            call_generic_claim_capacity,
        )?;
        resources.validate_graph_pass(compiler_graph::REQUIRED_GENERIC_DISPATCH_PASS, &[])?;
        resources.validate_graph_passes_if_present(
            [
                compiler_graph::AGGREGATE_CALL_SCAN_PASSES,
                compiler_graph::AGGREGATE_FINAL_SCAN_PASSES,
                compiler_graph::TYPE_SUBTREE_CALL_SCAN_PASSES,
                compiler_graph::TYPE_SUBTREE_FINAL_SCAN_PASSES,
            ]
            .into_iter()
            .flat_map(|passes| passes.names()),
        )?;
        allocation_stamp!("conditions_and_calls");
        resources.validate_graph_passes_if_present(compiler_graph::REGISTERED_VISIBLE_PASSES)?;
        resources.validate_graph_passes([
            compiler_graph::TYPE_INSTANCE_ARG_ROW_CLEAR_PASS,
            compiler_graph::TYPE_INSTANCES_MARK_GENERIC_PARAM_RECORDS_PASS,
        ])?;
        typecheck_graph.validate_registered_generic_param_bindings(&resources)?;
        let predicates = create_predicate_bind_groups(device, passes, &resources)?;
        resources.validate_graph_passes(compiler_graph::REGISTERED_PREDICATE_DIRECT_PASSES)?;
        resources.validate_graph_passes(compiler_graph::REGISTERED_PREDICATE_LOGICAL_PASSES)?;
        allocation_stamp!("predicates");
        if struct_init_passes_required(parser_feature_flags) {
            resources.validate_graph_passes([
                compiler_graph::TYPE_INSTANCES_STRUCT_INIT_CLEAR_PASS,
                compiler_graph::TYPE_INSTANCES_STRUCT_INIT_CONTEXTS_PASS,
                compiler_graph::TYPE_INSTANCES_STRUCT_INIT_FIELDS_PASS,
                compiler_graph::TYPE_INSTANCES_STRUCT_INIT_SUBSTITUTE_PASS,
            ])?;
        }
        if member_passes_required(parser_feature_flags) {
            resources.validate_graph_passes([
                compiler_graph::TYPE_INSTANCES_MEMBER_RECEIVERS_PASS,
                compiler_graph::TYPE_INSTANCES_MEMBER_RECEIVERS_AFTER_ARRAY_PASS,
                compiler_graph::TYPE_INSTANCES_MEMBER_RESULTS_PASS,
                compiler_graph::TYPE_INSTANCES_MEMBER_RESULTS_AFTER_ARRAY_PASS,
                compiler_graph::TYPE_INSTANCES_MEMBER_SUBSTITUTE_PASS,
                compiler_graph::TYPE_INSTANCES_MEMBER_SUBSTITUTE_AFTER_ARRAY_PASS,
            ])?;
        }
        let type_instances = create_type_instance_bind_groups(
            device,
            &typecheck_graph,
            passes,
            &resources,
            token_capacity,
        )?;
        allocation_stamp!("type_instances");
        resources.buffer("module_id_by_file_id", &module_path.module_id_by_file_id);
        resources.buffer("module_count_out", &module_path.module_count_out);
        let method_index = MethodIndex::new(
            device,
            &typecheck_graph,
            passes,
            &resources,
            &method_compact_dispatch_args,
        )?;
        let methods = create_method_bind_groups(
            device,
            &typecheck_graph,
            passes,
            &resources,
            method_index,
            &token_active_dispatch_args,
            &method_token_dispatch_args,
            &method_compact_dispatch_args,
            &method_hir_dispatch_args,
            &method_token_hir_dispatch_args,
        )?;
        allocation_stamp!("methods");

        let returns = ReturnValidationOperation::new(
            device,
            &typecheck_graph,
            &resources,
            passes,
            &hir_active_dispatch_args,
        )?;
        let scope_hir = reflected_bind_group_from_resources(
            device,
            "type_check_resident_scope_hir",
            &passes.kernel("type_checker/scope/hir"),
            &resources,
        )?;
        resources.validate_graph_pass(compiler_graph::SCOPE_HIR_PASS, &[])?;
        let if_depth_bind_groups = create_if_depth_bind_groups(
            passes,
            device,
            &resources,
            &if_depth_params,
            if_depth_n_blocks,
        )?;
        resources.validate_graph_passes([
            compiler_graph::IF_DEPTH_CLEAR_PASS,
            compiler_graph::IF_DEPTH_MARK_PASS,
            compiler_graph::IF_DEPTH_LOCAL_PASS,
            compiler_graph::IF_DEPTH_SCAN_PASS,
            compiler_graph::IF_DEPTH_APPLY_PASS,
        ])?;
        let fn_context_bind_groups =
            create_fn_context_bind_groups(passes, device, &resources, &fn_params, fn_n_blocks)?;
        resources.validate_graph_passes([
            compiler_graph::FN_CONTEXT_CLEAR_PASS,
            compiler_graph::FN_CONTEXT_MARK_PASS,
            compiler_graph::FN_CONTEXT_LOCAL_PASS,
            compiler_graph::FN_CONTEXT_SCAN_PASS,
            compiler_graph::FN_CONTEXT_APPLY_PASS,
        ])?;
        let visible_bind_groups = create_resident_visible_bind_groups(
            passes,
            &typecheck_graph,
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

        Ok(ResidentTypeCheckWorkspace {
            resettable_buffers: Vec::new(),
            upstream_workspace,
            cache_key: allocation,
            typecheck_graph,
            compact_expr_scalar_type_init,
            name_capacity,
            if_depth_n_blocks,
            fn_n_blocks,
            if_depth_params,
            fn_params,
            language_symbol_bytes,
            _language_name_id: language_name_id,
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
            _type_instance_aggregate_word_count: type_instance_aggregate_word_count,
            _call_dependency_library_id: call_dependency_library_id,
            _call_dependency_unit_id: call_dependency_unit_id,
            _call_dependency_local_index: call_dependency_local_index,
            _call_dependency_host_service: call_dependency_host_service,
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
            returns,
            conditions_compact_expr,
            conditions_compact_stmt,
            conditions_compact_aggregate_requests,
            condition_finalization,
            semantic_expression_refs_project,
            semantic_struct_literal_refs_project,
            semantic_array_index_refs_project,
            semantic_calls_project,
            semantic_artifact_project,
            semantic_local_const_literals_project,
            semantic_local_const_references_project,
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
