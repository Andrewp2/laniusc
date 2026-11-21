import codegen.lir.lowering_ir;
import codegen.lir.optimization_ir;
import codegen.lir.optimization.structure_tables;
import codegen.lir.optimization.demands.ssa_sparse_sets;

// Checks, one lane per edge, that an edge stays inside its function and is
// flagged retreating exactly when it does not ascend in scheduling position.
// The forward edges therefore form an acyclic graph, which is what lets every
// reachability and dominator lane finish without waiting on another.

void validate_dominator_edges_structure_failure(uint edge_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, edge_id);
}

public void validate_dominator_edges(uint edge_id, uint total, uint block_total)
{
    if (edge_id >= total) return;
    OptIrEdge edge = opt_ir_edges[edge_id];
    uint to_block = opt_ir_edge_to_block(edge.packed_target);
    if (edge.from_block >= block_total || to_block >= block_total)
    {
        validate_dominator_edges_structure_failure(edge_id);
        return;
    }
    OptIrBlock from = opt_ir_blocks[edge.from_block];
    OptIrBlock to = opt_ir_blocks[to_block];
    bool backward = to.position_start <= from.position_start;
    if (from.function_id != to.function_id || backward !=
        ((opt_ir_edge_flags(edge.packed_target) & OPT_IR_EDGE_BACK) != 0u))
        validate_dominator_edges_structure_failure(edge_id);
}

// Publishes the dominator every block knows without looking at another: a
// function entry dominates itself and an unreachable block has none. Every
// other reachable block starts unresolved for the resolve pass.

void seed_immediate_dominators_structure_failure(uint block_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block_id);
}

public void seed_immediate_dominators(uint block_id, uint block_total, uint function_total)
{
    if (block_id >= block_total) return;
    OptIrBlock block = opt_ir_blocks[block_id];
    if (block.function_id >= function_total)
    {
        seed_immediate_dominators_structure_failure(block_id);
        opt_ir_immediate_dominator[block_id] = OPT_IR_DOMINATOR_INVALID;
        return;
    }
    bool entry = block_id == opt_ir_functions[block.function_id].entry_block;
    if (opt_ir_reachable[block_id] == 0u)
    {
        if (entry) seed_immediate_dominators_structure_failure(block_id);
        opt_ir_immediate_dominator[block_id] = OPT_IR_DOMINATOR_UNREACHABLE;
        return;
    }
    opt_ir_immediate_dominator[block_id] = entry
        ? block_id : OPT_IR_DOMINATOR_UNRESOLVED;
}

// Resolves immediate dominators from the reachable forward CFG, one lane per
// block. A block's immediate dominator is the nearest common dominator of its
// reachable forward predecessors: a block with one such predecessor takes it
// directly, and a join walks the predecessors' dominator chains downward in
// scheduling position until they meet. Lexical source owners do not determine
// dominance.
//
// A walk may need the dominator of a join that is not resolved yet. The lane
// never waits for it: it computes that dominator itself and publishes it, then
// resumes its own walk. A dominator depends only on blocks at lower positions
// and every lane computes the same value from the same resolved inputs, so
// concurrent publications agree and every lane finishes whatever the others
// do.
//
// The later edge validator proves that every omitted retreating edge targets
// a dominator of its source. Adding those edges therefore preserves the exact
// dominators computed on this acyclic graph.

static const uint WALK_DONE = 0u;
// The walk needs the dominator of an unresolved block and keeps its place.
static const uint WALK_BLOCKED = 1u;
// The CFG is malformed at the goal. Every lane reaches the same verdict.
static const uint WALK_FAILED = 2u;
static const uint WALK_EXHAUSTED = 3u;

// The resumable computation of one block's immediate dominator.
struct Walk
{
    uint goal;
    // The next predecessor row to fold, and the end of the goal's rows.
    uint row;
    uint end;
    // The common dominator of the predecessors folded so far.
    uint left;
    // The predecessor being folded into `left`.
    uint right;
};

void resolve_immediate_dominators_structure_failure(uint block)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

