use anyhow::{Result, anyhow};

use super::{
    GpuWasmLinkInput,
    GpuWasmLinkRelocationRecord,
    GpuWasmRelocationTargetKind,
    executable::{bytemuck_words, dispatch, input_u32, link_params_words, rw_u32},
    symbol_partitions::GpuWasmSymbolPartitionPlan,
};
use crate::codegen::wasm::{GpuWasmLinker, create_wasm_bind_group};

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
    )?;
    let params = input_u32(
        device,
        "codegen.wasm.link.resolve.params",
        &params_words,
        wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
    );
    let symbols = input_u32(
        device,
        "codegen.wasm.link.resolve.symbols",
        &symbol_words,
        wgpu::BufferUsages::STORAGE,
    );
    let hash_table = rw_u32(
        device,
        "codegen.wasm.link.resolve.hash_table",
        hash_capacity,
        wgpu::BufferUsages::empty(),
    );
    let definitions = rw_u32(
        device,
        "codegen.wasm.link.resolve.definitions",
        definition_count,
        wgpu::BufferUsages::empty(),
    );
    let status = rw_u32(
        device,
        "codegen.wasm.link.resolve.status",
        4,
        wgpu::BufferUsages::COPY_SRC,
    );
    let relocation_capacity = first_batch_len.max(1);
    let relocations = rw_u32(
        device,
        "codegen.wasm.link.resolve.relocations",
        relocation_capacity * 8,
        wgpu::BufferUsages::empty(),
    );
    let resolved_targets = rw_u32(
        device,
        "codegen.wasm.link.resolve.targets",
        relocation_capacity,
        wgpu::BufferUsages::COPY_SRC,
    );
    let status_readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb.codegen.wasm.link.resolve.status"),
        size: 16,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let targets_readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb.codegen.wasm.link.resolve.targets"),
        size: (relocation_capacity * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let common = |pass: &crate::codegen::wasm::LazyWasmPass, label| {
        create_wasm_bind_group(
            device,
            Some(label),
            pass,
            0,
            &[
                ("gLink", params.as_entire_binding()),
                ("link_symbol", symbols.as_entire_binding()),
                ("link_hash_table", hash_table.as_entire_binding()),
                ("link_symbol_definition", definitions.as_entire_binding()),
                ("link_status", status.as_entire_binding()),
            ],
        )
    };
    let clear_group = create_wasm_bind_group(
        device,
        Some("codegen.wasm.link.resolve.clear.bind_group"),
        &generator.link_symbol_clear_pass,
        0,
        &[
            ("gLink", params.as_entire_binding()),
            ("link_hash_table", hash_table.as_entire_binding()),
            ("link_symbol_definition", definitions.as_entire_binding()),
            ("link_status", status.as_entire_binding()),
        ],
    )?;
    let insert_group = common(
        &generator.link_symbol_insert_pass,
        "codegen.wasm.link.resolve.insert.bind_group",
    )?;
    let define_group = common(
        &generator.link_symbol_define_pass,
        "codegen.wasm.link.resolve.define.bind_group",
    )?;
    let resolve_group = create_wasm_bind_group(
        device,
        Some("codegen.wasm.link.resolve.bind_group"),
        &generator.link_resolve_pass,
        0,
        &[
            ("gLink", params.as_entire_binding()),
            ("link_symbol", symbols.as_entire_binding()),
            ("link_hash_table", hash_table.as_entire_binding()),
            ("link_symbol_definition", definitions.as_entire_binding()),
            ("link_status", status.as_entire_binding()),
            ("link_relocation", relocations.as_entire_binding()),
            ("link_resolved_target", resolved_targets.as_entire_binding()),
        ],
    )?;

    let batches = partition
        .relocation_indices
        .chunks(max_relocations)
        .collect::<Vec<_>>();
    let submission_count = batches.len().max(1);
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
            )?;
            let relocation_words = relocation_words(input, batch)?;
            queue.write_buffer(&params, 0, bytemuck_words(&params_words));
            queue.write_buffer(&relocations, 0, bytemuck_words(&relocation_words));
        }
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.wasm.link.resolve.encoder"),
        });
        if batch_index == 0 {
            dispatch(
                &mut encoder,
                "codegen.wasm.link.resolve.clear",
                &generator.link_symbol_clear_pass,
                &clear_group,
                hash_capacity.max(definition_count).div_ceil(256) as u32,
            )?;
            if definition_count != 0 {
                dispatch(
                    &mut encoder,
                    "codegen.wasm.link.resolve.insert",
                    &generator.link_symbol_insert_pass,
                    &insert_group,
                    definition_count.div_ceil(256) as u32,
                )?;
                dispatch(
                    &mut encoder,
                    "codegen.wasm.link.resolve.define",
                    &generator.link_symbol_define_pass,
                    &define_group,
                    definition_count.div_ceil(256) as u32,
                )?;
            }
        }
        if !batch.is_empty() {
            dispatch(
                &mut encoder,
                "codegen.wasm.link.resolve",
                &generator.link_resolve_pass,
                &resolve_group,
                batch.len().div_ceil(256) as u32,
            )?;
            encoder.copy_buffer_to_buffer(
                &resolved_targets,
                0,
                &targets_readback,
                0,
                (batch.len() * 4) as u64,
            );
        }
        encoder.copy_buffer_to_buffer(&status, 0, &status_readback, 0, 16);
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
) -> Result<[u32; 12]> {
    let mut words = link_params_words(
        input,
        relocation_count,
        hash_capacity,
        output_len,
        output_page_base,
        output_page_len,
        type_input_base,
        body_input_base,
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
