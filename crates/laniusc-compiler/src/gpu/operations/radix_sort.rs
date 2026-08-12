use std::collections::HashMap;

use anyhow::{Result, anyhow};

use super::{record_direct_with_offsets, record_indirect_with_offsets};
use crate::gpu::{
    buffers::{DynamicUniformBuffer, LaniusBuffer, dynamic_uniforms_from_vals, uniform_from_val},
    compiler_graph::{
        CompilerGraphBuilder,
        CompilerPhase,
        RadixSortGraph,
        RadixSortGraphPasses,
        RadixSortGraphResources,
        ResourceDomain,
    },
    kernels::KernelRegistry,
    passes_core::PassData,
    resource_registry::{
        ResourceMap,
        buffer_binding_from_resources,
        reflected_bind_group_with_overrides,
    },
};

/// Identifies kernels participating in a repeated radix/key-scheduling step
/// from their reflected operation contract. The kernel registry uses this to
/// prepare the dynamic-parameter layout variant before daemon readiness.
pub(crate) fn uses_dynamic_uniform_kernel(reflection: &crate::reflection::SlangReflection) -> bool {
    let parameters = reflection
        .entry_points
        .iter()
        .find(|entry| entry.stage.as_deref() == Some("compute"))
        .and_then(|entry| entry.program_layout.as_ref())
        .map(|layout| {
            layout
                .parameters
                .iter()
                .flat_map(|set| set.parameters.iter())
                .collect::<Vec<_>>()
        })
        .unwrap_or_else(|| reflection.parameters.iter().collect());
    parameters
        .iter()
        .any(|parameter| parameter.name == "gParams")
        && parameters.iter().any(|parameter| {
            parameter.name.starts_with("radix_") || parameter.name == "target_schedule_order_in"
        })
}

/// Shader kernels implementing one stable radix-sort operation.
#[derive(Clone, Copy)]
struct RadixSortPasses<'a> {
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
pub(crate) struct RadixSortResources {
    pub count: &'static str,
    pub order: &'static str,
    pub temporary_order: &'static str,
    pub histogram: &'static str,
    pub bucket_prefix: &'static str,
    pub bucket_total: &'static str,
    pub bucket_base: &'static str,
}

