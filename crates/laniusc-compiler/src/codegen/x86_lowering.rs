//! Resident semantic-LIR to scheduled x86 virtual-instruction lowering.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    functions::GpuTargetFunctionTable,
    lowering::{GpuSemanticLirView, target_lowering_allocations},
    lowering_ir::{
        LoweringCapacities,
        SEMANTIC_LIR_PAGE_ROWS,
        TARGET_LIR_PAGE_ROWS,
        X86LirCore,
        X86LirOperands,
    },
    scan::{GpuResidentExclusiveScan, GraphScanContract},
    target_pages::GpuTargetPagePlanner,
    x86_artifact::GpuX86ArtifactStage,
    x86_object_artifact::GpuX86ObjectStage,
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{CompilerGraph, CompilerGraphWorkspace},
    operations::ComputeOperation,
    passes_core::{PassData, make_pass_data_from_shader_key},
    resource_registry::ResourceMap,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct CountParams {
    semantic_capacity: u32,
    semantic_start: u32,
    page_capacity: u32,
    reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct TargetPageParams {
    semantic_capacity: u32,
    target_capacity: u32,
    target_start: u32,
    page_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct DeclSlotParams {
    token_capacity: u32,
    parameter_capacity: u32,
    local_capacity: u32,
    function_capacity: u32,
}

pub(crate) struct GpuX86LirView<'a> {
    pub total: &'a LaniusBuffer<u32>,
    pub core: &'a LaniusBuffer<X86LirCore>,
    pub operands: &'a LaniusBuffer<X86LirOperands>,
}

/// Produces the uniform x86 virtual records consumed by register allocation
/// and instruction selection. `record` performs no setup or allocation.
pub(crate) struct GpuX86LirStage {
    count_pages: Vec<ComputeOperation>,
    pages: Vec<X86LirPage>,
    decl_slots_clear: ComputeOperation,
    decl_slots_scatter: ComputeOperation,
    count_scan: GpuResidentExclusiveScan,
    target_pages: GpuTargetPagePlanner,
    functions: GpuTargetFunctionTable,
    _count_params: Vec<LaniusBuffer<CountParams>>,
    _decl_slot_params: LaniusBuffer<DeclSlotParams>,
    _counts: LaniusBuffer<u32>,
    _offsets: LaniusBuffer<u32>,
    total: LaniusBuffer<u32>,
    core: LaniusBuffer<X86LirCore>,
    operands: LaniusBuffer<X86LirOperands>,
    #[cfg(test)]
    frame_slot_by_decl_token: LaniusBuffer<u32>,
    artifact: GpuX86ArtifactStage,
    object: GpuX86ObjectStage,
}

struct X86LirPage {
    _params: LaniusBuffer<TargetPageParams>,
    scatter: ComputeOperation,
    resolve: ComputeOperation,
    replay_scatter: ComputeOperation,
    replay_resolve: ComputeOperation,
    validate: ComputeOperation,
}

impl X86LirPage {
    fn record(&self, encoder: &mut wgpu::CommandEncoder, validate: bool) -> Result<()> {
        if validate {
            self.scatter.record(encoder)?;
            self.resolve.record(encoder)?;
            self.validate.record(encoder)?;
        } else {
            self.replay_scatter.record(encoder)?;
            self.replay_resolve.record(encoder)?;
        }
        Ok(())
    }
}

impl GpuX86LirStage {
    pub(crate) fn new(
        device: &wgpu::Device,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        capacities: LoweringCapacities,
        semantic: GpuSemanticLirView<'_>,
    ) -> Result<Self> {
        let allocations = target_lowering_allocations(graph, workspace, semantic)?;
        let resource = |name: &str| {
            graph
                .resource_id(name)
                .with_context(|| format!("x86 lowering graph is missing {name}"))
        };
        let alias_u32 = |name: &str, rows: u32| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(graph, resource(name)?, rows.max(1) as usize)
                .map_err(anyhow::Error::msg)
        };
        let semantic_capacity = capacities.semantic_instructions.max(1);
        let target_capacity = capacities.target_instructions.max(1);
        let target_page_rows = target_capacity.min(TARGET_LIR_PAGE_ROWS);
        let _semantic_order = semantic
            .execution_order
            .context("x86 lowering requires GPU-scheduled semantic LIR")?;
        let counts = alias_u32("lir.x86.count_by_semantic", semantic_capacity)?;
        let offsets = alias_u32("lir.x86.offset_by_semantic", semantic_capacity)?;
        let total = alias_u32("lir.x86.total", 1)?;
        let core = workspace
            .alias(graph, resource("lir.x86.core")?, target_page_rows as usize)
            .map_err(anyhow::Error::msg)?;
        let operands = workspace
            .alias(
                graph,
                resource("lir.x86.operands")?,
                target_page_rows as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let semantic_origins = alias_u32("lir.x86.semantic_origins", target_page_rows)?;
        let frame_slot_by_decl_token = alias_u32(
            "lir.x86.frame_slot_by_decl_token",
            capacities
                .tokens
                .saturating_add(capacities.hir_nodes)
                .max(1),
        )?;

        let count_pass = load(device, "lir.x86.count", "codegen/lir/x86/count")?;
        let scatter_pass = load(device, "lir.x86.scatter", "codegen/lir/x86/scatter")?;
        let resolve_pass = load(device, "lir.x86.resolve", "codegen/lir/x86/resolve")?;
        let validate_pass = load(device, "lir.x86.validate", "codegen/lir/x86/validate")?;
        let decl_slots_clear_pass = load(
            device,
            "lir.x86.decl_slots.clear",
            "codegen/lir/x86/decl_slots_clear",
        )?;
        let decl_slots_scatter_pass = load(
            device,
            "lir.x86.decl_slots.scatter",
            "codegen/lir/x86/decl_slots_scatter",
        )?;
        let decl_slot_params = uniform_from_val(
            device,
            "lir.x86.decl_slots.params",
            &DeclSlotParams {
                token_capacity: capacities
                    .tokens
                    .saturating_add(capacities.hir_nodes)
                    .max(1),
                parameter_capacity: capacities.parameters.max(1),
                local_capacity: capacities.hir_nodes.max(1),
                function_capacity: capacities.hir_nodes.max(1),
            },
        );
        let graph_bindings = workspace.bindings(graph).map_err(anyhow::Error::msg)?;
        let mut resources = ResourceMap::new();
        resources.register_graph_bindings(graph, &graph_bindings);
        semantic.register(graph, &mut resources)?;
        let context = (graph, &allocations);
        let count_params = (0..semantic_capacity.div_ceil(SEMANTIC_LIR_PAGE_ROWS))
            .map(|page_id| {
                let semantic_start = page_id * SEMANTIC_LIR_PAGE_ROWS;
                uniform_from_val(
                    device,
                    &format!("lir.x86.count.page.{page_id}.params"),
                    &CountParams {
                        semantic_capacity,
                        semantic_start,
                        page_capacity: semantic_capacity
                            .saturating_sub(semantic_start)
                            .min(SEMANTIC_LIR_PAGE_ROWS),
                        reserved: 0,
                    },
                )
            })
            .collect::<Vec<_>>();
        let count_pages = count_params
            .iter()
            .enumerate()
            .map(|(page_id, params)| {
                let semantic_start = page_id as u32 * SEMANTIC_LIR_PAGE_ROWS;
                let page_capacity = semantic_capacity
                    .saturating_sub(semantic_start)
                    .min(SEMANTIC_LIR_PAGE_ROWS);
                ComputeOperation::direct_with_uniform(
                    device,
                    &context,
                    &resources,
                    "lir.x86.count",
                    &count_pass,
                    params,
                    page_capacity,
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let count_scan = GpuResidentExclusiveScan::new(
            device,
            graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.target.count_scan.local",
                up_pass: "lir.target.count_scan.hierarchy_up",
                down_pass: "lir.target.count_scan.hierarchy_down",
                apply_pass: "lir.target.count_scan.apply",
                count: "lir.semantic.total",
                input: "lir.x86.count_by_semantic",
                local: "lir.target.count_scan_local",
                block_sum: "lir.target.count_scan_block_sum",
                block_prefix: "lir.target.count_scan_block_prefix",
                hierarchy: "lir.target.count_scan_hierarchy",
                output: "lir.x86.offset_by_semantic",
                total: "lir.x86.total",
            },
            semantic_capacity,
            semantic.count,
            &counts,
            &offsets,
            &total,
        )?;
        let target_pages = GpuTargetPagePlanner::new(
            device,
            graph,
            workspace,
            &allocations,
            &resources,
            capacities,
        )?;
        let pages = (0..target_capacity.div_ceil(TARGET_LIR_PAGE_ROWS))
            .map(|page_id| {
                let target_start = page_id * TARGET_LIR_PAGE_ROWS;
                let page_capacity = target_capacity
                    .saturating_sub(target_start)
                    .min(TARGET_LIR_PAGE_ROWS);
                let params = uniform_from_val(
                    device,
                    &format!("lir.x86.page.{page_id}.params"),
                    &TargetPageParams {
                        semantic_capacity,
                        target_capacity,
                        target_start,
                        page_capacity,
                    },
                );
                Ok(X86LirPage {
                    scatter: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.x86.scatter",
                        &scatter_pass,
                        &params,
                        page_capacity,
                    )?,
                    resolve: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.x86.resolve",
                        &resolve_pass,
                        &params,
                        page_capacity,
                    )?,
                    replay_scatter: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.x86.scatter.replay",
                        &scatter_pass,
                        &params,
                        page_capacity,
                    )?,
                    replay_resolve: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.x86.resolve.replay",
                        &resolve_pass,
                        &params,
                        page_capacity,
                    )?,
                    validate: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.x86.validate",
                        &validate_pass,
                        &params,
                        page_capacity,
                    )?,
                    _params: params,
                })
            })
            .collect::<Result<Vec<_>>>()?;
        let functions = GpuTargetFunctionTable::new(
            device,
            graph,
            workspace,
            &allocations,
            &resources,
            semantic_capacity,
            target_capacity,
            capacities.hir_nodes,
            semantic.count,
        )?;
        let decl_slots_clear = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.decl_slots.clear",
            &decl_slots_clear_pass,
            &decl_slot_params,
            frame_slot_by_decl_token.count as u32,
        )?;
        let decl_slots_scatter = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.x86.decl_slots.scatter",
            &decl_slots_scatter_pass,
            &decl_slot_params,
            capacities
                .parameters
                .max(capacities.semantic_instructions)
                .max(1),
        )?;
        let artifact = GpuX86ArtifactStage::new(
            device,
            graph,
            workspace,
            &allocations,
            capacities,
            semantic,
            &total,
            &core,
            &operands,
            &semantic_origins,
        )?;
        let object = GpuX86ObjectStage::new(
            device,
            graph,
            workspace,
            &allocations,
            capacities,
            semantic,
            artifact.object_view(),
        )?;
        Ok(Self {
            count_pages,
            pages,
            decl_slots_clear,
            decl_slots_scatter,
            count_scan,
            target_pages,
            functions,
            _count_params: count_params,
            _decl_slot_params: decl_slot_params,
            _counts: counts,
            _offsets: offsets,
            total,
            core,
            operands,
            #[cfg(test)]
            frame_slot_by_decl_token,
            artifact,
            object,
        })
    }

    pub(crate) fn output(&self) -> GpuX86LirView<'_> {
        GpuX86LirView {
            total: &self.total,
            core: &self.core,
            operands: &self.operands,
        }
    }

    pub(crate) fn record_count_page(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        page_id: usize,
    ) -> Result<()> {
        self.count_pages
            .get(page_id)
            .context("x86 semantic count page is outside the configured unit capacity")?
            .record(encoder)
    }

    pub(crate) fn count_page_count(&self) -> usize {
        self.count_pages.len()
    }

    pub(crate) fn target_page_count(&self) -> usize {
        self.pages.len()
    }

    pub(crate) fn record_before_target_pages(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.record_after_counts_prefix(encoder)
    }

    pub(crate) fn record_measure_page(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        page_id: usize,
    ) -> Result<()> {
        self.pages[page_id].record(encoder, true)?;
        self.artifact.record_byte_count(encoder, page_id)
    }

    pub(crate) fn record_between_target_pages(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        object: bool,
    ) -> Result<()> {
        self.artifact.record_layout_after_byte_counts(encoder)?;
        if object {
            self.object.record_status_normalization(encoder)?;
        }
        self.artifact.record_clear(encoder)?;
        Ok(())
    }

    pub(crate) fn record_emit_page(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        page_id: usize,
    ) -> Result<()> {
        self.pages[page_id].record(encoder, false)?;
        self.artifact.record_emit(encoder, page_id)
    }

    pub(crate) fn record_after_target_pages(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        object: bool,
    ) -> Result<()> {
        self.artifact
            .record_extra_emits(encoder, self.pages.len())?;
        if object {
            self.object.record_projection(encoder)
        } else {
            self.artifact.record_length_readback(encoder);
            Ok(())
        }
    }

    pub(crate) fn set_object_identity(&self, queue: &wgpu::Queue, library_id: u32, unit_id: u32) {
        self.object.set_identity(queue, library_id, unit_id);
    }

    #[cfg(test)]
    fn record_counts(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        for count in &self.count_pages {
            count.record(encoder)?;
        }
        Ok(())
    }

    fn record_after_counts_prefix(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.count_scan.record(encoder)?;
        self.target_pages.record(encoder)?;
        self.functions.record(encoder)?;
        self.decl_slots_clear.record(encoder)?;
        self.decl_slots_scatter.record(encoder)
    }

    #[cfg(test)]
    fn record_lir(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_counts(encoder)?;
        self.record_after_counts_prefix(encoder)?;
        for page in &self.pages {
            page.record(encoder, true)?;
        }
        Ok(())
    }

    pub(crate) fn finish_artifact(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
    ) -> Result<Vec<u8>> {
        self.artifact.finish(device, queue)
    }

    pub(crate) fn finish_object(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
    ) -> Result<super::x86::GpuX86RelocatableObject> {
        self.object.finish(device, queue, library_id, unit_id)
    }
}

