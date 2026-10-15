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

// Opt-in source fact dump only: no inference, normalization, or semantic writes.
fn trace_range_inference(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    state: &ResidentTypeCheckWorkspace,
    hir: &crate::parser::buffers::GpuHirView,
) -> Result<()> {
    let graph = &state.typecheck_graph;
    let mut columns = vec![
        ("count", hir.count.alias::<u32>(hir.count.byte_size / 4)),
        ("core", hir.core.alias::<u32>(hir.core.byte_size / 4)),
        ("payload", hir.payload.alias::<u32>(hir.payload.byte_size / 4)),
        ("expr_parent", hir.expr_parent.alias::<u32>(hir.expr_parent.byte_size / 4)),
    ];
    for name in ["call_inference_result_tag", "call_inference_result_payload",
        "literal_context_type_by_hir", "decl_type_ref_tag", "decl_type_ref_payload",
        "call_fn_index", "call_return_type", "visible_decl", "visible_type",
        "argument_expected_ref_tag", "argument_expected_ref_payload",
        "call_arg_row_count_out", "call_arg_row_node", "call_arg_row_call_node",
        "call_arg_row_ordinal", "call_arg_param_row", "call_param_row_ref_tag",
        "call_param_row_ref_payload", "call_dependency_library_id"] {
        columns.push((name, graph.u32_buffer(name)?));
    }
    let words = columns.iter().try_fold(0usize, |total, (_, buffer)| {
        total.checked_add(buffer.byte_size / 4)
            .ok_or_else(|| anyhow::anyhow!("range inference trace size overflow"))
    })?;
    let readback = readback_u32s(device, "rb.type_check.range_inference", words);
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("type-check-range-inference-trace"),
    });
    let mut offsets = Vec::new();
    let mut offset = 0usize;
    for (_, source) in &columns {
        offsets.push(offset);
        source.copy_to(&mut encoder, 0, &readback, (offset * 4) as u64, source.byte_size as u64);
        offset += source.byte_size / 4;
    }
    crate::gpu::passes_core::submit_with_progress(queue, "range inference trace", encoder.finish());
    let slice = readback.slice(..);
    crate::gpu::passes_core::map_readback_blocking(device, &slice, "type_check.range_inference")?;
    let mapped = slice.get_mapped_range();
    let data = mapped.chunks_exact(4).map(|bytes|
        u32::from_le_bytes(bytes.try_into().expect("four-byte trace word"))).collect::<Vec<_>>();
    drop(mapped);
    readback.unmap();
    let get = |column: usize, row: u32| -> u32 {
        let row = row as usize;
        if row >= columns[column].1.byte_size / 4 { return u32::MAX; }
        data[offsets[column] + row]
    };
    let count = get(0, 0).min(hir.capacity);
    let dump = |label: &str, node: u32| {
        if node >= count {
            eprintln!("[typecheck.range_inference] {label} node={node} invalid");
            return;
        }
        let core = [get(1,node*4),get(1,node*4+1),get(1,node*4+2),get(1,node*4+3)];
        let value = [get(2,node*4),get(2,node*4+1),get(2,node*4+2),get(2,node*4+3)];
        eprintln!("[typecheck.range_inference] {label} node={node} core={core:?} payload={value:?} expr_parent={} result=({}, {}) literal_context={} expected=({}, {})",
            get(3,node),get(4,node),get(5,node),get(6,node),get(13,node),get(14,node));
    };
    let dump_forward_chain = |label: &str, mut node: u32| {
        for _ in 0..count {
            dump(label,node);
            if node >= count { break; }
            let kind=get(1,node*4); let form=get(2,node*4);
            if !matches!(kind,14|16|17) || form != 1 { break; }
            let next=get(2,node*4+1); if next == node { break; } node=next;
        }
        node
    };
    eprintln!("[typecheck.range_inference] converged hir_count={count}");
    for node in 0..count {
        let kind=get(1,node*4); let form=get(2,node*4);
        if kind == 30 || (kind == 7 && form == 7) {
            dump("for",node);
            let binder=get(2,node*4+1);
            eprintln!("[typecheck.range_inference] binder token={binder} ref=({}, {}) visible=({}, {})",
                get(7,binder),get(8,binder),get(11,binder),get(12,binder));
            let iterable=dump_forward_chain("iterable",get(2,node*4+2));
            if iterable < count && matches!(get(1,iterable*4),14|16) &&
                (30..=35).contains(&get(2,iterable*4)) {
                dump_forward_chain("start",get(2,iterable*4+1));
                dump_forward_chain("end",get(2,iterable*4+2));
            }
        }
        // All calls are printed so a missing range edge cannot hide its actual
        // endpoint call. Raw HIR/token identities permit exact source pairing.
        if kind == 19 {
            dump("call",node);
            let callee=get(2,node*4); dump("callee",callee);
            if callee < count {
                let kind=get(1,callee*4);
                let token=if kind==21 {get(2,callee*4+2)} else {get(2,callee*4+3)};
                let token=if token < state.cache_key.token_capacity {token} else {get(1,callee*4+2)};
                eprintln!("[typecheck.range_inference] callee_token={token} fn={} return={} visible=({}, {}) dependency={}",
                    get(9,token),get(10,token),get(11,token),get(12,token),get(22,token));
            }
        }
    }
    let argument_count = get(15, 0).min(hir.capacity);
    for row in 0..argument_count {
        let node = get(16,row); let call = get(17,row); let parameter = get(19,row);
        eprintln!("[typecheck.range_inference] argument row={row} call={call} ordinal={} parameter={parameter} parameter_ref=({}, {})",
            get(18,row),get(20,parameter),get(21,parameter));
        dump_forward_chain("argument",node);
    }
    Ok(())
}

