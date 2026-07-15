use super::*;
use crate::gpu::buffers::uniform_from_val;

// Stable LSD radix order: same-end ancestor rank descending, source end
// ascending, then expression-forest root ascending. The rank is computed from
// the expression-parent forest with parallel pointer jumping, so ordering does
// not depend on parser node allocation order.
const RADIX_STEPS: u32 = 12;
const RADIX_BUCKETS: u32 = 256;

struct ExprDepthTreeStep {
    _params: LaniusBuffer<WasmExprDepthTreeParams>,
    bind_group: wgpu::BindGroup,
    workgroups: u32,
}

pub(super) struct ResidentWasmExprOrder {
    _radix_params: Vec<LaniusBuffer<WasmExprRadixParams>>,
    _scan_params: Vec<LaniusBuffer<WasmScanParams>>,
    _contribution_scan_params: Vec<LaniusBuffer<WasmScanParams>>,
    pub order_a: LaniusBuffer<u32>,
    _order_b: LaniusBuffer<u32>,
    _histogram: LaniusBuffer<u32>,
    _block_sum: LaniusBuffer<u32>,
    _block_prefix_a: LaniusBuffer<u32>,
    _block_prefix_b: LaniusBuffer<u32>,
    _contribution: LaniusBuffer<u32>,
    _contribution_local_prefix: LaniusBuffer<u32>,
    _contribution_block_sum: LaniusBuffer<u32>,
    _contribution_block_prefix_a: LaniusBuffer<u32>,
    _contribution_block_prefix_b: LaniusBuffer<u32>,
    _root_prefix: LaniusBuffer<u32>,
    pub node_emission: LaniusBuffer<u32>,
    pub root_order_range: LaniusBuffer<u32>,
    pub node_span: LaniusBuffer<u32>,
    pub root_total: LaniusBuffer<u32>,
    pub root_total_readback: wgpu::Buffer,
    init: wgpu::BindGroup,
    histograms: Vec<wgpu::BindGroup>,
    scan_local: wgpu::BindGroup,
    scan_blocks: Vec<wgpu::BindGroup>,
    scatters: Vec<wgpu::BindGroup>,
    depth_init: wgpu::BindGroup,
    depth_steps: Vec<wgpu::BindGroup>,
    depth_block_min: wgpu::BindGroup,
    depth_tree_steps: Vec<ExprDepthTreeStep>,
    contribution: wgpu::BindGroup,
    contribution_scan_local: wgpu::BindGroup,
    contribution_scan_blocks: Vec<wgpu::BindGroup>,
    root_prefix: wgpu::BindGroup,
    root_total_bind_group: wgpu::BindGroup,
    subtree_total_bind_group: wgpu::BindGroup,
    same_end_rank_init: wgpu::BindGroup,
    same_end_rank_steps: Vec<wgpu::BindGroup>,
    item_blocks: u32,
    scan_block_dispatches: u32,
}

