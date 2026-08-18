//! GPU-parallel x86_64 stack-location lowering and ELF byte emission.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    lowering::GpuSemanticLirView,
    lowering_ir::{
        LoweringCapacities,
        TARGET_LIR_PAGE_ROWS,
        X86ArtifactLayout,
        X86LirCore,
        X86LirLocations,
        X86LirOperands,
    },
    scan::{GpuResidentExclusiveScan, GraphScanContract},
};
use crate::gpu::{
    buffers::{LaniusBuffer, readback_bytes, uniform_from_val},
    compiler_graph::{CompilerGraph, CompilerGraphAllocations, CompilerGraphWorkspace},
    kernels::KernelRegistry,
    operations::{ComputeOperation, CopyBufferOperation},
    passes_core::{PassData, map_readback_blocking},
    readback::PagedReadback,
    resource_registry::ResourceMap,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct X86ArtifactParams {
    target_capacity: u32,
    token_capacity: u32,
    function_capacity: u32,
    artifact_capacity: u32,
    target_start: u32,
    page_capacity: u32,
    reserved0: u32,
    reserved1: u32,
}

#[derive(Clone, Copy)]
pub(crate) struct GpuX86ArtifactObjectView<'a> {
    pub layout: &'a LaniusBuffer<X86ArtifactLayout>,
}

pub(crate) struct GpuX86ArtifactStage {
    artifact_capacity: u32,
    byte_counts: Vec<ComputeOperation>,
    entrypoint_clear: ComputeOperation,
    entrypoint_reduce: ComputeOperation,
    layout_op: ComputeOperation,
    clear: ComputeOperation,
    safety_emits: Vec<ComputeOperation>,
    emits: Vec<ComputeOperation>,
    runtime_emit: ComputeOperation,
    byte_scan: GpuResidentExclusiveScan,
    _params: Vec<LaniusBuffer<X86ArtifactParams>>,
    _byte_lengths: LaniusBuffer<u32>,
    _byte_offsets: LaniusBuffer<u32>,
    _entrypoint_state: LaniusBuffer<u32>,
    layout: LaniusBuffer<X86ArtifactLayout>,
    words: LaniusBuffer<u32>,
    length_readback: LaniusBuffer<u8>,
    length_readback_copy: Option<CopyBufferOperation>,
    output_readback: PagedReadback,
}

