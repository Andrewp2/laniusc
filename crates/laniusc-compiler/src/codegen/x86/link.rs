//! Bounded input model for the GPU x86 linker.
//!
//! The host validates persisted containers and flattens their independent
//! arrays into upload buffers. Final section placement, symbol resolution,
//! byte movement, and relocation application remain GPU work.

mod executable;

use anyhow::Result;
#[cfg(test)]
use anyhow::bail;
#[cfg(test)]
use wgpu::util::DeviceExt;

#[cfg(test)]
use super::support::{
    dispatch_compute_pass,
    reflected_bind_group,
    storage_u32_copy,
    storage_u32_rw,
    u32_words_bytes,
    uniform_u32_words,
    workgroup_grid_1d,
};
use super::{GpuX86CodeGenerator, GpuX86RelocatableObject, GpuX86RelocationTargetKind};

pub(super) const X86_LINK_SYMBOL_IDENTITY_BYTES: usize = 12;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct GpuX86LinkObjectRecord {
    pub text_input_start: u32,
    pub text_len: u32,
    pub rodata_input_start: u32,
    pub rodata_len: u32,
    pub relocation_start: u32,
    pub relocation_count: u32,
    pub symbol_start: u32,
    pub symbol_count: u32,
    pub entry_offset: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct GpuX86LinkRelocationRecord {
    pub object_index: u32,
    pub kind: u32,
    pub site_section: u32,
    pub site_offset: u32,
    pub target_kind: u32,
    pub target_index: u32,
    pub target_offset: u32,
    pub addend_lo: u32,
    pub addend_hi: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct GpuX86LinkSymbolRecord {
    pub object_index: u32,
    pub identity: [u32; 3],
    pub section: u32,
    pub offset: u32,
    pub size: u32,
    pub flags: u32,
}

/// Flat, bounds-checked columns ready for GPU upload.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct GpuX86LinkInput {
    pub(super) objects: Vec<GpuX86LinkObjectRecord>,
    pub(super) text: Vec<u8>,
    pub(super) rodata: Vec<u8>,
    pub(super) relocations: Vec<GpuX86LinkRelocationRecord>,
    pub(super) symbols: Vec<GpuX86LinkSymbolRecord>,
    pub(super) entry_object_index: u32,
}

impl GpuX86LinkInput {
    /// Flattens independently validated object containers for one final link.
    pub(crate) fn for_executable(
        source_objects: &[GpuX86RelocatableObject],
    ) -> Result<Self, String> {
        if source_objects.is_empty() {
            return Err("x86 link requires at least one object".to_string());
        }
        checked_u32_count("object", source_objects.len())?;

        let mut input = Self {
            objects: Vec::with_capacity(source_objects.len()),
            text: Vec::new(),
            rodata: Vec::new(),
            relocations: Vec::new(),
            symbols: Vec::new(),
            entry_object_index: u32::MAX,
        };

        for (object_index, object) in source_objects.iter().enumerate() {
            object.validate()?;
            let object_index = object_index as u32;
            let text_input_start = checked_u32_count("flat text byte", input.text.len())?;
            let rodata_input_start = checked_u32_count("flat rodata byte", input.rodata.len())?;
            let relocation_start = checked_u32_count("flat relocation", input.relocations.len())?;
            let symbol_start = checked_u32_count("flat symbol", input.symbols.len())?;

            if let Some(entry_offset) = object.entry_offset {
                if input.entry_object_index != u32::MAX {
                    return Err(format!(
                        "x86 link has multiple entry objects: {} and {object_index}",
                        input.entry_object_index
                    ));
                }
                input.entry_object_index = object_index;
                debug_assert!(entry_offset < object.text.len() as u32);
            }

            input.text.extend_from_slice(&object.text);
            input.rodata.extend_from_slice(&object.rodata);
            checked_u32_count("flat text byte", input.text.len())?;
            checked_u32_count("flat rodata byte", input.rodata.len())?;

            for relocation in &object.relocations {
                let target_index = match relocation.target_kind {
                    GpuX86RelocationTargetKind::SectionOffset => relocation.target_index,
                    GpuX86RelocationTargetKind::Symbol => symbol_start
                        .checked_add(relocation.target_index)
                        .ok_or_else(|| "x86 link global symbol index overflows".to_string())?,
                };
                input.relocations.push(GpuX86LinkRelocationRecord {
                    object_index,
                    kind: relocation.kind as u32,
                    site_section: relocation.site_section as u32,
                    site_offset: relocation.site_offset,
                    target_kind: relocation.target_kind as u32,
                    target_index,
                    target_offset: relocation.target_offset,
                    addend_lo: relocation.addend as u64 as u32,
                    addend_hi: ((relocation.addend as u64) >> 32) as u32,
                });
            }

            for (symbol_index, symbol) in object.symbols.iter().enumerate() {
                let identity_start = symbol.identity_byte_start as usize;
                let identity_end = identity_start
                    .checked_add(symbol.identity_byte_len as usize)
                    .ok_or_else(|| "x86 link symbol identity range overflows".to_string())?;
                let identity = object
                    .identity_bytes
                    .get(identity_start..identity_end)
                    .ok_or_else(|| "x86 link symbol identity range is invalid".to_string())?;
                if identity.len() != X86_LINK_SYMBOL_IDENTITY_BYTES {
                    return Err(format!(
                        "x86 link object {object_index} symbol {symbol_index} has {} identity bytes; expected {X86_LINK_SYMBOL_IDENTITY_BYTES}",
                        identity.len()
                    ));
                }
                input.symbols.push(GpuX86LinkSymbolRecord {
                    object_index,
                    identity: [
                        u32::from_le_bytes(identity[0..4].try_into().expect("four bytes")),
                        u32::from_le_bytes(identity[4..8].try_into().expect("four bytes")),
                        u32::from_le_bytes(identity[8..12].try_into().expect("four bytes")),
                    ],
                    section: symbol.section as u32,
                    offset: symbol.offset,
                    size: symbol.size,
                    flags: symbol.flags,
                });
            }
            checked_u32_count("flat relocation", input.relocations.len())?;
            checked_u32_count("flat symbol", input.symbols.len())?;

            input.objects.push(GpuX86LinkObjectRecord {
                text_input_start,
                text_len: object.text.len() as u32,
                rodata_input_start,
                rodata_len: object.rodata.len() as u32,
                relocation_start,
                relocation_count: object.relocations.len() as u32,
                symbol_start,
                symbol_count: object.symbols.len() as u32,
                entry_offset: object.entry_offset.unwrap_or(u32::MAX),
            });
        }

        if input.entry_object_index == u32::MAX {
            return Err("x86 link has no entry object".to_string());
        }
        Ok(input)
    }
}

fn checked_u32_count(label: &str, count: usize) -> Result<u32, String> {
    u32::try_from(count).map_err(|_| format!("x86 link {label} count {count} exceeds u32"))
}

impl GpuX86CodeGenerator {
    #[cfg(test)]
    fn relocate_for_test(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: &GpuX86LinkInput,
        object_bases: &[[u32; 2]],
        symbol_definitions: &[u32],
        initial_output: &[u8],
    ) -> Result<(Vec<u8>, [u32; 4])> {
        let mut relocation_a = Vec::with_capacity(input.relocations.len() * 4);
        let mut relocation_b = Vec::with_capacity(input.relocations.len() * 4);
        let mut relocation_c = Vec::with_capacity(input.relocations.len() * 4);
        for relocation in &input.relocations {
            relocation_a.extend_from_slice(&[
                relocation.object_index,
                relocation.kind,
                relocation.site_section,
                relocation.site_offset,
            ]);
            relocation_b.extend_from_slice(&[
                relocation.target_kind,
                relocation.target_index,
                relocation.target_offset,
                relocation.addend_lo,
            ]);
            relocation_c.extend_from_slice(&[relocation.addend_hi, 0, 0, 0]);
        }
        let mut base_words = Vec::with_capacity(object_bases.len() * 2);
        for base in object_bases {
            base_words.extend_from_slice(base);
        }
        let mut identity_section = Vec::with_capacity(input.symbols.len() * 4);
        let mut locations = Vec::with_capacity(input.symbols.len() * 4);
        for symbol in &input.symbols {
            identity_section.extend_from_slice(&[
                symbol.identity[0],
                symbol.identity[1],
                symbol.identity[2],
                symbol.section,
            ]);
            locations.extend_from_slice(&[
                symbol.object_index,
                symbol.offset,
                symbol.size,
                symbol.flags,
            ]);
        }
        let relocation_a =
            storage_input_u32(device, "codegen.x86.link.relocation_a", &relocation_a);
        let relocation_b =
            storage_input_u32(device, "codegen.x86.link.relocation_b", &relocation_b);
        let relocation_c =
            storage_input_u32(device, "codegen.x86.link.relocation_c", &relocation_c);
        let object_bases = storage_input_u32(device, "codegen.x86.link.object_bases", &base_words);
        let identity_sections = storage_input_u32(
            device,
            "codegen.x86.link.relocation_symbol_identity_section",
            &identity_section,
        );
        let symbol_locations =
            storage_input_u32(device, "codegen.x86.link.symbol_location", &locations);
        let definitions = storage_input_u32(
            device,
            "codegen.x86.link.relocation_symbol_definition",
            symbol_definitions,
        );
        let symbol_status = storage_input_u32(
            device,
            "codegen.x86.link.relocation_symbol_status",
            &[1, 0, u32::MAX, input.symbols.len() as u32],
        );
        let text_len = input.text.len() as u32;
        let rodata_len = input.rodata.len() as u32;
        let elf_layout_words = [
            0x78,
            text_len,
            initial_output.len() as u32,
            0x400078,
            0x400000,
            0x1000,
            0x78 + text_len,
            rodata_len,
        ];
        let elf_layout = storage_input_u32(
            device,
            "codegen.x86.link.relocation_elf_layout",
            &elf_layout_words,
        );
        let output =
            storage_input_bytes_copy(device, "codegen.x86.link.relocation_output", initial_output);
        let relocation_status = storage_u32_copy(device, "codegen.x86.link.relocation_status", 4);
        let params = uniform_u32_words(
            device,
            "codegen.x86.link.relocation_params",
            &[
                input.objects.len() as u32,
                input.relocations.len() as u32,
                input.symbols.len() as u32,
                0,
            ],
        );
        let group = reflected_bind_group(
            device,
            Some("codegen.x86.link.relocate.bind_group"),
            &self.link_relocate_pass,
            0,
            &[
                ("gReloc", params.buffer.as_entire_binding()),
                ("link_relocation_a", relocation_a.as_entire_binding()),
                ("link_relocation_b", relocation_b.as_entire_binding()),
                ("link_relocation_c", relocation_c.as_entire_binding()),
                ("link_object_section_base", object_bases.as_entire_binding()),
                (
                    "link_symbol_identity_section",
                    identity_sections.as_entire_binding(),
                ),
                ("link_symbol_location", symbol_locations.as_entire_binding()),
                ("link_symbol_definition", definitions.as_entire_binding()),
                ("link_symbol_status", symbol_status.as_entire_binding()),
                ("x86_elf_layout", elf_layout.as_entire_binding()),
                ("out_words", output.as_entire_binding()),
                (
                    "link_relocation_status",
                    relocation_status.buffer.as_entire_binding(),
                ),
            ],
        )?;
        queue.write_buffer(
            &relocation_status.buffer,
            0,
            &u32_words_bytes(&[1, 0, u32::MAX, input.relocations.len() as u32]),
        );
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.x86.link.relocate.encoder"),
        });
        dispatch_compute_pass(
            &mut encoder,
            "link.relocate",
            "codegen.x86.link.relocate",
            &self.link_relocate_pass,
            &group,
            workgroup_grid_1d((input.relocations.len() as u32).div_ceil(256).max(1)),
        );
        let padded_len = initial_output.len().div_ceil(4).max(1) * 4;
        let readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.codegen.x86.link.relocate"),
            size: (padded_len + 16) as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&output, 0, &readback, 0, padded_len as u64);
        encoder.copy_buffer_to_buffer(
            &relocation_status.buffer,
            0,
            &readback,
            padded_len as u64,
            16,
        );
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.x86.link.relocate",
            encoder.finish(),
        );
        let slice = readback.slice(..);
        crate::gpu::passes_core::wait_for_readback_map(
            device,
            &slice,
            "codegen.x86.link.relocate",
            std::time::Duration::from_secs(30),
        )?;
        let (bytes, status) = {
            let mapped = slice.get_mapped_range();
            let bytes = mapped[..initial_output.len()].to_vec();
            let status = crate::gpu::readback::read_u32_words::<4>(
                &mapped[padded_len..padded_len + 16],
                "x86 link relocation status",
            )?;
            drop(mapped);
            (bytes, status)
        };
        readback.unmap();
        Ok((bytes, status))
    }

    #[cfg(test)]
    fn resolve_symbols_for_test(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        symbols: &[GpuX86LinkSymbolRecord],
    ) -> Result<(Vec<u32>, [u32; 4])> {
        if symbols.is_empty() {
            return Ok((Vec::new(), [1, 0, u32::MAX, 0]));
        }
        let symbol_count = symbols.len();
        let block_count = symbol_count.div_ceil(256).max(1);
        if block_count > 4096 {
            bail!("x86 linker symbol radix page exceeds 4096 blocks");
        }
        let mut identity_section_words = Vec::with_capacity(symbol_count * 4);
        for symbol in symbols {
            identity_section_words.extend_from_slice(&[
                symbol.identity[0],
                symbol.identity[1],
                symbol.identity[2],
                symbol.section,
            ]);
        }
        let identity_sections = storage_input_u32(
            device,
            "codegen.x86.link.symbol_identity_section",
            &identity_section_words,
        );
        let symbol_count_buffer = storage_input_u32(
            device,
            "codegen.x86.link.symbol_count",
            &[symbol_count as u32],
        );
        let order_a = storage_u32_rw(
            device,
            "codegen.x86.link.symbol_order_a",
            symbol_count,
            wgpu::BufferUsages::empty(),
        );
        let order_b = storage_u32_rw(
            device,
            "codegen.x86.link.symbol_order_b",
            symbol_count,
            wgpu::BufferUsages::empty(),
        );
        let histogram = storage_u32_rw(
            device,
            "codegen.x86.link.symbol_histogram",
            block_count * 257,
            wgpu::BufferUsages::empty(),
        );
        let block_bucket_prefix = storage_u32_rw(
            device,
            "codegen.x86.link.symbol_block_bucket_prefix",
            block_count * 257,
            wgpu::BufferUsages::empty(),
        );
        let bucket_total = storage_u32_rw(
            device,
            "codegen.x86.link.symbol_bucket_total",
            257,
            wgpu::BufferUsages::empty(),
        );
        let bucket_base = storage_u32_rw(
            device,
            "codegen.x86.link.symbol_bucket_base",
            257,
            wgpu::BufferUsages::empty(),
        );
        let definitions =
            storage_u32_copy(device, "codegen.x86.link.symbol_definition", symbol_count);
        let status = storage_u32_copy(device, "codegen.x86.link.symbol_status", 4);

        let mut params = Vec::with_capacity(13);
        let mut histogram_groups = Vec::with_capacity(13);
        let mut prefix_groups = Vec::with_capacity(13);
        let mut bases_groups = Vec::with_capacity(13);
        let mut scatter_groups = Vec::with_capacity(13);
        for key_step in 0..13u32 {
            params.push(uniform_u32_words(
                device,
                "codegen.x86.link.symbol_radix.params",
                &[symbol_count as u32, 0, block_count as u32, key_step],
            ));
            let (order_in, order_out) = if key_step & 1 == 0 {
                (&order_a.buffer, &order_b.buffer)
            } else {
                (&order_b.buffer, &order_a.buffer)
            };
            let param_binding = params.last().unwrap().buffer.as_entire_binding();
            histogram_groups.push(reflected_bind_group(
                device,
                Some("codegen.x86.link.symbol_histogram.bind_group"),
                &self.link_symbol_histogram_pass,
                0,
                &[
                    ("gParams", param_binding.clone()),
                    (
                        "link_symbol_identity_section",
                        identity_sections.as_entire_binding(),
                    ),
                    ("link_symbol_order_in", order_in.as_entire_binding()),
                    (
                        "radix_block_histogram",
                        histogram.buffer.as_entire_binding(),
                    ),
                ],
            )?);
            prefix_groups.push(reflected_bind_group(
                device,
                Some("codegen.x86.link.symbol_bucket_prefix.bind_group"),
                &self.link_symbol_bucket_prefix_pass,
                0,
                &[
                    ("gParams", param_binding.clone()),
                    ("name_count_in", symbol_count_buffer.as_entire_binding()),
                    (
                        "radix_block_histogram",
                        histogram.buffer.as_entire_binding(),
                    ),
                    (
                        "radix_block_bucket_prefix",
                        block_bucket_prefix.buffer.as_entire_binding(),
                    ),
                    (
                        "radix_bucket_total",
                        bucket_total.buffer.as_entire_binding(),
                    ),
                ],
            )?);
            bases_groups.push(reflected_bind_group(
                device,
                Some("codegen.x86.link.symbol_bucket_bases.bind_group"),
                &self.link_symbol_bucket_bases_pass,
                0,
                &[
                    ("gParams", param_binding.clone()),
                    (
                        "radix_bucket_total",
                        bucket_total.buffer.as_entire_binding(),
                    ),
                    ("radix_bucket_base", bucket_base.buffer.as_entire_binding()),
                ],
            )?);
            scatter_groups.push(reflected_bind_group(
                device,
                Some("codegen.x86.link.symbol_scatter.bind_group"),
                &self.link_symbol_scatter_pass,
                0,
                &[
                    ("gParams", param_binding),
                    (
                        "link_symbol_identity_section",
                        identity_sections.as_entire_binding(),
                    ),
                    ("link_symbol_order_in", order_in.as_entire_binding()),
                    ("radix_bucket_base", bucket_base.buffer.as_entire_binding()),
                    (
                        "radix_block_bucket_prefix",
                        block_bucket_prefix.buffer.as_entire_binding(),
                    ),
                    ("link_symbol_order_out", order_out.as_entire_binding()),
                ],
            )?);
        }
        let seed_group = reflected_bind_group(
            device,
            Some("codegen.x86.link.symbol_seed.bind_group"),
            &self.link_symbol_seed_pass,
            0,
            &[
                ("gParams", params[0].buffer.as_entire_binding()),
                ("link_symbol_order", order_a.buffer.as_entire_binding()),
            ],
        )?;
        // Thirteen passes leave the final order in B.
        let resolve_group = reflected_bind_group(
            device,
            Some("codegen.x86.link.symbol_resolve.bind_group"),
            &self.link_symbol_resolve_pass,
            0,
            &[
                ("gParams", params[0].buffer.as_entire_binding()),
                (
                    "link_symbol_identity_section",
                    identity_sections.as_entire_binding(),
                ),
                ("link_symbol_order", order_b.buffer.as_entire_binding()),
                (
                    "link_symbol_definition",
                    definitions.buffer.as_entire_binding(),
                ),
                ("link_symbol_status", status.buffer.as_entire_binding()),
            ],
        )?;

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.x86.link.symbols.encoder"),
        });
        queue.write_buffer(
            &status.buffer,
            0,
            &u32_words_bytes(&[1, 0, u32::MAX, symbol_count as u32]),
        );
        dispatch_compute_pass(
            &mut encoder,
            "link.symbol_seed",
            "codegen.x86.link.symbol_seed",
            &self.link_symbol_seed_pass,
            &seed_group,
            workgroup_grid_1d((symbol_count as u32).div_ceil(256)),
        );
        for step in 0..13 {
            dispatch_compute_pass(
                &mut encoder,
                "link.symbol_histogram",
                "codegen.x86.link.symbol_histogram",
                &self.link_symbol_histogram_pass,
                &histogram_groups[step],
                workgroup_grid_1d(block_count as u32),
            );
            dispatch_compute_pass(
                &mut encoder,
                "link.symbol_bucket_prefix",
                "codegen.x86.link.symbol_bucket_prefix",
                &self.link_symbol_bucket_prefix_pass,
                &prefix_groups[step],
                (257, 1),
            );
            dispatch_compute_pass(
                &mut encoder,
                "link.symbol_bucket_bases",
                "codegen.x86.link.symbol_bucket_bases",
                &self.link_symbol_bucket_bases_pass,
                &bases_groups[step],
                (1, 1),
            );
            dispatch_compute_pass(
                &mut encoder,
                "link.symbol_scatter",
                "codegen.x86.link.symbol_scatter",
                &self.link_symbol_scatter_pass,
                &scatter_groups[step],
                workgroup_grid_1d(block_count as u32),
            );
        }
        dispatch_compute_pass(
            &mut encoder,
            "link.symbol_resolve",
            "codegen.x86.link.symbol_resolve",
            &self.link_symbol_resolve_pass,
            &resolve_group,
            workgroup_grid_1d((symbol_count as u32).div_ceil(256)),
        );

        let definition_bytes = symbol_count * 4;
        let readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.codegen.x86.link.symbols"),
            size: (definition_bytes + 16) as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(
            &definitions.buffer,
            0,
            &readback,
            0,
            definition_bytes as u64,
        );
        encoder.copy_buffer_to_buffer(&status.buffer, 0, &readback, definition_bytes as u64, 16);
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.x86.link.symbols",
            encoder.finish(),
        );
        let slice = readback.slice(..);
        crate::gpu::passes_core::wait_for_readback_map(
            device,
            &slice,
            "codegen.x86.link.symbols",
            std::time::Duration::from_secs(30),
        )?;
        let (definition_rows, status_words) = {
            let mapped = slice.get_mapped_range();
            let definition_rows = mapped[..definition_bytes]
                .chunks_exact(4)
                .map(|word| u32::from_le_bytes(word.try_into().expect("four bytes")))
                .collect();
            let status_words = crate::gpu::readback::read_u32_words::<4>(
                &mapped[definition_bytes..definition_bytes + 16],
                "x86 link symbol status",
            )?;
            drop(mapped);
            (definition_rows, status_words)
        };
        readback.unmap();
        Ok((definition_rows, status_words))
    }

    /// Runs the section-layout/copy prefix of the GPU linker. Symbol resolution
    /// and relocation patching are deliberately not bypassed here; the method
    /// remains private until the remaining linker passes consume its buffers.
    #[cfg(test)]
    fn link_sections_for_test(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: &GpuX86LinkInput,
    ) -> Result<Vec<u8>> {
        let object_count = input.objects.len();
        let object_block_count = object_count.div_ceil(256).max(1);
        let output_len = 0x78usize
            .checked_add(input.text.len())
            .and_then(|len| len.checked_add(input.rodata.len()))
            .ok_or_else(|| anyhow::anyhow!("x86 linked output length overflows"))?;
        let output_capacity = output_len.div_ceil(4).saturating_mul(4).max(4);
        let output_capacity_u32 = u32::try_from(output_capacity)
            .map_err(|_| anyhow::anyhow!("x86 linked output exceeds u32"))?;

        let mut object_section_words = Vec::with_capacity(object_count * 4);
        let mut object_entry_words = Vec::with_capacity(object_count);
        for object in &input.objects {
            object_section_words.extend_from_slice(&[
                object.text_input_start,
                object.text_len,
                object.rodata_input_start,
                object.rodata_len,
            ]);
            object_entry_words.push(object.entry_offset);
        }
        let object_sections = storage_input_u32(
            device,
            "codegen.x86.link.object_sections",
            &object_section_words,
        );
        let object_entries = storage_input_u32(
            device,
            "codegen.x86.link.object_entries",
            &object_entry_words,
        );
        let text_input = storage_input_bytes(device, "codegen.x86.link.text_input", &input.text);
        let rodata_input =
            storage_input_bytes(device, "codegen.x86.link.rodata_input", &input.rodata);
        let local_prefix = storage_u32_rw(
            device,
            "codegen.x86.link.section_local_prefix",
            object_count * 2,
            wgpu::BufferUsages::empty(),
        );
        let block_sum = storage_u32_rw(
            device,
            "codegen.x86.link.section_block_sum",
            object_block_count * 2,
            wgpu::BufferUsages::empty(),
        );
        let block_prefix_a = storage_u32_rw(
            device,
            "codegen.x86.link.section_block_prefix_a",
            object_block_count * 2,
            wgpu::BufferUsages::empty(),
        );
        let block_prefix_b = storage_u32_rw(
            device,
            "codegen.x86.link.section_block_prefix_b",
            object_block_count * 2,
            wgpu::BufferUsages::empty(),
        );
        let object_bases = storage_u32_rw(
            device,
            "codegen.x86.link.object_section_base",
            object_count * 2,
            wgpu::BufferUsages::empty(),
        );
        let elf_layout = storage_u32_rw(
            device,
            "codegen.x86.link.elf_layout",
            8,
            wgpu::BufferUsages::empty(),
        );
        let layout_status = storage_u32_rw(
            device,
            "codegen.x86.link.layout_status",
            4,
            wgpu::BufferUsages::empty(),
        );
        let output_status = storage_u32_copy(device, "codegen.x86.link.output_status", 4);
        let output = storage_u32_rw(
            device,
            "codegen.x86.link.output",
            output_capacity / 4,
            wgpu::BufferUsages::COPY_SRC,
        );

        let link_params = uniform_u32_words(
            device,
            "codegen.x86.link.layout_params",
            &[
                object_count as u32,
                object_block_count as u32,
                input.entry_object_index,
                output_capacity_u32,
            ],
        );
        let copy_params = uniform_u32_words(
            device,
            "codegen.x86.link.copy_params",
            &[
                object_count as u32,
                input.text.len() as u32,
                input.rodata.len() as u32,
                0,
            ],
        );
        let elf_params = uniform_u32_words(
            device,
            "codegen.x86.link.elf_params",
            &[0, 0, output_capacity_u32, 0],
        );

        let local_group = reflected_bind_group(
            device,
            Some("codegen.x86.link.layout_scan_local.bind_group"),
            &self.link_layout_scan_local_pass,
            0,
            &[
                ("gLink", link_params.buffer.as_entire_binding()),
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

        let scan_steps = crate::gpu::scan::scan_step_values(object_block_count as u32);
        let mut scan_params = Vec::with_capacity(scan_steps.len());
        let mut scan_groups = Vec::with_capacity(scan_steps.len());
        for (step_i, step) in scan_steps.iter().copied().enumerate() {
            scan_params.push(uniform_u32_words(
                device,
                "codegen.x86.link.layout_scan_blocks.params",
                &[object_count as u32, object_block_count as u32, step, 0],
            ));
            let (prefix_in, prefix_out) = if step_i & 1 == 0 {
                (&block_prefix_b.buffer, &block_prefix_a.buffer)
            } else {
                (&block_prefix_a.buffer, &block_prefix_b.buffer)
            };
            scan_groups.push(reflected_bind_group(
                device,
                Some("codegen.x86.link.layout_scan_blocks.bind_group"),
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
            Some("codegen.x86.link.layout.bind_group"),
            &self.link_layout_pass,
            0,
            &[
                ("gLink", link_params.buffer.as_entire_binding()),
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
                    object_bases.buffer.as_entire_binding(),
                ),
                ("x86_elf_layout", elf_layout.buffer.as_entire_binding()),
                ("layout_status", layout_status.buffer.as_entire_binding()),
            ],
        )?;
        let elf_group = reflected_bind_group(
            device,
            Some("codegen.x86.link.elf_write.bind_group"),
            &self.elf_write_pass,
            0,
            &[
                ("gParams", elf_params.buffer.as_entire_binding()),
                ("x86_elf_layout", elf_layout.buffer.as_entire_binding()),
                ("layout_status", layout_status.buffer.as_entire_binding()),
                ("out_words", output.buffer.as_entire_binding()),
                ("status", output_status.buffer.as_entire_binding()),
            ],
        )?;
        let copy_group = reflected_bind_group(
            device,
            Some("codegen.x86.link.copy_sections.bind_group"),
            &self.link_copy_sections_pass,
            0,
            &[
                ("gCopy", copy_params.buffer.as_entire_binding()),
                ("link_object_sections", object_sections.as_entire_binding()),
                (
                    "link_object_section_base",
                    object_bases.buffer.as_entire_binding(),
                ),
                ("link_text_input", text_input.as_entire_binding()),
                ("link_rodata_input", rodata_input.as_entire_binding()),
                ("x86_elf_layout", elf_layout.buffer.as_entire_binding()),
                ("layout_status", layout_status.buffer.as_entire_binding()),
                ("out_words", output.buffer.as_entire_binding()),
            ],
        )?;

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.x86.link.sections.encoder"),
        });
        encoder.clear_buffer(&output.buffer, 0, None);
        encoder.clear_buffer(&output_status.buffer, 0, None);
        dispatch_compute_pass(
            &mut encoder,
            "link.layout_scan_local",
            "codegen.x86.link.layout_scan_local",
            &self.link_layout_scan_local_pass,
            &local_group,
            workgroup_grid_1d(object_block_count as u32),
        );
        for group in &scan_groups {
            dispatch_compute_pass(
                &mut encoder,
                "link.layout_scan_blocks",
                "codegen.x86.link.layout_scan_blocks",
                &self.link_layout_scan_blocks_pass,
                group,
                workgroup_grid_1d((object_block_count as u32).div_ceil(256)),
            );
        }
        dispatch_compute_pass(
            &mut encoder,
            "link.layout",
            "codegen.x86.link.layout",
            &self.link_layout_pass,
            &layout_group,
            workgroup_grid_1d((object_count as u32).div_ceil(256)),
        );
        dispatch_compute_pass(
            &mut encoder,
            "link.elf_write",
            "codegen.x86.link.elf_write",
            &self.elf_write_pass,
            &elf_group,
            (1, 1),
        );
        let copy_items = input.text.len().max(input.rodata.len()).max(1) as u32;
        dispatch_compute_pass(
            &mut encoder,
            "link.copy_sections",
            "codegen.x86.link.copy_sections",
            &self.link_copy_sections_pass,
            &copy_group,
            workgroup_grid_1d(copy_items.div_ceil(256)),
        );

        let readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.codegen.x86.link.sections"),
            size: (output_capacity + 16) as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&output.buffer, 0, &readback, 0, output_capacity as u64);
        encoder.copy_buffer_to_buffer(
            &output_status.buffer,
            0,
            &readback,
            output_capacity as u64,
            16,
        );
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.x86.link.sections",
            encoder.finish(),
        );
        let slice = readback.slice(..);
        crate::gpu::passes_core::wait_for_readback_map(
            device,
            &slice,
            "codegen.x86.link.sections",
            std::time::Duration::from_secs(30),
        )?;
        let bytes = {
            let mapped = slice.get_mapped_range();
            let status = crate::gpu::readback::read_u32_words::<4>(
                &mapped[output_capacity..output_capacity + 16],
                "x86 link section status",
            )?;
            if status[1] != 1 || status[2] != 0 || status[0] as usize != output_len {
                drop(mapped);
                readback.unmap();
                bail!("x86 link section passes failed with status {status:?}");
            }
            let bytes = mapped[..output_len].to_vec();
            drop(mapped);
            bytes
        };
        readback.unmap();
        Ok(bytes)
    }
}

