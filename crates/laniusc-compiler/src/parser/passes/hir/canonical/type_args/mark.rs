use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalTypeArgMarkPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalTypeArgMarkPass, label: "hir_canonical_type_arg_mark", shader: "parser/hir/canonical/type_args/mark");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalTypeArgMarkPass {
    const NAME: &'static str = "hir_canonical_type_arg_mark";
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
            (
                "hir_type_arg_owner".into(),
                b.hir_type_arg_owner_a.as_entire_binding(),
            ),
            (
                "hir_type_arg_rank".into(),
                b.hir_type_arg_rank_a.as_entire_binding(),
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_type_arg_start".into(),
                b.hir_type_arg_start.as_entire_binding(),
            ),
            (
                "hir_type_arg_count".into(),
                b.hir_type_arg_count.as_entire_binding(),
            ),
            (
                "family_flag".into(),
                b.hir_type_arg_family_flag.as_entire_binding(),
            ),
        ])
    }
}
