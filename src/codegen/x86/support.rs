use std::{
    sync::mpsc,
    time::{Duration, Instant},
};

use anyhow::Result;
use log::warn;

use super::{RecordedX86Codegen, X86Params, X86ScanParams};
use crate::gpu::passes_core::{PassData, bind_group};

pub(super) fn trace_x86_codegen(stage: &str) {
    if crate::gpu::env::env_bool_strict("LANIUS_X86_TRACE", false) {
        eprintln!("[laniusc][x86-codegen] {stage}");
    }
}

pub(super) fn x86_params_bytes(params: &X86Params) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params)
        .expect("failed to encode x86 codegen params");
    ub.as_ref().to_vec()
}

pub(super) fn x86_scan_params_bytes(params: &X86ScanParams) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params).expect("failed to encode x86 scan params");
    ub.as_ref().to_vec()
}

pub(super) fn u32_words_bytes(words: &[u32]) -> Vec<u8> {
    let mut out = Vec::with_capacity(words.len() * 4);
    for word in words {
        out.extend_from_slice(&word.to_le_bytes());
    }
    out
}

pub(super) fn write_u32_words(queue: &wgpu::Queue, buffer: &wgpu::Buffer, words: &[u32]) {
    queue.write_buffer(buffer, 0, &u32_words_bytes(words));
}

pub(super) fn write_repeated_u32_words(
    queue: &wgpu::Queue,
    buffer: &wgpu::Buffer,
    pattern: &[u32],
    repeats: usize,
) {
    queue.write_buffer(buffer, 0, &u32_words_bytes(pattern).repeat(repeats));
}

pub(super) fn uniform_u32_struct(device: &wgpu::Device, label: &str, bytes: &[u8]) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: bytes.len().max(1) as u64,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
        mapped_at_creation: false,
    })
}

pub(super) fn uniform_u32_words(device: &wgpu::Device, label: &str, words: &[u32]) -> wgpu::Buffer {
    uniform_u32_struct(device, label, &u32_words_bytes(words))
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

pub(super) fn storage_u32_copy(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    storage_u32_rw(device, label, count, wgpu::BufferUsages::COPY_SRC)
}

pub(super) fn readback_u32s(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
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

pub(super) fn scan_steps_for_blocks(n_blocks: usize) -> Vec<u32> {
    crate::gpu::scan::scan_step_values(n_blocks as u32)
}

pub(super) fn dispatch_compute_pass(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage: &str,
    label: &str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    groups: (u32, u32),
) {
    trace_x86_codegen(&format!("{trace_stage}.record.start"));
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(label),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, bind_group, &[]);
        compute.dispatch_workgroups(groups.0, groups.1, 1);
    }
    trace_x86_codegen(&format!("{trace_stage}.record.done"));
}

