use super::*;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct GpuWasmCallRelocation {
    pub body_byte_offset: u32,
    pub encoded_target: u32,
}

pub(super) struct ResidentWasmCallRelocations {
    pub scan_param_bufs: Vec<LaniusBuffer<WasmScanParams>>,
    pub max_scan_blocks: u32,
    pub relocation_capacity: u32,
    pub local_prefix_buf: LaniusBuffer<u32>,
    pub block_sum_buf: LaniusBuffer<u32>,
    pub prefix_a_buf: LaniusBuffer<u32>,
    pub prefix_b_buf: LaniusBuffer<u32>,
    pub site_buf: LaniusBuffer<u32>,
    pub target_buf: LaniusBuffer<u32>,
    pub status_buf: LaniusBuffer<u32>,
    pub scan_local_bind_group: wgpu::BindGroup,
    pub scan_block_bind_groups: Vec<wgpu::BindGroup>,
    pub scatter_bind_group: wgpu::BindGroup,
}

impl GpuWasmCodeGenerator {
    pub(super) fn create_wasm_call_relocations(
        &self,
        device: &wgpu::Device,
        output_capacity: usize,
        body_words: &wgpu::Buffer,
    ) -> Result<ResidentWasmCallRelocations> {
        let body_capacity = u32::try_from(output_capacity)
            .map_err(|_| anyhow!("Wasm body capacity {output_capacity} exceeds u32"))?;
        let max_scan_blocks = body_capacity.div_ceil(256).max(1);
        // A relocation marker occupies the first byte of a five-byte call
        // immediate, and every such immediate is preceded by the call opcode.
        let relocation_capacity = body_capacity.div_ceil(6).max(1);
        let scan_steps = scan_steps_for_blocks(max_scan_blocks as usize);
        let scan_param_bufs = create_wasm_scan_param_buffers(
            device,
            "codegen.wasm.call_reloc.scan.params",
            scan_steps.len(),
        );
        let local_prefix_buf = storage_u32_rw(
            device,
            "codegen.wasm.call_reloc.local_prefix",
            output_capacity,
            wgpu::BufferUsages::empty(),
        );
        let block_sum_buf = storage_u32_rw(
            device,
            "codegen.wasm.call_reloc.block_sum",
            max_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let prefix_a_buf = storage_u32_rw(
            device,
            "codegen.wasm.call_reloc.prefix_a",
            max_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let prefix_b_buf = storage_u32_rw(
            device,
            "codegen.wasm.call_reloc.prefix_b",
            max_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let site_buf = storage_u32_rw(
            device,
            "codegen.wasm.call_reloc.site",
            relocation_capacity as usize,
            wgpu::BufferUsages::COPY_SRC,
        );
        let target_buf = storage_u32_rw(
            device,
            "codegen.wasm.call_reloc.target",
            relocation_capacity as usize,
            wgpu::BufferUsages::COPY_SRC,
        );
        let status_buf = storage_u32_rw(
            device,
            "codegen.wasm.call_reloc.status",
            4,
            wgpu::BufferUsages::COPY_SRC,
        );

        let scan_local_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_call_reloc_scan_local"),
            &self.call_reloc_scan_local_pass,
            0,
            &[
                ("gScan", scan_param_bufs[0].as_entire_binding()),
                ("body_words", body_words.as_entire_binding()),
                (
                    "call_reloc_local_prefix",
                    local_prefix_buf.as_entire_binding(),
                ),
                ("call_reloc_block_sum", block_sum_buf.as_entire_binding()),
            ],
        )?;
        let scan_block_bind_groups = scan_param_bufs
            .iter()
            .enumerate()
            .map(|(step_i, params)| {
                let input = if step_i == 0 {
                    &block_sum_buf
                } else if step_i % 2 == 1 {
                    &prefix_a_buf
                } else {
                    &prefix_b_buf
                };
                let output = if step_i % 2 == 0 {
                    &prefix_a_buf
                } else {
                    &prefix_b_buf
                };
                create_wasm_bind_group(
                    device,
                    Some(&format!("codegen_wasm_call_reloc_scan_blocks.{step_i}")),
                    &self.hir_body_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", params.as_entire_binding()),
                        ("body_scan_block_sum", block_sum_buf.as_entire_binding()),
                        ("body_scan_block_prefix_in", input.as_entire_binding()),
                        ("body_scan_block_prefix_out", output.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let final_prefix = if (scan_param_bufs.len() - 1) % 2 == 0 {
            &prefix_a_buf
        } else {
            &prefix_b_buf
        };
        let scatter_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_call_reloc_scatter"),
            &self.call_reloc_scatter_pass,
            0,
            &[
                ("gScan", scan_param_bufs[0].as_entire_binding()),
                ("body_words", body_words.as_entire_binding()),
                (
                    "call_reloc_local_prefix",
                    local_prefix_buf.as_entire_binding(),
                ),
                ("call_reloc_block_prefix", final_prefix.as_entire_binding()),
                ("call_reloc_site", site_buf.as_entire_binding()),
                ("call_reloc_target", target_buf.as_entire_binding()),
                ("call_reloc_status", status_buf.as_entire_binding()),
            ],
        )?;

        Ok(ResidentWasmCallRelocations {
            scan_param_bufs,
            max_scan_blocks,
            relocation_capacity,
            local_prefix_buf,
            block_sum_buf,
            prefix_a_buf,
            prefix_b_buf,
            site_buf,
            target_buf,
            status_buf,
            scan_local_bind_group,
            scan_block_bind_groups,
            scatter_bind_group,
        })
    }

    pub(super) fn prepare_wasm_call_relocations(
        &self,
        queue: &wgpu::Queue,
        relocations: &ResidentWasmCallRelocations,
        body_len: u32,
    ) -> Result<()> {
        let n_blocks = body_len.div_ceil(256).max(1);
        if n_blocks > relocations.max_scan_blocks {
            return Err(anyhow!(
                "Wasm body length {body_len} needs {n_blocks} relocation scan blocks; capacity is {}",
                relocations.max_scan_blocks
            ));
        }
        for (params, scan_step) in relocations
            .scan_param_bufs
            .iter()
            .zip(scan_steps_for_blocks(relocations.max_scan_blocks as usize))
        {
            let value = WasmScanParams {
                n_items: body_len,
                n_blocks,
                scan_step,
                out_capacity: relocations.relocation_capacity,
            };
            queue.write_buffer(params, 0, &wasm_scan_params_bytes(&value));
        }
        let mut status = [0u8; 16];
        status[8..12].copy_from_slice(&u32::MAX.to_le_bytes());
        queue.write_buffer(&relocations.status_buf, 0, &status);
        Ok(())
    }

    pub(super) fn record_wasm_call_relocations(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        relocations: &ResidentWasmCallRelocations,
        body_len: u32,
    ) -> Result<()> {
        let n_blocks = body_len.div_ceil(256).max(1);
        let (local_x, local_y) = workgroup_grid_1d(n_blocks);
        let (block_x, block_y) = workgroup_grid_1d(n_blocks.div_ceil(256).max(1));

        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.call_reloc.scan_local"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.call_reloc_scan_local_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&relocations.scan_local_bind_group), &[]);
        compute.dispatch_workgroups(local_x, local_y, 1);
        drop(compute);

        for bind_group in &relocations.scan_block_bind_groups {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.call_reloc.scan_blocks"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(bind_group), &[]);
            compute.dispatch_workgroups(block_x, block_y, 1);
            drop(compute);
        }

        let scatter_groups = body_len.div_ceil(256).max(1);
        let (scatter_x, scatter_y) = workgroup_grid_1d(scatter_groups);
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.call_reloc.scatter"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.call_reloc_scatter_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&relocations.scatter_bind_group), &[]);
        compute.dispatch_workgroups(scatter_x, scatter_y, 1);
        drop(compute);
        Ok(())
    }

    pub(crate) fn read_recorded_wasm_call_relocations(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
    ) -> Result<Vec<GpuWasmCallRelocation>> {
        let guard = self
            .buffers
            .lock()
            .map_err(|_| anyhow!("GpuWasmCodeGenerator.buffers poisoned"))?;
        let bufs = guard
            .as_ref()
            .ok_or_else(|| anyhow!("WASM code generation buffers missing"))?;
        read_wasm_call_relocations(device, queue, &bufs.call_relocations)
    }
}

fn read_wasm_call_relocations(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    relocations: &ResidentWasmCallRelocations,
) -> Result<Vec<GpuWasmCallRelocation>> {
    let capacity = relocations.relocation_capacity as usize;
    let words = 4usize
        .checked_add(
            capacity
                .checked_mul(2)
                .ok_or_else(|| anyhow!("Wasm relocation readback length overflows"))?,
        )
        .ok_or_else(|| anyhow!("Wasm relocation readback length overflows"))?;
    let readback = readback_u32s(device, "rb.codegen.wasm.call_relocations", words);
    let sites_offset = 16u64;
    let targets_offset = sites_offset + (capacity * 4) as u64;
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("codegen.wasm.call_relocations.readback.encoder"),
    });
    encoder.copy_buffer_to_buffer(&relocations.status_buf, 0, &readback, 0, 16);
    encoder.copy_buffer_to_buffer(
        &relocations.site_buf,
        0,
        &readback,
        sites_offset,
        (capacity * 4) as u64,
    );
    encoder.copy_buffer_to_buffer(
        &relocations.target_buf,
        0,
        &readback,
        targets_offset,
        (capacity * 4) as u64,
    );
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "codegen.wasm.call_relocations.readback",
        encoder.finish(),
    );
    let slice = readback.slice(..);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &slice,
        "codegen.wasm.call_relocations",
        wasm_readback_timeout(),
    )?;
    let result = (|| -> Result<Vec<GpuWasmCallRelocation>> {
        let data = slice.get_mapped_range();
        let status =
            crate::gpu::readback::read_u32_words::<4>(&data[..16], "Wasm call relocation status")?;
        let count = status[0] as usize;
        if status[1] != 0 || status[3] != 0 || count > capacity {
            return Err(anyhow!(
                "Wasm call-relocation GPU status is invalid: {status:?}, capacity={capacity}"
            ));
        }
        let mut rows = Vec::with_capacity(count);
        for row in 0..count {
            let site_start = sites_offset as usize + row * 4;
            let target_start = targets_offset as usize + row * 4;
            rows.push(GpuWasmCallRelocation {
                body_byte_offset: u32::from_le_bytes(data[site_start..site_start + 4].try_into()?),
                encoded_target: u32::from_le_bytes(
                    data[target_start..target_start + 4].try_into()?,
                ),
            });
        }
        Ok(rows)
    })();
    readback.unmap();
    result
}

#[cfg(test)]
mod tests {
    use super::*;

