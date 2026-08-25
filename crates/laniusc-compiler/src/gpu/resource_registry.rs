//! Name-keyed GPU resource registry shared by reflected compiler operations.

use std::collections::HashMap;

use anyhow::Result;

use super::{
    buffers::{LaniusBuffer, TrackedBufferView},
    compiler_graph::{
        BoundGraphResource,
        CompilerGraph,
        CompilerGraphAllocations,
        CompilerGraphBindings,
        ResourceId,
    },
    passes_core::{PassData, bind_group},
};

/// Converts type-checker buffer wrappers into WGPU binding resources.
pub(crate) trait ResourceBinding<'a> {
    fn binding(self) -> wgpu::BindingResource<'a>;

    /// Returns the compiler allocation identity when this binding is backed by
    /// tracked storage, plus its bound byte offset and extent.
    fn graph_identity(self) -> (Option<u64>, u64, u64);

    /// Logical byte extent of this view, which may be smaller than its aliased
    /// physical allocation.
    fn logical_byte_size(self) -> u64;
}

impl<'a> ResourceBinding<'a> for &'a wgpu::Buffer {
    fn binding(self) -> wgpu::BindingResource<'a> {
        self.as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64, u64) {
        (None, 0, self.size())
    }

    fn logical_byte_size(self) -> u64 {
        self.size()
    }
}

impl<'a, 'b> ResourceBinding<'a> for &'b &'a wgpu::Buffer {
    fn binding(self) -> wgpu::BindingResource<'a> {
        (*self).as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64, u64) {
        (None, 0, self.size())
    }

    fn logical_byte_size(self) -> u64 {
        self.size()
    }
}

impl<'a, T> ResourceBinding<'a> for &'a LaniusBuffer<T> {
    fn binding(self) -> wgpu::BindingResource<'a> {
        self.as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64, u64) {
        (
            self.allocation_id(),
            self.byte_offset,
            self.byte_size as u64,
        )
    }

    fn logical_byte_size(self) -> u64 {
        (self.count as u64).saturating_mul(std::mem::size_of::<T>() as u64)
    }
}

impl<'a> ResourceBinding<'a> for TrackedBufferView<'a> {
    fn binding(self) -> wgpu::BindingResource<'a> {
        self.as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64, u64) {
        (self.allocation_id(), self.byte_offset, self.byte_size)
    }

    fn logical_byte_size(self) -> u64 {
        self.byte_size
    }
}

impl<'a, 'b> ResourceBinding<'a> for &'b TrackedBufferView<'a> {
    fn binding(self) -> wgpu::BindingResource<'a> {
        (*self).as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64, u64) {
        (self.allocation_id(), self.byte_offset, self.byte_size)
    }

    fn logical_byte_size(self) -> u64 {
        self.byte_size
    }
}

impl<'a, 'b, T> ResourceBinding<'a> for &'b &'a LaniusBuffer<T> {
    fn binding(self) -> wgpu::BindingResource<'a> {
        (*self).as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64, u64) {
        (
            self.allocation_id(),
            self.byte_offset,
            self.byte_size as u64,
        )
    }

    fn logical_byte_size(self) -> u64 {
        (self.count as u64).saturating_mul(std::mem::size_of::<T>() as u64)
    }
}

#[derive(Clone, Copy)]
struct GraphResourceIdentity {
    allocation_id: Option<u64>,
    byte_offset: u64,
    byte_size: u64,
    logical_byte_size: u64,
}

#[derive(Clone, Copy)]
struct GraphContext<'a> {
    graph: &'a CompilerGraph,
    allocations: &'a CompilerGraphAllocations,
}

/// Name-keyed binding resource map used by reflection-based bind-group builders.
#[derive(Clone)]
pub(crate) struct ResourceMap<'a> {
    resources: HashMap<String, wgpu::BindingResource<'a>>,
    graph_identities: HashMap<String, GraphResourceIdentity>,
    graph_context: Option<GraphContext<'a>>,
}

impl<'a> ResourceMap<'a> {
    /// Creates an empty resource map for one bind-group construction phase.
    pub(crate) fn new() -> Self {
        Self {
            resources: HashMap::new(),
            graph_identities: HashMap::new(),
            graph_context: None,
        }
    }

