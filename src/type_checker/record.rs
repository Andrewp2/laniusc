use super::*;

pub(super) fn record_visible_bind_groups(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    groups: &VisibleBindGroups,
) -> Result<()> {
    let n = token_capacity.max(1);
    record_compute(
        encoder,
        type_check_visible_clear_pass(device)?,
        &groups.clear,
        "type_check.visible.clear",
        n,
    )?;
    record_compute(
        encoder,
        type_check_visible_scope_blocks_pass(device)?,
        &groups.scope_blocks,
        "type_check.visible.scope_blocks",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_visible_scatter_pass(device)?,
        &groups.scatter,
        "type_check.visible.scatter",
        n,
    )?;
    record_compute(
        encoder,
        type_check_visible_decode_pass(device)?,
        &groups.decode,
        "type_check.visible.decode",
        n,
    )
}

pub(super) fn record_name_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    name_capacity: u32,
    groups: &NameBindGroups,
) -> Result<()> {
    let token_scan_work = groups.token_scan_n_blocks.saturating_mul(256).max(1);
    let radix_work = groups.radix_n_blocks.saturating_mul(256).max(1);
    record_compute(
        encoder,
        &passes.names_mark_lexemes,
        &groups.mark,
        "type_check.names.mark_lexemes",
        token_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.names_scan_local,
        &groups.scan_local,
        "type_check.names.scan_local",
        token_scan_work,
    )?;
    for bind_group in &groups.scan_blocks {
        record_compute(
            encoder,
            &passes.names_scan_blocks,
            bind_group,
            "type_check.names.scan_blocks",
            groups.token_scan_n_blocks.max(1),
        )?;
    }
    record_compute(
        encoder,
        &passes.names_scan_apply,
        &groups.scan_apply,
        "type_check.names.scan_apply",
        token_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.names_scatter_lexemes,
        &groups.scatter,
        "type_check.names.scatter_lexemes",
        token_capacity.max(1),
    )?;
    for i in 0..groups.radix_scatter.len() {
        record_compute(
            encoder,
            &passes.names_radix_histogram,
            &groups.radix_histogram[i],
            "type_check.names.radix_histogram",
            radix_work,
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &groups.radix_bucket_prefix[i],
            "type_check.names.radix_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &groups.radix_bucket_bases[i],
            "type_check.names.radix_bucket_bases",
            256,
        )?;
        record_compute(
            encoder,
            &passes.names_radix_scatter,
            &groups.radix_scatter[i],
            "type_check.names.radix_scatter",
            radix_work,
        )?;
    }
    record_compute(
        encoder,
        &passes.names_radix_dedup,
        &groups.dedup,
        "type_check.names.radix_dedup",
        name_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.names_scan_local,
        &groups.run_head_scan_local,
        "type_check.names.run_head_scan_local",
        radix_work,
    )?;
    for bind_group in &groups.run_head_scan_blocks {
        record_compute(
            encoder,
            &passes.names_scan_blocks,
            bind_group,
            "type_check.names.run_head_scan_blocks",
            groups.radix_n_blocks.max(1),
        )?;
    }
    record_compute(
        encoder,
        &passes.names_scan_apply,
        &groups.run_head_scan_apply,
        "type_check.names.run_head_scan_apply",
        name_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.names_radix_assign_ids,
        &groups.assign_ids,
        "type_check.names.radix_assign_ids",
        name_capacity.max(1),
    )
}

pub(super) fn record_language_name_bind_groups_with_passes(
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

pub(super) fn record_language_decl_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    groups: &LanguageNameBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.language_decls_materialize,
        &groups.decls_materialize,
        "type_check.language_decls.materialize",
        LANGUAGE_DECL_COUNT,
    )
}

