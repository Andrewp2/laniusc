use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that combines packing status with stack-effect validation.
pub struct ParserStatusFromBracketsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    ParserStatusFromBracketsPass,
    label: "parser_status_from_brackets",
    shader: "parser/status/from_brackets"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for ParserStatusFromBracketsPass {
    const NAME: &'static str = "parser_status_from_brackets";
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
                "partial_parse_status".into(),
                b.partial_parse_status.as_entire_binding(),
            ),
            ("bracket_depths".into(), b.depths_out.as_entire_binding()),
            ("bracket_valid".into(), b.valid_out.as_entire_binding()),
            ("ll1_status".into(), b.ll1_status.as_entire_binding()),
        ])
    }
}
