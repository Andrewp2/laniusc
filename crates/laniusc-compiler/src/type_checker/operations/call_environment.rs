//! Call-environment bindings validated once per publication.
//!
//! Recursive substitution reads explicit, contextual and argument constant
//! bindings at every step. Producers publish them; these passes record the
//! validated outcome next to the evidence, so readers only load it:
//! - `validate_explicit_constants` admits rows after `bind_explicit_applications`.
//! - `build_call_claim_indexes` selects and checks each `(callee, slot)` argument
//!   claim group after the claim index is rebuilt.
//! - `admit_context_constants` admits contextual constants after result
//!   comparisons, record contexts and explicit application validation.
//!   Method receiver binding and dependency result validation admit inline.

use super::super::*;
use crate::gpu::compiler_graph::ReflectedComputeSpec;

pub(in crate::type_checker) const CALLS_EXPLICIT_CONSTANTS_ADMIT: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.calls.explicit_applications.admit_constants",
        Tokens,
        "type_checker/calls/claims/validate_explicit_constants"
    )
    // Applications that reserved binding rows in bind_explicit_applications.
    .with_indirect_dispatch("call_explicit_admission_args");

pub(in crate::type_checker) const CALLS_CONTEXT_CONSTANTS_ADMIT: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.calls.contextual_result_requests.admit_constants",
        HirNodes,
        "type_checker/calls/claims/admit_context_constants"
    )
    .with_indirect_dispatch("inference_hir_list_args");
pub(in crate::type_checker) const CALLS_RECORD_CONTEXT_CONSTANTS_ADMIT: ReflectedComputeSpec =
    CALLS_CONTEXT_CONSTANTS_ADMIT.with_name("type_check.calls.record_contexts.admit_constants");
pub(in crate::type_checker) const CALLS_FINAL_CONTEXT_CONSTANTS_ADMIT: ReflectedComputeSpec =
    CALLS_CONTEXT_CONSTANTS_ADMIT
        .with_name("type_check.calls.contextual_results.final.admit_constants")
        .with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_EXPLICIT_CONTEXT_CONSTANTS_ADMIT: ReflectedComputeSpec =
    CALLS_CONTEXT_CONSTANTS_ADMIT
        .with_name("type_check.calls.explicit_applications.validate.admit_constants")
        .with_indirect_dispatch("hir_active_dispatch_args");

/// The producer whose deferred contextual publications are admitted next.
#[derive(Clone, Copy)]
pub(in crate::type_checker) enum ContextConstantProducer {
    ResultRequests,
    RecordContexts,
    FinalResultRequests,
    ExplicitValidation,
}

/// Admission passes recorded directly after their producers.
pub(in crate::type_checker) struct CallEnvironmentAdmission {
    explicit_constants: ComputeOperation,
    result_requests: ComputeOperation,
    record_contexts: Option<ComputeOperation>,
    final_result_requests: ComputeOperation,
    explicit_validation: ComputeOperation,
}

impl CallEnvironmentAdmission {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        passes: &TypeCheckPasses,
        resources: &ResourceMap<'_>,
        hir_dispatch_args: &LaniusBuffer<u32>,
        listed_hir_args: &LaniusBuffer<u32>,
        explicit_admission_args: &LaniusBuffer<u32>,
        record_contexts: bool,
    ) -> Result<Self> {
        let context = |spec| {
            ComputeOperation::indirect_spec(device, graph, resources, passes, spec, hir_dispatch_args)
        };
        // The rounds' admissions visit the listed active blocks.
        let listed = |spec| {
            ComputeOperation::indirect_spec(device, graph, resources, passes, spec, listed_hir_args)
        };
        Ok(Self {
            explicit_constants: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                passes,
                CALLS_EXPLICIT_CONSTANTS_ADMIT,
                explicit_admission_args,
            )?,
            result_requests: listed(CALLS_CONTEXT_CONSTANTS_ADMIT)?,
            record_contexts: if record_contexts {
                Some(listed(CALLS_RECORD_CONTEXT_CONSTANTS_ADMIT)?)
            } else {
                None
            },
            final_result_requests: context(CALLS_FINAL_CONTEXT_CONSTANTS_ADMIT)?,
            explicit_validation: context(CALLS_EXPLICIT_CONTEXT_CONSTANTS_ADMIT)?,
        })
    }

    /// Records explicit constant admission after explicit applications bind.
    pub(in crate::type_checker) fn record_explicit(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.explicit_constants.record(encoder)
    }

    /// Records contextual constant admission after `producer` publishes.
    pub(in crate::type_checker) fn record_context(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        producer: ContextConstantProducer,
    ) -> Result<()> {
        match producer {
            ContextConstantProducer::ResultRequests => self.result_requests.record(encoder),
            ContextConstantProducer::RecordContexts => self
                .record_contexts
                .as_ref()
                .ok_or_else(|| anyhow::anyhow!("record context admission is not compiled"))?
                .record(encoder),
            ContextConstantProducer::FinalResultRequests => {
                self.final_result_requests.record(encoder)
            }
            ContextConstantProducer::ExplicitValidation => self.explicit_validation.record(encoder),
        }
    }
}
