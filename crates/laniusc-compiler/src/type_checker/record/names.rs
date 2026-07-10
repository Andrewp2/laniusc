// src/type_checker/record/names.rs

use super::*;

/// Records lexeme marking, compaction, radix sorting, deduping, and name-id assignment.
pub(in crate::type_checker) fn record_name_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    _token_capacity: u32,
    _name_capacity: u32,
    token_active_dispatch_args: &wgpu::Buffer,
    groups: &NameBindGroups,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.names_mark_lexemes,
        &groups.mark,
        "type_check.names.mark_lexemes",
        token_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.counted_scan_local,
        &groups.scan_local,
        "type_check.names.scan_local",
        token_active_dispatch_args,
    )?;
    for bind_group in &groups.scan_blocks {
        record_compute(
            encoder,
            &passes.counted_scan_blocks,
            bind_group,
            "type_check.names.scan_blocks",
            groups.token_scan_n_blocks.max(1),
        )?;
    }
    record_compute_indirect(
        encoder,
        &passes.counted_scan_apply,
        &groups.scan_apply,
        "type_check.names.scan_apply",
        token_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.names_scatter_lexemes,
        &groups.scatter,
        "type_check.names.scatter_lexemes",
        token_active_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.names_hash_prepare,
        &groups.hash_prepare,
        "type_check.names.hash_prepare",
        groups.hash_work_items,
    )?;
    record_compute(
        encoder,
        &passes.names_hash_insert,
        &groups.hash_insert,
        "type_check.names.hash_insert",
        groups.hash_work_items,
    )?;
    record_compute(
        encoder,
        &passes.names_hash_assign_ids,
        &groups.hash_assign_ids,
        "type_check.names.hash_assign_ids",
        groups.hash_work_items,
    )
}

/// Records builtin language-name table initialization.
pub(in crate::type_checker) fn record_language_name_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    _token_capacity: u32,
    groups: &LanguageNameBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.language_names_clear,
        &groups.clear,
        "type_check.language_names.clear",
        LANGUAGE_SYMBOL_COUNT,
    )
}

/// Records builtin declaration materialization from language-name ids.
pub(in crate::type_checker) fn record_language_decl_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    name_capacity: u32,
    groups: &LanguageNameBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.language_type_codes_clear,
        &groups.type_codes_clear,
        "type_check.language_type_codes.clear",
        name_capacity,
    )?;
    record_compute(
        encoder,
        &passes.language_decls_materialize,
        &groups.decls_materialize,
        "type_check.language_decls.materialize",
        LANGUAGE_DECL_COUNT,
    )
}
