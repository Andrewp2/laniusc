use std::io::{Seek, SeekFrom, Write};

use anyhow::{Result, bail};
use wgpu::util::DeviceExt;

use super::{GpuX86LinkInput, paged::GpuX86PagedExecutablePlan};
use crate::codegen::x86::{
    GpuX86CodeGenerator,
    support::{
        dispatch_compute_pass,
        reflected_bind_group,
        storage_u32_copy,
        storage_u32_rw,
        u32_words_bytes,
        uniform_u32_words,
        workgroup_grid_1d,
    },
};

const RELOCATION_RECORD_BYTES_PER_COLUMN: usize = 16;
const RELOCATION_BATCH_BYTES_PER_COLUMN: usize = 4 * 1024 * 1024;

struct X86ResolvedLinkBuffers<'a> {
    object_bases: &'a [[u32; 2]],
    elf_layout: &'a wgpu::Buffer,
    layout_status: &'a wgpu::Buffer,
    relocation_status: &'a wgpu::Buffer,
}

impl GpuX86CodeGenerator {
    /// Links validated object columns entirely on the GPU and reads back only
    /// the final executable image and compact status words.
    #[cfg_attr(not(test), allow(dead_code))]
    pub(crate) fn link_executable(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: &GpuX86LinkInput,
    ) -> Result<Vec<u8>> {
        let mut bytes = Vec::new();
        self.link_executable_pages(device, queue, input, |output_base, page| {
            if output_base as usize != bytes.len() {
                bail!(
                    "x86 output pages are not dense: next base {output_base}, current length {}",
                    bytes.len()
                );
            }
            bytes.extend_from_slice(page);
            Ok(())
        })?;
        Ok(bytes)
    }

    pub(crate) fn link_executable_to_writer<W: Write + Seek>(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: &GpuX86LinkInput,
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
        input: &GpuX86LinkInput,
        consume_page: impl FnMut(u32, &[u8]) -> Result<()>,
    ) -> Result<usize> {
        let resolved_relocations = self.resolve_symbol_relocations(device, queue, input)?;
        let output_plan = GpuX86PagedExecutablePlan::new(
            input,
            device.limits().max_storage_buffer_binding_size as u64,
        )
        .map_err(anyhow::Error::msg)?;
        let output_len = output_plan.output_len;
        let output_capacity = output_len.div_ceil(4).saturating_mul(4).max(4);
        let output_capacity_u32 = u32::try_from(output_capacity)
            .map_err(|_| anyhow::anyhow!("x86 linked output exceeds the 32-bit ELF model"))?;

        let object_layout =
            self.resolve_object_layout_chunks(device, queue, input, output_capacity_u32)?;
        let relocation_status = storage_u32_copy(device, "codegen.x86.link.relocation_status", 4);

        self.emit_executable_pages(
            device,
            queue,
            input,
            &resolved_relocations,
            &output_plan,
            X86ResolvedLinkBuffers {
                object_bases: &object_layout.object_bases,
                elf_layout: &object_layout.elf_layout,
                layout_status: &object_layout.layout_status,
                relocation_status: &relocation_status.buffer,
            },
            consume_page,
        )
    }

