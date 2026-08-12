use super::super::*;
use crate::gpu::compiler_graph::ReflectedComputeSpec;

#[derive(Clone, Copy)]
pub(in crate::type_checker) enum CallClaimKind {
    Generic,
    Const,
}

impl CallClaimKind {
    fn label(self) -> &'static str {
        match self {
            Self::Generic => "type_check.calls.generic_claims.index",
            Self::Const => "type_check.calls.const_claims.index",
        }
    }

    fn specs(self) -> (ReflectedComputeSpec, ReflectedComputeSpec) {
        match self {
            Self::Generic => (
                CALLS_GENERIC_CLAIM_INDEX_CLEAR,
                CALLS_GENERIC_CLAIM_INDEX_BUILD,
            ),
            Self::Const => (CALLS_CONST_CLAIM_INDEX_CLEAR, CALLS_CONST_CLAIM_INDEX_BUILD),
        }
    }
}

pub(in crate::type_checker) struct CallClaimIndexBuild<'a> {
    pub kind: CallClaimKind,
    pub claim_capacity: u32,
    pub dispatch_args: &'a LaniusBuffer<u32>,
    pub graph: &'a compiler_graph::TypeCheckCompilerGraph,
    pub resources: &'a ResourceMap<'a>,
}

/// Exact GPU index over call claims keyed by `(callee, slot)`.
///
/// The active count prepares one indirect domain shared by clearing, building,
/// validation, and every downstream lookup consumer. No ordering is created.
pub(in crate::type_checker) struct CallClaimIndexOperation {
    dispatch_pass: PassData,
    _dispatch_params: LaniusBuffer<CountDispatchParams>,
    dispatch: wgpu::BindGroup,
    dispatch_args: LaniusBuffer<u32>,
    index: ExactLookupOperation,
}

impl CallClaimIndexOperation {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        passes: &TypeCheckPasses,
        input: CallClaimIndexBuild<'_>,
    ) -> Result<Self> {
        let mut resources = input.resources.clone();
        let (count, callee, slot, head, next) = match input.kind {
            CallClaimKind::Generic => (
                "call_generic_claim_count_out",
                "call_generic_claim_callee",
                "call_generic_claim_slot",
                "call_generic_claim_lookup_head",
                "call_generic_claim_lookup_next",
            ),
            CallClaimKind::Const => (
                "call_arg_row_count_out",
                "call_const_claim_callee",
                "call_const_claim_slot",
                "call_const_claim_lookup_head",
                "call_const_claim_lookup_next",
            ),
        };
        for (binding, resource) in [
            ("claim_count_in", count),
            ("claim_callee", callee),
            ("claim_slot", slot),
            ("claim_lookup_head", head),
            ("claim_lookup_next", next),
        ] {
            resources.alias(binding, resource)?;
        }

        let dispatch_params = uniform_from_val(
            device,
            &format!("{}.dispatch.params", input.kind.label()),
            &CountDispatchParams {
                capacity: input.claim_capacity,
                multiplier: 1,
                reserved0: 0,
                reserved1: 0,
            },
        );
        resources.buffer("gParams", &dispatch_params);
        let dispatch_pass = passes.kernel("type_checker/count/dispatch_args").clone();
        let dispatch = reflected_bind_group_with_overrides(
            device,
            &format!("{}.dispatch", input.kind.label()),
            &dispatch_pass,
            &resources,
            &[
                ("gParams", dispatch_params.as_entire_binding()),
                ("count_in", resources[count].clone()),
                ("dispatch_args", input.dispatch_args.as_entire_binding()),
            ],
        )?;
        let (clear, build) = input.kind.specs();
        let index = ExactLookupOperation::new_with_indirect_clear(
            device,
            input.graph,
            &resources,
            passes,
            clear,
            build,
            input.dispatch_args,
            input.dispatch_args,
        )?;

        Ok(Self {
            dispatch_pass,
            _dispatch_params: dispatch_params,
            dispatch,
            dispatch_args: input.dispatch_args.clone(),
            index,
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        record_compute(
            encoder,
            &self.dispatch_pass,
            &self.dispatch,
            "type_check.calls.claim_index.dispatch_args",
            1,
        )?;
        self.index.record(encoder)
    }

    pub(in crate::type_checker) fn dispatch_args(&self) -> &LaniusBuffer<u32> {
        &self.dispatch_args
    }
}
