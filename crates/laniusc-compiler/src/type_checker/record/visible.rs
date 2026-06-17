// src/type_checker/record/visible.rs

use super::*;

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
        &passes.visible_clear_resident,
        &groups.clear,
        "type_check.visible.clear",
        name_clear_n,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.visible.clear.done");
    record_compute(
        encoder,
        &passes.count_dispatch_args,
        &groups.hir_semantic_dispatch,
        "type_check.visible.hir_semantic_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.visible_mark_hir_decl_names,
        &groups.mark_hir_decl_names,
        "type_check.visible.mark_hir_decl_names",
        &groups.hir_semantic_dispatch_args,
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.visible.mark_hir_decl_names.done",
    );
    record_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        groups.hir_decl_scan_n_blocks,
        &groups.hir_semantic_dispatch_args,
        &groups.hir_decl_scan,
        "type_check.visible.hir_decl_scan",
    )?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.visible.hir_decl_scan.done");
    record_compute_indirect(
        encoder,
        &passes.visible_scatter_hir_decl_records,
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
        &passes.names_radix_dispatch_args,
        &groups.hir_decl_key_radix_dispatch,
        "type_check.visible.hir_decl_key_radix_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.visible_seed_hir_decl_order,
        &groups.seed_hir_decl_order,
        "type_check.visible.seed_hir_decl_order",
        &groups.hir_decl_key_radix_dispatch_args,
    )?;
    for i in 0..groups.sort_hir_decl_key_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.visible_sort_hir_decl_keys,
            &groups.sort_hir_decl_key_histogram[i],
            "type_check.visible.sort_hir_decl_keys_histogram",
            &groups.hir_decl_key_radix_dispatch_args,
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &groups.sort_hir_decl_key_bucket_prefix[i],
            "type_check.visible.sort_hir_decl_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &groups.sort_hir_decl_key_bucket_bases[i],
            "type_check.visible.sort_hir_decl_keys_bucket_bases",
            256,
        )?;
        record_compute_indirect(
            encoder,
            &passes.visible_sort_hir_decl_keys_scatter,
            &groups.sort_hir_decl_key_scatter[i],
            "type_check.visible.sort_hir_decl_keys_scatter",
            &groups.hir_decl_key_radix_dispatch_args,
        )?;
    }
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.visible.sort_hir_decl_keys.done",
    );
    record_compute(
        encoder,
        &passes.visible_build_hir_decl_scope_leaves,
        &groups.build_hir_decl_scope_leaves,
        "type_check.visible.build_hir_decl_scope_leaves",
        groups.hir_decl_scope_leaf_work_items.max(1),
    )?;
    for level in &groups.hir_decl_scope_tree_levels {
        record_compute(
            encoder,
            &passes.visible_build_hir_decl_scope_tree,
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
        &passes.visible_hir_names,
        &groups.hir_names,
        "type_check.visible.hir_names",
        &groups.hir_semantic_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.visible.hir_names.done");
    Ok(())
}
