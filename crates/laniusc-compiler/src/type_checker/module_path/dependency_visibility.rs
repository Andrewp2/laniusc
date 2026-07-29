use super::{super::*, buffers::Buffers, inputs::CreateInputs, layout::Layout};

/// Per-unit projection of immutable dependency declarations into the local
/// import graph. Local and dependency declaration identities intentionally use
/// separate outputs so downstream passes cannot interpret a persisted identity
/// as a local HIR row.
#[allow(dead_code)]
pub(in crate::type_checker) struct DependencyVisibilityState {
    pub(in crate::type_checker) visible_capacity: u32,
    pub(in crate::type_checker) lookup_capacity: u32,
    pub(in crate::type_checker) canonical_type_count: u32,
    pub(in crate::type_checker) canonical_declaration_count: u32,
    pub(in crate::type_checker) canonical_member_count: u32,
    pub(in crate::type_checker) call_compare_scan_input: LaniusBuffer<u32>,
    pub(in crate::type_checker) call_compare_dispatch_args: LaniusBuffer<u32>,
    pub(in crate::type_checker) canonical_type_subtree: Box<DependencyCanonicalTypeSubtreeState>,
    _retained_buffers: Box<[LaniusBuffer<u32>]>,
    pub(in crate::type_checker) canonical_type_jump_rounds: u32,
    pub(in crate::type_checker) scan: PrefixScanOperation,
    pub(in crate::type_checker) call_compare_scan: PrefixScanOperation,
    pub(in crate::type_checker) count_group: wgpu::BindGroup,
    pub(in crate::type_checker) scatter_group: wgpu::BindGroup,
    pub(in crate::type_checker) clear_lookup_group: wgpu::BindGroup,
    pub(in crate::type_checker) build_lookup_group: wgpu::BindGroup,
    pub(in crate::type_checker) resolve_type_group: wgpu::BindGroup,
    pub(in crate::type_checker) resolve_value_group: wgpu::BindGroup,
    pub(in crate::type_checker) project_calls_group: wgpu::BindGroup,
    pub(in crate::type_checker) project_call_params_group: wgpu::BindGroup,
    pub(in crate::type_checker) scatter_call_params_group: wgpu::BindGroup,
    pub(in crate::type_checker) validate_call_args_group: wgpu::BindGroup,
    pub(in crate::type_checker) validate_call_results_group: wgpu::BindGroup,
    pub(in crate::type_checker) validate_call_type_args_group: wgpu::BindGroup,
    pub(in crate::type_checker) call_compare_dispatch_group: wgpu::BindGroup,
    pub(in crate::type_checker) init_canonical_type_roots_group: wgpu::BindGroup,
    pub(in crate::type_checker) jump_canonical_type_roots_a_to_b_group: wgpu::BindGroup,
    pub(in crate::type_checker) jump_canonical_type_roots_b_to_a_group: wgpu::BindGroup,
    pub(in crate::type_checker) project_types_group: wgpu::BindGroup,
    pub(in crate::type_checker) clear_declaration_generic_arity_group: wgpu::BindGroup,
    pub(in crate::type_checker) count_declaration_generic_arity_group: wgpu::BindGroup,
    pub(in crate::type_checker) project_type_instances_group: wgpu::BindGroup,
    pub(in crate::type_checker) _params: LaniusBuffer<DependencyInterfaceVisibilityParams>,
    pub(in crate::type_checker) _type_params: LaniusBuffer<DependencyInterfaceVisibilityParams>,
    pub(in crate::type_checker) _value_params: LaniusBuffer<DependencyInterfaceVisibilityParams>,
    pub(in crate::type_checker) _canonical_type_params: LaniusBuffer<DependencyCanonicalTypeParams>,
    pub(in crate::type_checker) _call_compare_dispatch_params: LaniusBuffer<CountDispatchParams>,
}

#[allow(dead_code)]
pub(in crate::type_checker) struct DependencyCanonicalTypeSubtreeState {
    pub(in crate::type_checker) init_group: wgpu::BindGroup,
    pub(in crate::type_checker) jump_a_to_b_group: wgpu::BindGroup,
    pub(in crate::type_checker) jump_b_to_a_group: wgpu::BindGroup,
}