pub(super) fn dispatch_x86_stages(
    encoder: &mut wgpu::CommandEncoder,
    stages: &[(&'static str, &PassData, &wgpu::BindGroup)],
    groups: (u32, u32),
) {
    for (stage, pass, bind_group) in stages {
        let label = format!("codegen.x86.{stage}");
        dispatch_compute_pass(encoder, stage, &label, pass, bind_group, groups);
    }
}

pub(super) fn dispatch_x86_stage(
    encoder: &mut wgpu::CommandEncoder,
    stage: &'static str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    groups: (u32, u32),
) {
    let label = format!("codegen.x86.{stage}");
    dispatch_compute_pass(encoder, stage, &label, pass, bind_group, groups);
}

pub(super) fn reflected_bind_group(
    device: &wgpu::Device,
    label: Option<&'static str>,
    pass: &PassData,
    group_index: usize,
    bindings: &[(&str, wgpu::BindingResource<'_>)],
) -> Result<wgpu::BindGroup> {
    bind_group::create_bind_group_from_bindings(device, label, pass, group_index, bindings).map_err(
        |err| {
            anyhow::anyhow!(
                "create reflected bind group {}: {err:#}",
                label.unwrap_or("<unnamed>")
            )
        },
    )
}

pub(super) fn read_x86_output(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    recorded: &RecordedX86Codegen,
) -> Result<Vec<u8>> {
    let status_slice = recorded.status_readback.slice(..);
    wait_for_map(device, &status_slice, "codegen.x86.status")?;

    let len = {
        let data = recorded.status_readback.slice(..).get_mapped_range();
        let status_words = crate::gpu::readback::read_u32_words(&data, "x86 codegen status");
        drop(data);
        recorded.status_readback.unmap();
        let [len, mode, error_code, error_detail] = status_words?;
        let len = len as usize;

        if error_code != 0 {
            if let Some(status_trace_readback) = &recorded.status_trace_readback {
                if let Err(err) = dump_x86_status_trace(device, status_trace_readback) {
                    warn!("failed to read x86 status trace: {err:#}");
                }
            }
            let error_name = match error_code {
                2 => "missing main entrypoint",
                3 => "unsupported return expression",
                4 => "output capacity too small",
                5 => "register allocation failure",
                6 => "instruction sizing failure",
                7 => "ELF layout failure",
                8 => "relocation patch failure",
                17 => "instruction selection failure",
                _ => "unsupported source shape",
            };
            return Err(anyhow::anyhow!(
                "GPU x86 emitter rejected {error_name} (code {error_code}) at token {error_detail}"
            ));
        }
        if mode != 1 || len > recorded.output_capacity {
            return Err(anyhow::anyhow!(
                "GPU x86 emitter produced {} bytes for capacity {}",
                len,
                recorded.output_capacity
            ));
        }
        len
    };

    let output_bytes = (len.div_ceil(4) * 4) as u64;
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("codegen.x86.exact_output_readback.encoder"),
    });
    encoder.copy_buffer_to_buffer(
        &recorded.out_buf,
        0,
        &recorded.out_readback,
        0,
        output_bytes,
    );
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "codegen.x86.output-readback",
        encoder.finish(),
    );

    let output_slice = recorded.out_readback.slice(0..output_bytes);
    wait_for_map(device, &output_slice, "codegen.x86.output")?;

    let data = recorded
        .out_readback
        .slice(0..output_bytes)
        .get_mapped_range();
    let mut bytes = Vec::with_capacity(len);
    for &byte in data.iter().take(len) {
        bytes.push(byte);
    }
    drop(data);
    recorded.out_readback.unmap();
    Ok(bytes)
}

fn dump_x86_status_trace(device: &wgpu::Device, readback: &wgpu::Buffer) -> Result<()> {
    let slice = readback.slice(..);
    wait_for_map(device, &slice, "codegen.x86.status_trace")?;
    let data = readback.slice(..).get_mapped_range();
    let words: [u32; 126] = crate::gpu::readback::read_u32_words(&data, "x86 status trace")?;
    drop(data);
    readback.unmap();

    let mut offset = 0usize;
    for (name, len) in [
        ("lower", 4usize),
        ("use_edges", 4),
        ("liveness", 4),
        ("regalloc", 4),
        ("node_inst_count", 4),
        ("node_inst_order", 4),
        ("node_inst_range", 4),
        ("node_inst_locations", 4),
        ("virtual_inst", 4),
        ("virtual_use", 4),
        ("virtual_liveness", 4),
        ("virtual_regalloc", 4),
        ("func_inst_count", 9),
        ("func_inst_order", 9),
        ("func_inst_range", 9),
        ("func_layout", 9),
        ("func_return_inst", 4),
        ("entry_inst", 6),
        ("plan", 4),
        ("select", 4),
        ("size", 4),
        ("text", 4),
        ("encode", 4),
        ("reloc", 4),
        ("elf_layout", 4),
        ("final", 4),
    ] {
        let end = offset + len;
        if end <= words.len() {
            eprintln!("[laniusc][x86-status] {name}: {:?}", &words[offset..end]);
        }
        offset = end;
    }
    Ok(())
}

fn wait_for_map(device: &wgpu::Device, slice: &wgpu::BufferSlice<'_>, label: &str) -> Result<()> {
    let label = label.to_string();
    let cb_label = label.clone();
    let (tx, rx) = mpsc::channel();
    crate::gpu::passes_core::trace_gpu_progress(&format!("map.start :: {label}"));
    slice.map_async(wgpu::MapMode::Read, move |result| {
        if let Err(err) = tx.send(result) {
            warn!("failed to dispatch x86 readback status for {cb_label}: {err}");
        }
    });
    crate::gpu::passes_core::trace_gpu_progress(&format!("map.queued :: {label}"));

    let timeout = x86_readback_timeout();
    let start = Instant::now();
    loop {
        crate::gpu::passes_core::wait_for_map_progress(
            device,
            &format!("codegen.x86.output-poll({label})"),
            wgpu::PollType::Poll,
        );
        match rx.try_recv() {
            Ok(Ok(())) => return Ok(()),
            Ok(Err(err)) => return Err(anyhow::anyhow!("{label} readback map failed: {err}")),
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
        std::thread::yield_now();
    }
}

fn x86_readback_timeout() -> Duration {
    let ms = crate::gpu::env::env_u64("LANIUS_X86_READBACK_TIMEOUT_MS", 3_000);
    Duration::from_millis(ms)
}