pub(super) fn record_module_path_state_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.modules_mark_records,
        &state.bind_groups.mark_records,
        "type_check.modules.mark_records",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.names_scan_local,
        &state.bind_groups.scan_local,
        "type_check.modules.path_scan_local",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    for bind_group in &state.bind_groups.scan_blocks {
        record_compute(
            encoder,
            &passes.names_scan_blocks,
            bind_group,
            "type_check.modules.path_scan_blocks",
            state.n_blocks.max(1),
        )?;
    }
    record_compute(
        encoder,
        &passes.names_scan_apply,
        &state.bind_groups.scan_apply,
        "type_check.modules.path_scan_apply",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_scatter_paths,
        &state.bind_groups.scatter_paths,
        "type_check.modules.scatter_paths",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_scatter_path_segments,
        &state.bind_groups.scatter_path_segments,
        "type_check.modules.scatter_path_segments",
        state
            .n_blocks
            .saturating_mul(256)
            .saturating_mul(MODULE_PATH_MAX_SEGMENTS as u32)
            .max(1),
    )?;
    record_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        state.n_blocks,
        &state.bind_groups.module_scan,
        "type_check.modules.module_record_scan",
    )?;
    record_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        state.n_blocks,
        &state.bind_groups.import_scan,
        "type_check.modules.import_record_scan",
    )?;
    record_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        state.n_blocks,
        &state.bind_groups.decl_scan,
        "type_check.modules.decl_record_scan",
    )?;
    record_compute(
        encoder,
        &passes.modules_scatter_module_records,
        &state.bind_groups.scatter_module_records,
        "type_check.modules.scatter_module_records",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_build_module_keys,
        &state.bind_groups.build_module_keys,
        "type_check.modules.build_module_keys",
        state
            .n_blocks
            .saturating_mul(256)
            .saturating_mul(MODULE_PATH_MAX_SEGMENTS as u32)
            .max(1),
    )?;
    for i in 0..state.bind_groups.sort_module_key_scatter.len() {
        record_compute(
            encoder,
            &passes.modules_sort_module_keys_histogram,
            &state.bind_groups.sort_module_key_histogram[i],
            "type_check.modules.sort_module_keys_histogram",
            state.n_blocks.saturating_mul(256).max(1),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &state.bind_groups.sort_module_key_bucket_prefix[i],
            "type_check.modules.sort_module_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &state.bind_groups.sort_module_key_bucket_bases[i],
            "type_check.modules.sort_module_keys_bucket_bases",
            256,
        )?;
        record_compute(
            encoder,
            &passes.modules_sort_module_keys_scatter,
            &state.bind_groups.sort_module_key_scatter[i],
            "type_check.modules.sort_module_keys_scatter",
            state.n_blocks.saturating_mul(256).max(1),
        )?;
    }
    record_compute(
        encoder,
        &passes.modules_validate_modules,
        &state.bind_groups.validate_modules,
        "type_check.modules.validate_modules",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_clear_file_module_map,
        &state.bind_groups.clear_file_module_map,
        "type_check.modules.clear_file_module_map",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_build_file_module_map,
        &state.bind_groups.build_file_module_map,
        "type_check.modules.build_file_module_map",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_scatter_import_records,
        &state.bind_groups.scatter_import_records,
        "type_check.modules.scatter_import_records",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_resolve_imports,
        &state.bind_groups.resolve_imports,
        "type_check.modules.resolve_imports",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_scatter_decl_core_records,
        &state.bind_groups.scatter_decl_core_records,
        "type_check.modules.scatter_decl_core_records",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_scatter_decl_span_records,
        &state.bind_groups.scatter_decl_span_records,
        "type_check.modules.scatter_decl_span_records",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_attach_record_modules,
        &state.bind_groups.attach_record_modules,
        "type_check.modules.attach_record_modules",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_seed_decl_key_order,
        &state.bind_groups.seed_decl_key_order,
        "type_check.modules.seed_decl_key_order",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    for i in 0..state.bind_groups.sort_decl_key_scatter.len() {
        record_compute(
            encoder,
            &passes.modules_sort_decl_keys,
            &state.bind_groups.sort_decl_key_histogram[i],
            "type_check.modules.sort_decl_keys_histogram",
            state.n_blocks.saturating_mul(256).max(1),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &state.bind_groups.sort_decl_key_bucket_prefix[i],
            "type_check.modules.sort_decl_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &state.bind_groups.sort_decl_key_bucket_bases[i],
            "type_check.modules.sort_decl_keys_bucket_bases",
            256,
        )?;
        record_compute(
            encoder,
            &passes.modules_sort_decl_keys_scatter,
            &state.bind_groups.sort_decl_key_scatter[i],
            "type_check.modules.sort_decl_keys_scatter",
            state.n_blocks.saturating_mul(256).max(1),
        )?;
    }
    record_compute(
        encoder,
        &passes.modules_validate_decls,
        &state.bind_groups.validate_decls,
        "type_check.modules.validate_decls",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_mark_decl_namespace_keys,
        &state.bind_groups.mark_decl_namespace_keys,
        "type_check.modules.mark_decl_namespace_keys",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        state.n_blocks,
        &state.bind_groups.decl_type_key_scan,
        "type_check.modules.decl_type_key_scan",
    )?;
    record_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        state.n_blocks,
        &state.bind_groups.decl_value_key_scan,
        "type_check.modules.decl_value_key_scan",
    )?;
    record_compute(
        encoder,
        &passes.modules_scatter_decl_namespace_keys,
        &state.bind_groups.scatter_decl_namespace_keys,
        "type_check.modules.scatter_decl_namespace_keys",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_count_import_visibility,
        &state.bind_groups.count_import_visibility,
        "type_check.modules.count_import_visibility",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        state.n_blocks,
        &state.bind_groups.import_visible_type_scan,
        "type_check.modules.import_visible_type_scan",
    )?;
    record_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        state.n_blocks,
        &state.bind_groups.import_visible_value_scan,
        "type_check.modules.import_visible_value_scan",
    )?;
    record_compute(
        encoder,
        &passes.modules_scatter_import_visibility,
        &state.bind_groups.scatter_import_visible_type,
        "type_check.modules.scatter_import_visible_type",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_scatter_import_visibility,
        &state.bind_groups.scatter_import_visible_value,
        "type_check.modules.scatter_import_visible_value",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    for i in 0..state.bind_groups.sort_import_visible_type_key_scatter.len() {
        record_compute(
            encoder,
            &passes.modules_sort_import_visible_keys,
            &state.bind_groups.sort_import_visible_type_key_histogram[i],
            "type_check.modules.sort_import_visible_type_keys_histogram",
            state.n_blocks.saturating_mul(256).max(1),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &state.bind_groups.sort_import_visible_type_key_bucket_prefix[i],
            "type_check.modules.sort_import_visible_type_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &state.bind_groups.sort_import_visible_type_key_bucket_bases[i],
            "type_check.modules.sort_import_visible_type_keys_bucket_bases",
            256,
        )?;
        record_compute(
            encoder,
            &passes.modules_sort_import_visible_keys_scatter,
            &state.bind_groups.sort_import_visible_type_key_scatter[i],
            "type_check.modules.sort_import_visible_type_keys_scatter",
            state.n_blocks.saturating_mul(256).max(1),
        )?;
    }
    for i in 0..state
        .bind_groups
        .sort_import_visible_value_key_scatter
        .len()
    {
        record_compute(
            encoder,
            &passes.modules_sort_import_visible_keys,
            &state.bind_groups.sort_import_visible_value_key_histogram[i],
            "type_check.modules.sort_import_visible_value_keys_histogram",
            state.n_blocks.saturating_mul(256).max(1),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &state
                .bind_groups
                .sort_import_visible_value_key_bucket_prefix[i],
            "type_check.modules.sort_import_visible_value_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &state.bind_groups.sort_import_visible_value_key_bucket_bases[i],
            "type_check.modules.sort_import_visible_value_keys_bucket_bases",
            256,
        )?;
        record_compute(
            encoder,
            &passes.modules_sort_import_visible_keys_scatter,
            &state.bind_groups.sort_import_visible_value_key_scatter[i],
            "type_check.modules.sort_import_visible_value_keys_scatter",
            state.n_blocks.saturating_mul(256).max(1),
        )?;
    }
    record_compute(
        encoder,
        &passes.modules_build_import_visible_key_tables,
        &state.bind_groups.build_import_visible_type_key_table,
        "type_check.modules.build_import_visible_type_key_table",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_build_import_visible_key_tables,
        &state.bind_groups.build_import_visible_value_key_table,
        "type_check.modules.build_import_visible_value_key_table",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_validate_import_visible_keys,
        &state.bind_groups.validate_import_visible_keys,
        "type_check.modules.validate_import_visible_keys",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_resolve_local_paths,
        &state.bind_groups.resolve_local_type_paths,
        "type_check.modules.resolve_local_type_paths",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_resolve_local_paths,
        &state.bind_groups.resolve_local_value_paths,
        "type_check.modules.resolve_local_value_paths",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_resolve_imported_paths,
        &state.bind_groups.resolve_imported_type_paths,
        "type_check.modules.resolve_imported_type_paths",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_resolve_imported_paths,
        &state.bind_groups.resolve_imported_value_paths,
        "type_check.modules.resolve_imported_value_paths",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_resolve_qualified_paths,
        &state.bind_groups.resolve_qualified_type_paths,
        "type_check.modules.resolve_qualified_type_paths",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_resolve_qualified_paths,
        &state.bind_groups.resolve_qualified_value_paths,
        "type_check.modules.resolve_qualified_value_paths",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_clear_type_path_types,
        &state.bind_groups.clear_type_path_types,
        "type_check.modules.clear_type_path_types",
        state.token_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_project_type_paths,
        &state.bind_groups.project_type_paths,
        "type_check.modules.project_type_paths",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_mark_value_call_paths,
        &state.bind_groups.mark_value_call_paths,
        "type_check.modules.mark_value_call_paths",
        state.n_blocks.saturating_mul(256).max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_project_value_paths,
        &state.bind_groups.project_value_paths,
        "type_check.modules.project_value_paths",
        state.n_blocks.saturating_mul(256).max(1),
    )
}

