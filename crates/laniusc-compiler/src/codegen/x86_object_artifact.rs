//! Graph-native projection of scheduled x86 LIR into durable object columns.
//!
//! The target emitter produces body, runtime, and rodata bytes on the GPU.
//! This stage compacts relocation and symbol rows and projects those section
//! bytes without inspecting source, tokens, HIR, or target instructions on the
//! host. The host only validates and serializes the flat object contract.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    functions::GpuTargetFunctionView,
    lowering::{GpuSemanticLirView, bound, make_group, record_direct},
    lowering_ir::{
        LoweringCapacities,
        X86LirCore,
        X86LirOperands,
        X86ObjectDefinitionRow,
        X86ObjectRelocationRow,
        X86ObjectUndefinedRow,
    },
    scan::{GpuResidentExclusiveScan, GraphScanContract},
    x86::{
        GPU_X86_OBJECT_VERSION,
        GpuX86ObjectSection,
        GpuX86ObjectSymbolRecord,
        GpuX86RelocatableObject,
        GpuX86RelocationKind,
        GpuX86RelocationRecord,
        GpuX86RelocationTargetKind,
    },
    x86_artifact::GpuX86ArtifactObjectView,
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
struct X86ObjectParams {
    target_capacity: u32,
    function_capacity: u32,
    artifact_capacity: u32,
    reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct X86ObjectIdentity {
    library_id: u32,
    unit_id: u32,
    reserved0: u32,
    reserved1: u32,
}

pub(crate) struct GpuX86ObjectStage {
    target_capacity: u32,
    function_capacity: u32,
    artifact_capacity: u32,
    normalize_status_pass: PassData,
    relocation_flags_pass: PassData,
    definition_flags_pass: PassData,
    relocations_pass: PassData,
    definitions_pass: PassData,
    bytes_pass: PassData,
    normalize_status_group: wgpu::BindGroup,
    relocation_flags_group: wgpu::BindGroup,
    definition_flags_group: wgpu::BindGroup,
    relocations_group: wgpu::BindGroup,
    definitions_group: wgpu::BindGroup,
    bytes_group: wgpu::BindGroup,
    relocation_scan: GpuResidentExclusiveScan,
    symbol_scan: GpuResidentExclusiveScan,
    definition_scan: GpuResidentExclusiveScan,
    _params: LaniusBuffer<X86ObjectParams>,
    identity: LaniusBuffer<X86ObjectIdentity>,
    _relocation_flags: LaniusBuffer<u32>,
    _relocation_prefix: LaniusBuffer<u32>,
    relocation_total: LaniusBuffer<u32>,
    _symbol_flags: LaniusBuffer<u32>,
    _symbol_prefix: LaniusBuffer<u32>,
    symbol_total: LaniusBuffer<u32>,
    _definition_flags: LaniusBuffer<u32>,
    _definition_prefix: LaniusBuffer<u32>,
    definition_total: LaniusBuffer<u32>,
    relocations: LaniusBuffer<X86ObjectRelocationRow>,
    undefined_symbols: LaniusBuffer<X86ObjectUndefinedRow>,
    definitions: LaniusBuffer<X86ObjectDefinitionRow>,
    text_words: LaniusBuffer<u32>,
    rodata_words: LaniusBuffer<u32>,
    layout: LaniusBuffer<super::lowering_ir::X86ArtifactLayout>,
    metadata_readback: LaniusBuffer<u8>,
    payload_readback: LaniusBuffer<u8>,
    payload_layout: ObjectReadbackLayout,
}

#[derive(Clone, Copy)]
struct ObjectReadbackLayout {
    relocations: u64,
    undefined_symbols: u64,
    definitions: u64,
    text: u64,
    rodata: u64,
    total: u64,
}

impl GpuX86ObjectStage {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        device: &wgpu::Device,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        capacities: LoweringCapacities,
        semantic: GpuSemanticLirView<'_>,
        target_total: &LaniusBuffer<u32>,
        target_core: &LaniusBuffer<X86LirCore>,
        target_operands: &LaniusBuffer<X86LirOperands>,
        scheduled_function_ids: &LaniusBuffer<u32>,
        target_functions: GpuTargetFunctionView<'_>,
        artifact: GpuX86ArtifactObjectView<'_>,
    ) -> Result<Self> {
        let target_capacity = capacities.target_instructions.max(1);
        let function_capacity = capacities.hir_nodes.max(1);
        let artifact_capacity = capacities.artifact_bytes.max(1);
        let resource = |name: &str| {
            graph
                .resource_id(name)
                .with_context(|| format!("x86 object graph is missing {name}"))
        };
        let alias_u32 = |name: &str, rows: u32| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(graph, resource(name)?, rows.max(1) as usize)
                .map_err(anyhow::Error::msg)
        };
        let relocation_flags = alias_u32("artifact.x86.object.relocation_flags", target_capacity)?;
        let relocation_prefix =
            alias_u32("artifact.x86.object.relocation_prefix", target_capacity)?;
        let relocation_total = alias_u32("artifact.x86.object.relocation_total", 1)?;
        let symbol_flags = alias_u32("artifact.x86.object.symbol_flags", target_capacity)?;
        let symbol_prefix = alias_u32("artifact.x86.object.symbol_prefix", target_capacity)?;
        let symbol_total = alias_u32("artifact.x86.object.symbol_total", 1)?;
        let definition_flags =
            alias_u32("artifact.x86.object.definition_flags", function_capacity)?;
        let definition_prefix =
            alias_u32("artifact.x86.object.definition_prefix", function_capacity)?;
        let definition_total = alias_u32("artifact.x86.object.definition_total", 1)?;
        let relocations = workspace
            .alias(
                graph,
                resource("artifact.x86.object.relocations")?,
                target_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let undefined_symbols = workspace
            .alias(
                graph,
                resource("artifact.x86.object.undefined_symbols")?,
                target_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let definitions = workspace
            .alias(
                graph,
                resource("artifact.x86.object.definitions")?,
                function_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let text_words = alias_u32(
            "artifact.x86.object.text_bytes",
            artifact_capacity.div_ceil(4),
        )?;
        let rodata_words = alias_u32(
            "artifact.x86.object.rodata_bytes",
            artifact_capacity.div_ceil(4),
        )?;
        let payload_layout =
            ObjectReadbackLayout::new(target_capacity, function_capacity, artifact_capacity);
        let metadata_readback =
            readback_bytes(device, "artifact.x86.object.metadata.readback", 64, 64);
        let payload_readback = readback_bytes(
            device,
            "artifact.x86.object.payload.readback",
            payload_layout.total as usize,
            payload_layout.total as usize,
        );
        let params = uniform_from_val(
            device,
            "artifact.x86.object.params",
            &X86ObjectParams {
                target_capacity,
                function_capacity,
                artifact_capacity,
                reserved: 0,
            },
        );
        let identity = uniform_from_val(
            device,
            "artifact.x86.object.identity",
            &X86ObjectIdentity {
                library_id: 0,
                unit_id: 0,
                reserved0: 0,
                reserved1: 0,
            },
        );

        let normalize_status_pass = load(
            device,
            "artifact.x86.object.normalize_status",
            "codegen/lir/x86/object_normalize_status",
        )?;
        let relocation_flags_pass = load(
            device,
            "artifact.x86.object.relocation_flags",
            "codegen/lir/x86/object_relocation_flags",
        )?;
        let definition_flags_pass = load(
            device,
            "artifact.x86.object.definition_flags",
            "codegen/lir/x86/object_definition_flags",
        )?;
        let relocations_pass = load(
            device,
            "artifact.x86.object.relocations",
            "codegen/lir/x86/object_relocations",
        )?;
        let definitions_pass = load(
            device,
            "artifact.x86.object.definitions",
            "codegen/lir/x86/object_definitions",
        )?;
        let bytes_pass = load(
            device,
            "artifact.x86.object.bytes",
            "codegen/lir/x86/object_bytes",
        )?;

        let normalize_status_group = make_group(
            device,
            &normalize_status_pass,
            "artifact.x86.object.normalize_status.bind_group",
            &[
                (
                    "x86_entrypoint_state",
                    artifact.entrypoint_state.as_entire_binding(),
                ),
                ("x86_artifact_layout", artifact.layout.as_entire_binding()),
                ("lowering_status", semantic.status.as_entire_binding()),
            ],
        )?;
        let relocation_flags_group = make_group(
            device,
            &relocation_flags_pass,
            "artifact.x86.object.relocation_flags.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                ("target_lir_total", target_total.as_entire_binding()),
                ("target_lir_core", target_core.as_entire_binding()),
                (
                    "x86_object_relocation_flag",
                    relocation_flags.as_entire_binding(),
                ),
                ("x86_object_symbol_flag", symbol_flags.as_entire_binding()),
            ],
        )?;
        let relocation_scan = GpuResidentExclusiveScan::new(
            device,
            graph,
            workspace,
            allocations,
            scan_contract("relocation", "lir.x86.total"),
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
            scan_contract("symbol", "lir.x86.total"),
            target_capacity,
            target_total,
            &symbol_flags,
            &symbol_prefix,
            &symbol_total,
        )?;
        let definition_flags_group = make_group(
            device,
            &definition_flags_pass,
            "artifact.x86.object.definition_flags.bind_group",
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
                    "x86_object_definition_flag",
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
            "artifact.x86.object.relocations.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                ("target_lir_total", target_total.as_entire_binding()),
                ("target_lir_core", target_core.as_entire_binding()),
                ("target_lir_operands", target_operands.as_entire_binding()),
                (
                    "scheduled_function_id",
                    scheduled_function_ids.as_entire_binding(),
                ),
                (
                    "target_function_count",
                    target_functions.count.as_entire_binding(),
                ),
                (
                    "target_functions",
                    target_functions.rows.as_entire_binding(),
                ),
                (
                    "target_function_index_by_semantic",
                    target_functions.index_by_semantic.as_entire_binding(),
                ),
                (
                    "target_byte_length",
                    artifact.byte_lengths.as_entire_binding(),
                ),
                (
                    "target_byte_offset",
                    artifact.byte_offsets.as_entire_binding(),
                ),
                ("x86_artifact_layout", artifact.layout.as_entire_binding()),
                (
                    "semantic_lir_string_total",
                    semantic.string_count.as_entire_binding(),
                ),
                ("semantic_lir_strings", semantic.strings.as_entire_binding()),
                (
                    "x86_object_relocation_flag",
                    relocation_flags.as_entire_binding(),
                ),
                (
                    "x86_object_relocation_prefix",
                    relocation_prefix.as_entire_binding(),
                ),
                (
                    "x86_object_symbol_prefix",
                    symbol_prefix.as_entire_binding(),
                ),
                ("x86_object_relocations", relocations.as_entire_binding()),
                (
                    "x86_object_undefined_symbols",
                    undefined_symbols.as_entire_binding(),
                ),
            ],
        )?;
        let definitions_group = make_group(
            device,
            &definitions_pass,
            "artifact.x86.object.definitions.bind_group",
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
                (
                    "target_function_count",
                    target_functions.count.as_entire_binding(),
                ),
                (
                    "target_functions",
                    target_functions.rows.as_entire_binding(),
                ),
                (
                    "target_function_index_by_semantic",
                    target_functions.index_by_semantic.as_entire_binding(),
                ),
                (
                    "target_byte_length",
                    artifact.byte_lengths.as_entire_binding(),
                ),
                (
                    "target_byte_offset",
                    artifact.byte_offsets.as_entire_binding(),
                ),
                ("x86_artifact_layout", artifact.layout.as_entire_binding()),
                (
                    "x86_object_definition_flag",
                    definition_flags.as_entire_binding(),
                ),
                (
                    "x86_object_definition_prefix",
                    definition_prefix.as_entire_binding(),
                ),
                ("x86_object_definitions", definitions.as_entire_binding()),
            ],
        )?;
        let bytes_group = make_group(
            device,
            &bytes_pass,
            "artifact.x86.object.bytes.bind_group",
            &[
                ("gParams", params.as_entire_binding()),
                ("x86_artifact_layout", artifact.layout.as_entire_binding()),
                ("x86_artifact_bytes", artifact.words.as_entire_binding()),
                ("x86_object_text_bytes", text_words.as_entire_binding()),
                ("x86_object_rodata_bytes", rodata_words.as_entire_binding()),
            ],
        )?;

