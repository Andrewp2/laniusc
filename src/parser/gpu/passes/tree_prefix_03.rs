use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::gpu::buffers::ParserBuffers,
};

pub struct TreePrefixApplyPass {
    data: PassData,
}

impl TreePrefixApplyPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "tree_prefix_03_apply",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/tree_prefix_03_apply.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/tree_prefix_03_apply.reflect.json"
            )),
        )?;
        Ok(Self { data })
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for TreePrefixApplyPass {
    const NAME: &'static str = "tree_prefix_03_apply";
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
                "ll1_status".into(),
                if b.tree_count_uses_status && !b.tree_stream_uses_ll1 {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            (
                "prefix_inblock".into(),
                b.tree_prefix_inblock.as_entire_binding(),
            ),
            ("block_sum".into(), b.tree_block_sum.as_entire_binding()),
            (
                "block_prefix".into(),
                b.tree_block_prefix.as_entire_binding(),
            ),
            ("tree_prefix".into(), b.tree_prefix.as_entire_binding()),
            (
                "prefix_block_max".into(),
                b.tree_prefix_block_max.as_entire_binding(),
            ),
        ])
    }
}
