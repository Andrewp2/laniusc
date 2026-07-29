use super::{super::*, common::reflected_bind_group_from_resources};

/// Builds resident visible-declaration bind groups from loaded type-check passes.
#[allow(clippy::too_many_arguments)]
pub(in crate::type_checker) fn create_resident_visible_bind_groups(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    resources: &ResourceMap<'_>,
    shape: VisibleShape,
    rows: VisibleRows<'_>,
) -> Result<VisibleBindGroups> {
    let clear_pass = &passes.visible_clear_resident;
    let mark_hir_decl_names_pass = &passes.visible_mark_hir_decl_names;
    let count_dispatch_pass = &passes.count_dispatch_args;
    let scatter_hir_decl_records_pass = &passes.visible_scatter_hir_decl_records;
    let scatter_match_payload_decls_pass = &passes.visible_scatter_match_payload_decls;
    let finalize_decl_count_pass = &passes.visible_finalize_decl_count;
    let build_hir_decl_scope_leaves_pass = &passes.visible_build_hir_decl_scope_leaves;
    let build_hir_decl_scope_tree_pass = &passes.visible_build_hir_decl_scope_tree;
    let hir_names_pass = &passes.visible_hir_names;
    let hir_node_capacity = shape.hir_nodes;
    let hir_decl_record_capacity = shape.record_capacity;
    let hir_decl_record_n_blocks = shape.record_blocks;
    let hir_decl_tree_leaf_base = shape.leaf_base;
    let hir_semantic_count = rows.semantic_count;
    let hir_semantic_dispatch_args = rows.semantic_dispatch_args.clone();
    let hir_visible_decl_count_out = rows.count_out;
    let hir_visible_decl_scope_end = rows.scope_end;
    let hir_visible_decl_key_order = rows.order;
    let hir_visible_decl_key_radix_dispatch_args = rows.key_args;
    let hir_visible_decl_scope_tree = rows.scope_tree;

    let clear = reflected_bind_group_from_resources(
        device,
        "type_check_visible_01_clear",
        clear_pass,
        resources,
    )?;
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
    let hir_decl_scan = PrefixScanOperation::from_spec(
        device,
        passes.into(),
        resources,
        compiler_graph::VISIBLE_SCAN,
    )?;
    let scatter_hir_decl_records = reflected_bind_group_from_resources(
        device,
        "type_check_visible_03c_scatter_hir_decls",
        scatter_hir_decl_records_pass,
        resources,
    )?;
    let match_payload_dispatch_args = typed_storage_u32_rw(
        device,
        "type_check.visible.match_payload_dispatch_args",
        3,
        wgpu::BufferUsages::INDIRECT,
    );
    let match_payload_dispatch = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.visible.match_payload_dispatch"),
        count_dispatch_pass,
        0,
        &[
            ("gParams", hir_semantic_dispatch_params.as_entire_binding()),
            (
                "count_in",
                resources["compact_match_payload_row_count"].clone(),
            ),
            (
                "dispatch_args",
                match_payload_dispatch_args.as_entire_binding(),
            ),
        ],
    )?;
    let scatter_match_payload_decls = reflected_bind_group_from_resources(
        device,
        "type_check_visible_03c2_scatter_match_payload_decls",
        scatter_match_payload_decls_pass,
        resources,
    )?;
    let finalize_decl_count = reflected_bind_group_from_resources(
        device,
        "type_check_visible_03c3_finalize_decl_count",
        finalize_decl_count_pass,
        resources,
    )?;

    let hir_decl_capacity = hir_decl_record_capacity.max(1);
    let declarations = VisibleDeclSort::new(
        device,
        passes,
        resources,
        hir_decl_capacity,
        hir_decl_record_n_blocks,
        hir_visible_decl_key_radix_dispatch_args,
    )?;
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
        hir_semantic_dispatch_args,
        match_payload_dispatch_args,
        clear,
        hir_semantic_dispatch,
        mark_hir_decl_names,
        hir_decl_scan,
        scatter_hir_decl_records,
        match_payload_dispatch,
        scatter_match_payload_decls,
        finalize_decl_count,
        declarations,
        _hir_semantic_dispatch_params: hir_semantic_dispatch_params,
        _hir_decl_scope_leaf_params: leaf_params,
        build_hir_decl_scope_leaves,
        hir_decl_scope_leaf_work_items: hir_decl_tree_leaf_base,
        hir_decl_scope_tree_levels,
        hir_names,
    })
}
