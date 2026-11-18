//! Graph-native projection of scheduled x86 LIR into durable object columns.
//!
//! The target emitter produces body, runtime, and rodata bytes on the GPU.
//! This stage compacts relocation and symbol rows and projects those section
//! bytes without inspecting source, tokens, HIR, or target instructions on the
//! host. The host only validates and serializes the flat object contract.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::job_sized::JobSized;

/// A finished x86 object: on the host, or parked in the GPU link store with
/// its text and rodata left there (`codegen/x86/link/resident_linking.rs`).
pub(crate) enum GpuX86FinishedObject {
    Host(GpuX86RelocatableObject),
    Parked(super::x86::GpuX86FileObject),
}

/// Element counts of the object projection's direct operations for given
/// capacities (`JobSized`), as `GpuX86ObjectProjection::new` builds them.
mod object_extent {
    use super::LoweringCapacities;

    pub(super) fn relocations(c: LoweringCapacities) -> u32 {
        c.semantic_instructions.max(1)
    }
    pub(super) fn functions(c: LoweringCapacities) -> u32 {
        c.hir_nodes.max(1)
    }
    pub(super) fn artifact_bytes(c: LoweringCapacities) -> u32 {
        c.artifact_bytes.max(1)
    }
    pub(super) fn target_rows(c: LoweringCapacities) -> u32 {
        c.target_instructions.max(1)
    }
}

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
        GpuX86ObjectBodyRange,
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
    passes_core::PassData,
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
    runtime_relocation_capacity: u32,
    function_capacity: u32,
    artifact_capacity: u32,
    normalize_status: ComputeOperation,
    relocation_flags: JobSized,
    definition_flags_op: JobSized,
    relocations_op: JobSized,
    runtime_relocations_op: JobSized,
    definitions_op: JobSized,
    bytes_op: JobSized,
    relocation_scan: GpuResidentExclusiveScan,
    symbol_scan: GpuResidentExclusiveScan,
    definition_scan: GpuResidentExclusiveScan,
    runtime_relocation_scan: GpuResidentExclusiveScan,
    _params: LaniusBuffer<X86ObjectParams>,
    identity: LaniusBuffer<X86ObjectIdentity>,
    _relocation_flags: LaniusBuffer<u32>,
    _relocation_prefix: LaniusBuffer<u32>,
    _symbol_flags: LaniusBuffer<u32>,
    _symbol_prefix: LaniusBuffer<u32>,
    _definition_flags: LaniusBuffer<u32>,
    _definition_prefix: LaniusBuffer<u32>,
    _runtime_reference_flags: LaniusBuffer<u32>,
    _runtime_relocation_prefix: LaniusBuffer<u32>,
    relocations: LaniusBuffer<X86ObjectRelocationRow>,
    runtime_relocations: LaniusBuffer<X86ObjectRelocationRow>,
    undefined_symbols: LaniusBuffer<X86ObjectUndefinedRow>,
    call_hir_by_symbol: LaniusBuffer<u32>,
    definitions: LaniusBuffer<X86ObjectDefinitionRow>,
    text_words: LaniusBuffer<u32>,
    rodata_words: LaniusBuffer<u32>,
    metadata_readback_copies: Vec<CopyBufferOperation>,
    metadata_readback: LaniusBuffer<u8>,
    payload_readback: PagedReadback,
    /// The byte lengths of the last object's payload regions, in the order
    /// of [`Self::payload_regions`]. A job copies about that much for the
    /// host while it runs.
    last_payload_bytes: std::sync::Mutex<Option<[usize; 7]>>,
    /// The metadata words' sources, as the resident link store copies them:
    /// (buffer, byte offset, bytes, destination word).
    park_meta: [(wgpu::Buffer, u64, u64, u64); 5],
    /// The object the last projection parked for the resident link, until
    /// `finish` publishes it.
    parked: std::sync::Mutex<Option<super::x86::ParkTicket>>,
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
        let runtime_relocation_capacity = capacities.target_instructions.max(1);
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
        let target_total = alias_u32("lir.x86.total", 1)?;
        let runtime_reference_flags =
            alias_u32("lir.x86.runtime_reference_flag", runtime_relocation_capacity)?;
        let runtime_relocation_prefix = alias_u32(
            "artifact.x86.object.runtime_relocation_prefix",
            runtime_relocation_capacity,
        )?;
        let runtime_relocation_total =
            alias_u32("artifact.x86.object.runtime_relocation_total", 1)?;
        let runtime_relocations = workspace
            .alias(
                graph,
                resource("artifact.x86.object.runtime_relocations")?,
                runtime_relocation_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
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
        let call_hir_by_symbol = alias_u32(
            "artifact.x86.object.call_hir_by_symbol",
            relocation_capacity,
        )?;
        let text_words = alias_u32(
            "artifact.x86.object.text_bytes",
            artifact_capacity.div_ceil(4),
        )?;
        let rodata_words = alias_u32(
            "artifact.x86.object.rodata_bytes",
            artifact_capacity.div_ceil(4),
        )?;
        // The metadata, then the lowering status and job totals the lowering
        // pipeline copies after it (`metadata_readback()`).
        let metadata_bytes = super::lowering_ir::X86_OBJECT_METADATA_BYTES as usize
            + std::mem::size_of::<super::lowering_ir::LoweringStatus>()
            + 8;
        let metadata_readback = readback_bytes(
            device,
            "artifact.x86.object.metadata.readback",
            metadata_bytes,
            metadata_bytes,
        );
        // One page holds the whole payload up to 16 MiB, so the prefetch in
        // the job's submission answers `finish` without a submission of its
        // own. A 4 MiB page made a 5 MB object take two extra round trips.
        let payload_capacity = [
            &relocations.byte_size,
            &runtime_relocations.byte_size,
            &undefined_symbols.byte_size,
            &definitions.byte_size,
            &text_words.byte_size,
            &rodata_words.byte_size,
            &call_hir_by_symbol.byte_size,
        ]
        .into_iter()
        .sum::<usize>();
        let payload_readback = PagedReadback::new(
            device,
            "artifact.x86.object.payload.readback",
            payload_capacity.min(16 << 20),
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
        let runtime_relocations_pass = load(
            kernels,
            "artifact.x86.object.runtime_relocations",
            "codegen/lir/x86/object_runtime_relocations",
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
        let relocation_flags_op =
            JobSized::new(relocation_flags_op, object_extent::relocations, capacities)?;
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
        let definition_flags_op =
            JobSized::new(definition_flags_op, object_extent::functions, capacities)?;
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
        let mut identity_resources = resources.clone();
        identity_resources.buffer("gParams", &params);
        identity_resources.buffer("gIdentity", &identity);
        let relocations_op = ComputeOperation::direct(
            device,
            &context,
            &identity_resources,
            "artifact.x86.object.relocations",
            &relocations_pass,
            relocation_capacity,
        )?;
        let relocations_op = JobSized::new(relocations_op, object_extent::relocations, capacities)?;
        let runtime_relocation_scan = GpuResidentExclusiveScan::new(
            device,
            kernels,
            graph,
            workspace,
            allocations,
            scan_contract("runtime_relocation", "lir.x86.total"),
            runtime_relocation_capacity,
            &target_total,
            &runtime_reference_flags,
            &runtime_relocation_prefix,
            &runtime_relocation_total,
        )?;
        let runtime_relocations_op = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "artifact.x86.object.runtime_relocations",
            &runtime_relocations_pass,
            &params,
            runtime_relocation_capacity,
        )?;
        let runtime_relocations_op = JobSized::new(
            runtime_relocations_op,
            object_extent::target_rows,
            capacities,
        )?;
        let definitions_op = ComputeOperation::direct(
            device,
            &context,
            &identity_resources,
            "artifact.x86.object.definitions",
            &definitions_pass,
            function_capacity,
        )?;
        let definitions_op = JobSized::new(definitions_op, object_extent::functions, capacities)?;
        let bytes_op = ComputeOperation::direct_with_uniform(
            device,
            &context,
            &resources,
            "artifact.x86.object.bytes",
            &bytes_pass,
            &params,
            artifact_capacity,
        )?;
        let bytes_op = JobSized::new(bytes_op, object_extent::artifact_bytes, capacities)?;
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
        .chain(std::iter::once(CopyBufferOperation::new(
            &context,
            "artifact.x86.object.runtime_relocation_total.readback",
            "runtime_relocation_total",
            &runtime_relocation_total,
            0,
            "metadata_readback",
            &metadata_readback,
            64,
            4,
        )))
        .collect::<Result<Vec<_>>>()?;

        let park_meta = [
            (relocation_total.buffer.clone(), relocation_total.byte_offset, 4, 1),
            (symbol_total.buffer.clone(), symbol_total.byte_offset, 4, 2),
            (definition_total.buffer.clone(), definition_total.byte_offset, 4, 3),
            (artifact.layout.buffer.clone(), artifact.layout.byte_offset, 48, 4),
            (
                runtime_relocation_total.buffer.clone(),
                runtime_relocation_total.byte_offset,
                4,
                16,
            ),
        ];
        Ok(Self {
            relocation_capacity,
            runtime_relocation_capacity,
            function_capacity,
            artifact_capacity,
            normalize_status,
            relocation_flags: relocation_flags_op,
            definition_flags_op,
            relocations_op,
            runtime_relocations_op,
            definitions_op,
            bytes_op,
            relocation_scan,
            symbol_scan,
            definition_scan,
            runtime_relocation_scan,
            _params: params,
            identity,
            _relocation_flags: relocation_flags,
            _relocation_prefix: relocation_prefix,
            _symbol_flags: symbol_flags,
            _symbol_prefix: symbol_prefix,
            _definition_flags: definition_flags,
            _definition_prefix: definition_prefix,
            _runtime_reference_flags: runtime_reference_flags,
            _runtime_relocation_prefix: runtime_relocation_prefix,
            relocations,
            runtime_relocations,
            undefined_symbols,
            call_hir_by_symbol,
            definitions,
            text_words,
            rodata_words,
            metadata_readback_copies,
            metadata_readback,
            payload_readback,
            last_payload_bytes: std::sync::Mutex::new(None),
            park_meta,
            parked: std::sync::Mutex::new(None),
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
        self.identity.write(queue, 0, bytes.as_ref());
    }

    pub(crate) fn record_status_normalization(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.normalize_status.record(encoder)
    }

    /// Records the object projection; with `job`, its direct operations
    /// dispatch the job's grids (`JobSized`).
    pub(crate) fn record_projection(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        job: Option<LoweringCapacities>,
    ) -> Result<()> {
        self.relocation_flags.record_job(encoder, job)?;
        self.relocation_scan.record(encoder)?;
        self.symbol_scan.record(encoder)?;
        self.definition_flags_op.record_job(encoder, job)?;
        self.definition_scan.record(encoder)?;
        self.relocations_op.record_job(encoder, job)?;
        self.runtime_relocation_scan.record(encoder)?;
        self.runtime_relocations_op.record_job(encoder, job)?;
        self.definitions_op.record_job(encoder, job)?;
        self.bytes_op.record_job(encoder, job)?;
        for copy in &self.metadata_readback_copies {
            copy.record(encoder);
        }
        self.record_park(encoder, job);
        let parked = self.parked.lock().unwrap_or_else(std::sync::PoisonError::into_inner).is_some();
        // The payload's lengths are known only after the job ran. Copy as
        // much of each region as the last object had, with some room, in this
        // submission, so `finish` usually needs no round trip of its own.
        // Without a last object this discards a prefetch no job read.
        let expected = *self
            .last_payload_bytes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let regions = expected.and_then(|last| {
            let capacities = self.payload_capacities();
            let expected = std::array::from_fn(|index| {
                if parked && matches!(index, PAYLOAD_TEXT | PAYLOAD_RODATA) {
                    return 0;
                }
                (last[index] + last[index] / 8 + 256)
                    .next_multiple_of(4)
                    .min(capacities[index] / 4 * 4)
            });
            self.payload_regions(expected).ok()
        });
        self.payload_readback
            .record_prefetch(encoder, regions.as_ref().map_or(&[], |regions| &regions[..]));
        Ok(())
    }

    /// Copies the projection into the resident link store when a native
    /// build has one active. The job's grids bound every region.
    fn record_park(&self, encoder: &mut wgpu::CommandEncoder, job: Option<LoweringCapacities>) {
        let rows = |extent: Option<u32>, capacity: u32| extent.map_or(capacity, |e| e.min(capacity)) as u64;
        let relocation_rows = rows(job.map(object_extent::relocations), self.relocation_capacity);
        let runtime_rows = rows(job.map(object_extent::target_rows), self.runtime_relocation_capacity);
        let definition_rows = rows(job.map(object_extent::functions), self.function_capacity);
        let section_bytes = rows(job.map(object_extent::artifact_bytes), self.artifact_capacity);
        fn region(buffer: &wgpu::Buffer, offset: u64, bytes: u64, size: usize) -> super::x86::ParkRegion<'_> {
            super::x86::ParkRegion { buffer, offset, bytes: bytes.min(size as u64 / 4 * 4) }
        }
        let meta = std::array::from_fn(|index| {
            let (buffer, offset, bytes, word) = &self.park_meta[index];
            (buffer, *offset, *bytes, *word)
        });
        let sources = super::x86::ParkSources {
            meta,
            relocations: region(
                &self.relocations.buffer,
                self.relocations.byte_offset,
                relocation_rows * 32,
                self.relocations.byte_size,
            ),
            runtime_relocations: region(
                &self.runtime_relocations.buffer,
                self.runtime_relocations.byte_offset,
                runtime_rows * 32,
                self.runtime_relocations.byte_size,
            ),
            undefined: region(
                &self.undefined_symbols.buffer,
                self.undefined_symbols.byte_offset,
                relocation_rows * 16,
                self.undefined_symbols.byte_size,
            ),
            definitions: region(
                &self.definitions.buffer,
                self.definitions.byte_offset,
                definition_rows * 32,
                self.definitions.byte_size,
            ),
            text: region(
                &self.text_words.buffer,
                self.text_words.byte_offset,
                section_bytes.next_multiple_of(4),
                self.text_words.byte_size,
            ),
            rodata: region(
                &self.rodata_words.buffer,
                self.rodata_words.byte_offset,
                section_bytes.next_multiple_of(4),
                self.rodata_words.byte_size,
            ),
        };
        let ticket = super::x86::park_resident_object(encoder, &sources);
        *self.parked.lock().unwrap_or_else(std::sync::PoisonError::into_inner) = ticket;
    }

    /// The byte capacity of each payload region.
    fn payload_capacities(&self) -> [usize; 7] {
        [
            self.relocations.byte_size,
            self.runtime_relocations.byte_size,
            self.undefined_symbols.byte_size,
            self.definitions.byte_size,
            self.text_words.byte_size,
            self.rodata_words.byte_size,
            self.call_hir_by_symbol.byte_size,
        ]
    }

    /// The object's payload as readback regions of the given byte lengths:
    /// relocations, runtime relocations, undefined symbols, definitions,
    /// text, rodata and the call HIR identity of each undefined symbol.
    fn payload_regions(&self, bytes: [usize; 7]) -> Result<[ReadbackRegion<'_>; 7]> {
        Ok([
            ReadbackRegion::from_buffer(&self.relocations, 0, bytes[0], "x86 object relocations")?,
            ReadbackRegion::from_buffer(
                &self.runtime_relocations,
                0,
                bytes[1],
                "x86 object runtime relocations",
            )?,
            ReadbackRegion::from_buffer(
                &self.undefined_symbols,
                0,
                bytes[2],
                "x86 object undefined symbols",
            )?,
            ReadbackRegion::from_buffer(&self.definitions, 0, bytes[3], "x86 object definitions")?,
            ReadbackRegion::from_buffer(&self.text_words, 0, bytes[4], "x86 object text")?,
            ReadbackRegion::from_buffer(&self.rodata_words, 0, bytes[5], "x86 object rodata")?,
            ReadbackRegion::from_buffer(
                &self.call_hir_by_symbol,
                0,
                bytes[6],
                "x86 object call HIR identities",
            )?,
        ])
    }

    /// The readback the object metadata is copied into. The lowering
    /// pipeline copies its status and job totals after the metadata
    /// (`X86_OBJECT_METADATA_BYTES`), and maps it once for all of them.
    pub(crate) fn metadata_readback(&self) -> &LaniusBuffer<u8> {
        &self.metadata_readback
    }

    /// Validates the object's `metadata` words (`metadata_readback`) against
    /// the stage's capacities; returns its text and rodata bytes.
    pub(crate) fn section_bytes(&self, metadata: &[u32]) -> Result<usize> {
        Ok(self.layout(metadata)?.section_bytes)
    }

    fn layout(&self, metadata: &[u32]) -> Result<ObjectLayout> {
        let word = |index: usize| metadata[index];
        let relocation_count = word(1) as usize;
        let symbol_count = word(2) as usize;
        let definition_count = word(3) as usize;
        let runtime_relocation_count = word(16) as usize;
        let layout = (4..16).map(word).collect::<Vec<_>>();
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
            || runtime_relocation_count > self.runtime_relocation_capacity as usize
            || symbol_count > relocation_count
            || definition_count > self.function_capacity as usize
            || text_len > self.artifact_capacity as usize
            || rodata_len > self.artifact_capacity as usize
        {
            anyhow::bail!(
                "GPU x86 object metadata exceeds resident capacity: relocations={relocation_count}/{}, runtime relocations={runtime_relocation_count}/{}, symbols={symbol_count}, definitions={definition_count}/{}, text={text_len}/{}, rodata={rodata_len}/{}",
                self.relocation_capacity,
                self.runtime_relocation_capacity,
                self.function_capacity,
                self.artifact_capacity,
                self.artifact_capacity,
            );
        }
        Ok(ObjectLayout {
            relocation_count,
            symbol_count,
            definition_count,
            runtime_relocation_count,
            body_len,
            wrapper_len,
            text_len,
            rodata_len,
            entrypoint_count,
            section_bytes: text_len + rodata_len,
        })
    }

    /// The slot the recorded object parked in, until [`Self::finish`].
    pub(crate) fn parked_slot(&self) -> Option<super::x86::ParkedSlot> {
        self.parked
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .as_ref()
            .map(super::x86::ParkTicket::parked_slot)
    }

    /// Reads the object from its `metadata` words (`metadata_readback`),
    /// which [`Self::section_bytes`] accepted. An object parked in `keep`,
    /// the caller's link store, keeps its text and rodata on the GPU.
    pub(crate) fn finish(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
        metadata: &[u32],
        keep: Option<&std::sync::Arc<super::x86::GpuX86LinkStore>>,
    ) -> Result<(GpuX86FinishedObject, Vec<u32>)> {
        self.finish_with_reads(device, queue, library_id, unit_id, metadata, keep, &[])
            .map(|(object, call_hirs, _)| (object, call_hirs))
    }

    /// The object's undefined-symbol rows (four words each), the call HIR
    /// of each, the word that counts them and the rows the buffers hold,
    /// for the retained build's call rewrite, which updates the rows before
    /// [`Self::finish`] reads them.
    pub(crate) fn call_rows(&self) -> (
        crate::type_checker::program_retention::JobTable,
        crate::type_checker::program_retention::JobTable,
        (wgpu::Buffer, u64),
        u32,
    ) {
        use crate::type_checker::program_retention::JobTable;
        let (count, offset, _, _) = &self.park_meta[1];
        (
            JobTable::from_lanius(&self.undefined_symbols),
            JobTable::from_lanius(&self.call_hir_by_symbol),
            (count.clone(), *offset),
            u32::try_from(self.undefined_symbols.byte_size / 16).unwrap_or(u32::MAX),
        )
    }

    /// [`Self::finish`], reading `extra` in the same readback as the
    /// payload; their bytes follow the object.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn finish_with_reads(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
        metadata: &[u32],
        keep: Option<&std::sync::Arc<super::x86::GpuX86LinkStore>>,
        extra: &[ReadbackRegion<'_>],
    ) -> Result<(GpuX86FinishedObject, Vec<u32>, Vec<Vec<u8>>)> {
        let ticket = self.parked.lock().unwrap_or_else(std::sync::PoisonError::into_inner).take();
        // An object parked in another build's store is read in full; that
        // build's store may be cleared before this build links.
        let (parked, foreign) = match ticket {
            Some(ticket) if keep.is_some_and(|store| ticket.is_in(store)) => (Some(ticket), None),
            ticket => (None, ticket),
        };
        let ObjectLayout {
            relocation_count,
            symbol_count,
            definition_count,
            runtime_relocation_count,
            body_len,
            wrapper_len,
            text_len,
            rodata_len,
            entrypoint_count,
            section_bytes: _,
        } = self.layout(metadata)?;

        let payload_bytes = [
            relocation_count * 32,
            runtime_relocation_count * 32,
            symbol_count * 16,
            definition_count * 32,
            text_len,
            rodata_len,
            symbol_count * 4,
        ];
        *self
            .last_payload_bytes
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = Some(payload_bytes);
        let mut payload_bytes = payload_bytes;
        if parked.is_some() {
            payload_bytes[PAYLOAD_TEXT] = 0;
            payload_bytes[PAYLOAD_RODATA] = 0;
        }
        let mut regions = self.payload_regions(payload_bytes)?.to_vec();
        regions.extend_from_slice(extra);
        let mut read = self
            .payload_readback
            .read_regions(device, queue, &regions, crate::readback_label!("x86 object payload readback"))?;
        let extra_bytes = read.split_off(7.min(read.len()));
        let [
            relocation_bytes,
            runtime_relocation_bytes,
            undefined_bytes,
            definition_bytes,
            text,
            rodata,
            call_hir_bytes,
        ]: [Vec<u8>; 7] = read
            .try_into()
            .map_err(|_| anyhow::anyhow!("x86 object payload readback shape changed"))?;
        // Semantic rows (calls, string addresses) first, then each target
        // row's native-runtime reference in row order.
        let mut relocation_words = decode_words(&relocation_bytes);
        relocation_words.extend(decode_words(&runtime_relocation_bytes));
        let undefined_words = decode_words(&undefined_bytes);
        let definition_words = decode_words(&definition_bytes);
        let mut relocations = Vec::with_capacity(relocation_count + runtime_relocation_count);
        for (index, row) in relocation_words.chunks_exact(8).enumerate() {
            let kind = match row[0] {
                1 => GpuX86RelocationKind::Rel32,
                2 => GpuX86RelocationKind::CallRel32,
                3 => GpuX86RelocationKind::Abs32,
                4 => GpuX86RelocationKind::RawRel32,
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
            // [entry wrapper][body][native runtime + CRT bridge]
            body: Some(GpuX86ObjectBodyRange {
                start: wrapper_len as u32,
                end: (wrapper_len + body_len) as u32,
            }),
            text,
            rodata,
            relocations,
            symbols,
            identity_bytes,
        };
        let call_hirs = decode_words(&call_hir_bytes);
        let Some(ticket) = parked else {
            object.validate().map_err(anyhow::Error::msg)?;
            if let Some(ticket) = foreign {
                ticket.commit(library_id, unit_id);
            }
            return Ok((GpuX86FinishedObject::Host(object), call_hirs, extra_bytes));
        };
        let sections = ticket.sections(text_len as u32, rodata_len as u32);
        let object = super::x86::GpuX86FileObject::parked(object, sections).map_err(anyhow::Error::msg)?;
        ticket.commit(library_id, unit_id);
        Ok((GpuX86FinishedObject::Parked(object), call_hirs, extra_bytes))
    }
}

/// An object's counts and section lengths from its metadata words.
struct ObjectLayout {
    relocation_count: usize,
    symbol_count: usize,
    definition_count: usize,
    runtime_relocation_count: usize,
    body_len: usize,
    wrapper_len: usize,
    text_len: usize,
    rodata_len: usize,
    entrypoint_count: u32,
    section_bytes: usize,
}

/// Indexes of the text and rodata regions in `payload_regions`.
const PAYLOAD_TEXT: usize = 4;
const PAYLOAD_RODATA: usize = 5;

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
            apply_pass: "artifact.x86.object.relocation_scan.apply",
            count,
            input: "artifact.x86.object.relocation_flags",
            local: "artifact.x86.object.relocation_scan_local",
            block_sum: "artifact.x86.object.relocation_scan_block_sum",
            output: "artifact.x86.object.relocation_prefix",
            total: "artifact.x86.object.relocation_total",
        },
        "symbol" => GraphScanContract {
            local_pass: "artifact.x86.object.symbol_scan.local",
            apply_pass: "artifact.x86.object.symbol_scan.apply",
            count,
            input: "artifact.x86.object.symbol_flags",
            local: "artifact.x86.object.symbol_scan_local",
            block_sum: "artifact.x86.object.symbol_scan_block_sum",
            output: "artifact.x86.object.symbol_prefix",
            total: "artifact.x86.object.symbol_total",
        },
        "runtime_relocation" => GraphScanContract {
            local_pass: "artifact.x86.object.runtime_relocation_scan.local",
            apply_pass: "artifact.x86.object.runtime_relocation_scan.apply",
            count,
            input: "lir.x86.runtime_reference_flag",
            local: "artifact.x86.object.runtime_relocation_scan_local",
            block_sum: "artifact.x86.object.runtime_relocation_scan_block_sum",
            output: "artifact.x86.object.runtime_relocation_prefix",
            total: "artifact.x86.object.runtime_relocation_total",
        },
        "definition" => GraphScanContract {
            local_pass: "artifact.x86.object.definition_scan.local",
            apply_pass: "artifact.x86.object.definition_scan.apply",
            count,
            input: "artifact.x86.object.definition_flags",
            local: "artifact.x86.object.definition_scan_local",
            block_sum: "artifact.x86.object.definition_scan_block_sum",
            output: "artifact.x86.object.definition_prefix",
            total: "artifact.x86.object.definition_total",
        },
        _ => unreachable!(),
    }
}

fn load(kernels: &KernelRegistry, _label: &str, shader: &str) -> Result<PassData> {
    Ok(kernels.kernel(shader).clone())
}
