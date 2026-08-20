use std::io::{Seek, SeekFrom, Write};

use anyhow::{Result, bail};

use super::{GpuX86LinkInput, paged::GpuX86PagedExecutablePlan};
use crate::{
    codegen::x86::{GpuX86Linker, support::u32_words_bytes},
    gpu::{
        buffers::LaniusBuffer,
        compiler_graph::{
            CompilerGraphBuilder,
            CompilerPhase,
            MaterializedCompilerGraph,
            ResourceClass,
            ResourceDesc,
            ResourceDomain,
        },
        operations::{ClearBufferOperation, ComputeOperation, CopyBufferOperation},
        resource_registry::ResourceMap,
        workspace::WorkspaceUsageClass,
    },
};

const RELOCATION_RECORD_BYTES_PER_COLUMN: usize = 16;
const RELOCATION_BATCH_BYTES_PER_COLUMN: usize = 4 * 1024 * 1024;

pub(crate) struct X86ExecutablePageGraph {
    output_capacity: usize,
    text_capacity: usize,
    rodata_capacity: usize,
    relocation_capacity: usize,
    batch_capacity: usize,
    materialized: MaterializedCompilerGraph,
}

impl X86ExecutablePageGraph {
    fn covers(
        &self,
        output: usize,
        text: usize,
        rodata: usize,
        relocations: usize,
        batches: usize,
    ) -> bool {
        self.output_capacity >= output
            && self.text_capacity >= text
            && self.rodata_capacity >= rodata
            && self.relocation_capacity >= relocations
            && self.batch_capacity >= batches
    }

    #[allow(clippy::too_many_arguments)]
    fn new(
        generator: &GpuX86Linker,
        device: &wgpu::Device,
        output_capacity: usize,
        text_capacity: usize,
        rodata_capacity: usize,
        relocation_capacity: usize,
        batch_capacity: usize,
    ) -> Result<Self> {
        let output_capacity = output_capacity.max(4).next_multiple_of(4);
        let text_capacity = text_capacity.max(4).next_multiple_of(4);
        let rodata_capacity = rodata_capacity.max(4).next_multiple_of(4);
        let relocation_capacity = relocation_capacity.max(1);
        let batch_capacity = batch_capacity.max(1);
        let mut graph = CompilerGraphBuilder::new();
        let mut add = |name: &'static str, class: ResourceClass, bytes: usize| -> Result<()> {
            graph
                .add_resource(ResourceDesc {
                    name,
                    domain: ResourceDomain::ArtifactBytes,
                    class,
                    bytes: bytes.max(4) as u64,
                    usage: WorkspaceUsageClass::Storage,
                })
                .map(|_| ())
                .map_err(anyhow::Error::msg)
        };
        add("x86_elf_layout", ResourceClass::External, 32)?;
        add("layout_status", ResourceClass::External, 16)?;
        add("link_text_input", ResourceClass::Input, text_capacity)?;
        add("link_rodata_input", ResourceClass::Input, rodata_capacity)?;
        add(
            "link_relocation_a",
            ResourceClass::External,
            relocation_capacity * RELOCATION_RECORD_BYTES_PER_COLUMN,
        )?;
        add(
            "link_relocation_b",
            ResourceClass::External,
            relocation_capacity * RELOCATION_RECORD_BYTES_PER_COLUMN,
        )?;
        add(
            "link_relocation_c",
            ResourceClass::External,
            relocation_capacity * RELOCATION_RECORD_BYTES_PER_COLUMN,
        )?;
        add("link_relocation_status", ResourceClass::External, 16)?;
        add("out_words", ResourceClass::Workspace, output_capacity)?;
        add("status", ResourceClass::Workspace, 16)?;
        add(
            "page_readback",
            ResourceClass::External,
            output_capacity + 32,
        )?;
        drop(add);

