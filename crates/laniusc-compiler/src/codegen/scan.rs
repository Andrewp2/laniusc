//! Resident graph-backed hierarchical exclusive scan.

use anyhow::{Context, Result};

use super::lowering::{ScanHierarchyParams, ScanParams, bound, make_group, record_direct};
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

#[derive(Clone, Copy)]
pub(crate) struct GraphScanContract {
    pub local_pass: &'static str,
    pub up_pass: &'static str,
    pub down_pass: &'static str,
    pub apply_pass: &'static str,
    pub count: &'static str,
    pub input: &'static str,
    pub local: &'static str,
    pub block_sum: &'static str,
    pub block_prefix: &'static str,
    pub hierarchy: &'static str,
    pub output: &'static str,
    pub total: &'static str,
}

struct ScanPasses {
    local: PassData,
    up: PassData,
    down: PassData,
    apply: PassData,
}

/// All resources and bindings are fixed at construction. Recording is a pure
/// sequence of dispatches over the GPU-produced active count.
pub(crate) struct GpuResidentExclusiveScan {
    capacity: u32,
    passes: ScanPasses,
    levels: Vec<HierarchicalScanLevel>,
    local_group: wgpu::BindGroup,
    up_groups: Vec<wgpu::BindGroup>,
    down_groups: Vec<wgpu::BindGroup>,
    apply_group: wgpu::BindGroup,
    _params: LaniusBuffer<ScanParams>,
    _hierarchy_params: Vec<LaniusBuffer<ScanHierarchyParams>>,
    _local: LaniusBuffer<u32>,
    _block_sum: LaniusBuffer<u32>,
    _block_prefix: LaniusBuffer<u32>,
    _hierarchy: LaniusBuffer<u32>,
}

