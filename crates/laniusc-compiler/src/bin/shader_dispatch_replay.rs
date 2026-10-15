//! Replays one captured compute dispatch against a SPIR-V file.
//!
//! A capture directory comes from running the compiler with
//! `LANIUS_DEBUG_CAPTURE_PASS` (see `gpu/dispatch_capture.rs`). The
//! shader is loaded from disk, so patched SPIR-V variants of one kernel can
//! be compared on identical inputs without rebuilding the compiler. Reports
//! whether the dispatch finished within `LANIUS_READBACK_TIMEOUT_MS` and a
//! digest of every binding afterwards; `--out DIR` also saves the results.
//!
//! `--also CAPTURE SHADER.spv SHADER.reflect.json` (repeatable) loads more
//! kernels; with `REPLAY_INTERLEAVE=n` each of them is dispatched before the
//! first kernel in n timed rounds, to measure how one kernel's time depends
//! on what ran before it on the device.

use std::{
    env, fs,
    path::{Path, PathBuf},
    process::ExitCode,
    time::Instant,
};

use anyhow::{Context, Result, anyhow};
use laniusc_compiler::{
    gpu::{
        device,
        passes_core::{bgls_from_reflection, map_readback_blocking, pipeline_from_spirv_and_bgls},
    },
    reflection::parse_reflection_from_bytes,
};

const USAGE: &str = "usage: shader_dispatch_replay CAPTURE_DIR SHADER.spv SHADER.reflect.json \
     [--also CAPTURE_DIR SHADER.spv SHADER.reflect.json]... [--out DIR]";

fn digest(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf2_9ce4_8422_2325u64, |hash, byte| {
        (hash ^ u64::from(*byte)).wrapping_mul(0x100_0000_01b3)
    })
}

/// One captured dispatch with its pipeline, buffers and bind group.
struct Kernel {
    name: String,
    pipeline: wgpu::ComputePipeline,
    bind_group: wgpu::BindGroup,
    buffers: Vec<(u32, String, wgpu::Buffer, u64)>,
    groups: [u32; 3],
    pipeline_ms: f64,
}

