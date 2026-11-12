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

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_sparse_work;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint hir_capacity;
    uint block_capacity;
    uint edge_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<uint> opt_ir_edge_total;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<OptIrEdge> opt_ir_edges;
StructuredBuffer<uint> opt_ir_predecessor_prefix;
StructuredBuffer<uint> opt_ir_predecessor_edge_ids;
StructuredBuffer<uint> opt_ir_reachable;
RWStructuredBuffer<uint> opt_ir_immediate_dominator;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint NONE = 0xffffffffu;

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

void report_structure_failure(uint block)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

Walk walk_begin(uint goal, uint block_total, uint edge_total)
{
    Walk walk;
    walk.goal = goal;
    walk.row = opt_ir_predecessor_prefix[goal];
    walk.end = goal + 1u < block_total
        ? opt_ir_predecessor_prefix[goal + 1u] : edge_total;
    walk.left = NONE;
    walk.right = NONE;
    return walk;
}

uint walk_advance(inout Walk walk, uint block_total, uint edge_total,
    out uint blocker)
{
    blocker = NONE;
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
        if (walk.right == NONE)
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
            if (walk.left == NONE) walk.left = predecessor;
            else walk.right = predecessor;
            continue;
        }
        if (walk.left == walk.right)
        {
            walk.right = NONE;
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    if (block >= block_total) return;
    if (ssa_atomic_load(opt_ir_immediate_dominator, block) !=
        OPT_IR_DOMINATOR_UNRESOLVED)
        return;
    uint edge_total = min(opt_ir_edge_total[0u], gParams.edge_capacity);

    // `own` is this block's walk while the lane resolves `needed`, the block
    // that walk is blocked on. Resolving `needed` can itself block on a lower
    // block; the lane then resolves that one and starts `needed` over.
    Walk walk = walk_begin(block, block_total, edge_total);
    Walk own = walk;
    uint needed = NONE;
    // Each round resolves a block or descends to a lower one.
    uint budget = block_total > 0xffffu
        ? 0xffffffffu : block_total * block_total + 1u;
    for (uint round = 0u; round < budget; ++round)
    {
        if (needed != NONE)
        {
            if (ssa_atomic_load(opt_ir_immediate_dominator, needed) !=
                OPT_IR_DOMINATOR_UNRESOLVED)
            {
                walk = own;
                needed = NONE;
            }
            else if (walk.goal != needed &&
                ssa_atomic_load(opt_ir_immediate_dominator, walk.goal) !=
                    OPT_IR_DOMINATOR_UNRESOLVED)
                walk = walk_begin(needed, block_total, edge_total);
        }
        if (needed == NONE &&
            ssa_atomic_load(opt_ir_immediate_dominator, block) !=
                OPT_IR_DOMINATOR_UNRESOLVED)
            return;

        uint blocker;
        uint status = walk_advance(walk, block_total, edge_total, blocker);
        if (status == WALK_EXHAUSTED) break;
        if (status == WALK_BLOCKED)
        {
            if (needed == NONE)
            {
                own = walk;
                needed = blocker;
            }
            walk = walk_begin(blocker, block_total, edge_total);
            continue;
        }
        if (status == WALK_FAILED) report_structure_failure(walk.goal);
        uint ignored;
        InterlockedExchange(opt_ir_immediate_dominator[walk.goal],
            status == WALK_DONE ? walk.left : OPT_IR_DOMINATOR_INVALID,
            ignored);
        if (needed == NONE) return;
    }
    report_structure_failure(block);
}