impl GpuResidentExclusiveScan {
    #[allow(clippy::too_many_arguments)]
    pub(crate) fn new(
        device: &wgpu::Device,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        allocations: &CompilerGraphAllocations,
        contract: GraphScanContract,
        capacity: u32,
        count: &LaniusBuffer<u32>,
        input: &LaniusBuffer<u32>,
        output: &LaniusBuffer<u32>,
        total: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        let blocks = capacity.max(1).div_ceil(256);
        let alias = |name: &str, rows: u32| -> Result<LaniusBuffer<u32>> {
            workspace
                .alias(
                    graph,
                    graph
                        .resource_id(name)
                        .with_context(|| format!("scan graph is missing {name}"))?,
                    rows.max(1) as usize,
                )
                .map_err(anyhow::Error::msg)
        };
        let local = alias(contract.local, capacity)?;
        let block_sum = alias(contract.block_sum, blocks)?;
        let block_prefix = alias(contract.block_prefix, blocks)?;
        let hierarchy = alias(contract.hierarchy, blocks)?;
        let passes = ScanPasses {
            local: load(
                device,
                "lir.scan.local",
                "type_checker/counted/scan/00_local",
            )?,
            up: load(
                device,
                "lir.scan.up",
                "type_checker/counted/scan/01_hierarchy_up",
            )?,
            down: load(
                device,
                "lir.scan.down",
                "type_checker/counted/scan/02_hierarchy_down",
            )?,
            apply: load(
                device,
                "lir.scan.apply",
                "type_checker/counted/scan/02_apply",
            )?,
        };
        let params = uniform_from_val(
            device,
            "lir.scan.params",
            &ScanParams {
                n_items: capacity.max(1),
                n_blocks: blocks,
                scan_step: 0,
            },
        );
        let levels = hierarchical_scan_levels(blocks);
        let hierarchy_params = levels
            .iter()
            .enumerate()
            .map(|(index, level)| {
                let parent = levels.get(index + 1);
                uniform_from_val(
                    device,
                    &format!("lir.scan.hierarchy.{index}"),
                    &ScanHierarchyParams {
                        n_items: capacity.max(1),
                        n_blocks: blocks,
                        level_divisor: level.divisor,
                        level_offset: level.offset,
                        parent_divisor: parent.map_or(0, |parent| parent.divisor),
                        parent_offset: parent.map_or(0, |parent| parent.offset),
                    },
                )
            })
            .collect::<Vec<_>>();
        let local_group = make_group(
            device,
            &passes.local,
            "lir.scan.local.bind_group",
            &[
                ("gScan", params.as_entire_binding()),
                ("scan_count", count.as_entire_binding()),
                ("scan_input", input.as_entire_binding()),
                ("scan_local_prefix", local.as_entire_binding()),
                ("scan_block_sum", block_sum.as_entire_binding()),
            ],
        )?;
        let up_groups = hierarchy_params
            .iter()
            .map(|hierarchy_params| {
                make_group(
                    device,
                    &passes.up,
                    "lir.scan.up.bind_group",
                    &[
                        ("gHierarchy", hierarchy_params.as_entire_binding()),
                        ("scan_count", count.as_entire_binding()),
                        ("scan_block_sum", block_sum.as_entire_binding()),
                        ("scan_block_prefix", block_prefix.as_entire_binding()),
                        ("scan_hierarchy", hierarchy.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let down_groups = hierarchy_params
            .iter()
            .map(|hierarchy_params| {
                make_group(
                    device,
                    &passes.down,
                    "lir.scan.down.bind_group",
                    &[
                        ("gHierarchy", hierarchy_params.as_entire_binding()),
                        ("scan_count", count.as_entire_binding()),
                        ("scan_block_prefix", block_prefix.as_entire_binding()),
                        ("scan_hierarchy", hierarchy.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let apply_group = make_group(
            device,
            &passes.apply,
            "lir.scan.apply.bind_group",
            &[
                ("gScan", params.as_entire_binding()),
                ("scan_count", count.as_entire_binding()),
                ("scan_local_prefix", local.as_entire_binding()),
                ("scan_block_prefix", block_prefix.as_entire_binding()),
                ("scan_output_prefix", output.as_entire_binding()),
                ("scan_total", total.as_entire_binding()),
            ],
        )?;
        validate(
            graph,
            allocations,
            contract,
            count,
            input,
            output,
            total,
            &local,
            &block_sum,
            &block_prefix,
            &hierarchy,
        )?;
        Ok(Self {
            capacity,
            passes,
            levels,
            local_group,
            up_groups,
            down_groups,
            apply_group,
            _params: params,
            _hierarchy_params: hierarchy_params,
            _local: local,
            _block_sum: block_sum,
            _block_prefix: block_prefix,
            _hierarchy: hierarchy,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        record_direct(
            encoder,
            &self.passes.local,
            &self.local_group,
            self.capacity,
        )?;
        for (index, level) in self.levels.iter().enumerate() {
            record_direct(
                encoder,
                &self.passes.up,
                &self.up_groups[index],
                level.count,
            )?;
        }
        for child in (0..self.levels.len().saturating_sub(1)).rev() {
            record_direct(
                encoder,
                &self.passes.down,
                &self.down_groups[child],
                self.levels[child].count,
            )?;
        }
        record_direct(
            encoder,
            &self.passes.apply,
            &self.apply_group,
            self.capacity,
        )
    }
}

fn load(device: &wgpu::Device, label: &str, shader: &str) -> Result<PassData> {
    make_pass_data_from_shader_key(device, label, "main", shader)
}

#[allow(clippy::too_many_arguments)]
fn validate(
    graph: &CompilerGraph,
    allocations: &CompilerGraphAllocations,
    contract: GraphScanContract,
    count: &LaniusBuffer<u32>,
    input: &LaniusBuffer<u32>,
    output: &LaniusBuffer<u32>,
    total: &LaniusBuffer<u32>,
    local: &LaniusBuffer<u32>,
    block_sum: &LaniusBuffer<u32>,
    block_prefix: &LaniusBuffer<u32>,
    hierarchy: &LaniusBuffer<u32>,
) -> Result<()> {
    let resource = |name: &str| graph.resource_id(name).unwrap();
    let run = |pass: &str, bindings: Vec<BoundGraphResource>| {
        allocations
            .validate_pass_bindings(graph, graph.pass_id(pass).unwrap(), &bindings)
            .map_err(anyhow::Error::msg)
    };
    run(
        contract.local_pass,
        vec![
            bound("scan_count", resource(contract.count), count)?,
            bound("scan_input", resource(contract.input), input)?,
            bound("scan_local_prefix", resource(contract.local), local)?,
            bound("scan_block_sum", resource(contract.block_sum), block_sum)?,
        ],
    )?;
    run(
        contract.up_pass,
        vec![
            bound("scan_count", resource(contract.count), count)?,
            bound("scan_block_sum", resource(contract.block_sum), block_sum)?,
            bound(
                "scan_block_prefix",
                resource(contract.block_prefix),
                block_prefix,
            )?,
            bound("scan_hierarchy", resource(contract.hierarchy), hierarchy)?,
        ],
    )?;
    run(
        contract.down_pass,
        vec![
            bound("scan_count", resource(contract.count), count)?,
            bound(
                "scan_block_prefix",
                resource(contract.block_prefix),
                block_prefix,
            )?,
            bound("scan_hierarchy", resource(contract.hierarchy), hierarchy)?,
        ],
    )?;
    run(
        contract.apply_pass,
        vec![
            bound("scan_count", resource(contract.count), count)?,
            bound("scan_local_prefix", resource(contract.local), local)?,
            bound(
                "scan_block_prefix",
                resource(contract.block_prefix),
                block_prefix,
            )?,
            bound("scan_output_prefix", resource(contract.output), output)?,
            bound("scan_total", resource(contract.total), total)?,
        ],
    )
}
