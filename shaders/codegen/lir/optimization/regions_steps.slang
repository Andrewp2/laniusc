import codegen.lir.lowering_ir;
import codegen.lir.optimization_ir;
import codegen.lir.optimization.structure_tables;

// Marks real structured-control openers in scheduled OptIR order.

bool opens_region(uint op)
{
    return op == SEMANTIC_LIR_OP_BLOCK_BEGIN ||
        op == SEMANTIC_LIR_OP_LOOP_BEGIN ||
        op == SEMANTIC_LIR_OP_IF_BEGIN;
}

public void mark_control_flow_regions(uint position, uint total)
{
    if (position >= total) return;

    uint node = semantic_schedule_order[position];
    bool opener = node < total && opens_region(opt_ir_op(opt_ir_core[node]));
    opt_ir_block_start_flag[position] = opener ? 1u : 0u;
}

// Clears only the region range fields after block/function construction.

public void clear_function_region_ranges(uint function_id, uint total)
{
    if (function_id >= total) return;
    opt_ir_functions[function_id].region_start = STRUCTURE_INVALID;
    opt_ir_functions[function_id].region_count = 0u;
}

// Materializes one region interval per structured opener. Matching is local to
// the opener's synthetic semantic recipe: those rows have contiguous stable
// OptIR IDs even when scheduled child instructions occur inside the interval.

void scatter_control_flow_regions_structure_failure(uint node)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, node);
}

uint matching_owner_local_close(uint opener, uint total)
{
    uint owner = opt_ir_source_hir[opener];
    uint nesting = 1u;
    for (uint candidate = opener + 1u; candidate < total; ++candidate)
    {
        if (opt_ir_source_hir[candidate] != owner) break;
        uint op = opt_ir_op(opt_ir_core[candidate]);
        if (opens_region(op))
            nesting += 1u;
        else if (op == SEMANTIC_LIR_OP_CONTROL_END)
        {
            nesting -= 1u;
            if (nesting == 0u) return candidate;
        }
    }
    return STRUCTURE_INVALID;
}

// Adds every half-open region interval to a range-max segment tree. Dense
// region IDs follow opening position, so the maximum active ID is exactly the
// innermost region at a point. Closing labels are excluded and therefore
// inherit their parent region.

void write_region_ownership_ranges(uint region_id, OptIrRegion region, uint nodes)
{
    uint left = min(region.position_start, nodes) + nodes;
    uint right = min(region.position_end, nodes) + nodes;
    uint encoded = region_id + 1u;
    while (left < right)
    {
        if ((left & 1u) != 0u)
            InterlockedMax(opt_ir_region_ownership_tree[left++], encoded);
        if ((right & 1u) != 0u)
            InterlockedMax(opt_ir_region_ownership_tree[--right], encoded);
        left >>= 1u;
        right >>= 1u;
    }
}

public void scatter_control_flow_regions(uint position, uint total, uint region_total, uint block_total)
{
    if (position >= total || opt_ir_block_start_flag[position] == 0u) return;

    uint node = semantic_schedule_order[position];
    uint region_id = opt_ir_block_prefix[position];
    uint close = node < total ? matching_owner_local_close(node, total) : STRUCTURE_INVALID;
    uint close_position = close < total ? opt_ir_position_by_node[close] : STRUCTURE_INVALID;
    uint block_id = node < total ? opt_ir_control[node].block_id : STRUCTURE_INVALID;
    bool valid = region_id < region_total && block_id < block_total &&
        close_position > position && close_position < total;
    if (!valid)
    {
        scatter_control_flow_regions_structure_failure(node);
        return;
    }

    OptIrRegion region;
    region.function_id = opt_ir_blocks[block_id].function_id;
    region.parent_region = STRUCTURE_INVALID;
    region.position_start = position;
    region.position_end = close_position;
    opt_ir_regions[region_id] = region;
    write_region_ownership_ranges(region_id, region, total);

    OptIrNodeControl control = opt_ir_control[node];
    control.region_id = region_id;
    opt_ir_control[node] = control;
}

// Assigns the innermost active structured region to every scheduled OptIR
// node with one logarithmic segment-tree point query per invocation.

void assign_nodes_to_regions_structure_failure(uint node)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, node);
}

