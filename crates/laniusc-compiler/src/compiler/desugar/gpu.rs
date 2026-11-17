//! The buffers, bind groups and dispatches of the desugaring. The rounds
//! record inside the lexer's submission, so every buffer has one label and
//! keeps its storage from one build to the next.

use std::{
    collections::{HashMap, hash_map::Entry},
    sync::{Arc, LazyLock, Mutex, MutexGuard, PoisonError},
};

use anyhow::{Context, Result};

use crate::gpu::{
    buffers::{CapacityBufferCache, LaniusBuffer, live_tracked_allocation_ids, tracked_buffer_identity},
    passes_core::{self, DispatchDim, InputElements, PassData, make_pass_data_from_shader_key},
};

/// What a buffer the kernels read and write is used for.
const STORAGE: wgpu::BufferUsages =
    wgpu::BufferUsages::STORAGE.union(wgpu::BufferUsages::COPY_SRC).union(wgpu::BufferUsages::COPY_DST);

/// The bytes of one capacity step of a resident buffer: 4096 rows of four
/// words.
const BUCKET_BYTES: usize = 4 * 1024 * 16;

pub(in crate::compiler) type Binding<'a> = (&'static str, wgpu::BindingResource<'a>);

pub(in crate::compiler) struct Gpu<'a> {
    pub(in crate::compiler) device: &'a wgpu::Device,
    pub(in crate::compiler) queue: &'a wgpu::Queue,
}

/// The buffers and bind groups the desugaring keeps between builds.
#[derive(Default)]
struct Resident {
    buffers: CapacityBufferCache,
    state: Mutex<ResidentState>,
}

#[derive(Default)]
struct ResidentState {
    /// The bytes each label holds.
    capacity: HashMap<String, usize>,
    /// Bind groups by kernel and by the name, allocation, offset and size of
    /// each binding.
    groups: HashMap<(String, Vec<(&'static str, [u64; 3])>), Arc<wgpu::BindGroup>>,
}

static RESIDENT: LazyLock<Resident> = LazyLock::new(Resident::default);

impl Resident {
    fn state(&self) -> MutexGuard<'_, ResidentState> {
        self.state.lock().unwrap_or_else(PoisonError::into_inner)
    }
}

impl ResidentState {
    /// The bytes the buffer of `label` holds once it covers `bytes`. A
    /// buffer that grows gets 1/64 more than it needs, rounded up to
    /// `BUCKET_BYTES`, so the next text of nearly the same size fits.
    fn take(&mut self, label: &str, bytes: usize) -> usize {
        let bytes = bytes.max(4).next_multiple_of(4);
        let held = self.capacity.entry(label.to_owned()).or_default();
        if *held < bytes {
            *held = (bytes + bytes / 64).next_multiple_of(BUCKET_BYTES);
        }
        *held
    }
}

/// Frees the buffers of the desugaring, for a resident compiler that trims
/// its idle storage. The next build allocates them again.
pub(crate) fn release_resident_buffers() {
    *RESIDENT.state() = ResidentState::default();
    RESIDENT.buffers.clear();
}

/// The allocation, offset and size a binding names, when it is a buffer the
/// compiler tracks.
fn binding_identity(resource: &wgpu::BindingResource<'_>) -> Option<[u64; 3]> {
    let wgpu::BindingResource::Buffer(binding) = resource else {
        return None;
    };
    let (allocation, _, _) = tracked_buffer_identity(binding.buffer)?;
    Some([allocation, binding.offset, binding.size.map_or(0, std::num::NonZeroU64::get)])
}

/// Drops the bind groups whose buffer the lexer, the parser or this pool has
/// replaced: a bind group keeps its buffers alive.
pub(in crate::compiler) fn drop_stale_bind_groups() {
    let live = live_tracked_allocation_ids();
    RESIDENT.state().groups.retain(|(_, bindings), _| bindings.iter().all(|(_, binding)| live.contains(&binding[0])));
}

impl Gpu<'_> {
    pub(in crate::compiler) fn kernel(&self, key: &'static str) -> Result<PassData> {
        make_pass_data_from_shader_key(self.device, key, "main", key)
    }

