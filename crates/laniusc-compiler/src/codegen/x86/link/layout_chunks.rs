use anyhow::{Result, anyhow, bail};

use super::GpuX86LinkInput;
use crate::codegen::x86::{
    GpuX86Linker,
    support::{
        dispatch_compute_pass,
        reflected_bind_group,
        storage_u32_rw,
        uniform_u32_words,
        workgroup_grid_1d,
    },
};

const OBJECT_LAYOUT_BYTES_PER_INPUT_RECORD: usize = 16;
const OBJECT_LAYOUT_CHUNK_BYTES: usize = 4 * 1024 * 1024;

pub(super) struct GpuX86ResolvedObjectLayout {
    pub object_bases: Vec<[u32; 2]>,
    pub elf_layout: wgpu::Buffer,
    pub layout_status: wgpu::Buffer,
}

impl GpuX86Linker {
    pub(super) fn resolve_object_layout_chunks(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: &GpuX86LinkInput,
        output_capacity: u32,
    ) -> Result<GpuX86ResolvedObjectLayout> {
        let binding_limit = device.limits().max_storage_buffer_binding_size as usize;
        let chunk_capacity =
            binding_limit.min(OBJECT_LAYOUT_CHUNK_BYTES) / OBJECT_LAYOUT_BYTES_PER_INPUT_RECORD;
        if chunk_capacity == 0 {
            bail!("x86 GPU binding limit {binding_limit} cannot hold one object layout record");
        }
        let mut object_bases = Vec::with_capacity(input.objects.len());
        let mut text_base = 0u32;
        let mut rodata_base = 0u32;
        let mut entry_text_offset = u32::MAX;
        let mut final_elf_layout = None;
        let mut final_layout_status = None;

        for (chunk_index, objects) in input.objects.chunks(chunk_capacity).enumerate() {
            let chunk_start = chunk_index
                .checked_mul(chunk_capacity)
                .ok_or_else(|| anyhow!("x86 object layout chunk start overflows"))?;
            let chunk_count = objects.len();
            let block_count = chunk_count.div_ceil(256).max(1);
            let is_final = chunk_start + chunk_count == input.objects.len();
            let entry_global = input.entry_object_index as usize;
            let entry_local = if (chunk_start..chunk_start + chunk_count).contains(&entry_global) {
                (entry_global - chunk_start) as u32
            } else {
                u32::MAX
            };
            let mut section_words = Vec::with_capacity(chunk_count * 4);
            let mut entry_words = Vec::with_capacity(chunk_count);
            for object in objects {
                section_words.extend_from_slice(&[
                    object.text_input_start,
                    object.text_len,
                    object.rodata_input_start,
                    object.rodata_len,
                ]);
                entry_words.push(object.entry_offset);
            }
            let object_sections = super::executable::storage_input_u32(
                device,
                "codegen.x86.link.layout_chunk.object_sections",
                &section_words,
            );
            let object_entries = super::executable::storage_input_u32(
                device,
                "codegen.x86.link.layout_chunk.object_entries",
                &entry_words,
            );
            let local_prefix = storage_u32_rw(
                device,
                "codegen.x86.link.layout_chunk.local_prefix",
                chunk_count * 2,
                wgpu::BufferUsages::empty(),
            );
            let block_sum = storage_u32_rw(
                device,
                "codegen.x86.link.layout_chunk.block_sum",
                block_count * 2,
                wgpu::BufferUsages::empty(),
            );
            let block_prefix_a = storage_u32_rw(
                device,
                "codegen.x86.link.layout_chunk.block_prefix_a",
                block_count * 2,
                wgpu::BufferUsages::empty(),
            );
            let block_prefix_b = storage_u32_rw(
                device,
                "codegen.x86.link.layout_chunk.block_prefix_b",
                block_count * 2,
                wgpu::BufferUsages::empty(),
            );
            let chunk_bases = storage_u32_rw(
                device,
                "codegen.x86.link.layout_chunk.object_bases",
                chunk_count * 2,
                wgpu::BufferUsages::COPY_SRC,
            );
            let elf_layout = storage_u32_rw(
                device,
                "codegen.x86.link.layout_chunk.elf_layout",
                8,
                wgpu::BufferUsages::empty(),
            );
            let layout_status = storage_u32_rw(
                device,
                "codegen.x86.link.layout_chunk.status",
                4,
                wgpu::BufferUsages::empty(),
            );
            let params = uniform_u32_words(
                device,
                "codegen.x86.link.layout_chunk.params",
                &[
                    chunk_count as u32,
                    block_count as u32,
                    entry_local,
                    output_capacity,
                    text_base,
                    rodata_base,
                    entry_text_offset,
                    u32::from(is_final),
                ],
            );
            let local_group = reflected_bind_group(
                device,
                Some("codegen.x86.link.layout_chunk.local.bind_group"),
                &self.link_layout_scan_local_pass,
                0,
                &[
                    ("gLink", params.buffer.as_entire_binding()),
                    ("link_object_sections", object_sections.as_entire_binding()),
                    (
                        "link_section_local_prefix",
                        local_prefix.buffer.as_entire_binding(),
                    ),
                    (
                        "link_section_block_sum",
                        block_sum.buffer.as_entire_binding(),
                    ),
                ],
            )?;
            let scan_steps = crate::gpu::scan::scan_step_values(block_count as u32);
            let mut scan_params = Vec::with_capacity(scan_steps.len());
            let mut scan_groups = Vec::with_capacity(scan_steps.len());
            for (step_index, step) in scan_steps.iter().copied().enumerate() {
                scan_params.push(uniform_u32_words(
                    device,
                    "codegen.x86.link.layout_chunk.scan.params",
                    &[chunk_count as u32, block_count as u32, step, 0],
                ));
                let (prefix_in, prefix_out) = if step_index & 1 == 0 {
                    (&block_prefix_b.buffer, &block_prefix_a.buffer)
                } else {
                    (&block_prefix_a.buffer, &block_prefix_b.buffer)
                };
                scan_groups.push(reflected_bind_group(
                    device,
                    Some("codegen.x86.link.layout_chunk.scan.bind_group"),
                    &self.link_layout_scan_blocks_pass,
                    0,
                    &[
                        (
                            "gScan",
                            scan_params.last().unwrap().buffer.as_entire_binding(),
                        ),
                        (
                            "link_section_block_sum",
                            block_sum.buffer.as_entire_binding(),
                        ),
                        (
                            "link_section_block_prefix_in",
                            prefix_in.as_entire_binding(),
                        ),
                        (
                            "link_section_block_prefix_out",
                            prefix_out.as_entire_binding(),
                        ),
                    ],
                )?);
            }
            let final_block_prefix = if (scan_steps.len() - 1) & 1 == 0 {
                &block_prefix_a.buffer
            } else {
                &block_prefix_b.buffer
            };
            let layout_group = reflected_bind_group(
                device,
                Some("codegen.x86.link.layout_chunk.finalize.bind_group"),
                &self.link_layout_pass,
                0,
                &[
                    ("gLink", params.buffer.as_entire_binding()),
                    ("link_object_sections", object_sections.as_entire_binding()),
                    (
                        "link_object_entry_offset",
                        object_entries.as_entire_binding(),
                    ),
                    (
                        "link_section_local_prefix",
                        local_prefix.buffer.as_entire_binding(),
                    ),
                    (
                        "link_section_block_prefix",
                        final_block_prefix.as_entire_binding(),
                    ),
                    (
                        "link_object_section_base",
                        chunk_bases.buffer.as_entire_binding(),
                    ),
                    ("x86_elf_layout", elf_layout.buffer.as_entire_binding()),
                    ("layout_status", layout_status.buffer.as_entire_binding()),
                ],
            )?;
            let readback = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("rb.codegen.x86.link.layout_chunk.object_bases"),
                size: (chunk_count * 8) as u64,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            });
            let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("codegen.x86.link.layout_chunk.encoder"),
            });
            dispatch_compute_pass(
                &mut encoder,
                "link.layout_chunk.local",
                "codegen.x86.link.layout_chunk.local",
                &self.link_layout_scan_local_pass,
                &local_group,
                workgroup_grid_1d(block_count as u32),
            );
            for group in &scan_groups {
                dispatch_compute_pass(
                    &mut encoder,
                    "link.layout_chunk.scan",
                    "codegen.x86.link.layout_chunk.scan",
                    &self.link_layout_scan_blocks_pass,
                    group,
                    workgroup_grid_1d((block_count as u32).div_ceil(256)),
                );
            }
            dispatch_compute_pass(
                &mut encoder,
                "link.layout_chunk.finalize",
                "codegen.x86.link.layout_chunk.finalize",
                &self.link_layout_pass,
                &layout_group,
                workgroup_grid_1d((chunk_count as u32).div_ceil(256)),
            );
            encoder.copy_buffer_to_buffer(
                &chunk_bases.buffer,
                0,
                &readback,
                0,
                (chunk_count * 8) as u64,
            );
            crate::gpu::passes_core::submit_with_progress(
                queue,
                "codegen.x86.link.layout_chunk",
                encoder.finish(),
            );
            let slice = readback.slice(..);
            crate::gpu::passes_core::wait_for_readback_map(
                device,
                &slice,
                "codegen.x86.link.layout_chunk",
                std::time::Duration::from_secs(30),
            )?;
            let mapped = slice.get_mapped_range();
            for bytes in mapped.chunks_exact(8) {
                object_bases.push([
                    u32::from_le_bytes(bytes[0..4].try_into().unwrap()),
                    u32::from_le_bytes(bytes[4..8].try_into().unwrap()),
                ]);
            }
            drop(mapped);
            readback.unmap();

            let last_base = object_bases
                .last()
                .copied()
                .ok_or_else(|| anyhow!("x86 object layout chunk produced no bases"))?;
            let last = objects.last().unwrap();
            text_base = last_base[0]
                .checked_add(last.text_len)
                .ok_or_else(|| anyhow!("x86 aggregate text length exceeds u32"))?;
            rodata_base = last_base[1]
                .checked_add(last.rodata_len)
                .ok_or_else(|| anyhow!("x86 aggregate rodata length exceeds u32"))?;
            if entry_local != u32::MAX {
                let entry_base = object_bases[chunk_start + entry_local as usize][0];
                entry_text_offset = entry_base
                    .checked_add(objects[entry_local as usize].entry_offset)
                    .ok_or_else(|| anyhow!("x86 entry text offset exceeds u32"))?;
            }
            if is_final {
                final_elf_layout = Some(elf_layout.buffer);
                final_layout_status = Some(layout_status.buffer);
            }
        }
        Ok(GpuX86ResolvedObjectLayout {
            object_bases,
            elf_layout: final_elf_layout
                .ok_or_else(|| anyhow!("x86 object layout has no final ELF layout"))?,
            layout_status: final_layout_status
                .ok_or_else(|| anyhow!("x86 object layout has no final status"))?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn object_layout_chunk_capacity_has_a_practical_memory_cap() {
        let binding_limit = 128 * 1024 * 1024usize;
        let capacity =
            binding_limit.min(OBJECT_LAYOUT_CHUNK_BYTES) / OBJECT_LAYOUT_BYTES_PER_INPUT_RECORD;
        assert_eq!(capacity, 262_144);
    }
}
