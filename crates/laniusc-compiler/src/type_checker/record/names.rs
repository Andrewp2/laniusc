// src/type_checker/record/names.rs

use super::*;

/// Records lexeme compaction, exact hash-table construction, and name-ID assignment.
pub(in crate::type_checker) fn record_name_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    _token_capacity: u32,
    _name_capacity: u32,
    _token_active_dispatch_args: &LaniusBuffer<u32>,
    groups: &NameBindGroups,
) -> Result<()> {
    groups.compaction.record(encoder)?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/names/hash/00_prepare"),
        &groups.hash_prepare,
        "type_check.names.hash_prepare",
        groups.hash_work_items,
    )?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/names/hash/01_insert"),
        &groups.hash_insert,
        "type_check.names.hash_insert",
        groups.hash_work_items,
    )?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/names/hash/02_assign_ids"),
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
        &passes.kernel("type_checker/language/names/00_clear"),
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
        &passes.kernel("type_checker/language/decls/00a_clear_type_codes"),
        &groups.type_codes_clear,
        "type_check.language_type_codes.clear",
        name_capacity,
    )?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/language/decls/00_materialize"),
        &groups.decls_materialize,
        "type_check.language_decls.materialize",
        LANGUAGE_DECL_COUNT,
    )
}