pub(super) fn resolve_radix_sort_graph_resources(
    graph: &CompilerGraphBuilder,
    resources: RadixSortResources,
    dispatch_args: &str,
    count_binding: &'static str,
    keys: &[(&'static str, &'static str)],
) -> Result<RadixSortGraphResources, String> {
    let resource = |name: &str| {
        graph
            .resource_id(name)
            .ok_or_else(|| format!("radix sort resource `{name}` is not registered"))
    };
    Ok(RadixSortGraphResources {
        count: resource(resources.count)?,
        count_binding,
        keys: keys
            .iter()
            .map(|&(binding, name)| {
                resource(name).map(|resource| {
                    crate::gpu::compiler_graph::ReflectedResourceBinding {
                        binding,
                        resource,
                        mode: None,
                    }
                })
            })
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
pub(crate) struct RadixSortDefinition {
    pub phase: CompilerPhase,
    pub dispatch_domain: ResourceDomain,
    pub passes: RadixSortGraphPasses,
    pub kernels: RadixSortKernels,
    pub resources: RadixSortResources,
    pub dispatch_args: &'static str,
}

impl RadixSortDefinition {
    pub(crate) const fn label(self) -> &'static str {
        self.passes.order_to_temporary.histogram
    }

    pub(crate) fn plan<'a>(
        self,
        capacity: u32,
        small_capacity: u32,
        steps: u32,
        dispatch: RadixSortDispatch<'a>,
    ) -> RadixSortPlan<'a> {
        RadixSortPlan {
            label: self.label(),
            capacity,
            small_capacity,
            steps,
            kernels: self.kernels,
            dispatch,
            resources: self.resources,
        }
    }

    pub(crate) fn operation<P, F>(
        self,
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        resources: &ResourceMap<'_>,
        capacity: u32,
        small_capacity: u32,
        steps: u32,
        dispatch: RadixSortDispatch<'_>,
        make_params: F,
    ) -> Result<RadixSortOperation<P>>
    where
        P: encase::ShaderType + encase::internal::WriteInto,
        F: Fn(u32) -> P,
    {
        if small_capacity == 0 || capacity > small_capacity {
            resources.validate_graph_passes(self.passes.names())?;
        }
        RadixSortOperation::new(
            device,
            kernels,
            resources,
            self.plan(capacity, small_capacity, steps, dispatch),
            make_params,
        )
    }

    fn graph_resources(
        self,
        graph: &CompilerGraphBuilder,
        count_binding: &'static str,
        keys: &[(&'static str, &'static str)],
    ) -> Result<RadixSortGraphResources, String> {
        resolve_radix_sort_graph_resources(
            graph,
            self.resources,
            self.dispatch_args,
            count_binding,
            keys,
        )
    }

    pub(crate) fn register(
        self,
        graph: &mut CompilerGraphBuilder,
        capacity: u32,
        small_capacity: u32,
        digit_steps: u32,
        keys: &[&'static str],
    ) -> Result<(), String> {
        let bindings = keys.iter().map(|&name| (name, name)).collect::<Vec<_>>();
        self.register_with_bindings(
            graph,
            capacity,
            small_capacity,
            digit_steps,
            self.resources.count,
            &bindings,
        )
    }

    pub(crate) fn register_with_bindings(
        self,
        graph: &mut CompilerGraphBuilder,
        capacity: u32,
        small_capacity: u32,
        digit_steps: u32,
        count_binding: &'static str,
        keys: &[(&'static str, &'static str)],
    ) -> Result<(), String> {
        let resources = self.graph_resources(graph, count_binding, keys)?;
        graph.add_fragment(RadixSortGraph {
            phase: self.phase,
            dispatch_domain: self.dispatch_domain,
            digit_steps,
            starts_in_temporary: radix_sort_starts_in_temporary(
                capacity,
                small_capacity,
                digit_steps,
            ),
            schedule: self.passes,
            resources,
        })?;
        self.kernels.assign(graph, self.passes)?;
        for pass in self.passes.names() {
            graph.require_complete_reflection(pass)?;
        }
        Ok(())
    }
}

/// Key-specific kernels selected by one radix sort. Bucket prefix and base
/// construction are properties of the radix algorithm and remain shared.
#[derive(Clone, Copy)]
pub(crate) struct RadixSortKernels {
    small: Option<&'static str>,
    histogram: &'static str,
    scatter: &'static str,
}

impl RadixSortKernels {
    pub(crate) const fn new(histogram: &'static str, scatter: &'static str) -> Self {
        Self {
            small: None,
            histogram,
            scatter,
        }
    }

    pub(crate) const fn with_small(mut self, small: &'static str) -> Self {
        self.small = Some(small);
        self
    }

    fn resolve(self, kernels: &KernelRegistry) -> RadixSortPasses<'_> {
        RadixSortPasses {
            small: self.small.and_then(|key| kernels.optional(key)),
            histogram: kernels.dynamic_uniform_kernel(self.histogram, "gParams"),
            bucket_prefix: kernels.dynamic_uniform_kernel("radix/bucket_prefix", "gParams"),
            bucket_bases: kernels.dynamic_uniform_kernel("radix/bucket_bases", "gParams"),
            scatter: kernels.dynamic_uniform_kernel(self.scatter, "gParams"),
        }
    }

    fn assign(
        self,
        graph: &mut CompilerGraphBuilder,
        passes: RadixSortGraphPasses,
    ) -> Result<(), String> {
        for step in [passes.order_to_temporary, passes.temporary_to_order] {
            graph.assign_kernel(step.histogram, self.histogram)?;
            graph.assign_kernel(step.bucket_prefix, "radix/bucket_prefix")?;
            graph.assign_kernel(step.bucket_bases, "radix/bucket_bases")?;
            graph.assign_kernel(step.scatter, self.scatter)?;
        }
        Ok(())
    }
}

/// Configuration for one radix sort. Key extraction is implemented by the
/// supplied histogram and scatter shaders; the sorting algorithm is shared.
#[derive(Clone, Copy)]
pub(crate) struct RadixSortPlan<'a> {
    pub label: &'static str,
    pub capacity: u32,
    pub small_capacity: u32,
    pub steps: u32,
    pub kernels: RadixSortKernels,
    pub dispatch: RadixSortDispatch<'a>,
    pub resources: RadixSortResources,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum RadixSortStrategy {
    Small,
    Radix { steps: u32 },
}

pub(crate) const fn radix_sort_starts_in_temporary(
    capacity: u32,
    small_capacity: u32,
    steps: u32,
) -> bool {
    let uses_small_sort = small_capacity > 0 && capacity <= small_capacity;
    !uses_small_sort && steps % 2 != 0
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
            return Err(anyhow!(
                "radix sort `{label}` selected small sort without a small kernel"
            ));
        }
        return Ok(RadixSortStrategy::Small);
    }
    if steps == 0 {
        return Err(anyhow!(
            "radix sort `{label}` requires a positive radix step count, got {steps}"
        ));
    }
    Ok(RadixSortStrategy::Radix { steps })
}

