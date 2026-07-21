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
        &passes.type_aliases.clear_forwarding,
        &aliases.clear_forwarding,
        "type_check.modules.clear_type_alias_forwarding",
        module_path.n_blocks.saturating_mul(256),
    )?;
    record_compute_indirect(
        encoder,
        &passes.type_aliases.init_forwarding,
        &aliases.init_forwarding,
        "type_check.modules.init_type_alias_forwarding",
        &module_path.decl_key_radix_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.type_aliases.validate_forwarding_args,
        &aliases.validate_forwarding_args,
        "type_check.modules.validate_type_alias_forwarding_args",
        module_path.n_blocks.saturating_mul(256),
    )?;
    record_compute_indirect(
        encoder,
        &passes.type_aliases.init_roots,
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
            &passes.type_aliases.jump_roots,
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
        &passes.type_aliases.clear_equivalence,
        &aliases.clear_equivalence,
        "type_check.modules.clear_type_alias_equivalence",
        graph_work,
    )?;
    record_compute_indirect(
        encoder,
        &passes.type_aliases.init_decl_edges,
        &aliases.init_decl_edges,
        "type_check.modules.init_type_alias_decl_edges",
        &module_path.decl_key_radix_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.type_aliases.init_arg_edges,
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
            &passes.type_aliases.hook_equivalence,
            hook,
            "type_check.modules.hook_type_alias_equivalence",
            hir_work,
        )?;
        record_compute(
            encoder,
            &passes.type_aliases.jump_equivalence,
            jump,
            "type_check.modules.jump_type_alias_equivalence",
            graph_work,
        )?;
    }
    record_compute(
        encoder,
        &passes.type_aliases.select_generic_sources,
        &aliases.select_generic_sources,
        "type_check.modules.select_type_alias_generic_sources",
        hir_work,
    )?;
    record_compute(
        encoder,
        &passes.type_aliases.select_concrete_sources,
        &aliases.select_concrete_sources,
        "type_check.modules.select_type_alias_concrete_sources",
        hir_work,
    )?;
    record_compute_indirect(
        encoder,
        &passes.type_aliases.finalize_equivalence,
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
        &passes.type_aliases.project,
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
    record_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        bind_groups.type_subtree_compare_scan_n_blocks,
        &bind_groups.aggregate_compare_dispatch_args,
        &bind_groups.type_subtree_compare_scan,
        "type_check.conditions.type_subtree_compare_scan",
    )?;
    record_compute(
        encoder,
        &passes.count_dispatch_args,
        &bind_groups.type_subtree_compare_dispatch,
        "type_check.conditions.type_subtree_compare_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.conditions_type_subtree,
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
        let passes = TypeCheckPasses::new(device)?;
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

    /// Records resident type checking with parser-owned HIR metadata and a
    /// canonical dependency-interface batch for one bounded compilation unit.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn record_resident_token_buffer_with_hir_items_and_dependencies_on_gpu(
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
            None,
            dependency_interfaces,
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
            fingerprint_buffers.push(items.compact_hir_count);
            fingerprint_buffers.push(items.compact_hir_core);
            fingerprint_buffers.push(items.compact_hir_links);
            fingerprint_buffers.push(items.compact_hir_payload);
            fingerprint_buffers.push(items.compact_const_type);
            fingerprint_buffers.push(items.compact_type_arg_count);
            fingerprint_buffers.push(items.compact_type_args);
            fingerprint_buffers.push(items.compact_type_arg_ranges);
            fingerprint_buffers.push(items.compact_field_count);
            fingerprint_buffers.push(items.compact_fields);
            fingerprint_buffers.push(items.compact_variant_count);
            fingerprint_buffers.push(items.compact_variants);
            fingerprint_buffers.push(items.compact_variant_payload_start);
            fingerprint_buffers.push(items.compact_variant_payload_count);
            fingerprint_buffers.push(items.compact_variant_payload_row_count);
            fingerprint_buffers.push(items.compact_variant_payloads);
            fingerprint_buffers.push(items.compact_array_element_start);
            fingerprint_buffers.push(items.compact_array_element_count);
            fingerprint_buffers.push(items.compact_array_element_row_count);
            fingerprint_buffers.push(items.compact_array_elements);
            fingerprint_buffers.push(items.semantic_dense_node);
            fingerprint_buffers.push(items.semantic_count);
            fingerprint_buffers.push(items.semantic_subtree_end);
            fingerprint_buffers.push(items.type_root_owner);
            fingerprint_buffers.push(items.nearest_enclosing_control_node);
            fingerprint_buffers.push(items.nearest_loop_node);
        }
        if let Some(scratch) = external_scratch {
            fingerprint_buffers.push(scratch.fn_entrypoint_tag);
            fingerprint_buffers.push(scratch.type_expr_ref_tag);
            fingerprint_buffers.push(scratch.type_expr_ref_payload);
            fingerprint_buffers.push(scratch.type_generic_param_slot_by_token);
            fingerprint_buffers.push(scratch.type_const_param_slot_by_token);
            if let Some(record_family_flag) = scratch.record_family_flag {
                fingerprint_buffers.push(record_family_flag);
            }
            fingerprint_buffers.push(scratch.module_record_prefix);
            fingerprint_buffers.push(scratch.record_scan_local_prefix);
            fingerprint_buffers.push(scratch.path_id_by_owner_hir);
            fingerprint_buffers.push(scratch.call_param_count);
            fingerprint_buffers.push(scratch.call_param_type);
            fingerprint_buffers.push(scratch.call_arg_record);
            fingerprint_buffers.push(scratch.function_lookup_key);
            fingerprint_buffers.push(scratch.function_lookup_fn);
            fingerprint_buffers.push(scratch.type_decl_generic_param_count);
            fingerprint_buffers.push(scratch.type_decl_generic_param_count_by_owner_token);
            fingerprint_buffers.push(scratch.type_instance_arg_start);
            fingerprint_buffers.push(scratch.type_instance_arg_count);
            fingerprint_buffers.push(scratch.type_instance_arg_ref_tag);
            fingerprint_buffers.push(scratch.type_instance_arg_ref_payload);
            fingerprint_buffers.push(scratch.type_instance_elem_ref_tag);
            fingerprint_buffers.push(scratch.type_instance_elem_ref_payload);
            fingerprint_buffers.push(scratch.type_instance_len_kind);
            fingerprint_buffers.push(scratch.type_instance_len_payload);
            fingerprint_buffers.push(scratch.type_instance_state);
            fingerprint_buffers.push(scratch.decl_type_key_to_decl_id);
            fingerprint_buffers.push(scratch.decl_value_key_to_decl_id);
            fingerprint_buffers.push(scratch.method_decl_module_id);
            fingerprint_buffers.push(scratch.method_decl_method_row);
            fingerprint_buffers.push(scratch.method_decl_name_token);
            fingerprint_buffers.push(scratch.method_decl_name_id);
            fingerprint_buffers.push(scratch.method_decl_param_offset);
            fingerprint_buffers.push(scratch.method_decl_receiver_mode);
            fingerprint_buffers.push(scratch.method_decl_visibility);
            fingerprint_buffers.push(scratch.method_key_to_fn_token);
            fingerprint_buffers.push(scratch.method_key_status);
            fingerprint_buffers.push(scratch.method_key_radix_block_histogram);
            fingerprint_buffers.push(scratch.method_key_radix_block_bucket_prefix);
            fingerprint_buffers.push(scratch.method_call_receiver_ref_tag);
            fingerprint_buffers.push(scratch.method_call_receiver_ref_payload);
            fingerprint_buffers.push(scratch.method_call_name_id);
            fingerprint_buffers.push(scratch.method_call_site_module_id);
            fingerprint_buffers.push(scratch.import_visible_type_count);
            fingerprint_buffers.push(scratch.import_visible_value_count);
            fingerprint_buffers.push(scratch.import_visible_type_prefix);
            fingerprint_buffers.push(scratch.import_visible_value_prefix);
            fingerprint_buffers.push(scratch.resolved_type_decl);
            fingerprint_buffers.push(scratch.resolved_value_decl);
            fingerprint_buffers.push(scratch.resolved_type_status);
            fingerprint_buffers.push(scratch.resolved_value_status);
            fingerprint_buffers.push(scratch.member_result_ref_payload);
            fingerprint_buffers.push(scratch.member_result_field_ordinal);
            fingerprint_buffers.push(scratch.struct_init_field_expected_ref_tag);
            fingerprint_buffers.push(scratch.struct_init_field_expected_ref_payload);
            fingerprint_buffers.push(scratch.struct_init_field_context_instance);
            fingerprint_buffers.push(scratch.struct_init_field_ordinal);
            fingerprint_buffers.push(scratch.path_start);
            fingerprint_buffers.push(scratch.path_len);
            fingerprint_buffers.push(scratch.path_segment_count);
            fingerprint_buffers.push(scratch.path_segment_base);
            fingerprint_buffers.push(scratch.path_segment_name_id);
            fingerprint_buffers.push(scratch.path_segment_token);
            fingerprint_buffers.push(scratch.path_owner_hir);
            fingerprint_buffers.push(scratch.path_owner_token);
            fingerprint_buffers.push(scratch.path_owner_module_id);
            fingerprint_buffers.push(scratch.path_kind);
        }
        if let Some(scratch) = module_path_scratch {
            fingerprint_buffers.push(scratch.module_record_prefix);
            fingerprint_buffers.push(scratch.record_scan_local_prefix);
            fingerprint_buffers.push(scratch.module_path_key_radix_block_histogram);
            fingerprint_buffers.push(scratch.module_path_key_radix_block_bucket_prefix);
            fingerprint_buffers.push(scratch.path_id_by_owner_hir);
            fingerprint_buffers.push(scratch.decl_module_file_id);
            fingerprint_buffers.push(scratch.decl_module_id);
            fingerprint_buffers.push(scratch.decl_name_id);
            fingerprint_buffers.push(scratch.decl_namespace);
            fingerprint_buffers.push(scratch.decl_visibility);
            fingerprint_buffers.push(scratch.decl_token_start);
            fingerprint_buffers.push(scratch.decl_token_end);
            fingerprint_buffers.push(scratch.decl_key_to_decl_id);
            fingerprint_buffers.push(scratch.decl_key_order_tmp);
            fingerprint_buffers.push(scratch.decl_status);
            fingerprint_buffers.push(scratch.decl_type_key_to_decl_id);
            fingerprint_buffers.push(scratch.decl_value_key_to_decl_id);
            fingerprint_buffers.push(scratch.import_visible_type_count);
            fingerprint_buffers.push(scratch.import_visible_value_count);
            fingerprint_buffers.push(scratch.import_visible_type_prefix);
            fingerprint_buffers.push(scratch.import_visible_value_prefix);
            fingerprint_buffers.push(scratch.resolved_type_decl);
            fingerprint_buffers.push(scratch.resolved_value_decl);
            fingerprint_buffers.push(scratch.resolved_type_status);
            fingerprint_buffers.push(scratch.resolved_value_status);
            fingerprint_buffers.push(scratch.path_start);
            fingerprint_buffers.push(scratch.path_len);
            fingerprint_buffers.push(scratch.path_segment_count);
            fingerprint_buffers.push(scratch.path_segment_base);
            fingerprint_buffers.push(scratch.path_segment_name_id);
            fingerprint_buffers.push(scratch.path_segment_token);
            fingerprint_buffers.push(scratch.path_owner_hir);
            fingerprint_buffers.push(scratch.path_owner_token);
            fingerprint_buffers.push(scratch.path_owner_module_id);
            fingerprint_buffers.push(scratch.path_kind);
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
                    external_scratch,
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
            let parser_feature_flags = bind_groups.cache_key.parser_feature_flags;
            let methods_required = method_passes_required(parser_feature_flags);
            let arrays_required = array_passes_required(parser_feature_flags);
            let structs_required = struct_init_passes_required(parser_feature_flags);
            let members_required = member_passes_required(parser_feature_flags);
            let enums_required = enum_passes_required(parser_feature_flags);
            let matches_required = match_passes_required(parser_feature_flags);
            let aggregates_required = aggregate_passes_required(parser_feature_flags);
            let aliases_required = type_alias_passes_required(parser_feature_flags);

            queue.write_buffer(
                &bind_groups.name_bind_groups.name_max_len,
                0,
                &0u32.to_le_bytes(),
            );
            record_compute(
                encoder,
                &self.passes.hir_active_dispatch_args,
                &bind_groups.hir_active_dispatch,
                "type_check.hir_active_dispatch_args",
                1,
            )?;
            record_typecheck_clear_buffer(encoder, &bind_groups.semantic_feature_flags, 0, Some(4));
            record_compute_indirect(
                encoder,
                &self.passes.semantic_features_collect,
                &bind_groups.semantic_features_collect,
                "type_check.semantic_features.collect",
                &bind_groups.hir_active_dispatch_args,
            )?;
            record_compute(
                encoder,
                &self.passes.semantic_features_dispatch_args,
                &bind_groups.semantic_features_dispatch_args,
                "type_check.semantic_features.dispatch_args",
                1,
            )?;
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
                    &self.passes.predicates_clear_syntax_tokens,
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
                &self.passes.type_instances_clear,
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
                    &self.passes.dependencies.canonical_types.project_types,
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
                record_typecheck_clear_buffer(
                    encoder,
                    &bind_groups.generic_param_count_out,
                    0,
                    Some(4),
                );
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
                    &self.passes.modules_project_type_paths,
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
                    &self.passes.modules_project_type_paths,
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
                    &self.passes.modules_project_type_instances,
                    &module_path.bind_groups.project_type_instances,
                    "type_check.modules.project_type_instances",
                    &module_path.path_dispatch_args,
                )?;
                if let Some(dependency_visibility) = &module_path.dependency_visibility {
                    record_compute_indirect(
                        encoder,
                        &self
                            .passes
                            .dependencies
                            .canonical_types
                            .project_type_instances,
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
                    &self.passes.modules_project_type_paths,
                    &module_path.bind_groups.project_type_paths,
                    "type_check.modules.project_type_paths.after_alias_equivalence",
                    &module_path.path_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.type_instances_project.done");
                }
            }
            record_counted_u32_scan_bind_groups_with_passes(
                &self.passes,
                encoder,
                bind_groups
                    .type_instances
                    .type_instance_arg_row_scan_n_blocks,
                &bind_groups.token_active_dispatch_args,
                &bind_groups.type_instances.type_instance_arg_row_scan,
                "type_check.type_instances.arg_row_scan",
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_arg_row_scan.done");
            }
            record_compute_indirect(
                encoder,
                &self.passes.type_instances_collect_named_arg_refs,
                &bind_groups.type_instances.collect_named_arg_refs,
                "type_check.resident.type_instances_collect_named_arg_refs.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            if aliases_required && let Some(module_path) = &bind_groups.module_path {
                record_compute_indirect(
                    encoder,
                    &self.passes.type_aliases.project_instances,
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
                &self.passes.type_instances_hash_arg_rows,
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
                    &self.passes.type_instances_clear_semantic_type_rows,
                    &bind_groups.type_instances.clear_semantic_type_rows,
                    "type_check.type_instances.clear_semantic_type_rows",
                    token_capacity
                        .saturating_add(LANGUAGE_SYMBOL_COUNT)
                        .max(hir_node_capacity),
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.type_instances_mark_semantic_type_rows,
                    &bind_groups.type_instances.mark_semantic_type_rows,
                    "type_check.type_instances.mark_semantic_type_rows",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                record_counted_u32_scan_bind_groups_with_passes(
                    &self.passes,
                    encoder,
                    bind_groups.type_instances.semantic_type_scan_n_blocks,
                    &bind_groups.hir_active_dispatch_args,
                    &bind_groups.type_instances.semantic_type_scan,
                    "type_check.type_instances.semantic_type_scan",
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.type_instances_scatter_semantic_type_rows,
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
            record_call_bind_groups_with_passes(
                &self.passes,
                encoder,
                token_capacity,
                bind_groups.cache_key.call_param_row_capacity,
                n_work,
                &bind_groups.token_active_dispatch_args,
                &bind_groups.hir_active_dispatch_args,
                &bind_groups.token_hir_active_dispatch_args,
                &bind_groups.calls,
                bind_groups
                    .module_path
                    .as_ref()
                    .and_then(|module_path| module_path.dependency_visibility.as_ref())
                    .map(|dependency| {
                        (
                            &self.passes.dependencies.project_calls,
                            &dependency.project_calls_group,
                            &self.passes.dependencies.project_call_params,
                            &dependency.project_call_params_group,
                            &self.passes.dependencies.scatter_call_params,
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
                &self.passes.type_instances_decl_refs,
                &bind_groups.type_instances.decl_refs,
                "type_check.resident.type_instances_decl_refs.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            // For-binding element refs consume iterable decl refs published by
            // the same HIR-indexed shader, so run a second fixed pass after the
            // direct decl facts are stable.
            record_compute_indirect(
                encoder,
                &self.passes.type_instances_decl_refs,
                &bind_groups.type_instances.decl_refs,
                "type_check.resident.type_instances_decl_refs.for_bindings.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_decl_refs.done");
            }
            record_method_clear_with_passes(
                &self.passes,
                encoder,
                &bind_groups.token_active_dispatch_args,
                &bind_groups.methods,
            )?;
            if methods_required {
                record_method_declaration_passes_with_passes(
                    &self.passes,
                    encoder,
                    &bind_groups.method_token_dispatch_args,
                    &bind_groups.method_compact_dispatch_args,
                    &bind_groups.method_hir_dispatch_args,
                    &bind_groups.methods,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.methods.done");
                }
            }
            if members_required {
                record_compute_indirect(
                    encoder,
                    &self.passes.type_instances_member_receivers,
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
                    &self.passes.type_instances_member_results,
                    &bind_groups.type_instances.member_results,
                    "type_check.resident.type_instances_member_results.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.member_results.done");
                }
                record_compute_indirect(
                    encoder,
                    &self.passes.type_instances_member_substitute,
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
                    &self.passes.type_instances_struct_init_clear,
                    &bind_groups.type_instances.struct_init_clear,
                    "type_check.resident.type_instances_struct_init_clear.pass",
                    token_capacity.max(hir_node_capacity),
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.struct_init_clear.done");
                }
                record_compute_indirect(
                    encoder,
                    &self.passes.type_instances_struct_init_contexts,
                    &bind_groups.type_instances.struct_init_contexts,
                    "type_check.resident.type_instances_struct_init_contexts.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.struct_init_contexts.done");
                }
                record_compute_indirect(
                    encoder,
                    &self.passes.type_instances_struct_init_fields,
                    &bind_groups.type_instances.struct_init_fields,
                    "type_check.resident.type_instances_struct_init_fields.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.struct_init_fields.done");
                }
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instance_fields.done");
            }
            host_timer.stamp("methods_member_struct_fields");
            if matches_required && let Some(module_path) = &bind_groups.module_path {
                record_compute_indirect(
                    encoder,
                    &self.passes.modules_bind_match_patterns,
                    &module_path.bind_groups.bind_match_patterns,
                    "type_check.modules.bind_match_patterns",
                    &bind_groups.match_hir_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.modules_type_match_payloads,
                    &module_path.bind_groups.type_match_payloads,
                    "type_check.modules.type_match_payloads",
                    &bind_groups.match_hir_dispatch_args,
                )?;
            }
            record_compute_indirect(
                encoder,
                &self.passes.scope_hir,
                &bind_groups.scope_hir,
                "type_check.resident.scope.pass",
                &bind_groups.token_active_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.scope.done");
            }
            record_compute_indirect(
                encoder,
                &self.passes.calls_resolve,
                &bind_groups.calls.resolve,
                "type_check.resident.calls_resolve.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls_resolve.done");
            }
            record_call_arg_matching_and_collect_with_passes(
                &self.passes,
                encoder,
                n_work,
                &bind_groups.calls,
                "type_check.resident.calls_collect_row_args.pass",
            )?;
            record_compute_indirect(
                encoder,
                &self.passes.calls_apply_row_args,
                &bind_groups.calls.apply_row_args,
                "type_check.resident.calls_apply_row_args.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls_row_args.done");
            }
            if methods_required {
                record_compute_indirect(
                    encoder,
                    &self.passes.methods_mark_call_keys,
                    &bind_groups.methods.mark_call_keys,
                    "type_check.methods.mark_call_keys_before_module_value_calls",
                    &bind_groups.method_token_hir_dispatch_args,
                )?;
            }
            if let Some(module_path) = &bind_groups.module_path {
                record_compute_indirect(
                    encoder,
                    &self.passes.modules_consume_value_calls,
                    &module_path.bind_groups.consume_value_calls,
                    "type_check.modules.consume_value_calls",
                    &module_path.path_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.modules_mirror_value_call_leaf,
                    &module_path.bind_groups.mirror_value_call_leaf,
                    "type_check.modules.mirror_value_call_leaf",
                    &module_path.path_dispatch_args,
                )?;
                record_call_arg_matching_and_collect_with_passes(
                    &self.passes,
                    encoder,
                    n_work,
                    &bind_groups.calls,
                    "type_check.resident.calls_collect_row_args_after_modules.pass",
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.calls_apply_row_args,
                    &bind_groups.calls.apply_row_args,
                    "type_check.resident.calls_apply_row_args_after_modules.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.modules_mirror_value_call_leaf,
                    &module_path.bind_groups.mirror_value_call_leaf,
                    "type_check.modules.mirror_value_call_leaf_after_module_row_args",
                    &module_path.path_dispatch_args,
                )?;
            }
            if methods_required {
                record_method_key_table_passes_with_passes(
                    &self.passes,
                    encoder,
                    &bind_groups.method_token_dispatch_args,
                    &bind_groups.method_radix_prefix_dispatch_args,
                    &bind_groups.method_radix_bases_dispatch_args,
                    &bind_groups.methods,
                )?;
                record_method_call_resolution_passes_with_passes(
                    &self.passes,
                    encoder,
                    &bind_groups.method_token_dispatch_args,
                    &bind_groups.method_token_hir_dispatch_args,
                    &bind_groups.method_hir_dispatch_args,
                    &bind_groups.methods,
                )?;
            }
            record_call_arg_matching_and_collect_with_passes(
                &self.passes,
                encoder,
                n_work,
                &bind_groups.calls,
                "type_check.resident.calls_collect_row_args_after_methods.pass",
            )?;
            record_compute_indirect(
                encoder,
                &self.passes.calls_apply_row_args,
                &bind_groups.calls.apply_row_args,
                "type_check.resident.calls_apply_row_args_after_methods.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            if let Some(module_path) = &bind_groups.module_path {
                record_compute_indirect(
                    encoder,
                    &self.passes.modules_consume_value_calls,
                    &module_path.bind_groups.consume_value_calls,
                    "type_check.modules.consume_value_calls_after_methods",
                    &module_path.path_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.modules_mirror_value_call_leaf,
                    &module_path.bind_groups.mirror_value_call_leaf,
                    "type_check.modules.mirror_value_call_leaf_after_methods",
                    &module_path.path_dispatch_args,
                )?;
                record_call_arg_matching_and_collect_with_passes(
                    &self.passes,
                    encoder,
                    n_work,
                    &bind_groups.calls,
                    "type_check.resident.calls_collect_row_args_after_methods_modules.pass",
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.calls_apply_row_args,
                    &bind_groups.calls.apply_row_args,
                    "type_check.resident.calls_apply_row_args_after_methods_modules.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.modules_mirror_value_call_leaf,
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
                    &self.passes.calls_infer_array_generics,
                    &bind_groups.calls.infer_array_generics,
                    "type_check.resident.calls_infer_array_generics.pass",
                    n_work,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.calls_infer_array_generics.done");
                }
                record_compute_indirect(
                    encoder,
                    &self.passes.calls_mark_array_args,
                    &bind_groups.calls.mark_array_args,
                    "type_check.resident.calls_mark_array_args.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.calls_mark_array_args.done");
                }
                record_compute(
                    encoder,
                    &self.passes.calls_validate_array_results,
                    &bind_groups.calls.validate_array_results,
                    "type_check.resident.calls_validate_array_results.pass",
                    n_work,
                )?;
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
                        &self.passes.modules_consume_value_enum_calls,
                        &module_path.bind_groups.consume_value_enum_calls,
                        "type_check.modules.consume_value_enum_calls",
                        &module_path.path_dispatch_args,
                    )?;
                    record_compute(
                        encoder,
                        &self.passes.modules_validate_value_enum_call_payloads,
                        &module_path.bind_groups.validate_value_enum_call_payloads,
                        "type_check.modules.validate_value_enum_call_payloads",
                        hir_node_capacity.saturating_mul(4).max(1),
                    )?;
                    record_compute_indirect(
                        encoder,
                        &self.passes.modules_finalize_value_enum_calls,
                        &module_path.bind_groups.finalize_value_enum_calls,
                        "type_check.modules.finalize_value_enum_calls",
                        &module_path.path_dispatch_args,
                    )?;
                }
                if matches_required {
                    record_compute_indirect(
                        encoder,
                        &self.passes.modules_type_match_exprs,
                        &module_path.bind_groups.type_match_exprs,
                        "type_check.modules.type_match_exprs",
                        &bind_groups.hir_active_dispatch_args,
                    )?;
                }
                record_compute_indirect(
                    encoder,
                    &self.passes.modules_consume_value_consts,
                    &module_path.bind_groups.consume_value_consts,
                    "type_check.modules.consume_value_consts",
                    &module_path.path_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.modules_consume_value_enum_units,
                    &module_path.bind_groups.consume_value_enum_units,
                    "type_check.modules.consume_value_enum_units",
                    &module_path.path_dispatch_args,
                )?;
            }
            if methods_required {
                record_compute_indirect(
                    encoder,
                    &self.passes.methods_resolve,
                    &bind_groups.methods.resolve,
                    "type_check.resident.methods.resolve",
                    &bind_groups.method_token_hir_dispatch_args,
                )?;
            }
            record_call_arg_matching_and_collect_with_passes(
                &self.passes,
                encoder,
                n_work,
                &bind_groups.calls,
                "type_check.resident.calls_collect_row_args_after_final_methods.pass",
            )?;
            if generic_call_claim_passes_required(bind_groups.cache_key.parser_feature_flags)
                || dependency_interfaces.is_some()
            {
                if aggregates_required {
                    record_compute_indirect(
                        encoder,
                        &self.passes.calls_clear_generic_claim_type_args,
                        &bind_groups.calls.clear_generic_claim_type_args,
                        "type_check.calls.clear_generic_claim_type_args",
                        &bind_groups.hir_active_dispatch_args,
                    )?;
                }
                record_call_generic_claim_validation_with_passes(
                    &self.passes,
                    encoder,
                    &bind_groups.hir_active_dispatch_args,
                    &bind_groups.calls,
                )?;
                if let Some(dependency_visibility) = bind_groups
                    .module_path
                    .as_ref()
                    .and_then(|module_path| module_path.dependency_visibility.as_ref())
                {
                    record_compute_indirect(
                        encoder,
                        &self.passes.dependencies.validate_call_results,
                        &dependency_visibility.validate_call_results_group,
                        "type_check.dependencies.resolve_generic_call_results",
                        &bind_groups.hir_active_dispatch_args,
                    )?;
                }
                if aggregates_required {
                    record_counted_u32_scan_bind_groups_with_passes(
                        &self.passes,
                        encoder,
                        bind_groups.aggregate_compare_scan_n_blocks,
                        &bind_groups.hir_active_dispatch_args,
                        &bind_groups.aggregate_compare_scan,
                        "type_check.calls.generic_claim_type_arg_scan",
                    )?;
                    record_compute(
                        encoder,
                        &self.passes.count_dispatch_args,
                        &bind_groups.aggregate_compare_dispatch,
                        "type_check.calls.generic_claim_type_arg_dispatch_args",
                        1,
                    )?;
                    record_compute_indirect(
                        encoder,
                        &self.passes.conditions_aggregate_args,
                        &bind_groups.conditions_aggregate_args,
                        "type_check.calls.validate_generic_claim_type_args",
                        &bind_groups.aggregate_compare_dispatch_args,
                    )?;
                    record_type_subtree_comparison_passes(&self.passes, encoder, bind_groups)?;
                }
            }
            record_compute_indirect(
                encoder,
                &self.passes.calls_apply_row_args,
                &bind_groups.calls.apply_row_args,
                "type_check.resident.calls_apply_row_args_after_final_methods.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
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
                record_compute_indirect(
                    encoder,
                    &self.passes.type_instances_array_index_results,
                    &bind_groups.type_instances.array_index_results,
                    "type_check.resident.type_instances_array_index_results.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.array_index_results.done");
                }
                if members_required {
                    record_compute_indirect(
                        encoder,
                        &self.passes.type_instances_member_receivers,
                        &bind_groups.type_instances.member_receivers,
                        "type_check.resident.type_instances_member_receivers_after_array_index.pass",
                        &bind_groups.hir_active_dispatch_args,
                    )?;
                    record_compute_indirect(
                        encoder,
                        &self.passes.type_instances_member_results,
                        &bind_groups.type_instances.member_results,
                        "type_check.resident.type_instances_member_results_after_array_index.pass",
                        &bind_groups.hir_active_dispatch_args,
                    )?;
                    record_compute_indirect(
                        encoder,
                        &self.passes.type_instances_member_substitute,
                        &bind_groups.type_instances.member_substitute,
                        "type_check.resident.type_instances_member_substitute_after_array_index.pass",
                        &bind_groups.token_active_dispatch_args,
                    )?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.members_after_array_index.done");
                    }
                }
                record_compute_indirect(
                    encoder,
                    &self.passes.type_instances_array_return_refs,
                    &bind_groups.type_instances.array_return_refs,
                    "type_check.resident.type_instances_array_return_refs.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.array_return_refs.done");
                }
                record_compute_indirect(
                    encoder,
                    &self.passes.type_instances_array_literal_return_refs,
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
                    &self.passes.type_instances_struct_init_substitute,
                    &bind_groups.type_instances.struct_init_substitute,
                    "type_check.resident.type_instances_struct_init_substitute.pass",
                    &bind_groups.token_active_dispatch_args,
                )?;
            }
            if methods_required {
                record_compute_indirect(
                    encoder,
                    &self.passes.methods_mark_call_keys,
                    &bind_groups.methods.mark_call_keys,
                    "type_check.methods.mark_call_keys_before_aggregate_validation",
                    &bind_groups.method_token_hir_dispatch_args,
                )?;
            }
            if aggregates_required {
                record_compute_indirect(
                    encoder,
                    &self.passes.type_instances_validate_aggregate_access,
                    &bind_groups.type_instances.validate_aggregate_access,
                    "type_check.resident.type_instances_validate_aggregate_access.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
            }
            if let Some(predicates) = &bind_groups.predicates {
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_clear_bound_arg_facts,
                    &predicates.clear_bound_arg_facts,
                    "type_check.resident.predicates_clear_bound_arg_facts.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_collect_bound_arg_facts,
                    &predicates.collect_bound_arg_facts,
                    "type_check.resident.predicates_collect_bound_arg_facts.pass",
                    &bind_groups.predicate_hir_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.predicates_bound_args.done");
                }
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_collect_method_contracts,
                    &predicates.collect_method_contracts,
                    "type_check.resident.predicates_collect_method_contracts.pass",
                    &bind_groups.predicate_hir_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.predicates_method_contracts.done");
                }
                record_predicate_method_contract_keys_with_passes(
                    &self.passes,
                    encoder,
                    &bind_groups.predicate_hir_dispatch_args,
                    &bind_groups.predicate_radix_prefix_dispatch_args,
                    &bind_groups.predicate_radix_bases_dispatch_args,
                    predicates,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.predicates_method_contract_keys.done");
                }
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_collect,
                    &predicates.collect,
                    "type_check.resident.predicates_collect.pass",
                    &bind_groups.predicate_hir_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_validate_bound_args,
                    &predicates.validate_bound_args,
                    "type_check.resident.predicates_validate_bound_args.pass",
                    &bind_groups.predicate_hir_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_collect_impls,
                    &predicates.collect_impls,
                    "type_check.resident.predicates_collect_impls.pass",
                    &bind_groups.predicate_hir_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_collect_methods,
                    &predicates.collect_methods,
                    "type_check.resident.predicates_collect_methods.pass",
                    &bind_groups.predicate_hir_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.predicates_collect.done");
                }
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_emit_method_validation_rows,
                    &predicates.emit_method_validation_rows,
                    "type_check.resident.predicates_emit_method_validation_rows.pass",
                    &bind_groups.predicate_hir_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_validate_method_type_arg_rows,
                    &predicates.validate_method_type_arg_rows,
                    "type_check.resident.predicates_validate_method_type_arg_rows.pass",
                    &bind_groups.predicate_hir_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_reduce_method_validation_errors,
                    &predicates.reduce_method_validation_errors,
                    "type_check.resident.predicates_reduce_method_validation_errors.pass",
                    &bind_groups.predicate_hir_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.predicates_method_validation_rows.done");
                }
                record_predicate_bind_groups_with_passes(
                    &self.passes,
                    encoder,
                    &bind_groups.predicate_hir_dispatch_args,
                    &bind_groups.predicate_radix_prefix_dispatch_args,
                    &bind_groups.predicate_radix_bases_dispatch_args,
                    predicates,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.predicates_keys.done");
                }
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_obligations,
                    &predicates.count_obligation_pairs,
                    "type_check.resident.predicates_count_obligation_pairs.pass",
                    &bind_groups.predicate_hir_dispatch_args,
                )?;
                record_counted_u32_scan_bind_groups_with_passes(
                    &self.passes,
                    encoder,
                    predicates.obligation_pair_scan_n_blocks,
                    &bind_groups.predicate_hir_dispatch_args,
                    &predicates.obligation_pair_scan,
                    "type_check.predicates.obligation_pair_scan",
                )?;
                record_typecheck_clear_buffer(
                    encoder,
                    &predicates.obligation_pair_dispatch_args,
                    0,
                    Some(12),
                );
                record_compute_indirect(
                    encoder,
                    &self.passes.count_dispatch_args,
                    &predicates.obligation_pair_dispatch,
                    "type_check.predicates.obligation_pair_dispatch_args",
                    &bind_groups.predicate_single_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_obligations,
                    &predicates.validate_obligation_pairs,
                    "type_check.resident.predicates_validate_obligation_pairs.pass",
                    &predicates.obligation_pair_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.predicates_obligations.done");
                }
            }
            record_compute_indirect(
                encoder,
                &self.passes.returns_clear,
                &bind_groups.returns_clear,
                "type_check.resident.returns_clear.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self.passes.returns_mark,
                &bind_groups.returns_mark,
                "type_check.resident.returns_mark.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self.passes.returns_mark_if,
                &bind_groups.returns_mark_if,
                "type_check.resident.returns_mark_if.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            // One ordered propagation step lets a direct nested if/else mark
            // its enclosing block before an outer direct if/else consumes it.
            record_compute_indirect(
                encoder,
                &self.passes.returns_mark_if,
                &bind_groups.returns_mark_if,
                "type_check.resident.returns_mark_if.propagate.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self.passes.returns_validate,
                &bind_groups.returns_validate,
                "type_check.resident.returns_validate.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.returns.done");
            }
            record_compute_indirect(
                encoder,
                &self.passes.conditions_hir,
                &bind_groups.conditions_hir,
                "type_check.resident.conditions_hir.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            if let Some(dependency_visibility) = bind_groups
                .module_path
                .as_ref()
                .and_then(|module_path| module_path.dependency_visibility.as_ref())
            {
                record_compute_indirect(
                    encoder,
                    &self.passes.dependencies.validate_call_args,
                    &dependency_visibility.validate_call_args_group,
                    "type_check.dependencies.validate_call_args",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.dependencies.validate_call_results,
                    &dependency_visibility.validate_call_results_group,
                    "type_check.dependencies.validate_call_results",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                record_counted_u32_scan_bind_groups_with_passes(
                    &self.passes,
                    encoder,
                    dependency_visibility.call_compare_scan_n_blocks,
                    &bind_groups.hir_active_dispatch_args,
                    &dependency_visibility.call_compare_scan,
                    "type_check.dependencies.call_compare_scan",
                )?;
                record_compute(
                    encoder,
                    &self.passes.count_dispatch_args,
                    &dependency_visibility.call_compare_dispatch_group,
                    "type_check.dependencies.call_compare_dispatch_args",
                    1,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.dependencies.validate_call_type_args,
                    &dependency_visibility.validate_call_type_args_group,
                    "type_check.dependencies.validate_call_type_args",
                    &dependency_visibility.call_compare_dispatch_args,
                )?;
            }
            if aggregates_required {
                record_counted_u32_scan_bind_groups_with_passes(
                    &self.passes,
                    encoder,
                    bind_groups.aggregate_compare_scan_n_blocks,
                    &bind_groups.hir_active_dispatch_args,
                    &bind_groups.aggregate_compare_scan,
                    "type_check.conditions.aggregate_compare_scan",
                )?;
                record_compute(
                    encoder,
                    &self.passes.count_dispatch_args,
                    &bind_groups.aggregate_compare_dispatch,
                    "type_check.conditions.aggregate_compare_dispatch_args",
                    1,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.conditions_aggregate_args,
                    &bind_groups.conditions_aggregate_args,
                    "type_check.conditions.aggregate_args.pass",
                    &bind_groups.aggregate_compare_dispatch_args,
                )?;
                record_type_subtree_comparison_passes(&self.passes, encoder, bind_groups)?;
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.conditions_hir.done");
            }
            // Resident validation consumes HIR/fact tables rather than
            // whole-token syntax scans.
            record_compute_indirect(
                encoder,
                &self.passes.control_hir,
                &bind_groups.control,
                "type_check.resident.control.pass",
                &bind_groups.token_hir_active_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.control.done");
            }
            record_compute(
                encoder,
                &self.passes.calls_backend_targets,
                &bind_groups.calls.backend_targets,
                "type_check.calls.backend_targets",
                token_capacity,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls_backend_targets.done");
            }
            record_compute(
                encoder,
                &self.passes.expression_types_init,
                &bind_groups.compact_expr_scalar_type_init,
                "type_check.expression_types.init",
                hir_node_capacity,
            )?;
            for step in &bind_groups.compact_expr_scalar_type_steps {
                record_compute(
                    encoder,
                    &self.passes.expression_types_step,
                    step,
                    "type_check.expression_types.step",
                    hir_node_capacity,
                )?;
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.expression_types.done");
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
        Ok(RecordedTypeCheck)
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
        guard
            .as_ref()
            .map(|bind_groups| consume(&bind_groups.enclosing_fn))
    }

    /// Borrows the full retained semantic metadata set for GPU backend
    /// recording.
    ///
    /// The resident cache remains owned by the type checker after the callback
    /// returns.
    pub fn with_codegen_buffers<R>(
        &self,
        consume: impl FnOnce(GpuCodegenBuffers<'_>) -> R,
    ) -> Option<R> {
        let guard = self
            .resident_state
            .lock()
            .expect("GpuTypeChecker.resident_state poisoned");
        let bind_groups = guard.as_ref()?;
        let module_path = bind_groups.module_path.as_ref()?;
        Some(consume(GpuCodegenBuffers {
            lowering: GpuSemanticLoweringBuffers {
                compact_expr_scalar_type: &bind_groups.compact_expr_scalar_type,
                name_id_by_token: &bind_groups.name_id_by_token,
                language_name_id: &bind_groups.language_name_id,
                enclosing_fn: &bind_groups.enclosing_fn,
                if_depth: &bind_groups.if_depth,
                visible_decl: &bind_groups.visible_decl,
                visible_type: &bind_groups.visible_type,
                backend_call_fn_index: &bind_groups.backend_call_fn_index,
                call_intrinsic_tag: &bind_groups.call_intrinsic_tag,
                call_return_type: &bind_groups.call_return_type,
                fn_entrypoint_tag: &bind_groups.fn_entrypoint_tag,
                member_result_field_ordinal: &bind_groups.member_result_field_ordinal,
                struct_init_field_ordinal_by_row: &bind_groups.struct_init_field_ordinal_by_row,
            },
            compact_expr_scalar_type: &bind_groups.compact_expr_scalar_type,
            name_id_by_token: &bind_groups.name_id_by_token,
            language_name_id: &bind_groups.language_name_id,
            enclosing_fn: &bind_groups.enclosing_fn_start_token,
            if_depth: &bind_groups.if_depth,
            visible_decl: &bind_groups.visible_decl,
            visible_type: &bind_groups.visible_type,
            path_count_out: &module_path.path_count_out,
            path_owner_token: &module_path.path_owner_token,
            path_id_by_owner_hir: &module_path.path_id_by_owner_hir,
            path_id_by_owner_token: &module_path.path_id_by_owner_token,
            path_segment_count: &module_path.path_segment_count,
            path_segment_base: &module_path.path_segment_base,
            path_segment_token: &module_path.path_segment_token,
            resolved_value_decl: &module_path.resolved_value_decl,
            resolved_value_status: &module_path.resolved_value_status,
            decl_count_out: &module_path.decl_count_out,
            decl_kind: &module_path.decl_kind,
            decl_name_token: &module_path.decl_name_token,
            decl_id_by_name_token: &module_path.decl_id_by_name_token,
            decl_hir_node: &module_path.decl_hir_node,
            decl_parent_type_decl: &module_path.decl_parent_type_decl,
            public_decl_count: &module_path.interface_public_decl_count,
            public_decl_local_id: &module_path.interface_public_decl_local_id,
            public_decl_index_by_local: &module_path.interface_public_decl_index_by_local,
            decl_type_ref_tag: &bind_groups.decl_type_ref_tag,
            decl_type_ref_payload: &bind_groups.decl_type_ref_payload,
            type_expr_ref_tag: &bind_groups.type_expr_ref_tag,
            type_expr_ref_payload: &bind_groups.type_expr_ref_payload,
            module_value_path_call_head: &bind_groups.module_value_path_call_head,
            module_value_path_call_open: &bind_groups.module_value_path_call_open,
            module_value_path_const_head: &bind_groups.module_value_path_const_head,
            module_value_path_const_end: &bind_groups.module_value_path_const_end,
            call_fn_index: &bind_groups.backend_call_fn_index,
            call_dependency_decl: &bind_groups.call_dependency_decl,
            call_intrinsic_tag: &bind_groups.call_intrinsic_tag,
            fn_entrypoint_tag: &bind_groups.fn_entrypoint_tag,
            call_return_type: &bind_groups.call_return_type,
            call_return_type_token: &bind_groups.call_return_type_token,
            call_param_count: &bind_groups.call_param_count,
            call_param_type: &bind_groups.call_param_type,
            call_param_row_count_out: &bind_groups.call_param_row_count_out,
            call_param_row_fn_token: &bind_groups.call_param_row_fn_token,
            call_param_row_ordinal: &bind_groups.call_param_row_ordinal,
            call_param_row_type: &bind_groups.call_param_row_type,
            call_param_row_start: &bind_groups.call_param_row_start,
            call_param_row_count: &bind_groups.call_param_row_count,
            call_arg_row_node: &bind_groups.call_arg_row_node,
            call_arg_row_call_node: &bind_groups.call_arg_row_call_node,
            call_arg_row_ordinal: &bind_groups.call_arg_row_ordinal,
            call_arg_row_start: &bind_groups.call_arg_row_start,
            call_arg_row_count: &bind_groups.call_arg_row_count,
            method_decl_module_id: &bind_groups.method_decl_module_id,
            method_decl_name_token: &bind_groups.method_decl_name_token,
            method_decl_name_id: &bind_groups.method_decl_name_id,
            method_decl_receiver_ref_tag: &bind_groups.method_decl_receiver_ref_tag,
            method_decl_receiver_ref_payload: &bind_groups.method_decl_receiver_ref_payload,
            method_decl_param_offset: &bind_groups.method_decl_param_offset,
            method_decl_receiver_mode: &bind_groups.method_decl_receiver_mode,
            method_decl_visibility: &bind_groups.method_decl_visibility,
            method_key_to_fn_token: &bind_groups.method_key_to_fn_token,
            method_key_status: &bind_groups.method_key_status,
            method_call_receiver_ref_tag: &bind_groups.method_call_receiver_ref_tag,
            method_call_receiver_ref_payload: &bind_groups.method_call_receiver_ref_payload,
            method_call_name_id: &bind_groups.method_call_name_id,
            method_call_site_module_id: &bind_groups.method_call_site_module_id,
            type_instance_kind: &bind_groups.type_instance_kind,
            type_instance_decl_token: &bind_groups.type_instance_decl_token,
            type_instance_external_canonical: &bind_groups.type_instance_external_canonical,
            type_instance_arg_start: &bind_groups.type_instance_arg_start,
            type_instance_arg_count: &bind_groups.type_instance_arg_count,
            type_instance_arg_ref_tag: &bind_groups.type_instance_arg_ref_tag,
            type_instance_arg_ref_payload: &bind_groups.type_instance_arg_ref_payload,
            type_instance_arg_hash: &bind_groups.type_instance_arg_hash,
            type_decl_hir_node_by_token: &bind_groups.type_decl_hir_node_by_token,
            type_instance_len_kind: &bind_groups.type_instance_len_kind,
            type_instance_len_payload: &bind_groups.type_instance_len_payload,
            fn_return_ref_tag: &bind_groups.fn_return_ref_tag,
            fn_return_ref_payload: &bind_groups.fn_return_ref_payload,
            member_result_ref_tag: &bind_groups.member_result_ref_tag,
            member_result_ref_payload: &bind_groups.member_result_ref_payload,
            member_result_field_ordinal: &bind_groups.member_result_field_ordinal,
            member_result_field_node: &bind_groups.member_result_field_node,
            struct_init_field_expected_ref_tag: &bind_groups.struct_init_field_expected_ref_tag,
            struct_init_field_expected_ref_payload: &bind_groups
                .struct_init_field_expected_ref_payload,
            struct_init_field_ordinal: &bind_groups.struct_init_field_ordinal,
            struct_init_field_ordinal_by_node: &bind_groups.struct_init_field_ordinal_by_node,
            struct_init_field_decl_node_by_node: &bind_groups.struct_init_field_decl_node_by_node,
            struct_init_field_ordinal_by_row: &bind_groups.struct_init_field_ordinal_by_row,
            struct_init_field_decl_token_by_row: &bind_groups.struct_init_field_decl_token_by_row,
        }))
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
        Some(consume(GpuSemanticInterfaceIdentityBuffers {
            name_count_out: &state.name_scan_total,
            name_spans: &state.name_spans,
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
            type_expr_ref_tag: &state.type_expr_ref_tag,
            type_expr_ref_payload: &state.type_expr_ref_payload,
            type_generic_param_slot_by_token: &state.type_generic_param_slot_by_token,
            type_const_param_slot_by_token: &state.type_const_param_slot_by_token,
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
            generic_param_count_out: &state.generic_param_count_out,
            generic_param_owner_token: &state.generic_param_owner_token,
            generic_param_name_id: &state.generic_param_name_id,
            generic_param_token: &state.generic_param_token,
            generic_param_kind: &state.generic_param_kind,
            type_decl_generic_param_count_by_owner_token: &state
                .type_decl_generic_param_count_by_owner_token,
            type_decl_const_param_count_by_owner_token: &state
                .type_decl_const_param_count_by_owner_token,
        }))
    }

    /// Moves the full retained semantic metadata set out of the resident cache.
    ///
    /// Use this when a later phase must outlive or release the type-checker
    /// resident state. A successful call empties the resident cache.
    pub fn take_codegen_buffers(&self) -> Option<OwnedGpuCodegenBuffers> {
        let mut guard = self
            .resident_state
            .lock()
            .expect("GpuTypeChecker.resident_state poisoned");
        let bind_groups = guard.take()?;
        let ResidentTypeCheckState {
            compact_expr_scalar_type,
            name_id_by_token,
            language_name_id,
            enclosing_fn: enclosing_fn_hir,
            enclosing_fn_start_token,
            if_depth,
            visible_decl,
            visible_type,
            module_path,
            module_value_path_call_head,
            module_value_path_call_open,
            module_value_path_const_head,
            module_value_path_const_end,
            call_fn_index: _,
            backend_call_fn_index,
            call_dependency_decl,
            call_intrinsic_tag,
            fn_entrypoint_tag,
            call_return_type,
            call_return_type_token,
            call_param_count,
            call_param_type,
            call_param_row_count_out,
            call_param_row_fn_token,
            call_param_row_ordinal,
            call_param_row_type,
            call_param_row_start,
            call_param_row_count,
            call_arg_row_node,
            call_arg_row_call_node,
            call_arg_row_ordinal,
            call_arg_row_start,
            call_arg_row_count,
            method_decl_module_id,
            method_decl_name_token,
            method_decl_name_id,
            method_decl_receiver_ref_tag,
            method_decl_receiver_ref_payload,
            method_decl_param_offset,
            method_decl_receiver_mode,
            method_decl_visibility,
            method_key_to_fn_token,
            method_key_status,
            method_call_receiver_ref_tag,
            method_call_receiver_ref_payload,
            method_call_name_id,
            method_call_site_module_id,
            type_instance_kind,
            type_instance_decl_token,
            type_instance_external_canonical,
            type_instance_arg_start,
            type_instance_arg_count,
            type_instance_arg_ref_tag,
            type_instance_arg_ref_payload,
            type_instance_arg_hash,
            type_decl_hir_node_by_token,
            type_instance_len_kind,
            type_instance_len_payload,
            fn_return_ref_tag,
            fn_return_ref_payload,
            decl_type_ref_tag,
            decl_type_ref_payload,
            type_expr_ref_tag,
            type_expr_ref_payload,
            member_result_ref_tag,
            member_result_ref_payload,
            member_result_field_ordinal,
            member_result_field_node,
            struct_init_field_expected_ref_tag,
            struct_init_field_expected_ref_payload,
            struct_init_field_ordinal,
            struct_init_field_ordinal_by_node,
            struct_init_field_decl_node_by_node,
            struct_init_field_ordinal_by_row,
            struct_init_field_decl_token_by_row,
            ..
        } = bind_groups;
        let ModulePathState {
            path_count_out,
            path_owner_token,
            path_id_by_owner_hir,
            path_id_by_owner_token,
            path_segment_count,
            path_segment_base,
            path_segment_token,
            resolved_value_decl,
            resolved_value_status,
            decl_count_out,
            decl_kind,
            decl_name_token,
            decl_id_by_name_token,
            decl_hir_node,
            decl_parent_type_decl,
            interface_public_decl_count: public_decl_count,
            interface_public_decl_local_id: public_decl_local_id,
            interface_public_decl_index_by_local: public_decl_index_by_local,
            ..
        } = module_path?;

        Some(OwnedGpuCodegenBuffers {
            compact_expr_scalar_type,
            name_id_by_token,
            language_name_id,
            enclosing_fn_hir,
            enclosing_fn: enclosing_fn_start_token,
            if_depth,
            visible_decl,
            visible_type,
            path_count_out,
            path_owner_token,
            path_id_by_owner_hir,
            path_id_by_owner_token,
            path_segment_count,
            path_segment_base,
            path_segment_token,
            resolved_value_decl,
            resolved_value_status,
            decl_count_out,
            decl_kind,
            decl_name_token,
            decl_id_by_name_token,
            decl_hir_node,
            decl_parent_type_decl,
            public_decl_count,
            public_decl_local_id,
            public_decl_index_by_local,
            decl_type_ref_tag,
            decl_type_ref_payload,
            type_expr_ref_tag,
            type_expr_ref_payload,
            module_value_path_call_head,
            module_value_path_call_open,
            module_value_path_const_head,
            module_value_path_const_end,
            call_fn_index: backend_call_fn_index,
            call_dependency_decl,
            call_intrinsic_tag,
            fn_entrypoint_tag,
            call_return_type,
            call_return_type_token,
            call_param_count,
            call_param_type,
            call_param_row_count_out,
            call_param_row_fn_token,
            call_param_row_ordinal,
            call_param_row_type,
            call_param_row_start,
            call_param_row_count,
            call_arg_row_node,
            call_arg_row_call_node,
            call_arg_row_ordinal,
            call_arg_row_start,
            call_arg_row_count,
            method_decl_module_id,
            method_decl_name_token,
            method_decl_name_id,
            method_decl_receiver_ref_tag,
            method_decl_receiver_ref_payload,
            method_decl_param_offset,
            method_decl_receiver_mode,
            method_decl_visibility,
            method_key_to_fn_token,
            method_key_status,
            method_call_receiver_ref_tag,
            method_call_receiver_ref_payload,
            method_call_name_id,
            method_call_site_module_id,
            type_instance_kind,
            type_instance_decl_token,
            type_instance_external_canonical,
            type_instance_arg_start,
            type_instance_arg_count,
            type_instance_arg_ref_tag,
            type_instance_arg_ref_payload,
            type_instance_arg_hash,
            type_decl_hir_node_by_token,
            type_instance_len_kind,
            type_instance_len_payload,
            fn_return_ref_tag,
            fn_return_ref_payload,
            member_result_ref_tag,
            member_result_ref_payload,
            member_result_field_ordinal,
            member_result_field_node,
            struct_init_field_expected_ref_tag,
            struct_init_field_expected_ref_payload,
            struct_init_field_ordinal,
            struct_init_field_ordinal_by_node,
            struct_init_field_decl_node_by_node,
            struct_init_field_ordinal_by_row,
            struct_init_field_decl_token_by_row,
        })
    }

    /// Clones the x86 backend metadata handles without emptying the resident cache.
    ///
    /// `LaniusBuffer::clone` only clones the underlying `wgpu` handle. Keeping the
    /// resident state intact lets sequential daemon jobs reuse all type-check bind
    /// groups while the returned carrier safely outlives this lock guard.
    pub fn clone_x86_codegen_buffers(&self) -> Option<OwnedGpuX86CodegenBuffers> {
        let guard = self
            .resident_state
            .lock()
            .expect("GpuTypeChecker.resident_state poisoned");
        let bind_groups = guard.as_ref()?;
        let module_path = bind_groups.module_path.as_ref()?;
        Some(OwnedGpuX86CodegenBuffers {
            name_id_by_token: bind_groups.name_id_by_token.clone(),
            language_name_id: bind_groups.language_name_id.clone(),
            enclosing_fn: bind_groups.enclosing_fn_start_token.clone(),
            visible_decl: bind_groups.visible_decl.clone(),
            visible_type: bind_groups.visible_type.clone(),
            path_count_out: module_path.path_count_out.clone(),
            path_id_by_owner_hir: module_path.path_id_by_owner_hir.clone(),
            resolved_value_decl: module_path.resolved_value_decl.clone(),
            resolved_value_status: module_path.resolved_value_status.clone(),
            decl_count_out: module_path.decl_count_out.clone(),
            decl_kind: module_path.decl_kind.clone(),
            decl_name_token: module_path.decl_name_token.clone(),
            decl_id_by_name_token: module_path.decl_id_by_name_token.clone(),
            decl_hir_node: module_path.decl_hir_node.clone(),
            decl_parent_type_decl: module_path.decl_parent_type_decl.clone(),
            public_decl_count: module_path.interface_public_decl_count.clone(),
            public_decl_local_id: module_path.interface_public_decl_local_id.clone(),
            public_decl_index_by_hir: module_path.interface_public_decl_index_by_hir.clone(),
            decl_type_ref_tag: bind_groups.decl_type_ref_tag.clone(),
            decl_type_ref_payload: bind_groups.decl_type_ref_payload.clone(),
            type_expr_ref_tag: bind_groups.type_expr_ref_tag.clone(),
            type_expr_ref_payload: bind_groups.type_expr_ref_payload.clone(),
            module_type_path_type: bind_groups.module_type_path_type.clone(),
            type_decl_hir_node_by_token: bind_groups.type_decl_hir_node_by_token.clone(),
            call_fn_index: bind_groups.call_fn_index.clone(),
            call_dependency_decl: bind_groups.call_dependency_decl.clone(),
            call_intrinsic_tag: bind_groups.call_intrinsic_tag.clone(),
            fn_entrypoint_tag: bind_groups.fn_entrypoint_tag.clone(),
            fn_return_ref_tag: bind_groups.fn_return_ref_tag.clone(),
            fn_return_ref_payload: bind_groups.fn_return_ref_payload.clone(),
            call_return_type: bind_groups.call_return_type.clone(),
            call_return_type_token: bind_groups.call_return_type_token.clone(),
            call_param_type: bind_groups.call_param_type.clone(),
            call_arg_row_node: bind_groups.call_arg_row_node.clone(),
            call_arg_row_start: bind_groups.call_arg_row_start.clone(),
            call_arg_row_count: bind_groups.call_arg_row_count.clone(),
            method_decl_name_token: bind_groups.method_decl_name_token.clone(),
            method_decl_receiver_ref_tag: bind_groups.method_decl_receiver_ref_tag.clone(),
            method_decl_receiver_ref_payload: bind_groups.method_decl_receiver_ref_payload.clone(),
            method_decl_param_offset: bind_groups.method_decl_param_offset.clone(),
            method_decl_receiver_mode: bind_groups.method_decl_receiver_mode.clone(),
            type_instance_kind: bind_groups.type_instance_kind.clone(),
            type_instance_decl_token: bind_groups.type_instance_decl_token.clone(),
            type_instance_elem_ref_tag: bind_groups.type_instance_elem_ref_tag.clone(),
            type_instance_elem_ref_payload: bind_groups.type_instance_elem_ref_payload.clone(),
            type_instance_len_kind: bind_groups.type_instance_len_kind.clone(),
            type_instance_len_payload: bind_groups.type_instance_len_payload.clone(),
            member_result_field_ordinal: bind_groups.member_result_field_ordinal.clone(),
            member_result_field_node: bind_groups.member_result_field_node.clone(),
            struct_init_field_ordinal: bind_groups.struct_init_field_ordinal.clone(),
            struct_init_field_ordinal_by_node: bind_groups
                .struct_init_field_ordinal_by_node
                .clone(),
            struct_init_field_decl_node_by_node: bind_groups
                .struct_init_field_decl_node_by_node
                .clone(),
            struct_init_field_ordinal_by_row: bind_groups.struct_init_field_ordinal_by_row.clone(),
            struct_init_field_decl_token_by_row: bind_groups
                .struct_init_field_decl_token_by_row
                .clone(),
        })
    }

    /// Moves the x86 backend metadata subset out of the resident cache.
    ///
    /// A successful call empties the resident cache.
    pub fn take_x86_codegen_buffers(&self) -> Option<OwnedGpuX86CodegenBuffers> {
        let mut guard = self
            .resident_state
            .lock()
            .expect("GpuTypeChecker.resident_state poisoned");
        let bind_groups = guard.take()?;
        let ResidentTypeCheckState {
            name_id_by_token,
            language_name_id,
            enclosing_fn: _,
            enclosing_fn_start_token,
            visible_decl,
            visible_type,
            module_path,
            call_fn_index,
            call_intrinsic_tag,
            fn_entrypoint_tag,
            fn_return_ref_tag,
            fn_return_ref_payload,
            call_return_type,
            call_return_type_token,
            call_param_type,
            call_arg_row_node,
            call_arg_row_start,
            call_arg_row_count,
            method_decl_name_token,
            method_decl_receiver_ref_tag,
            method_decl_receiver_ref_payload,
            method_decl_param_offset,
            method_decl_receiver_mode,
            type_instance_kind,
            type_instance_decl_token,
            type_instance_elem_ref_tag,
            type_instance_elem_ref_payload,
            type_instance_len_kind,
            type_instance_len_payload,
            decl_type_ref_tag,
            decl_type_ref_payload,
            type_expr_ref_tag,
            type_expr_ref_payload,
            module_type_path_type,
            type_decl_hir_node_by_token,
            call_dependency_decl,
            member_result_field_ordinal,
            member_result_field_node,
            struct_init_field_ordinal,
            struct_init_field_ordinal_by_node,
            struct_init_field_decl_node_by_node,
            struct_init_field_ordinal_by_row,
            struct_init_field_decl_token_by_row,
            ..
        } = bind_groups;
        let ModulePathState {
            path_count_out,
            path_id_by_owner_hir,
            resolved_value_decl,
            resolved_value_status,
            decl_count_out,
            decl_kind,
            decl_name_token,
            decl_id_by_name_token,
            decl_hir_node,
            decl_parent_type_decl,
            interface_public_decl_count,
            interface_public_decl_local_id,
            interface_public_decl_index_by_hir,
            ..
        } = module_path?;

        Some(OwnedGpuX86CodegenBuffers {
            name_id_by_token,
            language_name_id,
            enclosing_fn: enclosing_fn_start_token,
            visible_decl,
            visible_type,
            path_count_out,
            path_id_by_owner_hir,
            resolved_value_decl,
            resolved_value_status,
            decl_count_out,
            decl_kind,
            decl_name_token,
            decl_id_by_name_token,
            decl_hir_node,
            decl_parent_type_decl,
            public_decl_count: interface_public_decl_count,
            public_decl_local_id: interface_public_decl_local_id,
            public_decl_index_by_hir: interface_public_decl_index_by_hir,
            decl_type_ref_tag,
            decl_type_ref_payload,
            type_expr_ref_tag,
            type_expr_ref_payload,
            module_type_path_type,
            type_decl_hir_node_by_token,
            call_fn_index,
            call_dependency_decl,
            call_intrinsic_tag,
            fn_entrypoint_tag,
            fn_return_ref_tag,
            fn_return_ref_payload,
            call_return_type,
            call_return_type_token,
            call_param_type,
            call_arg_row_node,
            call_arg_row_start,
            call_arg_row_count,
            method_decl_name_token,
            method_decl_receiver_ref_tag,
            method_decl_receiver_ref_payload,
            method_decl_param_offset,
            method_decl_receiver_mode,
            type_instance_kind,
            type_instance_decl_token,
            type_instance_elem_ref_tag,
            type_instance_elem_ref_payload,
            type_instance_len_kind,
            type_instance_len_payload,
            member_result_field_ordinal,
            member_result_field_node,
            struct_init_field_ordinal,
            struct_init_field_ordinal_by_node,
            struct_init_field_decl_node_by_node,
            struct_init_field_ordinal_by_row,
            struct_init_field_decl_token_by_row,
        })
    }

    #[allow(clippy::too_many_arguments)]
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
        guard.as_ref().map(|bind_groups| {
            consume(
                &bind_groups.type_expr_ref_tag,
                &bind_groups.type_expr_ref_payload,
                &bind_groups.type_instance_kind,
                &bind_groups.type_instance_decl_token,
                &bind_groups.type_instance_arg_start,
                &bind_groups.type_instance_arg_count,
                &bind_groups.type_instance_arg_ref_tag,
                &bind_groups.type_instance_arg_ref_payload,
                &bind_groups.member_result_ref_tag,
                &bind_groups.member_result_ref_payload,
                &bind_groups.type_instance_state,
                &bind_groups.type_instance_elem_ref_tag,
                &bind_groups.fn_return_ref_tag,
                &bind_groups.fn_return_ref_payload,
                &bind_groups.struct_init_field_expected_ref_tag,
                &bind_groups.struct_init_field_expected_ref_payload,
            )
        })
    }
}
