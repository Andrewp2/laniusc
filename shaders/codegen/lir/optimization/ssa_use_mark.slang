// Counts canonical fixed-operand uses per OptIR node. Declaration-state rows
// disappear at the SSA boundary, so their assignment operands do not become
// optimizer uses merely to preserve the old mutable representation.

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
StructuredBuffer<uint> opt_ir_ssa_value_total;
StructuredBuffer<uint> semantic_lir_call_arg_total;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_start_by_hir;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> opt_ir_ssa_call_argument_values;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement>
    semantic_lir_aggregate_elements;
StructuredBuffer<uint> opt_ir_ssa_aggregate_element_values;
RWStructuredBuffer<uint> opt_ir_ssa_node_use_count;
RWStructuredBuffer<uint> opt_ir_ssa_node_use_scan_dispatch_args;
RWStructuredBuffer<uint> opt_ir_ssa_call_use_flag;
RWStructuredBuffer<uint> opt_ir_ssa_call_use_scan_dispatch_args;
RWStructuredBuffer<uint> opt_ir_ssa_aggregate_use_flag;
RWStructuredBuffer<uint> opt_ir_ssa_aggregate_use_scan_dispatch_args;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WORKGROUP_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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

void write_scan_dispatch(uint total, RWStructuredBuffer<uint> args)
{
    uint groups = max(1u,
        (total + WORKGROUP_SIZE - 1u) / WORKGROUP_SIZE);
    args[0u] = min(groups, MAX_GROUPS_X);
    args[1u] = max(1u,
        (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    args[2u] = 1u;
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (row >= max(gParams.semantic_capacity,
        max(gParams.call_argument_capacity,
            gParams.aggregate_element_capacity))) return;
    uint node_total = min(opt_ir_total[0u], gParams.semantic_capacity);
    uint call_total = min(semantic_lir_call_arg_total[0u],
        gParams.call_argument_capacity);
    uint aggregate_total = min(semantic_lir_aggregate_element_total[0u],
        gParams.aggregate_element_capacity);
    if (row == 0u)
    {
        write_scan_dispatch(node_total,
            opt_ir_ssa_node_use_scan_dispatch_args);
        write_scan_dispatch(call_total,
            opt_ir_ssa_call_use_scan_dispatch_args);
        write_scan_dispatch(aggregate_total,
            opt_ir_ssa_aggregate_use_scan_dispatch_args);
    }
    uint value_total = min(opt_ir_ssa_value_total[0u],
        gParams.value_capacity);
    if (row < node_total)
    {
        uint count = 0u;
        OptIrNodeCore core = opt_ir_core[row];
        OptIrNodeOperands operands = opt_ir_ssa_operands[row];
        if (!opt_ir_is_declaration_state_node(core))
        {
            for (uint ordinal = 0u; ordinal < 3u; ++ordinal)
            {
                if (!opt_ir_operand_is_value(core, ordinal)) continue;
                uint value = opt_ir_operand(operands, ordinal);
                if (value >= value_total)
                    report_structure_failure(row);
                else
                    count += 1u;
            }
        }
        opt_ir_ssa_node_use_count[row] = count;
    }

    if (row < call_total)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[row];
        bool active = active_call_argument(row, argument, node_total);
        if (active && opt_ir_ssa_call_argument_values[row] >= value_total)
            report_structure_failure(argument.call_instruction);
        opt_ir_ssa_call_use_flag[row] = active ? 1u : 0u;
    }

    if (row < aggregate_total)
    {
        SemanticLirAggregateElement element =
            semantic_lir_aggregate_elements[row];
        bool active = active_aggregate_element(element, node_total);
        if (active &&
            opt_ir_ssa_aggregate_element_values[row] >= value_total)
            report_structure_failure(element.aggregate_instruction);
        opt_ir_ssa_aggregate_use_flag[row] = active ? 1u : 0u;
    }
}
