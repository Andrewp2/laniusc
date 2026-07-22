import codegen.lir.x86.common;
import codegen.lir.x86.runtime_abi;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint target_capacity; uint reserved0; uint reserved1; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirOperands> semantic_lir_operands;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<SemanticLirSchedule> semantic_lir_schedule;
StructuredBuffer<uint> semantic_lir_call_arg_start_by_instruction;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_instruction;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
StructuredBuffer<uint> semantic_lir_string_total;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> target_lir_offset;
StructuredBuffer<uint> target_lir_total;
RWStructuredBuffer<uint> semantic_to_target_start;
RWStructuredBuffer<X86LirCore> target_lir_core;
RWStructuredBuffer<X86LirOperands> target_lir_operands;
RWStructuredBuffer<uint> target_semantic_origin;
RWStructuredBuffer<uint> target_lir_flags;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint scheduled_owner(uint target_row, uint semantic_count)
{
    uint lo = 0u;
    uint hi = semantic_count;
    while (lo + 1u < hi)
    {
        uint mid = lo + (hi - lo) / 2u;
        if (target_lir_offset[mid] <= target_row) lo = mid;
        else hi = mid;
    }
    return lo;
}

uint call_argument_width(SemanticLirCallArg argument)
{
    if (argument.value_instruction >= gParams.semantic_capacity) return 1u;
    return x86_semantic_type_is_string(
        semantic_lir_core[argument.value_instruction]) ? 2u : 1u;
}

uint call_abi_argument_count(uint start, uint count)
{
    uint result = 0u;
    for (uint arg_i = 0u; arg_i < min(count, 6u); arg_i += 1u)
        result += call_argument_width(semantic_lir_call_args[start + arg_i]);
    return result;
}

