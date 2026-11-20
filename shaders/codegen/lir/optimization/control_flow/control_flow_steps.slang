import codegen.lir.lowering_ir;
import codegen.lir.optimization_ir;
import codegen.lir.optimization.structure_tables;

static const uint INVALID = 0xffffffffu;

public uint semantic_capacity() { return gParams.semantic_capacity; }
public uint block_capacity() { return gParams.block_capacity; }
public uint edge_capacity() { return gParams.edge_capacity; }

public void project_optimization_nodes(uint row, uint total, uint semantic_total)
{
    if (row == 0u)
    {
        // Bounded workspaces may process a prefix for diagnostics, but that
        // prefix is never a successful compilation of the complete program.
        uint required = semantic_total;
        if (required > gParams.semantic_capacity)
        {
            InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_SEMANTIC_CAPACITY);
            InterlockedMax(lowering_status[0u].required_capacity, required);
            InterlockedMin(lowering_status[0u].available_capacity, gParams.semantic_capacity);
        }
        opt_ir_total[0u] = total;
    }
    if (row >= total) return;

    OptIrNodeControl control;
    control.block_id = INVALID;
    control.region_id = INVALID;
    opt_ir_control[row] = control;

    OptIrNodeResults results;
    results.value_out = INVALID;
    results.effect_out = INVALID;
    opt_ir_results[row] = results;

    opt_ir_semantic_row[row] = row;
    opt_ir_source_hir[row] = semantic_owner_by_instruction[row];
}

uint function_for_node(uint node)
{
    uint source = semantic_owner_by_instruction[node];
    return source < gParams.hir_capacity
        ? semantic_function_id_by_hir[source] : INVALID;
}

bool starts_labeled_block(uint op)
{
    uint role = semantic_lir_control_role(op);
    return role == SEMANTIC_LIR_CONTROL_BLOCK_LABEL ||
        role == SEMANTIC_LIR_CONTROL_LOOP_HEADER ||
        role == SEMANTIC_LIR_CONTROL_MERGE_LABEL;
}

bool ends_block(uint op)
{
    return semantic_lir_op_has_flag(op, SEMANTIC_LIR_OP_FLAG_TERMINATOR);
}

public void mark_control_flow_blocks(uint position, uint total)
{
    uint node = semantic_schedule_order[position];
    if (node >= total) return;
    opt_ir_position_by_node[node] = position;

    uint op = opt_ir_op(opt_ir_core[node]);
    uint function_id = function_for_node(node);
    bool starts = position == 0u || starts_labeled_block(op);
    if (position != 0u)
    {
        uint previous = semantic_schedule_order[position - 1u];
        if (previous >= total)
            starts = true;
        else
            starts = starts || function_for_node(previous) != function_id ||
                ends_block(opt_ir_op(opt_ir_core[previous]));
    }
    opt_ir_block_start_flag[position] = starts ? 1u : 0u;
}

public void scatter_control_flow_blocks(uint position, uint total, uint block_total)
{
    if (position == 0u && block_total > gParams.block_capacity)
    {
        InterlockedOr(lowering_status[0u].flags,
            LOWERING_STATUS_OPTIMIZATION_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity, block_total);
        lowering_status[0u].available_capacity = gParams.block_capacity;
    }

    uint node = semantic_schedule_order[position];
    if (node >= total) return;
    uint start = opt_ir_block_start_flag[position];
    uint inclusive = opt_ir_block_prefix[position] + start;
    if (inclusive == 0u) return;
    uint block_id = inclusive - 1u;

    OptIrNodeControl control = opt_ir_control[node];
    control.block_id = block_id;
    opt_ir_control[node] = control;

    if (start == 0u || block_id >= gParams.block_capacity) return;
    uint source = opt_ir_source_hir[node];
    OptIrBlock block;
    block.function_id = source < gParams.hir_capacity
        ? semantic_function_id_by_hir[source] : INVALID;
    block.position_start = position;
    block.terminator = INVALID;
    block.edge_range = opt_ir_pack_block_edges(0u, 0u);
    opt_ir_blocks[block_id] = block;
}

bool is_terminator(uint op)
{
    return semantic_lir_op_has_flag(op, SEMANTIC_LIR_OP_FLAG_TERMINATOR);
}

public void finalize_control_flow_blocks(uint block_id, uint block_count, uint total)
{
    OptIrBlock block = opt_ir_blocks[block_id];
    uint end = block_id + 1u < block_count
        ? opt_ir_blocks[block_id + 1u].position_start : total;
    if (block.position_start >= end || end > total) return;
    uint node = semantic_schedule_order[end - 1u];
    if (node < total && is_terminator(opt_ir_op(opt_ir_core[node])))
        opt_ir_blocks[block_id].terminator = node;
}

