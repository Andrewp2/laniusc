use super::{WASM_BODY_PLAN_WORDS, support::readback_u32s};

pub(super) struct WasmReadbackBuffers {
    pub out: wgpu::Buffer,
    pub status: wgpu::Buffer,
    pub body_plan: wgpu::Buffer,
    pub body_fragment_len: wgpu::Buffer,
    pub body_fragment_aux: wgpu::Buffer,
    pub body_fragment_meta: wgpu::Buffer,
    pub func_invalid_count: wgpu::Buffer,
    pub func_detail: wgpu::Buffer,
}

pub(super) fn create_wasm_readback_buffers(
    device: &wgpu::Device,
    packed_output_words: usize,
    body_item_capacity: u32,
    token_capacity: u32,
) -> WasmReadbackBuffers {
    WasmReadbackBuffers {
        out: readback_u32s(device, "rb.codegen.wasm.out_words", packed_output_words),
        // The first four words are module status; phase two appends the four
        // call-relocation compaction status words without another map/wait.
        status: readback_u32s(device, "rb.codegen.wasm.status", 8),
        body_plan: readback_u32s(device, "rb.codegen.wasm.body_plan", WASM_BODY_PLAN_WORDS),
        body_fragment_len: readback_u32s(
            device,
            "rb.codegen.wasm.body_fragment_len",
            body_item_capacity as usize,
        ),
        body_fragment_aux: readback_u32s(
            device,
            "rb.codegen.wasm.body_fragment_aux",
            body_item_capacity as usize * 4,
        ),
        body_fragment_meta: readback_u32s(
            device,
            "rb.codegen.wasm.body_fragment_meta",
            body_item_capacity as usize * 4,
        ),
        func_invalid_count: readback_u32s(
            device,
            "rb.codegen.wasm.func_invalid_count",
            token_capacity as usize,
        ),
        func_detail: readback_u32s(
            device,
            "rb.codegen.wasm.func_detail",
            token_capacity as usize,
        ),
    }
}
