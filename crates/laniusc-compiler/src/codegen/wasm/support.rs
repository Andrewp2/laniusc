use std::{
    hash::{Hash, Hasher},
    time::Duration,
};

use anyhow::Result;

use super::{WasmOutputError, WasmParams, WasmScanParams};
use crate::gpu::buffers::LaniusBuffer;

/// Emits a WASM backend trace line when `LANIUS_WASM_TRACE` is enabled.
pub(super) fn trace_wasm_codegen(stage: &str) {
    if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
        eprintln!("[laniusc][wasm-codegen] {stage}");
    }
}

/// Encodes the main WASM parameter uniform using shader layout rules.
pub(super) fn wasm_params_bytes(params: &WasmParams) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params)
        .expect("failed to encode WASM codegen params");
    ub.as_ref().to_vec()
}

/// Encodes a WASM scan parameter uniform using shader layout rules.
pub(super) fn wasm_scan_params_bytes(params: &WasmScanParams) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params).expect("failed to encode WASM scan params");
    ub.as_ref().to_vec()
}

/// Returns the initial four-word body status buffer contents.
pub(super) fn body_status_init_bytes() -> [u8; 16] {
    let mut bytes = [0u8; 16];
    bytes[12..16].copy_from_slice(&u32::MAX.to_le_bytes());
    bytes
}

/// Returns initial body-plan aggregate/final words.
pub(super) fn body_plan_init_bytes() -> Vec<u8> {
    const INVALID: u32 = u32::MAX;
    let mut words = [0u32; 24];
    words[1] = INVALID;
    words[2] = INVALID;
    words[7] = INVALID;
    words[9] = INVALID;
    words[13] = INVALID;
    words[23] = INVALID;

    let mut bytes = Vec::with_capacity(words.len() * 4);
    for word in words {
        bytes.extend_from_slice(&word.to_le_bytes());
    }
    bytes
}

/// Returns body status bytes initialized to reject unsupported shapes.
pub(super) fn unsupported_shape_status_init_bytes() -> [u8; 16] {
    let mut bytes = body_status_init_bytes();
    bytes[8..12].copy_from_slice(&1u32.to_le_bytes());
    bytes
}

/// Encodes one WebGPU indirect-dispatch argument tuple.
pub(super) fn dispatch_args_bytes(x: u32, y: u32, z: u32) -> [u8; 12] {
    let mut bytes = [0u8; 12];
    bytes[0..4].copy_from_slice(&x.to_le_bytes());
    bytes[4..8].copy_from_slice(&y.to_le_bytes());
    bytes[8..12].copy_from_slice(&z.to_le_bytes());
    bytes
}

/// Reads WASM backend status and exact output bytes from readback buffers.
pub(super) fn read_wasm_output(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    out_buf: &wgpu::Buffer,
    packed_out_buf: &wgpu::Buffer,
    status_readback: &wgpu::Buffer,
    body_plan_readback: &wgpu::Buffer,
    out_readback: &wgpu::Buffer,
    output_capacity: usize,
    token_capacity: u32,
) -> Result<Vec<u8>> {
    let status_slice = status_readback.slice(..);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &status_slice,
        "codegen.wasm.status",
        wasm_readback_timeout(),
    )?;

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
            trace_body_plan_readback(device, body_plan_readback)?;
        }
        let len = len as usize;
        let ok = matches!(mode, 1 | 2 | 3 | 5);
        if error_code != 0 {
            let error_name = match error_code {
                2 => "unsupported for loop",
                3 => "unsupported WASM body HIR-node budget",
                830 => "unsupported array-helper body token budget",
                831 => "unsupported array-helper body HIR-node budget",
                800..=899 => "unsupported array-helper body shape",
                902 => "retired enum-match module token budget",
                903 => "retired enum-match module HIR-node budget",
                900..=999 => "unsupported retired enum-match module shape",
                _ => "unsupported source shape",
            };
            return Err(WasmOutputError::new(error_name, error_code, error_detail).into());
        }
        if !ok || len > output_capacity {
            return Err(anyhow::anyhow!(
                "WASM emitter produced {} bytes for capacity {} with {} tokens",
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
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &output_slice,
        "codegen.wasm.output",
        wasm_readback_timeout(),
    )?;

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

fn trace_body_plan_readback(
    device: &wgpu::Device,
    body_plan_readback: &wgpu::Buffer,
) -> Result<()> {
    let slice = body_plan_readback.slice(..);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &slice,
        "codegen.wasm.body_plan",
        wasm_readback_timeout(),
    )?;

    let data = body_plan_readback.slice(..).get_mapped_range();
    let words: [u32; 24] = crate::gpu::readback::read_u32_words(&data, "WASM body plan")?;
    drop(data);
    body_plan_readback.unmap();
    eprintln!("[laniusc][wasm-codegen] readback.body_plan words={words:?}");
    Ok(())
}

fn wasm_readback_timeout() -> Duration {
    let ms = crate::gpu::env::env_u64("LANIUS_WASM_READBACK_TIMEOUT_MS", 3_000);
    Duration::from_millis(ms)
}

/// Estimates a conservative WASM output buffer capacity for one source.
pub(super) fn estimate_wasm_output_capacity(source_len: usize, token_capacity: u32) -> usize {
    source_len
        .saturating_mul(16)
        .max((token_capacity as usize).saturating_mul(32))
        .saturating_add(4096)
        .max(4096)
}

/// Splits a one-dimensional workgroup count across x/y WebGPU dispatch limits.
pub(super) fn workgroup_grid_1d(groups: u32) -> (u32, u32) {
    const MAX_X: u32 = 65_535;
    let groups = groups.max(1);
    if groups <= MAX_X {
        (groups, 1)
    } else {
        (MAX_X, groups.div_ceil(MAX_X))
    }
}

/// Returns scan-step values for a WASM block-prefix scan.
pub(super) fn scan_steps_for_blocks(n_blocks: usize) -> Vec<u32> {
    crate::gpu::scan::scan_step_values(n_blocks as u32)
}

/// Hashes buffer identities that affect WASM resident bind-group reuse.
pub(super) fn buffer_fingerprint(buffers: &[&wgpu::Buffer]) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    for buffer in buffers {
        buffer.hash(&mut hasher);
    }
    hasher.finish()
}

/// Allocates writable WASM `u32` storage with at least one element.
pub(super) fn storage_u32_rw(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra_usage: wgpu::BufferUsages,
) -> LaniusBuffer<u32> {
    let count = count.max(1);
    let buffer = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | extra_usage,
        mapped_at_creation: false,
    });
    LaniusBuffer::new((buffer, (count * 4) as u64), count)
}

/// Allocates a host-readable readback buffer for `count` `u32` words.
pub(super) fn readback_u32s(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}
