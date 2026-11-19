import codegen.lir.lowering_ir;
import codegen.lir.optimization_ir;
import codegen.lir.optimization.structure_tables;

public void seed_control_flow_functions(uint function_id, uint total)
{
    if (function_id >= total) return;

    OptIrFunction function;
    function.node_start = STRUCTURE_INVALID;
    function.node_count = 0u;
    function.block_start = STRUCTURE_INVALID;
    function.block_count = 0u;
    function.entry_block = STRUCTURE_INVALID;
    function.flags = semantic_functions[function_id].flags;
    function.region_start = 0u;
    function.region_count = 0u;
    opt_ir_functions[function_id] = function;
}

public void summarize_control_flow_functions(uint block_id, uint block_total, uint function_total, uint node_total)
{
    if (block_id >= block_total) return;

    OptIrBlock block = opt_ir_blocks[block_id];
    if (block.function_id >= function_total)
    {
        uint ignored;
        InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
            LOWERING_DIAGNOSTIC_NONE,
            LOWERING_DIAGNOSTIC_OPT_STRUCTURE_FUNCTION_REDUCE, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
        InterlockedMin(lowering_status[0u].first_unsupported_opt_row,
            block.terminator);
        return;
    }
    uint node_end = block_id + 1u < block_total &&
        opt_ir_blocks[block_id + 1u].function_id == block.function_id
        ? opt_ir_blocks[block_id + 1u].position_start : node_total;

    InterlockedMin(opt_ir_functions[block.function_id].node_start,
        block.position_start);
    InterlockedMax(opt_ir_functions[block.function_id].node_count, node_end);
    InterlockedMin(opt_ir_functions[block.function_id].block_start, block_id);
    InterlockedMax(opt_ir_functions[block.function_id].block_count,
        block_id + 1u);
    InterlockedMin(opt_ir_functions[block.function_id].entry_block, block_id);
    // region_count is not observable until this three-pass construction is
    // complete. Use it as the block-membership count so finalization can prove
    // that each function owns one contiguous block range, then reset it to the
    // currently empty region count.
    InterlockedAdd(opt_ir_functions[block.function_id].region_count, 1u);
}

void finalize_control_flow_functions_structure_failure(uint node)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_STRUCTURE_FUNCTION_FINALIZE, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, node);
}

public void finalize_control_flow_functions(uint function_id, uint total)
{
    if (function_id >= total) return;

    OptIrFunction function = opt_ir_functions[function_id];
    if (function.block_start == STRUCTURE_INVALID)
    {
        if (function.node_start != STRUCTURE_INVALID || function.node_count != 0u ||
            function.block_count != 0u || function.entry_block != STRUCTURE_INVALID ||
            function.region_count != 0u)
            finalize_control_flow_functions_structure_failure(0u);
        function.node_start = 0u;
        function.node_count = 0u;
        function.block_start = 0u;
        function.block_count = 0u;
        function.entry_block = STRUCTURE_INVALID;
    }
    else
    {
        uint node_total = min(gParams.semantic_capacity, opt_ir_total[0u]);
        uint block_total = min(gParams.block_capacity, opt_ir_block_total[0u]);
        uint node_end = function.node_count;
        uint block_end = function.block_count;
        uint first_node = function.node_start < node_total
            ? semantic_schedule_order[function.node_start] : STRUCTURE_INVALID;
        bool valid = function.node_start < node_end && node_end <= node_total &&
            function.block_start < block_end && block_end <= block_total &&
            function.entry_block == function.block_start &&
            function.region_count == block_end - function.block_start;
        if (valid)
        {
            OptIrBlock first = opt_ir_blocks[function.block_start];
            OptIrBlock last = opt_ir_blocks[block_end - 1u];
            valid = first.function_id == function_id &&
                last.function_id == function_id &&
                first.position_start == function.node_start;
        }
        if (!valid)
            finalize_control_flow_functions_structure_failure(first_node);
        function.node_count = valid ? node_end - function.node_start : 0u;
        function.block_count = valid ? block_end - function.block_start : 0u;
    }
    function.region_count = 0u;
    opt_ir_functions[function_id] = function;
}

// Seeds exact CFG reachability, one lane per block. A block is dead when it is
// no function entry and every forward predecessor is dead, so each lane counts
// its own forward predecessors and marks its block reachable unless that count
// is zero. The close pass then removes what only dead blocks lead to.
//
// Forward edges ascend in scheduling position and so form an acyclic graph.
// Retreating edges are left out: a retreating edge targets a dominator of its
// source, which a later validator proves, so it reaches nothing new.

// A dead root: the close lane of this block owns the region below it.
static const uint CLAIM_ROOT = 0xffffffffu;
static const uint CLAIM_NONE = 0xfffffffeu;
// Keeps an entry's count from ever reaching the last-predecessor transition.
static const uint ENTRY_BIAS = 0x40000000u;

void seed_control_flow_reachability_structure_failure(uint block)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_STRUCTURE_REACHABILITY_SEED, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

