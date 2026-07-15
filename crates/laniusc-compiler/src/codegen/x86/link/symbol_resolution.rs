use anyhow::{Result, anyhow, bail};
use wgpu::util::DeviceExt;

use super::{
    GpuX86LinkInput,
    GpuX86LinkRelocationRecord,
    GpuX86LinkSymbolRecord,
    symbol_partitions::{GpuX86SymbolPartition, GpuX86SymbolPartitionPlan},
};
use crate::codegen::x86::{
    GpuX86CodeGenerator,
    support::{
        dispatch_compute_pass,
        reflected_bind_group,
        storage_u32_rw,
        u32_words_bytes,
        uniform_u32_words,
        workgroup_grid_1d,
    },
};

const SYMBOL_PARTITION_BYTES_PER_COLUMN: usize = 4 * 1024 * 1024;

impl GpuX86CodeGenerator {
    pub(super) fn resolve_symbol_relocations(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: &GpuX86LinkInput,
    ) -> Result<Vec<GpuX86LinkRelocationRecord>> {
        let binding_limit = device.limits().max_storage_buffer_binding_size as usize;
        let column_limit = binding_limit.min(SYMBOL_PARTITION_BYTES_PER_COLUMN);
        let max_definitions = column_limit / 16;
        let max_queries = column_limit / 16;
        if max_definitions < 2 || max_queries == 0 {
            bail!("x86 GPU binding limit {binding_limit} is too small for symbol resolution");
        }
        let plan =
            GpuX86SymbolPartitionPlan::new(input, max_definitions).map_err(anyhow::Error::msg)?;
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
                max_queries,
                &mut resolved,
            )?;
        }
        Ok(resolved)
    }
}

