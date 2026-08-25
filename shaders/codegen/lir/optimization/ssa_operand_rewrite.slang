// Projects every ordinary and variable-arity value edge into the canonical
// dense SSA value domain. The original semantic operands remain readable until
// the two target stages are cut over; this construction relation is temporary
// and is independently checked by the following pass.

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
    uint reserved0;
    uint reserved1;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<OptIrNodeResults> opt_ir_results;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> opt_ir_ssa_value_total;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_start_by_hir;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement>
    semantic_lir_aggregate_elements;
RWStructuredBuffer<OptIrNodeOperands> opt_ir_ssa_operands;
RWStructuredBuffer<uint> opt_ir_ssa_call_argument_values;
RWStructuredBuffer<uint> opt_ir_ssa_aggregate_element_values;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint node)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_OPERAND_REWRITE,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, node);
}

uint value_for_node(uint node, uint node_total, uint value_total,
    inout bool valid)
{
    if (node >= node_total)
    {
        valid = false;
        return INVALID;
    }
    uint value = opt_ir_results[node].value_out;
    if (value >= value_total) valid = false;
    return value;
}

uint rewritten_operand(OptIrNodeCore core, OptIrNodeOperands operands,
    uint ordinal, uint node_total, uint value_total, inout bool valid)
{
    uint operand = opt_ir_operand(operands, ordinal);
    return opt_ir_operand_is_value(core, ordinal)
        ? value_for_node(operand, node_total, value_total, valid)
        : operand;
}

bool active_call_argument(uint row, SemanticLirCallArg argument,
    uint node_total)
{
    if (argument.call_instruction >= node_total) return false;
    uint hir = opt_ir_source_hir[argument.call_instruction];
    if (hir >= gParams.hir_capacity) return false;
    uint start = semantic_lir_call_arg_start_by_hir[hir];
    uint count = semantic_lir_call_arg_count_by_hir[hir];
    return row >= start && row - start < count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint node_total = min(opt_ir_total[0u], gParams.semantic_capacity);
    uint value_total = min(opt_ir_ssa_value_total[0u],
        gParams.value_capacity);

    if (row < gParams.semantic_capacity)
    {
        OptIrNodeOperands rewritten;
        rewritten.result = INVALID;
        rewritten.a = INVALID;
        rewritten.b = INVALID;
        rewritten.c = INVALID;
        if (row < node_total)
        {
            bool valid = true;
            OptIrNodeCore core = opt_ir_core[row];
            OptIrNodeOperands operands = opt_ir_operands[row];
            uint result = opt_ir_results[row].value_out;
            rewritten.result = result < value_total ? result : INVALID;
            rewritten.a = rewritten_operand(core, operands, 0u,
                node_total, value_total, valid);
            rewritten.b = rewritten_operand(core, operands, 1u,
                node_total, value_total, valid);
            rewritten.c = rewritten_operand(core, operands, 2u,
                node_total, value_total, valid);
            if (!valid) report_structure_failure(row);
        }
        opt_ir_ssa_operands[row] = rewritten;
    }

    if (row < gParams.call_argument_capacity)
    {
        uint value = INVALID;
        SemanticLirCallArg argument = semantic_lir_call_args[row];
        if (active_call_argument(row, argument, node_total))
        {
            bool valid = true;
            value = value_for_node(argument.value_instruction,
                node_total, value_total, valid);
            if (!valid) report_structure_failure(argument.call_instruction);
        }
        opt_ir_ssa_call_argument_values[row] = value;
    }

    if (row < gParams.aggregate_element_capacity)
    {
        uint aggregate_total = min(
            semantic_lir_aggregate_element_total[0u],
            gParams.aggregate_element_capacity);
        uint value = INVALID;
        if (row < aggregate_total)
        {
            SemanticLirAggregateElement element =
                semantic_lir_aggregate_elements[row];
            bool active = element.aggregate_instruction < node_total &&
                element.value_instruction < node_total;
            if (active)
            {
                bool valid = true;
                value = value_for_node(element.value_instruction,
                    node_total, value_total, valid);
                if (!valid)
                    report_structure_failure(element.aggregate_instruction);
            }
        }
        opt_ir_ssa_aggregate_element_values[row] = value;
    }
}
