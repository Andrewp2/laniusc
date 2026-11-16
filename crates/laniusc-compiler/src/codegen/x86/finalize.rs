//! GPU symbol finalization for retained native x86 objects.
//!
//! An original object names each deferred generic call by the provisional
//! identity `(NATIVE_RESERVED_LIBRARY, NATIVE_NS_USE, use ordinal)`. After
//! discovery and admission, the GPU publishes a route table indexed by use
//! ordinal whose rows name a final native identity: an instance identity
//! `(NATIVE_RESERVED_LIBRARY, NATIVE_NS_INSTANCE, rank)` or an ordinary
//! `DeclNative` identity. The table may be sparse: only a use that a
//! provisional symbol names must have a valid row for this build, and a row
//! no symbol names is never read. This stage rewrites the provisional entries of the
//! objects' symbol and identity columns, recomputes their identity hashes on the
//! GPU and publishes the columns only when every input is valid.
//!
//! The host transfers opaque columns, submits the kernels and observes demand
//! and status. It never reads routes, joins uses to targets, renames a symbol
//! or hashes a rewritten identity. Text, rodata and relocation columns never
//! enter this stage, so their bytes and symbol indexes are unchanged.
//!
//! Readiness is an upstream GPU record. Publication requires the route table's
//! publication bit and the caller/target ABI certification bit. The ABI
//! comparison itself belongs to admission; this stage consumes its bit and does
//! not replace it with a host flag.
//!
//! Kernels: `shaders/codegen/x86/finalize/`. The constants here mirror
//! `symbol_finalize_common.slang`.

use std::{num::NonZeroU32, path::Path, sync::Mutex};

use anyhow::{Context, Result, anyhow, bail};

use super::{
    GPU_X86_OBJECT_HEADER_BYTES,
    GpuX86FileObject,
    GpuX86ObjectSymbolRecord,
    GpuX86RelocatableObject,
    GpuX86RelocatableObjectLayout,
    object::{GPU_X86_SYMBOL_ROW_BYTES, decode_symbol_rows, encode_symbol_rows},
    support::u32_words_bytes,
};
use crate::gpu::{
    buffers::{CapacityBufferCache, LaniusBuffer},
    compiler_graph::{
        AccessMode,
        CompilerGraphBuilder,
        CompilerPhase,
        MaterializedCompilerGraph,
        ResourceClass,
        ResourceDesc,
        ResourceDomain,
    },
    device,
    operations::{ComputeOperation, CopyBufferOperation},
    passes_core::{PassData, make_main_pass},
    resource_registry::ResourceMap,
    workspace::WorkspaceUsageClass,
};

/// Internal native library domain for provisional and instance symbols.
/// Before a producer is enabled, the build's GPU library map must keep
/// ordinary native libraries outside it; that mapping is not implemented yet.
pub(crate) const NATIVE_RESERVED_LIBRARY: u32 = 0xffff_fffe;
/// Namespace of provisional original-call symbols, keyed by use ordinal.
pub(crate) const NATIVE_NS_USE: u32 = 0xffff_0001;
/// Namespace of instance symbols, keyed by deterministic instance rank.
pub(crate) const NATIVE_NS_INSTANCE: u32 = 0xffff_0002;
/// Readiness flag: discovery published a complete route table.
pub(crate) const READY_ROUTES_PUBLISHED: u32 = 1;
/// Readiness flag: the GPU caller/target ABI comparison accepted every route.
pub(crate) const READY_ABI_CERTIFIED: u32 = 2;

const STATUS_WORDS: usize = 16;
const STATUS_FAILURE_BASE: usize = 4;

pub(crate) fn is_provisional_identity(identity: [u32; 3]) -> bool {
    identity[0] == NATIVE_RESERVED_LIBRARY && identity[1] == NATIVE_NS_USE
}

#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn provisional_identity(use_ordinal: u32) -> [u32; 3] {
    [NATIVE_RESERVED_LIBRARY, NATIVE_NS_USE, use_ordinal]
}

#[cfg_attr(not(test), allow(dead_code))]
pub(crate) fn instance_identity(rank: u32) -> [u32; 3] {
    [NATIVE_RESERVED_LIBRARY, NATIVE_NS_INSTANCE, rank]
}

/// One object's symbol column (object-format rows) and identity column.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct X86SymbolColumns {
    pub symbol_rows: Vec<u8>,
    pub identity_bytes: Vec<u8>,
}

#[cfg_attr(not(test), allow(dead_code))]
impl X86SymbolColumns {
    /// Wasm uses the same eight-word symbol column: kind/function index
    /// occupy the section/offset words. Finalization preserves both words.
    pub(crate) fn of_wasm_object(object: &crate::codegen::wasm::GpuWasmRelocatableObject) -> Self {
        let symbol_rows = object.symbols.iter().flat_map(|s| [
            s.identity_hash_lo,s.identity_hash_hi,s.identity_byte_start,s.identity_byte_len,
            s.kind as u32,s.function_index,s.size,s.flags,
        ]).flat_map(u32::to_le_bytes).collect();
        Self { symbol_rows, identity_bytes: object.identity_bytes.clone() }
    }

