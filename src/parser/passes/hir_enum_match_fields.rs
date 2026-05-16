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

pub struct HirEnumMatchFieldsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirEnumMatchFieldsPass,
    label: "hir_enum_match_fields",
    shader: "hir_enum_match_fields"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirEnumMatchFieldsPass {
    const NAME: &'static str = "hir_enum_match_fields";
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
                "gHirEnumMatch".into(),
                b.hir_enum_match_fields_params.as_entire_binding(),
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
            ("subtree_end".into(), b.subtree_end.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_variant_parent_enum".into(),
                b.hir_variant_parent_enum.as_entire_binding(),
            ),
            (
                "hir_variant_ordinal".into(),
                b.hir_variant_ordinal.as_entire_binding(),
            ),
            (
                "hir_variant_payload_start".into(),
                b.hir_variant_payload_start.as_entire_binding(),
            ),
            (
                "hir_variant_payload_count".into(),
                b.hir_variant_payload_count.as_entire_binding(),
            ),
            (
                "hir_match_scrutinee_node".into(),
                b.hir_match_scrutinee_node.as_entire_binding(),
            ),
            (
                "hir_match_arm_start".into(),
                b.hir_match_arm_start.as_entire_binding(),
            ),
            (
                "hir_match_arm_count".into(),
                b.hir_match_arm_count.as_entire_binding(),
            ),
            (
                "hir_match_arm_pattern_node".into(),
                b.hir_match_arm_pattern_node.as_entire_binding(),
            ),
            (
                "hir_match_arm_payload_start".into(),
                b.hir_match_arm_payload_start.as_entire_binding(),
            ),
            (
                "hir_match_arm_payload_count".into(),
                b.hir_match_arm_payload_count.as_entire_binding(),
            ),
            (
                "hir_match_arm_result_node".into(),
                b.hir_match_arm_result_node.as_entire_binding(),
            ),
        ])
    }
}
