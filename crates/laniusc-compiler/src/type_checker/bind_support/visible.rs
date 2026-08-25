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
    let name_clear_n = shape.tokens.saturating_add(LANGUAGE_SYMBOL_COUNT).max(1);
    let clear = ComputeOperation::direct(
        device,
        graph,
        resources,
        compiler_graph::VISIBLE_CLEAR_PASS,
        &passes.kernel("type_checker/visible/01/clear/resident"),
        name_clear_n,
    )?;
    let match_payload_dispatch_params = uniform_from_val(
        device,
        "type_check.visible.match_payload_dispatch.params",
        &CountDispatchParams {
            capacity: shape.hir_nodes.max(1),
            multiplier: 1,
            reserved0: 0,
            reserved1: 0,
        },
    );
    let hir_active_dispatch_args =
        typed_buffer_from_resources(resources, "hir_active_dispatch_args")?;
    let mark_hir_declarations = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        VISIBLE_HIR_DECL_MARK,
        &hir_active_dispatch_args,
    )?;
    let match_payload_dispatch_args = graph.u32_buffer("match_payload_dispatch_args")?;
    let match_payload_dispatch = ComputeOperation::direct_with_uniform(
        device,
        graph,
        resources,
        compiler_graph::VISIBLE_MATCH_DISPATCH_PASS,
        &passes.kernel("type_checker/count/dispatch_args"),
        &match_payload_dispatch_params,
        1,
    )?;
    let mark_match_payload_declarations = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        VISIBLE_MATCH_DECL_MARK,
        &match_payload_dispatch_args,
    )?;
    let declaration_scan =
        PrefixScanOperation::from_spec(device, passes, resources, compiler_graph::VISIBLE_SCAN)?;
    let token_active_dispatch_args =
        typed_buffer_from_resources(resources, "token_active_dispatch_args")?;
    let scatter_declarations = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        VISIBLE_DECL_SCATTER,
        &token_active_dispatch_args,
    )?;

    let declaration_capacity = shape.record_capacity.max(1);
    let declarations = VisibleDeclSort::new(
        device,
        graph,
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
    let build_hir_decl_scope_leaves = ComputeOperation::direct_with_uniform(
        device,
        graph,
        resources,
        VISIBLE_SCOPE_TREE_LEAVES.name,
        &passes.kernel("type_checker/visible/03g_build_hir_decl_scope_leaves"),
        &leaf_params,
        shape.leaf_base.max(1),
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
        let operation = ComputeOperation::direct_with_uniform(
            device,
            graph,
            resources,
            VISIBLE_SCOPE_TREE_LEVEL.name,
            &passes.kernel("type_checker/visible/03h_build_hir_decl_scope_tree"),
            &level_params,
            level_start.max(1),
        )?;
        hir_decl_scope_tree_levels.push(VisibleDeclScopeTreeLevel {
            _params: level_params,
            operation,
        });
        level_start /= 2;
    }

    let hir_names = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        VISIBLE_NAMES,
        &hir_active_dispatch_args,
    )?;
    Ok(VisibleBindGroups {
        clear,
        mark_hir_declarations,
        match_payload_dispatch,
        mark_match_payload_declarations,
        declaration_scan,
        scatter_declarations,
        declarations,
        _match_payload_dispatch_params: match_payload_dispatch_params,
        _hir_decl_scope_leaf_params: leaf_params,
        build_hir_decl_scope_leaves,
        hir_decl_scope_tree_levels,
        hir_names,
    })
}
