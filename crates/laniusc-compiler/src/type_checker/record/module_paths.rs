// src/type_checker/record/module_paths.rs

use super::*;

/// Records module, import, declaration, path, and projection relation passes.
pub(in crate::type_checker) fn record_module_path_state_with_passes(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    dependency_pages: Option<&GpuDependencyInterfacePages>,
    hir_active_dispatch_args: &wgpu::Buffer,
    _token_hir_active_dispatch_args: &wgpu::Buffer,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    record_module_path_prepare(
        passes,
        encoder,
        state,
        hir_active_dispatch_args,
        timer.as_deref_mut(),
    )?;
    if let Some(pages) = dependency_pages {
        record_dependency_pages(device, queue, encoder, pages, passes, state)?;
    } else {
        record_dependency_page(passes, encoder, state)?;
    }
    record_module_path_finalize(passes, encoder, state, timer)
}

pub(in crate::type_checker) fn record_module_path_prepare(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    hir_active_dispatch_args: &wgpu::Buffer,
    timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    record_module_path_stage(
        passes,
        encoder,
        state,
        hir_active_dispatch_args,
        timer,
        ModulePathRecordStage::Prepare,
    )
}

pub(in crate::type_checker) fn record_module_path_finalize(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    record_module_path_stage(
        passes,
        encoder,
        state,
        &state.path_dispatch_args,
        timer,
        ModulePathRecordStage::Finalize,
    )
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum ModulePathRecordStage {
    Prepare,
    Finalize,
}

fn record_module_path_stage(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    hir_active_dispatch_args: &wgpu::Buffer,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
    stage: ModulePathRecordStage,
) -> Result<()> {
    let hir_work = state.n_blocks.saturating_mul(256).max(1);

    if stage != ModulePathRecordStage::Finalize {
        state.bind_groups.mark_records.record(encoder)?;
        stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.mark_records.done");
        record_compute(
            encoder,
            &passes.kernel("type_checker/modules/01a_clear_path_state"),
            &state.bind_groups.clear_path_state,
            "type_check.modules.clear_path_state",
            hir_work,
        )?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/modules/01_scatter_paths"),
            &state.bind_groups.scatter_paths,
            "type_check.modules.scatter_paths",
            hir_work,
        )?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/count/dispatch_args"),
            &state.bind_groups.path_dispatch_args,
            "type_check.modules.path_dispatch_args",
            1,
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/01b/count_path_segments"),
            &state.bind_groups.count_path_segments,
            "type_check.modules.count_path_segments",
            &state.path_dispatch_args,
        )?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/modules/01b/scatter_path_segments"),
            &state.bind_groups.scatter_path_segments,
            "type_check.modules.scatter_path_segments",
            hir_work,
        )?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/modules/01c_path_prefix_dispatch_args"),
            &state.bind_groups.path_prefix_dispatch_args,
            "type_check.modules.path_prefix_dispatch_args",
            32,
        )?;
        for (round_i, round) in state.bind_groups.path_prefix_rounds.iter().enumerate() {
            let offset = round_i as u64 * 3 * std::mem::size_of::<u32>() as u64;
            record_compute_indirect_offset(
                encoder,
                &passes.kernel("type_checker/modules/01c_path_prefix_table_clear"),
                &round.clear,
                "type_check.modules.path_prefix_table_clear",
                &state.path_prefix_round_dispatch_args,
                offset,
            )?;
            record_compute_indirect_offset(
                encoder,
                &passes.kernel("type_checker/modules/01c_path_prefix_table_insert"),
                &round.insert,
                "type_check.modules.path_prefix_table_insert",
                &state.path_prefix_round_dispatch_args,
                offset,
            )?;
            record_compute_indirect_offset(
                encoder,
                &passes.kernel("type_checker/modules/01c_path_prefix_table_lookup"),
                &round.lookup,
                "type_check.modules.path_prefix_table_lookup",
                &state.path_prefix_round_dispatch_args,
                offset,
            )?;
        }
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/01c_path_prefix_finalize"),
            &state.bind_groups.path_prefix_finalize,
            "type_check.modules.path_prefix_finalize",
            &state.path_prefix_row_dispatch_args,
        )?;
        stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.paths.done");
        state.bind_groups.module_records.record(encoder)?;
        let module_key_work = state.module_n_blocks.saturating_mul(256).max(1);
        record_compute(
            encoder,
            &passes.kernel("type_checker/modules/02e_build_module_keys"),
            &state.bind_groups.build_module_keys,
            "type_check.modules.build_module_keys",
            module_key_work,
        )?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/names/radix/dispatch_args"),
            &state.bind_groups.module_key_radix_dispatch,
            "type_check.modules.module_key_radix_dispatch_args",
            1,
        )?;
        state.bind_groups.sort_module_keys.record(encoder)?;
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.modules.sort_module_keys.done",
        );
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/04_validate_modules"),
            &state.bind_groups.validate_modules,
            "type_check.modules.validate_modules",
            &state.module_key_radix_dispatch_args,
        )?;
        state.bind_groups.import_records.record(encoder)?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/count/dispatch_args"),
            &state.bind_groups.import_dispatch_args,
            "type_check.modules.import_dispatch_args",
            1,
        )?;
        state.bind_groups.decl_records.record(encoder)?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/modules/02c1_append_variant_decl_count"),
            &state.bind_groups.append_variant_decl_count,
            "type_check.modules.append_variant_decl_count",
            1,
        )?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/modules/02d/clear_decl_lookup"),
            &state.bind_groups.clear_decl_lookup,
            "type_check.modules.clear_decl_lookup",
            state.token_capacity.max(1),
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/02d/scatter_decl_span_records"),
            &state.bind_groups.scatter_decl_span_records,
            "type_check.modules.scatter_decl_span_records",
            hir_active_dispatch_args,
        )?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/modules/02c2_scatter_variant_decl_records"),
            &state.bind_groups.scatter_variant_decl_records,
            "type_check.modules.scatter_variant_decl_records",
            hir_work,
        )?;
        state.bind_groups.clear_file_module_map.record(encoder)?;
        state.bind_groups.build_file_module_map.record(encoder)?;
        stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.module_maps.done");
        state.bind_groups.attach_record_modules.record(encoder)?;
        state.bind_groups.resolve_imports.record(encoder)?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/names/radix/dispatch_args"),
            &state.bind_groups.import_edge_key_radix_dispatch,
            "type_check.modules.import_edge_key_radix_dispatch_args",
            1,
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/05e_seed_import_edge_key_order"),
            &state.bind_groups.seed_import_edge_key_order,
            "type_check.modules.seed_import_edge_key_order",
            &state.import_edge_key_radix_dispatch_args,
        )?;
        state.bind_groups.sort_import_edges.record(encoder)?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/05h_validate_import_cycles"),
            &state.bind_groups.validate_import_cycles,
            "type_check.modules.validate_import_cycles",
            &state.import_edge_key_radix_dispatch_args,
        )?;
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.modules.record_scans_and_import_decl_records.done",
        );
        record_compute(
            encoder,
            &passes.kernel("type_checker/names/radix/dispatch_args"),
            &state.bind_groups.decl_key_radix_dispatch,
            "type_check.modules.decl_key_radix_dispatch_args",
            1,
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/06a_seed_decl_key_order"),
            &state.bind_groups.seed_decl_key_order,
            "type_check.modules.seed_decl_key_order",
            &state.decl_key_radix_dispatch_args,
        )?;
        state.bind_groups.sort_decl_keys.record(encoder)?;
        stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.sort_decl_keys.done");
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/07_validate_decls"),
            &state.bind_groups.validate_decls,
            "type_check.modules.validate_decls",
            &state.decl_key_radix_dispatch_args,
        )?;
        state.bind_groups.mark_decl_namespace_keys.record(encoder)?;
        PrefixScanOperation::record_pair(
            &state.bind_groups.decl_type_key_scan,
            &state.bind_groups.decl_value_key_scan,
            encoder,
        )?;
        state
            .bind_groups
            .scatter_decl_namespace_keys
            .record(encoder)?;
        state.bind_groups.mark_public_decl_keys.record(encoder)?;
        PrefixScanOperation::record_pair(
            &state.bind_groups.decl_type_public_scan,
            &state.bind_groups.decl_value_public_scan,
            encoder,
        )?;
        let interface_decl_capacity =
            u32::try_from(state.interface_public_decl_local_id.count).unwrap_or(u32::MAX);
        record_compute(
            encoder,
            &passes.kernel("type_checker/interface/public_decls/00_clear"),
            &state.bind_groups.clear_interface_public_decls,
            "type_check.interface.public_decls.clear",
            interface_decl_capacity,
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/interface/public_decls/01_map"),
            &state.bind_groups.map_interface_public_decls,
            "type_check.interface.public_decls.map",
            &state.decl_key_radix_dispatch_args,
        )?;
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.modules.decl_namespace_keys.done",
        );
        state.bind_groups.count_import_visibility.record(encoder)?;
        PrefixScanOperation::record_pair(
            &state.bind_groups.import_visible_type_scan,
            &state.bind_groups.import_visible_value_scan,
            encoder,
        )?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/names/radix/dispatch_args"),
            &state.bind_groups.import_visible_type_key_radix_dispatch,
            "type_check.modules.import_visible_type_key_radix_dispatch_args",
            1,
        )?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/names/radix/dispatch_args"),
            &state.bind_groups.import_visible_value_key_radix_dispatch,
            "type_check.modules.import_visible_value_key_radix_dispatch_args",
            1,
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/09b_scatter_import_visibility"),
            &state.bind_groups.scatter_import_visible_type,
            "type_check.modules.scatter_import_visible_type",
            &state.import_visible_type_key_radix_dispatch_args,
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/09b_scatter_import_visibility"),
            &state.bind_groups.scatter_import_visible_value,
            "type_check.modules.scatter_import_visible_value",
            &state.import_visible_value_key_radix_dispatch_args,
        )?;
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.modules.import_visibility_scatter.done",
        );
        record_radix_sort_batch(
            &[
                RadixSortBatchItem {
                    sort: &state.bind_groups.sort_import_visible_type_keys,
                },
                RadixSortBatchItem {
                    sort: &state.bind_groups.sort_import_visible_value_keys,
                },
            ],
            encoder,
        )?;
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.modules.sort_import_visible_keys.done",
        );
        count_recorded_compute_pass();
        {
            let mut batch = crate::gpu::passes_core::ComputePassBatch::begin(
                encoder,
                "type_check.modules.build_import_visible_key_tables.paired",
            );
            batch.record_raw_indirect(
                &passes.kernel("type_checker/modules/09e_build_import_visible_key_tables"),
                &state.bind_groups.build_import_visible_type_key_table,
                &state.import_visible_type_key_radix_dispatch_args,
            );
            batch.record_raw_indirect(
                &passes.kernel("type_checker/modules/09e_build_import_visible_key_tables"),
                &state.bind_groups.build_import_visible_value_key_table,
                &state.import_visible_value_key_radix_dispatch_args,
            );
        }
        record_compute(
            encoder,
            &passes.kernel("type_checker/count/pair_max_dispatch_args"),
            &state.bind_groups.import_visible_validate_dispatch_args,
            "type_check.modules.import_visible_validate_dispatch_args",
            1,
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/09f_validate_import_visible_keys"),
            &state.bind_groups.initialize_import_visible_keys,
            "type_check.modules.initialize_import_visible_keys",
            &state.import_visible_validate_dispatch_args,
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/09f_validate_import_visible_keys"),
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
            &passes.kernel("type_checker/modules/10_resolve_local_paths"),
            &state.bind_groups.resolve_local_type_paths,
            "type_check.modules.resolve_local_type_paths",
            &state.path_dispatch_args,
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/10_resolve_local_paths"),
            &state.bind_groups.resolve_local_value_paths,
            "type_check.modules.resolve_local_value_paths",
            &state.path_dispatch_args,
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/10b_resolve_imported_paths"),
            &state.bind_groups.resolve_imported_type_paths,
            "type_check.modules.resolve_imported_type_paths",
            &state.path_dispatch_args,
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/10b_resolve_imported_paths"),
            &state.bind_groups.resolve_imported_value_paths,
            "type_check.modules.resolve_imported_value_paths",
            &state.path_dispatch_args,
        )?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/modules/10d_clear_type_path_types"),
            &state.bind_groups.clear_type_path_types,
            "type_check.modules.clear_type_path_types",
            state.token_capacity.max(1),
        )?;
    }
    if stage != ModulePathRecordStage::Prepare {
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/10c_resolve_qualified_paths"),
            &state.bind_groups.resolve_qualified_type_paths,
            "type_check.modules.resolve_qualified_type_paths",
            &state.path_dispatch_args,
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/10c_resolve_qualified_paths"),
            &state.bind_groups.resolve_qualified_value_paths,
            "type_check.modules.resolve_qualified_value_paths",
            &state.path_dispatch_args,
        )?;
        stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.resolve_paths.done");
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/10e_project_type_paths"),
            &state.bind_groups.project_type_paths,
            "type_check.modules.project_type_paths",
            &state.path_dispatch_args,
        )?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/modules/10f_mark_value_call_paths"),
            &state.bind_groups.mark_value_call_paths,
            "type_check.modules.mark_value_call_paths",
            state
                .token_capacity
                .max(state.parser_hir_n_blocks.saturating_mul(256))
                .max(1),
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/10g_project_value_paths"),
            &state.bind_groups.project_value_paths,
            "type_check.modules.project_value_paths",
            &state.path_dispatch_args,
        )?;
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/10e3_validate_type_paths"),
            &state.bind_groups.validate_type_paths,
            "type_check.modules.validate_type_paths",
            &state.path_dispatch_args,
        )?;
    }
    Ok(())
}