void write_call_arg(uint row, uint semantic_row, uint abi_row,
                    SemanticLirCore source, uint argument_start,
                    uint argument_count, uint call_result_words)
{
    SemanticLirCallArg argument;
    argument.call_instruction = INVALID;
    argument.value_instruction = INVALID;
    argument.ordinal = INVALID;
    argument.flags = 0u;
    uint component = 0u;
    uint abi_ordinal = 0u;
    uint cursor = 0u;
    for (uint arg_i = 0u; arg_i < min(argument_count, 6u); arg_i += 1u)
    {
        SemanticLirCallArg candidate = semantic_lir_call_args[argument_start + arg_i];
        uint width = call_argument_width(candidate);
        if (abi_row >= cursor && abi_row < cursor + width)
        {
            argument = candidate;
            component = abi_row - cursor;
            abi_ordinal = cursor + component;
            break;
        }
        cursor += width;
    }
    X86LirCore core;
    core.source_hir = source.source_hir;
    uint sret_shift = call_result_words > 2u ? 1u : 0u;
    core.local_ordinal = abi_ordinal + sret_shift;
    core.op = X86_LIR_OP_CALL_ARG;
    core.result_or_target = INVALID;
    X86LirOperands operands;
    operands.a = argument.value_instruction;
    operands.b = abi_ordinal + sret_shift;
    operands.c = component;
    // Carry the checked semantic value type through target resolution. The
    // emitter uses this target-IR fact to choose word- versus dword-sized ABI
    // moves without chasing the source expression's producer shape.
    SemanticLirCore argument_core;
    argument_core.op = 0u;
    argument_core.type_id = 0u;
    argument_core.type_ref_tag = SEMANTIC_TYPE_REF_INVALID;
    argument_core.type_ref_payload = INVALID;
    argument_core.source_hir = INVALID;
    argument_core.flags = 0u;
    if (argument.value_instruction < gParams.semantic_capacity)
        argument_core = semantic_lir_core[argument.value_instruction];
    uint argument_type = argument_core.type_id;
    operands.metadata = (argument_type & 0xffu) |
        (x86_semantic_type_is_aggregate(argument_core)
            ? X86_LIR_METADATA_AGGREGATE : 0u) |
        (x86_semantic_type_is_string(argument_core) && component == 0u
            ? X86_LIR_METADATA_WIDE : 0u);
    target_lir_core[row] = core;
    target_lir_operands[row] = operands;
    target_semantic_origin[row] = semantic_row;
    target_lir_flags[row] = argument.call_instruction == semantic_row &&
        argument.value_instruction < gParams.semantic_capacity &&
        abi_ordinal + sret_shift < 6u
        ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint target_total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= target_total) return;
    uint semantic_count = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    if (semantic_count == 0u) return;

    uint scheduled_row = scheduled_owner(row, semantic_count);
    uint semantic_row = semantic_schedule_order[scheduled_row];
    uint target_start = target_lir_offset[scheduled_row];
    SemanticLirCore source = semantic_lir_core[semantic_row];
    uint argument_count = semantic_lir_call_arg_count_by_instruction[semantic_row];
    uint argument_start = semantic_lir_call_arg_start_by_instruction[semantic_row];
    uint argument_rows = call_abi_argument_count(argument_start, argument_count);
    SemanticLirOperands args = semantic_lir_operands[semantic_row];
    uint function_count = min(gParams.semantic_capacity, semantic_lir_function_total[0u]);
    uint call_result_words = source.op == SEMANTIC_LIR_OP_CALL &&
        args.a < function_count ? semantic_lir_functions[args.a].result_word_count : 0u;
    // A call expands to argument-move rows followed by the value-producing
    // call row. Semantic operands name values, so their target projection must
    // point at the producer rather than the beginning of the expansion.
    semantic_to_target_start[semantic_row] = target_start + argument_rows;
    uint local_row = row - target_start;
    if (local_row < argument_rows)
    {
        write_call_arg(row, semantic_row, local_row, source,
            argument_start, argument_count, call_result_words);
        return;
    }

    uint operation_row = local_row - argument_rows;
    if (call_result_words != 0u && operation_row != 0u)
    {
        X86LirCore core;
        core.source_hir = source.source_hir;
        core.local_ordinal = operation_row - 1u;
        core.op = X86_LIR_OP_AGGREGATE_RESULT_SLOT;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = target_start + argument_rows;
        operands.b = operation_row - 1u;
        operands.c = call_result_words;
        operands.metadata = source.type_id;
        target_lir_core[row] = core;
        target_lir_operands[row] = operands;
        target_semantic_origin[row] = semantic_row;
        target_lir_flags[row] = 0u;
        return;
    }
    uint owner = semantic_lir_schedule[semantic_row].function_id;
    uint return_words = source.op == SEMANTIC_LIR_OP_RETURN && owner < function_count
        ? semantic_lir_functions[owner].result_word_count : 0u;
    if (return_words != 0u && operation_row < return_words)
    {
        X86LirCore core;
        core.source_hir = source.source_hir;
        core.local_ordinal = operation_row;
        core.op = X86_LIR_OP_AGGREGATE_RETURN_WORD;
        core.result_or_target = INVALID;
        X86LirOperands operands;
        operands.a = args.a;
        operands.b = operation_row;
        operands.c = return_words;
        operands.metadata = source.type_id;
        target_lir_core[row] = core;
        target_lir_operands[row] = operands;
        target_semantic_origin[row] = semantic_row;
        target_lir_flags[row] = args.a < gParams.semantic_capacity ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    if (source.op == SEMANTIC_LIR_OP_AGGREGATE_NEW && operation_row != 0u)
    {
        uint element_row = args.a + operation_row - 1u;
        SemanticLirAggregateElement element;
        element.aggregate_instruction = INVALID;
        element.value_instruction = INVALID;
        element.ordinal = INVALID;
        element.name_token = INVALID;
        uint element_total = semantic_lir_aggregate_element_total[0u];
        if (element_row < element_total)
            element = semantic_lir_aggregate_elements[element_row];
        X86LirCore core;
        core.source_hir = source.source_hir;
        core.local_ordinal = operation_row;
        core.op = X86_LIR_OP_ARRAY_INIT;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = element.value_instruction;
        operands.b = element.ordinal;
        operands.c = target_start + 1u + element.ordinal;
        operands.metadata = source.type_id;
        target_lir_core[row] = core;
        target_lir_operands[row] = operands;
        target_semantic_origin[row] = semantic_row;
        target_lir_flags[row] = element.aggregate_instruction == semantic_row &&
            element.value_instruction < gParams.semantic_capacity &&
            element.ordinal < args.b ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    if (source.op == SEMANTIC_LIR_OP_CONST_STRING)
    {
        X86LirCore core;
        core.source_hir = source.source_hir;
        core.local_ordinal = operation_row;
        core.op = operation_row == 0u ? X86_LIR_OP_STRING_ADDR : X86_LIR_OP_STRING_LEN;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = args.a;
        operands.b = 0u;
        operands.c = 0u;
        operands.metadata = source.type_id;
        target_lir_core[row] = core;
        target_lir_operands[row] = operands;
        target_semantic_origin[row] = semantic_row;
        target_lir_flags[row] = args.a < semantic_lir_string_total[0u]
            ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    uint op = x86_lir_opcode(source);
    uint result = args.result;
    uint a = args.a;
    uint b = args.b;
    uint c = args.c;
    uint flags = x86_lir_supported(source) ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
    if (source.op == SEMANTIC_LIR_OP_CALL_HOST &&
        (args.a == HOST_SERVICE_I32_TO_F32 || x86_runtime_service_supported(args.a)))
        flags = 0u;
    if (source.op == SEMANTIC_LIR_OP_CALL_INTRINSIC && args.a != 1u)
        flags = TARGET_LIR_FLAG_UNSUPPORTED;
    uint metadata = (source.type_id & 0xffu) | (source.flags << 8u) |
        (x86_semantic_type_is_aggregate(source) ? X86_LIR_METADATA_AGGREGATE : 0u);

    if (op == X86_LIR_OP_IMM_I32) { a = args.a; b = 0u; c = 0u; }
    else if (op == X86_LIR_OP_ARRAY_ADDR)
    {
        a = target_start + 1u;
        b = args.b;
        c = 0u;
    }
    else if (op == X86_LIR_OP_INDEX_LOAD)
    {
        a = args.a;
        b = args.b;
        c = 8u;
    }
    else if (op == X86_LIR_OP_FIELD_LOAD)
    {
        a = args.a;
        b = args.b;
        // x86 aggregates currently live in descending eight-byte frame value
        // slots. This concrete stride is deliberately target LIR metadata;
        // semantic LIR carries only the canonical field ordinal.
        c = 8u;
    }
    else if (op == X86_LIR_OP_BINARY) { c = args.b; b = args.a; a = x86_binary_payload(source); }
    else if (op == X86_LIR_OP_COMPARE) { c = args.b; b = args.a; a = args.c; }
    else if (op == X86_LIR_OP_UNARY)
    {
        a = source.op == SEMANTIC_LIR_OP_LOGICAL_NOT ? X86_LIR_UNARY_NOT_BOOL
            : source.type_id == X86_LIR_TY_FLOAT ? X86_LIR_UNARY_NEG_F32
            : X86_LIR_UNARY_NEG_I32;
        b = args.a; c = 0u;
    }
    else if (op == X86_LIR_OP_RETURN)
    {
        result = INVALID; a = return_words == 0u ? args.a : INVALID;
        b = 0u; c = return_words;
        if (a == INVALID) op = X86_LIR_OP_RETURN_VOID;
        if (return_words != 0u) op = X86_LIR_OP_RETURN;
    }
    else if (op == X86_LIR_OP_BRANCH)
    {
        result = INVALID;
        if (source.op == SEMANTIC_LIR_OP_IF_BEGIN) { a = args.a; b = args.b; c = args.c; }
        else if (source.op == SEMANTIC_LIR_OP_BRANCH_IF) { a = args.a; b = args.c; c = 0u; }
        else { a = INVALID; b = args.a; c = 0u; }
    }
    else if (op == X86_LIR_OP_LABEL)
    {
        result = INVALID; a = 0u; b = 0u; c = 0u;
    }
    else if ((op == X86_LIR_OP_CALL || op == X86_LIR_OP_CALL_HOST ||
              op == X86_LIR_OP_PRINT_I32) && args.a == INVALID)
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    if (op == X86_LIR_OP_CALL && call_result_words != 0u)
    {
        c = call_result_words;
    }
    else if (op == X86_LIR_OP_CALL &&
             (metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    if (op == X86_LIR_OP_BRANCH && b == INVALID) flags |= TARGET_LIR_FLAG_UNSUPPORTED;

    X86LirCore core;
    core.source_hir = source.source_hir;
    core.local_ordinal = 0u;
    core.op = op;
    core.result_or_target = result;
    X86LirOperands operands;
    operands.a = a;
    operands.b = b;
    operands.c = c;
    operands.metadata = metadata;
    target_lir_core[row] = core;
    target_lir_operands[row] = operands;
    target_semantic_origin[row] = semantic_row;
    target_lir_flags[row] = flags;
}
