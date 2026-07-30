use std::collections::HashMap;

use anyhow::{Result, anyhow};

use super::{
    radix_sort::{RadixSortResources, resolve_radix_sort_graph_resources},
    record_direct,
    record_indirect,
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{
        CompilerGraphBuilder,
        CompilerPhase,
        HierarchicalRadixSortGraphPasses,
        RadixSortGraph,
        RadixSortGraphSchedule,
        ResourceDomain,
    },
    kernels::KernelRegistry,
    passes_core::PassData,
    resource_registry::{buffer_from_resources, reflected_bind_group_with_overrides},
};

#[derive(Clone, Copy)]
struct HierarchicalRadixSortPasses<'a> {
    histogram: &'a PassData,
    bucket_local: &'a PassData,
    bucket_chunks: &'a PassData,
    bucket_apply: &'a PassData,
    bucket_bases: &'a PassData,
    scatter: &'a PassData,
}

#[derive(Clone, Copy)]
pub(crate) struct HierarchicalRadixSortKernels {
    pub histogram: &'static str,
    pub bucket_local: &'static str,
    pub bucket_chunks: &'static str,
    pub bucket_apply: &'static str,
    pub scatter: &'static str,
}

impl HierarchicalRadixSortKernels {
    fn resolve(self, kernels: &KernelRegistry) -> HierarchicalRadixSortPasses<'_> {
        HierarchicalRadixSortPasses {
            histogram: kernels.kernel(self.histogram),
            bucket_local: kernels.kernel(self.bucket_local),
            bucket_chunks: kernels.kernel(self.bucket_chunks),
            bucket_apply: kernels.kernel(self.bucket_apply),
            bucket_bases: kernels.kernel("type_checker/names/radix/00c/bucket/bases"),
            scatter: kernels.kernel(self.scatter),
        }
    }

    fn assign(
        self,
        graph: &mut CompilerGraphBuilder,
        passes: HierarchicalRadixSortGraphPasses,
    ) -> Result<(), String> {
        for step in [passes.order_to_temporary, passes.temporary_to_order] {
            graph.assign_kernel(step.histogram, self.histogram)?;
            graph.assign_kernel(step.bucket_local, self.bucket_local)?;
            graph.assign_kernel(step.bucket_chunks, self.bucket_chunks)?;
            graph.assign_kernel(step.bucket_apply, self.bucket_apply)?;
            graph.assign_kernel(
                step.bucket_bases,
                "type_checker/names/radix/00c/bucket/bases",
            )?;
            graph.assign_kernel(step.scatter, self.scatter)?;
            for pass in [
                step.histogram,
                step.bucket_local,
                step.bucket_chunks,
                step.bucket_apply,
                step.bucket_bases,
                step.scatter,
            ] {
                graph.require_complete_reflection(pass)?;
            }
        }
        Ok(())
    }
}

#[derive(Clone, Copy)]
pub(crate) struct HierarchicalRadixSortDefinition {
    pub phase: CompilerPhase,
    pub dispatch_domain: ResourceDomain,
    pub passes: HierarchicalRadixSortGraphPasses,
    pub kernels: HierarchicalRadixSortKernels,
    pub resources: RadixSortResources,
    pub dispatch_args: &'static str,
}

impl HierarchicalRadixSortDefinition {
    pub(crate) const fn label(self) -> &'static str {
        self.passes.order_to_temporary.histogram
    }

    pub(crate) fn register(
        self,
        graph: &mut CompilerGraphBuilder,
        digit_steps: u32,
        keys: &[&str],
    ) -> Result<(), String> {
        let resources =
            resolve_radix_sort_graph_resources(graph, self.resources, self.dispatch_args, keys)?;
        graph.add_fragment(RadixSortGraph {
            phase: self.phase,
            dispatch_domain: self.dispatch_domain,
            digit_steps,
            schedule: RadixSortGraphSchedule::Hierarchical(self.passes),
            resources,
        })?;
        self.kernels.assign(graph, self.passes)
    }

    pub(crate) fn plan<'a>(
        self,
        steps: u32,
        dispatch: HierarchicalRadixSortDispatch<'a>,
    ) -> HierarchicalRadixSortPlan<'a> {
        HierarchicalRadixSortPlan {
            label: self.label(),
            steps,
            kernels: self.kernels,
            dispatch,
            resources: self.resources,
        }
    }
}

#[derive(Clone, Copy)]
pub(crate) struct HierarchicalRadixSortPlan<'a> {
    pub label: &'static str,
    pub steps: u32,
    pub kernels: HierarchicalRadixSortKernels,
    pub dispatch: HierarchicalRadixSortDispatch<'a>,
    pub resources: RadixSortResources,
}