Walk walk_begin(uint goal, uint block_total, uint edge_total)
{
    Walk walk;
    walk.goal = goal;
    walk.row = opt_ir_edge_prefix[goal];
    walk.end = goal + 1u < block_total
        ? opt_ir_edge_prefix[goal + 1u] : edge_total;
    walk.left = STRUCTURE_INVALID;
    walk.right = STRUCTURE_INVALID;
    return walk;
}

uint walk_advance(inout Walk walk, uint block_total, uint edge_total,
    out uint blocker)
{
    blocker = STRUCTURE_INVALID;
    if (walk.end > edge_total || walk.row > walk.end) return WALK_FAILED;
    OptIrBlock record = opt_ir_blocks[walk.goal];
    // Every step reads one predecessor row, lowers one cursor or closes one
    // fold. A cursor strictly descends in position, so one fold takes at most
    // two steps per block. The right cursor starts again at each predecessor,
    // so a join of many arms needs one such walk per remaining row.
    uint rows = walk.end - walk.row;
    uint budget = rows > 0xffffu || block_total > 0x3fffu
        ? 0xffffffffu : (rows + 1u) * (2u * block_total + 3u);
    for (uint step = 0u; step < budget; ++step)
    {
        if (walk.right == STRUCTURE_INVALID)
        {
            if (walk.row >= walk.end)
                return walk.left < block_total ? WALK_DONE : WALK_FAILED;
            uint edge_id = opt_ir_predecessor_edge_ids[walk.row];
            walk.row += 1u;
            if (edge_id >= edge_total) return WALK_FAILED;
            OptIrEdge edge = opt_ir_edges[edge_id];
            uint predecessor = edge.from_block;
            if (predecessor >= block_total ||
                opt_ir_edge_to_block(edge.packed_target) != walk.goal)
                return WALK_FAILED;
            if ((opt_ir_edge_flags(edge.packed_target) & OPT_IR_EDGE_BACK) != 0u ||
                opt_ir_reachable[predecessor] == 0u)
                continue;
            OptIrBlock source = opt_ir_blocks[predecessor];
            if (source.function_id != record.function_id ||
                source.position_start >= record.position_start)
                return WALK_FAILED;
            if (walk.left == STRUCTURE_INVALID) walk.left = predecessor;
            else walk.right = predecessor;
            continue;
        }
        if (walk.left == walk.right)
        {
            walk.right = STRUCTURE_INVALID;
            continue;
        }
        // The cursor at the higher position cannot dominate the other.
        bool advance_left = opt_ir_blocks[walk.left].position_start >
            opt_ir_blocks[walk.right].position_start;
        uint cursor = advance_left ? walk.left : walk.right;
        uint parent = ssa_atomic_load(opt_ir_immediate_dominator, cursor);
        if (parent == OPT_IR_DOMINATOR_UNRESOLVED)
        {
            blocker = cursor;
            return WALK_BLOCKED;
        }
        if (parent >= block_total || parent == cursor ||
            opt_ir_blocks[parent].function_id != record.function_id ||
            opt_ir_blocks[parent].position_start >=
                opt_ir_blocks[cursor].position_start)
            return WALK_FAILED;
        if (advance_left) walk.left = parent;
        else walk.right = parent;
    }
    return WALK_EXHAUSTED;
}