fn resolve_partition(
    generator: &GpuX86CodeGenerator,
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    input: &GpuX86LinkInput,
    partition: &GpuX86SymbolPartition,
    max_queries: usize,
    resolved: &mut [GpuX86LinkRelocationRecord],
) -> Result<()> {
    let definition_count = partition.definition_indices.len();
    let hash_capacity = definition_count
        .saturating_mul(2)
        .checked_next_power_of_two()
        .ok_or_else(|| anyhow!("x86 symbol partition hash capacity overflows"))?
        .max(1);
    let hash_capacity_u32 = u32::try_from(hash_capacity)
        .map_err(|_| anyhow!("x86 symbol partition hash capacity exceeds u32"))?;
    let mut definition_words = Vec::with_capacity(definition_count * 4);
    for &definition_index in &partition.definition_indices {
        let definition = input
            .symbols
            .get(definition_index)
            .ok_or_else(|| anyhow!("x86 symbol partition definition index is invalid"))?;
        definition_words.extend_from_slice(&[
            definition.identity[0],
            definition.identity[1],
            definition.identity[2],
            u32::try_from(definition_index)
                .map_err(|_| anyhow!("x86 symbol definition index exceeds u32"))?,
        ]);
    }
    let query_capacity = partition.relocation_indices.len().min(max_queries).max(1);
    let first_query_count = partition.relocation_indices.len().min(max_queries);
    let params = uniform_u32_words(
        device,
        "codegen.x86.link.symbol_partition.params",
        &[
            definition_count as u32,
            first_query_count as u32,
            hash_capacity_u32,
            0,
        ],
    );
    let definitions = input_u32(
        device,
        "codegen.x86.link.symbol_partition.definitions",
        &definition_words,
        wgpu::BufferUsages::STORAGE,
    );
    let queries = storage_u32_rw(
        device,
        "codegen.x86.link.symbol_partition.queries",
        query_capacity * 4,
        wgpu::BufferUsages::COPY_DST,
    );
    let hash_table = storage_u32_rw(
        device,
        "codegen.x86.link.symbol_partition.hash_table",
        hash_capacity,
        wgpu::BufferUsages::empty(),
    );
    let definition_values = storage_u32_rw(
        device,
        "codegen.x86.link.symbol_partition.definition_values",
        definition_count.max(1),
        wgpu::BufferUsages::empty(),
    );
    let resolved_values = storage_u32_rw(
        device,
        "codegen.x86.link.symbol_partition.resolved_values",
        query_capacity,
        wgpu::BufferUsages::COPY_SRC,
    );
    let status = storage_u32_rw(
        device,
        "codegen.x86.link.symbol_partition.status",
        4,
        wgpu::BufferUsages::COPY_SRC,
    );
    let status_readback = readback(device, "rb.codegen.x86.link.symbol_partition.status", 16);
    let values_readback = readback(
        device,
        "rb.codegen.x86.link.symbol_partition.values",
        query_capacity * 4,
    );

    let clear_group = reflected_bind_group(
        device,
        Some("codegen.x86.link.symbol_partition.clear.bind_group"),
        &generator.link_symbol_partition_clear_pass,
        0,
        &[
            ("gSymbolPartition", params.buffer.as_entire_binding()),
            ("link_partition_definition", definitions.as_entire_binding()),
            ("link_partition_query", queries.buffer.as_entire_binding()),
            (
                "link_partition_hash_table",
                hash_table.buffer.as_entire_binding(),
            ),
            (
                "link_partition_definition_value",
                definition_values.buffer.as_entire_binding(),
            ),
            (
                "link_partition_resolved_value",
                resolved_values.buffer.as_entire_binding(),
            ),
            ("link_partition_status", status.buffer.as_entire_binding()),
        ],
    )?;
    let insert_group = reflected_bind_group(
        device,
        Some("codegen.x86.link.symbol_partition.insert.bind_group"),
        &generator.link_symbol_partition_insert_pass,
        0,
        &[
            ("gSymbolPartition", params.buffer.as_entire_binding()),
            ("link_partition_definition", definitions.as_entire_binding()),
            ("link_partition_query", queries.buffer.as_entire_binding()),
            (
                "link_partition_hash_table",
                hash_table.buffer.as_entire_binding(),
            ),
            (
                "link_partition_definition_value",
                definition_values.buffer.as_entire_binding(),
            ),
            (
                "link_partition_resolved_value",
                resolved_values.buffer.as_entire_binding(),
            ),
            ("link_partition_status", status.buffer.as_entire_binding()),
        ],
    )?;
    let define_group = reflected_bind_group(
        device,
        Some("codegen.x86.link.symbol_partition.define.bind_group"),
        &generator.link_symbol_partition_define_pass,
        0,
        &[
            ("gSymbolPartition", params.buffer.as_entire_binding()),
            ("link_partition_definition", definitions.as_entire_binding()),
            ("link_partition_query", queries.buffer.as_entire_binding()),
            (
                "link_partition_hash_table",
                hash_table.buffer.as_entire_binding(),
            ),
            (
                "link_partition_definition_value",
                definition_values.buffer.as_entire_binding(),
            ),
            (
                "link_partition_resolved_value",
                resolved_values.buffer.as_entire_binding(),
            ),
            ("link_partition_status", status.buffer.as_entire_binding()),
        ],
    )?;
    let resolve_group = reflected_bind_group(
        device,
        Some("codegen.x86.link.symbol_partition.resolve.bind_group"),
        &generator.link_symbol_partition_resolve_pass,
        0,
        &[
            ("gSymbolPartition", params.buffer.as_entire_binding()),
            ("link_partition_definition", definitions.as_entire_binding()),
            ("link_partition_query", queries.buffer.as_entire_binding()),
            (
                "link_partition_hash_table",
                hash_table.buffer.as_entire_binding(),
            ),
            (
                "link_partition_definition_value",
                definition_values.buffer.as_entire_binding(),
            ),
            (
                "link_partition_resolved_value",
                resolved_values.buffer.as_entire_binding(),
            ),
            ("link_partition_status", status.buffer.as_entire_binding()),
        ],
    )?;

    let batches = partition
        .relocation_indices
        .chunks(max_queries)
        .collect::<Vec<_>>();
    for batch_index in 0..batches.len().max(1) {
        let batch = batches.get(batch_index).copied().unwrap_or(&[]);
        queue.write_buffer(
            &params.buffer,
            0,
            &u32_words_bytes(&[
                definition_count as u32,
                batch.len() as u32,
                hash_capacity_u32,
                0,
            ]),
        );
        if !batch.is_empty() {
            let query_words = query_words(input, batch)?;
            queue.write_buffer(&queries.buffer, 0, &u32_words_bytes(&query_words));
        }
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.x86.link.symbol_partition.encoder"),
        });
        if batch_index == 0 {
            dispatch_compute_pass(
                &mut encoder,
                "link.symbol_partition.clear",
                "codegen.x86.link.symbol_partition.clear",
                &generator.link_symbol_partition_clear_pass,
                &clear_group,
                workgroup_grid_1d(
                    hash_capacity
                        .max(definition_count)
                        .max(batch.len())
                        .div_ceil(256) as u32,
                ),
            );
            if definition_count != 0 {
                dispatch_compute_pass(
                    &mut encoder,
                    "link.symbol_partition.insert",
                    "codegen.x86.link.symbol_partition.insert",
                    &generator.link_symbol_partition_insert_pass,
                    &insert_group,
                    workgroup_grid_1d((definition_count as u32).div_ceil(256)),
                );
                dispatch_compute_pass(
                    &mut encoder,
                    "link.symbol_partition.define",
                    "codegen.x86.link.symbol_partition.define",
                    &generator.link_symbol_partition_define_pass,
                    &define_group,
                    workgroup_grid_1d((definition_count as u32).div_ceil(256)),
                );
            }
        }
        if !batch.is_empty() {
            dispatch_compute_pass(
                &mut encoder,
                "link.symbol_partition.resolve",
                "codegen.x86.link.symbol_partition.resolve",
                &generator.link_symbol_partition_resolve_pass,
                &resolve_group,
                workgroup_grid_1d((batch.len() as u32).div_ceil(256)),
            );
            encoder.copy_buffer_to_buffer(
                &resolved_values.buffer,
                0,
                &values_readback,
                0,
                (batch.len() * 4) as u64,
            );
        }
        encoder.copy_buffer_to_buffer(&status.buffer, 0, &status_readback, 0, 16);
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.x86.link.symbol_partition",
            encoder.finish(),
        );
        read_partition_batch(
            device,
            input,
            &status_readback,
            &values_readback,
            batch,
            resolved,
        )?;
    }
    Ok(())
}

