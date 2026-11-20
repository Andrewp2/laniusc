//! A reflected step program with an encoder-ordered sync reset.

use anyhow::{Result, ensure};
use encase::ShaderType;

use super::{ComputeGraph, ComputeOperation};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    passes_core::PassData,
    resource_registry::ResourceMap,
};

// Match the launch size and slot layout in step_program.slang.
const GROUP_LANES: u32 = 256;
pub(crate) const STEP_PROGRAM_MAX_GROUPS: u32 = 164;
pub(crate) const STEP_PROGRAM_SYNC_WORDS: usize = 4;
const SLOT_BYTES: u64 = (STEP_PROGRAM_SYNC_WORDS * size_of::<u32>()) as u64;
const FAILED_OFFSET: u64 = size_of::<u32>() as u64;

#[derive(ShaderType)]
struct Launch {
    groups: u32,
    slot: u32,
    options: u32,
    reserved: u32,
}

/// A job whose largest table has at most this many rows runs its programs
/// with one workgroup: a step then costs under 2 us, and one group needs no
/// wait for other groups.
const SINGLE_GROUP_ROWS: u64 = 4096;

/// The group counts a stage builds each program for: `[small jobs, large
/// jobs]`. `step_program_group_variant` picks between them for a job.
///
/// 164 groups took less time than 64 and 328 across both settings lowerings
/// on the RTX 3090 (`codegen/lir/optimization.rs`). Other adapters use 64:
/// a dispatch with more groups than the device runs at once fails its wait.
pub(crate) fn step_program_group_counts() -> [u32; 2] {
    let large = if crate::gpu::device::is_rtx_3090_vulkan() {
        STEP_PROGRAM_MAX_GROUPS
    } else {
        64
    };
    [1, large]
}

/// Index into `step_program_group_counts` for a job whose largest table has
/// `rows` rows.
pub(crate) fn step_program_group_variant(rows: u64) -> usize {
    usize::from(rows > SINGLE_GROUP_ROWS)
}

pub(crate) struct StepProgramOperation {
    operation: ComputeOperation,
    sync: LaniusBuffer<u32>,
    offset: u64,
    _launch: LaniusBuffer<Launch>,
}

impl StepProgramOperation {
    /// A variant owns the binding for its dispatch dimensions and program
    /// options. Both the shader and the dispatch use the same group count.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        device: &wgpu::Device,
        graph: &impl ComputeGraph,
        resources: &ResourceMap<'_>,
        name: &'static str,
        pass: &PassData,
        sync: &LaniusBuffer<u32>,
        slot: u32,
        groups: u32,
        options: u32,
    ) -> Result<Self> {
        ensure!(
            (1..=STEP_PROGRAM_MAX_GROUPS).contains(&groups),
            "invalid step program group count {groups}",
        );
        ensure!(
            pass.thread_group_size == [GROUP_LANES, 1, 1],
            "{name} must use {GROUP_LANES} lanes",
        );
        let offset = u64::from(slot) * SLOT_BYTES;
        ensure!(
            offset + SLOT_BYTES <= sync.byte_size as u64,
            "{name} has no sync slot {slot}",
        );
        let binding = resources.tracked_view("step_program_sync")?;
        ensure!(
            *binding.buffer == sync.buffer
                && binding.byte_offset == sync.byte_offset
                && binding.byte_size == sync.byte_size as u64,
            "{name} must clear the buffer bound as step_program_sync",
        );
        let launch = uniform_from_val(
            device,
            name,
            &Launch {
                groups,
                slot,
                options,
                reserved: 0,
            },
        );
        let operation = ComputeOperation::direct_with_named_uniform(
            device,
            graph,
            resources,
            name,
            pass,
            "program_launch",
            &launch,
            groups * GROUP_LANES,
        )?;
        Ok(Self {
            operation,
            sync: sync.clone(),
            offset,
            _launch: launch,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        crate::gpu::passes_core::flush_deferred_compute(encoder);
        self.sync.clear(encoder, self.offset, Some(SLOT_BYTES));
        self.operation.record(encoder)
    }

    pub(crate) fn failed_offset(slot: u32) -> u64 {
        u64::from(slot) * SLOT_BYTES + FAILED_OFFSET
    }
}
