use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::gpu::buffers::ParserBuffers,
};

pub struct LL1BlocksFlattenEmitPass {
    data: PassData,
}

impl LL1BlocksFlattenEmitPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let spirv = include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/ll1_blocks_04_flatten_emit.spv"
        ));
        let reflect = include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/ll1_blocks_04_flatten_emit.reflect.json"
        ));
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "ll1_blocks_04_flatten_emit",
            "main",
            spirv,
            reflect,
        )?;
        Ok(Self { data })
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for LL1BlocksFlattenEmitPass {
    const NAME: &'static str = "ll1_blocks_04_flatten_emit";
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
                "seeded_status".into(),
                b.ll1_seeded_status.as_entire_binding(),
            ),
            ("seeded_emit".into(), b.ll1_seeded_emit.as_entire_binding()),
            (
                "seeded_emit_pos".into(),
                b.ll1_seeded_emit_pos.as_entire_binding(),
            ),
            ("token_count".into(), b.token_count.as_entire_binding()),
            (
                "block_emit_prefix".into(),
                b.ll1_emit_prefix_a.as_entire_binding(),
            ),
            (
                "block_status_summary_prefix".into(),
                b.ll1_status_summary_a.as_entire_binding(),
            ),
            (
                "seed_plan_status".into(),
                b.ll1_seed_plan_status.as_entire_binding(),
            ),
            ("ll1_emit".into(), b.ll1_emit.as_entire_binding()),
            ("ll1_emit_pos".into(), b.ll1_emit_pos.as_entire_binding()),
            ("ll1_status".into(), b.ll1_status.as_entire_binding()),
            ("gParams".into(), b.params_ll1_blocks.as_entire_binding()),
        ])
    }
}
