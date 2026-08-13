use super::*;

// Collapse all declaration-only alias chains with O(log n) race-free pointer
// jumping before projection. Dispatch is declaration-count bounded; the round
// count comes from resident capacity, so no chain-depth limit is encoded.
fn record_type_alias_root_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    module_path: &ModulePathState,
) -> Result<()> {
    let aliases = &module_path.bind_groups.type_aliases;
    record_compute(
        encoder,
        &passes.kernel("type_checker/modules/10e0_clear_type_alias_forwarding"),
        &aliases.clear_forwarding,
        "type_check.modules.clear_type_alias_forwarding",
        module_path.n_blocks.saturating_mul(256),
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/modules/10e0a_init_type_alias_forwarding"),
        &aliases.init_forwarding,
        "type_check.modules.init_type_alias_forwarding",
        &module_path.decl_key_radix_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/modules/10e0b_validate_type_alias_forwarding_args"),
        &aliases.validate_forwarding_args,
        "type_check.modules.validate_type_alias_forwarding_args",
        module_path.n_blocks.saturating_mul(256),
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/modules/10e1_init_type_alias_roots"),
        &aliases.init_roots,
        "type_check.modules.init_type_alias_roots",
        &module_path.decl_key_radix_dispatch_args,
    )?;
    for round in 0..aliases.jump_rounds {
        let bind_group = if round % 2 == 0 {
            &aliases.jump_a_to_b
        } else {
            &aliases.jump_b_to_a
        };
        record_compute_indirect(
            encoder,
            &passes.kernel("type_checker/modules/10e1a_jump_type_alias_roots"),
            bind_group,
            "type_check.modules.jump_type_alias_roots",
            &module_path.decl_key_radix_dispatch_args,
        )?;
    }
    Ok(())
}

// Build the producer-owned generic-alias substitution graph only after named
// type instances have been attached to their resolved declarations.
fn record_type_alias_equivalence_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    module_path: &ModulePathState,
) -> Result<()> {
    let aliases = &module_path.bind_groups.type_aliases;
    let hir_work = module_path.n_blocks.saturating_mul(256).max(1);
    let graph_work = module_path.token_capacity.saturating_add(hir_work).max(1);
    record_compute(
        encoder,
        &passes.kernel("type_checker/modules/10e0c_clear_type_alias_equivalence"),
        &aliases.clear_equivalence,
        "type_check.modules.clear_type_alias_equivalence",
        graph_work,
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/modules/10e0d_init_type_alias_decl_edges"),
        &aliases.init_decl_edges,
        "type_check.modules.init_type_alias_decl_edges",
        &module_path.decl_key_radix_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/modules/10e0e_init_type_alias_arg_edges"),
        &aliases.init_arg_edges,
        "type_check.modules.init_type_alias_arg_edges",
        hir_work,
    )?;
    for round in 0..aliases.equivalence_rounds {
        let (hook, jump) = if round % 2 == 0 {
            (
                &aliases.hook_equivalence_a,
                &aliases.jump_equivalence_a_to_b,
            )
        } else {
            (
                &aliases.hook_equivalence_b,
                &aliases.jump_equivalence_b_to_a,
            )
        };
        record_compute(
            encoder,
            &passes.kernel("type_checker/modules/10e0f_hook_type_alias_equivalence"),
            hook,
            "type_check.modules.hook_type_alias_equivalence",
            hir_work,
        )?;
        record_compute(
            encoder,
            &passes.kernel("type_checker/modules/10e0g_jump_type_alias_equivalence"),
            jump,
            "type_check.modules.jump_type_alias_equivalence",
            graph_work,
        )?;
    }
    record_compute(
        encoder,
        &passes.kernel("type_checker/modules/10e0h_select_type_alias_generic_sources"),
        &aliases.select_generic_sources,
        "type_check.modules.select_type_alias_generic_sources",
        hir_work,
    )?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/modules/10e0i_select_type_alias_concrete_sources"),
        &aliases.select_concrete_sources,
        "type_check.modules.select_type_alias_concrete_sources",
        hir_work,
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/modules/10e0j_finalize_type_alias_equivalence"),
        &aliases.finalize_equivalence,
        "type_check.modules.finalize_type_alias_equivalence",
        &module_path.decl_key_radix_dispatch_args,
    )
}

// Publish direct and identity-root-collapsed refs. Generic transformations are
// finalized after semantic type-instance declaration binding.
fn record_type_alias_projection_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    module_path: &ModulePathState,
    label: &'static str,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/modules/10e2_project_type_aliases"),
        &module_path.bind_groups.type_aliases.project,
        label,
        &module_path.decl_key_radix_dispatch_args,
    )
}

fn record_type_subtree_comparison_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    bind_groups: &ResidentTypeCheckWorkspace,
) -> Result<()> {
    bind_groups.type_subtree_compare_scan.record(encoder)?;
    record_compute(
        encoder,
        &passes.kernel("type_checker/count/dispatch_args"),
        &bind_groups.type_subtree_compare_dispatch,
        "type_check.conditions.type_subtree_compare_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/conditions/type_subtree"),
        &bind_groups.conditions_type_subtree,
        "type_check.conditions.type_subtree_compare",
        &bind_groups.type_subtree_compare_buffers.dispatch_args,
    )
}

struct TypeCheckRecordHostTimer {
    enabled: bool,
    start: std::time::Instant,
    last: std::time::Instant,
    baseline_compute_passes: u64,
    last_compute_passes: u64,
}

impl TypeCheckRecordHostTimer {
    fn new() -> Self {
        let now = std::time::Instant::now();
        let compute_passes = recorded_compute_pass_count();
        Self {
            enabled: crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false),
            start: now,
            last: now,
            baseline_compute_passes: compute_passes,
            last_compute_passes: compute_passes,
        }
    }

    fn stamp(&mut self, stage: &str) {
        if !self.enabled {
            return;
        }
        let now = std::time::Instant::now();
        let dt_ms = now.duration_since(self.last).as_secs_f64() * 1000.0;
        let total_ms = now.duration_since(self.start).as_secs_f64() * 1000.0;
        let compute_passes = recorded_compute_pass_count();
        let stage_compute_passes = compute_passes.saturating_sub(self.last_compute_passes);
        let total_compute_passes = compute_passes.saturating_sub(self.baseline_compute_passes);
        eprintln!(
            "[gpu_compile_host_timer] typecheck.record.{stage}: {dt_ms:.3}ms (total {total_ms:.3}ms compute_passes={stage_compute_passes} total_compute_passes={total_compute_passes})"
        );
        self.last = now;
        self.last_compute_passes = compute_passes;
    }
}

