use std::{
    hash::{Hash, Hasher},
    time::Duration,
};

use anyhow::Result;

use super::{WASM_BODY_PLAN_WORDS, WasmParams, WasmScanParams};
use crate::gpu::buffers::LaniusBuffer;

pub(super) struct WasmPrefixPlan {
    pub status: [u32; 4],
    pub body_plan: [u32; WASM_BODY_PLAN_WORDS],
}

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

pub(super) fn create_wasm_scan_param_buffers(
    device: &wgpu::Device,
    label_prefix: &str,
    step_count: usize,
) -> Vec<LaniusBuffer<WasmScanParams>> {
    (0..step_count)
        .map(|step_i| {
            let label = format!("{label_prefix}.{step_i}");
            LaniusBuffer::new_labeled(
                (
                    device.create_buffer(&wgpu::BufferDescriptor {
                        label: Some(&label),
                        size: 16,
                        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                        mapped_at_creation: false,
                    }),
                    16,
                ),
                1,
                label,
            )
        })
        .collect()
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
    let mut words = [0u32; WASM_BODY_PLAN_WORDS];
    words[1] = INVALID;
    words[2] = INVALID;
    words[7] = INVALID;
    words[9] = INVALID;
    words[13] = INVALID;
    words[23] = INVALID;
    words[34] = INVALID;

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

pub(super) fn read_wasm_prefix_plan(
    device: &wgpu::Device,
    status_readback: &wgpu::Buffer,
    body_plan_readback: &wgpu::Buffer,
) -> Result<WasmPrefixPlan> {
    let status_slice = status_readback.slice(..);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &status_slice,
        "codegen.wasm.prefix.status",
        wasm_readback_timeout(),
    )?;
    let status = {
        let data = status_readback.slice(..).get_mapped_range();
        let words = crate::gpu::readback::read_u32_words(&data, "WASM prefix status")?;
        drop(data);
        status_readback.unmap();
        words
    };

    let plan_slice = body_plan_readback.slice(..);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &plan_slice,
        "codegen.wasm.prefix.body_plan",
        wasm_readback_timeout(),
    )?;
    let body_plan = {
        let data = body_plan_readback.slice(..).get_mapped_range();
        let words: [u32; WASM_BODY_PLAN_WORDS] =
            crate::gpu::readback::read_u32_words(&data, "WASM prefix body plan")?;
        drop(data);
        body_plan_readback.unmap();
        words
    };

    if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
        eprintln!(
            "[laniusc][wasm-codegen] readback.prefix.status len={} mode={} error={} detail={}",
            status[0], status[1], status[2], status[3]
        );
        eprintln!("[laniusc][wasm-codegen] readback.prefix.body_plan={body_plan:?}");
    }

    Ok(WasmPrefixPlan { status, body_plan })
}

/// Reads WASM backend status and exact output bytes from readback buffers.
pub(super) fn read_wasm_output(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    body_buf: &wgpu::Buffer,
    out_buf: &wgpu::Buffer,
    packed_out_buf: &wgpu::Buffer,
    status_readback: &wgpu::Buffer,
    body_plan_readback: &wgpu::Buffer,
    body_fragment_len_readback: &wgpu::Buffer,
    wasm_func_invalid_count_readback: &wgpu::Buffer,
    wasm_func_detail_readback: &wgpu::Buffer,
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
        let [
            len,
            mode,
            error_code,
            error_detail,
            relocation_count,
            relocation_error_count,
            relocation_error_detail,
            relocation_error_code,
        ] = status_words?;
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
            eprintln!(
                "[laniusc][wasm-codegen] readback.status len={len} mode={mode} error={error_code} detail={error_detail}"
            );
            trace_body_plan_readback(device, body_plan_readback)?;
            trace_body_fragment_len_readback(device, body_fragment_len_readback, token_capacity)?;
            trace_func_invalid_readback(
                device,
                wasm_func_invalid_count_readback,
                wasm_func_detail_readback,
            )?;
        }
        let len = len as usize;
        let ok = matches!(mode, 1 | 2 | 3 | 5);
        if error_code != 0 {
            return Err(super::wasm_output_error_from_status(error_code, error_detail).into());
        }
        if relocation_error_code != 0 || relocation_error_count != 0 {
            if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
                trace_body_fragment_owner(
                    device,
                    body_fragment_len_readback,
                    relocation_error_detail,
                )?;
                trace_body_words_around(
                    device,
                    queue,
                    body_buf,
                    relocation_error_detail,
                    output_capacity,
                )?;
            }
            return Err(anyhow::anyhow!(
                "WASM call-relocation compaction failed: count={relocation_count} errors={relocation_error_count} code={relocation_error_code} detail={relocation_error_detail}"
            ));
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
    if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
        trace_wasm_output_bytes(&bytes);
    }
    Ok(bytes)
}

