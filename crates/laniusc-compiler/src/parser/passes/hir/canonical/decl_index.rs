use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

macro_rules! decl_index_pass {
    ($name:ident, $entry:literal, $label:literal) => {
        pub struct $name { data: PassData }

        crate::gpu::passes_core::impl_static_shader_pass!(
            $name,
            label: $label,
            entry: $entry,
            shader: "parser/hir/canonical/decl_index"
        );

        impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for $name {
            const NAME: &'static str = $label;
            const DIM: DispatchDim = DispatchDim::D1;
            fn from_data(data: PassData) -> Self { Self { data } }
            fn data(&self) -> &PassData { &self.data }
            fn create_resource_map<'a>(
                &self,
                b: &'a ParserBuffers,
            ) -> HashMap<String, wgpu::BindingResource<'a>> {
                HashMap::from([
                    ("gCanonical".into(), b.hir_canonical_params.as_entire_binding()),
                    ("canonical_count".into(), b.hir_canonical_count.as_entire_binding()),
                    ("hir_core".into(), b.hir_core.as_entire_binding()),
                    ("hir_payload".into(), b.hir_payload.as_entire_binding()),
                    (
                        "decl_by_name_token".into(),
                        b.hir_canonical_anchor_owner.as_entire_binding(),
                    ),
                ])
            }
        }
    };
}

decl_index_pass!(
    HirCanonicalDeclIndexClearPass,
    "clear",
    "hir_canonical_decl_index_clear"
);
decl_index_pass!(
    HirCanonicalDeclIndexScatterPass,
    "scatter",
    "hir_canonical_decl_index_scatter"
);
