use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::gpu::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct PackParams {
    pub n_tokens: u32,
    pub n_kinds: u32,
    pub total_sc: u32,
    pub total_emit: u32,

    // Offsets (u32 elements) inside tables_blob
    pub sc_superseq_off: u32,
    pub sc_off_off: u32,
    pub sc_len_off: u32,
    pub pp_superseq_off: u32,
    pub pp_off_off: u32,
    pub pp_len_off: u32,
}

pub struct PackVarlenPass {
    data: PassData,
}

impl PackVarlenPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let spirv = include_bytes!(concat!(env!("OUT_DIR"), "/shaders/pack_varlen.spv"));
        let reflect = include_bytes!(concat!(
            env!("OUT_DIR"),
            "/shaders/pack_varlen.reflect.json"
        ));
        let data =
            crate::gpu::passes_core::make_pass_data(device, "pack_varlen", "main", spirv, reflect)?;
        Ok(Self { data })
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for PackVarlenPass {
    const NAME: &'static str = "pack_varlen";
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
            ("sc_offsets".into(), b.sc_offsets.as_entire_binding()),
            ("emit_offsets".into(), b.emit_offsets.as_entire_binding()),
            ("tables_blob".into(), b.tables_blob.as_entire_binding()),
            ("out_sc".into(), b.out_sc.as_entire_binding()),
            ("out_emit".into(), b.out_emit.as_entire_binding()),
            ("gParams".into(), b.params_pack.as_entire_binding()),
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

        g.sc_offsets.set_from_copy(
            device,
            encoder,
            &b.sc_offsets,
            "parser.dbg.sc_offsets",
            b.sc_offsets.byte_size,
        );
        g.emit_offsets.set_from_copy(
            device,
            encoder,
            &b.emit_offsets,
            "parser.dbg.emit_offsets",
            b.emit_offsets.byte_size,
        );
        g.out_sc.set_from_copy(
            device,
            encoder,
            &b.out_sc,
            "parser.dbg.out_sc",
            b.out_sc.byte_size,
        );
        g.out_emit.set_from_copy(
            device,
            encoder,
            &b.out_emit,
            "parser.dbg.out_emit",
            b.out_emit.byte_size,
        );
    }
}
