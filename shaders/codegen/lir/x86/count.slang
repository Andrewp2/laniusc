import codegen.lir.x86.common;
import codegen.lir.x86.runtime_abi;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint semantic_start; uint page_capacity; uint reserved; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirOperands> semantic_lir_operands;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> semantic_owner_by_instruction;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_start_by_hir;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<SemanticLirParam> semantic_lir_params;
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
    SemanticLirCore core = semantic_lir_core[row];
    SemanticLirOperands operands = semantic_lir_operands[row];
    if (core.op == SEMANTIC_LIR_OP_CONST_I32)
    {
        value = operands.a;
        return true;
    }
    if (operands.a >= total || operands.b >= total) return false;
    SemanticLirCore left_core = semantic_lir_core[operands.a];
    SemanticLirCore right_core = semantic_lir_core[operands.b];
    if (left_core.op != SEMANTIC_LIR_OP_CONST_I32 ||
        right_core.op != SEMANTIC_LIR_OP_CONST_I32)
        return false;
    uint left = semantic_lir_operands[operands.a].a;
    uint right = semantic_lir_operands[operands.b].a;
    if (core.op == SEMANTIC_LIR_OP_ADD) value = left + right;
    else if (core.op == SEMANTIC_LIR_OP_SUB) value = left - right;
    else if (core.op == SEMANTIC_LIR_OP_MUL) value = left * right;
    else if (core.op == SEMANTIC_LIR_OP_REM && right != 0u)
        value = uint(int(left) % int(right));
    else if (core.op == SEMANTIC_LIR_OP_DIV && right != 0u)
        value = uint(int(left) / int(right));
    else return false;
    return true;
}

