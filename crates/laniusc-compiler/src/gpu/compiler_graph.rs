//! Declarative ownership graph for GPU compiler passes and logical resources.
//!
//! `LaniusBuffer` owns physical storage. This module owns the other half of the
//! contract: what a logical array contains, which pass initializes it, how it
//! is accessed, and when its storage becomes reusable.

use std::collections::{BTreeMap, BTreeSet};

use super::{
    buffers::LaniusBuffer,
    kernels::KernelReflections,
    workspace::{WorkspaceAssignment, WorkspacePlan, WorkspaceSlotPlan, WorkspaceUsageClass},
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
    /// Mutable graph-owned storage with a dedicated physical slot.
    ///
    /// Use this while a resource crosses a composition boundary whose full
    /// pass schedule is not yet represented in this graph. It preserves
    /// allocation ownership and binding validation without making an
    /// unsound liveness claim. Once the complete schedule is registered, the
    /// resource can become `Workspace` and participate in phase coloring.
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
}

impl PassAccess {
    pub const fn read(binding: &'static str, resource: ResourceId) -> Self {
        Self {
            binding,
            resource,
            mode: AccessMode::Read,
        }
    }

    pub const fn write(binding: &'static str, resource: ResourceId) -> Self {
        Self {
            binding,
            resource,
            mode: AccessMode::Write,
        }
    }