#[cfg(test)]
fn storage_input_u32(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &u32_words_bytes(words),
        usage: wgpu::BufferUsages::STORAGE,
    })
}

#[cfg(test)]
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
fn storage_input_bytes_copy(device: &wgpu::Device, label: &str, bytes: &[u8]) -> wgpu::Buffer {
    let mut padded = bytes.to_vec();
    padded.resize(padded.len().div_ceil(4).max(1) * 4, 0);
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &padded,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        codegen::x86::{
            GPU_X86_OBJECT_VERSION,
            GpuX86ObjectSection,
            GpuX86ObjectSymbolRecord,
            GpuX86RelocationKind,
            GpuX86RelocationRecord,
        },
        compiler::stable_name_hash,
    };

    fn identity(library_id: u32, unit_id: u32, declaration: u32) -> Vec<u8> {
        [library_id, unit_id, declaration]
            .into_iter()
            .flat_map(u32::to_le_bytes)
            .collect()
    }

    fn symbol(identity_bytes: &[u8], section: GpuX86ObjectSection) -> GpuX86ObjectSymbolRecord {
        let (identity_hash_lo, identity_hash_hi) = stable_name_hash(identity_bytes);
        GpuX86ObjectSymbolRecord {
            identity_hash_lo,
            identity_hash_hi,
            identity_byte_start: 0,
            identity_byte_len: identity_bytes.len() as u32,
            section,
            offset: u32::from(section != GpuX86ObjectSection::Undefined),
            size: u32::from(section != GpuX86ObjectSection::Undefined),
            flags: 0,
        }
    }

    #[test]
    fn link_input_globalizes_symbol_relocations_without_resolving_them() {
        let defined_identity = identity(6, 2, 0);
        let undefined_identity = defined_identity.clone();
        let dependency = GpuX86RelocatableObject {
            version: GPU_X86_OBJECT_VERSION,
            library_id: 6,
            unit_id: 2,
            entry_offset: None,
            text: vec![0x90, 0xc3],
            rodata: vec![1, 2],
            relocations: Vec::new(),
            symbols: vec![symbol(&defined_identity, GpuX86ObjectSection::Text)],
            identity_bytes: defined_identity,
        };
        let app = GpuX86RelocatableObject {
            version: GPU_X86_OBJECT_VERSION,
            library_id: 7,
            unit_id: 3,
            entry_offset: Some(0),
            text: vec![0xe8, 0, 0, 0, 0, 0xc3],
            rodata: vec![3],
            relocations: vec![GpuX86RelocationRecord {
                kind: GpuX86RelocationKind::CallRel32,
                site_section: GpuX86ObjectSection::Text,
                site_offset: 1,
                target_kind: GpuX86RelocationTargetKind::Symbol,
                target_index: 0,
                target_offset: 0,
                addend: -4,
            }],
            symbols: vec![symbol(&undefined_identity, GpuX86ObjectSection::Undefined)],
            identity_bytes: undefined_identity,
        };

        let input = GpuX86LinkInput::for_executable(&[dependency, app]).expect("link input");

        assert_eq!(input.entry_object_index, 1);
        assert_eq!(input.objects[1].text_input_start, 2);
        assert_eq!(input.objects[1].rodata_input_start, 2);
        assert_eq!(input.objects[1].symbol_start, 1);
        assert_eq!(input.relocations[0].target_index, 1);
        assert_eq!(input.symbols[0].identity, input.symbols[1].identity);
        assert_eq!(input.text, vec![0x90, 0xc3, 0xe8, 0, 0, 0, 0, 0xc3]);
    }

    #[test]
    fn executable_link_input_requires_one_entry_and_fixed_semantic_identities() {
        let mut object = GpuX86RelocatableObject {
            version: GPU_X86_OBJECT_VERSION,
            library_id: 1,
            unit_id: 0,
            entry_offset: None,
            text: vec![0xc3],
            rodata: Vec::new(),
            relocations: Vec::new(),
            symbols: Vec::new(),
            identity_bytes: Vec::new(),
        };
        assert!(GpuX86LinkInput::for_executable(&[object.clone()]).is_err());
        object.entry_offset = Some(0);
        assert!(GpuX86LinkInput::for_executable(&[object.clone(), object.clone()]).is_err());

        let short_identity = vec![0; 8];
        object.symbols = vec![symbol(&short_identity, GpuX86ObjectSection::Undefined)];
        object.identity_bytes = short_identity;
        assert!(GpuX86LinkInput::for_executable(&[object]).is_err());
    }

    #[test]
    fn gpu_link_section_scan_rebases_entry_and_copies_unaligned_sections() {
        let gpu = crate::gpu::device::global();
        let generator = GpuX86CodeGenerator::new_with_device(gpu).expect("x86 generator");
        let empty = GpuX86RelocatableObject {
            version: GPU_X86_OBJECT_VERSION,
            library_id: 1,
            unit_id: 0,
            entry_offset: None,
            text: Vec::new(),
            rodata: Vec::new(),
            relocations: Vec::new(),
            symbols: Vec::new(),
            identity_bytes: Vec::new(),
        };
        let dependency = GpuX86RelocatableObject {
            version: GPU_X86_OBJECT_VERSION,
            library_id: 2,
            unit_id: 0,
            entry_offset: None,
            text: vec![0x90, 0xc3, 0xcc],
            rodata: vec![1],
            relocations: Vec::new(),
            symbols: Vec::new(),
            identity_bytes: Vec::new(),
        };
        let app = GpuX86RelocatableObject {
            version: GPU_X86_OBJECT_VERSION,
            library_id: 3,
            unit_id: 0,
            entry_offset: Some(1),
            text: vec![0x90, 0xc3],
            rodata: vec![2, 3, 4],
            relocations: Vec::new(),
            symbols: Vec::new(),
            identity_bytes: Vec::new(),
        };
        let input = GpuX86LinkInput::for_executable(&[empty, dependency, app]).expect("link input");

        let bytes = generator
            .link_sections_for_test(&gpu.device, &gpu.queue, &input)
            .expect("GPU section link");

        assert_eq!(&bytes[..4], b"\x7fELF");
        let entry = u64::from_le_bytes(bytes[24..32].try_into().expect("ELF entry"));
        assert_eq!(entry, 0x400000 + 0x78 + 4);
        assert_eq!(&bytes[0x78..0x78 + 5], &[0x90, 0xc3, 0xcc, 0x90, 0xc3]);
        assert_eq!(&bytes[0x78 + 5..], &[1, 2, 3, 4]);

        let identity_a = [7, 3, 11];
        let identity_b = [7, 3, 12];
        let symbols = vec![
            GpuX86LinkSymbolRecord {
                object_index: 0,
                identity: identity_a,
                section: GpuX86ObjectSection::Text as u32,
                offset: 0,
                size: 1,
                flags: 0,
            },
            GpuX86LinkSymbolRecord {
                object_index: 1,
                identity: identity_a,
                section: GpuX86ObjectSection::Undefined as u32,
                offset: 0,
                size: 0,
                flags: 0,
            },
            GpuX86LinkSymbolRecord {
                object_index: 2,
                identity: identity_b,
                section: GpuX86ObjectSection::Undefined as u32,
                offset: 0,
                size: 0,
                flags: 0,
            },
        ];
        let (definitions, symbol_status) = generator
            .resolve_symbols_for_test(&gpu.device, &gpu.queue, &symbols)
            .expect("GPU symbol resolution");
        assert_eq!(definitions, vec![0, 0, u32::MAX]);
        assert_eq!(symbol_status, [1, 0, u32::MAX, 3]);

        let mut duplicates = symbols;
        duplicates[1].section = GpuX86ObjectSection::Text as u32;
        duplicates[1].size = 1;
        let (_, duplicate_status) = generator
            .resolve_symbols_for_test(&gpu.device, &gpu.queue, &duplicates)
            .expect("GPU duplicate symbol validation");
        assert_eq!(duplicate_status[0], 0);
        assert_eq!(duplicate_status[1], 1);

        let call_identity = identity(9, 0, 0);
        let mut dependency_symbol = symbol(&call_identity, GpuX86ObjectSection::Text);
        dependency_symbol.offset = 0;
        dependency_symbol.size = 6;
        let app = GpuX86RelocatableObject {
            version: GPU_X86_OBJECT_VERSION,
            library_id: 8,
            unit_id: 0,
            entry_offset: Some(0),
            text: vec![0xe8, 0, 0, 0, 0, 0xc3],
            rodata: Vec::new(),
            relocations: vec![GpuX86RelocationRecord {
                kind: GpuX86RelocationKind::CallRel32,
                site_section: GpuX86ObjectSection::Text,
                site_offset: 1,
                target_kind: GpuX86RelocationTargetKind::Symbol,
                target_index: 0,
                target_offset: 0,
                addend: -4,
            }],
            symbols: vec![symbol(&call_identity, GpuX86ObjectSection::Undefined)],
            identity_bytes: call_identity.clone(),
        };
        let dependency = GpuX86RelocatableObject {
            version: GPU_X86_OBJECT_VERSION,
            library_id: 9,
            unit_id: 0,
            entry_offset: None,
            text: vec![0xb8, 7, 0, 0, 0, 0xc3],
            rodata: Vec::new(),
            relocations: Vec::new(),
            symbols: vec![dependency_symbol],
            identity_bytes: call_identity,
        };
        let relocation_input =
            GpuX86LinkInput::for_executable(&[app, dependency]).expect("relocation input");
        let executable = generator
            .link_executable(&gpu.device, &gpu.queue, &relocation_input)
            .expect("complete GPU executable link");
        assert_eq!(&executable[..4], b"\x7fELF");
        assert_eq!(&executable[0x79..0x7d], &[1, 0, 0, 0]);

        let mut initial_output = vec![0u8; 0x78];
        initial_output.extend_from_slice(&relocation_input.text);
        let (relocated, relocation_status) = generator
            .relocate_for_test(
                &gpu.device,
                &gpu.queue,
                &relocation_input,
                &[[0, 0], [6, 0]],
                &[1, 1],
                &initial_output,
            )
            .expect("GPU relocation");
        assert_eq!(relocation_status, [1, 0, u32::MAX, 1]);
        assert_eq!(&relocated[0x79..0x7d], &[1, 0, 0, 0]);

        let (_, unresolved_status) = generator
            .relocate_for_test(
                &gpu.device,
                &gpu.queue,
                &relocation_input,
                &[[0, 0], [6, 0]],
                &[u32::MAX, 1],
                &initial_output,
            )
            .expect("GPU unresolved relocation");
        assert_eq!(unresolved_status[0], 0);
        assert_eq!(unresolved_status[1], 2);
    }
}
