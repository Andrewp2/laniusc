use super::*;

/// Streams every logical dependency page through one fixed GPU slot. A queue
/// submission separates each upload from the next overwrite; without that
/// ordering, all recorded dispatches would observe only the final page.
pub(in crate::type_checker) fn record_dependency_pages(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    pages: &GpuDependencyInterfacePages,
    passes: &TypeCheckPasses,
    state: &ModulePathState,
) -> Result<()> {
    record_each_dependency_page(device, queue, encoder, pages, |encoder| {
        record_dependency_page(passes, encoder, state)
    })
}

/// Records an arbitrary page-local operation over every dependency page while
/// keeping the upload/submission ordering in one place.
pub(in crate::type_checker) fn record_each_dependency_page(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    pages: &GpuDependencyInterfacePages,
    mut record: impl FnMut(&mut wgpu::CommandEncoder) -> Result<()>,
) -> Result<()> {
    if pages.len() == 1 {
        return record(encoder);
    }
    submit_dependency_page_boundary(device, queue, encoder);
    for page in 0..pages.len() {
        pages.write(queue, page)?;
        record(encoder)?;
        submit_dependency_page_boundary(device, queue, encoder);
    }
    Ok(())
}

fn submit_dependency_page_boundary(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
) {
    let next = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("type-check-dependency-page-encoder"),
    });
    let recorded = std::mem::replace(encoder, next);
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "type-check dependency page boundary",
        recorded.finish(),
    );
}

/// Records the complete page-local dependency lookup and projection region.
/// Local module/path discovery must precede this operation; consumers of the
/// projected stable identities must follow it. The operation contains no
/// allocation or bind-group construction and can therefore be submitted once
/// for every page loaded into the same dependency slot.
pub(in crate::type_checker) fn record_dependency_page(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
) -> Result<()> {
    let Some(visibility) = &state.dependency_visibility else {
        return Ok(());
    };
    let dependencies = state
        .dependency_interfaces
        .as_ref()
        .expect("dependency visibility requires dependency interfaces");
    record_compute(
        encoder,
        &passes.kernel("type_checker/dependencies/00a_clear_module_lookup"),
        state
            .bind_groups
            .clear_dependency_module_lookup
            .as_ref()
            .expect("dependency interfaces require module lookup clear"),
        "type_check.dependencies.clear_module_lookup",
        dependencies.module_lookup_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/dependencies/00_build_module_lookup"),
        state
            .bind_groups
            .build_dependency_module_lookup
            .as_ref()
            .expect("dependency interfaces require module lookup build"),
        "type_check.dependencies.build_module_lookup",
        dependencies.module_count.max(1),
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/dependencies/01_resolve_imports"),
        state
            .bind_groups
            .resolve_dependency_imports
            .as_ref()
            .expect("dependency interfaces require import resolution"),
        "type_check.dependencies.resolve_imports",
        &state.import_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/dependencies/02_count_import_visibility"),
        &visibility.count_group,
        "type_check.dependencies.count_import_visibility",
        &state.import_dispatch_args,
    )?;
    visibility.scan.record(encoder)?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/dependencies/03_scatter_import_visibility"),
        &visibility.scatter_group,
        "type_check.dependencies.scatter_import_visibility",
        visibility.visible_capacity,
    )?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/dependencies/04_clear_visible_lookup"),
        &visibility.clear_lookup_group,
        "type_check.dependencies.clear_visible_lookup",
        visibility.lookup_capacity,
    )?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/dependencies/05_build_visible_lookup"),
        &visibility.build_lookup_group,
        "type_check.dependencies.build_visible_lookup",
        visibility.visible_capacity,
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/dependencies/06_resolve_paths"),
        &visibility.resolve_type_group,
        "type_check.dependencies.resolve_type_paths",
        &state.path_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/dependencies/06_resolve_paths"),
        &visibility.resolve_value_group,
        "type_check.dependencies.resolve_value_paths",
        &state.path_dispatch_args,
    )?;
    record_dependency_type_index(passes, encoder, state)?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/dependencies/11_project_types"),
        &visibility.project_types_group,
        "type_check.dependencies.project_types",
        &state.path_dispatch_args,
    )
}

