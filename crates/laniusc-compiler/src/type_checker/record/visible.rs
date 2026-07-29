// src/type_checker/record/visible.rs

use super::*;

/// Records resident visible-declaration collection, sorting, and scope tree passes.
pub(in crate::type_checker) fn record_visible_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    groups: &VisibleBindGroups,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    let name_clear_n = token_capacity.saturating_add(LANGUAGE_SYMBOL_COUNT).max(1);
    record_compute(
        encoder,
        &passes.kernel("type_checker/visible/01/clear/resident"),
        &groups.clear,
        "type_check.visible.clear",
        name_clear_n,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.visible.clear.done");
    record_compute(
        encoder,
        &passes.kernel("type_checker/count/dispatch_args"),
        &groups.hir_semantic_dispatch,
        "type_check.visible.hir_semantic_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/visible/03b_mark_hir_decl_names"),
        &groups.mark_hir_decl_names,
        "type_check.visible.mark_hir_decl_names",
        &groups.hir_semantic_dispatch_args,
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.visible.mark_hir_decl_names.done",
    );
    groups.hir_decl_scan.record(encoder)?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.visible.hir_decl_scan.done");
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/visible/03c_scatter_hir_decls"),
        &groups.scatter_hir_decl_records,
        "type_check.visible.scatter_hir_decl_records",
        &groups.hir_semantic_dispatch_args,
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.visible.scatter_hir_decl_records.done",
    );
    record_compute(
        encoder,
        &passes.kernel("type_checker/count/dispatch_args"),
        &groups.match_payload_dispatch,
        "type_check.visible.match_payload_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/visible/03c2_scatter_match_payload_decls"),
        &groups.scatter_match_payload_decls,
        "type_check.visible.scatter_match_payload_decls",
        &groups.match_payload_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/visible/03c3_finalize_decl_count"),
        &groups.finalize_decl_count,
        "type_check.visible.finalize_decl_count",
        1,
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.visible.scatter_match_payload_decls.done",
    );
    groups.declarations.record(passes, encoder)?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.visible.sort_hir_decl_keys.done",
    );
    record_compute(
        encoder,
        &passes.kernel("type_checker/visible/03g_build_hir_decl_scope_leaves"),
        &groups.build_hir_decl_scope_leaves,
        "type_check.visible.build_hir_decl_scope_leaves",
        groups.hir_decl_scope_leaf_work_items.max(1),
    )?;
    for level in &groups.hir_decl_scope_tree_levels {
        record_compute(
            encoder,
            &passes.kernel("type_checker/visible/03h_build_hir_decl_scope_tree"),
            &level.bind_group,
            "type_check.visible.build_hir_decl_scope_tree",
            level.work_items.max(1),
        )?;
    }
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.visible.hir_decl_scope_tree.done",
    );
    // The resident path has compact HIR declaration records, so visible uses
    // are resolved below by sorted declaration tables.
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/visible/04_hir_names"),
        &groups.hir_names,
        "type_check.visible.hir_names",
        &groups.hir_semantic_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.visible.hir_names.done");
    Ok(())
}
