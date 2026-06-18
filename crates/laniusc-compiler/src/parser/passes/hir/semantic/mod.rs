/// Semantic child-index relation passes.
pub mod child;
/// Compaction pass from parser tree nodes to dense semantic HIR rows.
pub mod compact_scatter;
/// Semantic depth propagation passes.
pub mod depth;
/// Dispatch-argument generation for semantic-HIR work.
pub mod dispatch_args;
/// Navigation record pass for semantic siblings and relatives.
pub mod nav;
/// Semantic parent propagation and scatter passes.
pub mod parent;
/// Prefix-scan passes for semantic HIR compaction.
pub mod prefix;
/// Semantic subtree-end propagation pass.
pub mod subtree_end;
