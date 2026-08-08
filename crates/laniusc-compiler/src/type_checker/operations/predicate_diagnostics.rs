use super::*;
use crate::gpu::compiler_graph::{CompilerGraphBuilder, ReflectedComputeSpec};

pub(in crate::type_checker) const PREDICATE_DIAGNOSTICS_CLEAR: ReflectedComputeSpec = typecheck_operation!(
    "type_check.semantic_artifact.predicate_diagnostics.clear",
    HirNodes,
    "type_checker/semantic/artifact/00_predicate_diagnostics_clear";
    writes ["compact_predicate_diagnostic_facts"]
);
pub(in crate::type_checker) const PREDICATE_DIAGNOSTICS_CLAIM: ReflectedComputeSpec = typecheck_pass!(
    "type_check.semantic_artifact.predicate_diagnostics.claim",
    HirNodes,
    "type_checker/semantic/artifact/01_predicate_diagnostics_claim"
);
pub(in crate::type_checker) const PREDICATE_DIAGNOSTICS_PROJECT: ReflectedComputeSpec = typecheck_pass!(
    "type_check.semantic_artifact.predicate_diagnostics",
    HirNodes,
    "type_checker/semantic/artifact/02_predicate_diagnostics"
);

/// Selects one predicate diagnostic per HIR row and projects the compact artifact.
pub(in crate::type_checker) struct PredicateDiagnosticsOperation {
    clear: ComputeOperation,
    claim: ComputeOperation,
    project: ComputeOperation,
}

impl PredicateDiagnosticsOperation {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        kernels: &KernelRegistry,
        hir_capacity: u32,
        dispatch_args: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        Ok(Self {
            clear: ComputeOperation::direct_spec(
                device,
                graph,
                resources,
                kernels,
                PREDICATE_DIAGNOSTICS_CLEAR,
                hir_capacity,
            )?,
            claim: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                kernels,
                PREDICATE_DIAGNOSTICS_CLAIM,
                dispatch_args,
            )?,
            project: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                kernels,
                PREDICATE_DIAGNOSTICS_PROJECT,
                dispatch_args,
            )?,
        })
    }

    pub(in crate::type_checker) fn register(
        graph: &mut CompilerGraphBuilder,
        kernels: &impl crate::gpu::kernels::KernelReflections,
    ) -> Result<(), String> {
        for spec in [
            PREDICATE_DIAGNOSTICS_CLEAR,
            PREDICATE_DIAGNOSTICS_CLAIM,
            PREDICATE_DIAGNOSTICS_PROJECT,
        ] {
            spec.register_kernel(graph, kernels)?;
        }
        Ok(())
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.clear.record(encoder)?;
        self.claim.record(encoder)?;
        self.project.record(encoder)
    }
}
