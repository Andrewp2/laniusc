use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{BindGroupCache, PassData, record_or_defer_compute_direct},
    parser::buffers::{BracketsPairRadixStep, ParserBuffers},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Parameters for one stable bracket-pair radix byte.
pub struct Params {
    pub n_sc: u32,
    pub n_layers: u32,
    pub n_blocks: u32,
    pub key_step: u32,
}

macro_rules! radix_pass {
    ($name:ident, $label:literal, $shader:literal) => {
        struct $name {
            data: PassData,
        }
        crate::gpu::passes_core::impl_static_shader_pass!(
            $name,
            label: $label,
            shader: $shader
        );
    };
}

radix_pass!(
    PairRadixHistogramPass,
    "brackets_pair_radix_histogram",
    "parser/brackets/pair_radix_histogram"
);
radix_pass!(
    PairRadixPrefixPass,
    "brackets_pair_radix_prefix",
    "parser/brackets/pair_radix_prefix"
);
radix_pass!(
    PairRadixBasesPass,
    "brackets_pair_radix_bases",
    "parser/brackets/pair_radix_bases"
);

struct PairRadixScatterPass {
    data: PassData,
}

const WARP_HISTOGRAM_STORAGE_BYTES: u32 = 33 * 1024;

fn pair_radix_scatter_shader(max_workgroup_storage_bytes: u32) -> &'static str {
    if max_workgroup_storage_bytes >= WARP_HISTOGRAM_STORAGE_BYTES {
        "parser/brackets/pair_radix_scatter"
    } else {
        "parser/brackets/pair_radix_scatter_prefix"
    }
}

