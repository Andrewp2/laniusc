//! Declarative ownership graph for GPU compiler passes and logical resources.
//!
//! `LaniusBuffer` owns physical storage. This module owns the other half of the
//! contract: what a logical array contains, which pass initializes it, how it
//! is accessed, and when its storage becomes reusable.

use std::collections::{BTreeMap, BTreeSet};

use serde::Serialize;

use super::{
    buffers::{LaniusBuffer, TrackedBufferView},
    kernels::KernelReflections,
    workspace::{
        WorkspaceArenaLayout,
        WorkspaceArenaLimits,
        WorkspaceAssignment,
        WorkspacePlan,
        WorkspaceSlotPlan,
        WorkspaceUsageClass,
        plan_workspace_arenas_with_conflicts,
    },
};
use crate::reflection::{ParameterReflection, SlangReflection, slang_category_and_type_to_wgpu};

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum CompilerPhase {
    Source,
    Lex,
    Parse,
    Hir,
    TypeCheck,
    SemanticLowering,
    X86Lowering,
    WasmLowering,
    Artifact,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ResourceDomain {
    Bytes,
    SourceBytes,
    Tokens,
    RawNodes,
    HirNodes,
    Declarations,
    Types,
    Calls,
    CallArguments,
    SemanticInstructions,
    X86Instructions,
    WasmInstructions,
    ArtifactBytes,
    DispatchArguments,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ResourceClass {
    /// Initialized outside the graph and immutable inside it.
    Input,
    /// Mutable storage owned by another graph or compiler stage.
    ///
    /// External resources participate in access, liveness, reflection, and
    /// alias validation, but this graph neither allocates nor recolors them.
    /// This is the explicit boundary for incremental graph composition; it is
    /// not an escape hatch for untracked writable scratch.
    External,
    /// Initialized by exactly one pass and immutable afterwards.
    Artifact,
    /// Mutable scratch whose storage may be reused after its final access.
    Workspace,
    /// Mutable graph-owned storage with a dedicated logical slot.
    ///
    /// Use this while a resource crosses a composition boundary whose full
    /// pass schedule is not yet represented in this graph. It preserves
    /// allocation ownership and binding validation without making an
    /// unsound liveness claim. Its non-overlapping range may still live in a
    /// shared physical arena. Once the complete schedule is registered, the
    /// resource can become `Workspace` and participate in lifetime coloring.
    Resident,
    /// Mutable graph result retained after the final pass.
    Output,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AccessMode {
    Read,
    Write,
    ReadWrite,
}

impl AccessMode {
    pub const fn reads(self) -> bool {
        matches!(self, Self::Read | Self::ReadWrite)
    }

    pub const fn writes(self) -> bool {
        matches!(self, Self::Write | Self::ReadWrite)
    }
}

impl CompilerPhase {
    const fn diagnostic_name(self) -> &'static str {
        match self {
            Self::Source => "source",
            Self::Lex => "lex",
            Self::Parse => "parse",
            Self::Hir => "hir",
            Self::TypeCheck => "type_check",
            Self::SemanticLowering => "semantic_lowering",
            Self::X86Lowering => "x86_lowering",
            Self::WasmLowering => "wasm_lowering",
            Self::Artifact => "artifact",
        }
    }
}

impl ResourceDomain {
    const fn diagnostic_name(self) -> &'static str {
        match self {
            Self::Bytes => "bytes",
            Self::SourceBytes => "source_bytes",
            Self::Tokens => "tokens",
            Self::RawNodes => "raw_nodes",
            Self::HirNodes => "hir_nodes",
            Self::Declarations => "declarations",
            Self::Types => "types",
            Self::Calls => "calls",
            Self::CallArguments => "call_arguments",
            Self::SemanticInstructions => "semantic_instructions",
            Self::X86Instructions => "x86_instructions",
            Self::WasmInstructions => "wasm_instructions",
            Self::ArtifactBytes => "artifact_bytes",
            Self::DispatchArguments => "dispatch_arguments",
        }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct ResourceId(usize);

impl ResourceId {
    pub const fn index(self) -> usize {
        self.0
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub struct PassId(usize);

impl PassId {
    pub const fn index(self) -> usize {
        self.0
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ResourceDesc {
    pub name: &'static str,
    pub domain: ResourceDomain,
    pub class: ResourceClass,
    pub bytes: u64,
    pub usage: WorkspaceUsageClass,
}

/// A logical stream whose full extent need not be resident at once.
///
/// `ResourceDesc::bytes` is the storage actually owned by the graph. It must
/// contain `resident_pages` pages. `logical_bytes` is the largest stream a job
/// may address. Pass recording binds one page together with the logical range
/// represented by that page.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PagedResourceDesc {
    pub logical_bytes: u64,
    pub page_bytes: u64,
    pub resident_pages: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PassAccess {
    pub binding: &'static str,
    pub resource: ResourceId,
    pub mode: AccessMode,
    pub reflected: bool,
    /// The pass establishes this binding's contents before any invocation
    /// reads them, so no earlier producer is required.
    pub initializes_before_read: bool,
    /// Shader invocation within one recorded compute batch.
    pub invocation: u16,
}

impl PassAccess {
    pub const fn read(binding: &'static str, resource: ResourceId) -> Self {
        Self {
            binding,
            resource,
            mode: AccessMode::Read,
            reflected: true,
            initializes_before_read: false,
            invocation: 0,
        }
    }

    pub const fn write(binding: &'static str, resource: ResourceId) -> Self {
        Self {
            binding,
            resource,
            mode: AccessMode::Write,
            reflected: true,
            initializes_before_read: false,
            invocation: 0,
        }
    }

    pub const fn read_write(binding: &'static str, resource: ResourceId) -> Self {
        Self {
            binding,
            resource,
            mode: AccessMode::ReadWrite,
            reflected: true,
            initializes_before_read: false,
            invocation: 0,
        }
    }

    pub const fn initialize_read_write(binding: &'static str, resource: ResourceId) -> Self {
        Self {
            binding,
            resource,
            mode: AccessMode::ReadWrite,
            reflected: true,
            initializes_before_read: true,
            invocation: 0,
        }
    }

    /// A command-processor read used to source indirect dispatch dimensions.
    /// It participates in liveness and allocation validation but is not part
    /// of the shader's reflected storage interface.
    pub const fn indirect(binding: &'static str, resource: ResourceId) -> Self {
        Self {
            binding,
            resource,
            mode: AccessMode::Read,
            reflected: false,
            initializes_before_read: false,
            invocation: 0,
        }
    }

    pub const fn in_invocation(mut self, invocation: u16) -> Self {
        self.invocation = invocation;
        self
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PassDesc {
    pub name: &'static str,
    pub phase: CompilerPhase,
    pub dispatch_domain: ResourceDomain,
    pub accesses: Vec<PassAccess>,
}

/// Read-only diagnostic form of a resident compiler graph. This is populated
/// only when graph profiling is enabled, so normal compilation does not pay
/// for cloning names or constructing dependency rows.
#[derive(Clone, Debug, Serialize)]
pub(crate) struct CompilerGraphDiagnostic {
    pub label: String,
    pub nodes: Vec<CompilerGraphDiagnosticNode>,
    pub edges: Vec<CompilerGraphDiagnosticEdge>,
}

#[derive(Clone, Debug, Serialize)]
pub(crate) struct CompilerGraphDiagnosticNode {
    pub id: usize,
    pub name: &'static str,
    pub phase: &'static str,
    pub dispatch_domain: &'static str,
}

#[derive(Clone, Debug, Serialize)]
pub(crate) struct CompilerGraphDiagnosticEdge {
    pub source: usize,
    pub target: usize,
    pub dependencies: Vec<CompilerGraphDiagnosticDependency>,
}

#[derive(Clone, Debug, Serialize)]
pub(crate) struct CompilerGraphDiagnosticDependency {
    pub resource: &'static str,
    pub hazard: &'static str,
}

/// Maps one reflected storage binding to its logical graph resource.
///
/// `mode = None` conservatively derives `Read` or `ReadWrite` from Slang.
/// A precise override may narrow `ReadWrite` to `Write` for initialization
/// passes, but may never hide shader-visible reads or writes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ReflectedResourceBinding {
    pub binding: &'static str,
    pub resource: ResourceId,
    pub mode: Option<AccessMode>,
}

/// The graph-facing contract of one reflected compute operation.
///
/// Slang reflection supplies the complete storage surface. The specification
/// only names the operation's semantic position and the uncommon writable
/// bindings which are initialized rather than read-modified-written.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ReflectedComputeSpec {
    pub name: &'static str,
    pub kernel: &'static str,
    pub phase: CompilerPhase,
    pub dispatch_domain: ResourceDomain,
    pub modes: &'static [(&'static str, AccessMode)],
    pub aliases: &'static [ReflectedResourceAlias],
    pub initializes_writable_bindings: bool,
}

impl ReflectedComputeSpec {
    pub const fn new(
        name: &'static str,
        kernel: &'static str,
        phase: CompilerPhase,
        dispatch_domain: ResourceDomain,
    ) -> Self {
        Self {
            name,
            kernel,
            phase,
            dispatch_domain,
            modes: &[],
            aliases: &[],
            initializes_writable_bindings: false,
        }
    }

    pub const fn with_modes(mut self, modes: &'static [(&'static str, AccessMode)]) -> Self {
        self.modes = modes;
        self
    }

    pub const fn initializer(mut self) -> Self {
        self.initializes_writable_bindings = true;
        self
    }

    pub const fn with_aliases(mut self, aliases: &'static [ReflectedResourceAlias]) -> Self {
        self.aliases = aliases;
        self
    }

    pub(crate) fn register_kernel(
        self,
        graph: &mut CompilerGraphBuilder,
        kernels: &impl KernelReflections,
    ) -> Result<PassId, String> {
        let reflection = kernels.reflection(self.kernel)?;
        let pass = self.register_reflection(graph, reflection)?;
        Ok(pass)
    }

    pub(crate) fn register_reflection(
        self,
        graph: &mut CompilerGraphBuilder,
        reflection: &SlangReflection,
    ) -> Result<PassId, String> {
        let pass = if self.initializes_writable_bindings {
            if !self.modes.is_empty() || !self.aliases.is_empty() {
                return Err(format!(
                    "reflected compute specification {} combines initializer semantics with explicit modes",
                    self.name,
                ));
            }
            graph.add_reflected_initializer_by_name(
                self.name,
                self.phase,
                self.dispatch_domain,
                reflection,
            )
        } else {
            let mut overrides = Vec::with_capacity(self.modes.len() + self.aliases.len());
            for &(binding, mode) in self.modes {
                overrides.push(ReflectedResourceBinding {
                    binding,
                    resource: graph.resource_id(binding).ok_or_else(|| {
                        format!(
                            "reflected compute specification {} references unknown resource {binding}",
                            self.name,
                        )
                    })?,
                    mode: Some(mode),
                });
            }
            for alias in self.aliases {
                overrides.push(ReflectedResourceBinding {
                    binding: alias.binding,
                    resource: graph.resource_id(alias.resource).ok_or_else(|| {
                        format!(
                            "reflected compute specification {} aliases {} to unknown resource {}",
                            self.name, alias.binding, alias.resource,
                        )
                    })?,
                    mode: alias.mode,
                });
            }
            graph.add_reflected_compute_pass_by_name(
                self.name,
                self.phase,
                self.dispatch_domain,
                reflection,
                &overrides,
            )
        }?;
        graph.pass_kernels[pass.index()] = Some(self.kernel);
        Ok(pass)
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ReflectedResourceAlias {
    pub binding: &'static str,
    pub resource: &'static str,
    pub mode: Option<AccessMode>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ResourceLifetime {
    pub first_pass: PassId,
    pub last_pass: PassId,
    pub producer: Option<PassId>,
}

/// Conservatively extends one resource across a known execution interval.
///
/// This is a migration boundary for compiler phases whose complete command
/// schedule has not yet been imported into the graph. It prevents workspace
/// coloring from aliasing storage across omitted passes without pretending
/// those passes read or write bindings that they do not expose here.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ResourceLifetimeFence {
    pub resource: ResourceId,
    pub first_pass: &'static str,
    pub last_pass: &'static str,
}

/// A contiguous graph body executed more than once. Liveness covers the
/// entire repeated region, so scratch cannot be aliased merely because its
/// textual producer and consumer appear in the first body iteration.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RepeatedPassRegion {
    pub first_pass: PassId,
    pub pass_count: u32,
    pub iterations: u32,
}

/// A contiguous graph body recorded once for every populated window of a
/// paged logical stream. The GPU-produced total controls the number of active
/// windows; no host allocation is implied between iterations.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PagedPassRegion {
    pub first_pass: PassId,
    pub pass_count: u32,
    pub driving_resource: ResourceId,
}

/// A logical graph resource bound to a byte range of one physical GPU
/// allocation for a particular pass. Aliased `LaniusBuffer`s carry the same
/// allocation id, allowing the graph to reject unsafe simultaneous aliases
/// without depending on their Rust element type.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct BoundGraphResource {
    pub binding: &'static str,
    pub resource: ResourceId,
    pub allocation_id: u64,
    pub byte_offset: u64,
    pub byte_size: u64,
    pub logical_offset: u64,
    pub logical_size: u64,
}

impl BoundGraphResource {
    pub const fn whole(
        binding: &'static str,
        resource: ResourceId,
        allocation_id: u64,
        byte_size: u64,
    ) -> Self {
        Self {
            binding,
            resource,
            allocation_id,
            byte_offset: 0,
            byte_size,
            logical_offset: 0,
            logical_size: byte_size,
        }
    }

    pub const fn window(
        binding: &'static str,
        resource: ResourceId,
        allocation_id: u64,
        byte_offset: u64,
        byte_size: u64,
        logical_offset: u64,
        logical_size: u64,
    ) -> Self {
        Self {
            binding,
            resource,
            allocation_id,
            byte_offset,
            byte_size,
            logical_offset,
            logical_size,
        }
    }

    pub fn buffer<T>(
        binding: &'static str,
        resource: ResourceId,
        buffer: &LaniusBuffer<T>,
    ) -> Result<Self, String> {
        let allocation_id = buffer.allocation_id().ok_or_else(|| {
            format!("graph binding {binding} uses an allocation not owned by Lanius")
        })?;
        Ok(Self::window(
            binding,
            resource,
            allocation_id,
            buffer.byte_offset,
            buffer.byte_size as u64,
            0,
            buffer.byte_size as u64,
        ))
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompilerGraph {
    resources: Vec<ResourceDesc>,
    resource_aliases: BTreeMap<&'static str, ResourceId>,
    reflected_arena_conflicts: BTreeSet<(ResourceId, ResourceId)>,
    passes: Vec<PassDesc>,
    pass_kernels: Vec<Option<&'static str>>,
    reflection_complete: Vec<bool>,
    lifetimes: Vec<Option<ResourceLifetime>>,
    repeated_regions: Vec<RepeatedPassRegion>,
    paged_regions: Vec<PagedPassRegion>,
    paged_resources: Vec<Option<PagedResourceDesc>>,
    lifetime_fences: Vec<ResourceLifetimeFence>,
    workspace: WorkspacePlan,
}

/// Stable physical slot allocation for one compiler graph capacity. Logical
/// resources obtain typed aliases of these slots; the graph, rather than the
/// caller, decides which non-overlapping lifetimes share storage.
pub struct CompilerGraphWorkspace {
    slots: Vec<LaniusBuffer<u8>>,
    slot_by_resource: Vec<Option<u32>>,
}

/// A compiler graph together with the physical storage selected for it.
///
/// Compiler phases own semantic state, not allocation plumbing. This value is
/// the common boundary for materializing a graph, recovering typed resource
/// views, and validating the allocation identities used during recording.
pub(crate) struct MaterializedCompilerGraph {
    graph: CompilerGraph,
    workspace: CompilerGraphWorkspace,
    allocations: CompilerGraphAllocations,
}

/// Allocation-preserving views of every resource physically owned by one
/// compiler graph.  Binding construction consumes this set directly instead
/// of rebuilding the graph's resource table as hundreds of local variables.
pub(crate) struct CompilerGraphBindings {
    buffers: Vec<Option<LaniusBuffer<u8>>>,
}

impl CompilerGraphBindings {
    pub(crate) fn buffer(&self, resource: ResourceId) -> Option<&LaniusBuffer<u8>> {
        self.buffers.get(resource.index()).and_then(Option::as_ref)
    }

    pub(crate) fn iter(&self) -> impl Iterator<Item = (ResourceId, &LaniusBuffer<u8>)> {
        self.buffers
            .iter()
            .enumerate()
            .filter_map(|(index, buffer)| buffer.as_ref().map(|buffer| (ResourceId(index), buffer)))
    }
}

/// One byte range owned by a logical graph resource inside a physical GPU
/// allocation. Whole-buffer workspaces use offset zero; arena-backed
/// workspaces assign disjoint non-zero ranges of a shared allocation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct GraphAllocationRange {
    allocation_id: u64,
    byte_offset: u64,
    byte_size: u64,
}

/// Copyable ownership ranges for graph-managed physical storage. Stages keep
/// this after construction so recording can prove that non-input resources
/// still use both the allocation and byte range selected by the graph.
#[derive(Clone, Debug)]
pub struct CompilerGraphAllocations {
    allocation_by_resource: Vec<Option<GraphAllocationRange>>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
struct UpstreamSlotPlacement {
    slot_index: usize,
    upstream_index: usize,
    byte_offset: u64,
}

fn unique_physical_upstream_views<'a>(
    upstream: &[TrackedBufferView<'a>],
) -> Vec<TrackedBufferView<'a>> {
    let mut unique = Vec::<TrackedBufferView<'a>>::new();
    for candidate in upstream.iter().copied() {
        let Some(allocation_id) = candidate.allocation_id() else {
            continue;
        };
        if unique
            .iter()
            .any(|current| current.buffer == candidate.buffer)
        {
            continue;
        }
        // Cross-phase imports are valid only when the producer declares its
        // complete physical allocation dead. Recover that whole allocation
        // from any logical alias so the consumer can pack several slots into
        // it without inheriting producer-side fragmentation.
        unique.push(TrackedBufferView::from_parts(
            candidate.buffer,
            0,
            candidate.buffer.size(),
            Some(allocation_id),
        ));
    }
    unique
}

/// Packs simultaneously-live consumer slots into disjoint ranges of storage
/// whose producer phase is complete. Exclusive slots are placed before
/// flexible slots because consuming even one byte of an upstream allocation
/// makes it unavailable to a later exclusive slot. Within each constraint
/// class, larger slots are placed first and best-fit limits fragmentation
/// without depending on the producer's logical array boundaries.
fn pack_slots_into_upstream_storage(
    slot_ids: &[u32],
    slot_bytes: &[u64],
    upstream_bytes: &[u64],
    alignment: u64,
    incompatible_slots: &BTreeSet<(u32, u32)>,
    exclusive_slots: &BTreeSet<u32>,
) -> Vec<UpstreamSlotPlacement> {
    debug_assert_eq!(slot_ids.len(), slot_bytes.len());
    let alignment = alignment.max(1);
    let mut cursors = vec![0u64; upstream_bytes.len()];
    let mut upstream_slots = vec![Vec::<u32>::new(); upstream_bytes.len()];
    let mut upstream_is_exclusive = vec![false; upstream_bytes.len()];
    let mut placements = Vec::with_capacity(slot_bytes.len());
    let mut slot_indices = (0..slot_bytes.len()).collect::<Vec<_>>();
    slot_indices.sort_unstable_by_key(|&slot_index| {
        (
            !exclusive_slots.contains(&slot_ids[slot_index]),
            std::cmp::Reverse(slot_bytes[slot_index]),
            slot_ids[slot_index],
        )
    });
    for slot_index in slot_indices {
        let bytes = slot_bytes[slot_index];
        let slot = slot_ids[slot_index];
        let candidate = upstream_bytes
            .iter()
            .enumerate()
            .filter_map(|(upstream_index, &capacity)| {
                if upstream_is_exclusive[upstream_index]
                    || (exclusive_slots.contains(&slot)
                        && !upstream_slots[upstream_index].is_empty())
                {
                    return None;
                }
                if upstream_slots[upstream_index]
                    .iter()
                    .any(|&other| incompatible_slots.contains(&(slot.min(other), slot.max(other))))
                {
                    return None;
                }
                let offset = cursors[upstream_index].next_multiple_of(alignment);
                let end = offset.checked_add(bytes)?;
                (end <= capacity).then(|| (upstream_index, offset, capacity - end))
            })
            .min_by_key(|&(upstream_index, _, remaining)| (remaining, upstream_index));
        let Some((upstream_index, byte_offset, _)) = candidate else {
            continue;
        };
        cursors[upstream_index] = byte_offset + bytes;
        upstream_slots[upstream_index].push(slot);
        upstream_is_exclusive[upstream_index] = exclusive_slots.contains(&slot);
        placements.push(UpstreamSlotPlacement {
            slot_index,
            upstream_index,
            byte_offset,
        });
    }
    placements.sort_unstable_by_key(|placement| placement.slot_index);
    placements
}

impl CompilerGraphWorkspace {
    pub fn new(device: &wgpu::Device, label: &str, graph: &CompilerGraph) -> Result<Self, String> {
        Self::new_with_imports(device, label, graph, &[])
    }

    /// Reuses dead storage-only allocations from the preceding compiler phase.
    /// Largest compatible graph-owned slots are selected first and packed
    /// into disjoint aligned ranges; unmatched slots keep the normal stable
    /// allocation path.
    pub fn new_with_upstream_storage(
        device: &wgpu::Device,
        label: &str,
        graph: &CompilerGraph,
        upstream: &[TrackedBufferView<'_>],
    ) -> Result<Self, String> {
        if std::env::var_os("LANIUS_COMPILER_GRAPH_DISABLE_COLORING").is_some() {
            return Self::new(device, label, graph);
        }
        // A phase may expose several typed aliases of the same physical
        // allocation. Treat that allocation as one candidate. The producer
        // phase is complete, so multiple consumer slots may safely occupy
        // disjoint ranges of that candidate.
        let available = unique_physical_upstream_views(upstream);
        let mut slots = graph
            .workspace
            .slots
            .iter()
            .filter(|slot| {
                slot.usage == WorkspaceUsageClass::Storage
                    && graph.workspace.assignments.iter().any(|assignment| {
                        assignment.slot == slot.slot
                            && graph
                                .resource_id(assignment.name)
                                .and_then(|resource| graph.resource(resource))
                                .is_some_and(|resource| {
                                    !matches!(
                                        resource.class,
                                        ResourceClass::Input | ResourceClass::External
                                    )
                                })
                    })
            })
            .collect::<Vec<_>>();
        slots.sort_unstable_by_key(|slot| std::cmp::Reverse(slot.bytes));

        let arena_conflicts = graph.workspace_arena_conflicts();
        let placements = pack_slots_into_upstream_storage(
            &slots.iter().map(|slot| slot.slot).collect::<Vec<_>>(),
            &slots.iter().map(|slot| slot.bytes).collect::<Vec<_>>(),
            &available
                .iter()
                .map(|buffer| buffer.byte_size)
                .collect::<Vec<_>>(),
            u64::from(device.limits().min_storage_buffer_offset_alignment),
            &arena_conflicts,
            &BTreeSet::new(),
        );
        for (index, left) in placements.iter().enumerate() {
            for right in &placements[index + 1..] {
                if left.upstream_index != right.upstream_index {
                    continue;
                }
                let left_slot = slots[left.slot_index].slot;
                let right_slot = slots[right.slot_index].slot;
                assert!(
                    !arena_conflicts
                        .contains(&(left_slot.min(right_slot), left_slot.max(right_slot))),
                    "upstream arena packing placed incompatible slots {left_slot} and {right_slot} in allocation candidate {}",
                    left.upstream_index,
                );
            }
        }

        let mut imports = Vec::new();
        for placement in placements {
            let slot = slots[placement.slot_index];
            let allocation = available[placement.upstream_index];
            let buffer = allocation.subrange(placement.byte_offset, slot.bytes)?;
            let assignment = graph
                .workspace
                .assignments
                .iter()
                .find(|assignment| {
                    assignment.slot == slot.slot
                        && graph
                            .resource_id(assignment.name)
                            .and_then(|resource| graph.resource(resource))
                            .is_some_and(|resource| {
                                !matches!(
                                    resource.class,
                                    ResourceClass::Input | ResourceClass::External
                                )
                            })
                })
                .ok_or_else(|| format!("workspace slot {} has no logical resource", slot.slot))?;
            let resource = graph.resource_id(assignment.name).ok_or_else(|| {
                format!(
                    "workspace assignment names unknown resource {}",
                    assignment.name
                )
            })?;
            if std::env::var_os("LANIUS_COMPILER_GRAPH_DUMP_SLOTS").is_some() {
                eprintln!(
                    "compiler_graph_import label={label} slot={} resource={} allocation={:?} offset={} bytes={} slot_bytes={}",
                    slot.slot,
                    assignment.name,
                    buffer.allocation_id(),
                    buffer.byte_offset,
                    allocation.byte_size,
                    slot.bytes,
                );
            }
            imports.push((resource, buffer.alias::<u8>(slot.bytes as usize)));
        }
        Self::new_with_imports(device, label, graph, &imports)
    }

    /// Builds graph workspace while importing dead upstream allocations for
    /// selected slots. Every logical resource assigned to an imported slot
    /// continues to use the graph's lifetime and alias plan; only the physical
    /// allocation comes from the preceding compiler phase.
    pub fn new_with_imports(
        device: &wgpu::Device,
        label: &str,
        graph: &CompilerGraph,
        imports: &[(ResourceId, LaniusBuffer<u8>)],
    ) -> Result<Self, String> {
        let mut imported_by_slot = BTreeMap::<u32, LaniusBuffer<u8>>::new();
        for (resource, buffer) in imports {
            let desc = graph
                .resource(*resource)
                .ok_or_else(|| format!("unknown compiler resource {}", resource.index()))?;
            if matches!(desc.class, ResourceClass::Input | ResourceClass::External) {
                return Err(format!(
                    "compiler resource {} cannot import graph-owned storage because it is {:?}",
                    desc.name, desc.class,
                ));
            }
            let slot = graph
                .workspace
                .assignments
                .iter()
                .find(|assignment| assignment.name == desc.name)
                .map(|assignment| assignment.slot)
                .ok_or_else(|| format!("compiler resource {} has no workspace slot", desc.name))?;
            if let Some(previous) = imported_by_slot.insert(slot, buffer.clone()) {
                if previous.allocation_id() != buffer.allocation_id()
                    || previous.byte_offset != buffer.byte_offset
                    || previous.byte_size != buffer.byte_size
                {
                    return Err(format!(
                        "workspace slot {slot} has imports from two different allocation ranges",
                    ));
                }
            }
        }

        let unimported = WorkspacePlan {
            assignments: Vec::new(),
            slots: graph
                .workspace
                .slots
                .iter()
                .copied()
                .filter(|plan| !imported_by_slot.contains_key(&plan.slot))
                .collect(),
        };
        let arena_layout = plan_workspace_arenas_with_conflicts(
            &unimported,
            WorkspaceArenaLimits::from_device_limits(&device.limits())?,
            &graph.workspace_arena_conflicts(),
        )?;
        if std::env::var_os("LANIUS_COMPILER_GRAPH_DUMP_SLOTS").is_some() {
            for placement in &arena_layout.placements {
                let resources = graph
                    .workspace
                    .assignments
                    .iter()
                    .filter(|assignment| assignment.slot == placement.slot)
                    .map(|assignment| assignment.name)
                    .collect::<Vec<_>>();
                eprintln!(
                    "compiler_graph_arena label={label} arena={} slot={} offset={} bytes={} resources={resources:?}",
                    placement.arena, placement.slot, placement.byte_offset, placement.byte_size,
                );
            }
        }
        let arena_usage = wgpu::BufferUsages::STORAGE
            | wgpu::BufferUsages::COPY_SRC
            | wgpu::BufferUsages::COPY_DST
            | wgpu::BufferUsages::INDIRECT;
        let arenas = arena_layout
            .arenas
            .iter()
            .map(|plan| {
                let arena_label = format!("{label}.arena.{}", plan.arena);
                let raw = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some(&arena_label),
                    size: plan.bytes,
                    usage: arena_usage,
                    mapped_at_creation: false,
                });
                let buffer: LaniusBuffer<u8> =
                    LaniusBuffer::new_labeled((raw, plan.bytes), plan.bytes as usize, arena_label);
                crate::gpu::buffers::register_resettable_buffer(
                    &buffer,
                    crate::gpu::buffers::JobResetPolicy::ClearBeforeJob,
                );
                buffer
            })
            .collect::<Vec<_>>();

        let mut slots = Vec::with_capacity(graph.workspace.slots.len());
        for plan in &graph.workspace.slots {
            if plan.slot as usize != slots.len() {
                return Err(format!(
                    "compiler graph workspace has non-dense slot {}",
                    plan.slot
                ));
            }
            if let Some(imported) = imported_by_slot.remove(&plan.slot) {
                if plan.usage != WorkspaceUsageClass::Storage {
                    return Err(format!(
                        "workspace slot {} requires {:?} usage and cannot import storage-only phase scratch",
                        plan.slot, plan.usage,
                    ));
                }
                if imported.byte_size < plan.bytes as usize {
                    return Err(format!(
                        "workspace slot {} requires {} bytes but its upstream allocation has {}",
                        plan.slot, plan.bytes, imported.byte_size,
                    ));
                }
                let imported = imported.subrange::<u8>(0, plan.bytes, plan.bytes as usize)?;
                // Cross-phase imports are dead producer storage, but they are
                // still physical allocations reused by subsequent jobs. Make
                // them part of the consumer workspace's reset boundary just
                // like newly allocated arenas; otherwise old parser words can
                // leak into a later type-check job through an imported slot.
                crate::gpu::buffers::register_resettable_buffer(
                    &imported,
                    crate::gpu::buffers::JobResetPolicy::ClearBeforeJob,
                );
                slots.push(imported);
            } else {
                let placement = arena_layout
                    .placements
                    .iter()
                    .find(|placement| placement.slot == plan.slot)
                    .ok_or_else(|| {
                        format!("workspace slot {} has no arena placement", plan.slot)
                    })?;
                let arena = arenas.get(placement.arena as usize).ok_or_else(|| {
                    format!(
                        "workspace slot {} names missing arena {}",
                        plan.slot, placement.arena,
                    )
                })?;
                slots.push(arena.subrange::<u8>(
                    placement.byte_offset,
                    placement.byte_size,
                    placement.byte_size as usize,
                )?);
            }
        }
        debug_assert!(imported_by_slot.is_empty());
        let mut slot_by_resource = vec![None; graph.resources.len()];
        for assignment in &graph.workspace.assignments {
            let resource = graph.resource_id(assignment.name).ok_or_else(|| {
                format!(
                    "workspace assignment names unknown resource {}",
                    assignment.name
                )
            })?;
            slot_by_resource[resource.index()] = Some(assignment.slot);
        }
        let workspace = Self {
            slots,
            slot_by_resource,
        };
        register_compiler_graph_diagnostic(label, graph);
        Ok(workspace)
    }

    pub fn alias<T>(
        &self,
        graph: &CompilerGraph,
        resource: ResourceId,
        count: usize,
    ) -> Result<LaniusBuffer<T>, String> {
        let desc = graph
            .resource(resource)
            .ok_or_else(|| format!("unknown compiler resource {}", resource.index()))?;
        let required = (std::mem::size_of::<T>() as u64)
            .checked_mul(count as u64)
            .ok_or_else(|| format!("compiler resource {} typed size overflows", desc.name))?;
        if required > desc.bytes {
            return Err(format!(
                "compiler resource {} requests {} typed bytes but declares {}",
                desc.name, required, desc.bytes,
            ));
        }
        let slot = self
            .slot_by_resource
            .get(resource.index())
            .copied()
            .flatten()
            .ok_or_else(|| format!("compiler resource {} has no workspace slot", desc.name))?;
        self.slots
            .get(slot as usize)
            .map(|buffer| buffer.alias(count))
            .ok_or_else(|| format!("compiler resource {} names missing slot {slot}", desc.name))
    }

    pub fn allocations(&self) -> CompilerGraphAllocations {
        CompilerGraphAllocations {
            allocation_by_resource: self
                .slot_by_resource
                .iter()
                .map(|slot| {
                    slot.and_then(|slot| {
                        let buffer = self.slots.get(slot as usize)?;
                        Some(GraphAllocationRange {
                            allocation_id: buffer.allocation_id()?,
                            byte_offset: buffer.byte_offset,
                            byte_size: buffer.byte_size as u64,
                        })
                    })
                })
                .collect(),
        }
    }

    /// Materializes one untyped view for each graph-owned logical resource.
    /// Input and external resources are intentionally absent: their owning
    /// phase registers them explicitly at the graph boundary.
    pub(crate) fn bindings(&self, graph: &CompilerGraph) -> Result<CompilerGraphBindings, String> {
        let buffers = graph
            .resources()
            .iter()
            .enumerate()
            .map(|(index, resource)| {
                if matches!(
                    resource.class,
                    ResourceClass::Input | ResourceClass::External
                ) {
                    return Ok(None);
                }
                let count = usize::try_from(resource.bytes).map_err(|_| {
                    format!(
                        "compiler resource {} exceeds host addressable size",
                        resource.name
                    )
                })?;
                self.alias::<u8>(graph, ResourceId(index), count).map(Some)
            })
            .collect::<Result<Vec<_>, _>>()?;
        Ok(CompilerGraphBindings { buffers })
    }

    pub fn validate_pass_bindings(
        &self,
        graph: &CompilerGraph,
        pass: PassId,
        bindings: &[BoundGraphResource],
    ) -> Result<(), String> {
        self.allocations()
            .validate_pass_bindings(graph, pass, bindings)
    }
}

impl MaterializedCompilerGraph {
    pub(crate) fn new_with_upstream_storage(
        device: &wgpu::Device,
        label: &str,
        graph: CompilerGraph,
        upstream: &[TrackedBufferView<'_>],
    ) -> Result<Self, String> {
        let workspace =
            CompilerGraphWorkspace::new_with_upstream_storage(device, label, &graph, upstream)?;
        Ok(Self::from_parts(graph, workspace))
    }

    fn from_parts(graph: CompilerGraph, workspace: CompilerGraphWorkspace) -> Self {
        let allocations = workspace.allocations();
        Self {
            graph,
            workspace,
            allocations,
        }
    }

    pub(crate) fn graph(&self) -> &CompilerGraph {
        &self.graph
    }

    pub(crate) fn allocations(&self) -> &CompilerGraphAllocations {
        &self.allocations
    }

    pub(crate) fn bindings(&self) -> anyhow::Result<CompilerGraphBindings> {
        self.workspace
            .bindings(&self.graph)
            .map_err(anyhow::Error::msg)
    }

    /// Returns a full typed view of one named graph-owned resource.
    pub(crate) fn buffer<T>(&self, name: &str) -> anyhow::Result<LaniusBuffer<T>> {
        let resource = self
            .graph
            .resource_id(name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no resource `{name}`"))?;
        let bytes = self
            .graph
            .resource(resource)
            .expect("graph resource id")
            .bytes;
        let element_bytes = std::mem::size_of::<T>() as u64;
        if element_bytes == 0 || bytes % element_bytes != 0 {
            return Err(anyhow::anyhow!(
                "compiler resource `{name}` has {bytes} bytes, incompatible with {element_bytes}-byte elements",
            ));
        }
        let count = usize::try_from(bytes / element_bytes).map_err(|_| {
            anyhow::anyhow!("compiler resource `{name}` exceeds host addressable size")
        })?;
        self.workspace
            .alias(&self.graph, resource, count)
            .map_err(anyhow::Error::msg)
    }

    pub(crate) fn u32_buffer(&self, name: &str) -> anyhow::Result<LaniusBuffer<u32>> {
        self.buffer(name)
    }
}

impl CompilerGraphAllocations {
    /// Rebinds a logical resource at an explicit stage boundary. The caller is
    /// declaring that an upstream stage owns `buffer` and this stage imports
    /// that allocation under the graph resource's identity.
    pub fn import_buffer<T>(
        &mut self,
        graph: &CompilerGraph,
        resource: ResourceId,
        buffer: &LaniusBuffer<T>,
    ) -> Result<(), String> {
        let desc = graph
            .resource(resource)
            .ok_or_else(|| format!("unknown compiler resource {}", resource.index()))?;
        if matches!(desc.class, ResourceClass::Input | ResourceClass::External) {
            return Err(format!(
                "compiler resource {} is externally owned and does not need an allocation import",
                desc.name
            ));
        }
        let allocation_id = buffer.allocation_id().ok_or_else(|| {
            format!(
                "compiler resource {} imports a buffer without allocation identity",
                desc.name
            )
        })?;
        let slot = self
            .allocation_by_resource
            .get_mut(resource.index())
            .ok_or_else(|| format!("unknown compiler resource {}", resource.index()))?;
        *slot = Some(GraphAllocationRange {
            allocation_id,
            byte_offset: buffer.byte_offset,
            byte_size: buffer.byte_size as u64,
        });
        Ok(())
    }

    pub fn validate_pass_bindings(
        &self,
        graph: &CompilerGraph,
        pass: PassId,
        bindings: &[BoundGraphResource],
    ) -> Result<(), String> {
        graph.validate_pass_bindings(pass, bindings)?;
        let desc = graph
            .pass(pass)
            .ok_or_else(|| format!("unknown compiler pass {}", pass.index()))?;
        for access in &desc.accesses {
            let resource = graph
                .resource(access.resource)
                .ok_or_else(|| format!("unknown compiler resource {}", access.resource.index()))?;
            if matches!(
                resource.class,
                ResourceClass::Input | ResourceClass::External
            ) {
                continue;
            }
            let expected = self
                .allocation_by_resource
                .get(access.resource.index())
                .copied()
                .flatten()
                .ok_or_else(|| {
                    format!(
                        "compiler resource {} has no owned allocation",
                        resource.name
                    )
                })?;
            let bound = bindings
                .iter()
                .find(|bound| bound.binding == access.binding && bound.resource == access.resource)
                .expect("logical binding validation ran first");
            if bound.allocation_id != expected.allocation_id {
                return Err(format!(
                    "compiler pass {} binds graph-owned {} to allocation {} instead of {}",
                    desc.name, resource.name, bound.allocation_id, expected.allocation_id,
                ));
            }
            let bound_end = bound
                .byte_offset
                .checked_add(bound.byte_size)
                .ok_or_else(|| {
                    format!(
                        "compiler pass {} binding {} has an overflowing byte range",
                        desc.name, access.binding,
                    )
                })?;
            let expected_end = expected
                .byte_offset
                .checked_add(expected.byte_size)
                .expect("owned compiler allocation range overflow");
            if bound.byte_offset < expected.byte_offset || bound_end > expected_end {
                return Err(format!(
                    "compiler pass {} binds graph-owned {} to byte range {}..{} outside its owned range {}..{} in allocation {}",
                    desc.name,
                    resource.name,
                    bound.byte_offset,
                    bound_end,
                    expected.byte_offset,
                    expected_end,
                    expected.allocation_id,
                ));
            }
        }
        Ok(())
    }
}

impl CompilerGraph {
    #[cfg(test)]
    pub(crate) fn pass_kernel(&self, pass: PassId) -> Option<&'static str> {
        self.pass_kernels.get(pass.index()).copied().flatten()
    }

    pub fn resources(&self) -> &[ResourceDesc] {
        &self.resources
    }

    pub(crate) fn resource_aliases(&self) -> impl Iterator<Item = (&'static str, ResourceId)> + '_ {
        self.resource_aliases
            .iter()
            .map(|(name, resource)| (*name, *resource))
    }

    pub fn passes(&self) -> &[PassDesc] {
        &self.passes
    }

    fn diagnostic(&self, label: &str) -> CompilerGraphDiagnostic {
        let nodes = self
            .passes
            .iter()
            .enumerate()
            .map(|(id, pass)| CompilerGraphDiagnosticNode {
                id,
                name: pass.name,
                phase: pass.phase.diagnostic_name(),
                dispatch_domain: pass.dispatch_domain.diagnostic_name(),
            })
            .collect();

        // Preserve every resource hazard required by the declared pass order.
        // Read-after-write edges carry produced data; write-after-read and
        // write-after-write edges carry storage ordering. Unlike the GPU trace,
        // these edges do not imply that otherwise independent passes depend on
        // one another merely because one happened to be recorded first.
        let mut last_writer = vec![None; self.resources.len()];
        let mut readers = vec![BTreeSet::<usize>::new(); self.resources.len()];
        let mut dependencies =
            BTreeMap::<(usize, usize), BTreeSet<(&'static str, &'static str)>>::new();
        let mut add_dependency =
            |source: usize, target: usize, resource: &'static str, hazard: &'static str| {
                if source != target {
                    dependencies
                        .entry((source, target))
                        .or_default()
                        .insert((resource, hazard));
                }
            };
        for (target, pass) in self.passes.iter().enumerate() {
            for access in &pass.accesses {
                let resource_index = access.resource.index();
                let resource_name = self.resources[resource_index].name;
                let reads_previous = access.mode.reads() && !access.initializes_before_read;
                if reads_previous && let Some(source) = last_writer[resource_index] {
                    add_dependency(source, target, resource_name, "read_after_write");
                }
                if access.mode.writes() {
                    if let Some(source) = last_writer[resource_index] {
                        add_dependency(source, target, resource_name, "write_after_write");
                    }
                    for &source in &readers[resource_index] {
                        add_dependency(source, target, resource_name, "write_after_read");
                    }
                    readers[resource_index].clear();
                    last_writer[resource_index] = Some(target);
                } else if reads_previous {
                    readers[resource_index].insert(target);
                }
            }
        }
        let edges = dependencies
            .into_iter()
            .map(|((source, target), rows)| CompilerGraphDiagnosticEdge {
                source,
                target,
                dependencies: rows
                    .into_iter()
                    .map(|(resource, hazard)| CompilerGraphDiagnosticDependency {
                        resource,
                        hazard,
                    })
                    .collect(),
            })
            .collect();
        CompilerGraphDiagnostic {
            label: label.to_owned(),
            nodes,
            edges,
        }
    }

    pub fn repeated_regions(&self) -> &[RepeatedPassRegion] {
        &self.repeated_regions
    }

    pub fn paged_regions(&self) -> &[PagedPassRegion] {
        &self.paged_regions
    }

    pub fn lifetime_fences(&self) -> &[ResourceLifetimeFence] {
        &self.lifetime_fences
    }

    pub fn lifetime(&self, resource: ResourceId) -> Option<ResourceLifetime> {
        self.lifetimes.get(resource.index()).copied().flatten()
    }

    pub fn workspace_plan(&self) -> &WorkspacePlan {
        &self.workspace
    }

    /// Projects the graph's lifetime-colored slots onto the physical arena ABI
    /// supported by a particular device. Materialization is intentionally a
    /// separate step so allocation consolidation can be inspected before any
    /// shader interface is migrated.
    pub fn workspace_arena_layout(
        &self,
        limits: &wgpu::Limits,
    ) -> Result<WorkspaceArenaLayout, String> {
        plan_workspace_arenas_with_conflicts(
            &self.workspace,
            WorkspaceArenaLimits::from_device_limits(limits)?,
            &self.workspace_arena_conflicts(),
        )
    }

    fn workspace_arena_conflicts(&self) -> BTreeSet<(u32, u32)> {
        let all_slots = self
            .workspace
            .slots
            .iter()
            .map(|slot| slot.slot)
            .collect::<Vec<_>>();
        if std::env::var_os("LANIUS_COMPILER_GRAPH_DISABLE_COLORING").is_some() {
            return all_slots
                .iter()
                .enumerate()
                .flat_map(|(index, &left)| {
                    all_slots[index + 1..]
                        .iter()
                        .map(move |&right| (left.min(right), left.max(right)))
                })
                .collect();
        }
        let slot_by_resource = self
            .workspace
            .assignments
            .iter()
            .filter_map(|assignment| {
                self.resource_id(assignment.name)
                    .map(|resource| (resource, assignment.slot))
            })
            .collect::<BTreeMap<_, _>>();
        let mut conflicts = BTreeSet::new();
        for pass in &self.passes {
            let slots = pass
                .accesses
                .iter()
                .filter_map(|access| slot_by_resource.get(&access.resource).copied())
                .collect::<BTreeSet<_>>()
                .into_iter()
                .collect::<Vec<_>>();
            for (index, &left) in slots.iter().enumerate() {
                for &right in &slots[index + 1..] {
                    conflicts.insert((left, right));
                }
            }
        }
        for &(left_resource, right_resource) in &self.reflected_arena_conflicts {
            let (Some(&left), Some(&right)) = (
                slot_by_resource.get(&left_resource),
                slot_by_resource.get(&right_resource),
            ) else {
                continue;
            };
            if left != right {
                conflicts.insert((left.min(right), left.max(right)));
            }
        }
        // A range retained across the phase boundary keeps its complete
        // physical allocation alive. Mixing one such range with phase-local
        // scratch would therefore make the scratch allocation unavailable to
        // the next compiler graph even though its logical lifetime ended.
        // Keep retained outputs in output-only arenas. Multiple outputs may
        // still share one arena through disjoint ranges when no pass binds
        // them together.
        let output_slots = self
            .workspace
            .assignments
            .iter()
            .filter_map(|assignment| {
                let resource = self.resource_id(assignment.name)?;
                (self.resource(resource)?.class == ResourceClass::Output).then_some(assignment.slot)
            })
            .collect::<BTreeSet<_>>();
        for &output in &output_slots {
            for &other in &all_slots {
                if output != other && !output_slots.contains(&other) {
                    conflicts.insert((output.min(other), output.max(other)));
                }
            }
        }
        // WGPU's indirect-dispatch API receives a raw buffer plus one offset,
        // so keep those slots at offset zero in exclusive physical arenas.
        // Retained outputs are different: every compiler phase boundary now
        // carries `LaniusBuffer`/`TrackedBufferView`, including copies and
        // readbacks, so outputs may occupy disjoint ranges of one arena while
        // retaining distinct logical slots and allocation identity.
        let dedicated_slots = self
            .workspace
            .assignments
            .iter()
            .filter_map(|assignment| {
                if self.workspace.slots.iter().any(|slot| {
                    slot.slot == assignment.slot
                        && slot.usage == WorkspaceUsageClass::StorageIndirect
                }) {
                    return Some(assignment.slot);
                }
                None
            })
            .collect::<BTreeSet<_>>();
        for dedicated in dedicated_slots {
            for &other in &all_slots {
                if dedicated != other {
                    conflicts.insert((dedicated.min(other), dedicated.max(other)));
                }
            }
        }
        conflicts
    }

    pub fn paged_resource(&self, resource: ResourceId) -> Option<PagedResourceDesc> {
        self.paged_resources
            .get(resource.index())
            .copied()
            .flatten()
    }

    /// Total physical bytes required by the phase-colored workspace. Logical
    /// resource bytes are deliberately not summed because mutually dead
    /// resources alias the same slot.
    pub fn workspace_bytes(&self) -> u64 {
        self.workspace.slots.iter().map(|slot| slot.bytes).sum()
    }

    pub fn resource(&self, resource: ResourceId) -> Option<&ResourceDesc> {
        self.resources.get(resource.index())
    }

    pub fn pass(&self, pass: PassId) -> Option<&PassDesc> {
        self.passes.get(pass.index())
    }

    pub fn resource_id(&self, name: &str) -> Option<ResourceId> {
        self.resources
            .iter()
            .position(|resource| resource.name == name)
            .map(ResourceId)
            .or_else(|| self.resource_aliases.get(name).copied())
    }

    pub fn pass_id(&self, name: &str) -> Option<PassId> {
        self.passes
            .iter()
            .position(|pass| pass.name == name)
            .map(PassId)
    }

    /// Binds a caller-owned raw WGPU buffer as an immutable graph input.
    ///
    /// Some public compiler entry points receive `wgpu::Buffer` rather than a
    /// `LaniusBuffer`, so no allocation-ledger identity exists to preserve.
    /// Such buffers may only satisfy `Input` resources: the graph still checks
    /// their extent and read-only lifetime, while graph-owned writable storage
    /// continues to require a tracked allocation identity.
    pub fn bind_external_input(
        &self,
        binding: &'static str,
        resource: ResourceId,
        buffer: &wgpu::Buffer,
    ) -> Result<BoundGraphResource, String> {
        let desc = self
            .resource(resource)
            .ok_or_else(|| format!("unknown compiler resource {}", resource.index()))?;
        if desc.class != ResourceClass::Input {
            return Err(format!(
                "graph binding {binding} cannot use an untracked external buffer for writable resource {}",
                desc.name,
            ));
        }
        Ok(BoundGraphResource::whole(
            binding,
            resource,
            0,
            buffer.size(),
        ))
    }

    /// Binds a tracked caller-owned allocation to a mutable `External`
    /// resource. Unlike raw immutable inputs, external writable resources must
    /// preserve Lanius allocation identity so alias validation remains sound.
    pub fn bind_external_resource<T>(
        &self,
        binding: &'static str,
        resource: ResourceId,
        buffer: &LaniusBuffer<T>,
    ) -> Result<BoundGraphResource, String> {
        let desc = self
            .resource(resource)
            .ok_or_else(|| format!("unknown compiler resource {}", resource.index()))?;
        if desc.class != ResourceClass::External {
            return Err(format!(
                "graph binding {binding} expects an External resource, but {} is {:?}",
                desc.name, desc.class,
            ));
        }
        BoundGraphResource::buffer(binding, resource, buffer)
    }

    /// Converts allocation metadata retained by a reflected resource registry
    /// into a concrete graph binding. Immutable raw inputs may lack a Lanius
    /// allocation identity; every writable or graph-owned resource must keep
    /// one so overlap and workspace-ownership checks remain sound.
    pub fn bind_registered_resource(
        &self,
        binding: &'static str,
        resource: ResourceId,
        allocation_id: Option<u64>,
        byte_offset: u64,
        byte_size: u64,
    ) -> Result<BoundGraphResource, String> {
        let desc = self
            .resource(resource)
            .ok_or_else(|| format!("unknown compiler resource {}", resource.index()))?;
        let allocation_id = match (desc.class, allocation_id) {
            (ResourceClass::Input, allocation_id) => allocation_id.unwrap_or(0),
            (_, Some(allocation_id)) => allocation_id,
            (_, None) => {
                return Err(format!(
                    "graph binding {binding} for {:?} resource {} has no tracked Lanius allocation identity",
                    desc.class, desc.name,
                ));
            }
        };
        Ok(BoundGraphResource::window(
            binding,
            resource,
            allocation_id,
            byte_offset,
            byte_size,
            0,
            byte_size,
        ))
    }

    /// Validates the concrete allocation ranges used to record one pass.
    /// Every declared graph access must have exactly one matching binding;
    /// extra bindings remain permitted for uniforms and non-resource state.
    pub fn validate_pass_bindings(
        &self,
        pass: PassId,
        bindings: &[BoundGraphResource],
    ) -> Result<(), String> {
        let desc = self
            .passes
            .get(pass.index())
            .ok_or_else(|| format!("unknown compiler pass {}", pass.index()))?;

        for access in &desc.accesses {
            let matches = bindings
                .iter()
                .filter(|bound| {
                    bound.binding == access.binding && bound.resource == access.resource
                })
                .collect::<Vec<_>>();
            if matches.len() != 1 {
                return Err(format!(
                    "compiler pass {} requires exactly one binding for {} ({}) but found {}",
                    desc.name,
                    self.resources[access.resource.index()].name,
                    access.binding,
                    matches.len(),
                ));
            }
            let bound = matches[0];
            let resource = self.resources[access.resource.index()];
            let paged = self.paged_resources[access.resource.index()];
            // Input and External resources describe the maximum logical job
            // capacity. Their concrete job slice may be smaller and is guarded
            // by active-count buffers. Graph-owned storage must cover its full
            // declared range because the graph controls that allocation.
            let required = paged.map_or_else(
                || {
                    if matches!(
                        resource.class,
                        ResourceClass::Input | ResourceClass::External
                    ) {
                        1
                    } else {
                        resource.bytes
                    }
                },
                |stream| stream.page_bytes,
            );
            if bound.byte_size < required {
                return Err(format!(
                    "compiler pass {} binds {} with {} bytes but {} are required",
                    desc.name, access.binding, bound.byte_size, required,
                ));
            }
            if let Some(stream) = paged {
                let logical_end = bound
                    .logical_offset
                    .checked_add(bound.logical_size)
                    .ok_or_else(|| {
                        format!(
                            "compiler pass {} binding {} has an overflowing logical range",
                            desc.name, access.binding,
                        )
                    })?;
                if bound.logical_size > stream.page_bytes || logical_end > stream.logical_bytes {
                    return Err(format!(
                        "compiler pass {} binds {} logical range {}..{} outside its {}-byte stream or {}-byte page",
                        desc.name,
                        access.binding,
                        bound.logical_offset,
                        logical_end,
                        stream.logical_bytes,
                        stream.page_bytes,
                    ));
                }
                let resident_bytes = stream
                    .page_bytes
                    .checked_mul(u64::from(stream.resident_pages))
                    .expect("paged resource size validated by the builder");
                let physical_end =
                    bound
                        .byte_offset
                        .checked_add(bound.byte_size)
                        .ok_or_else(|| {
                            format!(
                                "compiler pass {} binding {} has an overflowing byte range",
                                desc.name, access.binding,
                            )
                        })?;
                if bound.byte_offset % stream.page_bytes != 0 || physical_end > resident_bytes {
                    return Err(format!(
                        "compiler pass {} binds {} to a non-page-aligned resident range",
                        desc.name, access.binding,
                    ));
                }
            } else if bound.logical_offset != 0 || bound.logical_size != bound.byte_size {
                return Err(format!(
                    "compiler pass {} gives resident binding {} a logical stream window",
                    desc.name, access.binding,
                ));
            }
            bound
                .byte_offset
                .checked_add(bound.byte_size)
                .ok_or_else(|| {
                    format!(
                        "compiler pass {} binding {} has an overflowing byte range",
                        desc.name, access.binding,
                    )
                })?;
        }

        for (left_index, left_access) in desc.accesses.iter().enumerate() {
            let left = bindings
                .iter()
                .find(|bound| {
                    bound.binding == left_access.binding && bound.resource == left_access.resource
                })
                .expect("declared binding presence checked above");
            for right_access in &desc.accesses[left_index + 1..] {
                if !left_access.mode.writes() && !right_access.mode.writes() {
                    continue;
                }
                let right = bindings
                    .iter()
                    .find(|bound| {
                        bound.binding == right_access.binding
                            && bound.resource == right_access.resource
                    })
                    .expect("declared binding presence checked above");
                if left.allocation_id != right.allocation_id {
                    continue;
                }
                let left_end = left.byte_offset + left.byte_size;
                let right_end = right.byte_offset + right.byte_size;
                if left.byte_offset < right_end && right.byte_offset < left_end {
                    return Err(format!(
                        "compiler pass {} binds overlapping writable aliases {} and {} to allocation {}",
                        desc.name, left_access.binding, right_access.binding, left.allocation_id,
                    ));
                }
            }
        }
        Ok(())
    }

    /// Checks graph-declared binding access against Slang's reflected shader
    /// interface. Uniforms and bindings not backed by logical graph resources
    /// remain outside this semantic ownership check.
    pub fn validate_pass_reflection(
        &self,
        pass: PassId,
        reflection: &SlangReflection,
    ) -> Result<(), String> {
        let desc = self
            .passes
            .get(pass.index())
            .ok_or_else(|| format!("unknown compiler pass {}", pass.index()))?;
        let parameters = reflected_parameters(reflection);
        for access in &desc.accesses {
            if !access.reflected {
                continue;
            }
            let parameter = parameters
                .iter()
                .copied()
                .find(|parameter| parameter.name == access.binding)
                .ok_or_else(|| {
                    format!(
                        "compiler pass {} declares binding {} but Slang reflection does not",
                        desc.name, access.binding,
                    )
                })?;
            let reflected_writable = parameter
                .ty
                .access
                .as_deref()
                .is_some_and(|access| access.eq_ignore_ascii_case("readWrite"));
            if access.mode.writes() && !reflected_writable {
                return Err(format!(
                    "compiler pass {} writes binding {} but Slang reflects it as read-only",
                    desc.name, access.binding,
                ));
            }
            if access.mode == AccessMode::Read && reflected_writable {
                return Err(format!(
                    "compiler pass {} declares binding {} read-only but the shader may write it",
                    desc.name, access.binding,
                ));
            }
        }
        Ok(())
    }

    /// Proves that a graph pass describes the shader's complete reflected
    /// storage-buffer surface. Uniforms remain outside buffer ownership, but
    /// every read-only or writable storage binding must have exactly one graph
    /// access. Use this gate before declaring a resource lifetime complete and
    /// eligible for workspace coloring.
    pub fn validate_complete_pass_reflection(
        &self,
        pass: PassId,
        reflection: &SlangReflection,
    ) -> Result<(), String> {
        self.validate_pass_reflection(pass, reflection)?;
        let desc = self
            .passes
            .get(pass.index())
            .ok_or_else(|| format!("unknown compiler pass {}", pass.index()))?;
        let invocations = desc
            .accesses
            .iter()
            .filter(|access| access.reflected)
            .map(|access| access.invocation)
            .collect::<BTreeSet<_>>();
        for invocation in invocations {
            for parameter in reflected_parameters(reflection) {
                let Some(binding_type) = slang_category_and_type_to_wgpu(parameter, &parameter.ty)
                else {
                    continue;
                };
                if !matches!(
                    binding_type,
                    wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { .. },
                        ..
                    }
                ) {
                    continue;
                }
                let count = desc
                    .accesses
                    .iter()
                    .filter(|access| {
                        access.reflected
                            && access.invocation == invocation
                            && access.binding == parameter.name
                    })
                    .count();
                if count != 1 {
                    return Err(format!(
                        "compiler pass {} invocation {invocation} must describe reflected storage binding {} exactly once, found {count}",
                        desc.name, parameter.name,
                    ));
                }
            }
        }
        Ok(())
    }

    /// Validates every pass that carries a generated-kernel identity.
    ///
    /// Phase constructors assign the kernel once when registering a pass;
    /// callers therefore do not need a second hand-maintained list pairing
    /// pass names with the same reflections.
    pub(crate) fn validate_assigned_pass_reflections(
        &self,
        kernels: &impl KernelReflections,
    ) -> Result<(), String> {
        for (index, kernel) in self.pass_kernels.iter().enumerate() {
            if !self.reflection_complete[index] {
                continue;
            }
            let Some(kernel) = kernel else { continue };
            self.validate_complete_pass_reflection(PassId(index), kernels.reflection(kernel)?)?;
        }
        Ok(())
    }
}

fn compiler_graph_diagnostics_enabled() -> bool {
    static ENABLED: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ENABLED
        .get_or_init(|| crate::gpu::env::env_bool_strict("LANIUS_COMPILER_GRAPH_BREAKDOWN", false))
}

static COMPILER_GRAPH_DIAGNOSTICS: std::sync::OnceLock<
    std::sync::Mutex<BTreeMap<String, CompilerGraphDiagnostic>>,
> = std::sync::OnceLock::new();

fn register_compiler_graph_diagnostic(label: &str, graph: &CompilerGraph) {
    if !compiler_graph_diagnostics_enabled() {
        return;
    }
    COMPILER_GRAPH_DIAGNOSTICS
        .get_or_init(Default::default)
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .insert(label.to_owned(), graph.diagnostic(label));
}

pub(crate) fn compiler_graph_diagnostics() -> Vec<CompilerGraphDiagnostic> {
    if !compiler_graph_diagnostics_enabled() {
        return Vec::new();
    }
    COMPILER_GRAPH_DIAGNOSTICS
        .get_or_init(Default::default)
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner)
        .values()
        .cloned()
        .collect()
}

fn reflected_parameters(reflection: &SlangReflection) -> Vec<&ParameterReflection> {
    reflection
        .entry_points
        .iter()
        .find(|entry| entry.stage.as_deref() == Some("compute"))
        .and_then(|entry| entry.program_layout.as_ref())
        .map(|layout| {
            layout
                .parameters
                .iter()
                .flat_map(|set| set.parameters.iter())
                .collect()
        })
        .unwrap_or_else(|| reflection.parameters.iter().collect())
}

/// A cohesive compiler operation which contributes logical resources and
/// passes to a graph.
///
/// Fragments are the graph-level counterpart of high-level parallel array
/// operations: callers provide typed boundary resources, while the fragment
/// keeps its internal scans, sorts, and dispatch sequence private.  This
/// prevents phase drivers from duplicating a shader family as resource lists,
/// pass lists, bind-group lists, and recording lists.
pub trait CompilerGraphFragment {
    type Output;

    fn add_to(self, graph: &mut CompilerGraphBuilder) -> Result<Self::Output, String>;
}

/// Stable names for one digit step of a radix sort.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RadixSortGraphStepPasses {
    pub histogram: &'static str,
    pub bucket_prefix: &'static str,
    pub bucket_bases: &'static str,
    pub scatter: &'static str,
}

/// Stable names for the logical stages of one radix sort.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RadixSortGraphPasses {
    pub order_to_temporary: RadixSortGraphStepPasses,
    pub temporary_to_order: RadixSortGraphStepPasses,
}