        validate_primary_passes(
            graph,
            allocations,
            semantic,
            target_total,
            target_core,
            target_operands,
            scheduled_function_ids,
            target_functions,
            artifact,
            &relocation_flags,
            &relocation_prefix,
            &symbol_flags,
            &symbol_prefix,
            &definition_flags,
            &definition_prefix,
            &relocations,
            &undefined_symbols,
            &definitions,
            &text_words,
            &rodata_words,
        )?;

        Ok(Self {
            target_capacity,
            function_capacity,
            artifact_capacity,
            normalize_status_pass,
            relocation_flags_pass,
            definition_flags_pass,
            relocations_pass,
            definitions_pass,
            bytes_pass,
            normalize_status_group,
            relocation_flags_group,
            definition_flags_group,
            relocations_group,
            definitions_group,
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
            undefined_symbols,
            definitions,
            text_words,
            rodata_words,
            layout: artifact.layout.clone(),
            metadata_readback,
            payload_readback,
            payload_layout,
        })
    }

    pub(crate) fn set_identity(&self, queue: &wgpu::Queue, library_id: u32, unit_id: u32) {
        let value = X86ObjectIdentity {
            library_id,
            unit_id,
            reserved0: 0,
            reserved1: 0,
        };
        let mut bytes = encase::UniformBuffer::new(Vec::new());
        bytes.write(&value).expect("x86 object identity encodes");
        queue.write_buffer(&self.identity.buffer, 0, bytes.as_ref());
    }

    pub(crate) fn record_status_normalization(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        record_direct(
            encoder,
            &self.normalize_status_pass,
            &self.normalize_status_group,
            1,
        )
    }

    pub(crate) fn record_projection(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
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
            &self.definitions_pass,
            &self.definitions_group,
            self.function_capacity,
        )?;
        record_direct(
            encoder,
            &self.bytes_pass,
            &self.bytes_group,
            self.artifact_capacity,
        )?;
        for (source, destination) in [
            (&self.relocation_total.buffer, 4),
            (&self.symbol_total.buffer, 8),
            (&self.definition_total.buffer, 12),
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
            16,
            48,
        );
        encoder.copy_buffer_to_buffer(
            &self.relocations.buffer,
            0,
            &self.payload_readback.buffer,
            self.payload_layout.relocations,
            u64::from(self.target_capacity) * 32,
        );
        encoder.copy_buffer_to_buffer(
            &self.undefined_symbols.buffer,
            0,
            &self.payload_readback.buffer,
            self.payload_layout.undefined_symbols,
            u64::from(self.target_capacity) * 16,
        );
        encoder.copy_buffer_to_buffer(
            &self.definitions.buffer,
            0,
            &self.payload_readback.buffer,
            self.payload_layout.definitions,
            u64::from(self.function_capacity) * 32,
        );
        let artifact_bytes = u64::from(self.artifact_capacity.div_ceil(4) * 4);
        encoder.copy_buffer_to_buffer(
            &self.text_words.buffer,
            0,
            &self.payload_readback.buffer,
            self.payload_layout.text,
            artifact_bytes,
        );
        encoder.copy_buffer_to_buffer(
            &self.rodata_words.buffer,
            0,
            &self.payload_readback.buffer,
            self.payload_layout.rodata,
            artifact_bytes,
        );
        Ok(())
    }

    pub(crate) fn finish(
        &self,
        device: &wgpu::Device,
        library_id: u32,
        unit_id: u32,
    ) -> Result<GpuX86RelocatableObject> {
        let metadata_slice = self.metadata_readback.slice(..);
        map_readback_blocking(device, &metadata_slice, "x86 object metadata readback")?;
        let metadata = metadata_slice.get_mapped_range();
        let word = |index: usize| {
            u32::from_le_bytes(metadata[index * 4..index * 4 + 4].try_into().unwrap())
        };
        let relocation_count = word(1) as usize;
        let symbol_count = word(2) as usize;
        let definition_count = word(3) as usize;
        let layout = (4..16).map(word).collect::<Vec<_>>();
        drop(metadata);
        self.metadata_readback.unmap();
        let body_len = layout[0] as usize;
        let wrapper_len = layout[6]
            .checked_sub(layout[5])
            .context("x86 object wrapper layout is inverted")? as usize;
        let runtime_len = layout[9] as usize;
        let text_len = wrapper_len
            .checked_add(body_len)
            .and_then(|len| len.checked_add(runtime_len))
            .context("x86 object text length overflows")?;
        let rodata_len = layout[11] as usize;
        let entrypoint_count = layout[2];
        if layout[7] != 0 || entrypoint_count > 1 {
            anyhow::bail!(
                "GPU x86 object layout is invalid: status={} entrypoints={entrypoint_count}",
                layout[7],
            );
        }
        if relocation_count > self.target_capacity as usize
            || symbol_count > relocation_count
            || definition_count > self.function_capacity as usize
            || text_len > self.artifact_capacity as usize
            || rodata_len > self.artifact_capacity as usize
        {
            anyhow::bail!(
                "GPU x86 object metadata exceeds resident capacity: relocations={relocation_count}/{}, symbols={symbol_count}, definitions={definition_count}/{}, text={text_len}/{}, rodata={rodata_len}/{}",
                self.target_capacity,
                self.function_capacity,
                self.artifact_capacity,
                self.artifact_capacity,
            );
        }

        let payload_slice = self.payload_readback.slice(..);
        map_readback_blocking(device, &payload_slice, "x86 object payload readback")?;
        let payload = payload_slice.get_mapped_range();
        let section = |start: u64, len: usize| &payload[start as usize..start as usize + len];
        let relocation_words = decode_words(section(
            self.payload_layout.relocations,
            relocation_count * 32,
        ));
        let undefined_words = decode_words(section(
            self.payload_layout.undefined_symbols,
            symbol_count * 16,
        ));
        let definition_words = decode_words(section(
            self.payload_layout.definitions,
            definition_count * 32,
        ));
        let text = section(self.payload_layout.text, text_len).to_vec();
        let rodata = section(self.payload_layout.rodata, rodata_len).to_vec();

        let mut relocations = Vec::with_capacity(relocation_count);
        for (index, row) in relocation_words.chunks_exact(8).enumerate() {
            let kind = match row[0] {
                1 => GpuX86RelocationKind::Rel32,
                2 => GpuX86RelocationKind::CallRel32,
                3 => GpuX86RelocationKind::Abs32,
                value => anyhow::bail!("GPU x86 object relocation {index} has kind {value}"),
            };
            let site_section = section_tag(row[1], "relocation site", index)?;
            let target_kind = match row[3] {
                1 => GpuX86RelocationTargetKind::SectionOffset,
                2 => GpuX86RelocationTargetKind::Symbol,
                value => anyhow::bail!("GPU x86 object relocation {index} has target kind {value}"),
            };
            relocations.push(GpuX86RelocationRecord {
                kind,
                site_section,
                site_offset: row[2],
                target_kind,
                target_index: row[4],
                target_offset: row[5],
                addend: ((u64::from(row[7]) << 32) | u64::from(row[6])) as i64,
            });
        }
        let mut identity_bytes = Vec::with_capacity((symbol_count + definition_count) * 12);
        let mut symbols = Vec::with_capacity(symbol_count + definition_count);
        for row in undefined_words.chunks_exact(4) {
            push_symbol(
                &mut identity_bytes,
                &mut symbols,
                [row[0], row[1], row[2]],
                GpuX86ObjectSection::Undefined,
                0,
                0,
                0,
            );
        }
        for (index, row) in definition_words.chunks_exact(8).enumerate() {
            if row[0] != library_id || row[1] != unit_id {
                anyhow::bail!(
                    "GPU x86 object definition {index} identity [{}, {}] does not match requested unit [{library_id}, {unit_id}]",
                    row[0],
                    row[1],
                );
            }
            push_symbol(
                &mut identity_bytes,
                &mut symbols,
                [row[0], row[1], row[2]],
                section_tag(row[3], "definition", index)?,
                row[4],
                row[5],
                row[6],
            );
        }
        drop(payload);
        self.payload_readback.unmap();

        let object = GpuX86RelocatableObject {
            version: GPU_X86_OBJECT_VERSION,
            library_id,
            unit_id,
            entry_offset: (entrypoint_count == 1).then_some(0),
            text,
            rodata,
            relocations,
            symbols,
            identity_bytes,
        };
        object.validate().map_err(anyhow::Error::msg)?;
        Ok(object)
    }
}

