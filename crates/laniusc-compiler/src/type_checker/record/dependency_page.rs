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
        record_dependency_page(passes, encoder, state, DEPENDENCY_PAGE_MODULE_PATHS)
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

fn record_graph_invocation(
    operation: &ComputeOperation,
    invocation: Option<&ComputeInvocation>,
    encoder: &mut wgpu::CommandEncoder,
) -> Result<()> {
    if let Some(invocation) = invocation {
        operation.record_invocation(encoder, invocation)
    } else {
        operation.record(encoder)
    }
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
    names: DependencyPagePassNames,
) -> Result<()> {
    let Some(visibility) = &state.dependency_visibility else {
        return Ok(());
    };
    let dependencies = state
        .dependency_interfaces
        .as_ref()
        .expect("dependency visibility requires dependency interfaces");
    let _ = dependencies;
    let clear_module_lookup = state
        .bind_groups
        .clear_dependency_module_lookup
        .as_ref()
        .expect("dependency interfaces require module lookup clear");
    let build_module_lookup = state
        .bind_groups
        .build_dependency_module_lookup
        .as_ref()
        .expect("dependency interfaces require module lookup build");
    let resolve_imports = state
        .bind_groups
        .resolve_dependency_imports
        .as_ref()
        .expect("dependency interfaces require import resolution");
    match names.stage {
        DependencyPageStage::ModulePaths => {
            clear_module_lookup.record(encoder)?;
            build_module_lookup.record(encoder)?;
            resolve_imports.record(encoder)?;
        }
        DependencyPageStage::CallCollection => {
            clear_module_lookup.record_invocation(
                encoder,
                state
                    .bind_groups
                    .clear_dependency_module_lookup_call_collection
                    .as_ref()
                    .expect("dependency call collection requires module lookup clear"),
            )?;
            build_module_lookup.record_invocation(
                encoder,
                state
                    .bind_groups
                    .build_dependency_module_lookup_call_collection
                    .as_ref()
                    .expect("dependency call collection requires module lookup build"),
            )?;
            resolve_imports.record_invocation(
                encoder,
                state
                    .bind_groups
                    .resolve_dependency_imports_call_collection
                    .as_ref()
                    .expect("dependency call collection requires import resolution"),
            )?;
        }
    }
    let call_collection = match names.stage {
        DependencyPageStage::ModulePaths => None,
        DependencyPageStage::CallCollection => Some(visibility),
    };
    record_graph_invocation(
        &visibility.count_group,
        call_collection.map(|state| &state.count_call_collection),
        encoder,
    )?;
    visibility
        .scan
        .record_with_graph_passes(encoder, names.visible_scan)?;
    record_graph_invocation(
        &visibility.scatter_group,
        call_collection.map(|state| &state.scatter_call_collection),
        encoder,
    )?;
    record_graph_invocation(
        &visibility.clear_lookup_group,
        call_collection.map(|state| &state.clear_lookup_call_collection),
        encoder,
    )?;
    record_graph_invocation(
        &visibility.build_lookup_group,
        call_collection.map(|state| &state.build_lookup_call_collection),
        encoder,
    )?;
    record_graph_invocation(
        &visibility.resolve_type_group,
        call_collection.map(|state| &state.resolve_type_call_collection),
        encoder,
    )?;
    record_graph_invocation(
        &visibility.resolve_value_group,
        call_collection.map(|state| &state.resolve_value_call_collection),
        encoder,
    )?;
    record_dependency_type_index(passes, encoder, state, names.type_index)?;
    record_graph_invocation(
        &visibility.project_types_group,
        call_collection.map(|state| &state.project_types_call_collection),
        encoder,
    )
}

/// Rebuilds the canonical type roots, subtree bounds, and declaration arity
/// for whichever page currently occupies the reusable dependency slot.
pub(in crate::type_checker) fn record_dependency_type_index(
    _passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    names: DependencyTypeIndexPassNames,
) -> Result<()> {
    let Some(visibility) = &state.dependency_visibility else {
        return Ok(());
    };
    let invocations = match names.stage {
        DependencyTypeIndexStage::ModulePaths => &visibility.type_index_module_paths,
        DependencyTypeIndexStage::CallCollection => &visibility.type_index_call_collection,
        DependencyTypeIndexStage::AfterTypeClear => &visibility.type_index_after_type_clear,
        DependencyTypeIndexStage::TypeInstanceProjection => {
            &visibility.type_index_type_instance_projection
        }
        DependencyTypeIndexStage::CallParamScatter => &visibility.type_index_call_param_scatter,
        DependencyTypeIndexStage::MethodProjection => &visibility.type_index_method_projection,
        DependencyTypeIndexStage::CallValidation => &visibility.type_index_call_validation,
    };
    visibility.type_index.record(encoder, invocations)
}

/// Projects direct member calls against the dependency page currently loaded
/// in the shared interface slot.  The projection runs before local method
/// resolution so imported methods are treated as resolved call targets rather
/// than being rejected by the local method table.
pub(in crate::type_checker) fn record_dependency_methods(
    _passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    _hir_active_dispatch_args: &LaniusBuffer<u32>,
) -> Result<()> {
    let Some(visibility) = &state.dependency_visibility else {
        return Ok(());
    };
    visibility.project_methods_group.record(encoder)
}

/// Validates calls whose stable declaration identities belong to the active
/// dependency page. Compound comparison requests are produced, scanned, and
/// consumed before the page slot may be overwritten.
pub(in crate::type_checker) fn record_dependency_call_validation(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    _hir_active_dispatch_args: &LaniusBuffer<u32>,
    rebuild_type_index: bool,
) -> Result<()> {
    let Some(visibility) = &state.dependency_visibility else {
        return Ok(());
    };
    if rebuild_type_index {
        record_dependency_type_index(
            passes,
            encoder,
            state,
            DEPENDENCY_TYPE_INDEX_CALL_VALIDATION,
        )?;
    }
    visibility.call_compare_scan_input.clear(encoder, 0, None);
    visibility.validate_call_args_group.record(encoder)?;
    visibility.validate_call_results_group.record(encoder)?;
    visibility
        .validate_call_results_group
        .record_invocation(encoder, &visibility.validate_call_results_validate)?;
    visibility.call_compare_scan.record(encoder)?;
    visibility.call_compare_dispatch_group.record(encoder)?;
    visibility.validate_call_type_args_group.record(encoder)
}
