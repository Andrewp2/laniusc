use super::{
    super::*,
    common::reflected_bind_group_from_resources,
    scan::create_counted_u32_scan_bind_groups_from_passes,
};

#[allow(clippy::too_many_arguments)]
pub(in crate::type_checker) fn create_resident_visible_bind_groups(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
    shape: VisibleShape,
    steps: &[NameScanStep],
    rows: VisibleRows<'_>,
) -> Result<VisibleBindGroups> {
    create_visible_bind_groups_from_passes(
        device,
        resources,
        &passes.visible_clear_resident,
        &passes.visible_mark_hir_decl_names,
        &passes.count_dispatch_args,
        &passes.counted_scan_local,
        &passes.counted_scan_blocks,
        &passes.counted_scan_apply,
        &passes.visible_scatter_hir_decl_records,
        &passes.visible_seed_hir_decl_order,
        &passes.visible_sort_hir_decl_keys,
        &passes.visible_sort_hir_decl_keys_scatter,
        &passes.visible_build_hir_decl_scope_leaves,
        &passes.visible_build_hir_decl_scope_tree,
        &passes.names_radix_dispatch_args,
        &passes.names_radix_bucket_prefix,
        &passes.names_radix_bucket_bases,
        &passes.visible_hir_names,
        shape.hir_nodes,
        shape.scan_blocks,
        shape.record_capacity,
        shape.record_blocks,
        shape.leaf_base,
        steps,
        rows.active_count,
        rows.semantic_count,
        rows.flag,
        rows.prefix,
        rows.scan.local_prefix,
        rows.scan.block_sum,
        rows.scan.prefix_a,
        rows.scan.prefix_b,
        rows.count_out,
        rows.owner_fn,
        rows.name_id,
        rows.token,
        rows.scope_end,
        rows.order,
        rows.order_tmp,
        rows.key_args,
        rows.key_radix.histogram,
        rows.key_radix.bucket_prefix,
        rows.key_radix.bucket_total,
        rows.key_radix.bucket_base,
        rows.scope_tree,
    )
}

