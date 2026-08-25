import codegen.lir.x86.common;
import codegen.lir.x86.runtime_abi;
import codegen.lowering_ir;
import codegen.optimization_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint semantic_start; uint page_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> opt_ir_total;
StructuredBuffer<OptIrNodeCore> opt_ir_core;
StructuredBuffer<OptIrNodeOperands> opt_ir_operands;
StructuredBuffer<uint> semantic_lir_layout_word_offset;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> opt_ir_source_hir;
StructuredBuffer<uint> opt_ir_semantic_row;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_start_by_hir;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
StructuredBuffer<uint> x86_live_by_semantic;
StructuredBuffer<X86InlineInfo> x86_inline_info_by_function;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
RWStructuredBuffer<uint> target_lir_count;
RWStructuredBuffer<LoweringStatus> lowering_status;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

bool constant_i32_value(uint row, uint total, out uint value)
{
    value = 0u;
    if (row >= total) return false;
    OptIrNodeCore core = opt_ir_core[row];
    OptIrNodeOperands operands = opt_ir_operands[row];
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CONST_I32)
    {
        value = operands.a;
        return true;
    }
    if (operands.a >= total || operands.b >= total) return false;
    OptIrNodeCore left_core = opt_ir_core[operands.a];
    OptIrNodeCore right_core = opt_ir_core[operands.b];
    if (opt_ir_op(left_core) != SEMANTIC_LIR_OP_CONST_I32 ||
        opt_ir_op(right_core) != SEMANTIC_LIR_OP_CONST_I32)
        return false;
    uint left = opt_ir_operands[operands.a].a;
    uint right = opt_ir_operands[operands.b].a;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_ADD) value = left + right;
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_SUB) value = left - right;
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_MUL) value = left * right;
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_REM && right != 0u)
        value = uint(int(left) % int(right));
    else if (opt_ir_op(core) == SEMANTIC_LIR_OP_DIV && right != 0u)
        value = uint(int(left) / int(right));
    else return false;
    return true;
}

void report_diagnostic(uint reason, uint detail_kind, uint detail, uint hir,
    uint opt_row)
{
    uint prior;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE, reason, prior);
    if (prior == LOWERING_DIAGNOSTIC_NONE || prior == reason)
    {
        lowering_status[0u].diagnostic_detail_kind = detail_kind;
        lowering_status[0u].diagnostic_detail = detail;
        InterlockedMin(lowering_status[0u].first_unsupported_hir, hir);
        InterlockedMin(lowering_status[0u].first_unsupported_semantic_row,
            opt_ir_semantic_row[opt_row]);
        InterlockedMin(lowering_status[0u].first_unsupported_opt_row, opt_row);
    }
    InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
}

