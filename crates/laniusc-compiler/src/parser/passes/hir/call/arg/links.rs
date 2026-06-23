use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that links call argument nodes to their owning call expression.
pub struct HirCallArgLinksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCallArgLinksPass,
    label: "hir_call_arg_links",
    shader: "parser/hir/call/arg/links"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCallArgLinksPass {
    const NAME: &'static str = "hir_call_arg_links";
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
                "gHirCall".into(),
                b.hir_call_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
            ("first_child".into(), b.first_child.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
            (
                "hir_call_arg_end".into(),
                b.hir_call_arg_end.as_entire_binding(),
            ),
            (
                "hir_call_arg_owner_a".into(),
                b.hir_call_arg_owner_a.as_entire_binding(),
            ),
            (
                "hir_call_arg_link_a".into(),
                b.hir_call_arg_link_a.as_entire_binding(),
            ),
            (
                "hir_call_arg_rank_a".into(),
                b.hir_call_arg_rank_a.as_entire_binding(),
            ),
            (
                "hir_call_arg_owner_b".into(),
                b.hir_call_arg_owner_b.as_entire_binding(),
            ),
            (
                "hir_call_arg_link_b".into(),
                b.hir_call_arg_link_b.as_entire_binding(),
            ),
            (
                "hir_call_arg_rank_b".into(),
                b.hir_call_arg_rank_b.as_entire_binding(),
            ),
        ])
    }
}