pub(super) fn record_type_instance_collection_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    bind_groups: &ResidentTypeCheckBindGroups,
    hir_node_capacity: u32,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.type_instances_collect,
        &bind_groups.type_instances_collect,
        "type_check.resident.type_instances_collect.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.type_instances_collect_named,
        &bind_groups.type_instances_collect_named,
        "type_check.resident.type_instances_collect_named.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.type_instances_collect_aggregate_refs,
        &bind_groups.type_instances_collect_aggregate_refs,
        "type_check.resident.type_instances_collect_aggregate_refs.pass",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.type_instances_collect_aggregate_details,
        &bind_groups.type_instances_collect_aggregate_details,
        "type_check.resident.type_instances_collect_aggregate_details.pass",
        hir_node_capacity.max(1),
    )?;

    Ok(())
}

pub(super) fn record_u32_scan_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    n_blocks: u32,
    scan: &U32ScanBindGroups,
    label: &'static str,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.names_scan_local,
        &scan.local,
        label,
        n_blocks.saturating_mul(256).max(1),
    )?;
    for bind_group in &scan.blocks {
        record_compute(
            encoder,
            &passes.names_scan_blocks,
            bind_group,
            label,
            n_blocks.max(1),
        )?;
    }
    record_compute(
        encoder,
        &passes.names_scan_apply,
        &scan.apply,
        label,
        n_blocks.saturating_mul(256).max(1),
    )
}

