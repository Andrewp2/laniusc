use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalPathMarkPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalPathMarkPass, label: "hir_canonical_path_mark", shader: "parser/hir/canonical/paths/mark");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalPathMarkPass {
    const NAME: &'static str = "hir_canonical_path_mark";
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
                "segment_count".into(),
                b.hir_path_segment_table_count.as_entire_binding(),
            ),
            (
                "path_segments".into(),
                b.hir_path_segment_rows.as_entire_binding(),
            ),
            (
                "family_flag".into(),
                b.hir_path_family_flag.as_entire_binding(),
            ),
        ])
    }
}
