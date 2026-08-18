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
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    record_module_path_prepare(passes, encoder, state, timer.as_deref_mut())?;
    if let Some(visibility) = state.dependency_visibility.as_ref() {
        visibility.clear_workspace_group.record(encoder)?;
    }
    if let Some(pages) = dependency_pages {
        record_dependency_pages(device, queue, encoder, pages, passes, state)?;
    } else {
        record_dependency_page(passes, encoder, state, DEPENDENCY_PAGE_MODULE_PATHS)?;
    }
    record_module_path_finalize(passes, encoder, state, timer)
}

pub(in crate::type_checker) fn record_module_path_prepare(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    record_module_path_stage(
        passes,
        encoder,
        state,
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
    _passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
    stage: ModulePathRecordStage,
) -> Result<()> {
    if stage != ModulePathRecordStage::Finalize {
        state.bind_groups.mark_records.record(encoder)?;
        stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.mark_records.done");
        state.bind_groups.clear_path_state.record(encoder)?;
        state.bind_groups.scatter_paths.record(encoder)?;
        state.bind_groups.path_dispatch_args.record(encoder)?;
        state.bind_groups.count_path_segments.record(encoder)?;
        state.bind_groups.scatter_path_segments.record(encoder)?;
        state
            .bind_groups
            .path_prefix_dispatch_args
            .record(encoder)?;
        state
            .bind_groups
            .path_prefix_initial_table_clear
            .record(encoder)?;
        for round in &state.bind_groups.path_prefix_rounds {
            round.intern.record(encoder)?;
        }
        state.bind_groups.path_prefix_finalize.record(encoder)?;
        stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.paths.done");
        state.bind_groups.module_records.record(encoder)?;
        state.bind_groups.clear_module_lookup.record(encoder)?;
        state.bind_groups.build_module_keys.record(encoder)?;
        state.bind_groups.module_dispatch.record(encoder)?;
        stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.module_lookup.done");
        state.bind_groups.validate_modules.record(encoder)?;
        state.bind_groups.import_records.record(encoder)?;
        state.bind_groups.import_dispatch_args.record(encoder)?;
        state.bind_groups.decl_records.record(encoder)?;
        state
            .bind_groups
            .append_variant_decl_count
            .record(encoder)?;
        state.bind_groups.clear_decl_lookup.record(encoder)?;
        state
            .bind_groups
            .scatter_decl_span_records
            .record(encoder)?;
        state
            .bind_groups
            .scatter_variant_decl_records
            .record(encoder)?;
        state.bind_groups.clear_file_module_map.record(encoder)?;
        state.bind_groups.build_file_module_map.record(encoder)?;
        stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.module_maps.done");
        state.bind_groups.attach_record_modules.record(encoder)?;
        state.bind_groups.resolve_imports.record(encoder)?;
        state.bind_groups.clear_import_edge_set.record(encoder)?;
        state.bind_groups.build_import_edge_set.record(encoder)?;
        state.bind_groups.validate_import_cycles.record(encoder)?;
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.modules.record_scans_and_import_decl_records.done",
        );
        state.bind_groups.decl_key_radix_dispatch.record(encoder)?;
        state.bind_groups.sort_decl_keys.record(encoder)?;
        stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.sort_decl_keys.done");
        state.bind_groups.validate_decls.record(encoder)?;
        state.bind_groups.decl_lookup.record(encoder)?;
        state.bind_groups.validate_decl_duplicates.record(encoder)?;
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
        state
            .bind_groups
            .clear_interface_public_decls
            .record(encoder)?;
        state
            .bind_groups
            .map_interface_public_decls
            .record(encoder)?;
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
        state
            .bind_groups
            .import_visible_validate_dispatch_args
            .record(encoder)?;
        ComputeOperation::record_pair(
            &state.bind_groups.scatter_import_visible_type,
            &state.bind_groups.scatter_import_visible_value,
            encoder,
        )?;
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.modules.import_visibility_scatter.done",
        );
        ComputeOperation::record_pair(
            &state.bind_groups.clear_import_visible_type_lookup,
            &state.bind_groups.clear_import_visible_value_lookup,
            encoder,
        )?;
        ComputeOperation::record_pair(
            &state.bind_groups.build_import_visible_type_key_table,
            &state.bind_groups.build_import_visible_value_key_table,
            encoder,
        )?;
        state
            .bind_groups
            .initialize_import_visible_keys
            .record(encoder)?;
        state
            .bind_groups
            .validate_import_visible_keys
            .record(encoder)?;
        stamp_typecheck_timer(
            &mut timer,
            encoder,
            "typecheck.modules.import_visible_tables.done",
        );
        ComputeOperation::record_pair(
            &state.bind_groups.resolve_local_type_paths,
            &state.bind_groups.resolve_local_value_paths,
            encoder,
        )?;
        ComputeOperation::record_pair(
            &state.bind_groups.resolve_imported_type_paths,
            &state.bind_groups.resolve_imported_value_paths,
            encoder,
        )?;
        state.bind_groups.clear_type_path_types.record(encoder)?;
    }
    if stage != ModulePathRecordStage::Prepare {
        ComputeOperation::record_pair(
            &state.bind_groups.resolve_qualified_type_paths,
            &state.bind_groups.resolve_qualified_value_paths,
            encoder,
        )?;
        stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.resolve_paths.done");
        state.bind_groups.project_type_paths.record(encoder)?;
        state.bind_groups.mark_value_call_paths.record(encoder)?;
        state.bind_groups.project_value_paths.record(encoder)?;
        state.bind_groups.validate_type_paths.record(encoder)?;
    }
    Ok(())
}