impl Kernel {
    fn load(gpu: &device::GpuDevice, capture: &str, spv: &str, reflection: &str) -> Result<Self> {
        let device = &gpu.device;
        let capture = Path::new(capture);
        let manifest: serde_json::Value = serde_json::from_slice(
            &fs::read(capture.join("manifest.json")).context("read capture manifest")?,
        )?;
        let groups = manifest["groups"]
            .as_array()
            .ok_or_else(|| anyhow!("manifest has no groups"))?
            .iter()
            .map(|value| value.as_u64().unwrap_or(0) as u32)
            .collect::<Vec<_>>();
        let spirv = fs::read(spv).with_context(|| format!("read {spv}"))?;
        let reflection =
            parse_reflection_from_bytes(&fs::read(reflection)?).map_err(anyhow::Error::msg)?;
        let layouts = bgls_from_reflection(device, &reflection)?;
        let layout_refs = layouts.iter().collect::<Vec<_>>();
        let started = Instant::now();
        let pipeline = pipeline_from_spirv_and_bgls(device, "replay", "main", &spirv, &layout_refs);
        let pipeline_ms = started.elapsed().as_secs_f64() * 1000.0;
        eprintln!("shader_dispatch_replay: {spv}: pipeline created in {pipeline_ms:.1} ms");
        let mut buffers = Vec::new();
        for binding in manifest["bindings"].as_array().ok_or_else(|| anyhow!("no bindings"))? {
            let index = binding["binding"].as_u64().unwrap_or(0) as u32;
            let name = binding["name"].as_str().unwrap_or("").to_owned();
            let data = fs::read(capture.join(binding["file"].as_str().unwrap_or("")))?;
            let size = (data.len() as u64).max(16).next_multiple_of(16);
            let buffer = device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(&name),
                size,
                usage: wgpu::BufferUsages::STORAGE
                    | wgpu::BufferUsages::UNIFORM
                    | wgpu::BufferUsages::COPY_SRC
                    | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            gpu.queue.write_buffer(&buffer, 0, &data);
            buffers.push((index, name, buffer, data.len() as u64));
        }
        let entries = buffers
            .iter()
            .map(|(index, _, buffer, _)| wgpu::BindGroupEntry {
                binding: *index,
                resource: buffer.as_entire_binding(),
            })
            .collect::<Vec<_>>();
        let bind_group = device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("replay"),
            layout: &layouts[0],
            entries: &entries,
        });
        Ok(Self {
            name: manifest["kernel"].as_str().unwrap_or(spv).to_owned(),
            pipeline,
            bind_group,
            buffers,
            groups: [groups[0], groups[1].max(1), groups[2].max(1)],
            pipeline_ms,
        })
    }

    fn record(&self, encoder: &mut wgpu::CommandEncoder) {
        let mut pass = encoder.begin_compute_pass(&Default::default());
        pass.set_pipeline(&self.pipeline);
        pass.set_bind_group(0, Some(&self.bind_group), &[]);
        pass.dispatch_workgroups(self.groups[0], self.groups[1], self.groups[2]);
    }

    /// Submits this dispatch alone and waits for it; returns the wall time.
    fn timed(&self, gpu: &device::GpuDevice) -> Result<f64> {
        let mut encoder = gpu.device.create_command_encoder(&Default::default());
        self.record(&mut encoder);
        let started = Instant::now();
        gpu.queue.submit(Some(encoder.finish()));
        gpu.device
            .poll(wgpu::PollType::wait_indefinitely())
            .map_err(|err| anyhow!("{}: timed dispatch did not finish: {err}", self.name))?;
        Ok(started.elapsed().as_secs_f64() * 1000.0)
    }
}

fn env_usize(name: &str) -> usize {
    env::var(name).ok().and_then(|v| v.parse().ok()).unwrap_or(0)
}

/// The process's shared and resident memory, as reported by the kernel, and
/// the device memory in use, as reported by `nvidia-smi` when it exists.
fn process_memory() -> String {
    let mut parts = fs::read_to_string("/proc/self/status")
        .unwrap_or_default()
        .lines()
        .filter(|line| line.starts_with("VmRSS") || line.starts_with("RssShmem"))
        .map(|line| line.split_whitespace().collect::<Vec<_>>().join(" "))
        .collect::<Vec<_>>();
    if let Ok(output) = std::process::Command::new("nvidia-smi")
        .args(["--query-gpu=memory.used", "--format=csv,noheader"])
        .output()
    {
        parts.push(format!("device used {}", String::from_utf8_lossy(&output.stdout).trim()));
    }
    parts.join(", ")
}

/// Device memory in use, in MiB, as reported by `nvidia-smi`.
fn device_used_mib() -> Option<u64> {
    let output = std::process::Command::new("nvidia-smi")
        .args(["--query-gpu=memory.used", "--format=csv,noheader,nounits"])
        .output()
        .ok()?;
    String::from_utf8_lossy(&output.stdout).trim().parse().ok()
}

/// Every kernel key under `root` (without `.spv`), sorted, skipping tests and
/// keeping those that contain `filter`.
fn kernel_keys(root: &str, filter: Option<&str>) -> Result<Vec<String>> {
    let mut keys = Vec::new();
    let mut pending = vec![PathBuf::from(root)];
    while let Some(dir) = pending.pop() {
        for entry in fs::read_dir(&dir)? {
            let path = entry?.path();
            if path.is_dir() {
                pending.push(path);
            } else if let Some(key) = path.to_str().and_then(|p| p.strip_suffix(".spv")) {
                let key = key.strip_prefix(root).unwrap_or(key).trim_start_matches('/').to_owned();
                if !key.starts_with("tests/") && filter.is_none_or(|f| key.contains(f)) {
                    keys.push(key);
                }
            }
        }
    }
    keys.sort();
    Ok(keys)
}

