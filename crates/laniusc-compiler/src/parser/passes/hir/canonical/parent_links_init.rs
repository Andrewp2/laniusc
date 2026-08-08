use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalParentLinksInitPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalParentLinksInitPass,
    label: "hir_canonical_parent_links_init",
    shader: "parser/hir/canonical/parent_links_init"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalParentLinksInitPass {
    const NAME: &'static str = "hir_canonical_parent_links_init";
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
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("parent".into(), b.parent.as_entire_binding()),
            (
                "canonical_flag".into(),
                b.hir_semantic_flag.as_entire_binding(),
            ),
            (
                "canonical_prefix_before_raw".into(),
                b.hir_canonical_prefix_before_raw.as_entire_binding(),
            ),
            (
                "parent_link_a".into(),
                b.hir_semantic_parent_link_a.as_entire_binding(),
            ),
            (
                "parent_value_a".into(),
                b.hir_semantic_parent_value_a.as_entire_binding(),
            ),
        ])
    }
}
