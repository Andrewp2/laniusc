use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct Params {
    pub n: u32,
    pub uses_ll1: u32,
}

pub struct HirItemDeclTokensPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirItemDeclTokensPass,
    label: "hir_item_decl_tokens",
    shader: "hir_item_decl_tokens"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirItemDeclTokensPass {
    const NAME: &'static str = "hir_item_decl_tokens";
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
                "gHirItemDecl".into(),
                b.hir_item_fields_params.as_entire_binding(),
            ),
            (
                "ll1_status".into(),
                if b.tree_count_uses_status && !b.tree_stream_uses_ll1 {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("hir_item_kind".into(), b.hir_item_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            (
                "hir_item_decl_token".into(),
                b.hir_item_decl_token.as_entire_binding(),
            ),
        ])
    }
}
