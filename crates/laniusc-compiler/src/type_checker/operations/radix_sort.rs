use super::super::*;

/// Shader kernels implementing one stable radix-sort operation.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct RadixSortPasses<'a> {
    pub small: Option<&'a PassData>,
    pub histogram: &'a PassData,
    pub bucket_prefix: &'a PassData,
    pub bucket_bases: &'a PassData,
    pub scatter: &'a PassData,
}

/// Names of the concrete resources participating in a radix sort.
///
/// The operation translates these stable graph identities to the generic
/// binding names exposed by radix kernels.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct RadixSortResources {
    pub count: &'static str,
    pub order: &'static str,
    pub temporary_order: &'static str,
    pub histogram: &'static str,
    pub bucket_prefix: &'static str,
    pub bucket_total: &'static str,
    pub bucket_base: &'static str,
}

pub(super) fn resolve_radix_sort_graph_resources(
    graph: &crate::gpu::compiler_graph::CompilerGraphBuilder,
    resources: RadixSortResources,
    dispatch_args: &str,
    keys: &[&str],
) -> Result<crate::gpu::compiler_graph::RadixSortGraphResources, String> {
    let resource = |name: &str| {
        graph
            .resource_id(name)
            .ok_or_else(|| format!("radix sort resource `{name}` is not registered"))
    };
    Ok(crate::gpu::compiler_graph::RadixSortGraphResources {
        count: resource(resources.count)?,
        keys: keys
            .iter()
            .map(|name| resource(name))
            .collect::<Result<Vec<_>, _>>()?,
        order: resource(resources.order)?,
        temporary_order: resource(resources.temporary_order)?,
        dispatch_args: resource(dispatch_args)?,
        histogram: resource(resources.histogram)?,
        bucket_prefix: resource(resources.bucket_prefix)?,
        bucket_total: resource(resources.bucket_total)?,
        bucket_base: resource(resources.bucket_base)?,
    })
}

/// Complete static contract for a stable radix sort.
///
/// The definition is shared by graph construction and executable operation
/// construction, so workspace identities and the GPU schedule cannot drift.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct RadixSortDefinition {
    pub dispatch_domain: crate::gpu::compiler_graph::ResourceDomain,
    pub passes: crate::gpu::compiler_graph::RadixSortGraphPasses,
    pub resources: RadixSortResources,
    pub dispatch_args: &'static str,
}

impl RadixSortDefinition {
    pub(in crate::type_checker) const fn label(self) -> &'static str {
        self.passes.order_to_temporary.histogram
    }

    fn graph_resources(
        self,
        graph: &crate::gpu::compiler_graph::CompilerGraphBuilder,
        keys: &[&str],
    ) -> Result<crate::gpu::compiler_graph::RadixSortGraphResources, String> {
        resolve_radix_sort_graph_resources(graph, self.resources, self.dispatch_args, keys)
    }

    pub(in crate::type_checker) fn register(
        self,
        graph: &mut crate::gpu::compiler_graph::CompilerGraphBuilder,
        digit_steps: u32,
        keys: &[&str],
    ) -> Result<(), String> {
        let resources = self.graph_resources(graph, keys)?;
        graph
            .add_fragment(crate::gpu::compiler_graph::RadixSortGraph {
                phase: crate::gpu::compiler_graph::CompilerPhase::TypeCheck,
                dispatch_domain: self.dispatch_domain,
                digit_steps,
                schedule: crate::gpu::compiler_graph::RadixSortGraphSchedule::Standard(self.passes),
                resources,
            })
            .map(|_| ())
    }
}

#[derive(Clone, Copy)]
pub(in crate::type_checker) struct RadixSortPairDefinition {
    pub key: RadixSortDefinition,
    pub slot: RadixSortDefinition,
}

impl RadixSortPairDefinition {
    pub(in crate::type_checker) fn register(
        self,
        graph: &mut crate::gpu::compiler_graph::CompilerGraphBuilder,
        digit_steps: u32,
        key_inputs: &[&str],
        slot_inputs: &[&str],
    ) -> Result<(), String> {
        let key = self.key.graph_resources(graph, key_inputs)?;
        let slot = self.slot.graph_resources(graph, slot_inputs)?;
        graph
            .add_fragment(crate::gpu::compiler_graph::RadixSortPairGraph {
                phase: crate::gpu::compiler_graph::CompilerPhase::TypeCheck,
                dispatch_domain: self.key.dispatch_domain,
                digit_steps,
                left_passes: self.key.passes,
                right_passes: self.slot.passes,
                left: key,
                right: slot,
            })
            .map(|_| ())
    }
}

