use super::super::*;

/// Builds visible-declaration collection, sorting, and scope-tree operations
/// from the reflected compiler graph.
pub(in crate::type_checker) fn create_resident_visible_bind_groups(
    passes: &TypeCheckPasses,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    device: &wgpu::Device,
    resources: &ResourceMap<'_>,
    shape: VisibleShape,
) -> Result<VisibleBindGroups> {
    let reflected = |label, kernel| {
        reflected_bind_group_from_resources(device, label, &passes.kernel(kernel), resources)
    };
    let clear = reflected(
        "type_check_visible_01_clear",
        "type_checker/visible/01/clear/resident",
    )?;
    let compact_hir_dispatch_args =
        typed_buffer_from_resources(resources, "compact_hir_dispatch_args")?;
    let compact_hir_dispatch_params = uniform_from_val(
        device,
        "type_check.visible.compact_hir_dispatch.params",
        &CountDispatchParams {
            capacity: shape.hir_nodes.max(1),
            multiplier: 1,
            reserved0: 0,
            reserved1: 0,
        },
    );
    let compact_hir_dispatch = reflected_bind_group_with_overrides(
        device,
        "type_check.visible.compact_hir_dispatch",
        &passes.kernel("type_checker/count/dispatch_args"),
        resources,
        &[
            ("gParams", compact_hir_dispatch_params.as_entire_binding()),
            ("count_in", resources["compact_hir_count"].clone()),
            (
                "dispatch_args",
                compact_hir_dispatch_args.as_entire_binding(),
            ),
        ],
    )?;
    let hir_declarations = CompactionOperation::indirect(
        device,
        graph,
        resources,
        passes,
        VISIBLE_DECL_COMPACTION,
        &compact_hir_dispatch_args,
    )?;
    let match_payload_dispatch_args = graph.u32_buffer("match_payload_dispatch_args")?;
    let match_payload_dispatch = reflected_bind_group_with_overrides(
        device,
        "type_check.visible.match_payload_dispatch",
        &passes.kernel("type_checker/count/dispatch_args"),
        resources,
        &[
            ("gParams", compact_hir_dispatch_params.as_entire_binding()),
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
    let scatter_match_payload_decls = reflected(
        "type_check_visible_03c2_scatter_match_payload_decls",
        "type_checker/visible/03c2_scatter_match_payload_decls",
    )?;
    let finalize_decl_count = reflected(
        "type_check_visible_03c3_finalize_decl_count",
        "type_checker/visible/03c3_finalize_decl_count",
    )?;

    let declaration_capacity = shape.record_capacity.max(1);
    let declarations = VisibleDeclSort::new(
        device,
        passes,
        resources,
        declaration_capacity,
        shape.record_blocks,
    )?;
    let leaf_params = uniform_from_val(
        device,
        "type_check.visible.hir_decl_scope_tree.leaves.params",
        &VisibleDeclTreeParams {
            decl_capacity: declaration_capacity,
            row_block_size: HIR_VISIBLE_DECL_ROW_BLOCK_SIZE,
            leaf_base: shape.leaf_base,
            level_start: 0,
            level_count: shape.leaf_base,
            reserved0: 0,
            reserved1: 0,
            reserved2: 0,
        },
    );
    let build_hir_decl_scope_leaves = reflected_bind_group_with_overrides(
        device,
        "type_check_visible_03g_build_hir_decl_scope_leaves",
        &passes.kernel("type_checker/visible/03g_build_hir_decl_scope_leaves"),
        resources,
        &[("gParams", leaf_params.as_entire_binding())],
    )?;

    let mut hir_decl_scope_tree_levels = Vec::new();
    let mut level_start = shape.leaf_base / 2;
    while level_start > 0 {
        let level_params = uniform_from_val(
            device,
            &format!("type_check.visible.hir_decl_scope_tree.level.{level_start}"),
            &VisibleDeclTreeParams {
                decl_capacity: declaration_capacity,
                row_block_size: HIR_VISIBLE_DECL_ROW_BLOCK_SIZE,
                leaf_base: shape.leaf_base,
                level_start,
                level_count: level_start,
                reserved0: 0,
                reserved1: 0,
                reserved2: 0,
            },
        );
        let bind_group = reflected_bind_group_with_overrides(
            device,
            "type_check_visible_03h_build_hir_decl_scope_tree",
            &passes.kernel("type_checker/visible/03h_build_hir_decl_scope_tree"),
            resources,
            &[("gParams", level_params.as_entire_binding())],
        )?;
        hir_decl_scope_tree_levels.push(VisibleDeclScopeTreeLevel {
            _params: level_params,
            bind_group,
            work_items: level_start,
        });
        level_start /= 2;
    }

    let hir_names = reflected(
        "type_check_visible_04_hir_names",
        "type_checker/visible/04_hir_names",
    )?;
    Ok(VisibleBindGroups {
        compact_hir_dispatch_args: typed_alias_storage_u32(&compact_hir_dispatch_args, 3),
        match_payload_dispatch_args,
        clear,
        compact_hir_dispatch,
        hir_declarations,
        match_payload_dispatch,
        scatter_match_payload_decls,
        finalize_decl_count,
        declarations,
        _compact_hir_dispatch_params: compact_hir_dispatch_params,
        _hir_decl_scope_leaf_params: leaf_params,
        build_hir_decl_scope_leaves,
        hir_decl_scope_leaf_work_items: shape.leaf_base,
        hir_decl_scope_tree_levels,
        hir_names,
    })
}
