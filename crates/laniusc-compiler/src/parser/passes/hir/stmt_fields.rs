use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for filling statement record fields.
pub struct Params {
    pub n: u32,
    pub uses_status_count: u32,
}

/// Absence of a statement record kind.
pub const HIR_STMT_RECORD_KIND_NONE: u32 = 0;
/// `let` statement record.
pub const HIR_STMT_RECORD_KIND_LET: u32 = 1;
/// `return` statement record.
pub const HIR_STMT_RECORD_KIND_RETURN: u32 = 2;
/// `if` statement record.
pub const HIR_STMT_RECORD_KIND_IF: u32 = 3;
/// Constant item used in statement position.
pub const HIR_STMT_RECORD_KIND_CONST: u32 = 4;
/// Assignment statement record.
pub const HIR_STMT_RECORD_KIND_ASSIGN: u32 = 5;
/// `while` statement record.
pub const HIR_STMT_RECORD_KIND_WHILE: u32 = 6;
/// `for` statement record.
pub const HIR_STMT_RECORD_KIND_FOR: u32 = 7;
/// `break` statement record.
pub const HIR_STMT_RECORD_KIND_BREAK: u32 = 8;
/// `continue` statement record.
pub const HIR_STMT_RECORD_KIND_CONTINUE: u32 = 9;

/// Plain assignment operator.
pub const HIR_ASSIGN_OP_SET: u32 = 1;
/// Add-assign operator.
pub const HIR_ASSIGN_OP_ADD: u32 = 2;
/// Subtract-assign operator.
pub const HIR_ASSIGN_OP_SUB: u32 = 3;
/// Multiply-assign operator.
pub const HIR_ASSIGN_OP_MUL: u32 = 4;
/// Divide-assign operator.
pub const HIR_ASSIGN_OP_DIV: u32 = 5;
/// Remainder-assign operator.
pub const HIR_ASSIGN_OP_MOD: u32 = 6;
/// Bitwise-xor-assign operator.
pub const HIR_ASSIGN_OP_XOR: u32 = 7;
/// Left-shift-assign operator.
pub const HIR_ASSIGN_OP_SHL: u32 = 8;
/// Right-shift-assign operator.
pub const HIR_ASSIGN_OP_SHR: u32 = 9;
/// Bitwise-and-assign operator.
pub const HIR_ASSIGN_OP_BAND: u32 = 10;
/// Bitwise-or-assign operator.
pub const HIR_ASSIGN_OP_BOR: u32 = 11;

/// Parser pass that fills statement kind, scope, and assignment records.
pub struct HirStmtFieldsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirStmtFieldsPass,
    label: "hir_stmt_fields",
    shader: "parser/hir/stmt_fields"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirStmtFieldsPass {
    const NAME: &'static str = "hir_stmt_fields";
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
                "gHirStmt".into(),
                b.hir_stmt_fields_params.as_entire_binding(),
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
            ("subtree_end".into(), b.subtree_end.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
            (
                "hir_expr_record".into(),
                b.hir_expr_record.as_entire_binding(),
            ),
            (
                "hir_expr_result_root_node".into(),
                b.hir_expr_result_root_node.as_entire_binding(),
            ),
            (
                "hir_member_name_token".into(),
                b.hir_member_name_token.as_entire_binding(),
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
                "hir_stmt_record".into(),
                b.hir_stmt_record.as_entire_binding(),
            ),
            (
                "hir_stmt_scope_end".into(),
                b.hir_stmt_scope_end.as_entire_binding(),
            ),
        ])
    }
}
