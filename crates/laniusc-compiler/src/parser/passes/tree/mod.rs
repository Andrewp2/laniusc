/// Applies scanned tree prefix values to recovered rows.
pub mod apply_arity_deficit_prefix;
/// Builds the max tree used by tree prefix recovery.
pub mod build_deficit_max_tree;
/// Previous-sibling buffer initialization.
pub mod clear_previous_siblings;
/// Source-file token boundary pass.
pub mod find_source_file_token_ends;
/// Per-workgroup raw-tree depth summaries from subtree close counts.
pub mod find_tree_depth_block_maxima;
/// Recovered tree parent construction pass.
pub mod find_tree_parents;
/// Recovered tree token-span pass.
pub mod find_tree_spans;
/// Scans tree prefix block sums.
pub mod scan_arity_deficit_blocks;
/// Previous-sibling scatter from next-sibling links.
pub mod scatter_previous_siblings;
/// Raw-tree-height indirect schedule construction.
pub mod schedule_tree_depth_jumps;
/// Computes local tree prefix values by block.
pub mod sum_arity_deficits_in_blocks;
/// Active recovered-tree indirect dispatch argument pass.
pub mod write_active_node_dispatch_args;