    fn emit_executable_pages(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: &GpuX86LinkInput,
        relocations: &[super::GpuX86LinkRelocationRecord],
        plan: &GpuX86PagedExecutablePlan,
        resolved: X86ResolvedLinkBuffers<'_>,
        mut consume_page: impl FnMut(u32, &[u8]) -> Result<()>,
    ) -> Result<usize> {
        let output_capacity = plan.output_len.div_ceil(4) * 4;
        let output_capacity_u32 = u32::try_from(output_capacity)
            .map_err(|_| anyhow::anyhow!("x86 linked output exceeds the 32-bit ELF model"))?;
        let mut emitted_len = 0usize;
        for page in &plan.pages {
            if emitted_len != page.output_base as usize {
                bail!(
                    "x86 output pages are not dense: next base {}, current length {}",
                    page.output_base,
                    emitted_len
                );
            }
            let page_capacity = (page.output_len as usize).div_ceil(4).max(1) * 4;
            let text_bytes = input
                .read_text_range(page.text_input.clone())
                .map_err(anyhow::Error::msg)?;
            let rodata_bytes = input
                .read_rodata_range(page.rodata_input.clone())
                .map_err(anyhow::Error::msg)?;
            let text_input = storage_input_bytes(device, "codegen.x86.link.page.text", &text_bytes);
            let rodata_input =
                storage_input_bytes(device, "codegen.x86.link.page.rodata", &rodata_bytes);
            let output = storage_u32_rw(
                device,
                "codegen.x86.link.page.output",
                page_capacity / 4,
                wgpu::BufferUsages::COPY_SRC,
            );
            let output_status = storage_u32_copy(device, "codegen.x86.link.page.output_status", 4);
            let elf_params = uniform_u32_words(
                device,
                "codegen.x86.link.page.elf_params",
                &[page.output_base, page.output_len, output_capacity_u32, 0],
            );
            let copy_params = uniform_u32_words(
                device,
                "codegen.x86.link.page.copy_params",
                &[
                    input.objects.len() as u32,
                    page.text_input.len() as u32,
                    page.rodata_input.len() as u32,
                    0,
                    page.text_input.start as u32,
                    page.rodata_input.start as u32,
                    page.output_base,
                    page.output_len,
                ],
            );
            let elf_group = reflected_bind_group(
                device,
                Some("codegen.x86.link.page.elf.bind_group"),
                &self.elf_write_pass,
                0,
                &[
                    ("gParams", elf_params.buffer.as_entire_binding()),
                    ("x86_elf_layout", resolved.elf_layout.as_entire_binding()),
                    ("layout_status", resolved.layout_status.as_entire_binding()),
                    ("out_words", output.buffer.as_entire_binding()),
                    ("status", output_status.buffer.as_entire_binding()),
                ],
            )?;
            let copy_group = reflected_bind_group(
                device,
                Some("codegen.x86.link.page.copy.bind_group"),
                &self.link_copy_sections_pass,
                0,
                &[
                    ("gCopy", copy_params.buffer.as_entire_binding()),
                    ("link_text_input", text_input.as_entire_binding()),
                    ("link_rodata_input", rodata_input.as_entire_binding()),
                    ("x86_elf_layout", resolved.elf_layout.as_entire_binding()),
                    ("layout_status", resolved.layout_status.as_entire_binding()),
                    ("out_words", output.buffer.as_entire_binding()),
                ],
            )?;
            let max_relocations_per_batch = max_relocation_batch_records(
                device.limits().max_storage_buffer_binding_size as usize,
            )?
            .min(page.relocation_indices.len().max(1));
            let relocation_a = storage_u32_rw(
                device,
                "codegen.x86.link.page.relocation_a",
                max_relocations_per_batch * 4,
                wgpu::BufferUsages::COPY_DST,
            );
            let relocation_b = storage_u32_rw(
                device,
                "codegen.x86.link.page.relocation_b",
                max_relocations_per_batch * 4,
                wgpu::BufferUsages::COPY_DST,
            );
            let relocation_c = storage_u32_rw(
                device,
                "codegen.x86.link.page.relocation_c",
                max_relocations_per_batch * 4,
                wgpu::BufferUsages::COPY_DST,
            );
            let relocation_params =
                uniform_u32_words(device, "codegen.x86.link.page.relocation_params", &[0; 8]);
            let relocate_group = reflected_bind_group(
                device,
                Some("codegen.x86.link.page.relocate.bind_group"),
                &self.link_relocate_pass,
                0,
                &[
                    ("gReloc", relocation_params.buffer.as_entire_binding()),
                    ("link_relocation_a", relocation_a.buffer.as_entire_binding()),
                    ("link_relocation_b", relocation_b.buffer.as_entire_binding()),
                    ("link_relocation_c", relocation_c.buffer.as_entire_binding()),
                    ("x86_elf_layout", resolved.elf_layout.as_entire_binding()),
                    ("out_words", output.buffer.as_entire_binding()),
                    (
                        "link_relocation_status",
                        resolved.relocation_status.as_entire_binding(),
                    ),
                ],
            )?;
            queue.write_buffer(
                resolved.relocation_status,
                0,
                &u32_words_bytes(&[1, 0, u32::MAX, page.relocation_indices.len() as u32]),
            );
            let readback = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("rb.codegen.x86.link.page"),
                size: (page_capacity + 32) as u64,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            });
            let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("codegen.x86.link.page.encoder"),
            });
            encoder.clear_buffer(&output.buffer, 0, None);
            encoder.clear_buffer(&output_status.buffer, 0, None);
            dispatch_compute_pass(
                &mut encoder,
                "link.page.elf_write",
                "codegen.x86.link.page.elf_write",
                &self.elf_write_pass,
                &elf_group,
                workgroup_grid_1d(((page_capacity / 4) as u32).div_ceil(256)),
            );
            let copy_count = page.text_input.len().max(page.rodata_input.len()).max(1) as u32;
            dispatch_compute_pass(
                &mut encoder,
                "link.page.copy_sections",
                "codegen.x86.link.page.copy_sections",
                &self.link_copy_sections_pass,
                &copy_group,
                workgroup_grid_1d(copy_count.div_ceil(256)),
            );
            crate::gpu::passes_core::submit_with_progress(
                queue,
                "codegen.x86.link.page.initialize",
                encoder.finish(),
            );
            for (batch_index, indices) in page
                .relocation_indices
                .chunks(max_relocations_per_batch)
                .enumerate()
            {
                let relocation_base = batch_index
                    .checked_mul(max_relocations_per_batch)
                    .and_then(|base| u32::try_from(base).ok())
                    .ok_or_else(|| anyhow::anyhow!("x86 relocation batch base exceeds u32"))?;
                let (a_words, b_words, c_words) =
                    relocation_words(input, relocations, resolved.object_bases, indices)?;
                queue.write_buffer(&relocation_a.buffer, 0, &u32_words_bytes(&a_words));
                queue.write_buffer(&relocation_b.buffer, 0, &u32_words_bytes(&b_words));
                queue.write_buffer(&relocation_c.buffer, 0, &u32_words_bytes(&c_words));
                queue.write_buffer(
                    &relocation_params.buffer,
                    0,
                    &u32_words_bytes(&[
                        input.objects.len() as u32,
                        indices.len() as u32,
                        0,
                        relocation_base,
                        page.output_base,
                        page.output_len,
                        0,
                        0,
                    ]),
                );
                let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("codegen.x86.link.page.relocation_batch.encoder"),
                });
                dispatch_compute_pass(
                    &mut encoder,
                    "link.page.relocate",
                    "codegen.x86.link.page.relocate",
                    &self.link_relocate_pass,
                    &relocate_group,
                    workgroup_grid_1d((indices.len() as u32).div_ceil(256)),
                );
                crate::gpu::passes_core::submit_with_progress(
                    queue,
                    "codegen.x86.link.page.relocation_batch",
                    encoder.finish(),
                );
            }
            let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("codegen.x86.link.page.readback.encoder"),
            });
            encoder.copy_buffer_to_buffer(&output.buffer, 0, &readback, 0, page_capacity as u64);
            for (index, status) in [&output_status.buffer, resolved.relocation_status]
                .into_iter()
                .enumerate()
            {
                encoder.copy_buffer_to_buffer(
                    status,
                    0,
                    &readback,
                    (page_capacity + index * 16) as u64,
                    16,
                );
            }
            crate::gpu::passes_core::submit_with_progress(
                queue,
                "codegen.x86.link.page",
                encoder.finish(),
            );
            let slice = readback.slice(..);
            crate::gpu::passes_core::wait_for_readback_map(
                device,
                &slice,
                "codegen.x86.link.page",
                std::time::Duration::from_secs(30),
            )?;
            let mapped = slice.get_mapped_range();
            let output_status_words = crate::gpu::readback::read_u32_words::<4>(
                &mapped[page_capacity..page_capacity + 16],
                "x86 linked output status",
            )?;
            let relocation_status_words = crate::gpu::readback::read_u32_words::<4>(
                &mapped[page_capacity + 16..page_capacity + 32],
                "x86 linked relocation status",
            )?;
            if output_status_words != [plan.output_len as u32, 1, 0, u32::MAX] {
                bail!("x86 GPU linker output failed with status {output_status_words:?}");
            }
            if relocation_status_words[0] != 1 || relocation_status_words[1] != 0 {
                bail!("x86 GPU linker relocation failed with status {relocation_status_words:?}");
            }
            consume_page(page.output_base, &mapped[..page.output_len as usize])?;
            emitted_len += page.output_len as usize;
            drop(mapped);
            readback.unmap();
        }
        Ok(emitted_len)
    }
}

