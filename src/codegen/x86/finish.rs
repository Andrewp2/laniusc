use anyhow::Result;

use super::{RecordedX86Codegen, support::read_x86_output};

impl RecordedX86Codegen {
    pub fn read_output(&self, device: &wgpu::Device, queue: &wgpu::Queue) -> Result<Vec<u8>> {
        read_x86_output(device, queue, self)
    }
}
