import codegen.lir.x86.common;
import codegen.lir.x86.runtime_abi;
import codegen.lowering_ir;
import gpu_index;

struct Params { uint semantic_capacity; uint target_capacity; uint target_start; uint page_capacity; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> semantic_lir_total;
StructuredBuffer<SemanticLirCore> semantic_lir_core;
StructuredBuffer<SemanticLirOperands> semantic_lir_operands;
StructuredBuffer<uint> semantic_lir_layout_word_offset;
StructuredBuffer<uint> semantic_schedule_order;
StructuredBuffer<uint> semantic_owner_by_instruction;
StructuredBuffer<uint> semantic_function_id_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_start_by_hir;
StructuredBuffer<uint> semantic_lir_call_arg_count_by_hir;
StructuredBuffer<SemanticLirCallArg> semantic_lir_call_args;
StructuredBuffer<uint> semantic_lir_aggregate_element_total;
StructuredBuffer<SemanticLirAggregateElement> semantic_lir_aggregate_elements;
StructuredBuffer<uint> semantic_lir_string_total;
StructuredBuffer<uint> semantic_lir_function_total;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> x86_live_by_semantic;
StructuredBuffer<X86ValueAnalysis> x86_value_by_semantic;
StructuredBuffer<X86SelectInfo> x86_select_by_semantic;
StructuredBuffer<uint> target_lir_offset;
StructuredBuffer<uint> target_lir_total;
RWStructuredBuffer<uint> semantic_to_target_start;
RWStructuredBuffer<X86LirCore> target_lir_core;
RWStructuredBuffer<X86LirOperands> target_lir_operands;
RWStructuredBuffer<uint> target_semantic_origin;
RWStructuredBuffer<uint> target_lir_flags;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint TARGET_PAGE_ROWS = 65536u;

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
    return (argument.value_metadata & SEMANTIC_LIR_VALUE_STRING) != 0u
        ? 2u : 1u;
}

uint call_abi_argument_count(uint start, uint count)
{
    uint result = 0u;
    for (uint arg_i = 0u; arg_i < min(count, 6u); arg_i += 1u)
        result += call_argument_width(semantic_lir_call_args[start + arg_i]);
    return result;
}

bool direct_i32_constant(uint semantic_row, uint semantic_count,
                         out uint value)
{
    value = 0u;
    if (semantic_row >= semantic_count) return false;
    X86ValueAnalysis analysis = x86_value_by_semantic[semantic_row];
    value = analysis.value;
    return analysis.known != 0u;
}