public void mark_control_flow_edges(uint block_id, uint block_count)
{
    OptIrBlock block = opt_ir_blocks[block_id];
    bool has_fallthrough = block_id + 1u < block_count &&
        opt_ir_blocks[block_id + 1u].function_id == block.function_id;
    uint edge_count = has_fallthrough ? 1u : 0u;
    if (block.terminator != INVALID && block.terminator < gParams.semantic_capacity)
    {
        uint role = semantic_lir_control_role(opt_ir_op(opt_ir_core[block.terminator]));
        if (role == SEMANTIC_LIR_CONTROL_CONDITIONAL_BRANCH)
            edge_count = (has_fallthrough ? 1u : 0u) + 1u;
        else if (role == SEMANTIC_LIR_CONTROL_ELSE_BRANCH ||
                 role == SEMANTIC_LIR_CONTROL_BRANCH)
            edge_count = 1u;
        else if (role == SEMANTIC_LIR_CONTROL_RETURN)
            edge_count = 0u;
    }
    opt_ir_edge_count_by_block[block_id] = edge_count;
}

void report_structure_failure_in_edges(uint node)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_STRUCTURE_EDGE_SCATTER, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, node);
}

uint target_block(uint node, uint function_id, uint block_count)
{
    if (node >= gParams.semantic_capacity)
        return INVALID;
    uint block_id = opt_ir_control[node].block_id;
    if (block_id >= block_count || opt_ir_blocks[block_id].function_id != function_id)
        return INVALID;
    return block_id;
}

void write_edge(uint row, uint from_block, uint to_block, uint flags)
{
    if (row >= gParams.edge_capacity) return;
    OptIrEdge edge;
    edge.from_block = from_block;
    edge.packed_target = opt_ir_edge_target(to_block, flags);
    if (opt_ir_blocks[to_block].position_start <=
        opt_ir_blocks[from_block].position_start)
        edge.packed_target = opt_ir_edge_target(
            to_block,
            flags | OPT_IR_EDGE_BACK);
    opt_ir_edges[row] = edge;
}

public void scatter_control_flow_edges(uint block_id, uint block_count, uint edge_total)
{
    if (block_id == 0u && edge_total > gParams.edge_capacity)
    {
        InterlockedOr(lowering_status[0u].flags,
            LOWERING_STATUS_OPTIMIZATION_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity, edge_total);
        lowering_status[0u].available_capacity = gParams.edge_capacity;
    }
    // The program calls this for block 0 of a job without blocks, so that
    // the capacity check above runs. Such a job has no block row to read.
    if (block_id >= block_count) return;

    uint start = opt_ir_edge_prefix[block_id];
    uint expected = opt_ir_edge_count_by_block[block_id];
    OptIrBlock block = opt_ir_blocks[block_id];
    uint written = 0u;
    block.edge_range = opt_ir_pack_block_edges(start, written);
    if (start >= gParams.edge_capacity && expected != 0u)
    {
        opt_ir_blocks[block_id].edge_range = block.edge_range;
        return;
    }

    bool has_fallthrough = block_id + 1u < block_count &&
        opt_ir_blocks[block_id + 1u].function_id == block.function_id;
    if (block.terminator == INVALID)
    {
        if (has_fallthrough)
        {
            write_edge(start, block_id, block_id + 1u,
                OPT_IR_EDGE_FALLTHROUGH);
            written = 1u;
            block.edge_range = opt_ir_pack_block_edges(start, written);
        }
        opt_ir_blocks[block_id].edge_range = block.edge_range;
        return;
    }
    if (block.terminator >= gParams.semantic_capacity)
    {
        report_structure_failure_in_edges(block.terminator);
        opt_ir_blocks[block_id].edge_range = block.edge_range;
        return;
    }

    uint op = opt_ir_op(opt_ir_core[block.terminator]);
    uint role = semantic_lir_control_role(op);
    OptIrNodeOperands operands = opt_ir_operands[block.terminator];
    if (role == SEMANTIC_LIR_CONTROL_CONDITIONAL_BRANCH)
    {
        uint cursor = start;
        if (has_fallthrough)
        {
            write_edge(cursor++, block_id, block_id + 1u,
                OPT_IR_EDGE_FALLTHROUGH | OPT_IR_EDGE_CONDITIONAL);
            written++;
        }
        uint destination = INVALID;
        if (op == SEMANTIC_LIR_OP_IF_BEGIN && operands.c != 0u)
        {
            // The ELSE marker terminates the true arm and branches over the
            // false arm. Semantic row IDs are not schedule positions, so
            // `else_row + 1` names CONTROL_END rather than the first false-arm
            // instruction. The false edge instead enters the block scheduled
            // immediately after the ELSE marker. This is also CONTROL_END for
            // an empty false arm.
            uint else_block = target_block(operands.b, block.function_id, block_count);
            if (else_block != INVALID && else_block + 1u < block_count &&
                opt_ir_blocks[else_block + 1u].function_id == block.function_id)
                destination = else_block + 1u;
        }
        else
        {
            uint target_node = op == SEMANTIC_LIR_OP_IF_BEGIN
                ? operands.b : operands.c;
            destination = target_block(target_node, block.function_id, block_count);
        }
        if (destination == INVALID)
            report_structure_failure_in_edges(block.terminator);
        else
        {
            write_edge(cursor, block_id, destination,
                OPT_IR_EDGE_BRANCH | OPT_IR_EDGE_CONDITIONAL);
            written++;
        }
    }
    else if (role == SEMANTIC_LIR_CONTROL_ELSE_BRANCH ||
             role == SEMANTIC_LIR_CONTROL_BRANCH)
    {
        uint destination = target_block(operands.a, block.function_id, block_count);
        if (destination == INVALID)
            report_structure_failure_in_edges(block.terminator);
        else
        {
            write_edge(start, block_id, destination, OPT_IR_EDGE_BRANCH);
            written = 1u;
        }
    }
    else if (role != SEMANTIC_LIR_CONTROL_RETURN)
        report_structure_failure_in_edges(block.terminator);

    block.edge_range = opt_ir_pack_block_edges(start, written);
    if (written != expected)
        report_structure_failure_in_edges(block.terminator);
    opt_ir_blocks[block_id].edge_range = block.edge_range;
}

