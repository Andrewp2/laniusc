//! One warmed, complete native build bounded by the Nsight Graphics SDK.
//! Launched by tools/run_nsight_gpu_trace.sh; see docs/nsight-gpu-trace.md.

use std::{
    ffi::{CString, c_char, c_int, c_void},
    fs,
    path::PathBuf,
    time::Instant,
};

use anyhow::{Context, Result, anyhow, ensure};
use laniusc_compiler::{
    compiler::{
        EntrySourceRoots,
        GpuCompiler,
        NativeLinkOptions,
        frontend_check_count,
        load_entry_path_manifest_with_source_roots,
    },
    gpu::device,
};

#[link(name = "dl")]
unsafe extern "C" {
    fn dlopen(filename: *const c_char, flags: c_int) -> *mut c_void;
    fn dlsym(handle: *mut c_void, symbol: *const c_char) -> *mut c_void;
    fn dup2(oldfd: c_int, newfd: c_int) -> c_int;
}

struct Capture {
    begin: unsafe extern "C" fn() -> c_int,
    end: unsafe extern "C" fn() -> c_int,
}

impl Capture {
    fn load() -> Result<Self> {
        let path = CString::new(
            std::env::var("LANIUS_NGFX_CONTROL_LIBRARY")
                .context("launch with tools/run_nsight_gpu_trace.sh")?,
        )?;
        // The wrapper builds this bridge from the installed NVIDIA SDK.
        // Keep it loaded for the process lifetime, including trace export.
        unsafe {
            let handle = dlopen(path.as_ptr(), 2); // RTLD_NOW
            ensure!(!handle.is_null(), "could not load NGFX SDK bridge");
            let begin = dlsym(handle, c"lanius_ngfx_begin".as_ptr());
            let end = dlsym(handle, c"lanius_ngfx_end".as_ptr());
            ensure!(
                !begin.is_null() && !end.is_null(),
                "incomplete NGFX SDK bridge"
            );
            Ok(Self {
                begin: std::mem::transmute::<*mut c_void, unsafe extern "C" fn() -> c_int>(begin),
                end: std::mem::transmute::<*mut c_void, unsafe extern "C" fn() -> c_int>(end),
            })
        }
    }
}

fn drain(gpu: &device::GpuDevice) -> Result<()> {
    gpu.device.poll(wgpu::PollType::wait_indefinitely())?;
    Ok(())
}

fn marker(gpu: &device::GpuDevice, pipeline: &wgpu::ComputePipeline, name: &str) -> Result<()> {
    let mut encoder = gpu.device.create_command_encoder(&Default::default());
    {
        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(name),
            timestamp_writes: None,
        });
        pass.set_pipeline(pipeline);
        pass.dispatch_workgroups(1, 1, 1);
    }
    gpu.queue.submit([encoder.finish()]);
    drain(gpu)
}

fn strings(value: &serde_json::Value, name: &str) -> Result<Vec<String>> {
    let Some(items) = value.get(name) else {
        return Ok(Vec::new());
    };
    items
        .as_array()
        .context("expected array")?
        .iter()
        .map(|item| item.as_str().map(str::to_owned).context("expected string"))
        .collect()
}

