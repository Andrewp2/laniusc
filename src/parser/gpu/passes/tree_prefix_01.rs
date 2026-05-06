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
    pub uses_ll1: u32,
    pub n_node_blocks: u32,
    pub n_prefix_blocks: u32,
    pub scan_step: u32,
}

pub struct TreePrefixLocalPass {
    data: PassData,
}

impl TreePrefixLocalPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "tree_prefix_01_local",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/tree_prefix_01_local.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/tree_prefix_01_local.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for TreePrefixLocalPass {
    const NAME: &'static str = "tree_prefix_01_local";
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
            ("gTree".into(), b.tree_prefix_params.as_entire_binding()),
            (
                "emit_stream".into(),
                if b.tree_stream_uses_ll1 {
                    b.ll1_emit.as_entire_binding()
                } else {
                    b.out_emit.as_entire_binding()
                },
            ),
            (
                "ll1_status".into(),
                if b.tree_count_uses_status && !b.tree_stream_uses_ll1 {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("prod_arity".into(), b.prod_arity.as_entire_binding()),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            (
                "prefix_inblock".into(),
                b.tree_prefix_inblock.as_entire_binding(),
            ),
            ("block_sum".into(), b.tree_block_sum.as_entire_binding()),
        ])
    }
}
