use super::super::*;

/// Converts type-checker buffer wrappers into WGPU binding resources.
pub(in crate::type_checker) trait ResourceBinding<'a> {
    fn binding(self) -> wgpu::BindingResource<'a>;

    /// Returns the compiler allocation identity when this binding is backed by
    /// a tracked `LaniusBuffer`, plus the complete bound byte extent.
    fn graph_identity(self) -> (Option<u64>, u64);
}

impl<'a> ResourceBinding<'a> for &'a wgpu::Buffer {
    fn binding(self) -> wgpu::BindingResource<'a> {
        self.as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64) {
        (None, self.size())
    }
}

impl<'a, 'b> ResourceBinding<'a> for &'b &'a wgpu::Buffer {
    fn binding(self) -> wgpu::BindingResource<'a> {
        (*self).as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64) {
        (None, self.size())
    }
}

impl<'a, T> ResourceBinding<'a> for &'a LaniusBuffer<T> {
    fn binding(self) -> wgpu::BindingResource<'a> {
        self.as_entire_binding()
    }

    fn graph_identity(self) -> (Option<u64>, u64) {
        (self.allocation_id(), self.byte_size as u64)
    }
}

#[derive(Clone, Copy)]
struct GraphResourceIdentity {
    allocation_id: Option<u64>,
    byte_size: u64,
}

/// Name-keyed binding resource map used by reflection-based bind-group builders.
pub(in crate::type_checker) struct ResourceMap<'a> {
    resources: HashMap<String, wgpu::BindingResource<'a>>,
    graph_identities: HashMap<String, GraphResourceIdentity>,
}

impl<'a> ResourceMap<'a> {
    /// Creates an empty resource map for one bind-group construction phase.
    pub(in crate::type_checker) fn new() -> Self {
        Self {
            resources: HashMap::new(),
            graph_identities: HashMap::new(),
        }
    }

    /// Inserts a prebuilt binding resource under the shader resource name.
    pub(in crate::type_checker) fn add(
        &mut self,
        name: &'static str,
        resource: wgpu::BindingResource<'a>,
    ) {
        self.resources.insert(name.to_owned(), resource);
    }

    /// Inserts a buffer-like value under the shader resource name.
    pub(in crate::type_checker) fn buffer<B>(&mut self, name: &'static str, buffer: B)
    where
        B: ResourceBinding<'a> + Copy,
    {
        let (allocation_id, byte_size) = buffer.graph_identity();
        self.graph_identities.insert(
            name.to_owned(),
            GraphResourceIdentity {
                allocation_id,
                byte_size,
            },
        );
        self.add(name, buffer.binding());
    }

    /// Resolves one graph pass's concrete storage bindings from the same
    /// name-keyed registry used to construct its reflected bind group.
    ///
    /// This keeps shader recording and ownership validation single-sourced:
    /// adding or changing a binding cannot silently update one description
    /// while leaving the other pointed at a different allocation.
    pub(in crate::type_checker) fn graph_bindings(
        &self,
        graph: &crate::gpu::compiler_graph::CompilerGraph,
        pass_name: &str,
    ) -> Result<Vec<crate::gpu::compiler_graph::BoundGraphResource>> {
        let pass = graph
            .pass_id(pass_name)
            .ok_or_else(|| anyhow::anyhow!("compiler graph has no pass `{pass_name}`"))?;
        graph
            .pass(pass)
            .expect("pass id came from this graph")
            .accesses
            .iter()
            .map(|access| {
                let identity = self.graph_identities.get(access.binding).ok_or_else(|| {
                    anyhow::anyhow!(
                        "compiler pass `{pass_name}` binding `{}` is not registered as a buffer",
                        access.binding,
                    )
                })?;
                graph
                    .bind_registered_resource(
                        access.binding,
                        access.resource,
                        identity.allocation_id,
                        identity.byte_size,
                    )
                    .map_err(anyhow::Error::msg)
            })
            .collect()
    }
}

impl<'a> std::ops::Deref for ResourceMap<'a> {
    type Target = HashMap<String, wgpu::BindingResource<'a>>;

    fn deref(&self) -> &Self::Target {
        &self.resources
    }
}

/// Builds a reflected bind group from the first layout in a loaded pass.
pub(in crate::type_checker) fn reflected_bind_group_from_resources(
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
pub(in crate::type_checker) fn buffer_from_resources<'buffer>(
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
