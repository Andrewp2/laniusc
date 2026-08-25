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
    scan::{PrefixScanHierarchyParams, PrefixScanParams},
};

#[derive(Clone, Copy)]
struct PrefixScanPasses<'a> {
    local: &'a PassData,
    block_prefix: &'a PassData,
    apply: &'a PassData,
}

fn standard_passes(kernels: &KernelRegistry) -> PrefixScanPasses<'_> {
    PrefixScanPasses {
        local: kernels.kernel("scan/counted/00_local"),
        block_prefix: kernels.kernel("scan/counted/04_block_prefix"),
        apply: kernels.kernel("scan/counted/02_apply"),
    }
}

fn in_place_passes(kernels: &KernelRegistry) -> PrefixScanPasses<'_> {
    PrefixScanPasses {
        local: kernels.kernel("scan/counted/00_local_in_place"),
        block_prefix: kernels.kernel("scan/counted/04_block_prefix"),
        apply: kernels.kernel("scan/counted/02_apply_in_place"),
    }
}

fn pair_passes(kernels: &KernelRegistry) -> Option<PrefixScanPasses<'_>> {
    Some(PrefixScanPasses {
        local: kernels.optional("scan/counted_pair/00_local")?,
        block_prefix: kernels.optional("scan/counted_pair/01_block_prefix")?,
        apply: kernels.optional("scan/counted_pair/03_apply")?,
    })
}

fn pair_in_place_passes(kernels: &KernelRegistry) -> Option<PrefixScanPasses<'_>> {
    Some(PrefixScanPasses {
        local: kernels.optional("scan/counted_pair/00_local_in_place")?,
        block_prefix: kernels.optional("scan/counted_pair/01_block_prefix")?,
        apply: kernels.optional("scan/counted_pair/03_apply_in_place")?,
    })
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

pub(crate) struct PrefixScanBuffers<'a> {
    count: TrackedBufferView<'a>,
    input: TrackedBufferView<'a>,
    output_prefix: TrackedBufferView<'a>,
    total: TrackedBufferView<'a>,
    dispatch_args: TrackedBufferView<'a>,
    local_prefix: TrackedBufferView<'a>,
    block_sum: TrackedBufferView<'a>,
    block_prefix: TrackedBufferView<'a>,
}

pub(crate) struct PrefixScanOperation {
    graph_passes: PrefixScanGraphPasses,
    passes: [PassData; 3],
    dispatch_args: LaniusBuffer<u32>,
    _params: LaniusBuffer<PrefixScanParams>,
    _block_params: LaniusBuffer<PrefixScanHierarchyParams>,
    local: wgpu::BindGroup,
    block_prefix: wgpu::BindGroup,
    apply: wgpu::BindGroup,
}

