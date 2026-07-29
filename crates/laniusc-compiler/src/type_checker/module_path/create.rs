use super::{
    super::*,
    bind_helpers::{create_pair_max_dispatch, create_radix_dispatch},
    buffers::Buffers,
    dependency_visibility,
    inputs::CreateInputs,
    layout::Layout,
    module_index::{ModuleIndex, create_module_index},
    path_sequences::{PathSequences, create_path_sequences},
    projection::{ProjectionBindGroups, create_projection_bind_groups},
    record_discovery::{RecordDiscovery, create_record_discovery},
    state::{BindGroups, State},
};

/// Creates the complete module/path state from loaded passes and typed inputs.
pub(in crate::type_checker) fn create_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    inputs: CreateInputs<'_>,
    resources: &ResourceMap<'_>,
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
    let PathSequences {
        clear_state: clear_path_state,
        dispatch_params: path_prefix_dispatch_params,
        dispatch_args: path_prefix_dispatch_args,
        rounds: path_prefix_rounds,
        finalize: path_prefix_finalize,
    } = create_path_sequences(passes, device, &inputs, &buffers, resources)?;
    let dependency_visibility =
        dependency_visibility::create(passes, device, layout, &inputs, &buffers, resources)?;
    let RecordDiscovery {
        mark_records,
        extract_module_record_flag_params,
        extract_module_record_flag,
        extract_import_record_flag_params,
        extract_import_record_flag,
        extract_decl_record_flag_params,
        extract_decl_record_flag,
        scatter_paths,
        path_dispatch_params,
        path_dispatch_args: path_dispatch_args_group,
        import_dispatch_params,
        import_dispatch_args: import_dispatch_args_group,
        count_path_segments,
        scatter_path_segments,
        module_scan,
        import_scan,
        decl_scan,
    } = create_record_discovery(passes, device, layout, &inputs, &buffers, resources)?;
    let ModuleIndex {
        scatter_module_records,
        build_module_keys,
        module_key_radix_dispatch_params,
        module_key_radix_dispatch,
        sort_module_keys,
        validate_modules,
        dependency_module_params,
        clear_dependency_module_lookup,
        build_dependency_module_lookup,
        resolve_dependency_imports,
        scatter_import_records,
        resolve_imports,
        seed_import_edge_key_order,
        import_edge_key_radix_dispatch,
        sort_import_edges,
        validate_import_cycles,
        mut retained_params,
    } = create_module_index(passes, device, layout, &inputs, &buffers, resources)?;
    let ProjectionBindGroups {
        clear_type_path_types,
        project_type_paths,
        validate_type_paths,
        type_aliases,
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
        module_key_canonical_id,
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
        import_target_dependency_module_id,
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
        interface_public_decl_count,
        interface_public_decl_local_id,
        interface_public_decl_index_by_local,
        interface_public_decl_index_by_hir,
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
        path_max_segment_count,
        path_prefix_base,
        path_prefix_id_a,
        path_prefix_id_b,
        path_prefix_table_state,
        path_prefix_row_dispatch_args,
        path_prefix_round_dispatch_args,
        path_owner_hir,
        path_call_hir,
        path_owner_token,
        path_id_by_owner_hir,
        path_id_by_owner_token,
        path_owner_module_id,
        path_kind,
        path_count_out,
        path_dispatch_args,
        import_dispatch_args,
    } = buffers;
    let CreateInputs {
        params,
        token_capacity,
        hir_node_capacity,
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
        &passes.kernel("type_checker/modules/05b_clear_file_module_map"),
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
        &passes.kernel("type_checker/modules/05c_build_file_module_map"),
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
        &passes.kernel("type_checker/modules/05d_attach_record_modules"),
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
            ("compact_hir_count", hir_items.hir.count.as_entire_binding()),
            ("compact_hir_links", hir_items.hir.links.as_entire_binding()),
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
        &passes.kernel("type_checker/modules/06a_seed_decl_key_order"),
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
        &passes.kernel("type_checker/names/radix/dispatch_args"),
        "type_check.modules.decl_key_radix_dispatch",
        &decl_key_radix_dispatch_params,
        &decl_count_out,
        &decl_key_radix_dispatch_args,
    )?;

    let (decl_key_radix_widths, decl_key_radix_steps) =
        decl_key_radix_layout(token_capacity, module_capacity_u32);
    let decl_key_resources = HashMap::from([
        (
            "decl_count_out".to_owned(),
            decl_count_out.as_entire_binding(),
        ),
        (
            "decl_module_id".to_owned(),
            decl_module_id.as_entire_binding(),
        ),
        (
            "decl_namespace".to_owned(),
            decl_namespace.as_entire_binding(),
        ),
        ("decl_name_id".to_owned(), decl_name_id.as_entire_binding()),
        (
            "decl_key_order".to_owned(),
            decl_key_to_decl_id.as_entire_binding(),
        ),
        (
            "decl_key_order_tmp".to_owned(),
            decl_key_order_tmp.as_entire_binding(),
        ),
        (
            "decl_key_radix_block_histogram".to_owned(),
            decl_key_radix_block_histogram.as_entire_binding(),
        ),
        (
            "decl_key_radix_block_bucket_prefix".to_owned(),
            decl_key_radix_block_bucket_prefix.as_entire_binding(),
        ),
        (
            "decl_key_radix_bucket_total".to_owned(),
            decl_key_radix_bucket_total.as_entire_binding(),
        ),
        (
            "decl_key_radix_bucket_base".to_owned(),
            decl_key_radix_bucket_base.as_entire_binding(),
        ),
    ]);
    let sort_decl_keys = RadixSortOperation::new(
        device,
        passes,
        &decl_key_resources,
        RadixSortPlan {
            label: "type_check.modules.decl_keys",
            capacity: record_capacity_u32,
            small_capacity: MODULE_RELATION_SMALL_SORT_CAPACITY,
            steps: decl_key_radix_steps,
            kernels: RadixSortKernels::new(
                "type_checker/modules/06_sort_decl_keys",
                "type_checker/modules/06b_sort_decl_keys_scatter",
            )
            .with_small("type_checker/modules/06a2_sort_decl_keys_small"),
            dispatch: RadixSortDispatch {
                small: RadixDispatchDomain::Indirect(&decl_key_radix_dispatch_args),
                rows: RadixDispatchDomain::Indirect(&decl_key_radix_dispatch_args),
                bucket_prefix: RadixDispatchDomain::Direct(NAME_RADIX_BUCKETS.saturating_mul(256)),
                bucket_bases: RadixDispatchDomain::Direct(256),
            },
            resources: RadixSortResources {
                count: "decl_count_out",
                order: "decl_key_order",
                temporary_order: "decl_key_order_tmp",
                histogram: "decl_key_radix_block_histogram",
                bucket_prefix: "decl_key_radix_block_bucket_prefix",
                bucket_total: "decl_key_radix_bucket_total",
                bucket_base: "decl_key_radix_bucket_base",
            },
        },
        |key_step| ModuleKeyRadixParams {
            module_capacity: record_capacity_u32,
            reserved: decl_key_radix_widths,
            n_blocks: record_n_blocks,
            key_step,
        },
    )?;

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
        &passes.kernel("type_checker/modules/07_validate_decls"),
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
        &passes.kernel("type_checker/modules/08_mark_decl_namespace_keys"),
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

    // Type and value namespace scans execute side-by-side at each scan level.
    // Give the value scan its own scratch so the paired dispatches remain
    // independent within one compute pass. This secondary scratch is reused by
    // all later type/value scan pairs in the module pipeline.
    let value_scan_local_prefix: LaniusBuffer<u32> = inputs
        .module_value_scan_workspace
        .local_prefix
        .alias(record_capacity_u32 as usize);
    let value_scan_block_sum: LaniusBuffer<u32> = inputs
        .module_value_scan_workspace
        .block_sum
        .alias(record_n_blocks as usize);
    let value_scan_prefix_a: LaniusBuffer<u32> = inputs
        .module_value_scan_workspace
        .block_prefix
        .alias(record_n_blocks as usize);
    let value_scan_prefix_b: LaniusBuffer<u32> = inputs
        .module_value_scan_workspace
        .hierarchy
        .alias(record_n_blocks as usize);

    let mut scan_resources = ResourceMap::new();
    scan_resources.buffers([
        ("decl_count_out", &decl_count_out),
        (
            "decl_key_radix_dispatch_args",
            &decl_key_radix_dispatch_args,
        ),
        ("type_instance_arg_ref_tag", &decl_type_key_flag),
        ("type_instance_arg_ref_payload", &decl_value_key_flag),
        ("decl_type_key_prefix", &decl_type_key_prefix),
        ("decl_value_key_prefix", &decl_value_key_prefix),
        ("decl_type_key_count_out", &decl_type_key_count_out),
        ("decl_value_key_count_out", &decl_value_key_count_out),
        ("module_record_scan_local_prefix", &record_scan_local_prefix),
        ("module_record_scan_block_sum", &record_scan_block_sum),
        ("module_record_scan_prefix_a", &record_scan_prefix_a),
        ("module_record_scan_prefix_b", &record_scan_prefix_b),
        ("module_value_scan_local_prefix", &value_scan_local_prefix),
        ("module_value_scan_block_sum", &value_scan_block_sum),
        ("module_value_scan_prefix_a", &value_scan_prefix_a),
        ("module_value_scan_prefix_b", &value_scan_prefix_b),
        ("decl_status", &decl_status),
        (
            "type_decl_generic_param_count_by_owner_token",
            &decl_duplicate_of,
        ),
        ("import_visible_type_count", &import_visible_type_count),
        ("import_visible_value_count", &import_visible_value_count),
        ("import_visible_type_prefix", &import_visible_type_prefix),
        ("import_visible_value_prefix", &import_visible_value_prefix),
        (
            "import_visible_type_count_out",
            &import_visible_type_count_out,
        ),
        (
            "import_visible_value_count_out",
            &import_visible_value_count_out,
        ),
        ("import_record_count_out", &import_count_out),
        ("import_dispatch_args", &import_dispatch_args),
    ]);

    let (decl_type_key_scan, decl_value_key_scan) = PrefixScanOperation::from_pair_spec(
        device,
        passes,
        &scan_resources,
        compiler_graph::DECL_NAMESPACE_SCAN,
    )?;

    let scatter_decl_namespace_keys = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_08b_scatter_decl_namespace_keys"),
        &passes.kernel("type_checker/modules/08b_scatter_decl_namespace_keys"),
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
        &passes.kernel("type_checker/modules/08c_mark_public_decl_keys"),
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

    let (decl_type_public_scan, decl_value_public_scan) = PrefixScanOperation::from_pair_spec(
        device,
        passes,
        &scan_resources,
        compiler_graph::DECL_PUBLIC_SCAN,
    )?;
    let clear_interface_public_decls = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_interface_public_decls_00_clear"),
        &passes.kernel("type_checker/interface/public_decls/00_clear"),
        0,
        &[
            ("gParams", validate_decl_params.as_entire_binding()),
            (
                "interface_public_decl_count",
                interface_public_decl_count.as_entire_binding(),
            ),
            (
                "interface_public_decl_local_id",
                interface_public_decl_local_id.as_entire_binding(),
            ),
            (
                "interface_public_decl_index_by_local",
                interface_public_decl_index_by_local.as_entire_binding(),
            ),
            (
                "interface_public_decl_index_by_hir",
                interface_public_decl_index_by_hir.as_entire_binding(),
            ),
        ],
    )?;
    let map_interface_public_decls = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_interface_public_decls_01_map"),
        &passes.kernel("type_checker/interface/public_decls/01_map"),
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
            ("decl_hir_node", decl_hir_node.as_entire_binding()),
            ("decl_kind", decl_kind.as_entire_binding()),
            (
                "interface_public_decl_count",
                interface_public_decl_count.as_entire_binding(),
            ),
            (
                "interface_public_decl_local_id",
                interface_public_decl_local_id.as_entire_binding(),
            ),
            (
                "interface_public_decl_index_by_local",
                interface_public_decl_index_by_local.as_entire_binding(),
            ),
            (
                "interface_public_decl_index_by_hir",
                interface_public_decl_index_by_hir.as_entire_binding(),
            ),
        ],
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
        &passes.kernel("type_checker/modules/09_count_import_visibility"),
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

    let (import_visible_type_scan, import_visible_value_scan) =
        PrefixScanOperation::from_pair_spec(
            device,
            passes,
            &scan_resources,
            compiler_graph::IMPORT_VISIBLE_SCAN,
        )?;

    let scatter_import_visible_type = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_09b_scatter_import_visibility.type"),
        &passes.kernel("type_checker/modules/09b_scatter_import_visibility"),
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
        &passes.kernel("type_checker/modules/09b_scatter_import_visibility"),
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
        &passes.kernel("type_checker/names/radix/dispatch_args"),
        "type_check.modules.import_visible_type_key_radix_dispatch",
        &import_visible_type_key_radix_dispatch_params,
        &import_visible_type_count_out,
        &import_visible_type_key_radix_dispatch_args,
    )?;

    let import_visible_type_key_resources = HashMap::from([
        (
            "import_visible_count_out".to_owned(),
            import_visible_type_count_out.as_entire_binding(),
        ),
        (
            "import_visible_module_id".to_owned(),
            import_visible_type_module_id.as_entire_binding(),
        ),
        (
            "import_visible_name_id".to_owned(),
            import_visible_type_name_id.as_entire_binding(),
        ),
        (
            "import_visible_key_order".to_owned(),
            import_visible_type_key_order.as_entire_binding(),
        ),
        (
            "import_visible_key_order_tmp".to_owned(),
            import_visible_type_key_order_tmp.as_entire_binding(),
        ),
        (
            "import_visible_radix_histogram".to_owned(),
            import_visible_key_radix_block_histogram.as_entire_binding(),
        ),
        (
            "import_visible_radix_prefix".to_owned(),
            import_visible_key_radix_block_bucket_prefix.as_entire_binding(),
        ),
        (
            "import_visible_radix_total".to_owned(),
            import_visible_key_radix_bucket_total.as_entire_binding(),
        ),
        (
            "import_visible_radix_base".to_owned(),
            import_visible_key_radix_bucket_base.as_entire_binding(),
        ),
    ]);
    let import_visible_sort_plan = |label, resources, dispatch_args| RadixSortPlan {
        label,
        capacity: import_visible_capacity_u32,
        small_capacity: MODULE_RELATION_SMALL_SORT_CAPACITY,
        steps: IMPORT_VISIBLE_KEY_RADIX_STEPS,
        kernels: RadixSortKernels::new(
            "type_checker/modules/09c_sort_import_visible_keys",
            "type_checker/modules/09d_sort_import_visible_keys_scatter",
        )
        .with_small("type_checker/modules/09b2_sort_import_visible_keys_small"),
        dispatch: RadixSortDispatch {
            small: RadixDispatchDomain::Indirect(dispatch_args),
            rows: RadixDispatchDomain::Indirect(dispatch_args),
            bucket_prefix: RadixDispatchDomain::Direct(NAME_RADIX_BUCKETS.saturating_mul(256)),
            bucket_bases: RadixDispatchDomain::Direct(256),
        },
        resources,
    };
    let import_visible_resources = RadixSortResources {
        count: "import_visible_count_out",
        order: "import_visible_key_order",
        temporary_order: "import_visible_key_order_tmp",
        histogram: "import_visible_radix_histogram",
        bucket_prefix: "import_visible_radix_prefix",
        bucket_total: "import_visible_radix_total",
        bucket_base: "import_visible_radix_base",
    };
    let sort_import_visible_type_keys = RadixSortOperation::new(
        device,
        passes,
        &import_visible_type_key_resources,
        import_visible_sort_plan(
            "type_check.modules.import_visible_type_keys",
            import_visible_resources,
            &import_visible_type_key_radix_dispatch_args,
        ),
        |key_step| ModuleKeyRadixParams {
            module_capacity: import_visible_capacity_u32,
            reserved: 0,
            n_blocks: import_visible_n_blocks,
            key_step,
        },
    )?;

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
        &passes.kernel("type_checker/names/radix/dispatch_args"),
        "type_check.modules.import_visible_value_key_radix_dispatch",
        &import_visible_value_key_radix_dispatch_params,
        &import_visible_value_count_out,
        &import_visible_value_key_radix_dispatch_args,
    )?;

    // Type and value visibility keys are sorted stage-by-stage in parallel.
    // Keep one secondary radix scratch set for the value namespace so those
    // dispatches have no write hazards inside their shared compute passes.
    let import_visible_value_radix_block_histogram = typed_storage_u32_rw(
        device,
        "type_check.modules.import_visible_value_radix_block_histogram",
        import_visible_key_radix_block_histogram.count,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_radix_block_bucket_prefix = typed_storage_u32_rw(
        device,
        "type_check.modules.import_visible_value_radix_block_bucket_prefix",
        import_visible_key_radix_block_bucket_prefix.count,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_radix_bucket_total = typed_storage_u32_rw(
        device,
        "type_check.modules.import_visible_value_radix_bucket_total",
        import_visible_key_radix_bucket_total.count,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_radix_bucket_base = typed_storage_u32_rw(
        device,
        "type_check.modules.import_visible_value_radix_bucket_base",
        import_visible_key_radix_bucket_base.count,
        wgpu::BufferUsages::empty(),
    );
    let import_visible_value_key_resources = HashMap::from([
        (
            "import_visible_count_out".to_owned(),
            import_visible_value_count_out.as_entire_binding(),
        ),
        (
            "import_visible_module_id".to_owned(),
            import_visible_value_module_id.as_entire_binding(),
        ),
        (
            "import_visible_name_id".to_owned(),
            import_visible_value_name_id.as_entire_binding(),
        ),
        (
            "import_visible_key_order".to_owned(),
            import_visible_value_key_order.as_entire_binding(),
        ),
        (
            "import_visible_key_order_tmp".to_owned(),
            import_visible_value_key_order_tmp.as_entire_binding(),
        ),
        (
            "import_visible_radix_histogram".to_owned(),
            import_visible_value_radix_block_histogram.as_entire_binding(),
        ),
        (
            "import_visible_radix_prefix".to_owned(),
            import_visible_value_radix_block_bucket_prefix.as_entire_binding(),
        ),
        (
            "import_visible_radix_total".to_owned(),
            import_visible_value_radix_bucket_total.as_entire_binding(),
        ),
        (
            "import_visible_radix_base".to_owned(),
            import_visible_value_radix_bucket_base.as_entire_binding(),
        ),
    ]);
    let sort_import_visible_value_keys = RadixSortOperation::new(
        device,
        passes,
        &import_visible_value_key_resources,
        import_visible_sort_plan(
            "type_check.modules.import_visible_value_keys",
            import_visible_resources,
            &import_visible_value_key_radix_dispatch_args,
        ),
        |key_step| ModuleKeyRadixParams {
            module_capacity: import_visible_capacity_u32,
            reserved: 0,
            n_blocks: import_visible_n_blocks,
            key_step,
        },
    )?;

    let build_import_visible_type_key_table = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_09e_build_import_visible_key_tables.type"),
        &passes.kernel("type_checker/modules/09e_build_import_visible_key_tables"),
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
        &passes.kernel("type_checker/modules/09e_build_import_visible_key_tables"),
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
            &passes.kernel("type_checker/count/pair_max_dispatch_args"),
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
                &passes.kernel("type_checker/modules/09f_validate_import_visible_keys"),
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
        &passes.kernel("type_checker/modules/10_resolve_local_paths"),
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
        &passes.kernel("type_checker/modules/10_resolve_local_paths"),
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
        &passes.kernel("type_checker/modules/10b_resolve_imported_paths"),
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
        &passes.kernel("type_checker/modules/10b_resolve_imported_paths"),
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
        &passes.kernel("type_checker/modules/10c_resolve_qualified_paths"),
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
            ("path_prefix_id", path_prefix_id_a.as_entire_binding()),
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
                "module_key_canonical_id",
                module_key_canonical_id.as_entire_binding(),
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
        &passes.kernel("type_checker/modules/10c_resolve_qualified_paths"),
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
            ("path_prefix_id", path_prefix_id_a.as_entire_binding()),
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
                "module_key_canonical_id",
                module_key_canonical_id.as_entire_binding(),
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
        &passes.kernel("type_checker/modules/02c_scatter_decl_core_records"),
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("decl_record_flag", decl_record_flag.as_entire_binding()),
            ("decl_record_prefix", decl_record_prefix.as_entire_binding()),
            ("compact_hir_core", hir_items.hir.core.as_entire_binding()),
            ("compact_hir_links", hir_items.hir.links.as_entire_binding()),
            (
                "compact_hir_payload",
                hir_items.hir.payload.as_entire_binding(),
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

    let append_variant_decl_count = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_02c1_append_variant_decl_count"),
        &passes.kernel("type_checker/modules/02c1_append_variant_decl_count"),
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "compact_variant_count",
                hir_items.hir.variant_count.as_entire_binding(),
            ),
            ("decl_count_out", decl_count_out.as_entire_binding()),
        ],
    )?;

    let clear_decl_lookup = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_02d_clear_decl_lookup"),
        &passes.kernel("type_checker/modules/02d/clear_decl_lookup"),
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
        &passes.kernel("type_checker/modules/02d/scatter_decl_span_records"),
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("decl_record_flag", decl_record_flag.as_entire_binding()),
            ("decl_record_prefix", decl_record_prefix.as_entire_binding()),
            ("compact_hir_core", hir_items.hir.core.as_entire_binding()),
            (
                "compact_hir_payload",
                hir_items.hir.payload.as_entire_binding(),
            ),
            ("decl_name_token", decl_name_token.as_entire_binding()),
            ("decl_token_start", decl_token_start.as_entire_binding()),
            ("decl_token_end", decl_token_end.as_entire_binding()),
            (
                "decl_id_by_name_token",
                decl_id_by_name_token.as_entire_binding(),
            ),
        ],
    )?;

    let scatter_variant_decl_records = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_02c2_scatter_variant_decl_records"),
        &passes.kernel("type_checker/modules/02c2_scatter_variant_decl_records"),
        0,
        &[
            ("gParams", params.as_entire_binding()),
            (
                "compact_variant_count",
                hir_items.hir.variant_count.as_entire_binding(),
            ),
            (
                "compact_variants",
                hir_items.hir.variants.as_entire_binding(),
            ),
            (
                "compact_hir_payload",
                hir_items.hir.payload.as_entire_binding(),
            ),
            ("decl_record_flag", decl_record_flag.as_entire_binding()),
            ("decl_record_prefix", decl_record_prefix.as_entire_binding()),
            ("decl_count_out", decl_count_out.as_entire_binding()),
            ("name_id_by_token", name_id_by_token.as_entire_binding()),
            (
                "decl_module_file_id",
                decl_module_file_id.as_entire_binding(),
            ),
            ("decl_name_token", decl_name_token.as_entire_binding()),
            ("decl_name_id", decl_name_id.as_entire_binding()),
            ("decl_kind", decl_kind.as_entire_binding()),
            ("decl_namespace", decl_namespace.as_entire_binding()),
            ("decl_visibility", decl_visibility.as_entire_binding()),
            ("decl_hir_node", decl_hir_node.as_entire_binding()),
            (
                "decl_parent_type_decl",
                decl_parent_type_decl.as_entire_binding(),
            ),
            ("decl_token_start", decl_token_start.as_entire_binding()),
            ("decl_token_end", decl_token_end.as_entire_binding()),
            (
                "decl_id_by_name_token",
                decl_id_by_name_token.as_entire_binding(),
            ),
        ],
    )?;
    retained_params.push(decl_module_params);
    retained_params.push(attach_record_modules_params);
    retained_params.push(build_file_module_map_params);
    retained_params.push(validate_decl_params);
    retained_params.push(import_visibility_params);
    retained_params.push(import_visibility_mark_params);
    retained_params.push(resolve_qualified_path_params);

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
        module_key_canonical_id,
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
        import_target_dependency_module_id,
        dependency_interfaces: inputs.dependency_interfaces.cloned(),
        dependency_visibility,
        dependency_module_params,
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
        interface_public_decl_count,
        interface_public_decl_local_id,
        interface_public_decl_index_by_local,
        interface_public_decl_index_by_hir,
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
        path_max_segment_count,
        path_prefix_base,
        path_prefix_id_a,
        path_prefix_id_b,
        path_prefix_table_state,
        path_prefix_row_dispatch_args,
        path_prefix_round_dispatch_args,
        path_owner_hir,
        path_call_hir,
        path_owner_token,
        path_id_by_owner_hir,
        path_id_by_owner_token,
        path_owner_module_id,
        path_kind,
        path_count_out,
        path_dispatch_args,
        _extract_module_record_flag_params: extract_module_record_flag_params,
        _extract_import_record_flag_params: extract_import_record_flag_params,
        _extract_decl_record_flag_params: extract_decl_record_flag_params,
        _path_dispatch_params: path_dispatch_params,
        _path_prefix_dispatch_params: path_prefix_dispatch_params,
        _import_dispatch_params: import_dispatch_params,
        _import_visible_validate_dispatch_params: import_visible_validate_dispatch_params,
        _module_key_radix_dispatch_params: module_key_radix_dispatch_params,
        _decl_key_radix_dispatch_params: decl_key_radix_dispatch_params,
        _import_visible_type_key_radix_dispatch_params:
            import_visible_type_key_radix_dispatch_params,
        _import_visible_value_key_radix_dispatch_params:
            import_visible_value_key_radix_dispatch_params,
        _retained_params: retained_params,
        bind_groups: BindGroups {
            mark_records,
            scatter_paths,
            count_path_segments,
            scatter_path_segments,
            clear_path_state,
            path_prefix_dispatch_args,
            path_prefix_rounds,
            path_prefix_finalize,
            extract_module_record_flag,
            module_scan,
            extract_import_record_flag,
            import_scan,
            extract_decl_record_flag,
            decl_scan,
            scatter_module_records,
            scatter_import_records,
            scatter_decl_core_records,
            append_variant_decl_count,
            scatter_variant_decl_records,
            clear_decl_lookup,
            scatter_decl_span_records,
            build_module_keys,
            module_key_radix_dispatch,
            sort_module_keys,
            validate_modules,
            clear_dependency_module_lookup,
            build_dependency_module_lookup,
            resolve_dependency_imports,
            resolve_imports,
            seed_import_edge_key_order,
            import_edge_key_radix_dispatch,
            sort_import_edges,
            validate_import_cycles,
            clear_file_module_map,
            build_file_module_map,
            attach_record_modules,
            import_dispatch_args: import_dispatch_args_group,
            seed_decl_key_order,
            decl_key_radix_dispatch,
            sort_decl_keys,
            validate_decls,
            mark_decl_namespace_keys,
            decl_type_key_scan,
            decl_value_key_scan,
            scatter_decl_namespace_keys,
            mark_public_decl_keys,
            decl_type_public_scan,
            decl_value_public_scan,
            clear_interface_public_decls,
            map_interface_public_decls,
            count_import_visibility,
            import_visible_type_scan,
            import_visible_value_scan,
            scatter_import_visible_type,
            scatter_import_visible_value,
            import_visible_type_key_radix_dispatch,
            sort_import_visible_type_keys,
            import_visible_value_key_radix_dispatch,
            sort_import_visible_value_keys,
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
            type_aliases,
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
