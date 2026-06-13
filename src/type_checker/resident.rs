use super::*;

const TYPE_ALIAS_PROJECTION_PASSES: usize = 8;

// Each dispatch projects one alias hop across all alias records. Repeating the
// pass keeps alias-chain convergence in the GPU pass graph instead of walking a
// per-lane chain inside the shader.
fn record_type_alias_projection_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    module_path: &ModulePathState,
    label: &'static str,
) -> Result<()> {
    for _ in 0..TYPE_ALIAS_PROJECTION_PASSES {
        record_compute_indirect(
            encoder,
            &passes.modules_project_type_aliases,
            &module_path.bind_groups.project_type_aliases,
            label,
            &module_path.decl_key_radix_dispatch_args,
        )?;
    }
    Ok(())
}

struct TypeCheckRecordHostTimer {
    enabled: bool,
    start: std::time::Instant,
    last: std::time::Instant,
}

impl TypeCheckRecordHostTimer {
    fn new() -> Self {
        let now = std::time::Instant::now();
        Self {
            enabled: crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false),
            start: now,
            last: now,
        }
    }

    fn stamp(&mut self, stage: &str) {
        if !self.enabled {
            return;
        }
        let now = std::time::Instant::now();
        let dt_ms = now.duration_since(self.last).as_secs_f64() * 1000.0;
        let total_ms = now.duration_since(self.start).as_secs_f64() * 1000.0;
        println!(
            "[gpu_compile_host_timer] typecheck.record.{stage}: {dt_ms:.3}ms (total {total_ms:.3}ms)"
        );
        self.last = now;
    }
}

