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
    pub uses_status_count: u32,
}

pub const HIR_METHOD_RECEIVER_NONE: u32 = 0;
pub const HIR_METHOD_RECEIVER_SELF: u32 = 1;
pub const HIR_METHOD_RECEIVER_REF_SELF: u32 = 2;
pub const HIR_METHOD_RECEIVER_EXPLICIT: u32 = 3;

pub const HIR_METHOD_VIS_PRIVATE: u32 = 0;
pub const HIR_METHOD_VIS_PUBLIC: u32 = 1;

pub struct HirMethodFieldsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirMethodFieldsPass,
    label: "hir_method_fields",
    shader: "parser/hir/method/fields"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirMethodFieldsPass {
    const NAME: &'static str = "hir_method_fields";
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
                "gHirMethod".into(),
                b.hir_method_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
            ("first_child".into(), b.first_child.as_entire_binding()),
            ("next_sibling".into(), b.next_sibling.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            (
                "hir_item_name_token".into(),
                b.hir_item_name_token.as_entire_binding(),
            ),
            (
                "hir_node_dense_id".into(),
                b.hir_node_dense_id.as_entire_binding(),
            ),
            (
                "hir_semantic_dense_node".into(),
                b.hir_semantic_dense_node.as_entire_binding(),
            ),
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_semantic_parent".into(),
                b.hir_semantic_parent.as_entire_binding(),
            ),
            (
                "hir_param_record".into(),
                b.hir_param_record.as_entire_binding(),
            ),
            (
                "hir_method_owner_node".into(),
                b.hir_method_owner_node.as_entire_binding(),
            ),
            (
                "hir_method_impl_node".into(),
                b.hir_method_impl_node.as_entire_binding(),
            ),
            (
                "hir_method_name_token".into(),
                b.hir_method_name_token.as_entire_binding(),
            ),
            (
                "hir_method_first_param_token".into(),
                b.hir_method_first_param_token.as_entire_binding(),
            ),
            (
                "hir_method_receiver_mode".into(),
                b.hir_method_receiver_mode.as_entire_binding(),
            ),
            (
                "hir_method_visibility".into(),
                b.hir_method_visibility.as_entire_binding(),
            ),
            (
                "hir_method_impl_receiver_type_node".into(),
                b.hir_method_impl_receiver_type_node.as_entire_binding(),
            ),
        ])
    }
}
