use super::super::*;

/// Converts type-checker buffer wrappers into WGPU binding resources.
pub(in crate::type_checker) trait ResourceBinding<'a> {
    fn binding(self) -> wgpu::BindingResource<'a>;
}

impl<'a> ResourceBinding<'a> for &'a wgpu::Buffer {
    fn binding(self) -> wgpu::BindingResource<'a> {
        self.as_entire_binding()
    }
}

impl<'a, 'b> ResourceBinding<'a> for &'b &'a wgpu::Buffer {
    fn binding(self) -> wgpu::BindingResource<'a> {
        (*self).as_entire_binding()
    }
}

impl<'a, T> ResourceBinding<'a> for &'a LaniusBuffer<T> {
    fn binding(self) -> wgpu::BindingResource<'a> {
        self.as_entire_binding()
    }
}

/// Name-keyed binding resource map used by reflection-based bind-group builders.
pub(in crate::type_checker) struct ResourceMap<'a> {
    resources: HashMap<String, wgpu::BindingResource<'a>>,
}

impl<'a> ResourceMap<'a> {
    /// Creates an empty resource map for one bind-group construction phase.
    pub(in crate::type_checker) fn new() -> Self {
        Self {
            resources: HashMap::new(),
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
        B: ResourceBinding<'a>,
    {
        self.add(name, buffer.binding());
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