/// Configuration for one radix sort. Key extraction is implemented by the
/// supplied histogram and scatter shaders; the sorting algorithm is shared.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct RadixSortPlan<'a> {
    pub label: &'static str,
    pub capacity: u32,
    pub small_capacity: u32,
    pub steps: u32,
    pub passes: RadixSortPasses<'a>,
    pub dispatch: RadixSortDispatch<'a>,
    pub resources: RadixSortResources,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum RadixSortStrategy {
    Small,
    Radix { steps: u32 },
}

fn select_strategy(
    label: &str,
    capacity: u32,
    small_capacity: u32,
    steps: u32,
    has_small_kernel: bool,
) -> Result<RadixSortStrategy> {
    if small_capacity > 0 && capacity <= small_capacity {
        if !has_small_kernel {
            return Err(anyhow::anyhow!(
                "radix sort `{label}` selected small sort without a small kernel"
            ));
        }
        return Ok(RadixSortStrategy::Small);
    }
    if steps == 0 || steps % 2 != 0 {
        return Err(anyhow::anyhow!(
            "radix sort `{label}` requires a positive even radix step count, got {steps}"
        ));
    }
    Ok(RadixSortStrategy::Radix { steps })
}

/// A work domain can be generated on the GPU or fixed by the kernel shape.
#[derive(Clone, Copy)]
pub(in crate::type_checker) enum RadixDispatchDomain<'a> {
    Indirect(&'a wgpu::Buffer),
    Direct(u32),
}

/// Dispatch domains required by the radix primitive.
#[derive(Clone, Copy)]
pub(in crate::type_checker) struct RadixSortDispatch<'a> {
    pub small: RadixDispatchDomain<'a>,
    pub rows: RadixDispatchDomain<'a>,
    pub bucket_prefix: RadixDispatchDomain<'a>,
    pub bucket_bases: RadixDispatchDomain<'a>,
}

/// One sort recorded as part of a shared compute-pass batch.
pub(in crate::type_checker) struct RadixSortBatchItem<'a, P> {
    pub sort: &'a RadixSortOperation<P>,
}

struct OwnedRadixSortPasses {
    small: Option<PassData>,
    histogram: PassData,
    bucket_prefix: PassData,
    bucket_bases: PassData,
    scatter: PassData,
}

impl From<RadixSortPasses<'_>> for OwnedRadixSortPasses {
    fn from(passes: RadixSortPasses<'_>) -> Self {
        Self {
            small: passes.small.cloned(),
            histogram: passes.histogram.clone(),
            bucket_prefix: passes.bucket_prefix.clone(),
            bucket_bases: passes.bucket_bases.clone(),
            scatter: passes.scatter.clone(),
        }
    }
}

enum OwnedRadixDispatchDomain {
    Indirect(wgpu::Buffer),
    Direct(u32),
}

impl From<RadixDispatchDomain<'_>> for OwnedRadixDispatchDomain {
    fn from(domain: RadixDispatchDomain<'_>) -> Self {
        match domain {
            RadixDispatchDomain::Indirect(args) => Self::Indirect(args.clone()),
            RadixDispatchDomain::Direct(elements) => Self::Direct(elements),
        }
    }
}

struct OwnedRadixSortDispatch {
    small: OwnedRadixDispatchDomain,
    rows: OwnedRadixDispatchDomain,
    bucket_prefix: OwnedRadixDispatchDomain,
    bucket_bases: OwnedRadixDispatchDomain,
}

impl From<RadixSortDispatch<'_>> for OwnedRadixSortDispatch {
    fn from(dispatch: RadixSortDispatch<'_>) -> Self {
        Self {
            small: dispatch.small.into(),
            rows: dispatch.rows.into(),
            bucket_prefix: dispatch.bucket_prefix.into(),
            bucket_bases: dispatch.bucket_bases.into(),
        }
    }
}

fn record_dispatch(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    group: &wgpu::BindGroup,
    label: &str,
    domain: &OwnedRadixDispatchDomain,
) -> Result<()> {
    match domain {
        OwnedRadixDispatchDomain::Indirect(args) => {
            record_compute_indirect(encoder, pass, group, label, args)
        }
        OwnedRadixDispatchDomain::Direct(elements) => {
            record_compute(encoder, pass, group, label, *elements)
        }
    }
}

