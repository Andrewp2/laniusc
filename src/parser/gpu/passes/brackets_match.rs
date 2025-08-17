use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::gpu::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct BracketParams {
    pub n_sc: u32,
    pub typed_check: u32, // 0 = generic, 1 = type-aware matching
}

pub struct BracketsMatchPass {
    data: PassData,
}

impl BracketsMatchPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let spirv = include_bytes!(concat!(env!("OUT_DIR"), "/shaders/brackets_match.spv"));
        let reflect = include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/brackets_match.reflect.json"
        ));
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "brackets_match",
            "main",
            spirv,
            reflect,
        )?;
        Ok(Self { data })
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for BracketsMatchPass {
    const NAME: &'static str = "brackets_match";
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
        // Shader expects: sc_stream, match_for_index, out_depths, valid_out, gParams.
        HashMap::from([
            ("sc_stream".into(), b.out_sc.as_entire_binding()),
            (
                "match_for_index".into(),
                b.match_for_index.as_entire_binding(),
            ),
            // FIX: name must match shader's RWStructuredBuffer<int> out_depths
            ("out_depths".into(), b.depths_out.as_entire_binding()),
            ("gParams".into(), b.params_brackets.as_entire_binding()),
            ("out_valid".into(), b.valid_out.as_entire_binding()),
        ])
    }

    fn record_debug(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        dbg: &mut crate::parser::gpu::debug::DebugOutput,
    ) {
        let g = &mut dbg.gpu;
        g.match_for_index.set_from_copy(
            device,
            encoder,
            &b.match_for_index,
            "parser.dbg.match_for_index",
            b.match_for_index.byte_size,
        );
        g.depths_out.set_from_copy(
            device,
            encoder,
            &b.depths_out,
            "parser.dbg.depths_out",
            b.depths_out.byte_size,
        );
        g.valid_out.set_from_copy(
            device,
            encoder,
            &b.valid_out,
            "parser.dbg.valid_out",
            b.valid_out.byte_size,
        );
    }
}