impl ObjectReadbackLayout {
    fn new(target_capacity: u32, function_capacity: u32, artifact_capacity: u32) -> Self {
        let relocations = 0;
        let undefined_symbols = u64::from(target_capacity) * 32;
        let definitions = undefined_symbols + u64::from(target_capacity) * 16;
        let text = definitions + u64::from(function_capacity) * 32;
        let artifact_bytes = u64::from(artifact_capacity.div_ceil(4) * 4);
        let rodata = text + artifact_bytes;
        Self {
            relocations,
            undefined_symbols,
            definitions,
            text,
            rodata,
            total: rodata + artifact_bytes,
        }
    }
}

fn decode_words(bytes: &[u8]) -> Vec<u32> {
    bytes
        .chunks_exact(4)
        .map(|word| u32::from_le_bytes(word.try_into().unwrap()))
        .collect()
}

fn section_tag(value: u32, owner: &str, index: usize) -> Result<GpuX86ObjectSection> {
    match value {
        0 => Ok(GpuX86ObjectSection::Undefined),
        1 => Ok(GpuX86ObjectSection::Text),
        2 => Ok(GpuX86ObjectSection::Rodata),
        _ => anyhow::bail!("GPU x86 object {owner} {index} has section {value}"),
    }
}

fn push_symbol(
    identity_bytes: &mut Vec<u8>,
    symbols: &mut Vec<GpuX86ObjectSymbolRecord>,
    identity: [u32; 3],
    section: GpuX86ObjectSection,
    offset: u32,
    size: u32,
    flags: u32,
) {
    let identity_byte_start = identity_bytes.len() as u32;
    for word in identity {
        identity_bytes.extend_from_slice(&word.to_le_bytes());
    }
    let bytes = &identity_bytes[identity_byte_start as usize..];
    let (identity_hash_lo, identity_hash_hi) = crate::compiler::stable_name_hash(bytes);
    symbols.push(GpuX86ObjectSymbolRecord {
        identity_hash_lo,
        identity_hash_hi,
        identity_byte_start,
        identity_byte_len: 12,
        section,
        offset,
        size,
        flags,
    });
}

