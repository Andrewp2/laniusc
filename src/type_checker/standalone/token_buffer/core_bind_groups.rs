use std::collections::HashMap;

use super::{super::super::*, passes::TokenTypeCheckPasses};

pub(super) struct CoreBindGroups {
    pub(super) tokens: wgpu::BindGroup,
    pub(super) control: wgpu::BindGroup,
    pub(super) scope: wgpu::BindGroup,
}

impl CoreBindGroups {
    pub(super) fn create(
        device: &wgpu::Device,
        passes: &TokenTypeCheckPasses,
        resources: &HashMap<String, wgpu::BindingResource<'_>>,
    ) -> Result<Self, GpuTypeCheckError> {
        Ok(Self {
            tokens: bind_group::create_bind_group_from_reflection(
                device,
                Some("type_check_tokens"),
                &passes.tokens.bind_group_layouts[0],
                &passes.tokens.reflection,
                0,
                resources,
            )?,
            control: bind_group::create_bind_group_from_reflection(
                device,
                Some("type_check_control"),
                &passes.control.bind_group_layouts[0],
                &passes.control.reflection,
                0,
                resources,
            )?,
            scope: bind_group::create_bind_group_from_reflection(
                device,
                Some("type_check_scope"),
                &passes.scope.bind_group_layouts[0],
                &passes.scope.reflection,
                0,
                resources,
            )?,
        })
    }
}
