//! Creates one reflected compute pipeline and reports its host latency.
//!
//! This deliberately does not dispatch the shader. It isolates driver pipeline
//! compilation from compiler initialization so Slang optimization variants can
//! be compared without constructing every Lanius pipeline.

use std::{env, fs, process::ExitCode, time::Instant};

use anyhow::{Context, Result, anyhow};
use laniusc_compiler::{
    gpu::{
        device,
        passes_core::{bgls_from_reflection, pipeline_from_spirv_and_bgls},
    },
    reflection::parse_reflection_from_bytes,
};

fn run() -> Result<()> {
    let mut args = env::args_os().skip(1);
    let spv_path = args
        .next()
        .ok_or_else(|| anyhow!("usage: shader_pipeline_probe SHADER.spv SHADER.reflect.json"))?;
    let reflection_path = args
        .next()
        .ok_or_else(|| anyhow!("usage: shader_pipeline_probe SHADER.spv SHADER.reflect.json"))?;
    if args.next().is_some() {
        return Err(anyhow!(
            "usage: shader_pipeline_probe SHADER.spv SHADER.reflect.json"
        ));
    }

    let spirv = fs::read(&spv_path)
        .with_context(|| format!("read SPIR-V {}", spv_path.to_string_lossy()))?;
    let reflection_bytes = fs::read(&reflection_path)
        .with_context(|| format!("read reflection {}", reflection_path.to_string_lossy()))?;
    let reflection = parse_reflection_from_bytes(&reflection_bytes).map_err(anyhow::Error::msg)?;
    let gpu = device::global_result().map_err(|err| anyhow!(err.to_string()))?;
    let layouts = bgls_from_reflection(&gpu.device, &reflection)?;
    let layout_refs = layouts.iter().collect::<Vec<_>>();

    let started = Instant::now();
    let pipeline = pipeline_from_spirv_and_bgls(
        &gpu.device,
        "shader_pipeline_probe",
        "main",
        &spirv,
        &layout_refs,
    );
    let elapsed_ms = started.elapsed().as_secs_f64() * 1000.0;
    drop(pipeline);

    println!(
        "{}",
        serde_json::json!({
            "schema": "lanius.shader-pipeline-probe.v1",
            "spv": spv_path.to_string_lossy(),
            "reflection": reflection_path.to_string_lossy(),
            "spv_bytes": spirv.len(),
            "reflected_parameters": reflection.parameters.len(),
            "pipeline_create_ms": elapsed_ms,
        })
    );
    Ok(())
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprintln!("shader_pipeline_probe: {err:#}");
            ExitCode::FAILURE
        }
    }
}
