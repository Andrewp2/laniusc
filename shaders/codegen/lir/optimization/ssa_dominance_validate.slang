// Independently validates the final dense value edges. Every ordinary,
// variable-arity, and block-argument use must name one canonical definition
// that is available at the use site.

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
StructuredBuffer<SemanticLirParam> semantic_params;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<OptIrNodeOperands> opt_ir_ssa_operands;
StructuredBuffer<OptIrNodeControl> opt_ir_control;
StructuredBuffer<OptIrNodeResults> opt_ir_results;
StructuredBuffer<uint> opt_ir_position_by_node;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> opt_ir_block_total;
StructuredBuffer<OptIrBlock> opt_ir_blocks;
StructuredBuffer<OptIrEdge> opt_ir_edges;
StructuredBuffer<uint> opt_ir_dominator_preorder;
StructuredBuffer<uint> opt_ir_dominator_subtree_end;
StructuredBuffer<uint> opt_ir_access_total;
StructuredBuffer<uint> opt_ir_access_source_rows;
StructuredBuffer<uint> opt_ir_access_kinds;
StructuredBuffer<uint> opt_ir_ssa_block_argument_total;
StructuredBuffer<OptIrBlockArgument> opt_ir_ssa_block_arguments;
StructuredBuffer<uint> opt_ir_ssa_block_argument_replacement;
StructuredBuffer<uint> opt_ir_ssa_block_argument_incoming_total;
StructuredBuffer<OptIrBlockArgumentIncoming>
    opt_ir_ssa_block_argument_incoming;
StructuredBuffer<OptIrIncomingValue> opt_ir_ssa_incoming_values;
StructuredBuffer<uint> opt_ir_ssa_value_total;
StructuredBuffer<OptIrValueDefinition> opt_ir_ssa_value_definitions;
StructuredBuffer<uint> opt_ir_ssa_value_by_block_argument;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_start_by_hir;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> opt_ir_ssa_call_argument_values;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement>
    semantic_lir_aggregate_elements;
StructuredBuffer<uint> opt_ir_ssa_aggregate_element_values;
RWStructuredBuffer<LoweringStatus> lowering_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

void report_structure_failure(uint row)
{
    uint ignored;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE,
        LOWERING_DIAGNOSTIC_OPT_SSA_DOMINANCE,
        ignored);
    InterlockedOr(lowering_status[0u].flags,
        LOWERING_STATUS_OPTIMIZATION_STRUCTURE);
    InterlockedMin(lowering_status[0u].first_unsupported_opt_row, row);
}

bool block_dominates(uint definition, uint use, uint block_total)
{
    if (definition >= block_total || use >= block_total) return false;
    if (opt_ir_blocks[definition].function_id !=
        opt_ir_blocks[use].function_id)
        return false;
    uint begin = opt_ir_dominator_preorder[definition];
    uint end = opt_ir_dominator_subtree_end[definition];
    uint point = opt_ir_dominator_preorder[use];
    return begin != INVALID && end != INVALID && point != INVALID &&
        begin <= point && point < end;
}

bool parameter_available(uint parameter, uint use_block,
    uint parameter_total, uint block_total)
{
    return parameter < parameter_total && use_block < block_total &&
        semantic_params[parameter].function_id ==
            opt_ir_blocks[use_block].function_id;
}

bool value_available_at_node(uint value, uint use_node, uint node_total,
    uint parameter_total, uint argument_total, uint value_total,
    uint block_total)
{
    if (value >= value_total || use_node >= node_total) return false;
    uint use_block = opt_ir_control[use_node].block_id;
    if (use_block >= block_total) return false;
    OptIrValueDefinition definition = opt_ir_ssa_value_definitions[value];
    uint kind = opt_ir_value_definition_kind(definition);
    uint payload = opt_ir_value_definition_payload(definition);
    if (kind == OPT_IR_VALUE_DEFINITION_PARAMETER)
        return parameter_available(payload, use_block,
            parameter_total, block_total);
    if (kind == OPT_IR_VALUE_DEFINITION_NODE)
    {
        if (payload >= node_total || opt_ir_results[payload].value_out != value)
            return false;
        uint definition_block = opt_ir_control[payload].block_id;
        if (definition_block == use_block)
            return opt_ir_position_by_node[payload] <
                opt_ir_position_by_node[use_node];
        return block_dominates(definition_block, use_block, block_total);
    }
    if (kind == OPT_IR_VALUE_DEFINITION_BLOCK_ARGUMENT)
    {
        if (payload >= argument_total ||
            opt_ir_ssa_value_by_block_argument[payload] != value)
            return false;
        uint definition_block = opt_ir_ssa_block_arguments[payload].block_id;
        return definition_block == use_block ||
            block_dominates(definition_block, use_block, block_total);
    }
    return false;
}

