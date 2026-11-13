use super::*;

/// Owns the dependency-page lifetime for a parameter-pattern operation.
/// Operations keep initialization, scans and indexes outside this replay;
/// only readers of page-local patterns execute once per immutable page.
pub(in crate::type_checker) struct DependencyPatternReplay<'a> {
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
            record_each_dependency_page(self.state, encoder, pages, |encoder| {
                record_dependency_type_index(self.passes, encoder, self.state,
                    DEPENDENCY_TYPE_INDEX_CALL_PARAM_SCATTER)?;
                pattern_reader(encoder)
            })
        } else {
            pattern_reader(encoder)
        }
    }
}

/// Streams every logical dependency page through one fixed GPU slot. Each
/// page is copied into the slot from the job's resident page store by a GPU
/// copy recorded before the page's passes, so the copies and the passes
/// execute in recording order within one submission.
pub(in crate::type_checker) fn record_dependency_pages(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    pages: &GpuDependencyInterfacePages,
    passes: &TypeCheckPasses,
    state: &ModulePathState,
) -> Result<()> {
    let _ = (device, queue);
    record_each_dependency_page(state, encoder, pages, |encoder| {
        record_dependency_page(passes, encoder, state, DEPENDENCY_PAGE_MODULE_PATHS)
    })
}

/// Records an arbitrary page-local operation over every dependency page while
/// keeping the upload/submission ordering in one place.
///
/// A page that enters the slot gets its method index rebuilt before the
/// operation reads it. A job with one page keeps that page in the slot, so
/// its callers pass it here once, for the module path stage, and record
/// later operations directly.
pub(in crate::type_checker) fn record_each_dependency_page(
    state: &ModulePathState,
    encoder: &mut wgpu::CommandEncoder,
    pages: &GpuDependencyInterfacePages,
    mut record: impl FnMut(&mut wgpu::CommandEncoder) -> Result<()>,
) -> Result<()> {
    let index_methods = |encoder: &mut wgpu::CommandEncoder| {
        for operation in state.bind_groups.dependency_method_lookup.iter().flatten() {
            operation.record(encoder)?;
        }
        Ok::<_, anyhow::Error>(())
    };
    if pages.len() == 1 {
        index_methods(encoder)?;
        return record(encoder);
    }
    for page in 0..pages.len() {
        pages.record_page(encoder, page)?;
        index_methods(encoder)?;
        record(encoder)?;
    }
    Ok(())
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
    // The index is a function of the loaded dependency page alone: its roots,
    // arity and field counts are written only by these passes, its constant
    // atoms and references are cleared once before the first build, and the
    // graph keeps each of these workspace resources for one interval from the
    // first build to the last read. With a single page the first build of a
    // recording therefore serves every later stage; with several pages each
    // page needs its own.
    use std::sync::atomic::Ordering::Relaxed;
    let reusable = visibility.type_index_reusable.load(Relaxed);
    if reusable && visibility.type_index_current.load(Relaxed) {
        return Ok(());
    }
    visibility.type_index.record(encoder, invocations)?;
    visibility.type_index_current.store(reusable, Relaxed);
    Ok(())
}

/// Starts a type-check recording's type index: none is built yet, and the
/// first build is reusable when the job loads at most one dependency page.
pub(in crate::type_checker) fn reset_dependency_type_index(
    state: &ModulePathState,
    pages: Option<&GpuDependencyInterfacePages>,
) {
    use std::sync::atomic::Ordering::Relaxed;
    let Some(visibility) = &state.dependency_visibility else {
        return;
    };
    let single_page = pages.is_none_or(|pages| pages.len() <= 1);
    visibility.type_index_current.store(false, Relaxed);
    visibility.type_index_reusable.store(single_page, Relaxed);
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
    let (collector, bound, projection, scatter) = match stage {
        MethodSelectionStage::Direct => (
            DEPENDENCY_METHODS_COLLECT, DEPENDENCY_BOUND_MEMBERS_OFFER,
            DEPENDENCY_METHODS_PROJECT, DEPENDENCY_METHOD_PARAMS_SCATTER,
        ),
        // The lookup sweeps dispatch from their gated grids.
        MethodSelectionStage::Lookup => {
            return if collect {
                visibility.collect_methods_lookup.record(encoder)?;
                // Imported traits' required members, through bounds on parameters.
                visibility.offer_bound_members_lookup.record(encoder)
            } else {
                visibility.project_methods_lookup.record(encoder)?;
                visibility.scatter_method_params_lookup.record(encoder)
            };
        }
        MethodSelectionStage::Inference => (
            DEPENDENCY_METHODS_COLLECT_INFERENCE, DEPENDENCY_BOUND_MEMBERS_OFFER_INFERENCE,
            DEPENDENCY_METHODS_PROJECT_INFERENCE, DEPENDENCY_METHOD_PARAMS_SCATTER_INFERENCE,
        ),
    };
    if collect {
        visibility.collect_methods_group.record_as(encoder, collector.name)?;
        // Imported traits' required members, through bounds on parameters.
        visibility.offer_bound_members_group.record_as(encoder, bound.name)
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