public void resolve_immediate_dominators(uint block, uint block_total, uint edge_total)
{
    if (block >= block_total) return;
    if (ssa_atomic_load(opt_ir_immediate_dominator, block) !=
        OPT_IR_DOMINATOR_UNRESOLVED)
        return;

    // `own` is this block's walk while the lane resolves `needed`, the block
    // that walk is blocked on. Resolving `needed` can itself block on a lower
    // block; the lane then resolves that one and starts `needed` over.
    Walk walk = walk_begin(block, block_total, edge_total);
    Walk own = walk;
    uint needed = STRUCTURE_INVALID;
    // Each round resolves a block or descends to a lower one.
    uint budget = block_total > 0xffffu
        ? 0xffffffffu : block_total * block_total + 1u;
    for (uint round = 0u; round < budget; ++round)
    {
        if (needed != STRUCTURE_INVALID)
        {
            if (ssa_atomic_load(opt_ir_immediate_dominator, needed) !=
                OPT_IR_DOMINATOR_UNRESOLVED)
            {
                walk = own;
                needed = STRUCTURE_INVALID;
            }
            else if (walk.goal != needed &&
                ssa_atomic_load(opt_ir_immediate_dominator, walk.goal) !=
                    OPT_IR_DOMINATOR_UNRESOLVED)
                walk = walk_begin(needed, block_total, edge_total);
        }
        if (needed == STRUCTURE_INVALID &&
            ssa_atomic_load(opt_ir_immediate_dominator, block) !=
                OPT_IR_DOMINATOR_UNRESOLVED)
            return;

        uint blocker;
        uint status = walk_advance(walk, block_total, edge_total, blocker);
        if (status == WALK_EXHAUSTED) break;
        if (status == WALK_BLOCKED)
        {
            if (needed == STRUCTURE_INVALID)
            {
                own = walk;
                needed = blocker;
            }
            walk = walk_begin(blocker, block_total, edge_total);
            continue;
        }
        if (status == WALK_FAILED) resolve_immediate_dominators_structure_failure(walk.goal);
        uint ignored;
        InterlockedExchange(opt_ir_immediate_dominator[walk.goal],
            status == WALK_DONE ? walk.left : OPT_IR_DOMINATOR_INVALID,
            ignored);
        if (needed == STRUCTURE_INVALID) return;
    }
    resolve_immediate_dominators_structure_failure(block);
}

// Validate one well-formed immediate dominator per reachable block before
// declaration-specific SSA work begins, and clear the reused per-block child
// count column that dominator-tree compaction counts into next. The clear
// writes only this block's row of a column the validation never reads.

void validate_immediate_dominators_structure_failure(uint block_id)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_STRUCTURE_DOMINATOR_VALIDATE, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block_id);
}

public void validate_immediate_dominators(uint block_id, uint block_total, uint function_total)
{
    if (block_id >= block_total) return;
    opt_ir_edge_count_by_block[block_id] = 0u;

    OptIrBlock block = opt_ir_blocks[block_id];
    if (block.function_id >= function_total)
    {
        validate_immediate_dominators_structure_failure(block_id);
        return;
    }

    uint dominator = opt_ir_immediate_dominator[block_id];
    uint entry = opt_ir_functions[block.function_id].entry_block;
    bool reachable = opt_ir_reachable[block_id] != 0u;
    bool valid = block_id == entry
        ? reachable && dominator == block_id
        : !reachable ? dominator == OPT_IR_DOMINATOR_UNREACHABLE
        : dominator < block_total && dominator != block_id &&
          opt_ir_blocks[dominator].function_id == block.function_id &&
          opt_ir_blocks[dominator].position_start < block.position_start;
    if (!valid) validate_immediate_dominators_structure_failure(block_id);
}

// Counts one tree child for every reachable non-entry CFG block.

void count_dominator_children_structure_failure(uint block_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block_id);
}

public void count_dominator_children(uint block_id, uint total)
{
    if (block_id >= total) return;

    uint dominator = opt_ir_immediate_dominator[block_id];
    if (dominator == block_id || dominator == OPT_IR_DOMINATOR_UNREACHABLE)
        return;
    if (dominator >= total)
    {
        count_dominator_children_structure_failure(block_id);
        return;
    }
    InterlockedAdd(opt_ir_edge_count_by_block[dominator], 1u);
}

// Converts child counts to per-parent scatter cursors. The immutable prefix
// column remains the compact range-start relation.

public void prepare_dominator_child_ranges(uint block_id, uint total)
{
    if (block_id < total)
        opt_ir_edge_count_by_block[block_id] =
            opt_ir_predecessor_cursor[block_id];
}

// Scatters dense child block IDs into their immediate dominator's range.

void scatter_dominator_children_structure_failure(uint block_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block_id);
}

