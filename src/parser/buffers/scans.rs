use log::warn;

use super::{
    BracketsBlockPrefixScanStep,
    BracketsHistogramScanStep,
    HirSemanticPrefixScanStep,
    LL1EmitPrefixScanStep,
    PackOffsetScanStep,
    PackTotalReduceStep,
    TokenDelimiterScanStep,
    TreePrefixMaxBuildStep,
    TreePrefixScanStep,
};
use crate::gpu::{
    buffers::uniform_from_val,
    scan::{ping_pong_scan_steps, ScanFinalize},
};

pub(super) fn make_ll1_emit_prefix_scan_steps(
    device: &wgpu::Device,
    base: super::super::passes::ll1_blocks_01::LL1BlocksParams,
    n_blocks: u32,
) -> Vec<LL1EmitPrefixScanStep> {
    ping_pong_scan_steps(n_blocks, ScanFinalize::CopyToAIfNeeded(n_blocks))
        .into_iter()
        .map(|plan| {
            let label = if plan.scan_step == 0 {
                "parser.ll1_emit_prefix_scan.params.init"
            } else if plan.scan_step == n_blocks {
                "parser.ll1_emit_prefix_scan.params.copy"
            } else {
                "parser.ll1_emit_prefix_scan.params.step"
            };
            LL1EmitPrefixScanStep {
                params: uniform_from_val(
                    device,
                    label,
                    &super::super::passes::ll1_blocks_01::LL1BlocksParams {
                        emit_scan_step: plan.scan_step,
                        ..base
                    },
                ),
                read_from_a: plan.read_from_a,
                write_to_a: plan.write_to_a,
            }
        })
        .collect()
}

pub(super) fn make_pack_offset_scan_steps(
    device: &wgpu::Device,
    n_pairs: u32,
) -> Vec<PackOffsetScanStep> {
    ping_pong_scan_steps(n_pairs, ScanFinalize::Always(n_pairs))
        .into_iter()
        .map(|plan| {
            let label = if plan.scan_step == 0 {
                "pack.offset_scan.params.init"
            } else if plan.scan_step == n_pairs {
                "pack.offset_scan.params.finalize"
            } else {
                "pack.offset_scan.params.step"
            };
            PackOffsetScanStep {
                params: uniform_from_val(
                    device,
                    label,
                    &super::super::passes::pack_offsets::Params {
                        n_pairs,
                        scan_step: plan.scan_step,
                    },
                ),
                read_from_a: plan.read_from_a,
                write_to_a: plan.write_to_a,
            }
        })
        .collect()
}

pub(super) fn make_pack_total_reduce_steps(
    device: &wgpu::Device,
    n_pairs: u32,
) -> Vec<PackTotalReduceStep> {
    let mut steps = Vec::new();
    let mut item_count = n_pairs.div_ceil(256).max(1);
    let mut read_from_a = true;
    let mut write_to_a = false;
    while item_count > 1 {
        let label = "pack.total_reduce.params";
        steps.push(PackTotalReduceStep {
            params: uniform_from_val(
                device,
                label,
                &super::super::passes::pack_totals_reduce::Params { item_count },
            ),
            item_count,
            read_from_a,
            write_to_a,
        });
        item_count = item_count.div_ceil(256).max(1);
        read_from_a = write_to_a;
        write_to_a = !write_to_a;
    }
    steps
}

pub(super) fn make_token_delimiter_scan_steps(
    device: &wgpu::Device,
    n_tokens: u32,
    n_blocks: u32,
) -> Vec<TokenDelimiterScanStep> {
    let base = super::TokenDelimiterParams {
        n_tokens,
        n_blocks,
        scan_step: 0,
    };
    ping_pong_scan_steps(n_blocks, ScanFinalize::Always(n_blocks))
        .into_iter()
        .map(|plan| {
            let label = if plan.scan_step == 0 {
                "parser.token_delimiter_scan.params.init"
            } else if plan.scan_step == n_blocks {
                "parser.token_delimiter_scan.params.finalize"
            } else {
                "parser.token_delimiter_scan.params.step"
            };
            TokenDelimiterScanStep {
                params: uniform_from_val(
                    device,
                    label,
                    &super::TokenDelimiterParams {
                        scan_step: plan.scan_step,
                        ..base
                    },
                ),
                read_from_a: plan.read_from_a,
                write_to_a: plan.write_to_a,
            }
        })
        .collect()
}

pub(super) fn make_brackets_block_prefix_scan_steps(
    device: &wgpu::Device,
    n_blocks: u32,
) -> Vec<BracketsBlockPrefixScanStep> {
    ping_pong_scan_steps(n_blocks, ScanFinalize::Always(n_blocks))
        .into_iter()
        .map(|plan| {
            let label = if plan.scan_step == 0 {
                "brackets.b02.scan.params.init"
            } else if plan.scan_step == n_blocks {
                "brackets.b02.scan.params.finalize"
            } else {
                "brackets.b02.scan.params.step"
            };
            BracketsBlockPrefixScanStep {
                params: uniform_from_val(
                    device,
                    label,
                    &super::super::passes::brackets_02::Params {
                        n_blocks,
                        scan_step: plan.scan_step,
                    },
                ),
                read_from_a: plan.read_from_a,
                write_to_a: plan.write_to_a,
            }
        })
        .collect()
}

