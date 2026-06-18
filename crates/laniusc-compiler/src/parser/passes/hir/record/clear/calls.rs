use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that clears call-related HIR record buffers before reconstruction.
pub struct HirRecordClearCallsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirRecordClearCallsPass,
    label: "hir_record_clear_calls",
    shader: "parser/hir/record/clear/calls"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirRecordClearCallsPass {
    const NAME: &'static str = "hir_record_clear_calls";
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
            ("gClear".into(), b.hir_params.as_entire_binding()),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_member_receiver_node".into(),
                b.hir_member_receiver_node.as_entire_binding(),
            ),
            (
                "hir_member_receiver_token".into(),
                b.hir_member_receiver_token.as_entire_binding(),
            ),
            (
                "hir_member_name_token".into(),
                b.hir_member_name_token.as_entire_binding(),
            ),
            (
                "hir_call_callee_node".into(),
                b.hir_call_callee_node.as_entire_binding(),
            ),
            (
                "hir_call_context_stmt_node".into(),
                b.hir_call_context_stmt_node.as_entire_binding(),
            ),
            (
                "hir_call_arg_start".into(),
                b.hir_call_arg_start.as_entire_binding(),
            ),
            (
                "hir_call_arg_end".into(),
                b.hir_call_arg_end.as_entire_binding(),
            ),
            (
                "hir_call_arg_count".into(),
                b.hir_call_arg_count.as_entire_binding(),
            ),
            (
                "hir_call_arg_parent_call".into(),
                b.hir_call_arg_parent_call.as_entire_binding(),
            ),
            (
                "hir_call_arg_ordinal".into(),
                b.hir_call_arg_ordinal.as_entire_binding(),
            ),
        ])
    }
}
