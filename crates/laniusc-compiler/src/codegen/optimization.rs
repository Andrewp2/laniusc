//! GPU-resident semantic-LIR to optimizer-IR projection.

use anyhow::{Context, Result};
use encase::ShaderType;

use super::{
    lowering::{GpuSemanticLirView, lowering_allocations_with_semantic},
    lowering_ir::{
        LoweringCapacities,
        LoweringStatus,
        SemanticLirAggregateElement,
        SemanticLirCallArg,
        SemanticLirFunction,
        SemanticLirLocal,
        SemanticLirParam,
        SemanticLirString,
    },
    optimization_ir::{
        OptIrAccessGroup,
        OptIrBlock,
        OptIrBlockArgument,
        OptIrBlockArgumentIncoming,
        OptIrDeclarationBlock,
        OptIrDominatorJump,
        OptIrDominatorTourLink,
        OptIrEdge,
        OptIrFunction,
        OptIrImmediateDominator,
        OptIrIncomingValue,
        OptIrNodeControl,
        OptIrNodeCore,
        OptIrNodeOperands,
        OptIrNodeResults,
        OptIrReachingDefinitionState,
        OptIrRegion,
        OptIrSsaDemand,
        OptIrUseGroup,
        OptIrValueDefinition,
    },
};
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    compiler_graph::{
        CompilerGraph,
        CompilerGraphWorkspace,
        CompilerPhase,
        PrefixScanGraphPasses,
        PrefixScanPairSpec,
        PrefixScanResources,
        PrefixScanSpec,
        RadixSortGraphPasses,
        RadixSortGraphStepPasses,
        ResourceDomain,
    },
    kernels::KernelRegistry,
    operations::{
        ClearBuffersOperation,
        ComputeOperation,
        PrefixScanOperation,
        PrefixScanPairOperation,
        RadixDispatchDomain,
        RadixSortDefinition,
        RadixSortDispatch,
        RadixSortKernels,
        RadixSortOperation,
        RadixSortResources,
    },
    resource_registry::ResourceMap,
    timer::GpuTimer,
};

pub(super) const OPT_IR_BLOCK_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationNodes,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.blocks.scan.local",
        hierarchy_up_first: "lir.opt.blocks.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.blocks.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.blocks.scan.block_prefix.down",
        apply: "lir.opt.blocks.scan.apply",
    },
    resources: PrefixScanResources {
        count: "lir.opt.total",
        input: "lir.opt.block_start_flag",
        output_prefix: "lir.opt.block_prefix",
        total: "lir.opt.block_total",
        dispatch_args: "lir.opt.block_scan_dispatch_args",
        local_prefix: "lir.opt.block_scan_local_prefix",
        block_sum: "lir.opt.block_scan_block_sum",
        block_prefix: "lir.opt.block_scan_block_prefix",
    },
};

pub(super) const OPT_IR_REGION_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationNodes,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.regions.scan.local",
        hierarchy_up_first: "lir.opt.regions.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.regions.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.regions.scan.block_prefix.down",
        apply: "lir.opt.regions.scan.apply",
    },
    resources: PrefixScanResources {
        count: "lir.opt.total",
        input: "lir.opt.block_start_flag",
        output_prefix: "lir.opt.block_prefix",
        total: "lir.opt.region_total",
        dispatch_args: "lir.opt.block_scan_dispatch_args",
        local_prefix: "lir.opt.block_scan_local_prefix",
        block_sum: "lir.opt.block_scan_block_sum",
        block_prefix: "lir.opt.block_scan_block_prefix",
    },
};

pub(super) const OPT_IR_EDGE_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationBlocks,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.edges.scan.local",
        hierarchy_up_first: "lir.opt.edges.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.edges.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.edges.scan.block_prefix.down",
        apply: "lir.opt.edges.scan.apply",
    },
    resources: PrefixScanResources {
        count: "lir.opt.block_total",
        input: "lir.opt.edge_count_by_block",
        output_prefix: "lir.opt.edge_prefix",
        total: "lir.opt.edge_total",
        dispatch_args: "lir.opt.edge_scan_dispatch_args",
        local_prefix: "lir.opt.edge_scan_local_prefix",
        block_sum: "lir.opt.edge_scan_block_sum",
        block_prefix: "lir.opt.edge_scan_block_prefix",
    },
};

pub(super) const OPT_IR_PREDECESSOR_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationBlocks,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.predecessors.scan.local",
        hierarchy_up_first: "lir.opt.predecessors.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.predecessors.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.predecessors.scan.block_prefix.down",
        apply: "lir.opt.predecessors.scan.apply",
    },
    resources: PrefixScanResources {
        count: "lir.opt.block_total",
        input: "lir.opt.edge_count_by_block",
        output_prefix: "lir.opt.edge_prefix",
        total: "lir.opt.predecessor_total",
        dispatch_args: "lir.opt.edge_scan_dispatch_args",
        local_prefix: "lir.opt.edge_scan_local_prefix",
        block_sum: "lir.opt.edge_scan_block_sum",
        block_prefix: "lir.opt.edge_scan_block_prefix",
    },
};

pub(super) const OPT_IR_DOMINATOR_CHILD_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationBlocks,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.dominators.children.scan.local",
        hierarchy_up_first: "lir.opt.dominators.children.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.dominators.children.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.dominators.children.scan.block_prefix.down",
        apply: "lir.opt.dominators.children.scan.apply",
    },
    resources: PrefixScanResources {
        count: "lir.opt.block_total",
        input: "lir.opt.edge_count_by_block",
        output_prefix: "lir.opt.predecessor_cursor",
        total: "lir.opt.predecessor_total",
        dispatch_args: "lir.opt.edge_scan_dispatch_args",
        local_prefix: "lir.opt.edge_scan_local_prefix",
        block_sum: "lir.opt.edge_scan_block_sum",
        block_prefix: "lir.opt.edge_scan_block_prefix",
    },
};

pub(super) const OPT_IR_ACCESS_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationNodes,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.access.scan.local",
        hierarchy_up_first: "lir.opt.access.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.access.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.access.scan.block_prefix.down",
        apply: "lir.opt.access.scan.apply",
    },
    resources: PrefixScanResources {
        count: "lir.opt.total",
        input: "lir.opt.access_flag",
        output_prefix: "lir.opt.access_prefix",
        total: "lir.opt.instruction_access_total",
        dispatch_args: "lir.opt.access_scan_dispatch_args",
        local_prefix: "lir.opt.access_scan_local_prefix",
        block_sum: "lir.opt.access_scan_block_sum",
        block_prefix: "lir.opt.access_scan_block_prefix",
    },
};

pub(super) const OPT_IR_ACCESS_GROUP_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationAccesses,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.access.groups.scan.local",
        hierarchy_up_first: "lir.opt.access.groups.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.access.groups.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.access.groups.scan.block_prefix.down",
        apply: "lir.opt.access.groups.scan.apply",
    },
    resources: PrefixScanResources {
        count: "lir.opt.access_total",
        input: "lir.opt.access_group_start_flag",
        output_prefix: "lir.opt.access_group_prefix",
        total: "lir.opt.access_group_total",
        dispatch_args: "lir.opt.access_radix_dispatch_args",
        local_prefix: "lir.opt.access_group_scan_local_prefix",
        block_sum: "lir.opt.access_group_scan_block_sum",
        block_prefix: "lir.opt.access_group_scan_block_prefix",
    },
};

pub(super) const OPT_IR_DECLARATION_BLOCK_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationAccesses,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.access.declaration_blocks.scan.local",
        hierarchy_up_first: "lir.opt.access.declaration_blocks.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.access.declaration_blocks.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.access.declaration_blocks.scan.block_prefix.down",
        apply: "lir.opt.access.declaration_blocks.scan.apply",
    },
    resources: PrefixScanResources {
        count: "lir.opt.declaration_access_total",
        input: "lir.opt.access_group_start_flag",
        output_prefix: "lir.opt.access_group_prefix",
        total: "lir.opt.declaration_block_total",
        dispatch_args: "lir.opt.access_radix_dispatch_args",
        local_prefix: "lir.opt.access_group_scan_local_prefix",
        block_sum: "lir.opt.access_group_scan_block_sum",
        block_prefix: "lir.opt.access_group_scan_block_prefix",
    },
};

pub(super) const OPT_IR_SSA_DEMAND_SEED_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationAccessGroups,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.ssa.demands.seed.scan.local",
        hierarchy_up_first: "lir.opt.ssa.demands.seed.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.ssa.demands.seed.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.ssa.demands.seed.scan.block_prefix.down",
        apply: "lir.opt.ssa.demands.seed.scan.apply",
    },
    resources: PrefixScanResources {
        count: "lir.opt.declaration_block_total",
        input: "lir.opt.ssa.demand_seed_flag",
        output_prefix: "lir.opt.ssa.demand_seed_prefix",
        total: "lir.opt.ssa.demand_total",
        dispatch_args: "lir.opt.access_radix_dispatch_args",
        local_prefix: "lir.opt.ssa.demand_seed_scan_local_prefix",
        block_sum: "lir.opt.ssa.demand_seed_scan_block_sum",
        block_prefix: "lir.opt.ssa.demand_seed_scan_block_prefix",
    },
};

pub(super) const OPT_IR_SSA_BLOCK_ARGUMENT_SCAN: PrefixScanPairSpec = PrefixScanPairSpec {
    left_label: "lir.opt.ssa.block_arguments",
    right_label: "lir.opt.ssa.block_argument_incoming",
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationSsaDemands,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.ssa.block_arguments.scan.local",
        hierarchy_up_first: "lir.opt.ssa.block_arguments.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.ssa.block_arguments.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.ssa.block_arguments.scan.block_prefix.down",
        apply: "lir.opt.ssa.block_arguments.scan.apply",
    },
    left: PrefixScanResources {
        count: "lir.opt.ssa.demand_total",
        input: "lir.opt.ssa.block_argument_flag",
        output_prefix: "lir.opt.ssa.block_argument_flag",
        total: "lir.opt.ssa.block_argument_total",
        dispatch_args: "lir.opt.ssa.demand_radix_dispatch_args",
        local_prefix: "lir.opt.ssa.block_argument_flag",
        block_sum: "lir.opt.ssa.block_argument_scan_block_sum",
        block_prefix: "lir.opt.ssa.block_argument_scan_block_prefix",
    },
    right: PrefixScanResources {
        count: "lir.opt.ssa.demand_total",
        input: "lir.opt.ssa.block_argument_incoming_count",
        output_prefix: "lir.opt.ssa.block_argument_incoming_count",
        total: "lir.opt.ssa.block_argument_incoming_total",
        dispatch_args: "lir.opt.ssa.demand_radix_dispatch_args",
        local_prefix: "lir.opt.ssa.block_argument_incoming_count",
        block_sum: "lir.opt.ssa.block_argument_incoming_scan_block_sum",
        block_prefix: "lir.opt.ssa.block_argument_incoming_scan_block_prefix",
    },
};

pub(super) const OPT_IR_SSA_BLOCK_ARGUMENT_USER_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationSsaBlockArguments,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.ssa.block_argument_users.scan.local",
        hierarchy_up_first: "lir.opt.ssa.block_argument_users.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.ssa.block_argument_users.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.ssa.block_argument_users.scan.block_prefix.down",
        apply: "lir.opt.ssa.block_argument_users.scan.apply",
    },
    resources: PrefixScanResources {
        count: "lir.opt.ssa.block_argument_total",
        input: "lir.opt.ssa.block_argument_user_count",
        output_prefix: "lir.opt.ssa.block_argument_user_prefix",
        total: "lir.opt.ssa.block_argument_user_total",
        dispatch_args: "lir.opt.ssa.demand_radix_dispatch_args",
        local_prefix: "lir.opt.ssa.block_argument_user_scan_local_prefix",
        block_sum: "lir.opt.ssa.block_argument_user_scan_block_sum",
        block_prefix: "lir.opt.ssa.block_argument_user_scan_block_prefix",
    },
};

pub(super) const OPT_IR_SSA_VALUE_SCAN: PrefixScanPairSpec = PrefixScanPairSpec {
    left_label: "lir.opt.ssa.node_values",
    right_label: "lir.opt.ssa.block_argument_values",
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationValues,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.ssa.values.scan.local",
        hierarchy_up_first: "lir.opt.ssa.values.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.ssa.values.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.ssa.values.scan.block_prefix.down",
        apply: "lir.opt.ssa.values.scan.apply",
    },
    left: PrefixScanResources {
        count: "lir.opt.total",
        input: "lir.opt.ssa.node_value_flag",
        output_prefix: "lir.opt.ssa.node_value_flag",
        total: "lir.opt.ssa.node_value_total",
        dispatch_args: "lir.opt.ssa.node_value_scan_dispatch_args",
        local_prefix: "lir.opt.ssa.node_value_flag",
        block_sum: "lir.opt.ssa.node_value_scan_block_sum",
        block_prefix: "lir.opt.ssa.node_value_scan_block_prefix",
    },
    right: PrefixScanResources {
        count: "lir.opt.ssa.block_argument_total",
        input: "lir.opt.ssa.block_argument_value_flag",
        output_prefix: "lir.opt.ssa.block_argument_value_flag",
        total: "lir.opt.ssa.surviving_block_argument_total",
        dispatch_args: "lir.opt.ssa.block_argument_value_scan_dispatch_args",
        local_prefix: "lir.opt.ssa.block_argument_value_flag",
        block_sum: "lir.opt.ssa.block_argument_value_scan_block_sum",
        block_prefix: "lir.opt.ssa.block_argument_value_scan_block_prefix",
    },
};

