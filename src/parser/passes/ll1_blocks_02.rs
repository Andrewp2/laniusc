use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub const LL1_SEED_PLAN_STATUS_WORDS: usize = 8;

pub struct LL1BlocksStitchPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    LL1BlocksStitchPass,
    label: "ll1_blocks_02_stitch",
    shader: "ll1_blocks_02_stitch"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for LL1BlocksStitchPass {
    const NAME: &'static str = "ll1_blocks_02_stitch";
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
            ("token_kinds".into(), b.token_kinds.as_entire_binding()),
            ("token_count".into(), b.token_count.as_entire_binding()),
            ("ll1_predict".into(), b.ll1_predict.as_entire_binding()),
            (
                "prod_rhs_off".into(),
                b.ll1_prod_rhs_off.as_entire_binding(),
            ),
            (
                "prod_rhs_len".into(),
                b.ll1_prod_rhs_len.as_entire_binding(),
            ),
            ("prod_rhs".into(), b.ll1_prod_rhs.as_entire_binding()),
            (
                "block_seed_len".into(),
                b.ll1_block_seed_len.as_entire_binding(),
            ),
            (
                "block_seed_stack".into(),
                b.ll1_block_seed_stack.as_entire_binding(),
            ),
            (
                "seed_plan_status".into(),
                b.ll1_seed_plan_status.as_entire_binding(),
            ),
            ("gParams".into(), b.params_ll1_blocks.as_entire_binding()),
        ])
    }
}
