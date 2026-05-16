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
    pub wg_size: u32,
}

pub struct BracketsApplyPrefixPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    BracketsApplyPrefixPass,
    label: "brackets_03_apply_prefix",
    shader: "brackets_03_apply_prefix"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for BracketsApplyPrefixPass {
    const NAME: &'static str = "brackets_03_apply_prefix";
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
            ("gParams".into(), b.b03_params.as_entire_binding()),
            ("sc_stream".into(), b.out_sc.as_entire_binding()),
            (
                "exscan_inblock".into(),
                b.b_exscan_inblock.as_entire_binding(),
            ),
            ("block_prefix".into(), b.b_block_prefix.as_entire_binding()),
            // read-only view of depths for offset
            ("out_depths_ro".into(), b.depths_out.as_entire_binding()),
            ("depth_exscan".into(), b.b_depth_exscan.as_entire_binding()),
            ("layer".into(), b.b_layer.as_entire_binding()),
        ])
    }
}
