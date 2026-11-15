//! Test capture of a lowering job's input columns.
//!
//! A test arms the capture, compiles a program and then reads the first
//! `words` words of every lowering input buffer of each lowering job the
//! compiler recorded while armed, by graph resource name
//! (`lowering::named_lowering_inputs`). The capture is a copy recorded in
//! the job's own command stream before its lowering, so it holds exactly
//! what lowering read. Nothing in the compiler reads it back.

use std::{collections::BTreeMap, sync::Mutex};

use crate::gpu::passes_core::map_readback_blocking;

struct Pending {
    buffers: Vec<(&'static str, wgpu::Buffer, u64)>,
}

struct State {
    words: u64,
    pending: Vec<Pending>,
}

static STATE: Mutex<Option<State>> = Mutex::new(None);

/// Captures the first `words` words of every input of each later lowering
/// job, until `take`.
#[doc(hidden)]
pub fn arm(words: u64) {
    *STATE.lock().unwrap() = Some(State {
        words,
        pending: Vec::new(),
    });
}

/// Disarms the capture and returns one map per lowering job, in recording
/// order. Reading waits for the device.
#[doc(hidden)]
pub fn take() -> Vec<BTreeMap<String, Vec<u32>>> {
    let state = STATE.lock().unwrap().take();
    let Some(state) = state else {
        return Vec::new();
    };
    let device = &crate::gpu::device::global().device;
    state
        .pending
        .into_iter()
        .map(|job| {
            job.buffers
                .into_iter()
                .map(|(name, buffer, bytes)| {
                    let slice = buffer.slice(..bytes);
                    map_readback_blocking(device, &slice, "lowering capture")
                        .expect("map lowering capture");
                    let words = slice
                        .get_mapped_range()
                        .chunks_exact(4)
                        .map(|w| u32::from_le_bytes(w.try_into().unwrap()))
                        .collect();
                    buffer.unmap();
                    (name.to_string(), words)
                })
                .collect()
        })
        .collect()
}

pub(crate) fn armed() -> bool {
    STATE.lock().unwrap().is_some()
}

/// Records copies of `inputs` into `encoder` when the capture is armed.
pub(crate) fn record(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    inputs: Vec<(&'static str, wgpu::Buffer, u64, u64)>,
) {
    let mut guard = STATE.lock().unwrap();
    let Some(state) = guard.as_mut() else {
        return;
    };
    let mut buffers = Vec::new();
    for (name, buffer, offset, size) in inputs {
        let bytes = (state.words * 4).min(size) & !3;
        if bytes == 0 {
            continue;
        }
        let copy = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("lowering.capture"),
            size: bytes,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(&buffer, offset, &copy, 0, bytes);
        buffers.push((name, copy, bytes));
    }
    state.pending.push(Pending { buffers });
}

/// The captured columns as one map, for tests that compare by name.
#[doc(hidden)]
pub type Capture = BTreeMap<String, Vec<u32>>;