/// Creates one kernel's `main` (or reflected) compute pipeline on `device`.
fn probe_pipeline(
    device: &wgpu::Device,
    cache: Option<&wgpu::PipelineCache>,
    root: &str,
    key: &str,
) -> Result<Option<wgpu::ComputePipeline>> {
    let spirv = fs::read(Path::new(root).join(format!("{key}.spv")))?;
    let reflection =
        parse_reflection_from_bytes(&fs::read(Path::new(root).join(format!("{key}.reflect.json")))?)
            .map_err(anyhow::Error::msg)?;
    let Some(entry) = reflection
        .entry_points
        .iter()
        .find(|entry| entry.stage.as_deref() == Some("compute"))
    else {
        return Ok(None);
    };
    let layouts = bgls_from_reflection(device, &reflection)?;
    let layout_refs = layouts.iter().map(Some).collect::<Vec<_>>();
    // SAFETY: Slang produced this SPIR-V for the selected backend, as in the
    // compiler's own pipeline creation.
    let module = unsafe {
        device.create_shader_module_passthrough(wgpu::ShaderModuleDescriptorPassthrough {
            label: Some(key),
            spirv: Some(wgpu::util::make_spirv_raw(&spirv)),
            ..Default::default()
        })
    };
    let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some(key),
        bind_group_layouts: &layout_refs,
        immediate_size: 0,
    });
    Ok(Some(device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some(key),
        layout: Some(&layout),
        module: &module,
        entry_point: Some(entry.name.as_deref().unwrap_or("main")),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache,
    })))
}

