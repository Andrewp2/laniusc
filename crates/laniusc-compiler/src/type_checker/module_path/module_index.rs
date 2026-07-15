use super::{
    super::*,
    bind_helpers::{create_radix_bucket_bases, create_radix_bucket_prefix, create_radix_dispatch},
    buffers::Buffers,
    inputs::CreateInputs,
    layout::Layout,
};

/// Bind groups for module identity, import resolution, and import-cycle checks.
///
/// The module index sorts module keys, resolves imports into module ids, and
/// validates the import graph before declaration lookup consumes it.
pub(in crate::type_checker) struct ModuleIndex {
    pub(in crate::type_checker) scatter_module_records: wgpu::BindGroup,
    pub(in crate::type_checker) build_module_keys: wgpu::BindGroup,
    pub(in crate::type_checker) module_key_radix_dispatch_params:
        LaniusBuffer<ModuleKeyRadixParams>,
    pub(in crate::type_checker) module_key_radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) sort_module_keys_small: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_module_key_histogram: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_module_key_bucket_prefix: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_module_key_bucket_bases: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_module_key_scatter: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) validate_modules: wgpu::BindGroup,
    pub(in crate::type_checker) dependency_module_params:
        Option<LaniusBuffer<DependencyInterfaceModuleParams>>,
    pub(in crate::type_checker) clear_dependency_module_lookup: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) build_dependency_module_lookup: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) resolve_dependency_imports: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) scatter_import_records: wgpu::BindGroup,
    pub(in crate::type_checker) resolve_imports: wgpu::BindGroup,
    pub(in crate::type_checker) seed_import_edge_key_order: wgpu::BindGroup,
    pub(in crate::type_checker) import_edge_key_radix_dispatch: wgpu::BindGroup,
    pub(in crate::type_checker) sort_import_edges_small: Option<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_import_edge_key_histogram: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_import_edge_key_bucket_prefix: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_import_edge_key_bucket_bases: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) sort_import_edge_key_scatter: Vec<wgpu::BindGroup>,
    pub(in crate::type_checker) validate_import_cycles: wgpu::BindGroup,
    pub(in crate::type_checker) retained_key_params: Vec<ModuleKeyRadixStep>,
}

