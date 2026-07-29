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

    pub(in crate::type_checker) fn record_call_resolution(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.mark_call_keys.record(encoder)?;
        for _ in 0..METHOD_CALL_RESULT_RECEIVER_PASSES {
            self.mark_call_return_keys.record(encoder)?;
            self.resolve_table.record(encoder)?;
        }
        Ok(())
    }
}
