// Computes spill storage independently for every scheduled OptIR node. The
// subsequent global prefix scan turns these widths into deterministic,
// function-relative stack offsets; no invocation walks a function.

import codegen.lowering_ir;
import codegen.optimization_ir;
import codegen.lir.x86.common;
import codegen.lir.x86.location_common;
import codegen.lir.x86.runtime_abi;
import gpu_index;

struct Params
{
    uint semantic_capacity;
    uint call_arg_capacity;
    uint aggregate_capacity;
    uint function_capacity;
    uint token_capacity;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement>
    semantic_lir_aggregate_elements;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> x86_live_by_semantic;
StructuredBuffer<uint> x86_last_use_by_semantic;
StructuredBuffer<X86FunctionRegisterAnalysis>
    x86_register_analysis_by_function;
RWStructuredBuffer<uint> x86_location_by_semantic;
RWStructuredBuffer<uint> x86_stack_words_by_position;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

bool produces_scalar_value(uint op)
{
    uint kind = semantic_lir_op_properties(op).result_kind;
    return kind == SEMANTIC_LIR_RESULT_SCALAR ||
        kind == SEMANTIC_LIR_RESULT_BOOL ||
        kind == SEMANTIC_LIR_RESULT_ADDRESS ||
        kind == SEMANTIC_LIR_RESULT_DYNAMIC;
}

bool scalar_gpr_result(OptIrNodeCore core)
{
    uint op = opt_ir_op(core);
    return op == SEMANTIC_LIR_OP_COMPARE || core.type_id == 1u ||
        core.type_id == 2u || core.type_id == 3u || core.type_id == 4u ||
        core.type_id == 6u || core.type_id == 8u;
}

bool produces_f32_value(uint op)
{
    // Comparisons and logical operations keep their operand type in the IR,
    // but produce an integer Boolean. They must never enter the XMM domain.
    return produces_scalar_value(op) &&
        op != SEMANTIC_LIR_OP_COMPARE &&
        op != SEMANTIC_LIR_OP_LOGICAL_NOT &&
        op != SEMANTIC_LIR_OP_LOGICAL_AND &&
        op != SEMANTIC_LIR_OP_LOGICAL_OR;
}

uint function_for_node(uint row)
{
    uint owner = opt_ir_source_hir[row];
    return owner < gParams.function_capacity
        ? semantic_function_id_by_hir[owner] : INVALID;
}

bool interval_crosses_call(uint position, uint last, uint total)
{
    // The bounded allocator admits intervals shorter than four positions, so
    // checking their interior is constant work per node. A call at `last`
    // consumes its arguments before clobbering caller-saved registers.
    for (uint cursor = position + 1u; cursor < last; ++cursor)
    {
        uint row = semantic_schedule_order[cursor];
        if (row < total && semantic_lir_is_call(opt_ir_op(opt_ir_core[row])))
            return true;
    }
    return false;
}

uint available_caller_lane(uint function_id, uint rank,
                           out uint available_count)
{
    uint reserved = 0u;
    bool has_call =
        x86_register_analysis_by_function[function_id].first_call != INVALID;
    if (!has_call)
    {
        SemanticLirFunction function = semantic_lir_functions[function_id];
        // Parameters always have ABI homes. Conservatively reserve homes for
        // the first six locals as well; dead declarations can reduce this mask
        // in a later, independently parallel declaration analysis.
        uint declaration_count = min(6u,
            function.param_count + function.local_count);
        for (uint ordinal = 0u; ordinal < declaration_count; ordinal += 1u)
        {
            uint physical = x86_caller_declaration_register(ordinal);
            if (physical >= 8u && physical <= 11u)
                reserved |= 1u << (physical - 8u);
        }
    }

    uint selected = INVALID;
    available_count = 0u;
    for (uint lane = 0u; lane < 4u; lane += 1u)
    {
        if ((reserved & (1u << lane)) != 0u) continue;
        if (available_count == rank) selected = lane;
        available_count += 1u;
    }
    return selected;
}

uint parallel_register_location(uint row, uint position, uint total)
{
    OptIrNodeCore core = opt_ir_core[row];
    uint op = opt_ir_op(core);
    if (!produces_scalar_value(op)) return INVALID;
    uint last = x86_last_use_by_semantic[row];
    if (last <= position) return INVALID;

    if (last == position + 1u && last < total)
    {
        uint consumer = semantic_schedule_order[last];
        if (consumer < total &&
            opt_ir_op(opt_ir_core[consumer]) == SEMANTIC_LIR_OP_RETURN &&
            opt_ir_operands[consumer].a == row)
            return X86_LOCATION_REGISTER;
    }
    uint function_id = function_for_node(row);
    if (function_id >= gParams.function_capacity) return INVALID;

    if (core.type_id == X86_LIR_TY_FLOAT && produces_f32_value(op))
    {
        if (last - position >= 8u ||
            interval_crosses_call(position, last, total))
            return INVALID;
        return x86_xmm_location(position & 7u);
    }

    if (!scalar_gpr_result(core)) return INVALID;
    uint available_count;
    available_caller_lane(function_id, 0u, available_count);
    if (available_count == 0u || last - position >= available_count)
        return INVALID;
    // The length guard bounds this local inspection to at most three
    // positions. No invocation performs a function-sized interval walk.
    if (interval_crosses_call(position, last, total)) return INVALID;
    uint rank = position % available_count;
    uint ignored_count;
    uint lane = available_caller_lane(function_id, rank, ignored_count);
    return lane == INVALID ? INVALID :
        X86_LOCATION_REGISTER | (8u + lane);
}

uint aggregate_copy_word_count(uint row, uint total, uint function_total)
{
    OptIrNodeCore core = opt_ir_core[row];
    OptIrNodeOperands operands = opt_ir_operands[row];
    uint op = opt_ir_op(core);
    if ((op != SEMANTIC_LIR_OP_VALUE_SET && op != SEMANTIC_LIR_OP_STORE) ||
        !x86_semantic_type_is_aggregate(core) || operands.b >= total)
        return 0u;
    OptIrNodeCore value_core = opt_ir_core[operands.b];
    OptIrNodeOperands value_operands = opt_ir_operands[operands.b];
    uint call_words = opt_ir_op(value_core) == SEMANTIC_LIR_OP_CALL &&
        value_operands.a < function_total
            ? semantic_lir_functions[value_operands.a].result_word_count : 0u;
    return max(max(core.value_word_count, call_words),
        x86_aggregate_value_word_count(value_core, value_operands));
}

uint aggregate_new_word_count(OptIrNodeCore core,
                              OptIrNodeOperands operands)
{
    uint words = 0u;
    uint element_total = min(gParams.aggregate_capacity,
        semantic_lir_aggregate_element_total[0u]);
    for (uint element = 0u; element < operands.b; element += 1u)
    {
        uint element_row = operands.a + element;
        if (element_row >= element_total) break;
        words += semantic_lir_aggregate_elements[element_row].word_count;
    }
    return max(core.value_word_count, words);
}

uint spill_word_count(uint row, uint total, uint function_total)
{
    OptIrNodeCore core = opt_ir_core[row];
    OptIrNodeOperands operands = opt_ir_operands[row];
    uint op = opt_ir_op(core);
    if (op == SEMANTIC_LIR_OP_VALUE_SET || op == SEMANTIC_LIR_OP_STORE)
    {
        uint words = aggregate_copy_word_count(row, total, function_total);
        return words == 0u ? 0u : 1u + words;
    }
    if (op == SEMANTIC_LIR_OP_AGGREGATE_NEW)
        return 1u + aggregate_new_word_count(core, operands);
    if (op == SEMANTIC_LIR_OP_CONST_STRING ||
        (op == SEMANTIC_LIR_OP_VALUE_GET &&
         core.type_id == SEMANTIC_LIR_TY_STRING))
        return 2u;
    if (op == SEMANTIC_LIR_OP_CALL)
    {
        uint words = operands.a < function_total
            ? semantic_lir_functions[operands.a].result_word_count : 0u;
        return 1u + words;
    }
    if (op == SEMANTIC_LIR_OP_CALL_SYMBOL)
        return 1u + core.value_word_count;
    if (op == SEMANTIC_LIR_OP_CALL_HOST)
        return operands.a == HOST_SERVICE_I32_TO_F32 ||
            x86_runtime_service_has_result(operands.a) ? 1u : 0u;
    if (op == SEMANTIC_LIR_OP_CALL_INTRINSIC)
        return operands.a == INTRINSIC_I32_ARRAY_DATA_PTR ? 1u : 0u;
    return produces_scalar_value(op) ? 1u : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint position = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (position >= total) return;
    uint row = semantic_schedule_order[position];
    uint words = 0u;
    if (row < total && x86_live_by_semantic[row] != 0u)
    {
        uint function_total = min(gParams.function_capacity,
            semantic_lir_function_total[0u]);
        uint location = parallel_register_location(row, position, total);
        if (location != INVALID)
            x86_location_by_semantic[row] = location;
        else
            words = spill_word_count(row, total, function_total);
    }
    x86_stack_words_by_position[position] = words;
}