impl RadixSortGraphPasses {
    pub fn names(self) -> [&'static str; 8] {
        [
            self.order_to_temporary.histogram,
            self.order_to_temporary.bucket_prefix,
            self.order_to_temporary.bucket_bases,
            self.order_to_temporary.scatter,
            self.temporary_to_order.histogram,
            self.temporary_to_order.bucket_prefix,
            self.temporary_to_order.bucket_bases,
            self.temporary_to_order.scatter,
        ]
    }
}

/// Logical arrays used by one radix sort.
///
/// `keys` contains the arrays read by the compiled key projection. The graph
/// owns the lifetime of all temporary arrays; callers do not declare access
/// modes or reproduce the implementation's pass sequence.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RadixSortGraphResources {
    pub count: ResourceId,
    pub count_binding: &'static str,
    pub keys: Vec<ReflectedResourceBinding>,
    pub order: ResourceId,
    pub temporary_order: ResourceId,
    pub dispatch_args: ResourceId,
    pub histogram: ResourceId,
    pub bucket_prefix: ResourceId,
    pub bucket_total: ResourceId,
    pub bucket_base: ResourceId,
}

/// Stable graph names for storage internal to a radix sort.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct RadixSortGraphResourceNames {
    pub order: &'static str,
    pub temporary_order: &'static str,
    pub dispatch_args: &'static str,
    pub histogram: &'static str,
    pub bucket_prefix: &'static str,
    pub bucket_total: &'static str,
    pub bucket_base: &'static str,
}