    pub(crate) fn apply_to_wasm_object(&self, object: &mut crate::codegen::wasm::GpuWasmRelocatableObject) -> Result<()> {
        let original = Self::of_wasm_object(object);
        if self.symbol_rows.len()!=original.symbol_rows.len() || self.identity_bytes.len()!=original.identity_bytes.len() {
            bail!("finalized Wasm symbol columns do not match the original object's shape");
        }
        for (before,after) in original.symbol_rows.chunks_exact(32).zip(self.symbol_rows.chunks_exact(32)) {
            if before[8..]!=after[8..] { bail!("finalized Wasm symbol changes the original object's layout"); }
        }
        let mut symbols=object.symbols.clone();
        for (symbol,row) in symbols.iter_mut().zip(self.symbol_rows.chunks_exact(32)) {
            symbol.identity_hash_lo=u32::from_le_bytes(row[0..4].try_into().unwrap());
            symbol.identity_hash_hi=u32::from_le_bytes(row[4..8].try_into().unwrap());
        }
        let old_symbols=std::mem::replace(&mut object.symbols,symbols);
        let old_identity=std::mem::replace(&mut object.identity_bytes,self.identity_bytes.clone());
        if let Err(error)=object.validate() {
            object.symbols=old_symbols; object.identity_bytes=old_identity;
            return Err(anyhow::Error::msg(error));
        }
        Ok(())
    }

    pub(crate) fn of_object(object: &GpuX86RelocatableObject) -> Self {
        let mut symbol_rows = Vec::new();
        encode_symbol_rows(&object.symbols, &mut symbol_rows);
        Self {
            symbol_rows,
            identity_bytes: object.identity_bytes.clone(),
        }
    }

    pub(crate) fn of_file_object(object: &GpuX86FileObject) -> Self {
        let mut symbol_rows = Vec::new();
        encode_symbol_rows(&object.symbols, &mut symbol_rows);
        Self {
            symbol_rows,
            identity_bytes: object.identity_bytes.clone(),
        }
    }

    /// Reads both columns of a serialized object file as one byte range,
    /// without loading or decoding its text, rodata or relocations.
    pub(crate) fn read_object_file(path: &Path) -> Result<Self> {
        use std::io::{Read, Seek, SeekFrom};

        let mut file = std::fs::File::open(path)
            .with_context(|| format!("open x86 object {}", path.display()))?;
        let mut header = [0u8; GPU_X86_OBJECT_HEADER_BYTES];
        file.read_exact(&mut header)
            .with_context(|| format!("read x86 object header {}", path.display()))?;
        let layout = GpuX86RelocatableObjectLayout::from_header_bytes(&header)
            .map_err(anyhow::Error::msg)?;
        let file_len = file.metadata()?.len();
        if file_len != layout.serialized_byte_len {
            bail!(
                "x86 object {} has {file_len} bytes but its layout describes {}",
                path.display(),
                layout.serialized_byte_len
            );
        }
        let range = layout
            .symbol_metadata_byte_range()
            .map_err(anyhow::Error::msg)?;
        let symbol_bytes = layout.symbol_count as usize * GPU_X86_SYMBOL_ROW_BYTES;
        if range.end - range.start != symbol_bytes as u64 + u64::from(layout.identity_byte_len) {
            bail!(
                "x86 object {} symbol columns disagree with its layout",
                path.display()
            );
        }
        file.seek(SeekFrom::Start(range.start))?;
        let mut bytes = vec![0u8; (range.end - range.start) as usize];
        file.read_exact(&mut bytes)
            .with_context(|| format!("read x86 object symbol columns {}", path.display()))?;
        let identity_bytes = bytes.split_off(symbol_bytes);
        Ok(Self {
            symbol_rows: bytes,
            identity_bytes,
        })
    }

    fn symbol_count(&self) -> Result<u32> {
        if self.symbol_rows.len() % GPU_X86_SYMBOL_ROW_BYTES != 0 {
            bail!("x86 symbol column is not a whole number of rows");
        }
        u32::try_from(self.symbol_rows.len() / GPU_X86_SYMBOL_ROW_BYTES)
            .map_err(|_| anyhow!("x86 symbol column exceeds u32 rows"))
    }

    /// Checks the transfer shape and every symbol field the GPU must preserve.
    /// This catches a batch result applied to a different symbol layout; the
    /// caller still owns the association when two objects have identical layouts.
    fn matching_symbols(
        &self,
        original: &[GpuX86ObjectSymbolRecord],
        identity_bytes: usize,
    ) -> Result<Vec<GpuX86ObjectSymbolRecord>> {
        let symbols = decode_symbol_rows(&self.symbol_rows).map_err(anyhow::Error::msg)?;
        if symbols.len() != original.len() || self.identity_bytes.len() != identity_bytes {
            bail!("finalized x86 symbol columns do not match the original object's shape");
        }
        for (index, (before, after)) in original.iter().zip(&symbols).enumerate() {
            let preserved = GpuX86ObjectSymbolRecord {
                identity_hash_lo: after.identity_hash_lo,
                identity_hash_hi: after.identity_hash_hi,
                ..*before
            };
            if preserved != *after {
                bail!("finalized x86 symbol {index} changes the original object's symbol layout");
            }
        }
        Ok(symbols)
    }

