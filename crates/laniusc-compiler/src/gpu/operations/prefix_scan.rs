use anyhow::{Result, anyhow};

use super::{record_direct, record_indirect};
use crate::gpu::{
    buffers::{CapacityBufferCache, LaniusBuffer, TrackedBufferView, uniform_from_val},
    compiler_graph::{
        PrefixScanGraphPasses,
        PrefixScanPairSpec,
        PrefixScanResources,
        PrefixScanSpec,
        PrefixScanWorkspace,
    },
    kernels::KernelRegistry,
    passes_core::{ComputePassBatch, PassData, bind_group},
    resource_registry::ResourceMap,
    scan::{
        HierarchicalScanLevel,
        PrefixScanHierarchyParams,
        PrefixScanParams,
        hierarchical_scan_levels,
    },
};

#[derive(Clone, Copy)]
struct PrefixScanPasses<'a> {
    local: &'a PassData,
    hierarchy_up: &'a PassData,
    hierarchy_down: &'a PassData,
    apply: &'a PassData,
}

fn standard_passes(kernels: &KernelRegistry) -> PrefixScanPasses<'_> {
    PrefixScanPasses {
        local: kernels.kernel("scan/counted/00_local"),
        hierarchy_up: kernels.kernel("scan/counted/01_hierarchy_up"),
        hierarchy_down: kernels.kernel("scan/counted/02_hierarchy_down"),
        apply: kernels.kernel("scan/counted/02_apply"),
    }
}

fn scan_uniform<T>(
    device: &wgpu::Device,
    reusable: Option<(&wgpu::Queue, &CapacityBufferCache)>,
    label: &str,
    value: &T,
) -> LaniusBuffer<T>
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    match reusable {
        Some((queue, cache)) => cache.uniform(device, queue, label, value),
        None => uniform_from_val(device, label, value),
    }
}

pub(crate) type PrefixScanBuffers<'a> = PrefixScanResources<TrackedBufferView<'a>>;

struct HierarchyStep {
    _params: LaniusBuffer<PrefixScanHierarchyParams>,
    group: wgpu::BindGroup,
    work_items: u32,
}

pub(crate) struct PrefixScanOperation {
    label: &'static str,
    pair_passes: Option<PrefixScanGraphPasses>,
    passes: [PassData; 4],
    dispatch_args: LaniusBuffer<u32>,
    _params: LaniusBuffer<PrefixScanParams>,
    local: wgpu::BindGroup,
    up: Vec<HierarchyStep>,
    down: Vec<HierarchyStep>,
    apply: wgpu::BindGroup,
}

impl PrefixScanOperation {
    pub(crate) fn from_pair_spec(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        resources: &ResourceMap<'_>,
        spec: PrefixScanPairSpec,
    ) -> Result<(Self, Self)> {
        resources.validate_graph_passes_if_present(spec.passes.names())?;
        let passes = standard_passes(kernels);
        let mut left = Self::from_resource_names_with_passes(
            device,
            spec.left_label,
            passes,
            resources,
            spec.left,
        )?;
        let mut right = Self::from_resource_names_with_passes(
            device,
            spec.right_label,
            passes,
            resources,
            spec.right,
        )?;
        left.pair_passes = Some(spec.passes);
        right.pair_passes = Some(spec.passes);
        Ok((left, right))
    }

    pub(crate) fn from_spec(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        resources: &ResourceMap<'_>,
        spec: PrefixScanSpec,
    ) -> Result<Self> {
        resources.validate_graph_passes_if_present(spec.passes.names())?;
        Self::from_resource_names_with_passes(
            device,
            spec.passes.local,
            standard_passes(kernels),
            resources,
            spec.resources,
        )
    }

    pub(crate) fn with_reusable_workspace(
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        cache: &CapacityBufferCache,
        kernels: &KernelRegistry,
        label: &'static str,
        params: PrefixScanParams,
        count: TrackedBufferView<'_>,
        dispatch_args: TrackedBufferView<'_>,
        input: TrackedBufferView<'_>,
        output_prefix: TrackedBufferView<'_>,
        total: TrackedBufferView<'_>,
        workspace: PrefixScanWorkspace<&LaniusBuffer<u32>>,
    ) -> Result<Self> {
        Self::new(
            device,
            Some((queue, cache)),
            label,
            params,
            standard_passes(kernels),
            PrefixScanBuffers {
                count,
                dispatch_args,
                input,
                output_prefix,
                total,
                local_prefix: workspace.local_prefix.into(),
                block_sum: workspace.block_sum.into(),
                block_prefix: workspace.block_prefix.into(),
                hierarchy: workspace.hierarchy.into(),
            },
        )
    }