/// A stable least-significant-digit radix sort in the compiler graph.
///
/// The semantic inputs are the row count, key projection inputs, number of
/// digit steps, and order relation. Histogram, scan, scatter, ping-pong, and
/// access metadata are implementation details expanded by this fragment.
pub struct RadixSortGraph {
    pub phase: CompilerPhase,
    pub dispatch_domain: ResourceDomain,
    pub digit_steps: u32,
    /// Odd schedules initialize `temporary_order` in their first histogram and
    /// begin with the temporary-to-order direction, avoiding a final copy.
    pub starts_in_temporary: bool,
    pub schedule: RadixSortGraphPasses,
    pub resources: RadixSortGraphResources,
}

fn validate_radix_sort_resources(
    graph: &CompilerGraphBuilder,
    label: &str,
    resources: &RadixSortGraphResources,
) -> Result<(), String> {
    let mut distinct = BTreeSet::new();
    for resource in [
        resources.count,
        resources.order,
        resources.temporary_order,
        resources.dispatch_args,
        resources.histogram,
        resources.bucket_prefix,
        resources.bucket_total,
        resources.bucket_base,
    ]
    .into_iter()
    .chain(resources.keys.iter().map(|key| key.resource))
    {
        let Some(desc) = graph.resources.get(resource.index()) else {
            return Err(format!(
                "radix sort {label} references unknown resource {}",
                resource.index(),
            ));
        };
        if !distinct.insert(resource) {
            return Err(format!(
                "radix sort {label} uses resource {} for two simultaneous roles",
                desc.name,
            ));
        }
    }
    Ok(())
}

fn radix_sort_step_passes(
    graph: &CompilerGraphBuilder,
    phase: CompilerPhase,
    dispatch_domain: ResourceDomain,
    passes: RadixSortGraphStepPasses,
    resources: &RadixSortGraphResources,
    input: ResourceId,
    output: ResourceId,
) -> Vec<PassDesc> {
    let r = resources;
    let name = |resource: ResourceId| graph.resources[resource.index()].name;
    let key_reads = || {
        r.keys
            .iter()
            .map(|key| PassAccess::read(key.binding, key.resource))
            .collect::<Vec<_>>()
    };
    let mut histogram_accesses = key_reads();
    histogram_accesses.extend([
        PassAccess::read(r.count_binding, r.count),
        PassAccess::initialize_read_write("radix_order_in", input),
        PassAccess::indirect(name(r.dispatch_args), r.dispatch_args),
        PassAccess::write("radix_block_histogram", r.histogram),
    ]);
    let mut scatter_accesses = key_reads();
    scatter_accesses.extend([
        PassAccess::read(r.count_binding, r.count),
        PassAccess::read("radix_order_in", input),
        PassAccess::indirect(name(r.dispatch_args), r.dispatch_args),
        PassAccess::read("radix_block_bucket_prefix", r.bucket_prefix),
        PassAccess::read("radix_bucket_base", r.bucket_base),
        PassAccess::write("radix_order_out", output),
    ]);
    vec![
        PassDesc {
            name: passes.histogram,
            phase,
            dispatch_domain,
            accesses: histogram_accesses,
        },
        PassDesc {
            name: passes.bucket_prefix,
            phase,
            dispatch_domain,
            accesses: vec![
                PassAccess::read("name_count_in", r.count),
                PassAccess::read("radix_block_histogram", r.histogram),
                PassAccess::write("radix_block_bucket_prefix", r.bucket_prefix),
                PassAccess::write("radix_bucket_total", r.bucket_total),
            ],
        },
        PassDesc {
            name: passes.bucket_bases,
            phase,
            dispatch_domain,
            accesses: vec![
                PassAccess::read("radix_bucket_total", r.bucket_total),
                PassAccess::write("radix_bucket_base", r.bucket_base),
            ],
        },
        PassDesc {
            name: passes.scatter,
            phase,
            dispatch_domain,
            accesses: scatter_accesses,
        },
    ]
}

impl CompilerGraphFragment for RadixSortGraph {
    type Output = ResourceId;

    fn add_to(self, graph: &mut CompilerGraphBuilder) -> Result<Self::Output, String> {
        let label = self.schedule.order_to_temporary.histogram;
        if self.digit_steps == 0 {
            return Err(format!(
                "radix sort {} requires a positive digit-step count, got {}",
                label, self.digit_steps,
            ));
        }
        let r = &self.resources;
        validate_radix_sort_resources(graph, label, r)?;
        let order_to_temporary = || {
            radix_sort_step_passes(
                graph,
                self.phase,
                self.dispatch_domain,
                self.schedule.order_to_temporary,
                r,
                r.order,
                r.temporary_order,
            )
        };
        let temporary_to_order = || {
            radix_sort_step_passes(
                graph,
                self.phase,
                self.dispatch_domain,
                self.schedule.temporary_to_order,
                r,
                r.temporary_order,
                r.order,
            )
        };
        let mut body = if self.starts_in_temporary {
            temporary_to_order()
        } else {
            order_to_temporary()
        };
        body.extend(if self.starts_in_temporary {
            order_to_temporary()
        } else {
            temporary_to_order()
        });
        // An odd schedule executes only the first half of its final modeled
        // pair. Modeling the complete pair conservatively extends scratch
        // liveness without inventing a runtime copy pass.
        graph.add_repeated_region(self.digit_steps.div_ceil(2), body)?;
        Ok(r.order)
    }
}

/// Two independent stable radix sorts whose stages are recorded together.
///
/// Read-only domains may be shared. Ordering and workspace arrays must be
/// distinct because both histograms are produced before either prefix pass.
pub struct RadixSortPairGraph {
    pub phase: CompilerPhase,
    pub dispatch_domain: ResourceDomain,
    pub digit_steps: u32,
    pub left_passes: RadixSortGraphPasses,
    pub right_passes: RadixSortGraphPasses,
    pub left: RadixSortGraphResources,
    pub right: RadixSortGraphResources,
}

impl CompilerGraphFragment for RadixSortPairGraph {
    type Output = (ResourceId, ResourceId);

