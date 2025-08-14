use std::sync::Arc;

// src/lexer/gpu/passes/mod.rs
use anyhow::{Result, anyhow};
use encase::ShaderType;

use crate::{
    lexer::gpu::{
        buffers::GpuBuffers,
        debug::{DebugBuffer, DebugOutput},
        timer::GpuTimer,
    },
    reflection::{
        EntryPointReflection,
        ParameterReflection,
        SlangReflection,
        parse_reflection_from_bytes,
        slang_category_and_type_to_wgpu,
    },
};

// ---------- export concrete pass modules ----------
pub mod apply_block_prefix_downsweep;
pub mod build_tokens;
pub mod compact_boundaries_all;
pub mod compact_boundaries_kept;
pub mod finalize_boundaries_and_seed;
pub mod retag_calls_and_arrays;
pub mod scan_block_summaries_inclusive;
pub mod scan_inblock_inclusive_pass;
pub mod sum_apply_block_prefix_downsweep_pairs;
pub mod sum_inblock_pairs;
pub mod sum_scan_block_totals_inclusive;

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub(super) struct ScanParams {
    pub stride: u32,
    pub use_ping_as_src: u32,
}

// ---------------- reflection/bgl helpers ----------------

fn bgls_from_reflection(
    device: &wgpu::Device,
    reflection: &SlangReflection,
) -> Result<Vec<wgpu::BindGroupLayout>> {
    let ep: &EntryPointReflection = reflection
        .entry_points
        .iter()
        .find(|e| e.stage.as_deref() == Some("compute"))
        .ok_or_else(|| anyhow!("no compute entry point found in reflection"))?;

    if let Some(layout) = ep.program_layout.as_ref() {
        let mut out = Vec::with_capacity(layout.parameters.len());
        for set in &layout.parameters {
            let entries: Vec<_> = set
                .parameters
                .iter()
                .filter_map(|p| {
                    let ty = slang_category_and_type_to_wgpu(p, &p.ty)?;
                    let idx = p.binding.index?;
                    Some(wgpu::BindGroupLayoutEntry {
                        binding: idx,
                        visibility: wgpu::ShaderStages::COMPUTE,
                        ty,
                        count: None,
                    })
                })
                .collect();
            out.push(
                device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
                    label: Some("reflected-bgl"),
                    entries: &entries,
                }),
            );
        }
        return Ok(out);
    }

    let entries: Vec<_> = reflection
        .parameters
        .iter()
        .filter_map(|p| {
            let ty = slang_category_and_type_to_wgpu(p, &p.ty)?;
            let idx = p.binding.index?;
            Some(wgpu::BindGroupLayoutEntry {
                binding: idx,
                visibility: wgpu::ShaderStages::COMPUTE,
                ty,
                count: None,
            })
        })
        .collect();

    Ok(vec![device.create_bind_group_layout(
        &wgpu::BindGroupLayoutDescriptor {
            label: Some("reflected-bgl-flat"),
            entries: &entries,
        },
    )])
}

fn pipeline_from_spirv_and_bgls(
    device: &wgpu::Device,
    label: &str,
    entry: &str,
    spirv: &'static [u8],
    bgls: &[&wgpu::BindGroupLayout],
) -> wgpu::ComputePipeline {
    let module = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some(label),
        source: wgpu::util::make_spirv(spirv),
    });
    let pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: Some(&format!("pl_{label}")),
        bind_group_layouts: bgls,
        push_constant_ranges: &[],
    });
    device.create_compute_pipeline(&wgpu::ComputePipelineDescriptor {
        label: Some(label),
        layout: Some(&pl),
        module: &module,
        entry_point: Some(entry),
        compilation_options: wgpu::PipelineCompilationOptions::default(),
        cache: None,
    })
}

/// Build `PassData` (pipeline + all BGLs + reflection + TGS) for a compute shader.
pub(crate) fn make_pass_data(
    device: &wgpu::Device,
    label: &str,
    entry: &str,
    spirv: &'static [u8],
    reflection_json: &'static [u8],
) -> Result<PassData> {
    let reflection: SlangReflection =
        parse_reflection_from_bytes(reflection_json).map_err(anyhow::Error::msg)?;

    // Own the BGLs so we can both create the pipeline and also store them.
    let owned_bgls = bgls_from_reflection(device, &reflection)?;
    let bgl_refs: Vec<&wgpu::BindGroupLayout> = owned_bgls.iter().collect();

    let pipeline = pipeline_from_spirv_and_bgls(device, label, entry, spirv, &bgl_refs);
    let tgs = crate::reflection::get_thread_group_size(&reflection).unwrap_or([1, 1, 1]);

    Ok(PassData {
        pipeline: Arc::new(pipeline),
        bind_group_layouts: owned_bgls.into_iter().map(Arc::new).collect(),
        shader_id: label.to_string(),
        thread_group_size: tgs,
        reflection: Arc::new(reflection),
    })
}

// ---------------- small bind-group utility (name→resource) ----------------

pub(crate) mod bind_group {
    use std::collections::HashMap;

    use super::*;