    fn padded(value: u32) -> [u32; 5] {
        [
            (value & 0x7f) | 0x80,
            ((value >> 7) & 0x7f) | 0x80,
            ((value >> 14) & 0x7f) | 0x80,
            ((value >> 21) & 0x7f) | 0x80,
            (value >> 28) & 0x0f,
        ]
    }

    fn place_call(words: &mut [u32], site: usize, target: u32) {
        words[site - 1] = 0x10;
        for (byte_i, byte) in padded(target).into_iter().enumerate() {
            words[site + byte_i] = byte | u32::from(byte_i == 0) * 0x100;
        }
    }

    #[test]
    fn gpu_compacts_marked_calls_across_scan_blocks() {
        let gpu = crate::gpu::device::global();
        let generator = GpuWasmCodeGenerator::new_with_device(gpu).expect("Wasm generator");
        let mut words = vec![0u32; 768];
        place_call(&mut words, 1, 42);
        place_call(&mut words, 256, 0x8000_0007);
        place_call(&mut words, 513, 165);
        let bytes: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
        let body = storage_u32_rw(
            &gpu.device,
            "test.codegen.wasm.call_reloc.body",
            words.len(),
            wgpu::BufferUsages::empty(),
        );
        gpu.queue.write_buffer(&body, 0, &bytes);
        let relocations = generator
            .create_wasm_call_relocations(&gpu.device, words.len(), &body)
            .expect("call relocation buffers");
        generator
            .prepare_wasm_call_relocations(&gpu.queue, &relocations, 520)
            .expect("call relocation params");
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.codegen.wasm.call_reloc.encoder"),
            });
        generator
            .record_wasm_call_relocations(&mut encoder, &relocations, 520)
            .expect("record call relocations");
        crate::gpu::passes_core::submit_with_progress(
            &gpu.queue,
            "test.codegen.wasm.call_reloc",
            encoder.finish(),
        );
        let rows = read_wasm_call_relocations(&gpu.device, &gpu.queue, &relocations)
            .expect("read call relocations");
        assert_eq!(
            rows,
            vec![
                GpuWasmCallRelocation {
                    body_byte_offset: 1,
                    encoded_target: 42,
                },
                GpuWasmCallRelocation {
                    body_byte_offset: 256,
                    encoded_target: 0x8000_0007,
                },
                GpuWasmCallRelocation {
                    body_byte_offset: 513,
                    encoded_target: 165,
                },
            ]
        );
    }
}
