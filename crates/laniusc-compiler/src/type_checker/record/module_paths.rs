// src/type_checker/record/module_paths.rs

use super::*;

/// Records module, import, declaration, path, and projection relation passes.
#[allow(clippy::too_many_arguments)]
pub(in crate::type_checker) fn record_module_path_state_with_passes(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    dependency_pages: Option<&GpuDependencyInterfacePages>,
    rows: u32,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    record_module_path_prepare(encoder, state, rows, timer.as_deref_mut())?;
    if let Some(visibility) = state.dependency_visibility.as_ref() {
        visibility.clear_workspace_group.record(encoder)?;
    }
    if let Some(pages) = dependency_pages {
        record_dependency_pages(device, queue, encoder, pages, passes, state)?;
    } else {
        record_dependency_page(passes, encoder, state, DEPENDENCY_PAGE_MODULE_PATHS)?;
    }
    record_module_path_finalize(encoder, state, timer)
}

fn record_module_path_prepare(
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    rows: u32,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
    state.programs.build_paths.record(encoder, rows)?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.paths.done");
    state.programs.compact_records.record(encoder, rows)?;
    state.bind_groups.clear_module_lookup.record(encoder)?;
    state.bind_groups.build_module_keys.record(encoder)?;
    state.bind_groups.module_dispatch.record(encoder)?;
    stamp_typecheck_timer(&mut timer, encoder, "typecheck.modules.module_lookup.done");
    state.bind_groups.validate_modules.record(encoder)?;
    state.bind_groups.import_dispatch_args.record(encoder)?;
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
    state.bind_groups.decl_namespace_scan.record(encoder)?;
    state
        .bind_groups
        .scatter_decl_namespace_keys
        .record(encoder)?;
    state.bind_groups.mark_public_decl_keys.record(encoder)?;
    state.bind_groups.decl_public_scan.record(encoder)?;
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
    state.bind_groups.import_visible_scan.record(encoder)?;
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
    Ok(())
}

fn record_module_path_finalize(
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
) -> Result<()> {
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
    Ok(())
}
