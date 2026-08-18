use anyhow::{Result, anyhow};

use super::{
    GpuWasmLinkInput,
    GpuWasmLinkRelocationRecord,
    GpuWasmRelocationTargetKind,
    executable::{bytemuck_words, input_u32, link_params_words, rw_u32},
    symbol_partitions::GpuWasmSymbolPartitionPlan,
};
use crate::{
    codegen::wasm::GpuWasmLinker,
    gpu::{
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

pub(crate) struct WasmSymbolPartitionGraph {
    definition_capacity: usize,
    relocation_capacity: usize,
    hash_capacity: usize,
    batch_capacity: usize,
    materialized: MaterializedCompilerGraph,
}

impl WasmSymbolPartitionGraph {
    fn covers(&self, definitions: usize, relocations: usize, hash: usize, batches: usize) -> bool {
        self.definition_capacity >= definitions
            && self.relocation_capacity >= relocations
            && self.hash_capacity >= hash
            && self.batch_capacity >= batches
    }

    fn new(
        generator: &GpuWasmLinker,
        device: &wgpu::Device,
        definition_capacity: usize,
        relocation_capacity: usize,
        hash_capacity: usize,
        batch_capacity: usize,
    ) -> Result<Self> {
        let definition_capacity = definition_capacity.max(1);
        let relocation_capacity = relocation_capacity.max(1);
        let hash_capacity = hash_capacity.max(1);
        let batch_capacity = batch_capacity.max(1);
        let mut graph = CompilerGraphBuilder::new();
        let mut add = |name: &'static str, class: ResourceClass, bytes: usize| -> Result<()> {
            graph
                .add_resource(ResourceDesc {
                    name,
                    domain: ResourceDomain::Declarations,
                    class,
                    bytes: bytes.max(4) as u64,
                    usage: WorkspaceUsageClass::Storage,
                })
                .map(|_| ())
                .map_err(anyhow::Error::msg)
        };
        add(
            "link_symbol",
            ResourceClass::Input,
            definition_capacity * 16,
        )?;
        add(
            "link_hash_table",
            ResourceClass::Workspace,
            hash_capacity * 4,
        )?;
        add(
            "link_symbol_definition",
            ResourceClass::Workspace,
            definition_capacity * 4,
        )?;
        add("link_status", ResourceClass::Workspace, 16)?;
        add(
            "link_relocation",
            ResourceClass::External,
            relocation_capacity * 32,
        )?;
        add(
            "link_resolved_target",
            ResourceClass::Workspace,
            relocation_capacity * 4,
        )?;
        add(
            "link_resolved_target_readback",
            ResourceClass::External,
            relocation_capacity * 4,
        )?;
        add("link_status_readback", ResourceClass::External, 16)?;
        drop(add);

        let resource = |name: &str| {
            graph
                .resource_id(name)
                .unwrap_or_else(|| panic!("Wasm symbol graph resource `{name}`"))
        };
        let hash_table = resource("link_hash_table");
        let definitions = resource("link_symbol_definition");
        let status = resource("link_status");
        let resolved_target = resource("link_resolved_target");
        let target_readback = resource("link_resolved_target_readback");
        let status_readback = resource("link_status_readback");
        graph
            .add_reflected_compute_pass_by_name(
                "codegen.wasm.link.resolve.clear",
                CompilerPhase::Artifact,
                ResourceDomain::Declarations,
                &generator.link_symbol_clear_pass.reflection,
                &[
                    ReflectedResourceBinding {
                        binding: "link_hash_table",
                        resource: hash_table,
                        mode: Some(AccessMode::Write),
                    },
                    ReflectedResourceBinding {
                        binding: "link_symbol_definition",
                        resource: definitions,
                        mode: Some(AccessMode::Write),
                    },
                    ReflectedResourceBinding {
                        binding: "link_status",
                        resource: status,
                        mode: Some(AccessMode::Write),
                    },
                ],
            )
            .map_err(anyhow::Error::msg)?;
        for (name, pass, overrides) in [
            (
                "codegen.wasm.link.resolve.insert",
                &generator.link_symbol_insert_pass,
                Vec::new(),
            ),
            (
                "codegen.wasm.link.resolve.define",
                &generator.link_symbol_define_pass,
                Vec::new(),
            ),
            (
                "codegen.wasm.link.resolve",
                &generator.link_resolve_pass,
                vec![ReflectedResourceBinding {
                    binding: "link_resolved_target",
                    resource: resolved_target,
                    mode: Some(AccessMode::Write),
                }],
            ),
        ] {
            graph
                .add_reflected_compute_pass_by_name(
                    name,
                    CompilerPhase::Artifact,
                    ResourceDomain::Declarations,
                    &pass.reflection,
                    &overrides,
                )
                .map_err(anyhow::Error::msg)?;
        }
        graph
            .repeat_pass_range(
                batch_capacity as u32,
                "codegen.wasm.link.resolve",
                "codegen.wasm.link.resolve",
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .add_buffer_copy_pass(
                "codegen.wasm.link.resolve.targets.readback",
                CompilerPhase::Artifact,
                "link_resolved_target",
                resolved_target,
                "link_resolved_target_readback",
                target_readback,
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .add_buffer_copy_pass(
                "codegen.wasm.link.resolve.status.readback",
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
            "wasm_link_symbol_partition",
            graph,
            &[],
        )
        .map_err(anyhow::Error::msg)?;
        Ok(Self {
            definition_capacity,
            relocation_capacity,
            hash_capacity,
            batch_capacity,
            materialized,
        })
    }
}

impl GpuWasmLinker {
    pub(super) fn resolve_symbol_relocations(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: &GpuWasmLinkInput,
    ) -> Result<Vec<GpuWasmLinkRelocationRecord>> {
        let binding_limit = device.limits().max_storage_buffer_binding_size as usize;
        let max_definitions = binding_limit / 16;
        let max_relocations = binding_limit / 32;
        if max_definitions < 2 || max_relocations == 0 {
            return Err(anyhow!(
                "Wasm GPU binding limit {binding_limit} is too small for symbol resolution"
            ));
        }
        let plan =
            GpuWasmSymbolPartitionPlan::new(input, max_definitions).map_err(anyhow::Error::msg)?;
        let mut resolved = input.relocations.clone();

        for partition in &plan.partitions {
            if partition.definition_indices.is_empty() && partition.relocation_indices.is_empty() {
                continue;
            }
            resolve_partition(
                self,
                device,
                queue,
                input,
                partition,
                max_relocations,
                &mut resolved,
            )?;
        }
        if let Some((index, _)) = resolved
            .iter()
            .enumerate()
            .find(|(_, relocation)| relocation.target_kind == GpuWasmRelocationTargetKind::Symbol)
        {
            return Err(anyhow!(
                "Wasm symbol partition plan did not resolve relocation {index}"
            ));
        }
        Ok(resolved)
    }
}

fn resolve_partition(
    generator: &GpuWasmLinker,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    input: &GpuWasmLinkInput,
    partition: &super::symbol_partitions::GpuWasmSymbolPartition,
    max_relocations: usize,
    resolved: &mut [GpuWasmLinkRelocationRecord],
) -> Result<()> {
    let definition_count = partition.definition_indices.len();
    let hash_capacity = definition_count
        .saturating_mul(2)
        .checked_next_power_of_two()
        .ok_or_else(|| anyhow!("Wasm partition definition hash capacity overflows"))?
        .max(1);
    let hash_capacity_u32 = u32::try_from(hash_capacity)
        .map_err(|_| anyhow!("Wasm partition definition hash capacity exceeds u32"))?;
    let mut symbol_words = Vec::with_capacity(definition_count * 4);
    for &definition_index in &partition.definition_indices {
        let symbol = input
            .symbols
            .get(definition_index)
            .ok_or_else(|| anyhow!("Wasm symbol partition definition index is invalid"))?;
        symbol_words.extend_from_slice(&[
            symbol.identity[0],
            symbol.identity[1],
            symbol.identity[2],
            symbol.function_index,
        ]);
    }
    let first_batch_len = partition.relocation_indices.len().min(max_relocations);
    let params_words = partition_params_words(
        input,
        definition_count,
        first_batch_len,
        hash_capacity_u32,
        0,
        0,
        0,
        0,
        0,
        0,
    )?;
    let params = input_u32(
        generator,
        device,
        queue,
        "codegen.wasm.link.resolve.params",
        &params_words,
        wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
    );
    let symbols = input_u32(
        generator,
        device,
        queue,
        "codegen.wasm.link.resolve.symbols",
        &symbol_words,
        wgpu::BufferUsages::STORAGE,
    );
    let relocation_capacity = first_batch_len.max(1);
    let batches = partition
        .relocation_indices
        .chunks(max_relocations)
        .collect::<Vec<_>>();
    let submission_count = batches.len().max(1);
    let mut graph_guard = generator
        .symbol_partition_graph
        .lock()
        .expect("Wasm symbol-partition graph cache poisoned");
    if !graph_guard.as_ref().is_some_and(|graph| {
        graph.covers(
            definition_count,
            relocation_capacity,
            hash_capacity,
            submission_count,
        )
    }) {
        *graph_guard = Some(WasmSymbolPartitionGraph::new(
            generator,
            device,
            definition_count,
            relocation_capacity,
            hash_capacity,
            submission_count,
        )?);
    }
    let graph_state = graph_guard
        .as_ref()
        .expect("Wasm symbol-partition graph installed");
    let graph = &graph_state.materialized;
    let status = graph.buffer::<u32>("link_status")?;
    let resolved_targets = graph.buffer::<u32>("link_resolved_target")?;
    let relocations = rw_u32(
        generator,
        device,
        "codegen.wasm.link.resolve.relocations",
        graph_state.relocation_capacity * 8,
        wgpu::BufferUsages::empty(),
    );
    let status_readback = generator.job_buffers.binding_capacity::<u8>(
        device,
        "rb.codegen.wasm.link.resolve.status",
        16,
        wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
    );
    let targets_readback = generator.job_buffers.binding_capacity::<u8>(
        device,
        "rb.codegen.wasm.link.resolve.targets",
        graph_state.relocation_capacity * 4,
        wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
    );
    let graph_bindings = graph.bindings()?;
    let mut resources = ResourceMap::new();
    resources.attach_graph(graph.graph(), graph.allocations());
    resources.register_graph_bindings(graph.graph(), &graph_bindings);
    resources.buffer("gLink", &params);
    resources.buffer("link_symbol", &symbols);
    resources.buffer("link_relocation", &relocations);
    resources.buffer("link_resolved_target_readback", &targets_readback);
    resources.buffer("link_status_readback", &status_readback);
    let clear = ComputeOperation::direct(
        device,
        graph,
        &resources,
        "codegen.wasm.link.resolve.clear",
        &generator.link_symbol_clear_pass,
        u32::try_from(
            graph_state
                .hash_capacity
                .max(graph_state.definition_capacity),
        )
        .map_err(|_| anyhow!("Wasm symbol clear capacity exceeds u32"))?,
    )?;
    let insert = ComputeOperation::direct(
        device,
        graph,
        &resources,
        "codegen.wasm.link.resolve.insert",
        &generator.link_symbol_insert_pass,
        u32::try_from(graph_state.definition_capacity)
            .map_err(|_| anyhow!("Wasm symbol capacity exceeds u32"))?,
    )?;
    let define = ComputeOperation::direct(
        device,
        graph,
        &resources,
        "codegen.wasm.link.resolve.define",
        &generator.link_symbol_define_pass,
        u32::try_from(graph_state.definition_capacity)
            .map_err(|_| anyhow!("Wasm symbol capacity exceeds u32"))?,
    )?;
    let resolve = ComputeOperation::direct(
        device,
        graph,
        &resources,
        "codegen.wasm.link.resolve",
        &generator.link_resolve_pass,
        u32::try_from(graph_state.relocation_capacity)
            .map_err(|_| anyhow!("Wasm relocation capacity exceeds u32"))?,
    )?;
    let status_copy = CopyBufferOperation::new(
        graph,
        "codegen.wasm.link.resolve.status.readback",
        "link_status",
        &status,
        0,
        "link_status_readback",
        &status_readback,
        0,
        16,
    )?;
    for batch_index in 0..submission_count {
        let batch = batches.get(batch_index).copied().unwrap_or(&[]);
        if !batch.is_empty() {
            let params_words = partition_params_words(
                input,
                definition_count,
                batch.len(),
                hash_capacity_u32,
                0,
                0,
                0,
                0,
                0,
                0,
            )?;
            let relocation_words = relocation_words(input, batch)?;
            queue.write_buffer(&params, 0, bytemuck_words(&params_words));
            queue.write_buffer(&relocations, 0, bytemuck_words(&relocation_words));
        }
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.wasm.link.resolve.encoder"),
        });
        if batch_index == 0 {
            clear.record_elements(&mut encoder, hash_capacity.max(definition_count) as u32)?;
            if definition_count != 0 {
                insert.record_elements(&mut encoder, definition_count as u32)?;
                define.record_elements(&mut encoder, definition_count as u32)?;
            }
        }
        if !batch.is_empty() {
            resolve.record_elements(&mut encoder, batch.len() as u32)?;
            CopyBufferOperation::new(
                graph,
                "codegen.wasm.link.resolve.targets.readback",
                "link_resolved_target",
                &resolved_targets,
                0,
                "link_resolved_target_readback",
                &targets_readback,
                0,
                (batch.len() * 4) as u64,
            )?
            .record(&mut encoder);
        }
        status_copy.record(&mut encoder);
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.wasm.link.resolve",
            encoder.finish(),
        );
        read_resolution_batch(device, &status_readback, &targets_readback, batch, resolved)?;
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn partition_params_words(
    input: &GpuWasmLinkInput,
    definition_count: usize,
    relocation_count: usize,
    hash_capacity: u32,
    output_len: u32,
    output_page_base: u32,
    output_page_len: u32,
    type_input_base: u32,
    body_input_base: u32,
    data_input_base: u32,
) -> Result<[u32; 14]> {
    let mut words = link_params_words(
        input,
        relocation_count,
        hash_capacity,
        output_len,
        output_page_base,
        output_page_len,
        type_input_base,
        body_input_base,
        data_input_base,
    )?;
    words[4] = u32::try_from(definition_count)
        .map_err(|_| anyhow!("Wasm partition definition count exceeds u32"))?;
    Ok(words)
}

fn relocation_words(input: &GpuWasmLinkInput, indices: &[usize]) -> Result<Vec<u32>> {
    let mut words = Vec::with_capacity(indices.len() * 8);
    for &index in indices {
        let relocation = input
            .relocations
            .get(index)
            .ok_or_else(|| anyhow!("Wasm symbol partition relocation index is invalid"))?;
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
    Ok(words)
}

fn read_resolution_batch(
    device: &wgpu::Device,
    status_readback: &wgpu::Buffer,
    targets_readback: &wgpu::Buffer,
    indices: &[usize],
    resolved: &mut [GpuWasmLinkRelocationRecord],
) -> Result<()> {
    let status_slice = status_readback.slice(..);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &status_slice,
        "codegen.wasm.link.resolve.status",
        std::time::Duration::from_secs(30),
    )?;
    let status_mapped = status_slice.get_mapped_range();
    let status_words =
        crate::gpu::readback::read_u32_words::<4>(&status_mapped, "Wasm resolve status")?;
    drop(status_mapped);
    status_readback.unmap();
    if status_words[0] != 1 || status_words[1] != 0 {
        return Err(anyhow!(
            "Wasm GPU symbol resolution failed with status {status_words:?}"
        ));
    }
    if indices.is_empty() {
        return Ok(());
    }
    let targets_slice = targets_readback.slice(..(indices.len() * 4) as u64);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &targets_slice,
        "codegen.wasm.link.resolve.targets",
        std::time::Duration::from_secs(30),
    )?;
    let targets_mapped = targets_slice.get_mapped_range();
    for (&relocation_index, target_bytes) in indices.iter().zip(targets_mapped.chunks_exact(4)) {
        let target = u32::from_le_bytes(
            target_bytes
                .try_into()
                .expect("four-byte resolved target chunk"),
        );
        let relocation = resolved
            .get_mut(relocation_index)
            .ok_or_else(|| anyhow!("Wasm resolved relocation index is invalid"))?;
        relocation.target_kind = GpuWasmRelocationTargetKind::LocalFunction;
        relocation.target_index = target;
        relocation.target_identity = [0; 3];
    }
    drop(targets_mapped);
    targets_readback.unmap();
    Ok(())
}
