//! Graph-native projection of scheduled Wasm LIR into durable object columns.
//!
//! This stage does not inspect source, tokens, or HIR. GPU scans compact the
//! target rows that need relocations, the subset that needs undefined symbols,
//! and semantic functions that define public symbols. The host only validates
//! and serializes those flat artifact rows.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    functions::GpuTargetFunctionView,
    lowering::{GpuSemanticLirView, bound, make_group, record_direct},
    lowering_ir::{
        LoweringCapacities,
        WasmLirFunction,
        WasmLirInstruction,
        WasmLirOperands,
        WasmModuleLayout,
        WasmObjectDefinitionRow,
        WasmObjectFunctionRow,
        WasmObjectRelocationRow,
    },
    scan::{GpuResidentExclusiveScan, GraphScanContract},
    wasm::{
        GPU_WASM_OBJECT_VERSION,
        GpuWasmFunctionRecord,
        GpuWasmObjectSymbolRecord,
        GpuWasmRelocatableObject,
        GpuWasmRelocationRecord,
        GpuWasmRelocationTargetKind,
        GpuWasmSymbolKind,
    },
    wasm_module::GpuWasmModuleObjectView,
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
struct WasmObjectParams {
    target_capacity: u32,
    function_capacity: u32,
    artifact_capacity: u32,
    reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmObjectIdentity {
    library_id: u32,
    unit_id: u32,
    reserved0: u32,
    reserved1: u32,
}

#[derive(Clone, Copy)]
pub(crate) struct GpuWasmObjectView<'a> {
    pub relocation_count: &'a LaniusBuffer<u32>,
    pub symbol_count: &'a LaniusBuffer<u32>,
    pub definition_count: &'a LaniusBuffer<u32>,
    pub relocations: &'a LaniusBuffer<WasmObjectRelocationRow>,
    pub functions: &'a LaniusBuffer<WasmObjectFunctionRow>,
    pub definitions: &'a LaniusBuffer<WasmObjectDefinitionRow>,
    pub type_words: &'a LaniusBuffer<u32>,
    pub body_words: &'a LaniusBuffer<u32>,
}

pub(crate) struct GpuWasmObjectStage {
    target_capacity: u32,
    function_capacity: u32,
    artifact_capacity: u32,
    relocation_flags_pass: PassData,
    definition_flags_pass: PassData,
    relocations_pass: PassData,
    functions_pass: PassData,
    bytes_pass: PassData,
    relocation_flags_group: wgpu::BindGroup,
    definition_flags_group: wgpu::BindGroup,
    relocations_group: wgpu::BindGroup,
    functions_group: wgpu::BindGroup,
    bytes_group: wgpu::BindGroup,
    relocation_scan: GpuResidentExclusiveScan,
    symbol_scan: GpuResidentExclusiveScan,
    definition_scan: GpuResidentExclusiveScan,
    _params: LaniusBuffer<WasmObjectParams>,
    identity: LaniusBuffer<WasmObjectIdentity>,
    _relocation_flags: LaniusBuffer<u32>,
    _relocation_prefix: LaniusBuffer<u32>,
    relocation_total: LaniusBuffer<u32>,
    _symbol_flags: LaniusBuffer<u32>,
    _symbol_prefix: LaniusBuffer<u32>,
    symbol_total: LaniusBuffer<u32>,
    _definition_flags: LaniusBuffer<u32>,
    _definition_prefix: LaniusBuffer<u32>,
    definition_total: LaniusBuffer<u32>,
    relocations: LaniusBuffer<WasmObjectRelocationRow>,
    functions: LaniusBuffer<WasmObjectFunctionRow>,
    definitions: LaniusBuffer<WasmObjectDefinitionRow>,
    type_words: LaniusBuffer<u32>,
    body_words: LaniusBuffer<u32>,
    function_count: LaniusBuffer<u32>,
    type_total: LaniusBuffer<u32>,
    code_total: LaniusBuffer<u32>,
    layout: LaniusBuffer<WasmModuleLayout>,
    metadata_readback: LaniusBuffer<u8>,
    payload_readback: LaniusBuffer<u8>,
    payload_layout: ObjectReadbackLayout,
}

#[derive(Clone, Copy)]
struct ObjectReadbackLayout {
    functions: u64,
    relocations: u64,
    definitions: u64,
    types: u64,
    bodies: u64,
    total: u64,
}

