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

pub const HIR_EXPR_FORM_NONE: u32 = 0;
pub const HIR_EXPR_FORM_FORWARD: u32 = 1;
pub const HIR_EXPR_FORM_NAME: u32 = 2;
pub const HIR_EXPR_FORM_INT: u32 = 3;
pub const HIR_EXPR_FORM_TRUE: u32 = 4;
pub const HIR_EXPR_FORM_FALSE: u32 = 5;
pub const HIR_EXPR_FORM_NOT: u32 = 6;
pub const HIR_EXPR_FORM_EQ: u32 = 7;
pub const HIR_EXPR_FORM_NE: u32 = 8;
pub const HIR_EXPR_FORM_LT: u32 = 9;
pub const HIR_EXPR_FORM_GT: u32 = 10;
pub const HIR_EXPR_FORM_LE: u32 = 11;
pub const HIR_EXPR_FORM_GE: u32 = 12;
pub const HIR_EXPR_FORM_NEG: u32 = 13;
pub const HIR_EXPR_FORM_ADD: u32 = 14;
pub const HIR_EXPR_FORM_SUB: u32 = 15;
pub const HIR_EXPR_FORM_MUL: u32 = 16;
pub const HIR_EXPR_FORM_AND: u32 = 17;
pub const HIR_EXPR_FORM_OR: u32 = 18;
pub const HIR_EXPR_FORM_MOD: u32 = 19;
pub const HIR_EXPR_FORM_DIV: u32 = 20;
pub const HIR_EXPR_FORM_BIT_OR: u32 = 21;
pub const HIR_EXPR_FORM_BIT_XOR: u32 = 22;
pub const HIR_EXPR_FORM_BIT_AND: u32 = 23;
pub const HIR_EXPR_FORM_SHL: u32 = 24;
pub const HIR_EXPR_FORM_SHR: u32 = 25;
pub const HIR_EXPR_FORM_INDEX: u32 = 26;
pub const HIR_EXPR_FORM_FLOAT: u32 = 27;
pub const HIR_EXPR_FORM_STRING: u32 = 28;
pub const HIR_EXPR_FORM_CHAR: u32 = 29;
pub const HIR_EXPR_FORM_RANGE: u32 = 30;
pub const HIR_EXPR_FORM_RANGE_FROM: u32 = 31;
pub const HIR_EXPR_FORM_RANGE_TO: u32 = 32;
pub const HIR_EXPR_FORM_RANGE_FULL: u32 = 33;
pub const HIR_EXPR_FORM_RANGE_INCLUSIVE: u32 = 34;
pub const HIR_EXPR_FORM_RANGE_TO_INCLUSIVE: u32 = 35;

pub struct HirExprFieldsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirExprFieldsPass,
    label: "hir_expr_fields",
    shader: "hir_expr_fields"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirExprFieldsPass {
    const NAME: &'static str = "hir_expr_fields";
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
                "gHirExpr".into(),
                b.hir_expr_fields_params.as_entire_binding(),
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
            ("next_sibling".into(), b.next_sibling.as_entire_binding()),
            ("prev_sibling".into(), b.prev_sibling.as_entire_binding()),
            ("subtree_end".into(), b.subtree_end.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            (
                "hir_semantic_dense_node".into(),
                b.hir_semantic_dense_node.as_entire_binding(),
            ),
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_expr_record".into(),
                b.hir_expr_record.as_entire_binding(),
            ),
            (
                "hir_expr_result_node".into(),
                b.hir_expr_result_node.as_entire_binding(),
            ),
            (
                "hir_expr_result_root_node".into(),
                b.hir_expr_result_root_node.as_entire_binding(),
            ),
        ])
    }
}
