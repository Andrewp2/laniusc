use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, PassData},
    lexer::{buffers::GpuBuffers, debug::DebugOutput},
};

/// Marks source-file start and end offsets in a concatenated source pack.
pub struct SourceFileBoundariesPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    SourceFileBoundariesPass,
    label: "source_file_boundaries",
    entry: "source_file_boundaries",
    shader: "lexer/source_file_boundaries"
);

impl crate::gpu::passes_core::Pass<GpuBuffers, DebugOutput> for SourceFileBoundariesPass {
    const NAME: &'static str = "source_file_boundaries";
    const DIM: DispatchDim = DispatchDim::D1;

    fn data(&self) -> &PassData {
        &self.data
    }

    fn from_data(data: PassData) -> Self {
        Self { data }
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a GpuBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            (
                "source_file_count".into(),
                b.source_file_count.as_entire_binding(),
            ),
            (
                "source_file_start".into(),
                b.source_file_start.as_entire_binding(),
            ),
            (
                "source_file_len".into(),
                b.source_file_len.as_entire_binding(),
            ),
            (
                "source_file_start_flags".into(),
                b.source_file_start_flags.as_entire_binding(),
            ),
            (
                "source_file_end_flags".into(),
                b.source_file_end_flags.as_entire_binding(),
            ),
        ])
    }
}