/// A work domain can be generated on the GPU or fixed by the kernel shape.
#[derive(Clone, Copy)]
pub(crate) enum RadixDispatchDomain<'a> {
    Indirect(&'a LaniusBuffer<u32>),
    Direct(u32),
}

/// Dispatch domains required by the radix primitive.
#[derive(Clone, Copy)]
pub(crate) struct RadixSortDispatch<'a> {
    pub small: RadixDispatchDomain<'a>,
    pub rows: RadixDispatchDomain<'a>,
    pub bucket_prefix: RadixDispatchDomain<'a>,
    pub bucket_bases: RadixDispatchDomain<'a>,
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
    Indirect(LaniusBuffer<u32>),
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
    dynamic_offsets: &[u32],
) -> Result<()> {
    match domain {
        OwnedRadixDispatchDomain::Indirect(args) => {
            record_indirect_with_offsets(encoder, pass, group, label, args, dynamic_offsets)
        }
        OwnedRadixDispatchDomain::Direct(elements) => {
            record_direct_with_offsets(encoder, pass, group, label, *elements, dynamic_offsets)
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
    _small_params: Option<LaniusBuffer<P>>,
    radix_params: Option<DynamicUniformBuffer<P>>,
    steps: usize,
    small: Option<wgpu::BindGroup>,
    histogram: Vec<wgpu::BindGroup>,
    bucket_prefix: Option<wgpu::BindGroup>,
    bucket_bases: Option<wgpu::BindGroup>,
    scatter: Vec<wgpu::BindGroup>,
    initial_direction: usize,
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
    pub(crate) fn new<F>(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        registry: &HashMap<String, wgpu::BindingResource<'_>>,
        plan: RadixSortPlan<'_>,
        make_params: F,
    ) -> Result<Self>
    where
        F: Fn(u32) -> P,
    {
        let passes = plan.kernels.resolve(kernels);
        let order = buffer_binding_from_resources(registry, plan.resources.order)?;
        let strategy = select_strategy(
            plan.label,
            plan.capacity,
            plan.small_capacity,
            plan.steps,
            passes.small.is_some(),
        )?;
        if strategy == RadixSortStrategy::Small {
            let pass = passes
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
                    ("radix_order", order.clone()),
                ],
            )?;
            return Ok(Self {
                labels: RadixSortStageLabels::new(plan.label),
                passes: passes.into(),
                dispatch: plan.dispatch.into(),
                _small_params: Some(params),
                radix_params: None,
                steps: 0,
                small: Some(small),
                histogram: Vec::new(),
                bucket_prefix: None,
                bucket_bases: None,
                scatter: Vec::new(),
                initial_direction: 0,
            });
        }
        let RadixSortStrategy::Radix { steps } = strategy else {
            unreachable!("small strategy returned above")
        };
        let temporary_order =
            buffer_binding_from_resources(registry, plan.resources.temporary_order)?;
        let count = buffer_binding_from_resources(registry, plan.resources.count)?;
        let initial_direction = usize::from(radix_sort_starts_in_temporary(
            plan.capacity,
            plan.small_capacity,
            steps,
        ));
        let histogram_rows = buffer_binding_from_resources(registry, plan.resources.histogram)?;
        let bucket_prefix_rows =
            buffer_binding_from_resources(registry, plan.resources.bucket_prefix)?;
        let bucket_total = buffer_binding_from_resources(registry, plan.resources.bucket_total)?;
        let bucket_base = buffer_binding_from_resources(registry, plan.resources.bucket_base)?;
        let param_values = (0..steps).map(make_params).collect::<Vec<_>>();
        let params =
            dynamic_uniforms_from_vals(device, &format!("{}.params", plan.label), &param_values);
        let mut histogram = Vec::with_capacity(2);
        let mut scatter = Vec::with_capacity(2);
        for direction in 0..2 {
            let (read_order, write_order) = if direction == 0 {
                (order.clone(), temporary_order.clone())
            } else {
                (temporary_order.clone(), order.clone())
            };
            histogram.push(reflected_bind_group_with_overrides(
                device,
                &format!("{}.histogram.{direction}", plan.label),
                passes.histogram,
                registry,
                &[
                    ("gParams", params.binding()),
                    ("radix_order_in", read_order.clone()),
                    ("radix_block_histogram", histogram_rows.clone()),
                ],
            )?);
            scatter.push(reflected_bind_group_with_overrides(
                device,
                &format!("{}.scatter.{direction}", plan.label),
                passes.scatter,
                registry,
                &[
                    ("gParams", params.binding()),
                    ("radix_order_in", read_order),
                    ("radix_bucket_base", bucket_base.clone()),
                    ("radix_block_bucket_prefix", bucket_prefix_rows.clone()),
                    ("radix_order_out", write_order),
                ],
            )?);
        }
        let bucket_prefix = reflected_bind_group_with_overrides(
            device,
            &format!("{}.bucket_prefix", plan.label),
            passes.bucket_prefix,
            registry,
            &[
                ("gParams", params.binding()),
                ("name_count_in", count),
                ("radix_block_histogram", histogram_rows),
                ("radix_block_bucket_prefix", bucket_prefix_rows),
                ("radix_bucket_total", bucket_total.clone()),
            ],
        )?;
        let bucket_bases = reflected_bind_group_with_overrides(
            device,
            &format!("{}.bucket_bases", plan.label),
            passes.bucket_bases,
            registry,
            &[
                ("gParams", params.binding()),
                ("radix_bucket_total", bucket_total),
                ("radix_bucket_base", bucket_base),
            ],
        )?;

        Ok(Self {
            labels: RadixSortStageLabels::new(plan.label),
            passes: passes.into(),
            dispatch: plan.dispatch.into(),
            _small_params: None,
            radix_params: Some(params),
            steps: steps as usize,
            small: None,
            histogram,
            bucket_prefix: Some(bucket_prefix),
            bucket_bases: Some(bucket_bases),
            scatter,
            initial_direction,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
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
                &[],
            );
        }
        let params = self
            .radix_params
            .as_ref()
            .expect("non-small radix sort must own dynamic parameters");
        for step in 0..self.steps {
            let dynamic_offsets = [params.dynamic_offset(step)];
            let direction = (step + self.initial_direction) % 2;
            record_dispatch(
                encoder,
                &passes.histogram,
                &self.histogram[direction],
                &self.labels.histogram,
                &dispatch.rows,
                &dynamic_offsets,
            )?;
            record_dispatch(
                encoder,
                &passes.bucket_prefix,
                self.bucket_prefix
                    .as_ref()
                    .expect("non-small radix sort must bind bucket prefix"),
                &self.labels.bucket_prefix,
                &dispatch.bucket_prefix,
                &dynamic_offsets,
            )?;
            record_dispatch(
                encoder,
                &passes.bucket_bases,
                self.bucket_bases
                    .as_ref()
                    .expect("non-small radix sort must bind bucket bases"),
                &self.labels.bucket_bases,
                &dispatch.bucket_bases,
                &dynamic_offsets,
            )?;
            record_dispatch(
                encoder,
                &passes.scatter,
                &self.scatter[direction],
                &self.labels.scatter,
                &dispatch.rows,
                &dynamic_offsets,
            )?;
        }
        Ok(())
    }
}

