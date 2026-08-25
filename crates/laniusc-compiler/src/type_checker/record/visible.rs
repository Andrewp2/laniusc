// src/type_checker/record/visible.rs

use super::*;

/// Records resident visible-declaration collection, sorting, and scope tree passes.
pub(in crate::type_checker) fn record_visible_bind_groups_with_passes(
    encoder: &mut wgpu::CommandEncoder,
    groups: &VisibleBindGroups,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    groups.clear.record(encoder)?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.visible.clear.done");
    groups.mark_hir_declarations.record(encoder)?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.visible.mark_hir_decl_names.done",
    );
    groups.match_payload_dispatch.record(encoder)?;
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
    groups.declarations.record(encoder)?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.visible.sort_hir_decl_keys.done",
    );
    groups.build_hir_decl_scope_leaves.record(encoder)?;
    for level in &groups.hir_decl_scope_tree_levels {
        level.operation.record(encoder)?;
    }
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.visible.hir_decl_scope_tree.done",
    );
    // The resident path has compact HIR declaration records, so visible uses
    // are resolved below by sorted declaration tables.
    groups.hir_names.record(encoder)?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.visible.hir_names.done");
    Ok(())
}