void write_call_arg(uint page_row, uint row, uint semantic_row, uint source_hir, uint abi_row,
                    SemanticLirCore source, uint argument_start,
                    uint argument_count, uint call_result_words,
                    uint semantic_count)
{
    SemanticLirCallArg argument;
    argument.call_instruction = INVALID;
    argument.value_instruction = INVALID;
    argument.ordinal = INVALID;
    argument.value_metadata = 0u;
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
    core.source_hir = source_hir;
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
    uint argument_type =
        argument.value_metadata & SEMANTIC_LIR_VALUE_TYPE_MASK;
    bool string_value =
        (argument.value_metadata & SEMANTIC_LIR_VALUE_STRING) != 0u;
    operands.metadata = (argument_type & 0xffu) |
        ((argument.value_metadata & SEMANTIC_LIR_VALUE_AGGREGATE) != 0u
            ? X86_LIR_METADATA_AGGREGATE : 0u) |
        (string_value &&
         component == 0u
            ? X86_LIR_METADATA_WIDE :
         string_value &&
         component == 1u
            ? X86_LIR_METADATA_STRING_LEN : 0u);
    if (argument_type == SEMANTIC_LIR_TY_POINTER)
        operands.metadata |= X86_LIR_METADATA_WIDE;
    uint immediate;
    bool encoded_immediate = !string_value &&
        (argument.value_metadata & SEMANTIC_LIR_VALUE_AGGREGATE) == 0u &&
        x86_scalar_immediate_type(argument_type) &&
        direct_i32_constant(
            argument.value_instruction, semantic_count, immediate);
    if (encoded_immediate)
    {
        operands.a = immediate;
        operands.metadata |= X86_LIR_METADATA_IMMEDIATE;
    }
    target_lir_core[page_row] = core;
    target_lir_operands[page_row] = operands;
    target_semantic_origin[page_row] = semantic_row;
    bool matching_call = argument.call_instruction < gParams.semantic_capacity &&
        semantic_owner_by_instruction[argument.call_instruction] == source_hir &&
        semantic_lir_op(semantic_lir_core[argument.call_instruction]) == semantic_lir_op(source);
    target_lir_flags[page_row] = matching_call &&
        argument.value_instruction < gParams.semantic_capacity &&
        abi_ordinal + sret_shift < 6u
        ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint page_row = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    if (page_row >= gParams.page_capacity) return;
    uint row = gParams.target_start + page_row;
    uint target_total = min(gParams.target_capacity, target_lir_total[0u]);
    if (row >= target_total) return;
    uint semantic_count = min(gParams.semantic_capacity, semantic_lir_total[0u]);
    if (semantic_count == 0u) return;

    uint scheduled_row = scheduled_owner(row, semantic_count);
    uint semantic_row = semantic_schedule_order[scheduled_row];
    uint source_hir = semantic_owner_by_instruction[semantic_row];
    uint target_start = target_lir_offset[scheduled_row];
    SemanticLirCore source = semantic_lir_core[semantic_row];
    // Call-argument rows are an ABI expansion of call instructions only. A
    // loop or control row may share a HIR-indexed workspace slot with a prior
    // call, so do not let stale/non-call metadata manufacture CALL_ARG rows.
    bool is_call = semantic_lir_op(source) == SEMANTIC_LIR_OP_CALL ||
        semantic_lir_op(source) == SEMANTIC_LIR_OP_CALL_SYMBOL ||
        semantic_lir_op(source) == SEMANTIC_LIR_OP_CALL_HOST ||
        semantic_lir_op(source) == SEMANTIC_LIR_OP_CALL_INTRINSIC;
    uint argument_count = is_call
        ? semantic_lir_call_arg_count_by_hir[source_hir] : 0u;
    uint argument_start = semantic_lir_call_arg_start_by_hir[source_hir];
    uint argument_rows = call_abi_argument_count(argument_start, argument_count);
    SemanticLirOperands args = semantic_lir_operands[semantic_row];
    uint function_count = min(gParams.semantic_capacity, semantic_lir_function_total[0u]);
    uint call_result_words = semantic_lir_op(source) == SEMANTIC_LIR_OP_CALL &&
        args.a < function_count ? semantic_lir_functions[args.a].result_word_count :
        semantic_lir_op(source) == SEMANTIC_LIR_OP_CALL_SYMBOL ? source.value_word_count : 0u;
    // A call expands to argument-move rows followed by the value-producing
    // call row. Semantic operands name values, so their target projection must
    // point at the producer rather than the beginning of the expansion.
    semantic_to_target_start[semantic_row] = target_start + argument_rows;
    uint local_row = row - target_start;
    if (local_row < argument_rows)
    {
        write_call_arg(page_row, row, semantic_row, source_hir, local_row, source,
            argument_start, argument_count, call_result_words, semantic_count);
        return;
    }

    uint operation_row = local_row - argument_rows;
    if (call_result_words != 0u && operation_row != 0u)
    {
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row - 1u;
        core.op = X86_LIR_OP_AGGREGATE_RESULT_SLOT;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = target_start + argument_rows;
        operands.b = operation_row - 1u;
        operands.c = call_result_words;
        operands.metadata = source.type_id;
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = 0u;
        return;
    }
    uint owner = semantic_function_id_by_hir[semantic_owner_by_instruction[semantic_row]];
    uint return_words = semantic_lir_op(source) == SEMANTIC_LIR_OP_RETURN && owner < function_count
        ? semantic_lir_functions[owner].result_word_count : 0u;
    if (return_words != 0u && operation_row < return_words)
    {
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row;
        core.op = X86_LIR_OP_AGGREGATE_RETURN_WORD;
        core.result_or_target = INVALID;
        X86LirOperands operands;
        operands.a = args.a;
        operands.b = operation_row;
        operands.c = return_words;
        operands.metadata = source.type_id;
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = args.a < gParams.semantic_capacity
            ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    uint copy_words = 0u;
    if ((semantic_lir_op(source) == SEMANTIC_LIR_OP_VALUE_SET ||
         semantic_lir_op(source) == SEMANTIC_LIR_OP_STORE) &&
        x86_semantic_type_is_aggregate(source) && args.b < semantic_count)
    {
        SemanticLirCore value_core = semantic_lir_core[args.b];
        SemanticLirOperands value_operands = semantic_lir_operands[args.b];
        uint call_words = semantic_lir_op(value_core) == SEMANTIC_LIR_OP_CALL &&
            value_operands.a < function_count
            ? semantic_lir_functions[value_operands.a].result_word_count : 0u;
        copy_words = max(max(source.value_word_count, call_words),
            x86_aggregate_value_word_count(value_core, value_operands));
    }
    if (copy_words != 0u && operation_row != 0u)
    {
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row - 1u;
        core.op = X86_LIR_OP_AGGREGATE_COPY_WORD;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = args.b;
        operands.b = operation_row - 1u;
        operands.c = copy_words;
        operands.metadata = source.type_id;
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = args.b < gParams.semantic_capacity &&
            operation_row <= copy_words ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    if (semantic_lir_op(source) == SEMANTIC_LIR_OP_AGGREGATE_NEW && operation_row != 0u)
    {
        uint word = operation_row - 1u;
        bool enum_discriminant =
            (args.c & SEMANTIC_LIR_AGGREGATE_ENUM) != 0u && word == 0u;
        SemanticLirAggregateElement element;
        element.aggregate_instruction = INVALID;
        element.value_instruction = INVALID;
        element.ordinal = INVALID;
        element.name_token = INVALID;
        element.value_metadata = 0u;
        element.word_offset = INVALID;
        element.word_count = 0u;
        uint element_total = semantic_lir_aggregate_element_total[0u];
        for (uint element_i = 0u; element_i < args.b; element_i += 1u)
        {
            uint element_row = args.a + element_i;
            if (element_row >= element_total) break;
            SemanticLirAggregateElement candidate =
                semantic_lir_aggregate_elements[element_row];
            if (word >= candidate.word_offset &&
                word - candidate.word_offset < candidate.word_count)
            {
                element = candidate;
                break;
            }
        }
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row;
        core.op = X86_LIR_OP_AGGREGATE_INIT;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = element.value_instruction;
        operands.b = word - element.word_offset;
        operands.c = target_start + 1u + word;
        uint element_type = element.value_instruction <
            gParams.semantic_capacity
                ? semantic_lir_core[element.value_instruction].type_id
                : source.type_id;
        operands.metadata = element_type |
            ((element.value_metadata & SEMANTIC_LIR_VALUE_AGGREGATE) != 0u
                ? X86_LIR_METADATA_AGGREGATE : 0u);
        if (enum_discriminant)
        {
            operands.a = args.c & SEMANTIC_LIR_AGGREGATE_TAG_MASK;
            operands.b = 0u;
            operands.metadata = source.type_id | X86_LIR_METADATA_IMMEDIATE;
        }
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = enum_discriminant ? 0u :
            element.aggregate_instruction == semantic_row &&
            element.value_instruction < gParams.semantic_capacity &&
            element.word_offset != INVALID && word >= element.word_offset &&
            word - element.word_offset < element.word_count
                ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    if (semantic_lir_op(source) == SEMANTIC_LIR_OP_CONST_STRING)
    {
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row;
        core.op = operation_row == 0u ? X86_LIR_OP_STRING_ADDR : X86_LIR_OP_STRING_LEN;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = args.a;
        operands.b = 0u;
        operands.c = 0u;
        operands.metadata = source.type_id;
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = args.a < semantic_lir_string_total[0u]
            ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    if (semantic_lir_op(source) == SEMANTIC_LIR_OP_VALUE_GET &&
        source.type_id == SEMANTIC_LIR_TY_STRING)
    {
        X86LirCore core;
        core.source_hir = source_hir;
        core.local_ordinal = operation_row;
        core.op = X86_LIR_OP_ALIAS;
        core.result_or_target = row;
        X86LirOperands operands;
        operands.a = args.a;
        operands.b = 0u;
        operands.c = operation_row;
        operands.metadata = source.type_id | X86_LIR_METADATA_STRING_PAIR |
            (operation_row == 1u ? X86_LIR_METADATA_STRING_LEN : 0u);
        target_lir_core[page_row] = core;
        target_lir_operands[page_row] = operands;
        target_semantic_origin[page_row] = semantic_row;
        target_lir_flags[page_row] = operation_row < 2u
            ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
        return;
    }
    uint op = x86_lir_opcode(source);
    uint result = args.result;
    uint a = args.a;
    uint b = args.b;
    uint c = args.c;
    uint local_ordinal = 0u;
    uint flags = x86_lir_supported(source) ? 0u : TARGET_LIR_FLAG_UNSUPPORTED;
    if ((source.flags & (SEMANTIC_LIR_FLAG_UNSUPPORTED |
                         SEMANTIC_LIR_FLAG_UNSUPPORTED_FOR_ITERABLE)) != 0u)
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    if ((semantic_lir_op(source) == SEMANTIC_LIR_OP_VALUE_SET ||
         semantic_lir_op(source) == SEMANTIC_LIR_OP_STORE) &&
        x86_semantic_type_is_aggregate(source) &&
        source.value_word_count != 0u && copy_words == 0u)
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    if (semantic_lir_op(source) == SEMANTIC_LIR_OP_CALL_HOST &&
        (args.a == HOST_SERVICE_I32_TO_F32 || x86_runtime_service_supported(args.a)))
        flags = 0u;
    if (semantic_lir_op(source) == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
        args.a != 1u && args.a != INTRINSIC_I32_ARRAY_DATA_PTR)
        flags = TARGET_LIR_FLAG_UNSUPPORTED;
    uint metadata = (source.type_id & 0xffu) | (source.flags << 8u) |
        (x86_semantic_type_is_aggregate(source) ? X86_LIR_METADATA_AGGREGATE : 0u);
    if ((semantic_lir_op(source) == SEMANTIC_LIR_OP_VALUE_SET ||
         semantic_lir_op(source) == SEMANTIC_LIR_OP_STORE) &&
        source.type_id == SEMANTIC_LIR_TY_STRING)
        metadata |= X86_LIR_METADATA_STRING_PAIR;

    bool select_store =
        x86_live_by_semantic[semantic_row] == X86_SEMANTIC_SELECT;
    uint propagated_value = 0u;
    bool propagated_constant = direct_i32_constant(
        semantic_row, semantic_count, propagated_value);
    if (select_store)
    {
        X86SelectInfo info = x86_select_by_semantic[semantic_row];
        if (info.condition >= semantic_count ||
            info.true_value >= semantic_count ||
            info.declaration == INVALID)
        {
            flags |= TARGET_LIR_FLAG_UNSUPPORTED;
        }
        else
        {
            SemanticLirCore compare_core = semantic_lir_core[info.condition];
            SemanticLirOperands compare = semantic_lir_operands[info.condition];
            uint left = 0u;
            uint immediate = 0u;
            bool left_constant = direct_i32_constant(
                compare.a, semantic_count, left);
            bool right_constant = direct_i32_constant(
                compare.b, semantic_count, immediate);
            bool immediate_compare = (right_constant || left_constant) &&
                x86_integer_immediate_operation(
                    SEMANTIC_LIR_OP_COMPARE, compare_core.type_id,
                    right_constant ? immediate : left);
            op = X86_LIR_OP_SELECT_STORE;
            result = info.declaration;
            a = immediate_compare && left_constant
                ? compare.b : compare.a;
            b = immediate_compare
                ? (right_constant ? immediate : left) : compare.b;
            c = info.true_value;
            metadata = compare_core.type_id & 0xffu;
            if (immediate_compare)
                metadata |= X86_LIR_METADATA_IMMEDIATE;
            local_ordinal = immediate_compare && left_constant
                ? x86_swapped_compare_predicate(compare.c) : compare.c;
        }
    }
    else if (propagated_constant)
    {
        op = X86_LIR_OP_IMM_I32;
        a = propagated_value;
        b = 0u;
        c = 0u;
    }
    else if (semantic_lir_op(source) == SEMANTIC_LIR_OP_CALL_INTRINSIC &&
             args.a == INTRINSIC_I32_ARRAY_DATA_PTR)
    {
        op = X86_LIR_OP_INTRINSIC_IDENTITY;
        a = 0u; b = 0u; c = 0u;
    }
    else if (op == X86_LIR_OP_AGGREGATE_ADDR)
    {
        a = target_start + 1u;
        b = args.b;
        c = 0u;
    }
    else if (op == X86_LIR_OP_INDEX_LOAD)
    {
        a = args.a;
        b = args.b;
        c = max(source.value_word_count, 1u);
    }
    else if (op == X86_LIR_OP_FIELD_LOAD)
    {
        a = args.a;
        b = semantic_lir_layout_word_offset[semantic_row];
        c = args.c;
    }
    else if (op == X86_LIR_OP_INDEX_STORE)
    {
        a = args.a;
        b = args.b;
        c = args.c;
    }
    else if (op == X86_LIR_OP_FIELD_STORE)
    {
        a = args.a;
        b = semantic_lir_layout_word_offset[semantic_row];
        c = args.c;
        metadata = (metadata & 0x00ffffffu) | (8u << 24u);
    }
    else if (op == X86_LIR_OP_BINARY)
    {
        uint semantic_op = semantic_lir_op(source);
        uint left = 0u;
        uint immediate = 0u;
        uint folded = 0u;
        c = args.b;
        b = args.a;
        a = x86_binary_payload(source);
        bool left_constant = direct_i32_constant(
            args.a, semantic_count, left);
        bool right_constant = direct_i32_constant(
            args.b, semantic_count, immediate);
        if (left_constant && right_constant &&
            x86_fold_integer_binary(semantic_op, source.type_id, args.c,
                left, immediate, folded))
        {
            op = X86_LIR_OP_IMM_I32;
            a = folded;
            b = 0u;
            c = 0u;
        }
        uint divisor_kind = op != X86_LIR_OP_IMM_I32 && right_constant
                ? x86_constant_divisor_kind(
                    semantic_op, source.type_id, immediate)
                : X86_CONSTANT_DIVISOR_NONE;
        if (divisor_kind == X86_CONSTANT_DIVISOR_POWER_OF_TWO)
        {
            a = semantic_op == SEMANTIC_LIR_OP_DIV
                ? X86_LIR_BINARY_DIV_CONST_POW2_I32
                : X86_LIR_BINARY_REM_CONST_POW2_I32;
            c = immediate;
        }
        else if (divisor_kind == X86_CONSTANT_DIVISOR_SIGNED)
        {
            a = semantic_op == SEMANTIC_LIR_OP_DIV
                ? X86_LIR_BINARY_DIV_CONST_I32
                : X86_LIR_BINARY_REM_CONST_I32;
            c = immediate;
        }
        else if (op != X86_LIR_OP_IMM_I32 &&
                 ((right_constant && x86_integer_immediate_operation(
                     semantic_op, source.type_id, immediate)) ||
                  (left_constant &&
                   x86_integer_immediate_commutative(semantic_op) &&
                   x86_integer_immediate_operation(
                       semantic_op, source.type_id, left))))
        {
            bool swap = !right_constant;
            b = swap ? args.b : args.a;
            c = swap ? left : immediate;
            metadata |= X86_LIR_METADATA_IMMEDIATE;
        }
    }
    else if (op == X86_LIR_OP_COMPARE)
    {
        c = args.b; b = args.a; a = args.c;
        uint left = 0u;
        uint immediate = 0u;
        uint folded = 0u;
        bool left_constant = direct_i32_constant(
            args.a, semantic_count, left);
        bool right_constant = direct_i32_constant(
            args.b, semantic_count, immediate);
        if (left_constant && right_constant &&
            x86_fold_integer_binary(SEMANTIC_LIR_OP_COMPARE, source.type_id,
                args.c, left, immediate, folded))
        {
            op = X86_LIR_OP_IMM_I32;
            a = folded;
            b = 0u;
            c = 0u;
        }
        else if ((right_constant || left_constant) &&
            x86_integer_immediate_operation(
                SEMANTIC_LIR_OP_COMPARE, source.type_id,
                right_constant ? immediate : left))
        {
            bool swap = !right_constant;
            a = swap ? x86_swapped_compare_predicate(args.c) : args.c;
            b = swap ? args.b : args.a;
            c = swap ? left : immediate;
            metadata |= X86_LIR_METADATA_IMMEDIATE;
        }
        if (source.type_id == SEMANTIC_LIR_TY_POINTER && args.b < gParams.semantic_capacity &&
            semantic_lir_core[args.b].type_id != SEMANTIC_LIR_TY_POINTER)
            metadata |= X86_LIR_METADATA_RHS_NARROW;
    }
    else if (op == X86_LIR_OP_UNARY)
    {
        uint folded;
        uint input;
        if (direct_i32_constant(args.a, semantic_count, input) &&
            x86_fold_integer_unary(
                semantic_lir_op(source), source.type_id, input, folded))
        {
            op = X86_LIR_OP_IMM_I32;
            a = folded; b = 0u; c = 0u;
        }
        else
        {
            a = semantic_lir_op(source) == SEMANTIC_LIR_OP_LOGICAL_NOT ? X86_LIR_UNARY_NOT_BOOL
                : source.type_id == X86_LIR_TY_FLOAT ? X86_LIR_UNARY_NEG_F32
                : X86_LIR_UNARY_NEG_I32;
            b = args.a; c = 0u;
        }
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
        bool conditional = semantic_lir_op(source) == SEMANTIC_LIR_OP_IF_BEGIN ||
            semantic_lir_op(source) == SEMANTIC_LIR_OP_BRANCH_IF;
        uint condition = conditional ? args.a : INVALID;
        uint comparison = condition;
        if (x86_live_by_semantic[semantic_row] ==
            X86_SEMANTIC_COMPARE_ALIAS_BRANCH)
            comparison = x86_select_by_semantic[semantic_row].condition;
        bool fused_compare = comparison < semantic_count &&
            x86_live_by_semantic[comparison] == 0u &&
            semantic_lir_op(semantic_lir_core[comparison]) ==
                SEMANTIC_LIR_OP_COMPARE;
        if (fused_compare)
        {
            SemanticLirCore compare_core = semantic_lir_core[comparison];
            SemanticLirOperands compare = semantic_lir_operands[comparison];
            uint left = 0u;
            uint immediate = 0u;
            bool left_constant = direct_i32_constant(
                compare.a, semantic_count, left);
            bool right_constant = direct_i32_constant(
                compare.b, semantic_count, immediate);
            bool immediate_compare = (right_constant || left_constant) &&
                x86_integer_immediate_operation(
                    SEMANTIC_LIR_OP_COMPARE, compare_core.type_id,
                    right_constant ? immediate : left);
            op = X86_LIR_OP_COMPARE_BRANCH_FALSE;
            a = immediate_compare && left_constant
                ? compare.b : compare.a;
            b = immediate_compare
                ? (right_constant ? immediate : left) : compare.b;
            c = semantic_lir_op(source) == SEMANTIC_LIR_OP_IF_BEGIN
                ? args.c : 0u;
            metadata = compare_core.type_id & 0xffu;
            if (immediate_compare)
                metadata |= X86_LIR_METADATA_IMMEDIATE;
            local_ordinal = immediate_compare && left_constant
                ? x86_swapped_compare_predicate(compare.c) : compare.c;
            if (compare_core.type_id == SEMANTIC_LIR_TY_POINTER &&
                compare.b < semantic_count &&
                semantic_lir_core[compare.b].type_id !=
                    SEMANTIC_LIR_TY_POINTER)
                metadata |= X86_LIR_METADATA_RHS_NARROW;
            result = semantic_lir_op(source) == SEMANTIC_LIR_OP_IF_BEGIN
                ? args.b : args.c;
        }
        else if (semantic_lir_op(source) == SEMANTIC_LIR_OP_IF_BEGIN) { a = args.a; b = args.b; c = args.c; }
        else if (semantic_lir_op(source) == SEMANTIC_LIR_OP_BRANCH_IF) { a = args.a; b = args.c; c = 0u; }
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
        c = call_result_words;
    else if ((op == X86_LIR_OP_CALL || op == X86_LIR_OP_CALL_SYMBOL) &&
             call_result_words == 0u &&
             (metadata & X86_LIR_METADATA_AGGREGATE) != 0u)
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;
    if ((op == X86_LIR_OP_BRANCH && b == INVALID) ||
        (op == X86_LIR_OP_COMPARE_BRANCH_FALSE && result == INVALID))
        flags |= TARGET_LIR_FLAG_UNSUPPORTED;

    X86LirCore core;
    core.source_hir = source_hir;
    core.local_ordinal = op == X86_LIR_OP_COMPARE_BRANCH_FALSE ||
        op == X86_LIR_OP_SELECT_STORE
        ? local_ordinal
        : (op == X86_LIR_OP_INDEX_LOAD || op == X86_LIR_OP_INDEX_STORE)
        ? semantic_lir_layout_word_offset[semantic_row]
        : op == X86_LIR_OP_CALL_SYMBOL ? call_result_words : 0u;
    core.op = op;
    // `result` is a semantic instruction identity. The target stream may
    // have inserted CALL_ARG rows before this operation, so machine emission
    // must address the concrete target row for the result value and any
    // caller-owned aggregate storage derived from it.
    core.result_or_target = op == X86_LIR_OP_COMPARE_BRANCH_FALSE ||
        op == X86_LIR_OP_SELECT_STORE
        ? result : result == INVALID ? INVALID : row;
    X86LirOperands operands;
    operands.a = a;
    operands.b = b;
    operands.c = c;
    operands.metadata = metadata;
    target_lir_core[page_row] = core;
    target_lir_operands[page_row] = operands;
    target_semantic_origin[page_row] = semantic_row;
    target_lir_flags[page_row] = flags;
}