    /// Replaces an object's symbol and identity columns with these published
    /// columns after validation. Every non-identity field is kept.
    pub(crate) fn apply_to_object(&self, object: &mut GpuX86RelocatableObject) -> Result<()> {
        let symbols = self.matching_symbols(&object.symbols, object.identity_bytes.len())?;
        super::object::validate_link_object_columns(
            object.version,
            object.entry_offset,
            object.body,
            object.text.len(),
            object.rodata.len(),
            &object.relocations,
            &symbols,
            &self.identity_bytes,
        )
        .map_err(anyhow::Error::msg)?;
        object.symbols = symbols;
        object.identity_bytes.clone_from(&self.identity_bytes);
        Ok(())
    }

    pub(crate) fn apply_to_file_object(&self, object: &mut GpuX86FileObject) -> Result<()> {
        let symbols = self.matching_symbols(&object.symbols, object.identity_bytes.len())?;
        debug_assert_eq!(object.validate(), Ok(()));
        super::object::validate_link_object_columns(
            object.layout.version,
            object.layout.entry_offset,
            object.layout.body,
            object.layout.text_byte_len as usize,
            object.layout.rodata_byte_len as usize,
            &object.relocations,
            &symbols,
            &self.identity_bytes,
        )
        .map_err(anyhow::Error::msg)?;
        object.symbols = symbols;
        object.identity_bytes.clone_from(&self.identity_bytes);
        // Column lengths and symbol layout did not change, so the durable
        // file layout remains valid without modifying its payload receipt.
        Ok(())
    }
}

/// GPU-resident route inputs published by discovery and admission.
pub(crate) struct X86RouteTable<'a> {
    /// `(library, namespace or unit, local identity, generation)` rows
    /// indexed by build-global use ordinal. Rows no provisional symbol names
    /// may be missing.
    pub routes: &'a LaniusBuffer<u32>,
    /// Rows `routes` can hold. The readiness record's use count must fit.
    pub route_capacity: u32,
    /// One `(generation, readiness flags, instance count, use count)` row.
    pub readiness: &'a LaniusBuffer<u32>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum X86FinalizeFailureKind {
    /// Detail: 0 stale generation, 1 routes unpublished, 2 ABI uncertified,
    /// 3 use count exceeds the route table.
    Readiness,
    ObjectMalformed,
    SymbolMalformed,
    RouteMissing,
    RouteToUse,
    RouteOutOfRange,
    RouteInvalidIdentity,
    UseOutOfRange,
    ProvisionalDefinition,
    IdentityOverlap,
}

const FAILURE_KINDS: [X86FinalizeFailureKind; 10] = [
    X86FinalizeFailureKind::Readiness,
    X86FinalizeFailureKind::ObjectMalformed,
    X86FinalizeFailureKind::SymbolMalformed,
    X86FinalizeFailureKind::RouteMissing,
    X86FinalizeFailureKind::RouteToUse,
    X86FinalizeFailureKind::RouteOutOfRange,
    X86FinalizeFailureKind::RouteInvalidIdentity,
    X86FinalizeFailureKind::UseOutOfRange,
    X86FinalizeFailureKind::ProvisionalDefinition,
    X86FinalizeFailureKind::IdentityOverlap,
];

/// The first failure in code order, with the smallest detail the GPU
/// recorded for it: a use ordinal, a symbol index in transfer order, or an
/// object index.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct X86FinalizeFailure {
    pub kind: X86FinalizeFailureKind,
    pub detail: u32,
}

impl std::fmt::Display for X86FinalizeFailure {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "GPU symbol finalization rejected its input: {:?} at {}",
            self.kind, self.detail
        )
    }
}