/// A compiled stable radix-sort operation.
///
/// Construction expands the high-level operation into reflected bind groups;
/// recording expands it into the selected small-sort kernel or repeated
/// histogram/scan/base/scatter schedule. Callers never manipulate individual
/// radix passes.
struct StandardRadixSortOperation<P> {
    labels: RadixSortStageLabels,
    passes: OwnedRadixSortPasses,
    dispatch: OwnedRadixSortDispatch,
    _params: Vec<LaniusBuffer<P>>,
    small: Option<wgpu::BindGroup>,
    histogram: Vec<wgpu::BindGroup>,
    bucket_prefix: Vec<wgpu::BindGroup>,
    bucket_bases: Vec<wgpu::BindGroup>,
    scatter: Vec<wgpu::BindGroup>,
}

struct RadixSortStageLabels {
    small: String,
    histogram: String,
    bucket_prefix: String,
    bucket_bases: String,
    scatter: String,
}

impl RadixSortStageLabels {
    fn new(label: &str) -> Self {
        Self {
            small: format!("{label}.small"),
            histogram: format!("{label}.histogram"),
            bucket_prefix: format!("{label}.bucket_prefix"),
            bucket_bases: format!("{label}.bucket_bases"),
            scatter: format!("{label}.scatter"),
        }
    }
}