pub(super) const OPT_IR_SSA_USE_SCAN: PrefixScanPairSpec = PrefixScanPairSpec {
    left_label: "lir.opt.ssa.node_uses",
    right_label: "lir.opt.ssa.call_uses",
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationNodes,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.ssa.uses.scan.local",
        hierarchy_up_first: "lir.opt.ssa.uses.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.ssa.uses.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.ssa.uses.scan.block_prefix.down",
        apply: "lir.opt.ssa.uses.scan.apply",
    },
    left: PrefixScanResources {
        count: "lir.opt.total",
        input: "lir.opt.ssa.node_use_count",
        output_prefix: "lir.opt.ssa.node_use_count",
        total: "lir.opt.ssa.node_use_total",
        dispatch_args: "lir.opt.ssa.node_use_scan_dispatch_args",
        local_prefix: "lir.opt.ssa.node_use_count",
        block_sum: "lir.opt.ssa.node_use_scan_block_sum",
        block_prefix: "lir.opt.ssa.node_use_scan_block_prefix",
    },
    right: PrefixScanResources {
        count: "lir.semantic.call_arg_total",
        input: "lir.opt.ssa.call_use_flag",
        output_prefix: "lir.opt.ssa.call_use_flag",
        total: "lir.opt.ssa.call_use_total",
        dispatch_args: "lir.opt.ssa.call_use_scan_dispatch_args",
        local_prefix: "lir.opt.ssa.call_use_flag",
        block_sum: "lir.opt.ssa.call_use_scan_block_sum",
        block_prefix: "lir.opt.ssa.call_use_scan_block_prefix",
    },
};

pub(super) const OPT_IR_SSA_AGGREGATE_USE_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationUses,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.ssa.aggregate_uses.scan.local",
        hierarchy_up_first: "lir.opt.ssa.aggregate_uses.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.ssa.aggregate_uses.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.ssa.aggregate_uses.scan.block_prefix.down",
        apply: "lir.opt.ssa.aggregate_uses.scan.apply",
    },
    resources: PrefixScanResources {
        count: "lir.semantic.aggregate_element_total",
        input: "lir.opt.ssa.aggregate_use_flag",
        output_prefix: "lir.opt.ssa.aggregate_use_flag",
        total: "lir.opt.ssa.aggregate_use_total",
        dispatch_args: "lir.opt.ssa.aggregate_use_scan_dispatch_args",
        local_prefix: "lir.opt.ssa.aggregate_use_flag",
        block_sum: "lir.opt.ssa.aggregate_use_scan_block_sum",
        block_prefix: "lir.opt.ssa.aggregate_use_scan_block_prefix",
    },
};

pub(super) const OPT_IR_ACCESS_RADIX_SORT: RadixSortDefinition = RadixSortDefinition {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationAccesses,
    small_pass: "lir.opt.access.sort",
    passes: RadixSortGraphPasses {
        order_to_temporary: RadixSortGraphStepPasses {
            histogram: "lir.opt.access.sort.histogram.a",
            bucket_prefix: "lir.opt.access.sort.prefix.a",
            bucket_bases: "lir.opt.access.sort.bases.a",
            scatter: "lir.opt.access.sort.scatter.a",
        },
        temporary_to_order: RadixSortGraphStepPasses {
            histogram: "lir.opt.access.sort.histogram.b",
            bucket_prefix: "lir.opt.access.sort.prefix.b",
            bucket_bases: "lir.opt.access.sort.bases.b",
            scatter: "lir.opt.access.sort.scatter.b",
        },
    },
    kernels: RadixSortKernels::new(
        "codegen/lir/optimization/access_sort_histogram",
        "codegen/lir/optimization/access_sort_scatter",
    ),
    resources: RadixSortResources {
        count: "lir.opt.access_total",
        order: "lir.opt.access_order",
        temporary_order: "lir.opt.access_order_tmp",
        histogram: "lir.opt.access_radix_histogram",
        bucket_prefix: "lir.opt.access_radix_bucket_prefix",
        bucket_total: "lir.opt.access_radix_bucket_total",
        bucket_base: "lir.opt.access_radix_bucket_base",
    },
    dispatch_args: "lir.opt.access_radix_dispatch_args",
};

pub(super) const OPT_IR_SSA_DEMAND_RADIX_SORT: RadixSortDefinition = RadixSortDefinition {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationSsaDemands,
    small_pass: "lir.opt.ssa.demands.sort",
    passes: RadixSortGraphPasses {
        order_to_temporary: RadixSortGraphStepPasses {
            histogram: "lir.opt.ssa.demands.sort.histogram.a",
            bucket_prefix: "lir.opt.ssa.demands.sort.prefix.a",
            bucket_bases: "lir.opt.ssa.demands.sort.bases.a",
            scatter: "lir.opt.ssa.demands.sort.scatter.a",
        },
        temporary_to_order: RadixSortGraphStepPasses {
            histogram: "lir.opt.ssa.demands.sort.histogram.b",
            bucket_prefix: "lir.opt.ssa.demands.sort.prefix.b",
            bucket_bases: "lir.opt.ssa.demands.sort.bases.b",
            scatter: "lir.opt.ssa.demands.sort.scatter.b",
        },
    },
    kernels: RadixSortKernels::new(
        "codegen/lir/optimization/ssa_demand_sort_histogram",
        "codegen/lir/optimization/ssa_demand_sort_scatter",
    ),
    resources: RadixSortResources {
        count: "lir.opt.ssa.demand_total",
        order: "lir.opt.ssa.demand_order",
        temporary_order: "lir.opt.ssa.demand_order_tmp",
        histogram: "lir.opt.ssa.demand_radix_histogram",
        bucket_prefix: "lir.opt.ssa.demand_radix_bucket_prefix",
        bucket_total: "lir.opt.ssa.demand_radix_bucket_total",
        bucket_base: "lir.opt.ssa.demand_radix_bucket_base",
    },
    dispatch_args: "lir.opt.ssa.demand_radix_dispatch_args",
};

pub(super) const OPT_IR_SSA_USE_RADIX_SORT: RadixSortDefinition = RadixSortDefinition {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationUses,
    small_pass: "lir.opt.ssa.uses.sort",
    passes: RadixSortGraphPasses {
        order_to_temporary: RadixSortGraphStepPasses {
            histogram: "lir.opt.ssa.uses.sort.histogram.a",
            bucket_prefix: "lir.opt.ssa.uses.sort.prefix.a",
            bucket_bases: "lir.opt.ssa.uses.sort.bases.a",
            scatter: "lir.opt.ssa.uses.sort.scatter.a",
        },
        temporary_to_order: RadixSortGraphStepPasses {
            histogram: "lir.opt.ssa.uses.sort.histogram.b",
            bucket_prefix: "lir.opt.ssa.uses.sort.prefix.b",
            bucket_bases: "lir.opt.ssa.uses.sort.bases.b",
            scatter: "lir.opt.ssa.uses.sort.scatter.b",
        },
    },
    kernels: RadixSortKernels::new(
        "codegen/lir/optimization/ssa_use_sort_histogram",
        "codegen/lir/optimization/ssa_use_sort_scatter",
    ),
    resources: RadixSortResources {
        count: "lir.opt.ssa.use_total",
        order: "lir.opt.ssa.use_order",
        temporary_order: "lir.opt.ssa.use_order_tmp",
        histogram: "lir.opt.ssa.use_radix_histogram",
        bucket_prefix: "lir.opt.ssa.use_radix_bucket_prefix",
        bucket_total: "lir.opt.ssa.use_radix_bucket_total",
        bucket_base: "lir.opt.ssa.use_radix_bucket_base",
    },
    dispatch_args: "lir.opt.ssa.use_radix_dispatch_args",
};

pub(super) const OPT_IR_SSA_USE_GROUP_SCAN: PrefixScanSpec = PrefixScanSpec {
    phase: CompilerPhase::Optimization,
    dispatch_domain: ResourceDomain::OptimizationUses,
    passes: PrefixScanGraphPasses {
        local: "lir.opt.ssa.use_groups.scan.local",
        hierarchy_up_first: "lir.opt.ssa.use_groups.scan.block_prefix",
        hierarchy_up_rest: "lir.opt.ssa.use_groups.scan.block_prefix.rest",
        hierarchy_down: "lir.opt.ssa.use_groups.scan.block_prefix.down",
        apply: "lir.opt.ssa.use_groups.scan.apply",
    },
    resources: PrefixScanResources {
        count: "lir.opt.ssa.use_total",
        input: "lir.opt.ssa.use_group_start_flag",
        output_prefix: "lir.opt.ssa.use_group_start_flag",
        total: "lir.opt.ssa.use_group_total",
        dispatch_args: "lir.opt.ssa.use_group_scan_dispatch_args",
        local_prefix: "lir.opt.ssa.use_group_start_flag",
        block_sum: "lir.opt.ssa.use_group_scan_block_sum",
        block_prefix: "lir.opt.ssa.use_group_scan_block_prefix",
    },
};

