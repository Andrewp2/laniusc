use super::super::*;
use crate::gpu::compiler_graph::ReflectedComputeSpec;

pub(in crate::type_checker) const STRUCT_FIELD_LOOKUP_CLEAR: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.struct_fields.lookup.clear",
        Declarations,
        "type_checker/type/instances/02a_clear_struct_field_lookup"
    )
    .initializer();

pub(in crate::type_checker) const STRUCT_FIELD_LOOKUP_BUILD: ReflectedComputeSpec = typecheck_pass!(
    "type_check.struct_fields.lookup.build",
    Declarations,
    "type_checker/type/instances/02b_build_struct_field_lookup"
);

pub(in crate::type_checker) struct StructFieldIndex(ExactLookupOperation);

impl StructFieldIndex {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        passes: &TypeCheckPasses,
        resources: &ResourceMap<'_>,
        token_capacity: u32,
    ) -> Result<Self> {
        let hir_dispatch = typed_buffer_from_resources(resources, "hir_active_dispatch_args")?;
        Ok(Self(ExactLookupOperation::new(
            device,
            graph,
            resources,
            passes,
            STRUCT_FIELD_LOOKUP_CLEAR,
            STRUCT_FIELD_LOOKUP_BUILD,
            token_capacity.saturating_mul(2).max(1),
            &hir_dispatch,
        )?))
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.0.record(encoder)
    }
}