#[derive(Clone, Copy)]
pub(crate) struct HierarchicalRadixSortDispatch<'a> {
    pub rows: &'a wgpu::Buffer,
    pub bucket_work_items: u32,
    pub bucket_chunk_work_items: u32,
    pub bucket_count: u32,
}

/// Stable radix sort whose per-bucket prefix sum spans multiple workgroups.
///
/// The caller describes the keys and work domain. Ping-pong ordering,
/// histogram storage, prefix passes, bind groups, and repeated recording are
/// internal to the operation.
pub(super) struct HierarchicalRadixSortSchedule<P> {
    labels: HierarchicalRadixSortStageLabels,
    passes: OwnedHierarchicalRadixSortPasses,
    row_dispatch_args: wgpu::Buffer,
    bucket_work_items: u32,
    bucket_chunk_work_items: u32,
    bucket_count: u32,
    _params: Vec<LaniusBuffer<P>>,
    histogram: Vec<wgpu::BindGroup>,
    bucket_local: Vec<wgpu::BindGroup>,
    bucket_chunks: Vec<wgpu::BindGroup>,
    bucket_apply: Vec<wgpu::BindGroup>,
    bucket_bases: Vec<wgpu::BindGroup>,
    scatter: Vec<wgpu::BindGroup>,
}

struct OwnedHierarchicalRadixSortPasses {
    histogram: PassData,
    bucket_local: PassData,
    bucket_chunks: PassData,
    bucket_apply: PassData,
    bucket_bases: PassData,
    scatter: PassData,
}

impl From<HierarchicalRadixSortPasses<'_>> for OwnedHierarchicalRadixSortPasses {
    fn from(passes: HierarchicalRadixSortPasses<'_>) -> Self {
        Self {
            histogram: passes.histogram.clone(),
            bucket_local: passes.bucket_local.clone(),
            bucket_chunks: passes.bucket_chunks.clone(),
            bucket_apply: passes.bucket_apply.clone(),
            bucket_bases: passes.bucket_bases.clone(),
            scatter: passes.scatter.clone(),
        }
    }
}

struct HierarchicalRadixSortStageLabels {
    histogram: String,
    bucket_local: String,
    bucket_chunks: String,
    bucket_apply: String,
    bucket_bases: String,
    scatter: String,
}

impl HierarchicalRadixSortStageLabels {
    fn new(label: &str) -> Self {
        Self {
            histogram: format!("{label}.histogram"),
            bucket_local: format!("{label}.bucket_local"),
            bucket_chunks: format!("{label}.bucket_chunks"),
            bucket_apply: format!("{label}.bucket_apply"),
            bucket_bases: format!("{label}.bucket_bases"),
            scatter: format!("{label}.scatter"),
        }
    }
}