const RADIX_ROWS_PER_BLOCK: u32 = 256;
const RADIX_BUCKET_COUNT: u32 = 256;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct OptIrAccessRadixLayout {
    pub subject_bits: u32,
    pub steps: u32,
    pub blocks: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct OptIrSsaDemandRadixLayout {
    pub block_bits: u32,
    pub declaration_bits: u32,
    pub steps: u32,
    pub blocks: u32,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) struct OptIrSsaUseRadixLayout {
    pub key_bits: u32,
    pub steps: u32,
    pub blocks: u32,
}

/// Capacity-derived key layout for stable access grouping.
///
/// Metadata rows precede scheduled instruction rows before sorting, so a
/// stable `(domain, subject)` order preserves control position without adding
/// it to the radix key. Declaration and memory subjects occupy distinct
/// domains even when their numeric IDs coincide.
pub(super) fn opt_ir_access_radix_layout(capacities: LoweringCapacities) -> OptIrAccessRadixLayout {
    let subject_capacity = capacities
        .declaration_capacity()
        .max(capacities.semantic_instructions)
        .max(1);
    let max_subject = subject_capacity - 1;
    let subject_bits = (u32::BITS - max_subject.leading_zeros()).max(1);
    let steps = (subject_bits + 1).div_ceil(8);
    let blocks = capacities
        .optimization_access_capacity()
        .div_ceil(RADIX_ROWS_PER_BLOCK)
        .max(1);
    OptIrAccessRadixLayout {
        subject_bits,
        steps,
        blocks,
    }
}

pub(super) fn opt_ir_ssa_demand_radix_layout(
    capacities: LoweringCapacities,
) -> OptIrSsaDemandRadixLayout {
    let max_block = capacities.optimization_block_capacity() - 1;
    let max_declaration = capacities.declaration_capacity() - 1;
    let block_bits = (u32::BITS - max_block.leading_zeros()).max(1);
    let declaration_bits = (u32::BITS - max_declaration.leading_zeros()).max(1);
    let steps = (block_bits + declaration_bits).div_ceil(8);
    let blocks = capacities
        .optimization_ssa_demand_capacity()
        .div_ceil(RADIX_ROWS_PER_BLOCK)
        .max(1);
    OptIrSsaDemandRadixLayout {
        block_bits,
        declaration_bits,
        steps,
        blocks,
    }
}

pub(super) fn opt_ir_ssa_use_radix_layout(
    capacities: LoweringCapacities,
) -> OptIrSsaUseRadixLayout {
    let max_value = capacities.optimization_value_capacity() - 1;
    let key_bits = (u32::BITS - max_value.leading_zeros()).max(1);
    let steps = key_bits.div_ceil(8);
    let blocks = capacities
        .optimization_use_capacity()
        .div_ceil(RADIX_ROWS_PER_BLOCK)
        .max(1);
    OptIrSsaUseRadixLayout {
        key_bits,
        steps,
        blocks,
    }
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct ProjectionParams {
    semantic_capacity: u32,
    hir_capacity: u32,
    block_capacity: u32,
    edge_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct AccessParams {
    semantic_capacity: u32,
    hir_capacity: u32,
    block_capacity: u32,
    access_capacity: u32,
    declaration_capacity: u32,
    parameter_capacity: u32,
    local_capacity: u32,
    reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct AccessRadixParams {
    item_capacity: u32,
    subject_bits: u32,
    max_blocks: u32,
    key_step: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct UseRadixParams {
    item_capacity: u32,
    key_bits: u32,
    max_blocks: u32,
    key_step: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct SsaParams {
    block_capacity: u32,
    edge_capacity: u32,
    access_capacity: u32,
    declaration_capacity: u32,
    declaration_block_capacity: u32,
    demand_capacity: u32,
    worker_count: u32,
    max_radix_blocks: u32,
    incoming_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct SsaValueParams {
    semantic_capacity: u32,
    parameter_capacity: u32,
    block_argument_capacity: u32,
    value_capacity: u32,
    call_argument_capacity: u32,
    aggregate_element_capacity: u32,
    block_capacity: u32,
    access_capacity: u32,
    incoming_capacity: u32,
    hir_capacity: u32,
    use_capacity: u32,
    reserved1: u32,
}

#[derive(Clone, Copy)]
pub(crate) struct GpuOptIrMetadataView<'a> {
    pub layout_word_offset: &'a LaniusBuffer<u32>,
    pub function_id_by_hir: &'a LaniusBuffer<u32>,
    pub call_args: &'a LaniusBuffer<SemanticLirCallArg>,
    pub call_arg_count: &'a LaniusBuffer<u32>,
    pub call_arg_start_by_hir: &'a LaniusBuffer<u32>,
    pub call_arg_count_by_hir: &'a LaniusBuffer<u32>,
    pub aggregate_elements: &'a LaniusBuffer<SemanticLirAggregateElement>,
    pub aggregate_element_count: &'a LaniusBuffer<u32>,
    pub strings: &'a LaniusBuffer<SemanticLirString>,
    pub string_count: &'a LaniusBuffer<u32>,
    pub string_data_words: &'a LaniusBuffer<u32>,
    pub string_pool_len: &'a LaniusBuffer<u32>,
    pub functions: &'a LaniusBuffer<SemanticLirFunction>,
    pub function_count: &'a LaniusBuffer<u32>,
    pub params: &'a LaniusBuffer<SemanticLirParam>,
    pub param_count: &'a LaniusBuffer<u32>,
    pub locals: &'a LaniusBuffer<SemanticLirLocal>,
    pub local_count: &'a LaniusBuffer<u32>,
    pub execution_order: Option<&'a LaniusBuffer<u32>>,
    pub status: &'a LaniusBuffer<LoweringStatus>,
}

impl<'a> GpuOptIrMetadataView<'a> {
    pub(super) fn from_semantic(semantic: GpuSemanticLirView<'a>) -> Self {
        Self {
            layout_word_offset: semantic.layout_word_offset,
            function_id_by_hir: semantic.function_id_by_hir,
            call_args: semantic.call_args,
            call_arg_count: semantic.call_arg_count,
            call_arg_start_by_hir: semantic.call_arg_start_by_hir,
            call_arg_count_by_hir: semantic.call_arg_count_by_hir,
            aggregate_elements: semantic.aggregate_elements,
            aggregate_element_count: semantic.aggregate_element_count,
            strings: semantic.strings,
            string_count: semantic.string_count,
            string_data_words: semantic.string_data_words,
            string_pool_len: semantic.string_pool_len,
            functions: semantic.functions,
            function_count: semantic.function_count,
            params: semantic.params,
            param_count: semantic.param_count,
            locals: semantic.locals,
            local_count: semantic.local_count,
            execution_order: semantic.execution_order,
            status: semantic.status,
        }
    }

    pub(super) fn register(
        self,
        graph: &CompilerGraph,
        resources: &mut ResourceMap<'a>,
    ) -> Result<()> {
        macro_rules! buffer {
            ($name:literal, $value:expr) => {
                resources.graph_buffer(graph, $name, $value)?
            };
        }
        buffer!("lir.semantic.layout_word_offset", self.layout_word_offset);
        buffer!("semantic.function_ids", self.function_id_by_hir);
        buffer!("lir.semantic.call_args", self.call_args);
        buffer!("lir.semantic.call_arg_total", self.call_arg_count);
        buffer!(
            "lir.semantic.call_arg_prefix_by_hir",
            self.call_arg_start_by_hir
        );
        buffer!(
            "lir.semantic.call_arg_counts_by_hir",
            self.call_arg_count_by_hir
        );
        buffer!("lir.semantic.aggregate_elements", self.aggregate_elements);
        buffer!(
            "lir.semantic.aggregate_element_total",
            self.aggregate_element_count
        );
        buffer!("lir.semantic.strings", self.strings);
        buffer!("lir.semantic.string_total", self.string_count);
        buffer!("lir.semantic.string_data", self.string_data_words);
        buffer!("lir.semantic.string_pool_len", self.string_pool_len);
        buffer!("lir.semantic.functions", self.functions);
        buffer!("lir.semantic.function_total", self.function_count);
        buffer!("lir.semantic.params", self.params);
        buffer!("lir.semantic.param_total", self.param_count);
        buffer!("lir.semantic.locals", self.locals);
        buffer!("lir.semantic.local_total", self.local_count);
        if let Some(order) = self.execution_order {
            buffer!("lir.semantic.schedule_order", order);
        }
        buffer!("lowering.status", self.status);
        Ok(())
    }
}

#[derive(Clone, Copy)]
pub(crate) struct GpuOptIrView<'a> {
    pub count: &'a LaniusBuffer<u32>,
    pub core: &'a LaniusBuffer<OptIrNodeCore>,
    pub operands: &'a LaniusBuffer<OptIrNodeOperands>,
    pub control: &'a LaniusBuffer<OptIrNodeControl>,
    pub results: &'a LaniusBuffer<OptIrNodeResults>,
    pub value_count: &'a LaniusBuffer<u32>,
    pub value_definitions: &'a LaniusBuffer<OptIrValueDefinition>,
    pub value_by_block_argument: &'a LaniusBuffer<u32>,
    /// Original semantic row for diagnostics and differential validation.
    pub semantic_row: &'a LaniusBuffer<u32>,
    /// Source HIR owner. Kept as a separate hot column so ordinary target
    /// passes do not fetch the diagnostic-only semantic row.
    pub source_hir: &'a LaniusBuffer<u32>,
    /// Inverse of `metadata.execution_order`: stable OptIR node ID to its
    /// position in the target-independent scheduled stream.
    pub position_by_node: &'a LaniusBuffer<u32>,
    /// Compact variable-arity rows and declaration/string metadata are
    /// immutable auxiliary inputs. Their storage representation is already
    /// suitable for OptIR, so the ownership boundary transfers it without a
    /// second copy or exposing the mutable semantic instruction view.
    pub metadata: GpuOptIrMetadataView<'a>,
}

impl<'a> GpuOptIrView<'a> {
    pub(super) fn register(
        self,
        graph: &CompilerGraph,
        resources: &mut ResourceMap<'a>,
    ) -> Result<()> {
        self.metadata.register(graph, resources)?;
        resources.graph_buffer(graph, "lir.opt.total", self.count)?;
        resources.graph_buffer(graph, "lir.opt.core", self.core)?;
        resources.graph_buffer(graph, "lir.opt.operands", self.operands)?;
        resources.graph_buffer(graph, "lir.opt.control", self.control)?;
        resources.graph_buffer(graph, "lir.opt.results", self.results)?;
        resources.graph_buffer(graph, "lir.opt.ssa.value_total", self.value_count)?;
        resources.graph_buffer(
            graph,
            "lir.opt.ssa.value_definitions",
            self.value_definitions,
        )?;
        resources.graph_buffer(
            graph,
            "lir.opt.ssa.value_by_block_argument",
            self.value_by_block_argument,
        )?;
        resources.graph_buffer(graph, "lir.opt.semantic_row", self.semantic_row)?;
        resources.graph_buffer(graph, "lir.opt.source_hir", self.source_hir)?;
        resources.graph_buffer(graph, "lir.opt.position_by_node", self.position_by_node)?;
        Ok(())
    }
}

pub(crate) struct GpuOptimizationStage {
    project: ComputeOperation,
    structure_mark: ComputeOperation,
    block_scan: PrefixScanOperation,
    structure_scatter: ComputeOperation,
    structure_finalize: ComputeOperation,
    structure_edge_mark: ComputeOperation,
    edge_scan: PrefixScanOperation,
    structure_edge_scatter: ComputeOperation,
    predecessor_clear: ComputeOperation,
    predecessor_count: ComputeOperation,
    predecessor_scan: PrefixScanOperation,
    predecessor_prepare: ComputeOperation,
    predecessor_scatter: ComputeOperation,
    predecessor_validate: ComputeOperation,
    structure_function_init: ComputeOperation,
    structure_function_reduce: ComputeOperation,
    structure_function_finalize: ComputeOperation,
    reachability_clear: ClearBuffersOperation,
    reachability_seed: ComputeOperation,
    reachability_close: ComputeOperation,
    reachability_validate: ComputeOperation,
    dominator_clear: ComputeOperation,
    dominator_count: ComputeOperation,
    dominator_seed: ComputeOperation,
    dominator_resolve: ComputeOperation,
    dominator_validate: ComputeOperation,
    dominator_child_clear: ComputeOperation,
    dominator_child_count: ComputeOperation,
    dominator_child_scan: PrefixScanOperation,
    dominator_child_prepare: ComputeOperation,
    dominator_child_scatter: ComputeOperation,
    dominator_child_validate: ComputeOperation,
    dominator_tour_child_rows_clear: ComputeOperation,
    dominator_tour_child_rows: ComputeOperation,
    dominator_tour_init: ComputeOperation,
    dominator_tour_a_to_b: ComputeOperation,
    dominator_tour_b_to_a: ComputeOperation,
    dominator_tour_finalize: ComputeOperation,
    dominator_preorder_inverse_clear: ComputeOperation,
    dominator_preorder_inverse_scatter: ComputeOperation,
    dominator_preorder_validate: ComputeOperation,
    dominator_depth_init: ComputeOperation,
    dominator_depth_a_to_b: ComputeOperation,
    dominator_depth_b_to_a: ComputeOperation,
    dominator_depth_finalize: ComputeOperation,
    dominator_depth_validate: ComputeOperation,
    region_mark: ComputeOperation,
    region_scan: PrefixScanOperation,
    region_function_clear: ComputeOperation,
    region_scatter: ComputeOperation,
    region_parent_init: ComputeOperation,
    region_parent_a_to_b: ComputeOperation,
    region_parent_b_to_a: ComputeOperation,
    region_finalize: ComputeOperation,
    region_function_finalize: ComputeOperation,
    region_ownership_clear: ComputeOperation,
    region_ownership_ranges: ComputeOperation,
    region_ownership_nodes: ComputeOperation,
    region_ownership_blocks: ComputeOperation,
    region_validate_edges: ComputeOperation,
    access_mark: ComputeOperation,
    access_scan: PrefixScanOperation,
    access_scatter: ComputeOperation,
    access_metadata: ComputeOperation,
    access_validate: ComputeOperation,
    access_sort: RadixSortOperation<AccessRadixParams>,
    access_sort_validate: ComputeOperation,
    access_group_mark: ComputeOperation,
    access_group_scan: PrefixScanOperation,
    declaration_block_mark: ComputeOperation,
    declaration_block_scan: PrefixScanOperation,
    access_group_scatter: ComputeOperation,
    declaration_block_scatter: ComputeOperation,
    access_group_finalize: ComputeOperation,
    access_local_definitions: ComputeOperation,
    access_local_definitions_validate: ComputeOperation,
    declaration_block_finalize: ComputeOperation,
    declaration_block_validate: ComputeOperation,
    demand_seed_mark: ComputeOperation,
    demand_seed_scan: PrefixScanOperation,
    demand_seed_scatter: ComputeOperation,
    demand_seed_validate: ComputeOperation,
    demand_work_clear: ClearBuffersOperation,
    demand_closure_prepare: ComputeOperation,
    demand_seed_publish: ComputeOperation,
    demand_close: ComputeOperation,
    demand_sort_prepare: ComputeOperation,
    demand_sort: RadixSortOperation<AccessRadixParams>,
    demand_validate: ComputeOperation,
    demand_materialize: ComputeOperation,
    demand_commit: ComputeOperation,
    block_argument_mark: ComputeOperation,
    block_argument_scan: PrefixScanPairOperation,
    block_argument_scatter: ComputeOperation,
    block_argument_validate: ComputeOperation,
    demand_alias_worker_clear: ClearBuffersOperation,
    demand_alias_resolve: ComputeOperation,
    demand_alias_validate: ComputeOperation,
    block_argument_user_count_clear: ClearBuffersOperation,
    block_argument_user_count: ComputeOperation,
    block_argument_user_scan: PrefixScanOperation,
    block_argument_user_cursor_clear: ClearBuffersOperation,
    block_argument_user_scatter: ComputeOperation,
    trivial_block_argument_work_clear: ClearBuffersOperation,
    trivial_block_argument_init: ComputeOperation,
    trivial_block_argument_propagate: ComputeOperation,
    trivial_block_argument_finalize: ComputeOperation,
    trivial_block_argument_validate: ComputeOperation,
    ssa_value_mark: ComputeOperation,
    ssa_value_scan: PrefixScanPairOperation,
    ssa_value_scatter: ComputeOperation,
    ssa_value_validate: ComputeOperation,
    ssa_value_resolve_init: ComputeOperation,
    ssa_value_resolve_reads: ComputeOperation,
    ssa_value_resolve_a_to_b: ComputeOperation,
    ssa_value_resolve_b_to_a: ComputeOperation,
    ssa_value_resolve_finalize: ComputeOperation,
    ssa_value_resolve_validate: ComputeOperation,
    ssa_operand_rewrite: ComputeOperation,
    ssa_operand_validate: ComputeOperation,
    ssa_incoming_rewrite: ComputeOperation,
    ssa_dominance_validate: ComputeOperation,
    ssa_use_mark: ComputeOperation,
    ssa_use_scan: PrefixScanPairOperation,
    ssa_aggregate_use_scan: PrefixScanOperation,
    ssa_use_scatter: ComputeOperation,
    ssa_use_validate: ComputeOperation,
    ssa_use_sort: RadixSortOperation<UseRadixParams>,
    ssa_use_sort_validate: ComputeOperation,
    ssa_use_group_mark: ComputeOperation,
    ssa_use_group_scan: PrefixScanOperation,
    ssa_use_group_scatter: ComputeOperation,
    ssa_use_group_finalize: ComputeOperation,
    ssa_use_group_validate: ComputeOperation,
    _params: LaniusBuffer<ProjectionParams>,
    _access_params: LaniusBuffer<AccessParams>,
    _access_radix_validate_params: LaniusBuffer<AccessRadixParams>,
    _ssa_params: LaniusBuffer<SsaParams>,
    _ssa_value_params: LaniusBuffer<SsaValueParams>,
    _ssa_use_radix_validate_params: LaniusBuffer<UseRadixParams>,
    count: LaniusBuffer<u32>,
    core: LaniusBuffer<OptIrNodeCore>,
    operands: LaniusBuffer<OptIrNodeOperands>,
    control: LaniusBuffer<OptIrNodeControl>,
    results: LaniusBuffer<OptIrNodeResults>,
    semantic_row: LaniusBuffer<u32>,
    source_hir: LaniusBuffer<u32>,
    position_by_node: LaniusBuffer<u32>,
    _block_count: LaniusBuffer<u32>,
    _blocks: LaniusBuffer<OptIrBlock>,
    _edge_count: LaniusBuffer<u32>,
    _edges: LaniusBuffer<OptIrEdge>,
    _predecessor_edge_ids: LaniusBuffer<u32>,
    _reachable: LaniusBuffer<u32>,
    _reachability_work_state: LaniusBuffer<u32>,
    _reachability_work_queue: LaniusBuffer<u32>,
    _immediate_dominator: LaniusBuffer<OptIrImmediateDominator>,
    _dominator_children: LaniusBuffer<u32>,
    _dominator_child_row_by_block: LaniusBuffer<u32>,
    _dominator_tour_link_a: LaniusBuffer<OptIrDominatorTourLink>,
    _dominator_tour_link_b: LaniusBuffer<OptIrDominatorTourLink>,
    _dominator_preorder: LaniusBuffer<u32>,
    _dominator_subtree_end: LaniusBuffer<u32>,
    _block_by_dominator_preorder: LaniusBuffer<u32>,
    _dominator_depth_link_a: LaniusBuffer<OptIrDominatorJump>,
    _dominator_depth_link_b: LaniusBuffer<OptIrDominatorJump>,
    _dominator_depth: LaniusBuffer<u32>,
    _region_count: LaniusBuffer<u32>,
    _regions: LaniusBuffer<OptIrRegion>,
    _region_parent_link_a: LaniusBuffer<u32>,
    _region_parent_link_b: LaniusBuffer<u32>,
    _region_ownership_tree: LaniusBuffer<u32>,
    _block_region: LaniusBuffer<u32>,
    _functions: LaniusBuffer<OptIrFunction>,
    _access_order: LaniusBuffer<u32>,
    _access_groups: LaniusBuffer<OptIrAccessGroup>,
    _local_definition_by_access: LaniusBuffer<u32>,
    _declaration_blocks: LaniusBuffer<OptIrDeclarationBlock>,
    _reaching_definition_states: LaniusBuffer<OptIrReachingDefinitionState>,
    _ssa_demands: LaniusBuffer<OptIrSsaDemand>,
    _ssa_demand_seed_total: LaniusBuffer<u32>,
    _ssa_worker_next_group: LaniusBuffer<u32>,
    _ssa_sparse_declaration: LaniusBuffer<u32>,
    _ssa_sparse_block: LaniusBuffer<u32>,
    _ssa_work_state: LaniusBuffer<u32>,
    _ssa_work_queue: LaniusBuffer<u32>,
    _ssa_demand_order: LaniusBuffer<u32>,
    _ssa_demand_radix_dispatch_args: LaniusBuffer<u32>,
    _ssa_canonical_demands_tmp: LaniusBuffer<OptIrSsaDemand>,
    _ssa_demand_resolutions: LaniusBuffer<u32>,
    _ssa_demand_resolution_tmp: LaniusBuffer<u32>,
    _ssa_block_argument_total: LaniusBuffer<u32>,
    _ssa_block_arguments: LaniusBuffer<OptIrBlockArgument>,
    _ssa_block_argument_incoming_total: LaniusBuffer<u32>,
    _ssa_block_argument_incoming: LaniusBuffer<OptIrBlockArgumentIncoming>,
    _ssa_block_argument_user_count: LaniusBuffer<u32>,
    _ssa_block_argument_user_prefix: LaniusBuffer<u32>,
    _ssa_block_argument_user_total: LaniusBuffer<u32>,
    _ssa_block_argument_user_arguments: LaniusBuffer<u32>,
    _ssa_block_argument_summary: LaniusBuffer<u32>,
    _ssa_block_argument_replacement: LaniusBuffer<u32>,
    value_count: LaniusBuffer<u32>,
    value_definitions: LaniusBuffer<OptIrValueDefinition>,
    value_by_block_argument: LaniusBuffer<u32>,
    _ssa_node_value_flag: LaniusBuffer<u32>,
    _ssa_node_value_total: LaniusBuffer<u32>,
    _ssa_block_argument_value_flag: LaniusBuffer<u32>,
    _ssa_surviving_block_argument_total: LaniusBuffer<u32>,
    _ssa_value_link_a: LaniusBuffer<u32>,
    _ssa_value_link_b: LaniusBuffer<u32>,
    _ssa_operands: LaniusBuffer<OptIrNodeOperands>,
    _ssa_call_argument_values: LaniusBuffer<u32>,
    _ssa_aggregate_element_values: LaniusBuffer<u32>,
    _ssa_incoming_values: LaniusBuffer<OptIrIncomingValue>,
    _ssa_node_use_count: LaniusBuffer<u32>,
    _ssa_node_use_total: LaniusBuffer<u32>,
    _ssa_call_use_flag: LaniusBuffer<u32>,
    _ssa_call_use_total: LaniusBuffer<u32>,
    _ssa_aggregate_use_flag: LaniusBuffer<u32>,
    _ssa_aggregate_use_total: LaniusBuffer<u32>,
    _ssa_use_total: LaniusBuffer<u32>,
    _ssa_use_values: LaniusBuffer<u32>,
    _ssa_use_users: LaniusBuffer<u32>,
    _ssa_use_order: LaniusBuffer<u32>,
    _ssa_use_radix_dispatch_args: LaniusBuffer<u32>,
    _ssa_use_group_start_flag: LaniusBuffer<u32>,
    _ssa_use_group_total: LaniusBuffer<u32>,
    _ssa_use_groups: LaniusBuffer<OptIrUseGroup>,
    region_parent_pairs: u32,
    dominator_tour_jump_pairs: u32,
    dominator_jump_pairs: u32,
    ssa_value_link_jump_pairs: u32,
}

impl GpuOptimizationStage {
    pub(crate) fn new(
        device: &wgpu::Device,
        graph: &CompilerGraph,
        workspace: &CompilerGraphWorkspace,
        capacities: LoweringCapacities,
        semantic: GpuSemanticLirView<'_>,
        kernels: &KernelRegistry,
    ) -> Result<Self> {
        let allocations = lowering_allocations_with_semantic(graph, workspace, semantic)?;
        let resource = |name: &str| {
            graph
                .resource_id(name)
                .with_context(|| format!("optimizer graph is missing {name}"))
        };
        let rows = capacities.semantic_instructions.max(1) as usize;
        let block_capacity = capacities.optimization_block_capacity();
        let edge_capacity = capacities.optimization_edge_capacity();
        let region_capacity = capacities.optimization_region_capacity();
        let access_capacity = capacities.optimization_access_capacity();
        let access_group_capacity = capacities.optimization_access_group_capacity();
        let declaration_block_capacity = capacities.optimization_declaration_block_capacity();
        let demand_capacity = capacities.optimization_ssa_demand_capacity();
        let incoming_capacity = capacities.optimization_ssa_incoming_capacity();
        let user_capacity = capacities.optimization_ssa_user_capacity();
        let ssa_sparse_capacity = capacities.optimization_ssa_sparse_capacity();
        let ssa_work_capacity = capacities.optimization_ssa_work_capacity();
        let value_capacity = capacities.optimization_value_capacity();
        let use_capacity = capacities.optimization_use_capacity();
        let access_radix = opt_ir_access_radix_layout(capacities);
        let ssa_demand_radix = opt_ir_ssa_demand_radix_layout(capacities);
        let ssa_use_radix = opt_ir_ssa_use_radix_layout(capacities);
        let count = workspace
            .alias(graph, resource("lir.opt.total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let core = workspace
            .alias(graph, resource("lir.opt.core")?, rows)
            .map_err(anyhow::Error::msg)?;
        let operands = workspace
            .alias(graph, resource("lir.opt.operands")?, rows)
            .map_err(anyhow::Error::msg)?;
        let control = workspace
            .alias(graph, resource("lir.opt.control")?, rows)
            .map_err(anyhow::Error::msg)?;
        let results = workspace
            .alias(graph, resource("lir.opt.results")?, rows)
            .map_err(anyhow::Error::msg)?;
        let semantic_row = workspace
            .alias(graph, resource("lir.opt.semantic_row")?, rows)
            .map_err(anyhow::Error::msg)?;
        let source_hir = workspace
            .alias(graph, resource("lir.opt.source_hir")?, rows)
            .map_err(anyhow::Error::msg)?;
        let position_by_node = workspace
            .alias(graph, resource("lir.opt.position_by_node")?, rows)
            .map_err(anyhow::Error::msg)?;
        let block_count = workspace
            .alias(graph, resource("lir.opt.block_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let blocks = workspace
            .alias(graph, resource("lir.opt.blocks")?, block_capacity as usize)
            .map_err(anyhow::Error::msg)?;
        let edge_count = workspace
            .alias(graph, resource("lir.opt.edge_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let edges = workspace
            .alias(graph, resource("lir.opt.edges")?, edge_capacity as usize)
            .map_err(anyhow::Error::msg)?;
        let predecessor_edge_ids = workspace
            .alias(
                graph,
                resource("lir.opt.predecessor_edge_ids")?,
                edge_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let reachable = workspace
            .alias(
                graph,
                resource("lir.opt.reachable")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let reachability_work_state = workspace
            .alias(graph, resource("lir.opt.reachability.work_state")?, 4)
            .map_err(anyhow::Error::msg)?;
        let reachability_work_queue = workspace
            .alias(
                graph,
                resource("lir.opt.reachability.work_queue")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let immediate_dominator = workspace
            .alias(
                graph,
                resource("lir.opt.immediate_dominator")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_children = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_children")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_child_row_by_block = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_child_row_by_block")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_tour_arc_capacity = block_capacity.saturating_mul(2);
        let dominator_tour_link_a = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_tour_link_a")?,
                dominator_tour_arc_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_tour_link_b = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_tour_link_b")?,
                dominator_tour_arc_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_preorder = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_preorder")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_subtree_end = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_subtree_end")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let block_by_dominator_preorder = workspace
            .alias(
                graph,
                resource("lir.opt.block_by_dominator_preorder")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_depth_link_a = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_depth_link_a")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_depth_link_b = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_depth_link_b")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let dominator_depth = workspace
            .alias(
                graph,
                resource("lir.opt.dominator_depth")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let region_count = workspace
            .alias(graph, resource("lir.opt.region_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let regions = workspace
            .alias(
                graph,
                resource("lir.opt.regions")?,
                region_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let region_parent_link_a = workspace
            .alias(
                graph,
                resource("lir.opt.region_parent_link_a")?,
                region_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let region_parent_link_b = workspace
            .alias(
                graph,
                resource("lir.opt.region_parent_link_b")?,
                region_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let region_ownership_tree = workspace
            .alias(
                graph,
                resource("lir.opt.region_ownership_tree")?,
                capacities.semantic_instructions.max(1).saturating_mul(2) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let block_region = workspace
            .alias(
                graph,
                resource("lir.opt.block_region")?,
                block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let functions = workspace
            .alias(
                graph,
                resource("lir.opt.functions")?,
                capacities.hir_nodes.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let access_order = workspace
            .alias(
                graph,
                resource("lir.opt.access_order")?,
                access_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let access_radix_dispatch_args = workspace
            .alias(graph, resource("lir.opt.access_radix_dispatch_args")?, 3)
            .map_err(anyhow::Error::msg)?;
        let access_groups = workspace
            .alias(
                graph,
                resource("lir.opt.access_groups")?,
                access_group_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let access_group_dispatch_args = workspace
            .alias(graph, resource("lir.opt.access_group_dispatch_args")?, 3)
            .map_err(anyhow::Error::msg)?;
        let local_definition_by_access = workspace
            .alias(
                graph,
                resource("lir.opt.local_definition_by_access")?,
                access_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let declaration_blocks = workspace
            .alias(
                graph,
                resource("lir.opt.declaration_blocks")?,
                declaration_block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let reaching_definition_states = workspace
            .alias(
                graph,
                resource("lir.opt.reaching_definition_states")?,
                declaration_block_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_demands = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.demands")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_demand_seed_total = workspace
            .alias(graph, resource("lir.opt.ssa.demand_seed_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_worker_next_group = workspace
            .alias(graph, resource("lir.opt.ssa.worker_next_group")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_sparse_declaration = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.sparse_declaration")?,
                ssa_sparse_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_sparse_block = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.sparse_block")?,
                ssa_sparse_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_work_state = workspace
            .alias(graph, resource("lir.opt.ssa.work_state")?, 4)
            .map_err(anyhow::Error::msg)?;
        let ssa_work_queue = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.work_queue")?,
                ssa_work_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_demand_order = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.demand_order")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_demand_radix_dispatch_args = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.demand_radix_dispatch_args")?,
                3,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_canonical_demands_tmp = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.canonical_demands_tmp")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_demand_resolutions = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.demand_resolutions")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_demand_resolution_tmp = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.demand_resolution_tmp")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_total = workspace
            .alias(graph, resource("lir.opt.ssa.block_argument_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_block_arguments = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_arguments")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_incoming_total = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_incoming_total")?,
                1,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_incoming = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_incoming")?,
                incoming_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_user_count = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_user_count")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_user_prefix = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_user_prefix")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_user_total = workspace
            .alias(graph, resource("lir.opt.ssa.block_argument_user_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_user_arguments = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_user_arguments")?,
                user_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_summary = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_summary")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_replacement = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_replacement")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_node_value_flag = workspace
            .alias(graph, resource("lir.opt.ssa.node_value_flag")?, rows)
            .map_err(anyhow::Error::msg)?;
        let ssa_node_value_total = workspace
            .alias(graph, resource("lir.opt.ssa.node_value_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_block_argument_value_flag = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.block_argument_value_flag")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_surviving_block_argument_total = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.surviving_block_argument_total")?,
                1,
            )
            .map_err(anyhow::Error::msg)?;
        let value_count = workspace
            .alias(graph, resource("lir.opt.ssa.value_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let value_definitions = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.value_definitions")?,
                value_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let value_by_block_argument = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.value_by_block_argument")?,
                demand_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_value_link_a = workspace
            .alias(graph, resource("lir.opt.ssa.value_link_a")?, rows)
            .map_err(anyhow::Error::msg)?;
        let ssa_value_link_b = workspace
            .alias(graph, resource("lir.opt.ssa.value_link_b")?, rows)
            .map_err(anyhow::Error::msg)?;
        let ssa_operands = workspace
            .alias(graph, resource("lir.opt.ssa.operands")?, rows)
            .map_err(anyhow::Error::msg)?;
        let ssa_call_argument_values = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.call_argument_values")?,
                capacities.call_arguments.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_aggregate_element_values = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.aggregate_element_values")?,
                capacities.aggregate_elements.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_incoming_values = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.incoming_values")?,
                incoming_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_node_use_count = workspace
            .alias(graph, resource("lir.opt.ssa.node_use_count")?, rows)
            .map_err(anyhow::Error::msg)?;
        let ssa_node_use_total = workspace
            .alias(graph, resource("lir.opt.ssa.node_use_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_call_use_flag = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.call_use_flag")?,
                capacities.call_arguments.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_call_use_total = workspace
            .alias(graph, resource("lir.opt.ssa.call_use_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_aggregate_use_flag = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.aggregate_use_flag")?,
                capacities.aggregate_elements.max(1) as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_aggregate_use_total = workspace
            .alias(graph, resource("lir.opt.ssa.aggregate_use_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_use_total = workspace
            .alias(graph, resource("lir.opt.ssa.use_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_use_values = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.use_values")?,
                use_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_use_users = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.use_users")?,
                use_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_use_order = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.use_order")?,
                use_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_use_radix_dispatch_args = workspace
            .alias(graph, resource("lir.opt.ssa.use_radix_dispatch_args")?, 3)
            .map_err(anyhow::Error::msg)?;
        let ssa_use_group_start_flag = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.use_group_start_flag")?,
                use_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        let ssa_use_group_total = workspace
            .alias(graph, resource("lir.opt.ssa.use_group_total")?, 1)
            .map_err(anyhow::Error::msg)?;
        let ssa_use_groups = workspace
            .alias(
                graph,
                resource("lir.opt.ssa.use_groups")?,
                value_capacity as usize,
            )
            .map_err(anyhow::Error::msg)?;
        semantic.execution_order.context(
            "target lowering graph omitted the semantic execution permutation required by OptIR",
        )?;

        let params = uniform_from_val(
            device,
            "lir.opt.project.params",
            &ProjectionParams {
                semantic_capacity: capacities.semantic_instructions.max(1),
                hir_capacity: capacities.hir_nodes.max(1),
                block_capacity,
                edge_capacity,
            },
        );
        let access_params = uniform_from_val(
            device,
            "lir.opt.access.params",
            &AccessParams {
                semantic_capacity: capacities.semantic_instructions.max(1),
                hir_capacity: capacities.hir_nodes.max(1),
                block_capacity,
                access_capacity,
                declaration_capacity: capacities.declaration_capacity(),
                parameter_capacity: capacities.parameters.max(1),
                local_capacity: capacities.local_capacity(),
                reserved: access_radix.blocks,
            },
        );
        let ssa_params = uniform_from_val(
            device,
            "lir.opt.ssa.params",
            &SsaParams {
                block_capacity,
                edge_capacity,
                access_capacity,
                declaration_capacity: capacities.declaration_capacity(),
                declaration_block_capacity,
                demand_capacity,
                worker_count: LoweringCapacities::OPTIMIZATION_SSA_WORKER_COUNT,
                max_radix_blocks: ssa_demand_radix.blocks,
                incoming_capacity,
            },
        );
        let ssa_value_params = uniform_from_val(
            device,
            "lir.opt.ssa.values.params",
            &SsaValueParams {
                semantic_capacity: capacities.semantic_instructions.max(1),
                parameter_capacity: capacities.parameters.max(1),
                block_argument_capacity: demand_capacity,
                value_capacity,
                call_argument_capacity: capacities.call_arguments.max(1),
                aggregate_element_capacity: capacities.aggregate_elements.max(1),
                block_capacity,
                access_capacity,
                incoming_capacity,
                hir_capacity: capacities.hir_nodes.max(1),
                use_capacity,
                reserved1: 0,
            },
        );
        let graph_bindings = workspace.bindings(graph).map_err(anyhow::Error::msg)?;
        let mut resources = ResourceMap::new();
        resources.attach_graph(graph, &allocations);
        resources.register_graph_bindings(graph, &graph_bindings);
        semantic.register(graph, &mut resources)?;
        let pass = kernels.kernel("codegen/lir/optimization/project");
        let project = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.project",
            pass,
            &params,
            capacities.semantic_instructions.max(1),
        )?;
        let structure_mark = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.structure.mark",
            kernels.kernel("codegen/lir/optimization/structure_mark"),
            &params,
            capacities.semantic_instructions.max(1),
        )?;
        let block_scan =
            PrefixScanOperation::from_spec(device, kernels, &resources, OPT_IR_BLOCK_SCAN)?;
        let structure_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.structure.scatter",
            kernels.kernel("codegen/lir/optimization/structure_scatter"),
            &params,
            capacities.semantic_instructions.max(1),
        )?;
        let structure_finalize = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.structure.finalize",
            kernels.kernel("codegen/lir/optimization/structure_finalize"),
            &params,
            block_capacity,
        )?;
        let structure_edge_mark = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.structure.edge_mark",
            kernels.kernel("codegen/lir/optimization/structure_edge_mark"),
            &params,
            block_capacity,
        )?;
        let edge_scan =
            PrefixScanOperation::from_spec(device, kernels, &resources, OPT_IR_EDGE_SCAN)?;
        let structure_edge_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.structure.edge_scatter",
            kernels.kernel("codegen/lir/optimization/structure_edge_scatter"),
            &params,
            block_capacity,
        )?;
        let predecessor_clear = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.predecessors.clear",
            kernels.kernel("codegen/lir/optimization/structure_predecessor_clear"),
            &params,
            block_capacity,
        )?;
        let predecessor_count = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.predecessors.count",
            kernels.kernel("codegen/lir/optimization/structure_predecessor_count"),
            &params,
            edge_capacity,
        )?;
        let predecessor_scan =
            PrefixScanOperation::from_spec(device, kernels, &resources, OPT_IR_PREDECESSOR_SCAN)?;
        let predecessor_prepare = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.predecessors.prepare",
            kernels.kernel("codegen/lir/optimization/structure_predecessor_prepare"),
            &params,
            block_capacity,
        )?;
        let predecessor_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.predecessors.scatter",
            kernels.kernel("codegen/lir/optimization/structure_predecessor_scatter"),
            &params,
            edge_capacity,
        )?;
        let predecessor_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.predecessors.validate",
            kernels.kernel("codegen/lir/optimization/structure_predecessor_validate"),
            &params,
            block_capacity,
        )?;
        let structure_function_init = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.structure.function_init",
            kernels.kernel("codegen/lir/optimization/structure_function_init"),
            &params,
            capacities.hir_nodes.max(1),
        )?;
        let structure_function_reduce = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.structure.function_reduce",
            kernels.kernel("codegen/lir/optimization/structure_function_reduce"),
            &params,
            block_capacity,
        )?;
        let structure_function_finalize = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.structure.function_finalize",
            kernels.kernel("codegen/lir/optimization/structure_function_finalize"),
            &params,
            capacities.hir_nodes.max(1),
        )?;
        let reachability_clear = ClearBuffersOperation::new(
            &(graph, &allocations),
            "lir.opt.reachability.clear",
            &[
                ("opt_ir_reachable", (&reachable).into()),
                (
                    "opt_ir_reachability_work_state",
                    (&reachability_work_state).into(),
                ),
            ],
        )?;
        let reachability_seed = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.reachability.seed",
            kernels.kernel("codegen/lir/optimization/structure_reachability_seed"),
            &params,
            capacities.hir_nodes.max(1),
        )?;
        let reachability_close = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.reachability.close",
            kernels.kernel("codegen/lir/optimization/structure_reachability_close"),
            &params,
            32,
        )?;
        let reachability_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.reachability.validate",
            kernels.kernel("codegen/lir/optimization/structure_reachability_validate"),
            &params,
            block_capacity,
        )?;
        let dominator_clear = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.clear",
            kernels.kernel("codegen/lir/optimization/structure_dominator_clear"),
            &params,
            block_capacity,
        )?;
        let dominator_count = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.count",
            kernels.kernel("codegen/lir/optimization/structure_dominator_count"),
            &params,
            edge_capacity,
        )?;
        let dominator_seed = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.seed",
            kernels.kernel("codegen/lir/optimization/structure_dominator_seed"),
            &params,
            block_capacity,
        )?;
        let dominator_resolve = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.resolve",
            kernels.kernel("codegen/lir/optimization/structure_dominator_resolve"),
            &params,
            block_capacity,
        )?;
        let dominator_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.validate",
            kernels.kernel("codegen/lir/optimization/structure_dominator_validate"),
            &params,
            block_capacity,
        )?;
        let dominator_child_clear = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.children.clear",
            kernels.kernel("codegen/lir/optimization/structure_dominator_child_clear"),
            &params,
            block_capacity,
        )?;
        let dominator_child_count = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.children.count",
            kernels.kernel("codegen/lir/optimization/structure_dominator_child_count"),
            &params,
            block_capacity,
        )?;
        let dominator_child_scan = PrefixScanOperation::from_spec(
            device,
            kernels,
            &resources,
            OPT_IR_DOMINATOR_CHILD_SCAN,
        )?;
        let dominator_child_prepare = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.children.prepare",
            kernels.kernel("codegen/lir/optimization/structure_dominator_child_prepare"),
            &params,
            block_capacity,
        )?;
        let dominator_child_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.children.scatter",
            kernels.kernel("codegen/lir/optimization/structure_dominator_child_scatter"),
            &params,
            block_capacity,
        )?;
        let dominator_child_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.children.validate",
            kernels.kernel("codegen/lir/optimization/structure_dominator_child_validate"),
            &params,
            block_capacity,
        )?;
        let dominator_tour_child_rows_clear = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.tour.child_rows.clear",
            kernels.kernel("codegen/lir/optimization/structure_dominator_tour_child_rows_clear"),
            &params,
            block_capacity,
        )?;
        let dominator_tour_child_rows = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.tour.child_rows",
            kernels.kernel("codegen/lir/optimization/structure_dominator_tour_child_rows"),
            &params,
            block_capacity,
        )?;
        let dominator_tour_init = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.tour.init",
            kernels.kernel("codegen/lir/optimization/structure_dominator_tour_init"),
            &params,
            dominator_tour_arc_capacity,
        )?;
        let dominator_tour_a_to_b = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.tour.step_a_to_b",
            kernels.kernel("codegen/lir/optimization/structure_dominator_tour_step"),
            &params,
            dominator_tour_arc_capacity,
        )?;
        let dominator_tour_b_to_a = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.tour.step_b_to_a",
            kernels.kernel("codegen/lir/optimization/structure_dominator_tour_step"),
            &params,
            dominator_tour_arc_capacity,
        )?;
        let dominator_tour_finalize = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.tour.finalize",
            kernels.kernel("codegen/lir/optimization/structure_dominator_tour_finalize"),
            &params,
            block_capacity,
        )?;
        let dominator_preorder_inverse_clear = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.preorder.inverse_clear",
            kernels.kernel("codegen/lir/optimization/structure_dominator_preorder_inverse_clear"),
            &params,
            block_capacity,
        )?;
        let dominator_preorder_inverse_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.preorder.inverse_scatter",
            kernels.kernel("codegen/lir/optimization/structure_dominator_preorder_inverse_scatter"),
            &params,
            block_capacity,
        )?;
        let dominator_preorder_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.preorder.validate",
            kernels.kernel("codegen/lir/optimization/structure_dominator_preorder_validate"),
            &params,
            block_capacity,
        )?;
        let dominator_tour_jump_pairs = (u32::BITS - dominator_tour_arc_capacity.leading_zeros())
            .max(1)
            .div_ceil(2);
        let dominator_depth_init = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.depth.init",
            kernels.kernel("codegen/lir/optimization/structure_dominator_depth_init"),
            &params,
            block_capacity,
        )?;
        let dominator_depth_a_to_b = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.depth.step_a_to_b",
            kernels.kernel("codegen/lir/optimization/structure_dominator_depth_step"),
            &params,
            block_capacity,
        )?;
        let dominator_depth_b_to_a = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.depth.step_b_to_a",
            kernels.kernel("codegen/lir/optimization/structure_dominator_depth_step"),
            &params,
            block_capacity,
        )?;
        let dominator_depth_finalize = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.depth.finalize",
            kernels.kernel("codegen/lir/optimization/structure_dominator_depth_finalize"),
            &params,
            block_capacity,
        )?;
        let dominator_depth_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.dominators.depth.validate",
            kernels.kernel("codegen/lir/optimization/structure_dominator_depth_validate"),
            &params,
            block_capacity,
        )?;
        let dominator_jump_pairs = (u32::BITS - block_capacity.leading_zeros())
            .max(1)
            .div_ceil(2);
        let region_mark = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.regions.mark",
            kernels.kernel("codegen/lir/optimization/structure_region_mark"),
            &params,
            capacities.semantic_instructions.max(1),
        )?;
        let region_scan =
            PrefixScanOperation::from_spec(device, kernels, &resources, OPT_IR_REGION_SCAN)?;
        let region_function_clear = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.regions.function_clear",
            kernels.kernel("codegen/lir/optimization/structure_region_function_clear"),
            &params,
            capacities.hir_nodes.max(1),
        )?;
        let region_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.regions.scatter",
            kernels.kernel("codegen/lir/optimization/structure_region_scatter"),
            &params,
            capacities.semantic_instructions.max(1),
        )?;
        let region_parent_init = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.regions.parent_init",
            kernels.kernel("codegen/lir/optimization/structure_region_parent_init"),
            &params,
            region_capacity,
        )?;
        let region_parent_a_to_b = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.regions.parent_step_a_to_b",
            kernels.kernel("codegen/lir/optimization/structure_region_parent_step"),
            &params,
            region_capacity,
        )?;
        let region_parent_b_to_a = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.regions.parent_step_b_to_a",
            kernels.kernel("codegen/lir/optimization/structure_region_parent_step"),
            &params,
            region_capacity,
        )?;
        let region_finalize = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.regions.finalize",
            kernels.kernel("codegen/lir/optimization/structure_region_finalize"),
            &params,
            region_capacity,
        )?;
        let region_function_finalize = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.regions.function_finalize",
            kernels.kernel("codegen/lir/optimization/structure_region_function_finalize"),
            &params,
            capacities.hir_nodes.max(1),
        )?;
        let region_ownership_clear = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.regions.ownership.clear",
            kernels.kernel("codegen/lir/optimization/structure_region_ownership_clear"),
            &params,
            capacities.semantic_instructions.max(1).saturating_mul(2),
        )?;
        let region_ownership_ranges = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.regions.ownership.ranges",
            kernels.kernel("codegen/lir/optimization/structure_region_ownership_ranges"),
            &params,
            region_capacity,
        )?;
        let region_ownership_nodes = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.regions.ownership.nodes",
            kernels.kernel("codegen/lir/optimization/structure_region_ownership_nodes"),
            &params,
            capacities.semantic_instructions.max(1),
        )?;
        let region_ownership_blocks = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.regions.ownership.blocks",
            kernels.kernel("codegen/lir/optimization/structure_region_ownership_blocks"),
            &params,
            block_capacity,
        )?;
        let region_validate_edges = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.regions.validate_edges",
            kernels.kernel("codegen/lir/optimization/structure_region_validate_edges"),
            &params,
            edge_capacity,
        )?;
        let region_parent_pairs = (u32::BITS - region_capacity.leading_zeros())
            .max(1)
            .div_ceil(2);
        let access_mark = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.mark",
            kernels.kernel("codegen/lir/optimization/access_mark"),
            &access_params,
            capacities.semantic_instructions.max(1),
        )?;
        let access_scan =
            PrefixScanOperation::from_spec(device, kernels, &resources, OPT_IR_ACCESS_SCAN)?;
        let access_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.scatter",
            kernels.kernel("codegen/lir/optimization/access_scatter"),
            &access_params,
            capacities.semantic_instructions.max(1),
        )?;
        let metadata_capacity = capacities
            .parameters
            .max(capacities.local_capacity())
            .max(1);
        let access_metadata = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.metadata",
            kernels.kernel("codegen/lir/optimization/access_metadata"),
            &access_params,
            metadata_capacity,
        )?;
        let access_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.validate",
            kernels.kernel("codegen/lir/optimization/access_validate"),
            &access_params,
            access_capacity,
        )?;
        let access_sort = OPT_IR_ACCESS_RADIX_SORT.operation(
            device,
            kernels,
            &resources,
            access_capacity,
            0,
            access_radix.steps,
            RadixSortDispatch {
                small: RadixDispatchDomain::Direct(1),
                rows: RadixDispatchDomain::Indirect(&access_radix_dispatch_args),
                bucket_prefix: RadixDispatchDomain::Direct(
                    RADIX_BUCKET_COUNT * RADIX_ROWS_PER_BLOCK,
                ),
                bucket_bases: RadixDispatchDomain::Direct(RADIX_BUCKET_COUNT),
            },
            |key_step| AccessRadixParams {
                item_capacity: access_capacity,
                subject_bits: access_radix.subject_bits,
                max_blocks: access_radix.blocks,
                key_step,
            },
        )?;
        let access_radix_validate_params = uniform_from_val(
            device,
            "lir.opt.access.sort.validate.params",
            &AccessRadixParams {
                item_capacity: access_capacity,
                subject_bits: access_radix.subject_bits,
                max_blocks: access_radix.blocks,
                key_step: 0,
            },
        );
        let access_sort_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.sort.validate",
            kernels.kernel("codegen/lir/optimization/access_sort_validate"),
            &access_radix_validate_params,
            access_capacity,
        )?;
        let access_group_mark = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.groups.mark",
            kernels.kernel("codegen/lir/optimization/access_group_mark"),
            &access_params,
            access_capacity,
        )?;
        let access_group_scan =
            PrefixScanOperation::from_spec(device, kernels, &resources, OPT_IR_ACCESS_GROUP_SCAN)?;
        let declaration_block_mark = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.declaration_blocks.mark",
            kernels.kernel("codegen/lir/optimization/access_declaration_block_mark"),
            &access_params,
            access_capacity,
        )?;
        let declaration_block_scan = PrefixScanOperation::from_spec(
            device,
            kernels,
            &resources,
            OPT_IR_DECLARATION_BLOCK_SCAN,
        )?;
        let access_group_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.groups.scatter",
            kernels.kernel("codegen/lir/optimization/access_group_scatter"),
            &access_params,
            access_capacity,
        )?;
        let declaration_block_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.declaration_blocks.scatter",
            kernels.kernel("codegen/lir/optimization/access_declaration_block_scatter"),
            &access_params,
            access_capacity,
        )?;
        let access_group_finalize = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.groups.finalize",
            kernels.kernel("codegen/lir/optimization/access_group_finalize"),
            &access_params,
            access_group_capacity,
        )?;
        let access_local_definitions = ComputeOperation::indirect(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.local_definitions",
            kernels.kernel("codegen/lir/optimization/access_local_definitions"),
            &access_group_dispatch_args,
        )?;
        let access_local_definitions_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.local_definitions.validate",
            kernels.kernel("codegen/lir/optimization/access_local_definitions_validate"),
            &access_params,
            access_capacity,
        )?;
        let declaration_block_finalize = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.declaration_blocks.finalize",
            kernels.kernel("codegen/lir/optimization/access_declaration_block_finalize"),
            &access_params,
            declaration_block_capacity,
        )?;
        let declaration_block_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.access.declaration_blocks.validate",
            kernels.kernel("codegen/lir/optimization/access_declaration_block_validate"),
            &access_params,
            declaration_block_capacity,
        )?;
        let demand_seed_mark = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.demands.seed.mark",
            kernels.kernel("codegen/lir/optimization/ssa_demand_seed_mark"),
            &access_params,
            declaration_block_capacity,
        )?;
        let demand_seed_scan = PrefixScanOperation::from_spec(
            device,
            kernels,
            &resources,
            OPT_IR_SSA_DEMAND_SEED_SCAN,
        )?;
        let demand_seed_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.demands.seed.scatter",
            kernels.kernel("codegen/lir/optimization/ssa_demand_seed_scatter"),
            &access_params,
            declaration_block_capacity,
        )?;
        let demand_seed_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.demands.seed.validate",
            kernels.kernel("codegen/lir/optimization/ssa_demand_seed_validate"),
            &access_params,
            declaration_block_capacity,
        )?;
        let demand_work_clear = ClearBuffersOperation::new(
            &(graph, &allocations),
            "lir.opt.ssa.demands.work_clear",
            &[
                (
                    "opt_ir_ssa_sparse_declaration",
                    (&ssa_sparse_declaration).into(),
                ),
                ("opt_ir_ssa_sparse_block", (&ssa_sparse_block).into()),
                ("opt_ir_ssa_work_state", (&ssa_work_state).into()),
                ("opt_ir_ssa_work_queue", (&ssa_work_queue).into()),
            ],
        )?;
        let demand_closure_prepare = ComputeOperation::direct(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.demands.closure.prepare",
            kernels.kernel("codegen/lir/optimization/ssa_demand_closure_prepare"),
            1,
        )?;
        let demand_seed_publish = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.demands.closure.seed_publish",
            kernels.kernel("codegen/lir/optimization/ssa_demand_seed_publish"),
            &ssa_params,
            demand_capacity,
        )?;
        let demand_close = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.demands.close",
            kernels.kernel("codegen/lir/optimization/ssa_demand_close"),
            &ssa_params,
            LoweringCapacities::OPTIMIZATION_SSA_WORKER_COUNT
                .saturating_mul(LoweringCapacities::OPTIMIZATION_SSA_QUEUE_WORKGROUP_SIZE),
        )?;
        let demand_sort_prepare = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.demands.sort.prepare",
            kernels.kernel("codegen/lir/optimization/ssa_demand_sort_prepare"),
            &ssa_params,
            1,
        )?;
        let demand_key_bits =
            ssa_demand_radix.block_bits | (ssa_demand_radix.declaration_bits << 16);
        let demand_sort = OPT_IR_SSA_DEMAND_RADIX_SORT.operation(
            device,
            kernels,
            &resources,
            demand_capacity,
            0,
            ssa_demand_radix.steps,
            RadixSortDispatch {
                small: RadixDispatchDomain::Direct(1),
                rows: RadixDispatchDomain::Indirect(&ssa_demand_radix_dispatch_args),
                bucket_prefix: RadixDispatchDomain::Direct(
                    RADIX_BUCKET_COUNT * RADIX_ROWS_PER_BLOCK,
                ),
                bucket_bases: RadixDispatchDomain::Direct(RADIX_BUCKET_COUNT),
            },
            |key_step| AccessRadixParams {
                item_capacity: demand_capacity,
                subject_bits: demand_key_bits,
                max_blocks: ssa_demand_radix.blocks,
                key_step,
            },
        )?;
        let demand_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.demands.validate",
            kernels.kernel("codegen/lir/optimization/ssa_demand_validate"),
            &ssa_params,
            demand_capacity,
        )?;
        let demand_materialize = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.demands.materialize",
            kernels.kernel("codegen/lir/optimization/ssa_demand_materialize"),
            &ssa_params,
            demand_capacity,
        )?;
        let demand_commit = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.demands.commit",
            kernels.kernel("codegen/lir/optimization/ssa_demand_commit"),
            &ssa_params,
            demand_capacity,
        )?;
        let block_argument_mark = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.block_arguments.mark",
            kernels.kernel("codegen/lir/optimization/ssa_block_argument_mark"),
            &ssa_params,
            demand_capacity,
        )?;
        let block_argument_scan = PrefixScanPairOperation::from_spec(
            device,
            kernels,
            &resources,
            OPT_IR_SSA_BLOCK_ARGUMENT_SCAN,
        )?;
        let block_argument_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.block_arguments.scatter",
            kernels.kernel("codegen/lir/optimization/ssa_block_argument_scatter"),
            &ssa_params,
            demand_capacity,
        )?;
        let block_argument_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.block_arguments.validate",
            kernels.kernel("codegen/lir/optimization/ssa_block_argument_validate"),
            &ssa_params,
            demand_capacity,
        )?;
        let demand_alias_worker_clear = ClearBuffersOperation::new(
            &(graph, &allocations),
            "lir.opt.ssa.demand_aliases.worker_clear",
            &[(
                "opt_ir_ssa_worker_next_group",
                (&ssa_worker_next_group).into(),
            )],
        )?;
        let demand_alias_resolve = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.demand_aliases.resolve",
            kernels.kernel("codegen/lir/optimization/ssa_demand_resolve_aliases"),
            &ssa_params,
            LoweringCapacities::OPTIMIZATION_SSA_WORKER_COUNT.saturating_mul(256),
        )?;
        let demand_alias_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.demand_aliases.validate",
            kernels.kernel("codegen/lir/optimization/ssa_demand_alias_validate"),
            &ssa_params,
            demand_capacity,
        )?;
        let block_argument_user_count_clear = ClearBuffersOperation::new(
            &(graph, &allocations),
            "lir.opt.ssa.block_argument_users.count_clear",
            &[((
                "opt_ir_ssa_block_argument_user_count",
                (&ssa_block_argument_user_count).into(),
            ))],
        )?;
        let block_argument_user_count = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.block_argument_users.count",
            kernels.kernel("codegen/lir/optimization/ssa_block_argument_user_count"),
            &ssa_params,
            demand_capacity,
        )?;
        let block_argument_user_scan = PrefixScanOperation::from_spec(
            device,
            kernels,
            &resources,
            OPT_IR_SSA_BLOCK_ARGUMENT_USER_SCAN,
        )?;
        let block_argument_user_cursor_clear = ClearBuffersOperation::new(
            &(graph, &allocations),
            "lir.opt.ssa.block_argument_users.cursor_clear",
            &[((
                "opt_ir_ssa_block_argument_user_count",
                (&ssa_block_argument_user_count).into(),
            ))],
        )?;
        let block_argument_user_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.block_argument_users.scatter",
            kernels.kernel("codegen/lir/optimization/ssa_block_argument_user_scatter"),
            &ssa_params,
            demand_capacity,
        )?;
        let trivial_block_argument_work_clear = ClearBuffersOperation::new(
            &(graph, &allocations),
            "lir.opt.ssa.trivial_block_arguments.work_clear",
            &[
                (("opt_ir_ssa_work_state", (&ssa_work_state).into())),
                (("opt_ir_ssa_work_queue", (&ssa_work_queue).into())),
            ],
        )?;
        let trivial_block_argument_init = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.trivial_block_arguments.init",
            kernels.kernel("codegen/lir/optimization/ssa_trivial_block_argument_init"),
            &ssa_params,
            demand_capacity,
        )?;
        let trivial_block_argument_propagate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.trivial_block_arguments.propagate",
            kernels.kernel("codegen/lir/optimization/ssa_trivial_block_argument_propagate"),
            &ssa_params,
            LoweringCapacities::OPTIMIZATION_SSA_WORKER_COUNT
                .saturating_mul(LoweringCapacities::OPTIMIZATION_SSA_QUEUE_WORKGROUP_SIZE),
        )?;
        let trivial_block_argument_finalize = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.trivial_block_arguments.finalize",
            kernels.kernel("codegen/lir/optimization/ssa_trivial_block_argument_finalize"),
            &ssa_params,
            demand_capacity,
        )?;
        let trivial_block_argument_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.trivial_block_arguments.validate",
            kernels.kernel("codegen/lir/optimization/ssa_trivial_block_argument_validate"),
            &ssa_params,
            demand_capacity,
        )?;
        let ssa_value_mark = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.values.mark",
            kernels.kernel("codegen/lir/optimization/ssa_value_mark"),
            &ssa_value_params,
            capacities.semantic_instructions.max(demand_capacity).max(1),
        )?;
        let ssa_value_scan =
            PrefixScanPairOperation::from_spec(device, kernels, &resources, OPT_IR_SSA_VALUE_SCAN)?;
        let ssa_value_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.values.scatter",
            kernels.kernel("codegen/lir/optimization/ssa_value_scatter"),
            &ssa_value_params,
            value_capacity,
        )?;
        let ssa_value_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.values.validate",
            kernels.kernel("codegen/lir/optimization/ssa_value_validate"),
            &ssa_value_params,
            value_capacity,
        )?;
        let ssa_value_resolve_init = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.values.resolve.init",
            kernels.kernel("codegen/lir/optimization/ssa_value_resolve_init"),
            &ssa_value_params,
            capacities.semantic_instructions.max(1),
        )?;
        let ssa_value_resolve_reads = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.values.resolve.reads",
            kernels.kernel("codegen/lir/optimization/ssa_value_resolve_reads"),
            &ssa_value_params,
            access_capacity,
        )?;
        let ssa_value_resolve_a_to_b = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.values.resolve.step_a_to_b",
            kernels.kernel("codegen/lir/optimization/ssa_value_resolve_step"),
            &ssa_value_params,
            capacities.semantic_instructions.max(1),
        )?;
        let ssa_value_resolve_b_to_a = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.values.resolve.step_b_to_a",
            kernels.kernel("codegen/lir/optimization/ssa_value_resolve_step"),
            &ssa_value_params,
            capacities.semantic_instructions.max(1),
        )?;
        let ssa_value_resolve_finalize = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.values.resolve.finalize",
            kernels.kernel("codegen/lir/optimization/ssa_value_resolve_finalize"),
            &ssa_value_params,
            capacities.semantic_instructions.max(1),
        )?;
        let ssa_value_resolve_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.values.resolve.validate",
            kernels.kernel("codegen/lir/optimization/ssa_value_resolve_validate"),
            &ssa_value_params,
            access_capacity,
        )?;
        let ssa_operand_capacity = capacities
            .semantic_instructions
            .max(capacities.call_arguments)
            .max(capacities.aggregate_elements)
            .max(1);
        let ssa_operand_rewrite = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.operands.rewrite",
            kernels.kernel("codegen/lir/optimization/ssa_operand_rewrite"),
            &ssa_value_params,
            ssa_operand_capacity,
        )?;
        let ssa_operand_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.operands.validate",
            kernels.kernel("codegen/lir/optimization/ssa_operand_validate"),
            &ssa_value_params,
            ssa_operand_capacity,
        )?;
        let ssa_incoming_rewrite = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.incoming.rewrite",
            kernels.kernel("codegen/lir/optimization/ssa_incoming_rewrite"),
            &ssa_value_params,
            incoming_capacity,
        )?;
        let ssa_validation_capacity = capacities
            .semantic_instructions
            .max(capacities.call_arguments)
            .max(capacities.aggregate_elements)
            .max(incoming_capacity)
            .max(1);
        let ssa_dominance_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.dominance.validate",
            kernels.kernel("codegen/lir/optimization/ssa_dominance_validate"),
            &ssa_value_params,
            ssa_validation_capacity,
        )?;
        let ssa_use_mark = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.uses.mark",
            kernels.kernel("codegen/lir/optimization/ssa_use_mark"),
            &ssa_value_params,
            capacities
                .semantic_instructions
                .max(capacities.call_arguments)
                .max(capacities.aggregate_elements)
                .max(1),
        )?;
        let ssa_use_scan =
            PrefixScanPairOperation::from_spec(device, kernels, &resources, OPT_IR_SSA_USE_SCAN)?;
        let ssa_aggregate_use_scan = PrefixScanOperation::from_spec(
            device,
            kernels,
            &resources,
            OPT_IR_SSA_AGGREGATE_USE_SCAN,
        )?;
        let ssa_use_dispatch_capacity = capacities
            .semantic_instructions
            .max(capacities.call_arguments)
            .max(capacities.aggregate_elements)
            .max(incoming_capacity)
            .max(1);
        let ssa_use_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.uses.scatter",
            kernels.kernel("codegen/lir/optimization/ssa_use_scatter"),
            &ssa_value_params,
            ssa_use_dispatch_capacity,
        )?;
        let ssa_use_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.uses.validate",
            kernels.kernel("codegen/lir/optimization/ssa_use_validate"),
            &ssa_value_params,
            ssa_use_dispatch_capacity,
        )?;
        let ssa_use_sort = OPT_IR_SSA_USE_RADIX_SORT.operation(
            device,
            kernels,
            &resources,
            use_capacity,
            0,
            ssa_use_radix.steps,
            RadixSortDispatch {
                small: RadixDispatchDomain::Direct(1),
                rows: RadixDispatchDomain::Indirect(&ssa_use_radix_dispatch_args),
                bucket_prefix: RadixDispatchDomain::Direct(
                    RADIX_BUCKET_COUNT * RADIX_ROWS_PER_BLOCK,
                ),
                bucket_bases: RadixDispatchDomain::Direct(RADIX_BUCKET_COUNT),
            },
            |key_step| UseRadixParams {
                item_capacity: use_capacity,
                key_bits: ssa_use_radix.key_bits,
                max_blocks: ssa_use_radix.blocks,
                key_step,
            },
        )?;
        let ssa_use_radix_validate_params = uniform_from_val(
            device,
            "lir.opt.ssa.uses.sort.validate.params",
            &UseRadixParams {
                item_capacity: use_capacity,
                key_bits: ssa_use_radix.key_bits,
                max_blocks: ssa_use_radix.blocks,
                key_step: 0,
            },
        );
        let ssa_use_sort_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.uses.sort.validate",
            kernels.kernel("codegen/lir/optimization/ssa_use_sort_validate"),
            &ssa_use_radix_validate_params,
            use_capacity,
        )?;
        let ssa_use_group_mark = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.use_groups.mark",
            kernels.kernel("codegen/lir/optimization/ssa_use_group_mark"),
            &ssa_value_params,
            use_capacity,
        )?;
        let ssa_use_group_scan =
            PrefixScanOperation::from_spec(device, kernels, &resources, OPT_IR_SSA_USE_GROUP_SCAN)?;
        let ssa_use_group_scatter = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.use_groups.scatter",
            kernels.kernel("codegen/lir/optimization/ssa_use_group_scatter"),
            &ssa_value_params,
            use_capacity,
        )?;
        let ssa_use_group_finalize = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.use_groups.finalize",
            kernels.kernel("codegen/lir/optimization/ssa_use_group_finalize"),
            &ssa_value_params,
            value_capacity,
        )?;
        let ssa_use_group_validate = ComputeOperation::direct_with_uniform(
            device,
            &(graph, &allocations),
            &resources,
            "lir.opt.ssa.use_groups.validate",
            kernels.kernel("codegen/lir/optimization/ssa_use_group_validate"),
            &ssa_value_params,
            use_capacity,
        )?;
        let ssa_value_link_jump_pairs = (u32::BITS
            - capacities.semantic_instructions.max(1).leading_zeros())
        .max(1)
        .div_ceil(2);

        Ok(Self {
            project,
            structure_mark,
            block_scan,
            structure_scatter,
            structure_finalize,
            structure_edge_mark,
            edge_scan,
            structure_edge_scatter,
            predecessor_clear,
            predecessor_count,
            predecessor_scan,
            predecessor_prepare,
            predecessor_scatter,
            predecessor_validate,
            structure_function_init,
            structure_function_reduce,
            structure_function_finalize,
            reachability_clear,
            reachability_seed,
            reachability_close,
            reachability_validate,
            dominator_clear,
            dominator_count,
            dominator_seed,
            dominator_resolve,
            dominator_validate,
            dominator_child_clear,
            dominator_child_count,
            dominator_child_scan,
            dominator_child_prepare,
            dominator_child_scatter,
            dominator_child_validate,
            dominator_tour_child_rows_clear,
            dominator_tour_child_rows,
            dominator_tour_init,
            dominator_tour_a_to_b,
            dominator_tour_b_to_a,
            dominator_tour_finalize,
            dominator_preorder_inverse_clear,
            dominator_preorder_inverse_scatter,
            dominator_preorder_validate,
            dominator_depth_init,
            dominator_depth_a_to_b,
            dominator_depth_b_to_a,
            dominator_depth_finalize,
            dominator_depth_validate,
            region_mark,
            region_scan,
            region_function_clear,
            region_scatter,
            region_parent_init,
            region_parent_a_to_b,
            region_parent_b_to_a,
            region_finalize,
            region_function_finalize,
            region_ownership_clear,
            region_ownership_ranges,
            region_ownership_nodes,
            region_ownership_blocks,
            region_validate_edges,
            access_mark,
            access_scan,
            access_scatter,
            access_metadata,
            access_validate,
            access_sort,
            access_sort_validate,
            access_group_mark,
            access_group_scan,
            declaration_block_mark,
            declaration_block_scan,
            access_group_scatter,
            declaration_block_scatter,
            access_group_finalize,
            access_local_definitions,
            access_local_definitions_validate,
            declaration_block_finalize,
            declaration_block_validate,
            demand_seed_mark,
            demand_seed_scan,
            demand_seed_scatter,
            demand_seed_validate,
            demand_work_clear,
            demand_closure_prepare,
            demand_seed_publish,
            demand_close,
            demand_sort_prepare,
            demand_sort,
            demand_validate,
            demand_materialize,
            demand_commit,
            block_argument_mark,
            block_argument_scan,
            block_argument_scatter,
            block_argument_validate,
            demand_alias_worker_clear,
            demand_alias_resolve,
            demand_alias_validate,
            block_argument_user_count_clear,
            block_argument_user_count,
            block_argument_user_scan,
            block_argument_user_cursor_clear,
            block_argument_user_scatter,
            trivial_block_argument_work_clear,
            trivial_block_argument_init,
            trivial_block_argument_propagate,
            trivial_block_argument_finalize,
            trivial_block_argument_validate,
            ssa_value_mark,
            ssa_value_scan,
            ssa_value_scatter,
            ssa_value_validate,
            ssa_value_resolve_init,
            ssa_value_resolve_reads,
            ssa_value_resolve_a_to_b,
            ssa_value_resolve_b_to_a,
            ssa_value_resolve_finalize,
            ssa_value_resolve_validate,
            ssa_operand_rewrite,
            ssa_operand_validate,
            ssa_incoming_rewrite,
            ssa_dominance_validate,
            ssa_use_mark,
            ssa_use_scan,
            ssa_aggregate_use_scan,
            ssa_use_scatter,
            ssa_use_validate,
            ssa_use_sort,
            ssa_use_sort_validate,
            ssa_use_group_mark,
            ssa_use_group_scan,
            ssa_use_group_scatter,
            ssa_use_group_finalize,
            ssa_use_group_validate,
            _params: params,
            _access_params: access_params,
            _access_radix_validate_params: access_radix_validate_params,
            _ssa_params: ssa_params,
            _ssa_value_params: ssa_value_params,
            _ssa_use_radix_validate_params: ssa_use_radix_validate_params,
            count,
            core,
            operands,
            control,
            results,
            semantic_row,
            source_hir,
            position_by_node,
            _block_count: block_count,
            _blocks: blocks,
            _edge_count: edge_count,
            _edges: edges,
            _predecessor_edge_ids: predecessor_edge_ids,
            _reachable: reachable,
            _reachability_work_state: reachability_work_state,
            _reachability_work_queue: reachability_work_queue,
            _immediate_dominator: immediate_dominator,
            _dominator_children: dominator_children,
            _dominator_child_row_by_block: dominator_child_row_by_block,
            _dominator_tour_link_a: dominator_tour_link_a,
            _dominator_tour_link_b: dominator_tour_link_b,
            _dominator_preorder: dominator_preorder,
            _dominator_subtree_end: dominator_subtree_end,
            _block_by_dominator_preorder: block_by_dominator_preorder,
            _dominator_depth_link_a: dominator_depth_link_a,
            _dominator_depth_link_b: dominator_depth_link_b,
            _dominator_depth: dominator_depth,
            _region_count: region_count,
            _regions: regions,
            _region_parent_link_a: region_parent_link_a,
            _region_parent_link_b: region_parent_link_b,
            _region_ownership_tree: region_ownership_tree,
            _block_region: block_region,
            _functions: functions,
            _access_order: access_order,
            _access_groups: access_groups,
            _local_definition_by_access: local_definition_by_access,
            _declaration_blocks: declaration_blocks,
            _reaching_definition_states: reaching_definition_states,
            _ssa_demands: ssa_demands,
            _ssa_demand_seed_total: ssa_demand_seed_total,
            _ssa_worker_next_group: ssa_worker_next_group,
            _ssa_sparse_declaration: ssa_sparse_declaration,
            _ssa_sparse_block: ssa_sparse_block,
            _ssa_work_state: ssa_work_state,
            _ssa_work_queue: ssa_work_queue,
            _ssa_demand_order: ssa_demand_order,
            _ssa_demand_radix_dispatch_args: ssa_demand_radix_dispatch_args,
            _ssa_canonical_demands_tmp: ssa_canonical_demands_tmp,
            _ssa_demand_resolutions: ssa_demand_resolutions,
            _ssa_demand_resolution_tmp: ssa_demand_resolution_tmp,
            _ssa_block_argument_total: ssa_block_argument_total,
            _ssa_block_arguments: ssa_block_arguments,
            _ssa_block_argument_incoming_total: ssa_block_argument_incoming_total,
            _ssa_block_argument_incoming: ssa_block_argument_incoming,
            _ssa_block_argument_user_count: ssa_block_argument_user_count,
            _ssa_block_argument_user_prefix: ssa_block_argument_user_prefix,
            _ssa_block_argument_user_total: ssa_block_argument_user_total,
            _ssa_block_argument_user_arguments: ssa_block_argument_user_arguments,
            _ssa_block_argument_summary: ssa_block_argument_summary,
            _ssa_block_argument_replacement: ssa_block_argument_replacement,
            value_count,
            value_definitions,
            value_by_block_argument,
            _ssa_node_value_flag: ssa_node_value_flag,
            _ssa_node_value_total: ssa_node_value_total,
            _ssa_block_argument_value_flag: ssa_block_argument_value_flag,
            _ssa_surviving_block_argument_total: ssa_surviving_block_argument_total,
            _ssa_value_link_a: ssa_value_link_a,
            _ssa_value_link_b: ssa_value_link_b,
            _ssa_operands: ssa_operands,
            _ssa_call_argument_values: ssa_call_argument_values,
            _ssa_aggregate_element_values: ssa_aggregate_element_values,
            _ssa_incoming_values: ssa_incoming_values,
            _ssa_node_use_count: ssa_node_use_count,
            _ssa_node_use_total: ssa_node_use_total,
            _ssa_call_use_flag: ssa_call_use_flag,
            _ssa_call_use_total: ssa_call_use_total,
            _ssa_aggregate_use_flag: ssa_aggregate_use_flag,
            _ssa_aggregate_use_total: ssa_aggregate_use_total,
            _ssa_use_total: ssa_use_total,
            _ssa_use_values: ssa_use_values,
            _ssa_use_users: ssa_use_users,
            _ssa_use_order: ssa_use_order,
            _ssa_use_radix_dispatch_args: ssa_use_radix_dispatch_args,
            _ssa_use_group_start_flag: ssa_use_group_start_flag,
            _ssa_use_group_total: ssa_use_group_total,
            _ssa_use_groups: ssa_use_groups,
            region_parent_pairs,
            dominator_tour_jump_pairs,
            dominator_jump_pairs,
            ssa_value_link_jump_pairs,
        })
    }

    pub(crate) fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        mut timer: Option<&mut GpuTimer>,
    ) -> Result<()> {
        if let Some(timer) = timer.as_deref_mut() {
            timer.set_phase(crate::gpu::timer::GpuCompilerPhase::Optimization);
        }
        self.project.record(encoder)?;
        self.structure_mark.record(encoder)?;
        self.block_scan.record(encoder)?;
        self.structure_scatter.record(encoder)?;
        self.structure_finalize.record(encoder)?;
        self.structure_edge_mark.record(encoder)?;
        self.edge_scan.record(encoder)?;
        self.structure_edge_scatter.record(encoder)?;
        self.predecessor_clear.record(encoder)?;
        self.predecessor_count.record(encoder)?;
        self.predecessor_scan.record(encoder)?;
        self.predecessor_prepare.record(encoder)?;
        self.predecessor_scatter.record(encoder)?;
        self.predecessor_validate.record(encoder)?;
        self.structure_function_init.record(encoder)?;
        self.structure_function_reduce.record(encoder)?;
        self.structure_function_finalize.record(encoder)?;
        self.reachability_clear.record(encoder);
        self.reachability_seed.record(encoder)?;
        self.reachability_close.record(encoder)?;
        self.reachability_validate.record(encoder)?;
        self.dominator_clear.record(encoder)?;
        self.dominator_count.record(encoder)?;
        self.dominator_seed.record(encoder)?;
        self.dominator_resolve.record(encoder)?;
        self.dominator_validate.record(encoder)?;
        self.dominator_child_clear.record(encoder)?;
        self.dominator_child_count.record(encoder)?;
        self.dominator_child_scan.record(encoder)?;
        self.dominator_child_prepare.record(encoder)?;
        self.dominator_child_scatter.record(encoder)?;
        self.dominator_child_validate.record(encoder)?;
        self.dominator_tour_child_rows_clear.record(encoder)?;
        self.dominator_tour_child_rows.record(encoder)?;
        self.dominator_tour_init.record(encoder)?;
        for _ in 0..self.dominator_tour_jump_pairs {
            self.dominator_tour_a_to_b.record(encoder)?;
            self.dominator_tour_b_to_a.record(encoder)?;
        }
        self.dominator_tour_finalize.record(encoder)?;
        self.dominator_preorder_inverse_clear.record(encoder)?;
        self.dominator_preorder_inverse_scatter.record(encoder)?;
        self.dominator_preorder_validate.record(encoder)?;
        self.dominator_depth_init.record(encoder)?;
        for _ in 0..self.dominator_jump_pairs {
            self.dominator_depth_a_to_b.record(encoder)?;
            self.dominator_depth_b_to_a.record(encoder)?;
        }
        self.dominator_depth_finalize.record(encoder)?;
        self.dominator_depth_validate.record(encoder)?;
        self.region_mark.record(encoder)?;
        self.region_scan.record(encoder)?;
        self.region_function_clear.record(encoder)?;
        self.region_scatter.record(encoder)?;
        self.region_parent_init.record(encoder)?;
        for _ in 0..self.region_parent_pairs {
            self.region_parent_a_to_b.record(encoder)?;
            self.region_parent_b_to_a.record(encoder)?;
        }
        self.region_finalize.record(encoder)?;
        self.region_function_finalize.record(encoder)?;
        self.region_ownership_clear.record(encoder)?;
        self.region_ownership_ranges.record(encoder)?;
        self.region_ownership_nodes.record(encoder)?;
        self.region_ownership_blocks.record(encoder)?;
        self.region_validate_edges.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.structure.done");
        }
        self.access_mark.record(encoder)?;
        self.access_scan.record(encoder)?;
        self.access_metadata.record(encoder)?;
        self.access_scatter.record(encoder)?;
        self.access_validate.record(encoder)?;
        self.access_sort.record(encoder)?;
        self.access_sort_validate.record(encoder)?;
        self.access_group_mark.record(encoder)?;
        self.access_group_scan.record(encoder)?;
        self.access_group_scatter.record(encoder)?;
        self.access_group_finalize.record(encoder)?;
        self.access_local_definitions.record(encoder)?;
        self.access_local_definitions_validate.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.accesses.done");
        }
        self.declaration_block_mark.record(encoder)?;
        self.declaration_block_scan.record(encoder)?;
        self.declaration_block_scatter.record(encoder)?;
        self.declaration_block_finalize.record(encoder)?;
        self.declaration_block_validate.record(encoder)?;
        self.demand_seed_mark.record(encoder)?;
        self.demand_seed_scan.record(encoder)?;
        self.demand_seed_scatter.record(encoder)?;
        self.demand_seed_validate.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.demand_seeds.done");
        }
        self.demand_work_clear.record(encoder);
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.demand_closure.clear.done");
        }
        self.demand_closure_prepare.record(encoder)?;
        self.demand_seed_publish.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.demand_closure.publish.done");
        }
        self.demand_close.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.demand_closure.close.done");
        }
        self.demand_sort_prepare.record(encoder)?;
        self.demand_sort.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.demand_closure.sort.done");
        }
        self.demand_validate.record(encoder)?;
        self.demand_materialize.record(encoder)?;
        self.demand_commit.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.demand_closure.done");
        }
        self.block_argument_mark.record(encoder)?;
        self.block_argument_scan.record(encoder)?;
        self.block_argument_scatter.record(encoder)?;
        self.block_argument_validate.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.block_arguments.done");
        }
        self.demand_alias_worker_clear.record(encoder);
        self.demand_alias_resolve.record(encoder)?;
        self.demand_alias_validate.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.demand_aliases.done");
        }
        self.block_argument_user_count_clear.record(encoder);
        self.block_argument_user_count.record(encoder)?;
        self.block_argument_user_scan.record(encoder)?;
        self.block_argument_user_cursor_clear.record(encoder);
        self.block_argument_user_scatter.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.block_argument_users.done");
        }
        self.trivial_block_argument_work_clear.record(encoder);
        self.trivial_block_argument_init.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.trivial_block_arguments.init.done");
        }
        self.trivial_block_argument_propagate.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(
                encoder,
                "optimization.trivial_block_arguments.propagate.done",
            );
        }
        self.trivial_block_argument_finalize.record(encoder)?;
        self.trivial_block_argument_validate.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.trivial_block_arguments.done");
        }
        self.ssa_value_mark.record(encoder)?;
        self.ssa_value_scan.record(encoder)?;
        self.ssa_value_scatter.record(encoder)?;
        self.ssa_value_validate.record(encoder)?;
        self.ssa_value_resolve_init.record(encoder)?;
        self.ssa_value_resolve_reads.record(encoder)?;
        for _ in 0..self.ssa_value_link_jump_pairs {
            self.ssa_value_resolve_a_to_b.record(encoder)?;
            self.ssa_value_resolve_b_to_a.record(encoder)?;
        }
        self.ssa_value_resolve_finalize.record(encoder)?;
        self.ssa_value_resolve_validate.record(encoder)?;
        self.ssa_operand_rewrite.record(encoder)?;
        self.ssa_operand_validate.record(encoder)?;
        self.ssa_incoming_rewrite.record(encoder)?;
        self.ssa_dominance_validate.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.ssa_values.done");
        }
        self.ssa_use_mark.record(encoder)?;
        self.ssa_use_scan.record(encoder)?;
        self.ssa_aggregate_use_scan.record(encoder)?;
        self.ssa_use_scatter.record(encoder)?;
        self.ssa_use_validate.record(encoder)?;
        self.ssa_use_sort.record(encoder)?;
        self.ssa_use_sort_validate.record(encoder)?;
        self.ssa_use_group_mark.record(encoder)?;
        self.ssa_use_group_scan.record(encoder)?;
        self.ssa_use_group_scatter.record(encoder)?;
        self.ssa_use_group_finalize.record(encoder)?;
        self.ssa_use_group_validate.record(encoder)?;
        if let Some(timer) = timer.as_deref_mut() {
            timer.stamp(encoder, "optimization.ssa_uses.done");
        }
        Ok(())
    }

    pub(crate) fn output<'a>(&'a self, semantic: GpuSemanticLirView<'a>) -> GpuOptIrView<'a> {
        GpuOptIrView {
            count: &self.count,
            core: &self.core,
            operands: &self.operands,
            control: &self.control,
            results: &self.results,
            value_count: &self.value_count,
            value_definitions: &self.value_definitions,
            value_by_block_argument: &self.value_by_block_argument,
            semantic_row: &self.semantic_row,
            source_hir: &self.source_hir,
            position_by_node: &self.position_by_node,
            metadata: GpuOptIrMetadataView::from_semantic(semantic),
        }
    }
}