impl GpuWasmObjectStage {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        device: &wgpu::Device,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        capacities: LoweringCapacities,
        semantic: GpuSemanticLirView<'_>,
        target_total: &LaniusBuffer<u32>,
        target_instructions: &LaniusBuffer<WasmLirInstruction>,
        target_operands: &LaniusBuffer<WasmLirOperands>,
        scheduled_function_ids: &LaniusBuffer<u32>,
        target_byte_offsets: &LaniusBuffer<u32>,
        target_functions: GpuTargetFunctionView<'_>,
        wasm_functions: &LaniusBuffer<WasmLirFunction>,
        module: GpuWasmModuleObjectView<'_>,
    ) -> Result<Self> {
        let target_capacity = capacities.target_instructions.max(1);
        let function_capacity = capacities.hir_nodes.max(1);
        let artifact_capacity = capacities.artifact_bytes.max(1);
        let resource = |name: &str| {
            graph
                .resource_id(name)
                .with_context(|| format!("Wasm object graph is missing {name}"))
        };
        let alias_u32 = |name: &str, rows: u32| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(graph, resource(name)?, rows.max(1) as usize)
                .map_err(anyhow::Error::msg)
        };
        let relocation_flags = alias_u32("artifact.wasm.object.relocation_flags", target_capacity)?;
        let relocation_prefix =
            alias_u32("artifact.wasm.object.relocation_prefix", target_capacity)?;
        let relocation_total = alias_u32("artifact.wasm.object.relocation_total", 1)?;
        let symbol_flags = alias_u32("artifact.wasm.object.symbol_flags", target_capacity)?;
        let symbol_prefix = alias_u32("artifact.wasm.object.symbol_prefix", target_capacity)?;
        let symbol_total = alias_u32("artifact.wasm.object.symbol_total", 1)?;
        let definition_flags =
            alias_u32("artifact.wasm.object.definition_flags", function_capacity)?;
        let definition_prefix =
            alias_u32("artifact.wasm.object.definition_prefix", function_capacity)?;
        let definition_total = alias_u32("artifact.wasm.object.definition_total", 1)?;
        let relocations = workspace
            .alias(
                graph,
                resource("artifact.wasm.object.relocations")?,
                target_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let functions = workspace
            .alias(
                graph,
                resource("artifact.wasm.object.functions")?,
                function_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let definitions = workspace
            .alias(
                graph,
                resource("artifact.wasm.object.definitions")?,
                function_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let type_words = alias_u32(
            "artifact.wasm.object.type_bytes",
            artifact_capacity.div_ceil(4),
        )?;
        let body_words = alias_u32(
            "artifact.wasm.object.body_bytes",
            artifact_capacity.div_ceil(4),
        )?;
        let payload_layout =
            ObjectReadbackLayout::new(function_capacity, target_capacity, artifact_capacity);
        let metadata_readback =
            readback_bytes(device, "artifact.wasm.object.metadata.readback", 96, 96);
        let payload_readback = readback_bytes(
            device,
            "artifact.wasm.object.payload.readback",
            payload_layout.total as usize,
            payload_layout.total as usize,
        );
        let params = uniform_from_val(
            device,
            "artifact.wasm.object.params",
            &WasmObjectParams {
                target_capacity,
                function_capacity,
                artifact_capacity,
                reserved: 0,
            },
        );
        let identity = uniform_from_val(
            device,
            "artifact.wasm.object.identity",
            &WasmObjectIdentity {
                library_id: 0,
                unit_id: 0,
                reserved0: 0,
                reserved1: 0,
            },
        );

        let relocation_flags_pass = load(
            device,
            "artifact.wasm.object.relocation_flags",
            "codegen/lir/wasm/object_relocation_flags",
        )?;
        let definition_flags_pass = load(
            device,
            "artifact.wasm.object.definition_flags",
            "codegen/lir/wasm/object_definition_flags",
        )?;
        let relocations_pass = load(
            device,
            "artifact.wasm.object.relocations",
            "codegen/lir/wasm/object_relocations",
        )?;
        let functions_pass = load(
            device,
            "artifact.wasm.object.functions",
            "codegen/lir/wasm/object_functions",
        )?;
        let bytes_pass = load(
            device,
            "artifact.wasm.object.bytes",
            "codegen/lir/wasm/object_bytes",
        )?;

        let relocation_flags_group = make_group(
            device,
            &relocation_flags_pass,
            "artifact.wasm.object.relocation_flags.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                ("target_lir_total", target_total.as_entire_binding()),
                ("target_lir_core", target_instructions.as_entire_binding()),
                ("semantic_lir_total", semantic.count.as_entire_binding()),
                ("semantic_lir_core", semantic.core.as_entire_binding()),
                (
                    "wasm_object_relocation_flag",
                    relocation_flags.as_entire_binding(),
                ),
                ("wasm_object_symbol_flag", symbol_flags.as_entire_binding()),
            ],
        )?;
        let relocation_scan = GpuResidentExclusiveScan::new(
            device,
            graph,
            workspace,
            allocations,
            scan_contract("relocation", "lir.wasm.total"),
            target_capacity,
            target_total,
            &relocation_flags,
            &relocation_prefix,
            &relocation_total,
        )?;
        let symbol_scan = GpuResidentExclusiveScan::new(
            device,
            graph,
            workspace,
            allocations,
            scan_contract("symbol", "lir.wasm.total"),
            target_capacity,
            target_total,
            &symbol_flags,
            &symbol_prefix,
            &symbol_total,
        )?;
        let definition_flags_group = make_group(
            device,
            &definition_flags_pass,
            "artifact.wasm.object.definition_flags.bind_group",
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
                (
                    "wasm_object_definition_flag",
                    definition_flags.as_entire_binding(),
                ),
            ],
        )?;
        let definition_scan = GpuResidentExclusiveScan::new(
            device,
            graph,
            workspace,
            allocations,
            scan_contract("definition", "lir.semantic.function_total"),
            function_capacity,
            semantic.function_count,
            &definition_flags,
            &definition_prefix,
            &definition_total,
        )?;
        let relocations_group = make_group(
            device,
            &relocations_pass,
            "artifact.wasm.object.relocations.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                ("target_lir_total", target_total.as_entire_binding()),
                ("target_lir_core", target_instructions.as_entire_binding()),
                ("target_lir_operands", target_operands.as_entire_binding()),
                (
                    "scheduled_function_id",
                    scheduled_function_ids.as_entire_binding(),
                ),
                (
                    "target_byte_offset",
                    target_byte_offsets.as_entire_binding(),
                ),
                (
                    "wasm_object_relocation_flag",
                    relocation_flags.as_entire_binding(),
                ),
                (
                    "wasm_object_relocation_prefix",
                    relocation_prefix.as_entire_binding(),
                ),
                (
                    "wasm_object_symbol_prefix",
                    symbol_prefix.as_entire_binding(),
                ),
                ("wasm_lir_functions", wasm_functions.as_entire_binding()),
                (
                    "wasm_code_entry_offset",
                    module.code_offsets.as_entire_binding(),
                ),
                ("wasm_object_relocations", relocations.as_entire_binding()),
            ],
        )?;
        let functions_group = make_group(
            device,
            &functions_pass,
            "artifact.wasm.object.functions.bind_group",
            &[
                ("gIdentity", identity.as_entire_binding()),
                ("gParams", params.as_entire_binding()),
                (
                    "semantic_lir_function_total",
                    semantic.function_count.as_entire_binding(),
                ),
                (
                    "semantic_lir_functions",
                    semantic.functions.as_entire_binding(),
                ),
                ("wasm_lir_functions", wasm_functions.as_entire_binding()),
                (
                    "wasm_type_entry_length",
                    module.type_lengths.as_entire_binding(),
                ),
                (
                    "wasm_type_entry_offset",
                    module.type_offsets.as_entire_binding(),
                ),
                (
                    "wasm_code_entry_length",
                    module.code_lengths.as_entire_binding(),
                ),
                (
                    "wasm_code_entry_offset",
                    module.code_offsets.as_entire_binding(),
                ),
                ("wasm_object_symbol_total", symbol_total.as_entire_binding()),
                (
                    "wasm_object_definition_flag",
                    definition_flags.as_entire_binding(),
                ),
                (
                    "wasm_object_definition_prefix",
                    definition_prefix.as_entire_binding(),
                ),
                ("wasm_object_functions", functions.as_entire_binding()),
                ("wasm_object_definitions", definitions.as_entire_binding()),
            ],
        )?;
        let bytes_group = make_group(
            device,
            &bytes_pass,
            "artifact.wasm.object.bytes.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "wasm_type_entries_length",
                    module.type_total.as_entire_binding(),
                ),
                (
                    "wasm_code_entries_length",
                    module.code_total.as_entire_binding(),
                ),
                ("wasm_module_layout", module.layout.as_entire_binding()),
                ("wasm_module_bytes", module.words.as_entire_binding()),
                ("wasm_object_type_bytes", type_words.as_entire_binding()),
                ("wasm_object_body_bytes", body_words.as_entire_binding()),
            ],
        )?;

        validate_primary_passes(
            graph,
            allocations,
            semantic,
            target_total,
            target_instructions,
            target_operands,
            scheduled_function_ids,
            target_byte_offsets,
            target_functions,
            wasm_functions,
            module,
            &relocation_flags,
            &relocation_prefix,
            &symbol_flags,
            &symbol_prefix,
            &symbol_total,
            &definition_flags,
            &definition_prefix,
            &relocations,
            &functions,
            &definitions,
            &type_words,
            &body_words,
        )?;

        Ok(Self {
            target_capacity,
            function_capacity,
            artifact_capacity,
            relocation_flags_pass,
            definition_flags_pass,
            relocations_pass,
            functions_pass,
            bytes_pass,
            relocation_flags_group,
            definition_flags_group,
            relocations_group,
            functions_group,
            bytes_group,
            relocation_scan,
            symbol_scan,
            definition_scan,
            _params: params,
            identity,
            _relocation_flags: relocation_flags,
            _relocation_prefix: relocation_prefix,
            relocation_total,
            _symbol_flags: symbol_flags,
            _symbol_prefix: symbol_prefix,
            symbol_total,
            _definition_flags: definition_flags,
            _definition_prefix: definition_prefix,
            definition_total,
            relocations,
            functions,
            definitions,
            type_words,
            body_words,
            function_count: semantic.function_count.clone(),
            type_total: module.type_total.clone(),
            code_total: module.code_total.clone(),
            layout: module.layout.clone(),
            metadata_readback,
            payload_readback,
            payload_layout,
        })
    }

    pub(crate) fn set_identity(&self, queue: &wgpu::Queue, library_id: u32, unit_id: u32) {
        let value = WasmObjectIdentity {
            library_id,
            unit_id,
            reserved0: 0,
            reserved1: 0,
        };
        let mut bytes = encase::UniformBuffer::new(Vec::new());
        bytes.write(&value).expect("Wasm object identity encodes");
        queue.write_buffer(&self.identity.buffer, 0, bytes.as_ref());
    }

    pub(crate) fn output(&self) -> GpuWasmObjectView<'_> {
        GpuWasmObjectView {
            relocation_count: &self.relocation_total,
            symbol_count: &self.symbol_total,
            definition_count: &self.definition_total,
            relocations: &self.relocations,
            functions: &self.functions,
            definitions: &self.definitions,
            type_words: &self.type_words,
            body_words: &self.body_words,
        }
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        record_direct(
            encoder,
            &self.relocation_flags_pass,
            &self.relocation_flags_group,
            self.target_capacity,
        )?;
        self.relocation_scan.record(encoder)?;
        self.symbol_scan.record(encoder)?;
        record_direct(
            encoder,
            &self.definition_flags_pass,
            &self.definition_flags_group,
            self.function_capacity,
        )?;
        self.definition_scan.record(encoder)?;
        record_direct(
            encoder,
            &self.relocations_pass,
            &self.relocations_group,
            self.target_capacity,
        )?;
        record_direct(
            encoder,
            &self.functions_pass,
            &self.functions_group,
            self.function_capacity,
        )?;
        record_direct(
            encoder,
            &self.bytes_pass,
            &self.bytes_group,
            self.artifact_capacity,
        )?;
        for (source, destination) in [
            (&self.function_count.buffer, 0),
            (&self.type_total.buffer, 4),
            (&self.code_total.buffer, 8),
            (&self.relocation_total.buffer, 12),
            (&self.symbol_total.buffer, 16),
            (&self.definition_total.buffer, 20),
        ] {
            encoder.copy_buffer_to_buffer(
                source,
                0,
                &self.metadata_readback.buffer,
                destination,
                4,
            );
        }
        encoder.copy_buffer_to_buffer(
            &self.layout.buffer,
            0,
            &self.metadata_readback.buffer,
            32,
            64,
        );
        encoder.copy_buffer_to_buffer(
            &self.functions.buffer,
            0,
            &self.payload_readback.buffer,
            self.payload_layout.functions,
            u64::from(self.function_capacity) * 24,
        );
        encoder.copy_buffer_to_buffer(
            &self.relocations.buffer,
            0,
            &self.payload_readback.buffer,
            self.payload_layout.relocations,
            u64::from(self.target_capacity) * 32,
        );
        encoder.copy_buffer_to_buffer(
            &self.definitions.buffer,
            0,
            &self.payload_readback.buffer,
            self.payload_layout.definitions,
            u64::from(self.function_capacity) * 32,
        );
        encoder.copy_buffer_to_buffer(
            &self.type_words.buffer,
            0,
            &self.payload_readback.buffer,
            self.payload_layout.types,
            u64::from(self.artifact_capacity.div_ceil(4) * 4),
        );
        encoder.copy_buffer_to_buffer(
            &self.body_words.buffer,
            0,
            &self.payload_readback.buffer,
            self.payload_layout.bodies,
            u64::from(self.artifact_capacity.div_ceil(4) * 4),
        );
        Ok(())
    }

    pub(crate) fn finish(
        &self,
        device: &wgpu::Device,
        library_id: u32,
        unit_id: u32,
    ) -> Result<GpuWasmRelocatableObject> {
        let metadata_slice = self.metadata_readback.slice(..);
        map_readback_blocking(device, &metadata_slice, "Wasm object metadata readback")?;
        let metadata = metadata_slice.get_mapped_range();
        let word = |index: usize| {
            u32::from_le_bytes(metadata[index * 4..index * 4 + 4].try_into().unwrap())
        };
        let function_count = word(0) as usize;
        let type_len = word(1) as usize;
        let body_len = word(2) as usize;
        let relocation_count = word(3) as usize;
        let symbol_count = word(4) as usize;
        let definition_count = word(5) as usize;
        let layout_words = (8..24).map(word).collect::<Vec<_>>();
        drop(metadata);
        self.metadata_readback.unmap();
        if function_count > self.function_capacity as usize
            || relocation_count > self.target_capacity as usize
            || symbol_count > relocation_count
            || definition_count > self.function_capacity as usize
            || type_len > self.artifact_capacity as usize
            || body_len > self.artifact_capacity as usize
        {
            anyhow::bail!(
                "GPU Wasm object metadata exceeds resident capacity: functions={function_count}/{}, relocations={relocation_count}/{}, symbols={symbol_count}, definitions={definition_count}/{}, type={type_len}/{}, body={body_len}/{}",
                self.function_capacity,
                self.target_capacity,
                self.function_capacity,
                self.artifact_capacity,
                self.artifact_capacity,
            );
        }
        let entrypoint_count = layout_words[1];
        let entrypoint_id = layout_words[2];
        if layout_words[3] != 0 || entrypoint_count > 1 {
            anyhow::bail!(
                "GPU Wasm object module layout is invalid: status={} entrypoints={entrypoint_count}",
                layout_words[3],
            );
        }

        let payload_slice = self.payload_readback.slice(..);
        map_readback_blocking(device, &payload_slice, "Wasm object payload readback")?;
        let payload = payload_slice.get_mapped_range();
        let section = |start: u64, len: usize| &payload[start as usize..start as usize + len];
        let function_words =
            decode_words(section(self.payload_layout.functions, function_count * 24));
        let relocation_words = decode_words(section(
            self.payload_layout.relocations,
            relocation_count * 32,
        ));
        let definition_words = decode_words(section(
            self.payload_layout.definitions,
            definition_count * 32,
        ));
        let type_bytes = section(self.payload_layout.types, type_len).to_vec();
        let body_bytes = section(self.payload_layout.bodies, body_len).to_vec();

        let functions = function_words
            .chunks_exact(6)
            .map(|row| GpuWasmFunctionRecord {
                type_byte_start: row[0],
                type_byte_len: row[1],
                body_byte_start: row[2],
                body_byte_len: row[3],
                symbol_index: row[4],
                flags: row[5],
            })
            .collect::<Vec<_>>();
        let mut relocations = Vec::with_capacity(relocation_count);
        let mut undefined_identities = vec![None; symbol_count];
        for (index, row) in relocation_words.chunks_exact(8).enumerate() {
            let target_kind = match row[1] {
                1 => GpuWasmRelocationTargetKind::LocalFunction,
                2 => GpuWasmRelocationTargetKind::Symbol,
                value => {
                    anyhow::bail!("GPU Wasm object relocation {index} has target kind {value}")
                }
            };
            if target_kind == GpuWasmRelocationTargetKind::Symbol {
                let slot = row[2] as usize;
                if slot >= symbol_count || undefined_identities[slot].is_some() {
                    anyhow::bail!(
                        "GPU Wasm object relocation {index} has invalid symbol slot {slot}"
                    );
                }
                undefined_identities[slot] = Some([row[4], row[5], row[6]]);
            }
            relocations.push(GpuWasmRelocationRecord {
                body_byte_offset: row[0],
                target_kind,
                target_index: row[2],
                addend: row[3] as i32,
            });
        }
        let mut identity_bytes = Vec::with_capacity((symbol_count + definition_count) * 12);
        let mut symbols = Vec::with_capacity(symbol_count + definition_count);
        for (slot, identity) in undefined_identities.into_iter().enumerate() {
            push_symbol(
                &mut identity_bytes,
                &mut symbols,
                identity.with_context(|| {
                    format!("GPU Wasm object did not define undefined-symbol slot {slot}")
                })?,
                GpuWasmSymbolKind::Undefined,
                u32::MAX,
                0,
                0,
            );
        }
        for (index, row) in definition_words.chunks_exact(8).enumerate() {
            if row[0] != library_id || row[1] != unit_id {
                anyhow::bail!(
                    "GPU Wasm object definition {index} identity [{}, {}] does not match requested unit [{library_id}, {unit_id}]",
                    row[0],
                    row[1],
                );
            }
            push_symbol(
                &mut identity_bytes,
                &mut symbols,
                [row[0], row[1], row[2]],
                GpuWasmSymbolKind::Function,
                row[3],
                row[4],
                row[5],
            );
        }
        drop(payload);
        self.payload_readback.unmap();

        let object = GpuWasmRelocatableObject {
            version: GPU_WASM_OBJECT_VERSION,
            library_id,
            unit_id,
            entry_function: (entrypoint_count == 1).then_some(entrypoint_id),
            functions,
            type_bytes,
            body_bytes,
            relocations,
            symbols,
            identity_bytes,
        };
        object.validate().map_err(anyhow::Error::msg)?;
        Ok(object)
    }
}

