use super::super::*;

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct HierarchicalRadixSortPasses<'a> {
    pub histogram: &'a PassData,
    pub bucket_local: &'a PassData,
    pub bucket_chunks: &'a PassData,
    pub bucket_apply: &'a PassData,
    pub bucket_bases: &'a PassData,
    pub scatter: &'a PassData,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct HierarchicalRadixSortDefinition {
    pub dispatch_domain: crate::gpu::compiler_graph::ResourceDomain,
    pub passes: crate::gpu::compiler_graph::HierarchicalRadixSortGraphPasses,
    pub resources: RadixSortResources,
    pub dispatch_args: &'static str,
}

impl HierarchicalRadixSortDefinition {
    pub(in crate::type_checker) const fn label(self) -> &'static str {
        self.passes.order_to_temporary.histogram
    }

    pub(in crate::type_checker) fn register(
        self,
        graph: &mut crate::gpu::compiler_graph::CompilerGraphBuilder,
        digit_steps: u32,
        keys: &[&str],
    ) -> Result<(), String> {
        let resources = super::radix_sort::resolve_radix_sort_graph_resources(
            graph,
            self.resources,
            self.dispatch_args,
            keys,
        )?;
        graph
            .add_fragment(crate::gpu::compiler_graph::RadixSortGraph {
                phase: crate::gpu::compiler_graph::CompilerPhase::TypeCheck,
                dispatch_domain: self.dispatch_domain,
                digit_steps,
                schedule: crate::gpu::compiler_graph::RadixSortGraphSchedule::Hierarchical(
                    self.passes,
                ),
                resources,
            })
            .map(|_| ())
    }
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct HierarchicalRadixSortPlan<'a> {
    pub label: &'static str,
    pub steps: u32,
    pub passes: HierarchicalRadixSortPasses<'a>,
    pub dispatch: HierarchicalRadixSortDispatch<'a>,
    pub resources: RadixSortResources,
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct HierarchicalRadixSortDispatch<'a> {
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
    pub(in crate::type_checker) fn new<F>(
        device: &wgpu::Device,
        registry: &HashMap<String, wgpu::BindingResource<'_>>,
        plan: HierarchicalRadixSortPlan<'_>,
        make_params: F,
    ) -> Result<Self>
    where
        F: Fn(u32) -> P,
    {
        if plan.steps == 0 || plan.steps % 2 != 0 {
            return Err(anyhow::anyhow!(
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
                plan.passes.histogram,
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
                plan.passes.bucket_local,
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
                plan.passes.bucket_chunks,
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
                plan.passes.bucket_apply,
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
                plan.passes.bucket_bases,
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
                plan.passes.scatter,
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
            passes: plan.passes.into(),
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

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        let passes = &self.passes;
        for step in 0..self.scatter.len() {
            record_compute_indirect(
                encoder,
                &passes.histogram,
                &self.histogram[step],
                &self.labels.histogram,
                &self.row_dispatch_args,
            )?;
            record_compute(
                encoder,
                &passes.bucket_local,
                &self.bucket_local[step],
                &self.labels.bucket_local,
                self.bucket_work_items,
            )?;
            record_compute(
                encoder,
                &passes.bucket_chunks,
                &self.bucket_chunks[step],
                &self.labels.bucket_chunks,
                self.bucket_chunk_work_items,
            )?;
            record_compute(
                encoder,
                &passes.bucket_apply,
                &self.bucket_apply[step],
                &self.labels.bucket_apply,
                self.bucket_work_items,
            )?;
            record_compute(
                encoder,
                &passes.bucket_bases,
                &self.bucket_bases[step],
                &self.labels.bucket_bases,
                self.bucket_count,
            )?;
            record_compute_indirect(
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