impl<P> StandardRadixSortOperation<P>
where
    P: encase::ShaderType + encase::internal::WriteInto,
{
    pub(in crate::type_checker) fn new<F>(
        device: &wgpu::Device,
        registry: &HashMap<String, wgpu::BindingResource<'_>>,
        plan: RadixSortPlan<'_>,
        make_params: F,
    ) -> Result<Self>
    where
        F: Fn(u32) -> P,
    {
        let order = buffer_from_resources(registry, plan.resources.order)?;
        let temporary_order = buffer_from_resources(registry, plan.resources.temporary_order)?;
        let count = buffer_from_resources(registry, plan.resources.count)?;
        let histogram_rows = buffer_from_resources(registry, plan.resources.histogram)?;
        let bucket_prefix_rows = buffer_from_resources(registry, plan.resources.bucket_prefix)?;
        let bucket_total = buffer_from_resources(registry, plan.resources.bucket_total)?;
        let bucket_base = buffer_from_resources(registry, plan.resources.bucket_base)?;

        let strategy = select_strategy(
            plan.label,
            plan.capacity,
            plan.small_capacity,
            plan.steps,
            plan.passes.small.is_some(),
        )?;
        if strategy == RadixSortStrategy::Small {
            let pass = plan
                .passes
                .small
                .expect("strategy selection checked the small kernel");
            let params = uniform_from_val(
                device,
                &format!("{}.params.small", plan.label),
                &make_params(0),
            );
            let small = reflected_bind_group_with_overrides(
                device,
                &format!("{}.small", plan.label),
                pass,
                registry,
                &[
                    ("gParams", params.as_entire_binding()),
                    ("radix_order", order.as_entire_binding()),
                ],
            )?;
            return Ok(Self {
                labels: RadixSortStageLabels::new(plan.label),
                passes: plan.passes.into(),
                dispatch: plan.dispatch.into(),
                _params: vec![params],
                small: Some(small),
                histogram: Vec::new(),
                bucket_prefix: Vec::new(),
                bucket_bases: Vec::new(),
                scatter: Vec::new(),
            });
        }
        let RadixSortStrategy::Radix { steps } = strategy else {
            unreachable!("small strategy returned above")
        };
        let mut params = Vec::with_capacity(steps as usize);
        let mut histogram = Vec::with_capacity(steps as usize);
        let mut bucket_prefix = Vec::with_capacity(steps as usize);
        let mut bucket_bases = Vec::with_capacity(steps as usize);
        let mut scatter = Vec::with_capacity(steps as usize);
        for step in 0..steps {
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
                    ("radix_order_in", read_order.as_entire_binding()),
                    ("radix_block_histogram", histogram_rows.as_entire_binding()),
                ],
            )?);
            bucket_prefix.push(reflected_bind_group_with_overrides(
                device,
                &format!("{}.bucket_prefix.{step}", plan.label),
                plan.passes.bucket_prefix,
                registry,
                &[
                    ("gParams", step_params.as_entire_binding()),
                    ("name_count_in", count.as_entire_binding()),
                    ("radix_block_histogram", histogram_rows.as_entire_binding()),
                    (
                        "radix_block_bucket_prefix",
                        bucket_prefix_rows.as_entire_binding(),
                    ),
                    ("radix_bucket_total", bucket_total.as_entire_binding()),
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
            labels: RadixSortStageLabels::new(plan.label),
            passes: plan.passes.into(),
            dispatch: plan.dispatch.into(),
            _params: params,
            small: None,
            histogram,
            bucket_prefix,
            bucket_bases,
            scatter,
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        let passes = &self.passes;
        let dispatch = &self.dispatch;
        if let Some(small) = &self.small {
            return record_dispatch(
                encoder,
                passes
                    .small
                    .as_ref()
                    .expect("compiled small sort has a small kernel"),
                small,
                &self.labels.small,
                &dispatch.small,
            );
        }
        for step in 0..self.scatter.len() {
            record_dispatch(
                encoder,
                &passes.histogram,
                &self.histogram[step],
                &self.labels.histogram,
                &dispatch.rows,
            )?;
            record_dispatch(
                encoder,
                &passes.bucket_prefix,
                &self.bucket_prefix[step],
                &self.labels.bucket_prefix,
                &dispatch.bucket_prefix,
            )?;
            record_dispatch(
                encoder,
                &passes.bucket_bases,
                &self.bucket_bases[step],
                &self.labels.bucket_bases,
                &dispatch.bucket_bases,
            )?;
            record_dispatch(
                encoder,
                &passes.scatter,
                &self.scatter[step],
                &self.labels.scatter,
                &dispatch.rows,
            )?;
        }
        Ok(())
    }

    pub(in crate::type_checker) fn uses_small_kernel(&self) -> bool {
        self.small.is_some()
    }
}

/// A stable radix sort independent of the selected GPU prefix schedule.
///
/// Device-specific scheduling is chosen when the operation is built. Users of
/// the operation record a radix sort and do not branch on that implementation.
pub(in crate::type_checker) struct RadixSortOperation<P> {
    schedule: RadixSortSchedule<P>,
}

enum RadixSortSchedule<P> {
    Standard(StandardRadixSortOperation<P>),
    Hierarchical(super::hierarchical_radix_sort::HierarchicalRadixSortSchedule<P>),
}

impl<P> RadixSortOperation<P>
where
    P: encase::ShaderType + encase::internal::WriteInto,
{
    pub(in crate::type_checker) fn new<F>(
        device: &wgpu::Device,
        registry: &HashMap<String, wgpu::BindingResource<'_>>,
        plan: RadixSortPlan<'_>,
        make_params: F,
    ) -> Result<Self>
    where
        F: Fn(u32) -> P,
    {
        Ok(Self {
            schedule: RadixSortSchedule::Standard(StandardRadixSortOperation::new(
                device,
                registry,
                plan,
                make_params,
            )?),
        })
    }

    pub(in crate::type_checker) fn new_hierarchical<F>(
        device: &wgpu::Device,
        registry: &HashMap<String, wgpu::BindingResource<'_>>,
        plan: HierarchicalRadixSortPlan<'_>,
        make_params: F,
    ) -> Result<Self>
    where
        F: Fn(u32) -> P,
    {
        Ok(Self {
            schedule: RadixSortSchedule::Hierarchical(
                super::hierarchical_radix_sort::HierarchicalRadixSortSchedule::new(
                    device,
                    registry,
                    plan,
                    make_params,
                )?,
            ),
        })
    }

    pub(in crate::type_checker) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        match &self.schedule {
            RadixSortSchedule::Standard(sort) => sort.record(encoder),
            RadixSortSchedule::Hierarchical(sort) => sort.record(encoder),
        }
    }

    pub(in crate::type_checker) fn uses_small_kernel(&self) -> bool {
        match &self.schedule {
            RadixSortSchedule::Standard(sort) => sort.uses_small_kernel(),
            RadixSortSchedule::Hierarchical(_) => false,
        }
    }

    fn standard(&self) -> Result<&StandardRadixSortOperation<P>> {
        match &self.schedule {
            RadixSortSchedule::Standard(sort) => Ok(sort),
            RadixSortSchedule::Hierarchical(_) => Err(anyhow::anyhow!(
                "hierarchical radix scheduling cannot be placed in a standard radix batch"
            )),
        }
    }
}