impl std::error::Error for X86FinalizeFailure {}

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) enum X86FinalizeAttempt {
    Published(Vec<X86SymbolColumns>),
    /// Output staging is too small. Nothing was published; grow and retry.
    NeedsCapacity {
        symbols: u32,
        identity_words: u32,
    },
    Rejected(X86FinalizeFailure),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct OutputCapacity {
    symbols: u32,
    identity_words: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct GraphShape {
    objects: u32,
    symbols: u32,
    identity_words: u32,
    routes: u32,
    output: OutputCapacity,
}

impl GraphShape {
    fn covers(&self, needed: &Self) -> bool {
        self.objects >= needed.objects
            && self.symbols >= needed.symbols
            && self.identity_words >= needed.identity_words
            && self.routes >= needed.routes
            && self.output.symbols >= needed.output.symbols
            && self.output.identity_words >= needed.output.identity_words
    }

    fn max(&self, other: &Self) -> Self {
        Self {
            objects: self.objects.max(other.objects),
            symbols: self.symbols.max(other.symbols),
            identity_words: self.identity_words.max(other.identity_words),
            routes: self.routes.max(other.routes),
            output: OutputCapacity {
                symbols: self.output.symbols.max(other.output.symbols),
                identity_words: self.output.identity_words.max(other.output.identity_words),
            },
        }
    }
}

struct FinalizeGraph {
    shape: GraphShape,
    materialized: MaterializedCompilerGraph,
}

const PASS_CLEAR: &str = "codegen.x86.finalize.clear";
const PASS_OBJECTS: &str = "codegen.x86.finalize.objects";
const PASS_ROUTES: &str = "codegen.x86.finalize.routes";
const PASS_CLASSIFY: &str = "codegen.x86.finalize.classify";
const PASS_CHECK: &str = "codegen.x86.finalize.check";
const PASS_EMIT_SYMBOLS: &str = "codegen.x86.finalize.emit_symbols";
const PASS_EMIT_IDENTITY: &str = "codegen.x86.finalize.emit_identity";
const COPY_STATUS: &str = "codegen.x86.finalize.status.readback";
const COPY_SYMBOLS: &str = "codegen.x86.finalize.symbols.readback";
const COPY_IDENTITY: &str = "codegen.x86.finalize.identity.readback";

/// Resident pipelines and retained storage for symbol finalization. Retained
/// storage carries no state between jobs: every job clears or overwrites it.
/// A finalization attempt on the GPU, read by
/// [`GpuX86SymbolFinalizer::read_once`].
#[must_use]
pub(crate) struct X86FinalizeSubmitted {
    transfer: Transfer,
    output: OutputCapacity,
    readback: LaniusBuffer<u8>,
    symbol_copy_bytes: usize,
    identity_copy_bytes: usize,
    identity_at: usize,
    generation: NonZeroU32,
}

pub(crate) struct GpuX86SymbolFinalizer {
    clear: PassData,
    objects: PassData,
    routes: PassData,
    classify: PassData,
    check: PassData,
    emit_symbols: PassData,
    emit_identity: PassData,
    buffers: CapacityBufferCache,
    graph: Mutex<Option<FinalizeGraph>>,
    output: Mutex<OutputCapacity>,
}

#[cfg_attr(not(test), allow(dead_code))]
impl GpuX86SymbolFinalizer {
    pub(crate) fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        macro_rules! load {
            ($label:literal, $spv:literal, $reflection:literal) => {
                make_main_pass!(&gpu.device, $label, artifacts: ($spv, $reflection))?
            };
        }
        Ok(Self {
            clear: load!(
                "codegen_x86_finalize_clear",
                "codegen/x86/finalize/clear.spv",
                "codegen/x86/finalize/clear.reflect.json"
            ),
            objects: load!(
                "codegen_x86_finalize_objects",
                "codegen/x86/finalize/objects.spv",
                "codegen/x86/finalize/objects.reflect.json"
            ),
            routes: load!(
                "codegen_x86_finalize_routes",
                "codegen/x86/finalize/routes.spv",
                "codegen/x86/finalize/routes.reflect.json"
            ),
            classify: load!(
                "codegen_x86_finalize_classify",
                "codegen/x86/finalize/classify.spv",
                "codegen/x86/finalize/classify.reflect.json"
            ),
            check: load!(
                "codegen_x86_finalize_check",
                "codegen/x86/finalize/check.spv",
                "codegen/x86/finalize/check.reflect.json"
            ),
            emit_symbols: load!(
                "codegen_x86_finalize_emit_symbols",
                "codegen/x86/finalize/emit_symbols.spv",
                "codegen/x86/finalize/emit_symbols.reflect.json"
            ),
            emit_identity: load!(
                "codegen_x86_finalize_emit_identity",
                "codegen/x86/finalize/emit_identity.spv",
                "codegen/x86/finalize/emit_identity.reflect.json"
            ),
            buffers: CapacityBufferCache::default(),
            graph: Mutex::new(None),
            output: Mutex::new(OutputCapacity {
                symbols: 1024,
                identity_words: 3 * 1024,
            }),
        })
    }

    /// Sets the retained output staging capacity used by the next attempt.
    pub(crate) fn set_output_capacity(&self, symbols: u32, identity_words: u32) {
        *self.output.lock().expect("finalize capacity poisoned") = OutputCapacity {
            symbols,
            identity_words,
        };
    }

    /// Finalizes the objects, growing output staging and replaying from the
    /// same immutable inputs when the GPU reports insufficient capacity.
    /// Returns the published columns, or the GPU's rejection.
    pub(crate) fn finalize(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        objects: &[X86SymbolColumns],
        routes: &X86RouteTable<'_>,
        generation: NonZeroU32,
    ) -> Result<std::result::Result<Vec<X86SymbolColumns>, X86FinalizeFailure>> {
        let submitted = self.submit_once(device, queue, objects, routes, generation);
        self.finish(device, queue, submitted, objects, routes, generation)
    }

    /// Completes [`Self::finalize`] from an attempt submitted by
    /// [`Self::submit_once`] with the same inputs. The caller may do host
    /// work between the two while the GPU runs the attempt.
    pub(crate) fn finish(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        submitted: Result<X86FinalizeSubmitted>,
        objects: &[X86SymbolColumns],
        routes: &X86RouteTable<'_>,
        generation: NonZeroU32,
    ) -> Result<std::result::Result<Vec<X86SymbolColumns>, X86FinalizeFailure>> {
        let mut submitted = Some(submitted?);
        // Output demand never exceeds the input size, so one growth suffices;
        // the bound only stops a broken status word from looping.
        for _ in 0..4 {
            let submitted = match submitted.take() {
                Some(submitted) => submitted,
                None => self.submit_once(device, queue, objects, routes, generation)?,
            };
            match self.read_once(device, submitted)? {
                X86FinalizeAttempt::Published(columns) => return Ok(Ok(columns)),
                X86FinalizeAttempt::Rejected(failure) => return Ok(Err(failure)),
                X86FinalizeAttempt::NeedsCapacity {
                    symbols,
                    identity_words,
                } => {
                    let mut output = self.output.lock().expect("finalize capacity poisoned");
                    output.symbols = output.symbols.max(symbols);
                    output.identity_words = output.identity_words.max(identity_words);
                }
            }
        }
        bail!("GPU symbol finalization kept requesting more output capacity")
    }

    /// One GPU attempt with the current output staging capacity.
    pub(crate) fn finalize_once(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        objects: &[X86SymbolColumns],
        routes: &X86RouteTable<'_>,
        generation: NonZeroU32,
    ) -> Result<X86FinalizeAttempt> {
        let submitted = self.submit_once(device, queue, objects, routes, generation)?;
        self.read_once(device, submitted)
    }

    /// Records and submits one attempt with the current output staging
    /// capacity; [`Self::read_once`] reads it.
    pub(crate) fn submit_once(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        objects: &[X86SymbolColumns],
        routes: &X86RouteTable<'_>,
        generation: NonZeroU32,
    ) -> Result<X86FinalizeSubmitted> {
        // Allocation bounds are a host transfer invariant. Never trust a
        // caller's capacity to make unchecked SPIR-V buffer reads safe.
        if u64::from(routes.route_capacity) * 16 > routes.routes.byte_size as u64 {
            bail!("x86 route capacity exceeds its GPU buffer size");
        }
        if routes.readiness.byte_size < 16 {
            bail!("x86 readiness GPU buffer is smaller than one row");
        }
        let transfer = Transfer::new(objects)?;
        let output = *self.output.lock().expect("finalize capacity poisoned");
        let needed = GraphShape {
            objects: transfer.object_count(),
            symbols: transfer.symbol_count,
            identity_words: transfer.identity_word_count(),
            routes: routes.route_capacity,
            output,
        };
        let mut graph_guard = self.graph.lock().expect("finalize graph poisoned");
        if !graph_guard
            .as_ref()
            .is_some_and(|graph| graph.shape.covers(&needed))
        {
            let shape = graph_guard
                .as_ref()
                .map_or(needed, |graph| graph.shape.max(&needed));
            *graph_guard = Some(self.build_graph(device, shape)?);
        }
        let graph = &graph_guard
            .as_ref()
            .expect("finalize graph installed")
            .materialized;

        let params = self.buffers.buffer::<u32>(
            device,
            "codegen.x86.finalize.params",
            32,
            8,
            wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        );
        params.write(
            queue,
            0,
            u32_words_bytes(&[
                transfer.object_count(),
                transfer.symbol_count,
                transfer.identity_word_count(),
                routes.route_capacity,
                generation.get(),
                output.symbols,
                output.identity_words,
                0,
            ]),
        );
        let object_table = self.input(
            device,
            queue,
            "codegen.x86.finalize.objects",
            &transfer.objects,
        );
        let symbols_in = self.input(
            device,
            queue,
            "codegen.x86.finalize.symbols_in",
            &transfer.symbol_words,
        );
        let identity_in = self.input(
            device,
            queue,
            "codegen.x86.finalize.identity_in",
            &transfer.identity_words,
        );
        let symbol_copy_bytes =
            transfer.symbol_count.min(output.symbols) as usize * GPU_X86_SYMBOL_ROW_BYTES;
        let identity_copy_bytes =
            transfer.identity_word_count().min(output.identity_words) as usize * 4;
        // The status, the symbols and the identity words in one buffer.
        let symbols_at = STATUS_WORDS * 4;
        let identity_at = symbols_at + output.symbols as usize * GPU_X86_SYMBOL_ROW_BYTES;
        let readback = self.readback(
            device,
            "rb.codegen.x86.finalize",
            identity_at + output.identity_words as usize * 4,
        );

        let graph_bindings = graph.bindings()?;
        let mut resources = ResourceMap::new();
        resources.attach_graph(graph.graph(), graph.allocations());
        resources.register_graph_bindings(graph.graph(), &graph_bindings);
        resources.buffer("gFinalize", &params);
        resources.buffer("fin_objects", &object_table);
        resources.buffer("fin_symbols_in", &symbols_in);
        resources.buffer("fin_identity_in", &identity_in);
        resources.buffer("fin_routes", routes.routes);
        resources.buffer("fin_readiness", routes.readiness);
        resources.buffer("fin_readback", &readback);

        let symbol_lanes = transfer.symbol_count.max(1);
        let operations = [
            (
                PASS_CLEAR,
                &self.clear,
                transfer.identity_word_count().max(STATUS_WORDS as u32),
            ),
            (PASS_OBJECTS, &self.objects, transfer.object_count().max(1)),
            (PASS_ROUTES, &self.routes, 1),
            (PASS_CLASSIFY, &self.classify, symbol_lanes),
            (PASS_CHECK, &self.check, symbol_lanes),
            (PASS_EMIT_SYMBOLS, &self.emit_symbols, symbol_lanes),
            (
                PASS_EMIT_IDENTITY,
                &self.emit_identity,
                transfer.identity_word_count().max(1),
            ),
        ]
        .into_iter()
        .map(|(name, pass, lanes)| {
            ComputeOperation::direct(device, graph, &resources, name, pass, lanes)
                .map(|operation| (operation, lanes))
        })
        .collect::<Result<Vec<_>>>()?;

        let status = graph.buffer::<u32>("fin_status")?;
        let symbols_out = graph.buffer::<u32>("fin_symbols_out")?;
        let identity_out = graph.buffer::<u32>("fin_identity_out")?;
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.x86.finalize.encoder"),
        });
        for (operation, lanes) in &operations {
            operation.record_elements(&mut encoder, *lanes)?;
        }
        CopyBufferOperation::new(
            graph,
            COPY_STATUS,
            "fin_status",
            &status,
            0,
            "fin_readback",
            &readback,
            0,
            (STATUS_WORDS * 4) as u64,
        )?
        .record(&mut encoder);
        if symbol_copy_bytes != 0 {
            CopyBufferOperation::new(
                graph,
                COPY_SYMBOLS,
                "fin_symbols_out",
                &symbols_out,
                0,
                "fin_readback",
                &readback,
                symbols_at as u64,
                symbol_copy_bytes as u64,
            )?
            .record(&mut encoder);
        }
        if identity_copy_bytes != 0 {
            CopyBufferOperation::new(
                graph,
                COPY_IDENTITY,
                "fin_identity_out",
                &identity_out,
                0,
                "fin_readback",
                &readback,
                identity_at as u64,
                identity_copy_bytes as u64,
            )?
            .record(&mut encoder);
        }
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.x86.finalize",
            encoder.finish(),
        );
        Ok(X86FinalizeSubmitted {
            transfer,
            output,
            readback,
            symbol_copy_bytes,
            identity_copy_bytes,
            identity_at,
            generation,
        })
    }

    /// Reads an attempt submitted by [`Self::submit_once`].
    pub(crate) fn read_once(
        &self,
        device: &wgpu::Device,
        submitted: X86FinalizeSubmitted,
    ) -> Result<X86FinalizeAttempt> {
        let X86FinalizeSubmitted {
            transfer,
            output,
            readback,
            symbol_copy_bytes,
            identity_copy_bytes,
            identity_at,
            generation,
        } = submitted;
        let symbols_at = STATUS_WORDS * 4;
        let end = if identity_copy_bytes != 0 {
            identity_at + identity_copy_bytes
        } else {
            symbols_at + symbol_copy_bytes
        };
        let bytes = read_bytes(device, &readback, end, "readback")?;
        let status_words = bytes[..symbols_at]
            .chunks_exact(4)
            .map(|word| u32::from_le_bytes(word.try_into().expect("four bytes")))
            .collect::<Vec<_>>();
        if let Some(failure) = FAILURE_KINDS.iter().enumerate().find_map(|(code, &kind)| {
            let detail = status_words[STATUS_FAILURE_BASE + code];
            (detail != u32::MAX).then_some(X86FinalizeFailure { kind, detail })
        }) {
            return Ok(X86FinalizeAttempt::Rejected(failure));
        }
        let (symbol_demand, identity_demand) = (status_words[1], status_words[2]);
        if symbol_demand != transfer.symbol_count
            || identity_demand != transfer.identity_word_count()
        {
            bail!(
                "GPU symbol finalization reported demand {symbol_demand}/{identity_demand} for {} symbols and {} identity words",
                transfer.symbol_count,
                transfer.identity_word_count()
            );
        }
        if symbol_demand > output.symbols || identity_demand > output.identity_words {
            if status_words[0] != 0 {
                bail!("GPU symbol finalization published past its output capacity");
            }
            return Ok(X86FinalizeAttempt::NeedsCapacity {
                symbols: symbol_demand,
                identity_words: identity_demand,
            });
        }
        if status_words[0] != generation.get() {
            bail!(
                "GPU symbol finalization did not seal generation {} (status {})",
                generation.get(),
                status_words[0]
            );
        }
        let symbol_bytes = &bytes[symbols_at..symbols_at + symbol_copy_bytes];
        let identity_bytes = &bytes[identity_at..identity_at + identity_copy_bytes];
        Ok(X86FinalizeAttempt::Published(
            transfer.split(symbol_bytes, identity_bytes),
        ))
    }

    fn input(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        label: &str,
        words: &[u32],
    ) -> LaniusBuffer<u32> {
        let contents = if words.is_empty() {
            &[0u8; 4][..]
        } else {
            u32_words_bytes(words)
        };
        let buffer = self.buffers.binding_capacity(
            device,
            label,
            contents.len(),
            wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        );
        buffer.write(queue, 0, contents);
        buffer
    }

    fn readback(&self, device: &wgpu::Device, label: &str, bytes: usize) -> LaniusBuffer<u8> {
        self.buffers.buffer(
            device,
            label,
            bytes.max(4),
            bytes.max(4),
            wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        )
    }

    fn build_graph(&self, device: &wgpu::Device, shape: GraphShape) -> Result<FinalizeGraph> {
        let objects = shape.objects.max(1) as u64;
        let symbols = shape.symbols.max(1) as u64;
        let words = shape.identity_words.max(1) as u64;
        let routes = shape.routes.max(1) as u64;
        let out_symbols = shape.output.symbols.max(1) as u64;
        let out_words = shape.output.identity_words.max(1) as u64;
        let mut graph = CompilerGraphBuilder::new();
        for (name, class, bytes) in [
            ("fin_objects", ResourceClass::Input, objects * 16),
            (
                "fin_symbols_in",
                ResourceClass::Input,
                symbols * GPU_X86_SYMBOL_ROW_BYTES as u64,
            ),
            ("fin_identity_in", ResourceClass::Input, words * 4),
            ("fin_routes", ResourceClass::Input, routes * 16),
            ("fin_readiness", ResourceClass::Input, 16),
            ("fin_word_owner", ResourceClass::Workspace, words * 4),
            ("fin_word_preserved", ResourceClass::Workspace, words * 4),
            ("fin_symbol_final", ResourceClass::Workspace, symbols * 16),
            (
                "fin_status",
                ResourceClass::Workspace,
                STATUS_WORDS as u64 * 4,
            ),
            (
                "fin_symbols_out",
                ResourceClass::Workspace,
                out_symbols * GPU_X86_SYMBOL_ROW_BYTES as u64,
            ),
            ("fin_identity_out", ResourceClass::Workspace, out_words * 4),
            // The status, the symbols and the identity words, mapped once.
            (
                "fin_readback",
                ResourceClass::External,
                STATUS_WORDS as u64 * 4
                    + out_symbols * GPU_X86_SYMBOL_ROW_BYTES as u64
                    + out_words * 4,
            ),
        ] {
            graph
                .add_resource(ResourceDesc {
                    name,
                    domain: ResourceDomain::Declarations,
                    class,
                    bytes,
                    usage: WorkspaceUsageClass::Storage,
                })
                .map_err(anyhow::Error::msg)?;
        }
        for (name, pass, first_writes) in [
            (
                PASS_CLEAR,
                &self.clear,
                &["fin_word_owner", "fin_word_preserved", "fin_status"][..],
            ),
            (PASS_OBJECTS, &self.objects, &[][..]),
            (PASS_ROUTES, &self.routes, &[][..]),
            (PASS_CLASSIFY, &self.classify, &["fin_symbol_final"][..]),
            (PASS_CHECK, &self.check, &[][..]),
            (
                PASS_EMIT_SYMBOLS,
                &self.emit_symbols,
                &["fin_symbols_out"][..],
            ),
            (
                PASS_EMIT_IDENTITY,
                &self.emit_identity,
                &["fin_identity_out"][..],
            ),
        ] {
            let modes = first_writes
                .iter()
                .map(|&binding| (binding, AccessMode::Write))
                .collect::<Vec<_>>();
            graph
                .add_reflected_compute_pass_by_name_with_modes(
                    name,
                    CompilerPhase::Artifact,
                    ResourceDomain::Declarations,
                    &pass.reflection,
                    &modes,
                )
                .map_err(anyhow::Error::msg)?;
        }
        for (name, source, destination) in [
            (COPY_STATUS, "fin_status", "fin_readback"),
            (COPY_SYMBOLS, "fin_symbols_out", "fin_readback"),
            (COPY_IDENTITY, "fin_identity_out", "fin_readback"),
        ] {
            let source_id = graph.resource_id(source).expect("finalize resource");
            let destination_id = graph.resource_id(destination).expect("finalize resource");
            graph
                .add_buffer_copy_pass(
                    name,
                    CompilerPhase::Artifact,
                    source,
                    source_id,
                    destination,
                    destination_id,
                )
                .map_err(anyhow::Error::msg)?;
        }
        let graph = graph.build().map_err(anyhow::Error::msg)?;
        let materialized = MaterializedCompilerGraph::new_with_upstream_storage(
            device,
            "x86_symbol_finalize",
            graph,
            &[],
        )
        .map_err(anyhow::Error::msg)?;
        Ok(FinalizeGraph {
            shape,
            materialized,
        })
    }

    /// Overwrites every retained workspace column with garbage, as a reused
    /// allocation from an unrelated job would leave it.
    #[cfg(test)]
    pub(crate) fn poison_workspace_for_test(&self, queue: &wgpu::Queue) -> Result<()> {
        let guard = self.graph.lock().expect("finalize graph poisoned");
        let Some(graph) = guard.as_ref() else {
            return Ok(());
        };
        for name in [
            "fin_word_owner",
            "fin_word_preserved",
            "fin_symbol_final",
            "fin_status",
            "fin_symbols_out",
            "fin_identity_out",
        ] {
            let buffer = graph.materialized.buffer::<u8>(name)?;
            let garbage = (0..buffer.byte_size)
                .map(|index| (index as u8).wrapping_mul(37) ^ 0xa5)
                .collect::<Vec<_>>();
            buffer.write(queue, 0, &garbage);
        }
        Ok(())
    }
}

