use std::io::{Seek, SeekFrom, Write};

use anyhow::{Result, anyhow};
use wgpu::util::DeviceExt;

use super::{GpuWasmLinkInput, paged::GpuWasmPagedExecutablePlan};
use crate::codegen::wasm::{GpuWasmCodeGenerator, create_wasm_bind_group, workgroup_grid_1d};

impl GpuWasmCodeGenerator {
    /// Emits and relocates a complete multi-unit Wasm module on the GPU.
    #[cfg_attr(not(test), allow(dead_code))]
    pub(crate) fn link_executable(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: &GpuWasmLinkInput,
    ) -> Result<Vec<u8>> {
        let mut bytes = Vec::new();
        self.link_executable_pages(device, queue, input, |output_base, page| {
            if output_base as usize != bytes.len() {
                return Err(anyhow!(
                    "Wasm output pages are not dense: next base {output_base}, current length {}",
                    bytes.len()
                ));
            }
            bytes.extend_from_slice(page);
            Ok(())
        })?;
        Ok(bytes)
    }

    /// Emits a bounded-page Wasm module directly into a seekable output sink.
    pub(crate) fn link_executable_to_writer<W: Write + Seek>(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: &GpuWasmLinkInput,
        output: &mut W,
    ) -> Result<usize> {
        self.link_executable_pages(device, queue, input, |output_base, page| {
            output.seek(SeekFrom::Start(output_base as u64))?;
            output.write_all(page)?;
            Ok(())
        })
    }