/// A compiled stable radix sort. Users record the operation without handling
/// its histogram, prefix, bucket-base, scatter, or ping-pong stages.
pub(crate) struct RadixSortOperation<P> {
    sort: StandardRadixSortOperation<P>,
}

impl<P> RadixSortOperation<P>
where
    P: encase::ShaderType + encase::internal::WriteInto,
{
    pub(crate) fn new<F>(
        device: &wgpu::Device,
        kernels: &KernelRegistry,
        registry: &HashMap<String, wgpu::BindingResource<'_>>,
        plan: RadixSortPlan<'_>,
        make_params: F,
    ) -> Result<Self>
    where
        F: Fn(u32) -> P,
    {
        Ok(Self {
            sort: StandardRadixSortOperation::new(device, kernels, registry, plan, make_params)?,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.sort.record(encoder)
    }
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
    fn odd_scalable_schedules_start_with_temporary_order() {
        assert_eq!(
            select_strategy("keys", 2049, 2048, 23, true).unwrap(),
            RadixSortStrategy::Radix { steps: 23 }
        );
        assert!(radix_sort_starts_in_temporary(2049, 2048, 23));
        assert!(!radix_sort_starts_in_temporary(2049, 2048, 24));
        assert!(!radix_sort_starts_in_temporary(2048, 2048, 23));
    }

    #[test]
    fn zero_small_capacity_disables_the_small_strategy() {
        assert_eq!(
            select_strategy("claims", 0, 0, 6, false).unwrap(),
            RadixSortStrategy::Radix { steps: 6 }
        );
    }
}
