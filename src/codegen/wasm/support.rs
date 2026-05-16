use std::{
    hash::{Hash, Hasher},
    sync::mpsc,
    time::{Duration, Instant},
};

use anyhow::Result;
use log::warn;

use super::WasmParams;

pub(super) fn trace_wasm_codegen(stage: &str) {
    if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
        eprintln!("[laniusc][wasm-codegen] {stage}");
    }
}

pub(super) fn wasm_params_bytes(params: &WasmParams) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params)
        .expect("failed to encode WASM codegen params");
    ub.as_ref().to_vec()
}

pub(super) fn fast_path_status_init_bytes() -> [u8; 16] {
    let mut bytes = [0u8; 16];
    bytes[4..8].copy_from_slice(&2u32.to_le_bytes());
    bytes[12..16].copy_from_slice(&u32::MAX.to_le_bytes());
    bytes
}

pub(super) fn read_wasm_output(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    out_buf: &wgpu::Buffer,
    packed_out_buf: &wgpu::Buffer,
    status_readback: &wgpu::Buffer,
    out_readback: &wgpu::Buffer,
    output_capacity: usize,
    token_capacity: u32,
) -> Result<Vec<u8>> {
    let status_slice = status_readback.slice(..);
    wait_for_map(device, &status_slice, "codegen.wasm.status")?;

    let (len, source_buf) = {
        let data = status_readback.slice(..).get_mapped_range();
        let status_words = crate::gpu::readback::read_u32_words(&data, "WASM codegen status");
        drop(data);
        status_readback.unmap();
        let [len, mode, error_code, error_detail] = status_words?;
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
            eprintln!(
                "[laniusc][wasm-codegen] readback.status len={len} mode={mode} error={error_code} detail={error_detail}"
            );
        }
        let len = len as usize;
        let ok = matches!(mode, 1 | 2 | 3 | 5);
        if error_code != 0 {
            let error_name = match error_code {
                2 => "unsupported for loop",
                _ => "unsupported source shape",
            };
            return Err(anyhow::anyhow!(
                "GPU WASM emitter rejected {error_name} (code {error_code}) at token {error_detail}"
            ));
        }
        if !ok || len > output_capacity {
            return Err(anyhow::anyhow!(
                "GPU WASM emitter produced {} bytes for capacity {} with {} tokens",
                len,
                output_capacity,
                token_capacity
            ));
        }
        let source_buf = if mode == 1 || mode == 5 {
            packed_out_buf
        } else {
            out_buf
        };
        (len, source_buf)
    };

    let output_bytes = (len.div_ceil(4) * 4) as u64;
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("codegen.wasm.exact_output_readback.encoder"),
    });
    encoder.copy_buffer_to_buffer(source_buf, 0, out_readback, 0, output_bytes);
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "codegen.wasm.output-readback",
        encoder.finish(),
    );

    let output_slice = out_readback.slice(0..output_bytes);
    wait_for_map(device, &output_slice, "codegen.wasm.output")?;

    let bytes = {
        let data = out_readback.slice(0..output_bytes).get_mapped_range();
        let mut bytes = Vec::with_capacity(len);
        for &byte in data.iter().take(len) {
            bytes.push(byte);
        }
        drop(data);
        out_readback.unmap();
        bytes
    };
    Ok(bytes)
}

fn wait_for_map(device: &wgpu::Device, slice: &wgpu::BufferSlice<'_>, label: &str) -> Result<()> {
    let label = label.to_string();
    let cb_label = label.clone();
    let (tx, rx) = mpsc::channel();
    crate::gpu::passes_core::trace_gpu_progress(&format!("map.start :: {label}"));
    slice.map_async(wgpu::MapMode::Read, move |result| {
        if let Err(err) = tx.send(result) {
            warn!("failed to dispatch readback status for {cb_label}: {err}");
        }
    });
    crate::gpu::passes_core::trace_gpu_progress(&format!("map.queued :: {label}"));

    let timeout = wasm_readback_timeout();
    let start = Instant::now();
    let mut spins = 0u32;
    loop {
        crate::gpu::passes_core::wait_for_map_progress(
            device,
            &format!("codegen.wasm.output-poll({label})"),
            wgpu::PollType::Poll,
        );
        match rx.try_recv() {
            Ok(Ok(())) => return Ok(()),
            Ok(Err(err)) => {
                return Err(anyhow::anyhow!("{label} readback map failed: {err}"));
            }
            Err(mpsc::TryRecvError::Empty) => {}
            Err(mpsc::TryRecvError::Disconnected) => {
                return Err(anyhow::anyhow!("{label} readback callback disconnected"));
            }
        }
        if start.elapsed() >= timeout {
            return Err(anyhow::anyhow!(
                "{label} readback did not complete within {} ms",
                timeout.as_millis()
            ));
        }
        if spins < 64 {
            std::hint::spin_loop();
            spins += 1;
        } else {
            std::thread::yield_now();
        }
    }
}

fn wasm_readback_timeout() -> Duration {
    let ms = crate::gpu::env::env_u64("LANIUS_WASM_READBACK_TIMEOUT_MS", 3_000);
    Duration::from_millis(ms)
}

pub(super) fn estimate_wasm_output_capacity(source_len: usize, token_capacity: u32) -> usize {
    source_len
        .saturating_mul(16)
        .max((token_capacity as usize).saturating_mul(32))
        .saturating_add(4096)
        .max(4096)
}

pub(super) fn workgroup_grid_1d(groups: u32) -> (u32, u32) {
    const MAX_X: u32 = 65_535;
    let groups = groups.max(1);
    if groups <= MAX_X {
        (groups, 1)
    } else {
        (MAX_X, groups.div_ceil(MAX_X))
    }
}

pub(super) fn buffer_fingerprint(buffers: &[&wgpu::Buffer]) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    for buffer in buffers {
        buffer.hash(&mut hasher);
    }
    hasher.finish()
}

pub(super) fn storage_u32_rw(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra_usage: wgpu::BufferUsages,
) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | extra_usage,
        mapped_at_creation: false,
    })
}

pub(super) fn readback_u32s(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}