    fn add_to(self, graph: &mut CompilerGraphBuilder) -> Result<Self::Output, String> {
        if self.digit_steps == 0 {
            return Err(format!(
                "paired radix sorts require a positive digit-step count, got {}",
                self.digit_steps,
            ));
        }
        validate_radix_sort_resources(
            graph,
            self.left_passes.order_to_temporary.histogram,
            &self.left,
        )?;
        validate_radix_sort_resources(
            graph,
            self.right_passes.order_to_temporary.histogram,
            &self.right,
        )?;
        let left_mutable = [
            self.left.order,
            self.left.temporary_order,
            self.left.histogram,
            self.left.bucket_prefix,
            self.left.bucket_total,
            self.left.bucket_base,
        ];
        let right_mutable = [
            self.right.order,
            self.right.temporary_order,
            self.right.histogram,
            self.right.bucket_prefix,
            self.right.bucket_total,
            self.right.bucket_base,
        ];
        if let Some(resource) = left_mutable
            .into_iter()
            .find(|resource| right_mutable.contains(resource))
        {
            return Err(format!(
                "paired radix sorts share mutable resource {}",
                graph.resources[resource.index()].name,
            ));
        }

        let interleave = |left: Vec<PassDesc>, right: Vec<PassDesc>| {
            left.into_iter()
                .zip(right)
                .flat_map(|(left, right)| [left, right])
                .collect::<Vec<_>>()
        };
        let mut body = interleave(
            radix_sort_step_passes(
                graph,
                self.phase,
                self.dispatch_domain,
                self.left_passes.order_to_temporary,
                &self.left,
                self.left.order,
                self.left.temporary_order,
            ),
            radix_sort_step_passes(
                graph,
                self.phase,
                self.dispatch_domain,
                self.right_passes.order_to_temporary,
                &self.right,
                self.right.order,
                self.right.temporary_order,
            ),
        );
        body.extend(interleave(
            radix_sort_step_passes(
                graph,
                self.phase,
                self.dispatch_domain,
                self.left_passes.temporary_to_order,
                &self.left,
                self.left.temporary_order,
                self.left.order,
            ),
            radix_sort_step_passes(
                graph,
                self.phase,
                self.dispatch_domain,
                self.right_passes.temporary_to_order,
                &self.right,
                self.right.temporary_order,
                self.right.order,
            ),
        ));
        graph.add_repeated_region(self.digit_steps.div_ceil(2), body)?;
        Ok((self.left.order, self.right.order))
    }
}

/// Stable pass names for one counted exclusive prefix scan.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PrefixScanGraphPasses {
    pub local: &'static str,
    pub hierarchy_up_first: &'static str,
    pub hierarchy_up_rest: &'static str,
    pub hierarchy_down: &'static str,
    pub apply: &'static str,
}

impl PrefixScanGraphPasses {
    pub fn names(self) -> [&'static str; 5] {
        [
            self.local,
            self.hierarchy_up_first,
            self.hierarchy_up_rest,
            self.hierarchy_down,
            self.apply,
        ]
    }
}

/// Resources used by one counted exclusive prefix scan.
///
/// The graph instantiates this with [`ResourceId`]; the runtime instantiates
/// the same shape with GPU buffer references. Keeping one resource schema
/// prevents execution and ownership declarations from drifting apart.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PrefixScanResources<T> {
    pub count: T,
    pub input: T,
    pub output_prefix: T,
    pub total: T,
    pub dispatch_args: T,
    pub local_prefix: T,
    pub block_sum: T,
    pub block_prefix: T,
    pub hierarchy: T,
}

/// Reusable phase-local storage required by a prefix scan.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PrefixScanWorkspace<T> {
    pub local_prefix: T,
    pub block_sum: T,
    pub block_prefix: T,
    pub hierarchy: T,
}

impl<T> PrefixScanWorkspace<T> {
    pub fn as_ref(&self) -> PrefixScanWorkspace<&T> {
        PrefixScanWorkspace {
            local_prefix: &self.local_prefix,
            block_sum: &self.block_sum,
            block_prefix: &self.block_prefix,
            hierarchy: &self.hierarchy,
        }
    }
}

impl<T: Copy> PrefixScanResources<T> {
    pub fn workspace(self) -> PrefixScanWorkspace<T> {
        PrefixScanWorkspace {
            local_prefix: self.local_prefix,
            block_sum: self.block_sum,
            block_prefix: self.block_prefix,
            hierarchy: self.hierarchy,
        }
    }
}

pub type PrefixScanGraphResources = PrefixScanResources<ResourceId>;

fn assign_prefix_scan_kernels(
    graph: &mut CompilerGraphBuilder,
    passes: PrefixScanGraphPasses,
) -> Result<(), String> {
    graph.assign_kernel(passes.local, "scan/counted/00_local")?;
    graph.assign_kernel(passes.hierarchy_up_first, "scan/counted/01_hierarchy_up")?;
    if graph.pass_names.contains(passes.hierarchy_up_rest) {
        graph.assign_kernel(passes.hierarchy_up_rest, "scan/counted/01_hierarchy_up")?;
    }
    if graph.pass_names.contains(passes.hierarchy_down) {
        graph.assign_kernel(passes.hierarchy_down, "scan/counted/02_hierarchy_down")?;
    }
    graph.assign_kernel(passes.apply, "scan/counted/02_apply")?;
    for pass in passes.names() {
        if graph.pass_names.contains(pass) {
            graph.require_complete_reflection(pass)?;
        }
    }
    Ok(())
}

/// Stable graph names for storage internal to a counted prefix scan.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PrefixScanGraphResourceNames {
    pub output_prefix: &'static str,
    pub total: &'static str,
    pub local_prefix: &'static str,
    pub block_sum: &'static str,
    pub block_prefix: &'static str,
    pub hierarchy: &'static str,
}

impl PrefixScanGraphResourceNames {
    pub fn workspace(self) -> PrefixScanWorkspace<&'static str> {
        PrefixScanWorkspace {
            local_prefix: self.local_prefix,
            block_sum: self.block_sum,
            block_prefix: self.block_prefix,
            hierarchy: self.hierarchy,
        }
    }
}

/// A GPU counted exclusive prefix scan.
///
/// Callers provide the count, input relation, and dispatch domain. The
/// operation owns output, hierarchy, and temporary storage and derives every
/// pass access.
/// The first hierarchy level initializes the loop-carried buffers; later up
/// and down levels explicitly read and write that state.
pub struct PrefixScanGraph {
    pub phase: CompilerPhase,
    pub dispatch_domain: ResourceDomain,
    pub hierarchy_levels: u32,
    pub passes: PrefixScanGraphPasses,
    pub resources: PrefixScanGraphResources,
}

/// One named prefix scan shared by graph construction and runtime binding.
///
/// The specification is the semantic operation; hierarchy depth and concrete
/// buffers are capacity-dependent materialization details.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PrefixScanSpec {
    pub phase: CompilerPhase,
    pub dispatch_domain: ResourceDomain,
    pub passes: PrefixScanGraphPasses,
    pub resources: PrefixScanResources<&'static str>,
}

impl PrefixScanSpec {
    pub(crate) fn register(
        self,
        graph: &mut CompilerGraphBuilder,
        hierarchy_levels: u32,
    ) -> Result<(ResourceId, ResourceId), String> {
        let resources = graph.resolve_prefix_scan_resources(self.resources)?;
        graph.add_fragment(PrefixScanGraph {
            phase: self.phase,
            dispatch_domain: self.dispatch_domain,
            hierarchy_levels,
            passes: self.passes,
            resources,
        })
    }
}

/// A stable compaction expressed as flag production, exclusive prefix scan,
/// and dense scatter. This is one semantic operation even though it lowers to
/// several compute passes.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct CompactionSpec {
    pub mark: ReflectedComputeSpec,
    pub scan: PrefixScanSpec,
    pub scatter: ReflectedComputeSpec,
}

impl CompactionSpec {
    pub(crate) fn register(
        self,
        graph: &mut CompilerGraphBuilder,
        kernels: &impl crate::gpu::kernels::KernelReflections,
        hierarchy_levels: u32,
    ) -> Result<(), String> {
        self.mark.register_kernel(graph, kernels)?;
        self.scan.register(graph, hierarchy_levels)?;
        self.scatter.register_kernel(graph, kernels)?;
        Ok(())
    }
}

/// Two independent counted prefix scans recorded stage-by-stage in the same
/// compute passes. Shared read-only count and dispatch resources are allowed;
/// every mutable relation must remain distinct.
pub struct PrefixScanPairGraph {
    pub phase: CompilerPhase,
    pub dispatch_domain: ResourceDomain,
    pub hierarchy_levels: u32,
    pub passes: PrefixScanGraphPasses,
    pub left: PrefixScanGraphResources,
    pub right: PrefixScanGraphResources,
}

/// Two independent prefix scans recorded stage-by-stage as one operation.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct PrefixScanPairSpec {
    pub left_label: &'static str,
    pub right_label: &'static str,
    pub phase: CompilerPhase,
    pub dispatch_domain: ResourceDomain,
    pub passes: PrefixScanGraphPasses,
    pub left: PrefixScanResources<&'static str>,
    pub right: PrefixScanResources<&'static str>,
}

impl PrefixScanPairSpec {
    pub fn register(
        self,
        graph: &mut CompilerGraphBuilder,
        hierarchy_levels: u32,
    ) -> Result<((ResourceId, ResourceId), (ResourceId, ResourceId)), String> {
        let left = graph.resolve_prefix_scan_resources(self.left)?;
        let right = graph.resolve_prefix_scan_resources(self.right)?;
        graph.add_fragment(PrefixScanPairGraph {
            phase: self.phase,
            dispatch_domain: self.dispatch_domain,
            hierarchy_levels,
            passes: self.passes,
            left,
            right,
        })
    }
}

struct PrefixScanPassSet {
    local: PassDesc,
    hierarchy_up_first: PassDesc,
    hierarchy_up_rest: Option<PassDesc>,
    hierarchy_down: Option<PassDesc>,
    apply: PassDesc,
}

impl PrefixScanPassSet {
    fn batch(self, other: Self) -> Self {
        fn batch(mut left: PassDesc, right: PassDesc) -> PassDesc {
            debug_assert_eq!(left.name, right.name);
            debug_assert_eq!(left.phase, right.phase);
            debug_assert_eq!(left.dispatch_domain, right.dispatch_domain);
            left.accesses.extend(right.accesses);
            left
        }
        Self {
            local: batch(self.local, other.local),
            hierarchy_up_first: batch(self.hierarchy_up_first, other.hierarchy_up_first),
            hierarchy_up_rest: self
                .hierarchy_up_rest
                .zip(other.hierarchy_up_rest)
                .map(|(left, right)| batch(left, right)),
            hierarchy_down: self
                .hierarchy_down
                .zip(other.hierarchy_down)
                .map(|(left, right)| batch(left, right)),
            apply: batch(self.apply, other.apply),
        }
    }
}

fn prefix_scan_passes(
    graph: &CompilerGraphBuilder,
    phase: CompilerPhase,
    dispatch_domain: ResourceDomain,
    hierarchy_levels: u32,
    passes: PrefixScanGraphPasses,
    r: PrefixScanGraphResources,
    invocation: u16,
) -> Result<PrefixScanPassSet, String> {
    if hierarchy_levels == 0 {
        return Err(format!(
            "prefix scan {} requires at least one hierarchy level",
            passes.local,
        ));
    }
    let mut distinct = BTreeSet::new();
    for resource in [
        r.count,
        r.input,
        r.output_prefix,
        r.total,
        r.dispatch_args,
        r.local_prefix,
        r.block_sum,
        r.block_prefix,
        r.hierarchy,
    ] {
        if graph.resources.get(resource.index()).is_none() {
            return Err(format!(
                "prefix scan {} references unknown resource {}",
                passes.local,
                resource.index(),
            ));
        }
        if !distinct.insert(resource) {
            return Err(format!(
                "prefix scan {} uses resource {} for two simultaneous roles",
                passes.local,
                graph.resources[resource.index()].name,
            ));
        }
    }
    let lane = |access: PassAccess| access.in_invocation(invocation);
    let pass = |name, accesses| PassDesc {
        name,
        phase,
        dispatch_domain,
        accesses,
    };
    Ok(PrefixScanPassSet {
        local: pass(
            passes.local,
            vec![
                lane(PassAccess::read("scan_count", r.count)),
                lane(PassAccess::read("scan_input", r.input)),
                lane(PassAccess::indirect("scan_dispatch_args", r.dispatch_args)),
                lane(PassAccess::write("scan_local_prefix", r.local_prefix)),
                lane(PassAccess::write("scan_block_sum", r.block_sum)),
            ],
        ),
        hierarchy_up_first: pass(
            passes.hierarchy_up_first,
            vec![
                lane(PassAccess::read("scan_count", r.count)),
                lane(PassAccess::read("scan_block_sum", r.block_sum)),
                lane(PassAccess::write("scan_block_prefix", r.block_prefix)),
                lane(PassAccess::write("scan_hierarchy", r.hierarchy)),
            ],
        ),
        hierarchy_up_rest: (hierarchy_levels > 1).then(|| {
            pass(
                passes.hierarchy_up_rest,
                vec![
                    lane(PassAccess::read("scan_count", r.count)),
                    lane(PassAccess::read("scan_block_sum", r.block_sum)),
                    lane(PassAccess::read_write("scan_block_prefix", r.block_prefix)),
                    lane(PassAccess::read_write("scan_hierarchy", r.hierarchy)),
                ],
            )
        }),
        hierarchy_down: (hierarchy_levels > 1).then(|| {
            pass(
                passes.hierarchy_down,
                vec![
                    lane(PassAccess::read("scan_count", r.count)),
                    lane(PassAccess::read_write("scan_block_prefix", r.block_prefix)),
                    lane(PassAccess::read_write("scan_hierarchy", r.hierarchy)),
                ],
            )
        }),
        apply: pass(
            passes.apply,
            vec![
                lane(PassAccess::read("scan_count", r.count)),
                lane(PassAccess::indirect("scan_dispatch_args", r.dispatch_args)),
                lane(PassAccess::read("scan_local_prefix", r.local_prefix)),
                lane(PassAccess::read("scan_block_prefix", r.block_prefix)),
                lane(PassAccess::write("scan_output_prefix", r.output_prefix)),
                lane(PassAccess::write("scan_total", r.total)),
            ],
        ),
    })
}

fn add_prefix_scan_passes(
    graph: &mut CompilerGraphBuilder,
    hierarchy_levels: u32,
    passes: PrefixScanPassSet,
) -> Result<(), String> {
    graph.add_pass(passes.local)?;
    graph.add_pass(passes.hierarchy_up_first)?;
    if let Some(pass) = passes.hierarchy_up_rest {
        graph.add_repeated_region(hierarchy_levels - 1, vec![pass])?;
    }
    if let Some(pass) = passes.hierarchy_down {
        graph.add_repeated_region(hierarchy_levels - 1, vec![pass])?;
    }
    graph.add_pass(passes.apply)?;
    Ok(())
}

impl CompilerGraphFragment for PrefixScanPairGraph {
    type Output = ((ResourceId, ResourceId), (ResourceId, ResourceId));

    fn add_to(self, graph: &mut CompilerGraphBuilder) -> Result<Self::Output, String> {
        let left = prefix_scan_passes(
            graph,
            self.phase,
            self.dispatch_domain,
            self.hierarchy_levels,
            self.passes,
            self.left,
            0,
        )?;
        let right = prefix_scan_passes(
            graph,
            self.phase,
            self.dispatch_domain,
            self.hierarchy_levels,
            self.passes,
            self.right,
            1,
        )?;
        add_prefix_scan_passes(graph, self.hierarchy_levels, left.batch(right))?;
        assign_prefix_scan_kernels(graph, self.passes)?;
        Ok((
            (self.left.output_prefix, self.left.total),
            (self.right.output_prefix, self.right.total),
        ))
    }
}

impl CompilerGraphFragment for PrefixScanGraph {
    type Output = (ResourceId, ResourceId);

    fn add_to(self, graph: &mut CompilerGraphBuilder) -> Result<Self::Output, String> {
        let passes = prefix_scan_passes(
            graph,
            self.phase,
            self.dispatch_domain,
            self.hierarchy_levels,
            self.passes,
            self.resources,
            0,
        )?;
        add_prefix_scan_passes(graph, self.hierarchy_levels, passes)?;
        assign_prefix_scan_kernels(graph, self.passes)?;
        Ok((self.resources.output_prefix, self.resources.total))
    }
}

#[derive(Default)]
pub struct CompilerGraphBuilder {
    resources: Vec<ResourceDesc>,
    passes: Vec<PassDesc>,
    pass_kernels: Vec<Option<&'static str>>,
    reflection_complete: Vec<bool>,
    resource_names: BTreeSet<&'static str>,
    resource_aliases: BTreeMap<&'static str, ResourceId>,
    reflected_binding_resources: BTreeMap<&'static str, BTreeSet<ResourceId>>,
    reflected_arena_conflicts: BTreeSet<(ResourceId, ResourceId)>,
    pass_names: BTreeSet<&'static str>,
    repeated_regions: Vec<RepeatedPassRegion>,
    paged_regions: Vec<PagedPassRegion>,
    paged_resources: Vec<Option<PagedResourceDesc>>,
    lifetime_fences: Vec<ResourceLifetimeFence>,
}

impl CompilerGraphBuilder {
    /// Associates a semantic graph pass with the generated shader that
    /// implements it. High-level operations use this after expanding their
    /// internal schedule so pipeline selection remains part of the graph.
    pub(crate) fn assign_kernel(
        &mut self,
        pass_name: &str,
        kernel: &'static str,
    ) -> Result<(), String> {
        let pass = self
            .passes
            .iter()
            .position(|pass| pass.name == pass_name)
            .map(PassId)
            .ok_or_else(|| {
                format!("cannot assign kernel `{kernel}` to unknown pass `{pass_name}`")
            })?;
        match self.pass_kernels[pass.index()] {
            Some(existing) if existing != kernel => Err(format!(
                "compiler pass `{pass_name}` already uses kernel `{existing}`, not `{kernel}`",
            )),
            _ => {
                self.pass_kernels[pass.index()] = Some(kernel);
                Ok(())
            }
        }
    }

    /// Marks a manually assembled pass as having the complete storage surface
    /// of its assigned kernel. Such passes join the graph-wide reflection
    /// validation performed before workspace materialization.
    pub(crate) fn require_complete_reflection(&mut self, pass_name: &str) -> Result<(), String> {
        let pass = self
            .passes
            .iter()
            .position(|pass| pass.name == pass_name)
            .map(PassId)
            .ok_or_else(|| format!("unknown compiler pass `{pass_name}`"))?;
        if self.pass_kernels[pass.index()].is_none() {
            return Err(format!(
                "compiler pass `{pass_name}` cannot require reflection without an assigned kernel",
            ));
        }
        self.reflection_complete[pass.index()] = true;
        Ok(())
    }

    pub fn new() -> Self {
        Self::default()
    }

    pub fn resource_id(&self, name: &str) -> Option<ResourceId> {
        self.resources
            .iter()
            .position(|resource| resource.name == name)
            .map(ResourceId)
            .or_else(|| self.resource_aliases.get(name).copied())
    }

    fn reflected_resource(&self, name: &str) -> Option<(&'static str, ResourceId)> {
        if let Some((index, resource)) = self
            .resources
            .iter()
            .enumerate()
            .find(|(_, resource)| resource.name == name)
        {
            return Some((resource.name, ResourceId(index)));
        }
        self.resource_aliases
            .get_key_value(name)
            .map(|(&alias, &resource)| (alias, resource))
    }

    /// Retains graph-owned relations after the last recorded pass.
    ///
    /// This is the explicit stage-output boundary corresponding to an array
    /// returned from a Futhark entry point: output storage cannot be colored
    /// over by later scratch even when its final in-graph read has completed.
    pub fn retain_outputs(&mut self, names: &[&str]) -> Result<(), String> {
        for &name in names {
            let resource = self
                .resource_id(name)
                .ok_or_else(|| format!("cannot retain unknown compiler resource `{name}`"))?;
            let desc = &mut self.resources[resource.index()];
            match desc.class {
                ResourceClass::Workspace | ResourceClass::Artifact => {
                    desc.class = ResourceClass::Output;
                }
                ResourceClass::Output => {}
                class => {
                    return Err(format!(
                        "compiler resource `{name}` has ownership class {class:?}; only graph-owned workspace or artifacts can become outputs",
                    ));
                }
            }
        }
        Ok(())
    }

    /// Gives graph-owned workspace a stable, non-colored allocation for a
    /// relation whose complete physical schedule is not represented yet.
    pub fn dedicate_workspace(&mut self, resource: ResourceId) -> Result<(), String> {
        let desc = self.resources.get_mut(resource.index()).ok_or_else(|| {
            format!(
                "cannot dedicate unknown compiler resource {}",
                resource.index()
            )
        })?;
        if desc.class != ResourceClass::Workspace {
            return Err(format!(
                "compiler resource `{}` has ownership class {:?}; only workspace can be dedicated",
                desc.name, desc.class,
            ));
        }
        desc.class = ResourceClass::Resident;
        Ok(())
    }

    /// Gives every graph-owned workspace relation a distinct physical identity.
    ///
    /// This is the conservative boundary for a phase whose handwritten
    /// recorder is not yet represented by the graph in exact execution order.
    /// Such a phase may still use the graph for reflected bindings and resource
    /// ownership, but it must not infer aliasing from an incomplete schedule.
    pub fn dedicate_all_workspace(&mut self) {
        for resource in &mut self.resources {
            if resource.class == ResourceClass::Workspace {
                resource.class = ResourceClass::Resident;
            }
        }
    }

    /// Adds physical-allocation conflicts for every prepared compute kernel.
    ///
    /// Some compiler phases still have a handwritten command recorder whose
    /// exact pass order is not yet represented by this graph. Their logical
    /// resources therefore remain `Resident`, but physical arenas may still
    /// pack disjoint ranges together when no shader ever binds them in the
    /// same dispatch. Slang reflection supplies that conservative co-binding
    /// relation without duplicating shader interfaces in Rust.
    pub(crate) fn add_reflected_arena_conflicts(
        &mut self,
        kernels: &impl KernelReflections,
    ) -> Result<(), String> {
        let mut reflected_conflicts = BTreeSet::new();
        let mapped_resources = |binding: &str| {
            if let Some(resources) = self.reflected_binding_resources.get(binding) {
                return resources.clone();
            }
            if let Some(resource) = self.resource_id(binding) {
                return BTreeSet::from([resource]);
            }
            let resources = self
                .passes
                .iter()
                .flat_map(|pass| pass.accesses.iter())
                .filter(|access| access.reflected && access.binding == binding)
                .map(|access| access.resource)
                .collect::<BTreeSet<_>>();
            if resources.len() == 1 {
                resources
            } else {
                BTreeSet::new()
            }
        };

        for key in kernels.reflection_keys() {
            let mut bound_resources = reflected_parameters(kernels.reflection(key)?)
                .into_iter()
                .filter(|parameter| {
                    slang_category_and_type_to_wgpu(parameter, &parameter.ty).is_some_and(|ty| {
                        matches!(
                            ty,
                            wgpu::BindingType::Buffer {
                                ty: wgpu::BufferBindingType::Storage { .. },
                                ..
                            }
                        )
                    })
                })
                .flat_map(|parameter| mapped_resources(&parameter.name))
                .collect::<BTreeSet<_>>()
                .into_iter()
                .collect::<Vec<_>>();
            bound_resources.sort_unstable();
            for (index, &left) in bound_resources.iter().enumerate() {
                for &right in &bound_resources[index + 1..] {
                    reflected_conflicts.insert((left, right));
                }
            }
        }
        self.reflected_arena_conflicts.extend(reflected_conflicts);
        Ok(())
    }

