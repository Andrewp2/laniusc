use super::*;

pub(super) struct WasmObjectInputBuffers {
    public_decl_count: wgpu::Buffer,
    public_decl_local_id: wgpu::Buffer,
    public_decl_index_by_local: wgpu::Buffer,
    decl_id_by_name_token: wgpu::Buffer,
    decl_hir_node: wgpu::Buffer,
    compact_hir_count: wgpu::Buffer,
    compact_hir_core: wgpu::Buffer,
}

impl WasmObjectInputBuffers {
    pub(super) fn from_codegen_inputs(inputs: GpuWasmCodegenInputs<'_>) -> Self {
        Self {
            public_decl_count: inputs.public_decl_count.clone(),
            public_decl_local_id: inputs.public_decl_local_id.clone(),
            public_decl_index_by_local: inputs.public_decl_index_by_local.clone(),
            decl_id_by_name_token: inputs.decl_id_by_name_token.clone(),
            decl_hir_node: inputs.decl_hir_node.clone(),
            compact_hir_count: inputs.canonical_hir.count.clone(),
            compact_hir_core: inputs.canonical_hir.core.clone(),
        }
    }
}

struct WasmObjectProjection {
    scan_param_bufs: Vec<LaniusBuffer<WasmScanParams>>,
    function_record: LaniusBuffer<u32>,
    body_len_by_slot: LaniusBuffer<u32>,
    body_scan_local_prefix: LaniusBuffer<u32>,
    body_scan_block_sum: LaniusBuffer<u32>,
    body_scan_prefix_a: LaniusBuffer<u32>,
    body_scan_prefix_b: LaniusBuffer<u32>,
    symbol_record: LaniusBuffer<u32>,
    type_words: LaniusBuffer<u32>,
    body_words: LaniusBuffer<u32>,
    metadata: LaniusBuffer<u32>,
    functions_bind_group: wgpu::BindGroup,
    body_scan_local_bind_group: wgpu::BindGroup,
    body_scan_block_bind_groups: Vec<wgpu::BindGroup>,
    function_bodies_bind_group: wgpu::BindGroup,
    symbols_bind_group: wgpu::BindGroup,
    bytes_bind_group: wgpu::BindGroup,
    metadata_bind_group: wgpu::BindGroup,
}