    fn add_named(&mut self, name: String, resource: wgpu::BindingResource<'a>) {
        if let wgpu::BindingResource::Buffer(binding) = &resource {
            let byte_size = binding
                .size
                .map(std::num::NonZeroU64::get)
                .unwrap_or_else(|| binding.buffer.size().saturating_sub(binding.offset));
            self.graph_identities.insert(
                name.clone(),
                GraphResourceIdentity {
                    allocation_id: super::buffers::tracked_buffer_identity(binding.buffer)
                        .map(|(id, _, _)| id),
                    byte_offset: binding.offset,
                    byte_size,
                    logical_byte_size: byte_size,
                },
            );
        }
        self.resources.insert(name, resource);
    }

    /// Associates this registry with the graph that owns its logical buffers.
    /// Cloned operation-local registries retain this contract automatically.
    pub(crate) fn attach_graph(
        &mut self,
        graph: &'a CompilerGraph,
        allocations: &'a CompilerGraphAllocations,
    ) {
        self.graph_context = Some(GraphContext { graph, allocations });
    }

    /// Returns the exact logical range registered for a reflected buffer.
    pub(crate) fn tracked_view(&self, name: &str) -> Result<TrackedBufferView<'a>> {
        let binding = match self.resources.get(name) {
            Some(wgpu::BindingResource::Buffer(binding)) => binding,
            Some(_) => return Err(anyhow::anyhow!("GPU resource `{name}` is not a buffer")),
            None => return Err(anyhow::anyhow!("GPU resource `{name}` is not registered")),
        };
        let identity = self
            .graph_identities
            .get(name)
            .ok_or_else(|| anyhow::anyhow!("GPU resource `{name}` has no range identity"))?;
        Ok(TrackedBufferView::from_parts(
            binding.buffer,
            identity.byte_offset,
            identity.byte_size,
            identity.allocation_id,
        ))
    }

    /// Inserts a prebuilt binding resource under the shader resource name.
    pub(crate) fn add(&mut self, name: &'static str, resource: wgpu::BindingResource<'a>) {
        self.add_named(name.to_owned(), resource);
    }

    /// Inserts a buffer-like value under the shader resource name.
    pub(crate) fn buffer<B>(&mut self, name: &'static str, buffer: B)
    where
        B: ResourceBinding<'a> + Copy,
    {
        let (allocation_id, byte_offset, byte_size) = buffer.graph_identity();
        let logical_byte_size = buffer.logical_byte_size();
        self.add(name, buffer.binding());
        self.graph_identities.insert(
            name.to_owned(),
            GraphResourceIdentity {
                allocation_id,
                byte_offset,
                byte_size,
                logical_byte_size,
            },
        );
    }

    pub(crate) fn buffers<B, const N: usize>(&mut self, buffers: [(&'static str, B); N])
    where
        B: ResourceBinding<'a> + Copy,
    {
        for (name, buffer) in buffers {
            self.buffer(name, buffer);
        }
    }

    /// Registers another shader name for an existing resource without erasing
    /// its allocation identity or logical view extent.
    pub(crate) fn alias(&mut self, name: &'static str, existing: &str) -> Result<()> {
        let resource = self
            .resources
            .get(existing)
            .cloned()
            .ok_or_else(|| anyhow::anyhow!("GPU resource `{existing}` is not registered"))?;
        let identity = *self
            .graph_identities
            .get(existing)
            .ok_or_else(|| anyhow::anyhow!("GPU resource `{existing}` has no tracked identity"))?;
        self.resources.insert(name.to_owned(), resource);
        self.graph_identities.insert(name.to_owned(), identity);
        Ok(())
    }

    /// Registers every graph-owned buffer under its canonical resource name
    /// and under reflected binding names that identify exactly one resource.
    /// Ambiguous operation-local names (for example radix ping-pong inputs)
    /// remain explicit overrides at the operation boundary.
    pub(crate) fn register_graph_bindings(
        &mut self,
        graph: &CompilerGraph,
        bindings: &'a CompilerGraphBindings,
    ) {
        for (resource, buffer) in bindings.iter() {
            self.buffer(
                graph
                    .resource(resource)
                    .expect("graph binding resource")
                    .name,
                buffer,
            );
        }
        for (name, resource) in graph.resource_aliases() {
            if let Some(buffer) = bindings.buffer(resource) {
                self.buffer(name, buffer);
            }
        }

        let mut binding_resources = HashMap::<&'static str, Option<ResourceId>>::new();
        for access in graph.passes().iter().flat_map(|pass| pass.accesses.iter()) {
            binding_resources
                .entry(access.binding)
                .and_modify(|resource| {
                    if *resource != Some(access.resource) {
                        *resource = None;
                    }
                })
                .or_insert(Some(access.resource));
        }
        for (name, resource) in binding_resources {
            if let Some(buffer) = resource.and_then(|resource| bindings.buffer(resource)) {
                self.buffer(name, buffer);
            }
        }
    }

    /// Registers only the graph-owned resources used by one operation.
    /// Operation caches should prefer this over importing the whole graph:
    /// construction cost then scales with the shader interface rather than
    /// with every resource declared by a large compiler phase.
    pub(crate) fn register_pass_bindings(
        &mut self,
        graph: &CompilerGraph,
        bindings: &'a CompilerGraphBindings,
        pass_name: &str,
    ) -> Result<()> {
        let pass = graph
            .pass_id(pass_name)
            .and_then(|pass| graph.pass(pass))
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{pass_name}`"))?;
        for access in &pass.accesses {
            let Some(buffer) = bindings.buffer(access.resource) else {
                continue;
            };
            let canonical = graph
                .resource(access.resource)
                .expect("pass access resource came from graph")
                .name;
            self.buffer(canonical, buffer);
            self.buffer(access.binding, buffer);
        }
        Ok(())
    }

    /// Rebinds one logical graph resource and every reflected name that refers
    /// to it. Phase imports use this after registering the resident workspace,
    /// so bind-group construction and ownership validation see the same view.
    pub(crate) fn graph_buffer<B>(
        &mut self,
        graph: &CompilerGraph,
        name: &str,
        buffer: B,
    ) -> Result<()>
    where
        B: ResourceBinding<'a> + Copy,
    {
        let resource = graph
            .resource_id(name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no resource `{name}`"))?;
        self.buffer(
            graph.resource(resource).expect("graph resource id").name,
            buffer,
        );
        for (alias, target) in graph.resource_aliases() {
            if target == resource {
                self.buffer(alias, buffer);
            }
        }
        for access in graph
            .passes()
            .iter()
            .flat_map(|pass| pass.accesses.iter())
            .filter(|access| access.resource == resource)
        {
            self.buffer(access.binding, buffer);
        }
        Ok(())
    }

    /// Logical number of `u32` rows exposed by a registered typed view.
    pub(crate) fn logical_u32_count(&self, name: &str) -> Result<u32> {
        let identity = self
            .graph_identities
            .get(name)
            .ok_or_else(|| anyhow::anyhow!("type-check resource `{name}` is not registered"))?;
        Ok((identity.logical_byte_size / 4).min(u64::from(u32::MAX)) as u32)
    }

    /// Resolves one graph pass's concrete storage bindings from the same
    /// name-keyed registry used to construct its reflected bind group.
    ///
    /// This keeps shader recording and ownership validation single-sourced:
    /// adding or changing a binding cannot silently update one description
    /// while leaving the other pointed at a different allocation.
    pub(crate) fn graph_bindings(
        &self,
        graph: &CompilerGraph,
        pass_name: &str,
    ) -> Result<Vec<BoundGraphResource>> {
        self.graph_bindings_with_aliases(graph, pass_name, &[])
    }

    /// Resolves a pass whose reflected binding names deliberately select
    /// different physical ping-pong buffers in different graph nodes.
    pub(crate) fn graph_bindings_with_aliases(
        &self,
        graph: &CompilerGraph,
        pass_name: &str,
        aliases: &[(&str, &str)],
    ) -> Result<Vec<BoundGraphResource>> {
        let pass = graph
            .pass_id(pass_name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{pass_name}`"))?;
        let mut bindings = Vec::new();
        for access in &graph
            .pass(pass)
            .expect("pass id came from this graph")
            .accesses
        {
            let explicit_name = aliases.iter().find_map(|(binding, registered)| {
                (*binding == access.binding).then_some(*registered)
            });
            let canonical_name = graph
                .resource(access.resource)
                .expect("pass access resource belongs to graph")
                .name;
            // Reflected binding names such as `scan_input` are deliberately
            // reused by many graph operations. They are therefore not stable
            // resource identities in a phase-wide registry. The graph's
            // canonical resource is authoritative unless the operation gives
            // an explicit local override (for example a radix ping-pong lane).
            // Falling back to the reflected name keeps small operation-local
            // registries valid when they contain no canonical graph names.
            let resolved = explicit_name
                .and_then(|name| self.graph_identities.get(name).map(|identity| (name, identity)))
                .or_else(|| {
                    self.graph_identities
                        .get(canonical_name)
                        .map(|identity| (canonical_name, identity))
                })
                .or_else(|| {
                    self.graph_identities
                        .get(access.binding)
                        .map(|identity| (access.binding, identity))
                })
                .ok_or_else(|| {
                    anyhow::anyhow!(
                        "compiler pass `{pass_name}` binding `{}` has no registered buffer for its explicit override {:?}, canonical resource `{canonical_name}`, or reflected name",
                        access.binding,
                        explicit_name,
                    )
                })?;
            let (_, identity) = resolved;
            let bound = graph
                .bind_registered_resource(
                    access.binding,
                    access.resource,
                    identity.allocation_id,
                    identity.byte_offset,
                    identity.byte_size,
                )
                .map_err(anyhow::Error::msg)?;
            if !bindings.contains(&bound) {
                bindings.push(bound);
            }
        }
        Ok(bindings)
    }

    /// Validates one operation pass against the graph attached to this
    /// registry. Operation constructors call this while creating bind groups,
    /// so callers do not maintain a second pass-by-pass validation schedule.
    pub(crate) fn validate_graph_pass(
        &self,
        pass_name: &str,
        aliases: &[(&str, &str)],
    ) -> Result<()> {
        let context = self.graph_context.ok_or_else(|| {
            anyhow::anyhow!(
                "GPU resource registry has no compiler graph while validating `{pass_name}`"
            )
        })?;
        let pass = context
            .graph
            .pass_id(pass_name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{pass_name}`"))?;
        let bindings = self.graph_bindings_with_aliases(context.graph, pass_name, aliases)?;
        context
            .allocations
            .validate_pass_bindings(context.graph, pass, &bindings)
            .map_err(anyhow::Error::msg)
    }

    pub(crate) fn validate_graph_passes<'b>(
        &self,
        passes: impl IntoIterator<Item = &'b str>,
    ) -> Result<()> {
        for pass in passes {
            self.validate_graph_pass(pass, &[])?;
        }
        Ok(())
    }

    pub(crate) fn validate_graph_passes_if_present<'b>(
        &self,
        passes: impl IntoIterator<Item = &'b str>,
    ) -> Result<()> {
        let context = self.graph_context.ok_or_else(|| {
            anyhow::anyhow!("GPU resource registry has no attached compiler graph")
        })?;
        for pass in passes {
            if context.graph.pass_id(pass).is_some() {
                self.validate_graph_pass(pass, &[])?;
            }
        }
        Ok(())
    }
}

/// Builds a reflected bind group from any name-keyed registry plus a small set
/// of operation-local aliases.
pub(crate) fn reflected_bind_group_with_overrides<'a>(
    device: &wgpu::Device,
    label: &str,
    pass: &PassData,
    resources: &HashMap<String, wgpu::BindingResource<'a>>,
    overrides: &[(&str, wgpu::BindingResource<'a>)],
) -> Result<wgpu::BindGroup> {
    let mut bindings = resources.clone();
    for (name, resource) in overrides {
        bindings.insert((*name).to_owned(), resource.clone());
    }
    bind_group::create_bind_group_from_reflection(
        device,
        Some(label),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &bindings,
    )
}

impl<'a> std::ops::Deref for ResourceMap<'a> {
    type Target = HashMap<String, wgpu::BindingResource<'a>>;

    fn deref(&self) -> &Self::Target {
        &self.resources
    }
}

/// Builds a reflected bind group from the first layout in a loaded pass.
pub(crate) fn reflected_bind_group_from_resources(
    device: &wgpu::Device,
    label: &'static str,
    pass: &PassData,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
) -> Result<wgpu::BindGroup> {
    bind_group::create_bind_group_from_reflection(
        device,
        Some(label),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        resources,
    )
}

/// Clones one reflected buffer binding without discarding its logical range.
///
/// Returning the raw `wgpu::Buffer` here is incorrect for arena-backed
/// resources: rebinding that handle would silently reset the offset to zero
/// and expose the entire physical uber-buffer.
pub(crate) fn buffer_binding_from_resources<'buffer>(
    resources: &HashMap<String, wgpu::BindingResource<'buffer>>,
    name: &str,
) -> Result<wgpu::BindingResource<'buffer>> {
    match resources.get(name) {
        Some(wgpu::BindingResource::Buffer(binding)) => {
            Ok(wgpu::BindingResource::Buffer(binding.clone()))
        }
        Some(_) => Err(anyhow::anyhow!(
            "type-check resource `{name}` is not a buffer binding"
        )),
        None => Err(anyhow::anyhow!(
            "type-check resource `{name}` is not registered"
        )),
    }
}

/// Reconstructs a typed logical view without discarding an arena binding's
/// byte range or compiler allocation identity.
pub(crate) fn typed_buffer_from_resources<T>(
    resources: &ResourceMap<'_>,
    name: &str,
) -> Result<LaniusBuffer<T>> {
    let binding = match resources.resources.get(name) {
        Some(wgpu::BindingResource::Buffer(binding)) => binding,
        Some(_) => return Err(anyhow::anyhow!("GPU resource `{name}` is not a buffer")),
        None => return Err(anyhow::anyhow!("GPU resource `{name}` is not registered")),
    };
    let identity = resources
        .graph_identities
        .get(name)
        .ok_or_else(|| anyhow::anyhow!("GPU resource `{name}` has no range identity"))?;
    let element_bytes = std::mem::size_of::<T>() as u64;
    if element_bytes == 0 || identity.logical_byte_size % element_bytes != 0 {
        return Err(anyhow::anyhow!(
            "GPU resource `{name}` is incompatible with the requested element type"
        ));
    }
    let count = usize::try_from(identity.logical_byte_size / element_bytes)
        .map_err(|_| anyhow::anyhow!("GPU resource `{name}` exceeds host addressable size"))?;
    Ok(TrackedBufferView::from_parts(
        binding.buffer,
        identity.byte_offset,
        identity.byte_size,
        identity.allocation_id,
    )
    .alias(count))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::gpu::{
        compiler_graph::{
            CompilerGraphBuilder,
            CompilerPhase,
            PassAccess,
            PassDesc,
            ResourceClass,
            ResourceDesc,
            ResourceDomain,
        },
        workspace::WorkspaceUsageClass,
    };

    #[test]
    fn graph_binding_resolution_prefers_canonical_resource_over_ambiguous_shader_name() {
        let mut builder = CompilerGraphBuilder::new();
        let input = builder
            .add_resource(ResourceDesc {
                name: "canonical.scan.input",
                domain: ResourceDomain::OptimizationNodes,
                class: ResourceClass::Input,
                bytes: 64,
                usage: WorkspaceUsageClass::Storage,
            })
            .unwrap();
        builder
            .add_pass(PassDesc {
                name: "scan.local",
                phase: CompilerPhase::Optimization,
                dispatch_domain: ResourceDomain::OptimizationNodes,
                accesses: vec![PassAccess::read("scan_input", input)],
            })
            .unwrap();
        let graph = builder.build().unwrap();

        let mut resources = ResourceMap::new();
        resources.graph_identities.insert(
            "scan_input".to_owned(),
            GraphResourceIdentity {
                allocation_id: Some(1),
                byte_offset: 0,
                byte_size: 16,
                logical_byte_size: 16,
            },
        );
        resources.graph_identities.insert(
            "canonical.scan.input".to_owned(),
            GraphResourceIdentity {
                allocation_id: Some(2),
                byte_offset: 256,
                byte_size: 64,
                logical_byte_size: 64,
            },
        );

        let bindings = resources.graph_bindings(&graph, "scan.local").unwrap();
        assert_eq!(bindings.len(), 1);
        assert_eq!(bindings[0].allocation_id, 2);
        assert_eq!(bindings[0].byte_offset, 256);
        assert_eq!(bindings[0].byte_size, 64);
    }
}
