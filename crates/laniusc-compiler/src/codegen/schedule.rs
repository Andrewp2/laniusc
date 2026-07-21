//! Shared stable GPU scheduling for semantic lowering records.
//!
//! Semantic lowering creates one `TargetScheduleKey` per semantic instruction.
//! This component owns the graph-colored radix workspace and pre-created bind
//! groups that turn those keys into a stable lexicographic execution order.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    lowering::{ScanHierarchyParams, ScanParams, bound, make_group, record_direct},
    lowering_ir::{TARGET_SCHEDULE_RADIX_STEPS, TargetScheduleKey},
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{
        BoundGraphResource,
        CompilerGraph,
        CompilerGraphAllocations,
        CompilerGraphWorkspace,
    },
    passes_core::{PassData, make_pass_data_from_shader_key},
    scan::{HierarchicalScanLevel, hierarchical_scan_levels},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct ScheduleParams {
    target_capacity: u32,
    max_blocks: u32,
    key_step: u32,
    reserved: u32,
}

struct SchedulePasses {
    slot_count: PassData,
    histogram: PassData,
    scan_local: PassData,
    scan_up: PassData,
    scan_down: PassData,
    scan_apply: PassData,
    scatter: PassData,
}

struct ScheduleStep {
    _params: LaniusBuffer<ScheduleParams>,
    histogram: wgpu::BindGroup,
    scatter: wgpu::BindGroup,
}

/// Fully resident scheduler. `record` creates no pipelines, buffers, uniforms,
/// or bind groups.
pub(crate) struct GpuStableScheduleSorter {
    target_capacity: u32,
    slot_capacity: u32,
    passes: SchedulePasses,
    slot_count_group: wgpu::BindGroup,
    scan_local_group: wgpu::BindGroup,
    scan_up_groups: Vec<wgpu::BindGroup>,
    scan_down_groups: Vec<wgpu::BindGroup>,
    scan_apply_group: wgpu::BindGroup,
    steps: Vec<ScheduleStep>,
    scan_levels: Vec<HierarchicalScanLevel>,
    _slot_params: LaniusBuffer<ScheduleParams>,
    _scan_params: LaniusBuffer<ScanParams>,
    _hierarchy_params: Vec<LaniusBuffer<ScanHierarchyParams>>,
    order: LaniusBuffer<u32>,
    _order_tmp: LaniusBuffer<u32>,
    _slot_count: LaniusBuffer<u32>,
    _histogram: LaniusBuffer<u32>,
    _global_prefix: LaniusBuffer<u32>,
    _scan_local: LaniusBuffer<u32>,
    _scan_block_sum: LaniusBuffer<u32>,
    _scan_block_prefix: LaniusBuffer<u32>,
    _scan_hierarchy: LaniusBuffer<u32>,
    _scan_total: LaniusBuffer<u32>,
}

