//! Canonical facts shared by the matching consumers (docs/canonical-type-ids.md,
//! "Matching"): the expected type of each struct-literal field in caller
//! scope, as an ID with a checked row (`type_checker/match/field_expected.slang`),
//! and the call environments that dependency call validation reads.
//! Resources, pass names, compiler-graph registration and the operations that
//! record them; kept out of `compiler_graph.rs`.

use super::*;
use crate::gpu::compiler_graph::{
    AccessMode,
    CompilerGraphBuilder,
    CompilerPhase,
    ReflectedResourceBinding,
    ResourceClass,
    ResourceDomain,
};

pub(super) const FIELD_EXPECTED_IDS_KERNEL: &str = "type_checker/match/01_field_expected_ids";
/// The rounds' copy over the listed struct-literal field rows.
pub(super) const LISTED_FIELD_EXPECTED_IDS_KERNEL: &str =
    "type_checker/match/01b_listed_field_expected_ids";
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
/// above), right after the struct-literal fields it follows. The pass writes
/// every token of `struct_init_field_expected_ct` without reading it, so it
/// initializes the column; the graph rows it realizes stay read-write.
pub(super) fn register_field_expected_ids_pass(
    graph: &mut CompilerGraphBuilder,
    kernels: &impl crate::gpu::kernels::KernelReflections,
    name: &'static str,
) -> Result<(), String> {
    let column = graph
        .resource_id("struct_init_field_expected_ct")
        .ok_or_else(|| format!("{name} needs struct_init_field_expected_ct registered first"))?;
    // The early pass writes every token. The rounds' pass writes the listed
    // field tokens and keeps the early pass's other tokens.
    let early = name == FIELD_EXPECTED_IDS_EARLY_PASS;
    graph.add_kernel_pass_by_name(
        name,
        CompilerPhase::TypeCheck,
        ResourceDomain::Tokens,
        kernels,
        if early { FIELD_EXPECTED_IDS_KERNEL } else { LISTED_FIELD_EXPECTED_IDS_KERNEL },
        &[ReflectedResourceBinding {
            binding: "struct_init_field_expected_ct",
            resource: column,
            mode: Some(if early { AccessMode::Write } else { AccessMode::ReadWrite }),
        }],
    )?;
    graph.add_indirect_dispatch(
        name,
        if early { "token_active_dispatch_args" } else { "struct_literal_field_args" },
    )?;
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
        Ok(Self {
            early: ComputeOperation::indirect(
                device,
                graph,
                resources,
                FIELD_EXPECTED_IDS_EARLY_PASS,
                &passes.kernel(FIELD_EXPECTED_IDS_KERNEL),
                &token_dispatch_args,
            )?,
            inference: if inference {
                Some(ComputeOperation::indirect(
                    device,
                    graph,
                    resources,
                    FIELD_EXPECTED_IDS_INFERENCE_PASS,
                    &passes.kernel(LISTED_FIELD_EXPECTED_IDS_KERNEL),
                    &typed_buffer_from_resources(resources, "struct_literal_field_args")?,
                )?)
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
