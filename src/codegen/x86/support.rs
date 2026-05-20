use std::{sync::OnceLock, time::Duration};

use anyhow::{Result, bail};
use log::warn;
use wgpu::util::DeviceExt;

use super::{RecordedX86Codegen, X86Params, X86RegallocParams, X86ScanParams};
use crate::gpu::passes_core::{PassData, bind_group};

fn x86_trace_enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| crate::gpu::env::env_bool_strict("LANIUS_X86_TRACE", false))
}

fn trace_x86_codegen_event(stage: &str, event: &str) {
    if x86_trace_enabled() {
        eprintln!("[laniusc][x86-codegen] {stage}.{event}");
    }
}

pub(super) fn trace_x86_codegen(stage: &str) {
    if x86_trace_enabled() {
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

pub(super) fn x86_regalloc_params_bytes(params: &X86RegallocParams) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params)
        .expect("failed to encode x86 register-allocation params");
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

pub(super) fn init_repeated_u32_words(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    fill_pass: &PassData,
    label: &str,
    buffer: &wgpu::Buffer,
    pattern: &[u32],
    repeats: usize,
) -> Result<()> {
    if pattern.is_empty() || repeats == 0 {
        return Ok(());
    }

    fill_repeated_u32_words_gpu(
        device, queue, encoder, fill_pass, label, buffer, pattern, repeats,
    )
}

pub(super) fn fill_repeated_u32_words_gpu(
    device: &wgpu::Device,
    _queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    fill_pass: &PassData,
    label: &str,
    buffer: &wgpu::Buffer,
    pattern: &[u32],
    repeats: usize,
) -> Result<()> {
    if pattern.is_empty() || repeats == 0 {
        return Ok(());
    }
    if pattern.len() > 4 {
        bail!("x86 GPU fill supports repeated patterns up to four u32 words");
    }

    let words = pattern.len().saturating_mul(repeats).max(1);
    let mut pattern_words = [0u32; 4];
    for (index, word) in pattern.iter().enumerate() {
        pattern_words[index] = *word;
    }
    let param_words = [
        words as u32,
        pattern.len() as u32,
        pattern_words[0],
        pattern_words[1],
        pattern_words[2],
        pattern_words[3],
        0,
        0,
    ];
    let params = uniform_u32_words(device, "codegen.x86.fill_u32.params", &param_words);
    let bind_group = reflected_bind_group(
        device,
        Some("codegen.x86.fill_u32.bind_group"),
        fill_pass,
        0,
        &[
            ("gFill", params.as_entire_binding()),
            ("target", buffer.as_entire_binding()),
        ],
    )?;
    let groups = workgroup_grid_1d((words as u32).div_ceil(256).max(1));
    let trace_stage = format!("fill_u32.{label}");
    let pass_label = format!("codegen.x86.fill_u32.{label}");
    dispatch_compute_pass(
        encoder,
        &trace_stage,
        &pass_label,
        fill_pass,
        &bind_group,
        groups,
    );
    Ok(())
}

pub(super) fn zero_u32_words(
    _queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    buffer: &wgpu::Buffer,
    words: usize,
) {
    let words = words.max(1);
    let bytes = words * 4;
    encoder.clear_buffer(buffer, 0, Some(bytes as u64));
}

pub(super) fn uniform_u32_struct(device: &wgpu::Device, label: &str, bytes: &[u8]) -> wgpu::Buffer {
    let contents = if bytes.is_empty() { &[0u8][..] } else { bytes };
    device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
        label: Some(label),
        contents,
        usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
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

pub(super) fn pointer_jump_steps_for_items(n_items: usize) -> Vec<u32> {
    let mut value = n_items.max(1) as u32;
    let mut steps = Vec::new();
    while value != 0 {
        steps.push(steps.len() as u32);
        value >>= 1;
    }
    steps
}

pub(super) fn dispatch_compute_pass(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage: &str,
    label: &str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    groups: (u32, u32),
) {
    trace_x86_codegen_event(trace_stage, "record.start");
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(label),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, bind_group, &[]);
        compute.dispatch_workgroups(groups.0, groups.1, 1);
    }
    trace_x86_codegen_event(trace_stage, "record.done");
}

pub(super) fn dispatch_compute_pass_indirect(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage: &str,
    label: &str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    indirect_buffer: &wgpu::Buffer,
) {
    dispatch_compute_pass_indirect_offset(
        encoder,
        trace_stage,
        label,
        pass,
        bind_group,
        indirect_buffer,
        0,
    );
}

pub(super) fn dispatch_compute_pass_indirect_offset(
    encoder: &mut wgpu::CommandEncoder,
    trace_stage: &str,
    label: &str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    indirect_buffer: &wgpu::Buffer,
    indirect_offset: u64,
) {
    trace_x86_codegen_event(trace_stage, "record.start");
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(label),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, bind_group, &[]);
        compute.dispatch_workgroups_indirect(indirect_buffer, indirect_offset);
    }
    trace_x86_codegen_event(trace_stage, "record.done");
}

