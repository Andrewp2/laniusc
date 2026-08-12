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
        &groups.compact_hir_dispatch,
        "type_check.visible.compact_hir_dispatch_args",
        1,
    )?;
    groups.mark_hir_declarations.record(encoder)?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.visible.mark_hir_decl_names.done",
    );
    record_compute(
        encoder,
        &passes.kernel("type_checker/count/dispatch_args"),
        &groups.match_payload_dispatch,
        "type_check.visible.match_payload_dispatch_args",
        1,
    )?;
    groups.mark_match_payload_declarations.record(encoder)?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.visible.mark_match_payload_decls.done",
    );
    groups.declaration_scan.record(encoder)?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.visible.decl_scan.done");
    groups.scatter_declarations.record(encoder)?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.visible.scatter_decl_records.done",
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
        &groups.compact_hir_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.visible.hir_names.done");
    Ok(())
}