uint region_for_position(uint position, uint nodes)
{
    uint cursor = nodes + position;
    uint encoded = 0u;
    while (cursor != 0u)
    {
        encoded = max(encoded, opt_ir_region_ownership_tree[cursor]);
        cursor >>= 1u;
    }
    return encoded == 0u ? STRUCTURE_INVALID : encoded - 1u;
}

// The parent covers the position before the opener. The ownership tree
// excludes closing labels, so a preceding sibling has already closed.
public void link_control_flow_region(uint row, uint regions, uint nodes, uint functions)
{
    OptIrRegion region = opt_ir_regions[row];
    uint parent = region.position_start > 0u
        ? region_for_position(region.position_start - 1u, nodes) : STRUCTURE_INVALID;
    bool valid = region.function_id < functions && region.position_start < region.position_end;
    if (parent != STRUCTURE_INVALID)
    {
        valid = valid && parent < row && parent < regions;
        if (valid)
        {
            if (opt_ir_regions[parent].function_id != region.function_id)
                parent = STRUCTURE_INVALID;
            else
                valid = opt_ir_regions[parent].position_end > region.position_end;
        }
    }
    if (!valid)
    {
        scatter_control_flow_regions_structure_failure(region.position_start);
        return;
    }

    opt_ir_regions[row].parent_region = parent;
    InterlockedMin(opt_ir_functions[region.function_id].region_start, row);
    InterlockedMax(opt_ir_functions[region.function_id].region_count, row + 1u);
}

// Converts temporary region ends into counts and validates per-function
// contiguity in dense opening order.

void finalize_function_region_ranges_structure_failure(uint function_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, function_id);
}

public void finalize_function_region_ranges(uint function_id, uint function_total, uint region_total)
{
    if (function_id >= function_total) return;

    OptIrFunction function = opt_ir_functions[function_id];
    if (function.region_start == STRUCTURE_INVALID)
    {
        if (function.region_count != 0u) finalize_function_region_ranges_structure_failure(function_id);
        function.region_start = 0u;
        function.region_count = 0u;
        opt_ir_functions[function_id] = function;
        return;
    }

    uint end = function.region_count;
    bool valid = function.region_start < end && end <= region_total &&
        opt_ir_regions[function.region_start].function_id == function_id &&
        opt_ir_regions[end - 1u].function_id == function_id;
    if (!valid)
    {
        finalize_function_region_ranges_structure_failure(function_id);
        function.region_count = 0u;
    }
    else
        function.region_count = end - function.region_start;
    opt_ir_functions[function_id] = function;
}

public void assign_nodes_to_regions(uint position, uint total, uint block_total, uint region_total)
{
    if (position >= total) return;

    uint node = semantic_schedule_order[position];
    if (node >= total)
    {
        assign_nodes_to_regions_structure_failure(node);
        return;
    }
    uint block_id = opt_ir_control[node].block_id;
    uint region_id = region_for_position(position, total);
    bool valid = block_id < block_total;
    if (region_id != STRUCTURE_INVALID)
    {
        valid = valid && region_id < region_total;
        if (valid)
        {
            OptIrRegion region = opt_ir_regions[region_id];
            valid = region.function_id == opt_ir_blocks[block_id].function_id &&
                region.position_start <= position && position < region.position_end;
            if (opens_region(opt_ir_op(opt_ir_core[node])))
            {
                uint expected_parent = position == 0u
                    ? STRUCTURE_INVALID : region_for_position(position - 1u, total);
                if (expected_parent != STRUCTURE_INVALID)
                {
                    valid = valid && expected_parent < region_total;
                    if (valid && opt_ir_regions[expected_parent].function_id !=
                        region.function_id)
                        expected_parent = STRUCTURE_INVALID;
                }
                valid = valid && region.position_start == position &&
                    region.parent_region == expected_parent;
            }
        }
    }
    if (!valid)
    {
        assign_nodes_to_regions_structure_failure(node);
        return;
    }

    OptIrNodeControl control = opt_ir_control[node];
    control.region_id = region_id;
    opt_ir_control[node] = control;
}

// Assigns block-entry region ownership from the same interval-stabbing tree.

void assign_blocks_to_regions_structure_failure(uint block_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, block_id);
}

