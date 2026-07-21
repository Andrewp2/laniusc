//! GPU-parallel Wasm module postprocessing over target LIR function records.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    lowering::{GpuSemanticLirView, bound, make_group, record_direct},
    lowering_ir::{LoweringCapacities, WasmLirFunction, WasmModuleLayout},
    scan::{GpuResidentExclusiveScan, GraphScanContract},
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{
        BoundGraphResource,
        CompilerGraph,
        CompilerGraphAllocations,
        CompilerGraphWorkspace,
    },
    passes_core::{PassData, make_pass_data_from_shader_key},
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

pub(crate) struct GpuWasmModuleStage {
    function_capacity: u32,
    artifact_capacity: u32,
    clear_pass: PassData,
    lengths_pass: PassData,
    layout_pass: PassData,
    headers_pass: PassData,
    functions_pass: PassData,
    clear_group: wgpu::BindGroup,
    lengths_group: wgpu::BindGroup,
    layout_group: wgpu::BindGroup,
    headers_group: wgpu::BindGroup,
    functions_group: wgpu::BindGroup,
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
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        capacities: LoweringCapacities,
        semantic: GpuSemanticLirView<'_>,
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
                reserved0: 0,
                reserved1: 0,
            },
        );
        let clear_pass = load(
            device,
            "lir.wasm.module.state_clear",
            "codegen/lir/wasm/module_state_clear",
        )?;
        let lengths_pass = load(
            device,
            "lir.wasm.module.lengths",
            "codegen/lir/wasm/module_lengths",
        )?;
        let layout_pass = load(
            device,
            "lir.wasm.module.layout",
            "codegen/lir/wasm/module_layout",
        )?;
        let headers_pass = load(
            device,
            "lir.wasm.module.emit_headers",
            "codegen/lir/wasm/module_emit_headers",
        )?;
        let functions_pass = load(
            device,
            "lir.wasm.module.emit_functions",
            "codegen/lir/wasm/module_emit_functions",
        )?;
        let clear_group = make_group(
            device,
            &clear_pass,
            "lir.wasm.module.state_clear.bind_group",
            &[(
                "wasm_module_entrypoint_state",
                entrypoint_state.as_entire_binding(),
            )],
        )?;
        let lengths_group = make_group(
            device,
            &lengths_pass,
            "lir.wasm.module.lengths.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "wasm_lir_function_total",
                    semantic.function_count.as_entire_binding(),
                ),
                ("wasm_lir_functions", functions.as_entire_binding()),
                ("wasm_type_entry_length", type_lengths.as_entire_binding()),
                ("wasm_code_entry_length", code_lengths.as_entire_binding()),
                (
                    "wasm_module_entrypoint_state",
                    entrypoint_state.as_entire_binding(),
                ),
            ],
        )?;
        let type_scan = GpuResidentExclusiveScan::new(
            device,
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
            semantic.function_count,
            &type_lengths,
            &type_offsets,
            &type_total,
        )?;
        let code_scan = GpuResidentExclusiveScan::new(
            device,
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
            semantic.function_count,
            &code_lengths,
            &code_offsets,
            &code_total,
        )?;
        let layout_group = make_group(
            device,
            &layout_pass,
            "lir.wasm.module.layout.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "wasm_lir_function_total",
                    semantic.function_count.as_entire_binding(),
                ),
                ("wasm_type_entries_length", type_total.as_entire_binding()),
                ("wasm_code_entries_length", code_total.as_entire_binding()),
                (
                    "wasm_module_entrypoint_state",
                    entrypoint_state.as_entire_binding(),
                ),
                ("wasm_module_layout", layout.as_entire_binding()),
                ("wasm_module_length", length.as_entire_binding()),
                ("lowering_status", semantic.status.as_entire_binding()),
            ],
        )?;
        let headers_group = make_group(
            device,
            &headers_pass,
            "lir.wasm.module.emit_headers.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                ("wasm_module_layout", layout.as_entire_binding()),
                ("wasm_module_bytes", words.as_entire_binding()),
            ],
        )?;
        let functions_group = make_group(
            device,
            &functions_pass,
            "lir.wasm.module.emit_functions.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "wasm_lir_function_total",
                    semantic.function_count.as_entire_binding(),
                ),
                ("wasm_lir_functions", functions.as_entire_binding()),
                ("semantic_lir_params", semantic.params.as_entire_binding()),
                ("semantic_lir_locals", semantic.locals.as_entire_binding()),
                ("wasm_type_entry_offset", type_offsets.as_entire_binding()),
                ("wasm_code_entry_offset", code_offsets.as_entire_binding()),
                ("wasm_body_bytes", body_words.as_entire_binding()),
                ("wasm_module_layout", layout.as_entire_binding()),
                ("wasm_module_bytes", words.as_entire_binding()),
            ],
        )?;

        validate(
            graph,
            allocations,
            semantic,
            functions,
            body_words,
            &type_lengths,
            &type_offsets,
            &type_total,
            &code_lengths,
            &code_offsets,
            &code_total,
            &entrypoint_state,
            &layout,
            &length,
            &words,
            semantic.status,
        )?;

        Ok(Self {
            function_capacity,
            artifact_capacity,
            clear_pass,
            lengths_pass,
            layout_pass,
            headers_pass,
            functions_pass,
            clear_group,
            lengths_group,
            layout_group,
            headers_group,
            functions_group,
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

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        record_direct(encoder, &self.clear_pass, &self.clear_group, 1)?;
        record_direct(
            encoder,
            &self.lengths_pass,
            &self.lengths_group,
            self.function_capacity,
        )?;
        self.type_scan.record(encoder)?;
        self.code_scan.record(encoder)?;
        record_direct(encoder, &self.layout_pass, &self.layout_group, 1)?;
        record_direct(
            encoder,
            &self.headers_pass,
            &self.headers_group,
            self.artifact_capacity,
        )?;
        record_direct(
            encoder,
            &self.functions_pass,
            &self.functions_group,
            self.function_capacity,
        )
    }
}