impl GpuTypeChecker {
    /// Creates a type checker from the shared compiler GPU device wrapper.
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        Self::new(&gpu.device)
    }

    /// Creates a type checker and loads all resident type-check pass pipelines.
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let supports_large_workgroup_storage =
            device.limits().max_compute_workgroup_storage_size >= 32 * 1024;
        let passes = TypeCheckPasses::prepare_prefixes(
            device,
            &["type_checker", "scan/counted", "radix"],
            |key| {
                key != "type_checker/predicates/01b2_sort_keys_small"
                    || supports_large_workgroup_storage
            },
        )?;
        let params_buf = zeroed_type_check_params_buffer(device, "type_check.resident.params");
        let status_buf = typed_storage_u32_rw(
            device,
            "type_check.resident.status",
            4,
            wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
        );
        let status_readback = LaniusBuffer::new_labeled(
            (
                readback_u32s(device, "rb.type_check.resident.status", 4),
                4 * std::mem::size_of::<u32>() as u64,
            ),
            4,
            "rb.type_check.resident.status",
        );

        Ok(Self {
            passes,
            params_buf,
            status_buf,
            status_readback,
            resident_workspace: Mutex::new(None),
            current_semantic_artifact: Mutex::new(None),
            dependency_interface_state: Mutex::new(None),
            semantic_interface_buffers: CapacityBufferCache::default(),
        })
    }

    /// Releases reusable semantic buffers and their bind groups while
    /// retaining the type-check pipelines and fixed status resources.
    pub fn release_current_resident_workspace(&self) {
        *self
            .current_semantic_artifact
            .lock()
            .expect("GpuTypeChecker.current_semantic_artifact poisoned") = None;
        *self
            .resident_workspace
            .lock()
            .expect("GpuTypeChecker.resident_workspace poisoned") = None;
        *self
            .dependency_interface_state
            .lock()
            .expect("GpuTypeChecker.dependency_interface_state poisoned") = None;
        self.semantic_interface_buffers.clear();
    }

    pub(crate) fn dependency_interface_pages(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        current_library_id: u32,
        current_unit_id: u32,
        interface_pages: &[&[crate::compiler::GpuSemanticInterfaceArtifact]],
    ) -> Result<GpuDependencyInterfacePages> {
        GpuDependencyInterfacePages::new_reusing(
            device,
            queue,
            current_library_id,
            current_unit_id,
            interface_pages,
            &mut self
                .dependency_interface_state
                .lock()
                .expect("GpuTypeChecker.dependency_interface_state poisoned"),
        )
    }

    /// Records resident type checking with parser-owned HIR item metadata.
    /// This is the path used by the compiler's LL(1) frontend.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn record_resident_token_buffer_with_hir_items_on_gpu(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        source_file_capacity: u32,
        token_capacity: u32,
        token_buf: TrackedBufferView<'_>,
        token_count_buf: TrackedBufferView<'_>,
        token_file_id_buf: TrackedBufferView<'_>,
        source_buf: TrackedBufferView<'_>,
        hir_node_capacity: u32,
        parser_hir_node_capacity: u32,
        hir_items: GpuTypeCheckHirItemBuffers<'_>,
        dependency_pages: Option<&GpuDependencyInterfacePages>,
        timer: Option<&mut crate::gpu::timer::GpuTimer>,
    ) -> Result<RecordedTypeCheck, GpuTypeCheckError> {
        self.record_resident_token_buffer_with_hir_impl_on_gpu(
            device,
            queue,
            encoder,
            source_len,
            source_file_capacity,
            token_capacity,
            token_buf,
            token_count_buf,
            token_file_id_buf,
            source_buf,
            hir_node_capacity,
            parser_hir_node_capacity,
            hir_items,
            dependency_pages,
            timer,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn record_resident_token_buffer_with_hir_impl_on_gpu(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        source_file_capacity: u32,
        token_capacity: u32,
        token_buf: TrackedBufferView<'_>,
        token_count_buf: TrackedBufferView<'_>,
        token_file_id_buf: TrackedBufferView<'_>,
        source_buf: TrackedBufferView<'_>,
        hir_node_capacity: u32,
        parser_hir_node_capacity: u32,
        hir_items: GpuTypeCheckHirItemBuffers<'_>,
        dependency_pages: Option<&GpuDependencyInterfacePages>,
        mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
    ) -> Result<RecordedTypeCheck, GpuTypeCheckError> {
        // Type-check phases contain dependent scans, sorts, and resolution
        // passes. Coalescing them into one compute pass provides no storage
        // barriers between dispatches and makes results timing-dependent.
        let _compute_batch = crate::gpu::passes_core::DeferredComputeBatchGuard::begin(
            false,
            "type_check.resident.batch",
        );
        let params = TypeCheckParams {
            n_tokens: token_capacity,
            source_len,
            n_hir_nodes: hir_node_capacity,
            n_source_files: source_file_capacity,
            parser_feature_flags: hir_items.parser_feature_flags,
        };
        self.params_buf
            .write(queue, 0, &type_check_params_bytes(&params));
        self.status_buf.write(queue, 0, &status_init_bytes());
        let dependency_interfaces = dependency_pages.map(GpuDependencyInterfacePages::state);
        let mut host_timer = TypeCheckRecordHostTimer::new();
        host_timer.stamp("params");

        let mut fingerprint_buffers = vec![
            token_buf.buffer,
            token_count_buf.buffer,
            token_file_id_buf.buffer,
            source_buf.buffer,
        ];
        fingerprint_buffers.extend(hir_items.hir.typecheck_buffers());
        fingerprint_buffers.extend(
            hir_items
                .upstream_workspace
                .iter()
                .map(|workspace| workspace.buffer),
        );
        if let Some(dependencies) = dependency_interfaces {
            fingerprint_buffers.push(&dependencies.words);
            fingerprint_buffers.push(&dependencies.module_lookup);
        }
        let input_fingerprint = buffer_fingerprint(&fingerprint_buffers);
        let module_record_capacity = hir_items.module_record_capacity.max(1);
        let call_param_row_capacity = hir_items.call_param_row_capacity.max(1);
        let call_arg_row_capacity = hir_items.call_arg_row_capacity.max(1);
        let parser_feature_flags = hir_items.parser_feature_flags;
        let cache_key = ResidentTypeCheckCacheKey {
            source_byte_capacity: source_len.max(1),
            source_file_capacity,
            token_capacity,
            hir_node_capacity,
            parser_hir_node_capacity,
            module_record_capacity,
            call_param_row_capacity,
            call_arg_row_capacity,
            parser_feature_flags,
            input_fingerprint,
        }
        .bucketed();

        {
            let mut resident_workspace_guard = self
                .resident_workspace
                .lock()
                .expect("GpuTypeChecker.resident_workspace poisoned");
            let needs_rebuild = resident_workspace_guard
                .as_ref()
                .map(|state| !state.can_reuse_for(cache_key))
                .unwrap_or(true);
            let allocation = resident_workspace_guard
                .as_ref()
                .map(|state| state.cache_key.grow_to_cover(cache_key))
                .unwrap_or(cache_key);
            let resident_cache_trace =
                crate::gpu::env::env_bool_truthy("LANIUS_TYPECHECK_RESIDENT_CACHE_TRACE", false);
            if (crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false)
                || resident_cache_trace)
                && needs_rebuild
            {
                if let Some(previous) = resident_workspace_guard.as_ref() {
                    eprintln!(
                        "[gpu_compile_host_timer] typecheck.resident_cache_miss: input_fingerprint={:#018x}->{:#018x} token_capacity={}->{} hir_capacity={}->{} parser_hir_capacity={}->{} module_capacity={}->{} call_param_capacity={}->{} call_arg_capacity={}->{} features={:#010x}->{:#010x}",
                        previous.cache_key.input_fingerprint,
                        cache_key.input_fingerprint,
                        previous.cache_key.token_capacity,
                        cache_key.token_capacity,
                        previous.cache_key.hir_node_capacity,
                        cache_key.hir_node_capacity,
                        previous.cache_key.parser_hir_node_capacity,
                        cache_key.parser_hir_node_capacity,
                        previous.cache_key.module_record_capacity,
                        cache_key.module_record_capacity,
                        previous.cache_key.call_param_row_capacity,
                        cache_key.call_param_row_capacity,
                        previous.cache_key.call_arg_row_capacity,
                        cache_key.call_arg_row_capacity,
                        previous.cache_key.parser_feature_flags,
                        cache_key.parser_feature_flags,
                    );
                }
            }
            if resident_cache_trace {
                eprintln!(
                    "[typecheck.resident_cache] rebuild={needs_rebuild} source={} files={} tokens={} hir={} parser_hir={} modules={} call_params={} call_args={} features={:#010x} fingerprint={:#018x} allocation_source={} allocation_files={} allocation_tokens={} allocation_hir={} allocation_parser_hir={} allocation_modules={} allocation_call_params={} allocation_call_args={} allocation_features={:#010x}",
                    cache_key.source_byte_capacity,
                    cache_key.source_file_capacity,
                    cache_key.token_capacity,
                    cache_key.hir_node_capacity,
                    cache_key.parser_hir_node_capacity,
                    cache_key.module_record_capacity,
                    cache_key.call_param_row_capacity,
                    cache_key.call_arg_row_capacity,
                    cache_key.parser_feature_flags,
                    cache_key.input_fingerprint,
                    allocation.source_byte_capacity,
                    allocation.source_file_capacity,
                    allocation.token_capacity,
                    allocation.hir_node_capacity,
                    allocation.parser_hir_node_capacity,
                    allocation.module_record_capacity,
                    allocation.call_param_row_capacity,
                    allocation.call_arg_row_capacity,
                    allocation.parser_feature_flags,
                );
            }
            let rebuilt = needs_rebuild;
            if needs_rebuild {
                // A cache miss changes bound allocation identities, so none of
                // the old bind groups or scratch buffers can be reused. Drop
                // that state before allocating its replacement; assigning the
                // replacement directly would transiently retain both complete
                // type-check workspaces at a compilation-unit boundary.
                self.current_semantic_artifact
                    .lock()
                    .expect("GpuTypeChecker.current_semantic_artifact poisoned")
                    .take();
                resident_workspace_guard.take();
                let (state, resettable_buffers) = crate::gpu::buffers::with_uniform_buffer_arena(
                    device,
                    "type_check.uniform_arena",
                    || {
                        crate::gpu::buffers::collect_resettable_buffers(|| {
                            self.create_resident_workspace(
                                device,
                                allocation,
                                token_buf,
                                token_count_buf,
                                token_file_id_buf,
                                source_buf,
                                hir_items,
                                &self.passes,
                                dependency_interfaces,
                            )
                        })
                    },
                );
                let mut state = state?;
                state.resettable_buffers = resettable_buffers;
                *resident_workspace_guard = Some(state);
            }
            host_timer.stamp(if rebuilt {
                "resident_workspace_rebuilt"
            } else {
                "resident_workspace_reused"
            });
            let bind_groups = resident_workspace_guard
                .as_ref()
                .expect("resident type-check state must exist");
            *self
                .current_semantic_artifact
                .lock()
                .expect("GpuTypeChecker.current_semantic_artifact poisoned") =
                Some(bind_groups.semantic_artifact()?);
            let module_path = &bind_groups.module_path;
            let predicates = &bind_groups.predicates;
            debug_assert!(
                bind_groups.resettable_buffers.iter().all(|buffer| {
                    Some(buffer.allocation_id) != self.status_buf.allocation_id()
                })
            );
            bind_groups.clear_job_storage(encoder);
            queue.write_buffer(
                &bind_groups.if_depth_params,
                0,
                &uniform_bytes(&IfDepthParams {
                    n_tokens: token_capacity,
                    n_hir_nodes: hir_node_capacity,
                    n_blocks: bind_groups.if_depth_n_blocks,
                    scan_step: 0,
                }),
            );
            queue.write_buffer(
                &bind_groups.fn_params,
                0,
                &uniform_bytes(&FnContextParams {
                    n_tokens: token_capacity,
                    n_hir_nodes: hir_node_capacity,
                    n_blocks: bind_groups.fn_n_blocks,
                    scan_step: 0,
                }),
            );
            let predicate_hir_dispatch_args = bind_groups
                .typecheck_graph
                .u32_buffer("predicate_hir_dispatch_args")?;
            let predicate_single_dispatch_args = bind_groups
                .typecheck_graph
                .u32_buffer("predicate_single_dispatch_args")?;
            let match_hir_dispatch_args = bind_groups
                .typecheck_graph
                .u32_buffer("match_hir_dispatch_args")?;
            let parser_feature_flags = bind_groups.cache_key.parser_feature_flags;
            let methods_required = method_passes_required(parser_feature_flags);
            let arrays_required = array_passes_required(parser_feature_flags);
            let structs_required = struct_init_passes_required(parser_feature_flags);
            let members_required = member_passes_required(parser_feature_flags);
            let enums_required = enum_passes_required(parser_feature_flags);
            let matches_required = match_passes_required(parser_feature_flags);
            let aggregates_required = aggregate_passes_required(parser_feature_flags);
            let aliases_required = type_alias_passes_required(parser_feature_flags);

            record_compute(
                encoder,
                &self.passes.kernel("type_checker/hir_active_dispatch_args"),
                &bind_groups.hir_active_dispatch,
                "type_check.hir_active_dispatch_args",
                1,
            )?;
            bind_groups.semantic_features.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.frontend_boundary.done");
            }
            record_if_depth_passes_with_passes(&self.passes, encoder, bind_groups)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.if_depth.done");
            }
            record_language_name_bind_groups_with_passes(
                &self.passes,
                encoder,
                bind_groups.cache_key.token_capacity,
                &bind_groups.language_name_bind_groups,
            )?;
            record_name_bind_groups_with_passes(
                &self.passes,
                encoder,
                bind_groups.cache_key.token_capacity,
                bind_groups.name_capacity,
                &bind_groups.token_active_dispatch_args,
                &bind_groups.name_bind_groups,
            )?;
            record_language_decl_bind_groups_with_passes(
                &self.passes,
                encoder,
                bind_groups.name_capacity,
                &bind_groups.language_name_bind_groups,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.names.done");
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.language_decls.done");
            }
            host_timer.stamp("loop_names_language_decls");
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/predicates/00a_clear_syntax_tokens"),
                &predicates.clear_syntax_tokens,
                "type_check.resident.predicates_clear_syntax_tokens.pass",
                &bind_groups.token_active_dispatch_args,
            )?;
            record_module_path_state_with_passes(
                device,
                queue,
                &self.passes,
                encoder,
                module_path,
                dependency_pages,
                &bind_groups.hir_active_dispatch_args,
                &bind_groups.token_hir_active_dispatch_args,
                timer.as_deref_mut(),
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.module_paths.done");
            }
            host_timer.stamp("module_paths");
            record_compute(
                encoder,
                &self.passes.kernel("type_checker/type/instances/00_clear"),
                &bind_groups.type_instances.clear,
                "type_check.resident.type_instances_clear.pass",
                token_capacity.max(hir_node_capacity),
            )?;
            if let Some(dependency_visibility) = module_path.dependency_visibility.as_ref() {
                // The shared type-instance clear resets token-indexed refs.
                // Re-publish canonical dependency refs before collection so
                // imported nominal types cannot be reclassified as unresolved
                // local generic parameters.  The dependency interface slot is
                // paged, so replay the projection for every page rather than
                // leaving only the final page's declarations visible.
                let project_types = |encoder: &mut wgpu::CommandEncoder| {
                    record_dependency_type_index(&self.passes, encoder, module_path)?;
                    record_compute_indirect(
                        encoder,
                        &self
                            .passes
                            .kernel("type_checker/dependencies/11_project_types"),
                        &dependency_visibility.project_types_group,
                        "type_check.dependencies.project_types.after_type_clear",
                        &module_path.path_dispatch_args,
                    )
                };
                if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                    record_each_dependency_page(device, queue, encoder, pages, project_types)?;
                } else {
                    project_types(encoder)?;
                }
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances.clear.done");
            }
            if generic_param_record_passes_required(bind_groups.cache_key.parser_feature_flags) {
                record_generic_param_record_passes_with_passes(
                    &self.passes,
                    encoder,
                    &bind_groups.type_instances,
                    &bind_groups.hir_active_dispatch_args,
                    timer.as_deref_mut(),
                )?;
            } else {
                let generic_param_count_out = bind_groups
                    .typecheck_graph
                    .u32_buffer("generic_param_count_out")?;
                record_typecheck_clear_buffer(encoder, &generic_param_count_out, 0, Some(4));
            }
            record_type_instance_collection_passes_with_passes(
                &self.passes,
                encoder,
                bind_groups,
                &bind_groups.hir_active_dispatch_args,
                &super::record::TYPE_INSTANCE_COLLECTION_INITIAL_LABELS,
                timer.as_deref_mut(),
            )?;
            if aliases_required {
                record_type_alias_root_passes(&self.passes, encoder, module_path)?;
                record_type_alias_projection_passes(
                    &self.passes,
                    encoder,
                    module_path,
                    "type_check.modules.project_type_aliases",
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.modules.project_type_aliases.done");
                }
            }
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/modules/10e_project_type_paths"),
                &module_path.bind_groups.project_type_paths,
                "type_check.modules.project_type_paths.after_aliases",
                &module_path.path_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(
                    encoder,
                    "typecheck.modules.project_type_paths.after_aliases.done",
                );
            }
            record_type_instance_collection_passes_with_passes(
                &self.passes,
                encoder,
                bind_groups,
                &bind_groups.hir_active_dispatch_args,
                &super::record::TYPE_INSTANCE_COLLECTION_PROJECTED_LABELS,
                timer.as_deref_mut(),
            )?;
            if aliases_required {
                record_type_alias_projection_passes(
                    &self.passes,
                    encoder,
                    module_path,
                    "type_check.modules.project_type_aliases.after_projected_refs",
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(
                        encoder,
                        "typecheck.modules.project_type_aliases.after_projected_refs.done",
                    );
                }
            }
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/modules/10e_project_type_paths"),
                &module_path.bind_groups.project_type_paths,
                "type_check.modules.project_type_paths.after_projected_aliases",
                &module_path.path_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(
                    encoder,
                    "typecheck.modules.project_type_paths.after_projected_aliases.done",
                );
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances.done");
            }
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/modules/10k_project_type_instances"),
                &module_path.bind_groups.project_type_instances,
                "type_check.modules.project_type_instances",
                &module_path.path_dispatch_args,
            )?;
            if let Some(dependency_visibility) = &module_path.dependency_visibility {
                let record_projection = |encoder: &mut wgpu::CommandEncoder| {
                    record_dependency_type_index(&self.passes, encoder, module_path)?;
                    record_compute_indirect(
                        encoder,
                        &self
                            .passes
                            .kernel("type_checker/dependencies/14_project_type_instances"),
                        &dependency_visibility.project_type_instances_group,
                        "type_check.dependencies.project_type_instances",
                        &module_path.path_dispatch_args,
                    )
                };
                if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                    record_each_dependency_page(device, queue, encoder, pages, record_projection)?;
                } else {
                    record_compute_indirect(
                        encoder,
                        &self
                            .passes
                            .kernel("type_checker/dependencies/14_project_type_instances"),
                        &dependency_visibility.project_type_instances_group,
                        "type_check.dependencies.project_type_instances",
                        &module_path.path_dispatch_args,
                    )?;
                }
            }
            if aliases_required {
                record_type_alias_equivalence_passes(&self.passes, encoder, module_path)?;
            }
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/modules/10e_project_type_paths"),
                &module_path.bind_groups.project_type_paths,
                "type_check.modules.project_type_paths.after_alias_equivalence",
                &module_path.path_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_project.done");
            }
            bind_groups
                .type_instances
                .type_instance_arg_row_scan
                .record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_arg_row_scan.done");
            }
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/type/instances/01e_collect_named_arg_refs"),
                &bind_groups.type_instances.collect_named_arg_refs,
                "type_check.resident.type_instances_collect_named_arg_refs.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            if aliases_required {
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/modules/10e0k_project_type_alias_instances"),
                    &module_path.bind_groups.type_aliases.project_instances,
                    "type_check.modules.project_type_alias_instances",
                    &bind_groups.hir_active_dispatch_args,
                )?;
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_named_arg_refs.done");
            }
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/type/instances/01g_hash_arg_rows"),
                &bind_groups.type_instances.hash_arg_rows,
                "type_check.resident.type_instances_hash_arg_rows.pass",
                &bind_groups.token_active_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_arg_hash.done");
            }
            if aggregates_required {
                record_compute(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/01h_clear_semantic_type_rows"),
                    &bind_groups.type_instances.clear_semantic_type_rows,
                    "type_check.type_instances.clear_semantic_type_rows",
                    token_capacity
                        .saturating_add(LANGUAGE_SYMBOL_COUNT)
                        .max(hir_node_capacity),
                )?;
                bind_groups
                    .type_instances
                    .semantic_type_rows
                    .record(encoder)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.type_instances_semantic_rows.done");
                }
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_collect.done");
            }
            host_timer.stamp("type_instances_collect");
            let n_work = token_capacity.max(hir_node_capacity).max(512);
            record_fn_context_bind_groups_with_passes(
                &self.passes,
                encoder,
                token_capacity,
                &bind_groups.hir_active_dispatch_args,
                bind_groups.fn_n_blocks,
                &bind_groups.fn_context_bind_groups,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.fn_context.done");
            }
            bind_groups.calls.record_primary_prefix(encoder)?;
            if let Some(visibility) = &module_path.dependency_visibility {
                if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                    record_each_dependency_page(device, queue, encoder, pages, |encoder| {
                        record_dependency_page(&self.passes, encoder, module_path)?;
                        record_dependency_call_counts(
                            &self.passes,
                            encoder,
                            visibility,
                            &bind_groups.hir_active_dispatch_args,
                        )
                    })?;
                } else {
                    record_dependency_call_counts(
                        &self.passes,
                        encoder,
                        visibility,
                        &bind_groups.hir_active_dispatch_args,
                    )?;
                }
            }
            bind_groups.calls.record_primary_scan(encoder)?;
            if let Some(visibility) = &module_path.dependency_visibility {
                if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                    record_each_dependency_page(device, queue, encoder, pages, |encoder| {
                        record_dependency_type_index(&self.passes, encoder, module_path)?;
                        record_dependency_call_params(
                            &self.passes,
                            encoder,
                            visibility,
                            &bind_groups.hir_active_dispatch_args,
                        )
                    })?;
                } else {
                    record_dependency_call_params(
                        &self.passes,
                        encoder,
                        visibility,
                        &bind_groups.hir_active_dispatch_args,
                    )?;
                }
            }
            bind_groups.calls.record_primary_suffix(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls.done");
            }
            record_visible_bind_groups_with_passes(
                &self.passes,
                encoder,
                token_capacity,
                &bind_groups.visible_bind_groups,
                timer.as_deref_mut(),
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.visible.done");
            }
            host_timer.stamp("fn_context_calls_visible");

            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/type/instances/01f_decl_refs"),
                &bind_groups.type_instances.decl_refs,
                "type_check.resident.type_instances_decl_refs.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            // For-binding element refs consume iterable decl refs published by
            // the same HIR-indexed shader, so run a second fixed pass after the
            // direct decl facts are stable.
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/type/instances/01f_decl_refs"),
                &bind_groups.type_instances.decl_refs,
                "type_check.resident.type_instances_decl_refs.for_bindings.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_decl_refs.done");
            }
            bind_groups.methods.clear.record(encoder)?;
            if methods_required {
                bind_groups.methods.record_declarations(encoder)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.methods.done");
                }
            }
            if members_required {
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/03a_member_receivers"),
                    &bind_groups.type_instances.member_receivers,
                    "type_check.resident.type_instances_member_receivers.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.member_receivers.done");
                }
            }
            if struct_field_index_passes_required(bind_groups.cache_key.parser_feature_flags) {
                record_struct_field_key_passes_with_passes(
                    encoder,
                    &bind_groups.type_instances,
                    timer.as_deref_mut(),
                )?;
            }
            if members_required {
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/03_member_results"),
                    &bind_groups.type_instances.member_results,
                    "type_check.resident.type_instances_member_results.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.member_results.done");
                }
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/03b_member_substitute"),
                    &bind_groups.type_instances.member_substitute,
                    "type_check.resident.type_instances_member_substitute.pass",
                    &bind_groups.token_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.member_substitute.done");
                }
            }
            if structs_required {
                record_compute(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/04a_struct_init_clear"),
                    &bind_groups.type_instances.struct_init_clear,
                    "type_check.resident.type_instances_struct_init_clear.pass",
                    token_capacity.max(hir_node_capacity),
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.struct_init_clear.done");
                }
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/04a2_struct_init_contexts"),
                    &bind_groups.type_instances.struct_init_contexts,
                    "type_check.resident.type_instances_struct_init_contexts.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.struct_init_contexts.done");
                }
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/04_struct_init_fields"),
                    &bind_groups.type_instances.struct_init_fields,
                    "type_check.resident.type_instances_struct_init_fields.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.struct_init_fields.done");
                }
                let semantic_ref_bytes = u64::from(hir_node_capacity.max(1)) * 4;
                let semantic_expr_ref_tag_by_hir = bind_groups
                    .typecheck_graph
                    .u32_buffer("semantic_expr_ref_tag_by_hir")?;
                let semantic_expr_ref_payload_by_hir = bind_groups
                    .typecheck_graph
                    .u32_buffer("semantic_expr_ref_payload_by_hir")?;
                let semantic_aggregate_decl_token_by_hir = bind_groups
                    .typecheck_graph
                    .u32_buffer("semantic_aggregate_decl_token_by_hir")?;
                record_typecheck_clear_buffer(
                    encoder,
                    &semantic_expr_ref_tag_by_hir,
                    0,
                    Some(semantic_ref_bytes),
                );
                record_typecheck_clear_buffer(
                    encoder,
                    &semantic_expr_ref_payload_by_hir,
                    0,
                    Some(semantic_ref_bytes),
                );
                record_typecheck_clear_buffer(
                    encoder,
                    &semantic_aggregate_decl_token_by_hir,
                    0,
                    Some(semantic_ref_bytes),
                );
                record_compute(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/semantic/artifact/01a_struct_literal_refs"),
                    &bind_groups.semantic_struct_literal_refs_project,
                    "type_check.semantic_artifact.struct_literal_refs_early",
                    hir_node_capacity,
                )?;
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instance_fields.done");
            }
            host_timer.stamp("methods_member_struct_fields");
            if matches_required {
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/modules/10m_bind_match_patterns"),
                    &module_path.bind_groups.bind_match_patterns,
                    "type_check.modules.bind_match_patterns",
                    &match_hir_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/modules/10m2_type_match_payloads"),
                    &module_path.bind_groups.type_match_payloads,
                    "type_check.modules.type_match_payloads",
                    &match_hir_dispatch_args,
                )?;
            }
            record_compute_indirect(
                encoder,
                &self.passes.kernel("type_checker/scope/hir"),
                &bind_groups.scope_hir,
                "type_check.resident.scope.pass",
                &bind_groups.token_active_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.scope.done");
            }
            bind_groups.calls.resolve.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls_resolve.done");
            }
            bind_groups.calls.argument_matching.record(encoder)?;
            bind_groups.calls.apply_row_args.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls_row_args.done");
            }
            if methods_required {
                bind_groups.methods.mark_call_keys.record(encoder)?;
                if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                    record_each_dependency_page(device, queue, encoder, pages, |encoder| {
                        record_dependency_type_index(&self.passes, encoder, module_path)?;
                        record_dependency_methods(
                            &self.passes,
                            encoder,
                            module_path,
                            &bind_groups.hir_active_dispatch_args,
                        )
                    })?;
                } else {
                    record_dependency_methods(
                        &self.passes,
                        encoder,
                        module_path,
                        &bind_groups.hir_active_dispatch_args,
                    )?;
                }
            }
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/modules/10h_consume_value_calls"),
                &module_path.bind_groups.consume_value_calls,
                "type_check.modules.consume_value_calls",
                &module_path.path_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/modules/10h2_mirror_value_call_leaf"),
                &module_path.bind_groups.mirror_value_call_leaf,
                "type_check.modules.mirror_value_call_leaf",
                &module_path.path_dispatch_args,
            )?;
            bind_groups.calls.argument_matching.record(encoder)?;
            bind_groups.calls.apply_row_args.record(encoder)?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/modules/10h2_mirror_value_call_leaf"),
                &module_path.bind_groups.mirror_value_call_leaf,
                "type_check.modules.mirror_value_call_leaf_after_module_row_args",
                &module_path.path_dispatch_args,
            )?;
            if methods_required {
                bind_groups.methods.keys.record(encoder)?;
                bind_groups.methods.record_call_resolution(encoder)?;
            }
            bind_groups.calls.project_result_instances.record(encoder)?;
            bind_groups.calls.argument_matching.record(encoder)?;
            bind_groups.calls.apply_row_args.record(encoder)?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/modules/10h_consume_value_calls"),
                &module_path.bind_groups.consume_value_calls,
                "type_check.modules.consume_value_calls_after_methods",
                &module_path.path_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/modules/10h2_mirror_value_call_leaf"),
                &module_path.bind_groups.mirror_value_call_leaf,
                "type_check.modules.mirror_value_call_leaf_after_methods",
                &module_path.path_dispatch_args,
            )?;
            bind_groups.calls.argument_matching.record(encoder)?;
            bind_groups.calls.apply_row_args.record(encoder)?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/modules/10h2_mirror_value_call_leaf"),
                &module_path.bind_groups.mirror_value_call_leaf,
                "type_check.modules.mirror_value_call_leaf_after_methods_module_row_args",
                &module_path.path_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(
                    encoder,
                    if methods_required {
                        "typecheck.methods_call_returns.done"
                    } else {
                        "typecheck.calls_reconcile.done"
                    },
                );
            }
            if arrays_required {
                record_compute(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/calls/03b_infer_array_generics"),
                    &bind_groups.calls.infer_array_generics,
                    "type_check.resident.calls_infer_array_generics.pass",
                    n_work,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.calls_infer_array_generics.done");
                }
                bind_groups.calls.mark_array_args.record(encoder)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.calls_mark_array_args.done");
                }
                bind_groups.calls.validate_array_results.record(encoder)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.calls_validate_array_results.done");
                }
            }
            if generic_call_claim_passes_required(parser_feature_flags)
                || dependency_interfaces.is_some()
            {
                record_call_erase_generic_params_with_passes(
                    &self.passes,
                    encoder,
                    token_capacity,
                    &bind_groups.calls,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.calls_erased.done");
                }
            }
            if enums_required {
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/modules/10l_consume_value_enum_calls"),
                    &module_path.bind_groups.consume_value_enum_calls,
                    "type_check.modules.consume_value_enum_calls",
                    &module_path.path_dispatch_args,
                )?;
                record_compute(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/modules/10l2_validate_value_enum_call_payloads"),
                    &module_path.bind_groups.validate_value_enum_call_payloads,
                    "type_check.modules.validate_value_enum_call_payloads",
                    hir_node_capacity.saturating_mul(4).max(1),
                )?;
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/modules/10l3_finalize_value_enum_calls"),
                    &module_path.bind_groups.finalize_value_enum_calls,
                    "type_check.modules.finalize_value_enum_calls",
                    &module_path.path_dispatch_args,
                )?;
            }
            if matches_required {
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/modules/10n_type_match_exprs"),
                    &module_path.bind_groups.type_match_exprs,
                    "type_check.modules.type_match_exprs",
                    &bind_groups.hir_active_dispatch_args,
                )?;
            }
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/modules/10i_consume_value_consts"),
                &module_path.bind_groups.consume_value_consts,
                "type_check.modules.consume_value_consts",
                &module_path.path_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/modules/10j_consume_value_enum_units"),
                &module_path.bind_groups.consume_value_enum_units,
                "type_check.modules.consume_value_enum_units",
                &module_path.path_dispatch_args,
            )?;
            if methods_required {
                bind_groups.methods.resolve.record(encoder)?;
            }
            bind_groups.calls.argument_matching.record(encoder)?;
            if generic_call_claim_passes_required(bind_groups.cache_key.parser_feature_flags)
                || dependency_interfaces.is_some()
            {
                if aggregates_required {
                    bind_groups
                        .calls
                        .clear_generic_claim_type_args
                        .record(encoder)?;
                }
                bind_groups
                    .calls
                    .generic_claim_validation
                    .record_claims(encoder)?;
                if let Some(dependency_visibility) = module_path.dependency_visibility.as_ref() {
                    record_compute_indirect(
                        encoder,
                        &self
                            .passes
                            .kernel("type_checker/dependencies/08a_validate_call_results"),
                        &dependency_visibility.validate_call_results_group,
                        "type_check.dependencies.resolve_generic_call_results",
                        &bind_groups.hir_active_dispatch_args,
                    )?;
                }
                if aggregates_required {
                    bind_groups
                        .calls
                        .contextual_result_requests
                        .record(encoder)?;
                    bind_groups.aggregate_compare_scan.record(encoder)?;
                    let aggregate_compare_dispatch_args = bind_groups
                        .typecheck_graph
                        .u32_buffer("aggregate_compare_dispatch_args")?;
                    record_compute(
                        encoder,
                        &self.passes.kernel("type_checker/count/dispatch_args"),
                        &bind_groups.aggregate_compare_dispatch,
                        "type_check.calls.generic_claim_type_arg_dispatch_args",
                        1,
                    )?;
                    record_compute_indirect(
                        encoder,
                        &self.passes.kernel("type_checker/conditions/aggregate_args"),
                        &bind_groups.conditions_aggregate_args,
                        "type_check.calls.validate_generic_claim_type_args",
                        &aggregate_compare_dispatch_args,
                    )?;
                    record_type_subtree_comparison_passes(&self.passes, encoder, bind_groups)?;
                }
                bind_groups
                    .calls
                    .generic_claim_validation
                    .record_required(encoder)?;
            }
            bind_groups.calls.apply_row_args.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(
                    encoder,
                    if methods_required {
                        "typecheck.methods_resolve.done"
                    } else {
                        "typecheck.calls_finalize.done"
                    },
                );
            }
            if members_required {
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/03a_member_receivers"),
                    &bind_groups.type_instances.member_receivers,
                    "type_check.resident.type_instances_member_receivers_after_final_types.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/03_member_results"),
                    &bind_groups.type_instances.member_results,
                    "type_check.resident.type_instances_member_results_after_final_types.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/03b_member_substitute"),
                    &bind_groups.type_instances.member_substitute,
                    "type_check.resident.type_instances_member_substitute_after_final_types.pass",
                    &bind_groups.token_active_dispatch_args,
                )?;
            }
            if arrays_required {
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/05_array_return_refs"),
                    &bind_groups.type_instances.array_return_refs,
                    "type_check.resident.type_instances_array_return_refs.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.array_return_refs.done");
                }
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/05b_array_literal_return_refs"),
                    &bind_groups.type_instances.array_literal_return_refs,
                    "type_check.resident.type_instances_array_literal_return_refs.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.array_literal_return_refs.done");
                }
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_late_consumers.done");
            }
            host_timer.stamp("late_value_consumers");
            if structs_required {
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/04b_struct_init_substitute"),
                    &bind_groups.type_instances.struct_init_substitute,
                    "type_check.resident.type_instances_struct_init_substitute.pass",
                    &bind_groups.token_active_dispatch_args,
                )?;
            }
            if methods_required {
                bind_groups.methods.mark_call_keys.record(encoder)?;
            }
            if aggregates_required {
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/08_validate_aggregate_access"),
                    &bind_groups.type_instances.validate_aggregate_access,
                    "type_check.resident.type_instances_validate_aggregate_access.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
            }
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/predicates/00_clear_bound_arg_facts"),
                &predicates.clear_bound_arg_facts,
                "type_check.resident.predicates_clear_bound_arg_facts.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/predicates/00b_collect_bound_arg_facts"),
                &predicates.collect_bound_arg_facts,
                "type_check.resident.predicates_collect_bound_arg_facts.pass",
                &predicate_hir_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.predicates_bound_args.done");
            }
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/predicates/00c_collect_method_contracts"),
                &predicates.collect_method_contracts,
                "type_check.resident.predicates_collect_method_contracts.pass",
                &predicate_hir_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.predicates_method_contracts.done");
            }
            record_compute_indirect(
                encoder,
                &self.passes.kernel("type_checker/predicates/01_collect"),
                &predicates.collect,
                "type_check.resident.predicates_collect.pass",
                &predicate_hir_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/predicates/01a_validate_bound_args"),
                &predicates.validate_bound_args,
                "type_check.resident.predicates_validate_bound_args.pass",
                &predicate_hir_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/predicates/01_collect_impls"),
                &predicates.collect_impls,
                "type_check.resident.predicates_collect_impls.pass",
                &predicate_hir_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.predicates_collect.done");
            }
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/predicates/01f_emit_method_validation_rows"),
                &predicates.emit_method_validation_rows,
                "type_check.resident.predicates_emit_method_validation_rows.pass",
                &predicate_hir_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/predicates/01f1_emit_method_param_validation_rows"),
                &predicates.emit_method_param_validation_rows,
                "type_check.resident.predicates_emit_method_param_validation_rows.pass",
                &predicate_hir_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/predicates/01f2_validate_method_type_arg_rows"),
                &predicates.validate_method_type_arg_rows,
                "type_check.resident.predicates_validate_method_type_arg_rows.pass",
                &predicate_hir_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/predicates/01g_reduce_method_validation_errors"),
                &predicates.reduce_method_validation_errors,
                "type_check.resident.predicates_reduce_method_validation_errors.pass",
                &predicate_hir_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.predicates_method_validation_rows.done");
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.predicates_indices.done");
            }
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/predicates/02a_count_obligations"),
                &predicates.count_obligation_pairs,
                "type_check.resident.predicates_count_obligation_pairs.pass",
                &predicate_hir_dispatch_args,
            )?;
            predicates.obligation_pair_scan.record(encoder)?;
            record_typecheck_clear_buffer(
                encoder,
                &predicates.obligation_pair_dispatch_args,
                0,
                Some(12),
            );
            record_compute_indirect(
                encoder,
                &self.passes.kernel("type_checker/count/dispatch_args"),
                &predicates.obligation_pair_dispatch,
                "type_check.predicates.obligation_pair_dispatch_args",
                &predicate_single_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/predicates/02b_validate_obligations"),
                &predicates.validate_obligation_pairs,
                "type_check.resident.predicates_validate_obligation_pairs.pass",
                &predicates.obligation_pair_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.predicates_obligations.done");
            }
            bind_groups.predicate_diagnostics.record(encoder)?;
            bind_groups.returns.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.returns.done");
            }
            if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                record_each_dependency_page(device, queue, encoder, pages, |encoder| {
                    record_dependency_call_validation(
                        &self.passes,
                        encoder,
                        module_path,
                        &bind_groups.hir_active_dispatch_args,
                        true,
                    )
                })?;
            } else {
                record_dependency_call_validation(
                    &self.passes,
                    encoder,
                    module_path,
                    &bind_groups.hir_active_dispatch_args,
                    false,
                )?;
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.compact_conditions.done");
            }
            bind_groups.calls.backend_targets.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls_backend_targets.done");
            }
            record_compute(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/semantic/artifact/00_calls"),
                &bind_groups.semantic_calls_project,
                "type_check.semantic_artifact.calls",
                hir_node_capacity,
            )?;
            record_compute(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/semantic/expression_types/00_init"),
                &bind_groups.compact_expr_scalar_type_init,
                "type_check.expression_types.init",
                hir_node_capacity,
            )?;
            for step in &bind_groups.compact_expr_scalar_type_steps {
                record_compute(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/semantic/expression_types/01_step"),
                    step,
                    "type_check.expression_types.step",
                    hir_node_capacity,
                )?;
            }
            record_compute(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/semantic/artifact/01_expression_refs"),
                &bind_groups.semantic_expression_refs_project,
                "type_check.semantic_artifact.expression_refs",
                hir_node_capacity,
            )?;
            record_compute(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/semantic/artifact/01a_struct_literal_refs"),
                &bind_groups.semantic_struct_literal_refs_project,
                "type_check.semantic_artifact.struct_literal_refs",
                hir_node_capacity,
            )?;
            record_compute(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/semantic/artifact/01b_array_index_refs"),
                &bind_groups.semantic_array_index_refs_project,
                "type_check.semantic_artifact.array_index_refs",
                hir_node_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.kernel("type_checker/conditions/compact_expr"),
                &bind_groups.conditions_compact_expr,
                "type_check.conditions.compact_expr",
                hir_node_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.kernel("type_checker/conditions/compact_stmt"),
                &bind_groups.conditions_compact_stmt,
                "type_check.conditions.compact_stmt",
                hir_node_capacity,
            )?;
            record_compute(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/conditions/compact_aggregate_requests"),
                &bind_groups.conditions_compact_aggregate_requests,
                "type_check.conditions.compact_aggregate_requests",
                hir_node_capacity,
            )?;
            if aggregates_required {
                bind_groups.aggregate_compare_scan.record(encoder)?;
                let aggregate_compare_dispatch_args = bind_groups
                    .typecheck_graph
                    .u32_buffer("aggregate_compare_dispatch_args")?;
                record_compute(
                    encoder,
                    &self.passes.kernel("type_checker/count/dispatch_args"),
                    &bind_groups.aggregate_compare_dispatch,
                    "type_check.conditions.aggregate_compare_dispatch_args",
                    1,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.kernel("type_checker/conditions/aggregate_args"),
                    &bind_groups.conditions_aggregate_args,
                    "type_check.conditions.aggregate_args.pass",
                    &aggregate_compare_dispatch_args,
                )?;
                record_type_subtree_comparison_passes(&self.passes, encoder, bind_groups)?;
            }
            if methods_required {
                // Re-publish method keys after all late call/type projections
                // have completed, immediately before condition reduction.
                // This also keeps the final condition pass independent of
                // temporary workspace reuse in preceding phases.
                bind_groups.methods.mark_call_keys.record(encoder)?;
            }
            bind_groups.condition_finalization.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.expression_types.done");
            }
            record_compute(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/semantic/artifact/00_project"),
                &bind_groups.semantic_artifact_project,
                "type_check.semantic_artifact.project",
                hir_node_capacity,
            )?;
            record_compute(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/semantic/artifact/00a_local_const_literals"),
                &bind_groups.semantic_local_const_literals_project,
                "type_check.semantic_artifact.local_const_literals",
                hir_node_capacity,
            )?;
            record_compute(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/semantic/artifact/00b_local_const_references"),
                &bind_groups.semantic_local_const_references_project,
                "type_check.semantic_artifact.local_const_references",
                hir_node_capacity,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.semantic_artifact.done");
            }
            host_timer.stamp("aggregate_conditions_control");
        }
        record_typecheck_copy_buffer_to_buffer(
            encoder,
            &self.status_buf,
            0,
            &self.status_readback,
            0,
            16,
        );
        host_timer.stamp("status_readback_recorded");
        Ok(RecordedTypeCheck {})
    }

    /// Reads the recorded status buffer and converts GPU status words to an
    /// accepted result or a typed rejection.
    pub fn finish_recorded_check(
        &self,
        device: &wgpu::Device,
        _recorded: &RecordedTypeCheck,
    ) -> Result<(), GpuTypeCheckError> {
        let slice = self.status_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(device, &slice, "type_check.status")?;
        let mapped = slice.get_mapped_range();
        let words = read_status_words(&mapped)?;
        drop(mapped);
        self.status_readback.unmap();

        if words[0] != 0 {
            return Ok(());
        }
        Err(GpuTypeCheckError::Rejected {
            token: words[1],
            code: GpuTypeCheckCode::from_u32(words[2]),
            detail: words[3],
        })
    }

    /// Borrows the retained visible-value declaration table if a resident check
    /// has populated it.
    pub fn with_visible_decl_buffer<R>(
        &self,
        consume: impl FnOnce(&wgpu::Buffer) -> R,
    ) -> Option<R> {
        let guard = self
            .resident_workspace
            .lock()
            .expect("GpuTypeChecker.resident_workspace poisoned");
        guard
            .as_ref()
            .map(|bind_groups| consume(&bind_groups.visible_decl))
    }

    /// Borrows the retained visible-type declaration table if available.
    pub fn with_visible_type_buffer<R>(
        &self,
        consume: impl FnOnce(&wgpu::Buffer) -> R,
    ) -> Option<R> {
        let guard = self
            .resident_workspace
            .lock()
            .expect("GpuTypeChecker.resident_workspace poisoned");
        guard
            .as_ref()
            .map(|bind_groups| consume(&bind_groups.visible_type))
    }

    /// Borrows the retained enclosing-function table if available.
    pub fn with_enclosing_fn_buffer<R>(
        &self,
        consume: impl FnOnce(&wgpu::Buffer) -> R,
    ) -> Option<R> {
        let guard = self
            .resident_workspace
            .lock()
            .expect("GpuTypeChecker.resident_workspace poisoned");
        let state = guard.as_ref()?;
        let enclosing_fn = state.typecheck_graph.u32_buffer("enclosing_fn").ok()?;
        Some(consume(&enclosing_fn))
    }

    /// Clones allocation-preserving handles for the compact checked artifact.
    /// Backend recording owns this boundary independently of the resident
    /// frontend workspace and cannot observe token-indexed type-check state.
    pub(crate) fn semantic_artifact(&self) -> Option<OwnedGpuSemanticArtifact> {
        self.current_semantic_artifact
            .lock()
            .expect("GpuTypeChecker.current_semantic_artifact poisoned")
            .clone()
    }

    /// Borrows the stable-identity and typed-root tables needed by the
    /// source-pack semantic-interface exporter.
    pub fn with_semantic_interface_identity_buffers<R>(
        &self,
        consume: impl FnOnce(GpuSemanticInterfaceIdentityBuffers<'_>) -> R,
    ) -> Option<R> {
        let guard = self
            .resident_workspace
            .lock()
            .expect("GpuTypeChecker.resident_workspace poisoned");
        let state = guard.as_ref()?;
        let module_path = &state.module_path;
        let name_scan_total = state.typecheck_graph.u32_buffer("name_scan_total").ok()?;
        let name_spans = state.typecheck_graph.u32_buffer("name_spans").ok()?;
        let type_expr_ref_tag = state.typecheck_graph.u32_buffer("type_expr_ref_tag").ok()?;
        let type_expr_ref_payload = state
            .typecheck_graph
            .u32_buffer("type_expr_ref_payload")
            .ok()?;
        let type_generic_param_slot_by_token = state
            .typecheck_graph
            .u32_buffer("type_generic_param_slot_by_token")
            .ok()?;
        let type_const_param_slot_by_token = state
            .typecheck_graph
            .u32_buffer("type_const_param_slot_by_token")
            .ok()?;
        let generic_param_count_out = state
            .typecheck_graph
            .u32_buffer("generic_param_count_out")
            .ok()?;
        let generic_param_owner_token = state
            .typecheck_graph
            .u32_buffer("generic_param_owner_token")
            .ok()?;
        let generic_param_name_id = state
            .typecheck_graph
            .u32_buffer("generic_param_name_id")
            .ok()?;
        let generic_param_token = state
            .typecheck_graph
            .u32_buffer("generic_param_token")
            .ok()?;
        let generic_param_kind = state
            .typecheck_graph
            .u32_buffer("generic_param_kind")
            .ok()?;
        let type_decl_generic_param_count_by_owner_token = state
            .typecheck_graph
            .u32_buffer("type_decl_generic_param_count_by_owner_token")
            .ok()?;
        let type_decl_const_param_count_by_owner_token = state
            .typecheck_graph
            .u32_buffer("type_decl_const_param_count_by_owner_token")
            .ok()?;
        let external_type_library_id = state
            .typecheck_graph
            .u32_buffer("external_type_library_id")
            .ok()?;
        let external_type_unit_id = state
            .typecheck_graph
            .u32_buffer("external_type_unit_id")
            .ok()?;
        let external_type_local_index = state
            .typecheck_graph
            .u32_buffer("external_type_local_index")
            .ok()?;
        let function_host_service_by_hir = state
            .typecheck_graph
            .u32_buffer("semantic_function_host_service_by_hir")
            .ok()?;
        let semantic_value_const_by_hir = state
            .typecheck_graph
            .u32_buffer("semantic_value_const_by_hir")
            .ok()?;
        let semantic_value_const_present_by_hir = state
            .typecheck_graph
            .u32_buffer("semantic_value_const_present_by_hir")
            .ok()?;
        let semantic_type_ref_tag_by_hir = state
            .typecheck_graph
            .u32_buffer("semantic_type_ref_tag_by_hir")
            .ok()?;
        let semantic_type_ref_payload_by_hir = state
            .typecheck_graph
            .u32_buffer("semantic_type_ref_payload_by_hir")
            .ok()?;
        let semantic_type_generic_param_slot_by_hir = state
            .typecheck_graph
            .u32_buffer("semantic_type_generic_param_slot_by_hir")
            .ok()?;
        let semantic_type_external_library_id_by_hir = state
            .typecheck_graph
            .u32_buffer("semantic_type_external_library_id_by_hir")
            .ok()?;
        let semantic_type_external_unit_id_by_hir = state
            .typecheck_graph
            .u32_buffer("semantic_type_external_unit_id_by_hir")
            .ok()?;
        let semantic_type_external_local_index_by_hir = state
            .typecheck_graph
            .u32_buffer("semantic_type_external_local_index_by_hir")
            .ok()?;
        Some(consume(GpuSemanticInterfaceIdentityBuffers {
            name_capacity: state.name_capacity,
            module_capacity: u32::try_from(module_path.module_key_segment_count.count)
                .unwrap_or(u32::MAX),
            declaration_capacity: u32::try_from(module_path.interface_public_decl_local_id.count)
                .unwrap_or(u32::MAX),
            module_segment_capacity: u32::try_from(module_path.module_key_segment_name_id.count)
                .unwrap_or(u32::MAX),
            name_count_out: &name_scan_total,
            name_spans: &name_spans,
            // The exact-name hash passes intentionally retain their outputs in
            // the name-order scratch rows after id assignment.
            name_hash_lo: &state.name_order_in,
            name_hash_hi: &state.name_order_tmp,
            name_id_by_token: &state.name_id_by_token,
            language_symbol_bytes: &state.language_symbol_bytes,
            module_count_out: &module_path.module_count_out,
            module_key_segment_count: &module_path.module_key_segment_count,
            module_key_segment_base: &module_path.module_key_segment_base,
            module_key_segment_name_id: &module_path.module_key_segment_name_id,
            decl_count_out: &module_path.decl_count_out,
            decl_module_id: &module_path.decl_module_id,
            decl_name_id: &module_path.decl_name_id,
            decl_kind: &module_path.decl_kind,
            decl_namespace: &module_path.decl_namespace,
            decl_visibility: &module_path.decl_visibility,
            decl_parent_type_decl: &module_path.decl_parent_type_decl,
            decl_hir_node: &module_path.decl_hir_node,
            semantic_value_const_by_hir: &semantic_value_const_by_hir,
            semantic_value_const_present_by_hir: &semantic_value_const_present_by_hir,
            function_host_service_by_hir: &function_host_service_by_hir,
            public_decl_count: &module_path.interface_public_decl_count,
            public_decl_local_id: &module_path.interface_public_decl_local_id,
            public_decl_index_by_local: &module_path.interface_public_decl_index_by_local,
            public_decl_index_by_hir: &module_path.interface_public_decl_index_by_hir,
            type_expr_ref_tag: &type_expr_ref_tag,
            type_expr_ref_payload: &type_expr_ref_payload,
            type_generic_param_slot_by_token: &type_generic_param_slot_by_token,
            type_const_param_slot_by_token: &type_const_param_slot_by_token,
            type_instance_decl_token: &state.type_instance_decl_token,
            external_type_library_id: &external_type_library_id,
            external_type_unit_id: &external_type_unit_id,
            external_type_local_index: &external_type_local_index,
            semantic_type_ref_tag_by_hir: &semantic_type_ref_tag_by_hir,
            semantic_type_ref_payload_by_hir: &semantic_type_ref_payload_by_hir,
            semantic_type_generic_param_slot_by_hir: &semantic_type_generic_param_slot_by_hir,
            semantic_type_external_library_id_by_hir: &semantic_type_external_library_id_by_hir,
            semantic_type_external_unit_id_by_hir: &semantic_type_external_unit_id_by_hir,
            semantic_type_external_local_index_by_hir: &semantic_type_external_local_index_by_hir,
            resolved_dependency_library_id: module_path
                .dependency_visibility
                .as_deref()
                .map(|visibility| &visibility.resolved_dependency_library_id)
                .unwrap_or(&external_type_library_id),
            resolved_dependency_unit_id: module_path
                .dependency_visibility
                .as_deref()
                .map(|visibility| &visibility.resolved_dependency_unit_id)
                .unwrap_or(&external_type_library_id),
            resolved_dependency_local_index: module_path
                .dependency_visibility
                .as_deref()
                .map(|visibility| &visibility.resolved_dependency_local_index)
                .unwrap_or(&external_type_library_id),
            path_id_by_owner_hir: &module_path.path_id_by_owner_hir,
            path_id_by_owner_token: &module_path.path_id_by_owner_token,
            resolved_type_decl: &module_path.resolved_type_decl,
            decl_id_by_name_token: &module_path.decl_id_by_name_token,
            generic_param_count_out: &generic_param_count_out,
            generic_param_owner_token: &generic_param_owner_token,
            generic_param_name_id: &generic_param_name_id,
            generic_param_token: &generic_param_token,
            generic_param_kind: &generic_param_kind,
            type_decl_generic_param_count_by_owner_token:
                &type_decl_generic_param_count_by_owner_token,
            type_decl_const_param_count_by_owner_token: &type_decl_const_param_count_by_owner_token,
        }))
    }

    /// Borrows the retained type-expression and type-instance metadata buffers.
    ///
    /// This narrow accessor exists for callers that need type-ref metadata
    /// without taking the larger backend metadata carrier.
    pub fn with_type_expr_metadata_buffers<R>(
        &self,
        consume: impl FnOnce(
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
        ) -> R,
    ) -> Option<R> {
        let guard = self
            .resident_workspace
            .lock()
            .expect("GpuTypeChecker.resident_workspace poisoned");
        let bind_groups = guard.as_ref()?;
        let graph = &bind_groups.typecheck_graph;
        let buffers = [
            graph.u32_buffer("type_expr_ref_tag").ok()?,
            graph.u32_buffer("type_expr_ref_payload").ok()?,
            graph.u32_buffer("type_instance_kind").ok()?,
            graph.u32_buffer("type_instance_arg_start").ok()?,
            graph.u32_buffer("type_instance_arg_count").ok()?,
            graph.u32_buffer("type_instance_arg_ref_tag").ok()?,
            graph.u32_buffer("type_instance_arg_ref_payload").ok()?,
            graph.u32_buffer("member_result_ref_tag").ok()?,
            graph.u32_buffer("member_result_ref_payload").ok()?,
            graph.u32_buffer("type_instance_state").ok()?,
            graph.u32_buffer("type_instance_elem_ref_tag").ok()?,
            graph.u32_buffer("fn_return_ref_tag").ok()?,
            graph.u32_buffer("fn_return_ref_payload").ok()?,
            graph
                .u32_buffer("struct_init_field_expected_ref_tag")
                .ok()?,
            graph
                .u32_buffer("struct_init_field_expected_ref_payload")
                .ok()?,
        ];
        Some(consume(
            &buffers[0],
            &buffers[1],
            &buffers[2],
            &bind_groups.type_instance_decl_token,
            &buffers[3],
            &buffers[4],
            &buffers[5],
            &buffers[6],
            &buffers[7],
            &buffers[8],
            &buffers[9],
            &buffers[10],
            &buffers[11],
            &buffers[12],
            &buffers[13],
            &buffers[14],
        ))
    }
}
