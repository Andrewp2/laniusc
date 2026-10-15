//! Debug capture of one compute dispatch for offline replay.
//!
//! `LANIUS_DEBUG_CAPTURE_PASS=<name>` selects the dispatches recorded under that
//! operation label (as `LANIUS_DEBUG_OPERATION_LOG=1` prints it) or of that
//! kernel (shader artifact key, e.g. `parser/tokens/to/kinds`), and
//! `LANIUS_DEBUG_CAPTURE_INDEX=k` (default 0) picks the k-th of them. The selected dispatch is recorded in a compute pass of its own,
//! with every bound range copied right before it (the inputs) and right after
//! it (the GPU's outputs), plus its indirect dispatch arguments.
//! `debug_write_capture` saves all of it to `LANIUS_DEBUG_CAPTURE_DIR` (default
//! `lanius-capture`): `manifest.json`, one `NNN_name.bin` per binding with the
//! inputs and `post/NNN_name.bin` with the outputs. `tools/cpu_kernel_replay.py`
//! reruns the kernel on the CPU from such a capture (see
//! docs/cpu-kernel-replay.md); `src/bin/shader_dispatch_replay.rs` and
//! `crates/vk-hang-probe` replay it on the GPU.
//!
//! With `LANIUS_DEBUG_OPERATION_LIMIT` the first dispatch of the label that the
//! limit drops is captured instead (hang debugging): only its inputs exist.

use std::sync::{LazyLock, Mutex, OnceLock};

use super::passes_core::{
    PassData,
    debug_operation_limited,
    debug_operation_skipped,
    map_readback_blocking,
};

/// How the captured dispatch is launched.
pub(crate) enum CaptureLaunch<'a> {
    Direct((u32, u32, u32)),
    Indirect(&'a wgpu::Buffer, u64),
}

#[derive(Clone)]
struct BoundRange {
    binding: u32,
    buffer: wgpu::Buffer,
    offset: u64,
    end: u64,
}

struct Binding {
    binding: u32,
    name: String,
    uniform: bool,
    buffer: wgpu::Buffer,
    offset: u64,
    bytes: u64,
    pre: Option<wgpu::Buffer>,
    post: Option<wgpu::Buffer>,
}

struct Selected {
    label: String,
    kernel: String,
    index: u64,
    thread_group_size: [u32; 3],
    bindings: Vec<Binding>,
    groups: Option<(u32, u32, u32)>,
    indirect: Option<(wgpu::Buffer, u64)>,
    indirect_copy: Option<wgpu::Buffer>,
    dynamic_offsets: Vec<u32>,
    /// False when `LANIUS_DEBUG_OPERATION_LIMIT` dropped the dispatch.
    dispatched: bool,
    pre_done: bool,
    post_done: bool,
}

#[derive(Default)]
struct CaptureState {
    /// Shader artifact key of each pipeline (by address): `PassData::shader_id`
    /// is the logical pass name, which may differ.
    shaders: Vec<(usize, String)>,
    /// Every buffer bind group created while capturing, with its bound ranges.
    bind_groups: Vec<(wgpu::BindGroup, Vec<BoundRange>)>,
    /// Dispatches of the captured label seen so far.
    seen: u64,
    selected: Option<Selected>,
}

static STATE: LazyLock<Mutex<CaptureState>> = LazyLock::new(Default::default);

/// The operation label being captured, if any.
pub(crate) fn capture_pass() -> Option<&'static str> {
    static PASS: OnceLock<Option<String>> = OnceLock::new();
    PASS.get_or_init(|| std::env::var("LANIUS_DEBUG_CAPTURE_PASS").ok())
        .as_deref()
}

fn capture_index() -> u64 {
    crate::gpu::env::env_u64("LANIUS_DEBUG_CAPTURE_INDEX", 0)
}

fn state() -> std::sync::MutexGuard<'static, CaptureState> {
    STATE.lock().expect("debug capture poisoned")
}

/// Remembers which shader artifact `pass`'s pipeline was built from.
pub(crate) fn record_kernel_shader(pass: &PassData, shader: &str) {
    if capture_pass().is_none() {
        return;
    }
    let pipeline = std::sync::Arc::as_ptr(&pass.pipeline) as usize;
    let mut state = state();
    if !state.shaders.iter().any(|(known, _)| *known == pipeline) {
        state.shaders.push((pipeline, shader.to_owned()));
    }
}

