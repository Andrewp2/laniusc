use anyhow::Result;

use super::{RecordedX86Codegen, support::read_x86_output};

impl RecordedX86Codegen {
    /// Reads and validates the output bytes produced by a recorded x86 backend run.
    pub fn read_output(&self, device: &wgpu::Device, queue: &wgpu::Queue) -> Result<Vec<u8>> {
        read_x86_output(device, queue, self)
    }
}