impl ObjectReadbackLayout {
    fn new(function_capacity: u32, target_capacity: u32, artifact_capacity: u32) -> Self {
        let functions = 0;
        let relocations = u64::from(function_capacity) * 24;
        let definitions = relocations + u64::from(target_capacity) * 32;
        let types = definitions + u64::from(function_capacity) * 32;
        let artifact_bytes = u64::from(artifact_capacity.div_ceil(4) * 4);
        let bodies = types + artifact_bytes;
        Self {
            functions,
            relocations,
            definitions,
            types,
            bodies,
            total: bodies + artifact_bytes,
        }
    }
}

fn decode_words(bytes: &[u8]) -> Vec<u32> {
    bytes
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect()
}

fn push_symbol(
    identity_bytes: &mut Vec<u8>,
    symbols: &mut Vec<GpuWasmObjectSymbolRecord>,
    identity: [u32; 3],
    kind: GpuWasmSymbolKind,
    function_index: u32,
    size: u32,
    flags: u32,
) {
    let identity_byte_start = identity_bytes.len() as u32;
    for word in identity {
        identity_bytes.extend_from_slice(&word.to_le_bytes());
    }
    let bytes = &identity_bytes[identity_byte_start as usize..];
    let (identity_hash_lo, identity_hash_hi) = crate::compiler::stable_name_hash(bytes);
    symbols.push(GpuWasmObjectSymbolRecord {
        identity_hash_lo,
        identity_hash_hi,
        identity_byte_start,
        identity_byte_len: 12,
        kind,
        function_index,
        size,
        flags,
    });
}

