use std::io::{Seek, SeekFrom, Write};

use anyhow::{Result, anyhow};

use super::{GpuWasmLinkInput, paged::GpuWasmPagedExecutablePlan};
use crate::{
    codegen::wasm::GpuWasmLinker,
    gpu::{
        buffers::LaniusBuffer,
        compiler_graph::{
            AccessMode,
            CompilerGraphBuilder,
            CompilerPhase,
            MaterializedCompilerGraph,
            ReflectedResourceBinding,
            ResourceClass,
            ResourceDesc,
            ResourceDomain,
        },
        operations::{ComputeOperation, CopyBufferOperation},
        resource_registry::ResourceMap,
        workspace::WorkspaceUsageClass,
    },
};

pub(crate) struct WasmExecutablePageGraph {
    output_capacity: usize,
    type_capacity: usize,
    body_capacity: usize,
    data_capacity: usize,
    relocation_capacity: usize,
    batch_capacity: usize,
    materialized: MaterializedCompilerGraph,
}

impl WasmExecutablePageGraph {
    fn covers(
        &self,
        output: usize,
        types: usize,
        bodies: usize,
        data: usize,
        relocations: usize,
        batches: usize,
    ) -> bool {
        self.output_capacity >= output
            && self.type_capacity >= types
            && self.body_capacity >= bodies
            && self.data_capacity >= data
            && self.relocation_capacity >= relocations
            && self.batch_capacity >= batches
    }

