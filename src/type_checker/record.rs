use super::*;

pub(super) fn record_visible_bind_groups(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    groups: &VisibleBindGroups,
) -> Result<()> {
    let legacy = groups
        .legacy_token_visibility
        .as_ref()
        .expect("standalone visible-name path requires legacy token visibility bind groups");
    let n = token_capacity.max(1);
    let name_clear_n = token_capacity.saturating_add(LANGUAGE_SYMBOL_COUNT).max(1);
    record_compute(
        encoder,
        type_check_visible_clear_pass(device)?,
        &groups.clear,
        "type_check.visible.clear",
        name_clear_n,
    )?;
    record_compute(
        encoder,
        type_check_visible_scope_blocks_pass(device)?,
        &legacy.scope_blocks,
        "type_check.visible.scope_blocks",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_visible_mark_hir_decl_names_pass(device)?,
        &groups.mark_hir_decl_names,
        "type_check.visible.mark_hir_decl_names",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_counted_scan_local_pass(device)?,
        &groups.hir_decl_scan.local,
        "type_check.visible.hir_decl_scan",
        hir_node_capacity.max(1),
    )?;
    let hir_decl_scan_n_blocks = groups.hir_decl_scan_n_blocks;
    let hir_decl_record_n_blocks = groups.hir_decl_record_n_blocks;
    for bind_group in &groups.hir_decl_scan.blocks {
        record_compute(
            encoder,
            type_check_counted_scan_blocks_pass(device)?,
            bind_group,
            "type_check.visible.hir_decl_scan",
            hir_decl_scan_n_blocks,
        )?;
    }
    record_compute(
        encoder,
        type_check_counted_scan_apply_pass(device)?,
        &groups.hir_decl_scan.apply,
        "type_check.visible.hir_decl_scan",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_visible_scatter_hir_decl_records_pass(device)?,
        &groups.scatter_hir_decl_records,
        "type_check.visible.scatter_hir_decl_records",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_visible_seed_hir_decl_order_pass(device)?,
        &groups.seed_hir_decl_order,
        "type_check.visible.seed_hir_decl_order",
        token_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_names_radix_dispatch_args_pass(device)?,
        &groups.hir_decl_key_radix_dispatch,
        "type_check.visible.hir_decl_key_radix_dispatch_args",
        1,
    )?;
    for i in 0..groups.sort_hir_decl_key_scatter.len() {
        record_compute(
            encoder,
            type_check_visible_sort_hir_decl_keys_pass(device)?,
            &groups.sort_hir_decl_key_histogram[i],
            "type_check.visible.sort_hir_decl_keys_histogram",
            hir_decl_record_n_blocks.saturating_mul(256).max(1),
        )?;
        record_compute(
            encoder,
            type_check_names_radix_bucket_prefix_pass(device)?,
            &groups.sort_hir_decl_key_bucket_prefix[i],
            "type_check.visible.sort_hir_decl_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            type_check_names_radix_bucket_bases_pass(device)?,
            &groups.sort_hir_decl_key_bucket_bases[i],
            "type_check.visible.sort_hir_decl_keys_bucket_bases",
            256,
        )?;
        record_compute(
            encoder,
            type_check_visible_sort_hir_decl_keys_scatter_pass(device)?,
            &groups.sort_hir_decl_key_scatter[i],
            "type_check.visible.sort_hir_decl_keys_scatter",
            hir_decl_record_n_blocks.saturating_mul(256).max(1),
        )?;
    }
    record_compute(
        encoder,
        type_check_visible_build_hir_decl_scope_leaves_pass(device)?,
        &groups.build_hir_decl_scope_leaves,
        "type_check.visible.build_hir_decl_scope_leaves",
        groups.hir_decl_scope_leaf_work_items.max(1),
    )?;
    for level in &groups.hir_decl_scope_tree_levels {
        record_compute(
            encoder,
            type_check_visible_build_hir_decl_scope_tree_pass(device)?,
            &level.bind_group,
            "type_check.visible.build_hir_decl_scope_tree",
            level.work_items.max(1),
        )?;
    }
    record_compute(
        encoder,
        type_check_visible_scatter_pass(device)?,
        &legacy.scatter,
        "type_check.visible.scatter",
        n,
    )?;
    record_compute(
        encoder,
        type_check_visible_decode_pass(device)?,
        &legacy.decode,
        "type_check.visible.decode",
        n,
    )?;
    record_compute(
        encoder,
        type_check_visible_hir_names_pass(device)?,
        &groups.hir_names,
        "type_check.visible.hir_names",
        hir_node_capacity.max(1),
    )
}

