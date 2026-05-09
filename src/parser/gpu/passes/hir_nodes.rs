use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::gpu::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct Params {
    pub n: u32,
    pub uses_ll1: u32,
}

pub const HIR_NODE_NONE: u32 = 0;
pub const HIR_NODE_FILE: u32 = 1;
pub const HIR_NODE_ITEM: u32 = 2;
pub const HIR_NODE_FN: u32 = 3;
pub const HIR_NODE_PARAM: u32 = 4;
pub const HIR_NODE_TYPE: u32 = 5;
pub const HIR_NODE_BLOCK: u32 = 6;
pub const HIR_NODE_STMT: u32 = 7;
pub const HIR_NODE_LET_STMT: u32 = 8;
pub const HIR_NODE_RETURN_STMT: u32 = 9;
pub const HIR_NODE_IF_STMT: u32 = 10;
pub const HIR_NODE_WHILE_STMT: u32 = 11;
pub const HIR_NODE_BREAK_STMT: u32 = 12;
pub const HIR_NODE_CONTINUE_STMT: u32 = 13;
pub const HIR_NODE_EXPR: u32 = 14;
pub const HIR_NODE_ASSIGN_EXPR: u32 = 15;
pub const HIR_NODE_BINARY_EXPR: u32 = 16;
pub const HIR_NODE_UNARY_EXPR: u32 = 17;
pub const HIR_NODE_POSTFIX_EXPR: u32 = 18;
pub const HIR_NODE_CALL_EXPR: u32 = 19;
pub const HIR_NODE_INDEX_EXPR: u32 = 20;
pub const HIR_NODE_MEMBER_EXPR: u32 = 21;
pub const HIR_NODE_NAME_EXPR: u32 = 22;
pub const HIR_NODE_LITERAL_EXPR: u32 = 23;
pub const HIR_NODE_ARRAY_EXPR: u32 = 24;
pub const HIR_NODE_CONST_ITEM: u32 = 25;
pub const HIR_NODE_ENUM_ITEM: u32 = 26;

pub struct HirNodesPass {
    data: PassData,
}

impl HirNodesPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let data = crate::gpu::passes_core::make_pass_data(
            device,
            "hir_nodes",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/hir_nodes.spv")),
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/hir_nodes.reflect.json")),
        )?;
        Ok(Self { data })
    }
}

impl Pass<ParserBuffers, crate::parser::gpu::debug::DebugOutput> for HirNodesPass {
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
            (
                "emit_stream".into(),
                if b.tree_stream_uses_ll1 {
                    b.ll1_emit.as_entire_binding()
                } else {
                    b.out_emit.as_entire_binding()
                },
            ),
            (
                "emit_pos".into(),
                if b.tree_stream_uses_ll1 {
                    b.ll1_emit_pos.as_entire_binding()
                } else {
                    b.out_emit_pos.as_entire_binding()
                },
            ),
            (
                "ll1_status".into(),
                if b.tree_count_uses_status && !b.tree_stream_uses_ll1 {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
        ])
    }
}
