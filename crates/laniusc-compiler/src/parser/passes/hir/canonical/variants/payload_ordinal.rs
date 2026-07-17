use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalVariantPayloadOrdinalPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalVariantPayloadOrdinalPass, label: "hir_canonical_variant_payload_ordinal", shader: "parser/hir/canonical/variants/payload_ordinal");

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput>
    for HirCanonicalVariantPayloadOrdinalPass
{
    const NAME: &'static str = "hir_canonical_variant_payload_ordinal";
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
                "payload_table_count".into(),
                b.hir_variant_payload_table_count.as_entire_binding(),
            ),
            (
                "variant_payload_start".into(),
                b.hir_variant_compact_payload_start.as_entire_binding(),
            ),
            (
                "variant_payload_count".into(),
                b.hir_variant_compact_payload_count.as_entire_binding(),
            ),
            (
                "hir_variant_payloads".into(),
                b.hir_variant_payload_rows.as_entire_binding(),
            ),
            (
                "canonical_status".into(),
                b.hir_canonical_status.as_entire_binding(),
            ),
        ])
    }
}