public void scatter_dominator_children(uint block_id, uint total)
{
    if (block_id >= total) return;

    uint dominator = opt_ir_immediate_dominator[block_id];
    if (dominator == block_id || dominator == OPT_IR_DOMINATOR_UNREACHABLE)
        return;
    if (dominator >= total)
    {
        scatter_dominator_children_structure_failure(block_id);
        return;
    }

    uint row;
    InterlockedAdd(opt_ir_edge_count_by_block[dominator], 1u, row);
    if (row >= total)
    {
        scatter_dominator_children_structure_failure(block_id);
        return;
    }
    opt_ir_dominator_children[row] = block_id;
}

// Validates compact dominator-tree ranges independently of scatter order.
// One invocation checks one parent cursor and, when present, one child row;
// no parent thread walks a potentially project-sized child range.
// It also clears this block's row of the inverse child-row index that the
// Euler tour fills next; the validation never reads that index.

void validate_dominator_child_ranges_structure_failure(uint block_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block_id);
}

public void validate_dominator_child_ranges(uint block_id, uint block_total, uint child_total)
{
    if (block_id >= block_total) return;
    opt_ir_dominator_child_row_by_block[block_id] = OPT_IR_DOMINATOR_INVALID;

    uint start = opt_ir_predecessor_cursor[block_id];
    uint end = block_id + 1u < block_total
        ? opt_ir_predecessor_cursor[block_id + 1u] : child_total;
    bool valid = end >= start && end <= child_total &&
        opt_ir_edge_count_by_block[block_id] == end;

    if (block_id < child_total)
    {
        uint row = block_id;
        uint lo = 0u;
        uint hi = block_total;
        while (lo < hi)
        {
            uint mid = lo + (hi - lo) / 2u;
            if (opt_ir_predecessor_cursor[mid] <= row) lo = mid + 1u;
            else hi = mid;
        }
        uint parent = lo == 0u ? OPT_IR_DOMINATOR_INVALID : lo - 1u;
        uint child = opt_ir_dominator_children[row];
        valid = valid && parent < block_total && child < block_total &&
            opt_ir_immediate_dominator[child] == parent;
    }
    if (!valid) validate_dominator_child_ranges_structure_failure(block_id);
}

// Inverts the compact dominator-child relation. Each reachable non-root block
// appears exactly once, so every invocation writes a distinct block row.

void index_dominator_tour_child_rows_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

public void index_dominator_tour_child_rows(uint row, uint block_total, uint child_total)
{
    if (row >= child_total) return;
    uint child = opt_ir_dominator_children[row];
    if (child >= block_total)
    {
        index_dominator_tour_child_rows_structure_failure(row);
        return;
    }
    opt_ir_dominator_child_row_by_block[child] = row;
}

// Creates one downward and one upward Euler-tour arc for each reachable
// non-root dominator-tree node. `previous` links each per-function tour into a
// list; down arcs contribute one to the eventual preorder count.

void seed_dominator_tour_structure_failure(uint block)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

uint child_range_end(uint block, uint block_total, uint child_total)
{
    return block + 1u < block_total
        ? opt_ir_predecessor_cursor[block + 1u]
        : child_total;
}