fn query_words(input: &GpuX86LinkInput, relocation_indices: &[usize]) -> Result<Vec<u32>> {
    let mut words = Vec::with_capacity(relocation_indices.len() * 4);
    for &relocation_index in relocation_indices {
        let relocation = input
            .relocations
            .get(relocation_index)
            .ok_or_else(|| anyhow!("x86 symbol partition relocation index is invalid"))?;
        let symbol = input
            .symbols
            .get(relocation.target_index as usize)
            .ok_or_else(|| anyhow!("x86 symbol partition query target is invalid"))?;
        words.extend_from_slice(&[
            symbol.identity[0],
            symbol.identity[1],
            symbol.identity[2],
            u32::try_from(relocation_index)
                .map_err(|_| anyhow!("x86 relocation index exceeds u32"))?,
        ]);
    }
    Ok(words)
}

fn read_partition_batch(
    device: &wgpu::Device,
    input: &GpuX86LinkInput,
    status_readback: &wgpu::Buffer,
    values_readback: &wgpu::Buffer,
    relocation_indices: &[usize],
    resolved: &mut [GpuX86LinkRelocationRecord],
) -> Result<()> {
    let status_slice = status_readback.slice(..);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &status_slice,
        "codegen.x86.link.symbol_partition.status",
        std::time::Duration::from_secs(30),
    )?;
    let mapped = status_slice.get_mapped_range();
    let status = crate::gpu::readback::read_u32_words::<4>(&mapped, "x86 symbol partition status")?;
    drop(mapped);
    status_readback.unmap();
    if status[0] != 1 || status[1] != 0 {
        bail!("x86 GPU symbol partition failed with status {status:?}");
    }
    if relocation_indices.is_empty() {
        return Ok(());
    }

    let values_slice = values_readback.slice(..(relocation_indices.len() * 4) as u64);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &values_slice,
        "codegen.x86.link.symbol_partition.values",
        std::time::Duration::from_secs(30),
    )?;
    let mapped = values_slice.get_mapped_range();
    let result = (|| {
        for (offset, &relocation_index) in relocation_indices.iter().enumerate() {
            let start = offset * 4;
            let definition_index = u32::from_le_bytes(mapped[start..start + 4].try_into().unwrap());
            let definition = input
                .symbols
                .get(definition_index as usize)
                .ok_or_else(|| anyhow!("x86 GPU symbol definition index is invalid"))?;
            let relocation = resolved
                .get_mut(relocation_index)
                .ok_or_else(|| anyhow!("x86 resolved relocation index is invalid"))?;
            rewrite_symbol_target(relocation, definition)?;
        }
        Ok(())
    })();
    drop(mapped);
    values_readback.unmap();
    result
}

