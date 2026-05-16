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

pub const HIR_ITEM_KIND_NONE: u32 = 0;
pub const HIR_ITEM_KIND_MODULE: u32 = 1;
pub const HIR_ITEM_KIND_IMPORT: u32 = 2;
pub const HIR_ITEM_KIND_CONST: u32 = 3;
pub const HIR_ITEM_KIND_FN: u32 = 4;
pub const HIR_ITEM_KIND_EXTERN_FN: u32 = 5;
pub const HIR_ITEM_KIND_STRUCT: u32 = 6;
pub const HIR_ITEM_KIND_ENUM: u32 = 7;
pub const HIR_ITEM_KIND_TYPE_ALIAS: u32 = 8;
pub const HIR_ITEM_KIND_ENUM_VARIANT: u32 = 9;

pub const HIR_ITEM_NAMESPACE_NONE: u32 = 0;
pub const HIR_ITEM_NAMESPACE_MODULE: u32 = 1;
pub const HIR_ITEM_NAMESPACE_VALUE: u32 = 2;
pub const HIR_ITEM_NAMESPACE_TYPE: u32 = 3;

pub const HIR_ITEM_VIS_PRIVATE: u32 = 0;
pub const HIR_ITEM_VIS_PUBLIC: u32 = 1;

pub const HIR_ITEM_IMPORT_TARGET_NONE: u32 = 0;
pub const HIR_ITEM_IMPORT_TARGET_PATH: u32 = 1;
pub const HIR_ITEM_IMPORT_TARGET_STRING: u32 = 2;

pub struct HirItemFieldsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirItemFieldsPass,
    label: "hir_item_fields",
    shader: "hir_item_fields"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirItemFieldsPass {
    const NAME: &'static str = "hir_item_fields";
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
                "gHirItem".into(),
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
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
            ("first_child".into(), b.first_child.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
            (
                "hir_token_file_id".into(),
                b.hir_token_file_id.as_entire_binding(),
            ),
            ("hir_item_kind".into(), b.hir_item_kind.as_entire_binding()),
            (
                "hir_item_name_token".into(),
                b.hir_item_name_token.as_entire_binding(),
            ),
            (
                "hir_item_namespace".into(),
                b.hir_item_namespace.as_entire_binding(),
            ),
            (
                "hir_item_visibility".into(),
                b.hir_item_visibility.as_entire_binding(),
            ),
            (
                "hir_item_path_start".into(),
                b.hir_item_path_start.as_entire_binding(),
            ),
            (
                "hir_item_path_end".into(),
                b.hir_item_path_end.as_entire_binding(),
            ),
            (
                "hir_item_file_id".into(),
                b.hir_item_file_id.as_entire_binding(),
            ),
            (
                "hir_item_import_target_kind".into(),
                b.hir_item_import_target_kind.as_entire_binding(),
            ),
        ])
    }
}