#[allow(clippy::too_many_arguments)]
fn validate_primary_passes(
    graph: &CompilerGraph,
    allocations: &CompilerGraphAllocations,
    semantic: GpuSemanticLirView<'_>,
    target_total: &LaniusBuffer<u32>,
    target_core: &LaniusBuffer<X86LirCore>,
    target_operands: &LaniusBuffer<X86LirOperands>,
    scheduled_function_ids: &LaniusBuffer<u32>,
    target_functions: GpuTargetFunctionView<'_>,
    artifact: GpuX86ArtifactObjectView<'_>,
    relocation_flags: &LaniusBuffer<u32>,
    relocation_prefix: &LaniusBuffer<u32>,
    symbol_flags: &LaniusBuffer<u32>,
    symbol_prefix: &LaniusBuffer<u32>,
    definition_flags: &LaniusBuffer<u32>,
    definition_prefix: &LaniusBuffer<u32>,
    relocations: &LaniusBuffer<X86ObjectRelocationRow>,
    undefined_symbols: &LaniusBuffer<X86ObjectUndefinedRow>,
    definitions: &LaniusBuffer<X86ObjectDefinitionRow>,
    text_words: &LaniusBuffer<u32>,
    rodata_words: &LaniusBuffer<u32>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    let run = |pass: &str, bindings: Vec<BoundGraphResource>| {
        allocations
            .validate_pass_bindings(graph, graph.pass_id(pass).unwrap(), &bindings)
            .map_err(anyhow::Error::msg)
    };
    run(
        "artifact.x86.object.normalize_status",
        vec![
            bound(
                "x86_entrypoint_state",
                resource("lir.x86.entrypoint_state"),
                artifact.entrypoint_state,
            )?,
            bound(
                "x86_artifact_layout",
                resource("lir.x86.artifact_layout"),
                artifact.layout,
            )?,
            bound(
                "lowering_status",
                resource("lowering.status"),
                semantic.status,
            )?,
        ],
    )?;
    run(
        "artifact.x86.object.relocation_flags",
        vec![
            bound("target_lir_total", resource("lir.x86.total"), target_total)?,
            bound("target_lir_core", resource("lir.x86.core"), target_core)?,
            bound(
                "x86_object_relocation_flag",
                resource("artifact.x86.object.relocation_flags"),
                relocation_flags,
            )?,
            bound(
                "x86_object_symbol_flag",
                resource("artifact.x86.object.symbol_flags"),
                symbol_flags,
            )?,
        ],
    )?;
    run(
        "artifact.x86.object.definition_flags",
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
                "x86_object_definition_flag",
                resource("artifact.x86.object.definition_flags"),
                definition_flags,
            )?,
        ],
    )?;
    run(
        "artifact.x86.object.relocations",
        vec![
            bound("target_lir_total", resource("lir.x86.total"), target_total)?,
            bound("target_lir_core", resource("lir.x86.core"), target_core)?,
            bound(
                "target_lir_operands",
                resource("lir.x86.operands"),
                target_operands,
            )?,
            bound(
                "scheduled_function_id",
                resource("lir.target.scheduled_function_ids"),
                scheduled_function_ids,
            )?,
            bound(
                "target_function_count",
                resource("lir.target.function_count"),
                target_functions.count,
            )?,
            bound(
                "target_functions",
                resource("lir.target.functions"),
                target_functions.rows,
            )?,
            bound(
                "target_function_index_by_semantic",
                resource("lir.target.function_index_by_semantic"),
                target_functions.index_by_semantic,
            )?,
            bound(
                "target_byte_length",
                resource("lir.x86.byte_lengths"),
                artifact.byte_lengths,
            )?,
            bound(
                "target_byte_offset",
                resource("lir.x86.byte_offsets"),
                artifact.byte_offsets,
            )?,
            bound(
                "x86_artifact_layout",
                resource("lir.x86.artifact_layout"),
                artifact.layout,
            )?,
            bound(
                "semantic_lir_string_total",
                resource("lir.semantic.string_total"),
                semantic.string_count,
            )?,
            bound(
                "semantic_lir_strings",
                resource("lir.semantic.strings"),
                semantic.strings,
            )?,
            bound(
                "x86_object_relocation_flag",
                resource("artifact.x86.object.relocation_flags"),
                relocation_flags,
            )?,
            bound(
                "x86_object_relocation_prefix",
                resource("artifact.x86.object.relocation_prefix"),
                relocation_prefix,
            )?,
            bound(
                "x86_object_symbol_prefix",
                resource("artifact.x86.object.symbol_prefix"),
                symbol_prefix,
            )?,
            bound(
                "x86_object_relocations",
                resource("artifact.x86.object.relocations"),
                relocations,
            )?,
            bound(
                "x86_object_undefined_symbols",
                resource("artifact.x86.object.undefined_symbols"),
                undefined_symbols,
            )?,
        ],
    )?;
    run(
        "artifact.x86.object.definitions",
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
                "target_function_count",
                resource("lir.target.function_count"),
                target_functions.count,
            )?,
            bound(
                "target_functions",
                resource("lir.target.functions"),
                target_functions.rows,
            )?,
            bound(
                "target_function_index_by_semantic",
                resource("lir.target.function_index_by_semantic"),
                target_functions.index_by_semantic,
            )?,
            bound(
                "target_byte_length",
                resource("lir.x86.byte_lengths"),
                artifact.byte_lengths,
            )?,
            bound(
                "target_byte_offset",
                resource("lir.x86.byte_offsets"),
                artifact.byte_offsets,
            )?,
            bound(
                "x86_artifact_layout",
                resource("lir.x86.artifact_layout"),
                artifact.layout,
            )?,
            bound(
                "x86_object_definition_flag",
                resource("artifact.x86.object.definition_flags"),
                definition_flags,
            )?,
            bound(
                "x86_object_definition_prefix",
                resource("artifact.x86.object.definition_prefix"),
                definition_prefix,
            )?,
            bound(
                "x86_object_definitions",
                resource("artifact.x86.object.definitions"),
                definitions,
            )?,
        ],
    )?;
    run(
        "artifact.x86.object.bytes",
        vec![
            bound(
                "x86_artifact_layout",
                resource("lir.x86.artifact_layout"),
                artifact.layout,
            )?,
            bound(
                "x86_artifact_bytes",
                resource("artifact.x86.bytes"),
                artifact.words,
            )?,
            bound(
                "x86_object_text_bytes",
                resource("artifact.x86.object.text_bytes"),
                text_words,
            )?,
            bound(
                "x86_object_rodata_bytes",
                resource("artifact.x86.object.rodata_bytes"),
                rodata_words,
            )?,
        ],
    )
}

