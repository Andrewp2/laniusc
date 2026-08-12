use super::super::*;

/// Exact GPU method index over compact method rows.
///
/// Construction clears hash heads and inserts every compact method row. The
/// validator then detects exact duplicates inside the selected bucket. Call
/// resolution consumes the same heads and chains, so no independently sorted
/// representation or key contract can drift from the lookup implementation.
pub(in crate::type_checker) struct MethodIndex {
    lookup: ExactLookupOperation,
    validate: ComputeOperation,
}

impl MethodIndex {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        passes: &TypeCheckPasses,
        resources: &ResourceMap<'_>,
        method_dispatch_args: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        Ok(Self {
            lookup: ExactLookupOperation::new_with_indirect_clear(
                device,
                graph,
                resources,
                passes,
                METHODS_LOOKUP_CLEAR,
                METHODS_LOOKUP_BUILD,
                method_dispatch_args,
                method_dispatch_args,
            )?,
            validate: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                passes,
                METHODS_VALIDATE_KEYS,
                method_dispatch_args,
            )?,
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.lookup.record(encoder)?;
        self.validate.record(encoder)
    }
}
