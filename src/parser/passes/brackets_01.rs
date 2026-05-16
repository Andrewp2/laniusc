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

pub struct BracketsScanInblockPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    BracketsScanInblockPass,
    label: "brackets_01_scan_inblock",
    shader: "brackets_01_scan_inblock"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for BracketsScanInblockPass {
    const NAME: &'static str = "brackets_01_scan_inblock";
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
            ("gParams".into(), b.b01_params.as_entire_binding()),
            ("sc_stream".into(), b.out_sc.as_entire_binding()),
            (
                "exscan_inblock".into(),
                b.b_exscan_inblock.as_entire_binding(),
            ),
            ("block_sum".into(), b.b_block_sum.as_entire_binding()),
            (
                "block_minpref".into(),
                b.b_block_minpref.as_entire_binding(),
            ),
            (
                "block_maxdepth".into(),
                b.b_block_maxdepth.as_entire_binding(),
            ),
        ])
    }
}
