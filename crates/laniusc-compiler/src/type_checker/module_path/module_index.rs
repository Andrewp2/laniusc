use super::{
    super::*,
    bind_helpers::create_radix_dispatch,
    buffers::Buffers,
    inputs::CreateInputs,
    layout::Layout,
};

/// Bind groups for module identity, import resolution, and import-cycle checks.
///
/// The module index sorts module keys, resolves imports into module ids, and
/// validates the import graph before declaration lookup consumes it.
pub(in crate::type_checker) struct ModuleIndex {
    pub(in crate::type_checker) scatter_module_records: ComputeOperation,
    pub(in crate::type_checker) build_module_keys: wgpu::BindGroup,
    pub(in crate::type_checker) module_key_radix_dispatch_params:
        LaniusBuffer<ModuleKeyRadixParams>,
    pub(in crate::type_checker) module_key_radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) sort_module_keys: RadixSortOperation<ModuleKeyRadixParams>,
    pub(in crate::type_checker) validate_modules: wgpu::BindGroup,
    pub(in crate::type_checker) dependency_module_params:
        Option<LaniusBuffer<DependencyInterfaceModuleParams>>,
    pub(in crate::type_checker) clear_dependency_module_lookup: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) build_dependency_module_lookup: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) resolve_dependency_imports: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) scatter_import_records: ComputeOperation,
    pub(in crate::type_checker) resolve_imports: ComputeOperation,
    pub(in crate::type_checker) seed_import_edge_key_order: wgpu::BindGroup,
    pub(in crate::type_checker) import_edge_key_radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) sort_import_edges: RadixSortOperation<ModuleKeyRadixParams>,
    pub(in crate::type_checker) validate_import_cycles: wgpu::BindGroup,
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
    let scatter_module_records = ComputeOperation::direct_spec(
        device,
        graph,
        &module_record_resources,
        passes,
        MODULE_RECORDS_SCATTER,
        layout
            .n_blocks
            .max(layout.module_n_blocks)
            .saturating_mul(256)
            .max(1),
    )?;

    let module_key_build_params = uniform_from_val(
        device,
        "type_check.modules.module_key_build.params",
        &ModuleKeyRadixParams {
            module_capacity: layout.record_capacity_u32,
            reserved: layout.module_capacity_u32,
            n_blocks: layout.module_n_blocks,
            key_step: 0,
        },
    );
    let build_module_keys = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_02e_build_module_keys",
        &passes.kernel("type_checker/modules/02e_build_module_keys"),
        &[
            ("gParams", module_key_build_params.as_entire_binding()),
            (
                "module_table_count_out",
                buffers.module_table_count_out.as_entire_binding(),
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
                "module_key_to_module_id",
                buffers.module_key_to_module_id.as_entire_binding(),
            ),
        ],
    )?;

    let module_key_radix_dispatch_params = uniform_from_val(
        device,
        "type_check.modules.module_key_radix.dispatch_params",
        &ModuleKeyRadixParams {
            module_capacity: layout.module_capacity_u32,
            reserved: 0,
            n_blocks: layout.module_n_blocks,
            key_step: 0,
        },
    );
    let module_key_radix_dispatch = create_radix_dispatch(
        device,
        &passes.kernel("type_checker/names/radix/dispatch_args"),
        "type_check.modules.module_key_radix_dispatch",
        &module_key_radix_dispatch_params,
        &buffers.module_table_count_out,
        &buffers.module_key_radix_dispatch_args,
    )?;

    let module_key_resources = HashMap::from([
        (
            "module_table_count_out".to_owned(),
            buffers.module_table_count_out.as_entire_binding(),
        ),
        (
            "module_key_canonical_id".to_owned(),
            buffers.module_key_canonical_id.as_entire_binding(),
        ),
        (
            "module_key_order".to_owned(),
            buffers.module_key_to_module_id.as_entire_binding(),
        ),
        (
            "module_key_order_tmp".to_owned(),
            buffers.module_key_order_tmp.as_entire_binding(),
        ),
        (
            "module_key_radix_block_histogram".to_owned(),
            buffers.module_key_radix_block_histogram.as_entire_binding(),
        ),
        (
            "module_key_radix_block_bucket_prefix".to_owned(),
            buffers
                .module_key_radix_block_bucket_prefix
                .as_entire_binding(),
        ),
        (
            "module_key_radix_bucket_total".to_owned(),
            buffers.module_key_radix_bucket_total.as_entire_binding(),
        ),
        (
            "module_key_radix_bucket_base".to_owned(),
            buffers.module_key_radix_bucket_base.as_entire_binding(),
        ),
    ]);
    let sort_module_keys = RadixSortOperation::new(
        device,
        passes,
        &module_key_resources,
        RadixSortPlan {
            label: "type_check.modules.module_keys",
            capacity: layout.module_capacity_u32,
            small_capacity: MODULE_KEY_SMALL_SORT_CAPACITY,
            steps: MODULE_KEY_RADIX_STEPS,
            kernels: RadixSortKernels::new(
                "type_checker/modules/03_sort_module_keys_histogram",
                "type_checker/modules/03b_sort_module_keys_scatter",
            )
            .with_small("type_checker/modules/02f_sort_module_keys_small"),
            dispatch: RadixSortDispatch {
                small: RadixDispatchDomain::Indirect(&buffers.module_key_radix_dispatch_args),
                rows: RadixDispatchDomain::Indirect(&buffers.module_key_radix_dispatch_args),
                bucket_prefix: RadixDispatchDomain::Direct(NAME_RADIX_BUCKETS.saturating_mul(256)),
                bucket_bases: RadixDispatchDomain::Direct(256),
            },
            resources: RadixSortResources {
                count: "module_table_count_out",
                order: "module_key_order",
                temporary_order: "module_key_order_tmp",
                histogram: "module_key_radix_block_histogram",
                bucket_prefix: "module_key_radix_block_bucket_prefix",
                bucket_total: "module_key_radix_bucket_total",
                bucket_base: "module_key_radix_bucket_base",
            },
        },
        |key_step| ModuleKeyRadixParams {
            module_capacity: layout.module_capacity_u32,
            reserved: 0,
            n_blocks: layout.module_n_blocks,
            key_step,
        },
    )?;
    let mut retained_params = Vec::with_capacity(5);

    let validate_module_params = uniform_from_val(
        device,
        "type_check.modules.module_key_radix.params.validate",
        &ModuleKeyRadixParams {
            module_capacity: layout.module_capacity_u32,
            reserved: layout.record_capacity_u32,
            n_blocks: layout.module_n_blocks,
            key_step: 0,
        },
    );
    let validate_modules = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_04_validate_modules",
        &passes.kernel("type_checker/modules/04_validate_modules"),
        &[
            ("gParams", validate_module_params.as_entire_binding()),
            (
                "module_table_count_out",
                buffers.module_table_count_out.as_entire_binding(),
            ),
            (
                "sorted_module_key_order",
                buffers.module_key_to_module_id.as_entire_binding(),
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

    retained_params.push(validate_module_params);

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
        &ModuleKeyRadixParams {
            module_capacity: layout.import_record_capacity_u32,
            reserved: layout.module_capacity_u32,
            // This field is the path-record capacity for the import resolver;
            // import rows and path rows occupy different compact domains.
            n_blocks: layout.record_capacity_u32,
            key_step: u32::from(inputs.dependency_interfaces.is_some()),
        },
    );
    let mut resolve_resources = resources.clone();
    resolve_resources.buffer("gParams", &resolve_import_params);
    resolve_resources.alias("sorted_module_key_order", "module_key_to_module_id")?;
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

    let import_edge_key_radix_params = uniform_from_val(
        device,
        "type_check.modules.import_edge_key_radix.dispatch_params",
        &ModuleKeyRadixParams {
            module_capacity: layout.import_record_capacity_u32,
            reserved: 0,
            n_blocks: layout.record_n_blocks,
            key_step: 0,
        },
    );
    let import_edge_key_radix_dispatch = create_radix_dispatch(
        device,
        &passes.kernel("type_checker/names/radix/dispatch_args"),
        "type_check.modules.import_edge_key_radix_dispatch",
        &import_edge_key_radix_params,
        &buffers.import_count_out,
        &buffers.import_edge_key_radix_dispatch_args,
    )?;

    let seed_import_edge_key_order = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_05e_seed_import_edge_key_order",
        &passes.kernel("type_checker/modules/05e_seed_import_edge_key_order"),
        &[
            ("gParams", resolve_import_params.as_entire_binding()),
            (
                "import_count_out",
                buffers.import_count_out.as_entire_binding(),
            ),
            (
                "import_edge_key_order",
                buffers.import_edge_key_order.as_entire_binding(),
            ),
            (
                "import_edge_key_order_tmp",
                buffers.import_edge_key_order_tmp.as_entire_binding(),
            ),
        ],
    )?;

    let import_edge_resources = HashMap::from([
        (
            "import_count_out".to_owned(),
            buffers.import_count_out.as_entire_binding(),
        ),
        (
            "import_module_id".to_owned(),
            buffers.import_module_id.as_entire_binding(),
        ),
        (
            "import_target_module_id".to_owned(),
            buffers.import_target_module_id.as_entire_binding(),
        ),
        (
            "import_status".to_owned(),
            buffers.import_status.as_entire_binding(),
        ),
        (
            "import_edge_key_order".to_owned(),
            buffers.import_edge_key_order.as_entire_binding(),
        ),
        (
            "import_edge_key_order_tmp".to_owned(),
            buffers.import_edge_key_order_tmp.as_entire_binding(),
        ),
        (
            "import_edge_key_radix_block_histogram".to_owned(),
            buffers.decl_key_radix_block_histogram.as_entire_binding(),
        ),
        (
            "import_edge_key_radix_block_bucket_prefix".to_owned(),
            buffers
                .decl_key_radix_block_bucket_prefix
                .as_entire_binding(),
        ),
        (
            "import_edge_key_radix_bucket_total".to_owned(),
            buffers.decl_key_radix_bucket_total.as_entire_binding(),
        ),
        (
            "import_edge_key_radix_bucket_base".to_owned(),
            buffers.decl_key_radix_bucket_base.as_entire_binding(),
        ),
    ]);
    let sort_import_edges = RadixSortOperation::new(
        device,
        passes,
        &import_edge_resources,
        RadixSortPlan {
            label: "type_check.modules.import_edges",
            capacity: layout.import_record_capacity_u32,
            small_capacity: MODULE_RELATION_SMALL_SORT_CAPACITY,
            steps: IMPORT_EDGE_KEY_RADIX_STEPS,
            kernels: RadixSortKernels::new(
                "type_checker/modules/05f_sort_import_edges",
                "type_checker/modules/05g_sort_import_edges_scatter",
            )
            .with_small("type_checker/modules/05e2_sort_import_edges_small"),
            dispatch: RadixSortDispatch {
                small: RadixDispatchDomain::Indirect(&buffers.import_edge_key_radix_dispatch_args),
                rows: RadixDispatchDomain::Indirect(&buffers.import_edge_key_radix_dispatch_args),
                bucket_prefix: RadixDispatchDomain::Direct(NAME_RADIX_BUCKETS.saturating_mul(256)),
                bucket_bases: RadixDispatchDomain::Direct(256),
            },
            resources: RadixSortResources {
                count: "import_count_out",
                order: "import_edge_key_order",
                temporary_order: "import_edge_key_order_tmp",
                histogram: "import_edge_key_radix_block_histogram",
                bucket_prefix: "import_edge_key_radix_block_bucket_prefix",
                bucket_total: "import_edge_key_radix_bucket_total",
                bucket_base: "import_edge_key_radix_bucket_base",
            },
        },
        |key_step| ModuleKeyRadixParams {
            module_capacity: layout.import_record_capacity_u32,
            reserved: 0,
            n_blocks: layout.record_n_blocks,
            key_step,
        },
    )?;

    let validate_import_cycles = resources.reflected_bind_group_with_overrides(
        device,
        "type_check_modules_05h_validate_import_cycles",
        &passes.kernel("type_checker/modules/05h_validate_import_cycles"),
        &[
            ("gParams", resolve_import_params.as_entire_binding()),
            (
                "import_count_out",
                buffers.import_count_out.as_entire_binding(),
            ),
            (
                "import_module_id",
                buffers.import_module_id.as_entire_binding(),
            ),
            (
                "import_target_module_id",
                buffers.import_target_module_id.as_entire_binding(),
            ),
            ("import_path_id", buffers.import_path_id.as_entire_binding()),
            (
                "path_owner_token",
                buffers.path_owner_token.as_entire_binding(),
            ),
            (
                "import_edge_key_order",
                buffers.import_edge_key_order.as_entire_binding(),
            ),
            ("import_status", buffers.import_status.as_entire_binding()),
        ],
    )?;

    retained_params.push(resolve_import_params);
    retained_params.push(import_edge_key_radix_params);
    retained_params.push(module_record_params);
    retained_params.push(module_key_build_params);

    Ok(ModuleIndex {
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
        retained_params,
    })
}
