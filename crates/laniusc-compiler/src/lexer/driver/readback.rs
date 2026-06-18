use anyhow::Result;

use super::buffers;
use crate::lexer::{
    types::{GpuToken, Token},
    util::{read_tokens_from_mapped, u32_from_first_4},
};

/// Reads resident source-pack token buffers back to host `Token` records.
pub(super) fn read_resident_tokens(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    bufs: &buffers::GpuBuffers,
) -> Result<Vec<Token>> {
    let count_readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb.lex.source_pack.count"),
        size: 4,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut count_encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("lex-source-pack-count-readback"),
    });
    count_encoder.copy_buffer_to_buffer(&bufs.token_count, 0, &count_readback, 0, 4);
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "lex.source-pack.count-readback",
        count_encoder.finish(),
    );

    let count_slice = count_readback.slice(..);
    crate::gpu::passes_core::map_readback_for_progress(&count_slice, "lex.source-pack.count");
    crate::gpu::passes_core::wait_for_map_progress(
        device,
        "lex.source-pack.count",
        wgpu::PollType::wait_indefinitely(),
    );
    let count_bytes = count_slice.get_mapped_range();
    let token_count = u32_from_first_4(&count_bytes) as usize;
    drop(count_bytes);
    count_readback.unmap();
    if token_count == 0 {
        return Ok(Vec::new());
    }

    let need_bytes = (token_count * std::mem::size_of::<GpuToken>()) as u64;
    let tokens_readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb.lex.source_pack.tokens"),
        size: need_bytes,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut tokens_encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("lex-source-pack-token-readback"),
    });
    tokens_encoder.copy_buffer_to_buffer(&bufs.tokens_out, 0, &tokens_readback, 0, need_bytes);
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "lex.source-pack.token-readback",
        tokens_encoder.finish(),
    );

    let tokens_slice = tokens_readback.slice(0..need_bytes);
    crate::gpu::passes_core::map_readback_for_progress(&tokens_slice, "lex.source-pack.tokens");
    crate::gpu::passes_core::wait_for_map_progress(
        device,
        "lex.source-pack.tokens",
        wgpu::PollType::wait_indefinitely(),
    );
    let mapped = tokens_slice.get_mapped_range();
    let tokens = read_tokens_from_mapped(&mapped, token_count).map_err(anyhow::Error::msg)?;
    drop(mapped);
    tokens_readback.unmap();
    Ok(tokens)
}
