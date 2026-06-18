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
        &passes.names_radix_byte_dispatch_args,
        &groups.radix_dispatch,
        "type_check.names.radix_dispatch_args",
        NAME_RADIX_MAX_BYTES,
    )?;
    for i in 0..groups.radix_scatter.len() {
        let radix_byte_dispatch_offset = ((1 + i) * 3 * std::mem::size_of::<u32>()) as u64;
        let radix_prefix_dispatch_offset =
            ((1 + NAME_RADIX_MAX_BYTES as usize + i) * 3 * std::mem::size_of::<u32>()) as u64;
        let radix_bases_dispatch_offset =
            ((1 + 2 * NAME_RADIX_MAX_BYTES as usize + i) * 3 * std::mem::size_of::<u32>()) as u64;
        record_compute_indirect_offset(
            encoder,
            &passes.names_radix_histogram,
            &groups.radix_histogram[i],
            "type_check.names.radix_histogram",
            &groups.radix_dispatch_args,
            radix_byte_dispatch_offset,
        )?;
        record_compute_indirect_offset(
            encoder,
            &passes.names_radix_bucket_prefix_active,
            &groups.radix_bucket_prefix[i],
            "type_check.names.radix_bucket_prefix",
            &groups.radix_dispatch_args,
            radix_prefix_dispatch_offset,
        )?;
        record_compute_indirect_offset(
            encoder,
            &passes.names_radix_bucket_bases_active,
            &groups.radix_bucket_bases[i],
            "type_check.names.radix_bucket_bases",
            &groups.radix_dispatch_args,
            radix_bases_dispatch_offset,
        )?;
        record_compute_indirect_offset(
            encoder,
            &passes.names_radix_scatter,
            &groups.radix_scatter[i],
            "type_check.names.radix_scatter",
            &groups.radix_dispatch_args,
            radix_byte_dispatch_offset,
        )?;
    }
    record_compute_indirect(
        encoder,
        &passes.names_radix_dedup,
        &groups.dedup,
        "type_check.names.radix_dedup",
        &groups.radix_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.counted_scan_local,
        &groups.run_head_scan_local,
        "type_check.names.run_head_scan_local",
        &groups.radix_dispatch_args,
    )?;
    for bind_group in &groups.run_head_scan_blocks {
        record_compute(
            encoder,
            &passes.counted_scan_blocks,
            bind_group,
            "type_check.names.run_head_scan_blocks",
            groups.radix_n_blocks.max(1),
        )?;
    }
    record_compute_indirect(
        encoder,
        &passes.counted_scan_apply,
        &groups.run_head_scan_apply,
        "type_check.names.run_head_scan_apply",
        &groups.radix_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.names_radix_assign_ids,
        &groups.assign_ids,
        "type_check.names.radix_assign_ids",
        &groups.radix_dispatch_args,
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