    /// Declares the graph resources which a shader-facing binding may name.
    ///
    /// Handwritten recorders sometimes bind one of several ping-pong resources
    /// under the same reflected parameter name. Arena conflict generation must
    /// protect every possible physical resource rather than inventing a
    /// same-named placeholder resource or assuming one fixed alias.
    pub fn add_reflected_binding_resources(
        &mut self,
        binding: &'static str,
        resources: impl IntoIterator<Item = ResourceId>,
    ) -> Result<(), String> {
        let resources = resources.into_iter().collect::<BTreeSet<_>>();
        if resources.is_empty() {
            return Err(format!(
                "reflected binding `{binding}` must name at least one graph resource"
            ));
        }
        for resource in &resources {
            if self.resources.get(resource.index()).is_none() {
                return Err(format!(
                    "reflected binding `{binding}` targets unknown resource {}",
                    resource.index(),
                ));
            }
        }
        self.reflected_binding_resources
            .entry(binding)
            .or_default()
            .extend(resources);
        Ok(())
    }

    /// Gives one physical ownership identity another logical operation name.
    pub fn add_resource_alias(
        &mut self,
        alias: &'static str,
        resource: ResourceId,
    ) -> Result<(), String> {
        if self.resource_id(alias).is_some() {
            return Err(format!("duplicate compiler resource alias {alias}"));
        }
        if self.resources.get(resource.index()).is_none() {
            return Err(format!(
                "compiler resource alias {alias} targets unknown resource {}",
                resource.index(),
            ));
        }
        self.resource_aliases.insert(alias, resource);
        Ok(())
    }

    /// Adds one high-level operation to the graph.
    pub fn add_fragment<F>(&mut self, fragment: F) -> Result<F::Output, String>
    where
        F: CompilerGraphFragment,
    {
        fragment.add_to(self)
    }

    pub fn add_resource(&mut self, desc: ResourceDesc) -> Result<ResourceId, String> {
        if desc.bytes == 0 {
            return Err(format!("compiler resource {} has zero bytes", desc.name));
        }
        if self.resource_aliases.contains_key(desc.name) || !self.resource_names.insert(desc.name) {
            return Err(format!("duplicate compiler resource {}", desc.name));
        }
        let id = ResourceId(self.resources.len());
        self.resources.push(desc);
        self.paged_resources.push(None);
        Ok(id)
    }

    /// Adds a GPU storage relation to the graph.
    ///
    /// Storage usage is an implementation property shared by compiler phases;
    /// phase-specific graph builders should only need to state the relation's
    /// semantic domain, ownership class, and extent.
    pub fn add_storage(
        &mut self,
        name: &'static str,
        domain: ResourceDomain,
        class: ResourceClass,
        bytes: u64,
    ) -> Result<ResourceId, String> {
        self.add_resource(ResourceDesc {
            name,
            domain,
            class,
            bytes,
            usage: WorkspaceUsageClass::Storage,
        })
    }

    /// Adds a storage relation which also serves as an indirect dispatch buffer.
    pub fn add_indirect_storage(
        &mut self,
        name: &'static str,
        domain: ResourceDomain,
        class: ResourceClass,
        bytes: u64,
    ) -> Result<ResourceId, String> {
        self.add_resource(ResourceDesc {
            name,
            domain,
            class,
            bytes,
            usage: WorkspaceUsageClass::StorageIndirect,
        })
    }

    /// Resolves the one shared named resource specification used by both a
    /// runtime prefix scan and its compiler-graph fragment.
    pub fn resolve_prefix_scan_resources(
        &self,
        names: PrefixScanResources<&str>,
    ) -> Result<PrefixScanGraphResources, String> {
        let resource = |name: &str| {
            self.resource_id(name)
                .ok_or_else(|| format!("prefix scan resource `{name}` is not registered"))
        };
        Ok(PrefixScanResources {
            count: resource(names.count)?,
            input: resource(names.input)?,
            output_prefix: resource(names.output_prefix)?,
            total: resource(names.total)?,
            dispatch_args: resource(names.dispatch_args)?,
            local_prefix: resource(names.local_prefix)?,
            block_sum: resource(names.block_sum)?,
            block_prefix: resource(names.block_prefix)?,
            hierarchy: resource(names.hierarchy)?,
        })
    }

    /// Reserves the result and temporary storage required by a radix sort.
    ///
    /// Buffer sizes, usage flags, and resource domains are properties of the
    /// algorithm. A caller provides the count and key arrays plus the maximum
    /// row count; it does not reproduce the storage calculation.
    pub fn add_radix_sort_resources(
        &mut self,
        count: ResourceId,
        keys: Vec<ResourceId>,
        domain: ResourceDomain,
        capacity: u64,
        rows_per_block: u64,
        bucket_count: u64,
        names: RadixSortGraphResourceNames,
    ) -> Result<RadixSortGraphResources, String> {
        if rows_per_block == 0 || bucket_count == 0 {
            return Err("radix sort requires nonzero rows per block and bucket count".into());
        }
        let capacity = capacity.max(1);
        let row_bytes = capacity
            .checked_mul(4)
            .ok_or_else(|| "radix sort order storage size overflows".to_owned())?;
        let histogram_bytes = capacity
            .div_ceil(rows_per_block)
            .checked_mul(bucket_count)
            .and_then(|rows| rows.checked_mul(4))
            .ok_or_else(|| "radix sort histogram storage size overflows".to_owned())?;
        let bucket_bytes = bucket_count
            .checked_mul(4)
            .ok_or_else(|| "radix sort bucket storage size overflows".to_owned())?;
        let mut storage = |name, resource_domain, bytes, usage| {
            self.add_resource(ResourceDesc {
                name,
                domain: resource_domain,
                class: ResourceClass::Workspace,
                bytes,
                usage,
            })
        };
        let order = storage(names.order, domain, row_bytes, WorkspaceUsageClass::Storage)?;
        let temporary_order = storage(
            names.temporary_order,
            domain,
            row_bytes,
            WorkspaceUsageClass::Storage,
        )?;
        let dispatch_args = storage(
            names.dispatch_args,
            ResourceDomain::DispatchArguments,
            12,
            WorkspaceUsageClass::StorageIndirect,
        )?;
        let histogram = storage(
            names.histogram,
            domain,
            histogram_bytes,
            WorkspaceUsageClass::Storage,
        )?;
        let bucket_prefix = storage(
            names.bucket_prefix,
            domain,
            histogram_bytes,
            WorkspaceUsageClass::Storage,
        )?;
        let bucket_total = storage(
            names.bucket_total,
            domain,
            bucket_bytes,
            WorkspaceUsageClass::Storage,
        )?;
        let bucket_base = storage(
            names.bucket_base,
            domain,
            bucket_bytes,
            WorkspaceUsageClass::Storage,
        )?;
        Ok(RadixSortGraphResources {
            count,
            count_binding: self.resources[count.index()].name,
            keys: keys
                .into_iter()
                .map(|resource| ReflectedResourceBinding {
                    binding: self.resources[resource.index()].name,
                    resource,
                    mode: None,
                })
                .collect(),
            order,
            temporary_order,
            dispatch_args,
            histogram,
            bucket_prefix,
            bucket_total,
            bucket_base,
        })
    }

    /// Reserves the output and temporary storage for a counted prefix scan.
    pub fn add_prefix_scan_resources(
        &mut self,
        count: ResourceId,
        input: ResourceId,
        dispatch_args: ResourceId,
        domain: ResourceDomain,
        capacity: u64,
        rows_per_block: u64,
        names: PrefixScanGraphResourceNames,
    ) -> Result<PrefixScanGraphResources, String> {
        if rows_per_block == 0 {
            return Err("prefix scan requires a nonzero row block size".into());
        }
        let capacity = capacity.max(1);
        let row_bytes = capacity
            .checked_mul(4)
            .ok_or_else(|| "prefix scan row storage size overflows".to_owned())?;
        let mut storage = |name, resource_domain, bytes, usage| {
            self.add_resource(ResourceDesc {
                name,
                domain: resource_domain,
                class: ResourceClass::Workspace,
                bytes,
                usage,
            })
        };
        let output_prefix = storage(
            names.output_prefix,
            domain,
            row_bytes,
            WorkspaceUsageClass::Storage,
        )?;
        let total = storage(names.total, domain, 4, WorkspaceUsageClass::Storage)?;
        let workspace =
            self.add_prefix_scan_workspace(domain, capacity, rows_per_block, names.workspace())?;
        Ok(PrefixScanGraphResources {
            count,
            input,
            dispatch_args,
            output_prefix,
            total,
            local_prefix: workspace.local_prefix,
            block_sum: workspace.block_sum,
            block_prefix: workspace.block_prefix,
            hierarchy: workspace.hierarchy,
        })
    }

    /// Reserves reusable internal storage without prescribing scan inputs or outputs.
    pub fn add_prefix_scan_workspace(
        &mut self,
        domain: ResourceDomain,
        capacity: u64,
        rows_per_block: u64,
        names: PrefixScanWorkspace<&'static str>,
    ) -> Result<PrefixScanWorkspace<ResourceId>, String> {
        if rows_per_block == 0 {
            return Err("prefix scan requires a nonzero row block size".into());
        }
        let capacity = capacity.max(1);
        let row_bytes = capacity
            .checked_mul(4)
            .ok_or_else(|| "prefix scan row storage size overflows".to_owned())?;
        let block_bytes = capacity
            .div_ceil(rows_per_block)
            .max(1)
            .checked_mul(4)
            .ok_or_else(|| "prefix scan block storage size overflows".to_owned())?;
        let mut add = |name, bytes| {
            self.add_resource(ResourceDesc {
                name,
                domain,
                class: ResourceClass::Workspace,
                bytes,
                usage: WorkspaceUsageClass::Storage,
            })
        };
        Ok(PrefixScanWorkspace {
            local_prefix: add(names.local_prefix, row_bytes)?,
            block_sum: add(names.block_sum, block_bytes)?,
            block_prefix: add(names.block_prefix, block_bytes)?,
            hierarchy: add(names.hierarchy, block_bytes)?,
        })
    }

    /// Keeps `resource` live from the named first pass through the named last
    /// pass. Both endpoints must exist and be ordered when the graph is built.
    pub fn fence_resource_lifetime(
        &mut self,
        resource: ResourceId,
        first_pass: &'static str,
        last_pass: &'static str,
    ) -> Result<(), String> {
        if self.resources.get(resource.index()).is_none() {
            return Err(format!(
                "cannot fence unknown compiler resource {}",
                resource.index()
            ));
        }
        self.lifetime_fences.push(ResourceLifetimeFence {
            resource,
            first_pass,
            last_pass,
        });
        Ok(())
    }

    /// Keeps every resource accessed by the selected passes live across an
    /// execution interval that is not yet represented as graph nodes.
    ///
    /// This is intended for incremental migration of an existing recorder:
    /// the selected passes describe the complete resource surface of an
    /// operation, while `first_pass` and `last_pass` bound the real interval
    /// over which that operation is invoked. Once every invocation is a graph
    /// node, the ordinary pass schedule makes this fence unnecessary.
    pub fn fence_resources_accessed_by_passes(
        &mut self,
        pass_names: &[&str],
        first_pass: &'static str,
        last_pass: &'static str,
    ) -> Result<(), String> {
        let mut resources = BTreeSet::new();
        for pass_name in pass_names {
            let pass = self
                .passes
                .iter()
                .find(|pass| pass.name == *pass_name)
                .ok_or_else(|| {
                    format!("cannot fence resources for unknown compiler pass {pass_name}")
                })?;
            resources.extend(pass.accesses.iter().map(|access| access.resource));
        }
        for resource in resources {
            self.fence_resource_lifetime(resource, first_pass, last_pass)?;
        }
        Ok(())
    }

    /// Marks a resource as a bounded resident window over a larger logical
    /// stream. This changes allocation policy, not pass ordering or ownership.
    pub fn page_resource(
        &mut self,
        resource: ResourceId,
        page_bytes: u64,
        resident_pages: u32,
    ) -> Result<(), String> {
        let resource_desc = self
            .resources
            .get_mut(resource.index())
            .ok_or_else(|| format!("unknown compiler resource {}", resource.index()))?;
        if page_bytes == 0 || resident_pages == 0 {
            return Err(format!(
                "paged compiler resource {} has an empty resident page set",
                resource_desc.name,
            ));
        }
        if self.paged_resources[resource.index()].is_some() {
            return Err(format!(
                "compiler resource {} is already paged",
                resource_desc.name,
            ));
        }
        let logical_bytes = resource_desc.bytes;
        let resident_bytes = page_bytes
            .checked_mul(u64::from(resident_pages))
            .ok_or_else(|| format!("paged compiler resource {} overflows", resource_desc.name))?;
        if logical_bytes < page_bytes {
            return Err(format!(
                "paged compiler resource {} has a logical extent smaller than one page",
                resource_desc.name,
            ));
        }
        resource_desc.bytes = resident_bytes;
        self.paged_resources[resource.index()] = Some(PagedResourceDesc {
            logical_bytes,
            page_bytes,
            resident_pages,
        });
        Ok(())
    }

    pub fn add_pass(&mut self, desc: PassDesc) -> Result<PassId, String> {
        if !self.pass_names.insert(desc.name) {
            return Err(format!("duplicate compiler pass {}", desc.name));
        }
        if let Some(previous) = self.passes.last()
            && previous.phase > desc.phase
        {
            return Err(format!(
                "compiler pass {} in {:?} appears after later phase {:?}",
                desc.name, desc.phase, previous.phase,
            ));
        }
        let mut resources = BTreeMap::<ResourceId, (AccessMode, u16)>::new();
        for access in &desc.accesses {
            if access.resource.index() >= self.resources.len() {
                return Err(format!(
                    "compiler pass {} references unknown resource {}",
                    desc.name,
                    access.resource.index(),
                ));
            }
            if let Some((mode, invocation)) = resources.get(&access.resource) {
                let reason = if *invocation == access.invocation {
                    "more than once in one invocation"
                } else if mode.writes() || access.mode.writes() {
                    "mutably in multiple invocations"
                } else {
                    continue;
                };
                return Err(format!(
                    "compiler pass {} declares resource {} {reason}",
                    desc.name,
                    self.resources[access.resource.index()].name,
                ));
            }
            resources.insert(access.resource, (access.mode, access.invocation));
        }
        let id = PassId(self.passes.len());
        self.passes.push(desc);
        self.pass_kernels.push(None);
        self.reflection_complete.push(false);
        Ok(id)
    }

    /// Models the command-encoder clear that initializes dedicated resident
    /// resources at the start of a reusable compiler job.
    ///
    /// Ordinary workspace resources are deliberately excluded: they must
    /// still name their real algorithmic producer so coloring cannot conceal
    /// an incomplete lifetime. `Resident` is the migration boundary for
    /// graph-owned storage whose full middle schedule is not yet represented.
    pub fn add_resident_clear_pass(
        &mut self,
        name: &'static str,
        phase: CompilerPhase,
    ) -> Result<PassId, String> {
        let accesses = self
            .resources
            .iter()
            .enumerate()
            .filter(|(_, resource)| resource.class == ResourceClass::Resident)
            .map(|(index, resource)| PassAccess::write(resource.name, ResourceId(index)))
            .collect();
        self.add_pass(PassDesc {
            name,
            phase,
            dispatch_domain: ResourceDomain::Bytes,
            accesses,
        })
    }

