use anyhow::{Result, anyhow};

use super::record_indirect;
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
    scan::PrefixScanParams,
};

#[derive(Clone, Copy)]
struct PrefixScanPasses<'a> {
    local: &'a PassData,
    apply: &'a PassData,
}

fn standard_passes(kernels: &KernelRegistry) -> PrefixScanPasses<'_> {
    PrefixScanPasses {
        local: kernels.kernel("scan/words/scan_counted_word_blocks"),
        apply: kernels.kernel("scan/words/apply_counted_word_carries"),
    }
}

fn in_place_passes(kernels: &KernelRegistry) -> PrefixScanPasses<'_> {
    PrefixScanPasses {
        local: kernels.kernel("scan/words/scan_counted_word_blocks_in_place"),
        apply: kernels.kernel("scan/words/apply_counted_word_carries_in_place"),
    }
}

fn total_dispatch_passes(kernels: &KernelRegistry) -> PrefixScanPasses<'_> {
    PrefixScanPasses {
        local: kernels.kernel("scan/words/scan_counted_word_blocks"),
        apply: kernels.kernel("scan/words/apply_counted_word_carries_and_size_dispatch"),
    }
}

fn pair_total_dispatch_passes(kernels: &KernelRegistry) -> Option<PrefixScanPasses<'_>> {
    Some(PrefixScanPasses {
        local: kernels.optional("scan/pairs/scan_counted_pair_blocks")?,
        apply: kernels.optional("scan/pairs/apply_counted_pair_carries_and_size_dispatch")?,
    })
}

fn pair_passes(kernels: &KernelRegistry) -> Option<PrefixScanPasses<'_>> {
    Some(PrefixScanPasses {
        local: kernels.optional("scan/pairs/scan_counted_pair_blocks")?,
        apply: kernels.optional("scan/pairs/apply_counted_pair_carries")?,
    })
}

fn pair_in_place_passes(kernels: &KernelRegistry) -> Option<PrefixScanPasses<'_>> {
    Some(PrefixScanPasses {
        local: kernels.optional("scan/pairs/scan_counted_pair_blocks_in_place")?,
        apply: kernels.optional("scan/pairs/apply_counted_pair_carries_in_place")?,
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

/// Indirect dispatch arguments an apply writes for its scan's total
/// (scan/blocks/scan_total_dispatch.slang): the `ScanTotalDispatchParams` uniform and
/// the argument buffer.
#[derive(Clone, Copy)]
pub(crate) struct ScanTotalDispatch<'a> {
    pub(crate) params: TrackedBufferView<'a>,
    pub(crate) dispatch_args: TrackedBufferView<'a>,
}

pub(crate) struct PrefixScanBuffers<'a> {
    count: TrackedBufferView<'a>,
    input: TrackedBufferView<'a>,
    output_prefix: TrackedBufferView<'a>,
    total: TrackedBufferView<'a>,
    dispatch_args: TrackedBufferView<'a>,
    local_prefix: TrackedBufferView<'a>,
    block_sum: TrackedBufferView<'a>,
}

pub(crate) struct PrefixScanOperation {
    graph_passes: PrefixScanGraphPasses,
    passes: [PassData; 2],
    dispatch_args: LaniusBuffer<u32>,
    _params: LaniusBuffer<PrefixScanParams>,
    local: wgpu::BindGroup,
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

    /// The scan of `spec` with an apply that also writes indirect dispatch
    /// arguments for the total into the resource `dispatch_args`.
    pub(crate) fn from_spec_with_total_dispatch(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        resources: &ResourceMap<'_>,
        spec: PrefixScanSpec,
        params: TrackedBufferView<'_>,
        dispatch_args: &str,
    ) -> Result<Self> {
        resources.validate_graph_passes_if_present(spec.passes.names())?;
        Self::from_resource_names_with_total_dispatch(
            device,
            spec.passes.local,
            spec.passes,
            kernels,
            resources,
            spec.resources,
            params,
            dispatch_args,
        )
    }