#[allow(clippy::too_many_arguments)]
pub(in crate::type_checker) fn create_visible_bind_groups_from_passes(
    device: &wgpu::Device,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
    clear_pass: &PassData,
    mark_hir_decl_names_pass: &PassData,
    count_dispatch_pass: &PassData,
    counted_scan_local_pass: &PassData,
    counted_scan_blocks_pass: &PassData,
    counted_scan_apply_pass: &PassData,
    scatter_hir_decl_records_pass: &PassData,
    seed_hir_decl_order_pass: &PassData,
    sort_hir_decl_keys_pass: &PassData,
    sort_hir_decl_keys_scatter_pass: &PassData,
    build_hir_decl_scope_leaves_pass: &PassData,
    build_hir_decl_scope_tree_pass: &PassData,
    radix_dispatch_pass: &PassData,
    radix_bucket_prefix_pass: &PassData,
    radix_bucket_bases_pass: &PassData,
    hir_names_pass: &PassData,
    hir_node_capacity: u32,
    hir_decl_scan_n_blocks: u32,
    hir_decl_record_capacity: u32,
    hir_decl_record_n_blocks: u32,
    hir_decl_tree_leaf_base: u32,
    hir_decl_scan_steps: &[NameScanStep],
    _hir_active_count: &wgpu::Buffer,
    hir_semantic_count: &wgpu::Buffer,
    hir_visible_decl_flag: &wgpu::Buffer,
    hir_visible_decl_prefix: &wgpu::Buffer,
    hir_visible_decl_scan_local_prefix: &wgpu::Buffer,
    hir_visible_decl_scan_block_sum: &wgpu::Buffer,
    hir_visible_decl_scan_prefix_a: &wgpu::Buffer,
    hir_visible_decl_scan_prefix_b: &wgpu::Buffer,
    hir_visible_decl_count_out: &wgpu::Buffer,
    hir_visible_decl_owner_fn: &wgpu::Buffer,
    hir_visible_decl_name_id: &wgpu::Buffer,
    hir_visible_decl_token: &wgpu::Buffer,
    hir_visible_decl_scope_end: &wgpu::Buffer,
    hir_visible_decl_key_order: &wgpu::Buffer,
    hir_visible_decl_key_order_tmp: &wgpu::Buffer,
    hir_visible_decl_key_radix_dispatch_args: &wgpu::Buffer,
    hir_visible_decl_key_radix_block_histogram: &wgpu::Buffer,
    hir_visible_decl_key_radix_block_bucket_prefix: &wgpu::Buffer,
    hir_visible_decl_key_radix_bucket_total: &wgpu::Buffer,
    hir_visible_decl_key_radix_bucket_base: &wgpu::Buffer,
    hir_visible_decl_scope_tree: &wgpu::Buffer,
) -> Result<VisibleBindGroups> {
    let clear = reflected_bind_group_from_resources(
        device,
        "type_check_visible_01_clear",
        clear_pass,
        resources,
    )?;
    let hir_semantic_dispatch_args = typed_storage_u32_rw(
        device,
        "type_check.visible.hir_semantic_dispatch_args",
        3,
        wgpu::BufferUsages::INDIRECT,
    );
    let hir_semantic_dispatch_params = uniform_from_val(
        device,
        "type_check.visible.hir_semantic_dispatch.params",
        &CountDispatchParams {
            capacity: hir_node_capacity.max(1),
            multiplier: 1,
            reserved0: 0,
            reserved1: 0,
        },
    );
    let hir_semantic_dispatch = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.visible.hir_semantic_dispatch"),
        count_dispatch_pass,
        0,
        &[
            ("gParams", hir_semantic_dispatch_params.as_entire_binding()),
            ("count_in", hir_semantic_count.as_entire_binding()),
            (
                "dispatch_args",
                hir_semantic_dispatch_args.as_entire_binding(),
            ),
        ],
    )?;
    let mark_hir_decl_names = reflected_bind_group_from_resources(
        device,
        "type_check_visible_03b_mark_hir_decl_names",
        mark_hir_decl_names_pass,
        resources,
    )?;
    let hir_decl_scan = create_counted_u32_scan_bind_groups_from_passes(
        counted_scan_local_pass,
        counted_scan_blocks_pass,
        counted_scan_apply_pass,
        device,
        "type_check.visible.hir_decl_scan",
        hir_decl_scan_steps,
        hir_semantic_count,
        hir_visible_decl_flag,
        hir_visible_decl_prefix,
        hir_visible_decl_count_out,
        hir_visible_decl_scan_local_prefix,
        hir_visible_decl_scan_block_sum,
        hir_visible_decl_scan_prefix_a,
        hir_visible_decl_scan_prefix_b,
    )?;
    let scatter_hir_decl_records = reflected_bind_group_from_resources(
        device,
        "type_check_visible_03c_scatter_hir_decls",
        scatter_hir_decl_records_pass,
        resources,
    )?;

    let hir_decl_capacity = hir_decl_record_capacity.max(1);
    let hir_decl_key_radix_bytes = visible_decl_key_radix_bytes(hir_decl_capacity);
    let hir_decl_key_radix_steps = visible_decl_key_radix_steps(hir_decl_capacity);
    let hir_decl_key_radix_dispatch_params = uniform_from_val(
        device,
        "type_check.visible.hir_decl_key_radix.dispatch_params",
        &ModuleKeyRadixParams {
            module_capacity: hir_decl_capacity,
            reserved: hir_decl_key_radix_bytes,
            n_blocks: hir_decl_record_n_blocks,
            key_step: 0,
        },
    );
    let hir_decl_key_radix_dispatch = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.visible.hir_decl_key_radix_dispatch"),
        radix_dispatch_pass,
        0,
        &[
            (
                "gParams",
                hir_decl_key_radix_dispatch_params.as_entire_binding(),
            ),
            (
                "name_count_in",
                hir_visible_decl_count_out.as_entire_binding(),
            ),
            (
                "radix_dispatch_args",
                hir_visible_decl_key_radix_dispatch_args.as_entire_binding(),
            ),
        ],
    )?;

    let seed_hir_decl_order = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_visible_03d_seed_hir_decl_order"),
        seed_hir_decl_order_pass,
        0,
        &[
            (
                "gParams",
                hir_decl_key_radix_dispatch_params.as_entire_binding(),
            ),
            (
                "hir_visible_decl_count_out",
                hir_visible_decl_count_out.as_entire_binding(),
            ),
            (
                "hir_visible_decl_key_order",
                hir_visible_decl_key_order.as_entire_binding(),
            ),
        ],
    )?;

    let mut hir_decl_key_radix_step_params = Vec::with_capacity(hir_decl_key_radix_steps as usize);
    let mut sort_hir_decl_key_histogram = Vec::with_capacity(hir_decl_key_radix_steps as usize);
    let mut sort_hir_decl_key_bucket_prefix = Vec::with_capacity(hir_decl_key_radix_steps as usize);
    let mut sort_hir_decl_key_bucket_bases = Vec::with_capacity(hir_decl_key_radix_steps as usize);
    let mut sort_hir_decl_key_scatter = Vec::with_capacity(hir_decl_key_radix_steps as usize);
    for key_step in 0..hir_decl_key_radix_steps {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.visible.hir_decl_key_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: hir_decl_capacity,
                reserved: hir_decl_key_radix_bytes,
                n_blocks: hir_decl_record_n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            hir_visible_decl_key_order
        } else {
            hir_visible_decl_key_order_tmp
        };
        let write_order = if key_step % 2 == 0 {
            hir_visible_decl_key_order_tmp
        } else {
            hir_visible_decl_key_order
        };

        sort_hir_decl_key_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_visible_03e_sort_hir_decl_keys"),
            sort_hir_decl_keys_pass,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "hir_visible_decl_count_out",
                    hir_visible_decl_count_out.as_entire_binding(),
                ),
                (
                    "hir_visible_decl_owner_fn",
                    hir_visible_decl_owner_fn.as_entire_binding(),
                ),
                (
                    "hir_visible_decl_name_id",
                    hir_visible_decl_name_id.as_entire_binding(),
                ),
                (
                    "hir_visible_decl_token",
                    hir_visible_decl_token.as_entire_binding(),
                ),
                (
                    "hir_visible_decl_key_order_in",
                    read_order.as_entire_binding(),
                ),
                (
                    "radix_block_histogram",
                    hir_visible_decl_key_radix_block_histogram.as_entire_binding(),
                ),
            ],
        )?);

        sort_hir_decl_key_bucket_prefix.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.visible.hir_decl_key_radix_bucket_prefix"),
            radix_bucket_prefix_pass,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "name_count_in",
                    hir_visible_decl_count_out.as_entire_binding(),
                ),
                (
                    "radix_block_histogram",
                    hir_visible_decl_key_radix_block_histogram.as_entire_binding(),
                ),
                (
                    "radix_block_bucket_prefix",
                    hir_visible_decl_key_radix_block_bucket_prefix.as_entire_binding(),
                ),
                (
                    "radix_bucket_total",
                    hir_visible_decl_key_radix_bucket_total.as_entire_binding(),
                ),
            ],
        )?);

        sort_hir_decl_key_bucket_bases.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.visible.hir_decl_key_radix_bucket_bases"),
            radix_bucket_bases_pass,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "radix_bucket_total",
                    hir_visible_decl_key_radix_bucket_total.as_entire_binding(),
                ),
                (
                    "radix_bucket_base",
                    hir_visible_decl_key_radix_bucket_base.as_entire_binding(),
                ),
            ],
        )?);

        sort_hir_decl_key_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_visible_03f_sort_hir_decl_keys_scatter"),
            sort_hir_decl_keys_scatter_pass,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "hir_visible_decl_count_out",
                    hir_visible_decl_count_out.as_entire_binding(),
                ),
                (
                    "hir_visible_decl_owner_fn",
                    hir_visible_decl_owner_fn.as_entire_binding(),
                ),
                (
                    "hir_visible_decl_name_id",
                    hir_visible_decl_name_id.as_entire_binding(),
                ),
                (
                    "hir_visible_decl_token",
                    hir_visible_decl_token.as_entire_binding(),
                ),
                (
                    "hir_visible_decl_key_order_in",
                    read_order.as_entire_binding(),
                ),
                (
                    "radix_bucket_base",
                    hir_visible_decl_key_radix_bucket_base.as_entire_binding(),
                ),
                (
                    "radix_block_bucket_prefix",
                    hir_visible_decl_key_radix_block_bucket_prefix.as_entire_binding(),
                ),
                (
                    "hir_visible_decl_key_order_out",
                    write_order.as_entire_binding(),
                ),
            ],
        )?);
        hir_decl_key_radix_step_params.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

    let leaf_params = uniform_from_val(
        device,
        "type_check.visible.hir_decl_scope_tree.leaves.params",
        &VisibleDeclTreeParams {
            decl_capacity: hir_decl_capacity,
            row_block_size: HIR_VISIBLE_DECL_ROW_BLOCK_SIZE,
            leaf_base: hir_decl_tree_leaf_base,
            level_start: 0,
            level_count: hir_decl_tree_leaf_base,
            reserved0: 0,
            reserved1: 0,
            reserved2: 0,
        },
    );
    let build_hir_decl_scope_leaves = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_visible_03g_build_hir_decl_scope_leaves"),
        build_hir_decl_scope_leaves_pass,
        0,
        &[
            ("gParams", leaf_params.as_entire_binding()),
            (
                "hir_visible_decl_count_out",
                hir_visible_decl_count_out.as_entire_binding(),
            ),
            (
                "hir_visible_decl_scope_end",
                hir_visible_decl_scope_end.as_entire_binding(),
            ),
            (
                "hir_visible_decl_key_order",
                hir_visible_decl_key_order.as_entire_binding(),
            ),
            (
                "hir_visible_decl_scope_tree",
                hir_visible_decl_scope_tree.as_entire_binding(),
            ),
        ],
    )?;

    let mut hir_decl_scope_tree_levels = Vec::new();
    let mut level_start = hir_decl_tree_leaf_base / 2;
    while level_start > 0 {
        let level_params = uniform_from_val(
            device,
            &format!("type_check.visible.hir_decl_scope_tree.level.{level_start}"),
            &VisibleDeclTreeParams {
                decl_capacity: hir_decl_capacity,
                row_block_size: HIR_VISIBLE_DECL_ROW_BLOCK_SIZE,
                leaf_base: hir_decl_tree_leaf_base,
                level_start,
                level_count: level_start,
                reserved0: 0,
                reserved1: 0,
                reserved2: 0,
            },
        );
        let bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_visible_03h_build_hir_decl_scope_tree"),
            build_hir_decl_scope_tree_pass,
            0,
            &[
                ("gParams", level_params.as_entire_binding()),
                (
                    "hir_visible_decl_scope_tree",
                    hir_visible_decl_scope_tree.as_entire_binding(),
                ),
            ],
        )?;
        hir_decl_scope_tree_levels.push(VisibleDeclScopeTreeLevel {
            _params: level_params,
            bind_group,
            work_items: level_start,
        });
        level_start /= 2;
    }

    let hir_names = reflected_bind_group_from_resources(
        device,
        "type_check_visible_04_hir_names",
        hir_names_pass,
        resources,
    )?;

    Ok(VisibleBindGroups {
        hir_decl_scan_n_blocks,
        hir_semantic_dispatch_args,
        clear,
        hir_semantic_dispatch,
        mark_hir_decl_names,
        hir_decl_scan,
        scatter_hir_decl_records,
        seed_hir_decl_order,
        hir_decl_key_radix_dispatch,
        hir_decl_key_radix_dispatch_args: typed_alias_storage_u32(
            hir_visible_decl_key_radix_dispatch_args,
            3,
        ),
        _hir_semantic_dispatch_params: hir_semantic_dispatch_params,
        _hir_decl_key_radix_dispatch_params: hir_decl_key_radix_dispatch_params,
        _hir_decl_key_radix_steps: hir_decl_key_radix_step_params,
        sort_hir_decl_key_histogram,
        sort_hir_decl_key_bucket_prefix,
        sort_hir_decl_key_bucket_bases,
        sort_hir_decl_key_scatter,
        _hir_decl_scope_leaf_params: leaf_params,
        build_hir_decl_scope_leaves,
        hir_decl_scope_leaf_work_items: hir_decl_tree_leaf_base,
        hir_decl_scope_tree_levels,
        hir_names,
    })
}