pub(super) fn relocation_words(
    input: &GpuX86LinkInput,
    relocations: &[super::GpuX86LinkRelocationRecord],
    object_bases: &[[u32; 2]],
    indices: &[usize],
) -> Result<(Vec<u32>, Vec<u32>, Vec<u32>)> {
    let mut a = Vec::with_capacity(indices.len() * 4);
    let mut b = Vec::with_capacity(indices.len() * 4);
    let mut c = Vec::with_capacity(indices.len() * 4);
    for &index in indices {
        let relocation = relocations
            .get(index)
            .ok_or_else(|| anyhow::anyhow!("x86 output page relocation index is invalid"))?;
        let site_file = section_file_offset(
            input,
            object_bases,
            relocation.object_index,
            relocation.site_section,
            relocation.site_offset,
        )?;
        let (target_object, target_section) = match relocation.target_kind {
            1 => (relocation.object_index, relocation.target_index),
            2 => (relocation.target_index, relocation.target_section),
            kind => bail!("x86 relocation has invalid target kind {kind}"),
        };
        let target_file = section_file_offset(
            input,
            object_bases,
            target_object,
            target_section,
            relocation.target_offset,
        )?;
        a.extend_from_slice(&[site_file, relocation.kind, 0, 0]);
        b.extend_from_slice(&[target_file, relocation.target_kind, 0, relocation.addend_lo]);
        c.extend_from_slice(&[relocation.addend_hi, 0, 0, 0]);
    }
    Ok((a, b, c))
}

