use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct Params {
    pub n_sc: u32,
}

pub struct BracketsClearMatchesPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    BracketsClearMatchesPass,
    label: "brackets_04_clear_matches",
    shader: "parser/brackets/04_clear_matches"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for BracketsClearMatchesPass {
    const NAME: &'static str = "brackets_04_clear_matches";
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
                "gClear".into(),
                b.b_clear_matches_params.as_entire_binding(),
            ),
            (
                "partial_parse_status".into(),
                b.partial_parse_status.as_entire_binding(),
            ),
            (
                "match_for_index".into(),
                b.match_for_index.as_entire_binding(),
            ),
        ])
    }
}
