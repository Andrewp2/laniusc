// Turns each declaration read into a temporary link to either a canonical
// dense value or another declaration-read node. The latter links are compact
// copy chains and are collapsed in logarithmic GPU rounds.

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
RWStructuredBuffer<uint> opt_ir_ssa_value_link_out;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
    InterlockedMax(lowering_status[0u].diagnostic_reason, 102u);
}

uint node_link(uint node, uint node_total, uint value_total)
{
    if (node >= node_total) return 0u;
    uint value = opt_ir_results[node].value_out;
    if (value < value_total)
        return opt_ir_pack_ssa_value_link(
            OPT_IR_SSA_VALUE_LINK_VALUE, value);
    if (opt_ir_op(opt_ir_core[node]) == SEMANTIC_LIR_OP_VALUE_GET)
        return opt_ir_pack_ssa_value_link(
            OPT_IR_SSA_VALUE_LINK_NODE, node);
    return 0u;
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

uint definition_link(
    uint access_id,
    uint declaration,
    uint access_total,
    uint node_total,
    uint parameter_total,
    uint value_total)
{
    if (access_id >= access_total ||
        opt_ir_accesses[access_id].subject != declaration)
        return 0u;
    uint kind = opt_ir_access_kinds[access_id];
    uint source = opt_ir_access_source_rows[access_id];
    if (kind == OPT_IR_ACCESS_PARAMETER_DEFINITION)
        return source < parameter_total && source < value_total
            ? opt_ir_pack_ssa_value_link(
                OPT_IR_SSA_VALUE_LINK_VALUE, source)
            : 0u;
    if (kind != OPT_IR_ACCESS_DECLARATION_WRITE || source >= node_total)
        return 0u;
    uint value_node = declaration_write_value_node(source, node_total);
    return node_link(value_node, node_total, value_total);
}

uint source_link(
    OptIrSsaValueRef source,
    uint declaration,
    uint access_total,
    uint node_total,
    uint parameter_total,
    uint argument_total,
    uint value_total)
{
    if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
    {
        if (source.payload >= argument_total) return 0u;
        source = opt_ir_unpack_ssa_source(
            opt_ir_ssa_block_argument_replacement[source.payload]);
        if (source.kind == OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT)
        {
            uint value = source.payload < argument_total
                ? opt_ir_ssa_value_by_block_argument[source.payload]
                : INVALID;
            return value < value_total
                ? opt_ir_pack_ssa_value_link(
                    OPT_IR_SSA_VALUE_LINK_VALUE, value)
                : 0u;
        }
    }
    return source.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION
        ? definition_link(source.payload, declaration, access_total,
            node_total, parameter_total, value_total)
        : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint access_id = linear_dispatch_thread_id_2d(
        dtid, DISPATCH_X_STRIDE);
    // `access_total` was already clamped to the physical access capacity by
    // access materialization. It also includes local-declaration metadata, so
    // semantic-plus-parameter capacity is not a valid upper bound here.
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
    bool valid = node < node_total &&
        opt_ir_op(opt_ir_core[node]) == SEMANTIC_LIR_OP_VALUE_GET &&
        opt_ir_operands[node].a == access.subject;

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

    uint link = valid ? source_link(source, access.subject,
        access_total, node_total, parameter_total, argument_total,
        value_total) : 0u;
    if (link == 0u)
    {
        report_structure_failure(access_id);
        return;
    }
    opt_ir_ssa_value_link_out[node] = link;
}
