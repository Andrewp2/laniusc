use encase::ShaderType;

use crate::gpu::buffers::{
    LaniusBuffer,
    storage_ro_from_bytes,
    storage_ro_from_u32s,
    storage_rw_for_array,
    storage_rw_uninit_bytes,
    uniform_from_val,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType, Default)]
pub struct ActionHeader {
    pub push_len: u32,
    pub emit_len: u32,
    pub pop_tag: u32,
    pub pop_count: u32,
}

pub struct ParserBuffers {
    pub token_kinds: LaniusBuffer<u32>,
    pub action_table: LaniusBuffer<u8>, // raw bytes table (shader-defined layout)
    pub params_llp: LaniusBuffer<super::passes::llp_pairs::LLPParams>,
    pub out_headers: LaniusBuffer<ActionHeader>,
    pub input_data: LaniusBuffer<u8>,
    pub output_data: LaniusBuffer<u8>,

    pub n_tokens: u32,
    pub n_kinds: u32,
}

impl ParserBuffers {
    pub fn new(
        device: &wgpu::Device,
        token_kinds_u32: &[u32],
        action_table_bytes: &[u8],
        n_kinds: u32,
    ) -> Self {
        let n_tokens = token_kinds_u32.len() as u32;

        // token kinds (read-only storage)
        let token_kinds = storage_ro_from_u32s(device, "parser.token_kinds", token_kinds_u32);

        // action table (raw bytes; shader-side defines the layout)
        let action_table = storage_ro_from_bytes::<u8>(
            device,
            "parser.action_table",
            action_table_bytes,
            action_table_bytes.len(),
        );

        // LLP params (uniform)
        let params_init = super::passes::llp_pairs::LLPParams { n_tokens, n_kinds };
        let params_llp = uniform_from_val(device, "parser.params_llp", &params_init);

        // headers output: (n_tokens - 1) entries, std430-sized via `encase`
        let n_pairs = n_tokens.saturating_sub(1) as usize;
        let out_headers: LaniusBuffer<ActionHeader> =
            storage_rw_for_array::<ActionHeader>(device, "parser.out_headers", n_pairs);

        // scratch io for pack_varlen (size chosen to mirror headers; adjust when shader is finalized)
        let scratch_bytes = out_headers.byte_size;
        let input_data =
            storage_rw_uninit_bytes(device, "parser.input_data", scratch_bytes, scratch_bytes);
        let output_data =
            storage_rw_uninit_bytes(device, "parser.output_data", scratch_bytes, scratch_bytes);

        Self {
            token_kinds,
            action_table,
            params_llp,
            out_headers,
            input_data,
            output_data,
            n_tokens,
            n_kinds,
        }
    }
}