impl GpuStableScheduleSorter {
    pub(crate) fn new_semantic(
        device: &wgpu::Device,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        semantic_capacity: u32,
        total: &LaniusBuffer<u32>,
        keys: &LaniusBuffer<TargetScheduleKey>,
        order: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        Self::new_scoped(
            device,
            graph,
            workspace,
            allocations,
            semantic_capacity,
            total,
            keys,
            order,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn new_scoped(
        device: &wgpu::Device,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        target_capacity: u32,
        total: &LaniusBuffer<u32>,
        keys: &LaniusBuffer<TargetScheduleKey>,
        order: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        let names = ScheduleResourceNames::semantic();
        let alias = |name: &str, count: u32| -> Result<LaniusBuffer<u32>> {
            let resource = graph
                .resource_id(name)
                .with_context(|| format!("lowering graph is missing {name}"))?;
            workspace
                .alias(graph, resource, count.max(1) as usize)
                .map_err(anyhow::Error::msg)
        };
        let max_blocks = target_capacity.max(1).div_ceil(256);
        let slot_capacity = max_blocks.saturating_mul(256);
        let scan_blocks = slot_capacity.div_ceil(256).max(1);
        let order_tmp = alias(names.order_tmp, target_capacity)?;
        let slot_count = alias(names.slot_count, 1)?;
        let histogram = alias(names.histogram, slot_capacity)?;
        let global_prefix = alias(names.global_prefix, slot_capacity)?;
        let scan_local = alias("lir.semantic.schedule_scan_local", slot_capacity)?;
        let scan_block_sum = alias("lir.semantic.schedule_scan_block_sum", scan_blocks)?;
        let scan_block_prefix = alias("lir.semantic.schedule_scan_block_prefix", scan_blocks)?;
        let scan_hierarchy = alias("lir.semantic.schedule_scan_hierarchy", scan_blocks)?;
        let scan_total = alias("lir.semantic.schedule_scan_total", 1)?;

        let passes = SchedulePasses {
            slot_count: load(
                device,
                "lir.target.schedule.slot_count",
                "codegen/lir/schedule/slot_count",
            )?,
            histogram: load(
                device,
                "lir.target.schedule.histogram",
                "codegen/lir/schedule/histogram",
            )?,
            scan_local: load(
                device,
                "lir.target.schedule.scan.local",
                "type_checker/counted/scan/00_local",
            )?,
            scan_up: load(
                device,
                "lir.target.schedule.scan.up",
                "type_checker/counted/scan/01_hierarchy_up",
            )?,
            scan_down: load(
                device,
                "lir.target.schedule.scan.down",
                "type_checker/counted/scan/02_hierarchy_down",
            )?,
            scan_apply: load(
                device,
                "lir.target.schedule.scan.apply",
                "type_checker/counted/scan/02_apply",
            )?,
            scatter: load(
                device,
                "lir.target.schedule.scatter",
                "codegen/lir/schedule/scatter",
            )?,
        };
        let slot_params = uniform_from_val(
            device,
            "lir.target.schedule.slot_count.params",
            &ScheduleParams {
                target_capacity,
                max_blocks,
                key_step: 0,
                reserved: 0,
            },
        );
        let scan_params = uniform_from_val(
            device,
            "lir.target.schedule.scan.params",
            &ScanParams {
                n_items: slot_capacity,
                n_blocks: scan_blocks,
                scan_step: 0,
            },
        );
        let scan_levels = hierarchical_scan_levels(scan_blocks);
        let hierarchy_params = scan_levels
            .iter()
            .enumerate()
            .map(|(index, level)| {
                let parent = scan_levels.get(index + 1);
                uniform_from_val(
                    device,
                    &format!("lir.target.schedule.scan.hierarchy.{index}"),
                    &ScanHierarchyParams {
                        n_items: slot_capacity,
                        n_blocks: scan_blocks,
                        level_divisor: level.divisor,
                        level_offset: level.offset,
                        parent_divisor: parent.map_or(0, |parent| parent.divisor),
                        parent_offset: parent.map_or(0, |parent| parent.offset),
                    },
                )
            })
            .collect::<Vec<_>>();

        let slot_count_group = make_group(
            device,
            &passes.slot_count,
            "lir.target.schedule.slot_count.bind_group",
            &[
                ("gParams", slot_params.as_entire_binding()),
                ("target_lir_total", total.as_entire_binding()),
                ("target_schedule_slot_count", slot_count.as_entire_binding()),
            ],
        )?;
        let scan_local_group = make_group(
            device,
            &passes.scan_local,
            "lir.target.schedule.scan.local.bind_group",
            &[
                ("gScan", scan_params.as_entire_binding()),
                ("scan_count", slot_count.as_entire_binding()),
                ("scan_input", histogram.as_entire_binding()),
                ("scan_local_prefix", scan_local.as_entire_binding()),
                ("scan_block_sum", scan_block_sum.as_entire_binding()),
            ],
        )?;
        let scan_up_groups = hierarchy_params
            .iter()
            .map(|params| {
                make_group(
                    device,
                    &passes.scan_up,
                    "lir.target.schedule.scan.up.bind_group",
                    &[
                        ("gHierarchy", params.as_entire_binding()),
                        ("scan_count", slot_count.as_entire_binding()),
                        ("scan_block_sum", scan_block_sum.as_entire_binding()),
                        ("scan_block_prefix", scan_block_prefix.as_entire_binding()),
                        ("scan_hierarchy", scan_hierarchy.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let scan_down_groups = hierarchy_params
            .iter()
            .map(|params| {
                make_group(
                    device,
                    &passes.scan_down,
                    "lir.target.schedule.scan.down.bind_group",
                    &[
                        ("gHierarchy", params.as_entire_binding()),
                        ("scan_count", slot_count.as_entire_binding()),
                        ("scan_block_prefix", scan_block_prefix.as_entire_binding()),
                        ("scan_hierarchy", scan_hierarchy.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let scan_apply_group = make_group(
            device,
            &passes.scan_apply,
            "lir.target.schedule.scan.apply.bind_group",
            &[
                ("gScan", scan_params.as_entire_binding()),
                ("scan_count", slot_count.as_entire_binding()),
                ("scan_local_prefix", scan_local.as_entire_binding()),
                ("scan_block_prefix", scan_block_prefix.as_entire_binding()),
                ("scan_output_prefix", global_prefix.as_entire_binding()),
                ("scan_total", scan_total.as_entire_binding()),
            ],
        )?;
        let mut steps = Vec::with_capacity(TARGET_SCHEDULE_RADIX_STEPS as usize);
        for key_step in 0..TARGET_SCHEDULE_RADIX_STEPS {
            let params = uniform_from_val(
                device,
                &format!("lir.target.schedule.radix.params.{key_step}"),
                &ScheduleParams {
                    target_capacity,
                    max_blocks,
                    key_step,
                    reserved: 0,
                },
            );
            let (input, output) = if key_step % 2 == 0 {
                (order, &order_tmp)
            } else {
                (&order_tmp, order)
            };
            let histogram_group = make_group(
                device,
                &passes.histogram,
                "lir.target.schedule.histogram.bind_group",
                &[
                    ("gParams", params.as_entire_binding()),
                    ("target_lir_total", total.as_entire_binding()),
                    ("target_schedule_key", keys.as_entire_binding()),
                    ("target_schedule_order_in", input.as_entire_binding()),
                    ("target_schedule_histogram", histogram.as_entire_binding()),
                ],
            )?;
            let scatter_group = make_group(
                device,
                &passes.scatter,
                "lir.target.schedule.scatter.bind_group",
                &[
                    ("gParams", params.as_entire_binding()),
                    ("target_lir_total", total.as_entire_binding()),
                    ("target_schedule_key", keys.as_entire_binding()),
                    ("target_schedule_order_in", input.as_entire_binding()),
                    (
                        "target_schedule_global_prefix",
                        global_prefix.as_entire_binding(),
                    ),
                    ("target_schedule_order_out", output.as_entire_binding()),
                ],
            )?;
            steps.push(ScheduleStep {
                _params: params,
                histogram: histogram_group,
                scatter: scatter_group,
            });
        }

        validate_bindings(
            graph,
            allocations,
            names,
            total,
            keys,
            order,
            &order_tmp,
            &slot_count,
            &histogram,
            &global_prefix,
            &scan_local,
            &scan_block_sum,
            &scan_block_prefix,
            &scan_hierarchy,
            &scan_total,
        )?;

        Ok(Self {
            target_capacity,
            slot_capacity,
            passes,
            slot_count_group,
            scan_local_group,
            scan_up_groups,
            scan_down_groups,
            scan_apply_group,
            steps,
            scan_levels,
            _slot_params: slot_params,
            _scan_params: scan_params,
            _hierarchy_params: hierarchy_params,
            order: order.clone(),
            _order_tmp: order_tmp,
            _slot_count: slot_count,
            _histogram: histogram,
            _global_prefix: global_prefix,
            _scan_local: scan_local,
            _scan_block_sum: scan_block_sum,
            _scan_block_prefix: scan_block_prefix,
            _scan_hierarchy: scan_hierarchy,
            _scan_total: scan_total,
        })
    }

    pub(crate) fn output_order(&self) -> &LaniusBuffer<u32> {
        &self.order
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        record_direct(encoder, &self.passes.slot_count, &self.slot_count_group, 1)?;
        for step in &self.steps {
            record_direct(
                encoder,
                &self.passes.histogram,
                &step.histogram,
                self.target_capacity,
            )?;
            record_direct(
                encoder,
                &self.passes.scan_local,
                &self.scan_local_group,
                self.slot_capacity,
            )?;
            for (index, level) in self.scan_levels.iter().enumerate() {
                record_direct(
                    encoder,
                    &self.passes.scan_up,
                    &self.scan_up_groups[index],
                    level.count,
                )?;
            }
            for child in (0..self.scan_levels.len().saturating_sub(1)).rev() {
                record_direct(
                    encoder,
                    &self.passes.scan_down,
                    &self.scan_down_groups[child],
                    self.scan_levels[child].count,
                )?;
            }
            record_direct(
                encoder,
                &self.passes.scan_apply,
                &self.scan_apply_group,
                self.slot_capacity,
            )?;
            record_direct(
                encoder,
                &self.passes.scatter,
                &step.scatter,
                self.target_capacity,
            )?;
        }
        Ok(())
    }
}

fn load(device: &wgpu::Device, label: &str, shader: &str) -> Result<PassData> {
    make_pass_data_from_shader_key(device, label, "main", shader)
}

#[derive(Clone, Copy)]
struct ScheduleResourceNames {
    total: &'static str,
    keys: &'static str,
    order: &'static str,
    order_tmp: &'static str,
    slot_count: &'static str,
    histogram: &'static str,
    global_prefix: &'static str,
}

impl ScheduleResourceNames {
    const fn semantic() -> Self {
        Self {
            total: "lir.semantic.total",
            // Both records are four u32 schedule words in the same order.
            // Sort the semantic schedule directly instead of copying it into
            // a duplicate target-key column.
            keys: "lir.semantic.schedule",
            order: "lir.semantic.schedule_order",
            order_tmp: "lir.semantic.schedule_order_tmp",
            slot_count: "lir.semantic.schedule_slot_count",
            histogram: "lir.semantic.schedule_histogram",
            global_prefix: "lir.semantic.schedule_global_prefix",
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn validate_bindings(
    graph: &CompilerGraph,
    allocations: &CompilerGraphAllocations,
    names: ScheduleResourceNames,
    total: &LaniusBuffer<u32>,
    keys: &LaniusBuffer<TargetScheduleKey>,
    order: &LaniusBuffer<u32>,
    order_tmp: &LaniusBuffer<u32>,
    slot_count: &LaniusBuffer<u32>,
    histogram: &LaniusBuffer<u32>,
    global_prefix: &LaniusBuffer<u32>,
    scan_local: &LaniusBuffer<u32>,
    scan_block_sum: &LaniusBuffer<u32>,
    scan_block_prefix: &LaniusBuffer<u32>,
    scan_hierarchy: &LaniusBuffer<u32>,
    scan_total: &LaniusBuffer<u32>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    let validate = |pass: &str, bindings: Vec<BoundGraphResource>| {
        allocations
            .validate_pass_bindings(graph, graph.pass_id(pass).unwrap(), &bindings)
            .map_err(anyhow::Error::msg)
    };
    validate(
        "lir.semantic.schedule.slot_count",
        vec![
            bound("target_lir_total", resource(names.total), total)?,
            bound(
                "target_schedule_slot_count",
                resource(names.slot_count),
                slot_count,
            )?,
        ],
    )?;
    for (suffix, input, output) in [("even", order, order_tmp), ("odd", order_tmp, order)] {
        validate(
            if suffix == "even" {
                "lir.semantic.schedule.histogram.even"
            } else {
                "lir.semantic.schedule.histogram.odd"
            },
            vec![
                bound("target_lir_total", resource(names.total), total)?,
                bound("target_schedule_key", resource(names.keys), keys)?,
                bound(
                    "target_schedule_order_in",
                    resource(if suffix == "even" {
                        names.order
                    } else {
                        names.order_tmp
                    }),
                    input,
                )?,
                bound(
                    "target_schedule_histogram",
                    resource(names.histogram),
                    histogram,
                )?,
            ],
        )?;
        validate(
            if suffix == "even" {
                "lir.semantic.schedule.scan.local.even"
            } else {
                "lir.semantic.schedule.scan.local.odd"
            },
            vec![
                bound("scan_count", resource(names.slot_count), slot_count)?,
                bound("scan_input", resource(names.histogram), histogram)?,
                bound(
                    "scan_local_prefix",
                    resource("lir.semantic.schedule_scan_local"),
                    scan_local,
                )?,
                bound(
                    "scan_block_sum",
                    resource("lir.semantic.schedule_scan_block_sum"),
                    scan_block_sum,
                )?,
            ],
        )?;
        validate(
            if suffix == "even" {
                "lir.semantic.schedule.scan.hierarchy_up.even"
            } else {
                "lir.semantic.schedule.scan.hierarchy_up.odd"
            },
            vec![
                bound("scan_count", resource(names.slot_count), slot_count)?,
                bound(
                    "scan_block_sum",
                    resource("lir.semantic.schedule_scan_block_sum"),
                    scan_block_sum,
                )?,
                bound(
                    "scan_block_prefix",
                    resource("lir.semantic.schedule_scan_block_prefix"),
                    scan_block_prefix,
                )?,
                bound(
                    "scan_hierarchy",
                    resource("lir.semantic.schedule_scan_hierarchy"),
                    scan_hierarchy,
                )?,
            ],
        )?;
        validate(
            if suffix == "even" {
                "lir.semantic.schedule.scan.hierarchy_down.even"
            } else {
                "lir.semantic.schedule.scan.hierarchy_down.odd"
            },
            vec![
                bound("scan_count", resource(names.slot_count), slot_count)?,
                bound(
                    "scan_block_prefix",
                    resource("lir.semantic.schedule_scan_block_prefix"),
                    scan_block_prefix,
                )?,
                bound(
                    "scan_hierarchy",
                    resource("lir.semantic.schedule_scan_hierarchy"),
                    scan_hierarchy,
                )?,
            ],
        )?;
        validate(
            if suffix == "even" {
                "lir.semantic.schedule.scan.apply.even"
            } else {
                "lir.semantic.schedule.scan.apply.odd"
            },
            vec![
                bound("scan_count", resource(names.slot_count), slot_count)?,
                bound(
                    "scan_local_prefix",
                    resource("lir.semantic.schedule_scan_local"),
                    scan_local,
                )?,
                bound(
                    "scan_block_prefix",
                    resource("lir.semantic.schedule_scan_block_prefix"),
                    scan_block_prefix,
                )?,
                bound(
                    "scan_output_prefix",
                    resource(names.global_prefix),
                    global_prefix,
                )?,
                bound(
                    "scan_total",
                    resource("lir.semantic.schedule_scan_total"),
                    scan_total,
                )?,
            ],
        )?;
        validate(
            if suffix == "even" {
                "lir.semantic.schedule.scatter.even"
            } else {
                "lir.semantic.schedule.scatter.odd"
            },
            vec![
                bound("target_lir_total", resource(names.total), total)?,
                bound("target_schedule_key", resource(names.keys), keys)?,
                bound(
                    "target_schedule_order_in",
                    resource(if suffix == "even" {
                        names.order
                    } else {
                        names.order_tmp
                    }),
                    input,
                )?,
                bound(
                    "target_schedule_global_prefix",
                    resource(names.global_prefix),
                    global_prefix,
                )?,
                bound(
                    "target_schedule_order_out",
                    resource(if suffix == "even" {
                        names.order_tmp
                    } else {
                        names.order
                    }),
                    output,
                )?,
            ],
        )?;
    }
    Ok(())
}
