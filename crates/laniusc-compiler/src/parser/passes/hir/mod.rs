/// Array literal record passes.
pub mod array;
/// Binary expression span and result passes.
pub mod binary;
/// Call expression and argument record passes.
pub mod call;
/// Final Pareas-style compact HIR phase boundary.
pub mod canonical;
/// Context relation passes for nearest statement, block, and control owners.
pub mod context;
/// Enum, variant, and match-related HIR passes.
pub mod enums;
/// Expression form and result-root passes.
pub mod expr;
/// Function signature and return-type passes.
pub mod functions;
/// Item kind, declaration-token, namespace, visibility, and import passes.
pub mod item;
/// Generic list ranking helpers shared by HIR record families.
pub mod list;
/// Literal value extraction passes.
pub mod literal_values;
/// Match expression and arm record passes.
pub mod matches;
/// Member access record passes.
pub mod member;
/// Method declaration and receiver record passes.
pub mod method;
/// Tree-node to HIR-node classification pass.
pub mod nodes;
/// Parameter linking, ranking, id, and field passes.
pub mod param;
/// Canonical path segment ownership and ordinal lowering passes.
pub mod path;
/// Member/index postfix metadata materialization pass.
pub mod postfix_fields;
/// Range-expression span passes.
pub mod range_spans;
/// HIR record clearing passes.
pub mod record;
/// Dense semantic-HIR topology and navigation passes.
pub mod semantic;
/// Common source-span propagation passes for HIR nodes.
pub mod spans;
/// Statement kind, scope, and assignment-field passes.
pub mod stmt_fields;
/// Statement scope relation passes.
pub mod stmt_scope;
/// Canonical decoded string literal lowering passes.
pub mod string;
/// Struct declaration, field, literal, and rank passes.
pub mod structs;
/// Type form, type-path, type-argument, and alias passes.
pub mod types;

/// Number of input links followed by one bounded relation-walk dispatch.
pub(crate) const BOUNDED_WALK_LINKS_PER_STEP: u32 = 16;

/// Capacity-stable rounds needed when each dispatch follows up to 16 links.
pub(crate) fn bounded_walk_step_capacity(items: u32) -> u32 {
    let target = items.max(1);
    let mut reach = 1u32;
    let mut steps = 0u32;
    while reach < target {
        reach = reach.saturating_mul(BOUNDED_WALK_LINKS_PER_STEP);
        steps += 1;
    }
    steps
}

#[cfg(test)]
mod tests {
    use super::bounded_walk_step_capacity;

    #[test]
    fn bounded_walk_rounds_cover_the_full_tree_capacity() {
        assert_eq!(bounded_walk_step_capacity(1), 0);
        assert_eq!(bounded_walk_step_capacity(16), 1);
        assert_eq!(bounded_walk_step_capacity(17), 2);
        assert_eq!(bounded_walk_step_capacity(16_777_216), 6);
    }
}