pub(super) fn record_fn_context_bind_groups(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    n_blocks: u32,
    groups: &FnContextBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        type_check_fn_context_clear_pass(device)?,
        &groups.clear,
        "type_check.fn_context.clear",
        token_capacity.max(n_blocks).max(1),
    )?;
    record_compute(
        encoder,
        type_check_fn_context_mark_pass(device)?,
        &groups.mark,
        "type_check.fn_context.mark",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_fn_context_local_pass(device)?,
        &groups.local,
        "type_check.fn_context.local",
        token_capacity.max(1),
    )?;
    for bind_group in &groups.scan {
        record_compute(
            encoder,
            type_check_fn_context_scan_pass(device)?,
            bind_group,
            "type_check.fn_context.scan",
            n_blocks.max(1),
        )?;
    }
    record_compute(
        encoder,
        type_check_fn_context_apply_pass(device)?,
        &groups.apply,
        "type_check.fn_context.apply",
        token_capacity.max(1),
    )
}

pub(super) fn record_call_bind_groups(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    n_work: u32,
    groups: &CallBindGroups,
) -> Result<()> {
    let lookup_work = token_capacity.saturating_mul(2).max(n_work);
    record_compute(
        encoder,
        type_check_calls_clear_pass(device)?,
        &groups.clear,
        "type_check.calls.clear",
        lookup_work,
    )?;
    record_compute(
        encoder,
        type_check_calls_return_refs_pass(device)?,
        &groups.return_refs,
        "type_check.calls.return_refs",
        n_work,
    )?;
    record_compute(
        encoder,
        type_check_calls_entrypoints_pass(device)?,
        &groups.entrypoints,
        "type_check.calls.entrypoints",
        n_work,
    )?;
    record_compute(
        encoder,
        type_check_calls_functions_pass(device)?,
        &groups.functions,
        "type_check.calls.functions",
        n_work,
    )?;
    record_compute(
        encoder,
        type_check_calls_param_types_pass(device)?,
        &groups.param_types,
        "type_check.calls.param_types",
        n_work,
    )?;
    record_compute(
        encoder,
        type_check_calls_intrinsics_pass(device)?,
        &groups.intrinsics,
        "type_check.calls.intrinsics",
        n_work,
    )?;
    record_compute(
        encoder,
        type_check_calls_clear_hir_call_args_pass(device)?,
        &groups.clear_hir_call_args,
        "type_check.calls.clear_hir_call_args",
        token_capacity
            .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
            .max(1),
    )?;
    record_compute(
        encoder,
        type_check_calls_pack_hir_call_args_pass(device)?,
        &groups.pack_hir_call_args,
        "type_check.calls.pack_hir_call_args",
        n_work,
    )?;
    record_compute(
        encoder,
        type_check_calls_resolve_pass(device)?,
        &groups.resolve,
        "type_check.calls.resolve",
        n_work,
    )?;
    record_compute(
        encoder,
        type_check_calls_erase_generic_params_pass(device)?,
        &groups.erase_generic_params,
        "type_check.calls.erase_generic_params",
        token_capacity
            .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
            .max(1),
    )
}

