use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalStringScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalStringScatterPass,
    label: "hir_canonical_string_scatter",
    shader: "parser/hir/canonical/strings/scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalStringScatterPass {
    const NAME: &'static str = "hir_canonical_string_scatter";
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
                "gCanonical".into(),
                b.hir_canonical_params.as_entire_binding(),
            ),
            (
                "raw_to_hir".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "canonical_anchor_owner".into(),
                b.hir_canonical_anchor_owner.as_entire_binding(),
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
            (
                "hir_expr_record".into(),
                b.hir_expr_record.as_entire_binding(),
            ),
            (
                "hir_call_callee_node".into(),
                b.hir_call_callee_node.as_entire_binding(),
            ),
            (
                "hir_token_file_id".into(),
                b.hir_token_file_id.as_entire_binding(),
            ),
            (
                "raw_string_count".into(),
                b.hir_string_count.as_entire_binding(),
            ),
            (
                "raw_string_node".into(),
                b.hir_string_node.as_entire_binding(),
            ),
            (
                "raw_string_data_offset".into(),
                b.hir_string_data_offset.as_entire_binding(),
            ),
            (
                "raw_string_decoded_len".into(),
                b.hir_string_decoded_len.as_entire_binding(),
            ),
            (
                "hir_strings".into(),
                b.hir_canonical_string_rows.as_entire_binding(),
            ),
            ("hir_payload".into(), b.hir_payload.as_entire_binding()),
            (
                "canonical_status".into(),
                b.hir_canonical_status.as_entire_binding(),
            ),
        ])
    }
}