// Reuses the forward-edge count column as predecessor counts once successor
// ranges have been packed into OptIrBlock records.

public void clear_control_flow_predecessors(uint block_id)
{
    opt_ir_edge_count_by_block[block_id] = 0u;
}

// Counts incoming CFG edges for every dense basic block.

void report_structure_failure_in_predecessors(uint edge_id)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, edge_id);
}

public void count_control_flow_predecessors(uint edge_id)
{
    OptIrEdge edge = opt_ir_edges[edge_id];
    uint to_block = opt_ir_edge_to_block(edge.packed_target);
    if (edge.from_block >= gParams.block_capacity ||
        to_block >= gParams.block_capacity)
    {
        report_structure_failure_in_predecessors(edge_id);
        return;
    }
    InterlockedAdd(opt_ir_edge_count_by_block[to_block], 1u);
}

// Initializes per-block scatter cursors from the exclusive predecessor prefix.

public void prepare_control_flow_predecessor_ranges(uint block_id)
{
    opt_ir_predecessor_cursor[block_id] =
        opt_ir_edge_prefix[block_id];
}

// Scatters canonical CFG edge IDs into predecessor ranges.

void report_capacity_in_predecessors(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.edge_capacity;
}

public void scatter_control_flow_predecessors(uint edge_id)
{
    OptIrEdge edge = opt_ir_edges[edge_id];
    uint to_block = opt_ir_edge_to_block(edge.packed_target);
    if (to_block >= gParams.block_capacity) return;
    uint destination;
    InterlockedAdd(opt_ir_predecessor_cursor[to_block], 1u, destination);
    if (destination >= gParams.edge_capacity)
    {
        report_capacity_in_predecessors(destination + 1u);
        return;
    }
    opt_ir_predecessor_edge_ids[destination] = edge_id;
}

// Validates compact predecessor ranges against the canonical forward CFG.

public void validate_control_flow_predecessors(
    uint block_id, uint edge_count, uint predecessor_total)
{
    uint start = opt_ir_edge_prefix[block_id];
    uint count = opt_ir_edge_count_by_block[block_id];
    uint end = start + count;
    bool valid = predecessor_total == edge_count &&
        end >= start && end <= edge_count &&
        opt_ir_predecessor_cursor[block_id] == end;
    for (uint row = start; valid && row < end; ++row)
    {
        uint edge_id = opt_ir_predecessor_edge_ids[row];
        valid = edge_id < edge_count &&
            opt_ir_edge_to_block(opt_ir_edges[edge_id].packed_target) ==
                block_id;
    }
    if (!valid) report_structure_failure_in_predecessors(block_id);
}