fn trace_body_fragment_owner(
    device: &wgpu::Device,
    body_fragment_len_readback: &wgpu::Buffer,
    body_offset: u32,
) -> Result<()> {
    let words = read_u32_vec_from_readback(
        device,
        body_fragment_len_readback,
        "codegen.wasm.body_fragment_len.owner",
    )?;
    let mut offset = 0u32;
    for (item, &len) in words.iter().enumerate() {
        if body_offset >= offset && body_offset < offset.saturating_add(len) {
            eprintln!(
                "[laniusc][wasm-codegen] readback.body_fragment_owner body_offset={body_offset} item={item} fragment_offset={offset} fragment_len={len} within={}",
                body_offset - offset
            );
            return Ok(());
        }
        offset = offset.saturating_add(len);
    }
    eprintln!(
        "[laniusc][wasm-codegen] readback.body_fragment_owner body_offset={body_offset} not_found total={offset}"
    );
    Ok(())
}

fn trace_body_words_around(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    body_buf: &wgpu::Buffer,
    detail: u32,
    capacity: usize,
) -> Result<()> {
    let center = detail as usize;
    let start = center.saturating_sub(8).min(capacity);
    let end = center.saturating_add(9).min(capacity);
    let count = end.saturating_sub(start);
    if count == 0 {
        return Ok(());
    }
    let readback = readback_u32s(device, "rb.codegen.wasm.body_words.error", count);
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("codegen.wasm.body_words.error.encoder"),
    });
    encoder.copy_buffer_to_buffer(
        body_buf,
        (start * 4) as u64,
        &readback,
        0,
        (count * 4) as u64,
    );
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "codegen.wasm.body_words.error",
        encoder.finish(),
    );
    let slice = readback.slice(..);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &slice,
        "codegen.wasm.body_words.error",
        wasm_readback_timeout(),
    )?;
    let data = slice.get_mapped_range();
    let words = data
        .chunks_exact(4)
        .map(|bytes| u32::from_le_bytes(bytes.try_into().expect("four-byte chunk")))
        .collect::<Vec<_>>();
    eprintln!("[laniusc][wasm-codegen] readback.body_words.error start={start} words={words:?}");
    drop(data);
    readback.unmap();
    Ok(())
}

fn trace_wasm_output_bytes(bytes: &[u8]) {
    let prefix_len = bytes.len().min(320);
    let prefix = bytes
        .iter()
        .take(prefix_len)
        .map(|byte| format!("{byte:02x}"))
        .collect::<Vec<_>>()
        .join(" ");
    eprintln!(
        "[laniusc][wasm-codegen] readback.output len={} prefix={prefix}",
        bytes.len()
    );

    let mut offset = 8usize;
    while offset < bytes.len() {
        let section_id = bytes[offset];
        offset += 1;
        let Some((payload_len, next_offset)) = read_u32_leb(bytes, offset) else {
            eprintln!(
                "[laniusc][wasm-codegen] readback.output.section id={section_id} malformed_leb_at={offset}"
            );
            break;
        };
        offset = next_offset;
        let payload_end = offset.saturating_add(payload_len as usize);
        eprintln!(
            "[laniusc][wasm-codegen] readback.output.section id={section_id} payload_len={payload_len} payload_start={offset} payload_end={payload_end}"
        );
        if section_id == 10 {
            let code_len = payload_end.saturating_sub(offset).min(160);
            let code = bytes[offset..offset + code_len]
                .iter()
                .map(|byte| format!("{byte:02x}"))
                .collect::<Vec<_>>()
                .join(" ");
            eprintln!("[laniusc][wasm-codegen] readback.output.code_prefix={code}");
        }
        if payload_end > bytes.len() {
            break;
        }
        offset = payload_end;
    }
}