/// Dense transfer layout: objects are concatenated in caller order, each
/// identity column starting on a word boundary. This is byte placement only;
/// the GPU validates it before using it.
struct Transfer {
    objects: Vec<u32>,
    symbol_words: Vec<u32>,
    identity_words: Vec<u32>,
    symbol_count: u32,
    ranges: Vec<(usize, usize, usize, usize)>,
}

impl Transfer {
    fn new(columns: &[X86SymbolColumns]) -> Result<Self> {
        let mut transfer = Self {
            objects: Vec::with_capacity(columns.len() * 4),
            symbol_words: Vec::new(),
            identity_words: Vec::new(),
            symbol_count: 0,
            ranges: Vec::with_capacity(columns.len()),
        };
        for column in columns {
            let symbol_count = column.symbol_count()?;
            let identity_len = u32::try_from(column.identity_bytes.len())
                .map_err(|_| anyhow!("x86 identity column exceeds u32 bytes"))?;
            let symbol_start = transfer.symbol_count;
            let word_start = u32::try_from(transfer.identity_words.len())
                .map_err(|_| anyhow!("x86 identity transfer exceeds u32 words"))?;
            transfer.objects.extend_from_slice(&[
                symbol_start,
                symbol_count,
                word_start,
                identity_len,
            ]);
            transfer.symbol_words.extend(
                column
                    .symbol_rows
                    .chunks_exact(4)
                    .map(|word| u32::from_le_bytes(word.try_into().expect("four bytes"))),
            );
            transfer
                .identity_words
                .extend(column.identity_bytes.chunks(4).map(|chunk| {
                    let mut word = [0u8; 4];
                    word[..chunk.len()].copy_from_slice(chunk);
                    u32::from_le_bytes(word)
                }));
            transfer.symbol_count = symbol_start
                .checked_add(symbol_count)
                .ok_or_else(|| anyhow!("x86 symbol transfer exceeds u32 rows"))?;
            transfer.ranges.push((
                symbol_start as usize * GPU_X86_SYMBOL_ROW_BYTES,
                column.symbol_rows.len(),
                word_start as usize * 4,
                column.identity_bytes.len(),
            ));
        }
        u32::try_from(transfer.identity_words.len())
            .map_err(|_| anyhow!("x86 identity transfer exceeds u32 words"))?;
        Ok(transfer)
    }

