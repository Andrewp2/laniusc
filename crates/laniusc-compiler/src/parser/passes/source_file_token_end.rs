use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for source-file token-end propagation.
pub struct Params {
    pub token_capacity: u32,
}

/// Pass that computes the end token index for each source file.
pub struct SourceFileTokenEndPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    SourceFileTokenEndPass,
    label: "source_file_token_end",
    shader: "parser/source_file_token_end"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for SourceFileTokenEndPass {
    const NAME: &'static str = "source_file_token_end";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self {
        Self { data }
    }

    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a ParserBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            (
                "gSourceFile".into(),
                b.source_file_token_end_params.as_entire_binding(),
            ),
            ("token_count".into(), b.token_count.as_entire_binding()),
            (
                "token_file_id".into(),
                b.default_token_file_id.as_entire_binding(),
            ),
            (
                "source_file_token_end".into(),
                b.source_file_token_end.as_entire_binding(),
            ),
        ])
    }
}
