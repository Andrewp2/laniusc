//! Graph-native projection of scheduled x86 LIR into durable object columns.
//!
//! The target emitter produces body, runtime, and rodata bytes on the GPU.
//! This stage compacts relocation and symbol rows and projects those section
//! bytes without inspecting source, tokens, HIR, or target instructions on the
//! host. The host only validates and serializes the flat object contract.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    lowering_ir::{
        LoweringCapacities,
        X86ObjectDefinitionRow,
        X86ObjectRelocationRow,
        X86ObjectUndefinedRow,
    },
    optimization::GpuOptIrView,
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
    compiler_graph::{CompilerGraph, CompilerGraphAllocations, CompilerGraphWorkspace},
    kernels::KernelRegistry,
    operations::{ComputeOperation, CopyBufferOperation},
    passes_core::{PassData, map_readback_blocking},
    readback::{PagedReadback, ReadbackRegion},
    resource_registry::ResourceMap,
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
    relocation_capacity: u32,
    function_capacity: u32,
    artifact_capacity: u32,
    normalize_status: ComputeOperation,
    relocation_flags: ComputeOperation,
    definition_flags_op: ComputeOperation,
    relocations_op: ComputeOperation,
    definitions_op: ComputeOperation,
    bytes_op: ComputeOperation,
    relocation_scan: GpuResidentExclusiveScan,
    symbol_scan: GpuResidentExclusiveScan,
    definition_scan: GpuResidentExclusiveScan,
    _params: LaniusBuffer<X86ObjectParams>,
    identity: LaniusBuffer<X86ObjectIdentity>,
    _relocation_flags: LaniusBuffer<u32>,
    _relocation_prefix: LaniusBuffer<u32>,
    _symbol_flags: LaniusBuffer<u32>,
    _symbol_prefix: LaniusBuffer<u32>,
    _definition_flags: LaniusBuffer<u32>,
    _definition_prefix: LaniusBuffer<u32>,
    relocations: LaniusBuffer<X86ObjectRelocationRow>,
    undefined_symbols: LaniusBuffer<X86ObjectUndefinedRow>,
    definitions: LaniusBuffer<X86ObjectDefinitionRow>,
    text_words: LaniusBuffer<u32>,
    rodata_words: LaniusBuffer<u32>,
    metadata_readback_copies: Vec<CopyBufferOperation>,
    metadata_readback: LaniusBuffer<u8>,
    payload_readback: PagedReadback,
}

