//! Direct lowering operations whose dispatch follows the job, not the workspace.
//!
//! A direct operation's workgroup count is fixed when its pipeline and bind
//! group are built, from the workspace's capacities. A daemon keeps the
//! workspace of its largest job, so every later job would launch that job's
//! grid and let nearly every thread exit at its bounds check. `JobSized`
//! keeps the element count as a function of the capacities, checks at build
//! time that the function gives the count the operation was built with, and
//! records each job with the count for its own capacities
//! (`LoweringCapacities::for_job`): the grid a fresh workspace for the job
//! would launch. Kernels keep the workspace's capacities in their uniforms,
//! and every reader is bounded by a job-written count or by the job's ids, so
//! rows past the job's grid are never read.

use std::{collections::HashSet, sync::OnceLock};

use anyhow::{Result, ensure};

use super::lowering_ir::LoweringCapacities;
use crate::gpu::operations::ComputeOperation;

/// A direct compute operation and the element count it dispatches for given
/// capacities.
pub(crate) struct JobSized {
    operation: ComputeOperation,
    elements: fn(LoweringCapacities) -> u32,
    built: u32,
}

impl JobSized {
    /// Wraps `operation`, which must be a direct operation built to dispatch
    /// `elements(built)` elements.
    pub(crate) fn new(
        operation: ComputeOperation,
        elements: fn(LoweringCapacities) -> u32,
        built: LoweringCapacities,
    ) -> Result<Self> {
        let expected = elements(built);
        let actual = operation.direct_elements();
        ensure!(
            actual == Some(expected),
            "job-sized operation `{}` was built for {actual:?} elements, but its capacity function gives {expected}",
            operation.name(),
        );
        if std::env::var_os("LANIUS_JOB_SIZED_LIST").is_some() {
            eprintln!("[job_sized] {}", operation.name());
        }
        Ok(Self {
            operation,
            elements,
            built: expected,
        })
    }

    /// Records the operation for `job`'s capacities, never past the grid it
    /// was built with; `None` records the built grid.
    pub(crate) fn record_job(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        job: Option<LoweringCapacities>,
    ) -> Result<()> {
        match job.filter(|_| job_sized_allows(self.operation.name())) {
            Some(job) => self
                .operation
                .record_elements(encoder, (self.elements)(job).min(self.built)),
            None => self.operation.record(encoder),
        }
    }
}

/// Whether `name` may record a job-sized grid. `LANIUS_JOB_SIZED_ONLY` set
/// to a comma-separated list of operation names (as `LANIUS_JOB_SIZED_LIST`
/// prints them, plus `schedule.sort`) sizes only those operations, to find
/// one whose grid must not follow the job. Unset, every operation may.
pub(crate) fn job_sized_allows(name: &str) -> bool {
    static ONLY: OnceLock<Option<HashSet<String>>> = OnceLock::new();
    ONLY.get_or_init(|| {
        std::env::var("LANIUS_JOB_SIZED_ONLY").ok().map(|names| {
            names
                .split(',')
                .map(str::trim)
                .filter(|name| !name.is_empty())
                .map(str::to_owned)
                .collect()
        })
    })
    .as_ref()
    .is_none_or(|names| names.contains(name))
}
