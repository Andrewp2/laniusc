use super::*;

impl GpuTypeChecker {
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        Self::new(&gpu.device)
    }

    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let passes = TypeCheckPasses::new(device)?;
        let params_buf = uniform_from_val(
            device,
            "type_check.resident.params",
            &TypeCheckParams {
                n_tokens: 0,
                source_len: 0,
                n_hir_nodes: 0,
            },
        );
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
        mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
    ) -> Result<RecordedTypeCheck, GpuTypeCheckError> {
        let params = TypeCheckParams {
            n_tokens: token_capacity,
            source_len,
            n_hir_nodes: hir_node_capacity,
        };
        queue.write_buffer(&self.params_buf, 0, &type_check_params_bytes(&params));
        queue.write_buffer(&self.status_buf, 0, &status_init_bytes());

        let pass = &self.passes.tokens;
        let uses_hir_control = hir_node_capacity > 0;
        let uses_hir_items = hir_items.is_some();
        let input_fingerprint = buffer_fingerprint(&[
            token_buf,
            token_count_buf,
            token_file_id_buf,
            source_buf,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_token_file_id_buf,
            hir_status_buf,
        ]);
        let control_pass = if uses_hir_control {
            &self.passes.control_hir
        } else {
            &self.passes.control
        };
        let scope_pass = &self.passes.scope;

        {
            let mut bind_group_guard = self
                .bind_groups
                .lock()
                .expect("GpuTypeChecker.bind_groups poisoned");
            let needs_rebuild = bind_group_guard
                .as_ref()
                .map(|groups| {
                    source_len != groups.source_len
                        || token_capacity > groups.token_capacity
                        || hir_node_capacity > groups.hir_node_capacity
                        || input_fingerprint != groups.input_fingerprint
                        || uses_hir_control != groups.uses_hir_control
                        || uses_hir_items != groups.uses_hir_items
                })
                .unwrap_or(true);
            if needs_rebuild {
                *bind_group_guard = Some(self.create_bind_groups(
                    device,
                    source_len,
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
                    pass,
                    control_pass,
                    scope_pass,
                    input_fingerprint,
                    uses_hir_control,
                    uses_hir_items,
                )?);
            }
            let bind_groups = bind_group_guard
                .as_ref()
                .expect("resident type checker bind groups must exist");

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
                &bind_groups.name_bind_groups,
            )?;
            record_language_decl_bind_groups_with_passes(
                &self.passes,
                encoder,
                &bind_groups.language_name_bind_groups,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.names.done");
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.language_decls.done");
            }
            if let Some(module_path) = &bind_groups.module_path {
                record_module_path_state_with_passes(&self.passes, encoder, module_path)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.module_paths.done");
                }
            }
            record_compute(
                encoder,
                &self.passes.type_instances_clear,
                &bind_groups.type_instances_clear,
                "type_check.resident.type_instances_clear.pass",
                token_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_decl_generic_params,
                &bind_groups.type_instances_decl_generic_params,
                "type_check.resident.type_instances_decl_generic_params.pass",
                hir_node_capacity.max(1),
            )?;
            record_type_instance_collection_passes_with_passes(
                &self.passes,
                encoder,
                bind_groups,
                hir_node_capacity,
            )?;
            if let Some(module_path) = &bind_groups.module_path {
                record_compute(
                    encoder,
                    &self.passes.modules_project_type_aliases,
                    &module_path.bind_groups.project_type_aliases,
                    "type_check.modules.project_type_aliases",
                    module_path.n_blocks.saturating_mul(256).max(1),
                )?;
                record_compute(
                    encoder,
                    &self.passes.modules_project_type_paths,
                    &module_path.bind_groups.project_type_paths,
                    "type_check.modules.project_type_paths.after_aliases",
                    module_path.n_blocks.saturating_mul(256).max(1),
                )?;
                record_type_instance_collection_passes_with_passes(
                    &self.passes,
                    encoder,
                    bind_groups,
                    hir_node_capacity,
                )?;
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_collect.done");
            }
            let n_work = token_capacity.max(hir_node_capacity).max(512);
            record_fn_context_bind_groups_with_passes(
                &self.passes,
                encoder,
                token_capacity,
                hir_node_capacity,
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
                &bind_groups.calls,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls.done");
            }
            record_visible_bind_groups_with_passes(
                &self.passes,
                encoder,
                token_capacity,
                hir_node_capacity,
                &bind_groups.visible_bind_groups,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.visible.done");
            }

            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances.done");
            }
            if let Some(module_path) = &bind_groups.module_path {
                record_compute(
                    encoder,
                    &self.passes.modules_project_type_instances,
                    &module_path.bind_groups.project_type_instances,
                    "type_check.modules.project_type_instances",
                    module_path.n_blocks.saturating_mul(256).max(1),
                )?;
            }
            record_compute(
                encoder,
                &self.passes.type_instances_collect_named_arg_refs,
                &bind_groups.type_instances_collect_named_arg_refs,
                "type_check.resident.type_instances_collect_named_arg_refs.pass",
                hir_node_capacity.max(1),
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_decl_refs,
                &bind_groups.type_instances_decl_refs,
                "type_check.resident.type_instances_decl_refs.pass",
                hir_node_capacity.max(1),
            )?;
            let method_lookup_work = token_capacity.saturating_mul(2).max(n_work);
            record_compute(
                encoder,
                &self.passes.methods_clear,
                &bind_groups.methods.clear,
                "type_check.resident.methods.decls.clear",
                method_lookup_work,
            )?;
            record_compute(
                encoder,
                &self.passes.methods_collect,
                &bind_groups.methods.collect,
                "type_check.resident.methods.decls.collect",
                hir_node_capacity.max(1),
            )?;
            record_compute(
                encoder,
                &self.passes.methods_attach_metadata,
                &bind_groups.methods.attach_metadata,
                "type_check.resident.methods.decls.attach_metadata",
                method_lookup_work,
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_member_receivers,
                &bind_groups.type_instances_member_receivers,
                "type_check.resident.type_instances_member_receivers.pass",
                token_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_member_results,
                &bind_groups.type_instances_member_results,
                "type_check.resident.type_instances_member_results.pass",
                token_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_member_substitute,
                &bind_groups.type_instances_member_substitute,
                "type_check.resident.type_instances_member_substitute.pass",
                token_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_struct_init_clear,
                &bind_groups.type_instances_struct_init_clear,
                "type_check.resident.type_instances_struct_init_clear.pass",
                token_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_struct_init_fields,
                &bind_groups.type_instances_struct_init_fields,
                "type_check.resident.type_instances_struct_init_fields.pass",
                n_work,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instance_fields.done");
            }
            if let Some(module_path) = &bind_groups.module_path {
                record_compute(
                    encoder,
                    &self.passes.modules_consume_value_calls,
                    &module_path.bind_groups.consume_value_calls,
                    "type_check.modules.consume_value_calls",
                    module_path.n_blocks.saturating_mul(256).max(1),
                )?;
                record_compute(
                    encoder,
                    &self.passes.modules_bind_match_patterns,
                    &module_path.bind_groups.bind_match_patterns,
                    "type_check.modules.bind_match_patterns",
                    module_path.n_blocks.saturating_mul(256).max(1),
                )?;
                record_compute(
                    encoder,
                    &self.passes.modules_type_match_payloads,
                    &module_path.bind_groups.type_match_payloads,
                    "type_check.modules.type_match_payloads",
                    n_work,
                )?;
                record_compute(
                    encoder,
                    &self.passes.modules_type_match_exprs,
                    &module_path.bind_groups.type_match_exprs,
                    "type_check.modules.type_match_exprs",
                    n_work,
                )?;
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
            record_method_bind_groups_with_passes(
                &self.passes,
                encoder,
                token_capacity,
                hir_node_capacity,
                n_work,
                &bind_groups.methods,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.methods.done");
            }
            record_compute(
                encoder,
                scope_pass,
                &bind_groups.scope,
                "type_check.resident.scope.pass",
                n_work,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.scope.done");
            }
            if let Some(module_path) = &bind_groups.module_path {
                record_compute(
                    encoder,
                    &self.passes.modules_consume_value_consts,
                    &module_path.bind_groups.consume_value_consts,
                    "type_check.modules.consume_value_consts",
                    module_path.n_blocks.saturating_mul(256).max(1),
                )?;
                record_compute(
                    encoder,
                    &self.passes.modules_consume_value_enum_units,
                    &module_path.bind_groups.consume_value_enum_units,
                    "type_check.modules.consume_value_enum_units",
                    module_path.n_blocks.saturating_mul(256).max(1),
                )?;
            }
            record_compute(
                encoder,
                &self.passes.methods_resolve,
                &bind_groups.methods.resolve,
                "type_check.resident.methods.resolve",
                token_capacity.max(hir_node_capacity).max(1),
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.methods_resolve.done");
            }
            record_compute(
                encoder,
                &self.passes.type_instances_array_index_results,
                &bind_groups.type_instances_array_index_results,
                "type_check.resident.type_instances_array_index_results.pass",
                hir_node_capacity.max(1),
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_array_return_refs,
                &bind_groups.type_instances_array_return_refs,
                "type_check.resident.type_instances_array_return_refs.pass",
                hir_node_capacity.max(1),
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_array_literal_return_refs,
                &bind_groups.type_instances_array_literal_return_refs,
                "type_check.resident.type_instances_array_literal_return_refs.pass",
                hir_node_capacity.max(1),
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_enum_ctors,
                &bind_groups.type_instances_enum_ctors,
                "type_check.resident.type_instances_enum_ctors.pass",
                token_capacity,
            )?;
            if let Some(module_path) = &bind_groups.module_path {
                record_compute(
                    encoder,
                    &self.passes.modules_consume_value_enum_calls,
                    &module_path.bind_groups.consume_value_enum_calls,
                    "type_check.modules.consume_value_enum_calls",
                    module_path.n_blocks.saturating_mul(256).max(1),
                )?;
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_late_consumers.done");
            }
            record_compute(
                encoder,
                &self.passes.type_instances_struct_init_substitute,
                &bind_groups.type_instances_struct_init_substitute,
                "type_check.resident.type_instances_struct_init_substitute.pass",
                token_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_validate_aggregate_access,
                &bind_groups.type_instances_validate_aggregate_access,
                "type_check.resident.type_instances_validate_aggregate_access.pass",
                hir_node_capacity.max(1),
            )?;
            record_compute(
                encoder,
                &self.passes.conditions_hir,
                &bind_groups.conditions_hir,
                "type_check.resident.conditions_hir.pass",
                hir_node_capacity.max(1),
            )?;
            record_compute(
                encoder,
                pass,
                &bind_groups.tokens,
                "type_check.resident.tokens.pass",
                n_work,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.tokens.done");
            }
            record_compute(
                encoder,
                control_pass,
                &bind_groups.control,
                "type_check.resident.control.pass",
                n_work,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.control.done");
            }
        }
        encoder.copy_buffer_to_buffer(&self.status_buf, 0, &self.status_readback, 0, 16);
        Ok(RecordedTypeCheck)
    }

    pub fn finish_recorded_check(
        &self,
        device: &wgpu::Device,
        _recorded: &RecordedTypeCheck,
    ) -> Result<(), GpuTypeCheckError> {
        let slice = self.status_readback.slice(..);
        crate::gpu::passes_core::map_readback_for_progress(&slice, "type_check.status");
        crate::gpu::passes_core::wait_for_map_progress(
            device,
            "type_check.status",
            wgpu::PollType::Wait,
        );
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
        guard.as_ref().map(|bind_groups| {
            consume(GpuCodegenBuffers {
                name_id_by_token: &bind_groups.name_id_by_token,
                visible_decl: &bind_groups.visible_decl,
                visible_type: &bind_groups.visible_type,
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
                method_decl_receiver_ref_tag: &bind_groups.method_decl_receiver_ref_tag,
                method_decl_receiver_ref_payload: &bind_groups.method_decl_receiver_ref_payload,
                method_decl_param_offset: &bind_groups.method_decl_param_offset,
                method_decl_receiver_mode: &bind_groups.method_decl_receiver_mode,
                method_call_receiver_ref_tag: &bind_groups.method_call_receiver_ref_tag,
                method_call_receiver_ref_payload: &bind_groups.method_call_receiver_ref_payload,
                type_instance_decl_token: &bind_groups.type_instance_decl_token,
                type_instance_arg_start: &bind_groups.type_instance_arg_start,
                type_instance_arg_count: &bind_groups.type_instance_arg_count,
                type_instance_arg_ref_tag: &bind_groups.type_instance_arg_ref_tag,
                type_instance_arg_ref_payload: &bind_groups.type_instance_arg_ref_payload,
                fn_return_ref_tag: &bind_groups.fn_return_ref_tag,
                fn_return_ref_payload: &bind_groups.fn_return_ref_payload,
                member_result_ref_tag: &bind_groups.member_result_ref_tag,
                member_result_ref_payload: &bind_groups.member_result_ref_payload,
                member_result_field_ordinal: &bind_groups.member_result_field_ordinal,
                struct_init_field_expected_ref_tag: &bind_groups.struct_init_field_expected_ref_tag,
                struct_init_field_expected_ref_payload: &bind_groups
                    .struct_init_field_expected_ref_payload,
                struct_init_field_ordinal: &bind_groups.struct_init_field_ordinal,
            })
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
