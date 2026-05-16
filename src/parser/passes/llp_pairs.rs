use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct LLPParams {
    pub n_tokens: u32,
    pub n_kinds: u32,
}

pub struct LLPPairsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    LLPPairsPass,
    label: "llp_pairs",
    shader: "llp_pairs"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for LLPPairsPass {
    const NAME: &'static str = "llp_pairs";
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
            ("action_table".into(), b.action_table.as_entire_binding()),
            ("out_headers".into(), b.out_headers.as_entire_binding()),
            ("gParams".into(), b.params_llp.as_entire_binding()),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        dbg: &mut crate::parser::debug::DebugOutput,
    ) {
        dbg.gpu.out_headers.set_from_copy(
            device,
            encoder,
            &b.out_headers,
            "parser.dbg.out_headers",
            b.out_headers.byte_size,
        );
    }
}