public void seed_dominator_tour(uint arc, uint block_total, uint child_total)
{
    if (arc >= block_total * 2u) return;
    uint block = arc >> 1u;
    bool upward = (arc & 1u) != 0u;

    OptIrDominatorTourLink link;
    link.previous = STRUCTURE_INVALID;
    link.down_count = 0u;
    uint parent = opt_ir_immediate_dominator[block];
    if (parent == block || parent == OPT_IR_DOMINATOR_UNREACHABLE)
    {
        opt_ir_dominator_tour_link_a[arc] = link;
        return;
    }

    bool valid = parent < block_total;
    if (!upward)
    {
        uint child_row = valid
            ? opt_ir_dominator_child_row_by_block[block] : STRUCTURE_INVALID;
        uint sibling_start = valid
            ? opt_ir_predecessor_cursor[parent] : STRUCTURE_INVALID;
        valid = valid && child_row >= sibling_start &&
            child_row < child_range_end(parent, block_total, child_total) &&
            opt_ir_dominator_children[child_row] == block;
        if (valid && child_row != sibling_start)
        {
            uint previous_sibling =
                opt_ir_dominator_children[child_row - 1u];
            valid = previous_sibling < block_total;
            link.previous = valid ? previous_sibling * 2u + 1u : STRUCTURE_INVALID;
        }
        else if (valid && opt_ir_immediate_dominator[parent] != parent)
            link.previous = parent * 2u;
        link.down_count = 1u;
    }
    else
    {
        uint start = opt_ir_predecessor_cursor[block];
        uint end = child_range_end(block, block_total, child_total);
        valid = valid && end >= start && end <= child_total;
        if (valid && end != start)
        {
            uint last_child = opt_ir_dominator_children[end - 1u];
            valid = last_child < block_total;
            link.previous = valid ? last_child * 2u + 1u : STRUCTURE_INVALID;
        }
        else if (valid)
            link.previous = block * 2u;
    }

    if (!valid)
    {
        seed_dominator_tour_structure_failure(block);
        link.previous = STRUCTURE_INVALID;
        link.down_count = 0u;
    }
    opt_ir_dominator_tour_link_a[arc] = link;
}

// One parallel list-ranking step over the Euler-tour predecessor relation:
// a round follows up to STRUCTURE_POINTER_JUMP_HOPS input links, so the reach of a
// link grows by that factor per round (`pointer_jump_hop_pairs` in
// lowering_ir.rs).

void propagate_dominator_tour_ranks_structure_failure(uint arc)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, arc >> 1u);
}

public void propagate_dominator_tour_ranks(
    uint arc,
    uint arc_total,
    RWStructuredBuffer<OptIrDominatorTourLink> in_links,
    RWStructuredBuffer<OptIrDominatorTourLink> out_links)
{
    if (arc >= arc_total) return;

    OptIrDominatorTourLink link = in_links[arc];
    for (uint hop = 0u; hop < STRUCTURE_POINTER_JUMP_HOPS && link.previous != STRUCTURE_INVALID; ++hop)
    {
        if (link.previous >= arc_total)
        {
            propagate_dominator_tour_ranks_structure_failure(arc);
            link.previous = STRUCTURE_INVALID;
            break;
        }
        OptIrDominatorTourLink previous =
            in_links[link.previous];
        link.previous = previous.previous;
        link.down_count += previous.down_count;
    }
    out_links[arc] = link;
}

// Converts ranked Euler arcs to an exact preorder and half-open subtree range
// for every reachable dominator-tree block. It also clears this block's row
// of the preorder-to-block inverse, which the next pass scatters into; this
// pass never reads the inverse.

void publish_dominator_tour_structure_failure(uint block)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

