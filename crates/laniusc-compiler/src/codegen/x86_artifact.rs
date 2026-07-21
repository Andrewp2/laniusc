//! GPU-parallel x86_64 stack-location lowering and ELF byte emission.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    functions::GpuTargetFunctionView,
    lowering::{GpuSemanticLirView, bound, make_group, record_direct},
    lowering_ir::{LoweringCapacities, X86ArtifactLayout, X86LirCore, X86LirOperands},
    scan::{GpuResidentExclusiveScan, GraphScanContract},
};
use crate::gpu::{
    buffers::{LaniusBuffer, readback_bytes, uniform_from_val},
    compiler_graph::{
        BoundGraphResource,
        CompilerGraph,
        CompilerGraphAllocations,
        CompilerGraphWorkspace,
    },
    passes_core::{PassData, make_pass_data_from_shader_key, map_readback_blocking},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct X86ArtifactParams {
    target_capacity: u32,
    token_capacity: u32,
    function_capacity: u32,
    artifact_capacity: u32,
}

pub(crate) struct GpuX86ArtifactView<'a> {
    pub length: &'a LaniusBuffer<u32>,
    pub words: &'a LaniusBuffer<u32>,
}

pub(crate) struct GpuX86ArtifactStage {
    target_capacity: u32,
    function_capacity: u32,
    artifact_capacity: u32,
    byte_count_pass: PassData,
    entrypoint_clear_pass: PassData,
    entrypoint_reduce_pass: PassData,
    layout_pass: PassData,
    clear_pass: PassData,
    emit_pass: PassData,
    byte_count_group: wgpu::BindGroup,
    entrypoint_clear_group: wgpu::BindGroup,
    entrypoint_reduce_group: wgpu::BindGroup,
    layout_group: wgpu::BindGroup,
    clear_group: wgpu::BindGroup,
    emit_group: wgpu::BindGroup,
    byte_scan: GpuResidentExclusiveScan,
    _params: LaniusBuffer<X86ArtifactParams>,
    _byte_lengths: LaniusBuffer<u32>,
    _byte_offsets: LaniusBuffer<u32>,
    _body_length: LaniusBuffer<u32>,
    _entrypoint_state: LaniusBuffer<u32>,
    _layout: LaniusBuffer<X86ArtifactLayout>,
    length: LaniusBuffer<u32>,
    words: LaniusBuffer<u32>,
    length_readback: LaniusBuffer<u8>,
    artifact_readback: LaniusBuffer<u8>,
}

impl GpuX86ArtifactStage {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        device: &wgpu::Device,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        capacities: LoweringCapacities,
        semantic: GpuSemanticLirView<'_>,
        total: &LaniusBuffer<u32>,
        core: &LaniusBuffer<X86LirCore>,
        operands: &LaniusBuffer<X86LirOperands>,
        scheduled_function_ids: &LaniusBuffer<u32>,
        functions: GpuTargetFunctionView<'_>,
        frame_slot_by_decl_token: &LaniusBuffer<u32>,
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
        let params = uniform_from_val(
            device,
            "lir.x86.artifact.params",
            &X86ArtifactParams {
                target_capacity,
                token_capacity: capacities
                    .tokens
                    .saturating_add(capacities.hir_nodes)
                    .max(1),
                function_capacity: capacities.hir_nodes.max(1),
                artifact_capacity,
            },
        );

        let byte_count_pass = load(device, "lir.x86.byte_count", "codegen/lir/x86/byte_count")?;
        let entrypoint_clear_pass = load(
            device,
            "lir.x86.entrypoint.clear",
            "codegen/lir/x86/entrypoint_clear",
        )?;
        let entrypoint_reduce_pass = load(
            device,
            "lir.x86.entrypoint.reduce",
            "codegen/lir/x86/entrypoint_reduce",
        )?;
        let layout_pass = load(
            device,
            "lir.x86.artifact.layout",
            "codegen/lir/x86/artifact_layout",
        )?;
        let clear_pass = load(
            device,
            "lir.x86.artifact.clear",
            "codegen/lir/x86/artifact_clear",
        )?;
        let emit_pass = load(device, "lir.x86.emit", "codegen/lir/x86/emit")?;