void report_diagnostic(uint reason, uint detail_kind, uint detail, uint hir)
{
    uint prior;
    InterlockedCompareExchange(lowering_status[0u].diagnostic_reason,
        LOWERING_DIAGNOSTIC_NONE, reason, prior);
    if (prior == LOWERING_DIAGNOSTIC_NONE || prior == reason)
    {
        lowering_status[0u].diagnostic_detail_kind = detail_kind;
        lowering_status[0u].diagnostic_detail = detail;
        InterlockedMin(lowering_status[0u].first_unsupported_hir, hir);
    }
    InterlockedOr(lowering_status[0u].flags, LOWERING_STATUS_UNSUPPORTED_TARGET);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint scheduled_row = gParams.semantic_start + page_row;
    uint total = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    if (scheduled_row >= total)
    {
        target_lir_count[scheduled_row] = 0u;
        return;
    }
    uint semantic_row = semantic_schedule_order[scheduled_row];
    SemanticLirCore core = semantic_lir_core[semantic_row];
    if ((core.flags & SEMANTIC_LIR_FLAG_UNSUPPORTED_FOR_ITERABLE) != 0u)
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_FOR_ITERABLE,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, core.source_hir, core.source_hir);
    if ((core.flags & SEMANTIC_LIR_FLAG_SHORT_CIRCUIT_CALL) != 0u)
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_SHORT_CIRCUIT_CALL,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, core.source_hir, core.source_hir);
    if ((core.flags & SEMANTIC_LIR_FLAG_SHORT_CIRCUIT_TRAP) != 0u)
    {
        uint detail_hir = core.source_hir;
        if ((core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
        {
            uint index_row = semantic_lir_operands[semantic_row].b;
            if (index_row < total)
                detail_hir = semantic_lir_core[index_row].source_hir;
        }
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_SHORT_CIRCUIT_TRAP,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, detail_hir, core.source_hir);
    }
    if ((core.flags & SEMANTIC_LIR_FLAG_UNSUPPORTED_MATCH_CONTEXT) != 0u)
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_MATCH_EXPRESSION,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, core.source_hir, core.source_hir);
    uint argument_count = (core.op == SEMANTIC_LIR_OP_CALL ||
                          core.op == SEMANTIC_LIR_OP_CALL_HOST ||
                          core.op == SEMANTIC_LIR_OP_CALL_INTRINSIC ||
                          core.op == SEMANTIC_LIR_OP_CALL_SYMBOL)
        ? semantic_lir_call_arg_count_by_hir[core.source_hir]
        : 0u;
    uint argument_rows = 0u;
    uint argument_start = semantic_lir_call_arg_start_by_hir[core.source_hir];
    for (uint arg_i = 0u; arg_i < min(argument_count, 6u); arg_i += 1u)
    {
        SemanticLirCallArg argument = semantic_lir_call_args[argument_start + arg_i];
        argument_rows +=
            (argument.value_metadata & SEMANTIC_LIR_VALUE_STRING) != 0u
                ? 2u : 1u;
    }
    SemanticLirOperands operands = semantic_lir_operands[semantic_row];
    uint constant_rhs = 0u;
    if ((core.op == SEMANTIC_LIR_OP_DIV || core.op == SEMANTIC_LIR_OP_REM) &&
        core.type_id != 5u &&
        constant_i32_value(operands.b, total, constant_rhs) && constant_rhs == 0u)
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_ZERO_DIVISOR,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, core.source_hir, core.source_hir);
    if ((core.flags & SEMANTIC_LIR_FLAG_INDEXED) != 0u)
    {
        uint length = core.array_length;
        uint index_value = 0u;
        if (length == INVALID)
        {
            uint detail_hir = operands.b < total
                ? semantic_lir_core[operands.b].source_hir : core.source_hir;
            report_diagnostic(LOWERING_DIAGNOSTIC_X86_DYNAMIC_ARRAY_INDEX,
                LOWERING_DIAGNOSTIC_DETAIL_HIR, detail_hir, core.source_hir);
        }
        else if (constant_i32_value(operands.b, total, index_value))
        {
            if (index_value >= length)
                report_diagnostic(LOWERING_DIAGNOSTIC_X86_ARRAY_INDEX_BOUNDS,
                    LOWERING_DIAGNOSTIC_DETAIL_HIR, core.source_hir, core.source_hir);
        }
    }
    uint function_count = min(gParams.semantic_capacity, semantic_lir_function_total[0u]);
    uint owner = semantic_function_id_by_hir[semantic_owner_by_instruction[semantic_row]];
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
                LOWERING_DIAGNOSTIC_DETAIL_TOKEN, detail, function.hir_function);
        }
        else if (entrypoint && function.result_word_count != 0u)
            report_diagnostic(LOWERING_DIAGNOSTIC_X86_ENTRYPOINT_AGGREGATE_RETURN,
                LOWERING_DIAGNOSTIC_DETAIL_TOKEN, function.name_token,
                function.hir_function);
        else if (!entrypoint && function.param_count > 6u)
        {
            uint detail = function.name_token;
            if (function.param_start != INVALID)
                detail = semantic_lir_params[function.param_start + 6u].declaration_id;
            report_diagnostic(LOWERING_DIAGNOSTIC_X86_PARAMETER_REGISTERS,
                LOWERING_DIAGNOSTIC_DETAIL_TOKEN, detail, function.hir_function);
        }
    }
    uint result_words = core.op == SEMANTIC_LIR_OP_CALL &&
        operands.a < function_count ? semantic_lir_functions[operands.a].result_word_count :
        core.op == SEMANTIC_LIR_OP_CALL_SYMBOL ? core.value_word_count : 0u;
    if (core.op == SEMANTIC_LIR_OP_CALL && operands.a < function_count &&
        (semantic_lir_functions[operands.a].flags & SEMANTIC_FUNCTION_FLAG_EXTERN) != 0u)
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_CALL_ABI,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, core.source_hir, core.source_hir);
    if ((core.op == SEMANTIC_LIR_OP_CALL || core.op == SEMANTIC_LIR_OP_CALL_SYMBOL) &&
        result_words != 0u && argument_rows >= 6u)
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_CALL_ABI,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, core.source_hir, core.source_hir);
    if (core.op == SEMANTIC_LIR_OP_CALL_HOST &&
        operands.a != HOST_SERVICE_I32_TO_F32 &&
        !x86_runtime_service_supported(operands.a))
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_CALL_ABI,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, core.source_hir, core.source_hir);
    if (core.op == SEMANTIC_LIR_OP_CALL_SYMBOL &&
        (operands.a == INVALID || operands.b == INVALID || operands.c == INVALID))
        report_diagnostic(LOWERING_DIAGNOSTIC_X86_CALL_ABI,
            LOWERING_DIAGNOSTIC_DETAIL_HIR, core.source_hir, core.source_hir);
    uint return_words = core.op == SEMANTIC_LIR_OP_RETURN && owner < function_count
        ? semantic_lir_functions[owner].result_word_count : 0u;
    uint copy_words = 0u;
    if ((core.op == SEMANTIC_LIR_OP_VALUE_SET ||
         core.op == SEMANTIC_LIR_OP_STORE) &&
        x86_semantic_type_is_aggregate(core) && operands.b < total)
    {
        SemanticLirCore value_core = semantic_lir_core[operands.b];
        SemanticLirOperands value_operands = semantic_lir_operands[operands.b];
        uint call_words = value_core.op == SEMANTIC_LIR_OP_CALL &&
            value_operands.a < function_count
            ? semantic_lir_functions[value_operands.a].result_word_count : 0u;
        copy_words = max(max(core.value_word_count, call_words),
            x86_aggregate_value_word_count(value_core, value_operands));
    }
    uint operation_rows = x86_lir_count(core, operands);
    if (core.op == SEMANTIC_LIR_OP_AGGREGATE_NEW)
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
