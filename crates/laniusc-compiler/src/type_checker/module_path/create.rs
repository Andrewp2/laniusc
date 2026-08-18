use super::{
    super::*,
    bind_helpers::create_pair_max_dispatch,
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
    graph: &compiler_graph::TypeCheckCompilerGraph,
    device: &wgpu::Device,
    inputs: CreateInputs<'_>,
    resources: &ResourceMap<'_>,
) -> Result<State> {
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
        ..
    } = layout;
    let buffers = Buffers::new(graph, layout, &inputs)?;
    let resource_buffers = buffers.clone();
    let mut module_resources = resources.clone();
    resource_buffers.register_resources(&mut module_resources);
    let PathSequences {
        clear_state: clear_path_state,
        dispatch_params: path_prefix_dispatch_params,
        dispatch_args: path_prefix_dispatch_args,
        initial_table_clear: path_prefix_initial_table_clear,
        rounds: path_prefix_rounds,
        finalize: path_prefix_finalize,
    } = create_path_sequences(passes, graph, device, &inputs, &buffers, &module_resources)?;
    let dependency_visibility = dependency_visibility::create(
        passes,
        device,
        graph,
        layout,
        &inputs,
        &buffers,
        &module_resources,
    )?;
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
    } = create_record_discovery(
        passes,
        graph,
        device,
        layout,
        &inputs,
        &buffers,
        &module_resources,
    )?;
    let ModuleIndex {
        scatter_module_records,
        clear_module_lookup,
        build_module_keys,
        module_dispatch_params,
        module_dispatch,
        validate_modules,
        clear_dependency_module_lookup,
        build_dependency_module_lookup,
        resolve_dependency_imports,
        clear_dependency_module_lookup_call_collection,
        build_dependency_module_lookup_call_collection,
        resolve_dependency_imports_call_collection,
        scatter_import_records,
        resolve_imports,
        clear_import_edge_set,
        build_import_edge_set,
        validate_import_cycles,
        module_lookup_params,
        import_resolve_params,
        mut retained_params,
    } = create_module_index(
        passes,
        graph,
        device,
        layout,
        &inputs,
        &buffers,
        &module_resources,
    )?;
    let ProjectionBindGroups {
        clear_type_path_types,
        project_type_paths,
        project_type_paths_after_aliases,
        project_type_paths_after_projected_aliases,
        project_type_paths_after_alias_equivalence,
        validate_type_paths,
        type_aliases,
        project_type_instances,
        mark_value_call_paths,
        project_value_paths,
        consume_value_calls,
        consume_value_calls_after_methods,
        mirror_value_call_leaf,
        mirror_value_call_leaf_after_row_args,
        mirror_value_call_leaf_after_methods,
        mirror_value_call_leaf_after_method_row_args,
        consume_value_consts,
        consume_value_enum_units,
        consume_value_enum_calls,
        validate_value_enum_call_payloads,
        finalize_value_enum_calls,
        bind_match_patterns,
        type_match_payloads,
        type_match_exprs,
    } = create_projection_bind_groups(passes, device, graph, &inputs, &module_resources)?;
    let Buffers {
        record_scan_local_prefix,
        record_scan_block_sum,
        record_scan_prefix_a,
        record_scan_prefix_b,
        import_count_out,
        decl_count_out,
        module_dispatch_args,
        decl_key_radix_dispatch_args,
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
        decl_lookup_state,
        import_visible_type_count,
        import_visible_value_count,
        import_visible_type_prefix,
        import_visible_value_prefix,
        import_visible_type_count_out,
        import_visible_value_count_out,
        import_visible_type_key_module_id,
        import_visible_type_key_name_id,
        import_visible_type_key_to_decl_id,
        import_visible_type_lookup_state,
        import_visible_type_status,
        import_visible_value_key_module_id,
        import_visible_value_key_name_id,
        import_visible_value_key_to_decl_id,
        import_visible_value_lookup_state,
        import_visible_value_status,
        import_visible_validate_dispatch_args,
        resolved_type_decl,
        resolved_value_decl,
        resolved_type_status,
        resolved_value_status,
        path_prefix_id_a,
        path_dispatch_args,
        import_dispatch_args,
        ..
    } = resource_buffers.clone();
    let CreateInputs {
        params,
        token_capacity,
        hir_node_capacity,
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
    let mut clear_file_map_resources = module_resources.clone();
    clear_file_map_resources.buffer("gParams", &decl_module_params);
    let clear_file_module_map = ComputeOperation::direct_spec(
        device,
        graph,
        &clear_file_map_resources,
        passes,
        FILE_MODULE_MAP_CLEAR,
        n_blocks.saturating_mul(256).max(1),
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
    let mut build_file_map_resources = module_resources.clone();
    build_file_map_resources.buffer("gParams", &build_file_module_map_params);
    let build_file_module_map = ComputeOperation::indirect_spec(
        device,
        graph,
        &build_file_map_resources,
        passes,
        FILE_MODULE_MAP_BUILD,
        &module_dispatch_args,
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
    let mut attach_resources = module_resources.clone();
    attach_resources.buffer("gParams", &attach_record_modules_params);
    let attach_record_modules = ComputeOperation::direct_spec(
        device,
        graph,
        &attach_resources,
        passes,
        ATTACH_RECORD_MODULES,
        record_n_blocks.saturating_mul(256).max(1),
    )?;

    let (decl_key_radix_widths, decl_key_radix_steps) =
        decl_key_radix_layout(token_capacity, module_capacity_u32);
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
    let mut decl_key_dispatch_resources = module_resources.clone();
    decl_key_dispatch_resources.buffer("gParams", &decl_key_radix_dispatch_params);
    let decl_key_radix_dispatch = ComputeOperation::direct_spec(
        device,
        graph,
        &decl_key_dispatch_resources,
        passes,
        DECL_KEY_RADIX_DISPATCH,
        1,
    )?;

    let sort_decl_keys = compiler_graph::MODULE_DECL_KEY_RADIX_SORT.operation(
        device,
        passes,
        &module_resources,
        record_capacity_u32,
        MODULE_RELATION_SMALL_SORT_CAPACITY,
        decl_key_radix_steps,
        RadixSortDispatch {
            small: RadixDispatchDomain::Indirect(&decl_key_radix_dispatch_args),
            rows: RadixDispatchDomain::Indirect(&decl_key_radix_dispatch_args),
            bucket_prefix: RadixDispatchDomain::Direct(RADIX_U8_BUCKET_COUNT.saturating_mul(256)),
            bucket_bases: RadixDispatchDomain::Direct(256),
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
    let mut validate_decl_resources = module_resources.clone();
    validate_decl_resources.buffer("gParams", &validate_decl_params);
    let validate_decls = ComputeOperation::indirect_spec(
        device,
        graph,
        &validate_decl_resources,
        passes,
        DECLS_VALIDATE,
        &decl_key_radix_dispatch_args,
    )?;

    let mut namespace_resources = module_resources.clone();
    namespace_resources.buffer("gParams", &validate_decl_params);
    namespace_resources.alias("sorted_decl_key_order", "decl_key_to_decl_id")?;
    let mark_decl_namespace_keys = ComputeOperation::indirect_spec(
        device,
        graph,
        &namespace_resources,
        passes,
        DECL_NAMESPACE_MARK,
        &decl_key_radix_dispatch_args,
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

    let mut scan_resources = module_resources.clone();
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

    let scatter_decl_namespace_keys = ComputeOperation::indirect_spec(
        device,
        graph,
        &namespace_resources,
        passes,
        DECL_NAMESPACE_SCATTER,
        &decl_key_radix_dispatch_args,
    )?;

    let lookup_table_capacity = record_capacity_u32.saturating_mul(2);
    let decl_lookup_params = uniform_from_val(
        device,
        "type_check.modules.decl_lookup.params",
        &ModuleKeyRadixParams {
            module_capacity: record_capacity_u32,
            reserved: 0,
            n_blocks: record_n_blocks,
            key_step: 0,
        },
    );
    let mut lookup_resources = module_resources.clone();
    lookup_resources.buffer("gParams", &decl_lookup_params);
    lookup_resources.buffer("decl_lookup_state", &decl_lookup_state);
    let decl_lookup = ExactLookupOperation::new(
        device,
        graph,
        &lookup_resources,
        passes,
        DECL_LOOKUP_CLEAR,
        DECL_LOOKUP_BUILD,
        lookup_table_capacity,
        &decl_key_radix_dispatch_args,
    )?;

    let mut duplicate_resources = module_resources.clone();
    duplicate_resources.buffer("gParams", &decl_lookup_params);
    let validate_decl_duplicates = ComputeOperation::indirect_spec(
        device,
        graph,
        &duplicate_resources,
        passes,
        DECL_DUPLICATES_VALIDATE,
        &decl_key_radix_dispatch_args,
    )?;

    // Declaration validation status/duplicate buffers are dead once
    // namespace flags have been marked. Reuse them for public declaration
    // prefixes so the compact type/value lookup prefix buffers remain intact.
    let decl_type_public_prefix = decl_status.clone();
    let decl_value_public_prefix = decl_duplicate_of.clone();
    let mut public_resources = module_resources.clone();
    public_resources.buffer("decl_type_public_flag", &decl_type_key_flag);
    public_resources.buffer("decl_value_public_flag", &decl_value_key_flag);
    public_resources.buffer("decl_type_public_prefix", &decl_type_public_prefix);
    public_resources.buffer("decl_value_public_prefix", &decl_value_public_prefix);
    let mut public_mark_resources = public_resources.clone();
    public_mark_resources.buffer("gParams", &validate_decl_params);
    let mark_public_decl_keys = ComputeOperation::indirect_spec(
        device,
        graph,
        &public_mark_resources,
        passes,
        DECL_PUBLIC_MARK,
        &decl_key_radix_dispatch_args,
    )?;

    let (decl_type_public_scan, decl_value_public_scan) = PrefixScanOperation::from_pair_spec(
        device,
        passes,
        &scan_resources,
        compiler_graph::DECL_PUBLIC_SCAN,
    )?;
    let mut interface_public_resources = public_resources.clone();
    interface_public_resources.buffer("gParams", &validate_decl_params);
    let interface_decl_capacity =
        u32::try_from(resource_buffers.interface_public_decl_local_id.count).unwrap_or(u32::MAX);
    let clear_interface_public_decls = ComputeOperation::direct_spec(
        device,
        graph,
        &interface_public_resources,
        passes,
        INTERFACE_PUBLIC_DECLS_CLEAR,
        interface_decl_capacity,
    )?;
    let map_interface_public_decls = ComputeOperation::indirect_spec(
        device,
        graph,
        &interface_public_resources,
        passes,
        INTERFACE_PUBLIC_DECLS_MAP,
        &decl_key_radix_dispatch_args,
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
    let mut import_visibility_resources = public_resources.clone();
    import_visibility_resources.buffer("gParams", &import_visibility_params);
    let count_import_visibility = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_visibility_resources,
        passes,
        IMPORT_VISIBILITY_COUNT,
        &import_dispatch_args,
    )?;

    let (import_visible_type_scan, import_visible_value_scan) =
        PrefixScanOperation::from_pair_spec(
            device,
            passes,
            &scan_resources,
            compiler_graph::IMPORT_VISIBLE_SCAN,
        )?;

    let mut import_visible_type_resources = public_resources.clone();
    import_visible_type_resources.buffer("import_visible_count", &import_visible_type_count);
    import_visible_type_resources
        .buffer("import_visible_count_out", &import_visible_type_count_out);
    import_visible_type_resources.buffer("import_visible_prefix", &import_visible_type_prefix);
    import_visible_type_resources.buffer("decl_key_count_out", &decl_type_key_count_out);
    import_visible_type_resources.buffer("decl_key_to_decl_id", &decl_type_key_to_decl_id);
    import_visible_type_resources.buffer("decl_public_flag", &decl_type_key_flag);
    import_visible_type_resources.buffer("decl_public_prefix", &decl_type_public_prefix);
    import_visible_type_resources.buffer(
        "import_visible_key_module_id",
        &import_visible_type_key_module_id,
    );
    import_visible_type_resources.buffer(
        "import_visible_key_name_id",
        &import_visible_type_key_name_id,
    );
    import_visible_type_resources.buffer(
        "import_visible_key_to_decl_id",
        &import_visible_type_key_to_decl_id,
    );
    import_visible_type_resources.buffer(
        "import_visible_lookup_state",
        &import_visible_type_lookup_state,
    );
    import_visible_type_resources.buffer("gParams", &import_visibility_params);
    let scatter_import_visible_type = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_visible_type_resources,
        passes,
        IMPORT_VISIBLE_TYPE_SCATTER,
        &import_visible_validate_dispatch_args,
    )?;

    let mut import_visible_value_resources = public_resources.clone();
    import_visible_value_resources.buffer("import_visible_count", &import_visible_value_count);
    import_visible_value_resources
        .buffer("import_visible_count_out", &import_visible_value_count_out);
    import_visible_value_resources.buffer("import_visible_prefix", &import_visible_value_prefix);
    import_visible_value_resources.buffer("decl_key_count_out", &decl_value_key_count_out);
    import_visible_value_resources.buffer("decl_key_to_decl_id", &decl_value_key_to_decl_id);
    import_visible_value_resources.buffer("decl_public_flag", &decl_value_key_flag);
    import_visible_value_resources.buffer("decl_public_prefix", &decl_value_public_prefix);
    import_visible_value_resources.buffer(
        "import_visible_key_module_id",
        &import_visible_value_key_module_id,
    );
    import_visible_value_resources.buffer(
        "import_visible_key_name_id",
        &import_visible_value_key_name_id,
    );
    import_visible_value_resources.buffer(
        "import_visible_key_to_decl_id",
        &import_visible_value_key_to_decl_id,
    );
    import_visible_value_resources.buffer(
        "import_visible_lookup_state",
        &import_visible_value_lookup_state,
    );
    import_visible_value_resources.buffer("gParams", &import_visibility_params);
    let scatter_import_visible_value = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_visible_value_resources,
        passes,
        IMPORT_VISIBLE_VALUE_SCATTER,
        &import_visible_validate_dispatch_args,
    )?;

    let import_lookup_capacity = import_visible_capacity_u32.saturating_mul(2);
    let clear_import_visible_type_lookup = ComputeOperation::direct_spec(
        device,
        graph,
        &import_visible_type_resources,
        passes,
        IMPORT_VISIBLE_TYPE_LOOKUP_CLEAR,
        import_lookup_capacity,
    )?;
    let clear_import_visible_value_lookup = ComputeOperation::direct_spec(
        device,
        graph,
        &import_visible_value_resources,
        passes,
        IMPORT_VISIBLE_VALUE_LOOKUP_CLEAR,
        import_lookup_capacity,
    )?;

    let build_import_visible_type_key_table = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_visible_type_resources,
        passes,
        IMPORT_VISIBLE_TYPE_LOOKUP_BUILD,
        &import_visible_validate_dispatch_args,
    )?;

    let build_import_visible_value_key_table = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_visible_value_resources,
        passes,
        IMPORT_VISIBLE_VALUE_LOOKUP_BUILD,
        &import_visible_validate_dispatch_args,
    )?;

    let (import_visible_validate_dispatch_params, import_visible_validate_dispatch_args_group) =
        create_pair_max_dispatch(
            device,
            graph,
            passes,
            &module_resources,
            IMPORT_VISIBLE_DISPATCH,
            "type_check.modules.import_visible_validate_dispatch.params",
            import_visible_capacity_u32,
            import_visible_capacity_u32,
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
    let initialize_import_visible_keys = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_visibility_resources,
        passes,
        IMPORT_VISIBLE_STATUS_INITIALIZE,
        &import_visible_validate_dispatch_args,
    )?;
    let mut import_visibility_mark_resources = module_resources.clone();
    import_visibility_mark_resources.buffer("gParams", &import_visibility_mark_params);
    let validate_import_visible_keys = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_visibility_mark_resources,
        passes,
        IMPORT_VISIBLE_AMBIGUITY_VALIDATE,
        &import_visible_validate_dispatch_args,
    )?;

    import_visible_type_resources.buffer("decl_key_count_out", &decl_type_key_count_out);
    import_visible_type_resources.buffer("decl_key_to_decl_id", &decl_type_key_to_decl_id);
    import_visible_type_resources.buffer("import_visible_status", &import_visible_type_status);
    import_visible_type_resources.buffer("resolved_decl", &resolved_type_decl);
    import_visible_type_resources.buffer("resolved_status", &resolved_type_status);
    import_visible_type_resources.buffer("path_prefix_id", &path_prefix_id_a);
    import_visible_type_resources.buffer(
        "module_by_canonical_id",
        &resource_buffers.module_by_canonical_id,
    );
    import_visible_value_resources.buffer("decl_key_count_out", &decl_value_key_count_out);
    import_visible_value_resources.buffer("decl_key_to_decl_id", &decl_value_key_to_decl_id);
    import_visible_value_resources.buffer("import_visible_status", &import_visible_value_status);
    import_visible_value_resources.buffer("resolved_decl", &resolved_value_decl);
    import_visible_value_resources.buffer("resolved_status", &resolved_value_status);
    import_visible_value_resources.buffer("path_prefix_id", &path_prefix_id_a);
    import_visible_value_resources.buffer(
        "module_by_canonical_id",
        &resource_buffers.module_by_canonical_id,
    );

    let resolve_local_type_paths = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_visible_type_resources,
        passes,
        RESOLVE_LOCAL_TYPE_PATHS,
        &path_dispatch_args,
    )?;

    let mut resolve_local_value_resources = import_visible_value_resources.clone();
    resolve_local_value_resources.buffer("gParams", &import_visibility_mark_params);
    let resolve_local_value_paths = ComputeOperation::indirect_spec(
        device,
        graph,
        &resolve_local_value_resources,
        passes,
        RESOLVE_LOCAL_VALUE_PATHS,
        &path_dispatch_args,
    )?;

    let resolve_imported_type_paths = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_visible_type_resources,
        passes,
        RESOLVE_IMPORTED_TYPE_PATHS,
        &path_dispatch_args,
    )?;

    let resolve_imported_value_paths = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_visible_value_resources,
        passes,
        RESOLVE_IMPORTED_VALUE_PATHS,
        &path_dispatch_args,
    )?;

    let resolve_qualified_path_params = uniform_from_val(
        device,
        "type_check.modules.resolve_qualified_paths.params",
        &QualifiedPathResolveParams {
            record_capacity: record_capacity_u32,
            path_segment_capacity: token_capacity,
            module_capacity: module_capacity_u32,
            reserved: 0,
        },
    );
    let resolve_qualified_value_path_params = uniform_from_val(
        device,
        "type_check.modules.resolve_qualified_value_paths.params",
        &QualifiedPathResolveParams {
            record_capacity: record_capacity_u32,
            path_segment_capacity: token_capacity,
            module_capacity: module_capacity_u32,
            reserved: 1,
        },
    );
    let mut resolve_qualified_type_resources = import_visible_type_resources.clone();
    resolve_qualified_type_resources.buffer("gParams", &resolve_qualified_path_params);
    let resolve_qualified_type_paths = ComputeOperation::indirect_spec(
        device,
        graph,
        &resolve_qualified_type_resources,
        passes,
        RESOLVE_QUALIFIED_TYPE_PATHS,
        &path_dispatch_args,
    )?;

    let mut resolve_qualified_value_resources = import_visible_value_resources.clone();
    resolve_qualified_value_resources.buffer("gParams", &resolve_qualified_value_path_params);
    let resolve_qualified_value_paths = ComputeOperation::indirect_spec(
        device,
        graph,
        &resolve_qualified_value_resources,
        passes,
        RESOLVE_QUALIFIED_VALUE_PATHS,
        &path_dispatch_args,
    )?;

    let mut decl_core_resources = module_resources.clone();
    decl_core_resources.buffer("gParams", params);
    let scatter_decl_core_records = ComputeOperation::indirect_spec(
        device,
        graph,
        &decl_core_resources,
        passes,
        DECL_RECORDS_SCATTER,
        inputs.hir_active_dispatch_args,
    )?;

    let append_variant_decl_count = ComputeOperation::direct_spec(
        device,
        graph,
        &decl_core_resources,
        passes,
        VARIANT_DECL_COUNT_APPEND,
        1,
    )?;

    let clear_decl_lookup = ComputeOperation::direct_spec(
        device,
        graph,
        &decl_core_resources,
        passes,
        DECL_RECORD_LOOKUP_CLEAR,
        token_capacity.saturating_mul(2).max(1),
    )?;

    let scatter_decl_span_records = ComputeOperation::indirect_spec(
        device,
        graph,
        &decl_core_resources,
        passes,
        DECL_SPAN_RECORDS_SCATTER,
        inputs.hir_active_dispatch_args,
    )?;

    let scatter_variant_decl_records = ComputeOperation::direct_spec(
        device,
        graph,
        &decl_core_resources,
        passes,
        VARIANT_DECL_RECORDS_SCATTER,
        n_blocks.saturating_mul(256).max(1),
    )?;
    retained_params.push(decl_module_params);
    retained_params.push(attach_record_modules_params);
    retained_params.push(build_file_module_map_params);
    retained_params.push(validate_decl_params);
    retained_params.push(decl_lookup_params);
    retained_params.push(import_visibility_params);
    retained_params.push(import_visibility_mark_params);
    Ok(State {
        resources: buffers,
        dependency_interfaces: inputs.dependency_interfaces.cloned(),
        dependency_visibility,
        _extract_module_record_flag_params: extract_module_record_flag_params,
        _extract_import_record_flag_params: extract_import_record_flag_params,
        _extract_decl_record_flag_params: extract_decl_record_flag_params,
        _path_dispatch_params: path_dispatch_params,
        _path_prefix_dispatch_params: path_prefix_dispatch_params,
        _import_dispatch_params: import_dispatch_params,
        _import_visible_validate_dispatch_params: import_visible_validate_dispatch_params,
        _module_dispatch_params: module_dispatch_params,
        _module_lookup_params: module_lookup_params,
        _import_resolve_params: import_resolve_params,
        _qualified_path_resolve_params: [
            resolve_qualified_path_params,
            resolve_qualified_value_path_params,
        ],
        _decl_key_radix_dispatch_params: decl_key_radix_dispatch_params,
        _retained_params: retained_params,
        bind_groups: BindGroups {
            mark_records,
            scatter_paths,
            count_path_segments,
            scatter_path_segments,
            clear_path_state,
            path_prefix_dispatch_args,
            path_prefix_initial_table_clear,
            path_prefix_rounds,
            path_prefix_finalize,
            module_records: CompactionOperation::new(
                extract_module_record_flag,
                module_scan,
                scatter_module_records,
            ),
            import_records: CompactionOperation::new(
                extract_import_record_flag,
                import_scan,
                scatter_import_records,
            ),
            decl_records: CompactionOperation::new(
                extract_decl_record_flag,
                decl_scan,
                scatter_decl_core_records,
            ),
            append_variant_decl_count,
            scatter_variant_decl_records,
            clear_decl_lookup,
            scatter_decl_span_records,
            clear_module_lookup,
            build_module_keys,
            module_dispatch,
            validate_modules,
            clear_dependency_module_lookup,
            build_dependency_module_lookup,
            resolve_dependency_imports,
            clear_dependency_module_lookup_call_collection,
            build_dependency_module_lookup_call_collection,
            resolve_dependency_imports_call_collection,
            resolve_imports,
            clear_import_edge_set,
            build_import_edge_set,
            validate_import_cycles,
            clear_file_module_map,
            build_file_module_map,
            attach_record_modules,
            import_dispatch_args: import_dispatch_args_group,
            decl_key_radix_dispatch,
            sort_decl_keys,
            validate_decls,
            mark_decl_namespace_keys,
            decl_type_key_scan,
            decl_value_key_scan,
            scatter_decl_namespace_keys,
            decl_lookup,
            validate_decl_duplicates,
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
            clear_import_visible_type_lookup,
            clear_import_visible_value_lookup,
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
            project_type_paths_after_aliases,
            project_type_paths_after_projected_aliases,
            project_type_paths_after_alias_equivalence,
            validate_type_paths,
            type_aliases,
            project_type_instances,
            mark_value_call_paths,
            project_value_paths,
            consume_value_calls,
            consume_value_calls_after_methods,
            mirror_value_call_leaf,
            mirror_value_call_leaf_after_row_args,
            mirror_value_call_leaf_after_methods,
            mirror_value_call_leaf_after_method_row_args,
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