    fn link_executable_pages(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: &GpuWasmLinkInput,
        mut consume_page: impl FnMut(u32, &[u8]) -> Result<()>,
    ) -> Result<usize> {
        let output_plan = GpuWasmPagedExecutablePlan::new(
            input,
            device.limits().max_storage_buffer_binding_size as u64,
        )
        .map_err(anyhow::Error::msg)?;
        let resolved_relocations = self.resolve_symbol_relocations(device, queue, input)?;
        let output_len = output_plan.output_len;
        let output_len_u32 = u32::try_from(output_len)
            .map_err(|_| anyhow!("Wasm output length {output_len} exceeds u32"))?;
        let hash_capacity_u32 = 1;
        let symbols = input_u32(
            device,
            "codegen.wasm.link.symbols",
            &[],
            wgpu::BufferUsages::STORAGE,
        );
        let hash_table = input_u32(
            device,
            "codegen.wasm.link.hash_table",
            &[u32::MAX],
            wgpu::BufferUsages::STORAGE,
        );
        let definitions = input_u32(
            device,
            "codegen.wasm.link.definitions",
            &[u32::MAX],
            wgpu::BufferUsages::STORAGE,
        );
        let status = input_u32(
            device,
            "codegen.wasm.link.status",
            &[1, 0, u32::MAX, 0],
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        );

        let status_readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.codegen.wasm.link.status"),
            size: 16,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        for page in &output_plan.pages {
            let max_relocations_per_batch =
                (device.limits().max_storage_buffer_binding_size as usize / 32).max(1);
            let relocation_buffer_records = page
                .relocation_indices
                .len()
                .min(max_relocations_per_batch)
                .max(1);
            let relocation_batches = page
                .relocation_indices
                .chunks(max_relocations_per_batch)
                .collect::<Vec<_>>();
            let first_relocation_count = relocation_batches.first().map_or(0, |batch| batch.len());
            let params_words = link_params_words(
                input,
                first_relocation_count,
                hash_capacity_u32,
                output_len_u32,
                page.output_base,
                page.output_len,
                page.type_input.start as u32,
                page.body_input.start as u32,
            )?;
            let params = input_u32(
                device,
                "codegen.wasm.link.page.params",
                &params_words,
                wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            );
            let type_page = input
                .read_type_range(page.type_input.clone())
                .map_err(anyhow::Error::msg)?;
            let types = input_bytes(device, "codegen.wasm.link.page.types", &type_page);
            let body_page = input
                .read_body_range(page.body_input.clone())
                .map_err(anyhow::Error::msg)?;
            let bodies = input_bytes(device, "codegen.wasm.link.page.bodies", &body_page);
            let relocations = rw_u32(
                device,
                "codegen.wasm.link.page.relocations",
                relocation_buffer_records.saturating_mul(8),
                wgpu::BufferUsages::empty(),
            );
            let output_words = (page.output_len as usize).div_ceil(4);
            let output = rw_u32(
                device,
                "codegen.wasm.link.page.output",
                output_words,
                wgpu::BufferUsages::COPY_SRC,
            );
            let module_group = create_wasm_bind_group(
                device,
                Some("codegen.wasm.link.page.module.bind_group"),
                &self.link_module_pass,
                0,
                &[
                    ("gLink", params.as_entire_binding()),
                    ("link_type_bytes", types.as_entire_binding()),
                    ("link_body_bytes", bodies.as_entire_binding()),
                    ("out_words", output.as_entire_binding()),
                ],
            )?;
            let relocate_group = create_wasm_bind_group(
                device,
                Some("codegen.wasm.link.page.relocate.bind_group"),
                &self.link_relocate_pass,
                0,
                &[
                    ("gLink", params.as_entire_binding()),
                    ("link_symbol", symbols.as_entire_binding()),
                    ("link_hash_table", hash_table.as_entire_binding()),
                    ("link_symbol_definition", definitions.as_entire_binding()),
                    ("link_status", status.as_entire_binding()),
                    ("link_relocation", relocations.as_entire_binding()),
                    ("out_words", output.as_entire_binding()),
                ],
            )?;
            let output_readback = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("rb.codegen.wasm.link.page.output"),
                size: (output_words * 4) as u64,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            });
            let batch_count = relocation_batches.len().max(1);
            for batch_index in 0..batch_count {
                let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("codegen.wasm.link.page.encoder"),
                });
                if batch_index == 0 {
                    dispatch(
                        &mut encoder,
                        "codegen.wasm.link.page.module",
                        &self.link_module_pass,
                        &module_group,
                        output_words.div_ceil(256) as u32,
                    )?;
                }
                if let Some(batch) = relocation_batches.get(batch_index) {
                    let batch_params = link_params_words(
                        input,
                        batch.len(),
                        hash_capacity_u32,
                        output_len_u32,
                        page.output_base,
                        page.output_len,
                        page.type_input.start as u32,
                        page.body_input.start as u32,
                    )?;
                    let relocation_words = page_relocation_words(&resolved_relocations, batch);
                    queue.write_buffer(&params, 0, bytemuck_words(&batch_params));
                    queue.write_buffer(&relocations, 0, bytemuck_words(&relocation_words));
                    dispatch(
                        &mut encoder,
                        "codegen.wasm.link.page.relocate",
                        &self.link_relocate_pass,
                        &relocate_group,
                        batch.len().div_ceil(256) as u32,
                    )?;
                }
                if batch_index + 1 == batch_count {
                    encoder.copy_buffer_to_buffer(
                        &output,
                        0,
                        &output_readback,
                        0,
                        (output_words * 4) as u64,
                    );
                    encoder.copy_buffer_to_buffer(&status, 0, &status_readback, 0, 16);
                }
                crate::gpu::passes_core::submit_with_progress(
                    queue,
                    "codegen.wasm.link.page",
                    encoder.finish(),
                );
            }
            let output_slice = output_readback.slice(..);
            let status_slice = status_readback.slice(..);
            crate::gpu::passes_core::wait_for_readback_map(
                device,
                &output_slice,
                "codegen.wasm.link.page.output",
                std::time::Duration::from_secs(30),
            )?;
            crate::gpu::passes_core::wait_for_readback_map(
                device,
                &status_slice,
                "codegen.wasm.link.page.status",
                std::time::Duration::from_secs(30),
            )?;
            let output_mapped = output_slice.get_mapped_range();
            let status_mapped = status_slice.get_mapped_range();
            let status_words =
                crate::gpu::readback::read_u32_words::<4>(&status_mapped, "Wasm link status")?;
            let page_result = if status_words[0] != 1 || status_words[1] != 0 {
                Err(anyhow!(
                    "Wasm GPU linker failed with status {status_words:?}"
                ))
            } else {
                consume_page(page.output_base, &output_mapped[..page.output_len as usize])
            };
            drop(status_mapped);
            drop(output_mapped);
            status_readback.unmap();
            output_readback.unmap();
            page_result?;
        }
        Ok(output_len)
    }
}