fn scan_contract(kind: &'static str, count: &'static str) -> GraphScanContract {
    match kind {
        "relocation" => GraphScanContract {
            local_pass: "artifact.x86.object.relocation_scan.local",
            up_pass: "artifact.x86.object.relocation_scan.hierarchy_up",
            down_pass: "artifact.x86.object.relocation_scan.hierarchy_down",
            apply_pass: "artifact.x86.object.relocation_scan.apply",
            count,
            input: "artifact.x86.object.relocation_flags",
            local: "artifact.x86.object.relocation_scan_local",
            block_sum: "artifact.x86.object.relocation_scan_block_sum",
            block_prefix: "artifact.x86.object.relocation_scan_block_prefix",
            hierarchy: "artifact.x86.object.relocation_scan_hierarchy",
            output: "artifact.x86.object.relocation_prefix",
            total: "artifact.x86.object.relocation_total",
        },
        "symbol" => GraphScanContract {
            local_pass: "artifact.x86.object.symbol_scan.local",
            up_pass: "artifact.x86.object.symbol_scan.hierarchy_up",
            down_pass: "artifact.x86.object.symbol_scan.hierarchy_down",
            apply_pass: "artifact.x86.object.symbol_scan.apply",
            count,
            input: "artifact.x86.object.symbol_flags",
            local: "artifact.x86.object.symbol_scan_local",
            block_sum: "artifact.x86.object.symbol_scan_block_sum",
            block_prefix: "artifact.x86.object.symbol_scan_block_prefix",
            hierarchy: "artifact.x86.object.symbol_scan_hierarchy",
            output: "artifact.x86.object.symbol_prefix",
            total: "artifact.x86.object.symbol_total",
        },
        "definition" => GraphScanContract {
            local_pass: "artifact.x86.object.definition_scan.local",
            up_pass: "artifact.x86.object.definition_scan.hierarchy_up",
            down_pass: "artifact.x86.object.definition_scan.hierarchy_down",
            apply_pass: "artifact.x86.object.definition_scan.apply",
            count,
            input: "artifact.x86.object.definition_flags",
            local: "artifact.x86.object.definition_scan_local",
            block_sum: "artifact.x86.object.definition_scan_block_sum",
            block_prefix: "artifact.x86.object.definition_scan_block_prefix",
            hierarchy: "artifact.x86.object.definition_scan_hierarchy",
            output: "artifact.x86.object.definition_prefix",
            total: "artifact.x86.object.definition_total",
        },
        _ => unreachable!(),
    }
}

fn load(device: &wgpu::Device, label: &str, shader: &str) -> Result<PassData> {
    make_pass_data_from_shader_key(device, label, "main", shader)
}