/// Rebuilds the canonical type roots, subtree bounds, and declaration arity
/// for whichever page currently occupies the reusable dependency slot.
pub(in crate::type_checker) fn record_dependency_type_index(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
) -> Result<()> {
    let Some(visibility) = &state.dependency_visibility else {
        return Ok(());
    };
    record_compute(
        encoder,
        &passes.kernel("type_checker/dependencies/09_init_canonical_type_roots"),
        &visibility.init_canonical_type_index_group,
        "type_check.dependencies.init_canonical_type_index",
        visibility.canonical_type_count.max(1),
    )?;
    for round in 0..visibility.canonical_type_jump_rounds {
        let group = if round % 2 == 0 {
            &visibility.jump_canonical_type_index_a_to_b_group
        } else {
            &visibility.jump_canonical_type_index_b_to_a_group
        };
        record_compute(
            encoder,
            &passes.kernel("type_checker/dependencies/10_jump_canonical_type_roots"),
            group,
            "type_check.dependencies.jump_canonical_type_index",
            visibility.canonical_type_count.max(1),
        )?;
    }
    record_compute(
        encoder,
        &passes.kernel("type_checker/dependencies/12_clear_declaration_generic_arity"),
        &visibility.clear_declaration_generic_arity_group,
        "type_check.dependencies.clear_declaration_generic_arity",
        visibility.canonical_declaration_count.max(1),
    )?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/dependencies/13_count_declaration_generic_arity"),
        &visibility.count_declaration_generic_arity_group,
        "type_check.dependencies.count_declaration_generic_arity",
        visibility.canonical_member_count.max(1),
    )
}

/// Projects direct member calls against the dependency page currently loaded
/// in the shared interface slot.  The projection runs before local method
/// resolution so imported methods are treated as resolved call targets rather
/// than being rejected by the local method table.
pub(in crate::type_checker) fn record_dependency_methods(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    hir_active_dispatch_args: &LaniusBuffer<u32>,
) -> Result<()> {
    let Some(visibility) = &state.dependency_visibility else {
        return Ok(());
    };
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/dependencies/15_project_methods"),
        &visibility.project_methods_group,
        "type_check.dependencies.project_methods",
        hir_active_dispatch_args,
    )
}

/// Validates calls whose stable declaration identities belong to the active
/// dependency page. Compound comparison requests are produced, scanned, and
/// consumed before the page slot may be overwritten.
pub(in crate::type_checker) fn record_dependency_call_validation(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    hir_active_dispatch_args: &LaniusBuffer<u32>,
    rebuild_type_index: bool,
) -> Result<()> {
    let Some(visibility) = &state.dependency_visibility else {
        return Ok(());
    };
    if rebuild_type_index {
        record_dependency_type_index(passes, encoder, state)?;
    }
    visibility.call_compare_scan_input.clear(encoder, 0, None);
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/dependencies/08_validate_call_args"),
        &visibility.validate_call_args_group,
        "type_check.dependencies.validate_call_args",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/dependencies/08a_validate_call_results"),
        &visibility.validate_call_results_group,
        "type_check.dependencies.validate_call_results.substitute",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/dependencies/08a_validate_call_results"),
        &visibility.validate_call_results_group,
        "type_check.dependencies.validate_call_results.validate",
        hir_active_dispatch_args,
    )?;
    visibility.call_compare_scan.record(encoder)?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/count/dispatch_args"),
        &visibility.call_compare_dispatch_group,
        "type_check.dependencies.call_compare_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/dependencies/08b_validate_call_type_args"),
        &visibility.validate_call_type_args_group,
        "type_check.dependencies.validate_call_type_args",
        &visibility.call_compare_dispatch_args,
    )
}