    /// [`Self::from_resource_names`] with an apply that also writes indirect
    /// dispatch arguments for the total into the resource `dispatch_args`.
    pub(crate) fn from_resource_names_with_total_dispatch(
        device: &wgpu::Device,
        label: &'static str,
        graph_passes: PrefixScanGraphPasses,
        kernels: &KernelRegistry,
        resources: &ResourceMap<'_>,
        names: PrefixScanResources<&str>,
        params: TrackedBufferView<'_>,
        dispatch_args: &str,
    ) -> Result<Self> {
        let (scan_params, buffers) = scan_buffers_from_names(resources, names)?;
        let total_dispatch = ScanTotalDispatch {
            params,
            dispatch_args: resources.tracked_view(dispatch_args)?,
        };
        Self::new_with_total_dispatch(
            device,
            None,
            label,
            scan_params,
            total_dispatch_passes(kernels),
            graph_passes,
            buffers,
            Some(total_dispatch),
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
        Self::new_with_total_dispatch(
            device,
            reusable,
            label,
            params,
            passes,
            graph_passes,
            buffers,
            None,
        )
    }

    fn new_with_total_dispatch(
        device: &wgpu::Device,
        reusable: Option<(&wgpu::Queue, &CapacityBufferCache)>,
        label: &'static str,
        params: PrefixScanParams,
        passes: PrefixScanPasses<'_>,
        graph_passes: PrefixScanGraphPasses,
        buffers: PrefixScanBuffers<'_>,
        total_dispatch: Option<ScanTotalDispatch<'_>>,
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
        if in_place && total_dispatch.is_some() {
            return Err(anyhow!(
                "prefix scan {label} writes total dispatch arguments only out of place"
            ));
        }
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
        let apply = if in_place {
            bind(
                "apply",
                passes.apply,
                &[
                    ("gScan", params_buffer.as_entire_binding()),
                    ("scan_count", buffers.count.as_entire_binding()),
                    ("scan_block_sum", buffers.block_sum.as_entire_binding()),
                    ("scan_values", buffers.output_prefix.as_entire_binding()),
                    ("scan_total", buffers.total.as_entire_binding()),
                ],
            )?
        } else {
            let mut bindings = vec![
                ("gScan", params_buffer.as_entire_binding()),
                ("scan_count", buffers.count.as_entire_binding()),
                (
                    "scan_local_prefix",
                    buffers.local_prefix.as_entire_binding(),
                ),
                ("scan_block_sum", buffers.block_sum.as_entire_binding()),
                (
                    "scan_output_prefix",
                    buffers.output_prefix.as_entire_binding(),
                ),
                ("scan_total", buffers.total.as_entire_binding()),
            ];
            if let Some(total_dispatch) = total_dispatch {
                bindings.push(("gTotalDispatch", total_dispatch.params.as_entire_binding()));
                bindings.push((
                    "scan_total_dispatch_args",
                    total_dispatch.dispatch_args.as_entire_binding(),
                ));
            }
            bind("apply", passes.apply, &bindings)?
        };
        Ok(Self {
            graph_passes,
            passes: [passes.local.clone(), passes.apply.clone()],
            dispatch_args: buffers.dispatch_args.alias(3),
            _params: params_buffer,
            local,
            apply,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.record_with_graph_passes(encoder, self.graph_passes)
    }

    /// The bind groups of the scan's two passes.
    pub(crate) fn bind_groups(&self) -> [&wgpu::BindGroup; 2] {
        [&self.local, &self.apply]
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
        record_indirect(
            encoder,
            &self.passes[1],
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
        pair_indirect(
            encoder,
            &left.passes[1],
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
    passes: [PassData; 2],
    dispatch_args: LaniusBuffer<u32>,
    _params: LaniusBuffer<PrefixScanParams>,
    local: wgpu::BindGroup,
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
        total_dispatch: Option<(ScanTotalDispatch<'_>, ScanTotalDispatch<'_>)>,
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
        let apply = if in_place {
            bind(
                "apply",
                passes.apply,
                &[
                    ("gScan", params_buffer.as_entire_binding()),
                    ("scan_count", left.count.as_entire_binding()),
                    ("scan_block_sum_left", left.block_sum.as_entire_binding()),
                    ("scan_block_sum_right", right.block_sum.as_entire_binding()),
                    ("scan_values_left", left.output_prefix.as_entire_binding()),
                    ("scan_values_right", right.output_prefix.as_entire_binding()),
                    ("scan_total_left", left.total.as_entire_binding()),
                    ("scan_total_right", right.total.as_entire_binding()),
                ],
            )?
        } else {
            let mut bindings = vec![
                ("gScan", params_buffer.as_entire_binding()),
                ("scan_count", left.count.as_entire_binding()),
                ("scan_block_sum_left", left.block_sum.as_entire_binding()),
                ("scan_block_sum_right", right.block_sum.as_entire_binding()),
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
            ];
            if let Some((left_dispatch, right_dispatch)) = total_dispatch {
                bindings.push(("gTotalDispatch", left_dispatch.params.as_entire_binding()));
                bindings.push((
                    "scan_total_dispatch_args_left",
                    left_dispatch.dispatch_args.as_entire_binding(),
                ));
                bindings.push((
                    "scan_total_dispatch_args_right",
                    right_dispatch.dispatch_args.as_entire_binding(),
                ));
            }
            bind("apply", passes.apply, &bindings)?
        };
        Ok(Self {
            graph_passes,
            passes: [passes.local.clone(), passes.apply.clone()],
            dispatch_args: left.dispatch_args.alias(3),
            _params: params_buffer,
            local,
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
        record_indirect(
            encoder,
            &self.passes[1],
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
        Self::from_spec_and_total_dispatch(device, kernels, resources, spec, None)
    }

    /// The pair of `spec` with an apply that also writes indirect dispatch
    /// arguments for each total into the resources `[left, right]`; both use
    /// the `ScanTotalDispatchParams` uniform `params`.
    pub(crate) fn from_spec_with_total_dispatch(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        resources: &ResourceMap<'_>,
        spec: PrefixScanPairSpec,
        params: TrackedBufferView<'_>,
        dispatch_args: [&str; 2],
    ) -> Result<Self> {
        let total_dispatch = (
            ScanTotalDispatch {
                params,
                dispatch_args: resources.tracked_view(dispatch_args[0])?,
            },
            ScanTotalDispatch {
                params,
                dispatch_args: resources.tracked_view(dispatch_args[1])?,
            },
        );
        Self::from_spec_and_total_dispatch(device, kernels, resources, spec, Some(total_dispatch))
    }

    fn from_spec_and_total_dispatch(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        resources: &ResourceMap<'_>,
        spec: PrefixScanPairSpec,
        total_dispatch: Option<(ScanTotalDispatch<'_>, ScanTotalDispatch<'_>)>,
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
        if left_in_place && total_dispatch.is_some() {
            return Err(anyhow!(
                "paired prefix scans write total dispatch arguments only out of place"
            ));
        }
        let fused_passes = if left_in_place {
            pair_in_place_passes(kernels)
        } else if total_dispatch.is_some() {
            pair_total_dispatch_passes(kernels)
        } else {
            pair_passes(kernels)
        };
        if compatible
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
                    total_dispatch,
                )?),
            });
        }

        let scalar = if left_in_place {
            in_place_passes(kernels)
        } else if total_dispatch.is_some() {
            total_dispatch_passes(kernels)
        } else {
            standard_passes(kernels)
        };
        Ok(Self {
            execution: PrefixScanPairExecution::Separate(Box::new((
                PrefixScanOperation::new_with_total_dispatch(
                    device,
                    None,
                    spec.left_label,
                    left_params,
                    scalar,
                    spec.passes,
                    left,
                    total_dispatch.map(|(left, _)| left),
                )?,
                PrefixScanOperation::new_with_total_dispatch(
                    device,
                    None,
                    spec.right_label,
                    right_params,
                    scalar,
                    spec.passes,
                    right,
                    total_dispatch.map(|(_, right)| right),
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