public void seed_control_flow_reachability(uint block, uint block_total, uint edge_total, uint function_total)
{
    if (block >= block_total) return;

    uint function_id = opt_ir_blocks[block].function_id;
    bool valid = function_id < function_total;
    bool entry = valid &&
        opt_ir_functions[function_id].entry_block == block;

    uint begin = opt_ir_predecessor_prefix[block];
    uint end = block + 1u < block_total
        ? opt_ir_predecessor_prefix[block + 1u] : edge_total;
    valid = valid && begin <= end && end <= edge_total;
    uint forward = 0u;
    for (uint row = begin; valid && row < end; ++row)
    {
        uint edge_id = opt_ir_predecessor_edge_ids[row];
        valid = edge_id < edge_total;
        if (!valid) break;
        uint flags = opt_ir_edge_flags(opt_ir_edges[edge_id].packed_target);
        if ((flags & OPT_IR_EDGE_BACK) == 0u) forward += 1u;
    }
    if (!valid) seed_control_flow_reachability_structure_failure(block);

    bool root = valid && !entry && forward == 0u;
    opt_ir_live_predecessor_count_by_block[block] =
        entry ? ENTRY_BIAS + forward : forward;
    opt_ir_reachable[block] = root ? 0u : 1u;
    opt_ir_dead_claim_by_block[block] = root ? CLAIM_ROOT : CLAIM_NONE;
}

// Closes the dead region below every dead root, one lane per block. Only the
// lane of a dead root does any work, so a program without dead blocks costs
// one load per block.
//
// A lane walks its region depth first. Each forward edge it leaves takes one
// from the target's count of live forward predecessors; the lane that takes
// the last one owns the target, marks it dead and descends into it. Exactly
// one lane owns each dead block, so no block is visited twice and no lane
// waits on another. The walk keeps no stack: a dead block records the edge
// that claimed it, and the lane returns along that edge to the next one.

void close_control_flow_reachability_structure_failure(uint block)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_STRUCTURE_REACHABILITY_CLOSE, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

public void close_control_flow_reachability(uint root, uint block_total, uint edge_total)
{
    if (root >= block_total) return;
    // Only this lane ever reads or writes the claim word of a dead root.
    if (opt_ir_dead_claim_by_block[root] != CLAIM_ROOT) return;

    uint block = root;
    uint ordinal = 0u;
    // Every step either consumes one edge of the region or returns from one
    // block of it.
    uint budget = block_total + edge_total + 1u;
    for (uint step = 0u; step < budget; ++step)
    {
        OptIrBlock source = opt_ir_blocks[block];
        uint edge_start = opt_ir_block_edge_start(source);
        uint edge_count = opt_ir_block_edge_count(source);
        if (edge_start > edge_total ||
            edge_count > edge_total - min(edge_start, edge_total))
        {
            close_control_flow_reachability_structure_failure(block);
            return;
        }
        if (ordinal < edge_count)
        {
            uint edge_id = edge_start + ordinal;
            ordinal += 1u;
            OptIrEdge edge = opt_ir_edges[edge_id];
            uint target = opt_ir_edge_to_block(edge.packed_target);
            if (edge.from_block != block || target >= block_total)
            {
                close_control_flow_reachability_structure_failure(block);
                continue;
            }
            if ((opt_ir_edge_flags(edge.packed_target) & OPT_IR_EDGE_BACK) != 0u)
                continue;
            uint prior;
            InterlockedAdd(opt_ir_live_predecessor_count_by_block[target],
                0xffffffffu, prior);
            if (prior != 1u) continue;
            // This lane took the last live forward predecessor of the target.
            opt_ir_reachable[target] = 0u;
            opt_ir_dead_claim_by_block[target] = edge_id;
            block = target;
            ordinal = 0u;
            continue;
        }
        uint claim = opt_ir_dead_claim_by_block[block];
        if (claim == CLAIM_ROOT) return;
        if (claim >= edge_total)
        {
            close_control_flow_reachability_structure_failure(block);
            return;
        }
        uint parent = opt_ir_edges[claim].from_block;
        if (parent >= block_total)
        {
            close_control_flow_reachability_structure_failure(block);
            return;
        }
        uint parent_start = opt_ir_block_edge_start(opt_ir_blocks[parent]);
        if (claim < parent_start)
        {
            close_control_flow_reachability_structure_failure(block);
            return;
        }
        ordinal = claim - parent_start + 1u;
        block = parent;
    }
    close_control_flow_reachability_structure_failure(root);
}

// Independently checks the reachability fixed point against the reverse CFG.

void validate_control_flow_reachability_structure_failure(uint block)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_STRUCTURE_REACHABILITY_VALIDATE, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block);
}

public void validate_control_flow_reachability(uint block, uint block_total, uint edge_total, uint function_total)
{
    if (block >= block_total) return;

    uint function_id = opt_ir_blocks[block].function_id;
    bool valid = function_id < function_total;
    bool entry = valid &&
        opt_ir_functions[function_id].entry_block == block;

    uint begin = opt_ir_predecessor_prefix[block];
    uint end = block + 1u < block_total
        ? opt_ir_predecessor_prefix[block + 1u] : edge_total;
    valid = valid && begin <= end && end <= edge_total;
    bool reachable_predecessor = false;
    for (uint row = begin; valid && row < end; ++row)
    {
        uint edge_id = opt_ir_predecessor_edge_ids[row];
        valid = edge_id < edge_total;
        if (!valid) break;
        OptIrEdge edge = opt_ir_edges[edge_id];
        valid = edge.from_block < block_total &&
            opt_ir_edge_to_block(edge.packed_target) == block;
        reachable_predecessor = reachable_predecessor ||
            (valid && opt_ir_reachable[edge.from_block] != 0u);
    }
    bool expected = entry || reachable_predecessor;
    valid = valid && (opt_ir_reachable[block] != 0u) == expected;
    if (!valid) validate_control_flow_reachability_structure_failure(block);
}
