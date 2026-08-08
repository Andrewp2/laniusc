use super::super::*;

const GENERIC_PARAM_KEY_FIELD_COUNT: u32 = 3;
const GENERIC_PARAM_KEY_MAX_RADIX_STEPS: u32 = 12;
const STRUCT_FIELD_KEY_FIELD_COUNT: u32 = 3;
const STRUCT_FIELD_KEY_MAX_RADIX_STEPS: u32 = 12;

/// Returns the byte width needed for each generic-parameter key field.
pub(in crate::type_checker) fn generic_param_key_radix_bytes(
    param_capacity: u32,
    hir_node_capacity: u32,
) -> u32 {
    let max_key = param_capacity
        .max(hir_node_capacity)
        .saturating_add(LANGUAGE_SYMBOL_COUNT)
        .saturating_add(1)
        .max(1);
    if max_key <= 0xff {
        1
    } else if max_key <= 0xffff {
        2
    } else if max_key <= 0x00ff_ffff {
        3
    } else {
        4
    }
}

/// Returns the even radix step count for sorting generic-parameter keys.
pub(in crate::type_checker) fn generic_param_key_radix_steps(
    param_capacity: u32,
    hir_node_capacity: u32,
) -> u32 {
    let steps = generic_param_key_radix_bytes(param_capacity, hir_node_capacity)
        * GENERIC_PARAM_KEY_FIELD_COUNT;
    let even_steps = if steps % 2 == 0 { steps } else { steps + 1 };
    even_steps.min(GENERIC_PARAM_KEY_MAX_RADIX_STEPS)
}

/// Returns the byte width needed for each struct-field key field.
pub(in crate::type_checker) fn struct_field_key_radix_bytes(
    hir_node_capacity: u32,
    token_capacity: u32,
) -> u32 {
    let max_key = hir_node_capacity
        .max(token_capacity.saturating_add(LANGUAGE_SYMBOL_COUNT))
        .saturating_add(1)
        .max(1);
    if max_key <= 0xff {
        1
    } else if max_key <= 0xffff {
        2
    } else if max_key <= 0x00ff_ffff {
        3
    } else {
        4
    }
}

/// Returns the even radix step count for sorting struct-field keys.
pub(in crate::type_checker) fn struct_field_key_radix_steps(
    hir_node_capacity: u32,
    token_capacity: u32,
) -> u32 {
    let steps = struct_field_key_radix_bytes(hir_node_capacity, token_capacity)
        * STRUCT_FIELD_KEY_FIELD_COUNT;
    let even_steps = if steps % 2 == 0 { steps } else { steps + 1 };
    even_steps.min(STRUCT_FIELD_KEY_MAX_RADIX_STEPS)
}

/// Returns the propagation passes needed to attach generic params to owners.
pub(in crate::type_checker) fn generic_decl_owner_step_count(hir_node_capacity: u32) -> u32 {
    let mut covered_depth = 1u32;
    let mut steps = 0u32;
    let target = hir_node_capacity.max(1);
    while covered_depth < target {
        covered_depth = covered_depth.saturating_mul(2);
        steps = steps.saturating_add(1);
    }
    if steps % 2 == 0 {
        steps
    } else {
        steps.saturating_add(1)
    }
}