pub(super) fn record_method_bind_groups(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    n_work: u32,
    groups: &MethodBindGroups,
) -> Result<()> {
    let lookup_work = token_capacity.saturating_mul(2).max(n_work);
    record_compute(
        encoder,
        type_check_methods_clear_pass(device)?,
        &groups.clear,
        "type_check.methods.clear",
        lookup_work,
    )?;
    record_compute(
        encoder,
        type_check_methods_collect_pass(device)?,
        &groups.collect,
        "type_check.methods.collect",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_methods_attach_metadata_pass(device)?,
        &groups.attach_metadata,
        "type_check.methods.attach_metadata",
        lookup_work,
    )?;
    record_compute(
        encoder,
        type_check_methods_bind_self_receivers_pass(device)?,
        &groups.bind_self_receivers,
        "type_check.methods.bind_self_receivers",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_methods_seed_key_order_pass(device)?,
        &groups.keys.seed_key_order,
        "type_check.methods.seed_key_order",
        token_capacity.max(1),
    )?;
    for i in 0..groups.keys.sort_key_scatter.len() {
        record_compute(
            encoder,
            type_check_methods_sort_keys_pass(device)?,
            &groups.keys.sort_key_histogram[i],
            "type_check.methods.sort_keys_histogram",
            token_capacity.max(1),
        )?;
        record_compute(
            encoder,
            type_check_names_radix_bucket_prefix_pass(device)?,
            &groups.keys.sort_key_bucket_prefix[i],
            "type_check.methods.sort_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            type_check_names_radix_bucket_bases_pass(device)?,
            &groups.keys.sort_key_bucket_bases[i],
            "type_check.methods.sort_keys_bucket_bases",
            256,
        )?;
        record_compute(
            encoder,
            type_check_methods_sort_keys_scatter_pass(device)?,
            &groups.keys.sort_key_scatter[i],
            "type_check.methods.sort_keys_scatter",
            token_capacity.max(1),
        )?;
    }
    record_compute(
        encoder,
        type_check_methods_validate_keys_pass(device)?,
        &groups.keys.validate_keys,
        "type_check.methods.validate_keys",
        token_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_methods_mark_call_keys_pass(device)?,
        &groups.mark_call_keys,
        "type_check.methods.mark_call_keys",
        token_capacity.max(hir_node_capacity).max(1),
    )?;
    record_compute(
        encoder,
        type_check_methods_mark_call_return_keys_pass(device)?,
        &groups.mark_call_return_keys,
        "type_check.methods.mark_call_return_keys",
        token_capacity.max(hir_node_capacity).max(1),
    )?;
    record_compute(
        encoder,
        type_check_methods_resolve_table_pass(device)?,
        &groups.resolve_table,
        "type_check.methods.resolve_table",
        token_capacity.max(1),
    )
}

