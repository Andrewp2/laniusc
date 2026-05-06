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
    pub n_prefix_blocks: u32,
    pub max_tree_leaf_base: u32,
}

pub struct TreeParentPass {
    data: PassData,
}

impl TreeParentPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "tree_parent_parallel",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/tree_parent_parallel.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/tree_parent_parallel.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for TreeParentPass {
    const NAME: &'static str = "tree_parent_parallel";
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
            ("gTree".into(), b.tree_params.as_entire_binding()),
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
            ("tree_prefix".into(), b.tree_prefix.as_entire_binding()),
            (
                "prefix_block_max".into(),
                b.tree_prefix_block_max.as_entire_binding(),
            ),
            (
                "prefix_block_max_tree".into(),
                b.tree_prefix_block_max_tree.as_entire_binding(),
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
        ])
    }
}
