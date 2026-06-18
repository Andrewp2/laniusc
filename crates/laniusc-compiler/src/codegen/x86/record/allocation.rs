use anyhow::Result;

use super::super::support::{pop_allocation_error_scope, push_allocation_error_scope};

/// Error-scope guard for grouped GPU buffer allocation in x86 recording.
pub(super) struct AllocationScope<'a> {
    device: &'a wgpu::Device,
    guard: Option<wgpu::ErrorScopeGuard>,
}

impl<'a> AllocationScope<'a> {
    /// Starts a new allocation error scope on the device.
    pub(super) fn new(device: &'a wgpu::Device) -> Self {
        Self {
            device,
            guard: Some(push_allocation_error_scope(device)),
        }
    }

    /// Closes the current allocation scope and opens the next stage's scope.
    pub(super) fn checkpoint(&mut self, stage: &str) -> Result<()> {
        let guard = self
            .guard
            .take()
            .expect("allocation scope checkpoint after finish");
        pop_allocation_error_scope(guard, stage)?;
        self.guard = Some(push_allocation_error_scope(self.device));
        Ok(())
    }

    /// Closes the final allocation scope.
    pub(super) fn finish(mut self, stage: &str) -> Result<()> {
        let guard = self
            .guard
            .take()
            .expect("allocation scope finish after finish");
        pop_allocation_error_scope(guard, stage)
    }
}