pub(super) fn record_name_bind_groups_with_passes(
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
        &passes.names_radix_dispatch_args,
        &groups.radix_dispatch,
        "type_check.names.radix_dispatch_args",
        1,
    )?;
    for i in 0..groups.radix_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.names_radix_histogram,
            &groups.radix_histogram[i],
            "type_check.names.radix_histogram",
            &groups.radix_dispatch_args,
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
        record_compute_indirect(
            encoder,
            &passes.names_radix_scatter,
            &groups.radix_scatter[i],
            "type_check.names.radix_scatter",
            &groups.radix_dispatch_args,
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

pub(super) fn record_module_path_state_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    hir_active_dispatch_args: &wgpu::Buffer,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    let hir_work = state.n_blocks.saturating_mul(256).max(1);
    let record_n_blocks = state.n_blocks.max(1);
    let file_map_clear_work = hir_work;

    record_compute_indirect(
        encoder,
        &passes.modules_mark_records,
        &state.bind_groups.mark_records,
        "type_check.modules.mark_records",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.mark_records.done");
    record_compute_indirect(
        encoder,
        &passes.modules_extract_record_flag,
        &state.bind_groups.extract_path_record_flag,
        "type_check.modules.extract_path_record_flag",
        hir_active_dispatch_args,
    )?;
    record_hir_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        state.n_blocks,
        hir_active_dispatch_args,
        &state.bind_groups.path_scan,
        "type_check.modules.path_record_scan",
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_scatter_paths,
        &state.bind_groups.scatter_paths,
        "type_check.modules.scatter_paths",
        hir_active_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.count_dispatch_args,
        &state.bind_groups.path_dispatch_args,
        "type_check.modules.path_dispatch_args",
        1,
    )?;
    record_compute(
        encoder,
        &passes.count_dispatch_args,
        &state.bind_groups.path_segment_dispatch_args,
        "type_check.modules.path_segment_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_count_path_segments,
        &state.bind_groups.count_path_segments,
        "type_check.modules.count_path_segments",
        &state.path_dispatch_args,
    )?;
    record_hir_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        state.n_blocks,
        &state.path_dispatch_args,
        &state.bind_groups.path_segment_scan,
        "type_check.modules.path_segment_scan",
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_scatter_path_segments,
        &state.bind_groups.scatter_path_segments,
        "type_check.modules.scatter_path_segments",
        &state.path_segment_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.paths.done");
    record_compute_indirect(
        encoder,
        &passes.modules_extract_record_flag,
        &state.bind_groups.extract_module_record_flag,
        "type_check.modules.extract_module_record_flag",
        hir_active_dispatch_args,
    )?;
    record_hir_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        state.n_blocks,
        hir_active_dispatch_args,
        &state.bind_groups.module_scan,
        "type_check.modules.module_record_scan",
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_scatter_module_records,
        &state.bind_groups.scatter_module_records,
        "type_check.modules.scatter_module_records",
        hir_active_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.count_dispatch_args,
        &state.bind_groups.module_key_segment_dispatch,
        "type_check.modules.module_key_segment_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_build_module_keys,
        &state.bind_groups.build_module_keys,
        "type_check.modules.build_module_keys",
        &state.module_key_radix_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.names_radix_dispatch_args,
        &state.bind_groups.module_key_radix_dispatch,
        "type_check.modules.module_key_radix_dispatch_args",
        1,
    )?;
    for i in 0..state.bind_groups.sort_module_key_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.modules_sort_module_keys_histogram,
            &state.bind_groups.sort_module_key_histogram[i],
            "type_check.modules.sort_module_keys_histogram",
            &state.module_key_radix_dispatch_args,
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
        record_compute_indirect(
            encoder,
            &passes.modules_sort_module_keys_scatter,
            &state.bind_groups.sort_module_key_scatter[i],
            "type_check.modules.sort_module_keys_scatter",
            &state.module_key_radix_dispatch_args,
        )?;
    }
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.modules.sort_module_keys.done",
    );
    record_compute_indirect(
        encoder,
        &passes.modules_validate_modules,
        &state.bind_groups.validate_modules,
        "type_check.modules.validate_modules",
        &state.module_key_radix_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.modules_clear_file_module_map,
        &state.bind_groups.clear_file_module_map,
        "type_check.modules.clear_file_module_map",
        file_map_clear_work,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_build_file_module_map,
        &state.bind_groups.build_file_module_map,
        "type_check.modules.build_file_module_map",
        &state.module_key_radix_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.module_maps.done");
    record_compute_indirect(
        encoder,
        &passes.modules_extract_record_flag,
        &state.bind_groups.extract_import_record_flag,
        "type_check.modules.extract_import_record_flag",
        hir_active_dispatch_args,
    )?;
    record_hir_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        state.n_blocks,
        hir_active_dispatch_args,
        &state.bind_groups.import_scan,
        "type_check.modules.import_record_scan",
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_scatter_import_records,
        &state.bind_groups.scatter_import_records,
        "type_check.modules.scatter_import_records",
        hir_active_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.count_dispatch_args,
        &state.bind_groups.import_dispatch_args,
        "type_check.modules.import_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_resolve_imports,
        &state.bind_groups.resolve_imports,
        "type_check.modules.resolve_imports",
        &state.import_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_extract_record_flag,
        &state.bind_groups.extract_decl_record_flag,
        "type_check.modules.extract_decl_record_flag",
        hir_active_dispatch_args,
    )?;
    record_hir_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        state.n_blocks,
        hir_active_dispatch_args,
        &state.bind_groups.decl_scan,
        "type_check.modules.decl_record_scan",
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_scatter_decl_core_records,
        &state.bind_groups.scatter_decl_core_records,
        "type_check.modules.scatter_decl_core_records",
        hir_active_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.modules_clear_decl_lookup,
        &state.bind_groups.clear_decl_lookup,
        "type_check.modules.clear_decl_lookup",
        state.token_capacity.max(1),
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_scatter_decl_span_records,
        &state.bind_groups.scatter_decl_span_records,
        "type_check.modules.scatter_decl_span_records",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_attach_record_modules,
        &state.bind_groups.attach_record_modules,
        "type_check.modules.attach_record_modules",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.modules.record_scans_and_import_decl_records.done",
    );
    record_compute(
        encoder,
        &passes.names_radix_dispatch_args,
        &state.bind_groups.decl_key_radix_dispatch,
        "type_check.modules.decl_key_radix_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_seed_decl_key_order,
        &state.bind_groups.seed_decl_key_order,
        "type_check.modules.seed_decl_key_order",
        &state.decl_key_radix_dispatch_args,
    )?;
    for i in 0..state.bind_groups.sort_decl_key_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.modules_sort_decl_keys,
            &state.bind_groups.sort_decl_key_histogram[i],
            "type_check.modules.sort_decl_keys_histogram",
            &state.decl_key_radix_dispatch_args,
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
        record_compute_indirect(
            encoder,
            &passes.modules_sort_decl_keys_scatter,
            &state.bind_groups.sort_decl_key_scatter[i],
            "type_check.modules.sort_decl_keys_scatter",
            &state.decl_key_radix_dispatch_args,
        )?;
    }
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.sort_decl_keys.done");
    record_compute_indirect(
        encoder,
        &passes.modules_validate_decls,
        &state.bind_groups.validate_decls,
        "type_check.modules.validate_decls",
        &state.decl_key_radix_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_mark_decl_namespace_keys,
        &state.bind_groups.mark_decl_namespace_keys,
        "type_check.modules.mark_decl_namespace_keys",
        &state.decl_key_radix_dispatch_args,
    )?;
    record_hir_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        record_n_blocks,
        &state.decl_key_radix_dispatch_args,
        &state.bind_groups.decl_type_key_scan,
        "type_check.modules.decl_type_key_scan",
    )?;
    record_hir_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        record_n_blocks,
        &state.decl_key_radix_dispatch_args,
        &state.bind_groups.decl_value_key_scan,
        "type_check.modules.decl_value_key_scan",
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_scatter_decl_namespace_keys,
        &state.bind_groups.scatter_decl_namespace_keys,
        "type_check.modules.scatter_decl_namespace_keys",
        &state.decl_key_radix_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_mark_public_decl_keys,
        &state.bind_groups.mark_public_decl_keys,
        "type_check.modules.mark_public_decl_keys",
        &state.decl_key_radix_dispatch_args,
    )?;
    record_hir_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        record_n_blocks,
        &state.decl_key_radix_dispatch_args,
        &state.bind_groups.decl_type_public_scan,
        "type_check.modules.decl_type_public_scan",
    )?;
    record_hir_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        record_n_blocks,
        &state.decl_key_radix_dispatch_args,
        &state.bind_groups.decl_value_public_scan,
        "type_check.modules.decl_value_public_scan",
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.modules.decl_namespace_keys.done",
    );
    record_compute_indirect(
        encoder,
        &passes.modules_count_import_visibility,
        &state.bind_groups.count_import_visibility,
        "type_check.modules.count_import_visibility",
        &state.import_dispatch_args,
    )?;
    record_hir_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        record_n_blocks,
        &state.import_dispatch_args,
        &state.bind_groups.import_visible_type_scan,
        "type_check.modules.import_visible_type_scan",
    )?;
    record_hir_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        record_n_blocks,
        &state.import_dispatch_args,
        &state.bind_groups.import_visible_value_scan,
        "type_check.modules.import_visible_value_scan",
    )?;
    record_compute(
        encoder,
        &passes.names_radix_dispatch_args,
        &state.bind_groups.import_visible_type_key_radix_dispatch,
        "type_check.modules.import_visible_type_key_radix_dispatch_args",
        1,
    )?;
    record_compute(
        encoder,
        &passes.names_radix_dispatch_args,
        &state.bind_groups.import_visible_value_key_radix_dispatch,
        "type_check.modules.import_visible_value_key_radix_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_scatter_import_visibility,
        &state.bind_groups.scatter_import_visible_type,
        "type_check.modules.scatter_import_visible_type",
        &state.import_visible_type_key_radix_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_scatter_import_visibility,
        &state.bind_groups.scatter_import_visible_value,
        "type_check.modules.scatter_import_visible_value",
        &state.import_visible_value_key_radix_dispatch_args,
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.modules.import_visibility_scatter.done",
    );
    for i in 0..state.bind_groups.sort_import_visible_type_key_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.modules_sort_import_visible_keys,
            &state.bind_groups.sort_import_visible_type_key_histogram[i],
            "type_check.modules.sort_import_visible_type_keys_histogram",
            &state.import_visible_type_key_radix_dispatch_args,
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
        record_compute_indirect(
            encoder,
            &passes.modules_sort_import_visible_keys_scatter,
            &state.bind_groups.sort_import_visible_type_key_scatter[i],
            "type_check.modules.sort_import_visible_type_keys_scatter",
            &state.import_visible_type_key_radix_dispatch_args,
        )?;
    }
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.modules.sort_import_visible_type_keys.done",
    );
    for i in 0..state
        .bind_groups
        .sort_import_visible_value_key_scatter
        .len()
    {
        record_compute_indirect(
            encoder,
            &passes.modules_sort_import_visible_keys,
            &state.bind_groups.sort_import_visible_value_key_histogram[i],
            "type_check.modules.sort_import_visible_value_keys_histogram",
            &state.import_visible_value_key_radix_dispatch_args,
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
        record_compute_indirect(
            encoder,
            &passes.modules_sort_import_visible_keys_scatter,
            &state.bind_groups.sort_import_visible_value_key_scatter[i],
            "type_check.modules.sort_import_visible_value_keys_scatter",
            &state.import_visible_value_key_radix_dispatch_args,
        )?;
    }
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.modules.sort_import_visible_value_keys.done",
    );
    record_compute_indirect(
        encoder,
        &passes.modules_build_import_visible_key_tables,
        &state.bind_groups.build_import_visible_type_key_table,
        "type_check.modules.build_import_visible_type_key_table",
        &state.import_visible_type_key_radix_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_build_import_visible_key_tables,
        &state.bind_groups.build_import_visible_value_key_table,
        "type_check.modules.build_import_visible_value_key_table",
        &state.import_visible_value_key_radix_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.count_pair_max_dispatch_args,
        &state.bind_groups.import_visible_validate_dispatch_args,
        "type_check.modules.import_visible_validate_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_validate_import_visible_keys,
        &state.bind_groups.validate_import_visible_keys,
        "type_check.modules.validate_import_visible_keys",
        &state.import_visible_validate_dispatch_args,
    )?;
    stamp_typecheck_timer(
        &mut timer,
        encoder,
        "typecheck.modules.import_visible_tables.done",
    );
    record_compute_indirect(
        encoder,
        &passes.modules_resolve_local_paths,
        &state.bind_groups.resolve_local_type_paths,
        "type_check.modules.resolve_local_type_paths",
        &state.path_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_resolve_local_paths,
        &state.bind_groups.resolve_local_value_paths,
        "type_check.modules.resolve_local_value_paths",
        &state.path_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_resolve_imported_paths,
        &state.bind_groups.resolve_imported_type_paths,
        "type_check.modules.resolve_imported_type_paths",
        &state.path_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_resolve_imported_paths,
        &state.bind_groups.resolve_imported_value_paths,
        "type_check.modules.resolve_imported_value_paths",
        &state.path_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_resolve_qualified_paths,
        &state.bind_groups.resolve_qualified_type_paths,
        "type_check.modules.resolve_qualified_type_paths",
        &state.path_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_resolve_qualified_paths,
        &state.bind_groups.resolve_qualified_value_paths,
        "type_check.modules.resolve_qualified_value_paths",
        &state.path_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.resolve_paths.done");
    record_compute(
        encoder,
        &passes.modules_clear_type_path_types,
        &state.bind_groups.clear_type_path_types,
        "type_check.modules.clear_type_path_types",
        state.token_capacity.max(1),
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_project_type_paths,
        &state.bind_groups.project_type_paths,
        "type_check.modules.project_type_paths",
        &state.path_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_mark_value_call_paths,
        &state.bind_groups.mark_value_call_paths,
        "type_check.modules.mark_value_call_paths",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_project_value_paths,
        &state.bind_groups.project_value_paths,
        "type_check.modules.project_value_paths",
        &state.path_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.modules_validate_type_paths,
        &state.bind_groups.validate_type_paths,
        "type_check.modules.validate_type_paths",
        &state.path_dispatch_args,
    )
}

