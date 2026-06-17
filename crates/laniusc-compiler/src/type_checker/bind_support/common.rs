use super::super::*;

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

pub(in crate::type_checker) struct ResourceMap<'a> {
    resources: HashMap<String, wgpu::BindingResource<'a>>,
}

impl<'a> ResourceMap<'a> {
    pub(in crate::type_checker) fn new() -> Self {
        Self {
            resources: HashMap::new(),
        }
    }

    pub(in crate::type_checker) fn add(
        &mut self,
        name: &'static str,
        resource: wgpu::BindingResource<'a>,
    ) {
        self.resources.insert(name.to_owned(), resource);
    }

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