        let out_words = graph.resource_id("out_words").expect("x86 page output");
        let status = graph.resource_id("status").expect("x86 page status");
        let relocation_status = graph
            .resource_id("link_relocation_status")
            .expect("x86 page relocation status");
        let readback = graph
            .resource_id("page_readback")
            .expect("x86 page readback");
        graph
            .add_buffer_clear_pass(
                "codegen.x86.link.page.output.clear",
                CompilerPhase::Artifact,
                "out_words",
                out_words,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .add_buffer_clear_pass(
                "codegen.x86.link.page.status.clear",
                CompilerPhase::Artifact,
                "status",
                status,
            )
            .map_err(anyhow::Error::msg)?;
        for (name, pass) in [
            ("codegen.x86.link.page.elf_write", &generator.elf_write_pass),
            (
                "codegen.x86.link.page.copy_sections",
                &generator.link_copy_sections_pass,
            ),
            (
                "codegen.x86.link.page.relocate",
                &generator.link_relocate_pass,
            ),
        ] {
            graph
                .add_reflected_compute_pass_by_name(
                    name,
                    CompilerPhase::Artifact,
                    ResourceDomain::ArtifactBytes,
                    &pass.reflection,
                    &[],
                )
                .map_err(anyhow::Error::msg)?;
        }
        graph
            .repeat_pass_range(
                batch_capacity as u32,
                "codegen.x86.link.page.relocate",
                "codegen.x86.link.page.relocate",
            )
            .map_err(anyhow::Error::msg)?;
        for (name, source_binding, source) in [
            (
                "codegen.x86.link.page.output.readback",
                "out_words",
                out_words,
            ),
            ("codegen.x86.link.page.status.readback", "status", status),
            (
                "codegen.x86.link.page.relocation_status.readback",
                "link_relocation_status",
                relocation_status,
            ),
        ] {
            graph
                .add_buffer_copy_pass(
                    name,
                    CompilerPhase::Artifact,
                    source_binding,
                    source,
                    "page_readback",
                    readback,
                )
                .map_err(anyhow::Error::msg)?;
        }
        let graph = graph.build().map_err(anyhow::Error::msg)?;
        let materialized = MaterializedCompilerGraph::new_with_upstream_storage(
            device,
            "x86_link_executable_page",
            graph,
            &[],
        )
        .map_err(anyhow::Error::msg)?;
        Ok(Self {
            output_capacity,
            text_capacity,
            rodata_capacity,
            relocation_capacity,
            batch_capacity,
            materialized,
        })
    }
}

struct X86ResolvedLinkBuffers<'a> {
    object_bases: &'a [[u32; 2]],
    elf_layout: &'a LaniusBuffer<u32>,
    layout_status: &'a LaniusBuffer<u32>,
}

impl GpuX86Linker {
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
        let timing = std::env::var_os("LANIUS_X86_LINK_TIMING").is_some();
        let started = std::time::Instant::now();
        let resolved_relocations = self.resolve_symbol_relocations(device, queue, input)?;
        let symbols_resolved = started.elapsed();
        if crate::gpu::env::env_bool_truthy("LANIUS_OBJECT_ID_TRACE", false) {
            eprintln!("[x86_object_identity] resolved_relocations={resolved_relocations:?}");
        }
        let output_plan = GpuX86PagedExecutablePlan::new(
            input,
            device.limits().max_storage_buffer_binding_size as u64,
        )
        .map_err(anyhow::Error::msg)?;
        let output_planned = started.elapsed();
        let output_len = output_plan.output_len;
        let output_capacity = output_len.div_ceil(4).saturating_mul(4).max(4);
        let output_capacity_u32 = u32::try_from(output_capacity)
            .map_err(|_| anyhow::anyhow!("x86 linked output exceeds the 32-bit ELF model"))?;