/// `--memory-probe SHADER_DIR [SUBSTRING]` measures how much device memory
/// creating each kernel's pipeline adds. The NVIDIA driver sizes one
/// device-wide local-memory reservation, the largest per-thread local memory
/// of any created pipeline times the resident threads, at pipeline creation,
/// and never shrinks it. So each kernel gets a fresh device, which shares the
/// compiler's driver pipeline cache, and the result is that kernel's own
/// reservation (plus its code, which is small). With
/// `REPLAY_PROBE_SHARED_DEVICE=1` every kernel is created on one device
/// instead, and the jumps show what a resident compiler sees.
/// `REPLAY_PROBE_ORDER=KEY,KEY,...` creates just those kernels, in that
/// order, on one device, then submits an empty command buffer and waits for
/// the device to go idle before a final reading.
fn memory_probe(root: &str, filter: Option<&str>) -> Result<()> {
    let order = env::var("REPLAY_PROBE_ORDER").ok();
    let keys = match &order {
        Some(list) => list.split(',').map(str::to_owned).collect(),
        None => kernel_keys(root, filter)?,
    };
    let gpu = device::global_result().map_err(|err| anyhow!(err.to_string()))?;
    let cache_data = device::pipeline_cache_for(&gpu.device).and_then(|cache| cache.get_data());
    let shared =
        order.is_some() || env::var("REPLAY_PROBE_SHARED_DEVICE").is_ok_and(|value| value == "1");
    let instance = wgpu::Instance::new(wgpu::InstanceDescriptor {
        backends: wgpu::Backends::VULKAN,
        ..wgpu::InstanceDescriptor::new_without_display_handle()
    });
    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        compatible_surface: None,
        force_fallback_adapter: false,
    }))
    .map_err(|err| anyhow!("no adapter: {err}"))?;
    let open = || -> Result<(wgpu::Device, wgpu::Queue, Option<wgpu::PipelineCache>)> {
        let features = wgpu::Features::PASSTHROUGH_SHADERS
            | (adapter.features() & wgpu::Features::PIPELINE_CACHE);
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("memory_probe"),
            required_features: features,
            required_limits: adapter.limits(),
            // SAFETY: passthrough SPIR-V, as in the compiler's device.
            experimental_features: unsafe { wgpu::ExperimentalFeatures::enabled() },
            memory_hints: wgpu::MemoryHints::default(),
            trace: wgpu::Trace::default(),
        }))
        .map_err(|err| anyhow!("request probe device: {err}"))?;
        let cache = features.contains(wgpu::Features::PIPELINE_CACHE).then(|| unsafe {
            device.create_pipeline_cache(&wgpu::PipelineCacheDescriptor {
                label: Some("memory_probe"),
                data: cache_data.as_deref(),
                fallback: true,
            })
        });
        Ok((device, queue, cache))
    };
    let mut shared_device = if shared { Some(open()?) } else { None };
    println!(
        "{}",
        serde_json::json!({
            "kernels": keys.len(),
            "shared_device": shared,
            "start_mib": device_used_mib(),
            "cache_bytes": cache_data.as_ref().map(Vec::len),
        })
    );
    for key in keys {
        let fresh = if shared_device.is_none() { Some(open()?) } else { None };
        let (device, _, cache) = shared_device.as_ref().or(fresh.as_ref()).expect("a probe device");
        let before = device_used_mib().unwrap_or(0);
        let started = Instant::now();
        let pipeline = probe_pipeline(device, cache.as_ref(), root, &key)?;
        let create_ms = started.elapsed().as_secs_f64() * 1000.0;
        let after = device_used_mib().unwrap_or(0);
        println!(
            "{}",
            serde_json::json!({
                "kernel": key,
                "created": pipeline.is_some(),
                "added_mib": after as i64 - before as i64,
                "used_mib": after,
                "create_ms": create_ms,
            })
        );
        drop(pipeline);
        drop(fresh);
    }
    if let Some((device, queue, _)) = &shared_device {
        queue.submit([device.create_command_encoder(&Default::default()).finish()]);
        device
            .poll(wgpu::PollType::wait_indefinitely())
            .map_err(|err| anyhow!("wait for probe device: {err}"))?;
        std::thread::sleep(std::time::Duration::from_millis(500));
        println!("{}", serde_json::json!({ "idle_used_mib": device_used_mib() }));
    }
    drop(shared_device.take());
    Ok(())
}

