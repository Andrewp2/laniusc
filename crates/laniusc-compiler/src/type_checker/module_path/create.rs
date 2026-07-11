use super::{
    super::*,
    bind_helpers::{
        create_pair_max_dispatch,
        create_radix_bucket_bases,
        create_radix_bucket_prefix,
        create_radix_dispatch,
    },
    buffers::Buffers,
    inputs::CreateInputs,
    layout::Layout,
    module_index::{ModuleIndex, create_module_index},
    projection::{ProjectionBindGroups, create_projection_bind_groups},
    record_discovery::{RecordDiscovery, create_record_discovery},
    state::{BindGroups, State},
};

/// Creates the complete module/path state from loaded passes and typed inputs.
pub(in crate::type_checker) fn create_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    inputs: CreateInputs<'_>,
) -> Result<State> {
    let parser_hir_n_blocks = inputs.parser_hir_node_capacity.div_ceil(256).max(1);
    let layout = Layout::new(
        inputs.source_file_capacity,
        inputs.token_capacity,
        inputs.hir_node_capacity,
        inputs.hir_items.module_record_capacity,
        inputs.hir_items.parser_feature_flags,
    );
    let Layout {
        n_blocks,
        record_capacity_u32,
        record_n_blocks,
        module_capacity_u32,
        module_n_blocks,
        import_visible_capacity_u32,
        import_visible_n_blocks,
        ..
    } = layout;
    let buffers = Buffers::new(device, layout, &inputs);
    let RecordDiscovery {
        mark_records,
        extract_path_record_flag_params,
        extract_path_record_flag,
        extract_module_record_flag_params,
        extract_module_record_flag,
        extract_import_record_flag_params,
        extract_import_record_flag,
        extract_decl_record_flag_params,
        extract_decl_record_flag,
        path_scan,
        scatter_paths,
        path_dispatch_params,
        path_dispatch_args: path_dispatch_args_group,
        import_dispatch_params,
        import_dispatch_args: import_dispatch_args_group,
        count_path_segments,
        path_segment_scan,
        scatter_path_segments,
        module_scan,
        import_scan,
        decl_scan,
    } = create_record_discovery(passes, device, layout, &inputs, &buffers)?;
    let ModuleIndex {
        scatter_module_records,
        build_module_keys,
        module_key_radix_dispatch_params,
        module_key_radix_dispatch,
        sort_module_keys_small,
        sort_module_key_histogram,
        sort_module_key_bucket_prefix,
        sort_module_key_bucket_bases,
        sort_module_key_scatter,
        validate_modules,
        scatter_import_records,
        resolve_imports,
        seed_import_edge_key_order,
        import_edge_key_radix_dispatch,
        sort_import_edges_small,
        sort_import_edge_key_histogram,
        sort_import_edge_key_bucket_prefix,
        sort_import_edge_key_bucket_bases,
        sort_import_edge_key_scatter,
        validate_import_cycles,
        mut retained_key_params,
    } = create_module_index(passes, device, layout, &inputs, &buffers)?;
    let ProjectionBindGroups {
        clear_type_path_types,
        project_type_paths,
        validate_type_paths,
        project_type_aliases,
        project_type_instances,
        mark_value_call_paths,
        project_value_paths,
        consume_value_calls,
        mirror_value_call_leaf,
        consume_value_consts,
        consume_value_enum_units,
        consume_value_enum_calls,
        validate_value_enum_call_payloads,
        finalize_value_enum_calls,
        bind_match_patterns,
        type_match_payloads,
        type_match_exprs,
    } = create_projection_bind_groups(passes, device, &inputs, &buffers)?;
    let Buffers {
        record_family_bits,
        record_family_flag,
        module_record_flag,
        import_record_flag,
        decl_record_flag,
        path_record_flag,
        module_record_prefix,
        import_record_prefix,
        decl_record_prefix,
        record_scan_local_prefix,
        record_scan_block_sum,
        record_scan_prefix_a,
        record_scan_prefix_b,
        module_count_out,
        module_table_count_out,
        import_count_out,
        decl_count_out,
        module_file_id,
        module_path_id,
        module_owner_hir,
        module_status,
        module_key_segment_count,
        module_key_segment_base,
        module_key_segment_name_id,
        module_key_to_module_id,
        module_key_order_tmp,
        module_key_radix_dispatch_args,
        module_key_radix_block_histogram,
        module_key_radix_block_bucket_prefix,
        module_key_radix_bucket_total,
        module_key_radix_bucket_base,
        module_id_by_file_id,
        import_module_file_id,
        import_path_id,
        import_kind,
        import_owner_hir,
        import_module_id,
        import_target_module_id,
        import_status,
        import_edge_key_order,
        import_edge_key_order_tmp,
        import_edge_key_radix_dispatch_args,
        decl_module_file_id,
        decl_module_id,
        decl_name_token,
        decl_id_by_name_token,
        decl_name_id,
        decl_kind,
        decl_namespace,
        decl_visibility,
        decl_hir_node,
        decl_parent_type_decl,
        decl_token_start,
        decl_token_end,
        decl_key_to_decl_id,
        decl_key_order_tmp,
        decl_key_radix_dispatch_args,
        decl_key_radix_block_histogram,
        decl_key_radix_block_bucket_prefix,
        decl_key_radix_bucket_total,
        decl_key_radix_bucket_base,
        decl_status,
        decl_duplicate_of,
        decl_type_key_flag,
        decl_value_key_flag,
        decl_type_key_prefix,
        decl_value_key_prefix,
        decl_type_key_count_out,
        decl_value_key_count_out,
        decl_type_key_to_decl_id,
        decl_value_key_to_decl_id,
        import_visible_type_count,
        import_visible_value_count,
        import_visible_type_prefix,
        import_visible_value_prefix,
        import_visible_type_count_out,
        import_visible_value_count_out,
        import_visible_type_module_id,
        import_visible_type_name_id,
        import_visible_type_decl_id,
        import_visible_type_key_order,
        import_visible_type_key_order_tmp,
        import_visible_type_key_module_id,
        import_visible_type_key_name_id,
        import_visible_type_key_to_decl_id,
        import_visible_type_status,
        import_visible_type_duplicate_of,
        import_visible_type_key_radix_dispatch_args,
        import_visible_value_module_id,
        import_visible_value_name_id,
        import_visible_value_decl_id,
        import_visible_value_key_order,
        import_visible_value_key_order_tmp,
        import_visible_value_key_module_id,
        import_visible_value_key_name_id,
        import_visible_value_key_to_decl_id,
        import_visible_value_status,
        import_visible_value_duplicate_of,
        import_visible_value_key_radix_dispatch_args,
        import_visible_validate_dispatch_args,
        import_visible_key_radix_block_histogram,
        import_visible_key_radix_block_bucket_prefix,
        import_visible_key_radix_bucket_total,
        import_visible_key_radix_bucket_base,
        resolved_type_decl,
        resolved_value_decl,
        resolved_type_status,
        resolved_value_status,
        path_record_prefix,
        path_scan_local_prefix,
        path_scan_block_sum,
        path_scan_prefix_a,
        path_scan_prefix_b,
        path_start,
        path_len,
        path_segment_count,
        path_segment_base,
        path_segment_name_id,
        path_segment_token,
        path_segment_count_out,
        path_owner_hir,
        path_owner_token,
        path_id_by_owner_hir,
        path_id_by_owner_token,
        path_owner_module_id,
        path_kind,
        path_count_out,
        path_dispatch_args,
        import_dispatch_args,
        scan_steps,
        record_scan_steps,
    } = buffers;
    let CreateInputs {
        params,
        token_capacity,
        hir_node_capacity,
        hir_token_pos_buf,
        hir_token_end_buf,
        status_buf,
        hir_active_count_buf: _,
        hir_items,
        name_id_by_token,
        ..
    } = inputs;

    let decl_module_params = uniform_from_val(
        device,
        "type_check.modules.decl_module.params",
        &ModuleKeyRadixParams {
            module_capacity: record_capacity_u32,
            reserved: module_capacity_u32,
            n_blocks,
            key_step: 0,
        },
    );
    let clear_file_module_map = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_05b_clear_file_module_map"),
        &passes.modules_clear_file_module_map,
        0,
        &[
            ("gParams", decl_module_params.as_entire_binding()),
            ("decl_count_out", decl_count_out.as_entire_binding()),
            ("import_count_out", import_count_out.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            (
                "module_id_by_file_id",
                module_id_by_file_id.as_entire_binding(),
            ),
            ("decl_module_id", decl_module_id.as_entire_binding()),
            ("import_module_id", import_module_id.as_entire_binding()),
            (
                "path_owner_module_id",
                path_owner_module_id.as_entire_binding(),
            ),
            ("status", status_buf.as_entire_binding()),
        ],
    )?;

    let build_file_module_map_params = uniform_from_val(
        device,
        "type_check.modules.file_module_map.params",
        &ModuleKeyRadixParams {
            module_capacity: module_capacity_u32,
            reserved: module_capacity_u32,
            n_blocks: module_n_blocks,
            key_step: 0,
        },
    );
    let build_file_module_map = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_05c_build_file_module_map"),
        &passes.modules_build_file_module_map,
        0,
        &[
            ("gParams", build_file_module_map_params.as_entire_binding()),
            (
                "module_table_count_out",
                module_table_count_out.as_entire_binding(),
            ),
            ("module_file_id", module_file_id.as_entire_binding()),
            (
                "module_id_by_file_id",
                module_id_by_file_id.as_entire_binding(),
            ),
        ],
    )?;

    let attach_record_modules_params = uniform_from_val(
        device,
        "type_check.modules.attach_record_modules.params",
        &ModuleKeyRadixParams {
            module_capacity: record_capacity_u32,
            reserved: module_capacity_u32,
            n_blocks: hir_node_capacity,
            key_step: 0,
        },
    );
    let attach_record_modules = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_05d_attach_record_modules"),
        &passes.modules_attach_record_modules,
        0,
        &[
            ("gParams", attach_record_modules_params.as_entire_binding()),
            ("decl_count_out", decl_count_out.as_entire_binding()),
            (
                "decl_module_file_id",
                decl_module_file_id.as_entire_binding(),
            ),
            ("import_count_out", import_count_out.as_entire_binding()),
            (
                "import_module_file_id",
                import_module_file_id.as_entire_binding(),
            ),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_owner_hir", path_owner_hir.as_entire_binding()),
            ("hir_item_file_id", hir_items.file_id.as_entire_binding()),
            ("module_count_out", module_count_out.as_entire_binding()),
            (
                "module_id_by_file_id",
                module_id_by_file_id.as_entire_binding(),
            ),
            ("decl_module_id", decl_module_id.as_entire_binding()),
            ("import_module_id", import_module_id.as_entire_binding()),
            (
                "path_owner_module_id",
                path_owner_module_id.as_entire_binding(),
            ),
        ],
    )?;

    let seed_decl_key_order = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_06a_seed_decl_key_order"),
        &passes.modules_seed_decl_key_order,
        0,
        &[
            ("gParams", decl_module_params.as_entire_binding()),
            ("decl_count_out", decl_count_out.as_entire_binding()),
            (
                "decl_key_to_decl_id",
                decl_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_status", decl_status.as_entire_binding()),
            ("decl_duplicate_of", decl_duplicate_of.as_entire_binding()),
        ],
    )?;

    let decl_key_radix_dispatch_params = uniform_from_val(
        device,
        "type_check.modules.decl_key_radix.dispatch_params",
        &ModuleKeyRadixParams {
            module_capacity: record_capacity_u32,
            reserved: 0,
            n_blocks,
            key_step: 0,
        },
    );
    let decl_key_radix_dispatch = create_radix_dispatch(
        device,
        &passes.names_radix_dispatch_args,
        "type_check.modules.decl_key_radix_dispatch",
        &decl_key_radix_dispatch_params,
        &decl_count_out,
        &decl_key_radix_dispatch_args,
    )?;

    let sort_decl_keys_small = if record_capacity_u32 <= MODULE_RELATION_SMALL_SORT_CAPACITY {
        Some(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_06a2_sort_decl_keys_small"),
            &passes.modules_sort_decl_keys_small,
            0,
            &[
                (
                    "gParams",
                    decl_key_radix_dispatch_params.as_entire_binding(),
                ),
                ("decl_count_out", decl_count_out.as_entire_binding()),
                ("decl_module_id", decl_module_id.as_entire_binding()),
                ("decl_namespace", decl_namespace.as_entire_binding()),
                ("decl_name_id", decl_name_id.as_entire_binding()),
                ("decl_key_order", decl_key_to_decl_id.as_entire_binding()),
            ],
        )?)
    } else {
        None
    };

    let mut sort_decl_key_histogram = Vec::with_capacity(DECL_KEY_RADIX_STEPS as usize);
    let mut sort_decl_key_bucket_prefix = Vec::with_capacity(DECL_KEY_RADIX_STEPS as usize);
    let mut sort_decl_key_bucket_bases = Vec::with_capacity(DECL_KEY_RADIX_STEPS as usize);
    let mut sort_decl_key_scatter = Vec::with_capacity(DECL_KEY_RADIX_STEPS as usize);
    for key_step in 0..DECL_KEY_RADIX_STEPS {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.modules.decl_key_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: record_capacity_u32,
                reserved: 0,
                n_blocks: record_n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            &decl_key_to_decl_id
        } else {
            &decl_key_order_tmp
        };
        let write_order = if key_step % 2 == 0 {
            &decl_key_order_tmp
        } else {
            &decl_key_to_decl_id
        };

        sort_decl_key_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_06_sort_decl_keys"),
            &passes.modules_sort_decl_keys,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("decl_count_out", decl_count_out.as_entire_binding()),
                ("decl_module_id", decl_module_id.as_entire_binding()),
                ("decl_namespace", decl_namespace.as_entire_binding()),
                ("decl_name_id", decl_name_id.as_entire_binding()),
                ("decl_key_order_in", read_order.as_entire_binding()),
                (
                    "radix_block_histogram",
                    decl_key_radix_block_histogram.as_entire_binding(),
                ),
            ],
        )?);

        sort_decl_key_bucket_prefix.push(create_radix_bucket_prefix(
            device,
            &passes.names_radix_bucket_prefix,
            "type_check_modules.decl_key_radix_bucket_prefix",
            &step_params,
            &decl_count_out,
            &decl_key_radix_block_histogram,
            &decl_key_radix_block_bucket_prefix,
            &decl_key_radix_bucket_total,
        )?);

        sort_decl_key_bucket_bases.push(create_radix_bucket_bases(
            device,
            &passes.names_radix_bucket_bases,
            "type_check_modules.decl_key_radix_bucket_bases",
            &step_params,
            &decl_key_radix_bucket_total,
            &decl_key_radix_bucket_base,
        )?);

        sort_decl_key_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_06b_sort_decl_keys_scatter"),
            &passes.modules_sort_decl_keys_scatter,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("decl_count_out", decl_count_out.as_entire_binding()),
                ("decl_module_id", decl_module_id.as_entire_binding()),
                ("decl_namespace", decl_namespace.as_entire_binding()),
                ("decl_name_id", decl_name_id.as_entire_binding()),
                ("decl_key_order_in", read_order.as_entire_binding()),
                (
                    "radix_bucket_base",
                    decl_key_radix_bucket_base.as_entire_binding(),
                ),
                (
                    "radix_block_bucket_prefix",
                    decl_key_radix_block_bucket_prefix.as_entire_binding(),
                ),
                ("decl_key_order_out", write_order.as_entire_binding()),
            ],
        )?);

        retained_key_params.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

    let validate_decl_params = uniform_from_val(
        device,
        "type_check.modules.decl_key_radix.params.validate",
        &ModuleKeyRadixParams {
            module_capacity: record_capacity_u32,
            reserved: module_capacity_u32,
            n_blocks: record_n_blocks,
            key_step: 0,
        },
    );
    let validate_decls = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_07_validate_decls"),
        &passes.modules_validate_decls,
        0,
        &[
            ("gParams", validate_decl_params.as_entire_binding()),
            ("decl_count_out", decl_count_out.as_entire_binding()),
            (
                "sorted_decl_key_order",
                decl_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_module_id", decl_module_id.as_entire_binding()),
            ("decl_namespace", decl_namespace.as_entire_binding()),
            ("decl_name_id", decl_name_id.as_entire_binding()),
            ("decl_token_start", decl_token_start.as_entire_binding()),
            ("decl_status", decl_status.as_entire_binding()),
            ("decl_duplicate_of", decl_duplicate_of.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
        ],
    )?;

    let mark_decl_namespace_keys = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_08_mark_decl_namespace_keys"),
        &passes.modules_mark_decl_namespace_keys,
        0,
        &[
            ("gParams", validate_decl_params.as_entire_binding()),
            ("decl_count_out", decl_count_out.as_entire_binding()),
            (
                "sorted_decl_key_order",
                decl_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_namespace", decl_namespace.as_entire_binding()),
            ("decl_status", decl_status.as_entire_binding()),
            ("decl_type_key_flag", decl_type_key_flag.as_entire_binding()),
            (
                "decl_value_key_flag",
                decl_value_key_flag.as_entire_binding(),
            ),
        ],
    )?;

    let decl_type_key_scan = create_counted_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.decl_type_keys",
        &record_scan_steps,
        &decl_count_out,
        &decl_type_key_flag,
        &decl_type_key_prefix,
        &decl_type_key_count_out,
        &record_scan_local_prefix,
        &record_scan_block_sum,
        &record_scan_prefix_a,
        &record_scan_prefix_b,
    )?;
    let decl_value_key_scan = create_counted_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.decl_value_keys",
        &record_scan_steps,
        &decl_count_out,
        &decl_value_key_flag,
        &decl_value_key_prefix,
        &decl_value_key_count_out,
        &record_scan_local_prefix,
        &record_scan_block_sum,
        &record_scan_prefix_a,
        &record_scan_prefix_b,
    )?;

    let scatter_decl_namespace_keys = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_08b_scatter_decl_namespace_keys"),
        &passes.modules_scatter_decl_namespace_keys,
        0,
        &[
            ("gParams", validate_decl_params.as_entire_binding()),
            ("decl_count_out", decl_count_out.as_entire_binding()),
            (
                "sorted_decl_key_order",
                decl_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_type_key_flag", decl_type_key_flag.as_entire_binding()),
            (
                "decl_type_key_prefix",
                decl_type_key_prefix.as_entire_binding(),
            ),
            (
                "decl_value_key_flag",
                decl_value_key_flag.as_entire_binding(),
            ),
            (
                "decl_value_key_prefix",
                decl_value_key_prefix.as_entire_binding(),
            ),
            (
                "decl_type_key_to_decl_id",
                decl_type_key_to_decl_id.as_entire_binding(),
            ),
            (
                "decl_value_key_to_decl_id",
                decl_value_key_to_decl_id.as_entire_binding(),
            ),
        ],
    )?;

    let mark_public_decl_keys = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_08c_mark_public_decl_keys"),
        &passes.modules_mark_public_decl_keys,
        0,
        &[
            ("gParams", validate_decl_params.as_entire_binding()),
            (
                "decl_type_key_count_out",
                decl_type_key_count_out.as_entire_binding(),
            ),
            (
                "decl_value_key_count_out",
                decl_value_key_count_out.as_entire_binding(),
            ),
            (
                "decl_type_key_to_decl_id",
                decl_type_key_to_decl_id.as_entire_binding(),
            ),
            (
                "decl_value_key_to_decl_id",
                decl_value_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_visibility", decl_visibility.as_entire_binding()),
            (
                "decl_type_public_flag",
                decl_type_key_flag.as_entire_binding(),
            ),
            (
                "decl_value_public_flag",
                decl_value_key_flag.as_entire_binding(),
            ),
        ],
    )?;

    // Declaration validation status/duplicate buffers are dead once
    // namespace flags have been marked. Reuse them for public declaration
    // prefixes so the compact type/value lookup prefix buffers remain intact.
    let decl_type_public_prefix =
        typed_alias_storage_u32(&decl_status, record_capacity_u32 as usize);
    let decl_value_public_prefix =
        typed_alias_storage_u32(&decl_duplicate_of, record_capacity_u32 as usize);

    let decl_type_public_scan = create_counted_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.decl_type_public_keys",
        &record_scan_steps,
        &decl_type_key_count_out,
        &decl_type_key_flag,
        &decl_type_public_prefix,
        &import_visible_type_count_out,
        &record_scan_local_prefix,
        &record_scan_block_sum,
        &record_scan_prefix_a,
        &record_scan_prefix_b,
    )?;
    let decl_value_public_scan = create_counted_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.decl_value_public_keys",
        &record_scan_steps,
        &decl_value_key_count_out,
        &decl_value_key_flag,
        &decl_value_public_prefix,
        &import_visible_value_count_out,
        &record_scan_local_prefix,
        &record_scan_block_sum,
        &record_scan_prefix_a,
        &record_scan_prefix_b,
    )?;

    let import_visibility_params = uniform_from_val(
        device,
        "type_check.modules.import_visibility.params",
        &ModuleKeyRadixParams {
            module_capacity: record_capacity_u32,
            reserved: import_visible_capacity_u32,
            n_blocks,
            key_step: 0,
        },
    );
    let count_import_visibility = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_09_count_import_visibility"),
        &passes.modules_count_import_visibility,
        0,
        &[
            ("gParams", import_visibility_params.as_entire_binding()),
            ("import_count_out", import_count_out.as_entire_binding()),
            ("import_status", import_status.as_entire_binding()),
            ("import_module_id", import_module_id.as_entire_binding()),
            (
                "import_target_module_id",
                import_target_module_id.as_entire_binding(),
            ),
            (
                "decl_type_key_count_out",
                decl_type_key_count_out.as_entire_binding(),
            ),
            (
                "decl_value_key_count_out",
                decl_value_key_count_out.as_entire_binding(),
            ),
            (
                "decl_type_key_to_decl_id",
                decl_type_key_to_decl_id.as_entire_binding(),
            ),
            (
                "decl_value_key_to_decl_id",
                decl_value_key_to_decl_id.as_entire_binding(),
            ),
            (
                "decl_type_public_flag",
                decl_type_key_flag.as_entire_binding(),
            ),
            (
                "decl_value_public_flag",
                decl_value_key_flag.as_entire_binding(),
            ),
            (
                "decl_type_public_prefix",
                decl_type_public_prefix.as_entire_binding(),
            ),
            (
                "decl_value_public_prefix",
                decl_value_public_prefix.as_entire_binding(),
            ),
            ("decl_module_id", decl_module_id.as_entire_binding()),
            (
                "import_visible_type_count",
                import_visible_type_count.as_entire_binding(),
            ),
            (
                "import_visible_value_count",
                import_visible_value_count.as_entire_binding(),
            ),
        ],
    )?;

    let import_visible_type_scan = create_counted_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.import_visible_type",
        &record_scan_steps,
        &import_count_out,
        &import_visible_type_count,
        &import_visible_type_prefix,
        &import_visible_type_count_out,
        &record_scan_local_prefix,
        &record_scan_block_sum,
        &record_scan_prefix_a,
        &record_scan_prefix_b,
    )?;
    let import_visible_value_scan = create_counted_u32_scan_bind_groups_with_passes(
        passes,
        device,
        "type_check_modules.import_visible_value",
        &record_scan_steps,
        &import_count_out,
        &import_visible_value_count,
        &import_visible_value_prefix,
        &import_visible_value_count_out,
        &record_scan_local_prefix,
        &record_scan_block_sum,
        &record_scan_prefix_a,
        &record_scan_prefix_b,
    )?;

    let scatter_import_visible_type = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_09b_scatter_import_visibility.type"),
        &passes.modules_scatter_import_visibility,
        0,
        &[
            ("gParams", import_visibility_params.as_entire_binding()),
            ("import_count_out", import_count_out.as_entire_binding()),
            ("import_status", import_status.as_entire_binding()),
            ("import_module_id", import_module_id.as_entire_binding()),
            (
                "import_target_module_id",
                import_target_module_id.as_entire_binding(),
            ),
            (
                "import_visible_count",
                import_visible_type_count.as_entire_binding(),
            ),
            (
                "import_visible_count_out",
                import_visible_type_count_out.as_entire_binding(),
            ),
            (
                "import_visible_prefix",
                import_visible_type_prefix.as_entire_binding(),
            ),
            (
                "decl_key_count_out",
                decl_type_key_count_out.as_entire_binding(),
            ),
            (
                "decl_key_to_decl_id",
                decl_type_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_public_flag", decl_type_key_flag.as_entire_binding()),
            (
                "decl_public_prefix",
                decl_type_public_prefix.as_entire_binding(),
            ),
            ("decl_module_id", decl_module_id.as_entire_binding()),
            ("decl_name_id", decl_name_id.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
            (
                "import_visible_module_id",
                import_visible_type_module_id.as_entire_binding(),
            ),
            (
                "import_visible_name_id",
                import_visible_type_name_id.as_entire_binding(),
            ),
            (
                "import_visible_decl_id",
                import_visible_type_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_key_order",
                import_visible_type_key_order.as_entire_binding(),
            ),
        ],
    )?;

    let scatter_import_visible_value = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_09b_scatter_import_visibility.value"),
        &passes.modules_scatter_import_visibility,
        0,
        &[
            ("gParams", import_visibility_params.as_entire_binding()),
            ("import_count_out", import_count_out.as_entire_binding()),
            ("import_status", import_status.as_entire_binding()),
            ("import_module_id", import_module_id.as_entire_binding()),
            (
                "import_target_module_id",
                import_target_module_id.as_entire_binding(),
            ),
            (
                "import_visible_count",
                import_visible_value_count.as_entire_binding(),
            ),
            (
                "import_visible_count_out",
                import_visible_value_count_out.as_entire_binding(),
            ),
            (
                "import_visible_prefix",
                import_visible_value_prefix.as_entire_binding(),
            ),
            (
                "decl_key_count_out",
                decl_value_key_count_out.as_entire_binding(),
            ),
            (
                "decl_key_to_decl_id",
                decl_value_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_public_flag", decl_value_key_flag.as_entire_binding()),
            (
                "decl_public_prefix",
                decl_value_public_prefix.as_entire_binding(),
            ),
            ("decl_module_id", decl_module_id.as_entire_binding()),
            ("decl_name_id", decl_name_id.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
            (
                "import_visible_module_id",
                import_visible_value_module_id.as_entire_binding(),
            ),
            (
                "import_visible_name_id",
                import_visible_value_name_id.as_entire_binding(),
            ),
            (
                "import_visible_decl_id",
                import_visible_value_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_key_order",
                import_visible_value_key_order.as_entire_binding(),
            ),
        ],
    )?;

    let import_visible_type_key_radix_dispatch_params = uniform_from_val(
        device,
        "type_check.modules.import_visible_type_key_radix.dispatch_params",
        &ModuleKeyRadixParams {
            module_capacity: import_visible_capacity_u32,
            reserved: 0,
            n_blocks: import_visible_n_blocks,
            key_step: 0,
        },
    );
    let import_visible_type_key_radix_dispatch = create_radix_dispatch(
        device,
        &passes.names_radix_dispatch_args,
        "type_check.modules.import_visible_type_key_radix_dispatch",
        &import_visible_type_key_radix_dispatch_params,
        &import_visible_type_count_out,
        &import_visible_type_key_radix_dispatch_args,
    )?;

    let sort_import_visible_type_keys_small =
        if import_visible_capacity_u32 <= MODULE_RELATION_SMALL_SORT_CAPACITY {
            Some(bind_group::create_bind_group_from_bindings(
                device,
                Some("type_check_modules_09b2_sort_import_visible_type_keys_small"),
                &passes.modules_sort_import_visible_keys_small,
                0,
                &[
                    (
                        "gParams",
                        import_visible_type_key_radix_dispatch_params.as_entire_binding(),
                    ),
                    (
                        "import_visible_count_out",
                        import_visible_type_count_out.as_entire_binding(),
                    ),
                    (
                        "import_visible_module_id",
                        import_visible_type_module_id.as_entire_binding(),
                    ),
                    (
                        "import_visible_name_id",
                        import_visible_type_name_id.as_entire_binding(),
                    ),
                    (
                        "import_visible_key_order",
                        import_visible_type_key_order.as_entire_binding(),
                    ),
                ],
            )?)
        } else {
            None
        };

    let mut sort_import_visible_type_key_histogram =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    let mut sort_import_visible_type_key_bucket_prefix =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    let mut sort_import_visible_type_key_bucket_bases =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    let mut sort_import_visible_type_key_scatter =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    for key_step in 0..IMPORT_VISIBLE_KEY_RADIX_STEPS {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.modules.import_visible_type_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: import_visible_capacity_u32,
                reserved: 0,
                n_blocks: import_visible_n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            &import_visible_type_key_order
        } else {
            &import_visible_type_key_order_tmp
        };
        let write_order = if key_step % 2 == 0 {
            &import_visible_type_key_order_tmp
        } else {
            &import_visible_type_key_order
        };
        sort_import_visible_type_key_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_09c_sort_import_visible_keys"),
            &passes.modules_sort_import_visible_keys,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "import_visible_count_out",
                    import_visible_type_count_out.as_entire_binding(),
                ),
                (
                    "import_visible_module_id",
                    import_visible_type_module_id.as_entire_binding(),
                ),
                (
                    "import_visible_name_id",
                    import_visible_type_name_id.as_entire_binding(),
                ),
                (
                    "import_visible_key_order_in",
                    read_order.as_entire_binding(),
                ),
                (
                    "radix_block_histogram",
                    import_visible_key_radix_block_histogram.as_entire_binding(),
                ),
            ],
        )?);
        sort_import_visible_type_key_bucket_prefix.push(create_radix_bucket_prefix(
            device,
            &passes.names_radix_bucket_prefix,
            "type_check_modules.import_visible_type_bucket_prefix",
            &step_params,
            &import_visible_type_count_out,
            &import_visible_key_radix_block_histogram,
            &import_visible_key_radix_block_bucket_prefix,
            &import_visible_key_radix_bucket_total,
        )?);
        sort_import_visible_type_key_bucket_bases.push(create_radix_bucket_bases(
            device,
            &passes.names_radix_bucket_bases,
            "type_check_modules.import_visible_type_bucket_bases",
            &step_params,
            &import_visible_key_radix_bucket_total,
            &import_visible_key_radix_bucket_base,
        )?);
        sort_import_visible_type_key_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_09d_sort_import_visible_keys_scatter"),
            &passes.modules_sort_import_visible_keys_scatter,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "import_visible_count_out",
                    import_visible_type_count_out.as_entire_binding(),
                ),
                (
                    "import_visible_module_id",
                    import_visible_type_module_id.as_entire_binding(),
                ),
                (
                    "import_visible_name_id",
                    import_visible_type_name_id.as_entire_binding(),
                ),
                (
                    "import_visible_key_order_in",
                    read_order.as_entire_binding(),
                ),
                (
                    "radix_bucket_base",
                    import_visible_key_radix_bucket_base.as_entire_binding(),
                ),
                (
                    "radix_block_bucket_prefix",
                    import_visible_key_radix_block_bucket_prefix.as_entire_binding(),
                ),
                (
                    "import_visible_key_order_out",
                    write_order.as_entire_binding(),
                ),
            ],
        )?);
        retained_key_params.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

    let import_visible_value_key_radix_dispatch_params = uniform_from_val(
        device,
        "type_check.modules.import_visible_value_key_radix.dispatch_params",
        &ModuleKeyRadixParams {
            module_capacity: import_visible_capacity_u32,
            reserved: 0,
            n_blocks: import_visible_n_blocks,
            key_step: 0,
        },
    );
    let import_visible_value_key_radix_dispatch = create_radix_dispatch(
        device,
        &passes.names_radix_dispatch_args,
        "type_check.modules.import_visible_value_key_radix_dispatch",
        &import_visible_value_key_radix_dispatch_params,
        &import_visible_value_count_out,
        &import_visible_value_key_radix_dispatch_args,
    )?;

    let sort_import_visible_value_keys_small =
        if import_visible_capacity_u32 <= MODULE_RELATION_SMALL_SORT_CAPACITY {
            Some(bind_group::create_bind_group_from_bindings(
                device,
                Some("type_check_modules_09b2_sort_import_visible_value_keys_small"),
                &passes.modules_sort_import_visible_keys_small,
                0,
                &[
                    (
                        "gParams",
                        import_visible_value_key_radix_dispatch_params.as_entire_binding(),
                    ),
                    (
                        "import_visible_count_out",
                        import_visible_value_count_out.as_entire_binding(),
                    ),
                    (
                        "import_visible_module_id",
                        import_visible_value_module_id.as_entire_binding(),
                    ),
                    (
                        "import_visible_name_id",
                        import_visible_value_name_id.as_entire_binding(),
                    ),
                    (
                        "import_visible_key_order",
                        import_visible_value_key_order.as_entire_binding(),
                    ),
                ],
            )?)
        } else {
            None
        };

    let mut sort_import_visible_value_key_histogram =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    let mut sort_import_visible_value_key_bucket_prefix =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    let mut sort_import_visible_value_key_bucket_bases =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    let mut sort_import_visible_value_key_scatter =
        Vec::with_capacity(IMPORT_VISIBLE_KEY_RADIX_STEPS as usize);
    for key_step in 0..IMPORT_VISIBLE_KEY_RADIX_STEPS {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.modules.import_visible_value_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: import_visible_capacity_u32,
                reserved: 0,
                n_blocks: import_visible_n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            &import_visible_value_key_order
        } else {
            &import_visible_value_key_order_tmp
        };
        let write_order = if key_step % 2 == 0 {
            &import_visible_value_key_order_tmp
        } else {
            &import_visible_value_key_order
        };
        sort_import_visible_value_key_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_09c_sort_import_visible_keys"),
            &passes.modules_sort_import_visible_keys,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "import_visible_count_out",
                    import_visible_value_count_out.as_entire_binding(),
                ),
                (
                    "import_visible_module_id",
                    import_visible_value_module_id.as_entire_binding(),
                ),
                (
                    "import_visible_name_id",
                    import_visible_value_name_id.as_entire_binding(),
                ),
                (
                    "import_visible_key_order_in",
                    read_order.as_entire_binding(),
                ),
                (
                    "radix_block_histogram",
                    import_visible_key_radix_block_histogram.as_entire_binding(),
                ),
            ],
        )?);
        sort_import_visible_value_key_bucket_prefix.push(create_radix_bucket_prefix(
            device,
            &passes.names_radix_bucket_prefix,
            "type_check_modules.import_visible_value_bucket_prefix",
            &step_params,
            &import_visible_value_count_out,
            &import_visible_key_radix_block_histogram,
            &import_visible_key_radix_block_bucket_prefix,
            &import_visible_key_radix_bucket_total,
        )?);
        sort_import_visible_value_key_bucket_bases.push(create_radix_bucket_bases(
            device,
            &passes.names_radix_bucket_bases,
            "type_check_modules.import_visible_value_bucket_bases",
            &step_params,
            &import_visible_key_radix_bucket_total,
            &import_visible_key_radix_bucket_base,
        )?);
        sort_import_visible_value_key_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_09d_sort_import_visible_keys_scatter"),
            &passes.modules_sort_import_visible_keys_scatter,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "import_visible_count_out",
                    import_visible_value_count_out.as_entire_binding(),
                ),
                (
                    "import_visible_module_id",
                    import_visible_value_module_id.as_entire_binding(),
                ),
                (
                    "import_visible_name_id",
                    import_visible_value_name_id.as_entire_binding(),
                ),
                (
                    "import_visible_key_order_in",
                    read_order.as_entire_binding(),
                ),
                (
                    "radix_bucket_base",
                    import_visible_key_radix_bucket_base.as_entire_binding(),
                ),
                (
                    "radix_block_bucket_prefix",
                    import_visible_key_radix_block_bucket_prefix.as_entire_binding(),
                ),
                (
                    "import_visible_key_order_out",
                    write_order.as_entire_binding(),
                ),
            ],
        )?);
        retained_key_params.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

    let build_import_visible_type_key_table = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_09e_build_import_visible_key_tables.type"),
        &passes.modules_build_import_visible_key_tables,
        0,
        &[
            ("gParams", import_visibility_params.as_entire_binding()),
            (
                "import_visible_count_out",
                import_visible_type_count_out.as_entire_binding(),
            ),
            (
                "import_visible_key_order",
                import_visible_type_key_order.as_entire_binding(),
            ),
            (
                "import_visible_module_id",
                import_visible_type_module_id.as_entire_binding(),
            ),
            (
                "import_visible_name_id",
                import_visible_type_name_id.as_entire_binding(),
            ),
            (
                "import_visible_decl_id",
                import_visible_type_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_key_module_id",
                import_visible_type_key_module_id.as_entire_binding(),
            ),
            (
                "import_visible_key_name_id",
                import_visible_type_key_name_id.as_entire_binding(),
            ),
            (
                "import_visible_key_to_decl_id",
                import_visible_type_key_to_decl_id.as_entire_binding(),
            ),
        ],
    )?;

    let build_import_visible_value_key_table = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_09e_build_import_visible_key_tables.value"),
        &passes.modules_build_import_visible_key_tables,
        0,
        &[
            ("gParams", import_visibility_params.as_entire_binding()),
            (
                "import_visible_count_out",
                import_visible_value_count_out.as_entire_binding(),
            ),
            (
                "import_visible_key_order",
                import_visible_value_key_order.as_entire_binding(),
            ),
            (
                "import_visible_module_id",
                import_visible_value_module_id.as_entire_binding(),
            ),
            (
                "import_visible_name_id",
                import_visible_value_name_id.as_entire_binding(),
            ),
            (
                "import_visible_decl_id",
                import_visible_value_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_key_module_id",
                import_visible_value_key_module_id.as_entire_binding(),
            ),
            (
                "import_visible_key_name_id",
                import_visible_value_key_name_id.as_entire_binding(),
            ),
            (
                "import_visible_key_to_decl_id",
                import_visible_value_key_to_decl_id.as_entire_binding(),
            ),
        ],
    )?;

    let (import_visible_validate_dispatch_params, import_visible_validate_dispatch_args_group) =
        create_pair_max_dispatch(
            device,
            &passes.count_pair_max_dispatch_args,
            "type_check.modules.import_visible_validate_dispatch.params",
            "type_check.modules.import_visible_validate_dispatch_args",
            import_visible_capacity_u32,
            import_visible_capacity_u32,
            &import_visible_type_count_out,
            &import_visible_value_count_out,
            &import_visible_validate_dispatch_args,
        )?;

    let import_visibility_mark_params = uniform_from_val(
        device,
        "type_check.modules.import_visibility.mark.params",
        &ModuleKeyRadixParams {
            module_capacity: record_capacity_u32,
            reserved: import_visible_capacity_u32,
            n_blocks,
            key_step: 1,
        },
    );
    let make_import_visible_validation_bind_group =
        |label: &str, params: &LaniusBuffer<ModuleKeyRadixParams>| {
            bind_group::create_bind_group_from_bindings(
                device,
                Some(label),
                &passes.modules_validate_import_visible_keys,
                0,
                &[
                    ("gParams", params.as_entire_binding()),
                    (
                        "import_visible_type_count_out",
                        import_visible_type_count_out.as_entire_binding(),
                    ),
                    (
                        "import_visible_type_key_module_id",
                        import_visible_type_key_module_id.as_entire_binding(),
                    ),
                    (
                        "import_visible_type_key_name_id",
                        import_visible_type_key_name_id.as_entire_binding(),
                    ),
                    (
                        "import_visible_type_key_to_decl_id",
                        import_visible_type_key_to_decl_id.as_entire_binding(),
                    ),
                    (
                        "import_visible_value_count_out",
                        import_visible_value_count_out.as_entire_binding(),
                    ),
                    (
                        "import_visible_value_key_module_id",
                        import_visible_value_key_module_id.as_entire_binding(),
                    ),
                    (
                        "import_visible_value_key_name_id",
                        import_visible_value_key_name_id.as_entire_binding(),
                    ),
                    (
                        "import_visible_value_key_to_decl_id",
                        import_visible_value_key_to_decl_id.as_entire_binding(),
                    ),
                    (
                        "import_visible_type_status",
                        import_visible_type_status.as_entire_binding(),
                    ),
                    (
                        "import_visible_type_duplicate_of",
                        import_visible_type_duplicate_of.as_entire_binding(),
                    ),
                    (
                        "import_visible_value_status",
                        import_visible_value_status.as_entire_binding(),
                    ),
                    (
                        "import_visible_value_duplicate_of",
                        import_visible_value_duplicate_of.as_entire_binding(),
                    ),
                ],
            )
        };
    let initialize_import_visible_keys = make_import_visible_validation_bind_group(
        "type_check_modules_09f_validate_import_visible_keys.init",
        &import_visibility_params,
    )?;
    let validate_import_visible_keys = make_import_visible_validation_bind_group(
        "type_check_modules_09f_validate_import_visible_keys.mark",
        &import_visibility_mark_params,
    )?;

    let resolve_local_type_paths = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10_resolve_local_paths.type"),
        &passes.modules_resolve_local_paths,
        0,
        &[
            ("gParams", import_visibility_params.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_kind", path_kind.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_segment_base", path_segment_base.as_entire_binding()),
            (
                "path_segment_name_id",
                path_segment_name_id.as_entire_binding(),
            ),
            (
                "path_owner_module_id",
                path_owner_module_id.as_entire_binding(),
            ),
            (
                "decl_key_count_out",
                decl_type_key_count_out.as_entire_binding(),
            ),
            (
                "decl_key_to_decl_id",
                decl_type_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_module_id", decl_module_id.as_entire_binding()),
            ("decl_name_id", decl_name_id.as_entire_binding()),
            ("resolved_decl", resolved_type_decl.as_entire_binding()),
            ("resolved_status", resolved_type_status.as_entire_binding()),
        ],
    )?;

    let resolve_local_value_paths = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10_resolve_local_paths.value"),
        &passes.modules_resolve_local_paths,
        0,
        &[
            ("gParams", import_visibility_params.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_kind", path_kind.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_segment_base", path_segment_base.as_entire_binding()),
            (
                "path_segment_name_id",
                path_segment_name_id.as_entire_binding(),
            ),
            (
                "path_owner_module_id",
                path_owner_module_id.as_entire_binding(),
            ),
            (
                "decl_key_count_out",
                decl_value_key_count_out.as_entire_binding(),
            ),
            (
                "decl_key_to_decl_id",
                decl_value_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_module_id", decl_module_id.as_entire_binding()),
            ("decl_name_id", decl_name_id.as_entire_binding()),
            ("resolved_decl", resolved_value_decl.as_entire_binding()),
            ("resolved_status", resolved_value_status.as_entire_binding()),
        ],
    )?;

    let resolve_imported_type_paths = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10b_resolve_imported_paths.type"),
        &passes.modules_resolve_imported_paths,
        0,
        &[
            ("gParams", import_visibility_params.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_kind", path_kind.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_segment_base", path_segment_base.as_entire_binding()),
            (
                "path_segment_name_id",
                path_segment_name_id.as_entire_binding(),
            ),
            (
                "path_owner_module_id",
                path_owner_module_id.as_entire_binding(),
            ),
            (
                "import_visible_count_out",
                import_visible_type_count_out.as_entire_binding(),
            ),
            (
                "import_visible_key_module_id",
                import_visible_type_key_module_id.as_entire_binding(),
            ),
            (
                "import_visible_key_name_id",
                import_visible_type_key_name_id.as_entire_binding(),
            ),
            (
                "import_visible_key_to_decl_id",
                import_visible_type_key_to_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_status",
                import_visible_type_status.as_entire_binding(),
            ),
            ("resolved_decl", resolved_type_decl.as_entire_binding()),
            ("resolved_status", resolved_type_status.as_entire_binding()),
        ],
    )?;

    let resolve_imported_value_paths = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10b_resolve_imported_paths.value"),
        &passes.modules_resolve_imported_paths,
        0,
        &[
            ("gParams", import_visibility_params.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_kind", path_kind.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_segment_base", path_segment_base.as_entire_binding()),
            (
                "path_segment_name_id",
                path_segment_name_id.as_entire_binding(),
            ),
            (
                "path_owner_module_id",
                path_owner_module_id.as_entire_binding(),
            ),
            (
                "import_visible_count_out",
                import_visible_value_count_out.as_entire_binding(),
            ),
            (
                "import_visible_key_module_id",
                import_visible_value_key_module_id.as_entire_binding(),
            ),
            (
                "import_visible_key_name_id",
                import_visible_value_key_name_id.as_entire_binding(),
            ),
            (
                "import_visible_key_to_decl_id",
                import_visible_value_key_to_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_status",
                import_visible_value_status.as_entire_binding(),
            ),
            ("resolved_decl", resolved_value_decl.as_entire_binding()),
            ("resolved_status", resolved_value_status.as_entire_binding()),
        ],
    )?;

    let resolve_qualified_path_params = uniform_from_val(
        device,
        "type_check.modules.resolve_qualified_paths.params",
        &ModuleKeyRadixParams {
            module_capacity: record_capacity_u32,
            reserved: module_capacity_u32,
            n_blocks,
            key_step: 0,
        },
    );
    let resolve_qualified_type_paths = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10c_resolve_qualified_paths.type"),
        &passes.modules_resolve_qualified_paths,
        0,
        &[
            ("gParams", resolve_qualified_path_params.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_kind", path_kind.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_segment_base", path_segment_base.as_entire_binding()),
            (
                "path_segment_name_id",
                path_segment_name_id.as_entire_binding(),
            ),
            (
                "path_owner_module_id",
                path_owner_module_id.as_entire_binding(),
            ),
            (
                "module_table_count_out",
                module_table_count_out.as_entire_binding(),
            ),
            (
                "sorted_module_key_order",
                module_key_to_module_id.as_entire_binding(),
            ),
            (
                "module_key_segment_count",
                module_key_segment_count.as_entire_binding(),
            ),
            (
                "module_key_segment_base",
                module_key_segment_base.as_entire_binding(),
            ),
            (
                "module_key_segment_name_id",
                module_key_segment_name_id.as_entire_binding(),
            ),
            ("import_count_out", import_count_out.as_entire_binding()),
            ("import_status", import_status.as_entire_binding()),
            ("import_module_id", import_module_id.as_entire_binding()),
            (
                "import_target_module_id",
                import_target_module_id.as_entire_binding(),
            ),
            (
                "import_edge_key_order",
                import_edge_key_order.as_entire_binding(),
            ),
            (
                "decl_key_count_out",
                decl_type_key_count_out.as_entire_binding(),
            ),
            (
                "decl_key_to_decl_id",
                decl_type_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_module_id", decl_module_id.as_entire_binding()),
            ("decl_visibility", decl_visibility.as_entire_binding()),
            ("decl_name_id", decl_name_id.as_entire_binding()),
            ("resolved_decl", resolved_type_decl.as_entire_binding()),
            ("resolved_status", resolved_type_status.as_entire_binding()),
        ],
    )?;

    let resolve_qualified_value_paths = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_10c_resolve_qualified_paths.value"),
        &passes.modules_resolve_qualified_paths,
        0,
        &[
            ("gParams", resolve_qualified_path_params.as_entire_binding()),
            ("path_count_out", path_count_out.as_entire_binding()),
            ("path_kind", path_kind.as_entire_binding()),
            ("path_segment_count", path_segment_count.as_entire_binding()),
            ("path_segment_base", path_segment_base.as_entire_binding()),
            (
                "path_segment_name_id",
                path_segment_name_id.as_entire_binding(),
            ),
            (
                "path_owner_module_id",
                path_owner_module_id.as_entire_binding(),
            ),
            (
                "module_table_count_out",
                module_table_count_out.as_entire_binding(),
            ),
            (
                "sorted_module_key_order",
                module_key_to_module_id.as_entire_binding(),
            ),
            (
                "module_key_segment_count",
                module_key_segment_count.as_entire_binding(),
            ),
            (
                "module_key_segment_base",
                module_key_segment_base.as_entire_binding(),
            ),
            (
                "module_key_segment_name_id",
                module_key_segment_name_id.as_entire_binding(),
            ),
            ("import_count_out", import_count_out.as_entire_binding()),
            ("import_status", import_status.as_entire_binding()),
            ("import_module_id", import_module_id.as_entire_binding()),
            (
                "import_target_module_id",
                import_target_module_id.as_entire_binding(),
            ),
            (
                "import_edge_key_order",
                import_edge_key_order.as_entire_binding(),
            ),
            (
                "decl_key_count_out",
                decl_value_key_count_out.as_entire_binding(),
            ),
            (
                "decl_key_to_decl_id",
                decl_value_key_to_decl_id.as_entire_binding(),
            ),
            ("decl_module_id", decl_module_id.as_entire_binding()),
            ("decl_visibility", decl_visibility.as_entire_binding()),
            ("decl_name_id", decl_name_id.as_entire_binding()),
            ("resolved_decl", resolved_value_decl.as_entire_binding()),
            ("resolved_status", resolved_value_status.as_entire_binding()),
        ],
    )?;

    let scatter_decl_core_records = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_02c_scatter_decl_core_records"),
        &passes.modules_scatter_decl_core_records,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("decl_record_flag", decl_record_flag.as_entire_binding()),
            ("decl_record_prefix", decl_record_prefix.as_entire_binding()),
            ("hir_item_file_id", hir_items.file_id.as_entire_binding()),
            (
                "hir_item_name_token",
                hir_items.name_token.as_entire_binding(),
            ),
            ("hir_item_kind", hir_items.kind.as_entire_binding()),
            (
                "hir_item_namespace",
                hir_items.namespace.as_entire_binding(),
            ),
            (
                "hir_item_visibility",
                hir_items.visibility.as_entire_binding(),
            ),
            (
                "hir_variant_parent_enum",
                hir_items.variant_parent_enum.as_entire_binding(),
            ),
            ("name_id_by_token", name_id_by_token.as_entire_binding()),
            (
                "decl_module_file_id",
                decl_module_file_id.as_entire_binding(),
            ),
            ("decl_name_id", decl_name_id.as_entire_binding()),
            ("decl_kind", decl_kind.as_entire_binding()),
            ("decl_namespace", decl_namespace.as_entire_binding()),
            ("decl_visibility", decl_visibility.as_entire_binding()),
            ("decl_hir_node", decl_hir_node.as_entire_binding()),
            (
                "decl_parent_type_decl",
                decl_parent_type_decl.as_entire_binding(),
            ),
        ],
    )?;

    let clear_decl_lookup = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_02d_clear_decl_lookup"),
        &passes.modules_clear_decl_lookup,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "decl_id_by_name_token",
                decl_id_by_name_token.as_entire_binding(),
            ),
        ],
    )?;

    let scatter_decl_span_records = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_02d_scatter_decl_span_records"),
        &passes.modules_scatter_decl_span_records,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("decl_record_flag", decl_record_flag.as_entire_binding()),
            ("decl_record_prefix", decl_record_prefix.as_entire_binding()),
            (
                "hir_item_name_token",
                hir_items.name_token.as_entire_binding(),
            ),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            ("hir_token_end", hir_token_end_buf.as_entire_binding()),
            ("decl_name_token", decl_name_token.as_entire_binding()),
            ("decl_token_start", decl_token_start.as_entire_binding()),
            ("decl_token_end", decl_token_end.as_entire_binding()),
            (
                "decl_id_by_name_token",
                decl_id_by_name_token.as_entire_binding(),
            ),
        ],
    )?;
    retained_key_params.push(ModuleKeyRadixStep {
        _params: decl_module_params,
    });
    retained_key_params.push(ModuleKeyRadixStep {
        _params: attach_record_modules_params,
    });
    retained_key_params.push(ModuleKeyRadixStep {
        _params: build_file_module_map_params,
    });
    retained_key_params.push(ModuleKeyRadixStep {
        _params: validate_decl_params,
    });
    retained_key_params.push(ModuleKeyRadixStep {
        _params: import_visibility_params,
    });
    retained_key_params.push(ModuleKeyRadixStep {
        _params: import_visibility_mark_params,
    });
    retained_key_params.push(ModuleKeyRadixStep {
        _params: resolve_qualified_path_params,
    });

    Ok(State {
        n_blocks,
        parser_hir_n_blocks,
        record_n_blocks,
        module_n_blocks,
        token_capacity,
        record_family_bits,
        record_family_flag,
        module_record_flag,
        import_record_flag,
        decl_record_flag,
        module_record_prefix,
        import_record_prefix,
        decl_record_prefix,
        record_scan_local_prefix,
        record_scan_block_sum,
        record_scan_prefix_a,
        record_scan_prefix_b,
        module_count_out,
        module_table_count_out,
        import_count_out,
        decl_count_out,
        module_file_id,
        module_path_id,
        module_owner_hir,
        module_status,
        module_key_segment_count,
        module_key_segment_base,
        module_key_segment_name_id,
        module_key_to_module_id,
        module_key_order_tmp,
        module_key_radix_dispatch_args,
        module_key_radix_block_histogram,
        module_key_radix_block_bucket_prefix,
        module_key_radix_bucket_total,
        module_key_radix_bucket_base,
        module_id_by_file_id,
        import_module_file_id,
        import_path_id,
        import_kind,
        import_owner_hir,
        import_module_id,
        import_target_module_id,
        import_status,
        import_edge_key_order,
        import_edge_key_order_tmp,
        import_edge_key_radix_dispatch_args,
        import_dispatch_args,
        decl_module_file_id,
        decl_module_id,
        decl_name_token,
        decl_id_by_name_token,
        decl_name_id,
        decl_kind,
        decl_namespace,
        decl_visibility,
        decl_hir_node,
        decl_parent_type_decl,
        decl_token_start,
        decl_token_end,
        decl_key_to_decl_id,
        decl_key_order_tmp,
        decl_key_radix_dispatch_args,
        decl_key_radix_block_histogram,
        decl_key_radix_block_bucket_prefix,
        decl_key_radix_bucket_total,
        decl_key_radix_bucket_base,
        decl_status,
        decl_duplicate_of,
        decl_type_key_flag,
        decl_value_key_flag,
        decl_type_key_prefix,
        decl_value_key_prefix,
        decl_type_key_count_out,
        decl_value_key_count_out,
        decl_type_key_to_decl_id,
        decl_value_key_to_decl_id,
        import_visible_type_count,
        import_visible_value_count,
        import_visible_type_prefix,
        import_visible_value_prefix,
        import_visible_type_count_out,
        import_visible_value_count_out,
        import_visible_type_module_id,
        import_visible_type_name_id,
        import_visible_type_decl_id,
        import_visible_type_key_order,
        import_visible_type_key_order_tmp,
        import_visible_type_key_module_id,
        import_visible_type_key_name_id,
        import_visible_type_key_to_decl_id,
        import_visible_type_status,
        import_visible_type_duplicate_of,
        import_visible_type_key_radix_dispatch_args,
        import_visible_value_module_id,
        import_visible_value_name_id,
        import_visible_value_decl_id,
        import_visible_value_key_order,
        import_visible_value_key_order_tmp,
        import_visible_value_key_module_id,
        import_visible_value_key_name_id,
        import_visible_value_key_to_decl_id,
        import_visible_value_status,
        import_visible_value_duplicate_of,
        import_visible_value_key_radix_dispatch_args,
        import_visible_validate_dispatch_args,
        import_visible_key_radix_block_histogram,
        import_visible_key_radix_block_bucket_prefix,
        import_visible_key_radix_bucket_total,
        import_visible_key_radix_bucket_base,
        resolved_type_decl,
        resolved_value_decl,
        resolved_type_status,
        resolved_value_status,
        path_record_flag,
        path_record_prefix,
        path_scan_local_prefix,
        path_scan_block_sum,
        path_scan_prefix_a,
        path_scan_prefix_b,
        path_start,
        path_len,
        path_segment_count,
        path_segment_base,
        path_segment_name_id,
        path_segment_token,
        path_segment_count_out,
        path_owner_hir,
        path_owner_token,
        path_id_by_owner_hir,
        path_id_by_owner_token,
        path_owner_module_id,
        path_kind,
        path_count_out,
        path_dispatch_args,
        scan_steps,
        record_scan_steps,
        _extract_path_record_flag_params: extract_path_record_flag_params,
        _extract_module_record_flag_params: extract_module_record_flag_params,
        _extract_import_record_flag_params: extract_import_record_flag_params,
        _extract_decl_record_flag_params: extract_decl_record_flag_params,
        _path_dispatch_params: path_dispatch_params,
        _import_dispatch_params: import_dispatch_params,
        _import_visible_validate_dispatch_params: import_visible_validate_dispatch_params,
        _module_key_radix_dispatch_params: module_key_radix_dispatch_params,
        _decl_key_radix_dispatch_params: decl_key_radix_dispatch_params,
        _import_visible_type_key_radix_dispatch_params:
            import_visible_type_key_radix_dispatch_params,
        _import_visible_value_key_radix_dispatch_params:
            import_visible_value_key_radix_dispatch_params,
        _retained_key_params: retained_key_params,
        bind_groups: BindGroups {
            mark_records,
            extract_path_record_flag,
            path_scan,
            scatter_paths,
            count_path_segments,
            path_segment_scan,
            scatter_path_segments,
            extract_module_record_flag,
            module_scan,
            extract_import_record_flag,
            import_scan,
            extract_decl_record_flag,
            decl_scan,
            scatter_module_records,
            scatter_import_records,
            scatter_decl_core_records,
            clear_decl_lookup,
            scatter_decl_span_records,
            build_module_keys,
            module_key_radix_dispatch,
            sort_module_keys_small,
            sort_module_key_histogram,
            sort_module_key_bucket_prefix,
            sort_module_key_bucket_bases,
            sort_module_key_scatter,
            validate_modules,
            resolve_imports,
            seed_import_edge_key_order,
            import_edge_key_radix_dispatch,
            sort_import_edges_small,
            sort_import_edge_key_histogram,
            sort_import_edge_key_bucket_prefix,
            sort_import_edge_key_bucket_bases,
            sort_import_edge_key_scatter,
            validate_import_cycles,
            clear_file_module_map,
            build_file_module_map,
            attach_record_modules,
            import_dispatch_args: import_dispatch_args_group,
            seed_decl_key_order,
            decl_key_radix_dispatch,
            sort_decl_keys_small,
            sort_decl_key_histogram,
            sort_decl_key_bucket_prefix,
            sort_decl_key_bucket_bases,
            sort_decl_key_scatter,
            validate_decls,
            mark_decl_namespace_keys,
            decl_type_key_scan,
            decl_value_key_scan,
            scatter_decl_namespace_keys,
            mark_public_decl_keys,
            decl_type_public_scan,
            decl_value_public_scan,
            count_import_visibility,
            import_visible_type_scan,
            import_visible_value_scan,
            scatter_import_visible_type,
            scatter_import_visible_value,
            import_visible_type_key_radix_dispatch,
            sort_import_visible_type_keys_small,
            sort_import_visible_type_key_histogram,
            sort_import_visible_type_key_bucket_prefix,
            sort_import_visible_type_key_bucket_bases,
            sort_import_visible_type_key_scatter,
            import_visible_value_key_radix_dispatch,
            sort_import_visible_value_keys_small,
            sort_import_visible_value_key_histogram,
            sort_import_visible_value_key_bucket_prefix,
            sort_import_visible_value_key_bucket_bases,
            sort_import_visible_value_key_scatter,
            build_import_visible_type_key_table,
            build_import_visible_value_key_table,
            import_visible_validate_dispatch_args: import_visible_validate_dispatch_args_group,
            initialize_import_visible_keys,
            validate_import_visible_keys,
            path_dispatch_args: path_dispatch_args_group,
            resolve_local_type_paths,
            resolve_local_value_paths,
            resolve_imported_type_paths,
            resolve_imported_value_paths,
            resolve_qualified_type_paths,
            resolve_qualified_value_paths,
            clear_type_path_types,
            project_type_paths,
            validate_type_paths,
            project_type_aliases,
            project_type_instances,
            mark_value_call_paths,
            project_value_paths,
            consume_value_calls,
            mirror_value_call_leaf,
            consume_value_consts,
            consume_value_enum_units,
            consume_value_enum_calls,
            validate_value_enum_call_payloads,
            finalize_value_enum_calls,
            bind_match_patterns,
            type_match_payloads,
            type_match_exprs,
        },
    })
}