#[allow(clippy::too_many_arguments)]
pub(super) fn link_params_words(
    input: &GpuWasmLinkInput,
    relocation_count: usize,
    hash_capacity: u32,
    output_len: u32,
    output_page_base: u32,
    output_page_len: u32,
    type_input_base: u32,
    body_input_base: u32,
) -> Result<[u32; 12]> {
    Ok([
        u32::try_from(input.function_count)
            .map_err(|_| anyhow!("Wasm function count exceeds u32"))?,
        u32::try_from(input.type_byte_len()).map_err(|_| anyhow!("Wasm type bytes exceed u32"))?,
        u32::try_from(input.body_byte_len()).map_err(|_| anyhow!("Wasm body bytes exceed u32"))?,
        input.entry_function,
        u32::try_from(input.symbols.len()).map_err(|_| anyhow!("Wasm symbol count exceeds u32"))?,
        u32::try_from(relocation_count).map_err(|_| anyhow!("Wasm relocation page exceeds u32"))?,
        hash_capacity,
        output_len,
        output_page_base,
        output_page_len,
        type_input_base,
        body_input_base,
    ])
}

fn page_relocation_words(
    relocations: &[super::GpuWasmLinkRelocationRecord],
    indices: &[usize],
) -> Vec<u32> {
    let mut words = Vec::with_capacity(indices.len() * 8);
    for &relocation_index in indices {
        let relocation = relocations
            .get(relocation_index)
            .expect("Wasm output plan relocation index");
        words.extend_from_slice(&[
            relocation.body_offset,
            relocation.target_kind as u32,
            relocation.target_index,
            relocation.addend as u32,
            relocation.target_identity[0],
            relocation.target_identity[1],
            relocation.target_identity[2],
            0,
        ]);
    }
    words
}

pub(super) fn dispatch(
    encoder: &mut wgpu::CommandEncoder,
    label: &str,
    pass: &crate::codegen::wasm::LazyWasmPass,
    group: &wgpu::BindGroup,
    groups: u32,
) -> Result<()> {
    let pipeline = pass.pipeline()?;
    let grid = workgroup_grid_1d(groups);
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pipeline);
    compute.set_bind_group(0, group, &[]);
    compute.dispatch_workgroups(grid.0, grid.1, 1);
    Ok(())
}

pub(super) fn input_u32(
    device: &wgpu::Device,
    label: &str,
    words: &[u32],
    usage: wgpu::BufferUsages,
) -> wgpu::Buffer {
    let fallback = [0u32];
    let words = if words.is_empty() {
        &fallback[..]
    } else {
        words
    };
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: bytemuck_words(words),
        usage,
    })
}
fn input_bytes(device: &wgpu::Device, label: &str, bytes: &[u8]) -> wgpu::Buffer {
    let mut data = bytes.to_vec();
    data.resize(data.len().div_ceil(4).max(1) * 4, 0);
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &data,
        usage: wgpu::BufferUsages::STORAGE,
    })
}
pub(super) fn rw_u32(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra: wgpu::BufferUsages,
) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | extra,
        mapped_at_creation: false,
    })
}
pub(super) fn bytemuck_words(words: &[u32]) -> &[u8] {
    unsafe { std::slice::from_raw_parts(words.as_ptr().cast(), words.len() * 4) }
}