fn stamp_typecheck_timer(
    timer: &mut Option<&mut crate::gpu::timer::GpuTimer>,
    encoder: &mut wgpu::CommandEncoder,
    label: &'static str,
) {
    if let Some(timer) = timer.as_deref_mut() {
        timer.stamp(encoder, label);
    }
}

pub(super) struct TypeInstanceCollectionTimerLabels {
    pub scalar: &'static str,
    pub named: &'static str,
    pub aggregate_refs: &'static str,
    pub aggregate_details: &'static str,
}

pub(super) const TYPE_INSTANCE_COLLECTION_INITIAL_LABELS: TypeInstanceCollectionTimerLabels =
    TypeInstanceCollectionTimerLabels {
        scalar: "typecheck.type_instances.initial.collect_scalar.done",
        named: "typecheck.type_instances.initial.collect_named.done",
        aggregate_refs: "typecheck.type_instances.initial.collect_aggregate_refs.done",
        aggregate_details: "typecheck.type_instances.initial.collect_aggregate_details.done",
    };

pub(super) const TYPE_INSTANCE_COLLECTION_PROJECTED_LABELS: TypeInstanceCollectionTimerLabels =
    TypeInstanceCollectionTimerLabels {
        scalar: "typecheck.type_instances.projected.collect_scalar.done",
        named: "typecheck.type_instances.projected.collect_named.done",
        aggregate_refs: "typecheck.type_instances.projected.collect_aggregate_refs.done",
        aggregate_details: "typecheck.type_instances.projected.collect_aggregate_details.done",
    };

