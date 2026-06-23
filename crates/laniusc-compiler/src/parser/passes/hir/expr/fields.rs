use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for filling expression record fields.
pub struct Params {
    pub n: u32,
    pub uses_status_count: u32,
}

/// Absence of an expression form.
pub const HIR_EXPR_FORM_NONE: u32 = 0;
/// Expression form forwarded from a child expression.
pub const HIR_EXPR_FORM_FORWARD: u32 = 1;
/// Name reference expression.
pub const HIR_EXPR_FORM_NAME: u32 = 2;
/// Integer literal expression.
pub const HIR_EXPR_FORM_INT: u32 = 3;
/// `true` literal expression.
pub const HIR_EXPR_FORM_TRUE: u32 = 4;
/// `false` literal expression.
pub const HIR_EXPR_FORM_FALSE: u32 = 5;
/// Logical-not unary expression.
pub const HIR_EXPR_FORM_NOT: u32 = 6;
/// Equality comparison expression.
pub const HIR_EXPR_FORM_EQ: u32 = 7;
/// Inequality comparison expression.
pub const HIR_EXPR_FORM_NE: u32 = 8;
/// Less-than comparison expression.
pub const HIR_EXPR_FORM_LT: u32 = 9;
/// Greater-than comparison expression.
pub const HIR_EXPR_FORM_GT: u32 = 10;
/// Less-than-or-equal comparison expression.
pub const HIR_EXPR_FORM_LE: u32 = 11;
/// Greater-than-or-equal comparison expression.
pub const HIR_EXPR_FORM_GE: u32 = 12;
/// Numeric negation expression.
pub const HIR_EXPR_FORM_NEG: u32 = 13;
/// Addition expression.
pub const HIR_EXPR_FORM_ADD: u32 = 14;
/// Subtraction expression.
pub const HIR_EXPR_FORM_SUB: u32 = 15;
/// Multiplication expression.
pub const HIR_EXPR_FORM_MUL: u32 = 16;
/// Logical-and expression.
pub const HIR_EXPR_FORM_AND: u32 = 17;
/// Logical-or expression.
pub const HIR_EXPR_FORM_OR: u32 = 18;
/// Remainder expression.
pub const HIR_EXPR_FORM_MOD: u32 = 19;
/// Division expression.
pub const HIR_EXPR_FORM_DIV: u32 = 20;
/// Bitwise-or expression.
pub const HIR_EXPR_FORM_BIT_OR: u32 = 21;
/// Bitwise-xor expression.
pub const HIR_EXPR_FORM_BIT_XOR: u32 = 22;
/// Bitwise-and expression.
pub const HIR_EXPR_FORM_BIT_AND: u32 = 23;
/// Left-shift expression.
pub const HIR_EXPR_FORM_SHL: u32 = 24;
/// Right-shift expression.
pub const HIR_EXPR_FORM_SHR: u32 = 25;
/// Index expression.
pub const HIR_EXPR_FORM_INDEX: u32 = 26;
/// Floating-point literal expression.
pub const HIR_EXPR_FORM_FLOAT: u32 = 27;
/// String literal expression.
pub const HIR_EXPR_FORM_STRING: u32 = 28;
/// Character literal expression.
pub const HIR_EXPR_FORM_CHAR: u32 = 29;
/// Half-open range expression.
pub const HIR_EXPR_FORM_RANGE: u32 = 30;
/// Range-from expression.
pub const HIR_EXPR_FORM_RANGE_FROM: u32 = 31;
/// Range-to expression.
pub const HIR_EXPR_FORM_RANGE_TO: u32 = 32;
/// Full-range expression.
pub const HIR_EXPR_FORM_RANGE_FULL: u32 = 33;
/// Inclusive range expression.
pub const HIR_EXPR_FORM_RANGE_INCLUSIVE: u32 = 34;
/// Range-to-inclusive expression.
pub const HIR_EXPR_FORM_RANGE_TO_INCLUSIVE: u32 = 35;

/// Parser pass that fills expression form and result-node records.
pub struct HirExprFieldsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirExprFieldsPass,
    label: "hir_expr_fields",
    shader: "parser/hir/expr/fields"
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
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
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
