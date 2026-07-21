//! Declarative ownership graph for GPU compiler passes and logical resources.
//!
//! `LaniusBuffer` owns physical storage. This module owns the other half of the
//! contract: what a logical array contains, which pass initializes it, how it
//! is accessed, and when its storage becomes reusable.

use std::collections::{BTreeMap, BTreeSet};

use super::{
    buffers::LaniusBuffer,
    workspace::{WorkspaceAssignment, WorkspacePlan, WorkspaceSlotPlan, WorkspaceUsageClass},
};
use crate::reflection::{ParameterReflection, SlangReflection};

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
    /// Initialized by exactly one pass and immutable afterwards.
    Artifact,
    /// Mutable scratch whose storage may be reused after its final access.
    Workspace,
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

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct ResourceLifetime {
    pub first_pass: PassId,
    pub last_pass: PassId,
    pub producer: Option<PassId>,
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
    passes: Vec<PassDesc>,
    lifetimes: Vec<Option<ResourceLifetime>>,
    repeated_regions: Vec<RepeatedPassRegion>,
    paged_regions: Vec<PagedPassRegion>,
    paged_resources: Vec<Option<PagedResourceDesc>>,
    workspace: WorkspacePlan,
}

/// Stable physical slot allocation for one compiler graph capacity. Logical
/// resources obtain typed aliases of these slots; the graph, rather than the
/// caller, decides which non-overlapping lifetimes share storage.
pub struct CompilerGraphWorkspace {
    slots: Vec<LaniusBuffer<u8>>,
    slot_by_resource: Vec<Option<u32>>,
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
        let mut slots = Vec::with_capacity(graph.workspace.slots.len());
        for plan in &graph.workspace.slots {
            if plan.slot as usize != slots.len() {
                return Err(format!(
                    "compiler graph workspace has non-dense slot {}",
                    plan.slot
                ));
            }
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
        if desc.class == ResourceClass::Input {
            return Err(format!(
                "compiler resource {} is already a graph input and does not need an allocation import",
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
            if resource.class == ResourceClass::Input {
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
    pub fn resources(&self) -> &[ResourceDesc] {
        &self.resources
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
    }

    pub fn pass_id(&self, name: &str) -> Option<PassId> {
        self.passes
            .iter()
            .position(|pass| pass.name == name)
            .map(PassId)
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
            // Input resources describe the maximum logical job capacity, not
            // a promise that every upstream producer allocated that maximum.
            // Active count buffers guard their runtime extent. Graph-owned
            // workspace and outputs, by contrast, must cover their complete
            // declared range because downstream passes may write any row in it.
            let required = paged.map_or_else(
                || {
                    if resource.class == ResourceClass::Input {
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

#[derive(Default)]
pub struct CompilerGraphBuilder {
    resources: Vec<ResourceDesc>,
    passes: Vec<PassDesc>,
    resource_names: BTreeSet<&'static str>,
    pass_names: BTreeSet<&'static str>,
    repeated_regions: Vec<RepeatedPassRegion>,
    paged_regions: Vec<PagedPassRegion>,
    paged_resources: Vec<Option<PagedResourceDesc>>,
}

impl CompilerGraphBuilder {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn add_resource(&mut self, desc: ResourceDesc) -> Result<ResourceId, String> {
        if desc.bytes == 0 {
            return Err(format!("compiler resource {} has zero bytes", desc.name));
        }
        if !self.resource_names.insert(desc.name) {
            return Err(format!("duplicate compiler resource {}", desc.name));
        }
        let id = ResourceId(self.resources.len());
        self.resources.push(desc);
        self.paged_resources.push(None);
        Ok(id)
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
        Ok(id)
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
            .map(|resource| resource.class == ResourceClass::Input)
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
                    ResourceClass::Artifact if producers[resource_index].is_some() => {
                        return Err(format!(
                            "compiler artifact {} has more than one producer",
                            resource.name,
                        ));
                    }
                    ResourceClass::Artifact => producers[resource_index] = Some(pass_id),
                    ResourceClass::Workspace | ResourceClass::Output => {
                        producers[resource_index].get_or_insert(pass_id);
                    }
                }
                initialized[resource_index] = true;
            }
        }

        for (index, resource) in self.resources.iter().enumerate() {
            match resource.class {
                ResourceClass::Input if first_pass[index].is_none() => {}
                ResourceClass::Input => {}
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
            passes: self.passes,
            lifetimes,
            repeated_regions: self.repeated_regions,
            paged_regions: self.paged_regions,
            paged_resources: self.paged_resources,
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
    }

    let mut order = resources
        .iter()
        .enumerate()
        .filter_map(|(index, resource)| {
            (resource.class != ResourceClass::Input).then_some((index, resource, lifetimes[index]?))
        })
        .collect::<Vec<_>>();
    order.sort_unstable_by_key(|(_, resource, lifetime)| {
        (
            lifetime.first_pass,
            std::cmp::Reverse(resource.bytes),
            resource.name,
        )
    });

    let mut slots = Vec::<SlotState>::new();
    let mut assignment_by_resource = BTreeMap::<usize, u32>::new();
    for (resource_index, resource, lifetime) in order {
        let reusable = slots.iter().position(|slot| {
            slot.plan.usage == resource.usage && slot.last_pass < lifetime.first_pass
        });
        let slot_index = reusable.unwrap_or_else(|| {
            let index = slots.len();
            slots.push(SlotState {
                plan: WorkspaceSlotPlan {
                    slot: index as u32,
                    bytes: resource.bytes,
                    usage: resource.usage,
                },
                last_pass: lifetime.last_pass,
            });
            index
        });
        let slot = &mut slots[slot_index];
        slot.plan.bytes = slot.plan.bytes.max(resource.bytes);
        slot.last_pass = lifetime.last_pass;
        assignment_by_resource.insert(resource_index, slot.plan.slot);
    }

    Ok(WorkspacePlan {
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
    })
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
