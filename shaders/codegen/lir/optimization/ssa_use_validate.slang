// Independently reconstructs every compact value-use row from the canonical
// operand and side-table relations.

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
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> opt_ir_ssa_node_use_prefix;
StructuredBuffer<uint> opt_ir_ssa_node_use_total;
StructuredBuffer<uint> opt_ir_ssa_value_total;
StructuredBuffer<uint> semantic_lir_call_arg_total;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_start_by_hir;
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
StructuredBuffer<uint> opt_ir_ssa_use_total;
StructuredBuffer<uint> opt_ir_ssa_use_values;
StructuredBuffer<uint> opt_ir_ssa_use_users;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_USE_VALIDATE,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

bool matches_use(uint destination, uint value, uint user, uint total)
{
    return destination < total &&
        opt_ir_ssa_use_values[destination] == value &&
        opt_ir_ssa_use_users[destination] == user;
}

bool active_call_argument(uint row, SemanticLirCallArg argument,
    uint node_total)
{
    if (argument.call_instruction >= node_total ||
        !semantic_lir_is_call(opt_ir_op(
            opt_ir_core[argument.call_instruction])))
        return false;
    uint hir = opt_ir_source_hir[argument.call_instruction];
    if (hir >= gParams.hir_capacity) return false;
    uint start = semantic_lir_call_arg_start_by_hir[hir];
    uint count = semantic_lir_call_arg_count_by_hir[hir];
    return row >= start && row - start < count;
}

bool active_aggregate_element(SemanticLirAggregateElement element,
    uint node_total)
{
    return element.aggregate_instruction < node_total &&
        element.value_instruction < node_total;
}

uint checked_add(uint left, uint right, inout bool valid)
{
    uint result = left + right;
    if (result < left) valid = false;
    return result;
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
    bool valid_total = true;
    uint call_base = fixed_total;
    uint aggregate_base = checked_add(call_base, call_total, valid_total);
    uint incoming_base = checked_add(aggregate_base, aggregate_total,
        valid_total);
    uint expected_total = checked_add(incoming_base, incoming_total,
        valid_total);
    uint total = min(opt_ir_ssa_use_total[0u], gParams.use_capacity);
    if (row == 0u && (!valid_total || total != expected_total))
        report_structure_failure(0u);

    if (row < node_total)
    {
        OptIrNodeCore core = opt_ir_core[row];
        OptIrNodeOperands operands = opt_ir_ssa_operands[row];
        uint start = opt_ir_ssa_node_use_prefix[row];
        uint end = row + 1u < node_total
            ? opt_ir_ssa_node_use_prefix[row + 1u] : fixed_total;
        uint expected = 0u;
        bool valid = start <= end && end <= fixed_total;
        if (!opt_ir_is_declaration_state_node(core))
        {
            for (uint ordinal = 0u; ordinal < 3u; ++ordinal)
            {
                if (!opt_ir_operand_is_value(core, ordinal)) continue;
                valid = valid && matches_use(start + expected,
                    opt_ir_operand(operands, ordinal),
                    opt_ir_pack_fixed_use(row, ordinal), total);
                expected += 1u;
            }
        }
        valid = valid && end - start == expected;
        if (!valid) report_structure_failure(row);
    }

    if (row < call_candidate_total)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[row];
        uint start = opt_ir_ssa_call_use_prefix[row];
        uint end = row + 1u < call_candidate_total
            ? opt_ir_ssa_call_use_prefix[row + 1u] : call_total;
        bool expected_active = active_call_argument(row, argument,
            node_total);
        bool valid = start <= end && end <= call_total &&
            end - start == (expected_active ? 1u : 0u);
        if (expected_active)
            valid = valid && matches_use(call_base + start,
                opt_ir_ssa_call_argument_values[row],
                opt_ir_pack_side_use(OPT_IR_USE_CALL_ARGUMENT, row), total);
        if (!valid)
            report_structure_failure(argument.call_instruction);
    }

    if (row < aggregate_candidate_total)
    {
        SemanticLirAggregateElement element =
            semantic_lir_aggregate_elements[row];
        uint start = opt_ir_ssa_aggregate_use_prefix[row];
        uint end = row + 1u < aggregate_candidate_total
            ? opt_ir_ssa_aggregate_use_prefix[row + 1u]
            : aggregate_total;
        bool expected_active = active_aggregate_element(element,
            node_total);
        bool valid = start <= end && end <= aggregate_total &&
            end - start == (expected_active ? 1u : 0u);
        if (expected_active)
            valid = valid && matches_use(aggregate_base + start,
                opt_ir_ssa_aggregate_element_values[row],
                opt_ir_pack_side_use(
                    OPT_IR_USE_AGGREGATE_ELEMENT, row), total);
        if (!valid)
            report_structure_failure(element.aggregate_instruction);
    }

    if (row < incoming_total && !matches_use(incoming_base + row,
        opt_ir_ssa_incoming_values[row].value,
        opt_ir_pack_side_use(
            OPT_IR_USE_BLOCK_ARGUMENT_INCOMING, row), total))
        report_structure_failure(row);
}