pub(in crate::type_checker) fn create(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    layout: Layout,
    inputs: &CreateInputs<'_>,
    buffers: &Buffers,
    resources: &ResourceMap<'_>,
) -> Result<Option<Box<DependencyVisibilityState>>> {
    let Some(dependencies) = inputs.dependency_interfaces else {
        return Ok(None);
    };
    let import_capacity = layout.import_record_capacity_u32.max(1);
    // Imported public declarations are not bounded by the importing unit's
    // token count. A small entry module can import a large persisted interface,
    // so retain enough rows for every declaration in the dependency batch.
    let visible_capacity = inputs
        .token_capacity
        .max(dependencies.declaration_count)
        .max(1);
    let lookup_capacity = visible_capacity
        .checked_mul(2)
        .and_then(u32::checked_next_power_of_two)
        .ok_or_else(|| anyhow::anyhow!("dependency visibility lookup capacity exceeds u32"))?;
    let path_capacity = layout.record_capacity_u32.max(1);

    let params_value = DependencyInterfaceVisibilityParams {
        declaration_count: dependencies.declaration_count,
        import_capacity,
        visible_capacity,
        lookup_capacity,
        source_len: inputs.source_len,
        path_capacity,
        namespace: 0,
        hir_capacity: inputs.hir_node_capacity.max(1),
    };
    let params = uniform_from_val(
        device,
        "type_check.dependencies.visibility.params",
        &params_value,
    );
    let type_params = uniform_from_val(
        device,
        "type_check.dependencies.visibility.type_params",
        &DependencyInterfaceVisibilityParams {
            namespace: 3,
            ..params_value
        },
    );
    let value_params = uniform_from_val(
        device,
        "type_check.dependencies.visibility.value_params",
        &DependencyInterfaceVisibilityParams {
            namespace: 2,
            ..params_value
        },
    );
    let canonical_type_params = uniform_from_val(
        device,
        "type_check.dependencies.canonical_type.params",
        &DependencyCanonicalTypeParams {
            type_count: dependencies.type_count,
            declaration_count: dependencies.declaration_count,
            member_count: dependencies.member_count,
            path_capacity,
            token_capacity: inputs.token_capacity.max(1),
        },
    );

    let count = typed_storage_u32_rw(
        device,
        "type_check.dependencies.visible.count",
        import_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let prefix = typed_storage_u32_rw(
        device,
        "type_check.dependencies.visible.prefix",
        import_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let total = typed_storage_u32_rw(
        device,
        "type_check.dependencies.visible.total",
        1,
        wgpu::BufferUsages::empty(),
    );
    let owner_module = typed_storage_u32_fill_rw(
        device,
        "type_check.dependencies.visible.owner_module",
        visible_capacity as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let declaration = typed_storage_u32_fill_rw(
        device,
        "type_check.dependencies.visible.declaration",
        visible_capacity as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let lookup = typed_storage_u32_fill_rw(
        device,
        "type_check.dependencies.visible.lookup",
        lookup_capacity as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let resolved_type_decl = typed_storage_u32_fill_rw(
        device,
        "type_check.dependencies.resolved_type_decl",
        path_capacity as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let resolved_value_decl = typed_storage_u32_fill_rw(
        device,
        "type_check.dependencies.resolved_value_decl",
        path_capacity as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let call_dependency_decl = inputs.call_dependency_decl.clone();
    let call_compare_capacity = inputs.hir_node_capacity.max(1);
    let call_compare_scan_input = typed_storage_u32_rw(
        device,
        "type_check.dependencies.call_compare.scan_input",
        call_compare_capacity as usize,
        wgpu::BufferUsages::COPY_DST,
    );
    let call_compare_prefix = typed_storage_u32_rw(
        device,
        "type_check.dependencies.call_compare.prefix",
        call_compare_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let call_compare_total = typed_storage_u32_rw(
        device,
        "type_check.dependencies.call_compare.total",
        1,
        wgpu::BufferUsages::empty(),
    );
    let call_compare_expected_type = typed_storage_u32_fill_rw(
        device,
        "type_check.dependencies.call_compare.expected_type",
        call_compare_capacity as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let call_compare_actual_instance = typed_storage_u32_fill_rw(
        device,
        "type_check.dependencies.call_compare.actual_instance",
        call_compare_capacity as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let call_compare_error_token = typed_storage_u32_fill_rw(
        device,
        "type_check.dependencies.call_compare.error_token",
        call_compare_capacity as usize,
        u32::MAX,
        wgpu::BufferUsages::empty(),
    );
    let mut scan_resources = ResourceMap::new();
    scan_resources.buffers([
        ("hir_active_count", inputs.hir_active_count_buf),
        ("hir_active_dispatch_args", inputs.hir_active_dispatch_args),
    ]);
    scan_resources.buffers([
        ("import_record_count_out", &buffers.import_count_out),
        ("import_dispatch_args", &buffers.import_dispatch_args),
        ("dependency_visible_count", &count),
        ("dependency_visible_prefix", &prefix),
        ("dependency_visible_total", &total),
        (
            "dependency_call_compare_scan_input",
            &call_compare_scan_input,
        ),
        ("dependency_call_compare_prefix", &call_compare_prefix),
        ("dependency_call_compare_total", &call_compare_total),
    ]);
    scan_resources.buffers([
        (
            "module_record_scan_local_prefix",
            inputs.module_record_scan_workspace.local_prefix,
        ),
        (
            "module_record_scan_block_sum",
            inputs.module_record_scan_workspace.block_sum,
        ),
        (
            "module_record_scan_prefix_a",
            inputs.module_record_scan_workspace.block_prefix,
        ),
        (
            "module_record_scan_prefix_b",
            inputs.module_record_scan_workspace.hierarchy,
        ),
        (
            "module_value_scan_local_prefix",
            inputs.module_value_scan_workspace.local_prefix,
        ),
        (
            "module_value_scan_block_sum",
            inputs.module_value_scan_workspace.block_sum,
        ),
        (
            "module_value_scan_prefix_a",
            inputs.module_value_scan_workspace.block_prefix,
        ),
        (
            "module_value_scan_prefix_b",
            inputs.module_value_scan_workspace.hierarchy,
        ),
    ]);
    let scan = PrefixScanOperation::from_spec(
        device,
        passes,
        &scan_resources,
        compiler_graph::DEPENDENCY_VISIBLE_SCAN,
    )?;
    let call_compare_scan = PrefixScanOperation::from_spec(
        device,
        passes,
        &scan_resources,
        compiler_graph::DEPENDENCY_CALL_COMPARE_SCAN,
    )?;
    let call_compare_dispatch_args = typed_storage_u32_rw(
        device,
        "type_check.dependencies.call_compare.dispatch_args",
        3,
        wgpu::BufferUsages::INDIRECT,
    );
    let call_compare_dispatch_params = uniform_from_val(
        device,
        "type_check.dependencies.call_compare.dispatch_params",
        &CountDispatchParams {
            capacity: u32::MAX,
            multiplier: 1,
            reserved0: 0,
            reserved1: 0,
        },
    );
    let call_compare_dispatch_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check.dependencies.call_compare.dispatch",
        &passes.kernel("type_checker/count/dispatch_args"),
        &[
            ("gParams", call_compare_dispatch_params.as_entire_binding()),
            ("count_in", call_compare_total.as_entire_binding()),
            (
                "dispatch_args",
                call_compare_dispatch_args.as_entire_binding(),
            ),
        ],
    )?;
    let canonical_type_capacity = dependencies.type_count.max(1);
    let canonical_type_roots_a = typed_storage_u32_rw(
        device,
        "type_check.dependencies.canonical_type_roots_a",
        canonical_type_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let canonical_type_roots_b = typed_storage_u32_rw(
        device,
        "type_check.dependencies.canonical_type_roots_b",
        canonical_type_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let canonical_type_subtree_scratch = typed_storage_u32_rw(
        device,
        "type_check.dependencies.canonical_type_subtree_scratch",
        canonical_type_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let declaration_generic_arity = typed_storage_u32_rw(
        device,
        "type_check.dependencies.declaration_generic_arity",
        dependencies.declaration_count.max(1) as usize,
        wgpu::BufferUsages::empty(),
    );
    let canonical_type_jump_rounds = if dependencies.type_count <= 1 {
        0
    } else {
        u32::BITS - (dependencies.type_count - 1).leading_zeros()
    };

    let count_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_02_count_import_visibility",
        &passes.kernel("type_checker/dependencies/02_count_import_visibility"),
        &[
            ("gParams", params.as_entire_binding()),
            (
                "import_count_out",
                buffers.import_count_out.as_entire_binding(),
            ),
            ("import_status", buffers.import_status.as_entire_binding()),
            (
                "import_module_id",
                buffers.import_module_id.as_entire_binding(),
            ),
            (
                "import_target_dependency_module_id",
                buffers
                    .import_target_dependency_module_id
                    .as_ref()
                    .expect("dependency state has dependency import targets")
                    .as_entire_binding(),
            ),
            (
                "dependency_declaration_words",
                dependencies.declaration_words.as_entire_binding(),
            ),
            ("dependency_visible_count", count.as_entire_binding()),
        ],
    )?;
    let scatter_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_03_scatter_import_visibility",
        &passes.kernel("type_checker/dependencies/03_scatter_import_visibility"),
        &[
            ("gParams", params.as_entire_binding()),
            (
                "import_count_out",
                buffers.import_count_out.as_entire_binding(),
            ),
            (
                "import_module_id",
                buffers.import_module_id.as_entire_binding(),
            ),
            (
                "import_target_dependency_module_id",
                buffers
                    .import_target_dependency_module_id
                    .as_ref()
                    .expect("dependency state has dependency import targets")
                    .as_entire_binding(),
            ),
            (
                "dependency_declaration_words",
                dependencies.declaration_words.as_entire_binding(),
            ),
            ("dependency_visible_count", count.as_entire_binding()),
            ("dependency_visible_prefix", prefix.as_entire_binding()),
            ("dependency_visible_total", total.as_entire_binding()),
            (
                "dependency_visible_owner_module",
                owner_module.as_entire_binding(),
            ),
            ("dependency_visible_decl", declaration.as_entire_binding()),
        ],
    )?;
    let clear_lookup_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_04_clear_visible_lookup",
        &passes.kernel("type_checker/dependencies/04_clear_visible_lookup"),
        &[
            ("gParams", params.as_entire_binding()),
            ("dependency_visible_lookup", lookup.as_entire_binding()),
        ],
    )?;
    let build_lookup_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_05_build_visible_lookup",
        &passes.kernel("type_checker/dependencies/05_build_visible_lookup"),
        &[
            ("gParams", params.as_entire_binding()),
            ("dependency_visible_total", total.as_entire_binding()),
            (
                "dependency_visible_owner_module",
                owner_module.as_entire_binding(),
            ),
            ("dependency_visible_decl", declaration.as_entire_binding()),
            (
                "dependency_declaration_words",
                dependencies.declaration_words.as_entire_binding(),
            ),
            ("dependency_visible_lookup", lookup.as_entire_binding()),
        ],
    )?;

    let make_resolve_group = |label: &'static str,
                              params: &LaniusBuffer<DependencyInterfaceVisibilityParams>,
                              resolved_decl: &LaniusBuffer<u32>,
                              resolved_status: &LaniusBuffer<u32>|
     -> Result<wgpu::BindGroup> {
        resources.reflected_bind_group_with_overrides(
            device,
            label,
            &passes.kernel("type_checker/dependencies/06_resolve_paths"),
            &[
                ("gParams", params.as_entire_binding()),
                ("path_count_out", buffers.path_count_out.as_entire_binding()),
                ("path_kind", buffers.path_kind.as_entire_binding()),
                (
                    "path_segment_count",
                    buffers.path_segment_count.as_entire_binding(),
                ),
                (
                    "path_segment_base",
                    buffers.path_segment_base.as_entire_binding(),
                ),
                (
                    "path_segment_name_id",
                    buffers.path_segment_name_id.as_entire_binding(),
                ),
                (
                    "path_owner_module_id",
                    buffers.path_owner_module_id.as_entire_binding(),
                ),
                (
                    "dependency_declaration_words",
                    dependencies.declaration_words.as_entire_binding(),
                ),
                (
                    "dependency_name_byte_words",
                    dependencies.name_byte_words.as_entire_binding(),
                ),
                (
                    "dependency_visible_owner_module",
                    owner_module.as_entire_binding(),
                ),
                ("dependency_visible_decl", declaration.as_entire_binding()),
                ("dependency_visible_lookup", lookup.as_entire_binding()),
                (
                    "resolved_dependency_decl",
                    resolved_decl.as_entire_binding(),
                ),
                ("resolved_status", resolved_status.as_entire_binding()),
            ],
        )
    };
    let resolve_type_group = make_resolve_group(
        "type_check_dependencies_06_resolve_type_paths",
        &type_params,
        &resolved_type_decl,
        &buffers.resolved_type_status,
    )?;
    let resolve_value_group = make_resolve_group(
        "type_check_dependencies_06_resolve_value_paths",
        &value_params,
        &resolved_value_decl,
        &buffers.resolved_value_status,
    )?;
    let init_canonical_type_roots_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_09_init_canonical_type_roots",
        &passes.kernel("type_checker/dependencies/09_init_canonical_type_roots"),
        &[
            ("gParams", canonical_type_params.as_entire_binding()),
            (
                "dependency_declaration_library_id",
                dependencies.declaration_library_id.as_entire_binding(),
            ),
            (
                "dependency_declaration_unit_id",
                dependencies.declaration_unit_id.as_entire_binding(),
            ),
            (
                "dependency_declaration_local_index",
                dependencies.declaration_local_index.as_entire_binding(),
            ),
            (
                "dependency_declaration_words",
                dependencies.declaration_words.as_entire_binding(),
            ),
            (
                "dependency_type_words",
                dependencies.type_words.as_entire_binding(),
            ),
            (
                "canonical_type_roots",
                canonical_type_roots_a.as_entire_binding(),
            ),
        ],
    )?;
    let make_jump_group = |label: &'static str,
                           input: &LaniusBuffer<u32>,
                           output: &LaniusBuffer<u32>|
     -> Result<wgpu::BindGroup> {
        resources.reflected_bind_group_with_overrides(
            device,
            label,
            &passes.kernel("type_checker/dependencies/10_jump_canonical_type_roots"),
            &[
                ("gParams", canonical_type_params.as_entire_binding()),
                ("canonical_type_roots_in", input.as_entire_binding()),
                ("canonical_type_roots_out", output.as_entire_binding()),
            ],
        )
    };
    let jump_canonical_type_roots_a_to_b_group = make_jump_group(
        "type_check_dependencies_10_jump_canonical_type_roots_a_to_b",
        &canonical_type_roots_a,
        &canonical_type_roots_b,
    )?;
    let jump_canonical_type_roots_b_to_a_group = make_jump_group(
        "type_check_dependencies_10_jump_canonical_type_roots_b_to_a",
        &canonical_type_roots_b,
        &canonical_type_roots_a,
    )?;
    let (canonical_type_roots, canonical_type_root_scratch) = if canonical_type_jump_rounds % 2 == 0
    {
        (&canonical_type_roots_a, &canonical_type_roots_b)
    } else {
        (&canonical_type_roots_b, &canonical_type_roots_a)
    };
    let init_canonical_type_subtree_start_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_09a_init_canonical_type_subtree_start",
        &passes.kernel("type_checker/dependencies/09a_init_canonical_type_subtree_start"),
        &[
            ("gParams", canonical_type_params.as_entire_binding()),
            (
                "dependency_type_words",
                dependencies.type_words.as_entire_binding(),
            ),
            (
                "dependency_type_edge_words",
                dependencies.type_edge_words.as_entire_binding(),
            ),
            (
                "canonical_type_subtree_start",
                canonical_type_root_scratch.as_entire_binding(),
            ),
        ],
    )?;
    let make_subtree_jump_group = |label: &'static str,
                                   input: &LaniusBuffer<u32>,
                                   output: &LaniusBuffer<u32>|
     -> Result<wgpu::BindGroup> {
        resources.reflected_bind_group_with_overrides(
            device,
            label,
            &passes.kernel("type_checker/dependencies/10a_jump_canonical_type_subtree_start"),
            &[
                ("gParams", canonical_type_params.as_entire_binding()),
                ("canonical_type_subtree_start_in", input.as_entire_binding()),
                (
                    "canonical_type_subtree_start_out",
                    output.as_entire_binding(),
                ),
            ],
        )
    };
    let jump_canonical_type_subtree_start_a_to_b_group = make_subtree_jump_group(
        "type_check_dependencies_10a_jump_canonical_type_subtree_start_a_to_b",
        canonical_type_root_scratch,
        &canonical_type_subtree_scratch,
    )?;
    let jump_canonical_type_subtree_start_b_to_a_group = make_subtree_jump_group(
        "type_check_dependencies_10a_jump_canonical_type_subtree_start_b_to_a",
        &canonical_type_subtree_scratch,
        canonical_type_root_scratch,
    )?;
    let canonical_type_subtree_start = if canonical_type_jump_rounds % 2 == 0 {
        canonical_type_root_scratch
    } else {
        &canonical_type_subtree_scratch
    };
    let project_types_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_11_project_types",
        &passes.kernel("type_checker/dependencies/11_project_types"),
        &[
            ("gParams", canonical_type_params.as_entire_binding()),
            ("path_count_out", buffers.path_count_out.as_entire_binding()),
            ("path_kind", buffers.path_kind.as_entire_binding()),
            (
                "path_owner_token",
                buffers.path_owner_token.as_entire_binding(),
            ),
            (
                "resolved_dependency_decl",
                resolved_type_decl.as_entire_binding(),
            ),
            (
                "dependency_declaration_words",
                dependencies.declaration_words.as_entire_binding(),
            ),
            (
                "dependency_type_words",
                dependencies.type_words.as_entire_binding(),
            ),
            (
                "canonical_type_roots",
                canonical_type_roots.as_entire_binding(),
            ),
        ],
    )?;
    let clear_declaration_generic_arity_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_12_clear_declaration_generic_arity",
        &passes.kernel("type_checker/dependencies/12_clear_declaration_generic_arity"),
        &[
            ("gParams", canonical_type_params.as_entire_binding()),
            (
                "declaration_generic_arity",
                declaration_generic_arity.as_entire_binding(),
            ),
        ],
    )?;
    let count_declaration_generic_arity_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_13_count_declaration_generic_arity",
        &passes.kernel("type_checker/dependencies/13_count_declaration_generic_arity"),
        &[
            ("gParams", canonical_type_params.as_entire_binding()),
            (
                "dependency_member_words",
                dependencies.member_words.as_entire_binding(),
            ),
            (
                "declaration_generic_arity",
                declaration_generic_arity.as_entire_binding(),
            ),
        ],
    )?;
    let project_type_instances_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_14_project_type_instances",
        &passes.kernel("type_checker/dependencies/14_project_type_instances"),
        &[
            ("gParams", canonical_type_params.as_entire_binding()),
            ("path_count_out", buffers.path_count_out.as_entire_binding()),
            ("path_kind", buffers.path_kind.as_entire_binding()),
            (
                "path_segment_count",
                buffers.path_segment_count.as_entire_binding(),
            ),
            (
                "path_segment_base",
                buffers.path_segment_base.as_entire_binding(),
            ),
            (
                "path_segment_token",
                buffers.path_segment_token.as_entire_binding(),
            ),
            (
                "path_owner_token",
                buffers.path_owner_token.as_entire_binding(),
            ),
            (
                "resolved_dependency_decl",
                resolved_type_decl.as_entire_binding(),
            ),
            (
                "dependency_declaration_words",
                dependencies.declaration_words.as_entire_binding(),
            ),
            (
                "canonical_type_roots",
                canonical_type_roots.as_entire_binding(),
            ),
            (
                "declaration_generic_arity",
                declaration_generic_arity.as_entire_binding(),
            ),
        ],
    )?;
    let project_calls_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_07_project_calls",
        &passes.kernel("type_checker/dependencies/07_project_calls"),
        &[
            ("gParams", value_params.as_entire_binding()),
            (
                "module_id_by_file_id",
                buffers.module_id_by_file_id.as_entire_binding(),
            ),
            (
                "dependency_declaration_words",
                dependencies.declaration_words.as_entire_binding(),
            ),
            (
                "dependency_type_words",
                dependencies.type_words.as_entire_binding(),
            ),
            (
                "dependency_type_edge_words",
                dependencies.type_edge_words.as_entire_binding(),
            ),
            (
                "canonical_type_roots",
                canonical_type_roots.as_entire_binding(),
            ),
            (
                "dependency_name_byte_words",
                dependencies.name_byte_words.as_entire_binding(),
            ),
            (
                "dependency_visible_owner_module",
                owner_module.as_entire_binding(),
            ),
            ("dependency_visible_decl", declaration.as_entire_binding()),
            ("dependency_visible_lookup", lookup.as_entire_binding()),
            (
                "call_dependency_decl",
                call_dependency_decl.as_entire_binding(),
            ),
        ],
    )?;
    let project_call_params_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_07a_project_call_params",
        &passes.kernel("type_checker/dependencies/07a_project_call_params"),
        &[
            ("gParams", value_params.as_entire_binding()),
            (
                "call_dependency_decl",
                call_dependency_decl.as_entire_binding(),
            ),
            (
                "dependency_declaration_words",
                dependencies.declaration_words.as_entire_binding(),
            ),
            (
                "dependency_type_words",
                dependencies.type_words.as_entire_binding(),
            ),
        ],
    )?;
    let scatter_call_params_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_07b_scatter_call_params",
        &passes.kernel("type_checker/dependencies/07b_scatter_call_params"),
        &[
            ("gParams", value_params.as_entire_binding()),
            (
                "call_dependency_decl",
                call_dependency_decl.as_entire_binding(),
            ),
            (
                "dependency_declaration_words",
                dependencies.declaration_words.as_entire_binding(),
            ),
            (
                "dependency_type_words",
                dependencies.type_words.as_entire_binding(),
            ),
            (
                "dependency_type_edge_words",
                dependencies.type_edge_words.as_entire_binding(),
            ),
            (
                "canonical_type_roots",
                canonical_type_roots.as_entire_binding(),
            ),
        ],
    )?;
    let validate_call_args_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_08_validate_call_args",
        &passes.kernel("type_checker/dependencies/08_validate_call_args"),
        &[
            ("gParams", value_params.as_entire_binding()),
            ("dependency_counts", dependencies.counts.as_entire_binding()),
            (
                "dependency_declaration_words",
                dependencies.declaration_words.as_entire_binding(),
            ),
            (
                "dependency_type_words",
                dependencies.type_words.as_entire_binding(),
            ),
            (
                "dependency_type_edge_words",
                dependencies.type_edge_words.as_entire_binding(),
            ),
            (
                "canonical_type_roots",
                canonical_type_roots.as_entire_binding(),
            ),
            (
                "canonical_type_subtree_start",
                canonical_type_subtree_start.as_entire_binding(),
            ),
            (
                "dependency_call_compare_scan_input",
                call_compare_scan_input.as_entire_binding(),
            ),
            (
                "dependency_call_compare_expected_type",
                call_compare_expected_type.as_entire_binding(),
            ),
            (
                "dependency_call_compare_actual_instance",
                call_compare_actual_instance.as_entire_binding(),
            ),
            (
                "dependency_call_compare_error_token",
                call_compare_error_token.as_entire_binding(),
            ),
        ],
    )?;
    let validate_call_results_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_08a_validate_call_results",
        &passes.kernel("type_checker/dependencies/08a_validate_call_results"),
        &{
            let mut bindings = Vec::with_capacity(45);
            bindings.extend([
                ("gParams", value_params.as_entire_binding()),
                (
                    "call_dependency_decl",
                    call_dependency_decl.as_entire_binding(),
                ),
            ]);
            bindings.extend([
                ("dependency_counts", dependencies.counts.as_entire_binding()),
                (
                    "dependency_type_words",
                    dependencies.type_words.as_entire_binding(),
                ),
                (
                    "canonical_type_roots",
                    canonical_type_roots.as_entire_binding(),
                ),
                (
                    "canonical_type_subtree_start",
                    canonical_type_subtree_start.as_entire_binding(),
                ),
                (
                    "dependency_call_compare_scan_input",
                    call_compare_scan_input.as_entire_binding(),
                ),
                (
                    "dependency_call_compare_expected_type",
                    call_compare_expected_type.as_entire_binding(),
                ),
                (
                    "dependency_call_compare_actual_instance",
                    call_compare_actual_instance.as_entire_binding(),
                ),
                (
                    "dependency_call_compare_error_token",
                    call_compare_error_token.as_entire_binding(),
                ),
            ]);
            bindings
        },
    )?;
    let validate_call_type_args_group = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_dependencies_08b_validate_call_type_args",
        &passes.kernel("type_checker/dependencies/08b_validate_call_type_args"),
        &[
            ("gParams", value_params.as_entire_binding()),
            ("dependency_counts", dependencies.counts.as_entire_binding()),
            (
                "dependency_call_compare_scan_input",
                call_compare_scan_input.as_entire_binding(),
            ),
            (
                "dependency_call_compare_prefix",
                call_compare_prefix.as_entire_binding(),
            ),
            (
                "dependency_call_compare_total",
                call_compare_total.as_entire_binding(),
            ),
            (
                "dependency_call_compare_expected_type",
                call_compare_expected_type.as_entire_binding(),
            ),
            (
                "dependency_call_compare_actual_instance",
                call_compare_actual_instance.as_entire_binding(),
            ),
            (
                "dependency_call_compare_error_token",
                call_compare_error_token.as_entire_binding(),
            ),
            (
                "dependency_type_words",
                dependencies.type_words.as_entire_binding(),
            ),
            (
                "dependency_type_edge_words",
                dependencies.type_edge_words.as_entire_binding(),
            ),
            (
                "canonical_type_roots",
                canonical_type_roots.as_entire_binding(),
            ),
            (
                "canonical_type_subtree_start",
                canonical_type_subtree_start.as_entire_binding(),
            ),
        ],
    )?;

    Ok(Some(Box::new(DependencyVisibilityState {
        visible_capacity,
        lookup_capacity,
        canonical_type_count: dependencies.type_count,
        canonical_declaration_count: dependencies.declaration_count,
        canonical_member_count: dependencies.member_count,
        call_compare_scan_input,
        call_compare_dispatch_args,
        canonical_type_subtree: Box::new(DependencyCanonicalTypeSubtreeState {
            init_group: init_canonical_type_subtree_start_group,
            jump_a_to_b_group: jump_canonical_type_subtree_start_a_to_b_group,
            jump_b_to_a_group: jump_canonical_type_subtree_start_b_to_a_group,
        }),
        _retained_buffers: Box::new([
            count,
            prefix,
            total,
            owner_module,
            declaration,
            lookup,
            resolved_type_decl,
            resolved_value_decl,
            call_dependency_decl,
            call_compare_prefix,
            call_compare_total,
            call_compare_expected_type,
            call_compare_actual_instance,
            call_compare_error_token,
            canonical_type_roots_a,
            canonical_type_roots_b,
            canonical_type_subtree_scratch,
            declaration_generic_arity,
        ]),
        canonical_type_jump_rounds,
        scan,
        call_compare_scan,
        count_group,
        scatter_group,
        clear_lookup_group,
        build_lookup_group,
        resolve_type_group,
        resolve_value_group,
        project_calls_group,
        project_call_params_group,
        scatter_call_params_group,
        validate_call_args_group,
        validate_call_results_group,
        validate_call_type_args_group,
        call_compare_dispatch_group,
        init_canonical_type_roots_group,
        jump_canonical_type_roots_a_to_b_group,
        jump_canonical_type_roots_b_to_a_group,
        project_types_group,
        clear_declaration_generic_arity_group,
        count_declaration_generic_arity_group,
        project_type_instances_group,
        _params: params,
        _type_params: type_params,
        _value_params: value_params,
        _canonical_type_params: canonical_type_params,
        _call_compare_dispatch_params: call_compare_dispatch_params,
    })))
}