public void assign_blocks_to_regions(uint block_id, uint block_total, uint region_total, uint nodes)
{
    if (block_id >= block_total) return;

    OptIrBlock block = opt_ir_blocks[block_id];
    bool valid = block.position_start < nodes;
    uint region_id = valid
        ? region_for_position(block.position_start, nodes) : STRUCTURE_INVALID;
    if (region_id != STRUCTURE_INVALID)
    {
        valid = valid && region_id < region_total;
        if (valid)
        {
            OptIrRegion region = opt_ir_regions[region_id];
            valid = region.function_id == block.function_id &&
                region.position_start <= block.position_start &&
                block.position_start < region.position_end;
        }
    }
    if (!valid)
    {
        assign_blocks_to_regions_structure_failure(block_id);
        return;
    }
    opt_ir_block_region[block_id] = region_id;
}

// Validates the completed immediate-dominator relation against every CFG
// edge. One invocation independently climbs the compact dominator relation
// from the source block; no invocation owns a function or project-wide walk.

void validate_region_edges_structure_failure(uint edge_id, uint reason)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_STRUCTURE_REGION_VALIDATE_EDGES, ignored);
    // Sort by edge first and subreason second so this detail describes the
    // same earliest edge published through first_unsupported_opt_row.
    InterlockedMin(lowering_status[0u].diagnostic_detail,
        (edge_id << 8u) | (reason & 0xffu));
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, edge_id);
}

public void validate_region_edges(uint edge_id, uint edge_total, uint block_total, uint function_total)
{
    if (edge_id >= edge_total) return;

    OptIrEdge edge = opt_ir_edges[edge_id];
    uint to_block = opt_ir_edge_to_block(edge.packed_target);
    bool valid = edge.from_block < block_total && to_block < block_total;
    if (!valid)
    {
        validate_region_edges_structure_failure(edge_id, 1u);
        return;
    }

    OptIrBlock from = opt_ir_blocks[edge.from_block];
    OptIrBlock to = opt_ir_blocks[to_block];
    uint edge_start = opt_ir_block_edge_start(from);
    uint edge_count = opt_ir_block_edge_count(from);
    bool expected_back = to.position_start <= from.position_start;
    valid = from.function_id < function_total &&
        to.function_id == from.function_id &&
        edge_id >= edge_start && edge_id < edge_start + edge_count &&
        expected_back ==
            ((opt_ir_edge_flags(edge.packed_target) &
                OPT_IR_EDGE_BACK) != 0u);

    uint entry = valid ? opt_ir_functions[from.function_id].entry_block : STRUCTURE_INVALID;
    bool source_unreachable = edge.from_block != entry &&
        opt_ir_immediate_dominator[edge.from_block] ==
            OPT_IR_DOMINATOR_UNREACHABLE;
    // Unreachable blocks remain in the structural IR so source provenance and
    // later dead-code elimination stay exact. Their outgoing edges are valid
    // CFG records, but they impose no dominance obligation on reachable code.
    if (source_unreachable)
        return;

    uint dominator = valid ? opt_ir_immediate_dominator[to_block] : STRUCTURE_INVALID;
    if (to_block == entry)
    {
        validate_region_edges_structure_failure(edge_id, 2u);
        return;
    }
    if (dominator >= block_total)
    {
        validate_region_edges_structure_failure(edge_id, 3u);
        return;
    }
    if (opt_ir_blocks[dominator].function_id != from.function_id)
    {
        validate_region_edges_structure_failure(edge_id, 4u);
        return;
    }

    // The acyclic resolver omits retreating edges. Prove that each such edge
    // targets a dominator of its source, so it cannot add an entry path that
    // invalidates the forward-graph solution. Checking only the target's
    // parent would admit a sibling-to-sibling retreating edge incorrectly.
    if (expected_back) dominator = to_block;
    uint cursor = edge.from_block;
    uint steps = 0u;
    while (valid && cursor != dominator)
    {
        uint parent = opt_ir_immediate_dominator[cursor];
        valid = parent < block_total && parent != cursor &&
            opt_ir_blocks[parent].function_id == from.function_id;
        cursor = parent;
        steps += 1u;
        valid = valid && steps < block_total;
    }
    if (!valid)
        validate_region_edges_structure_failure(edge_id, 5u);
    else if (cursor != dominator)
        validate_region_edges_structure_failure(edge_id, 6u);
}