bool value_available_at_block_end(uint value, uint use_block,
    uint node_total, uint parameter_total, uint argument_total,
    uint value_total, uint block_total)
{
    if (value >= value_total || use_block >= block_total) return false;
    OptIrValueDefinition definition = opt_ir_ssa_value_definitions[value];
    uint kind = opt_ir_value_definition_kind(definition);
    uint payload = opt_ir_value_definition_payload(definition);
    if (kind == OPT_IR_VALUE_DEFINITION_PARAMETER)
        return parameter_available(payload, use_block,
            parameter_total, block_total);
    if (kind == OPT_IR_VALUE_DEFINITION_NODE)
    {
        if (payload >= node_total || opt_ir_results[payload].value_out != value)
            return false;
        uint definition_block = opt_ir_control[payload].block_id;
        return definition_block == use_block ||
            block_dominates(definition_block, use_block, block_total);
    }
    if (kind == OPT_IR_VALUE_DEFINITION_BLOCK_ARGUMENT)
    {
        if (payload >= argument_total ||
            opt_ir_ssa_value_by_block_argument[payload] != value)
            return false;
        uint definition_block = opt_ir_ssa_block_arguments[payload].block_id;
        return definition_block == use_block ||
            block_dominates(definition_block, use_block, block_total);
    }
    return false;
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

uint expected_local_definition_value(uint access_id, uint access_total,
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

uint expected_source_value(OptIrSsaValueRef source, uint access_total,
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
        return expected_local_definition_value(source.payload, access_total,
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

uint incoming_owner(uint row, uint argument_total)
{
    uint lo = 0u;
    uint hi = argument_total;
    while (lo < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (opt_ir_ssa_block_arguments[mid].incoming_start <= row)
            lo = mid + 1u;
        else
            hi = mid;
    }
    if (lo == 0u) return INVALID;
    uint owner = lo - 1u;
    OptIrBlockArgument argument = opt_ir_ssa_block_arguments[owner];
    return row - argument.incoming_start < argument.incoming_count
        ? owner : INVALID;
}

bool has_cfg_edge(uint from, uint to, uint block_total)
{
    if (from >= block_total || to >= block_total) return false;
    OptIrBlock block = opt_ir_blocks[from];
    uint start = opt_ir_block_edge_start(block);
    uint count = opt_ir_block_edge_count(block);
    for (uint ordinal = 0u; ordinal < count; ++ordinal)
    {
        OptIrEdge edge = opt_ir_edges[start + ordinal];
        if (edge.from_block == from &&
            opt_ir_edge_to_block(edge.packed_target) == to)
            return true;
    }
    return false;
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
    uint parameter_total = min(semantic_param_total[0u],
        gParams.parameter_capacity);
    uint block_total = min(opt_ir_block_total[0u], gParams.block_capacity);
    uint argument_total = min(opt_ir_ssa_block_argument_total[0u],
        gParams.block_argument_capacity);
    uint incoming_total = min(opt_ir_ssa_block_argument_incoming_total[0u],
        gParams.incoming_capacity);
    uint value_total = min(opt_ir_ssa_value_total[0u],
        gParams.value_capacity);
    uint access_total = min(opt_ir_access_total[0u],
        gParams.access_capacity);

    if (row < node_total)
    {
        OptIrNodeCore core = opt_ir_core[row];
        OptIrNodeOperands operands = opt_ir_ssa_operands[row];
        for (uint ordinal = 0u; ordinal < 3u; ++ordinal)
        {
            if (!opt_ir_operand_is_value(core, ordinal)) continue;
            uint value = opt_ir_operand(operands, ordinal);
            if (!value_available_at_node(value, row, node_total,
                    parameter_total, argument_total, value_total,
                    block_total))
                report_structure_failure(row);
        }
    }

    if (row < gParams.call_argument_capacity)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[row];
        if (active_call_argument(row, argument, node_total) &&
            !value_available_at_node(opt_ir_ssa_call_argument_values[row],
                argument.call_instruction, node_total, parameter_total,
                argument_total, value_total, block_total))
            report_structure_failure(argument.call_instruction);
    }

    uint aggregate_total = min(semantic_lir_aggregate_element_total[0u],
        gParams.aggregate_element_capacity);
    if (row < aggregate_total)
    {
        SemanticLirAggregateElement element =
            semantic_lir_aggregate_elements[row];
        bool active = element.aggregate_instruction < node_total &&
            element.value_instruction < node_total;
        if (active && !value_available_at_node(
                opt_ir_ssa_aggregate_element_values[row],
                element.aggregate_instruction, node_total, parameter_total,
                argument_total, value_total, block_total))
            report_structure_failure(element.aggregate_instruction);
    }

    if (row < incoming_total)
    {
        OptIrBlockArgumentIncoming source =
            opt_ir_ssa_block_argument_incoming[row];
        OptIrIncomingValue incoming = opt_ir_ssa_incoming_values[row];
        uint owner = incoming_owner(row, argument_total);
        uint expected = expected_source_value(
            opt_ir_unpack_ssa_source(source.source), access_total,
            node_total, parameter_total, argument_total, value_total);
        bool valid = owner < argument_total && expected != INVALID &&
            incoming.predecessor == source.predecessor &&
            incoming.value == expected;
        uint target = valid
            ? opt_ir_ssa_block_arguments[owner].block_id : INVALID;
        valid = valid && has_cfg_edge(incoming.predecessor, target,
            block_total) && value_available_at_block_end(incoming.value,
            incoming.predecessor, node_total, parameter_total,
            argument_total, value_total, block_total);
        if (!valid) report_structure_failure(row);
    }
}