fn load(device: &wgpu::Device, label: &str, shader: &str) -> Result<PassData> {
    make_pass_data_from_shader_key(device, label, "main", shader)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        codegen::lowering_ir::{
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
            lowering_compiler_graph,
            opcode,
        },
        gpu::{
            buffers::{
                readback_bytes,
                storage_ro_from_bytes,
                storage_ro_from_u32s,
                tracked_buffer_allocation_stats,
            },
            device,
            passes_core::{map_readback_blocking, pipeline_creation_count},
        },
    };

    fn record_bytes<const N: usize>(records: &[[u32; N]]) -> Vec<u8> {
        records
            .iter()
            .flat_map(|record| record.iter())
            .flat_map(|word| word.to_le_bytes())
            .collect()
    }

    fn read_words(device: &wgpu::Device, buffer: &LaniusBuffer<u8>) -> Vec<u32> {
        let slice = buffer.slice(..);
        map_readback_blocking(device, &slice, "x86 LIR readback").unwrap();
        let mapped = slice.get_mapped_range();
        let words = mapped
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        drop(mapped);
        buffer.unmap();
        words
    }

    #[test]
    fn physical_gpu_runs_resident_semantic_to_scheduled_x86_lir() {
        let gpu = device::global();
        let capacities = LoweringCapacities {
            source_bytes: 8,
            tokens: 8,
            hir_nodes: 4,
            semantic_instructions: 8,
            call_arguments: 2,
            parameters: 2,
            aggregate_elements: 2,
            target_instructions: 10,
            artifact_bytes: 64,
        };
        let graph = lowering_compiler_graph(capacities, LoweringTarget::X86_64).unwrap();
        let workspace = CompilerGraphWorkspace::new(&gpu.device, "test.x86_lir", &graph).unwrap();
        let status: LaniusBuffer<LoweringStatus> = workspace
            .alias(&graph, graph.resource_id("lowering.status").unwrap(), 1)
            .unwrap();
        let total = storage_ro_from_u32s(&gpu.device, "test.x86_lir.total", &[8]);
        let page_core = storage_ro_from_bytes::<SemanticLirCore>(
            &gpu.device,
            "test.x86_lir.page_core",
            &record_bytes(&[
                [opcode::SEMANTIC_LIR_OP_CONST_I32, 3, 0, u32::MAX, 1, 0],
                [opcode::SEMANTIC_LIR_OP_CONST_I32, 3, 0, u32::MAX, 0, 0],
                [opcode::SEMANTIC_LIR_OP_ADD, 3, 0, u32::MAX, 2, 0],
                [opcode::SEMANTIC_LIR_OP_RETURN, 0, 0, u32::MAX, 3, 0],
                [opcode::SEMANTIC_LIR_OP_BRANCH, 0, 0, u32::MAX, 5, 0],
                [opcode::SEMANTIC_LIR_OP_BLOCK_BEGIN, 0, 0, u32::MAX, 6, 0],
                [opcode::SEMANTIC_LIR_OP_CALL, 3, 0, u32::MAX, 4, 0],
                [opcode::SEMANTIC_LIR_OP_CALL_SYMBOL, 3, 0, u32::MAX, 7, 0],
            ]),
            8,
        );
        let page_operands = storage_ro_from_bytes::<SemanticLirOperands>(
            &gpu.device,
            "test.x86_lir.page_operands",
            &record_bytes(&[
                [1, 9, u32::MAX, u32::MAX],
                [0, 7, u32::MAX, u32::MAX],
                [2, 1, 0, u32::MAX],
                [3, 2, u32::MAX, u32::MAX],
                [5, 6, u32::MAX, u32::MAX],
                [6, u32::MAX, u32::MAX, u32::MAX],
                [4, 42, 0, 2],
                [7, 7, 11, 23],
            ]),
            8,
        );
        let semantic_order: LaniusBuffer<u32> = workspace
            .alias(
                &graph,
                graph.resource_id("lir.semantic.schedule_order").unwrap(),
                8,
            )
            .unwrap();
        gpu.queue.write_buffer(
            &semantic_order.buffer,
            0,
            &record_bytes(&[[1u32, 0, 2, 3, 5, 6, 4, 7]]),
        );
        let semantic_owners =
            storage_ro_from_u32s(&gpu.device, "test.x86_lir.semantic_owners", &[0; 8]);
        let semantic_ops = storage_ro_from_u32s(
            &gpu.device,
            "test.x86_lir.semantic_ops",
            &[
                opcode::SEMANTIC_LIR_OP_CONST_I32,
                opcode::SEMANTIC_LIR_OP_CONST_I32,
                opcode::SEMANTIC_LIR_OP_ADD,
                opcode::SEMANTIC_LIR_OP_RETURN,
                opcode::SEMANTIC_LIR_OP_CALL,
                opcode::SEMANTIC_LIR_OP_BRANCH,
                opcode::SEMANTIC_LIR_OP_BLOCK_BEGIN,
                opcode::SEMANTIC_LIR_OP_CALL_SYMBOL,
            ],
        );
        let call_args = storage_ro_from_bytes::<SemanticLirCallArg>(
            &gpu.device,
            "test.x86_lir.call_args",
            &record_bytes(&[[4, 0, 0, 0], [4, 2, 1, 0]]),
            2,
        );
        let call_arg_start_by_hir = storage_ro_from_u32s(
            &gpu.device,
            "test.x86_lir.call_arg_start_by_hir",
            &[
                u32::MAX,
                u32::MAX,
                u32::MAX,
                u32::MAX,
                0,
                u32::MAX,
                u32::MAX,
                u32::MAX,
            ],
        );
        let call_arg_count_by_hir = storage_ro_from_u32s(
            &gpu.device,
            "test.x86_lir.call_arg_count_by_hir",
            &[0, 0, 0, 0, 2, 0, 0, 0],
        );
        let aggregate_elements = storage_ro_from_bytes::<SemanticLirAggregateElement>(
            &gpu.device,
            "test.x86_lir.aggregate_elements",
            &record_bytes(&[[u32::MAX; 5]; 4]),
            4,
        );
        let string_rows = storage_ro_from_bytes::<SemanticLirString>(
            &gpu.device,
            "test.x86_lir.strings",
            &record_bytes(&[[u32::MAX; 4]; 4]),
            4,
        );
        let empty_count = storage_ro_from_u32s(&gpu.device, "test.x86_lir.empty_count", &[0]);
        let string_data = storage_ro_from_u32s(&gpu.device, "test.x86_lir.string_data", &[0; 2]);
        let functions = storage_ro_from_bytes::<SemanticLirFunction>(
            &gpu.device,
            "test.x86_lir.functions",
            &record_bytes(&[
                [0, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 0, u32::MAX],
                [u32::MAX; 13],
                [u32::MAX; 13],
                [u32::MAX; 13],
            ]),
            4,
        );
        let params = storage_ro_from_bytes::<SemanticLirParam>(
            &gpu.device,
            "test.x86_lir.params",
            &record_bytes(&[[0, 3, 0, 3], [u32::MAX; 4]]),
            2,
        );
        let locals = storage_ro_from_bytes::<SemanticLirLocal>(
            &gpu.device,
            "test.x86_lir.locals",
            &record_bytes(&[
                [0, 4, 0, 3],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
            ]),
            8,
        );
        let function_count = storage_ro_from_u32s(&gpu.device, "test.x86_lir.fn_count", &[1]);
        let param_count = storage_ro_from_u32s(&gpu.device, "test.x86_lir.param_count", &[1]);
        let local_count = storage_ro_from_u32s(&gpu.device, "test.x86_lir.local_count", &[1]);
        let stage = GpuX86LirStage::new(
            &gpu.device,
            &graph,
            &workspace,
            capacities,
            GpuSemanticLirView {
                count: &total,
                core: &page_core,
                operands: &page_operands,
                owner_by_instruction: &semantic_owners,
                op_by_instruction: &semantic_ops,
                function_id_by_hir: &semantic_owners,
                call_args: &call_args,
                call_arg_start_by_hir: &call_arg_start_by_hir,
                call_arg_count_by_hir: &call_arg_count_by_hir,
                aggregate_elements: &aggregate_elements,
                aggregate_element_count: &empty_count,
                strings: &string_rows,
                string_count: &empty_count,
                string_data_words: &string_data,
                string_pool_len: &empty_count,
                functions: &functions,
                function_count: &function_count,
                params: &params,
                param_count: &param_count,
                locals: &locals,
                local_count: &local_count,
                execution_order: Some(&semantic_order),
                status: &status,
            },
        )
        .unwrap();
        let pipelines_before = pipeline_creation_count();
        let buffers_before = tracked_buffer_allocation_stats();
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.x86_lir.encoder"),
            });
        stage.record_lir(&mut encoder).unwrap();
        assert_eq!(pipeline_creation_count(), pipelines_before);
        assert_eq!(tracked_buffer_allocation_stats(), buffers_before);

        let output = stage.output();
        let functions = stage.functions.output();
        let total_rb = readback_bytes(&gpu.device, "test.x86_lir.total.rb", 4, 1);
        let core_rb = readback_bytes(&gpu.device, "test.x86_lir.core.rb", 160, 40);
        let operands_rb = readback_bytes(&gpu.device, "test.x86_lir.operands.rb", 160, 40);
        let function_count_rb = readback_bytes(&gpu.device, "test.x86_lir.function_count.rb", 4, 1);
        let functions_rb = readback_bytes(&gpu.device, "test.x86_lir.functions.rb", 64, 16);
        let status_rb = readback_bytes(&gpu.device, "test.x86_lir.status.rb", 16, 4);
        let frame_slots_rb = readback_bytes(&gpu.device, "test.x86_lir.frame_slots.rb", 32, 8);
        encoder.copy_buffer_to_buffer(&output.total.buffer, 0, &total_rb.buffer, 0, 4);
        encoder.copy_buffer_to_buffer(&output.core.buffer, 0, &core_rb.buffer, 0, 160);
        encoder.copy_buffer_to_buffer(&output.operands.buffer, 0, &operands_rb.buffer, 0, 160);
        encoder.copy_buffer_to_buffer(&functions.count.buffer, 0, &function_count_rb.buffer, 0, 4);
        encoder.copy_buffer_to_buffer(&functions.rows.buffer, 0, &functions_rb.buffer, 0, 64);
        encoder.copy_buffer_to_buffer(&status.buffer, 0, &status_rb.buffer, 0, 16);
        encoder.copy_buffer_to_buffer(
            &stage.frame_slot_by_decl_token.buffer,
            0,
            &frame_slots_rb.buffer,
            0,
            32,
        );
        gpu.queue.submit(Some(encoder.finish()));

        assert_eq!(read_words(&gpu.device, &total_rb)[0], 10);
        let core_words = read_words(&gpu.device, &core_rb);
        assert_eq!(
            [
                core_words[2],
                core_words[6],
                core_words[10],
                core_words[14],
                core_words[18],
                core_words[22],
                core_words[26],
                core_words[30],
                core_words[34],
                core_words[38],
            ],
            [
                opcode::X86_LIR_OP_IMM_I32,
                opcode::X86_LIR_OP_IMM_I32,
                opcode::X86_LIR_OP_BINARY,
                opcode::X86_LIR_OP_RETURN,
                opcode::X86_LIR_OP_BRANCH,
                opcode::X86_LIR_OP_LABEL,
                opcode::X86_LIR_OP_CALL_ARG,
                opcode::X86_LIR_OP_CALL_ARG,
                opcode::X86_LIR_OP_CALL,
                opcode::X86_LIR_OP_CALL_SYMBOL,
            ]
        );
        let operand_words = read_words(&gpu.device, &operands_rb);
        assert_eq!([operand_words[0], operand_words[4]], [9, 7]);
        assert_eq!(
            &operand_words[8..11],
            &[opcode::X86_LIR_BINARY_ADD_I32, 0, 1]
        );
        assert_eq!(read_words(&gpu.device, &function_count_rb)[0], 1);
        assert_eq!(&operand_words[16..20], &[u32::MAX, 5, 0, 0]);
        assert_eq!(&operand_words[36..39], &[7, 11, 23]);
        assert_eq!(&read_words(&gpu.device, &functions_rb)[..4], &[0, 0, 10, 0]);
        let frame_slots = read_words(&gpu.device, &frame_slots_rb);
        assert_eq!((frame_slots[3], frame_slots[4]), (10, 11));
        assert_eq!(
            read_words(&gpu.device, &status_rb)[0] & opcode::LOWERING_STATUS_UNSUPPORTED_TARGET,
            0
        );
    }
}
