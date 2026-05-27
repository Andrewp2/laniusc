use super::super::super::*;

pub(super) fn finish_with_status(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    mut encoder: wgpu::CommandEncoder,
    status_buf: &wgpu::Buffer,
    status_readback: &wgpu::Buffer,
) -> Result<(), GpuTypeCheckError> {
    encoder.copy_buffer_to_buffer(status_buf, 0, status_readback, 0, 16);
    crate::gpu::passes_core::submit_with_progress(queue, "type_check.resident", encoder.finish());

    let slice = status_readback.slice(..);
    crate::gpu::passes_core::map_readback_blocking(device, &slice, "type_check.resident.status")?;
    let mapped = slice.get_mapped_range();
    let words = read_status_words(&mapped)?;
    drop(mapped);
    status_readback.unmap();

    if words[0] != 0 {
        return Ok(());
    }

    Err(GpuTypeCheckError::Rejected {
        token: words[1],
        code: GpuTypeCheckCode::from_u32(words[2]),
        detail: words[3],
    })
}