impl PrefixScanOperation {
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
            kernels,
            spec.passes,
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
        graph_passes: PrefixScanGraphPasses,
        params: PrefixScanParams,
        count: TrackedBufferView<'_>,
        dispatch_args: TrackedBufferView<'_>,
        input: TrackedBufferView<'_>,
        output_prefix: TrackedBufferView<'_>,
        total: TrackedBufferView<'_>,
        workspace: PrefixScanWorkspace<&LaniusBuffer<u32>>,
    ) -> Result<Self> {
        let buffers = PrefixScanBuffers {
            count,
            dispatch_args,
            input,
            output_prefix,
            total,
            local_prefix: workspace.local_prefix.into(),
            block_sum: workspace.block_sum.into(),
            block_prefix: workspace.block_prefix.into(),
        };
        let passes = if same_view(buffers.input, buffers.output_prefix) {
            in_place_passes(kernels)
        } else {
            standard_passes(kernels)
        };
        Self::new(
            device,
            Some((queue, cache)),
            label,
            params,
            passes,
            graph_passes,
            buffers,
        )
    }

    pub(crate) fn from_resource_names(
        device: &wgpu::Device,
        label: &'static str,
        graph_passes: PrefixScanGraphPasses,
        kernels: &KernelRegistry,
        resources: &ResourceMap<'_>,
        names: PrefixScanResources<&str>,
    ) -> Result<Self> {
        Self::from_resource_names_with_passes(
            device,
            label,
            kernels,
            graph_passes,
            resources,
            names,
        )
    }

    fn from_resource_names_with_passes(
        device: &wgpu::Device,
        label: &'static str,
        kernels: &KernelRegistry,
        graph_passes: PrefixScanGraphPasses,
        resources: &ResourceMap<'_>,
        names: PrefixScanResources<&str>,
    ) -> Result<Self> {
        let (params, buffers) = scan_buffers_from_names(resources, names)?;
        let passes = if same_view(buffers.input, buffers.output_prefix) {
            in_place_passes(kernels)
        } else {
            standard_passes(kernels)
        };
        Self::new(device, None, label, params, passes, graph_passes, buffers)
    }

    fn new(
        device: &wgpu::Device,
        reusable: Option<(&wgpu::Queue, &CapacityBufferCache)>,
        label: &'static str,
        params: PrefixScanParams,
        passes: PrefixScanPasses<'_>,
        graph_passes: PrefixScanGraphPasses,
        buffers: PrefixScanBuffers<'_>,
    ) -> Result<Self> {
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
        let in_place = same_view(buffers.input, buffers.output_prefix);
        let local = if in_place {
            bind(
                "local",
                passes.local,
                &[
                    ("gScan", params_buffer.as_entire_binding()),
                    ("scan_count", buffers.count.as_entire_binding()),
                    ("scan_values", buffers.input.as_entire_binding()),
                    ("scan_block_sum", buffers.block_sum.as_entire_binding()),
                ],
            )?
        } else {
            bind(
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
            )?
        };
        let block_params = scan_uniform(
            device,
            reusable,
            &format!("{label}.block-prefix.params"),
            &PrefixScanHierarchyParams {
                n_items: params.n_items,
                n_blocks: params.n_blocks,
                level_divisor: 1,
                level_offset: 0,
                parent_divisor: 0,
                parent_offset: 0,
            },
        );
        let block_prefix = bind(
            "block-prefix",
            passes.block_prefix,
            &[
                ("gHierarchy", block_params.as_entire_binding()),
                ("scan_count", buffers.count.as_entire_binding()),
                ("scan_block_sum", buffers.block_sum.as_entire_binding()),
                (
                    "scan_block_prefix",
                    buffers.block_prefix.as_entire_binding(),
                ),
            ],
        )?;
        let apply = if in_place {
            bind(
                "apply",
                passes.apply,
                &[
                    ("gScan", params_buffer.as_entire_binding()),
                    ("scan_count", buffers.count.as_entire_binding()),
                    (
                        "scan_block_prefix",
                        buffers.block_prefix.as_entire_binding(),
                    ),
                    ("scan_values", buffers.output_prefix.as_entire_binding()),
                    ("scan_total", buffers.total.as_entire_binding()),
                ],
            )?
        } else {
            bind(
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
            )?
        };
        Ok(Self {
            graph_passes,
            passes: [
                passes.local.clone(),
                passes.block_prefix.clone(),
                passes.apply.clone(),
            ],
            dispatch_args: buffers.dispatch_args.alias(3),
            _params: params_buffer,
            _block_params: block_params,
            local,
            block_prefix,
            apply,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_with_graph_passes(encoder, self.graph_passes)
    }

    /// Records this materialized scan under another graph declaration with
    /// the same physical kernels and resources. This is used when one stable
    /// workspace is revisited at distinct semantic positions in the compiler
    /// schedule; the graph operation identity belongs to the invocation, not
    /// to the cached bind groups.
    pub(crate) fn record_with_graph_passes(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        graph_passes: PrefixScanGraphPasses,
    ) -> Result<()> {
        record_indirect(
            encoder,
            &self.passes[0],
            &self.local,
            graph_passes.local,
            &self.dispatch_args,
        )?;
        record_direct(
            encoder,
            &self.passes[1],
            &self.block_prefix,
            graph_passes.hierarchy_up_first,
            1,
        )?;
        record_indirect(
            encoder,
            &self.passes[2],
            &self.apply,
            graph_passes.apply,
            &self.dispatch_args,
        )
    }

    pub(crate) fn record_pair(
        left: &Self,
        right: &Self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        if crate::gpu::timer::operation_capture_requires_split_passes() {
            left.record(encoder)?;
            return right.record(encoder);
        }
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
        if left.graph_passes != right.graph_passes {
            return Err(anyhow!(
                "paired prefix scans must share compiler-graph passes"
            ));
        }
        let pair_passes = left.graph_passes;
        pair_indirect(
            encoder,
            &left.passes[0],
            &left.local,
            &left.dispatch_args,
            &right.local,
            &right.dispatch_args,
            pair_passes.local,
        );
        pair_steps(
            encoder,
            &left.passes[1],
            &left.block_prefix,
            &right.block_prefix,
            pair_passes.hierarchy_up_first,
        )?;
        pair_indirect(
            encoder,
            &left.passes[2],
            &left.apply,
            &left.dispatch_args,
            &right.apply,
            &right.dispatch_args,
            pair_passes.apply,
        );
        Ok(())
    }
}

fn scan_buffers_from_names<'a>(
    resources: &'a ResourceMap<'a>,
    names: PrefixScanResources<&str>,
) -> Result<(PrefixScanParams, PrefixScanBuffers<'a>)> {
    let buffer = |name| resources.tracked_view(name);
    let n_items = resources.logical_u32_count(names.input)?;
    Ok((
        PrefixScanParams {
            n_items,
            n_blocks: n_items.div_ceil(256).max(1),
            min_items: 0,
        },
        PrefixScanBuffers {
            count: buffer(names.count)?,
            input: buffer(names.input)?,
            output_prefix: buffer(names.output_prefix)?,
            total: buffer(names.total)?,
            dispatch_args: buffer(names.dispatch_args)?,
            local_prefix: buffer(names.local_prefix)?,
            block_sum: buffer(names.block_sum)?,
            block_prefix: buffer(names.block_prefix)?,
        },
    ))
}

