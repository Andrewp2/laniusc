use super::super::*;
use crate::gpu::compiler_graph::ReflectedComputeSpec;

#[derive(Clone, Copy)]
pub(in crate::type_checker) enum CallClaimKind {
    Generic,
    Const,
}

impl CallClaimKind {
    fn build_spec(self) -> ReflectedComputeSpec {
        match self {
            Self::Generic => CALLS_GENERIC_CLAIM_INDEX_BUILD,
            Self::Const => CALLS_CONST_CLAIM_INDEX_BUILD,
        }
    }
}

pub(in crate::type_checker) struct CallClaimIndexBuild<'a> {
    pub kind: CallClaimKind,
    pub dispatch_args: &'a LaniusBuffer<u32>,
    pub graph: &'a compiler_graph::TypeCheckCompilerGraph,
    pub resources: &'a ResourceMap<'a>,
}

/// Exact GPU index over call claims keyed by `(callee, slot)`.
///
/// The claim scan's apply writes the indirect domain shared by building,
/// validation, and every downstream lookup consumer. Claim emission
/// (03a1_emit_generic_claims) clears the bucket heads.
pub(in crate::type_checker) struct CallClaimIndexOperation {
    dispatch_args: LaniusBuffer<u32>,
    build: ComputeOperation,
}

impl CallClaimIndexOperation {
    pub(in crate::type_checker) fn new(
        device: &wgpu::Device,
        passes: &TypeCheckPasses,
        input: CallClaimIndexBuild<'_>,
    ) -> Result<Self> {
        let mut resources = input.resources.clone();
        let (count, callee, slot, head, next, mask) = match input.kind {
            CallClaimKind::Generic => (
                "call_generic_claim_count_out",
                "call_generic_claim_callee",
                "call_generic_claim_slot",
                "call_generic_claim_lookup_head",
                "call_generic_claim_lookup_next",
                "call_generic_claim_slot_mask",
            ),
            CallClaimKind::Const => (
                "call_const_claim_count_out",
                "call_const_claim_callee",
                "call_const_claim_slot",
                "call_const_claim_lookup_head",
                "call_const_claim_lookup_next",
                "call_const_claim_slot_mask",
            ),
        };
        for (binding, resource) in [
            ("claim_count_in", count),
            ("claim_callee", callee),
            ("claim_slot", slot),
            ("claim_lookup_head", head),
            ("claim_lookup_next", next),
            ("claim_slot_mask", mask),
        ] {
            resources.alias(binding, resource)?;
        }

        let build = ComputeOperation::indirect_spec(
            device,
            input.graph,
            &resources,
            passes,
            input.kind.build_spec(),
            input.dispatch_args,
        )?;

        Ok(Self {
            dispatch_args: input.dispatch_args.clone(),
            build,
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.build.record(encoder)
    }

    pub(in crate::type_checker) fn dispatch_args(&self) -> &LaniusBuffer<u32> {
        &self.dispatch_args
    }
}
