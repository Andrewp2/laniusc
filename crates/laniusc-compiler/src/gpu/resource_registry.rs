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
    /// a tracked `LaniusBuffer`, plus the complete bound byte extent.
    fn graph_identity(self) -> (Option<u64>, u64);

    /// Logical byte extent of this view, which may be smaller than its aliased
    /// physical allocation.
    fn logical_byte_size(self) -> u64;
}

impl<'a> ResourceBinding<'a> for &'a wgpu::Buffer {
    fn binding(self) -> wgpu::BindingResource<'a> {
        self.as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64) {
        (None, self.size())
    }

    fn logical_byte_size(self) -> u64 {
        self.size()
    }
}

impl<'a, 'b> ResourceBinding<'a> for &'b &'a wgpu::Buffer {
    fn binding(self) -> wgpu::BindingResource<'a> {
        (*self).as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64) {
        (None, self.size())
    }

    fn logical_byte_size(self) -> u64 {
        self.size()
    }
}

impl<'a, T> ResourceBinding<'a> for &'a LaniusBuffer<T> {
    fn binding(self) -> wgpu::BindingResource<'a> {
        self.as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64) {
        (self.allocation_id(), self.byte_size as u64)
    }

    fn logical_byte_size(self) -> u64 {
        (self.count as u64).saturating_mul(std::mem::size_of::<T>() as u64)
    }
}

impl<'a> ResourceBinding<'a> for TrackedBufferView<'a> {
    fn binding(self) -> wgpu::BindingResource<'a> {
        self.as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64) {
        (self.allocation_id(), self.byte_size)
    }

    fn logical_byte_size(self) -> u64 {
        self.byte_size
    }
}

impl<'a, 'b, T> ResourceBinding<'a> for &'b &'a LaniusBuffer<T> {
    fn binding(self) -> wgpu::BindingResource<'a> {
        (*self).as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64) {
        (self.allocation_id(), self.byte_size as u64)
    }

    fn logical_byte_size(self) -> u64 {
        (self.count as u64).saturating_mul(std::mem::size_of::<T>() as u64)
    }
}

#[derive(Clone, Copy)]
struct GraphResourceIdentity {
    allocation_id: Option<u64>,
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

    /// Associates this registry with the graph that owns its logical buffers.
    /// Cloned operation-local registries retain this contract automatically.
    pub(crate) fn attach_graph(
        &mut self,
        graph: &'a CompilerGraph,
        allocations: &'a CompilerGraphAllocations,
    ) {
        self.graph_context = Some(GraphContext { graph, allocations });
    }

    /// Clones the lightweight binding views for an operation that needs a
    /// small set of local aliases or uniform overrides.
    pub(crate) fn to_binding_map(&self) -> HashMap<String, wgpu::BindingResource<'a>> {
        self.resources.clone()
    }

    /// Inserts a prebuilt binding resource under the shader resource name.
    pub(crate) fn add(&mut self, name: &'static str, resource: wgpu::BindingResource<'a>) {
        // Raw upstream buffers are valid immutable graph inputs even when
        // they are not wrapped in `LaniusBuffer`. Preserve their extent here;
        // writable graph resources still fail validation without an owned
        // allocation identity.
        if let wgpu::BindingResource::Buffer(binding) = &resource {
            let byte_size = binding
                .size
                .map(std::num::NonZeroU64::get)
                .unwrap_or_else(|| binding.buffer.size().saturating_sub(binding.offset));
            self.graph_identities.insert(
                name.to_owned(),
                GraphResourceIdentity {
                    allocation_id: None,
                    byte_size,
                    logical_byte_size: byte_size,
                },
            );
        }
        self.resources.insert(name.to_owned(), resource);
    }

    /// Inserts a buffer-like value under the shader resource name.
    pub(crate) fn buffer<B>(&mut self, name: &'static str, buffer: B)
    where
        B: ResourceBinding<'a> + Copy,
    {
        let (allocation_id, byte_size) = buffer.graph_identity();
        let logical_byte_size = buffer.logical_byte_size();
        self.add(name, buffer.binding());
        self.graph_identities.insert(
            name.to_owned(),
            GraphResourceIdentity {
                allocation_id,
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

    /// Builds one reflected bind group from the shared resource registry,
    /// replacing only the bindings which are local to this invocation.
    ///
    /// Most compiler passes bind resources by their Slang names.  Algorithms
    /// such as radix sort additionally have a per-step uniform and ping-pong
    /// input/output aliases.  Keeping those few aliases here lets reflection
    /// remain the source of truth for the rest of the shader interface.
    pub(crate) fn reflected_bind_group_with_overrides(
        &self,
        device: &wgpu::Device,
        label: &str,
        pass: &PassData,
        overrides: &[(&str, wgpu::BindingResource<'a>)],
    ) -> Result<wgpu::BindGroup> {
        reflected_bind_group_with_overrides(device, label, pass, &self.resources, overrides)
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
            let registered_name = aliases
                .iter()
                .find_map(|(binding, registered)| {
                    (*binding == access.binding).then_some(*registered)
                })
                .unwrap_or(access.binding);
            let canonical_name = graph
                .resource(access.resource)
                .expect("pass access resource belongs to graph")
                .name;
            let identity = self
                .graph_identities
                .get(registered_name)
                .or_else(|| self.graph_identities.get(canonical_name))
                .ok_or_else(|| {
                    anyhow::anyhow!(
                        "compiler pass `{pass_name}` binding `{}` maps to `{registered_name}` (canonical resource `{canonical_name}`), which is not registered as a buffer",
                        access.binding,
                    )
                })?;
            let bound = graph
                .bind_registered_resource(
                    access.binding,
                    access.resource,
                    identity.allocation_id,
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

/// Borrows the buffer behind one reflected binding resource.
pub(crate) fn buffer_from_resources<'buffer>(
    resources: &HashMap<String, wgpu::BindingResource<'buffer>>,
    name: &str,
) -> Result<&'buffer wgpu::Buffer> {
    match resources.get(name) {
        Some(wgpu::BindingResource::Buffer(binding)) => Ok(binding.buffer),
        Some(_) => Err(anyhow::anyhow!(
            "type-check resource `{name}` is not a buffer binding"
        )),
        None => Err(anyhow::anyhow!(
            "type-check resource `{name}` is not registered"
        )),
    }
}
