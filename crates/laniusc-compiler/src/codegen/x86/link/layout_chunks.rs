use anyhow::{Result, anyhow, bail};

use super::GpuX86LinkInput;
use crate::{
    codegen::x86::GpuX86Linker,
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

const OBJECT_LAYOUT_BYTES_PER_INPUT_RECORD: usize = 16;
const OBJECT_LAYOUT_CHUNK_BYTES: usize = 4 * 1024 * 1024;

pub(crate) struct X86LayoutChunkGraph {
    object_capacity: usize,
    block_capacity: usize,
    materialized: MaterializedCompilerGraph,
}

impl X86LayoutChunkGraph {
    fn covers(&self, objects: usize, blocks: usize) -> bool {
        self.object_capacity >= objects && self.block_capacity >= blocks
    }

    fn new(
        generator: &GpuX86Linker,
        device: &wgpu::Device,
        object_capacity: usize,
        block_capacity: usize,
    ) -> Result<Self> {
        let object_capacity = object_capacity.max(1);
        let block_capacity = block_capacity.max(1);
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
        add(
            "link_object_sections",
            ResourceClass::Input,
            object_capacity * 16,
        )?;
        add(
            "link_object_entry_offset",
            ResourceClass::Input,
            object_capacity * 4,
        )?;
        add(
            "link_section_local_prefix",
            ResourceClass::Workspace,
            object_capacity * 8,
        )?;
        add(
            "link_section_block_sum",
            ResourceClass::Workspace,
            block_capacity * 8,
        )?;
        add(
            "link_section_block_prefix_a",
            ResourceClass::Workspace,
            block_capacity * 8,
        )?;
        add(
            "link_section_block_prefix_b",
            ResourceClass::Workspace,
            block_capacity * 8,
        )?;
        add(
            "link_object_section_base",
            ResourceClass::Workspace,
            object_capacity * 8,
        )?;
        add("x86_elf_layout", ResourceClass::Artifact, 32)?;
        add("layout_status", ResourceClass::Artifact, 16)?;
        add(
            "link_object_bases_readback",
            ResourceClass::External,
            object_capacity * 8,
        )?;
        drop(add);

        let resource = |name: &str| {
            graph
                .resource_id(name)
                .unwrap_or_else(|| panic!("x86 layout graph resource `{name}`"))
        };
        let local_prefix = resource("link_section_local_prefix");
        let block_sum = resource("link_section_block_sum");
        let prefix_a = resource("link_section_block_prefix_a");
        let prefix_b = resource("link_section_block_prefix_b");
        let object_bases = resource("link_object_section_base");
        let elf_layout = resource("x86_elf_layout");
        let layout_status = resource("layout_status");
        let object_bases_readback = resource("link_object_bases_readback");
        graph
            .add_reflected_compute_pass_by_name(
                "codegen.x86.link.layout_chunk.local",
                CompilerPhase::Artifact,
                ResourceDomain::Declarations,
                &generator.link_layout_scan_local_pass.reflection,
                &[
                    ReflectedResourceBinding {
                        binding: "link_section_local_prefix",
                        resource: local_prefix,
                        mode: Some(AccessMode::Write),
                    },
                    ReflectedResourceBinding {
                        binding: "link_section_block_sum",
                        resource: block_sum,
                        mode: Some(AccessMode::Write),
                    },
                ],
            )
            .map_err(anyhow::Error::msg)?;
        // The first step has stride zero and therefore does not inspect its
        // nominal ping input. Marking B initialized states that shader
        // contract without adding a physical clear.
        graph
            .mark_zero_initialized(prefix_b)
            .map_err(anyhow::Error::msg)?;
        for (name, input, output) in [
            (
                "codegen.x86.link.layout_chunk.scan.b_to_a",
                prefix_b,
                prefix_a,
            ),
            (
                "codegen.x86.link.layout_chunk.scan.a_to_b",
                prefix_a,
                prefix_b,
            ),
        ] {
            graph
                .add_reflected_compute_pass_by_name(
                    name,
                    CompilerPhase::Artifact,
                    ResourceDomain::Declarations,
                    &generator.link_layout_scan_blocks_pass.reflection,
                    &[
                        ReflectedResourceBinding {
                            binding: "link_section_block_prefix_in",
                            resource: input,
                            mode: Some(AccessMode::Read),
                        },
                        ReflectedResourceBinding {
                            binding: "link_section_block_prefix_out",
                            resource: output,
                            mode: Some(AccessMode::Write),
                        },
                    ],
                )
                .map_err(anyhow::Error::msg)?;
        }
        graph
            .repeat_pass_range(
                crate::gpu::scan::scan_step_values(block_capacity as u32)
                    .len()
                    .div_ceil(2) as u32,
                "codegen.x86.link.layout_chunk.scan.b_to_a",
                "codegen.x86.link.layout_chunk.scan.a_to_b",
            )
            .map_err(anyhow::Error::msg)?;
        let scan_steps = crate::gpu::scan::scan_step_values(block_capacity as u32);
        let final_prefix = if (scan_steps.len() - 1) & 1 == 0 {
            prefix_a
        } else {
            prefix_b
        };
        graph
            .add_reflected_compute_pass_by_name(
                "codegen.x86.link.layout_chunk.finalize",
                CompilerPhase::Artifact,
                ResourceDomain::Declarations,
                &generator.link_layout_pass.reflection,
                &[
                    ReflectedResourceBinding {
                        binding: "link_section_block_prefix",
                        resource: final_prefix,
                        mode: Some(AccessMode::Read),
                    },
                    ReflectedResourceBinding {
                        binding: "link_object_section_base",
                        resource: object_bases,
                        mode: Some(AccessMode::Write),
                    },
                    ReflectedResourceBinding {
                        binding: "x86_elf_layout",
                        resource: elf_layout,
                        mode: Some(AccessMode::Write),
                    },
                    ReflectedResourceBinding {
                        binding: "layout_status",
                        resource: layout_status,
                        mode: Some(AccessMode::Write),
                    },
                ],
            )
            .map_err(anyhow::Error::msg)?;
        graph
            .add_buffer_copy_pass(
                "codegen.x86.link.layout_chunk.object_bases.readback",
                CompilerPhase::Artifact,
                "link_object_section_base",
                object_bases,
                "link_object_bases_readback",
                object_bases_readback,
            )
            .map_err(anyhow::Error::msg)?;
        let graph = graph.build().map_err(anyhow::Error::msg)?;
        let materialized = MaterializedCompilerGraph::new_with_upstream_storage(
            device,
            "x86_link_layout_chunk",
            graph,
            &[],
        )
        .map_err(anyhow::Error::msg)?;
        Ok(Self {
            object_capacity,
            block_capacity,
            materialized,
        })
    }
}

pub(super) struct GpuX86ResolvedObjectLayout {
    pub object_bases: Vec<[u32; 2]>,
    pub elf_layout: LaniusBuffer<u32>,
    pub layout_status: LaniusBuffer<u32>,
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
        let retained_object_capacity = chunk_capacity.min(input.objects.len()).max(1);
        let retained_block_capacity = retained_object_capacity.div_ceil(256).max(1);
        let mut graph_guard = self
            .layout_chunk_graph
            .lock()
            .expect("x86 layout-chunk graph cache poisoned");
        if !graph_guard
            .as_ref()
            .is_some_and(|graph| graph.covers(retained_object_capacity, retained_block_capacity))
        {
            *graph_guard = Some(X86LayoutChunkGraph::new(
                self,
                device,
                retained_object_capacity,
                retained_block_capacity,
            )?);
        }
        let graph_state = graph_guard.as_ref().expect("layout graph installed");
        let graph = &graph_state.materialized;
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
            let object_sections = self.reusable_input_u32(
                device,
                queue,
                "codegen.x86.link.layout_chunk.object_sections",
                &section_words,
            );
            let object_entries = self.reusable_input_u32(
                device,
                queue,
                "codegen.x86.link.layout_chunk.object_entries",
                &entry_words,
            );
            let chunk_bases = graph.buffer::<u32>("link_object_section_base")?;
            let elf_layout = graph.buffer::<u32>("x86_elf_layout")?;
            let layout_status = graph.buffer::<u32>("layout_status")?;
            let params = self.reusable_uniform_u32(
                device,
                queue,
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
            let readback = self.reusable_readback(
                device,
                "rb.codegen.x86.link.layout_chunk.object_bases",
                chunk_count * 8,
            );
            let graph_bindings = graph.bindings()?;
            let mut resources = ResourceMap::new();
            resources.attach_graph(graph.graph(), graph.allocations());
            resources.register_graph_bindings(graph.graph(), &graph_bindings);
            resources.buffer("link_object_sections", &object_sections);
            resources.buffer("link_object_entry_offset", &object_entries);
            resources.buffer("link_object_bases_readback", &readback);
            resources.buffer("gLink", &params);
            let local = ComputeOperation::direct(
                device,
                graph,
                &resources,
                "codegen.x86.link.layout_chunk.local",
                &self.link_layout_scan_local_pass,
                graph_state.object_capacity as u32,
            )?;
            let scan_steps = crate::gpu::scan::scan_step_values(graph_state.block_capacity as u32);
            let mut scan_params = Vec::with_capacity(scan_steps.len());
            let mut scans = Vec::with_capacity(scan_steps.len());
            for (step_index, step) in scan_steps.iter().copied().enumerate() {
                let scan_param_label =
                    format!("codegen.x86.link.layout_chunk.scan.params.{step_index}");
                scan_params.push(self.reusable_uniform_u32(
                    device,
                    queue,
                    &scan_param_label,
                    &[chunk_count as u32, block_count as u32, step, 0],
                ));
                let pass_name = if step_index & 1 == 0 {
                    "codegen.x86.link.layout_chunk.scan.b_to_a"
                } else {
                    "codegen.x86.link.layout_chunk.scan.a_to_b"
                };
                let mut scan_resources = resources.clone();
                scan_resources.buffer("gScan", scan_params.last().unwrap());
                scans.push(ComputeOperation::direct(
                    device,
                    graph,
                    &scan_resources,
                    pass_name,
                    &self.link_layout_scan_blocks_pass,
                    graph_state.block_capacity as u32,
                )?);
            }
            let finalize = ComputeOperation::direct(
                device,
                graph,
                &resources,
                "codegen.x86.link.layout_chunk.finalize",
                &self.link_layout_pass,
                graph_state.object_capacity as u32,
            )?;
            let readback_copy = CopyBufferOperation::new(
                graph,
                "codegen.x86.link.layout_chunk.object_bases.readback",
                "link_object_section_base",
                &chunk_bases,
                0,
                "link_object_bases_readback",
                &readback,
                0,
                (chunk_count * 8) as u64,
            )?;
            let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("codegen.x86.link.layout_chunk.encoder"),
            });
            local.record_elements(&mut encoder, chunk_count as u32)?;
            for scan in &scans {
                scan.record_elements(&mut encoder, block_count as u32)?;
            }
            finalize.record_elements(&mut encoder, chunk_count as u32)?;
            readback_copy.record(&mut encoder);
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
                final_elf_layout = Some(elf_layout);
                final_layout_status = Some(layout_status);
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
