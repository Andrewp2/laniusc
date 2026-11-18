/// Array literal record passes.
pub mod array;
/// Call expression and argument record passes.
pub mod call;
/// Final Pareas-style compact HIR phase boundary.
pub mod canonical;
/// Context relation passes for nearest statement, block, and control owners.
pub mod context;
/// Enum, variant, and match-related HIR passes.
pub mod enums;
/// Function signature and return-type passes.
/// Item kind, declaration-token, namespace, visibility, and import passes.
pub mod item;
/// Generic list ranking helpers shared by HIR record families.
pub mod list;
/// HIR node classification and per-family record extraction.
pub mod records;
/// HIR source spans.
pub mod spans;
/// Match expression and arm record passes.
pub mod matches;
/// Method declaration and receiver record passes.
pub mod method;
/// Parameter linking, ranking, id, and field passes.
pub mod param;
/// Canonical path segment ownership and ordinal lowering passes.
pub mod path;
/// Dense semantic-HIR topology and navigation passes.
pub mod semantic;
/// Canonical decoded string literal lowering passes.
pub mod string;
/// Struct declaration, field, literal, and rank passes.
pub mod structs;
/// Type form, type-path, type-argument, and alias passes.
pub mod types;
/// Per-round state for the GPU early exit of bounded relation walks.
pub mod walk_state;

/// Number of input links followed by one bounded relation-walk dispatch.
// The walk kernels (`LINKS_PER_STEP` in shaders/parser/hir) and the
// GPU-side round schedules (tree/depth/schedule.slang,
// write_semantic_dispatch_args.slang) use the same count. At 64 the settings
// tree (2.9 M nodes) needs 4 rounds instead of 6; a walk that converges in
// fewer links stops early within the round.
pub(crate) const BOUNDED_WALK_LINKS_PER_STEP: u32 = 64;

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

/// `bounded_walk_step_capacity` rounded up to an even count, so the walk
/// always ends in its `_a` buffers and never needs the whole-buffer `_b`
/// to `_a` finalize copy. The enum, struct-field and match-arm walks read
/// their `_b` buffers only at worklist rows an earlier round wrote, so their
/// links passes do not initialize `_b`. The extra round, when there is one,
/// only rewrites rows the walk already resolved.
pub(crate) fn bounded_walk_even_step_capacity(items: u32) -> u32 {
    let steps = bounded_walk_step_capacity(items);
    steps + (steps & 1)
}

#[cfg(test)]
mod tests {
    use super::bounded_walk_step_capacity;

    #[test]
    fn bounded_walk_rounds_cover_the_full_tree_capacity() {
        assert_eq!(bounded_walk_step_capacity(1), 0);
        assert_eq!(bounded_walk_step_capacity(64), 1);
        assert_eq!(bounded_walk_step_capacity(65), 2);
        assert_eq!(bounded_walk_step_capacity(16_777_216), 4);
    }
}