impl PairRadixScatterPass {
    fn new(device: &wgpu::Device) -> Result<Self> {
        let shader = pair_radix_scatter_shader(device.limits().max_compute_workgroup_storage_size);
        Ok(Self {
            data: crate::gpu::passes_core::make_pass_data_from_shader_key(
                device,
                "brackets_pair_radix_scatter",
                "main",
                shader,
            )?,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scatter_pipeline_respects_exact_workgroup_storage_boundary() {
        assert_eq!(
            pair_radix_scatter_shader(WARP_HISTOGRAM_STORAGE_BYTES - 1),
            "parser/brackets/pair_radix_scatter_prefix"
        );
        assert_eq!(
            pair_radix_scatter_shader(WARP_HISTOGRAM_STORAGE_BYTES),
            "parser/brackets/pair_radix_scatter"
        );
    }
}

/// Stable GPU radix sorter for bracket events by `(layer, push/pop)`.
pub struct BracketsPairRadixPass {
    histogram: PairRadixHistogramPass,
    prefix: PairRadixPrefixPass,
    bases: PairRadixBasesPass,
    scatter: PairRadixScatterPass,
}

impl BracketsPairRadixPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            histogram: PairRadixHistogramPass::new(device)?,
            prefix: PairRadixPrefixPass::new(device)?,
            bases: PairRadixBasesPass::new(device)?,
            scatter: PairRadixScatterPass::new(device)?,
        })
    }

    pub fn record_sort(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let blocks = buffers.b_n_blocks.max(1);
        let groups = (blocks.min(65_535), blocks.div_ceil(65_535), 1);
        for step in &buffers.b_pair_radix_steps {
            let (order_in, order_out) = if step.read_from_pushes {
                (&buffers.b_pushes_by_layer, &buffers.b_pops_by_layer)
            } else {
                (&buffers.b_pops_by_layer, &buffers.b_pushes_by_layer)
            };
            self.record_histogram(device, encoder, buffers, step, order_in, groups, cache)?;
            self.record_prefix(device, encoder, buffers, step, cache)?;
            self.record_bases(device, encoder, buffers, step, cache)?;
            self.record_scatter(
                device, encoder, buffers, step, order_in, order_out, groups, cache,
            )?;
        }
        Ok(())
    }

    fn make_bind_group(
        cache: &mut BindGroupCache,
        device: &wgpu::Device,
        label: &str,
        pass: &PassData,
        resources: HashMap<String, wgpu::BindingResource<'_>>,
    ) -> Result<std::sync::Arc<wgpu::BindGroup>> {
        Ok(cache
            .reflected_for_pass_data(device, label, pass, &resources)?
            .into_iter()
            .next()
            .expect("bracket radix pass must have one bind group"))
    }

    fn record_histogram(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        step: &BracketsPairRadixStep,
        order_in: &crate::gpu::buffers::LaniusBuffer<u32>,
        groups: (u32, u32, u32),
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let bg = Self::make_bind_group(
            cache,
            device,
            &format!("brackets_pair_radix_histogram_{}", step.key_step),
            &self.histogram.data,
            HashMap::from([
                ("gParams".into(), step.params.as_entire_binding()),
                (
                    "partial_parse_status".into(),
                    b.partial_parse_status.as_entire_binding(),
                ),
                ("depths_out".into(), b.depths_out.as_entire_binding()),
                ("sc_stream".into(), b.out_sc.as_entire_binding()),
                ("layer".into(), b.b_layer.as_entire_binding()),
                ("order_in".into(), order_in.as_entire_binding()),
                (
                    "radix_block_histogram".into(),
                    b.b_pair_radix_block_histogram.as_entire_binding(),
                ),
            ]),
        )?;
        record_or_defer_compute_direct(
            encoder,
            &self.histogram.data,
            &bg,
            "brackets_pair_radix_histogram",
            groups,
        );
        Ok(())
    }

    fn record_prefix(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        step: &BracketsPairRadixStep,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let bg = Self::make_bind_group(
            cache,
            device,
            &format!("brackets_pair_radix_prefix_{}", step.key_step),
            &self.prefix.data,
            HashMap::from([
                ("gParams".into(), step.params.as_entire_binding()),
                (
                    "partial_parse_status".into(),
                    b.partial_parse_status.as_entire_binding(),
                ),
                ("depths_out".into(), b.depths_out.as_entire_binding()),
                (
                    "radix_block_histogram".into(),
                    b.b_pair_radix_block_histogram.as_entire_binding(),
                ),
                (
                    "radix_block_bucket_prefix".into(),
                    b.b_pair_radix_block_bucket_prefix.as_entire_binding(),
                ),
                (
                    "radix_bucket_total".into(),
                    b.b_pair_radix_bucket_total.as_entire_binding(),
                ),
            ]),
        )?;
        record_or_defer_compute_direct(
            encoder,
            &self.prefix.data,
            &bg,
            "brackets_pair_radix_prefix",
            (256, 1, 1),
        );
        Ok(())
    }

    fn record_bases(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        step: &BracketsPairRadixStep,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let bg = Self::make_bind_group(
            cache,
            device,
            &format!("brackets_pair_radix_bases_{}", step.key_step),
            &self.bases.data,
            HashMap::from([
                ("gParams".into(), step.params.as_entire_binding()),
                (
                    "partial_parse_status".into(),
                    b.partial_parse_status.as_entire_binding(),
                ),
                ("depths_out".into(), b.depths_out.as_entire_binding()),
                (
                    "radix_bucket_total".into(),
                    b.b_pair_radix_bucket_total.as_entire_binding(),
                ),
                (
                    "radix_bucket_base".into(),
                    b.b_pair_radix_bucket_base.as_entire_binding(),
                ),
            ]),
        )?;
        record_or_defer_compute_direct(
            encoder,
            &self.bases.data,
            &bg,
            "brackets_pair_radix_bases",
            (1, 1, 1),
        );
        Ok(())
    }

    #[allow(clippy::too_many_arguments)]
    fn record_scatter(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        b: &ParserBuffers,
        step: &BracketsPairRadixStep,
        order_in: &crate::gpu::buffers::LaniusBuffer<u32>,
        order_out: &crate::gpu::buffers::LaniusBuffer<u32>,
        groups: (u32, u32, u32),
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let bg = Self::make_bind_group(
            cache,
            device,
            &format!("brackets_pair_radix_scatter_{}", step.key_step),
            &self.scatter.data,
            HashMap::from([
                ("gParams".into(), step.params.as_entire_binding()),
                (
                    "partial_parse_status".into(),
                    b.partial_parse_status.as_entire_binding(),
                ),
                ("depths_out".into(), b.depths_out.as_entire_binding()),
                ("sc_stream".into(), b.out_sc.as_entire_binding()),
                ("layer".into(), b.b_layer.as_entire_binding()),
                ("order_in".into(), order_in.as_entire_binding()),
                (
                    "radix_bucket_base".into(),
                    b.b_pair_radix_bucket_base.as_entire_binding(),
                ),
                (
                    "radix_block_bucket_prefix".into(),
                    b.b_pair_radix_block_bucket_prefix.as_entire_binding(),
                ),
                ("order_out".into(), order_out.as_entire_binding()),
                (
                    "slot_for_index".into(),
                    b.b_slot_for_index.as_entire_binding(),
                ),
            ]),
        )?;
        record_or_defer_compute_direct(
            encoder,
            &self.scatter.data,
            &bg,
            "brackets_pair_radix_scatter",
            groups,
        );
        Ok(())
    }
}
