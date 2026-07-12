use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};
pub struct HirStringCompactScatterPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirStringCompactScatterPass, label: "hir_string_compact_scatter", shader: "parser/hir/string/compact_scatter");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirStringCompactScatterPass {
    const NAME: &'static str = "hir_string_compact_scatter";
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
                "gHirString".into(),
                b.hir_type_fields_params.as_entire_binding(),
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
                "hir_list_rank_flag".into(),
                b.hir_list_rank_flag.as_entire_binding(),
            ),
            (
                "hir_list_rank_local_prefix".into(),
                b.hir_list_rank_local_prefix.as_entire_binding(),
            ),
            (
                "hir_list_rank_block_prefix".into(),
                b.hir_list_rank_block_prefix_a.as_entire_binding(),
            ),
            (
                "hir_string_node".into(),
                b.hir_string_node.as_entire_binding(),
            ),
            (
                "hir_string_count".into(),
                b.hir_string_count.as_entire_binding(),
            ),
            (
                "hir_list_rank_dispatch_args".into(),
                b.hir_list_rank_dispatch_args.as_entire_binding(),
            ),
        ])
    }
}
