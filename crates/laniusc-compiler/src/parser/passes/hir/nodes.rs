use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for classifying tree nodes into parser HIR node kinds.
pub struct Params {
    pub n: u32,
    pub uses_status_count: u32,
    pub semantic_parent_local_ancestor_span: u32,
}

/// Ancestors each GPU lane examines locally before global pointer jumping.
pub const SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN: u32 = 32;

/// Absence of a HIR node kind.
pub const HIR_NODE_NONE: u32 = 0;
/// Source-file root node.
pub const HIR_NODE_FILE: u32 = 1;
/// Generic item node before the item family assigns a narrower item kind.
pub const HIR_NODE_ITEM: u32 = 2;
/// Function declaration or definition node.
pub const HIR_NODE_FN: u32 = 3;
/// Function, method, or generic parameter node.
pub const HIR_NODE_PARAM: u32 = 4;
/// Type expression node.
pub const HIR_NODE_TYPE: u32 = 5;
/// Block expression or statement-list node.
pub const HIR_NODE_BLOCK: u32 = 6;
/// Generic statement node before statement fields assign a narrower kind.
pub const HIR_NODE_STMT: u32 = 7;
/// `let` statement node.
pub const HIR_NODE_LET_STMT: u32 = 8;
/// `return` statement node.
pub const HIR_NODE_RETURN_STMT: u32 = 9;
/// `if` statement node.
pub const HIR_NODE_IF_STMT: u32 = 10;
/// `while` loop statement node.
pub const HIR_NODE_WHILE_STMT: u32 = 11;
/// `break` statement node.
pub const HIR_NODE_BREAK_STMT: u32 = 12;
/// `continue` statement node.
pub const HIR_NODE_CONTINUE_STMT: u32 = 13;
/// Generic expression node before expression fields assign a narrower form.
pub const HIR_NODE_EXPR: u32 = 14;
/// Assignment expression node.
pub const HIR_NODE_ASSIGN_EXPR: u32 = 15;
/// Binary operator expression node.
pub const HIR_NODE_BINARY_EXPR: u32 = 16;
/// Unary prefix operator expression node.
pub const HIR_NODE_UNARY_EXPR: u32 = 17;
/// Postfix expression node.
pub const HIR_NODE_POSTFIX_EXPR: u32 = 18;
/// Function or method call expression node.
pub const HIR_NODE_CALL_EXPR: u32 = 19;
/// Indexing expression node.
pub const HIR_NODE_INDEX_EXPR: u32 = 20;
/// Member access expression node.
pub const HIR_NODE_MEMBER_EXPR: u32 = 21;
/// Name/reference expression node.
pub const HIR_NODE_NAME_EXPR: u32 = 22;
/// Literal expression node.
pub const HIR_NODE_LITERAL_EXPR: u32 = 23;
/// Array literal expression node.
pub const HIR_NODE_ARRAY_EXPR: u32 = 24;
/// Constant item node.
pub const HIR_NODE_CONST_ITEM: u32 = 25;
/// Enum item node.
pub const HIR_NODE_ENUM_ITEM: u32 = 26;
/// Struct item node.
pub const HIR_NODE_STRUCT_ITEM: u32 = 27;
/// Struct literal expression node.
pub const HIR_NODE_STRUCT_LITERAL_EXPR: u32 = 28;
/// Type-alias item node.
pub const HIR_NODE_TYPE_ALIAS_ITEM: u32 = 29;
/// `for` loop statement node.
pub const HIR_NODE_FOR_STMT: u32 = 30;
/// Module item node.
pub const HIR_NODE_MODULE_ITEM: u32 = 31;
/// Import item node.
pub const HIR_NODE_IMPORT_ITEM: u32 = 32;
/// Qualified path expression node.
pub const HIR_NODE_PATH_EXPR: u32 = 33;
/// `match` expression node.
pub const HIR_NODE_MATCH_EXPR: u32 = 34;

/// Parser pass that classifies recovered tree nodes into HIR node kinds.
pub struct HirNodesPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirNodesPass,
    label: "hir_nodes",
    shader: "parser/hir/nodes"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirNodesPass {
    const NAME: &'static str = "hir_nodes";
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
            ("gHir".into(), b.hir_params.as_entire_binding()),
            ("emit_stream".into(), b.out_emit.as_entire_binding()),
            ("emit_pos".into(), b.out_emit_pos.as_entire_binding()),
            (
                "token_file_id".into(),
                b.default_token_file_id.as_entire_binding(),
            ),
            ("token_count".into(), b.token_count.as_entire_binding()),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            (
                "hir_token_file_id".into(),
                b.hir_token_file_id.as_entire_binding(),
            ),
        ])
    }
}