/// Remembers the buffer ranges of a newly created bind group.
pub(crate) fn record_bind_group(
    bind_group: &wgpu::BindGroup,
    entries: &[wgpu::BindGroupEntry<'_>],
) {
    if capture_pass().is_none() {
        return;
    }
    let ranges = entries
        .iter()
        .filter_map(|entry| match &entry.resource {
            wgpu::BindingResource::Buffer(binding) => Some(BoundRange {
                binding: entry.binding,
                buffer: binding.buffer.clone(),
                offset: binding.offset,
                end: binding.offset.saturating_add(binding.size.map_or_else(
                    || binding.buffer.size().saturating_sub(binding.offset),
                    |size| size.get(),
                )),
            }),
            _ => None,
        })
        .collect();
    state().bind_groups.push((bind_group.clone(), ranges));
}

/// Reflected (name, is constant buffer) of every binding index in set 0.
fn reflected_names(pass: &PassData) -> Vec<(u32, String, bool)> {
    let reflection = &pass.reflection;
    let parameters = reflection
        .entry_points
        .iter()
        .find(|entry| entry.stage.as_deref() == Some("compute"))
        .and_then(|entry| entry.program_layout.as_ref())
        .and_then(|layout| layout.parameters.first())
        .map(|set| set.parameters.as_slice())
        .unwrap_or(reflection.parameters.as_slice());
    parameters
        .iter()
        .filter_map(|parameter| {
            let index = parameter.binding.index?;
            let uniform = parameter.ty.kind.as_deref() == Some("constantBuffer");
            Some((index, parameter.name.clone(), uniform))
        })
        .collect()
}

/// Decides whether this dispatch of `label` is the captured one. Returns true
/// when the caller must record it in a compute pass of its own between
/// `debug_capture_before` and `debug_capture_after`. A capture of a dispatch
/// that the operation limit drops returns false; `debug_capture_snapshot`
/// then copies its inputs at the next flush.
pub(crate) fn debug_capture_select(
    label: &str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    dynamic_offsets: &[u32],
    launch: CaptureLaunch<'_>,
) -> bool {
    let Some(wanted) = capture_pass() else {
        return false;
    };
    let mut state = state();
    if state.selected.is_some() {
        return false;
    }
    let pipeline = std::sync::Arc::as_ptr(&pass.pipeline) as usize;
    let kernel = state
        .shaders
        .iter()
        .find(|(known, _)| *known == pipeline)
        .map_or_else(|| pass.shader_id.clone(), |(_, shader)| shader.clone());
    if label != wanted && kernel != wanted {
        return false;
    }
    let skipped = debug_operation_skipped();
    let limited = debug_operation_limited();
    if limited && !skipped {
        return false;
    }
    let index = state.seen;
    state.seen += 1;
    if !limited && index != capture_index() {
        return false;
    }
    let Some(ranges) = state
        .bind_groups
        .iter()
        .rev()
        .find(|(candidate, _)| candidate == bind_group)
        .map(|(_, ranges)| ranges.clone())
    else {
        eprintln!("[lanius-capture] {label}: dispatch #{index} uses an unrecorded bind group");
        return false;
    };
    let names = reflected_names(pass);
    let mut bindings = ranges
        .into_iter()
        .map(|range| {
            let (name, uniform) = names
                .iter()
                .find(|(index, _, _)| *index == range.binding)
                .map(|(_, name, uniform)| (name.clone(), *uniform))
                .unwrap_or_else(|| (format!("binding{}", range.binding), false));
            Binding {
                binding: range.binding,
                name,
                uniform,
                buffer: range.buffer,
                offset: range.offset,
                bytes: range.end.saturating_sub(range.offset) & !3,
                pre: None,
                post: None,
            }
        })
        .collect::<Vec<_>>();
    bindings.sort_by_key(|binding| binding.binding);
    // Dynamic offsets apply to the dynamic bindings in binding order; only
    // uniform buffers are ever bound with dynamic offsets here.
    let uniforms = bindings.iter().filter(|binding| binding.uniform).count();
    if !dynamic_offsets.is_empty() {
        if uniforms == dynamic_offsets.len() {
            for (binding, offset) in bindings
                .iter_mut()
                .filter(|binding| binding.uniform)
                .zip(dynamic_offsets)
            {
                binding.offset += u64::from(*offset);
            }
        } else {
            eprintln!(
                "[lanius-capture] {label}: {} dynamic offsets for {uniforms} uniform bindings; offsets not applied",
                dynamic_offsets.len()
            );
        }
    }
    let (groups, indirect) = match launch {
        CaptureLaunch::Direct(groups) => (Some(groups), None),
        CaptureLaunch::Indirect(buffer, offset) => (None, Some((buffer.clone(), offset))),
    };
    eprintln!(
        "[lanius-capture] {label}: selected dispatch #{index} of {kernel}{}",
        if skipped {
            " (dropped by the operation limit: inputs only)"
        } else {
            ""
        }
    );
    state.selected = Some(Selected {
        label: label.to_owned(),
        kernel,
        index,
        thread_group_size: pass.thread_group_size,
        bindings,
        groups,
        indirect,
        indirect_copy: None,
        dynamic_offsets: dynamic_offsets.to_vec(),
        dispatched: !skipped,
        pre_done: false,
        post_done: false,
    });
    !skipped
}

fn snapshot_buffer(
    encoder: &mut wgpu::CommandEncoder,
    source: &wgpu::Buffer,
    offset: u64,
    bytes: u64,
    what: &str,
) -> Option<wgpu::Buffer> {
    if !source.usage().contains(wgpu::BufferUsages::COPY_SRC) {
        eprintln!(
            "[lanius-capture] {what}: buffer lacks COPY_SRC (create it with buffers::with_debug_copy); not captured"
        );
        return None;
    }
    let device = &crate::gpu::device::global_result()
        .expect("debug capture device")
        .device;
    let copy = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("lanius-debug-capture-snapshot"),
        size: bytes.max(4),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::COPY_SRC,
        mapped_at_creation: false,
    });
    if bytes != 0 {
        encoder.copy_buffer_to_buffer(source, offset, &copy, 0, bytes);
    }
    Some(copy)
}

