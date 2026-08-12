use super::{
    super::*,
    bind_helpers::create_count_dispatch,
    buffers::Buffers,
    inputs::CreateInputs,
    layout::Layout,
};

/// Bind groups for module identity, import resolution, and import-cycle checks.
///
/// The module index maps canonical module keys, resolves imports into module ids, and
/// validates the import graph before declaration lookup consumes it.
pub(in crate::type_checker) struct ModuleIndex {
    pub(in crate::type_checker) scatter_module_records: ComputeOperation,
    pub(in crate::type_checker) clear_module_lookup: wgpu::BindGroup,
    pub(in crate::type_checker) build_module_keys: wgpu::BindGroup,
    pub(in crate::type_checker) module_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) module_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) validate_modules: wgpu::BindGroup,
    pub(in crate::type_checker) clear_dependency_module_lookup: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) build_dependency_module_lookup: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) resolve_dependency_imports: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) scatter_import_records: ComputeOperation,
    pub(in crate::type_checker) resolve_imports: ComputeOperation,
    pub(in crate::type_checker) clear_import_edge_set: ComputeOperation,
    pub(in crate::type_checker) build_import_edge_set: ComputeOperation,
    pub(in crate::type_checker) validate_import_cycles: ComputeOperation,
    pub(in crate::type_checker) module_lookup_params: LaniusBuffer<ModuleLookupParams>,
    pub(in crate::type_checker) import_resolve_params: LaniusBuffer<ImportResolveParams>,
    pub(in crate::type_checker) retained_params: Vec<LaniusBuffer<ModuleKeyRadixParams>>,
}