impl GpuWasmCodeGenerator {
    fn create_wasm_object_projection(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        bufs: &ResidentWasmBuffers,
        recorded: &RecordedWasmCodegen,
    ) -> Result<WasmObjectProjection> {
        let token_capacity = recorded.token_capacity.max(1);
        let output_capacity = recorded.output_capacity;
        let scan_steps = scan_steps_for_blocks(bufs.func_scan_blocks as usize);
        let scan_param_bufs = create_wasm_scan_param_buffers(
            device,
            "codegen.wasm.object.body_scan.params",
            scan_steps.len(),
        );
        for (params, scan_step) in scan_param_bufs.iter().zip(scan_steps) {
            let value = WasmScanParams {
                n_items: token_capacity,
                n_blocks: bufs.func_scan_blocks,
                scan_step,
                out_capacity: output_capacity as u32,
            };
            queue.write_buffer(params, 0, &wasm_scan_params_bytes(&value));
        }

        let function_record = storage_u32_rw(
            device,
            "codegen.wasm.object.function_record",
            token_capacity as usize * 6,
            wgpu::BufferUsages::COPY_SRC,
        );
        let body_len_by_slot = storage_u32_rw(
            device,
            "codegen.wasm.object.body_len_by_slot",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let body_scan_local_prefix = storage_u32_rw(
            device,
            "codegen.wasm.object.body_scan.local_prefix",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let body_scan_block_sum = storage_u32_rw(
            device,
            "codegen.wasm.object.body_scan.block_sum",
            bufs.func_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let body_scan_prefix_a = storage_u32_rw(
            device,
            "codegen.wasm.object.body_scan.prefix_a",
            bufs.func_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let body_scan_prefix_b = storage_u32_rw(
            device,
            "codegen.wasm.object.body_scan.prefix_b",
            bufs.func_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let symbol_record = storage_u32_rw(
            device,
            "codegen.wasm.object.symbol_record",
            token_capacity as usize * 4,
            wgpu::BufferUsages::COPY_SRC,
        );
        let packed_capacity = output_capacity.div_ceil(4).max(1);
        let type_words = storage_u32_rw(
            device,
            "codegen.wasm.object.type_words",
            packed_capacity,
            wgpu::BufferUsages::COPY_SRC,
        );
        let body_words = storage_u32_rw(
            device,
            "codegen.wasm.object.body_words",
            packed_capacity,
            wgpu::BufferUsages::COPY_SRC,
        );
        let metadata = storage_u32_rw(
            device,
            "codegen.wasm.object.metadata",
            8,
            wgpu::BufferUsages::COPY_SRC,
        );

        let final_type_prefix = if (bufs.func_scan_param_bufs.len() - 1) % 2 == 0 {
            &bufs._wasm_func_scan_prefix_a_buf
        } else {
            &bufs._wasm_func_scan_prefix_b_buf
        };
        let functions_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_object_functions"),
            &self.object_functions_pass,
            0,
            &[
                ("gParams", bufs.params_buf.as_entire_binding()),
                ("body_plan", bufs.body_plan_buf.as_entire_binding()),
                (
                    "wasm_func_token_by_slot",
                    bufs._wasm_func_token_by_slot_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_entry_len_by_slot",
                    bufs._wasm_func_flag_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_local_prefix",
                    bufs._wasm_func_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_block_prefix",
                    final_type_prefix.as_entire_binding(),
                ),
                (
                    "wasm_func_body_len_by_token",
                    bufs._wasm_func_body_len_by_token_buf.as_entire_binding(),
                ),
                (
                    "decl_id_by_name_token",
                    bufs.object_inputs.decl_id_by_name_token.as_entire_binding(),
                ),
                (
                    "interface_public_decl_index_by_local",
                    bufs.object_inputs
                        .public_decl_index_by_local
                        .as_entire_binding(),
                ),
                (
                    "object_function_record",
                    function_record.as_entire_binding(),
                ),
                (
                    "object_body_len_by_slot",
                    body_len_by_slot.as_entire_binding(),
                ),
            ],
        )?;
        let body_scan_local_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_object_body_scan_local"),
            &self.hir_body_scan_local_pass,
            0,
            &[
                ("gScan", scan_param_bufs[0].as_entire_binding()),
                ("body_fragment_len", body_len_by_slot.as_entire_binding()),
                (
                    "body_scan_local_prefix",
                    body_scan_local_prefix.as_entire_binding(),
                ),
                (
                    "body_scan_block_sum",
                    body_scan_block_sum.as_entire_binding(),
                ),
            ],
        )?;
        let body_scan_block_bind_groups = scan_param_bufs
            .iter()
            .enumerate()
            .map(|(step_i, params)| {
                let input = if step_i == 0 {
                    &body_scan_block_sum
                } else if step_i % 2 == 1 {
                    &body_scan_prefix_a
                } else {
                    &body_scan_prefix_b
                };
                let output = if step_i % 2 == 0 {
                    &body_scan_prefix_a
                } else {
                    &body_scan_prefix_b
                };
                create_wasm_bind_group(
                    device,
                    Some(&format!("codegen_wasm_object_body_scan_blocks.{step_i}")),
                    &self.hir_body_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", params.as_entire_binding()),
                        (
                            "body_scan_block_sum",
                            body_scan_block_sum.as_entire_binding(),
                        ),
                        ("body_scan_block_prefix_in", input.as_entire_binding()),
                        ("body_scan_block_prefix_out", output.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let final_body_prefix = if (scan_param_bufs.len() - 1) % 2 == 0 {
            &body_scan_prefix_a
        } else {
            &body_scan_prefix_b
        };
        let function_bodies_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_object_function_bodies"),
            &self.object_function_bodies_pass,
            0,
            &[
                ("gScan", scan_param_bufs[0].as_entire_binding()),
                (
                    "object_body_len_by_slot",
                    body_len_by_slot.as_entire_binding(),
                ),
                (
                    "object_body_scan_local_prefix",
                    body_scan_local_prefix.as_entire_binding(),
                ),
                (
                    "object_body_scan_block_prefix",
                    final_body_prefix.as_entire_binding(),
                ),
                (
                    "object_function_record",
                    function_record.as_entire_binding(),
                ),
            ],
        )?;
        let symbols_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_object_symbols"),
            &self.object_symbols_pass,
            0,
            &[
                ("gParams", bufs.params_buf.as_entire_binding()),
                (
                    "interface_public_decl_count",
                    bufs.object_inputs.public_decl_count.as_entire_binding(),
                ),
                (
                    "interface_public_decl_local_id",
                    bufs.object_inputs.public_decl_local_id.as_entire_binding(),
                ),
                (
                    "decl_hir_node",
                    bufs.object_inputs.decl_hir_node.as_entire_binding(),
                ),
                (
                    "compact_hir_count",
                    bufs.object_inputs.compact_hir_count.as_entire_binding(),
                ),
                (
                    "compact_hir_core",
                    bufs.object_inputs.compact_hir_core.as_entire_binding(),
                ),
                (
                    "wasm_func_slot_by_token",
                    bufs._wasm_func_slot_by_token_buf.as_entire_binding(),
                ),
                (
                    "object_body_len_by_slot",
                    body_len_by_slot.as_entire_binding(),
                ),
                ("object_symbol_record", symbol_record.as_entire_binding()),
            ],
        )?;
        let bytes_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_object_bytes"),
            &self.object_bytes_pass,
            0,
            &[
                ("gScan", scan_param_bufs[0].as_entire_binding()),
                ("module_words", bufs.out_buf.as_entire_binding()),
                ("body_words", bufs._body_buf.as_entire_binding()),
                ("body_plan", bufs.body_plan_buf.as_entire_binding()),
                (
                    "wasm_type_scan_block_prefix",
                    final_type_prefix.as_entire_binding(),
                ),
                ("object_type_words", type_words.as_entire_binding()),
                ("object_body_words", body_words.as_entire_binding()),
            ],
        )?;
        let metadata_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_object_metadata"),
            &self.object_metadata_pass,
            0,
            &[
                ("gScan", scan_param_bufs[0].as_entire_binding()),
                ("body_plan", bufs.body_plan_buf.as_entire_binding()),
                (
                    "interface_public_decl_count",
                    bufs.object_inputs.public_decl_count.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_block_prefix",
                    final_type_prefix.as_entire_binding(),
                ),
                (
                    "call_reloc_status",
                    bufs.call_relocations.status_buf.as_entire_binding(),
                ),
                ("object_metadata", metadata.as_entire_binding()),
            ],
        )?;

        Ok(WasmObjectProjection {
            scan_param_bufs,
            function_record,
            body_len_by_slot,
            body_scan_local_prefix,
            body_scan_block_sum,
            body_scan_prefix_a,
            body_scan_prefix_b,
            symbol_record,
            type_words,
            body_words,
            metadata,
            functions_bind_group,
            body_scan_local_bind_group,
            body_scan_block_bind_groups,
            function_bodies_bind_group,
            symbols_bind_group,
            bytes_bind_group,
            metadata_bind_group,
        })
    }

    fn record_wasm_object_projection(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ResidentWasmBuffers,
        recorded: &RecordedWasmCodegen,
        object: &WasmObjectProjection,
    ) -> Result<()> {
        let token_groups = recorded.token_capacity.div_ceil(256).max(1);
        let (token_x, token_y) = workgroup_grid_1d(token_groups);
        let (scan_x, scan_y) = workgroup_grid_1d(bufs.func_scan_blocks);
        let (block_x, block_y) = workgroup_grid_1d(bufs.func_scan_blocks.div_ceil(256).max(1));
        let output_word_groups = recorded.output_capacity.div_ceil(4).div_ceil(256).max(1);
        let (bytes_x, bytes_y) = workgroup_grid_1d(output_word_groups as u32);

        for (label, pass, group, grid) in [
            (
                "codegen.wasm.object.functions",
                &self.object_functions_pass,
                &object.functions_bind_group,
                (token_x, token_y),
            ),
            (
                "codegen.wasm.object.body_scan_local",
                &self.hir_body_scan_local_pass,
                &object.body_scan_local_bind_group,
                (scan_x, scan_y),
            ),
        ] {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some(label),
                timestamp_writes: None,
            });
            compute.set_pipeline(pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(group), &[]);
            compute.dispatch_workgroups(grid.0, grid.1, 1);
        }
        for group in &object.body_scan_block_bind_groups {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.object.body_scan_blocks"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(group), &[]);
            compute.dispatch_workgroups(block_x, block_y, 1);
        }
        for (label, pass, group, grid) in [
            (
                "codegen.wasm.object.function_bodies",
                &self.object_function_bodies_pass,
                &object.function_bodies_bind_group,
                (token_x, token_y),
            ),
            (
                "codegen.wasm.object.symbols",
                &self.object_symbols_pass,
                &object.symbols_bind_group,
                (token_x, token_y),
            ),
            (
                "codegen.wasm.object.bytes",
                &self.object_bytes_pass,
                &object.bytes_bind_group,
                (bytes_x, bytes_y),
            ),
            (
                "codegen.wasm.object.metadata",
                &self.object_metadata_pass,
                &object.metadata_bind_group,
                (1, 1),
            ),
        ] {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some(label),
                timestamp_writes: None,
            });
            compute.set_pipeline(pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(group), &[]);
            compute.dispatch_workgroups(grid.0, grid.1, 1);
        }
        Ok(())
    }

    /// Completes a recorded GPU Wasm run and projects it into a durable
    /// relocatable object without reading back an executable module.
    pub fn finish_recorded_wasm_object(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        recorded: &RecordedWasmCodegen,
        library_id: u32,
        unit_id: u32,
        dependency_symbols: Option<GpuWasmDependencySymbolBuffers<'_>>,
    ) -> Result<GpuWasmRelocatableObject> {
        self.complete_recorded_wasm(device, queue, recorded)?;
        let guard = self
            .buffers
            .lock()
            .map_err(|_| anyhow!("GpuWasmCodeGenerator.buffers poisoned"))?;
        let bufs = guard
            .as_ref()
            .ok_or_else(|| anyhow!("WASM code generation buffers missing"))?;
        let object = self.create_wasm_object_projection(device, queue, bufs, recorded)?;
        let metadata_readback = readback_u32s(device, "rb.codegen.wasm.object.metadata", 8);
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.wasm.object.encoder"),
        });
        self.record_wasm_object_projection(&mut encoder, bufs, recorded, &object)?;
        encoder.copy_buffer_to_buffer(&object.metadata, 0, &metadata_readback, 0, 32);
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.wasm.object",
            encoder.finish(),
        );
        let metadata_slice = metadata_readback.slice(..);
        crate::gpu::passes_core::wait_for_readback_map(
            device,
            &metadata_slice,
            "codegen.wasm.object.metadata",
            wasm_readback_timeout(),
        )?;
        let metadata = {
            let data = metadata_slice.get_mapped_range();
            let result = crate::gpu::readback::read_u32_words::<8>(&data, "Wasm object metadata");
            drop(data);
            metadata_readback.unmap();
            result?
        };
        let function_count = metadata[0] as usize;
        let body_len = metadata[1] as usize;
        let type_len = metadata[2] as usize;
        let public_count = metadata[3] as usize;
        let entry_function = metadata[4];
        let relocation_count = metadata[5] as usize;
        if metadata[6] != 0
            || function_count > recorded.token_capacity as usize
            || public_count > recorded.token_capacity as usize
            || body_len > recorded.output_capacity
            || type_len > recorded.output_capacity
            || relocation_count > bufs.call_relocations.relocation_capacity as usize
        {
            return Err(anyhow!("Wasm object GPU metadata is invalid: {metadata:?}"));
        }

        let dependency_count = dependency_symbols
            .as_ref()
            .map_or(0usize, |symbols| symbols.declaration_count as usize);
        let function_bytes = function_count * 6 * 4;
        let type_copy_bytes = type_len.div_ceil(4) * 4;
        let body_copy_bytes = body_len.div_ceil(4) * 4;
        let relocation_bytes = relocation_count * 2 * 4;
        let dependency_bytes = dependency_count * 3 * 4;
        let local_symbol_bytes = public_count * 4 * 4;
        let total_bytes = function_bytes
            .checked_add(type_copy_bytes)
            .and_then(|n| n.checked_add(body_copy_bytes))
            .and_then(|n| n.checked_add(relocation_bytes))
            .and_then(|n| n.checked_add(dependency_bytes))
            .and_then(|n| n.checked_add(local_symbol_bytes))
            .ok_or_else(|| anyhow!("Wasm object readback length overflows"))?;
        let readback = readback_u32s(device, "rb.codegen.wasm.object", total_bytes.div_ceil(4));
        let function_offset = 0u64;
        let type_offset = function_offset + function_bytes as u64;
        let body_offset = type_offset + type_copy_bytes as u64;
        let relocation_offset = body_offset + body_copy_bytes as u64;
        let dependency_offset = relocation_offset + relocation_bytes as u64;
        let local_symbol_offset = dependency_offset + dependency_bytes as u64;
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.wasm.object.readback.encoder"),
        });
        if function_bytes != 0 {
            encoder.copy_buffer_to_buffer(
                &object.function_record,
                0,
                &readback,
                function_offset,
                function_bytes as u64,
            );
        }
        if type_copy_bytes != 0 {
            encoder.copy_buffer_to_buffer(
                &object.type_words,
                0,
                &readback,
                type_offset,
                type_copy_bytes as u64,
            );
        }
        if body_copy_bytes != 0 {
            encoder.copy_buffer_to_buffer(
                &object.body_words,
                0,
                &readback,
                body_offset,
                body_copy_bytes as u64,
            );
        }
        if relocation_count != 0 {
            let one_array = (relocation_count * 4) as u64;
            encoder.copy_buffer_to_buffer(
                &bufs.call_relocations.site_buf,
                0,
                &readback,
                relocation_offset,
                one_array,
            );
            encoder.copy_buffer_to_buffer(
                &bufs.call_relocations.target_buf,
                0,
                &readback,
                relocation_offset + one_array,
                one_array,
            );
        }
        if let Some(symbols) = &dependency_symbols {
            if dependency_count != 0 {
                let one_array = (dependency_count * 4) as u64;
                for (source, offset) in [
                    (symbols.declaration_library_id, dependency_offset),
                    (symbols.declaration_unit_id, dependency_offset + one_array),
                    (
                        symbols.declaration_local_index,
                        dependency_offset + one_array * 2,
                    ),
                ] {
                    encoder.copy_buffer_to_buffer(source, 0, &readback, offset, one_array);
                }
            }
        }
        if local_symbol_bytes != 0 {
            encoder.copy_buffer_to_buffer(
                &object.symbol_record,
                0,
                &readback,
                local_symbol_offset,
                local_symbol_bytes as u64,
            );
        }
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.wasm.object.readback",
            encoder.finish(),
        );
        let slice = readback.slice(..total_bytes as u64);
        crate::gpu::passes_core::wait_for_readback_map(
            device,
            &slice,
            "codegen.wasm.object",
            wasm_readback_timeout(),
        )?;
        let result = (|| -> Result<GpuWasmRelocatableObject> {
            let data = slice.get_mapped_range();
            let function_words =
                decode_words(&data[function_offset as usize..type_offset as usize]);
            let type_bytes = data[type_offset as usize..type_offset as usize + type_len].to_vec();
            let body_bytes = data[body_offset as usize..body_offset as usize + body_len].to_vec();
            let relocation_words =
                decode_words(&data[relocation_offset as usize..dependency_offset as usize]);
            let dependency_words =
                decode_words(&data[dependency_offset as usize..local_symbol_offset as usize]);
            let local_symbol_words = decode_words(&data[local_symbol_offset as usize..]);

            let mut functions = Vec::with_capacity(function_count);
            for words in function_words.chunks_exact(6) {
                functions.push(GpuWasmFunctionRecord {
                    type_byte_start: words[0],
                    type_byte_len: words[1],
                    body_byte_start: words[2],
                    body_byte_len: words[3],
                    symbol_index: if words[4] == u32::MAX {
                        u32::MAX
                    } else {
                        u32::try_from(dependency_count)?
                            .checked_add(words[4])
                            .ok_or_else(|| anyhow!("Wasm function symbol index overflows"))?
                    },
                    flags: words[5],
                });
            }
            let (sites, targets) = relocation_words.split_at(relocation_count);
            let mut relocations = Vec::with_capacity(relocation_count);
            for index in 0..relocation_count {
                let target = targets[index];
                let (target_kind, target_index) = if target & 0x8000_0000 != 0 {
                    let dependency = target & 0x7fff_ffff;
                    if dependency as usize >= dependency_count {
                        return Err(anyhow!(
                            "Wasm relocation {index} dependency {dependency} is out of range"
                        ));
                    }
                    (GpuWasmRelocationTargetKind::Symbol, dependency)
                } else {
                    let local = target.checked_sub(42).ok_or_else(|| {
                        anyhow!("Wasm relocation {index} targets runtime import {target}")
                    })?;
                    (GpuWasmRelocationTargetKind::LocalFunction, local)
                };
                relocations.push(GpuWasmRelocationRecord {
                    body_byte_offset: sites[index],
                    target_kind,
                    target_index,
                    addend: 0,
                });
            }

            let (dependency_library, rest) = dependency_words.split_at(dependency_count);
            let (dependency_unit, dependency_local) = rest.split_at(dependency_count);
            let mut identity_bytes = Vec::with_capacity((dependency_count + public_count) * 12);
            let mut symbols = Vec::with_capacity(dependency_count + public_count);
            for index in 0..dependency_count {
                push_symbol(
                    &mut identity_bytes,
                    &mut symbols,
                    [
                        dependency_library[index],
                        dependency_unit[index],
                        dependency_local[index],
                    ],
                    GpuWasmSymbolKind::Undefined,
                    u32::MAX,
                    0,
                    0,
                );
            }
            for (persisted_decl, words) in local_symbol_words.chunks_exact(4).enumerate() {
                let kind = match words[0] {
                    0 => GpuWasmSymbolKind::Undefined,
                    1 => GpuWasmSymbolKind::Function,
                    other => {
                        return Err(anyhow!(
                            "Wasm local symbol {persisted_decl} has GPU kind {other}"
                        ));
                    }
                };
                push_symbol(
                    &mut identity_bytes,
                    &mut symbols,
                    [library_id, unit_id, persisted_decl as u32],
                    kind,
                    words[1],
                    words[2],
                    words[3],
                );
            }
            let object = GpuWasmRelocatableObject {
                version: GPU_WASM_OBJECT_VERSION,
                library_id,
                unit_id,
                entry_function: (entry_function != u32::MAX).then_some(entry_function),
                functions,
                type_bytes,
                body_bytes,
                relocations,
                symbols,
                identity_bytes,
            };
            object.validate().map_err(anyhow::Error::msg)?;
            if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
                eprintln!(
                    "[laniusc][wasm-object] library={} unit={} functions={} body_bytes={} relocations={}",
                    object.library_id,
                    object.unit_id,
                    object.functions.len(),
                    object.body_bytes.len(),
                    object.relocations.len()
                );
                for (index, relocation) in object.relocations.iter().enumerate() {
                    let site = relocation.body_byte_offset as usize;
                    let start = site.saturating_sub(1);
                    let end = site.saturating_add(5).min(object.body_bytes.len());
                    let bytes = object.body_bytes[start..end]
                        .iter()
                        .map(|byte| format!("{byte:02x}"))
                        .collect::<Vec<_>>()
                        .join(" ");
                    eprintln!(
                        "[laniusc][wasm-object] relocation={index} site={site} target={:?}:{} bytes=[{bytes}]",
                        relocation.target_kind, relocation.target_index
                    );
                }
            }
            Ok(object)
        })();
        readback.unmap();
        result
    }
}

fn decode_words(bytes: &[u8]) -> Vec<u32> {
    bytes
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().expect("four bytes")))
        .collect()
}

fn push_symbol(
    identity_bytes: &mut Vec<u8>,
    symbols: &mut Vec<GpuWasmObjectSymbolRecord>,
    identity: [u32; 3],
    kind: GpuWasmSymbolKind,
    function_index: u32,
    size: u32,
    flags: u32,
) {
    let identity_byte_start = identity_bytes.len() as u32;
    for word in identity {
        identity_bytes.extend_from_slice(&word.to_le_bytes());
    }
    let bytes = &identity_bytes[identity_byte_start as usize..];
    let (identity_hash_lo, identity_hash_hi) = crate::compiler::stable_name_hash(bytes);
    symbols.push(GpuWasmObjectSymbolRecord {
        identity_hash_lo,
        identity_hash_hi,
        identity_byte_start,
        identity_byte_len: 12,
        kind,
        function_index,
        size,
        flags,
    });
}
