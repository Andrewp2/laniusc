//! Call-environment bindings validated once per publication.
//!
//! Recursive substitution reads explicit, contextual and argument constant
//! bindings at every step. Producers publish them; these passes record the
//! validated outcome next to the evidence, so readers only load it:
//! - 03a0b admits explicit constant rows after 03a0 binds an application.
//! - 03a3b selects and checks each `(callee, slot)` argument claim group after
//!   the claim index is rebuilt.
//! - 03a4c admits contextual constants after producers that publish without
//!   inline admission (03a4b, 03k3 and 03a8); 03d and 08a admit inline.

use super::super::*;
use crate::gpu::compiler_graph::{AccessMode, ReflectedComputeSpec};

pub(in crate::type_checker) const CALLS_EXPLICIT_CONSTANTS_ADMIT: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.calls.explicit_applications.admit_constants",
        Tokens,
        "type_checker/calls/03a0b_validate_explicit_constants"
    )
    .with_indirect_dispatch("token_active_dispatch_args");

pub(in crate::type_checker) const CALLS_CONST_ENVIRONMENT_PUBLISH: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.calls.const_claims.environment",
        CallArguments,
        "type_checker/calls/03a3b_publish_call_environment"
    )
    // Each group's first chain row stores its outcome; readers stop at that
    // row, so cells of other rows are never read.
    .with_modes(&[("call_const_env_binding", AccessMode::Write)])
    .with_indirect_dispatch("call_const_claim_index_dispatch_args");

pub(in crate::type_checker) const CALLS_CONTEXT_CONSTANTS_ADMIT: ReflectedComputeSpec =
    typecheck_pass!(
        "type_check.calls.contextual_result_requests.admit_constants",
        HirNodes,
        "type_checker/calls/03a4c_admit_context_constants"
    )
    .with_indirect_dispatch("hir_active_dispatch_args");
pub(in crate::type_checker) const CALLS_RECORD_CONTEXT_CONSTANTS_ADMIT: ReflectedComputeSpec =
    CALLS_CONTEXT_CONSTANTS_ADMIT.with_name("type_check.calls.record_contexts.admit_constants");
pub(in crate::type_checker) const CALLS_FINAL_CONTEXT_CONSTANTS_ADMIT: ReflectedComputeSpec =
    CALLS_CONTEXT_CONSTANTS_ADMIT
        .with_name("type_check.calls.contextual_results.final.admit_constants");
pub(in crate::type_checker) const CALLS_EXPLICIT_CONTEXT_CONSTANTS_ADMIT: ReflectedComputeSpec =
    CALLS_CONTEXT_CONSTANTS_ADMIT
        .with_name("type_check.calls.explicit_applications.validate.admit_constants");

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
        token_dispatch_args: &LaniusBuffer<u32>,
        record_contexts: bool,
    ) -> Result<Self> {
        let context = |spec| {
            ComputeOperation::indirect_spec(device, graph, resources, passes, spec, hir_dispatch_args)
        };
        Ok(Self {
            explicit_constants: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                passes,
                CALLS_EXPLICIT_CONSTANTS_ADMIT,
                token_dispatch_args,
            )?,
            result_requests: context(CALLS_CONTEXT_CONSTANTS_ADMIT)?,
            record_contexts: if record_contexts {
                Some(context(CALLS_RECORD_CONTEXT_CONSTANTS_ADMIT)?)
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
