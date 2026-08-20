//! Graph-native projection of scheduled Wasm LIR into durable object columns.
//!
//! This stage does not inspect source, tokens, or HIR. GPU scans compact the
//! target rows that need relocations, the subset that needs undefined symbols,
//! and semantic functions that define public symbols. The host only validates
//! and serializes those flat artifact rows.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    lowering::GpuSemanticLirView,
    lowering_ir::{
        LoweringCapacities,
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
    compiler_graph::{CompilerGraph, CompilerGraphAllocations, CompilerGraphWorkspace},
    kernels::KernelRegistry,
    operations::{ComputeOperation, CopyBufferOperation},
    passes_core::{PassData, map_readback_blocking},
    readback::{PagedReadback, ReadbackRegion},
    resource_registry::ResourceMap,
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

#[cfg(test)]
#[derive(Clone, Copy)]
pub(crate) struct GpuWasmObjectView<'a> {
    pub relocation_count: &'a LaniusBuffer<u32>,
    pub symbol_count: &'a LaniusBuffer<u32>,
    pub definition_count: &'a LaniusBuffer<u32>,
    pub relocations: &'a LaniusBuffer<WasmObjectRelocationRow>,
    pub functions: &'a LaniusBuffer<WasmObjectFunctionRow>,
    pub definitions: &'a LaniusBuffer<WasmObjectDefinitionRow>,
}

pub(crate) struct GpuWasmObjectStage {
    relocation_capacity: u32,
    function_capacity: u32,
    artifact_capacity: u32,
    relocation_flags: ComputeOperation,
    definition_flags_op: ComputeOperation,
    relocations_op: ComputeOperation,
    functions_op: ComputeOperation,
    bytes_op: ComputeOperation,
    relocation_scan: GpuResidentExclusiveScan,
    symbol_scan: GpuResidentExclusiveScan,
    definition_scan: GpuResidentExclusiveScan,
    _params: LaniusBuffer<WasmObjectParams>,
    identity: LaniusBuffer<WasmObjectIdentity>,
    _relocation_flags: LaniusBuffer<u32>,
    _relocation_prefix: LaniusBuffer<u32>,
    _relocation_total: LaniusBuffer<u32>,
    _symbol_flags: LaniusBuffer<u32>,
    _symbol_prefix: LaniusBuffer<u32>,
    _symbol_total: LaniusBuffer<u32>,
    _definition_flags: LaniusBuffer<u32>,
    _definition_prefix: LaniusBuffer<u32>,
    _definition_total: LaniusBuffer<u32>,
    relocations: LaniusBuffer<WasmObjectRelocationRow>,
    functions: LaniusBuffer<WasmObjectFunctionRow>,
    definitions: LaniusBuffer<WasmObjectDefinitionRow>,
    type_words: LaniusBuffer<u32>,
    body_words: LaniusBuffer<u32>,
    data_words: LaniusBuffer<u32>,
    metadata_readback_copies: Vec<CopyBufferOperation>,
    metadata_readback: LaniusBuffer<u8>,
    payload_readback: PagedReadback,
}