/// Creates bind groups for module indexing and import-edge validation.
pub(in crate::type_checker) fn create_module_index(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    layout: Layout,
    inputs: &CreateInputs<'_>,
    buffers: &Buffers,
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
    let scatter_module_records = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_02_scatter_module_records"),
        &passes.modules_scatter_module_records,
        0,
        &[
            ("gParams", module_record_params.as_entire_binding()),
            (
                "module_record_flag",
                buffers.module_record_flag.as_entire_binding(),
            ),
            (
                "module_record_prefix",
                buffers.module_record_prefix.as_entire_binding(),
            ),
            (
                "hir_item_file_id",
                inputs.hir_items.file_id.as_entire_binding(),
            ),
            (
                "path_id_by_owner_hir",
                buffers.path_id_by_owner_hir.as_entire_binding(),
            ),
            ("module_file_id", buffers.module_file_id.as_entire_binding()),
            ("module_path_id", buffers.module_path_id.as_entire_binding()),
            (
                "module_owner_hir",
                buffers.module_owner_hir.as_entire_binding(),
            ),
        ],
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
    let build_module_keys = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_02e_build_module_keys"),
        &passes.modules_build_module_keys,
        0,
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
            ("status", inputs.status_buf.as_entire_binding()),
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
        &passes.names_radix_dispatch_args,
        "type_check.modules.module_key_radix_dispatch",
        &module_key_radix_dispatch_params,
        &buffers.module_table_count_out,
        &buffers.module_key_radix_dispatch_args,
    )?;

    let sort_module_keys_small = if layout.module_capacity_u32 <= MODULE_KEY_SMALL_SORT_CAPACITY {
        Some(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_02f_sort_module_keys_small"),
            &passes.modules_sort_module_keys_small,
            0,
            &[
                (
                    "gParams",
                    module_key_radix_dispatch_params.as_entire_binding(),
                ),
                (
                    "module_table_count_out",
                    buffers.module_table_count_out.as_entire_binding(),
                ),
                (
                    "module_key_canonical_id",
                    buffers.module_key_canonical_id.as_entire_binding(),
                ),
                (
                    "module_key_order",
                    buffers.module_key_to_module_id.as_entire_binding(),
                ),
            ],
        )?)
    } else {
        None
    };

    let mut retained_key_params = Vec::with_capacity(MODULE_KEY_RADIX_STEPS as usize + 3);
    let mut sort_module_key_histogram = Vec::with_capacity(MODULE_KEY_RADIX_STEPS as usize);
    let mut sort_module_key_bucket_prefix = Vec::with_capacity(MODULE_KEY_RADIX_STEPS as usize);
    let mut sort_module_key_bucket_bases = Vec::with_capacity(MODULE_KEY_RADIX_STEPS as usize);
    let mut sort_module_key_scatter = Vec::with_capacity(MODULE_KEY_RADIX_STEPS as usize);
    for key_step in 0..MODULE_KEY_RADIX_STEPS {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.modules.module_key_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: layout.module_capacity_u32,
                reserved: 0,
                n_blocks: layout.module_n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            &buffers.module_key_to_module_id
        } else {
            &buffers.module_key_order_tmp
        };
        let write_order = if key_step % 2 == 0 {
            &buffers.module_key_order_tmp
        } else {
            &buffers.module_key_to_module_id
        };

        sort_module_key_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_03_sort_module_keys_histogram"),
            &passes.modules_sort_module_keys_histogram,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "module_table_count_out",
                    buffers.module_table_count_out.as_entire_binding(),
                ),
                (
                    "module_key_canonical_id",
                    buffers.module_key_canonical_id.as_entire_binding(),
                ),
                ("module_key_order_in", read_order.as_entire_binding()),
                (
                    "radix_block_histogram",
                    buffers.module_key_radix_block_histogram.as_entire_binding(),
                ),
            ],
        )?);

        sort_module_key_bucket_prefix.push(create_radix_bucket_prefix(
            device,
            &passes.names_radix_bucket_prefix,
            "type_check_modules.module_key_radix_bucket_prefix",
            &step_params,
            &buffers.module_table_count_out,
            &buffers.module_key_radix_block_histogram,
            &buffers.module_key_radix_block_bucket_prefix,
            &buffers.module_key_radix_bucket_total,
        )?);

        sort_module_key_bucket_bases.push(create_radix_bucket_bases(
            device,
            &passes.names_radix_bucket_bases,
            "type_check_modules.module_key_radix_bucket_bases",
            &step_params,
            &buffers.module_key_radix_bucket_total,
            &buffers.module_key_radix_bucket_base,
        )?);

        sort_module_key_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_03b_sort_module_keys_scatter"),
            &passes.modules_sort_module_keys_scatter,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "module_table_count_out",
                    buffers.module_table_count_out.as_entire_binding(),
                ),
                (
                    "module_key_canonical_id",
                    buffers.module_key_canonical_id.as_entire_binding(),
                ),
                ("module_key_order_in", read_order.as_entire_binding()),
                (
                    "radix_bucket_base",
                    buffers.module_key_radix_bucket_base.as_entire_binding(),
                ),
                (
                    "radix_block_bucket_prefix",
                    buffers
                        .module_key_radix_block_bucket_prefix
                        .as_entire_binding(),
                ),
                ("module_key_order_out", write_order.as_entire_binding()),
            ],
        )?);

        retained_key_params.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

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
    let validate_modules = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_04_validate_modules"),
        &passes.modules_validate_modules,
        0,
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
            ("status", inputs.status_buf.as_entire_binding()),
            ("module_status", buffers.module_status.as_entire_binding()),
        ],
    )?;

    retained_key_params.push(ModuleKeyRadixStep {
        _params: validate_module_params,
    });

    let scatter_import_records = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_02b_scatter_import_records"),
        &passes.modules_scatter_import_records,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            (
                "import_record_flag",
                buffers.import_record_flag.as_entire_binding(),
            ),
            (
                "import_record_prefix",
                buffers.import_record_prefix.as_entire_binding(),
            ),
            (
                "hir_item_file_id",
                inputs.hir_items.file_id.as_entire_binding(),
            ),
            (
                "hir_item_import_target_kind",
                inputs.hir_items.import_target_kind.as_entire_binding(),
            ),
            (
                "path_id_by_owner_hir",
                buffers.path_id_by_owner_hir.as_entire_binding(),
            ),
            (
                "import_module_file_id",
                buffers.import_module_file_id.as_entire_binding(),
            ),
            ("import_path_id", buffers.import_path_id.as_entire_binding()),
            ("import_kind", buffers.import_kind.as_entire_binding()),
            (
                "import_owner_hir",
                buffers.import_owner_hir.as_entire_binding(),
            ),
        ],
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
    let resolve_imports = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_05_resolve_imports"),
        &passes.modules_resolve_imports,
        0,
        &[
            ("gParams", resolve_import_params.as_entire_binding()),
            (
                "import_count_out",
                buffers.import_count_out.as_entire_binding(),
            ),
            ("import_kind", buffers.import_kind.as_entire_binding()),
            ("import_path_id", buffers.import_path_id.as_entire_binding()),
            (
                "import_module_id",
                buffers.import_module_id.as_entire_binding(),
            ),
            (
                "import_owner_hir",
                buffers.import_owner_hir.as_entire_binding(),
            ),
            (
                "hir_token_pos",
                inputs.hir_token_pos_buf.as_entire_binding(),
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
            ("status", inputs.status_buf.as_entire_binding()),
            (
                "import_target_module_id",
                buffers.import_target_module_id.as_entire_binding(),
            ),
            ("import_status", buffers.import_status.as_entire_binding()),
        ],
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
        (Some(dependencies), Some(params)) => Some(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.dependencies.build_module_lookup"),
            &passes.dependencies.build_module_lookup,
            0,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "dependency_module_words",
                    dependencies.module_words.as_entire_binding(),
                ),
                (
                    "dependency_module_segment_words",
                    dependencies.module_segment_words.as_entire_binding(),
                ),
                (
                    "dependency_module_lookup",
                    dependencies.module_lookup.as_entire_binding(),
                ),
                ("status", inputs.status_buf.as_entire_binding()),
            ],
        )?),
        _ => None,
    };
    let clear_dependency_module_lookup = match (
        inputs.dependency_interfaces,
        dependency_module_params.as_ref(),
    ) {
        (Some(dependencies), Some(params)) => Some(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.dependencies.clear_module_lookup"),
            &passes.dependencies.clear_module_lookup,
            0,
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
            Some(bind_group::create_bind_group_from_bindings(
                device,
                Some("type_check.dependencies.resolve_imports"),
                &passes.dependencies.resolve_imports,
                0,
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
                    ("name_hash_lo", inputs.name_hash_lo.as_entire_binding()),
                    ("name_hash_hi", inputs.name_hash_hi.as_entire_binding()),
                    ("name_spans", inputs.name_spans.as_entire_binding()),
                    ("source_bytes", inputs.source_buf.as_entire_binding()),
                    (
                        "dependency_module_words",
                        dependencies.module_words.as_entire_binding(),
                    ),
                    (
                        "dependency_module_segment_words",
                        dependencies.module_segment_words.as_entire_binding(),
                    ),
                    (
                        "dependency_name_byte_words",
                        dependencies.name_byte_words.as_entire_binding(),
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
                    ("status", inputs.status_buf.as_entire_binding()),
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
        &passes.names_radix_dispatch_args,
        "type_check.modules.import_edge_key_radix_dispatch",
        &import_edge_key_radix_params,
        &buffers.import_count_out,
        &buffers.import_edge_key_radix_dispatch_args,
    )?;

    let seed_import_edge_key_order = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_05e_seed_import_edge_key_order"),
        &passes.modules_seed_import_edge_key_order,
        0,
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

    let sort_import_edges_small =
        if layout.import_record_capacity_u32 <= MODULE_RELATION_SMALL_SORT_CAPACITY {
            Some(bind_group::create_bind_group_from_bindings(
                device,
                Some("type_check_modules_05e2_sort_import_edges_small"),
                &passes.modules_sort_import_edges_small,
                0,
                &[
                    ("gParams", import_edge_key_radix_params.as_entire_binding()),
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
                    ("import_status", buffers.import_status.as_entire_binding()),
                    (
                        "import_edge_key_order",
                        buffers.import_edge_key_order.as_entire_binding(),
                    ),
                ],
            )?)
        } else {
            None
        };

    let mut sort_import_edge_key_histogram =
        Vec::with_capacity(IMPORT_EDGE_KEY_RADIX_STEPS as usize);
    let mut sort_import_edge_key_bucket_prefix =
        Vec::with_capacity(IMPORT_EDGE_KEY_RADIX_STEPS as usize);
    let mut sort_import_edge_key_bucket_bases =
        Vec::with_capacity(IMPORT_EDGE_KEY_RADIX_STEPS as usize);
    let mut sort_import_edge_key_scatter = Vec::with_capacity(IMPORT_EDGE_KEY_RADIX_STEPS as usize);
    for key_step in 0..IMPORT_EDGE_KEY_RADIX_STEPS {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.modules.import_edge_key_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: layout.import_record_capacity_u32,
                reserved: 0,
                n_blocks: layout.record_n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            &buffers.import_edge_key_order
        } else {
            &buffers.import_edge_key_order_tmp
        };
        let write_order = if key_step % 2 == 0 {
            &buffers.import_edge_key_order_tmp
        } else {
            &buffers.import_edge_key_order
        };

        sort_import_edge_key_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_05f_sort_import_edges"),
            &passes.modules_sort_import_edges,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
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
                ("import_status", buffers.import_status.as_entire_binding()),
                ("import_edge_key_order_in", read_order.as_entire_binding()),
                (
                    "radix_block_histogram",
                    buffers.decl_key_radix_block_histogram.as_entire_binding(),
                ),
            ],
        )?);

        sort_import_edge_key_bucket_prefix.push(create_radix_bucket_prefix(
            device,
            &passes.names_radix_bucket_prefix,
            "type_check_modules.import_edge_key_radix_bucket_prefix",
            &step_params,
            &buffers.import_count_out,
            &buffers.decl_key_radix_block_histogram,
            &buffers.decl_key_radix_block_bucket_prefix,
            &buffers.decl_key_radix_bucket_total,
        )?);

        sort_import_edge_key_bucket_bases.push(create_radix_bucket_bases(
            device,
            &passes.names_radix_bucket_bases,
            "type_check_modules.import_edge_key_radix_bucket_bases",
            &step_params,
            &buffers.decl_key_radix_bucket_total,
            &buffers.decl_key_radix_bucket_base,
        )?);

        sort_import_edge_key_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_05g_sort_import_edges_scatter"),
            &passes.modules_sort_import_edges_scatter,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
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
                ("import_status", buffers.import_status.as_entire_binding()),
                ("import_edge_key_order_in", read_order.as_entire_binding()),
                (
                    "radix_bucket_base",
                    buffers.decl_key_radix_bucket_base.as_entire_binding(),
                ),
                (
                    "radix_block_bucket_prefix",
                    buffers
                        .decl_key_radix_block_bucket_prefix
                        .as_entire_binding(),
                ),
                ("import_edge_key_order_out", write_order.as_entire_binding()),
            ],
        )?);

        retained_key_params.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

    let validate_import_cycles = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_05h_validate_import_cycles"),
        &passes.modules_validate_import_cycles,
        0,
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
            ("status", inputs.status_buf.as_entire_binding()),
            ("import_status", buffers.import_status.as_entire_binding()),
        ],
    )?;

    retained_key_params.push(ModuleKeyRadixStep {
        _params: resolve_import_params,
    });
    retained_key_params.push(ModuleKeyRadixStep {
        _params: import_edge_key_radix_params,
    });
    retained_key_params.push(ModuleKeyRadixStep {
        _params: module_record_params,
    });
    retained_key_params.push(ModuleKeyRadixStep {
        _params: module_key_build_params,
    });

    Ok(ModuleIndex {
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
        dependency_module_params,
        clear_dependency_module_lookup,
        build_dependency_module_lookup,
        resolve_dependency_imports,
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
        retained_key_params,
    })
}
