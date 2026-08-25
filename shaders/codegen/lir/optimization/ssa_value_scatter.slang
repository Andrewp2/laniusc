// Assigns one deterministic dense ID to every canonical SSA definition.

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
StructuredBuffer<uint> opt_ir_ssa_block_argument_total;
StructuredBuffer<uint> opt_ir_ssa_node_value_flag;
StructuredBuffer<uint> opt_ir_ssa_node_value_total;
StructuredBuffer<uint> opt_ir_ssa_block_argument_value_flag;
StructuredBuffer<uint> opt_ir_ssa_surviving_block_argument_total;
RWStructuredBuffer<OptIrNodeResults> opt_ir_results;
RWStructuredBuffer<uint> opt_ir_ssa_value_total;
RWStructuredBuffer<OptIrValueDefinition> opt_ir_ssa_value_definitions;
RWStructuredBuffer<uint> opt_ir_ssa_value_by_block_argument;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_capacity(uint required)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_CAPACITY);
    InterlockedMax(lowering_status[0u].required_capacity, required);
    lowering_status[0u].available_capacity = gParams.value_capacity;
}

void report_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_VALUE_SCATTER,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

uint checked_total(uint parameters, uint nodes, uint arguments)
{
    uint first = parameters + nodes;
    if (first < parameters) return INVALID;
    uint total = first + arguments;
    return total < first ? INVALID : total;
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
    uint value_total = checked_total(parameter_total, node_value_total,
        surviving_argument_total);
    if (row == 0u)
    {
        if (value_total == INVALID || value_total > gParams.value_capacity)
            report_capacity(value_total);
        opt_ir_ssa_value_total[0u] = min(value_total,
            gParams.value_capacity);
    }

    if (row < parameter_total && row < gParams.value_capacity)
    {
        OptIrValueDefinition definition;
        definition.source = opt_ir_pack_value_definition(
            OPT_IR_VALUE_DEFINITION_PARAMETER, row);
        opt_ir_ssa_value_definitions[row] = definition;
    }

    if (row < node_total)
    {
        uint prefix = opt_ir_ssa_node_value_flag[row];
        uint end = row + 1u < node_total
            ? opt_ir_ssa_node_value_flag[row + 1u]
            : node_value_total;
        uint op = opt_ir_op(opt_ir_core[row]);
        bool expected = semantic_lir_produces_value(op) &&
            op != SEMANTIC_LIR_OP_VALUE_GET;
        bool valid = prefix <= end && end <= node_value_total &&
            end - prefix <= 1u && expected == (end != prefix);
        OptIrNodeResults result = opt_ir_results[row];
        result.value_out = INVALID;
        if (valid && expected)
        {
            uint value = parameter_total + prefix;
            valid = value >= parameter_total && value < value_total &&
                value < gParams.value_capacity;
            if (valid)
            {
                result.value_out = value;
                OptIrValueDefinition definition;
                definition.source = opt_ir_pack_value_definition(
                    OPT_IR_VALUE_DEFINITION_NODE, row);
                opt_ir_ssa_value_definitions[value] = definition;
            }
        }
        opt_ir_results[row] = result;
        if (!valid) report_structure_failure(row);
    }

    if (row < argument_total)
    {
        uint prefix = opt_ir_ssa_block_argument_value_flag[row];
        uint end = row + 1u < argument_total
            ? opt_ir_ssa_block_argument_value_flag[row + 1u]
            : surviving_argument_total;
        bool valid = prefix <= end && end <= surviving_argument_total &&
            end - prefix <= 1u;
        uint value = INVALID;
        if (valid && end != prefix)
        {
            uint base = parameter_total + node_value_total;
            value = base + prefix;
            valid = base >= parameter_total && value >= base &&
                value < value_total && value < gParams.value_capacity;
            if (valid)
            {
                OptIrValueDefinition definition;
                definition.source = opt_ir_pack_value_definition(
                    OPT_IR_VALUE_DEFINITION_BLOCK_ARGUMENT, row);
                opt_ir_ssa_value_definitions[value] = definition;
            }
        }
        opt_ir_ssa_value_by_block_argument[row] = value;
        if (!valid) report_structure_failure(row);
    }
}