/// Builds bind groups for collecting, sorting, and projecting type instances.
pub(in crate::type_checker) fn create_type_instance_bind_groups(
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    passes: &TypeCheckPasses,
    resources: &ResourceMap<'_>,
    token_capacity: u32,
    hir_node_capacity: u32,
) -> Result<TypeInstanceBindGroups> {
    let param_capacity = token_capacity.max(1);
    let param_n_blocks = param_capacity.div_ceil(256).max(1);
    let radix_bytes = generic_param_key_radix_bytes(param_capacity, hir_node_capacity);
    let radix_steps = generic_param_key_radix_steps(param_capacity, hir_node_capacity);
    let owner_steps = generic_decl_owner_step_count(hir_node_capacity);
    // Every compact field row has a distinct source-token anchor, so its
    // capacity is bounded by the token domain rather than the raw parse tree.
    let struct_field_capacity = token_capacity.max(1);
    let struct_field_n_blocks = struct_field_capacity.div_ceil(256).max(1);
    let struct_field_radix_bytes =
        struct_field_key_radix_bytes(struct_field_capacity, token_capacity);
    let struct_field_radix_steps =
        struct_field_key_radix_steps(struct_field_capacity, token_capacity);
    let generic_parameter_sorts = GenericParameterSorts::new(
        device,
        passes,
        resources,
        param_capacity,
        param_n_blocks,
        radix_bytes,
        radix_steps,
    )?;
    let struct_field_radix_params = uniform_from_val(
        device,
        "type_check.type_instances.struct_field_key_radix.dispatch.params",
        &ModuleKeyRadixParams {
            module_capacity: struct_field_capacity,
            reserved: struct_field_radix_bytes,
            n_blocks: struct_field_n_blocks,
            key_step: 0,
        },
    );
    let struct_field_key_radix_dispatch = resources.reflected_bind_group_with_overrides(
        device,
        "type_check.type_instances.struct_field_key_radix_dispatch",
        &passes.kernel("type_checker/type/instances/02a_struct_field_radix_dispatch"),
        &[
            ("gParams", struct_field_radix_params.as_entire_binding()),
            (
                "compact_field_count",
                resources["compact_field_count"].clone(),
            ),
            (
                "radix_dispatch_args",
                resources["struct_field_key_radix_dispatch_args"].clone(),
            ),
        ],
    )?;

    let struct_field_key_radix_dispatch_args =
        typed_buffer_from_resources(resources, "struct_field_key_radix_dispatch_args")?;
    let sort_struct_fields = RadixSortOperation::new_hierarchical(
        device,
        passes,
        resources,
        compiler_graph::STRUCT_FIELD_RADIX_SORT.plan(
            struct_field_radix_steps,
            HierarchicalRadixSortDispatch {
                rows: &struct_field_key_radix_dispatch_args,
                bucket_work_items: struct_field_n_blocks
                    .div_ceil(256)
                    .saturating_mul(NAME_RADIX_BUCKETS)
                    .saturating_mul(256),
                bucket_chunk_work_items: NAME_RADIX_BUCKETS.saturating_mul(256),
                bucket_count: 256,
            },
        ),
        |key_step| StructFieldKeyRadixParams {
            hir_node_capacity: struct_field_capacity,
            token_capacity,
            n_blocks: struct_field_n_blocks,
            key_step,
            radix_bytes: struct_field_radix_bytes,
            reserved0: 0,
            reserved1: 0,
            reserved2: 0,
        },
    )?;

    let mut propagate_generic_decl_owner = Vec::with_capacity(owner_steps as usize);
    for step in 0..owner_steps {
        let read_owner = if step % 2 == 0 {
            resources["generic_decl_owner_by_node_a"].clone()
        } else {
            resources["generic_decl_owner_by_node_b"].clone()
        };
        let read_jump = if step % 2 == 0 {
            resources["generic_decl_parent_jump_a"].clone()
        } else {
            resources["generic_decl_parent_jump_b"].clone()
        };
        let read_bound_list = if step % 2 == 0 {
            resources["predicate_bound_list_by_node_a"].clone()
        } else {
            resources["predicate_bound_list_by_node_b"].clone()
        };
        let write_owner = if step % 2 == 0 {
            resources["generic_decl_owner_by_node_b"].clone()
        } else {
            resources["generic_decl_owner_by_node_a"].clone()
        };
        let write_jump = if step % 2 == 0 {
            resources["generic_decl_parent_jump_b"].clone()
        } else {
            resources["generic_decl_parent_jump_a"].clone()
        };
        let write_bound_list = if step % 2 == 0 {
            resources["predicate_bound_list_by_node_b"].clone()
        } else {
            resources["predicate_bound_list_by_node_a"].clone()
        };
        propagate_generic_decl_owner.push(resources.reflected_bind_group_with_overrides(
            device,
            "type_check_type_instances_00a1_propagate_generic_decl_owner",
            &passes.kernel("type_checker/type/instances/00a1_propagate_generic_decl_owner"),
            &[
                ("gParams", resources["gParams"].clone()),
                ("compact_hir_count", resources["compact_hir_count"].clone()),
                ("generic_decl_owner_by_node_in", read_owner),
                ("predicate_bound_list_by_node_in", read_bound_list),
                ("generic_decl_parent_jump_in", read_jump),
                ("generic_decl_owner_by_node_out", write_owner),
                ("predicate_bound_list_by_node_out", write_bound_list),
                ("generic_decl_parent_jump_out", write_jump),
            ],
        )?);
    }

    let type_instance_arg_row_scan = PrefixScanOperation::from_spec(
        device,
        passes,
        resources,
        compiler_graph::TYPE_INSTANCE_ARG_ROW_SCAN,
    )?;
    // These scans are recorded before aggregate comparison begins, so the
    // aggregate scan workspace can safely serve both relations without
    // increasing resident scratch memory.
    Ok(TypeInstanceBindGroups {
        clear: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_clear",
            &passes.kernel("type_checker/type/instances/00_clear"),
            resources,
        )?,
        mark_generic_param_records: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_mark_generic_param_records",
            &passes.kernel("type_checker/type/instances/00a_mark_generic_param_records"),
            resources,
        )?,
        propagate_generic_decl_owner,
        type_instance_arg_row_scan,
        decl_generic_params: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_decl_generic_params",
            &passes.kernel("type_checker/type/instances/00b_decl_generic_params"),
            resources,
        )?,
        generic_parameter_sorts,
        generic_param_use_slots: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_generic_param_use_slots",
            &passes.kernel("type_checker/type/instances/00e_generic_param_use_slots"),
            resources,
        )?,
        seed_struct_field_keys: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_seed_struct_field_keys",
            &passes.kernel("type_checker/type/instances/02_seed_struct_field_keys"),
            resources,
        )?,
        struct_field_key_radix_dispatch,
        sort_struct_fields,
        collect: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect",
            &passes.kernel("type_checker/type/instances/01_collect"),
            resources,
        )?,
        collect_named: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_named",
            &passes.kernel("type_checker/type/instances/01b_collect_named_instances"),
            resources,
        )?,
        collect_aggregate_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_aggregate_refs",
            &passes.kernel("type_checker/type/instances/01c_collect_aggregate_refs"),
            resources,
        )?,
        collect_aggregate_details: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_aggregate_details",
            &passes.kernel("type_checker/type/instances/01d_collect_aggregate_details"),
            resources,
        )?,
        collect_named_arg_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_named_arg_refs",
            &passes.kernel("type_checker/type/instances/01e_collect_named_arg_refs"),
            resources,
        )?,
        hash_arg_rows: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_hash_arg_rows",
            &passes.kernel("type_checker/type/instances/01g_hash_arg_rows"),
            resources,
        )?,
        clear_semantic_type_rows: Box::new(reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_clear_semantic_type_rows",
            &passes.kernel("type_checker/type/instances/01h_clear_semantic_type_rows"),
            resources,
        )?),
        semantic_type_rows: Box::new(CompactionOperation::indirect(
            device,
            graph,
            resources,
            passes,
            TYPE_SEMANTIC_COMPACTION,
            &typed_buffer_from_resources(resources, "hir_active_dispatch_args")?,
        )?),
        decl_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_decl_refs",
            &passes.kernel("type_checker/type/instances/01f_decl_refs"),
            resources,
        )?,
        member_receivers: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_member_receivers",
            &passes.kernel("type_checker/type/instances/03a_member_receivers"),
            resources,
        )?,
        member_results: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_member_results",
            &passes.kernel("type_checker/type/instances/03_member_results"),
            resources,
        )?,
        member_substitute: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_member_substitute",
            &passes.kernel("type_checker/type/instances/03b_member_substitute"),
            resources,
        )?,
        struct_init_clear: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_clear",
            &passes.kernel("type_checker/type/instances/04a_struct_init_clear"),
            resources,
        )?,
        struct_init_contexts: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_contexts",
            &passes.kernel("type_checker/type/instances/04a2_struct_init_contexts"),
            resources,
        )?,
        struct_init_fields: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_fields",
            &passes.kernel("type_checker/type/instances/04_struct_init_fields"),
            resources,
        )?,
        struct_init_substitute: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_substitute",
            &passes.kernel("type_checker/type/instances/04b_struct_init_substitute"),
            resources,
        )?,
        array_return_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_array_return_refs",
            &passes.kernel("type_checker/type/instances/05_array_return_refs"),
            resources,
        )?,
        array_literal_return_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_array_literal_return_refs",
            &passes.kernel("type_checker/type/instances/05b_array_literal_return_refs"),
            resources,
        )?,
        validate_aggregate_access: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_validate_aggregate_access",
            &passes.kernel("type_checker/type/instances/08_validate_aggregate_access"),
            resources,
        )?,
    })
}
