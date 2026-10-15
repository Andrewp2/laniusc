use super::*;

/// Owns the dependency-page lifetime for a parameter-pattern operation.
/// Operations keep initialization, scans and indexes outside this replay;
/// only readers of page-local patterns execute once per immutable page.
pub(in crate::type_checker) struct DependencyPatternReplay<'a> {
    pub device: &'a wgpu::Device,
    pub queue: &'a wgpu::Queue,
    pub pages: Option<&'a GpuDependencyInterfacePages>,
    pub passes: &'a TypeCheckPasses,
    pub state: &'a ModulePathState,
}

impl DependencyPatternReplay<'_> {
    pub(in crate::type_checker) fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        mut pattern_reader: impl FnMut(&mut wgpu::CommandEncoder) -> Result<()>,
    ) -> Result<()> {
        if let Some(pages) = self.pages.filter(|pages| pages.len() > 1) {
            record_each_dependency_page(self.device, self.queue, encoder, pages, |encoder| {
                record_dependency_type_index(self.passes, encoder, self.state,
                    DEPENDENCY_TYPE_INDEX_CALL_PARAM_SCATTER)?;
                pattern_reader(encoder)
            })
        } else {
            pattern_reader(encoder)
        }
    }
}

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
    // Page uploads may overwrite every dependency word. Submit all work that
    // reads the current page, including deferred compute dispatches, first.
    crate::gpu::passes_core::flush_deferred_compute(encoder);
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
    match names.stage {
        DependencyPageStage::ModulePaths => visibility.project_types_group.record(encoder),
        // Type expressions are already checked here. Republishing a canonical
        // seed would erase their complete application and declaration identity.
        DependencyPageStage::CallCollection => Ok(()),
    }
}

/// Rebuilds the canonical type roots and declaration arity
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
        DependencyTypeIndexStage::AliasTargets => &visibility.type_index_alias_targets,
        DependencyTypeIndexStage::CallParamScatter => &visibility.type_index_call_param_scatter,
        DependencyTypeIndexStage::MethodProjection => &visibility.type_index_method_projection,
        DependencyTypeIndexStage::MethodLookup => &visibility.type_index_method_lookup,
        DependencyTypeIndexStage::ReturnMaterialization => {
            &visibility.type_index_return_materialization
        }
        DependencyTypeIndexStage::CallValidation => &visibility.type_index_call_validation,
        DependencyTypeIndexStage::TraitContracts => &visibility.type_index_trait_contracts,
    };
    visibility.type_index.record(encoder, invocations)
}

/// Collects candidate identities or projects the finalized winner for the
/// currently loaded page. The caller owns the all-pages barrier between phases.
pub(in crate::type_checker) fn record_dependency_methods(
    encoder: &mut wgpu::CommandEncoder,
    state: &ModulePathState,
    stage: MethodSelectionStage,
    collect: bool,
) -> Result<()> {
    let Some(visibility) = &state.dependency_visibility else {
        return Ok(());
    };
    let (collector, projection, scatter) = match stage {
        MethodSelectionStage::Direct => (
            DEPENDENCY_METHODS_COLLECT, DEPENDENCY_METHODS_PROJECT,
            DEPENDENCY_METHOD_PARAMS_SCATTER,
        ),
        // The lookup sweeps dispatch from their gated grids.
        MethodSelectionStage::Lookup => {
            return if collect {
                visibility.collect_methods_lookup.record(encoder)
            } else {
                visibility.project_methods_lookup.record(encoder)?;
                visibility.scatter_method_params_lookup.record(encoder)
            };
        }
        MethodSelectionStage::Inference => (
            DEPENDENCY_METHODS_COLLECT_INFERENCE, DEPENDENCY_METHODS_PROJECT_INFERENCE,
            DEPENDENCY_METHOD_PARAMS_SCATTER_INFERENCE,
        ),
    };
    if collect {
        visibility.collect_methods_group.record_as(encoder, collector.name)
    } else {
        visibility.project_methods_group.record_as(encoder, projection.name)?;
        // Publish exact parameter patterns while the winner's page is active.
        visibility.scatter_call_params_group.record_as(encoder, scatter.name)
    }
}

/// Validates calls whose stable declaration identities belong to the active
/// dependency page. Canonical argument and result checks finish before the
/// page slot may be overwritten.
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
    visibility.validate_call_arity_group.record(encoder)?;
    visibility.validate_call_args_group.record(encoder)?;
    visibility.validate_call_results_group.record(encoder)?;
    visibility
        .validate_call_results_group
        .record_invocation(encoder, &visibility.validate_call_results_validate)
}
