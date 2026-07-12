use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};
pub struct HirStringOffsetScatterPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirStringOffsetScatterPass, label: "hir_string_offset_scatter", shader: "parser/hir/string/offset_scatter");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirStringOffsetScatterPass {
    const NAME: &'static str = "hir_string_offset_scatter";
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
                "hir_list_rank_local_prefix".into(),
                b.hir_list_rank_local_prefix.as_entire_binding(),
            ),
            (
                "hir_list_rank_block_prefix".into(),
                b.hir_list_rank_block_prefix_a.as_entire_binding(),
            ),
            (
                "hir_string_data_offset".into(),
                b.hir_string_data_offset.as_entire_binding(),
            ),
            (
                "hir_string_pool_len".into(),
                b.hir_string_pool_len.as_entire_binding(),
            ),
        ])
    }
}