uint function_abi_param_count(SemanticLirFunction function)
{
    uint count = 0u;
    for (uint ordinal = 0u; ordinal < function.param_count; ordinal += 1u)
        count += x86_abi_type_width(
            semantic_lir_params[function.param_start + ordinal].type_id);
    return count;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint scheduled_row = gParams.semantic_start + page_row;
    uint total = min(gParams.semantic_capacity, opt_ir_total[0u]);
    if (scheduled_row >= total)
    {
        target_lir_count[scheduled_row] = 0u;
        return;
    }
    uint semantic_row = semantic_schedule_order[scheduled_row];
    if (semantic_row >= total || x86_live_by_semantic[semantic_row] == 0u)
    {
        target_lir_count[scheduled_row] = 0u;
        return;
    }
    OptIrNodeCore core = opt_ir_core[semantic_row];
    uint source_hir = opt_ir_source_hir[semantic_row];
    uint function_count = min(gParams.semantic_capacity, semantic_lir_function_total[0u]);
    uint owner = semantic_function_id_by_hir[source_hir];
    if (owner < function_count &&
        x86_inline_info_by_function[owner].return_value != INVALID)
    {
        target_lir_count[scheduled_row] = 0u;
        return;
    }
    if ((core.flags & SEMANTIC_LIR_FLAG_UNSUPPORTED_FOR_ITERABLE) != 0u)
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_FOR_ITERABLE,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, source_hir, source_hir, semantic_row);
    if ((core.flags & SEMANTIC_LIR_FLAG_SHORT_CIRCUIT_CALL) != 0u)
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_SHORT_CIRCUIT_CALL,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, source_hir, source_hir, semantic_row);
    if ((core.flags & SEMANTIC_LIR_FLAG_SHORT_CIRCUIT_TRAP) != 0u)
    {
        uint detail_hir = source_hir;
        if ((core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
        {
            uint index_row = opt_ir_operands[semantic_row].b;
            if (index_row < total)
                detail_hir = opt_ir_source_hir[index_row];
        }
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_SHORT_CIRCUIT_TRAP,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, detail_hir, source_hir, semantic_row);
    }
    if ((core.flags & SEMANTIC_LIR_FLAG_UNSUPPORTED_MATCH_CONTEXT) != 0u)
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_MATCH_EXPRESSION,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, source_hir, source_hir, semantic_row);
    uint argument_count = semantic_lir_is_call(opt_ir_op(core))
        ? semantic_lir_call_arg_count_by_hir[source_hir]
        : 0u;
    uint argument_rows = 0u;
    uint argument_start = semantic_lir_call_arg_start_by_hir[source_hir];
    for (uint arg_i = 0u; arg_i < min(argument_count, 6u); arg_i += 1u)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[argument_start + arg_i];
        argument_rows +=
            (argument.value_metadata & SEMANTIC_LIR_VALUE_STRING) != 0u
                ? 2u : 1u;
    }
    OptIrNodeOperands operands = opt_ir_operands[semantic_row];
    uint constant_rhs = 0u;
    if ((opt_ir_op(core) == SEMANTIC_LIR_OP_DIV || opt_ir_op(core) == SEMANTIC_LIR_OP_REM) &&
        core.type_id != 5u &&
        constant_i32_value(operands.b, total, constant_rhs) && constant_rhs == 0u)
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_ZERO_DIVISOR,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, source_hir, source_hir, semantic_row);
    if ((core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
    {
        uint length = semantic_lir_layout_word_offset[semantic_row];
        uint index_value = 0u;
        if (length == INVALID)
        {
            uint detail_hir = operands.b < total
                ? opt_ir_source_hir[operands.b] : source_hir;
            report_diagnostic(LOWERING_DIAGNOSTIC_X86_DYNAMIC_ARRAY_INDEX,
                LOWERING_DIAGNOSTIC_DETAIL_HIR, detail_hir, source_hir, semantic_row);
        }
        else if (constant_i32_value(operands.b, total, index_value))
        {
            if (index_value >= length)
                report_diagnostic(LOWERING_DIAGNOSTIC_X86_ARRAY_INDEX_BOUNDS,
                    LOWERING_DIAGNOSTIC_DETAIL_HIR, source_hir, source_hir, semantic_row);
        }
    }
    if (owner < function_count)
    {
        SemanticLirFunction function = semantic_lir_functions[owner];
        bool entrypoint = (function.flags & SEMANTIC_FUNCTION_FLAG_ENTRYPOINT) != 0u;
        if (entrypoint && function.param_count != 0u)
        {
            uint detail = function.name_token;
            if (function.param_start != INVALID)
                detail = semantic_lir_params[function.param_start].declaration_id;
            report_diagnostic(LOWERING_DIAGNOSTIC_X86_ENTRYPOINT_PARAMETERS,
                LOWERING_DIAGNOSTIC_DETAIL_TOKEN, detail, function.hir_function,
                semantic_row);
        }
        else if (entrypoint && function.result_word_count != 0u)
            report_diagnostic(LOWERING_DIAGNOSTIC_X86_ENTRYPOINT_AGGREGATE_RETURN,
                LOWERING_DIAGNOSTIC_DETAIL_TOKEN, function.name_token,
                function.hir_function, semantic_row);
        else if (!entrypoint && function_abi_param_count(function) > 6u)
        {
            uint detail = function.name_token;
            if (function.param_start != INVALID)
            {
                uint abi_ordinal = 0u;
                for (uint param_ordinal = 0u;
                     param_ordinal < function.param_count; param_ordinal += 1u)
                {
                    SemanticLirParam param =
                        semantic_lir_params[function.param_start + param_ordinal];
                    if (abi_ordinal + x86_abi_type_width(param.type_id) > 6u)
                    {
                        detail = param.declaration_id;
                        break;
                    }
                    abi_ordinal += x86_abi_type_width(param.type_id);
                }
            }
            report_diagnostic(LOWERING_DIAGNOSTIC_X86_PARAMETER_REGISTERS,
                LOWERING_DIAGNOSTIC_DETAIL_TOKEN, detail, function.hir_function,
                semantic_row);
        }
    }
    uint result_words = opt_ir_op(core) == SEMANTIC_LIR_OP_CALL &&
        operands.a < function_count ? semantic_lir_functions[operands.a].result_word_count :
        opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL ? core.value_word_count : 0u;
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL && operands.a < function_count &&
        (semantic_lir_functions[operands.a].flags & SEMANTIC_FUNCTION_FLAG_EXTERN) != 0u)
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_CALL_ABI,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, source_hir, source_hir, semantic_row);
    if ((opt_ir_op(core) == SEMANTIC_LIR_OP_CALL || opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL) &&
        result_words != 0u && argument_rows >= 6u)
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_CALL_ABI,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, source_hir, source_hir, semantic_row);
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_HOST &&
        operands.a != HOST_SERVICE_I32_TO_F32 &&
        !x86_runtime_service_supported(operands.a))
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_CALL_ABI,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, source_hir, source_hir, semantic_row);
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL_SYMBOL &&
        (operands.a == INVALID || operands.b == INVALID || operands.c == INVALID))
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_CALL_ABI,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, source_hir, source_hir, semantic_row);
    uint return_words = opt_ir_op(core) == SEMANTIC_LIR_OP_RETURN && owner < function_count
        ? semantic_lir_functions[owner].result_word_count : 0u;
    uint copy_words = 0u;
    if ((opt_ir_op(core) == SEMANTIC_LIR_OP_VALUE_SET ||
         opt_ir_op(core) == SEMANTIC_LIR_OP_STORE) &&
        x86_semantic_type_is_aggregate(core) && operands.b < total)
    {
        OptIrNodeCore value_core = opt_ir_core[operands.b];
        OptIrNodeOperands value_operands = opt_ir_operands[operands.b];
        uint call_words = opt_ir_op(value_core) == SEMANTIC_LIR_OP_CALL &&
            value_operands.a < function_count
            ? semantic_lir_functions[value_operands.a].result_word_count : 0u;
        copy_words = max(max(core.value_word_count, call_words),
            x86_aggregate_value_word_count(value_core, value_operands));
    }
    uint operation_rows = x86_lir_count(core, operands);
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_CALL &&
        operands.a < function_count)
    {
        X86InlineInfo inline_info = x86_inline_info_by_function[operands.a];
        if (inline_info.return_value != INVALID)
        {
            target_lir_count[scheduled_row] = argument_rows +
                inline_info.body_row_count + 1u;
            return;
        }
    }
    if (opt_ir_op(core) == SEMANTIC_LIR_OP_AGGREGATE_NEW)
    {
        uint element_total = semantic_lir_aggregate_element_total[0u];
        uint words = 0u;
        for (uint element_i = 0u; element_i < operands.b; element_i += 1u)
        {
            uint row = operands.a + element_i;
            if (row >= element_total) break;
            words += semantic_lir_aggregate_elements[row].word_count;
        }
        operation_rows = 1u + max(core.value_word_count, words);
    }
    target_lir_count[scheduled_row] = operation_rows +
        argument_rows + result_words + return_words + copy_words;
}