        let byte_count_group = make_group(
            device,
            &byte_count_pass,
            "lir.x86.byte_count.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                ("target_lir_total", total.as_entire_binding()),
                ("target_lir_core", core.as_entire_binding()),
                ("target_lir_operands", operands.as_entire_binding()),
                (
                    "scheduled_function_id",
                    scheduled_function_ids.as_entire_binding(),
                ),
                ("target_function_count", functions.count.as_entire_binding()),
                ("target_functions", functions.rows.as_entire_binding()),
                (
                    "target_function_index_by_semantic",
                    functions.index_by_semantic.as_entire_binding(),
                ),
                (
                    "semantic_lir_function_total",
                    semantic.function_count.as_entire_binding(),
                ),
                (
                    "semantic_lir_functions",
                    semantic.functions.as_entire_binding(),
                ),
                ("target_byte_length", byte_lengths.as_entire_binding()),
                ("lowering_status", semantic.status.as_entire_binding()),
            ],
        )?;
        let byte_scan = GpuResidentExclusiveScan::new(
            device,
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
        let entrypoint_clear_group = make_group(
            device,
            &entrypoint_clear_pass,
            "lir.x86.entrypoint.clear.bind_group",
            &[("x86_entrypoint_state", entrypoint_state.as_entire_binding())],
        )?;
        let entrypoint_reduce_group = make_group(
            device,
            &entrypoint_reduce_pass,
            "lir.x86.entrypoint.reduce.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "semantic_lir_function_total",
                    semantic.function_count.as_entire_binding(),
                ),
                (
                    "semantic_lir_functions",
                    semantic.functions.as_entire_binding(),
                ),
                ("x86_entrypoint_state", entrypoint_state.as_entire_binding()),
            ],
        )?;
        let layout_group = make_group(
            device,
            &layout_pass,
            "lir.x86.artifact.layout.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                ("x86_body_length", body_length.as_entire_binding()),
                ("x86_entrypoint_state", entrypoint_state.as_entire_binding()),
                ("target_function_count", functions.count.as_entire_binding()),
                ("target_functions", functions.rows.as_entire_binding()),
                (
                    "target_function_index_by_semantic",
                    functions.index_by_semantic.as_entire_binding(),
                ),
                ("target_byte_offset", byte_offsets.as_entire_binding()),
                ("x86_artifact_layout", layout.as_entire_binding()),
                ("x86_artifact_length", length.as_entire_binding()),
                ("lowering_status", semantic.status.as_entire_binding()),
            ],
        )?;
        let clear_group = make_group(
            device,
            &clear_pass,
            "lir.x86.artifact.clear.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                ("artifact_bytes", words.as_entire_binding()),
            ],
        )?;
        let emit_group = make_group(
            device,
            &emit_pass,
            "lir.x86.emit.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                ("target_lir_total", total.as_entire_binding()),
                ("target_lir_core", core.as_entire_binding()),
                ("target_lir_operands", operands.as_entire_binding()),
                (
                    "scheduled_function_id",
                    scheduled_function_ids.as_entire_binding(),
                ),
                ("target_function_count", functions.count.as_entire_binding()),
                ("target_functions", functions.rows.as_entire_binding()),
                (
                    "target_function_index_by_semantic",
                    functions.index_by_semantic.as_entire_binding(),
                ),
                (
                    "semantic_lir_function_total",
                    semantic.function_count.as_entire_binding(),
                ),
                (
                    "semantic_lir_functions",
                    semantic.functions.as_entire_binding(),
                ),
                (
                    "x86_frame_slot_by_decl_token",
                    frame_slot_by_decl_token.as_entire_binding(),
                ),
                ("target_byte_length", byte_lengths.as_entire_binding()),
                ("target_byte_offset", byte_offsets.as_entire_binding()),
                ("x86_artifact_layout", layout.as_entire_binding()),
                ("artifact_bytes", words.as_entire_binding()),
            ],
        )?;

        validate(
            graph,
            allocations,
            semantic,
            total,
            core,
            operands,
            scheduled_function_ids,
            functions,
            frame_slot_by_decl_token,
            &byte_lengths,
            &byte_offsets,
            &body_length,
            &entrypoint_state,
            &layout,
            &length,
            &words,
        )?;

        let length_readback = readback_bytes(device, "artifact.x86.length.readback", 4, 4);
        let artifact_readback = readback_bytes(
            device,
            "artifact.x86.bytes.readback",
            artifact_capacity as usize,
            artifact_capacity as usize,
        );
        Ok(Self {
            target_capacity,
            function_capacity: capacities.hir_nodes.max(1),
            artifact_capacity,
            byte_count_pass,
            entrypoint_clear_pass,
            entrypoint_reduce_pass,
            layout_pass,
            clear_pass,
            emit_pass,
            byte_count_group,
            entrypoint_clear_group,
            entrypoint_reduce_group,
            layout_group,
            clear_group,
            emit_group,
            byte_scan,
            _params: params,
            _byte_lengths: byte_lengths,
            _byte_offsets: byte_offsets,
            _body_length: body_length,
            _entrypoint_state: entrypoint_state,
            _layout: layout,
            length,
            words,
            length_readback,
            artifact_readback,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        record_direct(
            encoder,
            &self.byte_count_pass,
            &self.byte_count_group,
            self.target_capacity,
        )?;
        self.byte_scan.record(encoder)?;
        record_direct(
            encoder,
            &self.entrypoint_clear_pass,
            &self.entrypoint_clear_group,
            1,
        )?;
        record_direct(
            encoder,
            &self.entrypoint_reduce_pass,
            &self.entrypoint_reduce_group,
            self.function_capacity,
        )?;
        record_direct(encoder, &self.layout_pass, &self.layout_group, 1)?;
        record_direct(
            encoder,
            &self.clear_pass,
            &self.clear_group,
            self.artifact_capacity.div_ceil(4),
        )?;
        record_direct(
            encoder,
            &self.emit_pass,
            &self.emit_group,
            self.target_capacity,
        )?;
        encoder.copy_buffer_to_buffer(&self.length.buffer, 0, &self.length_readback.buffer, 0, 4);
        encoder.copy_buffer_to_buffer(
            &self.words.buffer,
            0,
            &self.artifact_readback.buffer,
            0,
            self.artifact_capacity as u64,
        );
        Ok(())
    }

    pub(crate) fn output(&self) -> GpuX86ArtifactView<'_> {
        GpuX86ArtifactView {
            length: &self.length,
            words: &self.words,
        }
    }

    pub(crate) fn finish(&self, device: &wgpu::Device) -> Result<Vec<u8>> {
        let length_slice = self.length_readback.slice(..);
        map_readback_blocking(device, &length_slice, "x86 artifact length readback")?;
        let mapped = length_slice.get_mapped_range();
        let length = u32::from_le_bytes(mapped[..4].try_into().unwrap()) as usize;
        drop(mapped);
        self.length_readback.unmap();
        if length > self.artifact_readback.byte_size {
            anyhow::bail!(
                "GPU x86 artifact requires {length} bytes but the daemon workspace provides {}",
                self.artifact_readback.byte_size,
            );
        }
        let artifact_slice = self.artifact_readback.slice(..);
        map_readback_blocking(device, &artifact_slice, "x86 artifact byte readback")?;
        let mapped = artifact_slice.get_mapped_range();
        let bytes = mapped[..length].to_vec();
        drop(mapped);
        self.artifact_readback.unmap();
        Ok(bytes)
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
    total: &LaniusBuffer<u32>,
    core: &LaniusBuffer<X86LirCore>,
    operands: &LaniusBuffer<X86LirOperands>,
    function_ids: &LaniusBuffer<u32>,
    functions: GpuTargetFunctionView<'_>,
    frame_slots: &LaniusBuffer<u32>,
    byte_lengths: &LaniusBuffer<u32>,
    byte_offsets: &LaniusBuffer<u32>,
    body_length: &LaniusBuffer<u32>,
    entrypoint_state: &LaniusBuffer<u32>,
    layout: &LaniusBuffer<X86ArtifactLayout>,
    length: &LaniusBuffer<u32>,
    words: &LaniusBuffer<u32>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    let run = |pass: &str, bindings: Vec<BoundGraphResource>| {
        allocations
            .validate_pass_bindings(graph, graph.pass_id(pass).unwrap(), &bindings)
            .map_err(anyhow::Error::msg)
    };
    run(
        "lir.x86.byte_count",
        vec![
            bound("target_lir_total", resource("lir.x86.total"), total)?,
            bound("target_lir_core", resource("lir.x86.core"), core)?,
            bound(
                "target_lir_operands",
                resource("lir.x86.operands"),
                operands,
            )?,
            bound(
                "scheduled_function_id",
                resource("lir.target.scheduled_function_ids"),
                function_ids,
            )?,
            bound(
                "target_function_count",
                resource("lir.target.function_count"),
                functions.count,
            )?,
            bound(
                "target_functions",
                resource("lir.target.functions"),
                functions.rows,
            )?,
            bound(
                "target_function_index_by_semantic",
                resource("lir.target.function_index_by_semantic"),
                functions.index_by_semantic,
            )?,
            bound(
                "semantic_lir_function_total",
                resource("lir.semantic.function_total"),
                semantic.function_count,
            )?,
            bound(
                "semantic_lir_functions",
                resource("lir.semantic.functions"),
                semantic.functions,
            )?,
            bound(
                "target_byte_length",
                resource("lir.x86.byte_lengths"),
                byte_lengths,
            )?,
            bound(
                "lowering_status",
                resource("lowering.status"),
                semantic.status,
            )?,
        ],
    )?;
    run(
        "lir.x86.entrypoint.clear",
        vec![bound(
            "x86_entrypoint_state",
            resource("lir.x86.entrypoint_state"),
            entrypoint_state,
        )?],
    )?;
    run(
        "lir.x86.entrypoint.reduce",
        vec![
            bound(
                "semantic_lir_function_total",
                resource("lir.semantic.function_total"),
                semantic.function_count,
            )?,
            bound(
                "semantic_lir_functions",
                resource("lir.semantic.functions"),
                semantic.functions,
            )?,
            bound(
                "x86_entrypoint_state",
                resource("lir.x86.entrypoint_state"),
                entrypoint_state,
            )?,
        ],
    )?;
    run(
        "lir.x86.artifact.layout",
        vec![
            bound(
                "x86_body_length",
                resource("lir.x86.body_length"),
                body_length,
            )?,
            bound(
                "x86_entrypoint_state",
                resource("lir.x86.entrypoint_state"),
                entrypoint_state,
            )?,
            bound(
                "target_function_count",
                resource("lir.target.function_count"),
                functions.count,
            )?,
            bound(
                "target_functions",
                resource("lir.target.functions"),
                functions.rows,
            )?,
            bound(
                "target_function_index_by_semantic",
                resource("lir.target.function_index_by_semantic"),
                functions.index_by_semantic,
            )?,
            bound(
                "target_byte_offset",
                resource("lir.x86.byte_offsets"),
                byte_offsets,
            )?,
            bound(
                "x86_artifact_layout",
                resource("lir.x86.artifact_layout"),
                layout,
            )?,
            bound(
                "x86_artifact_length",
                resource("artifact.x86.length"),
                length,
            )?,
            bound(
                "lowering_status",
                resource("lowering.status"),
                semantic.status,
            )?,
        ],
    )?;
    run(
        "lir.x86.artifact.clear",
        vec![bound(
            "artifact_bytes",
            resource("artifact.x86.bytes"),
            words,
        )?],
    )?;
    run(
        "lir.x86.emit",
        vec![
            bound("target_lir_total", resource("lir.x86.total"), total)?,
            bound("target_lir_core", resource("lir.x86.core"), core)?,
            bound(
                "target_lir_operands",
                resource("lir.x86.operands"),
                operands,
            )?,
            bound(
                "scheduled_function_id",
                resource("lir.target.scheduled_function_ids"),
                function_ids,
            )?,
            bound(
                "target_function_count",
                resource("lir.target.function_count"),
                functions.count,
            )?,
            bound(
                "target_functions",
                resource("lir.target.functions"),
                functions.rows,
            )?,
            bound(
                "target_function_index_by_semantic",
                resource("lir.target.function_index_by_semantic"),
                functions.index_by_semantic,
            )?,
            bound(
                "semantic_lir_function_total",
                resource("lir.semantic.function_total"),
                semantic.function_count,
            )?,
            bound(
                "semantic_lir_functions",
                resource("lir.semantic.functions"),
                semantic.functions,
            )?,
            bound(
                "x86_frame_slot_by_decl_token",
                resource("lir.x86.frame_slot_by_decl_token"),
                frame_slots,
            )?,
            bound(
                "target_byte_length",
                resource("lir.x86.byte_lengths"),
                byte_lengths,
            )?,
            bound(
                "target_byte_offset",
                resource("lir.x86.byte_offsets"),
                byte_offsets,
            )?,
            bound(
                "x86_artifact_layout",
                resource("lir.x86.artifact_layout"),
                layout,
            )?,
            bound("artifact_bytes", resource("artifact.x86.bytes"), words)?,
        ],
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        codegen::{
            lowering::{GpuSemanticLirView, target_lowering_allocations},
            lowering_ir::{
                LoweringStatus,
                LoweringTarget,
                SemanticLirAggregateElement,
                SemanticLirCallArg,
                SemanticLirCore,
                SemanticLirFunction,
                SemanticLirLocal,
                SemanticLirOperands,
                SemanticLirParam,
                SemanticLirSchedule,
                SemanticLirString,
                TargetLirFunction,
                X86LirCore,
                X86LirOperands,
                lowering_compiler_graph,
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
            artifact_bytes: 512,
        };
        let graph = lowering_compiler_graph(capacities, LoweringTarget::X86_64).unwrap();
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
            &records(&[[u32::MAX; 4]; 2]),
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
                [0, 0, 0, 1, 3, 0, 0, 0, 0, 0, 0, 0],
                [1, 1, 1, 0, 3, 1, 0, 0, 0, 0, 0, 0],
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
        let semantic_schedule = storage_ro_from_bytes::<SemanticLirSchedule>(
            &gpu.device,
            "test.x86_artifact.sem.schedule",
            &records(&[[0; 4]; 12]),
            12,
        );
        let semantic = GpuSemanticLirView {
            count: &semantic_total,
            core: &semantic_core,
            operands: &semantic_operands,
            call_args: &semantic_call_args,
            call_arg_count: &zero,
            call_arg_start_by_instruction: &no_call_starts,
            call_arg_count_by_instruction: &no_call_counts,
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
            schedule: &semantic_schedule,
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
        let function_ids = workspace
            .alias::<u32>(
                &graph,
                graph
                    .resource_id("lir.target.scheduled_function_ids")
                    .unwrap(),
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
        let frame_slots = workspace
            .alias::<u32>(
                &graph,
                graph
                    .resource_id("lir.x86.frame_slot_by_decl_token")
                    .unwrap(),
                8,
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
            &function_ids.buffer,
            0,
            &records(&[[0], [0], [0], [0], [0], [0], [1], [1], [1], [1], [1], [1]]),
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
        gpu.queue
            .write_buffer(&frame_slots.buffer, 0, &records(&[[u32::MAX]; 8]));

        let stage = GpuX86ArtifactStage::new(
            &gpu.device,
            &graph,
            &workspace,
            &allocations,
            capacities,
            semantic,
            &total,
            &core,
            &operands,
            &function_ids,
            GpuTargetFunctionView {
                count: &function_count,
                rows: &functions,
                index_by_semantic: &function_index_by_semantic,
            },
            &frame_slots,
        )
        .unwrap();
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.x86_artifact.encoder"),
            });
        stage.record(&mut encoder).unwrap();
        gpu.queue.submit(Some(encoder.finish()));
        let bytes = stage.finish(&gpu.device).unwrap();
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
