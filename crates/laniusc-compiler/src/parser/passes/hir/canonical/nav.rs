use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalNavPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalNavPass,
    label: "hir_canonical_nav",
    shader: "parser/hir/canonical/nav"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalNavPass {
    const NAME: &'static str = "hir_canonical_nav";
    const DIM: DispatchDim = DispatchDim::D1;
    fn from_data(data: PassData) -> Self {
        Self { data }
    }
    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a ParserBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            (
                "gCanonical".into(),
                b.hir_canonical_params.as_entire_binding(),
            ),
            (
                "canonical_count".into(),
                b.hir_canonical_count.as_entire_binding(),
            ),
            ("hir_core".into(), b.hir_core.as_entire_binding()),
            ("hir_links".into(), b.hir_links.as_entire_binding()),
        ])
    }
}