pub(super) fn record_type_instance_collection_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    bind_groups: &ResidentTypeCheckBindGroups,
    hir_active_dispatch_args: &wgpu::Buffer,
    labels: &TypeInstanceCollectionTimerLabels,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.type_instances_collect,
        &bind_groups.type_instances_collect,
        "type_check.resident.type_instances_collect.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, labels.scalar);
    record_compute_indirect(
        encoder,
        &passes.type_instances_collect_named,
        &bind_groups.type_instances_collect_named,
        "type_check.resident.type_instances_collect_named.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, labels.named);
    record_compute_indirect(
        encoder,
        &passes.type_instances_collect_aggregate_refs,
        &bind_groups.type_instances_collect_aggregate_refs,
        "type_check.resident.type_instances_collect_aggregate_refs.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, labels.aggregate_refs);
    record_compute_indirect(
        encoder,
        &passes.type_instances_collect_aggregate_details,
        &bind_groups.type_instances_collect_aggregate_details,
        "type_check.resident.type_instances_collect_aggregate_details.pass",
        hir_active_dispatch_args,
    )?;
    stamp_typecheck_timer(&mut timer, encoder, labels.aggregate_details);

    Ok(())
}

pub(super) fn record_hir_counted_u32_scan_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    n_blocks: u32,
    hir_active_dispatch_args: &wgpu::Buffer,
    scan: &U32ScanBindGroups,
    label: &'static str,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.counted_scan_local,
        &scan.local,
        label,
        hir_active_dispatch_args,
    )?;
    for bind_group in &scan.blocks {
        record_compute(
            encoder,
            &passes.counted_scan_blocks,
            bind_group,
            label,
            n_blocks.max(1),
        )?;
    }
    record_compute_indirect(
        encoder,
        &passes.counted_scan_apply,
        &scan.apply,
        label,
        hir_active_dispatch_args,
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
        &groups.hir_active_dispatch_args,
        groups.loop_n_blocks,
        &groups.loop_bind_groups,
    )
}

