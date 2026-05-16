use anyhow::Result;

use super::{GpuX86CodeGenerator, RecordedX86Codegen, support::read_x86_output};

impl GpuX86CodeGenerator {
    pub fn finish_recorded_x86(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        recorded: &RecordedX86Codegen,
    ) -> Result<Vec<u8>> {
        read_x86_output(device, queue, recorded)
    }
}
