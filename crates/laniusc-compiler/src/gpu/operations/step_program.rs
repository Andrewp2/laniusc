//! A reflected step program with an encoder-ordered sync reset.

use anyhow::{Result, ensure};
use encase::ShaderType;

use super::{ComputeGraph, ComputeOperation};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    passes_core::{self, PassData},
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

enum ProgramDispatch {
    Graph(ComputeOperation),
    Reflected {
        pass: PassData,
        bind: wgpu::BindGroup,
        groups: u32,
    },
}

pub(crate) struct StepProgramOperation {
    dispatch: ProgramDispatch,
    sync: LaniusBuffer<u32>,
    offset: u64,
    _launch: Option<LaniusBuffer<Launch>>,
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
        let offset = Self::validate_launch(name, pass, sync, slot, groups)?;
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
            dispatch: ProgramDispatch::Graph(operation),
            sync: sync.clone(),
            offset,
            _launch: Some(launch),
        })
    }

    /// The shader reads its group count from the same grid used by the dispatch.
    pub(crate) fn new_indirect(
        device: &wgpu::Device,
        graph: &impl ComputeGraph,
        resources: &ResourceMap<'_>,
        name: &'static str,
        pass: &PassData,
        sync: &LaniusBuffer<u32>,
        slot: u32,
        args: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        let offset = Self::validate_launch(name, pass, sync, slot, 1)?;
        let launch = uniform_from_val(
            device,
            name,
            &Launch { groups: 0, slot, options: 0, reserved: 0 },
        );
        let operation = ComputeOperation::indirect_with_uniform(
            device, graph, resources, name, pass, args, "program_launch", &launch,
        )?;
        Ok(Self {
            dispatch: ProgramDispatch::Graph(operation),
            sync: sync.clone(),
            offset,
            _launch: Some(launch),
        })
    }

    /// Binds a program over stage-owned storage with no graph slot reuse.
    /// The sync and launch bindings are owned by the operation.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new_reflected(
        device: &wgpu::Device,
        name: &'static str,
        pass: &PassData,
        resources: &[(&str, wgpu::BindingResource<'_>)],
        sync: &LaniusBuffer<u32>,
        slot: u32,
        groups: u32,
        options: u32,
    ) -> Result<Self> {
        let launch = uniform_from_val(
            device,
            name,
            &Launch { groups, slot, options, reserved: 0 },
        );
        let mut operation = Self::new_reflected_with_launch(
            device, name, pass, resources, sync, slot, groups, launch.as_entire_binding(),
        )?;
        operation._launch = Some(launch);
        Ok(operation)
    }

    /// Uses a persistent stage-owned uniform for a reflected launch.
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new_reflected_with_launch(
        device: &wgpu::Device,
        name: &'static str,
        pass: &PassData,
        resources: &[(&str, wgpu::BindingResource<'_>)],
        sync: &LaniusBuffer<u32>,
        slot: u32,
        groups: u32,
        launch: wgpu::BindingResource<'_>,
    ) -> Result<Self> {
        let offset = Self::validate_launch(name, pass, sync, slot, groups)?;
        let mut entries = resources.to_vec();
        entries.push(("step_program_sync", sync.as_entire_binding()));
        entries.push(("program_launch", launch));
        let bind = passes_core::bind_group::create_bind_group_from_bindings(
            device, Some(name), pass, 0, &entries,
        )?;
        Ok(Self {
            dispatch: ProgramDispatch::Reflected { pass: pass.clone(), bind, groups },
            sync: sync.clone(),
            offset,
            _launch: None,
        })
    }

    fn validate_launch(
        name: &str,
        pass: &PassData,
        sync: &LaniusBuffer<u32>,
        slot: u32,
        groups: u32,
    ) -> Result<u64> {
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
        Ok(offset)
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        crate::gpu::passes_core::flush_deferred_compute(encoder);
        self.sync.clear(encoder, self.offset, Some(SLOT_BYTES));
        match &self.dispatch {
            ProgramDispatch::Graph(operation) => operation.record(encoder),
            ProgramDispatch::Reflected { pass, bind, groups } => {
                super::record_direct(encoder, pass, bind, &pass.shader_id, groups * GROUP_LANES)
            }
        }
    }

    pub(crate) fn failed_offset(slot: u32) -> u64 {
        u64::from(slot) * SLOT_BYTES + FAILED_OFFSET
    }
}