fn copy_inputs(encoder: &mut wgpu::CommandEncoder, capture: &mut Selected) {
    capture.pre_done = true;
    for binding in &mut capture.bindings {
        binding.pre = snapshot_buffer(
            encoder,
            &binding.buffer,
            binding.offset,
            binding.bytes,
            &binding.name,
        );
    }
    if let Some((buffer, offset)) = &capture.indirect {
        capture.indirect_copy =
            snapshot_buffer(encoder, buffer, *offset, 12, "indirect dispatch arguments");
    }
}

/// Copies the captured dispatch's inputs; record right before its pass.
pub(crate) fn debug_capture_before(encoder: &mut wgpu::CommandEncoder) {
    let mut state = state();
    if let Some(capture) = state.selected.as_mut().filter(|capture| !capture.pre_done) {
        copy_inputs(encoder, capture);
    }
}

/// Copies the captured dispatch's outputs; record right after its pass.
pub(crate) fn debug_capture_after(encoder: &mut wgpu::CommandEncoder) {
    let mut state = state();
    let Some(capture) = state.selected.as_mut() else {
        return;
    };
    if capture.post_done || !capture.dispatched {
        return;
    }
    capture.post_done = true;
    for binding in &mut capture.bindings {
        binding.post = snapshot_buffer(
            encoder,
            &binding.buffer,
            binding.offset,
            binding.bytes,
            &binding.name,
        );
    }
}

/// Copies the inputs of a selected dispatch that was never bracketed by
/// `debug_capture_before` (one the operation limit dropped) at this point of
/// the command stream, so later reuse of aliased memory cannot clobber them.
pub(crate) fn debug_capture_snapshot(encoder: &mut wgpu::CommandEncoder) {
    if capture_pass().is_none() {
        return;
    }
    let mut state = state();
    if let Some(capture) = state
        .selected
        .as_mut()
        .filter(|capture| !capture.pre_done && !capture.dispatched)
    {
        copy_inputs(encoder, capture);
    }
}

fn read_back(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    buffer: &wgpu::Buffer,
    offset: u64,
    bytes: u64,
) -> anyhow::Result<Vec<u8>> {
    let staging = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("lanius-debug-capture"),
        size: bytes.max(4),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("lanius-debug-capture"),
    });
    if bytes != 0 {
        encoder.copy_buffer_to_buffer(buffer, offset, &staging, 0, bytes);
    }
    queue.submit(Some(encoder.finish()));
    let slice = staging.slice(..);
    map_readback_blocking(device, &slice, "lanius-debug-capture")?;
    let data = slice.get_mapped_range()[..bytes as usize].to_vec();
    Ok(data)
}