impl GpuTypeChecker {
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        Self::new(&gpu.device)
    }

    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let passes = TypeCheckPasses::new(device)?;
        let params_buf = zeroed_type_check_params_buffer(device, "type_check.resident.params");
        let status_buf = storage_u32_rw(
            device,
            "type_check.resident.status",
            4,
            wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
        );
        let status_readback = readback_u32s(device, "rb.type_check.resident.status", 4);

        Ok(Self {
            passes,
            params_buf,
            status_buf,
            status_readback,
            bind_groups: Mutex::new(None),
        })
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
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_token_file_id_buf,
            hir_status_buf,
            Some(hir_items),
            None,
            timer,
        )
    }

    /// Records resident type checking with parser-owned HIR item metadata and
    /// parser-owned scratch buffers whose parser lifetimes have ended.
    #[allow(clippy::too_many_arguments)]
    pub fn record_resident_token_buffer_with_hir_items_and_scratch_on_gpu(
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
        hir_items: GpuTypeCheckHirItemBuffers<'_>,
        external_scratch: GpuTypeCheckExternalScratchBuffers<'_>,
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
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_token_file_id_buf,
            hir_status_buf,
            Some(hir_items),
            Some(external_scratch),
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
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_token_file_id_buf,
            hir_status_buf,
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
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_token_file_id_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        hir_items: Option<GpuTypeCheckHirItemBuffers<'_>>,
        external_scratch: Option<GpuTypeCheckExternalScratchBuffers<'_>>,
        mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
    ) -> Result<RecordedTypeCheck, GpuTypeCheckError> {
        let params = TypeCheckParams {
            n_tokens: token_capacity,
            source_len,
            n_hir_nodes: hir_node_capacity,
            n_source_files: source_file_capacity,
        };
        queue.write_buffer(&self.params_buf, 0, &type_check_params_bytes(&params));
        queue.write_buffer(&self.status_buf, 0, &status_init_bytes());
        let mut host_timer = TypeCheckRecordHostTimer::new();
        host_timer.stamp("params");

        let uses_hir_control = hir_node_capacity > 0;
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
            fingerprint_buffers.push(items.semantic_dense_node);
            fingerprint_buffers.push(items.semantic_count);
            fingerprint_buffers.push(items.nearest_loop_node);
        }
        if let Some(scratch) = external_scratch {
            fingerprint_buffers.push(scratch.fn_entrypoint_tag);
            fingerprint_buffers.push(scratch.type_expr_ref_tag);
            fingerprint_buffers.push(scratch.type_expr_ref_payload);
            fingerprint_buffers.push(scratch.type_generic_param_slot_by_token);
            fingerprint_buffers.push(scratch.type_const_param_slot_by_token);
            fingerprint_buffers.push(scratch.record_family_flag);
            fingerprint_buffers.push(scratch.module_record_prefix);
            fingerprint_buffers.push(scratch.record_scan_local_prefix);
            fingerprint_buffers.push(scratch.path_id_by_owner_hir);
            fingerprint_buffers.push(scratch.call_param_count);
            fingerprint_buffers.push(scratch.call_param_type);
            fingerprint_buffers.push(scratch.call_arg_record);
            fingerprint_buffers.push(scratch.function_lookup_key);
            fingerprint_buffers.push(scratch.function_lookup_fn);
            fingerprint_buffers.push(scratch.type_decl_generic_param_count);
            fingerprint_buffers.push(scratch.type_decl_generic_param_count_by_node);
            fingerprint_buffers.push(scratch.type_instance_arg_start);
            fingerprint_buffers.push(scratch.type_instance_arg_count);
            fingerprint_buffers.push(scratch.type_instance_arg_ref_tag);
            fingerprint_buffers.push(scratch.type_instance_arg_ref_payload);
            fingerprint_buffers.push(scratch.type_instance_len_kind);
            fingerprint_buffers.push(scratch.type_instance_len_payload);
            fingerprint_buffers.push(scratch.type_instance_state);
            fingerprint_buffers.push(scratch.decl_type_key_to_decl_id);
            fingerprint_buffers.push(scratch.decl_value_key_to_decl_id);
            fingerprint_buffers.push(scratch.method_decl_module_id);
            fingerprint_buffers.push(scratch.method_decl_impl_node);
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
        let input_fingerprint = buffer_fingerprint(&fingerprint_buffers);
        let control_pass = if uses_hir_control {
            &self.passes.control_hir
        } else {
            &self.passes.control
        };
        let scope_pass = if uses_hir_control {
            &self.passes.scope_hir
        } else {
            &self.passes.scope
        };

        {
            let mut bind_group_guard = self
                .bind_groups
                .lock()
                .expect("GpuTypeChecker.bind_groups poisoned");
            let needs_rebuild = bind_group_guard
                .as_ref()
                .map(|groups| {
                    source_file_capacity != groups.source_file_capacity
                        || token_capacity > groups.token_capacity
                        || hir_node_capacity > groups.hir_node_capacity
                        || input_fingerprint != groups.input_fingerprint
                        || uses_hir_control != groups.uses_hir_control
                        || uses_hir_items != groups.uses_hir_items
                })
                .unwrap_or(true);
            let rebuilt = needs_rebuild;
            if needs_rebuild {
                *bind_group_guard = Some(self.create_bind_groups(
                    device,
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
                    hir_items,
                    &self.passes,
                    control_pass,
                    scope_pass,
                    input_fingerprint,
                    uses_hir_control,
                    uses_hir_items,
                    external_scratch,
                )?);
            }
            host_timer.stamp(if rebuilt {
                "bind_groups_rebuilt"
            } else {
                "bind_groups_reused"
            });
            let bind_groups = bind_group_guard
                .as_ref()
                .expect("resident type checker bind groups must exist");

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
            record_loop_depth_passes_with_passes(&self.passes, encoder, bind_groups)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.loop_depth.done");
            }
            record_language_name_bind_groups_with_passes(
                &self.passes,
                encoder,
                bind_groups.token_capacity,
                &bind_groups.language_name_bind_groups,
            )?;
            record_name_bind_groups_with_passes(
                &self.passes,
                encoder,
                bind_groups.token_capacity,
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
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances.clear.done");
            }
            record_generic_param_record_passes_with_passes(
                &self.passes,
                encoder,
                &bind_groups.type_instances,
                hir_node_capacity.max(1).div_ceil(256).max(1),
                &bind_groups.hir_active_dispatch_args,
                timer.as_deref_mut(),
            )?;
            record_type_instance_collection_passes_with_passes(
                &self.passes,
                encoder,
                bind_groups,
                &bind_groups.hir_active_dispatch_args,
                &super::record::TYPE_INSTANCE_COLLECTION_INITIAL_LABELS,
                timer.as_deref_mut(),
            )?;
            if let Some(module_path) = &bind_groups.module_path {
                record_type_alias_projection_passes(
                    &self.passes,
                    encoder,
                    module_path,
                    "type_check.modules.project_type_aliases",
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.modules.project_type_aliases.done");
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
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.type_instances_project.done");
                }
            }
            record_compute_indirect(
                encoder,
                &self.passes.type_instances_collect_named_arg_refs,
                &bind_groups.type_instances.collect_named_arg_refs,
                "type_check.resident.type_instances_collect_named_arg_refs.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_named_arg_refs.done");
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
                n_work,
                &bind_groups.hir_active_dispatch_args,
                &bind_groups.token_hir_active_dispatch_args,
                &bind_groups.calls,
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
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_decl_refs.done");
            }
            record_method_declaration_passes_with_passes(
                &self.passes,
                encoder,
                token_capacity,
                &bind_groups.token_active_dispatch_args,
                &bind_groups.hir_active_dispatch_args,
                &bind_groups.methods,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.methods.done");
            }
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
            record_struct_field_key_passes_with_passes(
                &self.passes,
                encoder,
                &bind_groups.type_instances,
                &bind_groups.hir_active_dispatch_args,
                timer.as_deref_mut(),
            )?;
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
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instance_fields.done");
            }
            host_timer.stamp("methods_member_struct_fields");
            if let Some(module_path) = &bind_groups.module_path {
                record_compute_indirect(
                    encoder,
                    &self.passes.modules_bind_match_patterns,
                    &module_path.bind_groups.bind_match_patterns,
                    "type_check.modules.bind_match_patterns",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.modules_type_match_payloads,
                    &module_path.bind_groups.type_match_payloads,
                    "type_check.modules.type_match_payloads",
                    &bind_groups.hir_active_dispatch_args,
                )?;
            }
            record_compute_indirect(
                encoder,
                scope_pass,
                if uses_hir_control {
                    &bind_groups.scope_hir
                } else {
                    &bind_groups.scope
                },
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
            }
            record_method_key_table_passes_with_passes(
                &self.passes,
                encoder,
                &bind_groups.token_active_dispatch_args,
                &bind_groups.methods,
            )?;
            record_method_call_resolution_passes_with_passes(
                &self.passes,
                encoder,
                &bind_groups.token_active_dispatch_args,
                &bind_groups.hir_active_dispatch_args,
                &bind_groups.methods,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.methods_call_returns.done");
            }
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
            record_compute(
                encoder,
                &self.passes.calls_validate_array_results,
                &bind_groups.calls.validate_array_results,
                "type_check.resident.calls_validate_array_results.pass",
                n_work.saturating_mul(CALL_PARAM_CACHE_STRIDE as u32).max(1),
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls_validate_array_results.done");
            }
            record_call_erase_generic_params_with_passes(
                &self.passes,
                encoder,
                token_capacity,
                &bind_groups.calls,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls_erased.done");
            }
            if let Some(module_path) = &bind_groups.module_path {
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
                record_compute_indirect(
                    encoder,
                    &self.passes.modules_type_match_exprs,
                    &module_path.bind_groups.type_match_exprs,
                    "type_check.modules.type_match_exprs",
                    &bind_groups.hir_active_dispatch_args,
                )?;
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
            record_compute_indirect(
                encoder,
                &self.passes.methods_resolve,
                &bind_groups.methods.resolve,
                "type_check.resident.methods.resolve",
                &bind_groups.token_hir_active_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.methods_resolve.done");
            }
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
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_late_consumers.done");
            }
            host_timer.stamp("late_value_consumers");
            record_compute_indirect(
                encoder,
                &self.passes.type_instances_struct_init_substitute,
                &bind_groups.type_instances.struct_init_substitute,
                "type_check.resident.type_instances_struct_init_substitute.pass",
                &bind_groups.token_active_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &self.passes.type_instances_validate_aggregate_access,
                &bind_groups.type_instances.validate_aggregate_access,
                "type_check.resident.type_instances_validate_aggregate_access.pass",
                &bind_groups.hir_active_dispatch_args,
            )?;
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
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.predicates_bound_args.done");
                }
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_collect_method_contracts,
                    &predicates.collect_method_contracts,
                    "type_check.resident.predicates_collect_method_contracts.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.predicates_method_contracts.done");
                }
                record_predicate_method_contract_keys_with_passes(
                    &self.passes,
                    encoder,
                    &bind_groups.hir_active_dispatch_args,
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
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.predicates_collect.done");
                }
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_emit_method_validation_rows,
                    &predicates.emit_method_validation_rows,
                    "type_check.resident.predicates_emit_method_validation_rows.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_reduce_method_validation_errors,
                    &predicates.reduce_method_validation_errors,
                    "type_check.resident.predicates_reduce_method_validation_errors.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                record_compute_indirect(
                    encoder,
                    &self.passes.predicates_apply_method_validation_errors,
                    &predicates.apply_method_validation_errors,
                    "type_check.resident.predicates_apply_method_validation_errors.pass",
                    &bind_groups.hir_active_dispatch_args,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.predicates_method_validation_rows.done");
                }
                record_predicate_bind_groups_with_passes(
                    &self.passes,
                    encoder,
                    &bind_groups.hir_active_dispatch_args,
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
                    &bind_groups.hir_active_dispatch_args,
                )?;
                record_hir_counted_u32_scan_bind_groups_with_passes(
                    &self.passes,
                    encoder,
                    predicates.obligation_pair_scan_n_blocks,
                    &bind_groups.hir_active_dispatch_args,
                    &predicates.obligation_pair_scan,
                    "type_check.predicates.obligation_pair_scan",
                )?;
                record_compute(
                    encoder,
                    &self.passes.count_dispatch_args,
                    &predicates.obligation_pair_dispatch,
                    "type_check.predicates.obligation_pair_dispatch_args",
                    1,
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
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.conditions_hir.done");
            }
            // Resident validation consumes HIR/fact tables rather than
            // whole-token syntax scans.
            record_compute_indirect(
                encoder,
                control_pass,
                &bind_groups.control,
                "type_check.resident.control.pass",
                &bind_groups.token_hir_active_dispatch_args,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.control.done");
            }
            host_timer.stamp("aggregate_conditions_control");
        }
        encoder.copy_buffer_to_buffer(&self.status_buf, 0, &self.status_readback, 0, 16);
        host_timer.stamp("status_readback_recorded");
        Ok(RecordedTypeCheck)
    }

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

    pub fn with_visible_decl_buffer<R>(
        &self,
        consume: impl FnOnce(&wgpu::Buffer) -> R,
    ) -> Option<R> {
        let guard = self
            .bind_groups
            .lock()
            .expect("GpuTypeChecker.bind_groups poisoned");
        guard
            .as_ref()
            .map(|bind_groups| consume(&bind_groups.visible_decl))
    }

    pub fn with_visible_type_buffer<R>(
        &self,
        consume: impl FnOnce(&wgpu::Buffer) -> R,
    ) -> Option<R> {
        let guard = self
            .bind_groups
            .lock()
            .expect("GpuTypeChecker.bind_groups poisoned");
        guard
            .as_ref()
            .map(|bind_groups| consume(&bind_groups.visible_type))
    }

    pub fn with_enclosing_fn_buffer<R>(
        &self,
        consume: impl FnOnce(&wgpu::Buffer) -> R,
    ) -> Option<R> {
        let guard = self
            .bind_groups
            .lock()
            .expect("GpuTypeChecker.bind_groups poisoned");
        guard
            .as_ref()
            .map(|bind_groups| consume(&bind_groups.enclosing_fn))
    }

    pub fn with_codegen_buffers<R>(
        &self,
        consume: impl FnOnce(GpuCodegenBuffers<'_>) -> R,
    ) -> Option<R> {
        let guard = self
            .bind_groups
            .lock()
            .expect("GpuTypeChecker.bind_groups poisoned");
        let bind_groups = guard.as_ref()?;
        let module_path = bind_groups.module_path.as_ref()?;
        Some(consume(GpuCodegenBuffers {
            name_id_by_token: &bind_groups.name_id_by_token,
            enclosing_fn: &bind_groups.enclosing_fn,
            visible_decl: &bind_groups.visible_decl,
            visible_type: &bind_groups.visible_type,
            path_count_out: &module_path.path_count_out,
            path_owner_token: &module_path.path_owner_token,
            path_id_by_owner_hir: &module_path.path_id_by_owner_hir,
            resolved_value_decl: &module_path.resolved_value_decl,
            resolved_value_status: &module_path.resolved_value_status,
            decl_count_out: &module_path.decl_count_out,
            decl_kind: &module_path.decl_kind,
            decl_name_token: &module_path.decl_name_token,
            decl_id_by_name_token: &module_path.decl_id_by_name_token,
            decl_hir_node: &module_path.decl_hir_node,
            decl_parent_type_decl: &module_path.decl_parent_type_decl,
            decl_type_ref_tag: &bind_groups.decl_type_ref_tag,
            decl_type_ref_payload: &bind_groups.decl_type_ref_payload,
            type_expr_ref_tag: &bind_groups.type_expr_ref_tag,
            type_expr_ref_payload: &bind_groups.type_expr_ref_payload,
            module_value_path_call_head: &bind_groups.module_value_path_call_head,
            module_value_path_call_open: &bind_groups.module_value_path_call_open,
            module_value_path_const_head: &bind_groups.module_value_path_const_head,
            module_value_path_const_end: &bind_groups.module_value_path_const_end,
            call_fn_index: &bind_groups.call_fn_index,
            call_intrinsic_tag: &bind_groups.call_intrinsic_tag,
            fn_entrypoint_tag: &bind_groups.fn_entrypoint_tag,
            call_return_type: &bind_groups.call_return_type,
            call_return_type_token: &bind_groups.call_return_type_token,
            call_param_count: &bind_groups.call_param_count,
            call_param_type: &bind_groups.call_param_type,
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
            type_instance_arg_start: &bind_groups.type_instance_arg_start,
            type_instance_arg_count: &bind_groups.type_instance_arg_count,
            type_instance_arg_ref_tag: &bind_groups.type_instance_arg_ref_tag,
            type_instance_arg_ref_payload: &bind_groups.type_instance_arg_ref_payload,
            type_instance_len_kind: &bind_groups.type_instance_len_kind,
            type_instance_len_payload: &bind_groups.type_instance_len_payload,
            fn_return_ref_tag: &bind_groups.fn_return_ref_tag,
            fn_return_ref_payload: &bind_groups.fn_return_ref_payload,
            member_result_ref_tag: &bind_groups.member_result_ref_tag,
            member_result_ref_payload: &bind_groups.member_result_ref_payload,
            member_result_field_ordinal: &bind_groups.member_result_field_ordinal,
            struct_init_field_expected_ref_tag: &bind_groups.struct_init_field_expected_ref_tag,
            struct_init_field_expected_ref_payload: &bind_groups
                .struct_init_field_expected_ref_payload,
            struct_init_field_ordinal: &bind_groups.struct_init_field_ordinal,
            struct_init_field_ordinal_by_node: &bind_groups.struct_init_field_ordinal_by_node,
        }))
    }

    pub fn take_codegen_buffers(&self) -> Option<OwnedGpuCodegenBuffers> {
        let mut guard = self
            .bind_groups
            .lock()
            .expect("GpuTypeChecker.bind_groups poisoned");
        let bind_groups = guard.take()?;
        let ResidentTypeCheckBindGroups {
            name_id_by_token,
            enclosing_fn,
            visible_decl,
            visible_type,
            module_path,
            module_value_path_call_head,
            module_value_path_call_open,
            module_value_path_const_head,
            module_value_path_const_end,
            call_fn_index,
            call_intrinsic_tag,
            fn_entrypoint_tag,
            call_return_type,
            call_return_type_token,
            call_param_count,
            call_param_type,
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
            type_instance_arg_start,
            type_instance_arg_count,
            type_instance_arg_ref_tag,
            type_instance_arg_ref_payload,
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
            struct_init_field_expected_ref_tag,
            struct_init_field_expected_ref_payload,
            struct_init_field_ordinal,
            struct_init_field_ordinal_by_node,
            ..
        } = bind_groups;
        let ModulePathState {
            path_count_out,
            path_owner_token,
            path_id_by_owner_hir,
            resolved_value_decl,
            resolved_value_status,
            decl_count_out,
            decl_kind,
            decl_name_token,
            decl_id_by_name_token,
            decl_hir_node,
            decl_parent_type_decl,
            ..
        } = module_path?;

        Some(OwnedGpuCodegenBuffers {
            name_id_by_token,
            enclosing_fn,
            visible_decl,
            visible_type,
            path_count_out,
            path_owner_token,
            path_id_by_owner_hir,
            resolved_value_decl,
            resolved_value_status,
            decl_count_out,
            decl_kind,
            decl_name_token,
            decl_id_by_name_token,
            decl_hir_node,
            decl_parent_type_decl,
            decl_type_ref_tag,
            decl_type_ref_payload,
            type_expr_ref_tag,
            type_expr_ref_payload,
            module_value_path_call_head,
            module_value_path_call_open,
            module_value_path_const_head,
            module_value_path_const_end,
            call_fn_index,
            call_intrinsic_tag,
            fn_entrypoint_tag,
            call_return_type,
            call_return_type_token,
            call_param_count,
            call_param_type,
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
            type_instance_arg_start,
            type_instance_arg_count,
            type_instance_arg_ref_tag,
            type_instance_arg_ref_payload,
            type_instance_len_kind,
            type_instance_len_payload,
            fn_return_ref_tag,
            fn_return_ref_payload,
            member_result_ref_tag,
            member_result_ref_payload,
            member_result_field_ordinal,
            struct_init_field_expected_ref_tag,
            struct_init_field_expected_ref_payload,
            struct_init_field_ordinal,
            struct_init_field_ordinal_by_node,
        })
    }

    pub fn take_x86_codegen_buffers(&self) -> Option<OwnedGpuX86CodegenBuffers> {
        let mut guard = self
            .bind_groups
            .lock()
            .expect("GpuTypeChecker.bind_groups poisoned");
        let bind_groups = guard.take()?;
        let ResidentTypeCheckBindGroups {
            enclosing_fn,
            visible_decl,
            visible_type,
            module_path,
            call_fn_index,
            call_intrinsic_tag,
            fn_entrypoint_tag,
            call_return_type,
            call_return_type_token,
            call_param_type,
            method_decl_receiver_ref_tag,
            method_decl_receiver_ref_payload,
            method_decl_param_offset,
            type_instance_kind,
            type_instance_decl_token,
            type_instance_len_kind,
            type_instance_len_payload,
            decl_type_ref_tag,
            decl_type_ref_payload,
            member_result_field_ordinal,
            struct_init_field_ordinal,
            struct_init_field_ordinal_by_node,
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
            ..
        } = module_path?;

        Some(OwnedGpuX86CodegenBuffers {
            enclosing_fn,
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
            decl_type_ref_tag,
            decl_type_ref_payload,
            call_fn_index,
            call_intrinsic_tag,
            fn_entrypoint_tag,
            call_return_type,
            call_return_type_token,
            call_param_type,
            method_decl_receiver_ref_tag,
            method_decl_receiver_ref_payload,
            method_decl_param_offset,
            type_instance_kind,
            type_instance_decl_token,
            type_instance_len_kind,
            type_instance_len_payload,
            member_result_field_ordinal,
            struct_init_field_ordinal,
            struct_init_field_ordinal_by_node,
        })
    }

    #[allow(clippy::too_many_arguments)]
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
            .bind_groups
            .lock()
            .expect("GpuTypeChecker.bind_groups poisoned");
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