pub(super) fn record_visible_bind_groups_with_passes(
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
    record_hir_counted_u32_scan_bind_groups_with_passes(
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
    // are resolved below by sorted declaration tables instead of the legacy
    // token-neighborhood scatter/decode fallback.
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

pub(super) fn record_fn_context_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_active_dispatch_args: &wgpu::Buffer,
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
    record_compute_indirect(
        encoder,
        &passes.fn_context_mark,
        &groups.mark,
        "type_check.fn_context.mark",
        hir_active_dispatch_args,
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
    token_active_dispatch_args: &wgpu::Buffer,
    hir_active_dispatch_args: &wgpu::Buffer,
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
    record_compute_indirect(
        encoder,
        &passes.calls_return_refs,
        &groups.return_refs,
        "type_check.calls.return_refs",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_entrypoints,
        &groups.entrypoints,
        "type_check.calls.entrypoints",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_functions,
        &groups.functions,
        "type_check.calls.functions",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_param_types,
        &groups.param_types,
        "type_check.calls.param_types",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_intrinsics,
        &groups.intrinsics,
        "type_check.calls.intrinsics",
        hir_active_dispatch_args,
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
    record_compute_indirect(
        encoder,
        &passes.calls_pack_hir_call_args,
        &groups.pack_hir_call_args,
        "type_check.calls.pack_hir_call_args",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_resolve,
        &groups.resolve,
        "type_check.calls.resolve",
        token_active_dispatch_args,
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
    token_active_dispatch_args: &wgpu::Buffer,
    hir_active_dispatch_args: &wgpu::Buffer,
    groups: &MethodBindGroups,
) -> Result<()> {
    let lookup_work = token_capacity.max(1);
    record_compute(
        encoder,
        &passes.methods_clear,
        &groups.clear,
        "type_check.methods.clear",
        lookup_work,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_collect,
        &groups.collect,
        "type_check.methods.collect",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_attach_metadata,
        &groups.attach_metadata,
        "type_check.methods.attach_metadata",
        token_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_bind_self_receivers,
        &groups.bind_self_receivers,
        "type_check.methods.bind_self_receivers",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_seed_key_order,
        &groups.keys.seed_key_order,
        "type_check.methods.seed_key_order",
        token_active_dispatch_args,
    )?;
    for i in 0..groups.keys.sort_key_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.methods_sort_keys,
            &groups.keys.sort_key_histogram[i],
            "type_check.methods.sort_keys_histogram",
            token_active_dispatch_args,
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
        record_compute_indirect(
            encoder,
            &passes.methods_sort_keys_scatter,
            &groups.keys.sort_key_scatter[i],
            "type_check.methods.sort_keys_scatter",
            token_active_dispatch_args,
        )?;
    }
    record_compute_indirect(
        encoder,
        &passes.methods_validate_keys,
        &groups.keys.validate_keys,
        "type_check.methods.validate_keys",
        token_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_mark_call_keys,
        &groups.mark_call_keys,
        "type_check.methods.mark_call_keys",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_mark_call_return_keys,
        &groups.mark_call_return_keys,
        "type_check.methods.mark_call_return_keys",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_resolve_table,
        &groups.resolve_table,
        "type_check.methods.resolve_table",
        token_active_dispatch_args,
    )
}

pub(super) fn record_loop_depth_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_active_dispatch_args: &wgpu::Buffer,
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
    record_compute_indirect(
        encoder,
        &passes.loop_depth_mark,
        &groups.mark,
        "type_check.loop_depth.mark",
        hir_active_dispatch_args,
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

pub(super) fn record_compute_indirect(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &'static str,
    dispatch_args: &wgpu::Buffer,
) -> Result<()> {
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), &[]);
    compute.dispatch_workgroups_indirect(dispatch_args, 0);
    Ok(())
}