    #[allow(clippy::too_many_arguments)]
    fn new(
        generator: &GpuWasmLinker,
        device: &wgpu::Device,
        output_capacity: usize,
        type_capacity: usize,
        body_capacity: usize,
        data_capacity: usize,
        relocation_capacity: usize,
        batch_capacity: usize,
    ) -> Result<Self> {
        let output_capacity = output_capacity.max(4).next_multiple_of(4);
        let type_capacity = type_capacity.max(4).next_multiple_of(4);
        let body_capacity = body_capacity.max(4).next_multiple_of(4);
        let data_capacity = data_capacity.max(4).next_multiple_of(4);
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
        add("link_type_bytes", ResourceClass::Input, type_capacity)?;
        add("link_body_bytes", ResourceClass::Input, body_capacity)?;
        add("link_data_bytes", ResourceClass::Input, data_capacity)?;
        add("link_symbol", ResourceClass::Input, 4)?;
        add("link_hash_table", ResourceClass::External, 4)?;
        add("link_symbol_definition", ResourceClass::External, 4)?;
        add("link_status", ResourceClass::External, 16)?;
        add(
            "link_relocation",
            ResourceClass::External,
            relocation_capacity * 32,
        )?;
        add("out_words", ResourceClass::Workspace, output_capacity)?;
        add(
            "link_output_readback",
            ResourceClass::External,
            output_capacity,
        )?;
        add("link_status_readback", ResourceClass::External, 16)?;
        drop(add);

        let resource = |name: &str| {
            graph
                .resource_id(name)
                .unwrap_or_else(|| panic!("Wasm executable graph resource `{name}`"))
        };
        let output = resource("out_words");
        let output_readback = resource("link_output_readback");
        let status = resource("link_status");
        let status_readback = resource("link_status_readback");
        graph
            .add_reflected_compute_pass_by_name(
                "codegen.wasm.link.page.module",
                CompilerPhase::Artifact,
                ResourceDomain::ArtifactBytes,
                &generator.link_module_pass.reflection,
                &[ReflectedResourceBinding {
                    binding: "out_words",
                    resource: output,
                    mode: Some(AccessMode::Write),
                }],
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .add_reflected_compute_pass_by_name(
                "codegen.wasm.link.page.relocate",
                CompilerPhase::Artifact,
                ResourceDomain::ArtifactBytes,
                &generator.link_relocate_pass.reflection,
                &[],
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .repeat_pass_range(
                batch_capacity as u32,
                "codegen.wasm.link.page.relocate",
                "codegen.wasm.link.page.relocate",
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .add_buffer_copy_pass(
                "codegen.wasm.link.page.output.readback",
                CompilerPhase::Artifact,
                "out_words",
                output,
                "link_output_readback",
                output_readback,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .add_buffer_copy_pass(
                "codegen.wasm.link.page.status.readback",
                CompilerPhase::Artifact,
                "link_status",
                status,
                "link_status_readback",
                status_readback,
            )
            .map_err(anyhow::Error::msg)?;
        let graph = graph.build().map_err(anyhow::Error::msg)?;
        let materialized = MaterializedCompilerGraph::new_with_upstream_storage(
            device,
            "wasm_link_executable_page",
            graph,
            &[],
        )
        .map_err(anyhow::Error::msg)?;
        Ok(Self {
            output_capacity,
            type_capacity,
            body_capacity,
            data_capacity,
            relocation_capacity,
            batch_capacity,
            materialized,
        })
    }
}

impl GpuWasmLinker {
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
            self,
            device,
            queue,
            "codegen.wasm.link.symbols",
            &[],
            wgpu::BufferUsages::STORAGE,
        );
        let hash_table = input_u32(
            self,
            device,
            queue,
            "codegen.wasm.link.hash_table",
            &[u32::MAX],
            wgpu::BufferUsages::STORAGE,
        );
        let definitions = input_u32(
            self,
            device,
            queue,
            "codegen.wasm.link.definitions",
            &[u32::MAX],
            wgpu::BufferUsages::STORAGE,
        );
        let status = input_u32(
            self,
            device,
            queue,
            "codegen.wasm.link.status",
            &[1, 0, u32::MAX, 0],
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
        );

        let status_readback = self.job_buffers.binding_capacity::<u8>(
            device,
            "rb.codegen.wasm.link.status",
            16,
            wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        );
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
                page.data_input.start as u32,
            )?;
            let params = input_u32(
                self,
                device,
                queue,
                "codegen.wasm.link.page.params",
                &params_words,
                wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            );
            let type_page = input
                .read_type_range(page.type_input.clone())
                .map_err(anyhow::Error::msg)?;
            let types = input_bytes(
                self,
                device,
                queue,
                "codegen.wasm.link.page.types",
                &type_page,
            );
            let body_page = input
                .read_body_range(page.body_input.clone())
                .map_err(anyhow::Error::msg)?;
            let bodies = input_bytes(
                self,
                device,
                queue,
                "codegen.wasm.link.page.bodies",
                &body_page,
            );
            let data_page = input
                .read_data_range(page.data_input.clone())
                .map_err(anyhow::Error::msg)?;
            let data = input_bytes(
                self,
                device,
                queue,
                "codegen.wasm.link.page.data",
                &data_page,
            );
            let relocations = rw_u32(
                self,
                device,
                "codegen.wasm.link.page.relocations",
                relocation_buffer_records.saturating_mul(8),
                wgpu::BufferUsages::empty(),
            );
            let output_words = (page.output_len as usize).div_ceil(4);
            let output_bytes = output_words * 4;
            let batch_count = relocation_batches.len().max(1);
            let mut graph_guard = self
                .executable_page_graph
                .lock()
                .expect("Wasm executable-page graph cache poisoned");
            if !graph_guard.as_ref().is_some_and(|graph| {
                graph.covers(
                    output_bytes,
                    type_page.len(),
                    body_page.len(),
                    data_page.len(),
                    relocation_buffer_records,
                    batch_count,
                )
            }) {
                *graph_guard = Some(WasmExecutablePageGraph::new(
                    self,
                    device,
                    output_bytes,
                    type_page.len(),
                    body_page.len(),
                    data_page.len(),
                    relocation_buffer_records,
                    batch_count,
                )?);
            }
            let graph_state = graph_guard
                .as_ref()
                .expect("Wasm executable-page graph installed");
            let graph = &graph_state.materialized;
            let output = graph.buffer::<u32>("out_words")?;
            let output_readback = self.job_buffers.binding_capacity::<u8>(
                device,
                "rb.codegen.wasm.link.page.output",
                graph_state.output_capacity,
                wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            );
            let graph_bindings = graph.bindings()?;
            let mut resources = ResourceMap::new();
            resources.attach_graph(graph.graph(), graph.allocations());
            resources.register_graph_bindings(graph.graph(), &graph_bindings);
            resources.buffer("gLink", &params);
            resources.buffer("link_type_bytes", &types);
            resources.buffer("link_body_bytes", &bodies);
            resources.buffer("link_data_bytes", &data);
            resources.buffer("link_symbol", &symbols);
            resources.buffer("link_hash_table", &hash_table);
            resources.buffer("link_symbol_definition", &definitions);
            resources.buffer("link_status", &status);
            resources.buffer("link_relocation", &relocations);
            resources.buffer("link_output_readback", &output_readback);
            resources.buffer("link_status_readback", &status_readback);
            let module = ComputeOperation::direct(
                device,
                graph,
                &resources,
                "codegen.wasm.link.page.module",
                &self.link_module_pass,
                u32::try_from(graph_state.output_capacity / 4)
                    .map_err(|_| anyhow!("Wasm output page capacity exceeds u32"))?,
            )?;
            let relocate = ComputeOperation::direct(
                device,
                graph,
                &resources,
                "codegen.wasm.link.page.relocate",
                &self.link_relocate_pass,
                u32::try_from(graph_state.relocation_capacity)
                    .map_err(|_| anyhow!("Wasm relocation capacity exceeds u32"))?,
            )?;
            let output_copy = CopyBufferOperation::new(
                graph,
                "codegen.wasm.link.page.output.readback",
                "out_words",
                &output,
                0,
                "link_output_readback",
                &output_readback,
                0,
                output_bytes as u64,
            )?;
            let status_copy = CopyBufferOperation::new(
                graph,
                "codegen.wasm.link.page.status.readback",
                "link_status",
                &status,
                0,
                "link_status_readback",
                &status_readback,
                0,
                16,
            )?;
            for batch_index in 0..batch_count {
                let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                    label: Some("codegen.wasm.link.page.encoder"),
                });
                if batch_index == 0 {
                    module.record_elements(&mut encoder, output_words as u32)?;
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
                        page.data_input.start as u32,
                    )?;
                    let relocation_words = page_relocation_words(&resolved_relocations, batch);
                    queue.write_buffer(&params, 0, bytemuck_words(&batch_params));
                    queue.write_buffer(&relocations, 0, bytemuck_words(&relocation_words));
                    relocate.record_elements(&mut encoder, batch.len() as u32)?;
                }
                if batch_index + 1 == batch_count {
                    output_copy.record(&mut encoder);
                    status_copy.record(&mut encoder);
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
    data_input_base: u32,
) -> Result<[u32; 14]> {
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
        u32::try_from(input.data_byte_len()).map_err(|_| anyhow!("Wasm data bytes exceed u32"))?,
        data_input_base,
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

pub(super) fn input_u32(
    linker: &GpuWasmLinker,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    label: &str,
    words: &[u32],
    usage: wgpu::BufferUsages,
) -> LaniusBuffer<u32> {
    let fallback = [0u32];
    let words = if words.is_empty() {
        &fallback[..]
    } else {
        words
    };
    let bytes = bytemuck_words(words);
    let buffer = linker.job_buffers.binding_capacity::<u32>(
        device,
        label,
        bytes.len(),
        usage | wgpu::BufferUsages::COPY_DST,
    );
    buffer.write(queue, 0, bytes);
    buffer
}
fn input_bytes(
    linker: &GpuWasmLinker,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    label: &str,
    bytes: &[u8],
) -> LaniusBuffer<u8> {
    let mut data = bytes.to_vec();
    data.resize(data.len().div_ceil(4).max(1) * 4, 0);
    let buffer = linker.job_buffers.binding_capacity::<u8>(
        device,
        label,
        data.len(),
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
    );
    buffer.write(queue, 0, &data);
    buffer
}
pub(super) fn rw_u32(
    linker: &GpuWasmLinker,
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra: wgpu::BufferUsages,
) -> LaniusBuffer<u32> {
    linker.job_buffers.binding_capacity::<u32>(
        device,
        label,
        count.max(1) * 4,
        wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | extra,
    )
}
pub(super) fn bytemuck_words(words: &[u32]) -> &[u8] {
    unsafe { std::slice::from_raw_parts(words.as_ptr().cast(), words.len() * 4) }
}
