// Independently checks that the rewritten fixed and variable-arity operand
// relations are the exact dense-value projection of the semantic inputs.

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
StructuredBuffer<OptIrNodeOperands> opt_ir_ssa_operands;
StructuredBuffer<uint> opt_ir_ssa_call_argument_values;
StructuredBuffer<uint> opt_ir_ssa_aggregate_element_values;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint node)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_OPERAND_VALIDATE,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, node);
}

uint expected_value(uint node, uint node_total, uint value_total)
{
    return node < node_total && opt_ir_results[node].value_out < value_total
        ? opt_ir_results[node].value_out : INVALID;
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

    if (row < node_total)
    {
        OptIrNodeCore core = opt_ir_core[row];
        OptIrNodeOperands source = opt_ir_operands[row];
        OptIrNodeOperands rewritten = opt_ir_ssa_operands[row];
        bool valid = rewritten.result == expected_value(
            row, node_total, value_total);
        for (uint ordinal = 0u; ordinal < 3u; ++ordinal)
        {
            uint original = opt_ir_operand(source, ordinal);
            uint expected = opt_ir_operand_is_value(core, ordinal)
                ? expected_value(original, node_total, value_total)
                : original;
            valid = valid && opt_ir_operand(rewritten, ordinal) == expected;
        }
        if (!valid) report_structure_failure(row);
    }

    if (row < gParams.call_argument_capacity)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[row];
        if (active_call_argument(row, argument, node_total))
        {
            uint expected = expected_value(argument.value_instruction,
                node_total, value_total);
            if (expected == INVALID ||
                opt_ir_ssa_call_argument_values[row] != expected)
                report_structure_failure(argument.call_instruction);
        }
    }

    uint aggregate_total = min(
        semantic_lir_aggregate_element_total[0u],
        gParams.aggregate_element_capacity);
    if (row < aggregate_total)
    {
        SemanticLirAggregateElement element =
            semantic_lir_aggregate_elements[row];
        bool active = element.aggregate_instruction < node_total &&
            element.value_instruction < node_total;
        uint expected = active
            ? expected_value(element.value_instruction,
                node_total, value_total)
            : INVALID;
        if ((expected == INVALID && active) ||
            opt_ir_ssa_aggregate_element_values[row] != expected)
            report_structure_failure(active
                ? element.aggregate_instruction : row);
    }
}