fn section_file_offset(
    input: &GpuX86LinkInput,
    object_bases: &[[u32; 2]],
    object_index: u32,
    section: u32,
    section_offset: u32,
) -> Result<u32> {
    let base = object_bases
        .get(object_index as usize)
        .ok_or_else(|| anyhow::anyhow!("x86 relocation object index is invalid"))?;
    let (section_file_start, object_section_base) = match section {
        1 => (0x78u32, base[0]),
        2 => (
            0x78u32
                .checked_add(
                    u32::try_from(input.text_len())
                        .map_err(|_| anyhow::anyhow!("x86 text length exceeds u32"))?,
                )
                .ok_or_else(|| anyhow::anyhow!("x86 rodata file offset exceeds u32"))?,
            base[1],
        ),
        _ => bail!("x86 relocation section {section} is invalid"),
    };
    section_file_start
        .checked_add(object_section_base)
        .and_then(|offset| offset.checked_add(section_offset))
        .ok_or_else(|| anyhow::anyhow!("x86 relocation file offset exceeds u32"))
}

fn max_relocation_batch_records(max_storage_buffer_binding_size: usize) -> Result<usize> {
    let batch_bytes = max_storage_buffer_binding_size.min(RELOCATION_BATCH_BYTES_PER_COLUMN);
    let records = batch_bytes / RELOCATION_RECORD_BYTES_PER_COLUMN;
    if records == 0 {
        bail!(
            "x86 storage binding limit {max_storage_buffer_binding_size} cannot hold one relocation record"
        );
    }
    Ok(records.min(u32::MAX as usize))
}

pub(super) fn storage_input_u32(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    let contents = if words.is_empty() {
        u32_words_bytes(&[0])
    } else {
        u32_words_bytes(words)
    };
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &contents,
        usage: wgpu::BufferUsages::STORAGE,
    })
}

fn storage_input_bytes(device: &wgpu::Device, label: &str, bytes: &[u8]) -> wgpu::Buffer {
    let mut padded = bytes.to_vec();
    padded.resize(padded.len().div_ceil(4).max(1) * 4, 0);
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &padded,
        usage: wgpu::BufferUsages::STORAGE,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::codegen::{
        GpuLinkByteSource,
        x86::link::{GpuX86LinkObjectRecord, GpuX86LinkRelocationRecord},
    };

    #[test]
    fn relocation_batch_size_is_bounded_by_each_gpu_column_binding() {
        assert_eq!(max_relocation_batch_records(64).unwrap(), 4);
        assert_eq!(
            max_relocation_batch_records(128 * 1024 * 1024).unwrap(),
            RELOCATION_BATCH_BYTES_PER_COLUMN / RELOCATION_RECORD_BYTES_PER_COLUMN
        );
        assert!(max_relocation_batch_records(15).is_err());
    }

    #[test]
    fn relocation_batch_uses_gpu_scanned_cross_object_file_offsets() {
        let input = GpuX86LinkInput {
            objects: vec![
                GpuX86LinkObjectRecord {
                    text_input_start: 0,
                    text_len: 6,
                    rodata_input_start: 0,
                    rodata_len: 0,
                    relocation_start: 0,
                    relocation_count: 1,
                    symbol_start: 0,
                    symbol_count: 0,
                    entry_offset: 0,
                },
                GpuX86LinkObjectRecord {
                    text_input_start: 6,
                    text_len: 6,
                    rodata_input_start: 0,
                    rodata_len: 0,
                    relocation_start: 1,
                    relocation_count: 0,
                    symbol_start: 0,
                    symbol_count: 0,
                    entry_offset: u32::MAX,
                },
            ],
            text: GpuLinkByteSource::resident("test text", vec![0; 12]),
            rodata: GpuLinkByteSource::resident("test rodata", Vec::new()),
            relocations: Vec::new(),
            symbols: Vec::new(),
            entry_object_index: 0,
        };
        let relocations = [GpuX86LinkRelocationRecord {
            object_index: 0,
            kind: 2,
            site_section: 1,
            site_offset: 1,
            target_kind: 2,
            target_index: 1,
            target_offset: 0,
            target_section: 1,
            addend_lo: (-4i32) as u32,
            addend_hi: u32::MAX,
        }];

        let (a, b, c) = relocation_words(&input, &relocations, &[[0, 0], [6, 0]], &[0])
            .expect("encode relocation batch");

        assert_eq!(a, [0x79, 2, 0, 0]);
        assert_eq!(b, [0x7e, 2, 0, (-4i32) as u32]);
        assert_eq!(c, [u32::MAX, 0, 0, 0]);
    }
}