        let object_layout =
            self.resolve_object_layout_chunks(device, queue, input, output_capacity_u32)?;
        let layout_resolved = started.elapsed();
        let result = self.emit_executable_pages(
            device,
            queue,
            input,
            &resolved_relocations,
            &output_plan,
            X86ResolvedLinkBuffers {
                object_bases: &object_layout.object_bases,
                elf_layout: &object_layout.elf_layout,
                layout_status: &object_layout.layout_status,
            },
            consume_page,
        );
        if timing {
            eprintln!(
                "x86_link_timing phase=total objects={} relocations={} pages={} output_bytes={} symbols_ms={:.3} plan_ms={:.3} layout_ms={:.3} pages_ms={:.3} total_ms={:.3}",
                input.objects.len(),
                resolved_relocations.len(),
                output_plan.pages.len(),
                output_plan.output_len,
                symbols_resolved.as_secs_f64() * 1000.0,
                (output_planned - symbols_resolved).as_secs_f64() * 1000.0,
                (layout_resolved - output_planned).as_secs_f64() * 1000.0,
                (started.elapsed() - layout_resolved).as_secs_f64() * 1000.0,
                started.elapsed().as_secs_f64() * 1000.0,
            );
        }
        result
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
        let timing = std::env::var_os("LANIUS_X86_LINK_TIMING").is_some();
        for (page_index, page) in plan.pages.iter().enumerate() {
            let started = std::time::Instant::now();
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
            let sources_read = started.elapsed();
            let text_input =
                self.reusable_input_bytes(device, queue, "codegen.x86.link.page.text", &text_bytes);
            let rodata_input = self.reusable_input_bytes(
                device,
                queue,
                "codegen.x86.link.page.rodata",
                &rodata_bytes,
            );
            let elf_params = self.reusable_uniform_u32(
                device,
                queue,
                "codegen.x86.link.page.elf_params",
                &[page.output_base, page.output_len, output_capacity_u32, 0],
            );
            let copy_params = self.reusable_uniform_u32(
                device,
                queue,
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
            let max_relocations_per_batch = max_relocation_batch_records(
                device.limits().max_storage_buffer_binding_size as usize,
            )?
            .min(page.relocation_indices.len().max(1));
            let relocation_a = self.reusable_storage_u32(
                device,
                "codegen.x86.link.page.relocation_a",
                max_relocations_per_batch * 4,
                wgpu::BufferUsages::COPY_DST,
            );
            let relocation_b = self.reusable_storage_u32(
                device,
                "codegen.x86.link.page.relocation_b",
                max_relocations_per_batch * 4,
                wgpu::BufferUsages::COPY_DST,
            );
            let relocation_c = self.reusable_storage_u32(
                device,
                "codegen.x86.link.page.relocation_c",
                max_relocations_per_batch * 4,
                wgpu::BufferUsages::COPY_DST,
            );
            let relocation_params = self.reusable_uniform_u32(
                device,
                queue,
                "codegen.x86.link.page.relocation_params",
                &[0; 8],
            );
            let relocation_status = self.reusable_storage_u32(
                device,
                "codegen.x86.link.page.relocation_status",
                4,
                wgpu::BufferUsages::COPY_SRC,
            );
            queue.write_buffer(
                &relocation_status.buffer,
                0,
                u32_words_bytes(&[1, 0, u32::MAX, page.relocation_indices.len() as u32]),
            );

            let relocation_batch_count = page
                .relocation_indices
                .len()
                .div_ceil(max_relocations_per_batch)
                .max(1);
            let mut graph_guard = self
                .executable_page_graph
                .lock()
                .expect("x86 executable-page graph cache poisoned");
            if !graph_guard.as_ref().is_some_and(|graph| {
                graph.covers(
                    page_capacity,
                    text_bytes.len(),
                    rodata_bytes.len(),
                    max_relocations_per_batch,
                    relocation_batch_count,
                )
            }) {
                *graph_guard = Some(X86ExecutablePageGraph::new(
                    self,
                    device,
                    page_capacity,
                    text_bytes.len(),
                    rodata_bytes.len(),
                    max_relocations_per_batch,
                    relocation_batch_count,
                )?);
            }
            let graph_state = graph_guard
                .as_ref()
                .expect("x86 executable-page graph installed");
            let graph = &graph_state.materialized;
            let output = graph.buffer::<u32>("out_words")?;
            let output_status = graph.buffer::<u32>("status")?;
            let readback = self.reusable_readback(
                device,
                "rb.codegen.x86.link.page",
                graph_state.output_capacity + 32,
            );
            let graph_bindings = graph.bindings()?;
            let mut resources = ResourceMap::new();
            resources.attach_graph(graph.graph(), graph.allocations());
            resources.register_graph_bindings(graph.graph(), &graph_bindings);
            resources.buffer("x86_elf_layout", resolved.elf_layout);
            resources.buffer("layout_status", resolved.layout_status);
            resources.buffer("link_text_input", &text_input);
            resources.buffer("link_rodata_input", &rodata_input);
            resources.buffer("link_relocation_a", &relocation_a);
            resources.buffer("link_relocation_b", &relocation_b);
            resources.buffer("link_relocation_c", &relocation_c);
            resources.buffer("link_relocation_status", &relocation_status);
            resources.buffer("page_readback", &readback);

            let output_clear = ClearBufferOperation::entire(
                graph,
                "codegen.x86.link.page.output.clear",
                "out_words",
                &output,
            )?;
            let status_clear = ClearBufferOperation::entire(
                graph,
                "codegen.x86.link.page.status.clear",
                "status",
                &output_status,
            )?;
            let mut elf_resources = resources.clone();
            elf_resources.buffer("gParams", &elf_params);
            let elf_write = ComputeOperation::direct(
                device,
                graph,
                &elf_resources,
                "codegen.x86.link.page.elf_write",
                &self.elf_write_pass,
                u32::try_from(graph_state.output_capacity / 4)
                    .map_err(|_| anyhow::anyhow!("x86 executable page capacity exceeds u32"))?,
            )?;
            let mut copy_resources = resources.clone();
            copy_resources.buffer("gCopy", &copy_params);
            let copy_sections = ComputeOperation::direct(
                device,
                graph,
                &copy_resources,
                "codegen.x86.link.page.copy_sections",
                &self.link_copy_sections_pass,
                u32::try_from(graph_state.text_capacity.max(graph_state.rodata_capacity))
                    .map_err(|_| anyhow::anyhow!("x86 section input capacity exceeds u32"))?,
            )?;
            let mut relocation_resources = resources.clone();
            relocation_resources.buffer("gReloc", &relocation_params);
            let relocate = ComputeOperation::direct(
                device,
                graph,
                &relocation_resources,
                "codegen.x86.link.page.relocate",
                &self.link_relocate_pass,
                u32::try_from(graph_state.relocation_capacity)
                    .map_err(|_| anyhow::anyhow!("x86 relocation capacity exceeds u32"))?,
            )?;
            let output_copy = CopyBufferOperation::new(
                graph,
                "codegen.x86.link.page.output.readback",
                "out_words",
                &output,
                0,
                "page_readback",
                &readback,
                0,
                page_capacity as u64,
            )?;
            let status_copy = CopyBufferOperation::new(
                graph,
                "codegen.x86.link.page.status.readback",
                "status",
                &output_status,
                0,
                "page_readback",
                &readback,
                page_capacity as u64,
                16,
            )?;
            let relocation_status_copy = CopyBufferOperation::new(
                graph,
                "codegen.x86.link.page.relocation_status.readback",
                "link_relocation_status",
                &relocation_status,
                0,
                "page_readback",
                &readback,
                (page_capacity + 16) as u64,
                16,
            )?;
            let resources_prepared = started.elapsed();
            let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("codegen.x86.link.page.encoder"),
            });
            output_clear.record(&mut encoder);
            status_clear.record(&mut encoder);
            elf_write.record_elements(&mut encoder, (page_capacity / 4) as u32)?;
            let copy_count = page.text_input.len().max(page.rodata_input.len()).max(1) as u32;
            copy_sections.record_elements(&mut encoder, copy_count)?;
            crate::gpu::passes_core::submit_with_progress(
                queue,
                "codegen.x86.link.page.initialize",
                encoder.finish(),
            );
            let initialized = started.elapsed();
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
                queue.write_buffer(&relocation_a.buffer, 0, u32_words_bytes(&a_words));
                queue.write_buffer(&relocation_b.buffer, 0, u32_words_bytes(&b_words));
                queue.write_buffer(&relocation_c.buffer, 0, u32_words_bytes(&c_words));
                queue.write_buffer(
                    &relocation_params.buffer,
                    0,
                    u32_words_bytes(&[
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
                relocate.record_elements(&mut encoder, indices.len() as u32)?;
                crate::gpu::passes_core::submit_with_progress(
                    queue,
                    "codegen.x86.link.page.relocation_batch",
                    encoder.finish(),
                );
            }
            let relocations_submitted = started.elapsed();
            let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("codegen.x86.link.page.readback.encoder"),
            });
            output_copy.record(&mut encoder);
            status_copy.record(&mut encoder);
            relocation_status_copy.record(&mut encoder);
            crate::gpu::passes_core::submit_with_progress(
                queue,
                "codegen.x86.link.page",
                encoder.finish(),
            );
            let readback_submitted = started.elapsed();
            let slice = readback.slice(..);
            crate::gpu::passes_core::wait_for_readback_map(
                device,
                &slice,
                "codegen.x86.link.page",
                std::time::Duration::from_secs(30),
            )?;
            let mapped_ready = started.elapsed();
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
            let consumed = started.elapsed();
            emitted_len += page.output_len as usize;
            drop(mapped);
            readback.unmap();
            if timing {
                eprintln!(
                    "x86_link_timing phase=page index={} output_bytes={} text_bytes={} rodata_bytes={} relocations={} source_read_ms={:.3} resources_ms={:.3} initialize_submit_ms={:.3} relocate_submit_ms={:.3} readback_submit_ms={:.3} gpu_wait_ms={:.3} output_write_ms={:.3} total_ms={:.3}",
                    page_index,
                    page.output_len,
                    page.text_input.len(),
                    page.rodata_input.len(),
                    page.relocation_indices.len(),
                    sources_read.as_secs_f64() * 1000.0,
                    (resources_prepared - sources_read).as_secs_f64() * 1000.0,
                    (initialized - resources_prepared).as_secs_f64() * 1000.0,
                    (relocations_submitted - initialized).as_secs_f64() * 1000.0,
                    (readback_submitted - relocations_submitted).as_secs_f64() * 1000.0,
                    (mapped_ready - readback_submitted).as_secs_f64() * 1000.0,
                    (consumed - mapped_ready).as_secs_f64() * 1000.0,
                    started.elapsed().as_secs_f64() * 1000.0,
                );
            }
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
        if crate::gpu::env::env_bool_truthy("LANIUS_OBJECT_ID_TRACE", false) {
            eprintln!(
                "[x86_object_identity] relocation index={index} site={} target={} kind={} target_kind={} addend={}",
                site_file,
                target_file,
                relocation.kind,
                relocation.target_kind,
                relocation.addend_lo,
            );
        }
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