fn read_u32_leb(bytes: &[u8], mut offset: usize) -> Option<(u32, usize)> {
    let mut value = 0u32;
    let mut shift = 0u32;
    for _ in 0..5 {
        let byte = *bytes.get(offset)?;
        offset += 1;
        value |= u32::from(byte & 0x7f) << shift;
        if byte & 0x80 == 0 {
            return Some((value, offset));
        }
        shift += 7;
    }
    None
}

fn read_u32_vec_from_readback(
    device: &wgpu::Device,
    readback: &wgpu::Buffer,
    label: &'static str,
) -> Result<Vec<u32>> {
    let slice = readback.slice(..);
    crate::gpu::passes_core::wait_for_readback_map(device, &slice, label, wasm_readback_timeout())?;

    let data = readback.slice(..).get_mapped_range();
    let words = data
        .chunks_exact(4)
        .map(|chunk| u32::from_le_bytes(chunk.try_into().expect("u32 chunk")))
        .collect::<Vec<_>>();
    drop(data);
    readback.unmap();
    Ok(words)
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
    let words: [u32; WASM_BODY_PLAN_WORDS] =
        crate::gpu::readback::read_u32_words(&data, "WASM body plan")?;
    drop(data);
    body_plan_readback.unmap();
    eprintln!("[laniusc][wasm-codegen] readback.body_plan words={words:?}");
    Ok(())
}

pub(super) fn trace_body_fragment_len_readback(
    device: &wgpu::Device,
    body_fragment_len_readback: &wgpu::Buffer,
    token_capacity: u32,
) -> Result<()> {
    let words = read_u32_vec_from_readback(
        device,
        body_fragment_len_readback,
        "codegen.wasm.body_fragment_len",
    )?;

    let nonzero = words
        .iter()
        .copied()
        .enumerate()
        .filter(|(_, len)| *len != 0)
        .map(|(slot, len)| format!("{slot}:{len}"))
        .collect::<Vec<_>>()
        .join(",");
    eprintln!(
        "[laniusc][wasm-codegen] readback.body_fragment_len items={} token_capacity={} nonzero=[{nonzero}]",
        words.len(),
        token_capacity
    );
    Ok(())
}

pub(super) fn trace_expr_root_total_readback(
    device: &wgpu::Device,
    readback: &wgpu::Buffer,
    root_identity_readback: &wgpu::Buffer,
    identity_space: &str,
) -> Result<()> {
    let words = read_u32_vec_from_readback(device, readback, "codegen.wasm.expr_root_total")?;
    let root_identity = read_u32_vec_from_readback(
        device,
        root_identity_readback,
        "codegen.wasm.expr_root_identity",
    )?;
    let nonzero = words
        .chunks_exact(2)
        .enumerate()
        .filter(|(root, pair)| {
            root_identity.get(*root).copied() == Some(*root as u32)
                && (pair[0] != 0 || pair[1] != 0)
        })
        .map(|(root, pair)| format!("{root}:{}:{}", pair[0], pair[1]))
        .collect::<Vec<_>>()
        .join(",");
    eprintln!(
        "[laniusc][wasm-codegen] readback.expr_root_total space={identity_space} roots={} nonzero=[{nonzero}]",
        words.len() / 2
    );
    Ok(())
}

