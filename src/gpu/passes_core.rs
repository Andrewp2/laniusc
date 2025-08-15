use std::{collections::HashMap, sync::Arc};

use anyhow::{Result, anyhow};
use log::warn;
use wgpu;

use crate::reflection::{
    EntryPointReflection,
    ParameterReflection,
    SlangReflection,
    get_thread_group_size,
    parse_reflection_from_bytes,
    slang_category_and_type_to_wgpu,
};

pub struct PassData {
    pub pipeline: Arc<wgpu::ComputePipeline>,
    pub bind_group_layouts: Vec<Arc<wgpu::BindGroupLayout>>,
    pub shader_id: String,
    pub thread_group_size: [u32; 3],
    pub reflection: Arc<SlangReflection>,
}

#[derive(Copy, Clone, Debug)]
pub enum DispatchDim {
    D1,
    D2,
}

#[derive(Copy, Clone, Debug)]
pub enum InputElements {
    Elements1D(u32),
    Elements2D(u32, u32),
}

pub fn bgls_from_reflection(
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

pub fn pipeline_from_spirv_and_bgls(
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

pub fn make_pass_data(
    device: &wgpu::Device,
    label: &str,
    entry: &str,
    spirv: &'static [u8],
    reflection_json: &'static [u8],
) -> Result<PassData> {
    let reflection: SlangReflection =
        parse_reflection_from_bytes(reflection_json).map_err(anyhow::Error::msg)?;
    let owned_bgls = bgls_from_reflection(device, &reflection)?;
    let bgl_refs: Vec<&wgpu::BindGroupLayout> = owned_bgls.iter().collect();
    let pipeline = pipeline_from_spirv_and_bgls(device, label, entry, spirv, &bgl_refs);
    let tgs = get_thread_group_size(&reflection).unwrap_or([1, 1, 1]);
    Ok(PassData {
        pipeline: Arc::new(pipeline),
        bind_group_layouts: owned_bgls.into_iter().map(Arc::new).collect(),
        shader_id: label.to_string(),
        thread_group_size: tgs,
        reflection: Arc::new(reflection),
    })
}

pub mod bind_group {
    use std::collections::HashMap;

    use anyhow::anyhow;
    use wgpu;

    use super::*;

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

pub trait Pass<Buffers, DebugOutput> {
    const NAME: &'static str;

    const DIM: DispatchDim;

    fn from_data(data: PassData) -> Self
    where
        Self: Sized;

    fn data(&self) -> &PassData;

    fn create_resource_map<'a>(
        &self,
        buffers: &'a Buffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>>;

    fn record_pass(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &Buffers,
        input: InputElements,
        timer: &mut Option<&mut crate::gpu::timer::GpuTimer>,
    ) -> Result<(), anyhow::Error> {
        device.push_error_scope(wgpu::ErrorFilter::Validation);

        let pd = self.data();
        let mut bind_groups = Vec::new();
        let resources = self.create_resource_map(buffers);
        for (set_idx, bgl) in pd.bind_group_layouts.iter().enumerate() {
            let bg = bind_group::create_bind_group_from_reflection(
                device,
                Some(Self::NAME),
                bgl,
                &pd.reflection,
                set_idx,
                &resources,
            )?;
            bind_groups.push(bg);
        }

        let [tgsx, tgsy, _tgsz] = pd.thread_group_size;
        let (gx, gy, gz) = match (Self::DIM, input) {
            (DispatchDim::D1, InputElements::Elements1D(n)) => {
                (((n + tgsx - 1) / tgsx).max(1), 1, 1)
            }
            (DispatchDim::D2, InputElements::Elements2D(w, h)) => {
                let wx = ((w + tgsx - 1) / tgsx).max(1);
                let hy = ((h + tgsy - 1) / tgsy).max(1);
                (wx, hy, 1)
            }

            (DispatchDim::D2, InputElements::Elements1D(n)) => {
                const MAX_PER_DIM: u32 = 65_535;
                let tiles_x = n.min(MAX_PER_DIM);
                let tiles_y = if n == 0 {
                    1
                } else {
                    (n + MAX_PER_DIM - 1) / MAX_PER_DIM
                };
                let wx = ((tiles_x + tgsx - 1) / tgsx).max(1);
                let hy = ((tiles_y + tgsy - 1) / tgsy).max(1);
                (wx, hy, 1)
            }
            _ => unreachable!("dimension/input mismatch"),
        };

        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(Self::NAME),
            timestamp_writes: None,
        });
        pass.set_pipeline(&pd.pipeline);
        for (i, bg) in bind_groups.iter().enumerate() {
            pass.set_bind_group(i as u32, bg, &[]);
        }
        pass.dispatch_workgroups(gx, gy, gz);
        drop(pass);

        if let Some(t) = timer {
            t.stamp(encoder, Self::NAME.to_string());
        }

        if let Some(err) = pollster::block_on(device.pop_error_scope()) {
            return Err(anyhow!("validation in pass {}: {err:?}", Self::NAME));
        }
        Ok(())
    }

    fn record_debug(
        &self,
        _device: &wgpu::Device,
        _encoder: &mut wgpu::CommandEncoder,
        _b: &Buffers,
        _dbg: &mut DebugOutput,
    ) {
        warn!("debug output not implemented for pass {}", Self::NAME);
    }
}
