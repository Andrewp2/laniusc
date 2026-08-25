// Concatenates fixed operands and the three already-compact variable-arity
// relations into one deterministic value-use relation.

import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint parameter_capacity;
    uint block_argument_capacity;
    uint value_capacity;
    uint call_argument_capacity;
    uint aggregate_element_capacity;
    uint block_capacity;
    uint access_capacity;
    uint incoming_capacity;
    uint hir_capacity;
    uint use_capacity;
    uint reserved1;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_ssa_operands;
StructuredBuffer<uint> opt_ir_ssa_node_use_prefix;
StructuredBuffer<uint> opt_ir_ssa_node_use_total;
StructuredBuffer<uint> opt_ir_ssa_value_total;
StructuredBuffer<uint> semantic_lir_call_arg_total;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> opt_ir_ssa_call_argument_values;
StructuredBuffer<uint> opt_ir_ssa_call_use_prefix;
StructuredBuffer<uint> opt_ir_ssa_call_use_total;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement>
    semantic_lir_aggregate_elements;
StructuredBuffer<uint> opt_ir_ssa_aggregate_element_values;
StructuredBuffer<uint> opt_ir_ssa_aggregate_use_prefix;
StructuredBuffer<uint> opt_ir_ssa_aggregate_use_total;
StructuredBuffer<uint> opt_ir_ssa_block_argument_incoming_total;
StructuredBuffer<OptIrIncomingValue> opt_ir_ssa_incoming_values;
RWStructuredBuffer<uint> opt_ir_ssa_use_total;
RWStructuredBuffer<uint> opt_ir_ssa_use_values;
RWStructuredBuffer<uint> opt_ir_ssa_use_users;
RWStructuredBuffer<uint> opt_ir_ssa_use_radix_dispatch_args;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WORKGROUP_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

void report_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.use_capacity;
}

void report_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_USE_COMPACTION,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

uint checked_add(uint left, uint right, inout bool valid)
{
    uint result = left + right;
    if (result < left) valid = false;
    return result;
}

void write_use(uint destination, uint value, uint user,
    uint value_total, uint diagnostic_row)
{
    if (destination >= gParams.use_capacity || value >= value_total)
    {
        report_structure_failure(diagnostic_row);
        return;
    }
    opt_ir_ssa_use_values[destination] = value;
    opt_ir_ssa_use_users[destination] = user;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint node_total = min(opt_ir_total[0u], gParams.semantic_capacity);
    uint fixed_total = opt_ir_ssa_node_use_total[0u];
    uint call_candidate_total = min(semantic_lir_call_arg_total[0u],
        gParams.call_argument_capacity);
    uint call_total = min(opt_ir_ssa_call_use_total[0u],
        call_candidate_total);
    uint aggregate_candidate_total = min(
        semantic_lir_aggregate_element_total[0u],
        gParams.aggregate_element_capacity);
    uint aggregate_total = min(opt_ir_ssa_aggregate_use_total[0u],
        aggregate_candidate_total);
    uint incoming_total = min(
        opt_ir_ssa_block_argument_incoming_total[0u],
        gParams.incoming_capacity);
    uint value_total = min(opt_ir_ssa_value_total[0u],
        gParams.value_capacity);

    bool valid = gParams.semantic_capacity <=
        OPT_IR_USE_FIXED_NODE_MASK + 1u &&
        gParams.call_argument_capacity <= OPT_IR_USE_ROW_MASK + 1u &&
        gParams.aggregate_element_capacity <= OPT_IR_USE_ROW_MASK + 1u &&
        gParams.incoming_capacity <= OPT_IR_USE_ROW_MASK + 1u;
    uint call_base = fixed_total;
    uint aggregate_base = checked_add(call_base, call_total, valid);
    uint incoming_base = checked_add(aggregate_base, aggregate_total, valid);
    uint total = checked_add(incoming_base, incoming_total, valid);
    valid = valid && total <= gParams.use_capacity;
    if (row == 0u)
    {
        opt_ir_ssa_use_total[0u] = valid ? total :
            min(total, gParams.use_capacity);
        uint blocks = max(1u,
            (min(total, gParams.use_capacity) + WORKGROUP_SIZE - 1u) /
                WORKGROUP_SIZE);
        opt_ir_ssa_use_radix_dispatch_args[0u] =
            min(blocks, MAX_GROUPS_X);
        opt_ir_ssa_use_radix_dispatch_args[1u] = max(1u,
            (blocks + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
        opt_ir_ssa_use_radix_dispatch_args[2u] = 1u;
        if (!valid) report_capacity(total);
    }
    if (!valid) return;

    if (row < node_total)
    {
        OptIrNodeCore core = opt_ir_core[row];
        OptIrNodeOperands operands = opt_ir_ssa_operands[row];
        uint destination = opt_ir_ssa_node_use_prefix[row];
        if (!opt_ir_is_declaration_state_node(core))
        {
            uint rank = 0u;
            for (uint ordinal = 0u; ordinal < 3u; ++ordinal)
            {
                if (!opt_ir_operand_is_value(core, ordinal)) continue;
                write_use(destination + rank,
                    opt_ir_operand(operands, ordinal),
                    opt_ir_pack_fixed_use(row, ordinal),
                    value_total, row);
                rank += 1u;
            }
        }
    }

    if (row < call_candidate_total)
    {
        uint start = opt_ir_ssa_call_use_prefix[row];
        uint end = row + 1u < call_candidate_total
            ? opt_ir_ssa_call_use_prefix[row + 1u] : call_total;
        if (start > end || end > call_total || end - start > 1u)
        {
            report_structure_failure(
                semantic_lir_call_args[row].call_instruction);
        }
        else if (end != start)
        {
            SemanticLirCallArg argument = semantic_lir_call_args[row];
            write_use(call_base + start,
                opt_ir_ssa_call_argument_values[row],
                opt_ir_pack_side_use(OPT_IR_USE_CALL_ARGUMENT, row),
                value_total, argument.call_instruction);
        }
    }

    if (row < aggregate_candidate_total)
    {
        uint start = opt_ir_ssa_aggregate_use_prefix[row];
        uint end = row + 1u < aggregate_candidate_total
            ? opt_ir_ssa_aggregate_use_prefix[row + 1u]
            : aggregate_total;
        if (start > end || end > aggregate_total || end - start > 1u)
        {
            report_structure_failure(
                semantic_lir_aggregate_elements[row].aggregate_instruction);
        }
        else if (end != start)
        {
            SemanticLirAggregateElement element =
                semantic_lir_aggregate_elements[row];
            write_use(aggregate_base + start,
                opt_ir_ssa_aggregate_element_values[row],
                opt_ir_pack_side_use(OPT_IR_USE_AGGREGATE_ELEMENT, row),
                value_total, element.aggregate_instruction);
        }
    }

    if (row < incoming_total)
    {
        OptIrIncomingValue incoming = opt_ir_ssa_incoming_values[row];
        write_use(incoming_base + row, incoming.value,
            opt_ir_pack_side_use(
                OPT_IR_USE_BLOCK_ARGUMENT_INCOMING, row),
            value_total, row);
    }
}