    fn object_count(&self) -> u32 {
        (self.objects.len() / 4) as u32
    }

    fn identity_word_count(&self) -> u32 {
        self.identity_words.len() as u32
    }

    fn split(&self, symbols: &[u8], identity: &[u8]) -> Vec<X86SymbolColumns> {
        self.ranges
            .iter()
            .map(
                |&(symbol_start, symbol_len, identity_start, identity_len)| X86SymbolColumns {
                    symbol_rows: symbols[symbol_start..symbol_start + symbol_len].to_vec(),
                    identity_bytes: identity[identity_start..identity_start + identity_len]
                        .to_vec(),
                },
            )
            .collect()
    }
}

fn read_bytes(
    device: &wgpu::Device,
    readback: &LaniusBuffer<u8>,
    bytes: usize,
    label: &str,
) -> Result<Vec<u8>> {
    if bytes == 0 {
        return Ok(Vec::new());
    }
    let slice = readback.buffer.slice(..bytes as u64);
    if let Err(error) = crate::gpu::passes_core::wait_for_readback_map(
        device,
        &slice,
        &format!("codegen.x86.finalize.{label}"),
        std::time::Duration::from_secs(30),
    ) {
        // A timeout or device-poll failure may leave the map pending. Cancel
        // it before the cached allocation is reused by another submission.
        readback.buffer.unmap();
        return Err(error);
    }
    let mapped = slice.get_mapped_range();
    let out = mapped.to_vec();
    drop(mapped);
    readback.buffer.unmap();
    Ok(out)
}

#[cfg(test)]
mod tests;