pub(super) fn record_loop_depth_bind_groups(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    n_blocks: u32,
    groups: &LoopDepthBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        loop_depth_01_clear_pass(device)?,
        &groups.clear,
        "type_check.loop_depth.clear",
        token_capacity.saturating_add(1),
    )?;
    record_compute(
        encoder,
        loop_depth_02_mark_pass(device)?,
        &groups.mark,
        "type_check.loop_depth.mark",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        loop_depth_03_local_pass(device)?,
        &groups.local,
        "type_check.loop_depth.local",
        n_blocks.saturating_mul(256),
    )?;
    let scan_pass = loop_depth_04_scan_pass(device)?;
    for scan_group in &groups.scan {
        record_compute(
            encoder,
            scan_pass,
            scan_group,
            "type_check.loop_depth.scan",
            n_blocks,
        )?;
    }
    record_compute(
        encoder,
        loop_depth_05_apply_pass(device)?,
        &groups.apply,
        "type_check.loop_depth.apply",
        token_capacity.max(1),
    )
}

pub(super) fn record_loop_depth_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    groups: &ResidentTypeCheckBindGroups,
) -> Result<()> {
    record_loop_depth_bind_groups_with_passes(
        passes,
        encoder,
        groups.token_capacity,
        groups.hir_node_capacity,
        groups.loop_n_blocks,
        &groups.loop_bind_groups,
    )
}

pub(super) fn record_visible_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    groups: &VisibleBindGroups,
) -> Result<()> {
    let n = token_capacity.max(1);
    record_compute(
        encoder,
        &passes.visible_clear,
        &groups.clear,
        "type_check.visible.clear",
        n,
    )?;
    record_compute(
        encoder,
        &passes.visible_scope_blocks,
        &groups.scope_blocks,
        "type_check.visible.scope_blocks",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.visible_scatter,
        &groups.scatter,
        "type_check.visible.scatter",
        n,
    )?;
    record_compute(
        encoder,
        &passes.visible_decode,
        &groups.decode,
        "type_check.visible.decode",
        n,
    )
}

pub(super) fn record_fn_context_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    n_blocks: u32,
    groups: &FnContextBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.fn_context_clear,
        &groups.clear,
        "type_check.fn_context.clear",
        token_capacity.max(n_blocks).max(1),
    )?;
    record_compute(
        encoder,
        &passes.fn_context_mark,
        &groups.mark,
        "type_check.fn_context.mark",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.fn_context_local,
        &groups.local,
        "type_check.fn_context.local",
        token_capacity.max(1),
    )?;
    for bind_group in &groups.scan {
        record_compute(
            encoder,
            &passes.fn_context_scan,
            bind_group,
            "type_check.fn_context.scan",
            n_blocks.max(1),
        )?;
    }
    record_compute(
        encoder,
        &passes.fn_context_apply,
        &groups.apply,
        "type_check.fn_context.apply",
        token_capacity.max(1),
    )
}

pub(super) fn record_call_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    n_work: u32,
    groups: &CallBindGroups,
) -> Result<()> {
    let lookup_work = token_capacity.saturating_mul(2).max(n_work);
    record_compute(
        encoder,
        &passes.calls_clear,
        &groups.clear,
        "type_check.calls.clear",
        lookup_work,
    )?;
    record_compute(
        encoder,
        &passes.calls_return_refs,
        &groups.return_refs,
        "type_check.calls.return_refs",
        n_work,
    )?;
    record_compute(
        encoder,
        &passes.calls_entrypoints,
        &groups.entrypoints,
        "type_check.calls.entrypoints",
        n_work,
    )?;
    record_compute(
        encoder,
        &passes.calls_functions,
        &groups.functions,
        "type_check.calls.functions",
        n_work,
    )?;
    record_compute(
        encoder,
        &passes.calls_param_types,
        &groups.param_types,
        "type_check.calls.param_types",
        n_work,
    )?;
    record_compute(
        encoder,
        &passes.calls_intrinsics,
        &groups.intrinsics,
        "type_check.calls.intrinsics",
        n_work,
    )?;
    record_compute(
        encoder,
        &passes.calls_clear_hir_call_args,
        &groups.clear_hir_call_args,
        "type_check.calls.clear_hir_call_args",
        token_capacity
            .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
            .max(1),
    )?;
    record_compute(
        encoder,
        &passes.calls_pack_hir_call_args,
        &groups.pack_hir_call_args,
        "type_check.calls.pack_hir_call_args",
        n_work,
    )?;
    record_compute(
        encoder,
        &passes.calls_resolve,
        &groups.resolve,
        "type_check.calls.resolve",
        n_work,
    )
}

