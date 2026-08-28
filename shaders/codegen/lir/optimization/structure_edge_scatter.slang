import codegen.lowering_ir;
import codegen.optimization_ir;
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
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<OptIrNodeControl> opt_ir_control;
StructuredBuffer<uint> opt_ir_edge_count_by_block;
StructuredBuffer<uint> opt_ir_edge_prefix;
StructuredBuffer<uint> opt_ir_edge_total;
RWStructuredBuffer<OptIrBlock> opt_ir_blocks;
RWStructuredBuffer<OptIrEdge> opt_ir_edges;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint node)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_STRUCTURE_EDGE_SCATTER, ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, node);
}

uint target_block(uint node, uint function_id)
{
    if (node >= gParams.semantic_capacity)
        return INVALID;
    uint block_id = opt_ir_control[node].block_id;
    uint block_total = min(gParams.block_capacity, opt_ir_block_total[0u]);
    if (block_id >= block_total || opt_ir_blocks[block_id].function_id != function_id)
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint block_id = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint block_total = min(gParams.block_capacity, opt_ir_block_total[0u]);
    uint edge_total = opt_ir_edge_total[0u];
    if (block_id == 0u && edge_total > gParams.edge_capacity)
    {
        InterlockedOr(lowering_status[0u].flags,
            LOWERING_STATUS_OPTIMIZATION_CAPACITY);
        InterlockedMax(lowering_status[0u].required_capacity, edge_total);
        lowering_status[0u].available_capacity = gParams.edge_capacity;
    }
    if (block_id >= block_total) return;

    uint start = opt_ir_edge_prefix[block_id];
    uint expected = opt_ir_edge_count_by_block[block_id];
    OptIrBlock block = opt_ir_blocks[block_id];
    uint written = 0u;
    block.edge_range = opt_ir_pack_block_edges(start, written);
    if (start >= gParams.edge_capacity && expected != 0u)
    {
        opt_ir_blocks[block_id] = block;
        return;
    }

    bool has_fallthrough = block_id + 1u < block_total &&
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
        opt_ir_blocks[block_id] = block;
        return;
    }
    if (block.terminator >= gParams.semantic_capacity)
    {
        report_structure_failure(block.terminator);
        opt_ir_blocks[block_id] = block;
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
            uint else_block = target_block(operands.b, block.function_id);
            if (else_block != INVALID && else_block + 1u < block_total &&
                opt_ir_blocks[else_block + 1u].function_id == block.function_id)
                destination = else_block + 1u;
        }
        else
        {
            uint target_node = op == SEMANTIC_LIR_OP_IF_BEGIN
                ? operands.b : operands.c;
            destination = target_block(target_node, block.function_id);
        }
        if (destination == INVALID)
            report_structure_failure(block.terminator);
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
        uint destination = target_block(operands.a, block.function_id);
        if (destination == INVALID)
            report_structure_failure(block.terminator);
        else
        {
            write_edge(start, block_id, destination, OPT_IR_EDGE_BRANCH);
            written = 1u;
        }
    }
    else if (role != SEMANTIC_LIR_CONTROL_RETURN)
        report_structure_failure(block.terminator);

    block.edge_range = opt_ir_pack_block_edges(start, written);
    if (written != expected)
        report_structure_failure(block.terminator);
    opt_ir_blocks[block_id] = block;
}