    /// Adds a compute pass whose complete storage-buffer surface is checked
    /// against Slang reflection at graph construction time.
    ///
    /// Unlike post-hoc reflection validation, this rejects omitted storage
    /// bindings. That makes the graph's input/output surface complete by
    /// construction while still leaving uniforms outside ownership tracking.
    pub fn add_reflected_compute_pass(
        &mut self,
        name: &'static str,
        phase: CompilerPhase,
        dispatch_domain: ResourceDomain,
        reflection: &SlangReflection,
        bindings: &[ReflectedResourceBinding],
    ) -> Result<PassId, String> {
        let reflected = reflected_parameters(reflection)
            .into_iter()
            .filter_map(|parameter| {
                let ty = slang_category_and_type_to_wgpu(parameter, &parameter.ty)?;
                matches!(
                    ty,
                    wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { .. },
                        ..
                    }
                )
                .then_some(parameter)
            })
            .collect::<Vec<_>>();
        let mut supplied = BTreeMap::new();
        for binding in bindings {
            if supplied.insert(binding.binding, *binding).is_some() {
                return Err(format!(
                    "compiler pass {name} maps storage binding {} more than once",
                    binding.binding,
                ));
            }
        }
        let mut accesses = Vec::with_capacity(reflected.len());
        for parameter in reflected {
            let binding = supplied.remove(parameter.name.as_str()).ok_or_else(|| {
                format!(
                    "compiler pass {name} omits reflected storage binding {}",
                    parameter.name,
                )
            })?;
            let writable = parameter
                .ty
                .access
                .as_deref()
                .is_some_and(|access| access.eq_ignore_ascii_case("readWrite"));
            let mode = binding.mode.unwrap_or(if writable {
                AccessMode::ReadWrite
            } else {
                AccessMode::Read
            });
            if mode.writes() && !writable {
                return Err(format!(
                    "compiler pass {name} writes {} but Slang reflects it read-only",
                    binding.binding,
                ));
            }
            if mode == AccessMode::Read && writable {
                return Err(format!(
                    "compiler pass {name} hides reflected writes through {}",
                    binding.binding,
                ));
            }
            accesses.push(PassAccess {
                binding: binding.binding,
                resource: binding.resource,
                mode,
                reflected: true,
                initializes_before_read: false,
                invocation: 0,
            });
        }
        if let Some((extra, _)) = supplied.into_iter().next() {
            return Err(format!(
                "compiler pass {name} maps {extra}, which is not a reflected storage binding",
            ));
        }
        let pass = self.add_pass(PassDesc {
            name,
            phase,
            dispatch_domain,
            accesses,
        })?;
        self.reflection_complete[pass.index()] = true;
        Ok(pass)
    }

    /// Adds a reflected compute pass by matching storage-binding names to
    /// logical resource names. Callers provide overrides only for deliberate
    /// aliases (or a precise `Write` initialization mode), so ordinary shader
    /// interfaces do not require a second handwritten binding inventory.
    pub fn add_reflected_compute_pass_by_name(
        &mut self,
        name: &'static str,
        phase: CompilerPhase,
        dispatch_domain: ResourceDomain,
        reflection: &SlangReflection,
        overrides: &[ReflectedResourceBinding],
    ) -> Result<PassId, String> {
        let mut bindings = Vec::new();
        for parameter in reflected_parameters(reflection) {
            let Some(binding_type) = slang_category_and_type_to_wgpu(parameter, &parameter.ty)
            else {
                continue;
            };
            if !matches!(
                binding_type,
                wgpu::BindingType::Buffer {
                    ty: wgpu::BufferBindingType::Storage { .. },
                    ..
                }
            ) {
                continue;
            }
            if let Some(binding) = overrides
                .iter()
                .find(|binding| binding.binding == parameter.name)
            {
                bindings.push(*binding);
                continue;
            }
            let (binding, resource) = self.reflected_resource(&parameter.name).ok_or_else(|| {
                    format!(
                        "compiler pass {name} has reflected storage binding {} with no same-named graph resource or override",
                        parameter.name,
                    )
                })?;
            bindings.push(ReflectedResourceBinding {
                binding,
                resource,
                mode: None,
            });
        }
        self.add_reflected_compute_pass(name, phase, dispatch_domain, reflection, &bindings)
    }

    /// Registers a graph pass directly from one generated kernel identity.
    /// Reflection supplies the binding/access surface and the graph retains
    /// the same identity for later pipeline preparation and execution.
    pub(crate) fn add_kernel_pass_by_name(
        &mut self,
        name: &'static str,
        phase: CompilerPhase,
        dispatch_domain: ResourceDomain,
        kernels: &impl KernelReflections,
        kernel: &'static str,
        overrides: &[ReflectedResourceBinding],
    ) -> Result<PassId, String> {
        let pass = self.add_reflected_compute_pass_by_name(
            name,
            phase,
            dispatch_domain,
            kernels.reflection(kernel)?,
            overrides,
        )?;
        self.pass_kernels[pass.index()] = Some(kernel);
        Ok(pass)
    }

    pub(crate) fn add_kernel_initializer_by_name(
        &mut self,
        name: &'static str,
        phase: CompilerPhase,
        dispatch_domain: ResourceDomain,
        kernels: &impl KernelReflections,
        kernel: &'static str,
    ) -> Result<PassId, String> {
        let pass = self.add_reflected_initializer_by_name(
            name,
            phase,
            dispatch_domain,
            kernels.reflection(kernel)?,
        )?;
        self.pass_kernels[pass.index()] = Some(kernel);
        Ok(pass)
    }

    /// Adds a same-named reflected pass while refining the access mode of a
    /// small number of bindings. This is the common case for Slang
    /// `RWStructuredBuffer` outputs that a shader only initializes. Resource
    /// remapping remains explicit through `ReflectedResourceBinding`.
    pub fn add_reflected_compute_pass_by_name_with_modes(
        &mut self,
        name: &'static str,
        phase: CompilerPhase,
        dispatch_domain: ResourceDomain,
        reflection: &SlangReflection,
        modes: &[(&'static str, AccessMode)],
    ) -> Result<PassId, String> {
        let overrides = modes
            .iter()
            .map(|&(binding, mode)| {
                let resource = self.resource_id(binding).ok_or_else(|| {
                    format!(
                        "compiler pass {name} refines access for {binding}, which has no same-named graph resource"
                    )
                })?;
                Ok(ReflectedResourceBinding {
                    binding,
                    resource,
                    mode: Some(mode),
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        self.add_reflected_compute_pass_by_name(
            name,
            phase,
            dispatch_domain,
            reflection,
            &overrides,
        )
    }

    /// Adds a reflected compute pass whose writable storage bindings are
    /// initialized rather than updated. Read-only bindings remain ordinary
    /// inputs; writable bindings begin their logical resource lifetimes here.
    pub fn add_reflected_initializer_by_name(
        &mut self,
        name: &'static str,
        phase: CompilerPhase,
        dispatch_domain: ResourceDomain,
        reflection: &SlangReflection,
    ) -> Result<PassId, String> {
        let overrides = reflected_parameters(reflection)
            .into_iter()
            .filter_map(|parameter| {
                let binding_type = slang_category_and_type_to_wgpu(parameter, &parameter.ty)?;
                let writable = matches!(
                    binding_type,
                    wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: false },
                        ..
                    }
                );
                writable.then(|| {
                    let (binding, resource) = self
                        .reflected_resource(&parameter.name)
                        .ok_or_else(|| {
                            format!(
                                "compiler pass {name} has reflected initializer binding {} with no same-named graph resource",
                                parameter.name,
                            )
                    })?;
                    Ok(ReflectedResourceBinding {
                        binding,
                        resource,
                        mode: Some(AccessMode::Write),
                    })
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        self.add_reflected_compute_pass_by_name(
            name,
            phase,
            dispatch_domain,
            reflection,
            &overrides,
        )
    }

    /// Adds one contiguous loop body to the graph. Pass descriptors remain
    /// individually addressable for reflection/binding validation.
    pub fn add_repeated_region(
        &mut self,
        iterations: u32,
        body: Vec<PassDesc>,
    ) -> Result<Vec<PassId>, String> {
        if iterations == 0 {
            return Err("compiler repeated pass region has zero iterations".into());
        }
        if body.is_empty() {
            return Err("compiler repeated pass region has an empty body".into());
        }
        let first_pass = PassId(self.passes.len());
        let mut ids = Vec::with_capacity(body.len());
        for pass in body {
            ids.push(self.add_pass(pass)?);
        }
        self.repeated_regions.push(RepeatedPassRegion {
            first_pass,
            pass_count: ids.len() as u32,
            iterations,
        });
        Ok(ids)
    }

    /// Marks an already declared contiguous pass range as a repeated command
    /// body. This is useful when construction of the individual passes is
    /// shared with non-repeated target variants.
    pub fn repeat_pass_range(
        &mut self,
        iterations: u32,
        first: &'static str,
        last: &'static str,
    ) -> Result<(), String> {
        if iterations == 0 {
            return Err("compiler repeated pass region has zero iterations".into());
        }
        let first_pass = self
            .passes
            .iter()
            .position(|pass| pass.name == first)
            .ok_or_else(|| format!("unknown first repeated pass {first}"))?;
        let last_pass = self
            .passes
            .iter()
            .position(|pass| pass.name == last)
            .ok_or_else(|| format!("unknown last repeated pass {last}"))?;
        if last_pass < first_pass {
            return Err(format!("repeated pass range {first}..{last} is reversed"));
        }
        self.repeated_regions.push(RepeatedPassRegion {
            first_pass: PassId(first_pass),
            pass_count: (last_pass - first_pass + 1) as u32,
            iterations,
        });
        Ok(())
    }

    pub fn add_paged_region(
        &mut self,
        driving_resource: ResourceId,
        body: Vec<PassDesc>,
    ) -> Result<Vec<PassId>, String> {
        if self
            .paged_resources
            .get(driving_resource.index())
            .copied()
            .flatten()
            .is_none()
        {
            return Err(format!(
                "compiler paged region is driven by non-paged resource {}",
                driving_resource.index(),
            ));
        }
        if body.is_empty() {
            return Err("compiler paged pass region has an empty body".into());
        }
        let first_pass = PassId(self.passes.len());
        let mut ids = Vec::with_capacity(body.len());
        for pass in body {
            ids.push(self.add_pass(pass)?);
        }
        self.paged_regions.push(PagedPassRegion {
            first_pass,
            pass_count: ids.len() as u32,
            driving_resource,
        });
        Ok(ids)
    }

    pub fn build(self) -> Result<CompilerGraph, String> {
        let mut paged_pass_membership = vec![false; self.passes.len()];
        for region in &self.paged_regions {
            let end = region
                .first_pass
                .index()
                .checked_add(region.pass_count as usize)
                .ok_or_else(|| "compiler paged pass region overflows".to_owned())?;
            if end > self.passes.len() {
                return Err("compiler paged pass region extends past the graph".into());
            }
            paged_pass_membership[region.first_pass.index()..end].fill(true);
        }
        for (pass_index, pass) in self.passes.iter().enumerate() {
            if paged_pass_membership[pass_index] {
                continue;
            }
            if let Some(access) = pass
                .accesses
                .iter()
                .find(|access| self.paged_resources[access.resource.index()].is_some())
            {
                return Err(format!(
                    "compiler pass {} accesses paged resource {} outside a paged region",
                    pass.name,
                    self.resources[access.resource.index()].name,
                ));
            }
        }
        let mut initialized = self
            .resources
            .iter()
            .map(|resource| {
                matches!(
                    resource.class,
                    ResourceClass::Input | ResourceClass::External
                )
            })
            .collect::<Vec<_>>();
        let mut producers = vec![None; self.resources.len()];
        let mut first_pass = vec![None; self.resources.len()];
        let mut last_pass = vec![None; self.resources.len()];

        for (pass_index, pass) in self.passes.iter().enumerate() {
            let pass_id = PassId(pass_index);
            for access in &pass.accesses {
                let resource_index = access.resource.index();
                let resource = self.resources[resource_index];
                first_pass[resource_index].get_or_insert(pass_id);
                last_pass[resource_index] = Some(pass_id);

                if access.mode.reads()
                    && !initialized[resource_index]
                    && !access.initializes_before_read
                {
                    return Err(format!(
                        "compiler pass {} reads {} before it is initialized",
                        pass.name, resource.name,
                    ));
                }
                if !access.mode.writes() {
                    continue;
                }
                match resource.class {
                    ResourceClass::Input => {
                        return Err(format!(
                            "compiler pass {} writes immutable input {}",
                            pass.name, resource.name,
                        ));
                    }
                    ResourceClass::External => {}
                    ResourceClass::Artifact if producers[resource_index].is_some() => {
                        return Err(format!(
                            "compiler artifact {} has more than one producer",
                            resource.name,
                        ));
                    }
                    ResourceClass::Artifact => producers[resource_index] = Some(pass_id),
                    ResourceClass::Workspace | ResourceClass::Resident | ResourceClass::Output => {
                        producers[resource_index].get_or_insert(pass_id);
                    }
                }
                initialized[resource_index] = true;
            }
        }

        for (index, resource) in self.resources.iter().enumerate() {
            match resource.class {
                ResourceClass::Input | ResourceClass::External => {}
                _ if producers[index].is_none() => {
                    return Err(format!(
                        "compiler resource {} has no producing pass",
                        resource.name,
                    ));
                }
                _ => {}
            }
        }

        // Every resource touched in a repeated body remains live across the
        // whole loop. This is conservative for per-iteration temporaries and
        // exact for loop-carried values such as radix ping-pong arrays.
        for region in &self.repeated_regions {
            let region_last = PassId(
                region
                    .first_pass
                    .index()
                    .checked_add(region.pass_count as usize - 1)
                    .ok_or_else(|| "compiler repeated pass region overflows".to_owned())?,
            );
            let mut touched = BTreeSet::new();
            for pass in &self.passes[region.first_pass.index()..=region_last.index()] {
                touched.extend(pass.accesses.iter().map(|access| access.resource));
            }
            for resource in touched {
                let index = resource.index();
                first_pass[index] = Some(first_pass[index].unwrap().min(region.first_pass));
                last_pass[index] = Some(last_pass[index].unwrap().max(region_last));
            }
        }

        for region in &self.paged_regions {
            let region_last = PassId(
                region
                    .first_pass
                    .index()
                    .checked_add(region.pass_count as usize - 1)
                    .ok_or_else(|| "compiler paged pass region overflows".to_owned())?,
            );
            let mut touched = BTreeSet::new();
            for pass in &self.passes[region.first_pass.index()..=region_last.index()] {
                touched.extend(pass.accesses.iter().map(|access| access.resource));
            }
            for resource in touched {
                let index = resource.index();
                first_pass[index] = Some(first_pass[index].unwrap().min(region.first_pass));
                last_pass[index] = Some(last_pass[index].unwrap().max(region_last));
            }
        }

        for fence in &self.lifetime_fences {
            let first = self
                .passes
                .iter()
                .position(|pass| pass.name == fence.first_pass)
                .map(PassId)
                .ok_or_else(|| {
                    format!(
                        "compiler resource lifetime fence for {} starts at unknown pass {}",
                        self.resources[fence.resource.index()].name,
                        fence.first_pass,
                    )
                })?;
            let last = self
                .passes
                .iter()
                .position(|pass| pass.name == fence.last_pass)
                .map(PassId)
                .ok_or_else(|| {
                    format!(
                        "compiler resource lifetime fence for {} ends at unknown pass {}",
                        self.resources[fence.resource.index()].name,
                        fence.last_pass,
                    )
                })?;
            if first > last {
                return Err(format!(
                    "compiler resource lifetime fence for {} is reversed: {} follows {}",
                    self.resources[fence.resource.index()].name,
                    fence.first_pass,
                    fence.last_pass,
                ));
            }
            let index = fence.resource.index();
            let Some(resource_first) = first_pass[index] else {
                return Err(format!(
                    "compiler resource lifetime fence for {} has no graph access",
                    self.resources[index].name,
                ));
            };
            let resource_last = last_pass[index].expect("accessed resource has a last pass");
            first_pass[index] = Some(resource_first.min(first));
            last_pass[index] = Some(resource_last.max(last));
        }

        let graph_end = PassId(self.passes.len().saturating_sub(1));
        let lifetimes = (0..self.resources.len())
            .map(|index| {
                Some(ResourceLifetime {
                    first_pass: first_pass[index]?,
                    last_pass: if self.resources[index].class == ResourceClass::Output {
                        graph_end
                    } else {
                        last_pass[index]?
                    },
                    producer: producers[index],
                })
            })
            .collect::<Vec<_>>();
        let workspace = plan_graph_workspace(&self.resources, &lifetimes)?;
        Ok(CompilerGraph {
            resources: self.resources,
            resource_aliases: self.resource_aliases,
            reflected_arena_conflicts: self.reflected_arena_conflicts,
            passes: self.passes,
            pass_kernels: self.pass_kernels,
            reflection_complete: self.reflection_complete,
            lifetimes,
            repeated_regions: self.repeated_regions,
            paged_regions: self.paged_regions,
            paged_resources: self.paged_resources,
            lifetime_fences: self.lifetime_fences,
            workspace,
        })
    }
}

fn plan_graph_workspace(
    resources: &[ResourceDesc],
    lifetimes: &[Option<ResourceLifetime>],
) -> Result<WorkspacePlan, String> {
    struct SlotState {
        plan: WorkspaceSlotPlan,
        dedicated: bool,
        lifetimes: Vec<ResourceLifetime>,
    }

    // `Resident` is a per-resource incomplete-composition boundary. Keep that
    // allocation dedicated, but do not let one partially tracked family
    // suppress coloring for unrelated `Workspace` resources whose complete
    // pass lifetimes are already represented by this graph. This makes graph
    // migration compositional: a resource becomes colorable only when its own
    // class changes from `Resident` to `Workspace`.
    let mut order = resources
        .iter()
        .enumerate()
        .filter_map(|(index, resource)| {
            (!matches!(
                resource.class,
                ResourceClass::Input | ResourceClass::External
            ))
            .then_some((index, resource, lifetimes[index]?))
        })
        .collect::<Vec<_>>();
    // Place the largest intervals first. The first resource assigned to a
    // slot then fixes its physical size, and every later assignment is free.
    // Starting in pass order is a poor fit for weighted interval coloring:
    // deleting one large early interval can fragment smaller later resources
    // across several allocations and increase total memory.
    order.sort_unstable_by_key(|(_, resource, lifetime)| {
        (
            std::cmp::Reverse(resource.bytes),
            lifetime.first_pass,
            resource.name,
        )
    });

    // This diagnostic mode is intentionally internal: it preserves the graph
    // and all pass bindings while giving every logical workspace resource a
    // distinct allocation. A semantic difference between colored and
    // uncolored runs therefore identifies an incomplete lifetime declaration
    // rather than a shader or scheduling difference.
    let disable_coloring = std::env::var_os("LANIUS_COMPILER_GRAPH_DISABLE_COLORING").is_some();
    let mut slots = Vec::<SlotState>::new();
    let mut assignment_by_resource = BTreeMap::<usize, u32>::new();
    for (resource_index, resource, lifetime) in order {
        // Retained outputs cross the graph boundary and may be consumed by a
        // recorder stage that is intentionally outside this graph. Until a
        // caller imports that downstream schedule explicitly, treating an
        // output like phase-local scratch would let it reuse storage based on
        // an incomplete lifetime. Resident state and retained outputs therefore
        // both receive stable physical identities; Workspace remains colorable.
        let dedicated = matches!(
            resource.class,
            ResourceClass::Resident | ResourceClass::Output
        );
        let reusable = (!disable_coloring && !dedicated)
            .then(|| {
                slots
                    .iter()
                    .enumerate()
                    .filter(|(_, slot)| {
                        !slot.dedicated
                            && slot.plan.usage == resource.usage
                            && slot.lifetimes.iter().all(|other| {
                                lifetime.last_pass < other.first_pass
                                    || other.last_pass < lifetime.first_pass
                            })
                    })
                    .min_by_key(|(_, slot)| {
                        (
                            std::cmp::Reverse(slot.plan.bytes),
                            slot.lifetimes.len(),
                            slot.plan.slot,
                        )
                    })
                    .map(|(index, _)| index)
            })
            .flatten();
        let slot_index = reusable.unwrap_or_else(|| {
            let index = slots.len();
            slots.push(SlotState {
                plan: WorkspaceSlotPlan {
                    slot: index as u32,
                    bytes: resource.bytes,
                    usage: resource.usage,
                },
                dedicated,
                lifetimes: Vec::new(),
            });
            index
        });
        let slot = &mut slots[slot_index];
        slot.plan.bytes = slot.plan.bytes.max(resource.bytes);
        slot.lifetimes.push(lifetime);
        assignment_by_resource.insert(resource_index, slot.plan.slot);
    }

    let plan = WorkspacePlan {
        assignments: resources
            .iter()
            .enumerate()
            .filter_map(|(index, resource)| {
                assignment_by_resource
                    .get(&index)
                    .copied()
                    .map(|slot| WorkspaceAssignment {
                        name: resource.name,
                        slot,
                    })
            })
            .collect(),
        slots: slots.into_iter().map(|slot| slot.plan).collect(),
    };
    if std::env::var_os("LANIUS_COMPILER_GRAPH_DUMP_SLOTS").is_some() {
        for assignment in &plan.assignments {
            let resource_index = resources
                .iter()
                .position(|resource| resource.name == assignment.name)
                .expect("workspace assignment resource");
            let lifetime = lifetimes[resource_index].expect("workspace resource lifetime");
            eprintln!(
                "compiler_graph_slot slot={} index={} resource={} bytes={} usage={:?} class={:?} first={} last={}",
                assignment.slot,
                resource_index,
                assignment.name,
                resources[resource_index].bytes,
                resources[resource_index].usage,
                resources[resource_index].class,
                lifetime.first_pass.index(),
                lifetime.last_pass.index(),
            );
        }
    }
    Ok(plan)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn diagnostic_dependencies_come_from_resource_hazards_not_pass_sequence() {
        let mut builder = CompilerGraphBuilder::new();
        let input = builder
            .add_resource(ResourceDesc {
                name: "input",
                domain: ResourceDomain::Tokens,
                class: ResourceClass::Input,
                bytes: 16,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let scratch = builder
            .add_resource(ResourceDesc {
                name: "scratch",
                domain: ResourceDomain::Types,
                class: ResourceClass::Workspace,
                bytes: 16,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        for (name, accesses) in [
            ("produce", vec![PassAccess::write("scratch", scratch)]),
            ("independent", vec![PassAccess::read("input", input)]),
            ("consume", vec![PassAccess::read("scratch", scratch)]),
            ("reuse", vec![PassAccess::write("scratch", scratch)]),
        ] {
            builder
                .add_pass(PassDesc {
                    name,
                    phase: CompilerPhase::TypeCheck,
                    dispatch_domain: ResourceDomain::Types,
                    accesses,
                })
                .unwrap();
        }
        let diagnostic = builder.build().unwrap().diagnostic("test");
        let edges = diagnostic
            .edges
            .iter()
            .map(|edge| (edge.source, edge.target))
            .collect::<BTreeSet<_>>();

        assert_eq!(edges, BTreeSet::from([(0, 2), (0, 3), (2, 3)]));
        assert!(diagnostic.edges.iter().all(|edge| {
            edge.dependencies
                .iter()
                .all(|dependency| dependency.resource == "scratch")
        }));
    }

    #[test]
    fn upstream_storage_recovers_one_whole_dead_physical_allocation() {
        let device = &crate::gpu::device::global().device;
        let buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("compiler_graph.physical_upstream_identity"),
            size: 256,
            usage: wgpu::BufferUsages::STORAGE,
            mapped_at_creation: false,
        });
        let views = [
            TrackedBufferView::from_parts(&buffer, 0, 64, Some(1)),
            TrackedBufferView::from_parts(&buffer, 64, 128, Some(2)),
        ];

        let unique = unique_physical_upstream_views(&views);
        assert_eq!(unique.len(), 1);
        assert_eq!(unique[0].byte_offset, 0);
        assert_eq!(unique[0].byte_size, 256);
    }

    #[test]
    fn upstream_storage_packs_multiple_consumer_slots_into_disjoint_ranges() {
        let placements = pack_slots_into_upstream_storage(
            &[0, 1, 2],
            &[400, 300, 200],
            &[1024],
            64,
            &BTreeSet::new(),
            &BTreeSet::new(),
        );

        assert_eq!(
            placements,
            vec![
                UpstreamSlotPlacement {
                    slot_index: 0,
                    upstream_index: 0,
                    byte_offset: 0,
                },
                UpstreamSlotPlacement {
                    slot_index: 1,
                    upstream_index: 0,
                    byte_offset: 448,
                },
                UpstreamSlotPlacement {
                    slot_index: 2,
                    upstream_index: 0,
                    byte_offset: 768,
                },
            ]
        );
    }

    #[test]
    fn upstream_storage_leaves_slots_unplaced_when_aligned_ranges_do_not_fit() {
        let placements = pack_slots_into_upstream_storage(
            &[0, 1],
            &[129, 128],
            &[256],
            128,
            &BTreeSet::new(),
            &BTreeSet::new(),
        );

        assert_eq!(
            placements,
            vec![UpstreamSlotPlacement {
                slot_index: 0,
                upstream_index: 0,
                byte_offset: 0,
            }]
        );
    }

    #[test]
    fn upstream_storage_separates_slots_used_by_the_same_pass() {
        let placements = pack_slots_into_upstream_storage(
            &[4, 9],
            &[128, 128],
            &[512, 512],
            64,
            &BTreeSet::from([(4, 9)]),
            &BTreeSet::new(),
        );

        assert_eq!(placements.len(), 2);
        assert_ne!(placements[0].upstream_index, placements[1].upstream_index);
    }

    #[test]
    fn upstream_storage_gives_dedicated_slots_exclusive_physical_buffers() {
        let placements = pack_slots_into_upstream_storage(
            &[4, 9, 12],
            &[128, 128, 128],
            &[512, 512, 512],
            64,
            &BTreeSet::new(),
            &BTreeSet::from([4, 12]),
        );

        assert_eq!(placements.len(), 3);
        assert_eq!(placements[0].slot_index, 0);
        assert_eq!(placements[1].slot_index, 1);
        assert_eq!(placements[2].slot_index, 2);
        assert_ne!(placements[0].upstream_index, placements[1].upstream_index);
        assert_ne!(placements[0].upstream_index, placements[2].upstream_index);
        assert_ne!(placements[1].upstream_index, placements[2].upstream_index);
    }

    #[test]
    fn upstream_storage_places_exclusive_slots_before_flexible_slots() {
        let placements = pack_slots_into_upstream_storage(
            &[0, 1, 2],
            &[128, 128, 128],
            &[256, 128],
            64,
            &BTreeSet::new(),
            &BTreeSet::from([2]),
        );

        assert_eq!(placements.len(), 3);
        let exclusive_upstream = placements[2].upstream_index;
        assert!(
            placements[..2]
                .iter()
                .all(|placement| placement.upstream_index != exclusive_upstream)
        );
        assert_eq!(placements[0].upstream_index, placements[1].upstream_index);
    }

    #[test]
    fn retained_output_slots_do_not_share_an_arena_with_phase_scratch() {
        let mut builder = CompilerGraphBuilder::new();
        let scratch = builder
            .add_storage(
                "scratch",
                ResourceDomain::HirNodes,
                ResourceClass::Workspace,
                128,
            )
            .unwrap();
        let output = builder
            .add_storage(
                "output",
                ResourceDomain::HirNodes,
                ResourceClass::Output,
                128,
            )
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "produce.scratch",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![PassAccess::write("scratch", scratch)],
            })
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "produce.output",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![PassAccess::write("output", output)],
            })
            .unwrap();
        let graph = builder.build().unwrap();
        let scratch_slot = graph
            .workspace_plan()
            .assignments
            .iter()
            .find(|assignment| assignment.name == "scratch")
            .unwrap()
            .slot;
        let output_slot = graph
            .workspace_plan()
            .assignments
            .iter()
            .find(|assignment| assignment.name == "output")
            .unwrap()
            .slot;
        let conflicts = graph.workspace_arena_conflicts();
        assert!(
            conflicts.contains(&(scratch_slot.min(output_slot), scratch_slot.max(output_slot),))
        );

        let placements = pack_slots_into_upstream_storage(
            &[scratch_slot, output_slot],
            &[128, 128],
            &[512, 512],
            64,
            &conflicts,
            &BTreeSet::new(),
        );
        assert_eq!(placements.len(), 2);
        assert_ne!(placements[0].upstream_index, placements[1].upstream_index);
    }

    fn workspace(name: &'static str, domain: ResourceDomain, bytes: u64) -> ResourceDesc {
        ResourceDesc {
            name,
            domain,
            class: ResourceClass::Workspace,
            bytes,
            usage: WorkspaceUsageClass::Storage,
        }
    }

    #[test]
    fn mutable_external_resources_are_tracked_but_not_allocated() {
        let mut builder = CompilerGraphBuilder::new();
        let external = builder
            .add_resource(ResourceDesc {
                name: "upstream.semantic_state",
                domain: ResourceDomain::HirNodes,
                class: ResourceClass::External,
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let scratch = builder
            .add_resource(workspace("local.scratch", ResourceDomain::HirNodes, 64))
            .unwrap();
        let pass = builder
            .add_pass(PassDesc {
                name: "compose.external",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read_write("semantic_state", external),
                    PassAccess::write("scratch", scratch),
                ],
            })
            .unwrap();
        let graph = builder.build().unwrap();

        assert_eq!(graph.workspace_plan().slots.len(), 1);
        assert!(
            graph
                .workspace_plan()
                .assignments
                .iter()
                .all(|assignment| assignment.name != "upstream.semantic_state")
        );
        graph
            .validate_pass_bindings(
                pass,
                &[
                    BoundGraphResource::whole("semantic_state", external, 11, 4),
                    BoundGraphResource::whole("scratch", scratch, 12, 64),
                ],
            )
            .unwrap();
    }

    #[test]
    fn graph_derives_ownership_and_aliases_non_overlapping_resources() {
        let mut builder = CompilerGraphBuilder::new();
        let raw = builder
            .add_resource(workspace("raw", ResourceDomain::RawNodes, 64))
            .unwrap();
        let hir = builder
            .add_resource(workspace("hir", ResourceDomain::HirNodes, 96))
            .unwrap();
        let raw_pass = builder
            .add_pass(PassDesc {
                name: "raw.write",
                phase: CompilerPhase::Parse,
                dispatch_domain: ResourceDomain::RawNodes,
                accesses: vec![PassAccess::write("raw", raw)],
            })
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "raw.read",
                phase: CompilerPhase::Parse,
                dispatch_domain: ResourceDomain::RawNodes,
                accesses: vec![PassAccess::read("raw", raw)],
            })
            .unwrap();
        let hir_pass = builder
            .add_pass(PassDesc {
                name: "hir.write",
                phase: CompilerPhase::Hir,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![PassAccess::write("hir", hir)],
            })
            .unwrap();
        let graph = builder.build().unwrap();

        assert_eq!(graph.lifetime(raw).unwrap().producer, Some(raw_pass));
        assert_eq!(graph.lifetime(hir).unwrap().producer, Some(hir_pass));
        assert_eq!(graph.workspace_plan().slots.len(), 1);
        assert_eq!(graph.workspace_plan().slots[0].bytes, 96);
    }

    #[test]
    fn removing_workspace_interval_does_not_fragment_later_slots() {
        const ROWS: [(&str, usize, usize, u64); 6] = [
            ("long_small_a", 1, 4, 20),
            ("long_small_b", 2, 4, 20),
            ("middle_large", 2, 3, 100),
            ("late_large", 4, 4, 100),
            ("late_medium", 3, 4, 40),
            ("early_medium", 0, 1, 40),
        ];
        const PASSES: [&str; 5] = ["p0", "p1", "p2", "p3", "p4"];

        fn build_without(excluded: Option<&str>) -> CompilerGraph {
            let mut builder = CompilerGraphBuilder::new();
            let resources = ROWS
                .iter()
                .filter(|(name, _, _, _)| Some(*name) != excluded)
                .map(|&(name, first, last, bytes)| {
                    let resource = builder
                        .add_resource(workspace(name, ResourceDomain::DispatchArguments, bytes))
                        .unwrap();
                    (name, first, last, resource)
                })
                .collect::<Vec<_>>();
            for (pass_index, &name) in PASSES.iter().enumerate() {
                let accesses = resources
                    .iter()
                    .filter_map(|&(binding, first, last, resource)| {
                        if first == pass_index {
                            Some(PassAccess::write(binding, resource))
                        } else if last == pass_index {
                            Some(PassAccess::read(binding, resource))
                        } else {
                            None
                        }
                    })
                    .collect();
                builder
                    .add_pass(PassDesc {
                        name,
                        phase: CompilerPhase::SemanticLowering,
                        dispatch_domain: ResourceDomain::DispatchArguments,
                        accesses,
                    })
                    .unwrap();
            }
            builder.build().unwrap()
        }

        let full = build_without(None);
        let reduced = build_without(Some("middle_large"));
        assert_eq!(full.workspace_bytes(), 180);
        assert_eq!(reduced.workspace_bytes(), 180);
    }

    #[test]
    fn retained_stage_output_cannot_alias_later_scratch() {
        let mut builder = CompilerGraphBuilder::new();
        let output = builder
            .add_resource(workspace("stage.output", ResourceDomain::Types, 64))
            .unwrap();
        let scratch = builder
            .add_resource(workspace("later.scratch", ResourceDomain::Types, 64))
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "stage.write",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::write("output", output)],
            })
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "later.write",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::write("scratch", scratch)],
            })
            .unwrap();
        builder.retain_outputs(&["stage.output"]).unwrap();

        let graph = builder.build().unwrap();
        assert_eq!(graph.resource(output).unwrap().class, ResourceClass::Output);
        assert_eq!(graph.workspace_plan().slots.len(), 2);
        let layout = graph
            .workspace_arena_layout(&wgpu::Limits::default())
            .unwrap();
        let arena = |resource| {
            let slot = graph
                .workspace_plan()
                .assignments
                .iter()
                .find(|assignment| assignment.name == resource)
                .unwrap()
                .slot;
            layout
                .placements
                .iter()
                .find(|placement| placement.slot == slot)
                .unwrap()
                .arena
        };
        assert_ne!(arena("stage.output"), arena("later.scratch"));
    }

    #[test]
    fn retained_outputs_use_disjoint_ranges_of_one_physical_arena() {
        let mut builder = CompilerGraphBuilder::new();
        let left = builder
            .add_resource(workspace("stage.left", ResourceDomain::Types, 64))
            .unwrap();
        let right = builder
            .add_resource(workspace("stage.right", ResourceDomain::Types, 96))
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "stage.write_left",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::write("left", left)],
            })
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "stage.write_right",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::write("right", right)],
            })
            .unwrap();
        builder
            .retain_outputs(&["stage.left", "stage.right"])
            .unwrap();

        let graph = builder.build().unwrap();
        let layout = graph
            .workspace_arena_layout(&wgpu::Limits::default())
            .unwrap();
        let placement = |resource| {
            let slot = graph
                .workspace_plan()
                .assignments
                .iter()
                .find(|assignment| assignment.name == resource)
                .unwrap()
                .slot;
            layout
                .placements
                .iter()
                .find(|placement| placement.slot == slot)
                .unwrap()
        };
        let left = placement("stage.left");
        let right = placement("stage.right");
        assert_eq!(left.arena, right.arena);
        assert!(
            left.byte_offset + left.byte_size <= right.byte_offset
                || right.byte_offset + right.byte_size <= left.byte_offset
        );
    }

    #[test]
    fn logical_resource_alias_preserves_one_ownership_identity() {
        let mut builder = CompilerGraphBuilder::new();
        let scratch = builder
            .add_resource(workspace("radix.scratch", ResourceDomain::Declarations, 64))
            .unwrap();
        builder
            .add_resource_alias("generic_params.radix.scratch", scratch)
            .unwrap();
        assert_eq!(
            builder.resource_id("generic_params.radix.scratch"),
            Some(scratch)
        );
        builder
            .add_pass(PassDesc {
                name: "radix.write",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Declarations,
                accesses: vec![PassAccess::write("scratch", scratch)],
            })
            .unwrap();
        let graph = builder.build().unwrap();
        assert_eq!(
            graph.resource_id("generic_params.radix.scratch"),
            Some(scratch)
        );
    }

    #[test]
    fn lifetime_fence_prevents_aliasing_across_omitted_execution_passes() {
        let mut builder = CompilerGraphBuilder::new();
        let carried = builder
            .add_resource(workspace("carried", ResourceDomain::Types, 64))
            .unwrap();
        let late = builder
            .add_resource(workspace("late", ResourceDomain::Types, 64))
            .unwrap();
        let begin = builder
            .add_pass(PassDesc {
                name: "schedule.begin",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::write("carried", carried)],
            })
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "schedule.middle",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![],
            })
            .unwrap();
        let end = builder
            .add_pass(PassDesc {
                name: "schedule.end",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::write("late", late)],
            })
            .unwrap();
        builder
            .fence_resource_lifetime(carried, "schedule.begin", "schedule.end")
            .unwrap();
        let graph = builder.build().unwrap();

        assert_eq!(graph.lifetime(carried).unwrap().first_pass, begin);
        assert_eq!(graph.lifetime(carried).unwrap().last_pass, end);
        assert_eq!(graph.workspace_plan().slots.len(), 2);
        assert_eq!(graph.lifetime_fences().len(), 1);
    }

    #[test]
    fn lifetime_fence_rejects_reversed_execution_interval() {
        let mut builder = CompilerGraphBuilder::new();
        let carried = builder
            .add_resource(workspace("carried", ResourceDomain::Types, 64))
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "first",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::write("carried", carried)],
            })
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "last",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![],
            })
            .unwrap();
        builder
            .fence_resource_lifetime(carried, "last", "first")
            .unwrap();

        let error = builder.build().unwrap_err();
        assert!(error.contains("is reversed"), "{error}");
    }

    #[test]
    fn operation_resource_fence_extends_every_selected_pass_resource() {
        let mut builder = CompilerGraphBuilder::new();
        let first = builder
            .add_resource(workspace("first_resource", ResourceDomain::Types, 64))
            .unwrap();
        let second = builder
            .add_resource(workspace("second_resource", ResourceDomain::Types, 64))
            .unwrap();
        let begin = builder
            .add_pass(PassDesc {
                name: "operation.begin",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::write("first_resource", first)],
            })
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "operation.consume",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![
                    PassAccess::read("first_resource", first),
                    PassAccess::write("second_resource", second),
                ],
            })
            .unwrap();
        let end = builder
            .add_pass(PassDesc {
                name: "operation.interval_end",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![],
            })
            .unwrap();
        builder
            .fence_resources_accessed_by_passes(
                &["operation.begin", "operation.consume"],
                "operation.begin",
                "operation.interval_end",
            )
            .unwrap();

        let graph = builder.build().unwrap();
        assert_eq!(graph.lifetime(first).unwrap().first_pass, begin);
        assert_eq!(graph.lifetime(first).unwrap().last_pass, end);
        assert_eq!(graph.lifetime(second).unwrap().first_pass, begin);
        assert_eq!(graph.lifetime(second).unwrap().last_pass, end);
        assert_eq!(graph.workspace_plan().slots.len(), 2);
    }

    #[test]
    fn resident_resource_is_dedicated_without_suppressing_complete_workspace_coloring() {
        let mut builder = CompilerGraphBuilder::new();
        let early = builder
            .add_resource(workspace("early", ResourceDomain::Types, 64))
            .unwrap();
        let resident = builder
            .add_resource(ResourceDesc {
                name: "resident",
                domain: ResourceDomain::Types,
                class: ResourceClass::Resident,
                bytes: 32,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let late = builder
            .add_resource(workspace("late", ResourceDomain::Types, 16))
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "early.write",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::write("early", early)],
            })
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "resident.write",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::write("resident", resident)],
            })
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "late.write",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::write("late", late)],
            })
            .unwrap();
        let graph = builder.build().unwrap();
        let slot = |name| {
            graph
                .workspace_plan()
                .assignments
                .iter()
                .find(|assignment| assignment.name == name)
                .unwrap()
                .slot
        };
        assert_ne!(slot("early"), slot("resident"));
        assert_ne!(slot("resident"), slot("late"));
        assert_eq!(slot("early"), slot("late"));
    }

    #[test]
    fn indirect_slots_never_share_a_physical_arena_with_storage() {
        let mut builder = CompilerGraphBuilder::new();
        let dispatch = builder
            .add_resource(ResourceDesc {
                name: "dispatch",
                domain: ResourceDomain::DispatchArguments,
                class: ResourceClass::Workspace,
                bytes: 12,
                usage: WorkspaceUsageClass::StorageIndirect,
            })
            .unwrap();
        let storage = builder
            .add_resource(workspace("storage", ResourceDomain::Types, 64))
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "dispatch.write",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::DispatchArguments,
                accesses: vec![PassAccess::write("dispatch", dispatch)],
            })
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "storage.write",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::write("storage", storage)],
            })
            .unwrap();
        let graph = builder.build().unwrap();
        let slot = |name| {
            graph
                .workspace_plan()
                .assignments
                .iter()
                .find(|assignment| assignment.name == name)
                .unwrap()
                .slot
        };
        let pair = (
            slot("dispatch").min(slot("storage")),
            slot("dispatch").max(slot("storage")),
        );
        assert!(graph.workspace_arena_conflicts().contains(&pair));
    }

    #[test]
    fn resident_clear_is_a_physical_job_boundary_not_a_workspace_producer() {
        let mut builder = CompilerGraphBuilder::new();
        let resident = builder
            .add_resource(ResourceDesc {
                name: "resident",
                domain: ResourceDomain::Types,
                class: ResourceClass::Resident,
                bytes: 32,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        builder
            .add_resident_clear_pass("job.clear", CompilerPhase::TypeCheck)
            .unwrap();
        let graph = builder.build().unwrap();
        assert_eq!(
            graph.lifetime(resident).unwrap().producer,
            graph.pass_id("job.clear")
        );

        let mut incomplete = CompilerGraphBuilder::new();
        incomplete
            .add_resource(workspace("temporary", ResourceDomain::Types, 32))
            .unwrap();
        incomplete
            .add_resident_clear_pass("job.clear", CompilerPhase::TypeCheck)
            .unwrap();
        assert_eq!(
            incomplete.build().unwrap_err(),
            "compiler resource temporary has no producing pass",
        );
    }

    #[test]
    fn graph_keeps_simultaneously_accessed_resources_in_distinct_slots() {
        let mut builder = CompilerGraphBuilder::new();
        let left = builder
            .add_resource(workspace("left", ResourceDomain::HirNodes, 64))
            .unwrap();
        let right = builder
            .add_resource(workspace("right", ResourceDomain::HirNodes, 64))
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "pair.write",
                phase: CompilerPhase::Hir,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::write("left", left),
                    PassAccess::write("right", right),
                ],
            })
            .unwrap();
        let graph = builder.build().unwrap();
        assert_eq!(graph.workspace_plan().slots.len(), 2);
    }

    #[test]
    fn repeated_region_is_explicit_and_extends_body_liveness() {
        let mut builder = CompilerGraphBuilder::new();
        let early = builder
            .add_resource(workspace("loop.early", ResourceDomain::Types, 64))
            .unwrap();
        let late = builder
            .add_resource(workspace("loop.late", ResourceDomain::Types, 64))
            .unwrap();
        let ids = builder
            .add_repeated_region(
                8,
                vec![
                    PassDesc {
                        name: "loop.early.write",
                        phase: CompilerPhase::TypeCheck,
                        dispatch_domain: ResourceDomain::Types,
                        accesses: vec![PassAccess::write("early", early)],
                    },
                    PassDesc {
                        name: "loop.late.write",
                        phase: CompilerPhase::TypeCheck,
                        dispatch_domain: ResourceDomain::Types,
                        accesses: vec![PassAccess::write("late", late)],
                    },
                ],
            )
            .unwrap();
        let graph = builder.build().unwrap();
        assert_eq!(
            graph.repeated_regions(),
            &[RepeatedPassRegion {
                first_pass: ids[0],
                pass_count: 2,
                iterations: 8,
            }]
        );
        assert_eq!(graph.lifetime(early).unwrap().last_pass, ids[1]);
        assert_eq!(graph.lifetime(late).unwrap().first_pass, ids[0]);
    }

    #[test]
    fn radix_sort_adds_its_internal_passes_and_accesses() {
        let mut builder = CompilerGraphBuilder::new();
        let count = builder
            .add_resource(ResourceDesc {
                name: "sort.count",
                domain: ResourceDomain::Declarations,
                class: ResourceClass::Input,
                bytes: 4,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let key = builder
            .add_resource(ResourceDesc {
                name: "sort.key",
                domain: ResourceDomain::Declarations,
                class: ResourceClass::Input,
                bytes: 4_096,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let resources = builder
            .add_radix_sort_resources(
                count,
                vec![key],
                ResourceDomain::Declarations,
                1_024,
                256,
                256,
                RadixSortGraphResourceNames {
                    order: "sort.order",
                    temporary_order: "sort.temporary_order",
                    dispatch_args: "sort.dispatch_args",
                    histogram: "sort.histogram",
                    bucket_prefix: "sort.bucket_prefix",
                    bucket_total: "sort.bucket_total",
                    bucket_base: "sort.bucket_base",
                },
            )
            .unwrap();
        let order = resources.order;
        let temporary_order = resources.temporary_order;
        builder
            .add_pass(PassDesc {
                name: "sort.initialize",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Declarations,
                accesses: vec![
                    PassAccess::write("sort.order", resources.order),
                    PassAccess::write("sort.dispatch_args", resources.dispatch_args),
                ],
            })
            .unwrap();
        let result = builder
            .add_fragment(RadixSortGraph {
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Declarations,
                digit_steps: 6,
                starts_in_temporary: false,
                schedule: RadixSortGraphPasses {
                    order_to_temporary: RadixSortGraphStepPasses {
                        histogram: "sort.a.histogram",
                        bucket_prefix: "sort.a.prefix",
                        bucket_bases: "sort.a.bases",
                        scatter: "sort.a.scatter",
                    },
                    temporary_to_order: RadixSortGraphStepPasses {
                        histogram: "sort.b.histogram",
                        bucket_prefix: "sort.b.prefix",
                        bucket_bases: "sort.b.bases",
                        scatter: "sort.b.scatter",
                    },
                },
                resources,
            })
            .unwrap();
        assert_eq!(result, order);

        let graph = builder.build().unwrap();
        assert_eq!(graph.resource(order).unwrap().bytes, 4_096);
        assert_eq!(
            graph
                .resource(graph.resource_id("sort.histogram").unwrap())
                .unwrap()
                .bytes,
            4_096,
        );
        assert_eq!(
            graph
                .resource(graph.resource_id("sort.dispatch_args").unwrap())
                .unwrap()
                .usage,
            WorkspaceUsageClass::StorageIndirect,
        );
        assert_eq!(
            graph.repeated_regions(),
            &[RepeatedPassRegion {
                first_pass: graph.pass_id("sort.a.histogram").unwrap(),
                pass_count: 8,
                iterations: 3,
            }]
        );
        let a_scatter = graph
            .pass(graph.pass_id("sort.a.scatter").unwrap())
            .unwrap();
        assert!(
            a_scatter
                .accesses
                .iter()
                .any(|access| { access.resource == order && access.mode == AccessMode::Read })
        );
        assert!(a_scatter.accesses.iter().any(|access| {
            access.resource == temporary_order && access.mode == AccessMode::Write
        }));
        let b_scatter = graph
            .pass(graph.pass_id("sort.b.scatter").unwrap())
            .unwrap();
        assert!(b_scatter.accesses.iter().any(|access| {
            access.resource == temporary_order && access.mode == AccessMode::Read
        }));
        assert!(
            b_scatter
                .accesses
                .iter()
                .any(|access| { access.resource == order && access.mode == AccessMode::Write })
        );
    }

    #[test]
    fn paired_radix_sorts_reject_shared_mutable_storage() {
        let mut builder = CompilerGraphBuilder::new();
        let count = builder
            .add_resource(ResourceDesc {
                name: "pair.count",
                domain: ResourceDomain::Declarations,
                class: ResourceClass::Input,
                bytes: 4,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let key = builder
            .add_resource(ResourceDesc {
                name: "pair.key",
                domain: ResourceDomain::Declarations,
                class: ResourceClass::Input,
                bytes: 4_096,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let resources = builder
            .add_radix_sort_resources(
                count,
                vec![key],
                ResourceDomain::Declarations,
                1_024,
                256,
                256,
                RadixSortGraphResourceNames {
                    order: "pair.order",
                    temporary_order: "pair.temporary_order",
                    dispatch_args: "pair.dispatch_args",
                    histogram: "pair.histogram",
                    bucket_prefix: "pair.bucket_prefix",
                    bucket_total: "pair.bucket_total",
                    bucket_base: "pair.bucket_base",
                },
            )
            .unwrap();
        let passes = |prefix| RadixSortGraphPasses {
            order_to_temporary: RadixSortGraphStepPasses {
                histogram: prefix,
                bucket_prefix: "pair.a.prefix",
                bucket_bases: "pair.a.bases",
                scatter: "pair.a.scatter",
            },
            temporary_to_order: RadixSortGraphStepPasses {
                histogram: "pair.b.histogram",
                bucket_prefix: "pair.b.prefix",
                bucket_bases: "pair.b.bases",
                scatter: "pair.b.scatter",
            },
        };
        let error = builder
            .add_fragment(RadixSortPairGraph {
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Declarations,
                digit_steps: 4,
                left_passes: passes("pair.left.histogram"),
                right_passes: passes("pair.right.histogram"),
                left: resources.clone(),
                right: resources,
            })
            .unwrap_err();
        assert!(error.contains("share mutable resource"), "{error}");
    }

    #[test]
    fn radix_sort_models_an_odd_digit_step_count_as_a_conservative_pair() {
        let mut builder = CompilerGraphBuilder::new();
        let mut add = |name, class| {
            builder
                .add_resource(ResourceDesc {
                    name,
                    domain: ResourceDomain::Declarations,
                    class,
                    bytes: 4,
                    usage: WorkspaceUsageClass::Storage,
                })
                .unwrap()
        };
        let count = add("odd.count", ResourceClass::Input);
        let key = add("odd.key", ResourceClass::Input);
        let order = add("odd.order", ResourceClass::Workspace);
        let temporary_order = add("odd.temporary_order", ResourceClass::Workspace);
        let dispatch_args = add("odd.dispatch_args", ResourceClass::Workspace);
        let histogram = add("odd.histogram", ResourceClass::Workspace);
        let bucket_prefix = add("odd.bucket_prefix", ResourceClass::Workspace);
        let bucket_total = add("odd.bucket_total", ResourceClass::Workspace);
        let bucket_base = add("odd.bucket_base", ResourceClass::Workspace);
        let result = builder
            .add_fragment(RadixSortGraph {
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Declarations,
                digit_steps: 3,
                starts_in_temporary: true,
                schedule: RadixSortGraphPasses {
                    order_to_temporary: RadixSortGraphStepPasses {
                        histogram: "odd.a.histogram",
                        bucket_prefix: "odd.a.prefix",
                        bucket_bases: "odd.a.bases",
                        scatter: "odd.a.scatter",
                    },
                    temporary_to_order: RadixSortGraphStepPasses {
                        histogram: "odd.b.histogram",
                        bucket_prefix: "odd.b.prefix",
                        bucket_bases: "odd.b.bases",
                        scatter: "odd.b.scatter",
                    },
                },
                resources: RadixSortGraphResources {
                    count,
                    count_binding: "odd.count",
                    keys: vec![ReflectedResourceBinding {
                        binding: "odd.key",
                        resource: key,
                        mode: None,
                    }],
                    order,
                    temporary_order,
                    dispatch_args,
                    histogram,
                    bucket_prefix,
                    bucket_total,
                    bucket_base,
                },
            })
            .unwrap();
        assert_eq!(result, order);
        assert_eq!(builder.repeated_regions.len(), 1);
        assert_eq!(builder.repeated_regions[0].iterations, 2);
    }

    #[test]
    fn prefix_scan_adds_hierarchy_state_and_derived_accesses() {
        let mut builder = CompilerGraphBuilder::new();
        let count = builder
            .add_resource(ResourceDesc {
                name: "scan.count",
                domain: ResourceDomain::Declarations,
                class: ResourceClass::Input,
                bytes: 4,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let input = builder
            .add_resource(ResourceDesc {
                name: "scan.input",
                domain: ResourceDomain::Declarations,
                class: ResourceClass::Input,
                bytes: 4096,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let dispatch_args = builder
            .add_resource(ResourceDesc {
                name: "scan.dispatch_args",
                domain: ResourceDomain::DispatchArguments,
                class: ResourceClass::Input,
                bytes: 12,
                usage: WorkspaceUsageClass::StorageIndirect,
            })
            .unwrap();
        let resources = builder
            .add_prefix_scan_resources(
                count,
                input,
                dispatch_args,
                ResourceDomain::Declarations,
                1024,
                256,
                PrefixScanGraphResourceNames {
                    output_prefix: "scan.output",
                    total: "scan.total",
                    local_prefix: "scan.local_prefix",
                    block_sum: "scan.block_sum",
                    block_prefix: "scan.block_prefix",
                    hierarchy: "scan.hierarchy",
                },
            )
            .unwrap();
        let (output, total) = builder
            .add_fragment(PrefixScanGraph {
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Declarations,
                hierarchy_levels: 3,
                passes: PrefixScanGraphPasses {
                    local: "scan.local",
                    hierarchy_up_first: "scan.up.first",
                    hierarchy_up_rest: "scan.up.rest",
                    hierarchy_down: "scan.down",
                    apply: "scan.apply",
                },
                resources,
            })
            .unwrap();
        assert_eq!(output, resources.output_prefix);
        assert_eq!(total, resources.total);

        let graph = builder.build().unwrap();
        assert_eq!(graph.resource(output).unwrap().bytes, 4096);
        assert_eq!(graph.resource(resources.block_sum).unwrap().bytes, 16);
        assert_eq!(
            graph.resource(resources.dispatch_args).unwrap().usage,
            WorkspaceUsageClass::StorageIndirect,
        );
        assert_eq!(
            graph.repeated_regions(),
            &[
                RepeatedPassRegion {
                    first_pass: graph.pass_id("scan.up.rest").unwrap(),
                    pass_count: 1,
                    iterations: 2,
                },
                RepeatedPassRegion {
                    first_pass: graph.pass_id("scan.down").unwrap(),
                    pass_count: 1,
                    iterations: 2,
                },
            ],
        );
        let first_up = graph.pass(graph.pass_id("scan.up.first").unwrap()).unwrap();
        assert!(first_up.accesses.iter().any(|access| {
            access.resource == resources.hierarchy && access.mode == AccessMode::Write
        }));
        let later_up = graph.pass(graph.pass_id("scan.up.rest").unwrap()).unwrap();
        assert!(later_up.accesses.iter().any(|access| {
            access.resource == resources.hierarchy && access.mode == AccessMode::ReadWrite
        }));
    }

    #[test]
    fn paired_prefix_scan_shares_only_read_only_resources() {
        let mut builder = CompilerGraphBuilder::new();
        let mut add_input = |name, bytes, usage| {
            builder
                .add_resource(ResourceDesc {
                    name,
                    domain: ResourceDomain::Declarations,
                    class: ResourceClass::Input,
                    bytes,
                    usage,
                })
                .unwrap()
        };
        let count = add_input("pair.count", 4, WorkspaceUsageClass::Storage);
        let left_input = add_input("pair.left.input", 4096, WorkspaceUsageClass::Storage);
        let right_input = add_input("pair.right.input", 4096, WorkspaceUsageClass::Storage);
        let dispatch_args = add_input("pair.dispatch", 12, WorkspaceUsageClass::StorageIndirect);
        let left = builder
            .add_prefix_scan_resources(
                count,
                left_input,
                dispatch_args,
                ResourceDomain::Declarations,
                1024,
                256,
                PrefixScanGraphResourceNames {
                    output_prefix: "pair.left.output",
                    total: "pair.left.total",
                    local_prefix: "pair.left.local",
                    block_sum: "pair.left.sum",
                    block_prefix: "pair.left.prefix",
                    hierarchy: "pair.left.hierarchy",
                },
            )
            .unwrap();
        let right = builder
            .add_prefix_scan_resources(
                count,
                right_input,
                dispatch_args,
                ResourceDomain::Declarations,
                1024,
                256,
                PrefixScanGraphResourceNames {
                    output_prefix: "pair.right.output",
                    total: "pair.right.total",
                    local_prefix: "pair.right.local",
                    block_sum: "pair.right.sum",
                    block_prefix: "pair.right.prefix",
                    hierarchy: "pair.right.hierarchy",
                },
            )
            .unwrap();
        builder
            .add_fragment(PrefixScanPairGraph {
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Declarations,
                hierarchy_levels: 2,
                passes: PrefixScanGraphPasses {
                    local: "pair.local",
                    hierarchy_up_first: "pair.up.first",
                    hierarchy_up_rest: "pair.up.rest",
                    hierarchy_down: "pair.down",
                    apply: "pair.apply",
                },
                left,
                right,
            })
            .unwrap();
        let graph = builder.build().unwrap();
        let local = graph.pass(graph.pass_id("pair.local").unwrap()).unwrap();
        assert_eq!(
            local
                .accesses
                .iter()
                .filter(|access| access.resource == count)
                .count(),
            2,
        );
        assert_eq!(
            local
                .accesses
                .iter()
                .filter(|access| access.resource == count)
                .map(|access| access.invocation)
                .collect::<BTreeSet<_>>(),
            BTreeSet::from([0, 1]),
        );
        let slot = |resource| {
            let name = graph.resource(resource).unwrap().name;
            graph
                .workspace_plan()
                .assignments
                .iter()
                .find(|assignment| assignment.name == name)
                .unwrap()
                .slot
        };
        assert_ne!(slot(left.local_prefix), slot(right.local_prefix));
        assert_ne!(slot(left.block_sum), slot(right.block_sum));
        assert_ne!(slot(left.block_prefix), slot(right.block_prefix));
        assert_ne!(slot(left.hierarchy), slot(right.hierarchy));
    }

    #[test]
    fn prefix_scan_rejects_an_empty_hierarchy() {
        let mut builder = CompilerGraphBuilder::new();
        let mut add = |name, class| {
            builder
                .add_resource(ResourceDesc {
                    name,
                    domain: ResourceDomain::Declarations,
                    class,
                    bytes: 4,
                    usage: WorkspaceUsageClass::Storage,
                })
                .unwrap()
        };
        let resources = PrefixScanGraphResources {
            count: add("empty.count", ResourceClass::Input),
            input: add("empty.input", ResourceClass::Input),
            output_prefix: add("empty.output", ResourceClass::Workspace),
            total: add("empty.total", ResourceClass::Workspace),
            dispatch_args: add("empty.dispatch", ResourceClass::Workspace),
            local_prefix: add("empty.local", ResourceClass::Workspace),
            block_sum: add("empty.sum", ResourceClass::Workspace),
            block_prefix: add("empty.prefix", ResourceClass::Workspace),
            hierarchy: add("empty.hierarchy", ResourceClass::Workspace),
        };
        let error = builder
            .add_fragment(PrefixScanGraph {
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Declarations,
                hierarchy_levels: 0,
                passes: PrefixScanGraphPasses {
                    local: "empty.local.pass",
                    hierarchy_up_first: "empty.up.first",
                    hierarchy_up_rest: "empty.up.rest",
                    hierarchy_down: "empty.down",
                    apply: "empty.apply",
                },
                resources,
            })
            .unwrap_err();
        assert!(error.contains("at least one hierarchy level"));
    }

    #[test]
    fn graph_rejects_read_before_producer() {
        let mut builder = CompilerGraphBuilder::new();
        let value = builder
            .add_resource(workspace("value", ResourceDomain::Types, 4))
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "bad.read",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::read("value", value)],
            })
            .unwrap();
        assert!(
            builder
                .build()
                .unwrap_err()
                .contains("before it is initialized")
        );
    }

    #[test]
    fn graph_accepts_a_pass_that_initializes_before_reading() {
        let mut builder = CompilerGraphBuilder::new();
        let value = builder
            .add_resource(workspace("value", ResourceDomain::Types, 4))
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "initialize_then_read",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::initialize_read_write("value", value)],
            })
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "read_after_initialization",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Types,
                accesses: vec![PassAccess::read("value", value)],
            })
            .unwrap();
        builder.build().unwrap();
    }

    #[test]
    fn graph_rejects_second_artifact_producer() {
        let mut builder = CompilerGraphBuilder::new();
        let artifact = builder
            .add_resource(ResourceDesc {
                name: "semantic.types",
                domain: ResourceDomain::Types,
                class: ResourceClass::Artifact,
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        for name in ["types.first", "types.second"] {
            builder
                .add_pass(PassDesc {
                    name,
                    phase: CompilerPhase::TypeCheck,
                    dispatch_domain: ResourceDomain::HirNodes,
                    accesses: vec![PassAccess::write("semantic_types", artifact)],
                })
                .unwrap();
        }
        assert!(
            builder
                .build()
                .unwrap_err()
                .contains("more than one producer")
        );
    }

    fn reflected_storage(name: &str, writable: bool) -> ParameterReflection {
        ParameterReflection {
            name: name.to_owned(),
            binding: crate::reflection::BindingInfo {
                kind: "descriptorTableSlot".to_owned(),
                index: Some(0),
                offset: None,
                size: None,
            },
            ty: crate::reflection::TypeLayout {
                kind: Some("resource".to_owned()),
                base_shape: Some("structuredBuffer".to_owned()),
                access: writable.then(|| "readWrite".to_owned()),
                ..Default::default()
            },
            user_attribs: Vec::new(),
        }
    }

    #[test]
    fn reflected_pass_requires_the_complete_storage_surface() {
        let reflection = SlangReflection {
            parameters: vec![
                reflected_storage("hir_core", false),
                reflected_storage("semantic_out", true),
            ],
            ..Default::default()
        };
        let mut builder = CompilerGraphBuilder::new();
        let input = builder
            .add_resource(ResourceDesc {
                name: "hir.core",
                domain: ResourceDomain::HirNodes,
                class: ResourceClass::Input,
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let output = builder
            .add_resource(workspace("semantic.out", ResourceDomain::HirNodes, 64))
            .unwrap();
        builder
            .add_reflected_compute_pass(
                "semantic.project",
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                &reflection,
                &[
                    ReflectedResourceBinding {
                        binding: "hir_core",
                        resource: input,
                        mode: None,
                    },
                    ReflectedResourceBinding {
                        binding: "semantic_out",
                        resource: output,
                        mode: Some(AccessMode::Write),
                    },
                ],
            )
            .unwrap();
        builder.build().unwrap();

        let mut missing = CompilerGraphBuilder::new();
        let input = missing
            .add_resource(ResourceDesc {
                name: "hir.core",
                domain: ResourceDomain::HirNodes,
                class: ResourceClass::Input,
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        assert!(
            missing
                .add_reflected_compute_pass(
                    "semantic.incomplete",
                    CompilerPhase::TypeCheck,
                    ResourceDomain::HirNodes,
                    &reflection,
                    &[ReflectedResourceBinding {
                        binding: "hir_core",
                        resource: input,
                        mode: None,
                    }],
                )
                .unwrap_err()
                .contains("omits reflected storage binding semantic_out")
        );
    }

    #[test]
    fn reflected_pass_matches_same_named_resources_and_only_requires_alias_overrides() {
        let reflection = SlangReflection {
            parameters: vec![
                reflected_storage("compact_hir_core", false),
                reflected_storage("semantic_out", true),
            ],
            ..Default::default()
        };
        let mut builder = CompilerGraphBuilder::new();
        builder
            .add_resource(ResourceDesc {
                name: "compact_hir_core",
                domain: ResourceDomain::HirNodes,
                class: ResourceClass::Input,
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let output = builder
            .add_resource(workspace("semantic.rows", ResourceDomain::HirNodes, 64))
            .unwrap();
        let pass = builder
            .add_reflected_compute_pass_by_name(
                "semantic.project.by_name",
                CompilerPhase::TypeCheck,
                ResourceDomain::HirNodes,
                &reflection,
                &[ReflectedResourceBinding {
                    binding: "semantic_out",
                    resource: output,
                    mode: Some(AccessMode::Write),
                }],
            )
            .unwrap();
        let graph = builder.build().unwrap();
        let accesses = &graph.pass(pass).unwrap().accesses;
        assert_eq!(accesses.len(), 2);
        assert_eq!(accesses[0].binding, "compact_hir_core");
        assert_eq!(accesses[1].resource, output);
        assert_eq!(accesses[1].mode, AccessMode::Write);
    }

    #[test]
    fn reflected_compute_spec_is_the_graph_access_contract() {
        let reflection = SlangReflection {
            parameters: vec![
                reflected_storage("compact_hir_core", false),
                reflected_storage("semantic_out", true),
            ],
            ..Default::default()
        };
        let mut builder = CompilerGraphBuilder::new();
        builder
            .add_storage(
                "compact_hir_core",
                ResourceDomain::HirNodes,
                ResourceClass::Input,
                64,
            )
            .unwrap();
        builder
            .add_storage(
                "semantic.rows",
                ResourceDomain::HirNodes,
                ResourceClass::Workspace,
                64,
            )
            .unwrap();
        let spec = ReflectedComputeSpec::new(
            "semantic.project.spec",
            "test/semantic/project",
            CompilerPhase::SemanticLowering,
            ResourceDomain::HirNodes,
        )
        .with_aliases(&[ReflectedResourceAlias {
            binding: "semantic_out",
            resource: "semantic.rows",
            mode: Some(AccessMode::Write),
        }]);
        let pass = spec.register_reflection(&mut builder, &reflection).unwrap();
        let graph = builder.build().unwrap();

        assert_eq!(graph.pass(pass).unwrap().name, spec.name);
        assert_eq!(graph.pass(pass).unwrap().accesses[0].mode, AccessMode::Read);
        assert_eq!(
            graph.pass(pass).unwrap().accesses[1].mode,
            AccessMode::Write
        );
        assert_eq!(graph.pass_kernel(pass), Some("test/semantic/project"));
    }

    #[test]
    fn graph_checks_declared_access_against_slang_reflection() {
        let mut builder = CompilerGraphBuilder::new();
        let input = builder
            .add_resource(ResourceDesc {
                name: "hir.core",
                domain: ResourceDomain::HirNodes,
                class: ResourceClass::Input,
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let output = builder
            .add_resource(workspace("lir.count", ResourceDomain::HirNodes, 64))
            .unwrap();
        let pass = builder
            .add_pass(PassDesc {
                name: "lir.count",
                phase: CompilerPhase::SemanticLowering,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("hir_core", input),
                    PassAccess::write("lir_count", output),
                ],
            })
            .unwrap();
        let graph = builder.build().unwrap();
        let reflection = SlangReflection {
            parameters: vec![
                reflected_storage("hir_core", false),
                reflected_storage("lir_count", true),
            ],
            ..Default::default()
        };
        graph.validate_pass_reflection(pass, &reflection).unwrap();
        graph
            .validate_complete_pass_reflection(pass, &reflection)
            .unwrap();

        let incomplete_graph_reflection = SlangReflection {
            parameters: vec![
                reflected_storage("hir_core", false),
                reflected_storage("lir_count", true),
                reflected_storage("forgotten_scratch", true),
            ],
            ..Default::default()
        };
        assert!(
            graph
                .validate_complete_pass_reflection(pass, &incomplete_graph_reflection)
                .unwrap_err()
                .contains("forgotten_scratch exactly once")
        );

        let bad_reflection = SlangReflection {
            parameters: vec![
                reflected_storage("hir_core", true),
                reflected_storage("lir_count", true),
            ],
            ..Default::default()
        };
        assert!(
            graph
                .validate_pass_reflection(pass, &bad_reflection)
                .unwrap_err()
                .contains("shader may write")
        );
    }

    #[test]
    fn graph_rejects_simultaneously_bound_writable_aliases() {
        let mut builder = CompilerGraphBuilder::new();
        let input = builder
            .add_resource(ResourceDesc {
                name: "input",
                domain: ResourceDomain::HirNodes,
                class: ResourceClass::Input,
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let output = builder
            .add_resource(workspace("output", ResourceDomain::HirNodes, 64))
            .unwrap();
        let pass = builder
            .add_pass(PassDesc {
                name: "aliasing.pass",
                phase: CompilerPhase::Hir,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("input", input),
                    PassAccess::write("output", output),
                ],
            })
            .unwrap();
        let graph = builder.build().unwrap();

        let error = graph
            .validate_pass_bindings(
                pass,
                &[
                    BoundGraphResource::whole("input", input, 7, 64),
                    BoundGraphResource::whole("output", output, 7, 64),
                ],
            )
            .unwrap_err();
        assert!(error.contains("overlapping writable aliases"));

        graph
            .validate_pass_bindings(
                pass,
                &[
                    BoundGraphResource::whole("input", input, 7, 64),
                    BoundGraphResource::whole("output", output, 8, 64),
                ],
            )
            .unwrap();
    }

    #[test]
    fn graph_accepts_compact_job_inputs_below_daemon_capacity() {
        let mut builder = CompilerGraphBuilder::new();
        let input = builder
            .add_resource(ResourceDesc {
                name: "compact.input",
                domain: ResourceDomain::HirNodes,
                class: ResourceClass::Input,
                bytes: 4096,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let output = builder
            .add_resource(workspace("resident.output", ResourceDomain::HirNodes, 64))
            .unwrap();
        let pass = builder
            .add_pass(PassDesc {
                name: "compact.input.consumer",
                phase: CompilerPhase::Hir,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("input", input),
                    PassAccess::write("output", output),
                ],
            })
            .unwrap();
        let graph = builder.build().unwrap();

        graph
            .validate_pass_bindings(
                pass,
                &[
                    BoundGraphResource::whole("input", input, 7, 4),
                    BoundGraphResource::whole("output", output, 8, 64),
                ],
            )
            .unwrap();
        let error = graph
            .validate_pass_bindings(
                pass,
                &[
                    BoundGraphResource::whole("input", input, 7, 4),
                    BoundGraphResource::whole("output", output, 8, 4),
                ],
            )
            .unwrap_err();
        assert!(error.contains("64 are required"));
    }

    #[test]
    fn registered_resources_require_identity_for_writable_external_state() {
        let mut builder = CompilerGraphBuilder::new();
        let input = builder
            .add_resource(ResourceDesc {
                name: "raw.input",
                domain: ResourceDomain::Tokens,
                class: ResourceClass::Input,
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let external = builder
            .add_resource(ResourceDesc {
                name: "tracked.output",
                domain: ResourceDomain::Tokens,
                class: ResourceClass::External,
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "registered.pass",
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Tokens,
                accesses: vec![
                    PassAccess::read("input", input),
                    PassAccess::write("output", external),
                ],
            })
            .unwrap();
        let graph = builder.build().unwrap();

        assert_eq!(
            graph
                .bind_registered_resource("input", input, None, 0, 64)
                .unwrap()
                .allocation_id,
            0,
        );
        let error = graph
            .bind_registered_resource("output", external, None, 0, 64)
            .unwrap_err();
        assert!(error.contains("no tracked Lanius allocation identity"));
        let bound = graph
            .bind_registered_resource("output", external, Some(17), 256, 64)
            .unwrap();
        assert_eq!(bound.allocation_id, 17);
        assert_eq!((bound.byte_offset, bound.byte_size), (256, 64));
    }

    #[test]
    fn paged_resource_tracks_logical_extent_with_bounded_residency() {
        let mut builder = CompilerGraphBuilder::new();
        let stream = builder
            .add_resource(workspace(
                "lir.semantic.stream",
                ResourceDomain::SemanticInstructions,
                1024,
            ))
            .unwrap();
        builder.page_resource(stream, 64, 2).unwrap();
        let pass = builder
            .add_paged_region(
                stream,
                vec![PassDesc {
                    name: "lir.semantic.scatter_page",
                    phase: CompilerPhase::SemanticLowering,
                    dispatch_domain: ResourceDomain::SemanticInstructions,
                    accesses: vec![PassAccess::write("semantic_lir", stream)],
                }],
            )
            .unwrap()[0];
        let graph = builder.build().unwrap();

        assert_eq!(graph.workspace_bytes(), 128);
        assert_eq!(graph.paged_regions()[0].driving_resource, stream);
        assert_eq!(
            graph.paged_resource(stream),
            Some(PagedResourceDesc {
                logical_bytes: 1024,
                page_bytes: 64,
                resident_pages: 2,
            })
        );
        graph
            .validate_pass_bindings(
                pass,
                &[BoundGraphResource::window(
                    "semantic_lir",
                    stream,
                    7,
                    64,
                    64,
                    448,
                    64,
                )],
            )
            .unwrap();

        let error = graph
            .validate_pass_bindings(
                pass,
                &[BoundGraphResource::window(
                    "semantic_lir",
                    stream,
                    7,
                    64,
                    64,
                    992,
                    64,
                )],
            )
            .unwrap_err();
        assert!(error.contains("outside its 1024-byte stream"));
    }

    #[test]
    fn paged_resource_cannot_hide_inside_a_resident_pass() {
        let mut builder = CompilerGraphBuilder::new();
        let stream = builder
            .add_resource(workspace(
                "lir.target.stream",
                ResourceDomain::X86Instructions,
                1024,
            ))
            .unwrap();
        builder.page_resource(stream, 64, 2).unwrap();
        builder
            .add_pass(PassDesc {
                name: "lir.target.unbounded_scatter",
                phase: CompilerPhase::X86Lowering,
                dispatch_domain: ResourceDomain::X86Instructions,
                accesses: vec![PassAccess::write("target_lir", stream)],
            })
            .unwrap();
        let error = builder.build().unwrap_err();
        assert!(error.contains("outside a paged region"));
    }

    #[test]
    fn workspace_ownership_rejects_foreign_non_input_allocation() {
        let mut builder = CompilerGraphBuilder::new();
        let input = builder
            .add_resource(ResourceDesc {
                name: "external.input",
                domain: ResourceDomain::HirNodes,
                class: ResourceClass::Input,
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        let output = builder
            .add_resource(workspace("owned.output", ResourceDomain::HirNodes, 64))
            .unwrap();
        let pass = builder
            .add_pass(PassDesc {
                name: "ownership.pass",
                phase: CompilerPhase::Hir,
                dispatch_domain: ResourceDomain::HirNodes,
                accesses: vec![
                    PassAccess::read("input", input),
                    PassAccess::write("output", output),
                ],
            })
            .unwrap();
        let graph = builder.build().unwrap();
        let ownership = CompilerGraphAllocations {
            allocation_by_resource: vec![
                None,
                Some(GraphAllocationRange {
                    allocation_id: 9,
                    byte_offset: 0,
                    byte_size: 64,
                }),
            ],
        };
        let input_binding = BoundGraphResource::whole("input", input, 77, 64);
        let error = ownership
            .validate_pass_bindings(
                &graph,
                pass,
                &[
                    input_binding,
                    BoundGraphResource::whole("output", output, 10, 64),
                ],
            )
            .unwrap_err();
        assert!(error.contains("instead of 9"));
        ownership
            .validate_pass_bindings(
                &graph,
                pass,
                &[
                    input_binding,
                    BoundGraphResource::whole("output", output, 9, 64),
                ],
            )
            .unwrap();

        let error = ownership
            .validate_pass_bindings(
                &graph,
                pass,
                &[
                    input_binding,
                    BoundGraphResource::window("output", output, 9, 32, 64, 0, 64),
                ],
            )
            .unwrap_err();
        assert!(error.contains("outside its owned range 0..64"));
    }

    #[test]
    fn graph_accepts_disjoint_ranges_of_one_allocation() {
        let mut builder = CompilerGraphBuilder::new();
        let left = builder
            .add_resource(workspace("left", ResourceDomain::Bytes, 32))
            .unwrap();
        let right = builder
            .add_resource(workspace("right", ResourceDomain::Bytes, 32))
            .unwrap();
        let pass = builder
            .add_pass(PassDesc {
                name: "disjoint.pass",
                phase: CompilerPhase::Parse,
                dispatch_domain: ResourceDomain::Bytes,
                accesses: vec![
                    PassAccess::write("left", left),
                    PassAccess::write("right", right),
                ],
            })
            .unwrap();
        let graph = builder.build().unwrap();
        graph
            .validate_pass_bindings(
                pass,
                &[
                    BoundGraphResource {
                        binding: "left",
                        resource: left,
                        allocation_id: 3,
                        byte_offset: 0,
                        byte_size: 32,
                        logical_offset: 0,
                        logical_size: 32,
                    },
                    BoundGraphResource {
                        binding: "right",
                        resource: right,
                        allocation_id: 3,
                        byte_offset: 32,
                        byte_size: 32,
                        logical_offset: 0,
                        logical_size: 32,
                    },
                ],
            )
            .unwrap();
    }
}
