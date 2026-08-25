//! GPU-parallel Wasm module postprocessing over target LIR function records.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    lowering_ir::{LoweringCapacities, WasmLirFunction, WasmModuleLayout},
    optimization::GpuOptIrMetadataView,
    scan::{GpuResidentExclusiveScan, GraphScanContract},
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{CompilerGraph, CompilerGraphAllocations, CompilerGraphWorkspace},
    kernels::KernelRegistry,
    operations::ComputeOperation,
    resource_registry::ResourceMap,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmModuleParams {
    function_capacity: u32,
    artifact_capacity: u32,
    reserved0: u32,
    reserved1: u32,
}

pub(crate) struct GpuWasmModuleView<'a> {
    pub length: &'a LaniusBuffer<u32>,
    pub words: &'a LaniusBuffer<u32>,
}

#[derive(Clone, Copy)]
pub(crate) struct GpuWasmModuleObjectView<'a> {
    pub type_total: &'a LaniusBuffer<u32>,
    pub code_total: &'a LaniusBuffer<u32>,
    pub layout: &'a LaniusBuffer<WasmModuleLayout>,
}

pub(crate) struct GpuWasmModuleStage {
    clear: ComputeOperation,
    lengths: ComputeOperation,
    layout: ComputeOperation,
    headers: ComputeOperation,
    functions: ComputeOperation,
    type_scan: GpuResidentExclusiveScan,
    code_scan: GpuResidentExclusiveScan,
    _params: LaniusBuffer<WasmModuleParams>,
    _type_lengths: LaniusBuffer<u32>,
    _type_offsets: LaniusBuffer<u32>,
    _type_total: LaniusBuffer<u32>,
    _code_lengths: LaniusBuffer<u32>,
    _code_offsets: LaniusBuffer<u32>,
    _code_total: LaniusBuffer<u32>,
    _entrypoint_state: LaniusBuffer<u32>,
    _layout: LaniusBuffer<WasmModuleLayout>,
    length: LaniusBuffer<u32>,
    words: LaniusBuffer<u32>,
}

