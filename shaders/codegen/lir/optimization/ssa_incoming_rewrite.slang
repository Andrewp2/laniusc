// Replaces construction-only packed reaching-definition sources with the
// canonical dense values carried by each block-argument edge.

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
StructuredBuffer<uint> semantic_param_total;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<OptIrNodeResults> opt_ir_results;
StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<uint> opt_ir_access_source_rows;
StructuredBuffer<uint> opt_ir_access_kinds;
StructuredBuffer<uint> opt_ir_ssa_block_argument_total;
StructuredBuffer<uint> opt_ir_ssa_block_argument_replacement;
StructuredBuffer<uint> opt_ir_ssa_block_argument_incoming_total;
StructuredBuffer<OptIrBlockArgumentIncoming>
    opt_ir_ssa_block_argument_incoming;
StructuredBuffer<uint> opt_ir_ssa_value_total;
StructuredBuffer<uint> opt_ir_ssa_value_by_block_argument;
RWStructuredBuffer<OptIrIncomingValue> opt_ir_ssa_incoming_values;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_INCOMING_REWRITE,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

uint declaration_write_value_node(uint node, uint node_total)
{
    if (node >= node_total) return INVALID;
    OptIrNodeCore core = opt_ir_core[node];
    OptIrNodeOperands operands = opt_ir_operands[node];
    uint found = INVALID;
    uint count = 0u;
    for (uint ordinal = 0u; ordinal < 3u; ++ordinal)
    {
        if (!opt_ir_operand_is_value(core, ordinal)) continue;
        found = opt_ir_operand(operands, ordinal);
        count += 1u;
    }
    return count == 1u ? found : INVALID;
}

uint local_definition_value(uint access_id, uint access_total,
    uint node_total, uint parameter_total, uint value_total)
{
    if (access_id >= access_total) return INVALID;
    uint kind = opt_ir_access_kinds[access_id];
    uint source = opt_ir_access_source_rows[access_id];
    if (kind == OPT_IR_ACCESS_PARAMETER_DEFINITION)
        return source < parameter_total && source < value_total
            ? source : INVALID;
    if (kind != OPT_IR_ACCESS_DECLARATION_WRITE) return INVALID;
    uint value_node = declaration_write_value_node(source, node_total);
    if (value_node >= node_total) return INVALID;
    uint value = opt_ir_results[value_node].value_out;
    return value < value_total ? value : INVALID;
}

uint source_value(OptIrSsaValueRef source, uint access_total,
    uint node_total, uint parameter_total, uint argument_total,
    uint value_total)
{
    if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
    {
        if (source.payload >= argument_total) return INVALID;
        source = opt_ir_unpack_ssa_source(
            opt_ir_ssa_block_argument_replacement[source.payload]);
    }
    if (source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION)
        return local_definition_value(source.payload, access_total,
            node_total, parameter_total, value_total);
    if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
    {
        uint value = source.payload < argument_total
            ? opt_ir_ssa_value_by_block_argument[source.payload]
            : INVALID;
        return value < value_total ? value : INVALID;
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= gParams.incoming_capacity) return;

    OptIrIncomingValue rewritten;
    rewritten.predecessor = INVALID;
    rewritten.value = INVALID;
    uint incoming_total = min(
        opt_ir_ssa_block_argument_incoming_total[0u],
        gParams.incoming_capacity);
    if (row < incoming_total)
    {
        uint node_total = min(opt_ir_total[0u],
            gParams.semantic_capacity);
        uint parameter_total = min(semantic_param_total[0u],
            gParams.parameter_capacity);
        uint argument_total = min(opt_ir_ssa_block_argument_total[0u],
            gParams.block_argument_capacity);
        uint access_total = min(opt_ir_access_total[0u],
            gParams.access_capacity);
        uint value_total = min(opt_ir_ssa_value_total[0u],
            gParams.value_capacity);
        OptIrBlockArgumentIncoming incoming =
            opt_ir_ssa_block_argument_incoming[row];
        rewritten.predecessor = incoming.predecessor;
        rewritten.value = source_value(
            opt_ir_unpack_ssa_source(incoming.source),
            access_total, node_total, parameter_total, argument_total,
            value_total);
        if (rewritten.predecessor >= gParams.block_capacity ||
            rewritten.value == INVALID)
            report_structure_failure(row);
    }
    opt_ir_ssa_incoming_values[row] = rewritten;
}