fn same_view(left: TrackedBufferView<'_>, right: TrackedBufferView<'_>) -> bool {
    left.buffer == right.buffer
        && left.byte_offset == right.byte_offset
        && left.byte_size == right.byte_size
        && left.allocation_id() == right.allocation_id()
}

struct FusedPrefixScanPair {
    graph_passes: PrefixScanGraphPasses,
    passes: [PassData; 3],
    dispatch_args: LaniusBuffer<u32>,
    _params: LaniusBuffer<PrefixScanParams>,
    _block_params: LaniusBuffer<PrefixScanHierarchyParams>,
    local: wgpu::BindGroup,
    block_prefix: wgpu::BindGroup,
    apply: wgpu::BindGroup,
}

impl FusedPrefixScanPair {
    fn new(
        device: &wgpu::Device,
        labels: (&str, &str),
        passes: PrefixScanPasses<'_>,
        graph_passes: PrefixScanGraphPasses,
        params: PrefixScanParams,
        left: PrefixScanBuffers<'_>,
        right: PrefixScanBuffers<'_>,
    ) -> Result<Self> {
        let label = format!("{}+{}", labels.0, labels.1);
        let params_buffer = uniform_from_val(device, &format!("{label}.params"), &params);
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
        let in_place = same_view(left.input, left.output_prefix);
        let local = if in_place {
            bind(
                "local",
                passes.local,
                &[
                    ("gScan", params_buffer.as_entire_binding()),
                    ("scan_count", left.count.as_entire_binding()),
                    ("scan_values_left", left.input.as_entire_binding()),
                    ("scan_values_right", right.input.as_entire_binding()),
                    ("scan_block_sum_left", left.block_sum.as_entire_binding()),
                    ("scan_block_sum_right", right.block_sum.as_entire_binding()),
                ],
            )?
        } else {
            bind(
                "local",
                passes.local,
                &[
                    ("gScan", params_buffer.as_entire_binding()),
                    ("scan_count", left.count.as_entire_binding()),
                    ("scan_input_left", left.input.as_entire_binding()),
                    ("scan_input_right", right.input.as_entire_binding()),
                    (
                        "scan_output_prefix_left",
                        left.output_prefix.as_entire_binding(),
                    ),
                    (
                        "scan_output_prefix_right",
                        right.output_prefix.as_entire_binding(),
                    ),
                    ("scan_block_sum_left", left.block_sum.as_entire_binding()),
                    ("scan_block_sum_right", right.block_sum.as_entire_binding()),
                ],
            )?
        };
        let block_params = uniform_from_val(
            device,
            &format!("{label}.block-prefix.params"),
            &PrefixScanHierarchyParams {
                n_items: params.n_items,
                n_blocks: params.n_blocks,
                level_divisor: 1,
                level_offset: 0,
                parent_divisor: 0,
                parent_offset: 0,
            },
        );
        let block_prefix = bind(
            "block-prefix",
            passes.block_prefix,
            &[
                ("gHierarchy", block_params.as_entire_binding()),
                ("scan_count", left.count.as_entire_binding()),
                ("scan_block_sum_left", left.block_sum.as_entire_binding()),
                ("scan_block_sum_right", right.block_sum.as_entire_binding()),
                (
                    "scan_block_prefix_left",
                    left.block_prefix.as_entire_binding(),
                ),
                (
                    "scan_block_prefix_right",
                    right.block_prefix.as_entire_binding(),
                ),
            ],
        )?;
        let apply = if in_place {
            bind(
                "apply",
                passes.apply,
                &[
                    ("gScan", params_buffer.as_entire_binding()),
                    ("scan_count", left.count.as_entire_binding()),
                    (
                        "scan_block_prefix_left",
                        left.block_prefix.as_entire_binding(),
                    ),
                    (
                        "scan_block_prefix_right",
                        right.block_prefix.as_entire_binding(),
                    ),
                    ("scan_values_left", left.output_prefix.as_entire_binding()),
                    ("scan_values_right", right.output_prefix.as_entire_binding()),
                    ("scan_total_left", left.total.as_entire_binding()),
                    ("scan_total_right", right.total.as_entire_binding()),
                ],
            )?
        } else {
            bind(
                "apply",
                passes.apply,
                &[
                    ("gScan", params_buffer.as_entire_binding()),
                    ("scan_count", left.count.as_entire_binding()),
                    (
                        "scan_block_prefix_left",
                        left.block_prefix.as_entire_binding(),
                    ),
                    (
                        "scan_block_prefix_right",
                        right.block_prefix.as_entire_binding(),
                    ),
                    (
                        "scan_output_prefix_left",
                        left.output_prefix.as_entire_binding(),
                    ),
                    (
                        "scan_output_prefix_right",
                        right.output_prefix.as_entire_binding(),
                    ),
                    ("scan_total_left", left.total.as_entire_binding()),
                    ("scan_total_right", right.total.as_entire_binding()),
                ],
            )?
        };
        Ok(Self {
            graph_passes,
            passes: [
                passes.local.clone(),
                passes.block_prefix.clone(),
                passes.apply.clone(),
            ],
            dispatch_args: left.dispatch_args.alias(3),
            _params: params_buffer,
            _block_params: block_params,
            local,
            block_prefix,
            apply,
        })
    }

    fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        record_indirect(
            encoder,
            &self.passes[0],
            &self.local,
            self.graph_passes.local,
            &self.dispatch_args,
        )?;
        record_direct(
            encoder,
            &self.passes[1],
            &self.block_prefix,
            self.graph_passes.hierarchy_up_first,
            1,
        )?;
        record_indirect(
            encoder,
            &self.passes[2],
            &self.apply,
            self.graph_passes.apply,
            &self.dispatch_args,
        )
    }
}

enum PrefixScanPairExecution {
    Fused(FusedPrefixScanPair),
    Separate(Box<(PrefixScanOperation, PrefixScanOperation)>),
}

/// Two independent prefix scans lowered to one uint2 GPU scan when the device
/// can expose the required storage bindings. The scalar hierarchy remains the
/// portability fallback and has identical graph semantics.
pub(crate) struct PrefixScanPairOperation {
    execution: PrefixScanPairExecution,
}

impl PrefixScanPairOperation {
    pub(crate) fn from_spec(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        resources: &ResourceMap<'_>,
        spec: PrefixScanPairSpec,
    ) -> Result<Self> {
        resources.validate_graph_passes_if_present(spec.passes.names())?;
        let (left_params, left) = scan_buffers_from_names(resources, spec.left)?;
        let (right_params, right) = scan_buffers_from_names(resources, spec.right)?;
        let compatible = left_params.n_items == right_params.n_items
            && left_params.min_items == right_params.min_items
            && same_view(left.count, right.count)
            && same_view(left.dispatch_args, right.dispatch_args);
        let left_in_place = same_view(left.input, left.output_prefix);
        let right_in_place = same_view(right.input, right.output_prefix);
        if left_in_place != right_in_place {
            return Err(anyhow!(
                "paired prefix scans must use the same storage mode in both lanes"
            ));
        }
        let paired_scan_enabled =
            !crate::gpu::env::env_bool_strict("LANIUS_GPU_DISABLE_PAIRED_PREFIX_SCAN", false);
        let fused_passes = if left_in_place {
            pair_in_place_passes(kernels)
        } else {
            pair_passes(kernels)
        };
        if compatible
            && paired_scan_enabled
            && let Some(passes) = fused_passes
        {
            return Ok(Self {
                execution: PrefixScanPairExecution::Fused(FusedPrefixScanPair::new(
                    device,
                    (spec.left_label, spec.right_label),
                    passes,
                    spec.passes,
                    left_params,
                    left,
                    right,
                )?),
            });
        }

        let scalar = if left_in_place {
            in_place_passes(kernels)
        } else {
            standard_passes(kernels)
        };
        Ok(Self {
            execution: PrefixScanPairExecution::Separate(Box::new((
                PrefixScanOperation::new(
                    device,
                    None,
                    spec.left_label,
                    left_params,
                    scalar,
                    spec.passes,
                    left,
                )?,
                PrefixScanOperation::new(
                    device,
                    None,
                    spec.right_label,
                    right_params,
                    scalar,
                    spec.passes,
                    right,
                )?,
            ))),
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        match &self.execution {
            PrefixScanPairExecution::Fused(pair) => pair.record(encoder),
            PrefixScanPairExecution::Separate(pair) => {
                PrefixScanOperation::record_pair(&pair.0, &pair.1, encoder)
            }
        }
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
    let mut batch = ComputePassBatch::begin_graph_operation(encoder, label);
    batch.record_buffer_indirect(pass, left, left_args);
    batch.record_buffer_indirect(pass, right, right_args);
}

fn pair_steps<'a>(
    encoder: &'a mut wgpu::CommandEncoder,
    pass: &'a PassData,
    left: &'a wgpu::BindGroup,
    right: &'a wgpu::BindGroup,
    label: &'static str,
) -> Result<()> {
    let mut batch = ComputePassBatch::begin_graph_operation(encoder, label);
    batch.record_raw(pass, left, 1)?;
    batch.record_raw(pass, right, 1)?;
    Ok(())
}
