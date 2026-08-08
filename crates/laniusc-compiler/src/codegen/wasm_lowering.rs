//! Resident target-specific lowering from semantic LIR to scheduled Wasm LIR.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    functions::GpuTargetFunctionTable,
    lowering::{GpuSemanticLirView, target_lowering_allocations},
    lowering_ir::{LoweringCapacities, SEMANTIC_LIR_PAGE_ROWS, TARGET_LIR_PAGE_ROWS},
    scan::{GpuResidentExclusiveScan, GraphScanContract},
    target_pages::GpuTargetPagePlanner,
    wasm_module::GpuWasmModuleStage,
    wasm_object_artifact::GpuWasmObjectStage,
};
use crate::gpu::{
    buffers::{LaniusBuffer, readback_bytes, uniform_from_val},
    compiler_graph::{CompilerGraph, CompilerGraphWorkspace},
    operations::ComputeOperation,
    passes_core::{PassData, make_pass_data_from_shader_key, map_readback_blocking},
    readback::PagedReadback,
    resource_registry::ResourceMap,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmCountParams {
    semantic_capacity: u32,
    semantic_start: u32,
    page_capacity: u32,
    reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmScatterParams {
    semantic_capacity: u32,
    target_capacity: u32,
    target_start: u32,
    page_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmByteCountParams {
    target_capacity: u32,
    target_start: u32,
    page_capacity: u32,
    reserved0: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmEmitParams {
    target_capacity: u32,
    artifact_capacity: u32,
    target_start: u32,
    page_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmAbiParams {
    function_capacity: u32,
    param_capacity: u32,
    local_capacity: u32,
    n_tokens: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmResolveParams {
    target_capacity: u32,
    n_tokens: u32,
    semantic_capacity: u32,
    target_start: u32,
    page_capacity: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmAttachBodyParams {
    function_capacity: u32,
    target_capacity: u32,
    reserved0: u32,
    reserved1: u32,
}

/// The complete second lowering level for Wasm through stable scheduling.
/// Every object needed by `record` is resident and bound during construction.
pub(crate) struct GpuWasmLirStage {
    count_pages: Vec<ComputeOperation>,
    pages: Vec<WasmLirPage>,
    param_width: ComputeOperation,
    local_width: ComputeOperation,
    abi_functions_op: ComputeOperation,
    declaration_indices: ComputeOperation,
    attach_bodies: ComputeOperation,
    count_scan: GpuResidentExclusiveScan,
    target_pages: GpuTargetPagePlanner,
    functions: GpuTargetFunctionTable,
    byte_scan: GpuResidentExclusiveScan,
    param_scan: GpuResidentExclusiveScan,
    local_scan: GpuResidentExclusiveScan,
    _count_params: Vec<LaniusBuffer<WasmCountParams>>,
    _abi_params: LaniusBuffer<WasmAbiParams>,
    _attach_body_params: LaniusBuffer<WasmAttachBodyParams>,
    _counts: LaniusBuffer<u32>,
    _offsets: LaniusBuffer<u32>,
    #[cfg(test)]
    instructions: LaniusBuffer<super::lowering_ir::WasmLirInstruction>,
    #[cfg(test)]
    abi_functions: LaniusBuffer<super::lowering_ir::WasmLirFunction>,
    module: GpuWasmModuleStage,
    object: GpuWasmObjectStage,
    artifact_length_readback: LaniusBuffer<u8>,
    artifact_readback: PagedReadback,
    _param_widths: LaniusBuffer<u32>,
    _local_widths: LaniusBuffer<u32>,
}

struct WasmLirPage {
    _scatter_params: LaniusBuffer<WasmScatterParams>,
    _byte_count_params: LaniusBuffer<WasmByteCountParams>,
    _emit_params: LaniusBuffer<WasmEmitParams>,
    _resolve_params: LaniusBuffer<WasmResolveParams>,
    scatter: ComputeOperation,
    resolve: ComputeOperation,
    replay_scatter: ComputeOperation,
    replay_resolve: ComputeOperation,
    validate: ComputeOperation,
    byte_count: ComputeOperation,
    emit: ComputeOperation,
}

impl WasmLirPage {
    fn record_measure(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.scatter.record(encoder)?;
        self.resolve.record(encoder)?;
        self.validate.record(encoder)?;
        self.byte_count.record(encoder)
    }

    fn record_emit(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.replay_scatter.record(encoder)?;
        self.replay_resolve.record(encoder)?;
        self.emit.record(encoder)
    }
}

impl GpuWasmLirStage {
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
                .with_context(|| format!("Wasm lowering graph is missing {name}"))
        };
        let alias_u32 = |name: &str, rows: u32| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(graph, resource(name)?, rows.max(1) as usize)
                .map_err(anyhow::Error::msg)
        };
        let semantic_capacity = capacities.semantic_instructions.max(1);
        let target_capacity = capacities.target_instructions.max(1);
        #[cfg(test)]
        let target_page_rows = target_capacity.min(TARGET_LIR_PAGE_ROWS);
        let _semantic_order = semantic
            .execution_order
            .context("Wasm lowering requires GPU-scheduled semantic LIR")?;
        let counts = alias_u32("lir.wasm.count_by_semantic", semantic_capacity)?;
        let offsets = alias_u32("lir.wasm.offset_by_semantic", semantic_capacity)?;
        let total = alias_u32("lir.wasm.total", 1)?;
        #[cfg(test)]
        let instructions: LaniusBuffer<super::lowering_ir::WasmLirInstruction> = workspace
            .alias(
                graph,
                resource("lir.wasm.instructions")?,
                target_page_rows as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let byte_lengths = alias_u32("lir.wasm.byte_lengths", target_capacity)?;
        let byte_offsets = alias_u32("lir.wasm.byte_offsets", target_capacity)?;
        let artifact_length = alias_u32("lir.wasm.body_length", 1)?;
        let artifact_capacity = capacities.artifact_bytes.max(1);
        let artifact_words = alias_u32("lir.wasm.body_bytes", artifact_capacity.div_ceil(4))?;
        let param_widths = alias_u32("lir.wasm.param_widths", capacities.parameters)?;
        let param_prefix = alias_u32("lir.wasm.param_prefix", capacities.parameters)?;
        let param_value_total = alias_u32("lir.wasm.param_value_total", 1)?;
        let local_widths = alias_u32("lir.wasm.local_widths", capacities.hir_nodes)?;
        let local_prefix = alias_u32("lir.wasm.local_prefix", capacities.hir_nodes)?;
        let local_value_total = alias_u32("lir.wasm.local_value_total", 1)?;
        let abi_functions = workspace
            .alias(
                graph,
                resource("lir.wasm.functions")?,
                capacities.hir_nodes.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let value_capacity = capacities
            .tokens
            .saturating_add(capacities.hir_nodes)
            .max(1);
        let count_pass = load(device, "lir.wasm.count", "codegen/lir/wasm/count")?;
        let scatter_pass = load(device, "lir.wasm.scatter", "codegen/lir/wasm/scatter")?;
        let validate_pass = load(device, "lir.wasm.validate", "codegen/lir/wasm/validate")?;
        let byte_count_pass = load(device, "lir.wasm.byte_count", "codegen/lir/wasm/byte_count")?;
        let emit_pass = load(device, "lir.wasm.emit", "codegen/lir/wasm/emit")?;
        let param_width_pass = load(
            device,
            "lir.wasm.abi.param_widths",
            "codegen/lir/wasm/param_widths",
        )?;
        let local_width_pass = load(
            device,
            "lir.wasm.abi.local_widths",
            "codegen/lir/wasm/local_widths",
        )?;
        let abi_functions_pass = load(
            device,
            "lir.wasm.abi.functions",
            "codegen/lir/wasm/functions",
        )?;
        let declaration_indices_pass = load(
            device,
            "lir.wasm.abi.declaration_indices",
            "codegen/lir/wasm/declaration_indices",
        )?;
        let resolve_indices_pass = load(
            device,
            "lir.wasm.resolve_indices",
            "codegen/lir/wasm/resolve_indices",
        )?;
        let attach_bodies_pass = load(
            device,
            "lir.wasm.abi.attach_bodies",
            "codegen/lir/wasm/attach_bodies",
        )?;
        let abi_params = uniform_from_val(
            device,
            "lir.wasm.abi.params",
            &WasmAbiParams {
                function_capacity: capacities.hir_nodes.max(1),
                param_capacity: capacities.parameters.max(1),
                local_capacity: capacities.hir_nodes.max(1),
                n_tokens: value_capacity,
            },
        );
        let attach_body_params = uniform_from_val(
            device,
            "lir.wasm.attach_bodies.params",
            &WasmAttachBodyParams {
                function_capacity: capacities.hir_nodes.max(1),
                target_capacity,
                reserved0: 0,
                reserved1: 0,
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
                    &format!("lir.wasm.count.page.{page_id}.params"),
                    &WasmCountParams {
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
                    "lir.wasm.count",
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
                input: "lir.wasm.count_by_semantic",
                local: "lir.target.count_scan_local",
                block_sum: "lir.target.count_scan_block_sum",
                block_prefix: "lir.target.count_scan_block_prefix",
                hierarchy: "lir.target.count_scan_hierarchy",
                output: "lir.wasm.offset_by_semantic",
                total: "lir.wasm.total",
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
        let param_width = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.wasm.abi.param_widths",
            &param_width_pass,
            &abi_params,
            param_widths.count as u32,
        )?;
        let param_scan = GpuResidentExclusiveScan::new(
            device,
            graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.wasm.abi.param_scan.local",
                up_pass: "lir.wasm.abi.param_scan.hierarchy_up",
                down_pass: "lir.wasm.abi.param_scan.hierarchy_down",
                apply_pass: "lir.wasm.abi.param_scan.apply",
                count: "lir.semantic.param_total",
                input: "lir.wasm.param_widths",
                local: "lir.wasm.param_scan_local",
                block_sum: "lir.wasm.param_scan_block_sum",
                block_prefix: "lir.wasm.param_scan_block_prefix",
                hierarchy: "lir.wasm.param_scan_hierarchy",
                output: "lir.wasm.param_prefix",
                total: "lir.wasm.param_value_total",
            },
            capacities.parameters.max(1),
            semantic.param_count,
            &param_widths,
            &param_prefix,
            &param_value_total,
        )?;
        let local_width = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.wasm.abi.local_widths",
            &local_width_pass,
            &abi_params,
            local_widths.count as u32,
        )?;
        let local_scan = GpuResidentExclusiveScan::new(
            device,
            graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.wasm.abi.local_scan.local",
                up_pass: "lir.wasm.abi.local_scan.hierarchy_up",
                down_pass: "lir.wasm.abi.local_scan.hierarchy_down",
                apply_pass: "lir.wasm.abi.local_scan.apply",
                count: "lir.semantic.local_total",
                input: "lir.wasm.local_widths",
                local: "lir.wasm.local_scan_local",
                block_sum: "lir.wasm.local_scan_block_sum",
                block_prefix: "lir.wasm.local_scan_block_prefix",
                hierarchy: "lir.wasm.local_scan_hierarchy",
                output: "lir.wasm.local_prefix",
                total: "lir.wasm.local_value_total",
            },
            capacities.hir_nodes.max(1),
            semantic.local_count,
            &local_widths,
            &local_prefix,
            &local_value_total,
        )?;
        let abi_functions_op = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.wasm.abi.functions",
            &abi_functions_pass,
            &abi_params,
            abi_functions.count as u32,
        )?;
        let declaration_indices = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.wasm.abi.declaration_indices",
            &declaration_indices_pass,
            &abi_params,
            param_widths.count.max(local_widths.count) as u32,
        )?;
        let pages = (0..target_capacity.div_ceil(TARGET_LIR_PAGE_ROWS))
            .map(|page_id| {
                let target_start = page_id * TARGET_LIR_PAGE_ROWS;
                let page_capacity = target_capacity
                    .saturating_sub(target_start)
                    .min(TARGET_LIR_PAGE_ROWS);
                let scatter_params = uniform_from_val(
                    device,
                    &format!("lir.wasm.page.{page_id}.scatter.params"),
                    &WasmScatterParams {
                        semantic_capacity,
                        target_capacity,
                        target_start,
                        page_capacity,
                    },
                );
                let resolve_params = uniform_from_val(
                    device,
                    &format!("lir.wasm.page.{page_id}.resolve.params"),
                    &WasmResolveParams {
                        target_capacity,
                        n_tokens: value_capacity,
                        semantic_capacity,
                        target_start,
                        page_capacity,
                        reserved0: 0,
                        reserved1: 0,
                        reserved2: 0,
                    },
                );
                let byte_count_params = uniform_from_val(
                    device,
                    &format!("lir.wasm.page.{page_id}.byte_count.params"),
                    &WasmByteCountParams {
                        target_capacity,
                        target_start,
                        page_capacity,
                        reserved0: 0,
                    },
                );
                let emit_params = uniform_from_val(
                    device,
                    &format!("lir.wasm.page.{page_id}.emit.params"),
                    &WasmEmitParams {
                        target_capacity,
                        artifact_capacity,
                        target_start,
                        page_capacity,
                    },
                );
                Ok(WasmLirPage {
                    scatter: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.wasm.scatter",
                        &scatter_pass,
                        &scatter_params,
                        page_capacity,
                    )?,
                    resolve: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.wasm.resolve_indices",
                        &resolve_indices_pass,
                        &resolve_params,
                        page_capacity,
                    )?,
                    replay_scatter: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.wasm.scatter.replay",
                        &scatter_pass,
                        &scatter_params,
                        page_capacity,
                    )?,
                    replay_resolve: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.wasm.resolve_indices.replay",
                        &resolve_indices_pass,
                        &resolve_params,
                        page_capacity,
                    )?,
                    validate: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.wasm.validate",
                        &validate_pass,
                        &scatter_params,
                        page_capacity,
                    )?,
                    byte_count: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.wasm.byte_count",
                        &byte_count_pass,
                        &byte_count_params,
                        page_capacity,
                    )?,
                    emit: ComputeOperation::direct_with_uniform(
                        device,
                        &context,
                        &resources,
                        "lir.wasm.emit",
                        &emit_pass,
                        &emit_params,
                        page_capacity,
                    )?,
                    _scatter_params: scatter_params,
                    _resolve_params: resolve_params,
                    _byte_count_params: byte_count_params,
                    _emit_params: emit_params,
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
        let byte_scan = GpuResidentExclusiveScan::new(
            device,
            graph,
            workspace,
            &allocations,
            GraphScanContract {
                local_pass: "lir.target.byte_scan.local",
                up_pass: "lir.target.byte_scan.hierarchy_up",
                down_pass: "lir.target.byte_scan.hierarchy_down",
                apply_pass: "lir.target.byte_scan.apply",
                count: "lir.wasm.total",
                input: "lir.wasm.byte_lengths",
                local: "lir.target.byte_scan_local",
                block_sum: "lir.target.byte_scan_block_sum",
                block_prefix: "lir.target.byte_scan_block_prefix",
                hierarchy: "lir.target.byte_scan_hierarchy",
                output: "lir.wasm.byte_offsets",
                total: "lir.wasm.body_length",
            },
            target_capacity,
            &total,
            &byte_lengths,
            &byte_offsets,
            &artifact_length,
        )?;
        let attach_bodies = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.wasm.abi.attach_bodies",
            &attach_bodies_pass,
            &attach_body_params,
            abi_functions.count as u32,
        )?;
        let module = GpuWasmModuleStage::new(
            device,
            graph,
            workspace,
            &allocations,
            capacities,
            semantic,
            &abi_functions,
            &artifact_words,
        )?;
        let object = GpuWasmObjectStage::new(
            device,
            graph,
            workspace,
            &allocations,
            capacities,
            semantic,
            module.object_projection_inputs(),
        )?;
        let artifact_length_readback =
            readback_bytes(device, "artifact.wasm.length.readback", 4, 4);
        let artifact_readback = PagedReadback::new(
            device,
            "artifact.wasm.bytes.readback",
            (capacities.artifact_bytes as usize).min(4 << 20),
        );
        Ok(Self {
            count_pages,
            pages,
            param_width,
            local_width,
            abi_functions_op,
            declaration_indices,
            attach_bodies,
            count_scan,
            target_pages,
            functions,
            byte_scan,
            param_scan,
            local_scan,
            _count_params: count_params,
            _abi_params: abi_params,
            _attach_body_params: attach_body_params,
            _counts: counts,
            _offsets: offsets,
            #[cfg(test)]
            instructions,
            #[cfg(test)]
            abi_functions,
            module,
            object,
            artifact_length_readback,
            artifact_readback,
            _param_widths: param_widths,
            _local_widths: local_widths,
        })
    }

    #[cfg(test)]
    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_counts(encoder)?;
        self.record_after_counts(encoder)?;
        self.record_after_target_pages(encoder, false)
    }

    #[cfg(test)]
    pub(crate) fn object(&self) -> super::wasm_object_artifact::GpuWasmObjectView<'_> {
        self.object.output()
    }

    /// Records the same lowering and module layout as executable mode, then
    /// projects relocatable columns. Pipelines and bind groups are resident;
    /// the per-job object identity is the only updated value.
    #[cfg(test)]
    pub(crate) fn record_object(
        &self,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        library_id: u32,
        unit_id: u32,
    ) -> Result<()> {
        self.object.set_identity(queue, library_id, unit_id);
        self.record_counts(encoder)?;
        self.record_after_counts(encoder)?;
        self.record_after_target_pages(encoder, true)
    }

    pub(crate) fn set_object_identity(&self, queue: &wgpu::Queue, library_id: u32, unit_id: u32) {
        self.object.set_identity(queue, library_id, unit_id);
    }

    pub(crate) fn finish_object(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
    ) -> Result<super::wasm::GpuWasmRelocatableObject> {
        self.object.finish(device, queue, library_id, unit_id)
    }

    /// Maps the daemon-resident readback buffers after the command buffer has
    /// been submitted. Recording allocates nothing; the same staging storage
    /// is reused by every sequential daemon job.
    pub(crate) fn finish_artifact(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
    ) -> Result<Vec<u8>> {
        let length_slice = self.artifact_length_readback.slice(..);
        map_readback_blocking(device, &length_slice, "Wasm artifact length readback")?;
        let mapped_length = length_slice.get_mapped_range();
        let length = u32::from_le_bytes(mapped_length[0..4].try_into().unwrap()) as usize;
        drop(mapped_length);
        self.artifact_length_readback.unmap();
        let artifact = self.module.output();
        if length > artifact.words.byte_size {
            anyhow::bail!(
                "GPU Wasm artifact requires {length} bytes but the daemon workspace provides {}",
                artifact.words.byte_size,
            );
        }
        self.artifact_readback.read_buffer(
            device,
            queue,
            artifact.words,
            0,
            length,
            "Wasm artifact byte readback",
        )
    }

    #[cfg(test)]
    fn record_lir(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_counts(encoder)?;
        self.record_after_counts(encoder)
    }

    pub(crate) fn record_count_page(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        page_id: usize,
    ) -> Result<()> {
        self.count_pages
            .get(page_id)
            .context("Wasm semantic count page is outside the configured unit capacity")?
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
        self.count_scan.record(encoder)?;
        self.target_pages.record(encoder)?;
        self.param_width.record(encoder)?;
        self.param_scan.record(encoder)?;
        self.local_width.record(encoder)?;
        self.local_scan.record(encoder)?;
        self.abi_functions_op.record(encoder)?;
        self.declaration_indices.record(encoder)?;
        self.functions.record(encoder)
    }

    pub(crate) fn record_measure_page(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        page_id: usize,
    ) -> Result<()> {
        self.pages[page_id].record_measure(encoder)
    }

    pub(crate) fn record_between_target_pages(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        _object: bool,
    ) -> Result<()> {
        self.byte_scan.record(encoder)?;
        self.attach_bodies.record(encoder)
    }

    pub(crate) fn record_emit_page(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        page_id: usize,
    ) -> Result<()> {
        self.pages[page_id].record_emit(encoder)
    }

    pub(crate) fn record_after_target_pages(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        object: bool,
    ) -> Result<()> {
        self.module.record(encoder)?;
        if object {
            self.object.record(encoder)
        } else {
            let artifact = self.module.output();
            artifact
                .length
                .copy_to(encoder, 0, &self.artifact_length_readback, 0, 4);
            Ok(())
        }
    }

    #[cfg(test)]
    fn record_after_counts(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_before_target_pages(encoder)?;
        for page in &self.pages {
            page.record_measure(encoder)?;
        }
        self.record_between_target_pages(encoder, false)?;
        for page in &self.pages {
            page.record_emit(encoder)?;
        }
        Ok(())
    }

    #[cfg(test)]
    fn record_counts(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        for count in &self.count_pages {
            count.record(encoder)?;
        }
        Ok(())
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

    fn words<const N: usize>(records: &[[u32; N]]) -> Vec<u8> {
        records
            .iter()
            .flat_map(|record| record.iter())
            .flat_map(|word| word.to_le_bytes())
            .collect()
    }

    fn read_words(device: &wgpu::Device, buffer: &LaniusBuffer<u8>) -> Vec<u32> {
        let slice = buffer.slice(..);
        map_readback_blocking(device, &slice, "Wasm LIR readback").unwrap();
        let mapped = slice.get_mapped_range();
        let result = mapped
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        drop(mapped);
        buffer.unmap();
        result
    }

    #[test]
    fn physical_gpu_runs_resident_semantic_to_scheduled_wasm_bytes() {
        let gpu = device::global();
        let capacities = LoweringCapacities {
            source_bytes: 8,
            tokens: 16,
            hir_nodes: 4,
            semantic_instructions: 8,
            call_arguments: 1,
            parameters: 4,
            aggregate_elements: 1,
            target_instructions: 10,
            artifact_bytes: 2048,
        };
        let graph = lowering_compiler_graph(capacities, LoweringTarget::Wasm).unwrap();
        let workspace =
            CompilerGraphWorkspace::new(&gpu.device, "test.wasm_stage", &graph).unwrap();
        let workspace_u32 = |name: &str, count: usize| -> LaniusBuffer<u32> {
            workspace
                .alias(&graph, graph.resource_id(name).unwrap(), count)
                .unwrap()
        };
        let semantic_status: LaniusBuffer<LoweringStatus> = workspace
            .alias(&graph, graph.resource_id("lowering.status").unwrap(), 1)
            .unwrap();
        let semantic_total =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.semantic_total", &[8]);
        let semantic_page_core = storage_ro_from_bytes::<SemanticLirCore>(
            &gpu.device,
            "test.wasm_stage.semantic_page_core",
            &words(&[
                [opcode::SEMANTIC_LIR_OP_CONST_I32, 3, 0, u32::MAX, 1, 0, 0],
                [opcode::SEMANTIC_LIR_OP_CONST_I32, 3, 0, u32::MAX, 0, 0, 0],
                [opcode::SEMANTIC_LIR_OP_ADD, 3, 0, u32::MAX, 2, 0, 0],
                [
                    opcode::SEMANTIC_LIR_OP_BRANCH_IF,
                    0,
                    0,
                    u32::MAX,
                    3,
                    opcode::SEMANTIC_LIR_FLAG_BRANCH_DEPTH_VALID
                        | opcode::SEMANTIC_LIR_FLAG_BRANCH_FALSE,
                    0,
                ],
                [opcode::SEMANTIC_LIR_OP_VALUE_GET, 7, 0, u32::MAX, 5, 0, 0],
                [opcode::SEMANTIC_LIR_OP_VALUE_SET, 3, 0, u32::MAX, 6, 0, 0],
                [opcode::SEMANTIC_LIR_OP_CALL_SYMBOL, 3, 0, u32::MAX, 7, 0, 0],
                [opcode::SEMANTIC_LIR_OP_RETURN, 0, 0, u32::MAX, 4, 0, 0],
            ]),
            8,
        );
        let semantic_page_operands = storage_ro_from_bytes::<SemanticLirOperands>(
            &gpu.device,
            "test.wasm_stage.semantic_page_operands",
            &words(&[
                [1, 9, u32::MAX, u32::MAX],
                [0, 7, u32::MAX, u32::MAX],
                [2, 1, 0, u32::MAX],
                [3, 2, 0, u32::MAX],
                [5, 4, u32::MAX, u32::MAX],
                [6, 8, 5, u32::MAX],
                [7, 7, 11, 23],
                [4, 2, u32::MAX, u32::MAX],
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
        semantic_order.write(&gpu.queue, 0, &words(&[[1u32, 0, 2, 3, 5, 6, 7, 4]]));
        let semantic_owners =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.semantic_owners", &[0; 8]);
        let semantic_ops = storage_ro_from_u32s(
            &gpu.device,
            "test.wasm_stage.semantic_ops",
            &[
                opcode::SEMANTIC_LIR_OP_CONST_I32,
                opcode::SEMANTIC_LIR_OP_CONST_I32,
                opcode::SEMANTIC_LIR_OP_ADD,
                opcode::SEMANTIC_LIR_OP_BRANCH_IF,
                opcode::SEMANTIC_LIR_OP_RETURN,
                opcode::SEMANTIC_LIR_OP_VALUE_GET,
                opcode::SEMANTIC_LIR_OP_VALUE_SET,
                opcode::SEMANTIC_LIR_OP_CALL_SYMBOL,
            ],
        );
        let semantic_call_args = storage_ro_from_bytes::<SemanticLirCallArg>(
            &gpu.device,
            "test.wasm_stage.semantic_call_args",
            &words(&[[u32::MAX; 4]]),
            1,
        );
        let semantic_call_arg_start = storage_ro_from_u32s(
            &gpu.device,
            "test.wasm_stage.call_arg_start",
            &[u32::MAX; 8],
        );
        let semantic_call_arg_count_by_hir = storage_ro_from_u32s(
            &gpu.device,
            "test.wasm_stage.call_arg_count_by_hir",
            &[0; 8],
        );
        let semantic_aggregate_elements = storage_ro_from_bytes::<SemanticLirAggregateElement>(
            &gpu.device,
            "test.wasm_stage.aggregate_elements",
            &words(&[[u32::MAX; 7]; 2]),
            2,
        );
        let semantic_string_rows = storage_ro_from_bytes::<SemanticLirString>(
            &gpu.device,
            "test.wasm_stage.strings",
            &words(&[[u32::MAX; 4]; 4]),
            4,
        );
        let semantic_empty_count =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.empty_count", &[0]);
        let semantic_string_data =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.string_data", &[0; 2]);
        let semantic_functions = storage_ro_from_bytes::<SemanticLirFunction>(
            &gpu.device,
            "test.wasm_stage.functions",
            &words(&[
                [0, 1, 0, 2, 0, 1, 0, 0, 2, 0, 0, 0, u32::MAX],
                [u32::MAX; 13],
                [u32::MAX; 13],
                [u32::MAX; 13],
            ]),
            4,
        );
        let semantic_params = storage_ro_from_bytes::<SemanticLirParam>(
            &gpu.device,
            "test.wasm_stage.params",
            &words(&[[0, 2, 0, 3], [0, 4, 1, 7], [u32::MAX; 4], [u32::MAX; 4]]),
            4,
        );
        let semantic_locals = storage_ro_from_bytes::<SemanticLirLocal>(
            &gpu.device,
            "test.wasm_stage.locals",
            &words(&[
                [0, 6, 0, 7],
                [0, 8, 1, 3],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
                [u32::MAX; 4],
            ]),
            8,
        );
        let semantic_function_count =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.function_count", &[1]);
        let semantic_param_count =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.param_count", &[2]);
        let semantic_local_count =
            storage_ro_from_u32s(&gpu.device, "test.wasm_stage.local_count", &[2]);
        let stage = GpuWasmLirStage::new(
            &gpu.device,
            &graph,
            &workspace,
            capacities,
            GpuSemanticLirView {
                count: &semantic_total,
                core: &semantic_page_core,
                operands: &semantic_page_operands,
                layout_word_offset: &semantic_owners,
                owner_by_instruction: &semantic_owners,
                op_by_instruction: &semantic_ops,
                function_id_by_hir: &semantic_owners,
                call_args: &semantic_call_args,
                call_arg_start_by_hir: &semantic_call_arg_start,
                call_arg_count_by_hir: &semantic_call_arg_count_by_hir,
                aggregate_elements: &semantic_aggregate_elements,
                aggregate_element_count: &semantic_empty_count,
                strings: &semantic_string_rows,
                string_count: &semantic_empty_count,
                string_data_words: &semantic_string_data,
                string_pool_len: &semantic_empty_count,
                functions: &semantic_functions,
                function_count: &semantic_function_count,
                params: &semantic_params,
                param_count: &semantic_param_count,
                locals: &semantic_locals,
                local_count: &semantic_local_count,
                execution_order: Some(&semantic_order),
                status: &semantic_status,
            },
        )
        .unwrap();
        let pipelines_before = pipeline_creation_count();
        let buffers_before = tracked_buffer_allocation_stats();
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.wasm_stage.encoder"),
            });
        stage.record_lir(&mut encoder).unwrap();
        assert_eq!(pipeline_creation_count(), pipelines_before);
        assert_eq!(tracked_buffer_allocation_stats(), buffers_before);

        let functions = stage.functions.output();
        let artifact = stage.module.output();
        let target_total = workspace_u32("lir.wasm.total", 1);
        let body_length = workspace_u32("lir.wasm.body_length", 1);
        let body_words = workspace_u32("lir.wasm.body_bytes", 16);
        let total_readback = readback_bytes(&gpu.device, "test.wasm_stage.total.rb", 4, 1);
        let core_readback = readback_bytes(&gpu.device, "test.wasm_stage.core.rb", 160, 40);
        let function_count_readback =
            readback_bytes(&gpu.device, "test.wasm_stage.function_count.rb", 4, 1);
        let functions_readback =
            readback_bytes(&gpu.device, "test.wasm_stage.functions.rb", 64, 16);
        let abi_functions_readback =
            readback_bytes(&gpu.device, "test.wasm_stage.abi_functions.rb", 224, 56);
        let artifact_length_readback =
            readback_bytes(&gpu.device, "test.wasm_stage.artifact_length.rb", 4, 1);
        let artifact_readback =
            readback_bytes(&gpu.device, "test.wasm_stage.artifact.rb", 2048, 512);
        let body_length_readback =
            readback_bytes(&gpu.device, "test.wasm_stage.body_length.rb", 4, 1);
        let body_readback = readback_bytes(&gpu.device, "test.wasm_stage.body.rb", 64, 16);
        target_total.copy_to(&mut encoder, 0, &total_readback, 0, 4);
        stage
            .instructions
            .copy_to(&mut encoder, 0, &core_readback, 0, 160);
        functions
            .count
            .copy_to(&mut encoder, 0, &function_count_readback, 0, 4);
        functions
            .rows
            .copy_to(&mut encoder, 0, &functions_readback, 0, 64);
        stage
            .abi_functions
            .copy_to(&mut encoder, 0, &abi_functions_readback, 0, 224);
        body_length.copy_to(&mut encoder, 0, &body_length_readback, 0, 4);
        body_words.copy_to(&mut encoder, 0, &body_readback, 0, 64);
        stage.module.record(&mut encoder).unwrap();
        artifact
            .length
            .copy_to(&mut encoder, 0, &artifact_length_readback, 0, 4);
        artifact
            .words
            .copy_to(&mut encoder, 0, &artifact_readback, 0, 2048);
        gpu.queue.submit(Some(encoder.finish()));

        let core = read_words(&gpu.device, &core_readback);
        assert_eq!(read_words(&gpu.device, &total_readback)[0], 10);
        assert_eq!(
            [
                core[0], core[4], core[8], core[12], core[16], core[20], core[24], core[28],
                core[32], core[36],
            ],
            [
                opcode::WASM_LIR_OP_I32_CONST,
                opcode::WASM_LIR_OP_I32_CONST,
                opcode::WASM_LIR_OP_I32_ADD,
                opcode::WASM_LIR_OP_I32_EQZ,
                opcode::WASM_LIR_OP_BRANCH_IF,
                opcode::WASM_LIR_OP_LOCAL_SET,
                opcode::WASM_LIR_OP_CALL_SYMBOL,
                opcode::WASM_LIR_OP_RETURN,
                opcode::WASM_LIR_OP_LOCAL_GET,
                opcode::WASM_LIR_OP_LOCAL_GET,
            ]
        );
        assert_eq!(core[21], 5);
        assert_eq!(core[33], 1);
        assert_eq!(core[37], 2);
        assert_eq!(
            core[23],
            1u32 << 8,
            "resolved local.set must remain supported"
        );
        assert_eq!(
            core[35],
            1u32 << 8,
            "the first word of a resolved string local.get must remain supported"
        );
        assert_eq!(
            core[39],
            1u32 << 8,
            "the second word of a resolved string local.get must remain supported"
        );
        assert_eq!(read_words(&gpu.device, &function_count_readback)[0], 1);
        assert_eq!(
            &read_words(&gpu.device, &functions_readback)[0..4],
            &[0, 0, 10, 0]
        );
        let abi = read_words(&gpu.device, &abi_functions_readback);
        assert_eq!(&abi[0..14], &[0, 10, 3, 3, 0, 10, 0, 21, 1, 0, 0, 2, 0, 2]);
        assert_eq!(read_words(&gpu.device, &body_length_readback)[0], 21);
        let body_bytes = read_words(&gpu.device, &body_readback)
            .into_iter()
            .flat_map(u32::to_le_bytes)
            .collect::<Vec<_>>();
        assert_eq!(
            &body_bytes[..21],
            &[
                opcode::WASM_LIR_OP_I32_CONST as u8,
                7,
                opcode::WASM_LIR_OP_I32_CONST as u8,
                9,
                opcode::WASM_LIR_OP_I32_ADD as u8,
                opcode::WASM_LIR_OP_I32_EQZ as u8,
                opcode::WASM_LIR_OP_BRANCH_IF as u8,
                0,
                opcode::WASM_LIR_OP_LOCAL_SET as u8,
                5,
                opcode::WASM_LIR_OP_CALL as u8,
                0x80,
                0x80,
                0x80,
                0x80,
                0,
                opcode::WASM_LIR_OP_RETURN as u8,
                opcode::WASM_LIR_OP_LOCAL_GET as u8,
                1,
                opcode::WASM_LIR_OP_LOCAL_GET as u8,
                2,
            ]
        );
        // The module includes the target runtime's memory and mutable heap-pointer
        // global in addition to the function/table/export/code sections.
        assert_eq!(read_words(&gpu.device, &artifact_length_readback)[0], 1020);
        let artifact_bytes = read_words(&gpu.device, &artifact_readback)
            .into_iter()
            .flat_map(u32::to_le_bytes)
            .collect::<Vec<_>>();
        assert_eq!(&artifact_bytes[..8], b"\0asm\x01\0\0\0");

        let allocations_before = tracked_buffer_allocation_stats();
        // A full compiler job regenerates semantic order before target lowering.
        // This target-only resident replay supplies the same input explicitly.
        semantic_order.write(&gpu.queue, 0, &words(&[[1u32, 0, 2, 3, 5, 6, 7, 4]]));
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.wasm_stage.resident_artifact.encoder"),
            });
        stage.record(&mut encoder).unwrap();
        assert_eq!(tracked_buffer_allocation_stats(), allocations_before);
        gpu.queue.submit(Some(encoder.finish()));
        let resident_artifact = stage.finish_artifact(&gpu.device, &gpu.queue).unwrap();
        assert_eq!(resident_artifact.len(), 1020);
        assert_eq!(&resident_artifact[..8], b"\0asm\x01\0\0\0");

        // Object projection is a separate recording mode over the same
        // resident lowering graph. This fixture has one public function and
        // one imported call, exercising definition, symbol, and relocation
        // compaction together.
        semantic_order.write(&gpu.queue, 0, &words(&[[1u32, 0, 2, 3, 5, 6, 7, 4]]));
        let object = stage.object();
        let object_counts = readback_bytes(&gpu.device, "test.wasm_object.counts.rb", 12, 3);
        let object_function = readback_bytes(&gpu.device, "test.wasm_object.function.rb", 24, 6);
        let object_definition =
            readback_bytes(&gpu.device, "test.wasm_object.definition.rb", 32, 8);
        let object_relocation =
            readback_bytes(&gpu.device, "test.wasm_object.relocation.rb", 32, 8);
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.wasm_object.encoder"),
            });
        stage
            .record_object(&gpu.queue, &mut encoder, 7, 11)
            .unwrap();
        object
            .relocation_count
            .copy_to(&mut encoder, 0, &object_counts, 0, 4);
        object
            .symbol_count
            .copy_to(&mut encoder, 0, &object_counts, 4, 4);
        object
            .definition_count
            .copy_to(&mut encoder, 0, &object_counts, 8, 4);
        object
            .functions
            .copy_to(&mut encoder, 0, &object_function, 0, 24);
        object
            .definitions
            .copy_to(&mut encoder, 0, &object_definition, 0, 32);
        object
            .relocations
            .copy_to(&mut encoder, 0, &object_relocation, 0, 32);
        gpu.queue.submit(Some(encoder.finish()));
        assert_eq!(read_words(&gpu.device, &object_counts), &[1, 1, 1]);
        assert_eq!(
            read_words(&gpu.device, &object_function),
            &[0, 14, 0, 56, 1, 1]
        );
        assert_eq!(
            read_words(&gpu.device, &object_definition),
            &[7, 11, 0, 0, 21, 0, 0, 0]
        );
        assert_eq!(
            read_words(&gpu.device, &object_relocation),
            &[45, 2, 0, 0, 7, 11, 23, 0]
        );
        let durable = stage.finish_object(&gpu.device, &gpu.queue, 7, 11).unwrap();
        assert_eq!(durable.functions.len(), 1);
        assert_eq!(durable.functions[0].symbol_index, 1);
        assert_eq!(durable.type_bytes.len(), 14);
        assert_eq!(durable.body_bytes.len(), 56);
        assert_eq!(durable.relocations.len(), 1);
        assert_eq!(durable.relocations[0].body_byte_offset, 45);
        assert_eq!(durable.relocations[0].target_index, 0);
        assert_eq!(durable.symbols.len(), 2);
        assert_eq!(durable.identity_bytes, words(&[[7, 11, 23], [7, 11, 0]]));
    }
}