pub(super) fn dispatch_x86_stages(
    encoder: &mut wgpu::CommandEncoder,
    stages: &[(&'static str, &PassData, &wgpu::BindGroup)],
    groups: (u32, u32),
) {
    if stages.is_empty() {
        return;
    }
    let label = if stages.len() == 1 {
        format!("codegen.x86.{}", stages[0].0)
    } else {
        format!("codegen.x86.group.{}+{}", stages[0].0, stages.len())
    };
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(&label),
        timestamp_writes: None,
    });
    for (stage, pass, bind_group) in stages {
        trace_x86_codegen_event(stage, "record.start");
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, *bind_group, &[]);
        compute.dispatch_workgroups(groups.0, groups.1, 1);
        trace_x86_codegen_event(stage, "record.done");
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

pub(super) fn dispatch_x86_stages_indirect(
    encoder: &mut wgpu::CommandEncoder,
    stages: &[(&'static str, &PassData, &wgpu::BindGroup)],
    indirect_buffer: &wgpu::Buffer,
) {
    if stages.is_empty() {
        return;
    }
    let label = if stages.len() == 1 {
        format!("codegen.x86.{}", stages[0].0)
    } else {
        format!("codegen.x86.group.{}+{}", stages[0].0, stages.len())
    };
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(&label),
        timestamp_writes: None,
    });
    for (stage, pass, bind_group) in stages {
        trace_x86_codegen_event(stage, "record.start");
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, *bind_group, &[]);
        compute.dispatch_workgroups_indirect(indirect_buffer, 0);
        trace_x86_codegen_event(stage, "record.done");
    }
}

pub(super) fn dispatch_x86_stage_indirect(
    encoder: &mut wgpu::CommandEncoder,
    stage: &'static str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    indirect_buffer: &wgpu::Buffer,
) {
    let label = format!("codegen.x86.{stage}");
    dispatch_compute_pass_indirect(encoder, stage, &label, pass, bind_group, indirect_buffer);
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
    _queue: &wgpu::Queue,
    recorded: &RecordedX86Codegen,
) -> Result<Vec<u8>> {
    let readback_slice = recorded.output_readback.slice(..);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &readback_slice,
        "codegen.x86.output_status",
        x86_readback_timeout(),
    )?;

    let bytes = {
        let data = recorded.output_readback.slice(..).get_mapped_range();
        let status_offset = recorded.output_status_offset as usize;
        let status_end = status_offset.saturating_add(16);
        let status_words = if status_end <= data.len() {
            crate::gpu::readback::read_u32_words(
                &data[status_offset..status_end],
                "x86 codegen status",
            )
        } else {
            Err(anyhow::anyhow!(
                "x86 codegen status readback was truncated: expected status at bytes {status_offset}..{status_end}, got {} bytes",
                data.len()
            ))
        };
        let [len, mode, error_code, error_detail] = match status_words {
            Ok(status_words) => status_words,
            Err(err) => {
                drop(data);
                recorded.output_readback.unmap();
                return Err(err);
            }
        };
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
                15 => "virtual register allocation failure",
                17 => "instruction selection failure",
                _ => "unsupported source shape",
            };
            drop(data);
            recorded.output_readback.unmap();
            return Err(anyhow::anyhow!(
                "GPU x86 emitter rejected {error_name} (code {error_code}) at token {error_detail}"
            ));
        }
        if mode != 1 || len > recorded.output_capacity {
            drop(data);
            recorded.output_readback.unmap();
            return Err(anyhow::anyhow!(
                "GPU x86 emitter produced {} bytes for capacity {}",
                len,
                recorded.output_capacity
            ));
        }
        if let Some(status_trace_readback) = &recorded.status_trace_readback {
            if let Err(err) = dump_x86_status_trace(device, status_trace_readback) {
                warn!("failed to read x86 status trace: {err:#}");
            }
        }
        let bytes = data[..len].to_vec();
        drop(data);
        recorded.output_readback.unmap();
        bytes
    };

    Ok(bytes)
}

fn dump_x86_status_trace(device: &wgpu::Device, readback: &wgpu::Buffer) -> Result<()> {
    let slice = readback.slice(..);
    crate::gpu::passes_core::wait_for_readback_map(
        device,
        &slice,
        "codegen.x86.status_trace",
        x86_readback_timeout(),
    )?;
    let data = readback.slice(..).get_mapped_range();
    let words: [u32; 84] = crate::gpu::readback::read_u32_words(&data, "x86 status trace")?;
    drop(data);
    readback.unmap();

    let mut offset = 0usize;
    for (name, len) in [
        ("enum_records", 4usize),
        ("struct_records", 4),
        ("decl_layout", 4),
        ("node_inst_count", 4),
        ("node_inst_order", 4),
        ("node_inst_range", 4),
        ("node_inst_subtree_bounds", 4),
        ("node_inst_locations", 4),
        ("node_inst_gen_input", 4),
        ("virtual_inst", 4),
        ("virtual_func_first_row", 4),
        ("virtual_next_call", 4),
        ("func_param_reg_mask", 4),
        ("virtual_liveness", 4),
        ("virtual_regalloc", 4),
        ("select", 4),
        ("size", 4),
        ("text", 4),
        ("encode", 4),
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

fn x86_readback_timeout() -> Duration {
    let ms = crate::gpu::env::env_u64("LANIUS_X86_READBACK_TIMEOUT_MS", 3_000);
    Duration::from_millis(ms)
}