pub(super) fn make_brackets_histogram_scan_steps(
    device: &wgpu::Device,
    n_layers: u32,
) -> Vec<BracketsHistogramScanStep> {
    ping_pong_scan_steps(n_layers, ScanFinalize::CopyToAIfNeeded(n_layers))
        .into_iter()
        .map(|plan| {
            let label = if plan.scan_step == 0 {
                "brackets.b05.scan.params.init"
            } else if plan.scan_step == n_layers {
                "brackets.b05.scan.params.copy"
            } else {
                "brackets.b05.scan.params.step"
            };
            BracketsHistogramScanStep {
                params: uniform_from_val(
                    device,
                    label,
                    &super::super::passes::brackets_05::Params {
                        n_layers,
                        scan_step: plan.scan_step,
                    },
                ),
                read_from_offsets: plan.read_from_a,
                write_to_offsets: plan.write_to_a,
            }
        })
        .collect()
}

pub(super) fn make_tree_prefix_scan_steps(
    device: &wgpu::Device,
    base: super::super::passes::tree_prefix_01::Params,
    n_blocks: u32,
) -> Vec<TreePrefixScanStep> {
    ping_pong_scan_steps(n_blocks, ScanFinalize::Always(n_blocks))
        .into_iter()
        .map(|plan| {
            let label = if plan.scan_step == 0 {
                "parser.tree_prefix_scan.params.init"
            } else if plan.scan_step == n_blocks {
                "parser.tree_prefix_scan.params.finalize"
            } else {
                "parser.tree_prefix_scan.params.step"
            };
            TreePrefixScanStep {
                params: uniform_from_val(
                    device,
                    label,
                    &super::super::passes::tree_prefix_01::Params {
                        scan_step: plan.scan_step,
                        ..base
                    },
                ),
                read_from_a: plan.read_from_a,
                write_to_a: plan.write_to_a,
            }
        })
        .collect()
}

pub(super) fn make_hir_semantic_prefix_scan_steps(
    device: &wgpu::Device,
    n_blocks: u32,
) -> Vec<HirSemanticPrefixScanStep> {
    ping_pong_scan_steps(n_blocks, ScanFinalize::CopyToAIfNeeded(n_blocks))
        .into_iter()
        .map(|plan| {
            let label = if plan.scan_step == 0 {
                "parser.hir_semantic_prefix.params.init"
            } else if plan.scan_step == n_blocks {
                "parser.hir_semantic_prefix.params.copy"
            } else {
                "parser.hir_semantic_prefix.params.step"
            };
            HirSemanticPrefixScanStep {
                params: uniform_from_val(
                    device,
                    label,
                    &super::super::passes::hir_semantic_prefix_blocks::Params {
                        n_blocks,
                        scan_step: plan.scan_step,
                    },
                ),
                read_from_a: plan.read_from_a,
                write_to_a: plan.write_to_a,
            }
        })
        .collect()
}

pub(super) fn make_tree_prefix_max_build_steps(
    device: &wgpu::Device,
    n_blocks: u32,
    leaf_base: u32,
) -> Vec<TreePrefixMaxBuildStep> {
    let mut steps = Vec::new();
    steps.push(TreePrefixMaxBuildStep {
        params: uniform_from_val(
            device,
            "parser.tree_prefix_max.params.leaves",
            &super::super::passes::tree_prefix_04::Params {
                n_blocks,
                leaf_base,
                start_node: 0,
                node_count: leaf_base,
                mode: 0,
                _pad0: 0,
                _pad1: 0,
                _pad2: 0,
            },
        ),
        work_items: leaf_base,
    });

    let mut start_node = leaf_base / 2;
    while start_node > 0 {
        steps.push(TreePrefixMaxBuildStep {
            params: uniform_from_val(
                device,
                "parser.tree_prefix_max.params.combine",
                &super::super::passes::tree_prefix_04::Params {
                    n_blocks,
                    leaf_base,
                    start_node,
                    node_count: start_node,
                    mode: 1,
                    _pad0: 0,
                    _pad1: 0,
                    _pad2: 0,
                },
            ),
            work_items: start_node,
        });

        if start_node == 1 {
            break;
        }
        start_node /= 2;
    }

    steps
}

pub(super) fn next_power_of_two_u32(value: u32) -> u32 {
    value.checked_next_power_of_two().unwrap_or_else(|| {
        warn!(
            "value {value} overflows next_power_of_two_u32; using saturated value {}",
            1 << 31
        );
        1 << 31
    })
}