impl GpuWasmModuleStage {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        capacities: LoweringCapacities,
        metadata: GpuOptIrMetadataView<'_>,
        functions: &LaniusBuffer<WasmLirFunction>,
        body_words: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        let function_capacity = capacities.hir_nodes.max(1);
        let artifact_capacity = capacities.artifact_bytes.max(1);
        let resource = |name: &str| {
            graph
                .resource_id(name)
                .with_context(|| format!("Wasm module graph is missing {name}"))
        };
        let alias_u32 = |name: &str, count: u32| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(graph, resource(name)?, count.max(1) as usize)
                .map_err(anyhow::Error::msg)
        };
        let type_lengths = alias_u32("lir.wasm.module.type_lengths", function_capacity)?;
        let type_offsets = alias_u32("lir.wasm.module.type_offsets", function_capacity)?;
        let type_total = alias_u32("lir.wasm.module.type_total", 1)?;
        let code_lengths = alias_u32("lir.wasm.module.code_lengths", function_capacity)?;
        let code_offsets = alias_u32("lir.wasm.module.code_offsets", function_capacity)?;
        let code_total = alias_u32("lir.wasm.module.code_total", 1)?;
        let entrypoint_state = alias_u32("lir.wasm.module.entrypoint_state", 2)?;
        let layout = workspace
            .alias(graph, resource("lir.wasm.module.layout")?, 1)
            .map_err(anyhow::Error::msg)?;
        let length = alias_u32("artifact.wasm.length", 1)?;
        let words = alias_u32("artifact.wasm.bytes", artifact_capacity.div_ceil(4))?;
        let params = uniform_from_val(
            device,
            "lir.wasm.module.params",
            &WasmModuleParams {
                function_capacity,
                artifact_capacity,
                reserved0: capacities.source_bytes.max(16 * 65_536).div_ceil(65_536),
                reserved1: 0,
            },
        );
        let mut resources = ResourceMap::new();
        metadata.register(graph, &mut resources)?;
        resources.graph_buffer(graph, "lir.wasm.functions", functions)?;
        resources.graph_buffer(graph, "lir.wasm.body_bytes", body_words)?;
        resources.graph_buffer(graph, "lir.wasm.module.type_lengths", &type_lengths)?;
        resources.graph_buffer(graph, "lir.wasm.module.type_offsets", &type_offsets)?;
        resources.graph_buffer(graph, "lir.wasm.module.type_total", &type_total)?;
        resources.graph_buffer(graph, "lir.wasm.module.code_lengths", &code_lengths)?;
        resources.graph_buffer(graph, "lir.wasm.module.code_offsets", &code_offsets)?;
        resources.graph_buffer(graph, "lir.wasm.module.code_total", &code_total)?;
        resources.graph_buffer(graph, "lir.wasm.module.entrypoint_state", &entrypoint_state)?;
        resources.graph_buffer(graph, "lir.wasm.module.layout", &layout)?;
        resources.graph_buffer(graph, "artifact.wasm.length", &length)?;
        resources.graph_buffer(graph, "artifact.wasm.bytes", &words)?;
        let context = (graph, allocations);
        let clear = ComputeOperation::direct(
            device,
            &context,
            &resources,
            "lir.wasm.module.state_clear",
            kernels.kernel("codegen/lir/wasm/module_state_clear"),
            1,
        )?;
        let lengths = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.wasm.module.lengths",
            kernels.kernel("codegen/lir/wasm/module_lengths"),
            &params,
            function_capacity,
        )?;
        let type_scan = GpuResidentExclusiveScan::new(
            device,
            kernels,
            graph,
            workspace,
            allocations,
            GraphScanContract {
                local_pass: "lir.wasm.module.type_scan.local",
                up_pass: "lir.wasm.module.type_scan.hierarchy_up",
                down_pass: "lir.wasm.module.type_scan.hierarchy_down",
                apply_pass: "lir.wasm.module.type_scan.apply",
                count: "lir.semantic.function_total",
                input: "lir.wasm.module.type_lengths",
                local: "lir.wasm.module.type_scan_local",
                block_sum: "lir.wasm.module.type_scan_block_sum",
                block_prefix: "lir.wasm.module.type_scan_block_prefix",
                hierarchy: "lir.wasm.module.type_scan_hierarchy",
                output: "lir.wasm.module.type_offsets",
                total: "lir.wasm.module.type_total",
            },
            function_capacity,
            metadata.function_count,
            &type_lengths,
            &type_offsets,
            &type_total,
        )?;
        let code_scan = GpuResidentExclusiveScan::new(
            device,
            kernels,
            graph,
            workspace,
            allocations,
            GraphScanContract {
                local_pass: "lir.wasm.module.code_scan.local",
                up_pass: "lir.wasm.module.code_scan.hierarchy_up",
                down_pass: "lir.wasm.module.code_scan.hierarchy_down",
                apply_pass: "lir.wasm.module.code_scan.apply",
                count: "lir.semantic.function_total",
                input: "lir.wasm.module.code_lengths",
                local: "lir.wasm.module.code_scan_local",
                block_sum: "lir.wasm.module.code_scan_block_sum",
                block_prefix: "lir.wasm.module.code_scan_block_prefix",
                hierarchy: "lir.wasm.module.code_scan_hierarchy",
                output: "lir.wasm.module.code_offsets",
                total: "lir.wasm.module.code_total",
            },
            function_capacity,
            metadata.function_count,
            &code_lengths,
            &code_offsets,
            &code_total,
        )?;
        let layout_operation = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.wasm.module.layout",
            kernels.kernel("codegen/lir/wasm/module_layout"),
            &params,
            1,
        )?;
        let headers = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.wasm.module.emit_headers",
            kernels.kernel("codegen/lir/wasm/module_emit_headers"),
            &params,
            artifact_capacity,
        )?;
        let function_emission = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "lir.wasm.module.emit_functions",
            kernels.kernel("codegen/lir/wasm/module_emit_functions"),
            &params,
            function_capacity,
        )?;

        Ok(Self {
            clear,
            lengths,
            layout: layout_operation,
            headers,
            functions: function_emission,
            type_scan,
            code_scan,
            _params: params,
            _type_lengths: type_lengths,
            _type_offsets: type_offsets,
            _type_total: type_total,
            _code_lengths: code_lengths,
            _code_offsets: code_offsets,
            _code_total: code_total,
            _entrypoint_state: entrypoint_state,
            _layout: layout,
            length,
            words,
        })
    }

    pub(crate) fn output(&self) -> GpuWasmModuleView<'_> {
        GpuWasmModuleView {
            length: &self.length,
            words: &self.words,
        }
    }

    pub(crate) fn object_projection_inputs(&self) -> GpuWasmModuleObjectView<'_> {
        GpuWasmModuleObjectView {
            type_total: &self._type_total,
            code_total: &self._code_total,
            layout: &self._layout,
        }
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.clear.record(encoder)?;
        self.lengths.record(encoder)?;
        self.type_scan.record(encoder)?;
        self.code_scan.record(encoder)?;
        self.layout.record(encoder)?;
        self.headers.record(encoder)?;
        self.functions.record(encoder)
    }
}