/// Creates bind groups for module indexing and import-edge validation.
pub(in crate::type_checker) fn create_module_index(
    passes: &TypeCheckPasses,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    device: &wgpu::Device,
    layout: Layout,
    inputs: &CreateInputs<'_>,
    buffers: &Buffers,
    resources: &ResourceMap<'_>,
) -> Result<ModuleIndex> {
    let module_record_params = uniform_from_val(
        device,
        "type_check.modules.module_records.params",
        &ModuleKeyRadixParams {
            module_capacity: inputs.hir_node_capacity,
            reserved: layout.module_capacity_u32,
            n_blocks: layout.n_blocks,
            key_step: 0,
        },
    );
    let mut module_record_resources = resources.clone();
    module_record_resources.buffer("gParams", &module_record_params);
    // Module rows are a compaction scatter over the active dense-HIR domain.
    // Dispatching over the capacity here would reinterpret stale flag/prefix
    // rows beyond the current compact HIR as live records on daemon reuse.
    let scatter_module_records = ComputeOperation::indirect_spec(
        device,
        graph,
        &module_record_resources,
        passes,
        MODULE_RECORDS_SCATTER,
        inputs.hir_active_dispatch_args,
    )?;

    let module_lookup_params = uniform_from_val(
        device,
        "type_check.modules.module_lookup.params",
        &ModuleLookupParams {
            path_capacity: layout.record_capacity_u32,
            path_segment_capacity: inputs.token_capacity,
            module_capacity: layout.module_capacity_u32,
            reserved: 0,
        },
    );
    let clear_module_lookup = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_02d_clear_module_lookup",
        &passes.kernel("type_checker/modules/02d_clear_module_lookup"),
        &[
            ("gParams", module_lookup_params.as_entire_binding()),
            (
                "module_by_canonical_id",
                buffers.module_by_canonical_id.as_entire_binding(),
            ),
        ],
    )?;
    let build_module_keys = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_02e_build_module_keys",
        &passes.kernel("type_checker/modules/02e_build_module_keys"),
        &[
            ("gParams", module_lookup_params.as_entire_binding()),
            (
                "module_count_out",
                buffers.module_count_out.as_entire_binding(),
            ),
            ("module_path_id", buffers.module_path_id.as_entire_binding()),
            (
                "module_owner_hir",
                buffers.module_owner_hir.as_entire_binding(),
            ),
            (
                "path_segment_count",
                buffers.path_segment_count.as_entire_binding(),
            ),
            (
                "path_segment_base",
                buffers.path_segment_base.as_entire_binding(),
            ),
            (
                "path_prefix_id",
                buffers.path_prefix_id_a.as_entire_binding(),
            ),
            (
                "path_owner_token",
                buffers.path_owner_token.as_entire_binding(),
            ),
            ("module_status", buffers.module_status.as_entire_binding()),
            (
                "module_key_canonical_id",
                buffers.module_key_canonical_id.as_entire_binding(),
            ),
            (
                "module_key_segment_count",
                buffers.module_key_segment_count.as_entire_binding(),
            ),
            (
                "module_key_segment_base",
                buffers.module_key_segment_base.as_entire_binding(),
            ),
            (
                "module_by_canonical_id",
                buffers.module_by_canonical_id.as_entire_binding(),
            ),
        ],
    )?;

    let (module_dispatch_params, module_dispatch) = create_count_dispatch(
        device,
        &passes.kernel("type_checker/count/dispatch_args"),
        "type_check.modules.module_dispatch.params",
        "type_check.modules.module_dispatch",
        layout.module_capacity_u32,
        1,
        &buffers.module_count_out,
        &buffers.module_dispatch_args,
    )?;

    let mut retained_params = Vec::with_capacity(5);

    let validate_modules = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_04_validate_modules",
        &passes.kernel("type_checker/modules/04_validate_modules"),
        &[
            ("gParams", module_lookup_params.as_entire_binding()),
            (
                "module_count_out",
                buffers.module_count_out.as_entire_binding(),
            ),
            (
                "module_by_canonical_id",
                buffers.module_by_canonical_id.as_entire_binding(),
            ),
            (
                "module_key_canonical_id",
                buffers.module_key_canonical_id.as_entire_binding(),
            ),
            ("module_path_id", buffers.module_path_id.as_entire_binding()),
            (
                "path_owner_token",
                buffers.path_owner_token.as_entire_binding(),
            ),
            ("module_status", buffers.module_status.as_entire_binding()),
        ],
    )?;

    let scatter_import_records = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        IMPORT_RECORDS_SCATTER,
        inputs.hir_active_dispatch_args,
    )?;

    let resolve_import_params = uniform_from_val(
        device,
        "type_check.modules.resolve_imports.params",
        &ImportResolveParams {
            import_capacity: layout.import_record_capacity_u32,
            path_capacity: layout.record_capacity_u32,
            path_segment_capacity: inputs.token_capacity,
            module_capacity: layout.module_capacity_u32,
            dependency_interfaces_present: u32::from(inputs.dependency_interfaces.is_some()),
            reserved0: 0,
            reserved1: 0,
            reserved2: 0,
        },
    );
    let mut resolve_resources = resources.clone();
    resolve_resources.buffer("gParams", &resolve_import_params);
    resolve_resources.alias("path_prefix_id", "path_prefix_id_a")?;
    let resolve_imports = ComputeOperation::indirect_spec(
        device,
        graph,
        &resolve_resources,
        passes,
        RESOLVE_IMPORTS,
        &buffers.import_dispatch_args,
    )?;

    let dependency_module_params = inputs.dependency_interfaces.map(|dependencies| {
        uniform_from_val(
            device,
            "type_check.dependencies.module_params",
            &DependencyInterfaceModuleParams {
                module_count: dependencies.module_count,
                lookup_capacity: dependencies.module_lookup_capacity,
                import_capacity: layout.import_record_capacity_u32,
                source_len: inputs.source_len,
            },
        )
    });
    let build_dependency_module_lookup = match (
        inputs.dependency_interfaces,
        dependency_module_params.as_ref(),
    ) {
        (Some(dependencies), Some(params)) => Some(resources.reflected_bind_group_with_overrides(
            device,
            "type_check.dependencies.build_module_lookup",
            &passes.kernel("type_checker/dependencies/00_build_module_lookup"),
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "dependency_module_lookup",
                    dependencies.module_lookup.as_entire_binding(),
                ),
            ],
        )?),
        _ => None,
    };
    let clear_dependency_module_lookup = match (
        inputs.dependency_interfaces,
        dependency_module_params.as_ref(),
    ) {
        (Some(dependencies), Some(params)) => Some(resources.reflected_bind_group_with_overrides(
            device,
            "type_check.dependencies.clear_module_lookup",
            &passes.kernel("type_checker/dependencies/00a_clear_module_lookup"),
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "dependency_module_lookup",
                    dependencies.module_lookup.as_entire_binding(),
                ),
            ],
        )?),
        _ => None,
    };
    let resolve_dependency_imports = match (
        inputs.dependency_interfaces,
        dependency_module_params.as_ref(),
        buffers.import_target_dependency_module_id.as_ref(),
    ) {
        (Some(dependencies), Some(params), Some(target_dependency_module)) => {
            Some(resources.reflected_bind_group_with_overrides(
                device,
                "type_check.dependencies.resolve_imports",
                &passes.kernel("type_checker/dependencies/01_resolve_imports"),
                &[
                    ("gParams", params.as_entire_binding()),
                    (
                        "import_count_out",
                        buffers.import_count_out.as_entire_binding(),
                    ),
                    ("import_path_id", buffers.import_path_id.as_entire_binding()),
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
                        "path_owner_token",
                        buffers.path_owner_token.as_entire_binding(),
                    ),
                    (
                        "dependency_module_lookup",
                        dependencies.module_lookup.as_entire_binding(),
                    ),
                    (
                        "import_target_dependency_module_id",
                        target_dependency_module.as_entire_binding(),
                    ),
                    ("import_status", buffers.import_status.as_entire_binding()),
                ],
            )?)
        }
        _ => None,
    };

    let mut import_edge_resources = resources.clone();
    import_edge_resources.buffer("gParams", &resolve_import_params);
    let clear_import_edge_set = ComputeOperation::direct_spec(
        device,
        graph,
        &import_edge_resources,
        passes,
        IMPORT_EDGE_SET_CLEAR,
        layout.import_record_capacity_u32.saturating_mul(2).max(1),
    )?;
    let build_import_edge_set = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_edge_resources,
        passes,
        IMPORT_EDGE_SET_BUILD,
        &buffers.import_dispatch_args,
    )?;
    let validate_import_cycles = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_edge_resources,
        passes,
        IMPORT_CYCLES_VALIDATE,
        &buffers.import_dispatch_args,
    )?;

    retained_params.push(module_record_params);

    Ok(ModuleIndex {
        scatter_module_records,
        clear_module_lookup,
        build_module_keys,
        module_dispatch_params,
        module_dispatch,
        validate_modules,
        clear_dependency_module_lookup,
        build_dependency_module_lookup,
        resolve_dependency_imports,
        scatter_import_records,
        resolve_imports,
        clear_import_edge_set,
        build_import_edge_set,
        validate_import_cycles,
        module_lookup_params,
        import_resolve_params: resolve_import_params,
        retained_params,
    })
}
