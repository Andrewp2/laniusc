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
    bind_groups: &ResidentTypeCheckState,
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
    last_compute_passes: u32,
}

impl TypeCheckRecordHostTimer {
    fn new() -> Self {
        let now = std::time::Instant::now();
        Self {
            enabled: crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false),
            start: now,
            last: now,
            last_compute_passes: 0,
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
        eprintln!(
            "[gpu_compile_host_timer] typecheck.record.{stage}: {dt_ms:.3}ms (total {total_ms:.3}ms compute_passes={stage_compute_passes} total_compute_passes={compute_passes})"
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
        let passes =
            TypeCheckPasses::prepare_prefixes(device, &["type_checker", "scan/counted"], |key| {
                key != "type_checker/predicates/01b2_sort_keys_small"
                    || supports_large_workgroup_storage
            })?;
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
            resident_state: Mutex::new(None),
        })
    }

    /// Releases reusable semantic buffers and their bind groups while
    /// retaining the type-check pipelines and fixed status resources.
    pub fn release_current_resident_state(&self) {
        *self
            .resident_state
            .lock()
            .expect("GpuTypeChecker.resident_state poisoned") = None;
    }

    /// Checks resident compiler buffers. The cached bind groups assume buffer
    /// identities stay stable until the requested capacities grow.
    pub fn check_resident_token_buffer_with_hir_on_gpu(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        source_len: u32,
        source_file_capacity: u32,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        hir_node_capacity: u32,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_token_file_id_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
    ) -> Result<(), GpuTypeCheckError> {
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("type_check.resident.encoder"),
        });
        let recorded = self.record_resident_token_buffer_with_hir_on_gpu(
            device,
            queue,
            &mut encoder,
            source_len,
            source_file_capacity,
            token_capacity,
            token_buf,
            token_count_buf,
            token_file_id_buf,
            source_buf,
            hir_node_capacity,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_token_file_id_buf,
            hir_status_buf,
            None,
        )?;
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "type_check.resident-with-hir",
            encoder.finish(),
        );
        self.finish_recorded_check(device, &recorded)
    }

    /// Records resident type checking with parser-owned HIR item metadata.
    /// This is the path used by the compiler's LL(1) frontend.
    #[allow(clippy::too_many_arguments)]
    pub fn record_resident_token_buffer_with_hir_items_on_gpu(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        source_file_capacity: u32,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        hir_node_capacity: u32,
        parser_hir_node_capacity: u32,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_token_file_id_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        hir_items: GpuTypeCheckHirItemBuffers<'_>,
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
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_token_file_id_buf,
            hir_status_buf,
            Some(hir_items),
            None,
            None,
            None,
            timer,
        )
    }

    /// Records resident type checking with parser-owned HIR item metadata and
    /// parser-owned scratch buffers whose parser lifetimes have ended.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn record_resident_token_buffer_with_hir_items_and_scratch_on_gpu(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        source_file_capacity: u32,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        hir_node_capacity: u32,
        parser_hir_node_capacity: u32,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_token_file_id_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        hir_items: GpuTypeCheckHirItemBuffers<'_>,
        external_scratch: GpuTypeCheckExternalScratchBuffers<'_>,
        dependency_interfaces: Option<&GpuDependencyInterfaceState>,
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
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_token_file_id_buf,
            hir_status_buf,
            Some(hir_items),
            None,
            Some(external_scratch),
            dependency_interfaces,
            timer,
        )
    }

    /// Records resident type checking into an existing command encoder. The caller
    /// owns submission and must call `finish_recorded_check` after the submission
    /// has completed.
    #[allow(clippy::too_many_arguments)]
    pub fn record_resident_token_buffer_with_hir_on_gpu(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        source_file_capacity: u32,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        hir_node_capacity: u32,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_token_file_id_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
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
            hir_node_capacity,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_token_file_id_buf,
            hir_status_buf,
            None,
            None,
            None,
            None,
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
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        hir_node_capacity: u32,
        parser_hir_node_capacity: u32,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_token_file_id_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        hir_items: Option<GpuTypeCheckHirItemBuffers<'_>>,
        external_scratch: Option<GpuTypeCheckExternalScratchBuffers<'_>>,
        module_path_scratch: Option<GpuTypeCheckExternalScratchBuffers<'_>>,
        dependency_interfaces: Option<&GpuDependencyInterfaceState>,
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
            parser_feature_flags: hir_items
                .map(|items| items.parser_feature_flags)
                .unwrap_or(u32::MAX),
        };
        queue.write_buffer(&self.params_buf, 0, &type_check_params_bytes(&params));
        queue.write_buffer(&self.status_buf, 0, &status_init_bytes());
        let mut host_timer = TypeCheckRecordHostTimer::new();
        reset_recorded_compute_pass_count();
        host_timer.stamp("params");

        let uses_hir_items = hir_items.is_some();
        let mut fingerprint_buffers = vec![
            token_buf,
            token_count_buf,
            token_file_id_buf,
            source_buf,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_token_file_id_buf,
            hir_status_buf,
        ];
        if let Some(items) = hir_items {
            fingerprint_buffers.push(&items.hir.count);
            fingerprint_buffers.push(&items.hir.core);
            fingerprint_buffers.push(&items.hir.links);
            fingerprint_buffers.push(&items.hir.payload);
            fingerprint_buffers.push(&items.hir.const_type);
            fingerprint_buffers.push(&items.hir.type_arg_count);
            fingerprint_buffers.push(&items.hir.type_args);
            fingerprint_buffers.push(&items.hir.type_arg_ranges);
            fingerprint_buffers.push(&items.hir.field_count);
            fingerprint_buffers.push(&items.hir.fields);
            fingerprint_buffers.push(&items.hir.variant_count);
            fingerprint_buffers.push(&items.hir.variants);
            fingerprint_buffers.push(&items.hir.variant_payload_start);
            fingerprint_buffers.push(&items.hir.variant_payload_count);
            fingerprint_buffers.push(&items.hir.variant_payload_row_count);
            fingerprint_buffers.push(&items.hir.variant_payloads);
            fingerprint_buffers.push(&items.hir.array_element_start);
            fingerprint_buffers.push(&items.hir.array_element_count);
            fingerprint_buffers.push(&items.hir.array_element_row_count);
            fingerprint_buffers.push(&items.hir.array_elements);
            fingerprint_buffers.push(items.semantic_dense_node);
            fingerprint_buffers.push(items.semantic_count);
            fingerprint_buffers.push(items.semantic_subtree_end);
            fingerprint_buffers.push(items.type_root_owner);
            fingerprint_buffers.push(items.nearest_loop_node);
        }
        if let Some(scratch) = external_scratch {
            if let Some(record_family_flag) = scratch.record_family_flag {
                fingerprint_buffers.push(record_family_flag);
            }
            fingerprint_buffers.push(scratch.path_id_by_owner_hir.buffer);
            fingerprint_buffers.push(scratch.decl_type_key_to_decl_id.buffer);
            fingerprint_buffers.push(scratch.decl_value_key_to_decl_id.buffer);
            fingerprint_buffers.push(scratch.resolved_type_decl.buffer);
            fingerprint_buffers.push(scratch.resolved_value_decl.buffer);
            fingerprint_buffers.push(scratch.resolved_type_status.buffer);
            fingerprint_buffers.push(scratch.resolved_value_status.buffer);
            fingerprint_buffers.push(scratch.path_start.buffer);
            fingerprint_buffers.push(scratch.path_len.buffer);
            fingerprint_buffers.push(scratch.path_segment_count.buffer);
            fingerprint_buffers.push(scratch.path_segment_base.buffer);
            fingerprint_buffers.push(scratch.path_segment_name_id.buffer);
            fingerprint_buffers.push(scratch.path_segment_token.buffer);
            fingerprint_buffers.push(scratch.path_owner_hir.buffer);
            fingerprint_buffers.push(scratch.path_owner_token.buffer);
            fingerprint_buffers.push(scratch.path_owner_module_id.buffer);
            fingerprint_buffers.push(scratch.path_kind.buffer);
        }
        if let Some(scratch) = module_path_scratch {
            fingerprint_buffers.push(scratch.path_id_by_owner_hir.buffer);
            fingerprint_buffers.push(scratch.decl_type_key_to_decl_id.buffer);
            fingerprint_buffers.push(scratch.decl_value_key_to_decl_id.buffer);
            fingerprint_buffers.push(scratch.resolved_type_decl.buffer);
            fingerprint_buffers.push(scratch.resolved_value_decl.buffer);
            fingerprint_buffers.push(scratch.resolved_type_status.buffer);
            fingerprint_buffers.push(scratch.resolved_value_status.buffer);
            fingerprint_buffers.push(scratch.path_start.buffer);
            fingerprint_buffers.push(scratch.path_len.buffer);
            fingerprint_buffers.push(scratch.path_segment_count.buffer);
            fingerprint_buffers.push(scratch.path_segment_base.buffer);
            fingerprint_buffers.push(scratch.path_segment_name_id.buffer);
            fingerprint_buffers.push(scratch.path_segment_token.buffer);
            fingerprint_buffers.push(scratch.path_owner_hir.buffer);
            fingerprint_buffers.push(scratch.path_owner_token.buffer);
            fingerprint_buffers.push(scratch.path_owner_module_id.buffer);
            fingerprint_buffers.push(scratch.path_kind.buffer);
        }
        if let Some(dependencies) = dependency_interfaces {
            fingerprint_buffers.push(&dependencies.counts);
            fingerprint_buffers.push(&dependencies.module_library_id);
            fingerprint_buffers.push(&dependencies.module_unit_id);
            fingerprint_buffers.push(&dependencies.module_local_index);
            fingerprint_buffers.push(&dependencies.module_words);
            fingerprint_buffers.push(&dependencies.module_segment_words);
            fingerprint_buffers.push(&dependencies.declaration_library_id);
            fingerprint_buffers.push(&dependencies.declaration_unit_id);
            fingerprint_buffers.push(&dependencies.declaration_local_index);
            fingerprint_buffers.push(&dependencies.declaration_words);
            fingerprint_buffers.push(&dependencies.type_words);
            fingerprint_buffers.push(&dependencies.type_edge_words);
            fingerprint_buffers.push(&dependencies.member_words);
            fingerprint_buffers.push(&dependencies.name_byte_words);
            fingerprint_buffers.push(&dependencies.module_lookup);
        }
        let input_fingerprint = buffer_fingerprint(&fingerprint_buffers);
        let module_record_capacity = hir_items
            .map(|items| items.module_record_capacity)
            .unwrap_or(token_capacity)
            .max(1);
        let call_param_row_capacity = hir_items
            .map(|items| items.call_param_row_capacity)
            .unwrap_or(hir_node_capacity)
            .max(1);
        let call_arg_row_capacity = hir_items
            .map(|items| items.call_arg_row_capacity)
            .unwrap_or(hir_node_capacity)
            .max(1);
        let parser_feature_flags = hir_items
            .map(|items| items.parser_feature_flags)
            .unwrap_or(u32::MAX);
        let cache_key = ResidentTypeCheckCacheKey {
            source_file_capacity,
            token_capacity,
            hir_node_capacity,
            parser_hir_node_capacity,
            module_record_capacity,
            call_param_row_capacity,
            call_arg_row_capacity,
            parser_feature_flags,
            input_fingerprint,
            uses_hir_items,
        };

        let mut debug_semantic_rows = None;
        {
            let mut resident_state_guard = self
                .resident_state
                .lock()
                .expect("GpuTypeChecker.resident_state poisoned");
            let needs_rebuild = resident_state_guard
                .as_ref()
                .map(|state| !state.can_reuse_for(cache_key))
                .unwrap_or(true);
            let rebuilt = needs_rebuild;
            if needs_rebuild {
                *resident_state_guard = Some(self.create_resident_state(
                    device,
                    source_len,
                    source_file_capacity,
                    token_capacity,
                    token_buf,
                    token_count_buf,
                    token_file_id_buf,
                    source_buf,
                    hir_node_capacity,
                    parser_hir_node_capacity,
                    hir_kind_buf,
                    hir_token_pos_buf,
                    hir_token_end_buf,
                    hir_token_file_id_buf,
                    hir_status_buf,
                    hir_items,
                    &self.passes,
                    input_fingerprint,
                    uses_hir_items,
                    module_path_scratch,
                    dependency_interfaces,
                )?);
            }
            host_timer.stamp(if rebuilt {
                "resident_state_rebuilt"
            } else {
                "resident_state_reused"
            });
            let bind_groups = resident_state_guard
                .as_ref()
                .expect("resident type-check state must exist");
            let method_compact_dispatch_args = bind_groups
                .typecheck_graph
                .u32_buffer("method_compact_dispatch_args")?;
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
            if let Some(predicates) = &bind_groups.predicates {
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/predicates/00a_clear_syntax_tokens"),
                    &predicates.clear_syntax_tokens,
                    "type_check.resident.predicates_clear_syntax_tokens.pass",
                    &bind_groups.token_active_dispatch_args,
                )?;
            }
            if let Some(module_path) = &bind_groups.module_path {
                record_module_path_state_with_passes(
                    &self.passes,
                    encoder,
                    module_path,
                    &bind_groups.hir_active_dispatch_args,
                    &bind_groups.token_hir_active_dispatch_args,
                    timer.as_deref_mut(),
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.module_paths.done");
                }
            }
            host_timer.stamp("module_paths");
            record_compute(
                encoder,
                &self.passes.kernel("type_checker/type/instances/00_clear"),
                &bind_groups.type_instances.clear,
                "type_check.resident.type_instances_clear.pass",
                token_capacity.max(hir_node_capacity),
            )?;
            if let Some(dependency_visibility) = bind_groups
                .module_path
                .as_ref()
                .and_then(|module_path| module_path.dependency_visibility.as_ref())
            {
                // The shared type-instance clear resets token-indexed refs.
                // Re-publish canonical dependency refs before collection so
                // imported nominal types cannot be reclassified as unresolved
                // local generic parameters.
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/dependencies/11_project_types"),
                    &dependency_visibility.project_types_group,
                    "type_check.dependencies.project_types.after_type_clear",
                    &bind_groups
                        .module_path
                        .as_ref()
                        .expect("dependency visibility requires module paths")
                        .path_dispatch_args,
                )?;
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
            if let Some(module_path) = &bind_groups.module_path {
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
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances.done");
            }
            if let Some(module_path) = &bind_groups.module_path {
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
            if aliases_required && let Some(module_path) = &bind_groups.module_path {
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
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/01i_mark_semantic_type_rows"),
                    &bind_groups.type_instances.mark_semantic_type_rows,
                    "type_check.type_instances.mark_semantic_type_rows",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                bind_groups
                    .type_instances
                    .semantic_type_scan
                    .record(encoder)?;
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/type/instances/01j_scatter_semantic_type_rows"),
                    &bind_groups.type_instances.scatter_semantic_type_rows,
                    "type_check.type_instances.scatter_semantic_type_rows",
                    &bind_groups.hir_active_dispatch_args,
                )?;
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
            bind_groups.calls.record_primary(
                encoder,
                &bind_groups.hir_active_dispatch_args,
                bind_groups
                    .module_path
                    .as_ref()
                    .and_then(|module_path| module_path.dependency_visibility.as_ref())
                    .map(|dependency| {
                        (
                            self.passes
                                .kernel("type_checker/dependencies/07_project_calls"),
                            &dependency.project_calls_group,
                            self.passes
                                .kernel("type_checker/dependencies/07a_project_call_params"),
                            &dependency.project_call_params_group,
                            self.passes
                                .kernel("type_checker/dependencies/07b_scatter_call_params"),
                            &dependency.scatter_call_params_group,
                        )
                    }),
            )?;
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
            if struct_field_key_passes_required(bind_groups.cache_key.parser_feature_flags) {
                record_struct_field_key_passes_with_passes(
                    &self.passes,
                    encoder,
                    &bind_groups.type_instances,
                    &bind_groups.hir_active_dispatch_args,
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
            if matches_required && let Some(module_path) = &bind_groups.module_path {
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
            }
            if let Some(module_path) = &bind_groups.module_path {
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
            }
            if methods_required {
                bind_groups.methods.keys.record(encoder)?;
                bind_groups.methods.record_call_resolution(encoder)?;
            }
            bind_groups.calls.project_result_instances.record(encoder)?;
            bind_groups.calls.argument_matching.record(encoder)?;
            bind_groups.calls.apply_row_args.record(encoder)?;
            if let Some(module_path) = &bind_groups.module_path {
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
            }
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
            if let Some(module_path) = &bind_groups.module_path {
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
            }
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
                bind_groups.calls.generic_claim_validation.record(encoder)?;
                if let Some(dependency_visibility) = bind_groups
                    .module_path
                    .as_ref()
                    .and_then(|module_path| module_path.dependency_visibility.as_ref())
                {
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
            if arrays_required {
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
            if let Some(predicates) = &bind_groups.predicates {
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
                record_predicate_method_contract_keys_with_passes(
                    &self.passes,
                    encoder,
                    &predicate_hir_dispatch_args,
                    predicates,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.predicates_method_contract_keys.done");
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
                record_predicate_bind_groups_with_passes(&self.passes, encoder, predicates)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.predicates_keys.done");
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
            }
            record_compute(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/semantic/artifact/00_predicate_diagnostics_clear"),
                &bind_groups.semantic_predicate_diagnostics_clear,
                "type_check.semantic_artifact.predicate_diagnostics.clear",
                hir_node_capacity,
            )?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/semantic/artifact/01_predicate_diagnostics_claim"),
                &bind_groups.semantic_predicate_diagnostics_claim,
                "type_check.semantic_artifact.predicate_diagnostics.claim",
                &bind_groups.hir_active_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/semantic/artifact/02_predicate_diagnostics"),
                &bind_groups.semantic_predicate_diagnostics_project,
                "type_check.semantic_artifact.predicate_diagnostics",
                &bind_groups.hir_active_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self.passes.kernel("type_checker/returns/00_clear"),
                &bind_groups.returns_clear,
                "type_check.resident.returns_clear.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self.passes.kernel("type_checker/returns/01_mark"),
                &bind_groups.returns_mark,
                "type_check.resident.returns_mark.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self.passes.kernel("type_checker/returns/02_mark_if"),
                &bind_groups.returns_mark_if,
                "type_check.resident.returns_mark_if.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            // One ordered propagation step lets a direct nested if/else mark
            // its enclosing block before an outer direct if/else consumes it.
            record_compute_indirect(
                encoder,
                &self.passes.kernel("type_checker/returns/02_mark_if"),
                &bind_groups.returns_mark_if,
                "type_check.resident.returns_mark_if.propagate.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self.passes.kernel("type_checker/returns/03_validate"),
                &bind_groups.returns_validate,
                "type_check.resident.returns_validate.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.returns.done");
            }
            if let Some(dependency_visibility) = bind_groups
                .module_path
                .as_ref()
                .and_then(|module_path| module_path.dependency_visibility.as_ref())
            {
                // Argument and return comparison requests share a dense-HIR
                // request domain. Clear the count column once before the two
                // ordered scatter passes publish live requests.
                encoder.clear_buffer(
                    &dependency_visibility.call_compare_scan_input.buffer,
                    0,
                    None,
                );
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/dependencies/08_validate_call_args"),
                    &dependency_visibility.validate_call_args_group,
                    "type_check.dependencies.validate_call_args",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/dependencies/08a_validate_call_results"),
                    &dependency_visibility.validate_call_results_group,
                    "type_check.dependencies.validate_call_results.substitute",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                // The shader's call lanes publish inferred dependency return
                // substitutions. A second ordered dispatch lets return lanes
                // consume those substitutions without a cross-workgroup race.
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/dependencies/08a_validate_call_results"),
                    &dependency_visibility.validate_call_results_group,
                    "type_check.dependencies.validate_call_results.validate",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                dependency_visibility.call_compare_scan.record(encoder)?;
                record_compute(
                    encoder,
                    &self.passes.kernel("type_checker/count/dispatch_args"),
                    &dependency_visibility.call_compare_dispatch_group,
                    "type_check.dependencies.call_compare_dispatch_args",
                    1,
                )?;
                record_compute_indirect(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/dependencies/08b_validate_call_type_args"),
                    &dependency_visibility.validate_call_type_args_group,
                    "type_check.dependencies.validate_call_type_args",
                    &dependency_visibility.call_compare_dispatch_args,
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
            if arrays_required {
                record_compute(
                    encoder,
                    &self
                        .passes
                        .kernel("type_checker/semantic/artifact/01b_array_index_refs"),
                    &bind_groups.semantic_array_index_refs_project,
                    "type_check.semantic_artifact.array_index_refs",
                    hir_node_capacity,
                )?;
            }
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
            record_compute(
                encoder,
                &self.passes.kernel("type_checker/conditions/compact_calls"),
                &bind_groups.conditions_compact_calls,
                "type_check.conditions.compact_calls",
                hir_node_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.kernel("type_checker/conditions/compact_types"),
                &bind_groups.conditions_compact_types,
                "type_check.conditions.compact_types",
                hir_node_capacity,
            )?;
            record_compute_indirect(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/conditions/compact_methods"),
                &bind_groups.conditions_compact_methods,
                "type_check.conditions.compact_methods",
                &method_compact_dispatch_args,
            )?;
            record_compute(
                encoder,
                &self
                    .passes
                    .kernel("type_checker/conditions/compact_predicates"),
                &bind_groups.conditions_compact_predicates,
                "type_check.conditions.compact_predicates",
                hir_node_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.kernel("type_checker/conditions/compact_names"),
                &bind_groups.conditions_compact_names,
                "type_check.conditions.compact_names",
                hir_node_capacity,
            )?;
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
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.semantic_artifact.done");
            }
            if std::env::var_os("LANIUS_DEBUG_SEMANTIC_ROWS").is_some()
                && let Some(items) = hir_items
            {
                let semantic_calls_by_hir = bind_groups
                    .typecheck_graph
                    .buffer::<GpuCheckedCallArtifact>("semantic_calls_by_hir")?;
                let call_fn_index = bind_groups.typecheck_graph.u32_buffer("call_fn_index")?;
                let backend_call_fn_index = bind_groups
                    .typecheck_graph
                    .u32_buffer("backend_call_fn_index")?;
                let call_return_type =
                    bind_groups.typecheck_graph.u32_buffer("call_return_type")?;
                let hir_rows = hir_node_capacity
                    .min((items.hir.core.size() / 16) as u32)
                    .min((items.hir.payload.size() / 16) as u32)
                    .min((bind_groups.compact_expr_scalar_type.size() / 4) as u32)
                    .min((semantic_calls_by_hir.size() / 32) as u32)
                    .min(256);
                let token_rows = token_capacity
                    .min((call_fn_index.size() / 4) as u32)
                    .min((backend_call_fn_index.size() / 4) as u32)
                    .min((call_return_type.size() / 4) as u32)
                    .min(256);
                let hir_words = hir_rows as u64 * 17;
                let total_words = hir_words + token_rows as u64 * 4;
                let buffer = readback_u32s(
                    device,
                    "rb.type_check.semantic_rows",
                    total_words.max(1) as usize,
                );
                let mut word_offset = 0u64;
                let mut copy_words = |source: &wgpu::Buffer, words: u64| {
                    if words != 0 {
                        encoder.copy_buffer_to_buffer(
                            source,
                            0,
                            &buffer,
                            word_offset * 4,
                            words * 4,
                        );
                    }
                    word_offset += words;
                };
                copy_words(&items.hir.core, hir_rows as u64 * 4);
                copy_words(&items.hir.payload, hir_rows as u64 * 4);
                copy_words(&bind_groups.compact_expr_scalar_type, hir_rows as u64);
                copy_words(&semantic_calls_by_hir, hir_rows as u64 * 8);
                copy_words(&call_fn_index, token_rows as u64);
                copy_words(&backend_call_fn_index, token_rows as u64);
                copy_words(&call_return_type, token_rows as u64);
                copy_words(&bind_groups.name_id_by_token, token_rows as u64);
                debug_semantic_rows = Some(TypeCheckSemanticDebugReadback {
                    buffer,
                    hir_rows,
                    token_rows,
                });
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
        Ok(RecordedTypeCheck {
            debug_semantic_rows,
        })
    }

    /// Reads the recorded status buffer and converts GPU status words to an
    /// accepted result or a typed rejection.
    pub fn finish_recorded_check(
        &self,
        device: &wgpu::Device,
        recorded: &RecordedTypeCheck,
    ) -> Result<(), GpuTypeCheckError> {
        let slice = self.status_readback.slice(..);
        crate::gpu::passes_core::map_readback_blocking(device, &slice, "type_check.status")?;
        let mapped = slice.get_mapped_range();
        let words = read_status_words(&mapped)?;
        drop(mapped);
        self.status_readback.unmap();

        if let Some(debug) = &recorded.debug_semantic_rows {
            let slice = debug.buffer.slice(..);
            crate::gpu::passes_core::map_readback_blocking(
                device,
                &slice,
                "type_check.semantic_rows",
            )?;
            let mapped = slice.get_mapped_range();
            let values = mapped
                .chunks_exact(4)
                .map(|bytes| u32::from_le_bytes(bytes.try_into().expect("u32 word")))
                .collect::<Vec<_>>();
            let hir = debug.hir_rows as usize;
            let core_base = 0;
            let payload_base = hir * 4;
            let scalar_base = payload_base + hir * 4;
            let call_base = scalar_base + hir;
            eprintln!("[typecheck.semantic_rows] hir_rows={hir}");
            for row in 0..hir {
                let core = &values[core_base + row * 4..core_base + row * 4 + 4];
                if core[0] == 0 || core[0] == u32::MAX {
                    continue;
                }
                let payload = &values[payload_base + row * 4..payload_base + row * 4 + 4];
                let call = &values[call_base + row * 8..call_base + row * 8 + 8];
                eprintln!(
                    "[typecheck.semantic_rows] hir[{row}] core={core:?} payload={payload:?} scalar={:#010x} call={call:?}",
                    values[scalar_base + row]
                );
            }
            let token_base = call_base + hir * 8;
            let tokens = debug.token_rows as usize;
            let backend_base = token_base + tokens;
            let return_base = backend_base + tokens;
            let name_base = return_base + tokens;
            for token in 0..tokens {
                let semantic_target = values[token_base + token];
                let backend_target = values[backend_base + token];
                let return_type = values[return_base + token];
                let name_id = values[name_base + token];
                if semantic_target != u32::MAX
                    || backend_target != u32::MAX
                    || return_type != 0
                    || name_id != u32::MAX
                {
                    eprintln!(
                        "[typecheck.semantic_rows] token[{token}] name_id={name_id} semantic_target={semantic_target} backend_target={backend_target} return_type={return_type}"
                    );
                }
            }
            drop(mapped);
            debug.buffer.unmap();
        }

        if std::env::var_os("LANIUS_DEBUG_STAGE_ERRORS").is_some() {
            eprintln!("GPU type-check status words: {words:?}");
        }

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
            .resident_state
            .lock()
            .expect("GpuTypeChecker.resident_state poisoned");
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
            .resident_state
            .lock()
            .expect("GpuTypeChecker.resident_state poisoned");
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
            .resident_state
            .lock()
            .expect("GpuTypeChecker.resident_state poisoned");
        let state = guard.as_ref()?;
        let enclosing_fn = state.typecheck_graph.u32_buffer("enclosing_fn").ok()?;
        Some(consume(&enclosing_fn))
    }

    /// Clones allocation-preserving handles for the compact checked artifact.
    /// Backend recording owns this boundary independently of the resident
    /// frontend workspace and cannot observe token-indexed type-check state.
    pub(crate) fn semantic_artifact(&self) -> Option<OwnedGpuSemanticArtifact> {
        let guard = self
            .resident_state
            .lock()
            .expect("GpuTypeChecker.resident_state poisoned");
        let state = guard.as_ref()?;
        let module_path = state.module_path.as_ref()?;
        Some(OwnedGpuSemanticArtifact {
            value_decl_by_hir: state
                .typecheck_graph
                .buffer("semantic_value_decl_by_hir")
                .ok()?,
            value_type_by_hir: state
                .typecheck_graph
                .buffer("semantic_value_type_by_hir")
                .ok()?,
            param_type_by_row: state
                .typecheck_graph
                .buffer("semantic_param_type_by_row")
                .ok()?,
            enclosing_fn_by_hir: state
                .typecheck_graph
                .buffer("semantic_enclosing_fn_by_hir")
                .ok()?,
            function_return_type_by_hir: state
                .typecheck_graph
                .buffer("semantic_function_return_type_by_hir")
                .ok()?,
            function_entrypoint_by_hir: state
                .typecheck_graph
                .buffer("semantic_function_entrypoint_by_hir")
                .ok()?,
            function_host_service_by_hir: state
                .typecheck_graph
                .buffer("semantic_function_host_service_by_hir")
                .ok()?,
            control_depth_by_hir: state
                .typecheck_graph
                .buffer("semantic_control_depth_by_hir")
                .ok()?,
            calls_by_hir: state.typecheck_graph.buffer("semantic_calls_by_hir").ok()?,
            expr_ref_tag_by_hir: state
                .typecheck_graph
                .buffer("semantic_expr_ref_tag_by_hir")
                .ok()?,
            expr_ref_payload_by_hir: state
                .typecheck_graph
                .buffer("semantic_expr_ref_payload_by_hir")
                .ok()?,
            array_length_by_hir: state
                .typecheck_graph
                .buffer("semantic_array_length_by_hir")
                .ok()?,
            member_field_ordinal_by_hir: state
                .typecheck_graph
                .buffer("semantic_member_field_ordinal_by_hir")
                .ok()?,
            compact_expr_scalar_type: state.compact_expr_scalar_type.clone(),
            public_decl_index_by_hir: module_path.interface_public_decl_index_by_hir.clone(),
            struct_init_field_ordinal_by_row: state
                .typecheck_graph
                .buffer("struct_init_field_ordinal_by_row")
                .ok()?,
        })
    }

    /// Borrows the stable-identity and typed-root tables needed by the
    /// source-pack semantic-interface exporter.
    pub fn with_semantic_interface_identity_buffers<R>(
        &self,
        consume: impl FnOnce(GpuSemanticInterfaceIdentityBuffers<'_>) -> R,
    ) -> Option<R> {
        let guard = self
            .resident_state
            .lock()
            .expect("GpuTypeChecker.resident_state poisoned");
        let state = guard.as_ref()?;
        let module_path = state.module_path.as_ref()?;
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
        Some(consume(GpuSemanticInterfaceIdentityBuffers {
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
            public_decl_count: &module_path.interface_public_decl_count,
            public_decl_local_id: &module_path.interface_public_decl_local_id,
            public_decl_index_by_local: &module_path.interface_public_decl_index_by_local,
            public_decl_index_by_hir: &module_path.interface_public_decl_index_by_hir,
            type_expr_ref_tag: &type_expr_ref_tag,
            type_expr_ref_payload: &type_expr_ref_payload,
            type_generic_param_slot_by_token: &type_generic_param_slot_by_token,
            type_const_param_slot_by_token: &type_const_param_slot_by_token,
            type_instance_decl_token: &state.type_instance_decl_token,
            type_instance_external_canonical: &state.type_instance_external_canonical,
            dependency_type_count: module_path
                .dependency_interfaces
                .as_ref()
                .map_or(0, |dependencies| dependencies.type_count),
            dependency_type_words: module_path
                .dependency_interfaces
                .as_ref()
                .map_or(&state.type_instance_external_canonical, |dependencies| {
                    &dependencies.type_words
                }),
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
            .resident_state
            .lock()
            .expect("GpuTypeChecker.resident_state poisoned");
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
