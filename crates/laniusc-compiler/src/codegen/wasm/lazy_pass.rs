use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
    time::{Duration, Instant},
};

use anyhow::{Context, Result, anyhow};

use super::trace_wasm_codegen;
use crate::{
    gpu::{
        device,
        passes_core::{bgls_from_reflection, bind_group, pipeline_from_spirv_and_bgls},
    },
    reflection::{SlangReflection, parse_reflection_from_bytes},
};

pub(crate) struct LazyWasmPass {
    stage: &'static str,
    label: &'static str,
    entry: &'static str,
    spirv: Arc<Vec<u8>>,
    bind_group_layouts: Vec<Arc<wgpu::BindGroupLayout>>,
    reflection: Arc<SlangReflection>,
    pipeline: Mutex<Option<Arc<wgpu::ComputePipeline>>>,
    device: Arc<wgpu::Device>,
}

impl LazyWasmPass {
    pub(super) fn from_artifacts(
        device: &Arc<wgpu::Device>,
        stage: &'static str,
        label: &'static str,
        spv: &'static str,
        reflection: &'static str,
    ) -> Result<Self> {
        let spv_path = crate::shader_artifacts::artifact_path(spv);
        let reflection_path = crate::shader_artifacts::artifact_path(reflection);
        let spirv = std::fs::read(&spv_path)
            .map_err(|err| anyhow!("read shader SPIR-V {}: {err}", spv_path.display()))?;
        let reflection_json = std::fs::read(&reflection_path).map_err(|err| {
            anyhow!(
                "read shader reflection {}: {err}",
                reflection_path.display()
            )
        })?;
        let reflection: SlangReflection =
            parse_reflection_from_bytes(&reflection_json).map_err(anyhow::Error::msg)?;
        let bind_group_layouts = bgls_from_reflection(device, &reflection)?
            .into_iter()
            .map(Arc::new)
            .collect();
        Ok(Self {
            stage,
            label,
            entry: "main",
            spirv: Arc::new(spirv),
            bind_group_layouts,
            reflection: Arc::new(reflection),
            pipeline: Mutex::new(None),
            device: device.clone(),
        })
    }

    pub(super) fn pipeline(&self) -> Result<Arc<wgpu::ComputePipeline>> {
        let mut pipeline = self
            .pipeline
            .lock()
            .map_err(|_| anyhow!("WASM pass {} pipeline lock poisoned", self.stage))?;
        if let Some(pipeline) = pipeline.as_ref() {
            return Ok(pipeline.clone());
        }

        trace_wasm_codegen(&format!("{}.pipeline.start", self.stage));
        let start = Instant::now();
        let bgl_refs: Vec<&wgpu::BindGroupLayout> = self
            .bind_group_layouts
            .iter()
            .map(|layout| layout.as_ref())
            .collect();
        let created = pipeline_from_spirv_and_bgls(
            &self.device,
            self.label,
            self.entry,
            &self.spirv,
            &bgl_refs,
        );
        let end = Instant::now();
        let dt_ms = end.duration_since(start).as_secs_f64() * 1000.0;
        if crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false) {
            eprintln!(
                "[gpu_compile_host_timer] codegen.wasm.pipeline.{}: {:.3}ms",
                self.stage, dt_ms
            );
        }
        if crate::gpu::trace::enabled() {
            crate::gpu::trace::record_host_span(
                "host.wasm.pipeline",
                &format!("codegen.wasm.pipeline.{}", self.stage),
                start,
                end,
            );
        }
        trace_wasm_codegen(&format!("{}.pipeline.done", self.stage));
        let created = Arc::new(created);
        *pipeline = Some(created.clone());
        // Optional recovery mode for driver pipelines that take longer than a
        // compile timeout. Normal compilation defers cache serialization to
        // the owning CLI/daemon lifecycle so it never blocks a job phase.
        if end.duration_since(start) >= Duration::from_secs(1)
            && crate::gpu::env::env_bool_truthy("LANIUS_PIPELINE_CACHE_CHECKPOINT_SLOW", false)
        {
            device::persist_pipeline_cache_for_device(&self.device);
        }
        Ok(created)
    }
}

pub(crate) fn create_wasm_bind_group<'a>(
    device: &wgpu::Device,
    label: Option<&str>,
    pass: &LazyWasmPass,
    set_index: usize,
    bindings: &[(&str, wgpu::BindingResource<'a>)],
) -> Result<wgpu::BindGroup> {
    let resources: HashMap<String, wgpu::BindingResource<'a>> = bindings
        .iter()
        .map(|(name, resource)| ((*name).to_string(), resource.clone()))
        .collect();
    bind_group::create_bind_group_from_reflection(
        device,
        label,
        &pass.bind_group_layouts[set_index],
        &pass.reflection,
        set_index,
        &resources,
    )
    .with_context(|| {
        format!(
            "create WASM bind group {} for pass {}",
            label.unwrap_or("<unnamed>"),
            pass.stage
        )
    })
}