fn scan_contract(kind: &'static str, count: &'static str) -> GraphScanContract {
    match kind {
        "relocation" => GraphScanContract {
            local_pass: "artifact.wasm.object.relocation_scan.local",
            up_pass: "artifact.wasm.object.relocation_scan.hierarchy_up",
            down_pass: "artifact.wasm.object.relocation_scan.hierarchy_down",
            apply_pass: "artifact.wasm.object.relocation_scan.apply",
            count,
            input: "artifact.wasm.object.relocation_flags",
            local: "artifact.wasm.object.relocation_scan_local",
            block_sum: "artifact.wasm.object.relocation_scan_block_sum",
            block_prefix: "artifact.wasm.object.relocation_scan_block_prefix",
            hierarchy: "artifact.wasm.object.relocation_scan_hierarchy",
            output: "artifact.wasm.object.relocation_prefix",
            total: "artifact.wasm.object.relocation_total",
        },
        "symbol" => GraphScanContract {
            local_pass: "artifact.wasm.object.symbol_scan.local",
            up_pass: "artifact.wasm.object.symbol_scan.hierarchy_up",
            down_pass: "artifact.wasm.object.symbol_scan.hierarchy_down",
            apply_pass: "artifact.wasm.object.symbol_scan.apply",
            count,
            input: "artifact.wasm.object.symbol_flags",
            local: "artifact.wasm.object.symbol_scan_local",
            block_sum: "artifact.wasm.object.symbol_scan_block_sum",
            block_prefix: "artifact.wasm.object.symbol_scan_block_prefix",
            hierarchy: "artifact.wasm.object.symbol_scan_hierarchy",
            output: "artifact.wasm.object.symbol_prefix",
            total: "artifact.wasm.object.symbol_total",
        },
        "definition" => GraphScanContract {
            local_pass: "artifact.wasm.object.definition_scan.local",
            up_pass: "artifact.wasm.object.definition_scan.hierarchy_up",
            down_pass: "artifact.wasm.object.definition_scan.hierarchy_down",
            apply_pass: "artifact.wasm.object.definition_scan.apply",
            count,
            input: "artifact.wasm.object.definition_flags",
            local: "artifact.wasm.object.definition_scan_local",
            block_sum: "artifact.wasm.object.definition_scan_block_sum",
            block_prefix: "artifact.wasm.object.definition_scan_block_prefix",
            hierarchy: "artifact.wasm.object.definition_scan_hierarchy",
            output: "artifact.wasm.object.definition_prefix",
            total: "artifact.wasm.object.definition_total",
        },
        _ => unreachable!(),
    }
}

