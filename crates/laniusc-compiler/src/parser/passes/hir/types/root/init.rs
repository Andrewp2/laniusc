use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Seeds direct type-parent links and self-owned type roots.
pub struct HirTypeRootOwnerInitPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirTypeRootOwnerInitPass,
    label: "hir_type_root_owner_init",
    shader: "parser/hir/type/root/owner/init"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirTypeRootOwnerInitPass {
    const NAME: &'static str = "hir_type_root_owner_init";
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
                "gHirType".into(),
                b.hir_type_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_type_arg_owner".into(),
                b.hir_type_arg_owner_a.as_entire_binding(),
            ),
            (
                "hir_type_root_link_a".into(),
                b.hir_type_arg_link_a.as_entire_binding(),
            ),
            (
                "hir_type_root_owner_a".into(),
                b.hir_type_root_owner.as_entire_binding(),
            ),
        ])
    }
}
