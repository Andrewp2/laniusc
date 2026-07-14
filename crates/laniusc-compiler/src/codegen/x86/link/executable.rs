use anyhow::{Result, bail};
use wgpu::util::DeviceExt;

use super::{GpuX86LinkInput, GpuX86LinkSymbolRecord};
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

const ELF_HEADER_AND_PROGRAM_HEADER_BYTES: usize = 0x78;
const SYMBOL_RADIX_STEPS: usize = 13;
const RADIX_BUCKETS: usize = 257;
const MAX_RADIX_BLOCKS: usize = 4096;

impl GpuX86CodeGenerator {
    /// Links validated object columns entirely on the GPU and reads back only
    /// the final executable image and compact status words.
    pub(crate) fn link_executable(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: &GpuX86LinkInput,
    ) -> Result<Vec<u8>> {
        let object_count = input.objects.len();
        let symbol_count = input.symbols.len();
        let relocation_count = input.relocations.len();
        let object_block_count = object_count.div_ceil(256).max(1);
        let symbol_block_count = symbol_count.div_ceil(256).max(1);
        if symbol_count != 0 && symbol_block_count > MAX_RADIX_BLOCKS {
            bail!(
                "x86 linker symbol page has {symbol_block_count} radix blocks; bounded pages support at most {MAX_RADIX_BLOCKS}"
            );
        }
        let output_len = ELF_HEADER_AND_PROGRAM_HEADER_BYTES
            .checked_add(input.text.len())
            .and_then(|len| len.checked_add(input.rodata.len()))
            .ok_or_else(|| anyhow::anyhow!("x86 linked output length overflows"))?;
        let output_capacity = output_len.div_ceil(4).saturating_mul(4).max(4);
        let output_capacity_u32 = u32::try_from(output_capacity)
            .map_err(|_| anyhow::anyhow!("x86 linked output exceeds the 32-bit ELF model"))?;

        let (object_section_words, object_entry_words) = object_words(input);
        let (symbol_identity_words, symbol_location_words) = symbol_words(&input.symbols);
        let (relocation_a_words, relocation_b_words, relocation_c_words) = relocation_words(input);
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
        let symbol_identities = storage_input_u32(
            device,
            "codegen.x86.link.symbol_identity_section",
            &symbol_identity_words,
        );
        let symbol_locations = storage_input_u32(
            device,
            "codegen.x86.link.symbol_location",
            &symbol_location_words,
        );
        let symbol_count_buffer = storage_input_u32(
            device,
            "codegen.x86.link.symbol_count",
            &[symbol_count as u32],
        );
        let relocation_a =
            storage_input_u32(device, "codegen.x86.link.relocation_a", &relocation_a_words);
        let relocation_b =
            storage_input_u32(device, "codegen.x86.link.relocation_b", &relocation_b_words);
        let relocation_c =
            storage_input_u32(device, "codegen.x86.link.relocation_c", &relocation_c_words);

        let section_local_prefix = storage_u32_rw(
            device,
            "codegen.x86.link.section_local_prefix",
            object_count * 2,
            wgpu::BufferUsages::empty(),
        );
        let section_block_sum = storage_u32_rw(
            device,
            "codegen.x86.link.section_block_sum",
            object_block_count * 2,
            wgpu::BufferUsages::empty(),
        );
        let section_block_prefix_a = storage_u32_rw(
            device,
            "codegen.x86.link.section_block_prefix_a",
            object_block_count * 2,
            wgpu::BufferUsages::empty(),
        );
        let section_block_prefix_b = storage_u32_rw(
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

        let symbol_order_a = storage_u32_rw(
            device,
            "codegen.x86.link.symbol_order_a",
            symbol_count,
            wgpu::BufferUsages::empty(),
        );
        let symbol_order_b = storage_u32_rw(
            device,
            "codegen.x86.link.symbol_order_b",
            symbol_count,
            wgpu::BufferUsages::empty(),
        );
        let symbol_histogram = storage_u32_rw(
            device,
            "codegen.x86.link.symbol_histogram",
            symbol_block_count * RADIX_BUCKETS,
            wgpu::BufferUsages::empty(),
        );
        let symbol_block_bucket_prefix = storage_u32_rw(
            device,
            "codegen.x86.link.symbol_block_bucket_prefix",
            symbol_block_count * RADIX_BUCKETS,
            wgpu::BufferUsages::empty(),
        );
        let symbol_bucket_total = storage_u32_rw(
            device,
            "codegen.x86.link.symbol_bucket_total",
            RADIX_BUCKETS,
            wgpu::BufferUsages::empty(),
        );
        let symbol_bucket_base = storage_u32_rw(
            device,
            "codegen.x86.link.symbol_bucket_base",
            RADIX_BUCKETS,
            wgpu::BufferUsages::empty(),
        );
        let symbol_definitions = storage_u32_rw(
            device,
            "codegen.x86.link.symbol_definition",
            symbol_count,
            wgpu::BufferUsages::empty(),
        );
        let symbol_status = storage_u32_copy(device, "codegen.x86.link.symbol_status", 4);
        let relocation_status = storage_u32_copy(device, "codegen.x86.link.relocation_status", 4);

        let layout_params = uniform_u32_words(
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
        let relocation_params = uniform_u32_words(
            device,
            "codegen.x86.link.relocation_params",
            &[
                object_count as u32,
                relocation_count as u32,
                symbol_count as u32,
                0,
            ],
        );

        let layout_local_group = reflected_bind_group(
            device,
            Some("codegen.x86.link.layout_scan_local.bind_group"),
            &self.link_layout_scan_local_pass,
            0,
            &[
                ("gLink", layout_params.buffer.as_entire_binding()),
                ("link_object_sections", object_sections.as_entire_binding()),
                (
                    "link_section_local_prefix",
                    section_local_prefix.buffer.as_entire_binding(),
                ),
                (
                    "link_section_block_sum",
                    section_block_sum.buffer.as_entire_binding(),
                ),
            ],
        )?;
        let layout_scan_steps = crate::gpu::scan::scan_step_values(object_block_count as u32);
        let mut layout_scan_params = Vec::with_capacity(layout_scan_steps.len());
        let mut layout_scan_groups = Vec::with_capacity(layout_scan_steps.len());
        for (step_i, step) in layout_scan_steps.iter().copied().enumerate() {
            layout_scan_params.push(uniform_u32_words(
                device,
                "codegen.x86.link.layout_scan_blocks.params",
                &[object_count as u32, object_block_count as u32, step, 0],
            ));
            let (prefix_in, prefix_out) = if step_i & 1 == 0 {
                (
                    &section_block_prefix_b.buffer,
                    &section_block_prefix_a.buffer,
                )
            } else {
                (
                    &section_block_prefix_a.buffer,
                    &section_block_prefix_b.buffer,
                )
            };
            layout_scan_groups.push(reflected_bind_group(
                device,
                Some("codegen.x86.link.layout_scan_blocks.bind_group"),
                &self.link_layout_scan_blocks_pass,
                0,
                &[
                    (
                        "gScan",
                        layout_scan_params
                            .last()
                            .unwrap()
                            .buffer
                            .as_entire_binding(),
                    ),
                    (
                        "link_section_block_sum",
                        section_block_sum.buffer.as_entire_binding(),
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
        let final_section_block_prefix = if (layout_scan_steps.len() - 1) & 1 == 0 {
            &section_block_prefix_a.buffer
        } else {
            &section_block_prefix_b.buffer
        };
        let layout_group = reflected_bind_group(
            device,
            Some("codegen.x86.link.layout.bind_group"),
            &self.link_layout_pass,
            0,
            &[
                ("gLink", layout_params.buffer.as_entire_binding()),
                ("link_object_sections", object_sections.as_entire_binding()),
                (
                    "link_object_entry_offset",
                    object_entries.as_entire_binding(),
                ),
                (
                    "link_section_local_prefix",
                    section_local_prefix.buffer.as_entire_binding(),
                ),
                (
                    "link_section_block_prefix",
                    final_section_block_prefix.as_entire_binding(),
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

        let mut symbol_params = Vec::with_capacity(SYMBOL_RADIX_STEPS);
        let mut symbol_histogram_groups = Vec::with_capacity(SYMBOL_RADIX_STEPS);
        let mut symbol_prefix_groups = Vec::with_capacity(SYMBOL_RADIX_STEPS);
        let mut symbol_base_groups = Vec::with_capacity(SYMBOL_RADIX_STEPS);
        let mut symbol_scatter_groups = Vec::with_capacity(SYMBOL_RADIX_STEPS);
        if symbol_count != 0 {
            for key_step in 0..SYMBOL_RADIX_STEPS as u32 {
                symbol_params.push(uniform_u32_words(
                    device,
                    "codegen.x86.link.symbol_radix.params",
                    &[symbol_count as u32, 0, symbol_block_count as u32, key_step],
                ));
                let (order_in, order_out) = if key_step & 1 == 0 {
                    (&symbol_order_a.buffer, &symbol_order_b.buffer)
                } else {
                    (&symbol_order_b.buffer, &symbol_order_a.buffer)
                };
                let param = symbol_params.last().unwrap();
                symbol_histogram_groups.push(reflected_bind_group(
                    device,
                    Some("codegen.x86.link.symbol_histogram.bind_group"),
                    &self.link_symbol_histogram_pass,
                    0,
                    &[
                        ("gParams", param.buffer.as_entire_binding()),
                        (
                            "link_symbol_identity_section",
                            symbol_identities.as_entire_binding(),
                        ),
                        ("link_symbol_order_in", order_in.as_entire_binding()),
                        (
                            "radix_block_histogram",
                            symbol_histogram.buffer.as_entire_binding(),
                        ),
                    ],
                )?);
                symbol_prefix_groups.push(reflected_bind_group(
                    device,
                    Some("codegen.x86.link.symbol_bucket_prefix.bind_group"),
                    &self.link_symbol_bucket_prefix_pass,
                    0,
                    &[
                        ("gParams", param.buffer.as_entire_binding()),
                        ("name_count_in", symbol_count_buffer.as_entire_binding()),
                        (
                            "radix_block_histogram",
                            symbol_histogram.buffer.as_entire_binding(),
                        ),
                        (
                            "radix_block_bucket_prefix",
                            symbol_block_bucket_prefix.buffer.as_entire_binding(),
                        ),
                        (
                            "radix_bucket_total",
                            symbol_bucket_total.buffer.as_entire_binding(),
                        ),
                    ],
                )?);
                symbol_base_groups.push(reflected_bind_group(
                    device,
                    Some("codegen.x86.link.symbol_bucket_bases.bind_group"),
                    &self.link_symbol_bucket_bases_pass,
                    0,
                    &[
                        ("gParams", param.buffer.as_entire_binding()),
                        (
                            "radix_bucket_total",
                            symbol_bucket_total.buffer.as_entire_binding(),
                        ),
                        (
                            "radix_bucket_base",
                            symbol_bucket_base.buffer.as_entire_binding(),
                        ),
                    ],
                )?);
                symbol_scatter_groups.push(reflected_bind_group(
                    device,
                    Some("codegen.x86.link.symbol_scatter.bind_group"),
                    &self.link_symbol_scatter_pass,
                    0,
                    &[
                        ("gParams", param.buffer.as_entire_binding()),
                        (
                            "link_symbol_identity_section",
                            symbol_identities.as_entire_binding(),
                        ),
                        ("link_symbol_order_in", order_in.as_entire_binding()),
                        (
                            "radix_bucket_base",
                            symbol_bucket_base.buffer.as_entire_binding(),
                        ),
                        (
                            "radix_block_bucket_prefix",
                            symbol_block_bucket_prefix.buffer.as_entire_binding(),
                        ),
                        ("link_symbol_order_out", order_out.as_entire_binding()),
                    ],
                )?);
            }
        }
        let symbol_seed_group = if symbol_count == 0 {
            None
        } else {
            Some(reflected_bind_group(
                device,
                Some("codegen.x86.link.symbol_seed.bind_group"),
                &self.link_symbol_seed_pass,
                0,
                &[
                    ("gParams", symbol_params[0].buffer.as_entire_binding()),
                    (
                        "link_symbol_order",
                        symbol_order_a.buffer.as_entire_binding(),
                    ),
                ],
            )?)
        };
        let symbol_resolve_group = if symbol_count == 0 {
            None
        } else {
            Some(reflected_bind_group(
                device,
                Some("codegen.x86.link.symbol_resolve.bind_group"),
                &self.link_symbol_resolve_pass,
                0,
                &[
                    ("gParams", symbol_params[0].buffer.as_entire_binding()),
                    (
                        "link_symbol_identity_section",
                        symbol_identities.as_entire_binding(),
                    ),
                    (
                        "link_symbol_order",
                        symbol_order_b.buffer.as_entire_binding(),
                    ),
                    (
                        "link_symbol_definition",
                        symbol_definitions.buffer.as_entire_binding(),
                    ),
                    (
                        "link_symbol_status",
                        symbol_status.buffer.as_entire_binding(),
                    ),
                ],
            )?)
        };
        let relocate_group = if relocation_count == 0 {
            None
        } else {
            Some(reflected_bind_group(
                device,
                Some("codegen.x86.link.relocate.bind_group"),
                &self.link_relocate_pass,
                0,
                &[
                    ("gReloc", relocation_params.buffer.as_entire_binding()),
                    ("link_relocation_a", relocation_a.as_entire_binding()),
                    ("link_relocation_b", relocation_b.as_entire_binding()),
                    ("link_relocation_c", relocation_c.as_entire_binding()),
                    (
                        "link_object_section_base",
                        object_bases.buffer.as_entire_binding(),
                    ),
                    (
                        "link_symbol_identity_section",
                        symbol_identities.as_entire_binding(),
                    ),
                    ("link_symbol_location", symbol_locations.as_entire_binding()),
                    (
                        "link_symbol_definition",
                        symbol_definitions.buffer.as_entire_binding(),
                    ),
                    (
                        "link_symbol_status",
                        symbol_status.buffer.as_entire_binding(),
                    ),
                    ("x86_elf_layout", elf_layout.buffer.as_entire_binding()),
                    ("out_words", output.buffer.as_entire_binding()),
                    (
                        "link_relocation_status",
                        relocation_status.buffer.as_entire_binding(),
                    ),
                ],
            )?)
        };

        queue.write_buffer(
            &symbol_status.buffer,
            0,
            &u32_words_bytes(&[1, 0, u32::MAX, symbol_count as u32]),
        );
        queue.write_buffer(
            &relocation_status.buffer,
            0,
            &u32_words_bytes(&[1, 0, u32::MAX, relocation_count as u32]),
        );
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.x86.link.executable.encoder"),
        });
        encoder.clear_buffer(&output.buffer, 0, None);
        encoder.clear_buffer(&output_status.buffer, 0, None);
        dispatch_compute_pass(
            &mut encoder,
            "link.layout_scan_local",
            "codegen.x86.link.layout_scan_local",
            &self.link_layout_scan_local_pass,
            &layout_local_group,
            workgroup_grid_1d(object_block_count as u32),
        );
        for group in &layout_scan_groups {
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
        let copy_count = input.text.len().max(input.rodata.len()).max(1) as u32;
        dispatch_compute_pass(
            &mut encoder,
            "link.copy_sections",
            "codegen.x86.link.copy_sections",
            &self.link_copy_sections_pass,
            &copy_group,
            workgroup_grid_1d(copy_count.div_ceil(256)),
        );
        if let (Some(seed_group), Some(resolve_group)) = (&symbol_seed_group, &symbol_resolve_group)
        {
            dispatch_compute_pass(
                &mut encoder,
                "link.symbol_seed",
                "codegen.x86.link.symbol_seed",
                &self.link_symbol_seed_pass,
                seed_group,
                workgroup_grid_1d((symbol_count as u32).div_ceil(256)),
            );
            for step in 0..SYMBOL_RADIX_STEPS {
                dispatch_compute_pass(
                    &mut encoder,
                    "link.symbol_histogram",
                    "codegen.x86.link.symbol_histogram",
                    &self.link_symbol_histogram_pass,
                    &symbol_histogram_groups[step],
                    workgroup_grid_1d(symbol_block_count as u32),
                );
                dispatch_compute_pass(
                    &mut encoder,
                    "link.symbol_bucket_prefix",
                    "codegen.x86.link.symbol_bucket_prefix",
                    &self.link_symbol_bucket_prefix_pass,
                    &symbol_prefix_groups[step],
                    (RADIX_BUCKETS as u32, 1),
                );
                dispatch_compute_pass(
                    &mut encoder,
                    "link.symbol_bucket_bases",
                    "codegen.x86.link.symbol_bucket_bases",
                    &self.link_symbol_bucket_bases_pass,
                    &symbol_base_groups[step],
                    (1, 1),
                );
                dispatch_compute_pass(
                    &mut encoder,
                    "link.symbol_scatter",
                    "codegen.x86.link.symbol_scatter",
                    &self.link_symbol_scatter_pass,
                    &symbol_scatter_groups[step],
                    workgroup_grid_1d(symbol_block_count as u32),
                );
            }
            dispatch_compute_pass(
                &mut encoder,
                "link.symbol_resolve",
                "codegen.x86.link.symbol_resolve",
                &self.link_symbol_resolve_pass,
                resolve_group,
                workgroup_grid_1d((symbol_count as u32).div_ceil(256)),
            );
        }
        if let Some(group) = &relocate_group {
            dispatch_compute_pass(
                &mut encoder,
                "link.relocate",
                "codegen.x86.link.relocate",
                &self.link_relocate_pass,
                group,
                workgroup_grid_1d((relocation_count as u32).div_ceil(256)),
            );
        }

        let readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("rb.codegen.x86.link.executable"),
            size: (output_capacity + 48) as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&output.buffer, 0, &readback, 0, output_capacity as u64);
        for (index, status) in [
            &output_status.buffer,
            &symbol_status.buffer,
            &relocation_status.buffer,
        ]
        .into_iter()
        .enumerate()
        {
            encoder.copy_buffer_to_buffer(
                status,
                0,
                &readback,
                (output_capacity + index * 16) as u64,
                16,
            );
        }
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.x86.link.executable",
            encoder.finish(),
        );
        let slice = readback.slice(..);
        crate::gpu::passes_core::wait_for_readback_map(
            device,
            &slice,
            "codegen.x86.link.executable",
            std::time::Duration::from_secs(30),
        )?;
        let result = {
            let mapped = slice.get_mapped_range();
            let output_status = crate::gpu::readback::read_u32_words::<4>(
                &mapped[output_capacity..output_capacity + 16],
                "x86 linked output status",
            )?;
            let symbol_status = crate::gpu::readback::read_u32_words::<4>(
                &mapped[output_capacity + 16..output_capacity + 32],
                "x86 linked symbol status",
            )?;
            let relocation_status = crate::gpu::readback::read_u32_words::<4>(
                &mapped[output_capacity + 32..output_capacity + 48],
                "x86 linked relocation status",
            )?;
            if output_status != [output_len as u32, 1, 0, u32::MAX] {
                Err(anyhow::anyhow!(
                    "x86 GPU linker output failed with status {output_status:?}"
                ))
            } else if symbol_status[0] != 1 || symbol_status[1] != 0 {
                Err(anyhow::anyhow!(
                    "x86 GPU linker symbol resolution failed with status {symbol_status:?}"
                ))
            } else if relocation_status[0] != 1 || relocation_status[1] != 0 {
                Err(anyhow::anyhow!(
                    "x86 GPU linker relocation failed with status {relocation_status:?}"
                ))
            } else {
                Ok(mapped[..output_len].to_vec())
            }
        };
        readback.unmap();
        result
    }
}

fn object_words(input: &GpuX86LinkInput) -> (Vec<u32>, Vec<u32>) {
    let mut sections = Vec::with_capacity(input.objects.len() * 4);
    let mut entries = Vec::with_capacity(input.objects.len());
    for object in &input.objects {
        sections.extend_from_slice(&[
            object.text_input_start,
            object.text_len,
            object.rodata_input_start,
            object.rodata_len,
        ]);
        entries.push(object.entry_offset);
    }
    (sections, entries)
}

fn symbol_words(symbols: &[GpuX86LinkSymbolRecord]) -> (Vec<u32>, Vec<u32>) {
    let mut identities = Vec::with_capacity(symbols.len() * 4);
    let mut locations = Vec::with_capacity(symbols.len() * 4);
    for symbol in symbols {
        identities.extend_from_slice(&[
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
    (identities, locations)
}

fn relocation_words(input: &GpuX86LinkInput) -> (Vec<u32>, Vec<u32>, Vec<u32>) {
    let mut a = Vec::with_capacity(input.relocations.len() * 4);
    let mut b = Vec::with_capacity(input.relocations.len() * 4);
    let mut c = Vec::with_capacity(input.relocations.len() * 4);
    for relocation in &input.relocations {
        a.extend_from_slice(&[
            relocation.object_index,
            relocation.kind,
            relocation.site_section,
            relocation.site_offset,
        ]);
        b.extend_from_slice(&[
            relocation.target_kind,
            relocation.target_index,
            relocation.target_offset,
            relocation.addend_lo,
        ]);
        c.extend_from_slice(&[relocation.addend_hi, 0, 0, 0]);
    }
    (a, b, c)
}

fn storage_input_u32(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
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
