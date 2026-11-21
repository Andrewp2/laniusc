// Gathers each scheduled position's allocation inputs for the serial walks of
// allocate_x86_registers_and_spill_words.slang. One invocation per position computes the row's function,
// opcode classes, register-independent location, last use, store home and
// spill width: pure functions of the row, so a walk reads them from one
// record instead of chasing dependent table loads at every step.

#include "native_register_allocator.slang"

RWStructuredBuffer<X86AllocationPrepared> x86_allocation_prepared;
RWStructuredBuffer<uint2> x86_allocation_boundary_masks;
groupshared uint call_masks[8];
groupshared uint label_masks[8];

uint prepare_position(uint position, uint total)
{
    uint function_total = min(gParams.function_capacity,
        semantic_lir_function_total[0u]);
    X86AllocationPrepared prepared;
    prepared.row = semantic_schedule_order[position];
    prepared.function_id = INVALID;
    prepared.flags = 0u;
    prepared.location = INVALID;
    prepared.last = 0u;
    prepared.home = INVALID;
    prepared.words = 0u;
    prepared.operand = INVALID;
    uint row = prepared.row;
    if (row < total)
    {
        prepared.function_id = function_for_node(row);
        uint op = opt_ir_op(opt_ir_core[row]);
        OptIrNodeOperands operands = opt_ir_operands[row];
        if (control_label(op)) prepared.flags |= PREPARED_CONTROL_LABEL;
        if (semantic_lir_is_call(op)) prepared.flags |= PREPARED_CALL;
        if (op == SEMANTIC_LIR_OP_VALUE_GET || op == SEMANTIC_LIR_OP_ADDRESS)
        {
            prepared.flags |= PREPARED_READS_DECLARATION;
            prepared.operand = operands.a;
        }
        else
        {
            uint target = branch_target(op, operands);
            prepared.operand = target;
            if (target < total && function_for_node(target) == prepared.function_id &&
                control_label(opt_ir_op(opt_ir_core[target])))
                prepared.flags |= PREPARED_TARGET_LABEL;
        }
        if (x86_live_by_semantic[row] != 0u)
        {
            prepared.flags |= PREPARED_LIVE;
            bool gpr;
            bool argument;
            prepared.location = parallel_register_location(row, position, total, gpr, argument);
            if (gpr) prepared.flags |= PREPARED_GPR;
            if (argument) prepared.flags |= PREPARED_ARGUMENT;
            uint last = x86_last_use_by_semantic[row];
            prepared.last = last;
            if (in_place_read(row, op, false)) prepared.flags |= PREPARED_IN_PLACE;
            if (in_place_read(row, op, true)) prepared.flags |= PREPARED_IN_PLACE_ACROSS;
            prepared.home = store_home(row, op, position, last, total);
            prepared.words = spill_word_count(row, total, function_total);
        }
    }
    x86_allocation_prepared[position] = prepared;
    x86_stack_words_by_position[position] = INVALID;
    return prepared.flags;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID, uint lane: SV_GroupIndex)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    uint group_start = position - lane;
    if (group_start >= total) return;
    if (lane < 8u)
    {
        call_masks[lane] = 0u;
        label_masks[lane] = 0u;
    }
    GroupMemoryBarrierWithGroupSync();
    if (position < total)
    {
        uint flags = prepare_position(position, total);
        uint bit = 1u << (lane & 31u);
        if ((flags & PREPARED_CALL) != 0u) InterlockedOr(call_masks[lane >> 5u], bit);
        if ((flags & PREPARED_CONTROL_LABEL) != 0u) InterlockedOr(label_masks[lane >> 5u], bit);
    }
    GroupMemoryBarrierWithGroupSync();
    if (lane < 8u && group_start + lane * 32u < total)
        x86_allocation_boundary_masks[(group_start >> 5u) + lane] =
            uint2(call_masks[lane], label_masks[lane]);
}
