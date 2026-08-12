use super::super::*;
use crate::gpu::compiler_graph::ReflectedComputeSpec;

pub(in crate::type_checker) const GENERIC_PARAM_LOOKUP_CLEAR: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.generic_params.lookup.clear",
        Declarations,
        "type_checker/type/instances/00b1_clear_generic_param_lookup"
    )
    .initializer();

pub(in crate::type_checker) const GENERIC_PARAM_LOOKUP_BUILD: ReflectedComputeSpec = typecheck_pass!(
    "type_check.generic_params.lookup.build",
    Declarations,
    "type_checker/type/instances/00b2_build_generic_param_lookup"
);

pub(in crate::type_checker) const GENERIC_PARAM_ROWS_SCATTER: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.generic_params.rows.scatter",
        Declarations,
        "type_checker/type/instances/00d_scatter_generic_param_rows"
    )
    .with_modes(&[(
        "generic_type_param_rows",
        crate::gpu::compiler_graph::AccessMode::Write,
    )]);

/// Exact name lookup and stable per-kind compaction for generic parameters.
///
/// This operation preserves the compact HIR's source ordering. It does not
/// impose an additional lexicographic ordering merely to support lookup or
/// slot assignment.
pub(in crate::type_checker) struct GenericParameterIndex {
    lookup: ExactLookupOperation,
    type_scan: PrefixScanOperation,
    const_scan: PrefixScanOperation,
    scatter_rows: ComputeOperation,
}

impl GenericParameterIndex {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        passes: &TypeCheckPasses,
        resources: &ResourceMap<'_>,
        token_capacity: u32,
    ) -> Result<Self> {
        let hir_dispatch = typed_buffer_from_resources(resources, "hir_active_dispatch_args")?;
        let (type_scan, const_scan) = PrefixScanOperation::from_pair_spec(
            device,
            passes,
            resources,
            compiler_graph::GENERIC_PARAM_SLOT_SCAN,
        )?;
        Ok(Self {
            lookup: ExactLookupOperation::new(
                device,
                graph,
                resources,
                passes,
                GENERIC_PARAM_LOOKUP_CLEAR,
                GENERIC_PARAM_LOOKUP_BUILD,
                token_capacity.saturating_mul(2).max(1),
                &hir_dispatch,
            )?,
            type_scan,
            const_scan,
            scatter_rows: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                passes,
                GENERIC_PARAM_ROWS_SCATTER,
                &hir_dispatch,
            )?,
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.lookup.record(encoder)?;
        PrefixScanOperation::record_pair(&self.type_scan, &self.const_scan, encoder)?;
        self.scatter_rows.record(encoder)
    }
}
