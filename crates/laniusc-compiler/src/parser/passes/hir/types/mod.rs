/// Type alias target extraction pass.
pub mod find_type_alias_targets;
/// Scatters resolved type path leaf ownership rows.
pub mod publish_type_path_leaves;
/// Type alias owner propagation seed pass.
pub mod seed_type_alias_owners;
/// Root-owner seed pass.
pub mod seed_type_roots;
/// Type alias owner propagation pointer-jump pass.
pub mod walk_type_alias_owners;
/// Propagates type path leaf rows through nested type syntax.
pub mod walk_type_path_leaves;
/// Root-owner pointer-jump pass.
pub mod walk_type_roots;