    /// Build a bind group for `set_index` using parameter names from reflection
    /// and a name→BindingResource map provided by the pass.
    pub fn create_bind_group_from_reflection<'a>(
        device: &wgpu::Device,
        label: Option<&str>,
        bgl: &Arc<wgpu::BindGroupLayout>,
        reflection: &Arc<SlangReflection>,
        set_index: usize,
        resources: &HashMap<String, wgpu::BindingResource<'a>>,
    ) -> Result<wgpu::BindGroup> {
        let params: Vec<ParameterReflection> = if let Some(pl) = reflection
            .entry_points
            .iter()
            .find(|e| e.stage.as_deref() == Some("compute"))
            .and_then(|ep| ep.program_layout.clone())
        {
            pl.parameters
                .get(set_index)
                .map(|s| s.parameters.clone())
                .unwrap_or_default()
        } else {
            reflection.parameters.clone()
        };

        let mut entries = Vec::<wgpu::BindGroupEntry>::new();
        for p in &params {
            if let (Some(idx), Some(_ty)) = (p.binding.index, p.ty.kind.as_ref()) {
                if let Some(res) = resources.get(&p.name) {
                    entries.push(wgpu::BindGroupEntry {
                        binding: idx,
                        resource: res.clone(),
                    });
                } else {
                    return Err(anyhow!("no resource provided for '{}'", p.name));
                }
            }
        }

        Ok(device.create_bind_group(&wgpu::BindGroupDescriptor {
            label,
            layout: bgl,
            entries: &entries,
        }))
    }
}

// ---------------- core Pass trait ----------------

pub struct PassData {
    pub pipeline: Arc<wgpu::ComputePipeline>,
    /// One layout per descriptor set (set = index in this vec).
    pub bind_group_layouts: Vec<Arc<wgpu::BindGroupLayout>>,
    pub shader_id: String,
    pub thread_group_size: [u32; 3],
    pub reflection: Arc<SlangReflection>,
}

#[derive(Copy, Clone)]
pub enum DispatchDim {
    D1,
}

#[derive(Copy, Clone)]
pub enum InputElements {
    Elements1D(u32),
    #[allow(dead_code)]
    Elements2D(u32, u32),
}

pub trait Pass {
    const NAME: &'static str = "";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self;
    fn data(&self) -> &PassData;

    /// Build the name→resource map for this pass.
    fn create_resource_map<'a>(
        &self,
        buffers: &'a GpuBuffers,
    ) -> std::collections::HashMap<String, wgpu::BindingResource<'a>>;

    /// Default recording: bind **all** sets reflected by the shader, then dispatch.
    /// If `timer` is provided, this stamps a GPU timestamp after the dispatch.
    fn record_pass(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &GpuBuffers,
        _debug_output: &mut DebugOutput,
        input: InputElements,
        timer: Option<&mut GpuTimer>,
    ) {
        let dispatch = match (Self::DIM, input) {
            (DispatchDim::D1, InputElements::Elements1D(n)) => self.get_dispatch_size_1d(n),
            _ => unreachable!("dimension/input mismatch"),
        };

        let resources = self.create_resource_map(buffers);
        let pass_data = self.data();

        // Create a bind group for every set the reflection reports.
        let mut bind_groups = Vec::<wgpu::BindGroup>::new();
        for (set_index, bgl) in pass_data.bind_group_layouts.iter().enumerate() {
            let bg = bind_group::create_bind_group_from_reflection(
                device,
                Some(Self::NAME),
                bgl,
                &pass_data.reflection,
                set_index,
                &resources,
            )
            .unwrap_or_else(|e| {
                panic!(
                    "Failed create bind group for {} (set {}): {}",
                    pass_data.shader_id, set_index, e
                )
            });
            bind_groups.push(bg);
        }

        {
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some(Self::NAME),
                timestamp_writes: None,
            });
            pass.set_pipeline(&pass_data.pipeline);
            for (i, bg) in bind_groups.iter().enumerate() {
                pass.set_bind_group(i as u32, bg, &[]);
            }
            pass.dispatch_workgroups(dispatch.0, dispatch.1, dispatch.2);
        }
        if let Some(t) = timer {
            t.stamp(encoder, Self::NAME.to_string());
        }
        #[cfg(feature = "gpu-debug")]
        {
            self.record_debug(device, encoder, buffers, _debug_output);
        }
    }

    /// Optional: emit staging copies for debug snapshots.
    #[allow(dead_code)]
    fn record_debug(
        &self,
        _device: &wgpu::Device,
        _encoder: &mut wgpu::CommandEncoder,
        _bufs: &GpuBuffers,
        _dbg: &mut DebugOutput,
    ) {
        log::warn!("{}: no debug recording implemented", Self::NAME);
    }

    /// Default: ceil_div(input, tgs_x)
    fn get_dispatch_size_1d(&self, n_elements: u32) -> (u32, u32, u32) {
        let tgs = self.data().thread_group_size[0].max(1);
        let groups = (n_elements + tgs - 1) / tgs;
        (groups, 1, 1)
    }
}

// ---------- debug helpers each pass uses ----------
#[allow(dead_code)]
impl DebugBuffer {
    pub fn set_from_copy(
        &mut self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        src: &wgpu::Buffer,
        label: &'static str,
        size: usize,
    ) {
        let b = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: size as u64,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        encoder.copy_buffer_to_buffer(src, 0, &b, 0, size as u64);
        *self = DebugBuffer {
            label,
            buffer: Some(b),
            byte_len: size,
        };
    }
}