fn record_batch_dispatch<'a>(
    batch: &mut crate::gpu::passes_core::ComputePassBatch<'a>,
    pass: &'a PassData,
    bind_group: &'a wgpu::BindGroup,
    domain: &'a OwnedRadixDispatchDomain,
) -> Result<()> {
    match domain {
        OwnedRadixDispatchDomain::Indirect(args) => {
            batch.record_raw_indirect(pass, bind_group, args);
            Ok(())
        }
        OwnedRadixDispatchDomain::Direct(elements) => batch.record_raw(pass, bind_group, *elements),
    }
}

/// Records independent radix sorts while sharing compute-pass boundaries.
///
/// This is a scheduling optimization only: each item remains an ordinary
/// stable radix sort with its own keys, ordering, and temporary storage.
pub(in crate::type_checker) fn record_radix_sort_batch<'a, P>(
    items: &'a [RadixSortBatchItem<'a, P>],
    encoder: &'a mut wgpu::CommandEncoder,
) -> Result<()>
where
    P: encase::ShaderType + encase::internal::WriteInto,
{
    let Some(_) = items.first() else {
        return Ok(());
    };
    let sorts = items
        .iter()
        .map(|item| item.sort.standard())
        .collect::<Result<Vec<_>>>()?;
    let first = sorts[0];
    if sorts.iter().any(|sort| sort.small.is_some()) {
        if sorts.iter().any(|sort| sort.small.is_none()) {
            return Err(anyhow::anyhow!(
                "batched radix sorts selected incompatible algorithms"
            ));
        }
        count_recorded_compute_pass();
        let mut small = crate::gpu::passes_core::ComputePassBatch::begin(
            encoder,
            "type_check.radix_sort.batch.small",
        );
        for sort in &sorts {
            record_batch_dispatch(
                &mut small,
                sort.passes
                    .small
                    .as_ref()
                    .expect("compiled small sort has a small kernel"),
                sort.small.as_ref().expect("small algorithm selected"),
                &sort.dispatch.small,
            )?;
        }
        return Ok(());
    }
    let steps = first.scatter.len();
    if sorts.iter().any(|sort| sort.scatter.len() != steps) {
        return Err(anyhow::anyhow!(
            "batched radix sorts must have the same digit-step count"
        ));
    }

    for step in 0..steps {
        count_recorded_compute_pass();
        let mut histogram = crate::gpu::passes_core::ComputePassBatch::begin(
            encoder,
            "type_check.radix_sort.batch.histogram",
        );
        for sort in &sorts {
            record_batch_dispatch(
                &mut histogram,
                &sort.passes.histogram,
                &sort.histogram[step],
                &sort.dispatch.rows,
            )?;
        }
        drop(histogram);

        count_recorded_compute_pass();
        let mut prefix = crate::gpu::passes_core::ComputePassBatch::begin(
            encoder,
            "type_check.radix_sort.batch.bucket_prefix",
        );
        for sort in &sorts {
            record_batch_dispatch(
                &mut prefix,
                &sort.passes.bucket_prefix,
                &sort.bucket_prefix[step],
                &sort.dispatch.bucket_prefix,
            )?;
        }
        drop(prefix);

        count_recorded_compute_pass();
        let mut bases = crate::gpu::passes_core::ComputePassBatch::begin(
            encoder,
            "type_check.radix_sort.batch.bucket_bases",
        );
        for sort in &sorts {
            record_batch_dispatch(
                &mut bases,
                &sort.passes.bucket_bases,
                &sort.bucket_bases[step],
                &sort.dispatch.bucket_bases,
            )?;
        }
        drop(bases);

        count_recorded_compute_pass();
        let mut scatter = crate::gpu::passes_core::ComputePassBatch::begin(
            encoder,
            "type_check.radix_sort.batch.scatter",
        );
        for sort in &sorts {
            record_batch_dispatch(
                &mut scatter,
                &sort.passes.scatter,
                &sort.scatter[step],
                &sort.dispatch.rows,
            )?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn radix_strategy_selects_small_kernel_at_its_capacity_boundary() {
        assert_eq!(
            select_strategy("keys", 2048, 2048, 24, true).unwrap(),
            RadixSortStrategy::Small
        );
    }

    #[test]
    fn radix_strategy_rejects_schedules_that_leave_output_in_scratch() {
        let error = select_strategy("keys", 2049, 2048, 23, true).unwrap_err();
        assert!(error.to_string().contains("positive even radix step count"));
    }

    #[test]
    fn zero_small_capacity_disables_the_small_strategy() {
        assert_eq!(
            select_strategy("claims", 0, 0, 6, false).unwrap(),
            RadixSortStrategy::Radix { steps: 6 }
        );
    }
}