fn run() -> Result<()> {
    let mut args = std::env::args_os().skip(1);
    let request_path = args
        .next()
        .context("usage: nsight_compile REQUEST.json OUTPUT [WARMUPS=2]")?;
    let output = PathBuf::from(args.next().context("missing OUTPUT")?);
    let warmups = args
        .next()
        .map(|arg| arg.to_string_lossy().parse::<usize>())
        .transpose()?
        .unwrap_or(2);
    ensure!(
        warmups > 0 && args.next().is_none(),
        "at least one warmup is required"
    );
    let control = Capture::load()?;
    let token = std::env::var("LANIUS_NGFX_CAPTURE_TOKEN")?;
    let completion = PathBuf::from(
        std::env::var_os("LANIUS_NGFX_COMPLETION_FILE").context("missing completion path")?,
    );
    let json: serde_json::Value = serde_json::from_slice(&fs::read(request_path)?)?;
    let request = json.get("request").unwrap_or(&json);
    let entry = request["input"]
        .as_str()
        .context("request.input is required")?;
    let roots = EntrySourceRoots {
        stdlib_root: request["stdlib_root"].as_str().map(Into::into),
        user_roots: strings(request, "source_roots")?
            .into_iter()
            .map(Into::into)
            .collect(),
    };
    let native = NativeLinkOptions {
        libraries: strings(request, "native_libraries")?,
        objects: strings(request, "native_objects")?
            .into_iter()
            .map(Into::into)
            .collect(),
        ..Default::default()
    };
    let manifest = load_entry_path_manifest_with_source_roots(entry, &roots)?;
    let compiler = pollster::block_on(GpuCompiler::new())?;
    let gpu = device::global_result().map_err(|err| anyhow!(err.to_string()))?;
    // Prepare markers before warming up, so pipeline creation is outside the capture.
    let shader = gpu
        .device
        .create_shader_module(wgpu::ShaderModuleDescriptor {
            label: Some("capture boundary"),
            source: wgpu::ShaderSource::Wgsl("@compute @workgroup_size(1) fn main() {}".into()),
        });
    let pipeline = gpu
        .device
        .create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
            label: Some("capture boundary"),
            layout: None,
            module: &shader,
            entry_point: Some("main"),
            compilation_options: Default::default(),
            cache: None,
        });
    for warmup in 0..warmups {
        pollster::block_on(compiler.compile_path_manifest_with_native_link(&manifest, &native))?;
        eprintln!("nsight_compile: warmup {} complete", warmup + 1);
    }
    drain(gpu)?;
    let sdk_start = unsafe { (control.begin)() };
    ensure!(sdk_start == 0, "NGFX start failed: {sdk_start}");
    let started = Instant::now();
    marker(gpu, &pipeline, &format!("lanius.capture.{token}.begin"))?;
    let before = frontend_check_count();
    let compile_started = Instant::now();
    let bytes =
        pollster::block_on(compiler.compile_path_manifest_with_native_link(&manifest, &native))?;
    let compile_ms = compile_started.elapsed().as_secs_f64() * 1000.0;
    let frontend_recordings = frontend_check_count() - before;
    let report = pollster::block_on(compiler.native_monomorphization_report())
        .context("missing monomorphization report")?;
    ensure!(
        frontend_recordings as usize >= report.units as usize,
        "capture reused original compilation results"
    );
    fs::write(&output, &bytes)?;
    marker(gpu, &pipeline, &format!("lanius.capture.{token}.end"))?;
    // The link and output readback have completed, and every queue has drained.
    let capture_elapsed_ms = started.elapsed().as_secs_f64() * 1000.0;
    let sdk_stop = unsafe { (control.end)() };
    ensure!(
        sdk_stop == 0,
        "NGFX stopped before workload completion: {sdk_stop}"
    );
    let receipt = serde_json::json!({
        "schema": "lanius.nsight-workload.v1", "token": token,
        "complete": true, "sdk_start": sdk_start, "sdk_stop": sdk_stop,
        "capture_elapsed_ms": capture_elapsed_ms, "compile_ms": compile_ms,
        "warmups": warmups, "input": entry, "output": output, "bytes": bytes.len(),
        "frontend_recordings": frontend_recordings, "units": report.units,
        "instances": report.projection.instances, "instance_objects": report.instance_objects,
        "scope": "full native compile, including all original units, instantiation, lowering and link",
    });
    let temporary = completion.with_extension("tmp");
    fs::write(&temporary, serde_json::to_vec_pretty(&receipt)?)?;
    fs::rename(temporary, completion)?;
    // ngfx exports asynchronously and terminates its target when done. Exiting
    // here would tear down the device before collection has finished.
    loop {
        std::thread::park();
    }
}

fn main() -> Result<()> {
    // ngfx does not forward target stderr. Keep diagnostics even when it kills
    // the target after capture, or a panic occurs before the receipt is written.
    if let Some(path) = std::env::var_os("LANIUS_NGFX_COMPLETION_FILE") {
        use std::os::fd::AsRawFd;
        let log = fs::File::create(PathBuf::from(path).with_file_name("workload.log"))?;
        ensure!(
            unsafe { dup2(log.as_raw_fd(), 2) } >= 0,
            "redirect workload stderr"
        );
    }
    let result = run();
    if let Err(error) = &result {
        if let Some(path) = std::env::var_os("LANIUS_NGFX_COMPLETION_FILE") {
            let _ = fs::write(
                PathBuf::from(path).with_file_name("workload-error.txt"),
                format!("{error:#}\n"),
            );
        }
    }
    result
}