fn rewrite_symbol_target(
    relocation: &mut GpuX86LinkRelocationRecord,
    definition: &GpuX86LinkSymbolRecord,
) -> Result<()> {
    if definition.section == 0 {
        bail!("x86 symbol resolution cannot target an undefined symbol row");
    }
    relocation.target_index = definition.object_index;
    relocation.target_section = definition.section;
    relocation.target_offset = definition
        .offset
        .checked_add(relocation.target_offset)
        .ok_or_else(|| anyhow!("x86 resolved symbol target offset overflows u32"))?;
    Ok(())
}

fn input_u32(
    device: &wgpu::Device,
    label: &str,
    words: &[u32],
    usage: wgpu::BufferUsages,
) -> wgpu::Buffer {
    let contents = if words.is_empty() {
        u32_words_bytes(&[0])
    } else {
        u32_words_bytes(words)
    };
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents: &contents,
        usage,
    })
}

fn readback(device: &wgpu::Device, label: &str, byte_len: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_len.max(4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn practical_partition_column_cap_is_bounded_below_large_device_bindings() {
        let binding_limit = 128 * 1024 * 1024usize;
        let column_limit = binding_limit.min(SYMBOL_PARTITION_BYTES_PER_COLUMN);
        assert_eq!(column_limit, 4 * 1024 * 1024);
        assert_eq!(column_limit / 16, 262_144);
    }

    #[test]
    fn resolved_symbol_target_uses_definition_object_section_and_reference_offset() {
        let mut relocation = GpuX86LinkRelocationRecord {
            object_index: 3,
            kind: 2,
            site_section: 1,
            site_offset: 9,
            target_kind: 2,
            target_index: 17,
            target_offset: 5,
            target_section: 0,
            addend_lo: 0,
            addend_hi: 0,
        };
        let definition = GpuX86LinkSymbolRecord {
            object_index: 8,
            identity: [1, 2, 3],
            section: 2,
            offset: 40,
            size: 12,
            flags: 0,
        };

        rewrite_symbol_target(&mut relocation, &definition).expect("rewrite symbol target");

        assert_eq!(relocation.target_index, 8);
        assert_eq!(relocation.target_section, 2);
        assert_eq!(relocation.target_offset, 45);
    }

    #[test]
    fn resolved_symbol_target_rejects_offset_overflow() {
        let mut relocation = GpuX86LinkRelocationRecord {
            object_index: 0,
            kind: 2,
            site_section: 1,
            site_offset: 0,
            target_kind: 2,
            target_index: 0,
            target_offset: 1,
            target_section: 0,
            addend_lo: 0,
            addend_hi: 0,
        };
        let definition = GpuX86LinkSymbolRecord {
            object_index: 1,
            identity: [4, 5, 6],
            section: 1,
            offset: u32::MAX,
            size: 1,
            flags: 0,
        };

        assert!(rewrite_symbol_target(&mut relocation, &definition).is_err());
    }
}
