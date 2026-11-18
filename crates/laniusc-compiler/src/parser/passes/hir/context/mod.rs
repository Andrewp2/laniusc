/// Statement scope relation passes.
pub mod finish_stmt_scopes;
/// Scatters nearest-context relation rows into semantic HIR records.
pub mod publish_context_relations;
/// Initializes nearest-context relation rows.
pub mod seed_context_relations;
/// Propagates nearest-context relation rows through semantic HIR ancestry.
pub mod walk_context_relations;
/// Propagates small nearest-context tables in one cooperative workgroup.
pub mod walk_small_context_relations;