pub(super) fn lowering_allocations_with_opt(
    graph: &CompilerGraph,
    workspace: &CompilerGraphWorkspace,
    opt: GpuOptIrView<'_>,
) -> Result<crate::gpu::compiler_graph::CompilerGraphAllocations> {
    let mut allocations = workspace.allocations();
    macro_rules! import {
        ($name:literal, $buffer:expr) => {
            allocations
                .import_buffer(
                    graph,
                    graph
                        .resource_id($name)
                        .with_context(|| format!("lowering graph is missing {}", $name))?,
                    $buffer,
                )
                .map_err(anyhow::Error::msg)?;
        };
    }
    let metadata = opt.metadata;
    import!(
        "lir.semantic.layout_word_offset",
        metadata.layout_word_offset
    );
    import!("semantic.function_ids", metadata.function_id_by_hir);
    import!("lir.semantic.call_args", metadata.call_args);
    import!(
        "lir.semantic.call_arg_prefix_by_hir",
        metadata.call_arg_start_by_hir
    );
    import!(
        "lir.semantic.call_arg_counts_by_hir",
        metadata.call_arg_count_by_hir
    );
    import!(
        "lir.semantic.aggregate_elements",
        metadata.aggregate_elements
    );
    import!(
        "lir.semantic.aggregate_element_total",
        metadata.aggregate_element_count
    );
    import!("lir.semantic.strings", metadata.strings);
    import!("lir.semantic.string_total", metadata.string_count);
    import!("lir.semantic.string_data", metadata.string_data_words);
    import!("lir.semantic.string_pool_len", metadata.string_pool_len);
    import!("lir.semantic.functions", metadata.functions);
    import!("lir.semantic.function_total", metadata.function_count);
    import!("lir.semantic.params", metadata.params);
    import!("lir.semantic.param_total", metadata.param_count);
    import!("lir.semantic.locals", metadata.locals);
    import!("lir.semantic.local_total", metadata.local_count);
    Ok(allocations)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn capacities(
        semantic_instructions: u32,
        tokens: u32,
        hir_nodes: u32,
        parameters: u32,
    ) -> LoweringCapacities {
        LoweringCapacities {
            source_bytes: 1,
            tokens,
            hir_nodes,
            semantic_instructions,
            call_arguments: 1,
            parameters,
            aggregate_elements: 1,
            target_instructions: 1,
            artifact_bytes: 1,
        }
    }

    #[test]
    fn access_radix_key_uses_only_significant_subject_and_domain_bits() {
        let seven_subject_bits = opt_ir_access_radix_layout(capacities(128, 1, 1, 1));
        assert_eq!(seven_subject_bits.subject_bits, 7);
        assert_eq!(seven_subject_bits.steps, 1);

        let eight_subject_bits = opt_ir_access_radix_layout(capacities(129, 1, 1, 1));
        assert_eq!(eight_subject_bits.subject_bits, 8);
        assert_eq!(eight_subject_bits.steps, 2);

        let full_width = opt_ir_access_radix_layout(capacities(u32::MAX, 1, 1, 1));
        assert_eq!(full_width.subject_bits, 32);
        assert_eq!(full_width.steps, 5);
    }

    #[test]
    fn access_radix_layout_does_not_restore_the_old_4096_block_limit() {
        let layout = opt_ir_access_radix_layout(capacities(2_000_000, 1, 1, 1));
        assert!(layout.blocks > 4096);
        assert_eq!(layout.blocks, 2_000_004u32.div_ceil(256));
    }

    #[test]
    fn ssa_use_radix_layout_covers_its_capacity_without_a_block_ceiling() {
        for semantic_instructions in [1, 257, 2_000_000] {
            let capacities = capacities(semantic_instructions, 1, 1, 1);
            let layout = opt_ir_ssa_use_radix_layout(capacities);
            let value_capacity = capacities.optimization_value_capacity();
            let max_value = value_capacity - 1;
            let required_bits = (u32::BITS - max_value.leading_zeros()).max(1);
            assert_eq!(layout.key_bits, required_bits);
            assert_eq!(layout.steps, required_bits.div_ceil(8));
            assert_eq!(
                layout.blocks,
                capacities.optimization_use_capacity().div_ceil(256)
            );
        }
        assert!(opt_ir_ssa_use_radix_layout(capacities(2_000_000, 1, 1, 1)).blocks > 4096);
    }
}
