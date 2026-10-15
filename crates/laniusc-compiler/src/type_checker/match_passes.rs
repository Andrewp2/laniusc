//! Canonical facts shared by the matching consumers (docs/canonical-type-ids.md,
//! "Matching"): the expected type of each struct-literal field in caller
//! scope, as an ID with a checked row (`type_checker/match/field_expected.slang`),
//! and the call environments that dependency call validation reads.
//! Resources, pass names, compiler-graph registration and the operations that
//! record them; kept out of `compiler_graph.rs`.

use super::*;
use crate::gpu::compiler_graph::{
    CompilerGraphBuilder,
    CompilerPhase,
    ResourceClass,
    ResourceDomain,
};

pub(super) const FIELD_EXPECTED_IDS_KERNEL: &str = "type_checker/match/01_field_expected_ids";
/// After the struct-literal fields that precede call inference.
pub(super) const FIELD_EXPECTED_IDS_EARLY_PASS: &str = "type_check.match.field_expected_ids.early";
/// After the struct-literal fields of each inference round.
pub(super) const FIELD_EXPECTED_IDS_INFERENCE_PASS: &str =
    "type_check.match.field_expected_ids.inference";

/// The call environments once more after inference, for dependency call
/// validation: the final round's admissions follow its own publication.
pub(super) const VALIDATION_CALL_ENVS_PASS: &str = "type_check.match.call_envs.validation";

/// Declares `struct_init_field_expected_ct`, one word per token.
pub(super) fn register_match_storage(
    graph: &mut CompilerGraphBuilder,
    token_rows: u64,
) -> Result<(), String> {
    graph.add_storage(
        "struct_init_field_expected_ct",
        ResourceDomain::Tokens,
        ResourceClass::Workspace,
        token_rows.max(1) * 4,
    )?;
    Ok(())
}

/// Registers one field-expectation pass (`name` is one of the pass names
/// above), right after the struct-literal fields it follows.
pub(super) fn register_field_expected_ids_pass(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    name: &'static str,
) -> Result<(), String> {
    graph.add_kernel_pass_by_name(
        name,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        FIELD_EXPECTED_IDS_KERNEL,
        &[],
    )?;
    graph.add_indirect_dispatch(name, "token_active_dispatch_args")?;
    Ok(())
}

/// Registers the call-environment publication that dependency call
/// validation reads, right before that validation.
pub(super) fn register_validation_call_env_pass(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
) -> Result<(), String> {
    graph.add_kernel_pass_by_name(
        VALIDATION_CALL_ENVS_PASS,
        CompilerPhase::TypeCheck,
        ResourceDomain::HirNodes,
        kernels,
        super::substitution_passes::SUBSTITUTION_CALL_ENVS_KERNEL,
        &[],
    )?;
    graph.add_indirect_dispatch(VALIDATION_CALL_ENVS_PASS, "hir_active_dispatch_args")?;
    Ok(())
}

/// The call-environment publication before dependency call validation.
pub(in crate::type_checker) struct ValidationCallEnvOperation {
    publish: ComputeOperation,
}

impl ValidationCallEnvOperation {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        passes: &TypeCheckPasses,
        hir_dispatch_args: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        Ok(Self {
            publish: ComputeOperation::indirect(
                device,
                graph,
                resources,
                VALIDATION_CALL_ENVS_PASS,
                &passes.kernel(super::substitution_passes::SUBSTITUTION_CALL_ENVS_KERNEL),
                hir_dispatch_args,
            )?,
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.publish.record(encoder)
    }
}

/// The field-expectation passes: one before call inference, and one per
/// inference round when the round projects struct-literal fields.
pub(in crate::type_checker) struct FieldExpectedIdOperations {
    early: ComputeOperation,
    inference: Option<ComputeOperation>,
}

impl FieldExpectedIdOperations {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        resources: &ResourceMap<'_>,
        passes: &TypeCheckPasses,
        inference: bool,
    ) -> Result<Self> {
        let token_dispatch_args = typed_buffer_from_resources(resources, "token_active_dispatch_args")?;
        let operation = |name| {
            ComputeOperation::indirect(
                device,
                graph,
                resources,
                name,
                &passes.kernel(FIELD_EXPECTED_IDS_KERNEL),
                &token_dispatch_args,
            )
        };
        Ok(Self {
            early: operation(FIELD_EXPECTED_IDS_EARLY_PASS)?,
            inference: if inference {
                Some(operation(FIELD_EXPECTED_IDS_INFERENCE_PASS)?)
            } else {
                None
            },
        })
    }

    /// After the struct-literal fields that precede call inference.
    pub(in crate::type_checker) fn record_early(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.early.record(encoder)
    }

    /// After an inference round's struct-literal fields.
    pub(in crate::type_checker) fn record_inference(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        match &self.inference {
            Some(operation) => operation.record(encoder),
            None => Ok(()),
        }
    }
}