fn load(device: &wgpu::Device, label: &str, shader: &str) -> Result<PassData> {
    make_pass_data_from_shader_key(device, label, "main", shader)
}

#[allow(clippy::too_many_arguments)]
fn validate(
    graph: &CompilerGraph,
    allocations: &CompilerGraphAllocations,
    semantic: GpuSemanticLirView<'_>,
    functions: &LaniusBuffer<WasmLirFunction>,
    body_words: &LaniusBuffer<u32>,
    type_lengths: &LaniusBuffer<u32>,
    type_offsets: &LaniusBuffer<u32>,
    type_total: &LaniusBuffer<u32>,
    code_lengths: &LaniusBuffer<u32>,
    code_offsets: &LaniusBuffer<u32>,
    code_total: &LaniusBuffer<u32>,
    entrypoint_state: &LaniusBuffer<u32>,
    layout: &LaniusBuffer<WasmModuleLayout>,
    length: &LaniusBuffer<u32>,
    words: &LaniusBuffer<u32>,
    status: &LaniusBuffer<super::lowering_ir::LoweringStatus>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    let run = |pass: &str, bindings: Vec<BoundGraphResource>| {
        allocations
            .validate_pass_bindings(graph, graph.pass_id(pass).unwrap(), &bindings)
            .map_err(anyhow::Error::msg)
    };
    run(
        "lir.wasm.module.state_clear",
        vec![bound(
            "wasm_module_entrypoint_state",
            resource("lir.wasm.module.entrypoint_state"),
            entrypoint_state,
        )?],
    )?;
    run(
        "lir.wasm.module.lengths",
        vec![
            bound(
                "wasm_lir_function_total",
                resource("lir.semantic.function_total"),
                semantic.function_count,
            )?,
            bound(
                "wasm_lir_functions",
                resource("lir.wasm.functions"),
                functions,
            )?,
            bound(
                "wasm_type_entry_length",
                resource("lir.wasm.module.type_lengths"),
                type_lengths,
            )?,
            bound(
                "wasm_code_entry_length",
                resource("lir.wasm.module.code_lengths"),
                code_lengths,
            )?,
            bound(
                "wasm_module_entrypoint_state",
                resource("lir.wasm.module.entrypoint_state"),
                entrypoint_state,
            )?,
        ],
    )?;
    run(
        "lir.wasm.module.layout",
        vec![
            bound(
                "wasm_lir_function_total",
                resource("lir.semantic.function_total"),
                semantic.function_count,
            )?,
            bound(
                "wasm_type_entries_length",
                resource("lir.wasm.module.type_total"),
                type_total,
            )?,
            bound(
                "wasm_code_entries_length",
                resource("lir.wasm.module.code_total"),
                code_total,
            )?,
            bound(
                "wasm_module_entrypoint_state",
                resource("lir.wasm.module.entrypoint_state"),
                entrypoint_state,
            )?,
            bound(
                "wasm_module_layout",
                resource("lir.wasm.module.layout"),
                layout,
            )?,
            bound(
                "wasm_module_length",
                resource("artifact.wasm.length"),
                length,
            )?,
            bound("lowering_status", resource("lowering.status"), status)?,
        ],
    )?;
    run(
        "lir.wasm.module.emit_headers",
        vec![
            bound(
                "wasm_module_layout",
                resource("lir.wasm.module.layout"),
                layout,
            )?,
            bound("wasm_module_bytes", resource("artifact.wasm.bytes"), words)?,
        ],
    )?;
    run(
        "lir.wasm.module.emit_functions",
        vec![
            bound(
                "wasm_lir_function_total",
                resource("lir.semantic.function_total"),
                semantic.function_count,
            )?,
            bound(
                "wasm_lir_functions",
                resource("lir.wasm.functions"),
                functions,
            )?,
            bound(
                "semantic_lir_params",
                resource("lir.semantic.params"),
                semantic.params,
            )?,
            bound(
                "semantic_lir_locals",
                resource("lir.semantic.locals"),
                semantic.locals,
            )?,
            bound(
                "wasm_type_entry_offset",
                resource("lir.wasm.module.type_offsets"),
                type_offsets,
            )?,
            bound(
                "wasm_code_entry_offset",
                resource("lir.wasm.module.code_offsets"),
                code_offsets,
            )?,
            bound(
                "wasm_body_bytes",
                resource("lir.wasm.body_bytes"),
                body_words,
            )?,
            bound(
                "wasm_module_layout",
                resource("lir.wasm.module.layout"),
                layout,
            )?,
            bound("wasm_module_bytes", resource("artifact.wasm.bytes"), words)?,
        ],
    )
}
