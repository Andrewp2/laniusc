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

pub const HIR_STMT_RECORD_KIND_NONE: u32 = 0;
pub const HIR_STMT_RECORD_KIND_LET: u32 = 1;
pub const HIR_STMT_RECORD_KIND_RETURN: u32 = 2;
pub const HIR_STMT_RECORD_KIND_IF: u32 = 3;
pub const HIR_STMT_RECORD_KIND_CONST: u32 = 4;
pub const HIR_STMT_RECORD_KIND_ASSIGN: u32 = 5;
pub const HIR_STMT_RECORD_KIND_WHILE: u32 = 6;
pub const HIR_STMT_RECORD_KIND_FOR: u32 = 7;
pub const HIR_STMT_RECORD_KIND_BREAK: u32 = 8;
pub const HIR_STMT_RECORD_KIND_CONTINUE: u32 = 9;

pub const HIR_ASSIGN_OP_SET: u32 = 1;
pub const HIR_ASSIGN_OP_ADD: u32 = 2;
pub const HIR_ASSIGN_OP_SUB: u32 = 3;
pub const HIR_ASSIGN_OP_MUL: u32 = 4;
pub const HIR_ASSIGN_OP_DIV: u32 = 5;
pub const HIR_ASSIGN_OP_MOD: u32 = 6;
pub const HIR_ASSIGN_OP_XOR: u32 = 7;
pub const HIR_ASSIGN_OP_SHL: u32 = 8;
pub const HIR_ASSIGN_OP_SHR: u32 = 9;
pub const HIR_ASSIGN_OP_BAND: u32 = 10;
pub const HIR_ASSIGN_OP_BOR: u32 = 11;

pub struct HirStmtFieldsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirStmtFieldsPass,
    label: "hir_stmt_fields",
    shader: "hir_stmt_fields"
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
