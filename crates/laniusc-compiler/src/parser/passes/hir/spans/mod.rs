/// Applies propagated binary expression spans.
pub mod apply_binary_spans;
/// Common source-span propagation passes for HIR nodes.
pub mod compute_hir_spans;
/// Binary expression span seed pass.
pub mod seed_binary_spans;
/// Range-expression span passes.
pub mod trim_range_spans;
/// Propagates binary expression spans through syntax parents.
pub mod walk_binary_spans;
/// Call source-span pass.
pub mod widen_call_spans;
/// Member expression span extraction pass.
pub mod widen_member_spans;
/// Struct literal span pass.
pub mod widen_struct_literal_spans;