impl GpuWasmCodeGenerator {
    pub(super) fn create_wasm_expr_order(
        &self,
        device: &wgpu::Device,
        hir_node_capacity: u32,
        forest_root: &wgpu::Buffer,
        inputs: GpuWasmCodegenInputs<'_>,
        working: &WasmWorkingBuffers,
    ) -> Result<ResidentWasmExprOrder> {
        let n_items = hir_node_capacity.max(1);
        let item_blocks = n_items.div_ceil(256).max(1);
        let depth_tree_leaf_base = item_blocks.next_power_of_two().max(1);
        let histogram_len = item_blocks.saturating_mul(RADIX_BUCKETS);
        let scan_steps = scan_steps_for_blocks(item_blocks as usize);

        let order_a = storage_u32_rw(
            device,
            "codegen.wasm.expr_order.a",
            n_items as usize,
            wgpu::BufferUsages::COPY_SRC,
        );
        let order_b = storage_u32_rw(
            device,
            "codegen.wasm.expr_order.b",
            n_items as usize,
            wgpu::BufferUsages::empty(),
        );
        let histogram = storage_u32_rw(
            device,
            "codegen.wasm.expr_order.histogram",
            histogram_len as usize,
            wgpu::BufferUsages::empty(),
        );
        let block_sum = storage_u32_rw(
            device,
            "codegen.wasm.expr_order.block_sum",
            item_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let block_prefix_a = storage_u32_rw(
            device,
            "codegen.wasm.expr_order.block_prefix.a",
            item_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let block_prefix_b = storage_u32_rw(
            device,
            "codegen.wasm.expr_order.block_prefix.b",
            item_blocks as usize,
            wgpu::BufferUsages::empty(),
        );

        let radix_params = (0..RADIX_STEPS)
            .map(|key_step| {
                uniform_from_val(
                    device,
                    &format!("codegen.wasm.expr_order.radix_params.{key_step}"),
                    &WasmExprRadixParams {
                        n_items,
                        n_blocks: item_blocks,
                        key_step,
                        reserved: 0,
                    },
                )
            })
            .collect::<Vec<_>>();
        let scan_params = scan_steps
            .iter()
            .enumerate()
            .map(|(step_i, &scan_step)| {
                uniform_from_val(
                    device,
                    &format!("codegen.wasm.expr_order.scan_params.{step_i}"),
                    &WasmScanParams {
                        n_items: histogram_len,
                        n_blocks: item_blocks,
                        scan_step,
                        out_capacity: histogram_len,
                    },
                )
            })
            .collect::<Vec<_>>();
        let contribution_scan_params = scan_steps
            .iter()
            .enumerate()
            .map(|(step_i, &scan_step)| {
                uniform_from_val(
                    device,
                    &format!("codegen.wasm.expr_contribution.scan_params.{step_i}"),
                    &WasmScanParams {
                        n_items,
                        n_blocks: item_blocks,
                        scan_step,
                        out_capacity: n_items,
                    },
                )
            })
            .collect::<Vec<_>>();

        // These buffers contain uint4(byte_len, unsupported,
        // generic-incompatible, member) rows; storage_u32_rw counts scalar
        // words.
        let contribution = storage_u32_rw(
            device,
            "codegen.wasm.expr_contribution",
            n_items as usize * 4,
            wgpu::BufferUsages::empty(),
        );
        let contribution_local_prefix = storage_u32_rw(
            device,
            "codegen.wasm.expr_contribution.local_prefix",
            n_items as usize * 4,
            wgpu::BufferUsages::empty(),
        );
        // Reuse the contribution scan inputs as the final same-end link/rank
        // pair. They are not populated with byte contributions until after the
        // expression radix order has consumed the rank.
        let mut same_end_rank_step_count = pointer_jump_step_count(n_items);
        if same_end_rank_step_count % 2 != 0 {
            // One extra converged pointer-jump step is idempotent and leaves
            // the final rank in the reusable contribution pair.
            same_end_rank_step_count += 1;
        }
        let depth_step_count = same_end_rank_step_count;
        let contribution_block_sum = storage_u32_rw(
            device,
            "codegen.wasm.expr_contribution.block_sum",
            item_blocks as usize * 4,
            wgpu::BufferUsages::empty(),
        );
        let contribution_block_prefix_a = storage_u32_rw(
            device,
            "codegen.wasm.expr_contribution.block_prefix.a",
            item_blocks as usize * 4,
            wgpu::BufferUsages::empty(),
        );
        let contribution_block_prefix_b = storage_u32_rw(
            device,
            "codegen.wasm.expr_contribution.block_prefix.b",
            item_blocks as usize * 4,
            wgpu::BufferUsages::empty(),
        );
        let root_prefix = storage_u32_rw(
            device,
            "codegen.wasm.expr_root_prefix",
            n_items as usize * 4,
            wgpu::BufferUsages::empty(),
        );
        let node_emission = storage_u32_rw(
            device,
            "codegen.wasm.expr_node_emission",
            n_items as usize * 2,
            wgpu::BufferUsages::empty(),
        );
        let root_order_range = storage_u32_rw(
            device,
            "codegen.wasm.expr_root_order_range",
            n_items as usize * 2,
            wgpu::BufferUsages::empty(),
        );
        let node_span = storage_u32_rw(
            device,
            "codegen.wasm.expr_node_span",
            n_items as usize * 2,
            wgpu::BufferUsages::empty(),
        );
        let root_total = storage_u32_rw(
            device,
            "codegen.wasm.expr_root_total",
            n_items as usize * 2,
            wgpu::BufferUsages::COPY_SRC,
        );
        let subtree_total = &working.expr_subtree_total_buf;
        let subtree_features = &working.expr_subtree_features_buf;
        let root_total_readback = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("codegen.wasm.expr_root_total.readback"),
            size: if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
                (n_items as u64 * 8).max(8)
            } else {
                8
            },
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        let init = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_expr_order_init"),
            &self.hir_expr_order_init_pass,
            0,
            &[
                ("gExprRadix", radix_params[0].as_entire_binding()),
                ("expr_order", order_a.as_entire_binding()),
            ],
        )?;
        let same_end_rank_init = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_expr_same_end_rank_init"),
            &self.hir_expr_same_end_rank_init_pass,
            0,
            &[
                ("gExprRadix", radix_params[0].as_entire_binding()),
                (
                    "hir_expr_parent_node",
                    inputs.expressions.parent_node.as_entire_binding(),
                ),
                ("hir_token_end", inputs.hir_token_end.as_entire_binding()),
                ("expr_same_end_link", contribution.as_entire_binding()),
                (
                    "expr_same_end_rank",
                    contribution_local_prefix.as_entire_binding(),
                ),
            ],
        )?;
        let same_end_rank_steps = (0..same_end_rank_step_count)
            .map(|step| {
                let (link_in, rank_in, link_out, rank_out) = if step % 2 == 0 {
                    (
                        &contribution,
                        &contribution_local_prefix,
                        &order_a,
                        &order_b,
                    )
                } else {
                    (
                        &order_a,
                        &order_b,
                        &contribution,
                        &contribution_local_prefix,
                    )
                };
                create_wasm_bind_group(
                    device,
                    Some("codegen_wasm_hir_expr_same_end_rank_step"),
                    &self.hir_expr_same_end_rank_step_pass,
                    0,
                    &[
                        ("gExprRadix", radix_params[0].as_entire_binding()),
                        ("expr_same_end_link_in", link_in.as_entire_binding()),
                        ("expr_same_end_rank_in", rank_in.as_entire_binding()),
                        ("expr_same_end_link_out", link_out.as_entire_binding()),
                        ("expr_same_end_rank_out", rank_out.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        // Once the radix order has consumed same-end ranks, the two uint2
        // metadata buffers are transient expression-depth states. The final
        // state remains in node_span until call ranges are published; the
        // regular root-total pass then overwrites both buffers with their
        // long-lived meanings.
        let depth_init = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_expr_depth_init"),
            &self.hir_expr_depth_init_pass,
            0,
            &[
                ("gExprRadix", radix_params[0].as_entire_binding()),
                (
                    "hir_expr_parent_node",
                    inputs.expressions.parent_node.as_entire_binding(),
                ),
                ("expr_depth_state", node_span.as_entire_binding()),
            ],
        )?;
        let depth_steps = (0..depth_step_count)
            .map(|step| {
                let (state_in, state_out) = if step % 2 == 0 {
                    (&node_span, &root_total)
                } else {
                    (&root_total, &node_span)
                };
                create_wasm_bind_group(
                    device,
                    Some("codegen_wasm_hir_expr_depth_step"),
                    &self.hir_expr_depth_step_pass,
                    0,
                    &[
                        ("gExprRadix", radix_params[0].as_entire_binding()),
                        ("expr_depth_state_in", state_in.as_entire_binding()),
                        ("expr_depth_state_out", state_out.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let depth_block_min = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_expr_depth_block_min"),
            &self.hir_expr_depth_block_min_pass,
            0,
            &[
                ("gExprRadix", radix_params[0].as_entire_binding()),
                ("expr_order", order_a.as_entire_binding()),
                ("expr_depth_state", node_span.as_entire_binding()),
                (
                    "expr_depth_block_min",
                    contribution_block_sum.as_entire_binding(),
                ),
            ],
        )?;
        let mut depth_tree_steps = Vec::new();
        let leaf_params = uniform_from_val(
            device,
            "codegen.wasm.expr_depth_tree.leaves",
            &WasmExprDepthTreeParams {
                n_blocks: item_blocks,
                leaf_base: depth_tree_leaf_base,
                start_node: 0,
                node_count: depth_tree_leaf_base,
                mode: 0,
                reserved0: 0,
                reserved1: 0,
                reserved2: 0,
            },
        );
        let leaf_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_expr_depth_tree_leaves"),
            &self.hir_expr_depth_build_min_tree_pass,
            0,
            &[
                ("gExprDepthTree", leaf_params.as_entire_binding()),
                (
                    "expr_depth_block_min",
                    contribution_block_sum.as_entire_binding(),
                ),
                ("expr_depth_min_tree", histogram.as_entire_binding()),
            ],
        )?;
        depth_tree_steps.push(ExprDepthTreeStep {
            _params: leaf_params,
            bind_group: leaf_bind_group,
            workgroups: depth_tree_leaf_base.div_ceil(256).max(1),
        });
        let mut level_start = depth_tree_leaf_base / 2;
        while level_start != 0 {
            let params = uniform_from_val(
                device,
                &format!("codegen.wasm.expr_depth_tree.level.{level_start}"),
                &WasmExprDepthTreeParams {
                    n_blocks: item_blocks,
                    leaf_base: depth_tree_leaf_base,
                    start_node: level_start,
                    node_count: level_start,
                    mode: 1,
                    reserved0: 0,
                    reserved1: 0,
                    reserved2: 0,
                },
            );
            let bind_group = create_wasm_bind_group(
                device,
                Some("codegen_wasm_hir_expr_depth_tree_level"),
                &self.hir_expr_depth_build_min_tree_pass,
                0,
                &[
                    ("gExprDepthTree", params.as_entire_binding()),
                    (
                        "expr_depth_block_min",
                        contribution_block_sum.as_entire_binding(),
                    ),
                    ("expr_depth_min_tree", histogram.as_entire_binding()),
                ],
            )?;
            depth_tree_steps.push(ExprDepthTreeStep {
                _params: params,
                bind_group,
                workgroups: level_start.div_ceil(256).max(1),
            });
            level_start /= 2;
        }
        let mut histograms = Vec::new();
        let mut scatters = Vec::new();
        for key_step in 0..RADIX_STEPS as usize {
            let (input, output) = if key_step % 2 == 0 {
                (&order_a, &order_b)
            } else {
                (&order_b, &order_a)
            };
            histograms.push(create_wasm_bind_group(
                device,
                Some("codegen_wasm_hir_expr_order_histogram"),
                &self.hir_expr_order_histogram_pass,
                0,
                &[
                    ("gExprRadix", radix_params[key_step].as_entire_binding()),
                    ("hir_expr_forest_root_node", forest_root.as_entire_binding()),
                    ("hir_token_end", inputs.hir_token_end.as_entire_binding()),
                    (
                        "expr_same_end_rank",
                        contribution_local_prefix.as_entire_binding(),
                    ),
                    ("expr_order_in", input.as_entire_binding()),
                    ("expr_radix_histogram", histogram.as_entire_binding()),
                ],
            )?);
            scatters.push(create_wasm_bind_group(
                device,
                Some("codegen_wasm_hir_expr_order_scatter"),
                &self.hir_expr_order_scatter_pass,
                0,
                &[
                    ("gExprRadix", radix_params[key_step].as_entire_binding()),
                    ("hir_expr_forest_root_node", forest_root.as_entire_binding()),
                    ("hir_token_end", inputs.hir_token_end.as_entire_binding()),
                    (
                        "expr_same_end_rank",
                        contribution_local_prefix.as_entire_binding(),
                    ),
                    ("expr_order_in", input.as_entire_binding()),
                    ("expr_radix_histogram_prefix", histogram.as_entire_binding()),
                    (
                        "expr_radix_block_prefix",
                        final_prefix(&scan_params, &block_prefix_a, &block_prefix_b)
                            .as_entire_binding(),
                    ),
                    ("expr_order_out", output.as_entire_binding()),
                ],
            )?);
        }
        let scan_local = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_expr_order_scan_local"),
            &self.hir_expr_order_scan_local_pass,
            0,
            &[
                ("gScan", scan_params[0].as_entire_binding()),
                ("expr_radix_histogram", histogram.as_entire_binding()),
                ("expr_radix_block_sum", block_sum.as_entire_binding()),
            ],
        )?;
        let scan_blocks = scan_params
            .iter()
            .enumerate()
            .map(|(step_i, params)| {
                let input = if step_i == 0 {
                    &block_sum
                } else if step_i % 2 == 1 {
                    &block_prefix_a
                } else {
                    &block_prefix_b
                };
                let output = if step_i % 2 == 0 {
                    &block_prefix_a
                } else {
                    &block_prefix_b
                };
                create_wasm_bind_group(
                    device,
                    Some("codegen_wasm_hir_expr_order_scan_blocks"),
                    &self.hir_body_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", params.as_entire_binding()),
                        ("body_scan_block_sum", block_sum.as_entire_binding()),
                        ("body_scan_block_prefix_in", input.as_entire_binding()),
                        ("body_scan_block_prefix_out", output.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;

        let body_binding_context = WasmBodyBindingContext::new(inputs, working);
        let final_agg_prefix = if (working.func_scan_param_bufs.len() - 1) % 2 == 0 {
            &working.wasm_agg_scan_prefix_a_buf
        } else {
            &working.wasm_agg_scan_prefix_b_buf
        };
        let mut contribution_bindings = Vec::new();
        body_binding_context.extend(&mut contribution_bindings, final_agg_prefix);
        contribution_bindings.extend([
            ("hir_expr_forest_root_node", forest_root.as_entire_binding()),
            (
                "hir_expr_parent_node",
                inputs.expressions.parent_node.as_entire_binding(),
            ),
            ("expr_order", order_a.as_entire_binding()),
            ("expr_contribution", contribution.as_entire_binding()),
            ("expr_node_emission", node_emission.as_entire_binding()),
        ]);
        let contribution_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_expr_contribution"),
            &self.hir_expr_contribution_pass,
            0,
            &contribution_bindings,
        )?;
        let contribution_scan_local = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_expr_contribution_scan_local"),
            &self.hir_expr_contribution_scan_local_pass,
            0,
            &[
                ("gScan", contribution_scan_params[0].as_entire_binding()),
                ("expr_contribution", contribution.as_entire_binding()),
                (
                    "expr_contribution_local_prefix",
                    contribution_local_prefix.as_entire_binding(),
                ),
                (
                    "expr_contribution_block_sum",
                    contribution_block_sum.as_entire_binding(),
                ),
            ],
        )?;
        let contribution_scan_blocks = contribution_scan_params
            .iter()
            .enumerate()
            .map(|(step_i, params)| {
                let input = if step_i == 0 {
                    &contribution_block_sum
                } else if step_i % 2 == 1 {
                    &contribution_block_prefix_a
                } else {
                    &contribution_block_prefix_b
                };
                let output = if step_i % 2 == 0 {
                    &contribution_block_prefix_a
                } else {
                    &contribution_block_prefix_b
                };
                create_wasm_bind_group(
                    device,
                    Some("codegen_wasm_hir_expr_contribution_scan_blocks"),
                    &self.hir_expr_contribution_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", params.as_entire_binding()),
                        (
                            "expr_contribution_block_sum",
                            contribution_block_sum.as_entire_binding(),
                        ),
                        (
                            "expr_contribution_block_prefix_in",
                            input.as_entire_binding(),
                        ),
                        (
                            "expr_contribution_block_prefix_out",
                            output.as_entire_binding(),
                        ),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let final_contribution_prefix = final_prefix(
            &contribution_scan_params,
            &contribution_block_prefix_a,
            &contribution_block_prefix_b,
        );
        let root_prefix_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_expr_root_prefix"),
            &self.hir_expr_root_prefix_pass,
            0,
            &[
                ("gExprRadix", radix_params[0].as_entire_binding()),
                ("hir_expr_forest_root_node", forest_root.as_entire_binding()),
                ("expr_order", order_a.as_entire_binding()),
                (
                    "expr_contribution_local_prefix",
                    contribution_local_prefix.as_entire_binding(),
                ),
                (
                    "expr_contribution_block_prefix",
                    final_contribution_prefix.as_entire_binding(),
                ),
                ("expr_root_prefix", root_prefix.as_entire_binding()),
                (
                    "expr_root_order_range",
                    root_order_range.as_entire_binding(),
                ),
            ],
        )?;
        let root_total_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_expr_root_total"),
            &self.hir_expr_root_total_pass,
            0,
            &[
                ("gExprRadix", radix_params[0].as_entire_binding()),
                ("hir_expr_forest_root_node", forest_root.as_entire_binding()),
                ("expr_order", order_a.as_entire_binding()),
                ("expr_contribution", contribution.as_entire_binding()),
                (
                    "expr_contribution_local_prefix",
                    contribution_local_prefix.as_entire_binding(),
                ),
                (
                    "expr_contribution_block_prefix",
                    final_contribution_prefix.as_entire_binding(),
                ),
                ("expr_root_prefix", root_prefix.as_entire_binding()),
                ("expr_root_total", root_total.as_entire_binding()),
                (
                    "expr_root_order_range",
                    root_order_range.as_entire_binding(),
                ),
                ("expr_node_span", node_span.as_entire_binding()),
            ],
        )?;
        let subtree_total_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_expr_subtree_total"),
            &self.hir_expr_subtree_total_pass,
            0,
            &[
                ("gExprRadix", radix_params[0].as_entire_binding()),
                (
                    "gExprDepthTree",
                    depth_tree_steps[0]._params.as_entire_binding(),
                ),
                ("hir_expr_forest_root_node", forest_root.as_entire_binding()),
                ("expr_order", order_a.as_entire_binding()),
                (
                    "expr_root_order_range",
                    root_order_range.as_entire_binding(),
                ),
                ("expr_depth_state", node_span.as_entire_binding()),
                (
                    "expr_depth_block_min",
                    contribution_block_sum.as_entire_binding(),
                ),
                ("expr_depth_min_tree", histogram.as_entire_binding()),
                ("expr_contribution", contribution.as_entire_binding()),
                (
                    "expr_contribution_local_prefix",
                    contribution_local_prefix.as_entire_binding(),
                ),
                (
                    "expr_contribution_block_prefix",
                    final_contribution_prefix.as_entire_binding(),
                ),
                ("expr_subtree_total", subtree_total.as_entire_binding()),
                (
                    "expr_subtree_features",
                    subtree_features.as_entire_binding(),
                ),
            ],
        )?;

        Ok(ResidentWasmExprOrder {
            _radix_params: radix_params,
            _scan_params: scan_params,
            _contribution_scan_params: contribution_scan_params,
            order_a,
            _order_b: order_b,
            _histogram: histogram,
            _block_sum: block_sum,
            _block_prefix_a: block_prefix_a,
            _block_prefix_b: block_prefix_b,
            _contribution: contribution,
            _contribution_local_prefix: contribution_local_prefix,
            _contribution_block_sum: contribution_block_sum,
            _contribution_block_prefix_a: contribution_block_prefix_a,
            _contribution_block_prefix_b: contribution_block_prefix_b,
            _root_prefix: root_prefix,
            node_emission,
            root_order_range,
            node_span,
            root_total,
            root_total_readback,
            init,
            histograms,
            scan_local,
            scan_blocks,
            scatters,
            depth_init,
            depth_steps,
            depth_block_min,
            depth_tree_steps,
            contribution: contribution_bind_group,
            contribution_scan_local,
            contribution_scan_blocks,
            root_prefix: root_prefix_bind_group,
            root_total_bind_group,
            subtree_total_bind_group,
            same_end_rank_init,
            same_end_rank_steps,
            item_blocks,
            scan_block_dispatches: item_blocks.div_ceil(256).max(1),
        })
    }

    pub(super) fn record_wasm_expr_order(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        order: &ResidentWasmExprOrder,
    ) -> Result<()> {
        record_expr_order_pass(
            encoder,
            self.hir_expr_same_end_rank_init_pass.pipeline()?.as_ref(),
            &order.same_end_rank_init,
            order.item_blocks,
            "codegen.wasm.expr_same_end_rank.init",
        );
        for bind_group in &order.same_end_rank_steps {
            record_expr_order_pass(
                encoder,
                self.hir_expr_same_end_rank_step_pass.pipeline()?.as_ref(),
                bind_group,
                order.item_blocks,
                "codegen.wasm.expr_same_end_rank.step",
            );
        }
        record_expr_order_pass(
            encoder,
            self.hir_expr_order_init_pass.pipeline()?.as_ref(),
            &order.init,
            order.item_blocks,
            "codegen.wasm.expr_order.init",
        );
        for step in 0..RADIX_STEPS as usize {
            record_expr_order_pass(
                encoder,
                self.hir_expr_order_histogram_pass.pipeline()?.as_ref(),
                &order.histograms[step],
                order.item_blocks,
                "codegen.wasm.expr_order.histogram",
            );
            record_expr_order_pass(
                encoder,
                self.hir_expr_order_scan_local_pass.pipeline()?.as_ref(),
                &order.scan_local,
                order.item_blocks,
                "codegen.wasm.expr_order.scan_local",
            );
            for bind_group in &order.scan_blocks {
                record_expr_order_pass(
                    encoder,
                    self.hir_body_scan_blocks_pass.pipeline()?.as_ref(),
                    bind_group,
                    order.scan_block_dispatches,
                    "codegen.wasm.expr_order.scan_blocks",
                );
            }
            record_expr_order_pass(
                encoder,
                self.hir_expr_order_scatter_pass.pipeline()?.as_ref(),
                &order.scatters[step],
                order.item_blocks,
                "codegen.wasm.expr_order.scatter",
            );
        }
        Ok(())
    }

    pub(super) fn record_wasm_expr_contributions(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        order: &ResidentWasmExprOrder,
    ) -> Result<()> {
        record_expr_order_pass(
            encoder,
            self.hir_expr_depth_init_pass.pipeline()?.as_ref(),
            &order.depth_init,
            order.item_blocks,
            "codegen.wasm.expr_depth.init",
        );
        for bind_group in &order.depth_steps {
            record_expr_order_pass(
                encoder,
                self.hir_expr_depth_step_pass.pipeline()?.as_ref(),
                bind_group,
                order.item_blocks,
                "codegen.wasm.expr_depth.step",
            );
        }
        record_expr_order_pass(
            encoder,
            self.hir_expr_depth_block_min_pass.pipeline()?.as_ref(),
            &order.depth_block_min,
            order.item_blocks,
            "codegen.wasm.expr_depth.block_min",
        );
        for step in &order.depth_tree_steps {
            record_expr_order_pass(
                encoder,
                self.hir_expr_depth_build_min_tree_pass.pipeline()?.as_ref(),
                &step.bind_group,
                step.workgroups,
                "codegen.wasm.expr_depth.build_min_tree",
            );
        }
        record_expr_order_pass(
            encoder,
            self.hir_expr_contribution_pass.pipeline()?.as_ref(),
            &order.contribution,
            order.item_blocks,
            "codegen.wasm.expr_contribution",
        );
        record_expr_order_pass(
            encoder,
            self.hir_expr_contribution_scan_local_pass
                .pipeline()?
                .as_ref(),
            &order.contribution_scan_local,
            order.item_blocks,
            "codegen.wasm.expr_contribution_scan_local",
        );
        for bind_group in &order.contribution_scan_blocks {
            record_expr_order_pass(
                encoder,
                self.hir_expr_contribution_scan_blocks_pass
                    .pipeline()?
                    .as_ref(),
                bind_group,
                order.scan_block_dispatches,
                "codegen.wasm.expr_contribution_scan_blocks",
            );
        }
        record_expr_order_pass(
            encoder,
            self.hir_expr_root_prefix_pass.pipeline()?.as_ref(),
            &order.root_prefix,
            order.item_blocks,
            "codegen.wasm.expr_root_prefix",
        );
        record_expr_order_pass(
            encoder,
            self.hir_expr_subtree_total_pass.pipeline()?.as_ref(),
            &order.subtree_total_bind_group,
            order.item_blocks,
            "codegen.wasm.expr_subtree_total",
        );
        record_expr_order_pass(
            encoder,
            self.hir_expr_root_total_pass.pipeline()?.as_ref(),
            &order.root_total_bind_group,
            order.item_blocks,
            "codegen.wasm.expr_root_total",
        );
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
            encoder.copy_buffer_to_buffer(
                &order.root_total,
                0,
                &order.root_total_readback,
                0,
                order.root_total.size(),
            );
        }
        Ok(())
    }
}

fn pointer_jump_step_count(n_items: u32) -> u32 {
    let mut span = 1u32;
    let mut steps = 0u32;
    while span < n_items.max(1) {
        span = span.saturating_mul(2);
        steps += 1;
    }
    steps
}

fn final_prefix<'a>(
    scan_params: &[LaniusBuffer<WasmScanParams>],
    a: &'a LaniusBuffer<u32>,
    b: &'a LaniusBuffer<u32>,
) -> &'a LaniusBuffer<u32> {
    if (scan_params.len() - 1) % 2 == 0 {
        a
    } else {
        b
    }
}

fn record_expr_order_pass(
    encoder: &mut wgpu::CommandEncoder,
    pipeline: &wgpu::ComputePipeline,
    bind_group: &wgpu::BindGroup,
    groups: u32,
    label: &'static str,
) {
    let (x, y) = workgroup_grid_1d(groups);
    let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    pass.set_pipeline(pipeline);
    pass.set_bind_group(0, Some(bind_group), &[]);
    pass.dispatch_workgroups(x, y, 1);
}
