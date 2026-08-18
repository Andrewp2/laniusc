// src/type_checker/record/names.rs

use super::*;

/// Records lexeme compaction, exact hash-table construction, and name-ID assignment.
pub(in crate::type_checker) fn record_name_bind_groups_with_passes(
    encoder: &mut wgpu::CommandEncoder,
    groups: &NameBindGroups,
) -> Result<()> {
    groups.compaction.record(encoder)?;
    groups.hash_prepare.record(encoder)?;
    groups.hash_insert.record(encoder)?;
    groups.hash_assign_ids.record(encoder)
}

/// Records builtin language-name table initialization.
pub(in crate::type_checker) fn record_language_name_bind_groups_with_passes(
    encoder: &mut wgpu::CommandEncoder,
    groups: &LanguageNameBindGroups,
) -> Result<()> {
    groups.clear.record(encoder)
}

/// Records builtin declaration materialization from language-name ids.
pub(in crate::type_checker) fn record_language_decl_bind_groups_with_passes(
    encoder: &mut wgpu::CommandEncoder,
    groups: &LanguageNameBindGroups,
) -> Result<()> {
    groups.type_codes_clear.record(encoder)?;
    groups.decls_materialize.record(encoder)
}