/// Submits the recorded work and reads a small host-visible buffer.
fn submit_and_read_u32s(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    readback: &LaniusBuffer<u32>,
    label: &'static str,
) -> Result<Vec<u32>> {
    crate::gpu::passes_core::flush_deferred_compute(encoder);
    let next = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("type-check-canonical-encoder"),
    });
    let recorded = std::mem::replace(encoder, next);
    crate::gpu::passes_core::submit_with_progress(queue, label, recorded.finish());
    let slice = readback.slice(..);
    crate::gpu::passes_core::map_readback_blocking(device, &slice, label)?;
    let words = slice
        .get_mapped_range()
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().expect("four-byte word")))
        .collect();
    readback.unmap();
    Ok(words)
}

/// Interns canonical type identities (docs/canonical-type-ids.md): the first
/// batch of rounds, then one more batch per counter readback that still
/// reports pending candidates. The GPU's round limit finalizes every
/// candidate within the last batch.
fn record_canonical_types(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    canonical: &CanonicalTypeOperations,
    stage: CanonicalStage,
    counts_readback: &LaniusBuffer<u32>,
    validation_readback: &LaniusBuffer<u32>,
) -> Result<()> {
    canonical.record_first_batch(encoder, stage)?;
    let trace = crate::gpu::env::env_bool_truthy("LANIUS_TRACE_CANONICAL", false);
    let batches = canonical_passes::CANONICAL_MAX_ROUNDS / canonical_passes::CANONICAL_ROUNDS_PER_BATCH;
    for batch in 0..batches {
        let counts =
            submit_and_read_u32s(device, queue, encoder, counts_readback, "type_check.canonical")?;
        let pending = counts[canonical_passes::CANONICAL_COUNT_PENDING];
        let overflow = counts[canonical_passes::CANONICAL_COUNT_OVERFLOW];
        if trace || overflow != 0 {
            eprintln!(
                "[typecheck.canonical] stage={} batch={batch} rounds={} pending={pending} records={} args={} overflow={overflow:#x}",
                stage.label(),
                counts[canonical_passes::CANONICAL_COUNT_ROUND],
                counts[0],
                counts[1],
            );
        }
        if pending == 0 || batch + 1 == batches {
            break;
        }
        canonical.record_batch(encoder, stage)?;
    }
    if stage == CanonicalStage::Late && canonical_passes::canonical_validation_enabled() {
        canonical.record_validation(encoder)?;
        let words = submit_and_read_u32s(
            device,
            queue,
            encoder,
            validation_readback,
            "type_check.canonical.validation",
        )?;
        eprintln!("{}", canonical_passes::canonical_validation_report(&words));
    }
    Ok(())
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
                // Program catalogs own these pipelines separately and can outlive
                // source-job workspaces. Source checking never dispatches them.
                if key.starts_with("type_checker/program_evidence/") {
                    return false;
                }
                if canonical_passes::CANONICAL_DEBUG_KERNELS.contains(&key)
                    && !canonical_passes::canonical_validation_enabled()
                {
                    return false;
                }
                (key != "type_checker/predicates/01b2_sort_keys_small"
                    || supports_large_workgroup_storage)
                    && (!key.starts_with("scan/counted_pair/")
                        || device.limits().max_storage_buffers_per_shader_stage >= 7)
            },
        )?;
        let params_buf = zeroed_type_check_params_buffer(device, "type_check.resident.params");
        let body_specialization_inputs = storage_ro_from_u32s(
            device,
            "type_check.body_specialization_inputs",
            &[0; generic_body::BODY_SPECIALIZATION_WORDS],
        );
        // An absent interface still has a valid, immutable zero-count page.
        // It must never alias workspace columns written by the same shader.
        let empty_dependency_words = storage_ro_from_u32s(
            device,
            "type_check.empty_dependency_words",
            &[0; dependency_interface::HEADER_WORDS],
        );
        let status_buf = typed_storage_u32_rw(
            device,
            "type_check.resident.status",
            4,
            wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
        );
        let status_readback = readback_u32s(device, "rb.type_check.resident.status", 4);
        let call_inference_state = typed_storage_u32_rw(
            device,
            "type_check.calls.inference_state",
            2,
            wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
        );
        let call_inference_readback = readback_u32s(device, "rb.type_check.calls.inference", 2);
        let canonical_counts_readback = readback_u32s(
            device,
            "rb.type_check.canonical.counts",
            canonical_passes::CANONICAL_COUNT_WORDS,
        );
        let canonical_validation_readback = readback_u32s(
            device,
            "rb.type_check.canonical.validation",
            canonical_passes::CANONICAL_VALIDATION_WORDS,
        );
        let preflight_graph = preflight::TypeCheckPreflightGraph::new(device, &passes)?;

        Ok(Self {
            passes,
            params_buf,
            body_specialization_inputs,
            empty_dependency_words,
            status_buf,
            status_readback,
            call_inference_state,
            call_inference_readback,
            canonical_counts_readback,
            canonical_validation_readback,
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
        // Packed expression facts reserve the low 27-bit all-ones link as
        // absent. Reject capacity overflow before creating or packing rows.
        if hir_node_capacity >= crate::primitive_types::SCALAR_TYPE_LINK_MASK {
            return Err(GpuTypeCheckError::Rejected {
                token: 0,
                code: GpuTypeCheckCode::BadHir,
                detail: hir_node_capacity,
            });
        }
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
        // Every job and parser-capacity retry overwrites both policy words.
        // Resident workspace reuse must not retain a previous replay's authority.
        let (trait_obligation_mode, authorized_replay_callable) =
            hir_items.frontend_trait_check.shader_words();
        let params = TypeCheckParams {
            n_tokens: token_capacity,
            source_len,
            n_hir_nodes: hir_node_capacity,
            n_source_files: source_file_capacity,
            parser_feature_flags: hir_items.parser_feature_flags,
            dependency_interfaces_present: u32::from(dependency_pages.is_some()),
            retain_callable_owners: u32::from(hir_items.semantic_interface_required),
            trait_obligation_mode,
            authorized_replay_callable,
            canonical_library_id: dependency_pages
                .map_or(canonical_passes::CANONICAL_NO_LIBRARY, |pages| pages.current_library_id()),
            canonical_unit_id: dependency_pages
                .map_or(canonical_passes::CANONICAL_NO_LIBRARY, |pages| pages.current_unit_id()),
        };
        self.params_buf
            .write(queue, 0, &type_check_params_bytes(&params));
        self.status_buf.write(queue, 0, &status_init_bytes());
        let dependency_types_present =
            dependency_pages.is_some_and(GpuDependencyInterfacePages::has_type_references);
        let application_types_required =
            generic_param_record_passes_required(hir_items.parser_feature_flags)
                || dependency_types_present;
        let defer_inference = 1u8;
        self.call_inference_state
            .write(queue, 0, &[defer_inference, 0, 0, 0, 0, 0, 0, 0]);
        let specialization = hir_items
            .body_specialization
            .map(CheckedBodySpecialization::packet)
            .transpose()
            .map_err(GpuTypeCheckError::Gpu)?
            .unwrap_or([0; generic_body::BODY_SPECIALIZATION_WORDS]);
        let specialization_bytes: Vec<u8> = specialization
            .into_iter()
            .flat_map(u32::to_le_bytes)
            .collect();
        self.body_specialization_inputs
            .write(queue, 0, &specialization_bytes);
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
                Some(bind_groups.semantic_artifact(
                    hir_items.hir,
                    parser_feature_flags,
                    dependency_interfaces.is_some(),
                    hir_items.semantic_interface_required,
                )?);
            let module_path = &bind_groups.module_path;
            let pattern_pages = DependencyPatternReplay {
                device,
                queue,
                pages: dependency_pages,
                passes: &self.passes,
                state: module_path,
            };
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
            let aliases_required = module_path.bind_groups.type_aliases.is_some();

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
            // Initialize every constant partition before the first dependency page.
            bind_groups.type_instances.clear_constants.record(encoder)?;
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
            let canonical = &bind_groups.semantic_projection.canonical_types;
            canonical.record_clear(encoder)?;
            if let Some(dependency_visibility) = &module_path.dependency_visibility {
                // Each page interns its signature types while it is resident.
                let intern_page = |encoder: &mut wgpu::CommandEncoder| {
                    record_canonical_types(
                        device,
                        queue,
                        encoder,
                        canonical,
                        CanonicalStage::Dependency,
                        &self.canonical_counts_readback,
                        &self.canonical_validation_readback,
                    )
                };
                let record_projection = |encoder: &mut wgpu::CommandEncoder| {
                    record_dependency_type_index(
                        &self.passes,
                        encoder,
                        module_path,
                        DEPENDENCY_TYPE_INDEX_TYPE_INSTANCE_PROJECTION,
                    )?;
                    dependency_visibility
                        .project_type_instances_group
                        .record(encoder)?;
                    intern_page(encoder)
                };
                if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                    record_each_dependency_page(device, queue, encoder, pages, record_projection)?;
                } else {
                    dependency_visibility
                        .project_type_instances_group
                        .record(encoder)?;
                    if dependency_pages.is_some() {
                        intern_page(encoder)?;
                    }
                }
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
            bind_groups.type_instances.collection.constant_scalars.record_invocation(
                encoder, &bind_groups.type_instances.collection.alias_constant_scalars,
            )?;
            if aggregates_required {
                // Snapshot child refs only after every dependency page has
                // replaced imported nominal roots with persistent instances.
                // Alias normalization must never receive page-local tag 5
                // through a cached array, slice, or reference child edge.
                let collection = &bind_groups.type_instances.collection;
                collection.aggregate_details.record_invocation(
                    encoder,
                    &collection.projected_aggregate_details,
                )?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(
                        encoder,
                        super::record::TYPE_INSTANCE_COLLECTION_PROJECTED_LABELS.aggregate_details,
                    );
                }
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
            if let Some(dependency_visibility) = &module_path.dependency_visibility {
                let materialize_alias_targets = |encoder: &mut wgpu::CommandEncoder| {
                    record_dependency_type_index(
                        &self.passes, encoder, module_path, DEPENDENCY_TYPE_INDEX_ALIAS_TARGETS,
                    )?;
                    dependency_visibility.materialize_alias_targets_group.record(encoder)
                };
                if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                    record_each_dependency_page(device, queue, encoder, pages, materialize_alias_targets)?;
                } else {
                    materialize_alias_targets(encoder)?;
                }
            }
            if aliases_required {
                module_path
                    .bind_groups
                    .type_aliases
                    .as_ref()
                    .expect("alias operations exist for local syntax or imported types")
                    .record_instances(encoder)?;
            }
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_named_arg_refs.done");
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
            record_canonical_types(
                device,
                queue,
                encoder,
                &bind_groups.semantic_projection.canonical_types,
                CanonicalStage::Early,
                &self.canonical_counts_readback,
                &self.canonical_validation_readback,
            )?;
            if let Some(index) = &bind_groups.type_instances.index_closed_applications {
                index.record(encoder)?;
            }
            if let Some(producer) = &bind_groups.type_instances.materialize_applications {
                producer.record(encoder)?;
            }
            if let Some(index) = &bind_groups.type_instances.index_generated_applications {
                index.record(encoder)?;
            }
            if let Some(project) = &bind_groups.type_instances.project_imported_fields {
                project.record(encoder)?;
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
                    .nested_struct_init_contexts
                    .record(encoder)?;
                if let Some(dependency_visibility) = &module_path.dependency_visibility {
                    let project = |encoder: &mut wgpu::CommandEncoder| {
                        record_dependency_type_index(
                            &self.passes,
                            encoder,
                            module_path,
                            DEPENDENCY_TYPE_INDEX_TYPE_INSTANCE_PROJECTION,
                        )?;
                        dependency_visibility
                            .project_struct_literals_group
                            .record(encoder)
                    };
                    if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                        record_each_dependency_page(device, queue, encoder, pages, project)?;
                    } else {
                        dependency_visibility
                            .project_struct_literals_group
                            .record(encoder)?;
                    }
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
                if members_required {
                    bind_groups
                        .type_instances
                        .member_receivers
                        .record_invocation(
                            encoder,
                            &bind_groups.type_instances.member_receivers_after_match,
                        )?;
                    bind_groups
                        .type_instances
                        .member_results
                        .record_invocation(
                            encoder,
                            &bind_groups.type_instances.member_results_after_match,
                        )?;
                    bind_groups
                        .type_instances
                        .member_substitute
                        .record_invocation(
                            encoder,
                            &bind_groups.type_instances.member_substitute_after_match,
                        )?;
                }
            }
            // Bound-member method selection reads accepted bounds, their owner
            // chains and member contracts in every method transaction.
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
                .record(encoder, CallArgumentMatchStage::Direct, &pattern_pages)?;
            bind_groups
                .calls
                .apply_row_args
                .record_as(encoder, CallArgumentMatchStage::Direct.operation_names().2)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls_row_args.done");
            }
            let record_method_pages = |encoder: &mut wgpu::CommandEncoder,
                                       stage: MethodSelectionStage,
                                       collect: bool| -> Result<()> {
                let page = |encoder: &mut wgpu::CommandEncoder| -> Result<()> {
                    record_dependency_type_index(
                        &self.passes, encoder, module_path,
                        match stage {
                            MethodSelectionStage::Direct => DEPENDENCY_TYPE_INDEX_METHOD_PROJECTION,
                            MethodSelectionStage::Lookup => DEPENDENCY_TYPE_INDEX_METHOD_LOOKUP,
                            MethodSelectionStage::Inference => DEPENDENCY_TYPE_INDEX_RETURN_MATERIALIZATION,
                        },
                    )?;
                    record_dependency_methods(encoder, module_path, stage, collect)
                };
                if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                    record_each_dependency_page(device, queue, encoder, pages, page)
                } else {
                    page(encoder)
                }
            };
            if methods_required {
                // Imported results can establish an unannotated receiver.
                bind_groups.type_instances.infer_imported_decl_refs.record(encoder)?;
                // Local and imported methods compete in the initial transaction.
                bind_groups.methods.keys.record(encoder)?;
                bind_groups.methods.record_call_selection(
                    encoder, MethodSelectionStage::Direct,
                    |encoder, collect| record_method_pages(encoder, MethodSelectionStage::Direct, collect),
                )?;
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
                .record(encoder, CallArgumentMatchStage::ModuleValues, &pattern_pages)?;
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
                bind_groups.methods.record_call_resolution(encoder, |encoder, collect| {
                    record_method_pages(encoder, MethodSelectionStage::Lookup, collect)
                })?;
            }
            bind_groups.calls.project_result_instances.record(encoder)?;
            bind_groups
                .calls
                .argument_matching
                .record(encoder, CallArgumentMatchStage::MethodResults, &pattern_pages)?;
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
                .record(encoder, CallArgumentMatchStage::MethodModules, &pattern_pages)?;
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
            }
            if generic_call_claim_passes_required(parser_feature_flags) || dependency_types_present
            {
                record_call_erase_generic_params_with_passes(encoder, &bind_groups.calls)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.calls_erased.done");
                }
            }
            if enums_required || dependency_types_present {
                // A unit variant may itself be an argument to a payload-bearing
                // variant constructor. Publish its type before validating the
                // outer constructor's payloads.
                module_path
                    .bind_groups
                    .consume_value_enum_units
                    .record(encoder)?;
            }
            if enums_required {
                module_path
                    .bind_groups
                    .consume_value_enum_calls
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
            bind_groups
                .type_instances
                .infer_imported_decl_refs
                .record(encoder)?;
            if methods_required {
                bind_groups.methods.resolve.record(encoder)?;
            }
            for operation in [
                &bind_groups.calls.return_type_index_clear,
                &bind_groups.calls.return_type_source_index,
            ]
            .into_iter()
            .flatten()
            {
                if application_types_required {
                    operation.record(encoder)?;
                }
            }
            // Every winner change invalidates the old impl environment. Rebuild
            // explicit and inferred claims before materializing under the winner.
            let regenerate_call_claims = |encoder: &mut wgpu::CommandEncoder| -> Result<()> {
                bind_groups.calls.explicit_application_binding.record(encoder)?;
                bind_groups.calls.environment_admission.record_explicit(encoder)?;
                bind_groups
                    .calls
                    .argument_matching
                    .record(encoder, CallArgumentMatchStage::Final, &pattern_pages)?;
                if aggregates_required {
                    bind_groups
                        .calls
                        .clear_generic_claim_type_args
                        .record(encoder)?;
                }
                if generic_call_claim_passes_required(parser_feature_flags)
                    || dependency_types_present
                {
                    bind_groups
                        .calls
                        .generic_claim_validation
                        .record_claims(encoder, &pattern_pages)?;
                }
                if aggregates_required {
                    bind_groups.calls.contextual_result_requests.record(encoder)?;
                    bind_groups.calls.environment_admission.record_context(
                        encoder,
                        ContextConstantProducer::ResultRequests,
                    )?;
                }
                if let Some(visibility) = module_path
                    .dependency_visibility
                    .as_ref()
                    .filter(|_| dependency_types_present)
                {
                    let contextual_results =
                        |encoder: &mut wgpu::CommandEncoder| -> Result<()> {
                            record_dependency_type_index(
                                &self.passes,
                                encoder,
                                module_path,
                                DEPENDENCY_TYPE_INDEX_RETURN_MATERIALIZATION,
                            )?;
                            visibility.validate_call_results_group.record_invocation(
                                encoder,
                                &visibility.generic_call_results_resolve,
                            )
                        };
                    if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                        record_each_dependency_page(
                            device,
                            queue,
                            encoder,
                            pages,
                            contextual_results,
                        )?;
                    } else {
                        contextual_results(encoder)?;
                    }
                }
                if aggregates_required {
                    bind_groups
                        .aggregate_comparison
                        .record(encoder, AggregateComparisonStage::Calls)?;
                }
                bind_groups.calls.apply_row_args.record_as(
                    encoder,
                    CallArgumentMatchStage::Final.operation_names().2,
                )?;
                Ok(())
            };
            let materialize_returns = |encoder: &mut wgpu::CommandEncoder| -> Result<()> {
                if dependency_types_present {
                    record_dependency_type_index(
                        &self.passes,
                        encoder,
                        module_path,
                        DEPENDENCY_TYPE_INDEX_RETURN_MATERIALIZATION,
                    )?;
                }
                if methods_required {
                    if let Some(operation) = &bind_groups.calls.bind_method_receiver_environment {
                        operation.record(encoder)?;
                    }
                }
                // Publish receiving parameter types before literal fields can
                // choose a default type. Record and call results then consume
                // the same immutable argument-context snapshot.
                if let Some(contexts) = &bind_groups.calls.project_argument_contexts {
                    contexts.record(encoder)?;
                }
                if let Some(records) = &bind_groups.calls.record_literal_inference {
                    if let Some(index) = &bind_groups.calls.return_type_index {
                        index.record_as(encoder, compiler_graph::CALLS_ARGUMENT_CONTEXT_TYPE_INDEX_PASS)?;
                    }
                    records.contexts.record(encoder)?;
                    bind_groups.calls.environment_admission.record_context(
                        encoder,
                        ContextConstantProducer::RecordContexts,
                    )?;
                }
                for operation in [
                    &bind_groups.calls.materialize_return_types,
                    &bind_groups.calls.expand_application_fields,
                    &bind_groups.calls.materialize_match_payloads,
                    &bind_groups.calls.return_type_index,
                    &bind_groups.calls.return_imported_fields,
                ]
                .into_iter()
                .flatten()
                {
                    operation.record(encoder)?;
                }
                Ok(())
            };
            let record_returns = |encoder: &mut wgpu::CommandEncoder| -> Result<()> {
                if methods_required {
                    bind_groups.methods.record_call_selection(
                        encoder, MethodSelectionStage::Inference,
                        |encoder, collect| record_method_pages(encoder, MethodSelectionStage::Inference, collect),
                    )?;
                }
                regenerate_call_claims(encoder)?;
                if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                    record_each_dependency_page(
                        device,
                        queue,
                        encoder,
                        pages,
                        &materialize_returns,
                    )?;
                } else {
                    materialize_returns(encoder)?;
                }
                if members_required {
                    bind_groups
                        .type_instances
                        .member_receivers
                        .record_invocation(
                            encoder,
                            &bind_groups.type_instances.member_receivers_inference,
                        )?;
                    bind_groups
                        .type_instances
                        .member_results
                        .record_invocation(
                            encoder,
                            &bind_groups.type_instances.member_results_inference,
                        )?;
                    bind_groups
                        .type_instances
                        .member_substitute
                        .record_invocation(
                            encoder,
                            &bind_groups.type_instances.member_substitute_inference,
                        )?;
                }
                if matches_required {
                    module_path
                        .bind_groups
                        .type_match_payloads
                        .record_as(encoder, MATCH_PAYLOADS_TYPE_INFERENCE.name)?;
                    module_path
                        .bind_groups
                        .type_match_exprs
                        .record_as(encoder, MATCH_EXPRS_TYPE_INFERENCE.name)?;
                }
                if let Some(records) = &bind_groups.calls.record_literal_inference {
                    records.nested_contexts.record(encoder)?;
                    if let Some(visibility) = module_path.dependency_visibility.as_ref() {
                        let project = |encoder: &mut wgpu::CommandEncoder| {
                            record_dependency_type_index(
                                &self.passes,
                                encoder,
                                module_path,
                                DEPENDENCY_TYPE_INDEX_RETURN_MATERIALIZATION,
                            )?;
                            visibility.project_struct_literals_group.record_as(
                                encoder,
                                compiler_graph::CALLS_RECORD_IMPORTED_FIELDS_PASS,
                            )
                        };
                        if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                            record_each_dependency_page(device, queue, encoder, pages, project)?;
                        } else {
                            project(encoder)?;
                        }
                    }
                    records.fields.record(encoder)?;
                    records.references.record(encoder)?;
                }
                if enums_required || dependency_types_present {
                    module_path.bind_groups.consume_value_enum_units.record_as(
                        encoder, VALUE_ENUM_UNITS_CONSUME_INFERENCE.name,
                    )?;
                }
                if let Some(project) = &bind_groups.calls.project_literal_contexts {
                    project.record(encoder)?;
                }
                if let Some(project) = &bind_groups.calls.project_expression_types {
                    project.record(encoder)?;
                }
                if let Some(pass) = &bind_groups.calls.project_array_literal_elements {
                    pass.record(encoder)?;
                }
                if let Some(pass) = &bind_groups.calls.materialize_array_literals {
                    pass.record(encoder)?;
                }
                if let Some(pass) = &bind_groups.calls.validate_array_literals {
                    pass.record(encoder)?;
                }
                if let Some(infer) = &bind_groups.calls.infer_return_bindings {
                    // Named iteration contracts retain their stable kind and
                    // exact element type while their declaration page is resident.
                    // Nonresident pages do not clear another page's publication.
                    if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                        record_each_dependency_page(device, queue, encoder, pages, |encoder| {
                            infer.record(encoder)
                        })?;
                    } else {
                        infer.record(encoder)?;
                    }
                }
                if methods_required {
                    bind_groups
                        .methods
                        .resolve
                        .record_as(encoder, METHODS_RESOLVE_INFERENCE.name)?;
                }
                Ok(())
            };
            if bind_groups.calls.materialize_return_types.is_some() {
                // A call can depend on an earlier inferred call result. Close
                // the checked type facts before required-parameter validation;
                // an arbitrary number of fixed sweeps cannot express this.
                // Each round publishes accepted GPU facts only. The host reads
                // a progress count and neither infers types nor guesses layouts.
                let round_limit = hir_node_capacity
                    .max(1)
                    .saturating_mul(compiler_graph::CALL_INFERENCE_ROUND_FACTOR);
                let trace_inference =
                    crate::gpu::env::env_bool_truthy("LANIUS_TRACE_CALL_INFERENCE", false);
                for round in 0..round_limit {
                    self.call_inference_state
                        .write(queue, 0, &[1, 0, 0, 0, 0, 0, 0, 0]);
                    record_returns(encoder)?;
                    bind_groups.calls.inference_readback.record(encoder);
                    let next = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                        label: Some("type-check-call-inference-encoder"),
                    });
                    let recorded = std::mem::replace(encoder, next);
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "type-check call inference",
                        recorded.finish(),
                    );
                    let slice = self.call_inference_readback.slice(..);
                    crate::gpu::passes_core::map_readback_blocking(
                        device,
                        &slice,
                        "type_check.call_inference",
                    )?;
                    let mapped = slice.get_mapped_range();
                    let changed = u32::from_le_bytes(
                        mapped[4..8]
                            .try_into()
                            .expect("two-word inference readback"),
                    );
                    drop(mapped);
                    self.call_inference_readback.unmap();
                    if trace_inference {
                        eprintln!("[typecheck.call_inference] round={round} changed={changed}");
                    }
                    if changed == 0 {
                        if crate::gpu::env::env_bool_truthy("LANIUS_TRACE_RANGE_INFERENCE", false) {
                            trace_range_inference(device, queue, bind_groups, hir_items.hir)?;
                        }
                        break;
                    }
                    if round + 1 == round_limit {
                        return Err(GpuTypeCheckError::Rejected {
                            token: 0,
                            code: GpuTypeCheckCode::GenericInstantiationBoundary,
                            detail: 5,
                        });
                    }
                }
                // The same producer diagnoses missing or unsupported types
                // after inference has stopped producing new facts.
                self.call_inference_state.write(queue, 0, &[0; 8]);
                if aggregates_required {
                    bind_groups
                        .calls
                        .contextual_result_requests
                        .record_as(encoder, CALLS_CONTEXTUAL_RESULTS_FINAL.name)?;
                    bind_groups.calls.environment_admission.record_context(
                        encoder,
                        ContextConstantProducer::FinalResultRequests,
                    )?;
                }
                record_returns(encoder)?;
            } else {
                self.call_inference_state.write(queue, 0, &[0; 8]);
                // Even jobs with no materializer require current argument
                // claims and a final method selection before strict checks.
                record_returns(encoder)?;
            }
            if enums_required || dependency_types_present {
                module_path.bind_groups.consume_value_enum_units.record_as(
                    encoder, VALUE_ENUM_UNITS_CONSUME_AFTER_INFERENCE.name,
                )?;
            }
            if enums_required {
                // Refresh derived name/type caches after shared call inference.
                // Generic argument and result validation owns acceptance.
                module_path
                    .bind_groups
                    .consume_value_enum_calls
                    .record_as(encoder, VALUE_ENUM_CALLS_CONSUME_AFTER_INFERENCE.name)?;
                module_path
                    .bind_groups
                    .finalize_value_enum_calls
                    .record_as(encoder, VALUE_ENUM_CALLS_FINALIZE_AFTER_INFERENCE.name)?;
            }
            if generic_call_claim_passes_required(parser_feature_flags) || dependency_types_present
            {
                bind_groups
                    .calls
                    .generic_claim_validation
                    .record_required(encoder)?;
            }
            if arrays_required {
                bind_groups.calls.validate_array_results.record(encoder)?;
                if let Some(timer) = timer.as_deref_mut() {
                    timer.stamp(encoder, "typecheck.calls_validate_array_results.done");
                }
            }
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
            // Call closure can infer an enum scrutinee's complete type. Its
            // payload bindings must be available before final member checking,
            // including when the declaration has no source annotation.
            if matches_required {
                module_path
                    .bind_groups
                    .type_match_payloads
                    .record_as(encoder, MATCH_PAYLOADS_TYPE_AFTER_CALLS.name)?;
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
            // Array literals validate against substituted struct-field contexts.
            if structs_required {
                bind_groups
                    .type_instances
                    .struct_init_substitute
                    .record(encoder)?;
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
            // Pattern validation consumes closed actual references, including
            // member/index results. Provisional declaration caches cannot
            // establish the nominal family of a compound scrutinee.
            if matches_required {
                module_path
                    .bind_groups
                    .validate_imported_unit_patterns
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
            predicates.collect_impls.record(encoder)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.predicates_collect.done");
            }
            predicates.emit_method_validation_rows.record(encoder)?;
            predicates
                .emit_method_param_validation_rows
                .record(encoder)?;
            if methods_required && module_path.dependency_visibility.is_some() {
                let validate = |encoder: &mut wgpu::CommandEncoder| {
                    record_dependency_type_index(&self.passes, encoder, module_path,
                        DEPENDENCY_TYPE_INDEX_TRAIT_CONTRACTS)?;
                    predicates.validate_imported_methods.record(encoder)
                };
                if let Some(pages) = dependency_pages.filter(|pages| pages.len() > 1) {
                    record_each_dependency_page(device, queue, encoder, pages, validate)?;
                } else {
                    validate(encoder)?;
                }
            }
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
            if hir_items.body_specialization.is_some() {
                for (required_feature, operation) in
                    &bind_groups.semantic_projection.body_specialization
                {
                    if *required_feature != 0 && parser_feature_flags & required_feature == 0 {
                        continue;
                    }
                    operation.record(encoder)?;
                }
            }
            bind_groups.semantic_projection.calls.record(encoder)?;
            bind_groups
                .semantic_projection
                .generic_call_results
                .record(encoder)?;
            record_canonical_types(
                device,
                queue,
                encoder,
                &bind_groups.semantic_projection.canonical_types,
                CanonicalStage::Late,
                &self.canonical_counts_readback,
                &self.canonical_validation_readback,
            )?;
            bind_groups
                .semantic_projection
                .generic_native_words
                .record(encoder)?;
            if hir_items.body_specialization.is_some() {
                bind_groups.semantic_projection.body_native_layout_admission.record(encoder)?;
            }
            if members_required {
                bind_groups
                    .semantic_projection
                    .member_layout
                    .record(encoder)?;
            }
            if hir_items.semantic_interface_required {
                bind_groups
                    .semantic_projection
                    .retained_callables
                    .record(encoder)?;
            }
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
            bind_groups.calls.explicit_application_validation.record(encoder)?;
            bind_groups.calls.environment_admission.record_context(
                encoder,
                ContextConstantProducer::ExplicitValidation,
            )?;
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
        if words[2] == 6 && words[3] & 0xffff_0000 == 0x474e_0000 {
            return Err(GpuTypeCheckError::Rejected {
                token: words[1],
                code: GpuTypeCheckCode::GenericInstantiationBoundary,
                detail: words[3] & 0xffff,
            });
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
        let generic_param_lookup_state = state
            .typecheck_graph
            .u32_buffer("generic_param_lookup_state")
            .ok()?;
        let generic_decl_owner_by_node_a = state
            .typecheck_graph
            .u32_buffer("generic_decl_owner_by_node_a")
            .ok()?;
        let resolved_dependency_trait_header = if module_path.dependency_visibility.is_some() {
            state.typecheck_graph.u32_buffer("resolved_dependency_trait_header").ok()?
        } else {
            self.empty_dependency_words.clone()
        };
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
                .unwrap_or_else(|| (&self.empty_dependency_words).into()),
            resolved_dependency_unit_id: module_path
                .dependency_visibility
                .as_deref()
                .map(|visibility| (&visibility.resolved_dependency_unit_id).into())
                .unwrap_or_else(|| (&self.empty_dependency_words).into()),
            resolved_dependency_local_index: module_path
                .dependency_visibility
                .as_deref()
                .map(|visibility| (&visibility.resolved_dependency_local_index).into())
                .unwrap_or_else(|| (&self.empty_dependency_words).into()),
            resolved_dependency_trait_header: (&resolved_dependency_trait_header).into(),
            path_id_by_owner_hir: (&module_path.path_id_by_owner_hir).into(),
            path_id_by_owner_token: (&module_path.path_id_by_owner_token).into(),
            resolved_type_decl: (&module_path.resolved_type_decl).into(),
            decl_id_by_name_token: (&module_path.decl_id_by_name_token).into(),
            generic_param_count_out: (&generic_param_count_out).into(),
            generic_param_owner_token: (&generic_param_owner_token).into(),
            generic_param_name_id: (&generic_param_name_id).into(),
            generic_param_token: (&generic_param_token).into(),
            generic_param_kind: (&generic_param_kind).into(),
            generic_param_lookup_state: (&generic_param_lookup_state).into(),
            generic_decl_owner_by_node_a: (&generic_decl_owner_by_node_a).into(),
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
