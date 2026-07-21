use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalCallArgMarkPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalCallArgMarkPass, label: "hir_canonical_call_arg_mark", shader: "parser/hir/canonical/call_args/mark");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalCallArgMarkPass {
    const NAME: &'static str = "hir_canonical_call_arg_mark";
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
                "canonical_raw_to_dense".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_call_arg_count".into(),
                b.hir_call_arg_count.as_entire_binding(),
            ),
            (
                "family_flag".into(),
                b.hir_call_arg_family_flag.as_entire_binding(),
            ),
        ])
    }
}
