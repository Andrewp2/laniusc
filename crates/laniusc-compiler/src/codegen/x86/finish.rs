use anyhow::Result;

use super::{
    GpuX86DependencySymbolBuffers,
    GpuX86RelocatableObject,
    RecordedX86Codegen,
    RecordedX86ObjectCodegen,
    support::{read_x86_object, read_x86_output},
};

impl RecordedX86Codegen {
    /// Reads and validates the output bytes produced by a recorded x86 backend run.
    pub fn read_output(&self, device: &wgpu::Device, queue: &wgpu::Queue) -> Result<Vec<u8>> {
        read_x86_output(device, queue, self)
    }
}

impl RecordedX86ObjectCodegen {
    /// Reads and validates the section-relative object produced by this GPU run.
    pub fn read_object(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        library_id: u32,
        unit_id: u32,
        dependency_symbols: Option<GpuX86DependencySymbolBuffers<'_>>,
    ) -> Result<GpuX86RelocatableObject> {
        read_x86_object(
            device,
            queue,
            &self.recorded,
            library_id,
            unit_id,
            dependency_symbols,
        )
    }
}
