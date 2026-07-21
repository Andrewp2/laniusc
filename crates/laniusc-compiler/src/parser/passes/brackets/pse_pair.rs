use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for bracket pairing by layer/rank.
pub struct Params {
    pub n_sc: u32,
    pub n_blocks: u32,
    pub leaf_base: u32,
    pub typed_check: u32,
    pub emit_matches: u32,
}

/// Pass that pairs bracket pushes and pops by layer/rank.
pub struct BracketsPsePairPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    BracketsPsePairPass,
    label: "brackets_pse_04_pair_by_layer",
    shader: "parser/brackets/pse_04_pair_by_layer"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for BracketsPsePairPass {
    const NAME: &'static str = "brackets_pse_04_pair_by_layer";
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
            ("gParams".into(), b.b07_params.as_entire_binding()),
            ("sc_stream".into(), b.out_sc.as_entire_binding()),
            (
                "partial_parse_status".into(),
                b.partial_parse_status.as_entire_binding(),
            ),
            ("layer".into(), b.b_layer.as_entire_binding()),
            (
                "block_row_min".into(),
                b.b_block_row_min.as_entire_binding(),
            ),
            ("block_prefix".into(), b.b_block_prefix.as_entire_binding()),
            ("min_tree".into(), b.b_min_tree.as_entire_binding()),
            (
                "match_for_index".into(),
                b.match_for_index.as_entire_binding(),
            ),
            ("out_valid".into(), b.valid_out.as_entire_binding()),
        ])
    }
}