pub(super) fn record_call_erase_generic_params_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    groups: &CallBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.calls_erase_generic_params,
        &groups.erase_generic_params,
        "type_check.calls.erase_generic_params",
        token_capacity
            .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
            .max(1),
    )
}

pub(super) fn record_method_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    n_work: u32,
    groups: &MethodBindGroups,
) -> Result<()> {
    let lookup_work = token_capacity.saturating_mul(2).max(n_work);
    record_compute(
        encoder,
        &passes.methods_clear,
        &groups.clear,
        "type_check.methods.clear",
        lookup_work,
    )?;
    record_compute(
        encoder,
        &passes.methods_collect,
        &groups.collect,
        "type_check.methods.collect",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.methods_attach_metadata,
        &groups.attach_metadata,
        "type_check.methods.attach_metadata",
        lookup_work,
    )?;
    record_compute(
        encoder,
        &passes.methods_bind_self_receivers,
        &groups.bind_self_receivers,
        "type_check.methods.bind_self_receivers",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.methods_seed_key_order,
        &groups.keys.seed_key_order,
        "type_check.methods.seed_key_order",
        token_capacity.max(1),
    )?;
    for i in 0..groups.keys.sort_key_scatter.len() {
        record_compute(
            encoder,
            &passes.methods_sort_keys,
            &groups.keys.sort_key_histogram[i],
            "type_check.methods.sort_keys_histogram",
            token_capacity.max(1),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &groups.keys.sort_key_bucket_prefix[i],
            "type_check.methods.sort_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &groups.keys.sort_key_bucket_bases[i],
            "type_check.methods.sort_keys_bucket_bases",
            256,
        )?;
        record_compute(
            encoder,
            &passes.methods_sort_keys_scatter,
            &groups.keys.sort_key_scatter[i],
            "type_check.methods.sort_keys_scatter",
            token_capacity.max(1),
        )?;
    }
    record_compute(
        encoder,
        &passes.methods_validate_keys,
        &groups.keys.validate_keys,
        "type_check.methods.validate_keys",
        token_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.methods_mark_call_keys,
        &groups.mark_call_keys,
        "type_check.methods.mark_call_keys",
        token_capacity.max(hir_node_capacity).max(1),
    )?;
    record_compute(
        encoder,
        &passes.methods_mark_call_return_keys,
        &groups.mark_call_return_keys,
        "type_check.methods.mark_call_return_keys",
        token_capacity.max(hir_node_capacity).max(1),
    )?;
    record_compute(
        encoder,
        &passes.methods_resolve_table,
        &groups.resolve_table,
        "type_check.methods.resolve_table",
        token_capacity.max(1),
    )
}

pub(super) fn record_loop_depth_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    n_blocks: u32,
    groups: &LoopDepthBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.loop_depth_clear,
        &groups.clear,
        "type_check.loop_depth.clear",
        token_capacity.saturating_add(1),
    )?;
    record_compute(
        encoder,
        &passes.loop_depth_mark,
        &groups.mark,
        "type_check.loop_depth.mark",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.loop_depth_local,
        &groups.local,
        "type_check.loop_depth.local",
        n_blocks.saturating_mul(256),
    )?;
    for scan_group in &groups.scan {
        record_compute(
            encoder,
            &passes.loop_depth_scan,
            scan_group,
            "type_check.loop_depth.scan",
            n_blocks,
        )?;
    }
    record_compute(
        encoder,
        &passes.loop_depth_apply,
        &groups.apply,
        "type_check.loop_depth.apply",
        token_capacity.max(1),
    )
}

pub(super) fn record_compute(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &'static str,
    n_elements: u32,
) -> Result<()> {
    let [tgsx, tgsy, _] = pass.thread_group_size;
    let (gx, gy, gz) = plan_workgroups(
        DispatchDim::D1,
        InputElements::Elements1D(n_elements),
        [tgsx, tgsy, 1],
    )?;
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), &[]);
    compute.dispatch_workgroups(gx, gy, gz);
    Ok(())
}