impl GpuX86ObjectStage {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        capacities: LoweringCapacities,
        opt: GpuOptIrView<'_>,
        artifact: GpuX86ArtifactObjectView<'_>,
    ) -> Result<Self> {
        let metadata = opt.metadata;
        let target_capacity = capacities.target_instructions.max(1);
        let relocation_capacity = capacities.semantic_instructions.max(1);
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
        let relocation_flags =
            alias_u32("artifact.x86.object.relocation_flags", relocation_capacity)?;
        let relocation_prefix =
            alias_u32("artifact.x86.object.relocation_prefix", relocation_capacity)?;
        let relocation_total = alias_u32("artifact.x86.object.relocation_total", 1)?;
        let symbol_flags = alias_u32("artifact.x86.object.symbol_flags", relocation_capacity)?;
        let symbol_prefix = alias_u32("artifact.x86.object.symbol_prefix", relocation_capacity)?;
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
                relocation_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let undefined_symbols = workspace
            .alias(
                graph,
                resource("artifact.x86.object.undefined_symbols")?,
                relocation_capacity as usize,
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
        let metadata_readback =
            readback_bytes(device, "artifact.x86.object.metadata.readback", 64, 64);
        let payload_readback = PagedReadback::new(
            device,
            "artifact.x86.object.payload.readback",
            (artifact_capacity as usize).min(4 << 20),
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
            kernels,
            "artifact.x86.object.normalize_status",
            "codegen/lir/x86/object_normalize_status",
        )?;

        let relocation_flags_pass = load(
            kernels,
            "artifact.x86.object.relocation_flags",
            "codegen/lir/x86/object_relocation_flags",
        )?;
        let definition_flags_pass = load(
            kernels,
            "artifact.x86.object.definition_flags",
            "codegen/lir/x86/object_definition_flags",
        )?;
        let relocations_pass = load(
            kernels,
            "artifact.x86.object.relocations",
            "codegen/lir/x86/object_relocations",
        )?;
        let definitions_pass = load(
            kernels,
            "artifact.x86.object.definitions",
            "codegen/lir/x86/object_definitions",
        )?;
        let bytes_pass = load(
            kernels,
            "artifact.x86.object.bytes",
            "codegen/lir/x86/object_bytes",
        )?;

        let graph_bindings = workspace.bindings(graph).map_err(anyhow::Error::msg)?;
        let mut resources = ResourceMap::new();
        resources.register_graph_bindings(graph, &graph_bindings);
        opt.register(graph, &mut resources)?;
        let context = (graph, allocations);
        let normalize_status = ComputeOperation::direct(
            device,
            &context,
            &resources,
            "artifact.x86.object.normalize_status",
            &normalize_status_pass,
            1,
        )?;
        let relocation_flags_op = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "artifact.x86.object.relocation_flags",
            &relocation_flags_pass,
            &params,
            relocation_capacity,
        )?;
        let relocation_scan = GpuResidentExclusiveScan::new(
            device,
            kernels,
            graph,
            workspace,
            allocations,
            scan_contract("relocation", "lir.opt.total"),
            relocation_capacity,
            opt.count,
            &relocation_flags,
            &relocation_prefix,
            &relocation_total,
        )?;
        let symbol_scan = GpuResidentExclusiveScan::new(
            device,
            kernels,
            graph,
            workspace,
            allocations,
            scan_contract("symbol", "lir.opt.total"),
            relocation_capacity,
            opt.count,
            &symbol_flags,
            &symbol_prefix,
            &symbol_total,
        )?;
        let definition_flags_op = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "artifact.x86.object.definition_flags",
            &definition_flags_pass,
            &params,
            function_capacity,
        )?;
        let definition_scan = GpuResidentExclusiveScan::new(
            device,
            kernels,
            graph,
            workspace,
            allocations,
            scan_contract("definition", "lir.semantic.function_total"),
            function_capacity,
            metadata.function_count,
            &definition_flags,
            &definition_prefix,
            &definition_total,
        )?;
        let relocations_op = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "artifact.x86.object.relocations",
            &relocations_pass,
            &params,
            relocation_capacity,
        )?;
        let mut identity_resources = resources.clone();
        identity_resources.buffer("gParams", &params);
        identity_resources.buffer("gIdentity", &identity);
        let definitions_op = ComputeOperation::direct(
            device,
            &context,
            &identity_resources,
            "artifact.x86.object.definitions",
            &definitions_pass,
            function_capacity,
        )?;
        let bytes_op = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "artifact.x86.object.bytes",
            &bytes_pass,
            &params,
            artifact_capacity,
        )?;
        let metadata_readback_copies = [
            (
                "artifact.x86.object.relocation_total.readback",
                "relocation_total",
                &relocation_total,
                0,
                4,
                4,
            ),
            (
                "artifact.x86.object.symbol_total.readback",
                "symbol_total",
                &symbol_total,
                0,
                8,
                4,
            ),
            (
                "artifact.x86.object.definition_total.readback",
                "definition_total",
                &definition_total,
                0,
                12,
                4,
            ),
        ]
        .into_iter()
        .map(
            |(name, source_binding, source, source_offset, destination_offset, size)| {
                CopyBufferOperation::new(
                    &context,
                    name,
                    source_binding,
                    source,
                    source_offset,
                    "metadata_readback",
                    &metadata_readback,
                    destination_offset,
                    size,
                )
            },
        )
        .chain(std::iter::once(CopyBufferOperation::new(
            &context,
            "artifact.x86.object.layout.readback",
            "artifact_layout",
            artifact.layout,
            0,
            "metadata_readback",
            &metadata_readback,
            16,
            48,
        )))
        .collect::<Result<Vec<_>>>()?;

        Ok(Self {
            relocation_capacity,
            function_capacity,
            artifact_capacity,
            normalize_status,
            relocation_flags: relocation_flags_op,
            definition_flags_op,
            relocations_op,
            definitions_op,
            bytes_op,
            relocation_scan,
            symbol_scan,
            definition_scan,
            _params: params,
            identity,
            _relocation_flags: relocation_flags,
            _relocation_prefix: relocation_prefix,
            _symbol_flags: symbol_flags,
            _symbol_prefix: symbol_prefix,
            _definition_flags: definition_flags,
            _definition_prefix: definition_prefix,
            relocations,
            undefined_symbols,
            definitions,
            text_words,
            rodata_words,
            metadata_readback_copies,
            metadata_readback,
            payload_readback,
        })
    }

    pub(crate) fn set_identity(&self, queue: &wgpu::Queue, library_id: u32, unit_id: u32) {
        if crate::gpu::env::env_bool_truthy("LANIUS_OBJECT_ID_TRACE", false) {
            eprintln!("[x86_object_identity] set library={library_id} unit={unit_id}");
        }
        let value = X86ObjectIdentity {
            library_id,
            unit_id,
            reserved0: 0,
            reserved1: 0,
        };
        let mut bytes = encase::UniformBuffer::new(Vec::new());
        bytes.write(&value).expect("x86 object identity encodes");
        if crate::gpu::env::env_bool_truthy("LANIUS_OBJECT_ID_TRACE", false) {
            eprintln!("[x86_object_identity] bytes={:?}", bytes.as_ref());
        }
        self.identity.write(queue, 0, bytes.as_ref());
    }

    pub(crate) fn record_status_normalization(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.normalize_status.record(encoder)
    }

    pub(crate) fn record_projection(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.relocation_flags.record(encoder)?;
        self.relocation_scan.record(encoder)?;
        self.symbol_scan.record(encoder)?;
        self.definition_flags_op.record(encoder)?;
        self.definition_scan.record(encoder)?;
        self.relocations_op.record(encoder)?;
        self.definitions_op.record(encoder)?;
        self.bytes_op.record(encoder)?;
        for copy in &self.metadata_readback_copies {
            copy.record(encoder);
        }
        Ok(())
    }

    pub(crate) fn finish(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
    ) -> Result<GpuX86RelocatableObject> {
        if crate::gpu::env::env_bool_truthy("LANIUS_OBJECT_ID_TRACE", false) {
            eprintln!("[x86_object_identity] finish requested library={library_id} unit={unit_id}");
        }
        let metadata_slice = self.metadata_readback.slice(..);
        map_readback_blocking(device, &metadata_slice, "x86 object metadata readback")?;
        let metadata = metadata_slice.get_mapped_range();
        let word = |index: usize| {
            u32::from_le_bytes(metadata[index * 4..index * 4 + 4].try_into().unwrap())
        };
        let relocation_count = word(1) as usize;
        let symbol_count = word(2) as usize;
        let definition_count = word(3) as usize;
        if crate::gpu::env::env_bool_truthy("LANIUS_OBJECT_ID_TRACE", false) {
            eprintln!(
                "[x86_object_identity] counts relocations={relocation_count} symbols={symbol_count} definitions={definition_count}"
            );
        }
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
        if relocation_count > self.relocation_capacity as usize
            || symbol_count > relocation_count
            || definition_count > self.function_capacity as usize
            || text_len > self.artifact_capacity as usize
            || rodata_len > self.artifact_capacity as usize
        {
            anyhow::bail!(
                "GPU x86 object metadata exceeds resident capacity: relocations={relocation_count}/{}, symbols={symbol_count}, definitions={definition_count}/{}, text={text_len}/{}, rodata={rodata_len}/{}",
                self.relocation_capacity,
                self.function_capacity,
                self.artifact_capacity,
                self.artifact_capacity,
            );
        }

        let [
            relocation_bytes,
            undefined_bytes,
            definition_bytes,
            text,
            rodata,
        ]: [Vec<u8>; 5] = self
            .payload_readback
            .read_regions(
                device,
                queue,
                &[
                    ReadbackRegion::from_buffer(
                        &self.relocations,
                        0,
                        relocation_count * 32,
                        "x86 object relocations",
                    )?,
                    ReadbackRegion::from_buffer(
                        &self.undefined_symbols,
                        0,
                        symbol_count * 16,
                        "x86 object undefined symbols",
                    )?,
                    ReadbackRegion::from_buffer(
                        &self.definitions,
                        0,
                        definition_count * 32,
                        "x86 object definitions",
                    )?,
                    ReadbackRegion::from_buffer(&self.text_words, 0, text_len, "x86 object text")?,
                    ReadbackRegion::from_buffer(
                        &self.rodata_words,
                        0,
                        rodata_len,
                        "x86 object rodata",
                    )?,
                ],
                "x86 object payload readback",
            )?
            .try_into()
            .map_err(|_| anyhow::anyhow!("x86 object payload readback shape changed"))?;
        let relocation_words = decode_words(&relocation_bytes);
        let undefined_words = decode_words(&undefined_bytes);
        let definition_words = decode_words(&definition_bytes);
        if crate::gpu::env::env_bool_truthy("LANIUS_OBJECT_ID_TRACE", false) {
            let identities = definition_words
                .chunks_exact(8)
                .map(|row| [row[0], row[1], row[2]])
                .collect::<Vec<_>>();
            eprintln!("[x86_object_identity] definition_identities={identities:?}");
            eprintln!("[x86_object_identity] relocation_words={relocation_words:?}");
            eprintln!("[x86_object_identity] undefined_words={undefined_words:?}");
        }
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

fn load(kernels: &KernelRegistry, _label: &str, shader: &str) -> Result<PassData> {
    Ok(kernels.kernel(shader).clone())
}