    pub(crate) fn from_resource_names(
        device: &wgpu::Device,
        label: &'static str,
        kernels: &KernelRegistry,
        resources: &ResourceMap<'_>,
        names: PrefixScanResources<&str>,
    ) -> Result<Self> {
        Self::from_resource_names_with_passes(
            device,
            label,
            standard_passes(kernels),
            resources,
            names,
        )
    }

    fn from_resource_names_with_passes(
        device: &wgpu::Device,
        label: &'static str,
        passes: PrefixScanPasses<'_>,
        resources: &ResourceMap<'_>,
        names: PrefixScanResources<&str>,
    ) -> Result<Self> {
        let buffer = |name| resources.tracked_view(name);
        let n_items = resources.logical_u32_count(names.input)?;
        Self::new(
            device,
            None,
            label,
            PrefixScanParams {
                n_items,
                n_blocks: n_items.div_ceil(256).max(1),
                scan_step: 0,
            },
            passes,
            PrefixScanBuffers {
                count: buffer(names.count)?,
                input: buffer(names.input)?,
                output_prefix: buffer(names.output_prefix)?,
                total: buffer(names.total)?,
                dispatch_args: buffer(names.dispatch_args)?,
                local_prefix: buffer(names.local_prefix)?,
                block_sum: buffer(names.block_sum)?,
                block_prefix: buffer(names.block_prefix)?,
                hierarchy: buffer(names.hierarchy)?,
            },
        )
    }

