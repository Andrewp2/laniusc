//! Replays one captured compute dispatch against a SPIR-V file.
//!
//! A capture directory comes from running the compiler with
//! `LANIUS_DEBUG_CAPTURE_PASS` (see `gpu/dispatch_capture.rs`). The
//! shader is loaded from disk, so patched SPIR-V variants of one kernel can
//! be compared on identical inputs without rebuilding the compiler. Reports
//! whether the dispatch finished within `LANIUS_READBACK_TIMEOUT_MS` and a
//! digest of every binding afterwards; `--out DIR` also saves the results.

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

const USAGE: &str =
    "usage: shader_dispatch_replay CAPTURE_DIR SHADER.spv SHADER.reflect.json [--out DIR]";

fn digest(bytes: &[u8]) -> u64 {
    bytes.iter().fold(0xcbf2_9ce4_8422_2325u64, |hash, byte| {
        (hash ^ u64::from(*byte)).wrapping_mul(0x100_0000_01b3)
    })
}

fn run() -> Result<()> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let (positional, out) = match args.iter().position(|arg| arg == "--out") {
        Some(at) => (
            &args[..at],
            Some(PathBuf::from(args.get(at + 1).ok_or_else(|| anyhow!(USAGE))?)),
        ),
        None => (&args[..], None),
    };
    let [capture, spv, reflection] = positional else {
        return Err(anyhow!(USAGE));
    };
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
    let reflection = parse_reflection_from_bytes(&fs::read(reflection)?).map_err(anyhow::Error::msg)?;
    let gpu = device::global_result().map_err(|err| anyhow!(err.to_string()))?;
    let device = &gpu.device;
    let layouts = bgls_from_reflection(device, &reflection)?;
    let layout_refs = layouts.iter().collect::<Vec<_>>();
    let started = Instant::now();
    let pipeline = pipeline_from_spirv_and_bgls(device, "replay", "main", &spirv, &layout_refs);
    let pipeline_ms = started.elapsed().as_secs_f64() * 1000.0;
    eprintln!("shader_dispatch_replay: pipeline created in {pipeline_ms:.1} ms");

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

    // `REPLAY_GROUPS_X=n` dispatches only the first n workgroups.
    let groups_x = env::var("REPLAY_GROUPS_X").ok().and_then(|v| v.parse().ok()).unwrap_or(groups[0]);
    let record_dispatch = |encoder: &mut wgpu::CommandEncoder| {
        let mut pass = encoder.begin_compute_pass(&Default::default());
        pass.set_pipeline(&pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        pass.dispatch_workgroups(groups_x, groups[1].max(1), groups[2].max(1));
    };
    let mut encoder = device.create_command_encoder(&Default::default());
    record_dispatch(&mut encoder);
    let mut staging = Vec::new();
    for (_, name, buffer, bytes) in &buffers {
        let target = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(name),
            size: buffer.size(),
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(buffer, 0, &target, 0, buffer.size());
        staging.push((name.clone(), target, *bytes));
    }
    let dispatched = Instant::now();
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
    let timed = env::var("REPLAY_TIMED").ok().and_then(|v| v.parse::<usize>().ok()).unwrap_or(0);
    let mut kernel_ms = Vec::with_capacity(timed);
    for _ in 0..timed {
        let mut encoder = device.create_command_encoder(&Default::default());
        record_dispatch(&mut encoder);
        let started = Instant::now();
        gpu.queue.submit(Some(encoder.finish()));
        device
            .poll(wgpu::PollType::wait_indefinitely())
            .map_err(|err| anyhow!("timed dispatch did not finish: {err}"))?;
        kernel_ms.push(started.elapsed().as_secs_f64() * 1000.0);
    }
    println!(
        "{}",
        serde_json::json!({
            "pipeline_create_ms": pipeline_ms,
            "dispatch_ms": dispatch_ms,
            "kernel_ms": kernel_ms,
            "groups": [groups_x, groups[1], groups[2]],
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