fn run() -> Result<()> {
    let mut args = env::args().skip(1).collect::<Vec<_>>();
    if args.first().map(String::as_str) == Some("--memory-probe") {
        let root = args.get(1).ok_or_else(|| anyhow!(USAGE))?;
        return memory_probe(root, args.get(2).map(String::as_str));
    }
    let out = match args.iter().position(|arg| arg == "--out") {
        Some(at) => {
            let dir = PathBuf::from(args.get(at + 1).ok_or_else(|| anyhow!(USAGE))?);
            args.drain(at..at + 2);
            Some(dir)
        }
        None => None,
    };
    let mut specs = args.split(|arg| arg == "--also");
    let Some([capture, spv, reflection]) = specs.next() else {
        return Err(anyhow!(USAGE));
    };
    let gpu = device::global_result().map_err(|err| anyhow!(err.to_string()))?;
    let device = &gpu.device;
    let mut kernel = Kernel::load(gpu, capture, spv, reflection)?;
    let mut others = Vec::new();
    for spec in specs {
        let [capture, spv, reflection] = spec else {
            return Err(anyhow!(USAGE));
        };
        others.push(Kernel::load(gpu, capture, spv, reflection)?);
    }

    // `REPLAY_BALLAST_MB=n` first allocates n MiB of unrelated storage, to
    // replay under the device-memory pressure of a resident compiler.
    let mut ballast = Vec::new();
    for chunk in 0..(env_usize("REPLAY_BALLAST_MB") as u64).div_ceil(256) {
        let buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("replay ballast"),
            size: 256 << 20,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        gpu.queue.write_buffer(&buffer, 0, &(chunk as u32).to_le_bytes());
        ballast.push(buffer);
    }
    if !ballast.is_empty() {
        gpu.queue.submit(std::iter::empty());
        let _ = device.poll(wgpu::PollType::wait_indefinitely());
        eprintln!("shader_dispatch_replay: {} MiB ballast allocated", ballast.len() * 256);
    }

    // `REPLAY_GROUPS_X=n` dispatches only the first n workgroups.
    if let Some(groups_x) = env::var("REPLAY_GROUPS_X").ok().and_then(|v| v.parse().ok()) {
        kernel.groups[0] = groups_x;
    }
    // The first dispatch runs on the captured inputs; time it alone before
    // the readback copies.
    let dispatched = Instant::now();
    let first_kernel_ms = kernel.timed(gpu)?;
    let mut encoder = device.create_command_encoder(&Default::default());
    let mut staging = Vec::new();
    for (_, name, buffer, bytes) in &kernel.buffers {
        let target = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(name),
            size: buffer.size(),
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(buffer, 0, &target, 0, buffer.size());
        staging.push((name.clone(), target, *bytes));
    }
    gpu.queue.submit(Some(encoder.finish()));
    let mut results = serde_json::Map::new();
    for (index, (name, target, bytes)) in staging.iter().enumerate() {
        let slice = target.slice(..);
        map_readback_blocking(device, &slice, "replay")
            .with_context(|| format!("dispatch did not finish (waiting on {name})"))?;
        let data = slice.get_mapped_range();
        let data = &data[..*bytes as usize];
        results.insert(name.clone(), serde_json::json!(format!("{:016x}", digest(data))));
        if let Some(out) = &out {
            fs::create_dir_all(out)?;
            fs::write(out.join(format!("{index:03}_{name}.bin")), data)?;
        }
    }
    let dispatch_ms = dispatched.elapsed().as_secs_f64() * 1000.0;
    drop(staging);
    // `REPLAY_TIMED=n` then times n more dispatches, each submitted alone and
    // waited for, so the time excludes the readback copies above. They run on
    // the first dispatch's outputs; the digests above are unaffected.
    let kernel_ms = (0..env_usize("REPLAY_TIMED"))
        .map(|_| kernel.timed(gpu))
        .collect::<Result<Vec<_>>>()?;
    let memory_before = process_memory();
    // `REPLAY_INTERLEAVE=n` runs n rounds of: every `--also` kernel, each
    // timed alone, then the first kernel timed alone.
    let mut rounds = Vec::new();
    for _ in 0..env_usize("REPLAY_INTERLEAVE") {
        let mut other_ms = serde_json::Map::new();
        for other in &others {
            other_ms.insert(other.name.clone(), serde_json::json!(other.timed(gpu)?));
        }
        let ms = kernel.timed(gpu)?;
        rounds.push(serde_json::json!({ "others_ms": other_ms, "kernel_ms": ms }));
    }
    let kernel_after_ms = if rounds.is_empty() {
        Vec::new()
    } else {
        (0..env_usize("REPLAY_TIMED"))
            .map(|_| kernel.timed(gpu))
            .collect::<Result<Vec<_>>>()?
    };
    println!(
        "{}",
        serde_json::json!({
            "pipeline_create_ms": kernel.pipeline_ms,
            "dispatch_ms": dispatch_ms,
            "first_kernel_ms": first_kernel_ms,
            "ballast_mib": ballast.len() * 256,
            "kernel_ms": kernel_ms,
            "groups": kernel.groups,
            "interleave": rounds,
            "kernel_after_interleave_ms": kernel_after_ms,
            "memory_before_interleave": memory_before,
            "memory_after_interleave": process_memory(),
            "digests": results,
        })
    );
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("shader_dispatch_replay: {err:#}");
            ExitCode::FAILURE
        }
    }
}
