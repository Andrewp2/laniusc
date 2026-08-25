// Marks the three sources that own canonical SSA definitions: parameters,
// ordinary value-producing nodes, and nontrivial block arguments. Parameters
// are already dense and therefore need no scan lane.

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
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<uint> opt_ir_ssa_block_argument_total;
StructuredBuffer<uint> opt_ir_ssa_block_argument_replacement;
RWStructuredBuffer<uint> opt_ir_ssa_node_value_flag;
RWStructuredBuffer<uint> opt_ir_ssa_block_argument_value_flag;
RWStructuredBuffer<uint> opt_ir_ssa_node_value_scan_dispatch_args;
RWStructuredBuffer<uint> opt_ir_ssa_block_argument_value_scan_dispatch_args;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WORKGROUP_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

void write_scan_dispatch(uint total, RWStructuredBuffer<uint> args)
{
    uint groups = max(1u, (total + WORKGROUP_SIZE - 1u) / WORKGROUP_SIZE);
    args[0u] = min(groups, MAX_GROUPS_X);
    args[1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    args[2u] = 1u;
}

void report_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_VALUE_MARK,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint node_total = min(opt_ir_total[0u], gParams.semantic_capacity);
    uint argument_total = min(opt_ir_ssa_block_argument_total[0u],
        gParams.block_argument_capacity);
    if (row == 0u)
    {
        write_scan_dispatch(node_total,
            opt_ir_ssa_node_value_scan_dispatch_args);
        write_scan_dispatch(argument_total,
            opt_ir_ssa_block_argument_value_scan_dispatch_args);
    }

    if (row < node_total)
    {
        uint op = opt_ir_op(opt_ir_core[row]);
        bool owns_definition = semantic_lir_produces_value(op) &&
            op != SEMANTIC_LIR_OP_VALUE_GET;
        opt_ir_ssa_node_value_flag[row] = owns_definition ? 1u : 0u;
    }

    if (row < argument_total)
    {
        OptIrSsaValueRef replacement = opt_ir_unpack_ssa_source(
            opt_ir_ssa_block_argument_replacement[row]);
        bool survives = replacement.kind ==
                OPT_IR_SSA_SOURCE_BLOCK_ARGUMENT &&
            replacement.payload == row;
        bool valid = survives ||
            replacement.kind == OPT_IR_SSA_SOURCE_LOCAL_DEFINITION;
        opt_ir_ssa_block_argument_value_flag[row] = survives ? 1u : 0u;
        if (!valid) report_structure_failure(row);
    }
}