    pub(in crate::compiler) fn encoder(&self, label: &str) -> wgpu::CommandEncoder {
        self.device.create_command_encoder(&wgpu::CommandEncoderDescriptor { label: Some(label) })
    }

    /// A resident storage buffer of at least `bytes` bytes that no dispatch
    /// clears, keyed by `label`.
    pub(in crate::compiler) fn fixed_storage(
        &self,
        label: &str,
        bytes: usize,
        usage: wgpu::BufferUsages,
    ) -> LaniusBuffer<u8> {
        let capacity = RESIDENT.state().take(label, bytes);
        RESIDENT.buffers.binding_capacity(self.device, label, capacity, usage | STORAGE)
    }

    /// A storage buffer keyed by `label` that starts with `words`.
    pub(in crate::compiler) fn fixed_words_from(&self, label: &str, words: &[u32]) -> LaniusBuffer<u8> {
        let bytes: Vec<u8> = words.iter().flat_map(|word| word.to_le_bytes()).collect();
        let buffer = self.fixed_storage(label, bytes.len(), wgpu::BufferUsages::empty());
        buffer.write(self.queue, 0, &bytes);
        buffer
    }

    /// The parameters of one dispatch, keyed by `label`.
    pub(in crate::compiler) fn fixed_uniform<T>(&self, label: &str, value: &T) -> LaniusBuffer<T>
    where
        T: encase::ShaderType + encase::internal::WriteInto,
    {
        RESIDENT.buffers.uniform(self.device, self.queue, label, value)
    }

    /// Records one dispatch whose workgroup counts are the three words at
    /// `args[3 * triple..]`.
    pub(in crate::compiler) fn dispatch_indirect(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pass: &PassData,
        label: &str,
        bindings: &[Binding<'_>],
        args: &LaniusBuffer<u8>,
        triple: u32,
    ) -> Result<()> {
        self.record(encoder, pass, label, bindings, |compute| {
            compute.dispatch_workgroups_indirect(&args.buffer, args.byte_offset + u64::from(triple) * 12);
        })
    }

    /// Records one dispatch of one lane per element.
    pub(in crate::compiler) fn fixed_dispatch(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pass: &PassData,
        label: &str,
        bindings: &[Binding<'_>],
        elements: u32,
    ) -> Result<()> {
        let (x, y, z) =
            passes_core::plan_workgroups(DispatchDim::D1, InputElements::Elements1D(elements), pass.thread_group_size)?;
        self.record(encoder, pass, label, bindings, |compute| compute.dispatch_workgroups(x, y, z))
    }

    fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        pass: &PassData,
        label: &str,
        bindings: &[Binding<'_>],
        dispatch: impl FnOnce(&mut wgpu::ComputePass<'_>),
    ) -> Result<()> {
        passes_core::bind_group::validate_exact_binding_names(pass, 0, bindings)
            .with_context(|| format!("bind {label}"))?;
        let create = || {
            passes_core::bind_group::create_bind_group_from_bindings(self.device, Some(label), pass, 0, bindings)
                .map(Arc::new)
        };
        let group = {
            let mut state = RESIDENT.state();
            let identity: Option<Vec<_>> =
                bindings.iter().map(|(name, resource)| Some((*name, binding_identity(resource)?))).collect();
            match identity {
                None => create()?,
                Some(identity) => match state.groups.entry((pass.shader_id.clone(), identity)) {
                    Entry::Occupied(group) => group.get().clone(),
                    Entry::Vacant(slot) => slot.insert(create()?).clone(),
                },
            }
        };
        let mut compute = passes_core::begin_counted_compute_pass(
            encoder,
            &wgpu::ComputePassDescriptor { label: Some(label), timestamp_writes: None },
        );
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(group.as_ref()), &[]);
        passes_core::record_compute_dispatch();
        if !passes_core::debug_operation_skipped() {
            dispatch(&mut compute);
        }
        drop(compute);
        // A profiled job needs one timestamp per dispatch.
        crate::gpu::timer::stamp_active_operation(encoder, label.to_owned());
        Ok(())
    }
}
