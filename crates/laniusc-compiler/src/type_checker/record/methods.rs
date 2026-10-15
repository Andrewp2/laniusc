// src/type_checker/record/methods.rs

use super::*;

const METHOD_CALL_RESULT_RECEIVER_PASSES: usize = 8;

impl MethodBindGroups {
    pub(in crate::type_checker) fn record_declarations(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.collect.record(encoder)?;
        self.attach_metadata.record(encoder)?;
        self.bind_self_receivers.record(encoder)
    }

    /// Freeze sources, collect every contender, then publish a single winner.
    /// The callback streams all pages once to collect and again to project;
    /// it must finish its page submissions before returning in either phase.
    pub(in crate::type_checker) fn record_call_selection<F>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        stage: MethodSelectionStage,
        mut dependency_phase: F,
    ) -> Result<()>
    where
        F: FnMut(&mut wgpu::CommandEncoder, bool) -> Result<()>,
    {
        if matches!(stage, MethodSelectionStage::Lookup) {
            return self.lookup.record_sweep(encoder, &mut dependency_phase);
        }
        let (direct, returns, reset, local, bound, finalize) = match stage {
            MethodSelectionStage::Direct => (
                METHODS_MARK_CALL_KEYS, METHODS_MARK_CALL_RETURN_KEYS_DIRECT,
                METHODS_RESET_CANDIDATES_DIRECT, METHODS_RESOLVE_TABLE_DIRECT,
                METHODS_OFFER_BOUND_MEMBERS_DIRECT, METHODS_FINALIZE_CANDIDATES_DIRECT,
            ),
            MethodSelectionStage::Inference | MethodSelectionStage::Lookup => (
                METHODS_MARK_CALL_KEYS_INFERENCE, METHODS_MARK_CALL_RETURN_KEYS_INFERENCE,
                METHODS_RESET_CANDIDATES_INFERENCE, METHODS_RESOLVE_TABLE_INFERENCE,
                METHODS_OFFER_BOUND_MEMBERS_INFERENCE, METHODS_FINALIZE_CANDIDATES_INFERENCE,
            ),
        };
        self.mark_call_keys.record_as(encoder, direct.name)?;
        self.mark_call_return_keys.record_as(encoder, returns.name)?;
        self.reset_candidates.record_as(encoder, reset.name)?;
        self.resolve_table.record_as(encoder, local.name)?;
        self.offer_bound_members.record_as(encoder, bound.name)?;
        dependency_phase(encoder, true)?;
        self.finalize_candidates.record_as(encoder, finalize.name)?;
        dependency_phase(encoder, false)
    }

    pub(in crate::type_checker) fn record_call_resolution<F>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        mut dependency_phase: F,
    ) -> Result<()>
    where
        F: FnMut(&mut wgpu::CommandEncoder, bool) -> Result<()>,
    {
        // Each sweep can resolve one more link of a call-result receiver
        // chain. The gate stops the sweeps on the GPU after one that changes
        // no target, since every later sweep would repeat it.
        self.lookup.arm.record(encoder)?;
        for _ in 0..METHOD_CALL_RESULT_RECEIVER_PASSES {
            self.record_call_selection(
                encoder, MethodSelectionStage::Lookup, &mut dependency_phase,
            )?;
        }
        Ok(())
    }
}

impl MethodLookupSweeps {
    /// One lookup sweep: the selection transaction, then its gate.
    fn record_sweep<F>(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        dependency_phase: &mut F,
    ) -> Result<()>
    where
        F: FnMut(&mut wgpu::CommandEncoder, bool) -> Result<()>,
    {
        self.mark_call_keys.record(encoder)?;
        self.mark_call_return_keys.record(encoder)?;
        self.reset_candidates.record(encoder)?;
        self.resolve_table.record(encoder)?;
        self.offer_bound_members.record(encoder)?;
        dependency_phase(encoder, true)?;
        self.finalize_candidates.record(encoder)?;
        dependency_phase(encoder, false)?;
        self.gate.record(encoder)
    }
}