    pub const fn read_write(binding: &'static str, resource: ResourceId) -> Self {
        Self {
            binding,
            resource,
            mode: AccessMode::ReadWrite,
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PassDesc {
    pub name: &'static str,
    pub phase: CompilerPhase,
    pub dispatch_domain: ResourceDomain,
    pub accesses: Vec<PassAccess>,
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
        Ok(Self::whole(
            binding,
            resource,
            allocation_id,
            buffer.byte_size as u64,
        ))
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CompilerGraph {
    resources: Vec<ResourceDesc>,
    resource_aliases: BTreeMap<&'static str, ResourceId>,
    passes: Vec<PassDesc>,
    pass_kernels: Vec<Option<&'static str>>,
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

/// Copyable ownership identity for graph-managed physical slots. Stages keep
/// this after construction so recording can prove that non-input resources
/// still use the allocations selected by the graph.
#[derive(Clone, Debug)]
pub struct CompilerGraphAllocations {
    allocation_by_resource: Vec<Option<u64>>,
}

impl CompilerGraphWorkspace {
    pub fn new(device: &wgpu::Device, label: &str, graph: &CompilerGraph) -> Result<Self, String> {
        Self::new_with_imports(device, label, graph, &[])
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
            if desc.class != ResourceClass::Workspace {
                return Err(format!(
                    "compiler resource {} cannot import a workspace slot because it is {:?}",
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
                if previous.allocation_id() != buffer.allocation_id() {
                    return Err(format!(
                        "workspace slot {slot} has imports from two different allocations",
                    ));
                }
            }
        }
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
                slots.push(imported);
            } else {
                let usage = wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::COPY_SRC
                    | wgpu::BufferUsages::COPY_DST
                    | match plan.usage {
                        WorkspaceUsageClass::Storage => wgpu::BufferUsages::empty(),
                        WorkspaceUsageClass::StorageIndirect => wgpu::BufferUsages::INDIRECT,
                    };
                let raw = device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some(&format!("{label}.slot.{}", plan.slot)),
                    size: plan.bytes,
                    usage,
                    mapped_at_creation: false,
                });
                slots.push(LaniusBuffer::new_labeled(
                    (raw, plan.bytes),
                    plan.bytes as usize,
                    format!("{label}.slot.{}", plan.slot),
                ));
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
        Ok(Self {
            slots,
            slot_by_resource,
        })
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

    /// Returns a typed view of the allocation selected for a named logical
    /// resource. Shader-facing layers generally know the reflected resource
    /// name, while resource IDs remain a graph-construction detail.
    pub fn alias_named<T>(
        &self,
        graph: &CompilerGraph,
        name: &str,
        count: usize,
    ) -> Result<LaniusBuffer<T>, String> {
        let resource = graph
            .resource_id(name)
            .ok_or_else(|| format!("compiler graph has no resource `{name}`"))?;
        self.alias(graph, resource, count)
    }

    pub fn allocation_count(&self) -> usize {
        self.slots.len()
    }

    pub fn allocations(&self) -> CompilerGraphAllocations {
        CompilerGraphAllocations {
            allocation_by_resource: self
                .slot_by_resource
                .iter()
                .map(|slot| {
                    slot.and_then(|slot| {
                        self.slots
                            .get(slot as usize)
                            .and_then(LaniusBuffer::allocation_id)
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
        let allocation = buffer.allocation_id().ok_or_else(|| {
            format!(
                "compiler resource {} imports a buffer without allocation identity",
                desc.name
            )
        })?;
        let slot = self
            .allocation_by_resource
            .get_mut(resource.index())
            .ok_or_else(|| format!("unknown compiler resource {}", resource.index()))?;
        *slot = Some(allocation);
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
            if bound.allocation_id != expected {
                return Err(format!(
                    "compiler pass {} binds graph-owned {} to allocation {} instead of {}",
                    desc.name, resource.name, bound.allocation_id, expected,
                ));
            }
        }
        Ok(())
    }
}

impl CompilerGraph {
    /// Returns the generated shader artifact implementing a reflected pass.
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
        Ok(BoundGraphResource::whole(
            binding,
            resource,
            allocation_id,
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
                .filter(|access| access.binding == parameter.name)
                .count();
            if count != 1 {
                return Err(format!(
                    "compiler pass {} must describe reflected storage binding {} exactly once, found {count}",
                    desc.name, parameter.name,
                ));
            }
        }
        Ok(())
    }
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

/// Pass names for a radix implementation whose block-prefix relation is
/// scanned hierarchically across workgroups.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HierarchicalRadixSortGraphStepPasses {
    pub histogram: &'static str,
    pub bucket_local: &'static str,
    pub bucket_chunks: &'static str,
    pub bucket_apply: &'static str,
    pub bucket_bases: &'static str,
    pub scatter: &'static str,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct HierarchicalRadixSortGraphPasses {
    pub order_to_temporary: HierarchicalRadixSortGraphStepPasses,
    pub temporary_to_order: HierarchicalRadixSortGraphStepPasses,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum RadixSortGraphSchedule {
    Standard(RadixSortGraphPasses),
    Hierarchical(HierarchicalRadixSortGraphPasses),
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
    pub keys: Vec<ResourceId>,
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
    pub schedule: RadixSortGraphSchedule,
    pub resources: RadixSortGraphResources,
}

fn hierarchical_radix_sort_step_passes(
    graph: &CompilerGraphBuilder,
    phase: CompilerPhase,
    dispatch_domain: ResourceDomain,
    passes: HierarchicalRadixSortGraphStepPasses,
    resources: &RadixSortGraphResources,
    input: ResourceId,
    output: ResourceId,
) -> Vec<PassDesc> {
    let r = resources;
    let name = |resource: ResourceId| graph.resources[resource.index()].name;
    let key_reads = || {
        r.keys
            .iter()
            .map(|resource| PassAccess::read(name(*resource), *resource))
            .collect::<Vec<_>>()
    };
    let mut histogram_accesses = key_reads();
    histogram_accesses.extend([
        PassAccess::read(name(r.count), r.count),
        PassAccess::read(name(input), input),
        PassAccess::read(name(r.dispatch_args), r.dispatch_args),
        PassAccess::write(name(r.histogram), r.histogram),
    ]);
    let mut scatter_accesses = key_reads();
    scatter_accesses.extend([
        PassAccess::read(name(r.count), r.count),
        PassAccess::read(name(input), input),
        PassAccess::read(name(r.dispatch_args), r.dispatch_args),
        PassAccess::read(name(r.bucket_prefix), r.bucket_prefix),
        PassAccess::read(name(r.bucket_base), r.bucket_base),
        PassAccess::write(name(output), output),
    ]);
    vec![
        PassDesc {
            name: passes.histogram,
            phase,
            dispatch_domain,
            accesses: histogram_accesses,
        },
        PassDesc {
            name: passes.bucket_local,
            phase,
            dispatch_domain,
            accesses: vec![
                PassAccess::read(name(r.count), r.count),
                PassAccess::read_write(name(r.histogram), r.histogram),
                PassAccess::write(name(r.bucket_prefix), r.bucket_prefix),
                PassAccess::write(name(r.bucket_total), r.bucket_total),
            ],
        },
        PassDesc {
            name: passes.bucket_chunks,
            phase,
            dispatch_domain,
            accesses: vec![
                PassAccess::read(name(r.count), r.count),
                PassAccess::read_write(name(r.histogram), r.histogram),
                PassAccess::read_write(name(r.bucket_total), r.bucket_total),
            ],
        },
        PassDesc {
            name: passes.bucket_apply,
            phase,
            dispatch_domain,
            accesses: vec![
                PassAccess::read(name(r.count), r.count),
                PassAccess::read(name(r.histogram), r.histogram),
                PassAccess::read_write(name(r.bucket_prefix), r.bucket_prefix),
            ],
        },
        PassDesc {
            name: passes.bucket_bases,
            phase,
            dispatch_domain,
            accesses: vec![
                PassAccess::read(name(r.bucket_total), r.bucket_total),
                PassAccess::write(name(r.bucket_base), r.bucket_base),
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
    .chain(resources.keys.iter().copied())
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
            .map(|resource| PassAccess::read(name(*resource), *resource))
            .collect::<Vec<_>>()
    };
    let mut histogram_accesses = key_reads();
    histogram_accesses.extend([
        PassAccess::read(name(r.count), r.count),
        PassAccess::read(name(input), input),
        PassAccess::read(name(r.dispatch_args), r.dispatch_args),
        PassAccess::write(name(r.histogram), r.histogram),
    ]);
    let mut scatter_accesses = key_reads();
    scatter_accesses.extend([
        PassAccess::read(name(r.count), r.count),
        PassAccess::read(name(input), input),
        PassAccess::read(name(r.dispatch_args), r.dispatch_args),
        PassAccess::read(name(r.bucket_prefix), r.bucket_prefix),
        PassAccess::read(name(r.bucket_base), r.bucket_base),
        PassAccess::write(name(output), output),
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
                PassAccess::read(name(r.count), r.count),
                PassAccess::read(name(r.histogram), r.histogram),
                PassAccess::write(name(r.bucket_prefix), r.bucket_prefix),
                PassAccess::write(name(r.bucket_total), r.bucket_total),
            ],
        },
        PassDesc {
            name: passes.bucket_bases,
            phase,
            dispatch_domain,
            accesses: vec![
                PassAccess::read(name(r.bucket_total), r.bucket_total),
                PassAccess::write(name(r.bucket_base), r.bucket_base),
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
        let label = match self.schedule {
            RadixSortGraphSchedule::Standard(passes) => passes.order_to_temporary.histogram,
            RadixSortGraphSchedule::Hierarchical(passes) => passes.order_to_temporary.histogram,
        };
        if self.digit_steps == 0 || self.digit_steps % 2 != 0 {
            return Err(format!(
                "radix sort {} requires a positive even digit-step count, got {}",
                label, self.digit_steps,
            ));
        }
        let r = &self.resources;
        validate_radix_sort_resources(graph, label, r)?;
        let body = match self.schedule {
            RadixSortGraphSchedule::Standard(passes) => {
                let mut body = radix_sort_step_passes(
                    graph,
                    self.phase,
                    self.dispatch_domain,
                    passes.order_to_temporary,
                    r,
                    r.order,
                    r.temporary_order,
                );
                body.extend(radix_sort_step_passes(
                    graph,
                    self.phase,
                    self.dispatch_domain,
                    passes.temporary_to_order,
                    r,
                    r.temporary_order,
                    r.order,
                ));
                body
            }
            RadixSortGraphSchedule::Hierarchical(passes) => {
                let mut body = hierarchical_radix_sort_step_passes(
                    graph,
                    self.phase,
                    self.dispatch_domain,
                    passes.order_to_temporary,
                    r,
                    r.order,
                    r.temporary_order,
                );
                body.extend(hierarchical_radix_sort_step_passes(
                    graph,
                    self.phase,
                    self.dispatch_domain,
                    passes.temporary_to_order,
                    r,
                    r.temporary_order,
                    r.order,
                ));
                body
            }
        };
        graph.add_repeated_region(self.digit_steps / 2, body)?;
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
        if self.digit_steps == 0 || self.digit_steps % 2 != 0 {
            return Err(format!(
                "paired radix sorts require a positive even digit-step count, got {}",
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
        graph.add_repeated_region(self.digit_steps / 2, body)?;
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
    graph.assign_kernel(passes.apply, "scan/counted/02_apply")
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
    pub fn register(
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

fn paired_scan_accesses(
    graph: &CompilerGraphBuilder,
    accesses: impl IntoIterator<Item = (AccessMode, ResourceId)>,
) -> Result<Vec<PassAccess>, String> {
    let mut merged = Vec::<PassAccess>::new();
    for (mode, resource) in accesses {
        let desc = graph.resources.get(resource.index()).ok_or_else(|| {
            format!(
                "prefix scan references unknown resource {}",
                resource.index()
            )
        })?;
        if let Some(previous) = merged.iter().find(|access| access.resource == resource) {
            if previous.mode == AccessMode::Read && mode == AccessMode::Read {
                continue;
            }
            return Err(format!(
                "paired prefix scans use mutable resource {} in two simultaneous roles",
                desc.name,
            ));
        }
        merged.push(PassAccess {
            binding: desc.name,
            resource,
            mode,
        });
    }
    Ok(merged)
}

impl CompilerGraphFragment for PrefixScanPairGraph {
    type Output = ((ResourceId, ResourceId), (ResourceId, ResourceId));

    fn add_to(self, graph: &mut CompilerGraphBuilder) -> Result<Self::Output, String> {
        if self.hierarchy_levels == 0 {
            return Err(format!(
                "paired prefix scan {} requires at least one hierarchy level",
                self.passes.local,
            ));
        }
        let l = self.left;
        let r = self.right;
        graph.add_pass(PassDesc {
            name: self.passes.local,
            phase: self.phase,
            dispatch_domain: self.dispatch_domain,
            accesses: paired_scan_accesses(
                graph,
                [
                    (AccessMode::Read, l.count),
                    (AccessMode::Read, l.input),
                    (AccessMode::Read, l.dispatch_args),
                    (AccessMode::Write, l.local_prefix),
                    (AccessMode::Write, l.block_sum),
                    (AccessMode::Read, r.count),
                    (AccessMode::Read, r.input),
                    (AccessMode::Read, r.dispatch_args),
                    (AccessMode::Write, r.local_prefix),
                    (AccessMode::Write, r.block_sum),
                ],
            )?,
        })?;
        graph.add_pass(PassDesc {
            name: self.passes.hierarchy_up_first,
            phase: self.phase,
            dispatch_domain: self.dispatch_domain,
            accesses: paired_scan_accesses(
                graph,
                [
                    (AccessMode::Read, l.count),
                    (AccessMode::Read, l.block_sum),
                    (AccessMode::Write, l.block_prefix),
                    (AccessMode::Write, l.hierarchy),
                    (AccessMode::Read, r.count),
                    (AccessMode::Read, r.block_sum),
                    (AccessMode::Write, r.block_prefix),
                    (AccessMode::Write, r.hierarchy),
                ],
            )?,
        })?;
        if self.hierarchy_levels > 1 {
            graph.add_repeated_region(
                self.hierarchy_levels - 1,
                vec![PassDesc {
                    name: self.passes.hierarchy_up_rest,
                    phase: self.phase,
                    dispatch_domain: self.dispatch_domain,
                    accesses: paired_scan_accesses(
                        graph,
                        [
                            (AccessMode::Read, l.count),
                            (AccessMode::Read, l.block_sum),
                            (AccessMode::ReadWrite, l.block_prefix),
                            (AccessMode::ReadWrite, l.hierarchy),
                            (AccessMode::Read, r.count),
                            (AccessMode::Read, r.block_sum),
                            (AccessMode::ReadWrite, r.block_prefix),
                            (AccessMode::ReadWrite, r.hierarchy),
                        ],
                    )?,
                }],
            )?;
            graph.add_repeated_region(
                self.hierarchy_levels - 1,
                vec![PassDesc {
                    name: self.passes.hierarchy_down,
                    phase: self.phase,
                    dispatch_domain: self.dispatch_domain,
                    accesses: paired_scan_accesses(
                        graph,
                        [
                            (AccessMode::Read, l.count),
                            (AccessMode::ReadWrite, l.block_prefix),
                            (AccessMode::ReadWrite, l.hierarchy),
                            (AccessMode::Read, r.count),
                            (AccessMode::ReadWrite, r.block_prefix),
                            (AccessMode::ReadWrite, r.hierarchy),
                        ],
                    )?,
                }],
            )?;
        }
        graph.add_pass(PassDesc {
            name: self.passes.apply,
            phase: self.phase,
            dispatch_domain: self.dispatch_domain,
            accesses: paired_scan_accesses(
                graph,
                [
                    (AccessMode::Read, l.count),
                    (AccessMode::Read, l.dispatch_args),
                    (AccessMode::Read, l.local_prefix),
                    (AccessMode::Read, l.block_prefix),
                    (AccessMode::Write, l.output_prefix),
                    (AccessMode::Write, l.total),
                    (AccessMode::Read, r.count),
                    (AccessMode::Read, r.dispatch_args),
                    (AccessMode::Read, r.local_prefix),
                    (AccessMode::Read, r.block_prefix),
                    (AccessMode::Write, r.output_prefix),
                    (AccessMode::Write, r.total),
                ],
            )?,
        })?;
        assign_prefix_scan_kernels(graph, self.passes)?;
        Ok(((l.output_prefix, l.total), (r.output_prefix, r.total)))
    }
}

impl CompilerGraphFragment for PrefixScanGraph {
    type Output = (ResourceId, ResourceId);

    fn add_to(self, graph: &mut CompilerGraphBuilder) -> Result<Self::Output, String> {
        if self.hierarchy_levels == 0 {
            return Err(format!(
                "prefix scan {} requires at least one hierarchy level",
                self.passes.local,
            ));
        }
        let r = self.resources;
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
                    self.passes.local,
                    resource.index(),
                ));
            }
            if !distinct.insert(resource) {
                return Err(format!(
                    "prefix scan {} uses resource {} for two simultaneous roles",
                    self.passes.local,
                    graph.resources[resource.index()].name,
                ));
            }
        }

        let count_name = graph.resources[r.count.index()].name;
        let input_name = graph.resources[r.input.index()].name;
        let output_prefix_name = graph.resources[r.output_prefix.index()].name;
        let total_name = graph.resources[r.total.index()].name;
        let dispatch_args_name = graph.resources[r.dispatch_args.index()].name;
        let local_prefix_name = graph.resources[r.local_prefix.index()].name;
        let block_sum_name = graph.resources[r.block_sum.index()].name;
        let block_prefix_name = graph.resources[r.block_prefix.index()].name;
        let hierarchy_name = graph.resources[r.hierarchy.index()].name;
        graph.add_pass(PassDesc {
            name: self.passes.local,
            phase: self.phase,
            dispatch_domain: self.dispatch_domain,
            accesses: vec![
                PassAccess::read(count_name, r.count),
                PassAccess::read(input_name, r.input),
                PassAccess::read(dispatch_args_name, r.dispatch_args),
                PassAccess::write(local_prefix_name, r.local_prefix),
                PassAccess::write(block_sum_name, r.block_sum),
            ],
        })?;
        graph.add_pass(PassDesc {
            name: self.passes.hierarchy_up_first,
            phase: self.phase,
            dispatch_domain: self.dispatch_domain,
            accesses: vec![
                PassAccess::read(count_name, r.count),
                PassAccess::read(block_sum_name, r.block_sum),
                PassAccess::write(block_prefix_name, r.block_prefix),
                PassAccess::write(hierarchy_name, r.hierarchy),
            ],
        })?;

        if self.hierarchy_levels > 1 {
            graph.add_repeated_region(
                self.hierarchy_levels - 1,
                vec![PassDesc {
                    name: self.passes.hierarchy_up_rest,
                    phase: self.phase,
                    dispatch_domain: self.dispatch_domain,
                    accesses: vec![
                        PassAccess::read(count_name, r.count),
                        PassAccess::read(block_sum_name, r.block_sum),
                        PassAccess::read_write(block_prefix_name, r.block_prefix),
                        PassAccess::read_write(hierarchy_name, r.hierarchy),
                    ],
                }],
            )?;
            graph.add_repeated_region(
                self.hierarchy_levels - 1,
                vec![PassDesc {
                    name: self.passes.hierarchy_down,
                    phase: self.phase,
                    dispatch_domain: self.dispatch_domain,
                    accesses: vec![
                        PassAccess::read(count_name, r.count),
                        PassAccess::read_write(block_prefix_name, r.block_prefix),
                        PassAccess::read_write(hierarchy_name, r.hierarchy),
                    ],
                }],
            )?;
        }

        graph.add_pass(PassDesc {
            name: self.passes.apply,
            phase: self.phase,
            dispatch_domain: self.dispatch_domain,
            accesses: vec![
                PassAccess::read(count_name, r.count),
                PassAccess::read(dispatch_args_name, r.dispatch_args),
                PassAccess::read(local_prefix_name, r.local_prefix),
                PassAccess::read(block_prefix_name, r.block_prefix),
                PassAccess::write(output_prefix_name, r.output_prefix),
                PassAccess::write(total_name, r.total),
            ],
        })?;
        assign_prefix_scan_kernels(graph, self.passes)?;
        Ok((r.output_prefix, r.total))
    }
}

#[derive(Default)]
pub struct CompilerGraphBuilder {
    resources: Vec<ResourceDesc>,
    passes: Vec<PassDesc>,
    pass_kernels: Vec<Option<&'static str>>,
    resource_names: BTreeSet<&'static str>,
    resource_aliases: BTreeMap<&'static str, ResourceId>,
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
            self.resources
                .iter()
                .position(|resource| resource.name == name)
                .map(ResourceId)
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
            keys,
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
        let mut resources = BTreeSet::new();
        for access in &desc.accesses {
            if access.resource.index() >= self.resources.len() {
                return Err(format!(
                    "compiler pass {} references unknown resource {}",
                    desc.name,
                    access.resource.index(),
                ));
            }
            if !resources.insert(access.resource) {
                return Err(format!(
                    "compiler pass {} declares resource {} more than once",
                    desc.name,
                    self.resources[access.resource.index()].name,
                ));
            }
        }
        let id = PassId(self.passes.len());
        self.passes.push(desc);
        self.pass_kernels.push(None);
        Ok(id)
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
            });
        }
        if let Some((extra, _)) = supplied.into_iter().next() {
            return Err(format!(
                "compiler pass {name} maps {extra}, which is not a reflected storage binding",
            ));
        }
        self.add_pass(PassDesc {
            name,
            phase,
            dispatch_domain,
            accesses,
        })
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
            let (resource_index, resource) = self
                .resources
                .iter()
                .enumerate()
                .find(|(_, resource)| resource.name == parameter.name)
                .ok_or_else(|| {
                    format!(
                        "compiler pass {name} has reflected storage binding {} with no same-named graph resource or override",
                        parameter.name,
                    )
                })?;
            bindings.push(ReflectedResourceBinding {
                binding: resource.name,
                resource: ResourceId(resource_index),
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
                let resource = self
                    .resources
                    .iter()
                    .position(|resource| resource.name == binding)
                    .map(ResourceId)
                    .ok_or_else(|| {
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
                    let resource = self
                        .resources
                        .iter()
                        .position(|resource| resource.name == parameter.name)
                        .map(ResourceId)
                        .ok_or_else(|| {
                            format!(
                                "compiler pass {name} has reflected initializer binding {} with no same-named graph resource",
                                parameter.name,
                            )
                        })?;
                    Ok(ReflectedResourceBinding {
                        binding: self.resources[resource.index()].name,
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

                if access.mode.reads() && !initialized[resource_index] {
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
            passes: self.passes,
            pass_kernels: self.pass_kernels,
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
    #[derive(Clone, Copy)]
    struct SlotState {
        plan: WorkspaceSlotPlan,
        last_pass: PassId,
        dedicated: bool,
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
    order.sort_unstable_by_key(|(_, resource, lifetime)| {
        (
            lifetime.first_pass,
            std::cmp::Reverse(resource.bytes),
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
        let dedicated = resource.class == ResourceClass::Resident;
        let reusable = (!disable_coloring && !dedicated)
            .then(|| {
                slots
                    .iter()
                    .enumerate()
                    .filter(|(_, slot)| {
                        !slot.dedicated
                            && slot.plan.usage == resource.usage
                            && slot.last_pass < lifetime.first_pass
                    })
                    .min_by_key(|(_, slot)| {
                        let resulting_bytes = slot.plan.bytes.max(resource.bytes);
                        (
                            resulting_bytes - slot.plan.bytes,
                            resulting_bytes,
                            std::cmp::Reverse(slot.last_pass),
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
                last_pass: lifetime.last_pass,
                dedicated,
            });
            index
        });
        let slot = &mut slots[slot_index];
        slot.plan.bytes = slot.plan.bytes.max(resource.bytes);
        slot.last_pass = lifetime.last_pass;
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
                "compiler_graph_slot slot={} index={} resource={} first={} last={}",
                assignment.slot,
                resource_index,
                assignment.name,
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
                schedule: RadixSortGraphSchedule::Standard(RadixSortGraphPasses {
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
                }),
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
    fn radix_sort_rejects_an_odd_digit_step_count() {
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
        let error = builder
            .add_fragment(RadixSortGraph {
                phase: CompilerPhase::TypeCheck,
                dispatch_domain: ResourceDomain::Declarations,
                digit_steps: 3,
                schedule: RadixSortGraphSchedule::Standard(RadixSortGraphPasses {
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
                }),
                resources: RadixSortGraphResources {
                    count,
                    keys: vec![key],
                    order,
                    temporary_order,
                    dispatch_args,
                    histogram,
                    bucket_prefix,
                    bucket_total,
                    bucket_base,
                },
            })
            .unwrap_err();
        assert!(error.contains("positive even digit-step count"), "{error}");
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
            1,
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
                .bind_registered_resource("input", input, None, 64)
                .unwrap()
                .allocation_id,
            0,
        );
        let error = graph
            .bind_registered_resource("output", external, None, 64)
            .unwrap_err();
        assert!(error.contains("no tracked Lanius allocation identity"));
        assert_eq!(
            graph
                .bind_registered_resource("output", external, Some(17), 64)
                .unwrap()
                .allocation_id,
            17,
        );
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
            allocation_by_resource: vec![None, Some(9)],
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
