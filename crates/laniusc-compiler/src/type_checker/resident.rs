use super::*;

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
            &["type_checker", "scan/counted", "scan/counted_pair", "radix"],
            |key| {
                (key != "type_checker/predicates/01b2_sort_keys_small"
                    || supports_large_workgroup_storage)
                    && (!key.starts_with("scan/counted_pair/")
                        || device.limits().max_storage_buffers_per_shader_stage >= 7)
            },
        )?;
        let params_buf = zeroed_type_check_params_buffer(device, "type_check.resident.params");
        let status_buf = typed_storage_u32_rw(
            device,
            "type_check.resident.status",
            4,
            wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
        );
        let status_readback = readback_u32s(device, "rb.type_check.resident.status", 4);
        let preflight_graph = preflight::TypeCheckPreflightGraph::new(device, &passes)?;

        Ok(Self {
            passes,
            params_buf,
            status_buf,
            status_readback,
            preflight_graph,
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
        hir_items: GpuTypeCheckHirItemBuffers<'_>,
        dependency_pages: Option<&GpuDependencyInterfacePages>,
        timer: Option<&mut crate::gpu::timer::GpuTimer>,
        release_workspace_consumers: impl FnOnce(),
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
            hir_items,
            dependency_pages,
            timer,
            release_workspace_consumers,
        )
    }

    /// Ensures that the resident type-check graph and its physical workspace
    /// cover the supplied frontend allocation identities and capacities.
    ///
    /// This operation does not read HIR contents, publish a semantic artifact,
    /// or record type-check commands. The compiler may therefore overlap it
    /// with an already-submitted parser job, then record against the prepared
    /// workspace only after accepting the parser status.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn prepare_resident_token_buffer_with_hir_items(
        &self,
        device: &wgpu::Device,
        source_len: u32,
        source_file_capacity: u32,
        token_capacity: u32,
        token_buf: TrackedBufferView<'_>,
        token_count_buf: TrackedBufferView<'_>,
        token_file_id_buf: TrackedBufferView<'_>,
        source_buf: TrackedBufferView<'_>,
        hir_node_capacity: u32,
        hir_items: GpuTypeCheckHirItemBuffers<'_>,
        dependency_pages: Option<&GpuDependencyInterfacePages>,
        release_workspace_consumers: impl FnOnce(),
    ) -> Result<(), GpuTypeCheckError> {
        let dependency_interfaces = dependency_pages.map(GpuDependencyInterfacePages::state);
        self.ensure_resident_workspace(
            device,
            source_len,
            source_file_capacity,
            token_capacity,
            token_buf,
            token_count_buf,
            token_file_id_buf,
            source_buf,
            hir_node_capacity,
            hir_items,
            dependency_interfaces,
            release_workspace_consumers,
        )?;
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    fn ensure_resident_workspace(
        &self,
        device: &wgpu::Device,
        source_len: u32,
        source_file_capacity: u32,
        token_capacity: u32,
        token_buf: TrackedBufferView<'_>,
        token_count_buf: TrackedBufferView<'_>,
        token_file_id_buf: TrackedBufferView<'_>,
        source_buf: TrackedBufferView<'_>,
        hir_node_capacity: u32,
        hir_items: GpuTypeCheckHirItemBuffers<'_>,
        dependency_interfaces: Option<&GpuDependencyInterfaceState>,
        release_workspace_consumers: impl FnOnce(),
    ) -> Result<bool, GpuTypeCheckError> {
        let input_buffers = [
            token_buf.buffer,
            token_count_buf.buffer,
            token_file_id_buf.buffer,
            source_buf.buffer,
        ];
        let hir_buffers = hir_items.hir.typecheck_buffers();
        let upstream_workspace_buffers = hir_items
            .upstream_workspace
            .iter()
            .map(|workspace| workspace.buffer)
            .collect::<Vec<_>>();
        let dependency_buffers = dependency_interfaces
            .map(|dependencies| {
                vec![
                    &dependencies.words.buffer,
                    &dependencies.module_lookup.buffer,
                ]
            })
            .unwrap_or_default();
        let mut fingerprint_buffers = input_buffers.to_vec();
        fingerprint_buffers.extend(hir_buffers.iter().copied());
        fingerprint_buffers.extend(upstream_workspace_buffers.iter().copied());
        fingerprint_buffers.extend(dependency_buffers.iter().copied());
        let cache_key = ResidentTypeCheckCacheKey {
            source_byte_capacity: source_len.max(1),
            source_file_capacity,
            token_capacity,
            hir_node_capacity,
            module_record_capacity: hir_items.module_record_capacity.max(1),
            call_param_row_capacity: hir_items.call_param_row_capacity.max(1),
            call_arg_row_capacity: hir_items.call_arg_row_capacity.max(1),
            parser_feature_flags: hir_items.parser_feature_flags,
            semantic_interface_required: hir_items.semantic_interface_required,
            input_fingerprint: buffer_fingerprint(&fingerprint_buffers),
        }
        .bucketed();

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
            && let Some(previous) = resident_workspace_guard.as_ref()
        {
            eprintln!(
                "[gpu_compile_host_timer] typecheck.resident_cache_miss: input_fingerprint={:#018x}->{:#018x} token_capacity={}->{} hir_capacity={}->{} module_capacity={}->{} call_param_capacity={}->{} call_arg_capacity={}->{} features={:#010x}->{:#010x} semantic_interface={}->{}",
                previous.cache_key.input_fingerprint,
                cache_key.input_fingerprint,
                previous.cache_key.token_capacity,
                cache_key.token_capacity,
                previous.cache_key.hir_node_capacity,
                cache_key.hir_node_capacity,
                previous.cache_key.module_record_capacity,
                cache_key.module_record_capacity,
                previous.cache_key.call_param_row_capacity,
                cache_key.call_param_row_capacity,
                previous.cache_key.call_arg_row_capacity,
                cache_key.call_arg_row_capacity,
                previous.cache_key.parser_feature_flags,
                cache_key.parser_feature_flags,
                previous.cache_key.semantic_interface_required,
                cache_key.semantic_interface_required,
            );
        }
        if resident_cache_trace {
            eprintln!(
                "[typecheck.resident_cache] rebuild={needs_rebuild} source={} files={} tokens={} hir={} modules={} call_params={} call_args={} features={:#010x} semantic_interface={} fingerprint={:#018x} input_fingerprint={:#018x} hir_fingerprint={:#018x} upstream_workspace_fingerprint={:#018x} dependency_fingerprint={:#018x} allocation_source={} allocation_files={} allocation_tokens={} allocation_hir={} allocation_modules={} allocation_call_params={} allocation_call_args={} allocation_features={:#010x} allocation_semantic_interface={}",
                cache_key.source_byte_capacity,
                cache_key.source_file_capacity,
                cache_key.token_capacity,
                cache_key.hir_node_capacity,
                cache_key.module_record_capacity,
                cache_key.call_param_row_capacity,
                cache_key.call_arg_row_capacity,
                cache_key.parser_feature_flags,
                cache_key.semantic_interface_required,
                cache_key.input_fingerprint,
                buffer_fingerprint(&input_buffers),
                buffer_fingerprint(&hir_buffers),
                buffer_fingerprint(&upstream_workspace_buffers),
                buffer_fingerprint(&dependency_buffers),
                allocation.source_byte_capacity,
                allocation.source_file_capacity,
                allocation.token_capacity,
                allocation.hir_node_capacity,
                allocation.module_record_capacity,
                allocation.call_param_row_capacity,
                allocation.call_arg_row_capacity,
                allocation.parser_feature_flags,
                allocation.semantic_interface_required,
            );
        }
        if needs_rebuild {
            // A cache miss changes bound allocation identities, so none of the
            // old bind groups or scratch buffers can be reused. Drop that
            // state before allocating its replacement to avoid retaining two
            // complete type-check workspaces at a unit boundary.
            self.current_semantic_artifact
                .lock()
                .expect("GpuTypeChecker.current_semantic_artifact poisoned")
                .take();
            resident_workspace_guard.take();
            release_workspace_consumers();
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
        Ok(needs_rebuild)
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
        hir_items: GpuTypeCheckHirItemBuffers<'_>,
        dependency_pages: Option<&GpuDependencyInterfacePages>,
        mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
        release_workspace_consumers: impl FnOnce(),
    ) -> Result<RecordedTypeCheck, GpuTypeCheckError> {
        let _operation_capture = timer
            .as_deref()
            .map(crate::gpu::timer::GpuTimer::capture_operations);
        if let Some(timer) = timer.as_deref_mut() {
            timer.set_phase(crate::gpu::timer::GpuCompilerPhase::TypeChecking);
        }
        // Wgpu gives each compute dispatch its own resource-usage scope and
        // inserts barriers before conflicting dispatches. Buffer clear/copy
        // operations flush the deferred stream, while timestamped or
        // validation-scoped recording keeps separate compute passes.
        let _compute_batch = crate::gpu::passes_core::DeferredComputeBatchGuard::begin(
            crate::gpu::passes_core::compute_pass_batching_allowed(timer.is_some()),
            "type_check.resident.batch",
        );
        let params = TypeCheckParams {
            n_tokens: token_capacity,
            source_len,
            n_hir_nodes: hir_node_capacity,
            n_source_files: source_file_capacity,
            parser_feature_flags: hir_items.parser_feature_flags,
            dependency_interfaces_present: u32::from(dependency_pages.is_some()),
        };
        self.params_buf
            .write(queue, 0, &type_check_params_bytes(&params));
        self.status_buf.write(queue, 0, &status_init_bytes());
        let mut host_timer = TypeCheckRecordHostTimer::new();
        host_timer.stamp("params");
        let parser_feature_flags = hir_items.parser_feature_flags;
        let dependency_interfaces = dependency_pages.map(GpuDependencyInterfacePages::state);
        let rebuilt = self.ensure_resident_workspace(
            device,
            source_len,
            source_file_capacity,
            token_capacity,
            token_buf,
            token_count_buf,
            token_file_id_buf,
            source_buf,
            hir_node_capacity,
            hir_items,
            dependency_interfaces,
            release_workspace_consumers,
        )?;
        host_timer.stamp(if rebuilt {
            "resident_workspace_rebuilt"
        } else {
            "resident_workspace_reused"
        });
        {
            let resident_workspace_guard = self
                .resident_workspace
                .lock()
                .expect("GpuTypeChecker.resident_workspace poisoned");
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
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.workspace_ready");
            }
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
            let methods_required = method_passes_required(parser_feature_flags);
            let arrays_required = array_passes_required(parser_feature_flags);
            let structs_required = struct_init_passes_required(parser_feature_flags);
            let members_required = member_passes_required(parser_feature_flags);
            let enums_required = enum_passes_required(parser_feature_flags);
            let matches_required = match_passes_required(parser_feature_flags);
            let aggregates_required = aggregate_passes_required(parser_feature_flags);
            let aliases_required = type_alias_passes_required(parser_feature_flags);

            // Parser scratch is reused physically by the resident type-check
            // graph. The job reset precedes parser execution, so reset those
            // imported allocations here after parsing has finished and before
            // type checking reads or partially initializes them.
            bind_groups.typecheck_graph.record_phase_reset(encoder);
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.phase_reset.done");
            }

            bind_groups.hir_active_dispatch.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.hir_active_dispatch.done");
            }
            bind_groups.semantic_features.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.frontend_boundary.done");
            }
            record_if_depth_passes_with_passes(encoder, bind_groups)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.if_depth.done");
            }
            record_language_name_bind_groups_with_passes(
                encoder,
                &bind_groups.language_name_bind_groups,
            )?;
            record_name_bind_groups_with_passes(encoder, &bind_groups.name_bind_groups)?;
            record_language_decl_bind_groups_with_passes(
                encoder,
                &bind_groups.language_name_bind_groups,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.names.done");
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.language_decls.done");
            }
            host_timer.stamp("loop_names_language_decls");
            predicates.clear_syntax_tokens.record(encoder)?;
            record_module_path_state_with_passes(
                device,
                queue,
                &self.passes,
                encoder,
                module_path,
                dependency_pages,
                timer.as_deref_mut(),
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.module_paths.done");
            }
            host_timer.stamp("module_paths");
            bind_groups.type_instances.clear.record(encoder)?;
            if let Some(dependency_visibility) = module_path.dependency_visibility.as_ref() {
                // The shared type-instance clear resets token-indexed refs.
                // Re-publish canonical dependency refs before collection so
                // imported nominal types cannot be reclassified as unresolved
                // local generic parameters.  The dependency interface slot is
                // paged, so replay the projection for every page rather than
                // leaving only the final page's declarations visible.
                let project_types = |encoder: &mut wgpu::CommandEncoder| {
                    record_dependency_type_index(
                        &self.passes,
                        encoder,
                        module_path,
                        DEPENDENCY_TYPE_INDEX_AFTER_TYPE_CLEAR,
                    )?;
                    dependency_visibility.project_types_group.record_invocation(
                        encoder,
                        &dependency_visibility.project_types_after_clear,
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
            record_generic_param_record_passes_with_passes(
                encoder,
                &bind_groups.type_instances,
                timer.as_deref_mut(),
            )?;
            record_type_instance_collection_passes_with_passes(
                encoder,
                bind_groups,
                parser_feature_flags,
                &super::record::TYPE_INSTANCE_COLLECTION_INITIAL_LABELS,
                timer.as_deref_mut(),
            )?;
            if aliases_required {
                let aliases = module_path
                    .bind_groups
                    .type_aliases
                    .as_ref()
                    .expect("alias operations exist when alias syntax is present");
                aliases.record_roots(encoder)?;
                aliases.record_projection(encoder, TypeAliasProjectStage::Initial)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.modules.project_type_aliases.done");
                }
            }
            module_path
                .bind_groups
                .project_type_paths
                .record_invocation(
                    encoder,
                    &module_path.bind_groups.project_type_paths_after_aliases,
                )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(
                    encoder,
                    "typecheck.modules.project_type_paths.after_aliases.done",
                );
            }
            record_type_instance_collection_passes_with_passes(
                encoder,
                bind_groups,
                parser_feature_flags,
                &super::record::TYPE_INSTANCE_COLLECTION_PROJECTED_LABELS,
                timer.as_deref_mut(),
            )?;
            if aliases_required {
                module_path
                    .bind_groups
                    .type_aliases
                    .as_ref()
                    .expect("alias operations exist when alias syntax is present")
                    .record_projection(encoder, TypeAliasProjectStage::AfterProjectedRefs)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(
                        encoder,
                        "typecheck.modules.project_type_aliases.after_projected_refs.done",
                    );
                }
            }
            module_path
                .bind_groups
                .project_type_paths
                .record_invocation(
                    encoder,
                    &module_path
                        .bind_groups
                        .project_type_paths_after_projected_aliases,
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
            module_path
                .bind_groups
                .project_type_instances
                .record(encoder)?;
            if let Some(dependency_visibility) = &module_path.dependency_visibility {
                let record_projection = |encoder: &mut wgpu::CommandEncoder| {
                    record_dependency_type_index(
                        &self.passes,
                        encoder,
                        module_path,
                        DEPENDENCY_TYPE_INDEX_TYPE_INSTANCE_PROJECTION,
                    )?;
                    dependency_visibility
                        .project_type_instances_group
                        .record(encoder)
                };
                if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                    record_each_dependency_page(device, queue, encoder, pages, record_projection)?;
                } else {
                    dependency_visibility
                        .project_type_instances_group
                        .record(encoder)?;
                }
            }
            if aliases_required {
                module_path
                    .bind_groups
                    .type_aliases
                    .as_ref()
                    .expect("alias operations exist when alias syntax is present")
                    .record_equivalence(encoder)?;
            }
            module_path
                .bind_groups
                .project_type_paths
                .record_invocation(
                    encoder,
                    &module_path
                        .bind_groups
                        .project_type_paths_after_alias_equivalence,
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
            bind_groups
                .type_instances
                .collect_named_arg_refs
                .record(encoder)?;
            if aliases_required {
                module_path
                    .bind_groups
                    .type_aliases
                    .as_ref()
                    .expect("alias operations exist when alias syntax is present")
                    .record_instances(encoder)?;
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_named_arg_refs.done");
            }
            bind_groups.type_instances.hash_arg_rows.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_arg_hash.done");
            }
            if aggregates_required {
                bind_groups
                    .type_instances
                    .clear_semantic_type_rows
                    .record(encoder)?;
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
            record_fn_context_bind_groups_with_passes(
                encoder,
                &bind_groups.fn_context_bind_groups,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.fn_context.done");
            }
            bind_groups.calls.record_primary_prefix(encoder)?;
            if let Some(visibility) = &module_path.dependency_visibility {
                if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                    record_each_dependency_page(device, queue, encoder, pages, |encoder| {
                        record_dependency_page(
                            &self.passes,
                            encoder,
                            module_path,
                            DEPENDENCY_PAGE_CALL_COLLECTION,
                        )?;
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
                        record_dependency_type_index(
                            &self.passes,
                            encoder,
                            module_path,
                            DEPENDENCY_TYPE_INDEX_CALL_PARAM_SCATTER,
                        )?;
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
                encoder,
                &bind_groups.visible_bind_groups,
                timer.as_deref_mut(),
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.visible.done");
            }
            host_timer.stamp("fn_context_calls_visible");

            bind_groups.type_instances.decl_refs.record(encoder)?;
            // For-binding element refs consume iterable decl refs published by
            // the same HIR-indexed shader, so run a second fixed pass after the
            // direct decl facts are stable.
            bind_groups
                .type_instances
                .decl_refs
                .record_invocation(encoder, &bind_groups.type_instances.decl_refs_for_bindings)?;
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
                bind_groups
                    .type_instances
                    .member_receivers
                    .record(encoder)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.member_receivers.done");
                }
            }
            if struct_field_index_passes_required(parser_feature_flags) {
                record_struct_field_key_passes_with_passes(
                    encoder,
                    &bind_groups.type_instances,
                    timer.as_deref_mut(),
                )?;
            }
            if members_required {
                bind_groups.type_instances.member_results.record(encoder)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.member_results.done");
                }
                bind_groups
                    .type_instances
                    .member_substitute
                    .record(encoder)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.member_substitute.done");
                }
            }
            if structs_required {
                bind_groups
                    .type_instances
                    .struct_init_clear
                    .record(encoder)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.struct_init_clear.done");
                }
                bind_groups
                    .type_instances
                    .struct_init_contexts
                    .record(encoder)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.struct_init_contexts.done");
                }
                bind_groups
                    .type_instances
                    .struct_init_fields
                    .record(encoder)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.struct_init_fields.done");
                }
                bind_groups
                    .semantic_projection
                    .struct_literal_refs_early_clear
                    .record(encoder);
                bind_groups
                    .semantic_projection
                    .struct_literal_refs
                    .record_invocation(
                        encoder,
                        &bind_groups.semantic_projection.struct_literal_refs_early,
                    )?;
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instance_fields.done");
            }
            host_timer.stamp("methods_member_struct_fields");
            if matches_required {
                module_path
                    .bind_groups
                    .bind_match_patterns
                    .record(encoder)?;
                module_path
                    .bind_groups
                    .type_match_payloads
                    .record(encoder)?;
            }
            bind_groups.scope_hir.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.scope.done");
            }
            bind_groups.calls.resolve.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls_resolve.done");
            }
            bind_groups
                .calls
                .argument_matching
                .record(encoder, CallArgumentMatchStage::Direct)?;
            bind_groups
                .calls
                .apply_row_args
                .record_as(encoder, CallArgumentMatchStage::Direct.operation_names().2)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls_row_args.done");
            }
            if methods_required {
                bind_groups
                    .methods
                    .mark_call_keys
                    .record_as(encoder, METHODS_MARK_CALL_KEYS.name)?;
                if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                    record_each_dependency_page(device, queue, encoder, pages, |encoder| {
                        record_dependency_type_index(
                            &self.passes,
                            encoder,
                            module_path,
                            DEPENDENCY_TYPE_INDEX_METHOD_PROJECTION,
                        )?;
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
            module_path
                .bind_groups
                .consume_value_calls
                .record(encoder)?;
            module_path
                .bind_groups
                .mirror_value_call_leaf
                .record(encoder)?;
            bind_groups
                .calls
                .argument_matching
                .record(encoder, CallArgumentMatchStage::ModuleValues)?;
            bind_groups.calls.apply_row_args.record_as(
                encoder,
                CallArgumentMatchStage::ModuleValues.operation_names().2,
            )?;
            module_path
                .bind_groups
                .mirror_value_call_leaf
                .record_invocation(
                    encoder,
                    &module_path
                        .bind_groups
                        .mirror_value_call_leaf_after_row_args,
                )?;
            if methods_required {
                bind_groups.methods.keys.record(encoder)?;
                bind_groups.methods.record_call_resolution(encoder)?;
            }
            bind_groups.calls.project_result_instances.record(encoder)?;
            bind_groups
                .calls
                .argument_matching
                .record(encoder, CallArgumentMatchStage::MethodResults)?;
            bind_groups.calls.apply_row_args.record_as(
                encoder,
                CallArgumentMatchStage::MethodResults.operation_names().2,
            )?;
            module_path
                .bind_groups
                .consume_value_calls
                .record_invocation(
                    encoder,
                    &module_path.bind_groups.consume_value_calls_after_methods,
                )?;
            module_path
                .bind_groups
                .mirror_value_call_leaf
                .record_invocation(
                    encoder,
                    &module_path.bind_groups.mirror_value_call_leaf_after_methods,
                )?;
            bind_groups
                .calls
                .argument_matching
                .record(encoder, CallArgumentMatchStage::MethodModules)?;
            bind_groups.calls.apply_row_args.record_as(
                encoder,
                CallArgumentMatchStage::MethodModules.operation_names().2,
            )?;
            module_path
                .bind_groups
                .mirror_value_call_leaf
                .record_invocation(
                    encoder,
                    &module_path
                        .bind_groups
                        .mirror_value_call_leaf_after_method_row_args,
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
                bind_groups.calls.infer_array_generics.record(encoder)?;
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
                record_call_erase_generic_params_with_passes(encoder, &bind_groups.calls)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.calls_erased.done");
                }
            }
            if enums_required {
                module_path
                    .bind_groups
                    .consume_value_enum_calls
                    .record(encoder)?;
                module_path
                    .bind_groups
                    .validate_value_enum_call_payloads
                    .record(encoder)?;
                module_path
                    .bind_groups
                    .finalize_value_enum_calls
                    .record(encoder)?;
            }
            if matches_required {
                module_path.bind_groups.type_match_exprs.record(encoder)?;
            }
            module_path
                .bind_groups
                .consume_value_consts
                .record(encoder)?;
            module_path
                .bind_groups
                .consume_value_enum_units
                .record(encoder)?;
            if methods_required {
                bind_groups.methods.resolve.record(encoder)?;
            }
            bind_groups
                .calls
                .argument_matching
                .record(encoder, CallArgumentMatchStage::Final)?;
            if generic_call_claim_passes_required(parser_feature_flags)
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
                    dependency_visibility
                        .validate_call_results_group
                        .record_invocation(
                            encoder,
                            &dependency_visibility.generic_call_results_resolve,
                        )?;
                }
                if aggregates_required {
                    bind_groups
                        .calls
                        .contextual_result_requests
                        .record(encoder)?;
                    bind_groups
                        .aggregate_comparison
                        .record(encoder, AggregateComparisonStage::Calls)?;
                }
                bind_groups
                    .calls
                    .generic_claim_validation
                    .record_required(encoder)?;
            }
            bind_groups
                .calls
                .apply_row_args
                .record_as(encoder, CallArgumentMatchStage::Final.operation_names().2)?;
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
                bind_groups
                    .type_instances
                    .member_receivers
                    .record_invocation(
                        encoder,
                        &bind_groups.type_instances.member_receivers_after_array,
                    )?;
                bind_groups
                    .type_instances
                    .member_results
                    .record_invocation(
                        encoder,
                        &bind_groups.type_instances.member_results_after_array,
                    )?;
                bind_groups
                    .type_instances
                    .member_substitute
                    .record_invocation(
                        encoder,
                        &bind_groups.type_instances.member_substitute_after_array,
                    )?;
            }
            if arrays_required {
                bind_groups
                    .type_instances
                    .array_return_refs
                    .record(encoder)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.array_return_refs.done");
                }
                bind_groups
                    .type_instances
                    .array_literal_return_refs
                    .record(encoder)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.array_literal_return_refs.done");
                }
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_late_consumers.done");
            }
            host_timer.stamp("late_value_consumers");
            if structs_required {
                bind_groups
                    .type_instances
                    .struct_init_substitute
                    .record(encoder)?;
            }
            if methods_required {
                bind_groups
                    .methods
                    .mark_call_keys
                    .record_as(encoder, METHODS_MARK_CALL_KEYS_AGGREGATE_VALIDATION.name)?;
            }
            if aggregates_required {
                bind_groups
                    .type_instances
                    .validate_aggregate_access
                    .record(encoder)?;
            }
            predicates.clear_bound_arg_facts.record(encoder)?;
            predicates.collect_bound_arg_facts.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.predicates_bound_args.done");
            }
            predicates.collect_method_contracts.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.predicates_method_contracts.done");
            }
            predicates.collect.record(encoder)?;
            predicates.validate_bound_args.record(encoder)?;
            predicates.collect_impls.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.predicates_collect.done");
            }
            predicates.emit_method_validation_rows.record(encoder)?;
            predicates
                .emit_method_param_validation_rows
                .record(encoder)?;
            predicates.validate_method_type_arg_rows.record(encoder)?;
            predicates.reduce_method_validation_errors.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.predicates_method_validation_rows.done");
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.predicates_indices.done");
            }
            predicates.count_obligation_pairs.record(encoder)?;
            predicates.obligation_pair_scan.record(encoder)?;
            predicates.obligation_pair_dispatch_clear.record(encoder);
            predicates.obligation_pair_dispatch.record(encoder)?;
            predicates.validate_obligation_pairs.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.predicates_obligations.done");
            }
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
            bind_groups.semantic_projection.calls.record(encoder)?;
            bind_groups
                .semantic_projection
                .expression_types_init
                .record(encoder)?;
            bind_groups
                .semantic_projection
                .expression_refs
                .record(encoder)?;
            bind_groups
                .semantic_projection
                .struct_literal_refs
                .record(encoder)?;
            bind_groups
                .semantic_projection
                .array_index_refs
                .record(encoder)?;
            bind_groups
                .semantic_projection
                .compact_expr
                .record(encoder)?;
            bind_groups
                .semantic_projection
                .compact_stmt
                .record(encoder)?;
            bind_groups
                .semantic_projection
                .compact_aggregate_requests
                .record(encoder)?;
            if aggregates_required {
                bind_groups
                    .aggregate_comparison
                    .record(encoder, AggregateComparisonStage::Final)?;
            }
            if methods_required {
                // Re-publish method keys after all late call/type projections
                // have completed, immediately before condition reduction.
                // This also keeps the final condition pass independent of
                // temporary workspace reuse in preceding phases.
                bind_groups
                    .methods
                    .mark_call_keys
                    .record_as(encoder, METHODS_MARK_CALL_KEYS_CONDITION_FINALIZATION.name)?;
            }
            bind_groups.condition_finalization.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.expression_types.done");
            }
            bind_groups.semantic_projection.artifact.record(encoder)?;
            bind_groups
                .semantic_projection
                .local_const_literals
                .record(encoder)?;
            bind_groups
                .semantic_projection
                .local_const_references
                .record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.semantic_artifact.done");
            }
            host_timer.stamp("aggregate_conditions_control");
            bind_groups.status_readback.record(encoder);
        }
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

    pub(crate) fn with_post_typecheck_workspace<R>(
        &self,
        semantic: &OwnedGpuSemanticArtifact,
        consume: impl FnOnce(&[crate::gpu::buffers::TrackedBufferView<'_>]) -> R,
    ) -> Option<R> {
        let guard = self
            .resident_workspace
            .lock()
            .expect("GpuTypeChecker.resident_workspace poisoned");
        let state = guard.as_ref()?;
        let workspace = state.post_typecheck_workspace(semantic);
        Some(consume(&workspace))
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
            name_count_out: (&name_scan_total).into(),
            name_spans: (&name_spans).into(),
            // The exact-name hash passes intentionally retain their outputs in
            // the name-order scratch rows after id assignment.
            name_hash_lo: (&state.name_order_in).into(),
            name_hash_hi: (&state.name_order_tmp).into(),
            name_id_by_token: (&state.name_id_by_token).into(),
            language_symbol_bytes: (&state.language_symbol_bytes).into(),
            module_count_out: (&module_path.module_count_out).into(),
            module_key_segment_count: (&module_path.module_key_segment_count).into(),
            module_key_segment_base: (&module_path.module_key_segment_base).into(),
            module_key_segment_name_id: (&module_path.module_key_segment_name_id).into(),
            decl_count_out: (&module_path.decl_count_out).into(),
            decl_module_id: (&module_path.decl_module_id).into(),
            decl_name_id: (&module_path.decl_name_id).into(),
            decl_kind: (&module_path.decl_kind).into(),
            decl_namespace: (&module_path.decl_namespace).into(),
            decl_visibility: (&module_path.decl_visibility).into(),
            decl_parent_type_decl: (&module_path.decl_parent_type_decl).into(),
            decl_hir_node: (&module_path.decl_hir_node).into(),
            semantic_value_const_by_hir: (&semantic_value_const_by_hir).into(),
            semantic_value_const_present_by_hir: (&semantic_value_const_present_by_hir).into(),
            function_host_service_by_hir: (&function_host_service_by_hir).into(),
            public_decl_count: (&module_path.interface_public_decl_count).into(),
            public_decl_local_id: (&module_path.interface_public_decl_local_id).into(),
            public_decl_index_by_local: (&module_path.interface_public_decl_index_by_local).into(),
            public_decl_index_by_hir: (&module_path.interface_public_decl_index_by_hir).into(),
            type_expr_ref_tag: (&type_expr_ref_tag).into(),
            type_expr_ref_payload: (&type_expr_ref_payload).into(),
            type_generic_param_slot_by_token: (&type_generic_param_slot_by_token).into(),
            type_const_param_slot_by_token: (&type_const_param_slot_by_token).into(),
            type_instance_decl_token: (&state.type_instance_decl_token).into(),
            external_type_library_id: (&external_type_library_id).into(),
            external_type_unit_id: (&external_type_unit_id).into(),
            external_type_local_index: (&external_type_local_index).into(),
            semantic_type_ref_tag_by_hir: (&semantic_type_ref_tag_by_hir).into(),
            semantic_type_ref_payload_by_hir: (&semantic_type_ref_payload_by_hir).into(),
            semantic_type_generic_param_slot_by_hir: (&semantic_type_generic_param_slot_by_hir)
                .into(),
            semantic_type_external_library_id_by_hir: (&semantic_type_external_library_id_by_hir)
                .into(),
            semantic_type_external_unit_id_by_hir: (&semantic_type_external_unit_id_by_hir).into(),
            semantic_type_external_local_index_by_hir: (&semantic_type_external_local_index_by_hir)
                .into(),
            resolved_dependency_library_id: module_path
                .dependency_visibility
                .as_deref()
                .map(|visibility| (&visibility.resolved_dependency_library_id).into())
                .unwrap_or_else(|| (&external_type_library_id).into()),
            resolved_dependency_unit_id: module_path
                .dependency_visibility
                .as_deref()
                .map(|visibility| (&visibility.resolved_dependency_unit_id).into())
                .unwrap_or_else(|| (&external_type_library_id).into()),
            resolved_dependency_local_index: module_path
                .dependency_visibility
                .as_deref()
                .map(|visibility| (&visibility.resolved_dependency_local_index).into())
                .unwrap_or_else(|| (&external_type_library_id).into()),
            path_id_by_owner_hir: (&module_path.path_id_by_owner_hir).into(),
            path_id_by_owner_token: (&module_path.path_id_by_owner_token).into(),
            resolved_type_decl: (&module_path.resolved_type_decl).into(),
            decl_id_by_name_token: (&module_path.decl_id_by_name_token).into(),
            generic_param_count_out: (&generic_param_count_out).into(),
            generic_param_owner_token: (&generic_param_owner_token).into(),
            generic_param_name_id: (&generic_param_name_id).into(),
            generic_param_token: (&generic_param_token).into(),
            generic_param_kind: (&generic_param_kind).into(),
            type_decl_generic_param_count_by_owner_token:
                (&type_decl_generic_param_count_by_owner_token).into(),
            type_decl_const_param_count_by_owner_token:
                (&type_decl_const_param_count_by_owner_token).into(),
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
