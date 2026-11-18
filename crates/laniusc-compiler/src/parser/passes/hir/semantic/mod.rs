/// Builds the (minimum, count) heaps the child-index query reads.
pub mod build_child_index_heaps;
/// Builds the semantic-end search heaps the parent search reads.
pub mod build_semantic_end_heaps;
/// Semantic depth propagation passes.
pub mod depth;
/// Counts each semantic row's earlier siblings with a heap range query.
pub mod find_child_indices;
/// Finds dense semantic parents by searching the semantic-end heaps.
pub mod find_semantic_parents;
/// Compaction pass from parser tree nodes to dense semantic HIR rows.
pub mod list_semantic_rows;
/// Local semantic-node prefix count pass.
pub mod mark_semantic_rows;
/// Navigation record pass for semantic siblings and relatives.
pub mod project_semantic_navigation;
/// Semantic subtree-end propagation pass.
pub mod project_semantic_subtree_ends;
/// Block scan for semantic-node prefix counts.
pub mod scan_semantic_blocks;
/// Propagates semantic parent rows through tree ancestry.
pub mod walk_semantic_parents;
/// Dispatch-argument generation for semantic-HIR work.
pub mod write_semantic_dispatch_args;