impl GpuWasmObjectStage {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        capacities: LoweringCapacities,
        semantic: GpuSemanticLirView<'_>,
        module: GpuWasmModuleObjectView<'_>,
    ) -> Result<Self> {
        let target_capacity = capacities.target_instructions.max(1);
        let relocation_capacity = capacities.semantic_instructions.max(1);
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
        let relocation_flags =
            alias_u32("artifact.wasm.object.relocation_flags", relocation_capacity)?;
        let relocation_prefix = alias_u32(
            "artifact.wasm.object.relocation_prefix",
            relocation_capacity,
        )?;
        let relocation_total = alias_u32("artifact.wasm.object.relocation_total", 1)?;
        let symbol_flags = alias_u32("artifact.wasm.object.symbol_flags", relocation_capacity)?;
        let symbol_prefix = alias_u32("artifact.wasm.object.symbol_prefix", relocation_capacity)?;
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
                relocation_capacity as usize,
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
        let data_words = alias_u32(
            "artifact.wasm.object.data_bytes",
            artifact_capacity.div_ceil(4),
        )?;
        let metadata_readback =
            readback_bytes(device, "artifact.wasm.object.metadata.readback", 96, 96);
        let payload_readback = PagedReadback::new(
            device,
            "artifact.wasm.object.payload.readback",
            (artifact_capacity as usize).min(4 << 20),
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
            kernels,
            "artifact.wasm.object.relocation_flags",
            "codegen/lir/wasm/object_relocation_flags",
        )?;
        let definition_flags_pass = load(
            kernels,
            "artifact.wasm.object.definition_flags",
            "codegen/lir/wasm/object_definition_flags",
        )?;
        let relocations_pass = load(
            kernels,
            "artifact.wasm.object.relocations",
            "codegen/lir/wasm/object_relocations",
        )?;
        let functions_pass = load(
            kernels,
            "artifact.wasm.object.functions",
            "codegen/lir/wasm/object_functions",
        )?;
        let bytes_pass = load(
            kernels,
            "artifact.wasm.object.bytes",
            "codegen/lir/wasm/object_bytes",
        )?;

        let graph_bindings = workspace.bindings(graph).map_err(anyhow::Error::msg)?;
        let mut resources = ResourceMap::new();
        resources.register_graph_bindings(graph, &graph_bindings);
        semantic.register(graph, &mut resources)?;
        let context = (graph, allocations);
        let relocation_flags_op = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "artifact.wasm.object.relocation_flags",
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
            scan_contract("relocation", "lir.semantic.total"),
            relocation_capacity,
            semantic.count,
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
            scan_contract("symbol", "lir.semantic.total"),
            relocation_capacity,
            semantic.count,
            &symbol_flags,
            &symbol_prefix,
            &symbol_total,
        )?;
        let definition_flags_op = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "artifact.wasm.object.definition_flags",
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
            semantic.function_count,
            &definition_flags,
            &definition_prefix,
            &definition_total,
        )?;
        let relocations_op = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "artifact.wasm.object.relocations",
            &relocations_pass,
            &params,
            relocation_capacity,
        )?;
        let mut identity_resources = resources.clone();
        identity_resources.buffer("gParams", &params);
        identity_resources.buffer("gIdentity", &identity);
        let functions_op = ComputeOperation::direct(
            device,
            &context,
            &identity_resources,
            "artifact.wasm.object.functions",
            &functions_pass,
            function_capacity,
        )?;
        let bytes_op = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "artifact.wasm.object.bytes",
            &bytes_pass,
            &params,
            artifact_capacity,
        )?;
        let metadata_readback_copies = [
            (
                "artifact.wasm.object.function_count.readback",
                "function_count",
                semantic.function_count,
                0,
            ),
            (
                "artifact.wasm.object.type_total.readback",
                "type_total",
                module.type_total,
                4,
            ),
            (
                "artifact.wasm.object.code_total.readback",
                "code_total",
                module.code_total,
                8,
            ),
            (
                "artifact.wasm.object.relocation_total.readback",
                "relocation_total",
                &relocation_total,
                12,
            ),
            (
                "artifact.wasm.object.symbol_total.readback",
                "symbol_total",
                &symbol_total,
                16,
            ),
            (
                "artifact.wasm.object.definition_total.readback",
                "definition_total",
                &definition_total,
                20,
            ),
            (
                "artifact.wasm.object.string_pool_len.readback",
                "string_pool_len",
                semantic.string_pool_len,
                24,
            ),
        ]
        .into_iter()
        .map(|(name, source_binding, source, destination_offset)| {
            CopyBufferOperation::new(
                &context,
                name,
                source_binding,
                source,
                0,
                "metadata_readback",
                &metadata_readback,
                destination_offset,
                4,
            )
        })
        .chain(std::iter::once(CopyBufferOperation::new(
            &context,
            "artifact.wasm.object.layout.readback",
            "module_layout",
            module.layout,
            0,
            "metadata_readback",
            &metadata_readback,
            32,
            64,
        )))
        .collect::<Result<Vec<_>>>()?;

        Ok(Self {
            relocation_capacity,
            function_capacity,
            artifact_capacity,
            relocation_flags: relocation_flags_op,
            definition_flags_op,
            relocations_op,
            functions_op,
            bytes_op,
            relocation_scan,
            symbol_scan,
            definition_scan,
            _params: params,
            identity,
            _relocation_flags: relocation_flags,
            _relocation_prefix: relocation_prefix,
            _relocation_total: relocation_total,
            _symbol_flags: symbol_flags,
            _symbol_prefix: symbol_prefix,
            _symbol_total: symbol_total,
            _definition_flags: definition_flags,
            _definition_prefix: definition_prefix,
            _definition_total: definition_total,
            relocations,
            functions,
            definitions,
            type_words,
            body_words,
            data_words,
            metadata_readback_copies,
            metadata_readback,
            payload_readback,
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
        self.identity.write(queue, 0, bytes.as_ref());
    }

    #[cfg(test)]
    pub(crate) fn output(&self) -> GpuWasmObjectView<'_> {
        GpuWasmObjectView {
            relocation_count: &self._relocation_total,
            symbol_count: &self._symbol_total,
            definition_count: &self._definition_total,
            relocations: &self.relocations,
            functions: &self.functions,
            definitions: &self.definitions,
        }
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.relocation_flags.record(encoder)?;
        self.relocation_scan.record(encoder)?;
        self.symbol_scan.record(encoder)?;
        self.definition_flags_op.record(encoder)?;
        self.definition_scan.record(encoder)?;
        self.relocations_op.record(encoder)?;
        self.functions_op.record(encoder)?;
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
        let data_len = word(6) as usize;
        let layout_words = (8..24).map(word).collect::<Vec<_>>();
        drop(metadata);
        self.metadata_readback.unmap();
        if function_count > self.function_capacity as usize
            || relocation_count > self.relocation_capacity as usize
            || symbol_count > relocation_count
            || definition_count > self.function_capacity as usize
            || type_len > self.artifact_capacity as usize
            || body_len > self.artifact_capacity as usize
            || data_len > self.artifact_capacity as usize
        {
            anyhow::bail!(
                "GPU Wasm object metadata exceeds resident capacity: functions={function_count}/{}, relocations={relocation_count}/{}, symbols={symbol_count}, definitions={definition_count}/{}, type={type_len}/{}, body={body_len}/{}",
                self.function_capacity,
                self.relocation_capacity,
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

        let [
            function_bytes,
            relocation_bytes,
            definition_bytes,
            type_bytes,
            body_bytes,
            data_bytes,
        ]: [Vec<u8>; 6] = self
            .payload_readback
            .read_regions(
                device,
                queue,
                &[
                    ReadbackRegion::from_buffer(
                        &self.functions,
                        0,
                        function_count * 24,
                        "Wasm object functions",
                    )?,
                    ReadbackRegion::from_buffer(
                        &self.relocations,
                        0,
                        relocation_count * 32,
                        "Wasm object relocations",
                    )?,
                    ReadbackRegion::from_buffer(
                        &self.definitions,
                        0,
                        definition_count * 32,
                        "Wasm object definitions",
                    )?,
                    ReadbackRegion::from_buffer(
                        &self.type_words,
                        0,
                        type_len,
                        "Wasm object types",
                    )?,
                    ReadbackRegion::from_buffer(
                        &self.body_words,
                        0,
                        body_len,
                        "Wasm object bodies",
                    )?,
                    ReadbackRegion::from_buffer(&self.data_words, 0, data_len, "Wasm object data")?,
                ],
                "Wasm object payload readback",
            )?
            .try_into()
            .map_err(|_| anyhow::anyhow!("Wasm object payload readback shape changed"))?;
        let function_words = decode_words(&function_bytes);
        let relocation_words = decode_words(&relocation_bytes);
        let definition_words = decode_words(&definition_bytes);

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
                3 => GpuWasmRelocationTargetKind::DataOffset,
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
        let object = GpuWasmRelocatableObject {
            version: GPU_WASM_OBJECT_VERSION,
            library_id,
            unit_id,
            entry_function: (entrypoint_count == 1).then_some(entrypoint_id),
            functions,
            type_bytes,
            body_bytes,
            data_bytes,
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

fn load(kernels: &KernelRegistry, _label: &str, shader: &str) -> Result<PassData> {
    Ok(kernels.kernel(shader).clone())
}
