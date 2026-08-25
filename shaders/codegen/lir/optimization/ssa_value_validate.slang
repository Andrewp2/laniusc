// Independently validates the dense value bijection and each category's
// prefix-derived assignment.

import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint parameter_capacity;
    uint block_argument_capacity;
    uint value_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_param_total;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeResults> opt_ir_results;
StructuredBuffer<uint> opt_ir_ssa_block_argument_total;
StructuredBuffer<uint> opt_ir_ssa_block_argument_replacement;
StructuredBuffer<uint> opt_ir_ssa_node_value_flag;
StructuredBuffer<uint> opt_ir_ssa_node_value_total;
StructuredBuffer<uint> opt_ir_ssa_block_argument_value_flag;
StructuredBuffer<uint> opt_ir_ssa_surviving_block_argument_total;
StructuredBuffer<uint> opt_ir_ssa_value_total;
StructuredBuffer<OptIrValueDefinition> opt_ir_ssa_value_definitions;
StructuredBuffer<uint> opt_ir_ssa_value_by_block_argument;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_VALUE_VALIDATE,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

bool valid_definition(uint value, uint parameter_total, uint node_total,
    uint argument_total)
{
    OptIrValueDefinition definition = opt_ir_ssa_value_definitions[value];
    uint kind = opt_ir_value_definition_kind(definition);
    uint payload = opt_ir_value_definition_payload(definition);
    if (kind == OPT_IR_VALUE_DEFINITION_PARAMETER)
        return payload < parameter_total && value == payload;
    if (kind == OPT_IR_VALUE_DEFINITION_NODE)
        return payload < node_total &&
            opt_ir_results[payload].value_out == value;
    if (kind == OPT_IR_VALUE_DEFINITION_BLOCK_ARGUMENT)
        return payload < argument_total &&
            opt_ir_ssa_value_by_block_argument[payload] == value;
    return false;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint parameter_total = min(semantic_param_total[0u],
        gParams.parameter_capacity);
    uint node_total = min(opt_ir_total[0u], gParams.semantic_capacity);
    uint node_value_total = opt_ir_ssa_node_value_total[0u];
    uint argument_total = min(opt_ir_ssa_block_argument_total[0u],
        gParams.block_argument_capacity);
    uint surviving_argument_total =
        opt_ir_ssa_surviving_block_argument_total[0u];
    uint value_total = opt_ir_ssa_value_total[0u];
    bool valid = value_total == parameter_total + node_value_total +
        surviving_argument_total && value_total <= gParams.value_capacity;

    if (row < node_total)
    {
        uint prefix = opt_ir_ssa_node_value_flag[row];
        uint end = row + 1u < node_total
            ? opt_ir_ssa_node_value_flag[row + 1u]
            : node_value_total;
        uint op = opt_ir_op(opt_ir_core[row]);
        bool owns_definition = semantic_lir_produces_value(op) &&
            op != SEMANTIC_LIR_OP_VALUE_GET;
        valid = valid && prefix <= end && end - prefix <= 1u &&
            owns_definition == (end != prefix);
        uint expected = owns_definition ? parameter_total + prefix : INVALID;
        valid = valid && opt_ir_results[row].value_out == expected;
    }

    if (row < argument_total)
    {
        uint prefix = opt_ir_ssa_block_argument_value_flag[row];
        uint end = row + 1u < argument_total
            ? opt_ir_ssa_block_argument_value_flag[row + 1u]
            : surviving_argument_total;
        OptIrSsaValueRef replacement = opt_ir_unpack_ssa_source(
            opt_ir_ssa_block_argument_replacement[row]);
        bool survives = replacement.kind ==
                OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
            replacement.payload == row;
        valid = valid && prefix <= end && end - prefix <= 1u &&
            survives == (end != prefix);
        uint expected = survives
            ? parameter_total + node_value_total + prefix
            : INVALID;
        valid = valid &&
            opt_ir_ssa_value_by_block_argument[row] == expected;
    }

    if (row < value_total)
        valid = valid && valid_definition(row, parameter_total,
            node_total, argument_total);

    if (!valid) report_structure_failure(row);
}