fn load(device: &wgpu::Device, label: &str, shader: &str) -> Result<PassData> {
    make_pass_data_from_shader_key(device, label, "main", shader)
}

#[allow(clippy::too_many_arguments)]
fn validate_primary_passes(
    graph: &CompilerGraph,
    allocations: &CompilerGraphAllocations,
    semantic: GpuSemanticLirView<'_>,
    target_total: &LaniusBuffer<u32>,
    target_instructions: &LaniusBuffer<WasmLirInstruction>,
    target_operands: &LaniusBuffer<WasmLirOperands>,
    scheduled_function_ids: &LaniusBuffer<u32>,
    target_byte_offsets: &LaniusBuffer<u32>,
    _target_functions: GpuTargetFunctionView<'_>,
    wasm_functions: &LaniusBuffer<WasmLirFunction>,
    module: GpuWasmModuleObjectView<'_>,
    relocation_flags: &LaniusBuffer<u32>,
    relocation_prefix: &LaniusBuffer<u32>,
    symbol_flags: &LaniusBuffer<u32>,
    symbol_prefix: &LaniusBuffer<u32>,
    symbol_total: &LaniusBuffer<u32>,
    definition_flags: &LaniusBuffer<u32>,
    definition_prefix: &LaniusBuffer<u32>,
    relocations: &LaniusBuffer<WasmObjectRelocationRow>,
    functions: &LaniusBuffer<WasmObjectFunctionRow>,
    definitions: &LaniusBuffer<WasmObjectDefinitionRow>,
    type_words: &LaniusBuffer<u32>,
    body_words: &LaniusBuffer<u32>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    let run = |pass: &str, bindings: Vec<BoundGraphResource>| {
        allocations
            .validate_pass_bindings(graph, graph.pass_id(pass).unwrap(), &bindings)
            .map_err(anyhow::Error::msg)
    };
    run(
        "artifact.wasm.object.relocation_flags",
        vec![
            bound("target_lir_total", resource("lir.wasm.total"), target_total)?,
            bound(
                "target_lir_core",
                resource("lir.wasm.instructions"),
                target_instructions,
            )?,
            bound(
                "semantic_lir_total",
                resource("lir.semantic.total"),
                semantic.count,
            )?,
            bound(
                "semantic_lir_core",
                resource("lir.semantic.core"),
                semantic.core,
            )?,
            bound(
                "wasm_object_relocation_flag",
                resource("artifact.wasm.object.relocation_flags"),
                relocation_flags,
            )?,
            bound(
                "wasm_object_symbol_flag",
                resource("artifact.wasm.object.symbol_flags"),
                symbol_flags,
            )?,
        ],
    )?;
    run(
        "artifact.wasm.object.definition_flags",
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
                "wasm_object_definition_flag",
                resource("artifact.wasm.object.definition_flags"),
                definition_flags,
            )?,
        ],
    )?;
    run(
        "artifact.wasm.object.relocations",
        vec![
            bound("target_lir_total", resource("lir.wasm.total"), target_total)?,
            bound(
                "target_lir_core",
                resource("lir.wasm.instructions"),
                target_instructions,
            )?,
            bound(
                "target_lir_operands",
                resource("lir.wasm.operands"),
                target_operands,
            )?,
            bound(
                "scheduled_function_id",
                resource("lir.target.scheduled_function_ids"),
                scheduled_function_ids,
            )?,
            bound(
                "target_byte_offset",
                resource("lir.wasm.byte_offsets"),
                target_byte_offsets,
            )?,
            bound(
                "wasm_object_relocation_flag",
                resource("artifact.wasm.object.relocation_flags"),
                relocation_flags,
            )?,
            bound(
                "wasm_object_relocation_prefix",
                resource("artifact.wasm.object.relocation_prefix"),
                relocation_prefix,
            )?,
            bound(
                "wasm_object_symbol_prefix",
                resource("artifact.wasm.object.symbol_prefix"),
                symbol_prefix,
            )?,
            bound(
                "wasm_lir_functions",
                resource("lir.wasm.functions"),
                wasm_functions,
            )?,
            bound(
                "wasm_code_entry_offset",
                resource("lir.wasm.module.code_offsets"),
                module.code_offsets,
            )?,
            bound(
                "wasm_object_relocations",
                resource("artifact.wasm.object.relocations"),
                relocations,
            )?,
        ],
    )?;
    run(
        "artifact.wasm.object.functions",
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
                "wasm_lir_functions",
                resource("lir.wasm.functions"),
                wasm_functions,
            )?,
            bound(
                "wasm_type_entry_length",
                resource("lir.wasm.module.type_lengths"),
                module.type_lengths,
            )?,
            bound(
                "wasm_type_entry_offset",
                resource("lir.wasm.module.type_offsets"),
                module.type_offsets,
            )?,
            bound(
                "wasm_code_entry_length",
                resource("lir.wasm.module.code_lengths"),
                module.code_lengths,
            )?,
            bound(
                "wasm_code_entry_offset",
                resource("lir.wasm.module.code_offsets"),
                module.code_offsets,
            )?,
            bound(
                "wasm_object_symbol_total",
                resource("artifact.wasm.object.symbol_total"),
                symbol_total,
            )?,
            bound(
                "wasm_object_definition_flag",
                resource("artifact.wasm.object.definition_flags"),
                definition_flags,
            )?,
            bound(
                "wasm_object_definition_prefix",
                resource("artifact.wasm.object.definition_prefix"),
                definition_prefix,
            )?,
            bound(
                "wasm_object_functions",
                resource("artifact.wasm.object.functions"),
                functions,
            )?,
            bound(
                "wasm_object_definitions",
                resource("artifact.wasm.object.definitions"),
                definitions,
            )?,
        ],
    )?;
    run(
        "artifact.wasm.object.bytes",
        vec![
            bound(
                "wasm_type_entries_length",
                resource("lir.wasm.module.type_total"),
                module.type_total,
            )?,
            bound(
                "wasm_code_entries_length",
                resource("lir.wasm.module.code_total"),
                module.code_total,
            )?,
            bound(
                "wasm_module_layout",
                resource("lir.wasm.module.layout"),
                module.layout,
            )?,
            bound(
                "wasm_module_bytes",
                resource("artifact.wasm.bytes"),
                module.words,
            )?,
            bound(
                "wasm_object_type_bytes",
                resource("artifact.wasm.object.type_bytes"),
                type_words,
            )?,
            bound(
                "wasm_object_body_bytes",
                resource("artifact.wasm.object.body_bytes"),
                body_words,
            )?,
        ],
    )
}
