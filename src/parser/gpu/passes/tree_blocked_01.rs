use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::gpu::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct Params {
    pub n: u32,
    pub block_size: u32,
}

pub struct TreeBlockLocalPass {
    data: PassData,
}

impl TreeBlockLocalPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "tree_blocked_01_local",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/tree_blocked_01_local.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/tree_blocked_01_local.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for TreeBlockLocalPass {
    const NAME: &'static str = "tree_blocked_01_local";
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
            ("gTB".into(), b.tb01_params.as_entire_binding()),
            ("emit_stream".into(), b.out_emit.as_entire_binding()),
            ("prod_arity".into(), b.prod_arity.as_entire_binding()),
            ("end_off".into(), b.tb_end_off.as_entire_binding()),
            ("end_nodes".into(), b.tb_end_nodes.as_entire_binding()),
            ("end_rem".into(), b.tb_end_rem.as_entire_binding()),
        ])
    }
}
