// Independently checks the local/global reaching-definition equation after
// declaration-read aliases have been published. This does not inspect the
// temporary pointer-jump links.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.optimization.ssa_demand_canonical_lookup;
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
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<OptIrNodeResults> opt_ir_results;
StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<OptIrAccessCore> opt_ir_accesses;
StructuredBuffer<uint> opt_ir_access_source_rows;
StructuredBuffer<uint> opt_ir_access_kinds;
StructuredBuffer<uint> opt_ir_local_definition_by_access;
StructuredBuffer<uint> opt_ir_ssa_demand_resolutions;
StructuredBuffer<uint> opt_ir_ssa_block_argument_total;
StructuredBuffer<uint> opt_ir_ssa_block_argument_replacement;
StructuredBuffer<uint> opt_ir_ssa_value_total;
StructuredBuffer<uint> opt_ir_ssa_value_by_block_argument;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
    InterlockedMax(lowering_status[0u].diagnostic_reason, 104u);
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

uint definition_value(
    uint access_id,
    uint declaration,
    uint access_total,
    uint node_total,
    uint parameter_total)
{
    if (access_id >= access_total ||
        opt_ir_accesses[access_id].subject != declaration)
        return INVALID;
    uint kind = opt_ir_access_kinds[access_id];
    uint source = opt_ir_access_source_rows[access_id];
    if (kind == OPT_IR_ACCESS_PARAMETER_DEFINITION)
        return source < parameter_total ? source : INVALID;
    if (kind != OPT_IR_ACCESS_DECLARATION_WRITE || source >= node_total)
        return INVALID;
    uint value_node = declaration_write_value_node(source, node_total);
    return value_node < node_total
        ? opt_ir_results[value_node].value_out : INVALID;
}

uint source_value(
    OptIrSsaValueRef source,
    uint declaration,
    uint access_total,
    uint node_total,
    uint parameter_total,
    uint argument_total)
{
    if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
    {
        if (source.payload >= argument_total) return INVALID;
        source = opt_ir_unpack_ssa_source(
            opt_ir_ssa_block_argument_replacement[source.payload]);
        if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
            return source.payload < argument_total
                ? opt_ir_ssa_value_by_block_argument[source.payload]
                : INVALID;
    }
    return source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION
        ? definition_value(source.payload, declaration, access_total,
            node_total, parameter_total)
        : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint access_id = linear_dispatch_thread_id_2d(
        dtid, DISPATCH_X_STRIDE);
    uint access_total = opt_ir_access_total[0u];
    if (access_id >= access_total ||
        opt_ir_access_kinds[access_id] !=
            OPT_IR_ACCESS_DECLARATION_READ)
        return;

    uint node_total = min(opt_ir_total[0u], gParams.semantic_capacity);
    uint parameter_total = min(semantic_param_total[0u],
        gParams.parameter_capacity);
    uint argument_total = min(opt_ir_ssa_block_argument_total[0u],
        gParams.block_argument_capacity);
    uint value_total = min(opt_ir_ssa_value_total[0u],
        gParams.value_capacity);
    uint node = opt_ir_access_source_rows[access_id];
    OptIrAccessCore access = opt_ir_accesses[access_id];

    OptIrSsaValueRef source;
    source.kind = OPT_IR_SSA_SOURCE_INVALID;
    source.payload = INVALID;
    uint local = opt_ir_local_definition_by_access[access_id];
    if (local != INVALID)
    {
        source.kind = OPT_IR_SSA_SOURCE_LOCAL_DEFINITION;
        source.payload = local;
    }
    else
    {
        uint demand_total = opt_ir_active_ssa_demand_total(
            gParams.block_argument_capacity);
        uint demand = opt_ir_find_ssa_demand(
            access.subject, access.block_id, demand_total);
        if (demand != INVALID)
            source = opt_ir_unpack_ssa_source(
                opt_ir_ssa_demand_resolutions[demand]);
    }

    uint expected = source_value(source, access.subject, access_total,
        node_total, parameter_total, argument_total);
    bool valid = node < node_total && expected < value_total &&
        opt_ir_op(opt_ir_core[node]) == SEMANTIC_LIR_OP_VALUE_GET &&
        opt_ir_operands[node].a == access.subject &&
        opt_ir_results[node].value_out == expected;
    if (!valid)
    {
        lowering_status[0u].first_unsupported_semantic_row = node;
        lowering_status[0u].required_capacity = access.subject;
        lowering_status[0u].available_capacity = access.block_id;
        lowering_status[0u].diagnostic_detail_kind = local;
        uint failed_demand = opt_ir_find_ssa_demand(
            access.subject, access.block_id,
            opt_ir_active_ssa_demand_total(
                gParams.block_argument_capacity));
        lowering_status[0u].diagnostic_detail = failed_demand == INVALID
            ? INVALID : opt_ir_ssa_demand_resolutions[failed_demand];
        report_structure_failure(access_id);
    }
}
