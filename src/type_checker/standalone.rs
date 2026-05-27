use super::*;

mod token_buffer;
pub use token_buffer::check_token_buffer_with_hir_on_gpu;

pub async fn check_tokens_on_gpu(src: &str, tokens: &[Token]) -> Result<(), GpuTypeCheckError> {
    check_tokens_on_gpu_inner(src, tokens).await
}

async fn check_tokens_on_gpu_inner(src: &str, tokens: &[Token]) -> Result<(), GpuTypeCheckError> {
    let ctx = device::global();
    let device = &ctx.device;
    let queue = &ctx.queue;

    let token_bytes = token_bytes(tokens);
    let source_bytes = nonempty_bytes(src.as_bytes());

    let token_buf = storage_ro_from_bytes::<u32>(
        device,
        "type_check.tokens.tokens",
        &token_bytes,
        tokens.len(),
    );
    let token_count_buf = storage_ro_from_u32s(
        device,
        "type_check.tokens.token_count",
        &[tokens.len() as u32],
    );
    let source_buf = storage_ro_from_bytes::<u8>(
        device,
        "type_check.tokens.source",
        &source_bytes,
        source_bytes.len(),
    );
    let hir_kind_buf = storage_ro_from_u32s(device, "type_check.tokens.hir_kind.empty", &[0]);
    let hir_token_pos_buf =
        storage_ro_from_u32s(device, "type_check.tokens.hir_token_pos.empty", &[0]);
    let hir_token_end_buf =
        storage_ro_from_u32s(device, "type_check.tokens.hir_token_end.empty", &[0]);
    let hir_token_file_id_buf =
        storage_ro_from_u32s(device, "type_check.tokens.hir_token_file_id.empty", &[0]);
    let hir_status_buf = storage_ro_from_u32s(
        device,
        "type_check.tokens.hir_status.empty",
        &[0, 0, 0, 0, 0, 0],
    );
    check_token_buffer_with_hir_on_gpu(
        device,
        queue,
        src.len() as u32,
        tokens.len() as u32,
        &token_buf,
        &token_count_buf,
        &source_buf,
        0,
        &hir_kind_buf,
        &hir_token_pos_buf,
        &hir_token_end_buf,
        &hir_token_file_id_buf,
        &hir_status_buf,
    )
}

pub fn check_token_buffer_on_gpu(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    source_len: u32,
    token_capacity: u32,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    source_buf: &wgpu::Buffer,
) -> Result<(), GpuTypeCheckError> {
    let empty = storage_ro_from_u32s(device, "type_check.tokens.hir_kind.empty", &[0]);
    let empty_pos = storage_ro_from_u32s(device, "type_check.tokens.hir_token_pos.empty", &[0]);
    let empty_end = storage_ro_from_u32s(device, "type_check.tokens.hir_token_end.empty", &[0]);
    let empty_file_id =
        storage_ro_from_u32s(device, "type_check.tokens.hir_token_file_id.empty", &[0]);
    let empty_status = storage_ro_from_u32s(
        device,
        "type_check.tokens.hir_status.empty",
        &[0, 0, 0, 0, 0, 0],
    );
    check_token_buffer_with_hir_on_gpu(
        device,
        queue,
        source_len,
        token_capacity,
        token_buf,
        token_count_buf,
        source_buf,
        0,
        &empty,
        &empty_pos,
        &empty_end,
        &empty_file_id,
        &empty_status,
    )
}