impl GpuX86ArtifactStage {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        capacities: LoweringCapacities,
        semantic: GpuSemanticLirView<'_>,
        total: &LaniusBuffer<u32>,
        core: &LaniusBuffer<X86LirCore>,
        operands: &LaniusBuffer<X86LirOperands>,
        locations: &LaniusBuffer<X86LirLocations>,
        semantic_origins: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        let resource = |name: &str| {
            graph
                .resource_id(name)
                .with_context(|| format!("x86 artifact graph is missing {name}"))
        };
        let alias_u32 = |name: &str, count: u32| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(graph, resource(name)?, count.max(1) as usize)
                .map_err(anyhow::Error::msg)
        };
        let target_capacity = capacities.target_instructions.max(1);
        let emit_capacity = target_capacity.max(capacities.source_bytes.max(1).div_ceil(4));
        let artifact_capacity = capacities.artifact_bytes.max(4).next_multiple_of(4);
        let byte_lengths = alias_u32("lir.x86.byte_lengths", target_capacity)?;
        let byte_offsets = alias_u32("lir.x86.byte_offsets", target_capacity)?;
        let body_length = alias_u32("lir.x86.body_length", 1)?;
        let entrypoint_state = alias_u32("lir.x86.entrypoint_state", 2)?;
        let layout = workspace
            .alias(graph, resource("lir.x86.artifact_layout")?, 1)
            .map_err(anyhow::Error::msg)?;
        let length = alias_u32("artifact.x86.length", 1)?;
        let words = alias_u32("artifact.x86.bytes", artifact_capacity.div_ceil(4))?;
        let token_capacity = capacities.declaration_capacity();
        let function_capacity = capacities.hir_nodes.max(1);
        let params = (0..emit_capacity.div_ceil(TARGET_LIR_PAGE_ROWS))
            .map(|page_id| {
                let target_start = page_id * TARGET_LIR_PAGE_ROWS;
                uniform_from_val(
                    device,
                    &format!("lir.x86.artifact.page.{page_id}.params"),
                    &X86ArtifactParams {
                        target_capacity,
                        token_capacity,
                        function_capacity,
                        artifact_capacity,
                        target_start,
                        page_capacity: emit_capacity
                            .saturating_sub(target_start)
                            .min(TARGET_LIR_PAGE_ROWS),
                        reserved0: 0,
                        reserved1: 0,
                    },
                )
            })
            .collect::<Vec<_>>();
        let fixed_params = &params[0];

        let byte_count_pass = load(kernels, "lir.x86.byte_count", "codegen/lir/x86/byte_count")?;
        let entrypoint_clear_pass = load(
            kernels,
            "lir.x86.entrypoint.clear",
            "codegen/lir/x86/entrypoint_clear",
        )?;
        let entrypoint_reduce_pass = load(
            kernels,
            "lir.x86.entrypoint.reduce",
            "codegen/lir/x86/entrypoint_reduce",
        )?;
        let layout_pass = load(
            kernels,
            "lir.x86.artifact.layout",
            "codegen/lir/x86/artifact_layout",
        )?;
        let clear_pass = load(
            kernels,
            "lir.x86.artifact.clear",
            "codegen/lir/x86/artifact_clear",
        )?;
        let emit_pass = load(kernels, "lir.x86.emit", "codegen/lir/x86/emit")?;
        let safety_emit_pass = load(
            kernels,
            "lir.x86.safety.emit",
            "codegen/lir/x86/safety_emit",
        )?;
        let runtime_emit_pass = load(
            kernels,
            "lir.x86.runtime.emit",
            "codegen/lir/x86/runtime_emit",
        )?;
        let graph_bindings = workspace.bindings(graph).map_err(anyhow::Error::msg)?;
        let mut resources = ResourceMap::new();
        resources.register_graph_bindings(graph, &graph_bindings);
        semantic.register(graph, &mut resources)?;
        resources.graph_buffer(graph, "lir.x86.total", total)?;
        resources.graph_buffer(graph, "lir.x86.core", core)?;
        resources.graph_buffer(graph, "lir.x86.operands", operands)?;
        resources.graph_buffer(graph, "lir.x86.locations", locations)?;
        resources.graph_buffer(graph, "lir.x86.semantic_origins", semantic_origins)?;
        let context = (graph, allocations);
        let byte_counts = params
            .iter()
            .enumerate()
            .take(target_capacity.div_ceil(TARGET_LIR_PAGE_ROWS) as usize)
            .map(|(page_id, params)| {
                let target_start = page_id as u32 * TARGET_LIR_PAGE_ROWS;
                ComputeOperation::direct_with_uniform(
                    device,
                    &context,
                    &resources,
                    "lir.x86.byte_count",
                    &byte_count_pass,
                    params,
                    target_capacity
                        .saturating_sub(target_start)
                        .min(TARGET_LIR_PAGE_ROWS),
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let byte_scan = GpuResidentExclusiveScan::new(
            device,
            kernels,
            graph,
            workspace,
            allocations,
            GraphScanContract {
                local_pass: "lir.target.byte_scan.local",
                up_pass: "lir.target.byte_scan.hierarchy_up",
                down_pass: "lir.target.byte_scan.hierarchy_down",
                apply_pass: "lir.target.byte_scan.apply",
                count: "lir.x86.total",
                input: "lir.x86.byte_lengths",
                local: "lir.target.byte_scan_local",
                block_sum: "lir.target.byte_scan_block_sum",
                block_prefix: "lir.target.byte_scan_block_prefix",
                hierarchy: "lir.target.byte_scan_hierarchy",
                output: "lir.x86.byte_offsets",
                total: "lir.x86.body_length",
            },
            target_capacity,
            total,
            &byte_lengths,
            &byte_offsets,
            &body_length,
        )?;
        let entrypoint_clear = ComputeOperation::direct(
            device,
            &context,
            &resources,
            "lir.x86.entrypoint.clear",
            &entrypoint_clear_pass,
            1,
        )?;
        let entrypoint_reduce = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.entrypoint.reduce",
            &entrypoint_reduce_pass,
            fixed_params,
            capacities.hir_nodes.max(1),
        )?;
        let layout_op = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.artifact.layout",
            &layout_pass,
            fixed_params,
            1,
        )?;
        let clear = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.artifact.clear",
            &clear_pass,
            fixed_params,
            artifact_capacity.div_ceil(4),
        )?;
        let emits = params
            .iter()
            .enumerate()
            .map(|(page_id, params)| {
                let target_start = page_id as u32 * TARGET_LIR_PAGE_ROWS;
                ComputeOperation::direct_with_uniform(
                    device,
                    &context,
                    &resources,
                    "lir.x86.emit",
                    &emit_pass,
                    params,
                    emit_capacity
                        .saturating_sub(target_start)
                        .min(TARGET_LIR_PAGE_ROWS),
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let safety_emits = params
            .iter()
            .enumerate()
            .map(|(page_id, params)| {
                let target_start = page_id as u32 * TARGET_LIR_PAGE_ROWS;
                ComputeOperation::direct_with_uniform(
                    device,
                    &context,
                    &resources,
                    "lir.x86.safety.emit",
                    &safety_emit_pass,
                    params,
                    emit_capacity
                        .saturating_sub(target_start)
                        .min(TARGET_LIR_PAGE_ROWS),
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let runtime_emit = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.runtime.emit",
            &runtime_emit_pass,
            fixed_params,
            2048,
        )?;

        let length_readback = readback_bytes(device, "artifact.x86.length.readback", 4, 4);
        let length_readback_copy = graph
            .pass_id("artifact.x86.length.readback")
            .map(|_| {
                CopyBufferOperation::new(
                    &context,
                    "artifact.x86.length.readback",
                    "artifact_length",
                    &length,
                    0,
                    "artifact_length_readback",
                    &length_readback,
                    0,
                    4,
                )
            })
            .transpose()?;
        let output_readback = PagedReadback::new(
            device,
            "artifact.x86.bytes.readback",
            (artifact_capacity as usize).min(4 << 20),
        );
        Ok(Self {
            artifact_capacity,
            byte_counts,
            entrypoint_clear,
            entrypoint_reduce,
            layout_op,
            clear,
            safety_emits,
            emits,
            runtime_emit,
            byte_scan,
            _params: params,
            _byte_lengths: byte_lengths,
            _byte_offsets: byte_offsets,
            _entrypoint_state: entrypoint_state,
            layout,
            words,
            length_readback,
            length_readback_copy,
            output_readback,
        })
    }

    pub(crate) fn record_byte_count(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        page_id: usize,
    ) -> Result<()> {
        self.byte_counts
            .get(page_id)
            .context("x86 target page has no byte-count operation")?
            .record(encoder)
    }

    pub(crate) fn record_layout_after_byte_counts(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.byte_scan.record(encoder)?;
        self.entrypoint_clear.record(encoder)?;
        self.entrypoint_reduce.record(encoder)?;
        self.layout_op.record(encoder)?;
        Ok(())
    }

    pub(crate) fn record_clear(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.clear.record(encoder)
    }

    pub(crate) fn record_emit(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        page_id: usize,
    ) -> Result<()> {
        self.safety_emits
            .get(page_id)
            .context("x86 target page has no safety-emit operation")?
            .record(encoder)?;
        self.emits
            .get(page_id)
            .context("x86 target page has no emit operation")?
            .record(encoder)
    }

    pub(crate) fn record_extra_emits(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        first_page: usize,
    ) -> Result<()> {
        for emit in &self.emits[first_page..] {
            emit.record(encoder)?;
        }
        self.runtime_emit.record(encoder)?;
        Ok(())
    }

    pub(crate) fn record_length_readback(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.length_readback_copy
            .as_ref()
            .context("x86 artifact graph has no executable length-readback operation")?
            .record(encoder);
        Ok(())
    }

    #[cfg(test)]
    fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_byte_count(encoder, 0)?;
        self.record_layout_after_byte_counts(encoder)?;
        self.record_clear(encoder)?;
        self.record_emit(encoder, 0)?;
        self.record_extra_emits(encoder, 1)?;
        self.record_length_readback(encoder)?;
        Ok(())
    }

    pub(crate) fn object_view(&self) -> GpuX86ArtifactObjectView<'_> {
        GpuX86ArtifactObjectView {
            layout: &self.layout,
        }
    }

    pub(crate) fn finish(&self, device: &wgpu::Device, queue: &wgpu::Queue) -> Result<Vec<u8>> {
        let length_slice = self.length_readback.slice(..);
        map_readback_blocking(device, &length_slice, "x86 artifact length readback")?;
        let mapped = length_slice.get_mapped_range();
        let length = u32::from_le_bytes(mapped[..4].try_into().unwrap()) as usize;
        drop(mapped);
        self.length_readback.unmap();
        if length > self.artifact_capacity as usize {
            anyhow::bail!(
                "GPU x86 artifact requires {length} bytes but the daemon workspace provides {}",
                self.artifact_capacity,
            );
        }
        self.output_readback.read_buffer(
            device,
            queue,
            &self.words,
            0,
            length,
            "x86 artifact byte readback",
        )
    }
}

fn load(kernels: &KernelRegistry, _label: &str, shader: &str) -> Result<PassData> {
    Ok(kernels.kernel(shader).clone())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        codegen::{
            lowering::{GpuSemanticLirView, target_lowering_allocations},
            lowering_ir::{
                LoweringArtifactKind,
                LoweringStatus,
                LoweringTarget,
                SemanticLirAggregateElement,
                SemanticLirCallArg,
                SemanticLirCore,
                SemanticLirFunction,
                SemanticLirLocal,
                SemanticLirOperands,
                SemanticLirParam,
                SemanticLirString,
                TargetLirFunction,
                X86LirCore,
                X86LirLocations,
                X86LirOperands,
                lowering_compiler_graph_for_artifact,
                opcode,
            },
        },
        gpu::{
            buffers::{storage_ro_from_bytes, storage_ro_from_u32s},
            device,
        },
    };

    fn records<const N: usize>(rows: &[[u32; N]]) -> Vec<u8> {
        rows.iter()
            .flat_map(|row| row.iter())
            .flat_map(|word| word.to_le_bytes())
            .collect()
    }

    #[test]
    fn physical_gpu_emits_runnable_x86_elf_from_uniform_lir() {
        let gpu = device::global();
        let capacities = LoweringCapacities {
            source_bytes: 16,
            tokens: 8,
            hir_nodes: 2,
            semantic_instructions: 12,
            call_arguments: 2,
            parameters: 1,
            aggregate_elements: 1,
            target_instructions: 12,
            artifact_bytes: 2048,
        };
        let graph = lowering_compiler_graph_for_artifact(
            capacities,
            LoweringTarget::X86_64,
            LoweringArtifactKind::Executable,
        )
        .unwrap();
        let workspace =
            CompilerGraphWorkspace::new(&gpu.device, "test.x86_artifact", &graph).unwrap();
        let status: LaniusBuffer<LoweringStatus> = workspace
            .alias(&graph, graph.resource_id("lowering.status").unwrap(), 1)
            .unwrap();
        gpu.queue
            .write_buffer(&status.buffer, 0, &records(&[[0, u32::MAX, 0, u32::MAX]]));

        let semantic_total =
            storage_ro_from_u32s(&gpu.device, "test.x86_artifact.sem.total", &[12]);
        let semantic_core = storage_ro_from_bytes::<SemanticLirCore>(
            &gpu.device,
            "test.x86_artifact.sem.core",
            &records(&[[0; 4]; 12]),
            12,
        );
        let semantic_operands = storage_ro_from_bytes::<SemanticLirOperands>(
            &gpu.device,
            "test.x86_artifact.sem.operands",
            &records(&[[0; 4]; 12]),
            12,
        );
        let semantic_call_args = storage_ro_from_bytes::<SemanticLirCallArg>(
            &gpu.device,
            "test.x86_artifact.sem.call_args",
            &records(&[[u32::MAX; 5]; 2]),
            2,
        );
        let zero = storage_ro_from_u32s(&gpu.device, "test.x86_artifact.zero", &[0]);
        let no_call_starts = storage_ro_from_u32s(
            &gpu.device,
            "test.x86_artifact.no_call_starts",
            &[u32::MAX; 12],
        );
        let no_call_counts =
            storage_ro_from_u32s(&gpu.device, "test.x86_artifact.no_call_counts", &[0; 12]);
        let function_ids = storage_ro_from_u32s(
            &gpu.device,
            "test.x86_artifact.function_ids",
            &[0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 1, 1],
        );
        let aggregate_elements = storage_ro_from_bytes::<SemanticLirAggregateElement>(
            &gpu.device,
            "test.x86_artifact.sem.aggregate",
            &records(&[[u32::MAX; 4]; 2]),
            2,
        );
        let strings = storage_ro_from_bytes::<SemanticLirString>(
            &gpu.device,
            "test.x86_artifact.sem.strings",
            &records(&[[u32::MAX; 4]; 2]),
            2,
        );
        let string_data =
            storage_ro_from_u32s(&gpu.device, "test.x86_artifact.sem.string_data", &[0; 4]);
        let semantic_functions = storage_ro_from_bytes::<SemanticLirFunction>(
            &gpu.device,
            "test.x86_artifact.sem.functions",
            &records(&[
                [0, 0, 0, 1, 3, 0, 0, 0, 0, 0, 0, 0, u32::MAX],
                [1, 1, 1, 0, 3, 1, 0, 0, 0, 0, 0, 0, u32::MAX],
            ]),
            2,
        );
        let semantic_function_count =
            storage_ro_from_u32s(&gpu.device, "test.x86_artifact.sem.function_count", &[2]);
        let semantic_params = storage_ro_from_bytes::<SemanticLirParam>(
            &gpu.device,
            "test.x86_artifact.sem.params",
            &records(&[[0, 0, 0, 3]]),
            1,
        );
        let semantic_locals = storage_ro_from_bytes::<SemanticLirLocal>(
            &gpu.device,
            "test.x86_artifact.sem.locals",
            &records(&[[u32::MAX; 4]; 2]),
            2,
        );
        let semantic = GpuSemanticLirView {
            count: &semantic_total,
            core: &semantic_core,
            operands: &semantic_operands,
            layout_word_offset: &no_call_counts,
            owner_by_instruction: &no_call_counts,
            op_by_instruction: &no_call_counts,
            function_id_by_hir: &function_ids,
            call_args: &semantic_call_args,
            call_arg_start_by_hir: &no_call_starts,
            call_arg_count_by_hir: &no_call_counts,
            aggregate_elements: &aggregate_elements,
            aggregate_element_count: &zero,
            strings: &strings,
            string_count: &zero,
            string_data_words: &string_data,
            string_pool_len: &zero,
            functions: &semantic_functions,
            function_count: &semantic_function_count,
            params: &semantic_params,
            param_count: &zero,
            locals: &semantic_locals,
            local_count: &zero,
            execution_order: None,
            status: &status,
        };
        let allocations = target_lowering_allocations(&graph, &workspace, semantic).unwrap();

        let total = workspace
            .alias::<u32>(&graph, graph.resource_id("lir.x86.total").unwrap(), 1)
            .unwrap();
        let core = workspace
            .alias::<X86LirCore>(&graph, graph.resource_id("lir.x86.core").unwrap(), 12)
            .unwrap();
        let operands = workspace
            .alias::<X86LirOperands>(&graph, graph.resource_id("lir.x86.operands").unwrap(), 12)
            .unwrap();
        let locations = workspace
            .alias::<X86LirLocations>(&graph, graph.resource_id("lir.x86.locations").unwrap(), 12)
            .unwrap();
        let semantic_origins = workspace
            .alias::<u32>(
                &graph,
                graph.resource_id("lir.x86.semantic_origins").unwrap(),
                12,
            )
            .unwrap();
        let function_count = workspace
            .alias::<u32>(
                &graph,
                graph.resource_id("lir.target.function_count").unwrap(),
                1,
            )
            .unwrap();
        let functions = workspace
            .alias::<TargetLirFunction>(
                &graph,
                graph.resource_id("lir.target.functions").unwrap(),
                2,
            )
            .unwrap();
        let function_index_by_semantic = workspace
            .alias::<u32>(
                &graph,
                graph
                    .resource_id("lir.target.function_index_by_semantic")
                    .unwrap(),
                2,
            )
            .unwrap();
        let declaration_locations = workspace
            .alias::<u32>(
                &graph,
                graph.resource_id("lir.x86.decl_location_by_token").unwrap(),
                8,
            )
            .unwrap();
        let saved_masks = workspace
            .alias::<u32>(
                &graph,
                graph
                    .resource_id("lir.x86.saved_gpr_mask_by_function")
                    .unwrap(),
                2,
            )
            .unwrap();
        gpu.queue
            .write_buffer(&total.buffer, 0, &12u32.to_le_bytes());
        gpu.queue.write_buffer(
            &core.buffer,
            0,
            &records(&[
                [0, 0, opcode::X86_LIR_OP_IMM_I32, 0],
                [1, 0, opcode::X86_LIR_OP_IMM_I32, 1],
                [2, 0, opcode::X86_LIR_OP_BINARY, 2],
                [3, 0, opcode::X86_LIR_OP_IMM_I32, 3],
                [4, 0, opcode::X86_LIR_OP_COMPARE, 4],
                [5, 0, opcode::X86_LIR_OP_RETURN, u32::MAX],
                [6, 0, opcode::X86_LIR_OP_IMM_I32, 6],
                [7, 0, opcode::X86_LIR_OP_CALL_ARG, u32::MAX],
                [8, 0, opcode::X86_LIR_OP_CALL, 8],
                [9, 0, opcode::X86_LIR_OP_CALL_ARG, u32::MAX],
                [10, 0, opcode::X86_LIR_OP_CALL_HOST, 10],
                [11, 0, opcode::X86_LIR_OP_RETURN, u32::MAX],
            ]),
        );
        gpu.queue.write_buffer(
            &operands.buffer,
            0,
            &records(&[
                [1.5f32.to_bits(), 0, 0, 5],
                [2.0f32.to_bits(), 0, 0, 5],
                [opcode::X86_LIR_BINARY_ADD_F32, 0, 1, 5],
                [3.5f32.to_bits(), 0, 0, 5],
                [0, 2, 3, 5],
                [4, 0, 0, 0],
                [7, 0, 0, 3],
                [6, 0, 0, 0],
                [0, 0, 0, 3],
                [8, 0, 0, 0],
                [29, 0, 0, 3],
                [10, 0, 0, 0],
            ]),
        );
        gpu.queue.write_buffer(
            &locations.buffer,
            0,
            &records(&[
                [0, 0, 0, 0],
                [1, 0, 0, 0],
                [2, 0, 1, 0],
                [3, 0, 0, 0],
                [4, 0, 2, 3],
                [u32::MAX, 4, 0, 0],
                [6, 0, 0, 0],
                [u32::MAX, 6, 0, 0],
                [8, 0, 0, 0],
                [u32::MAX, 8, 0, 0],
                [10, 0, 0, 0],
                [u32::MAX, 10, 0, 0],
            ]),
        );
        gpu.queue.write_buffer(
            &semantic_origins.buffer,
            0,
            &records(&[[0], [1], [2], [3], [4], [5], [6], [7], [8], [9], [10], [11]]),
        );
        gpu.queue
            .write_buffer(&function_count.buffer, 0, &2u32.to_le_bytes());
        gpu.queue.write_buffer(
            &functions.buffer,
            0,
            &records(&[[0, 0, 6, 0], [1, 6, 6, 0]]),
        );
        gpu.queue
            .write_buffer(&function_index_by_semantic.buffer, 0, &records(&[[0], [1]]));
        gpu.queue.write_buffer(
            &declaration_locations.buffer,
            0,
            &records(&[
                [6],
                [u32::MAX],
                [u32::MAX],
                [u32::MAX],
                [u32::MAX],
                [u32::MAX],
                [u32::MAX],
                [u32::MAX],
            ]),
        );
        gpu.queue
            .write_buffer(&saved_masks.buffer, 0, &records(&[[0], [0]]));

        let kernels =
            KernelRegistry::prepare_prefixes(&gpu.device, &["codegen/lir", "scan/counted"], |_| {
                true
            })
            .unwrap();
        let stage = GpuX86ArtifactStage::new(
            &gpu.device,
            &kernels,
            &graph,
            &workspace,
            &allocations,
            capacities,
            semantic,
            &total,
            &core,
            &operands,
            &locations,
            &semantic_origins,
        )
        .unwrap();
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.x86_artifact.encoder"),
            });
        stage.record(&mut encoder).unwrap();
        gpu.queue.submit(Some(encoder.finish()));
        let bytes = stage.finish(&gpu.device, &gpu.queue).unwrap();
        assert_eq!(&bytes[..4], b"\x7fELF");
        assert!(bytes.len() > 190);

        #[cfg(target_os = "linux")]
        {
            use std::{os::unix::fs::PermissionsExt, process::Command};
            let path =
                std::env::temp_dir().join(format!("lanius-uniform-lir-{}", std::process::id()));
            std::fs::write(&path, &bytes).unwrap();
            std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o700)).unwrap();
            let status = Command::new(&path).status().unwrap();
            let _ = std::fs::remove_file(&path);
            assert_eq!(status.code(), Some(1));
        }
    }
}