    fn new(
        device: &wgpu::Device,
        reusable: Option<(&wgpu::Queue, &CapacityBufferCache)>,
        label: &'static str,
        params: PrefixScanParams,
        passes: PrefixScanPasses<'_>,
        buffers: PrefixScanBuffers<'_>,
    ) -> Result<Self> {
        let levels = hierarchical_scan_levels(params.n_blocks);
        let params_buffer = scan_uniform(device, reusable, &format!("{label}.params"), &params);
        let bind =
            |suffix: &str, pass: &PassData, bindings: &[(&str, wgpu::BindingResource<'_>)]| {
                bind_group::create_bind_group_from_bindings(
                    device,
                    Some(&format!("{label}.{suffix}")),
                    pass,
                    0,
                    bindings,
                )
            };
        let local = bind(
            "local",
            passes.local,
            &[
                ("gScan", params_buffer.as_entire_binding()),
                ("scan_count", buffers.count.as_entire_binding()),
                ("scan_input", buffers.input.as_entire_binding()),
                (
                    "scan_local_prefix",
                    buffers.local_prefix.as_entire_binding(),
                ),
                ("scan_block_sum", buffers.block_sum.as_entire_binding()),
            ],
        )?;
        let hierarchy = |suffix,
                         pass,
                         index,
                         level: HierarchicalScanLevel,
                         parent: Option<HierarchicalScanLevel>|
         -> Result<HierarchyStep> {
            let level_params = scan_uniform(
                device,
                reusable,
                &format!("{label}.{suffix}.{index}.params"),
                &PrefixScanHierarchyParams {
                    n_items: params.n_items,
                    n_blocks: params.n_blocks,
                    level_divisor: level.divisor,
                    level_offset: level.offset,
                    parent_divisor: parent.map_or(0, |value| value.divisor),
                    parent_offset: parent.map_or(0, |value| value.offset),
                },
            );
            let mut bindings = vec![
                ("gHierarchy", level_params.as_entire_binding()),
                ("scan_count", buffers.count.as_entire_binding()),
                (
                    "scan_block_prefix",
                    buffers.block_prefix.as_entire_binding(),
                ),
                ("scan_hierarchy", buffers.hierarchy.as_entire_binding()),
            ];
            if suffix == "up" {
                bindings.insert(2, ("scan_block_sum", buffers.block_sum.as_entire_binding()));
            }
            Ok(HierarchyStep {
                group: bind(suffix, pass, &bindings)?,
                _params: level_params,
                work_items: level.count,
            })
        };
        let up = levels
            .iter()
            .copied()
            .enumerate()
            .map(|(index, level)| {
                hierarchy(
                    "up",
                    passes.hierarchy_up,
                    index,
                    level,
                    levels.get(index + 1).copied(),
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let down = (0..levels.len().saturating_sub(1))
            .rev()
            .map(|index| {
                hierarchy(
                    "down",
                    passes.hierarchy_down,
                    index,
                    levels[index],
                    Some(levels[index + 1]),
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let apply = bind(
            "apply",
            passes.apply,
            &[
                ("gScan", params_buffer.as_entire_binding()),
                ("scan_count", buffers.count.as_entire_binding()),
                (
                    "scan_local_prefix",
                    buffers.local_prefix.as_entire_binding(),
                ),
                (
                    "scan_block_prefix",
                    buffers.block_prefix.as_entire_binding(),
                ),
                (
                    "scan_output_prefix",
                    buffers.output_prefix.as_entire_binding(),
                ),
                ("scan_total", buffers.total.as_entire_binding()),
            ],
        )?;
        Ok(Self {
            label,
            pair_passes: None,
            passes: [
                passes.local.clone(),
                passes.hierarchy_up.clone(),
                passes.hierarchy_down.clone(),
                passes.apply.clone(),
            ],
            dispatch_args: buffers.dispatch_args.alias(3),
            _params: params_buffer,
            local,
            up,
            down,
            apply,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        record_indirect(
            encoder,
            &self.passes[0],
            &self.local,
            self.label,
            &self.dispatch_args,
        )?;
        for step in &self.up {
            record_direct(
                encoder,
                &self.passes[1],
                &step.group,
                self.label,
                step.work_items,
            )?;
        }
        for step in &self.down {
            record_direct(
                encoder,
                &self.passes[2],
                &step.group,
                self.label,
                step.work_items,
            )?;
        }
        record_indirect(
            encoder,
            &self.passes[3],
            &self.apply,
            self.label,
            &self.dispatch_args,
        )
    }

    pub(crate) fn record_pair(
        left: &Self,
        right: &Self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        if left
            .passes
            .iter()
            .zip(&right.passes)
            .any(|(a, b)| a.shader_id != b.shader_id)
        {
            return Err(anyhow!(
                "paired prefix scans must use the same scan kernels"
            ));
        }
        let pair_passes = left
            .pair_passes
            .filter(|passes| Some(*passes) == right.pair_passes)
            .ok_or_else(|| anyhow!("paired prefix scans must share compiler-graph passes"))?;
        pair_indirect(
            encoder,
            &left.passes[0],
            &left.local,
            &left.dispatch_args,
            &right.local,
            &right.dispatch_args,
            pair_passes.local,
        );
        for index in 0..left.up.len().max(right.up.len()) {
            pair_steps(
                encoder,
                &left.passes[1],
                left.up.get(index),
                right.up.get(index),
                if index == 0 {
                    pair_passes.hierarchy_up_first
                } else {
                    pair_passes.hierarchy_up_rest
                },
            )?;
        }
        for index in 0..left.down.len().max(right.down.len()) {
            pair_steps(
                encoder,
                &left.passes[2],
                left.down.get(index),
                right.down.get(index),
                pair_passes.hierarchy_down,
            )?;
        }
        pair_indirect(
            encoder,
            &left.passes[3],
            &left.apply,
            &left.dispatch_args,
            &right.apply,
            &right.dispatch_args,
            pair_passes.apply,
        );
        Ok(())
    }
}

fn pair_indirect<'a>(
    encoder: &'a mut wgpu::CommandEncoder,
    pass: &'a PassData,
    left: &'a wgpu::BindGroup,
    left_args: &'a LaniusBuffer<u32>,
    right: &'a wgpu::BindGroup,
    right_args: &'a LaniusBuffer<u32>,
    label: &'static str,
) {
    let mut batch = ComputePassBatch::begin(encoder, label);
    batch.record_buffer_indirect(pass, left, left_args);
    batch.record_buffer_indirect(pass, right, right_args);
}

fn pair_steps<'a>(
    encoder: &'a mut wgpu::CommandEncoder,
    pass: &'a PassData,
    left: Option<&'a HierarchyStep>,
    right: Option<&'a HierarchyStep>,
    label: &'static str,
) -> Result<()> {
    let mut batch = ComputePassBatch::begin(encoder, label);
    if let Some(step) = left {
        batch.record_raw(pass, &step.group, step.work_items)?;
    }
    if let Some(step) = right {
        batch.record_raw(pass, &step.group, step.work_items)?;
    }
    Ok(())
}