public void publish_dominator_tour(uint block, uint block_total, uint function_total)
{
    if (block >= block_total) return;
    opt_ir_block_by_dominator_preorder[block] = STRUCTURE_INVALID;

    uint function_id = opt_ir_blocks[block].function_id;
    uint parent = opt_ir_immediate_dominator[block];
    bool valid = function_id < function_total;
    OptIrFunction function = valid ? opt_ir_functions[function_id]
        : opt_ir_functions[0u];
    uint preorder = STRUCTURE_INVALID;
    uint subtree_end = STRUCTURE_INVALID;

    if (parent == OPT_IR_DOMINATOR_UNREACHABLE)
    {
        opt_ir_dominator_preorder[block] = STRUCTURE_INVALID;
        opt_ir_dominator_subtree_end[block] = STRUCTURE_INVALID;
        return;
    }
    if (parent == block)
    {
        uint child_total = min(opt_ir_predecessor_total[0u], block_total);
        uint start = opt_ir_predecessor_cursor[block];
        uint end = block + 1u < block_total
            ? opt_ir_predecessor_cursor[block + 1u] : child_total;
        valid = valid && function.entry_block == block && end >= start &&
            end <= child_total;
        uint descendants = 0u;
        if (valid && end != start)
        {
            uint last_child = opt_ir_dominator_children[end - 1u];
            valid = last_child < block_total;
            OptIrDominatorTourLink last = valid
                ? opt_ir_dominator_tour_link_a[last_child * 2u + 1u]
                : opt_ir_dominator_tour_link_a[0u];
            valid = valid && last.previous == STRUCTURE_INVALID;
            descendants = valid ? last.down_count : 0u;
        }
        preorder = function.block_start;
        subtree_end = preorder + descendants + 1u;
    }
    else
    {
        valid = valid && parent < block_total;
        OptIrDominatorTourLink down = valid
            ? opt_ir_dominator_tour_link_a[block * 2u]
            : opt_ir_dominator_tour_link_a[0u];
        OptIrDominatorTourLink up = valid
            ? opt_ir_dominator_tour_link_a[block * 2u + 1u]
            : opt_ir_dominator_tour_link_a[0u];
        valid = valid && down.previous == STRUCTURE_INVALID && up.previous == STRUCTURE_INVALID &&
            down.down_count != 0u && up.down_count >= down.down_count;
        preorder = function.block_start + down.down_count;
        subtree_end = preorder + up.down_count - down.down_count + 1u;
    }

    valid = valid && preorder >= function.block_start &&
        subtree_end > preorder &&
        subtree_end <= function.block_start + function.block_count;
    if (!valid)
    {
        publish_dominator_tour_structure_failure(block);
        preorder = STRUCTURE_INVALID;
        subtree_end = STRUCTURE_INVALID;
    }
    opt_ir_dominator_preorder[block] = preorder;
    opt_ir_dominator_subtree_end[block] = subtree_end;
}

// Inverts reachable preorder identities and reports duplicate assignments.

void invert_dominator_preorder_structure_failure(uint block)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

public void invert_dominator_preorder(uint block, uint total)
{
    if (block >= total) return;
    uint preorder = opt_ir_dominator_preorder[block];
    if (preorder == STRUCTURE_INVALID) return;
    if (preorder >= total)
    {
        invert_dominator_preorder_structure_failure(block);
        return;
    }
    uint previous;
    InterlockedCompareExchange(
        opt_ir_block_by_dominator_preorder[preorder], STRUCTURE_INVALID,
        block, previous);
    if (previous != STRUCTURE_INVALID) invert_dominator_preorder_structure_failure(block);
}

// Validates exact preorder inversion and parent/child subtree containment.

void validate_dominator_preorder_structure_failure(uint block)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

public void validate_dominator_preorder(uint block, uint block_total, uint function_total)
{
    if (block >= block_total) return;

    uint parent = opt_ir_immediate_dominator[block];
    uint preorder = opt_ir_dominator_preorder[block];
    uint subtree_end = opt_ir_dominator_subtree_end[block];
    if (parent == OPT_IR_DOMINATOR_UNREACHABLE)
    {
        if (preorder != STRUCTURE_INVALID || subtree_end != STRUCTURE_INVALID)
            validate_dominator_preorder_structure_failure(block);
        return;
    }

    uint function_id = opt_ir_blocks[block].function_id;
    bool valid = parent < block_total && function_id < function_total &&
        preorder < block_total && subtree_end > preorder &&
        opt_ir_block_by_dominator_preorder[preorder] == block;
    OptIrFunction function = valid ? opt_ir_functions[function_id]
        : opt_ir_functions[0u];
    valid = valid && preorder >= function.block_start &&
        subtree_end <= function.block_start + function.block_count;
    if (valid && parent == block)
        valid = function.entry_block == block &&
            preorder == function.block_start;
    else if (valid)
    {
        uint parent_preorder = opt_ir_dominator_preorder[parent];
        uint parent_end = opt_ir_dominator_subtree_end[parent];
        valid = opt_ir_blocks[parent].function_id == function_id &&
            parent_preorder <= preorder && subtree_end <= parent_end &&
            parent_preorder != preorder;
    }
    if (!valid) validate_dominator_preorder_structure_failure(block);
}