pub(super) fn trace_expr_order_readback(
    device: &wgpu::Device,
    order_readback: &wgpu::Buffer,
    root_readback: &wgpu::Buffer,
    contribution_readback: &wgpu::Buffer,
    identity_space: &str,
) -> Result<()> {
    let order = read_u32_vec_from_readback(device, order_readback, "codegen.wasm.expr_order")?;
    let roots =
        read_u32_vec_from_readback(device, root_readback, "codegen.wasm.expr_root_identity")?;
    let contribution = read_u32_vec_from_readback(
        device,
        contribution_readback,
        "codegen.wasm.expr_contribution",
    )?;
    let rows = order
        .iter()
        .copied()
        .enumerate()
        .map(|(i, node)| {
            let root = roots.get(node as usize).copied().unwrap_or(u32::MAX);
            let base = i * 4;
            let c = contribution.get(base..base + 4).unwrap_or(&[]);
            if c.len() == 4 {
                format!("{i}:{node}:{root}:{},{},{},{}", c[0], c[1], c[2], c[3])
            } else {
                format!("{i}:{node}:{root}:missing")
            }
        })
        .collect::<Vec<_>>()
        .join(",");
    eprintln!("[laniusc][wasm-codegen] readback.expr_order space={identity_space} rows=[{rows}]");
    Ok(())
}

pub(super) fn trace_body_fragment_aux_readback(
    device: &wgpu::Device,
    body_fragment_aux_readback: &wgpu::Buffer,
    token_capacity: u32,
) -> Result<()> {
    let words = read_u32_vec_from_readback(
        device,
        body_fragment_aux_readback,
        "codegen.wasm.body_fragment_aux",
    )?;
    let records = words
        .chunks_exact(4)
        .enumerate()
        .filter(|(_, record)| {
            !record.iter().all(|word| *word == 0)
                && (record[0] != u32::MAX || record[1] != 0 || record[2] != 0 || record[3] != 0)
        })
        .map(|(slot, record)| {
            format!(
                "{slot}:[{},{},{},{}]",
                record[0], record[1], record[2], record[3]
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    eprintln!(
        "[laniusc][wasm-codegen] readback.body_fragment_aux items={} token_capacity={} records=[{records}]",
        words.len() / 4,
        token_capacity
    );
    Ok(())
}

pub(super) fn trace_body_fragment_meta_readback(
    device: &wgpu::Device,
    body_fragment_meta_readback: &wgpu::Buffer,
    token_capacity: u32,
) -> Result<()> {
    let words = read_u32_vec_from_readback(
        device,
        body_fragment_meta_readback,
        "codegen.wasm.body_fragment_meta",
    )?;
    let records = words
        .chunks_exact(4)
        .enumerate()
        .filter(|(_, record)| {
            record[0] != 0 || record[1] != 0 || record[2] != 0 || record[3] != u32::MAX
        })
        .map(|(slot, record)| {
            format!(
                "{slot}:[{},{},{},{}]",
                record[0], record[1], record[2], record[3]
            )
        })
        .collect::<Vec<_>>()
        .join(",");
    eprintln!(
        "[laniusc][wasm-codegen] readback.body_fragment_meta items={} token_capacity={} records=[{records}]",
        words.len() / 4,
        token_capacity
    );
    Ok(())
}

pub(super) fn trace_func_invalid_readback(
    device: &wgpu::Device,
    invalid_count_readback: &wgpu::Buffer,
    detail_readback: &wgpu::Buffer,
) -> Result<()> {
    let invalid_counts = read_u32_vec_from_readback(
        device,
        invalid_count_readback,
        "codegen.wasm.func_invalid_count",
    )?;
    let details = read_u32_vec_from_readback(device, detail_readback, "codegen.wasm.func_detail")?;
    let invalid = invalid_counts
        .iter()
        .copied()
        .enumerate()
        .filter(|(_, count)| *count != 0)
        .map(|(token, count)| {
            let detail = details.get(token).copied().unwrap_or(u32::MAX);
            format!("{token}:{count}/{detail}")
        })
        .collect::<Vec<_>>()
        .join(",");
    eprintln!("[laniusc][wasm-codegen] readback.func_invalid token:count/detail=[{invalid}]");
    Ok(())
}

pub(super) fn wasm_readback_timeout() -> Duration {
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
    LaniusBuffer::new_labeled((buffer, (count * 4) as u64), count, label)
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