impl<P> HierarchicalRadixSortSchedule<P>
where
    P: encase::ShaderType + encase::internal::WriteInto,
{
    pub(crate) fn new<F>(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        registry: &HashMap<String, wgpu::BindingResource<'_>>,
        plan: HierarchicalRadixSortPlan<'_>,
        make_params: F,
    ) -> Result<Self>
    where
        F: Fn(u32) -> P,
    {
        let passes = plan.kernels.resolve(kernels);
        if plan.steps == 0 || plan.steps % 2 != 0 {
            return Err(anyhow!(
                "radix sort `{}` requires a positive even radix step count, got {}",
                plan.label,
                plan.steps,
            ));
        }
        let order = buffer_from_resources(registry, plan.resources.order)?;
        let temporary_order = buffer_from_resources(registry, plan.resources.temporary_order)?;
        let count = buffer_from_resources(registry, plan.resources.count)?;
        let histogram_rows = buffer_from_resources(registry, plan.resources.histogram)?;
        let bucket_prefix_rows = buffer_from_resources(registry, plan.resources.bucket_prefix)?;
        let bucket_total = buffer_from_resources(registry, plan.resources.bucket_total)?;
        let bucket_base = buffer_from_resources(registry, plan.resources.bucket_base)?;

        let mut params = Vec::with_capacity(plan.steps as usize);
        let mut histogram = Vec::with_capacity(plan.steps as usize);
        let mut bucket_local = Vec::with_capacity(plan.steps as usize);
        let mut bucket_chunks = Vec::with_capacity(plan.steps as usize);
        let mut bucket_apply = Vec::with_capacity(plan.steps as usize);
        let mut bucket_bases = Vec::with_capacity(plan.steps as usize);
        let mut scatter = Vec::with_capacity(plan.steps as usize);
        for step in 0..plan.steps {
            let step_params = uniform_from_val(
                device,
                &format!("{}.params.{step}", plan.label),
                &make_params(step),
            );
            let (read_order, write_order) = if step % 2 == 0 {
                (order, temporary_order)
            } else {
                (temporary_order, order)
            };
            histogram.push(reflected_bind_group_with_overrides(
                device,
                &format!("{}.histogram.{step}", plan.label),
                passes.histogram,
                registry,
                &[
                    ("gParams", step_params.as_entire_binding()),
                    (plan.resources.count, count.as_entire_binding()),
                    ("radix_order_in", read_order.as_entire_binding()),
                    ("radix_block_histogram", histogram_rows.as_entire_binding()),
                ],
            )?);
            bucket_local.push(reflected_bind_group_with_overrides(
                device,
                &format!("{}.bucket_local.{step}", plan.label),
                passes.bucket_local,
                registry,
                &[
                    ("gParams", step_params.as_entire_binding()),
                    (plan.resources.count, count.as_entire_binding()),
                    ("radix_block_histogram", histogram_rows.as_entire_binding()),
                    (
                        "radix_block_bucket_prefix",
                        bucket_prefix_rows.as_entire_binding(),
                    ),
                    ("radix_bucket_total", bucket_total.as_entire_binding()),
                ],
            )?);
            bucket_chunks.push(reflected_bind_group_with_overrides(
                device,
                &format!("{}.bucket_chunks.{step}", plan.label),
                passes.bucket_chunks,
                registry,
                &[
                    ("gParams", step_params.as_entire_binding()),
                    (plan.resources.count, count.as_entire_binding()),
                    ("radix_block_histogram", histogram_rows.as_entire_binding()),
                    ("radix_bucket_total", bucket_total.as_entire_binding()),
                ],
            )?);
            bucket_apply.push(reflected_bind_group_with_overrides(
                device,
                &format!("{}.bucket_apply.{step}", plan.label),
                passes.bucket_apply,
                registry,
                &[
                    ("gParams", step_params.as_entire_binding()),
                    (plan.resources.count, count.as_entire_binding()),
                    ("radix_block_histogram", histogram_rows.as_entire_binding()),
                    (
                        "radix_block_bucket_prefix",
                        bucket_prefix_rows.as_entire_binding(),
                    ),
                ],
            )?);
            bucket_bases.push(reflected_bind_group_with_overrides(
                device,
                &format!("{}.bucket_bases.{step}", plan.label),
                passes.bucket_bases,
                registry,
                &[
                    ("gParams", step_params.as_entire_binding()),
                    ("radix_bucket_total", bucket_total.as_entire_binding()),
                    ("radix_bucket_base", bucket_base.as_entire_binding()),
                ],
            )?);
            scatter.push(reflected_bind_group_with_overrides(
                device,
                &format!("{}.scatter.{step}", plan.label),
                passes.scatter,
                registry,
                &[
                    ("gParams", step_params.as_entire_binding()),
                    (plan.resources.count, count.as_entire_binding()),
                    ("radix_order_in", read_order.as_entire_binding()),
                    ("radix_bucket_base", bucket_base.as_entire_binding()),
                    (
                        "radix_block_bucket_prefix",
                        bucket_prefix_rows.as_entire_binding(),
                    ),
                    ("radix_order_out", write_order.as_entire_binding()),
                ],
            )?);
            params.push(step_params);
        }

        Ok(Self {
            labels: HierarchicalRadixSortStageLabels::new(plan.label),
            passes: passes.into(),
            row_dispatch_args: plan.dispatch.rows.clone(),
            bucket_work_items: plan.dispatch.bucket_work_items,
            bucket_chunk_work_items: plan.dispatch.bucket_chunk_work_items,
            bucket_count: plan.dispatch.bucket_count,
            _params: params,
            histogram,
            bucket_local,
            bucket_chunks,
            bucket_apply,
            bucket_bases,
            scatter,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        let passes = &self.passes;
        for step in 0..self.scatter.len() {
            record_indirect(
                encoder,
                &passes.histogram,
                &self.histogram[step],
                &self.labels.histogram,
                &self.row_dispatch_args,
            )?;
            record_direct(
                encoder,
                &passes.bucket_local,
                &self.bucket_local[step],
                &self.labels.bucket_local,
                self.bucket_work_items,
            )?;
            record_direct(
                encoder,
                &passes.bucket_chunks,
                &self.bucket_chunks[step],
                &self.labels.bucket_chunks,
                self.bucket_chunk_work_items,
            )?;
            record_direct(
                encoder,
                &passes.bucket_apply,
                &self.bucket_apply[step],
                &self.labels.bucket_apply,
                self.bucket_work_items,
            )?;
            record_direct(
                encoder,
                &passes.bucket_bases,
                &self.bucket_bases[step],
                &self.labels.bucket_bases,
                self.bucket_count,
            )?;
            record_indirect(
                encoder,
                &passes.scatter,
                &self.scatter[step],
                &self.labels.scatter,
                &self.row_dispatch_args,
            )?;
        }
        Ok(())
    }
}
