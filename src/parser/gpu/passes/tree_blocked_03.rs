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

pub struct TreeBlockSeededPass {
    data: PassData,
}

impl TreeBlockSeededPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "tree_blocked_03_seeded",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/tree_blocked_03_seeded.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/tree_blocked_03_seeded.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for TreeBlockSeededPass {
    const NAME: &'static str = "tree_blocked_03_seeded";
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
            ("gTB".into(), b.tb03_params.as_entire_binding()),
            ("emit_stream".into(), b.out_emit.as_entire_binding()),
            ("prod_arity".into(), b.prod_arity.as_entire_binding()),
            ("start_off".into(), b.tb_start_off.as_entire_binding()),
            ("start_nodes".into(), b.tb_start_nodes.as_entire_binding()),
            ("start_rem".into(), b.tb_start_rem.as_entire_binding()),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
        ])
    }
}