/// Writes the selected capture to `LANIUS_DEBUG_CAPTURE_DIR`.
pub(crate) fn debug_write_capture(device: &wgpu::Device, queue: &wgpu::Queue) {
    let Some(pass) = capture_pass() else { return };
    if let Err(err) = write_capture(device, queue, pass) {
        eprintln!("[lanius-capture] {pass}: {err:#}");
    }
}

fn write_capture(device: &wgpu::Device, queue: &wgpu::Queue, pass: &str) -> anyhow::Result<()> {
    let selected = state().selected.take();
    let Some(capture) = selected else {
        let seen = state().seen;
        anyhow::bail!(
            "no dispatch captured ({seen} dispatches of this label went through a capturing dispatch path)"
        );
    };
    let dir = std::path::PathBuf::from(
        std::env::var("LANIUS_DEBUG_CAPTURE_DIR").unwrap_or_else(|_| "lanius-capture".into()),
    );
    let has_post = capture.post_done;
    std::fs::create_dir_all(if has_post {
        dir.join("post")
    } else {
        dir.clone()
    })?;
    let mut bindings = Vec::new();
    for binding in &capture.bindings {
        let file = format!("{:03}_{}.bin", binding.binding, binding.name);
        // A capture whose inputs were never snapshotted reads the live buffers.
        let pre = match &binding.pre {
            Some(copy) => read_back(device, queue, copy, 0, binding.bytes)?,
            None if !capture.pre_done
                && binding
                    .buffer
                    .usage()
                    .contains(wgpu::BufferUsages::COPY_SRC) =>
            {
                read_back(
                    device,
                    queue,
                    &binding.buffer,
                    binding.offset,
                    binding.bytes,
                )?
            }
            None => continue,
        };
        std::fs::write(dir.join(&file), &pre)?;
        let mut entry = serde_json::json!({
            "binding": binding.binding,
            "name": binding.name,
            "file": file,
            "bytes": binding.bytes,
            "uniform": binding.uniform,
        });
        if let Some(post) = &binding.post {
            let post_file = format!("post/{file}");
            std::fs::write(
                dir.join(&post_file),
                read_back(device, queue, post, 0, binding.bytes)?,
            )?;
            entry["post_file"] = serde_json::json!(post_file);
        }
        bindings.push(entry);
    }
    let groups = match (&capture.groups, &capture.indirect_copy) {
        (Some(groups), _) => *groups,
        (None, Some(copy)) => {
            let words = read_back(device, queue, copy, 0, 12)?;
            let word =
                |i: usize| u32::from_le_bytes(words[i * 4..i * 4 + 4].try_into().expect("word"));
            (word(0), word(1), word(2))
        }
        (None, None) => (0, 0, 0),
    };
    let manifest = serde_json::json!({
        "pass": pass,
        "label": capture.label,
        "kernel": capture.kernel,
        "dispatch_index": capture.index,
        "thread_group_size": capture.thread_group_size,
        "groups": [groups.0, groups.1, groups.2],
        "indirect": capture.indirect.is_some(),
        "dispatched": capture.dispatched,
        "post": has_post,
        "dynamic_offsets": capture.dynamic_offsets,
        "bindings": bindings,
    });
    std::fs::write(
        dir.join("manifest.json"),
        serde_json::to_string_pretty(&manifest)?,
    )?;
    eprintln!(
        "[lanius-capture] {pass}: wrote dispatch #{} of {} ({} bindings{}, groups {:?}) to {}",
        capture.index,
        capture.kernel,
        bindings.len(),
        if has_post {
            ", inputs and outputs"
        } else {
            ", inputs only"
        },
        groups,
        dir.display()
    );
    Ok(())
}

/// Starts the capture bracket around a dispatch recorded in a compute pass of
/// its own; pass the result to `debug_capture_end` after the pass ends.
pub(crate) fn debug_capture_begin(
    encoder: &mut wgpu::CommandEncoder,
    label: &str,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    dynamic_offsets: &[u32],
    launch: CaptureLaunch<'_>,
) -> bool {
    let captured = debug_capture_select(label, pass, bind_group, dynamic_offsets, launch);
    if captured {
        debug_capture_before(encoder);
    }
    captured
}

/// Ends the bracket `debug_capture_begin` started.
pub(crate) fn debug_capture_end(encoder: &mut wgpu::CommandEncoder, captured: bool) {
    if captured {
        debug_capture_after(encoder);
    }
}
