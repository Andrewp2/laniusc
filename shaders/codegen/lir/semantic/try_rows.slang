// The rows of `value?` (HIR_TRY_EXPR), written over the scatter's after it
// ran. count reserves SEMANTIC_TRY_ROW_COUNT rows; the value is the last.
//
//  0 VALUE_SET  tmp = operand          (the operand enum's address)
//  1 VALUE_GET  tmp
//  2 LOAD       tag, word 0
//  3 CONST_I32  1                      (Err and None are ordinal 1)
//  4 COMPARE    tag == 1
//  5 IF_BEGIN   4, end 10
//  6 VALUE_GET  tmp                    (Option: NOP)
//  7 LOAD       error, word 1          (Option: NOP)
//  8 AGGREGATE_NEW Err(error) / None of the function's result type
//  9 RETURN     8
// 10 CONTROL_END
// 11 VALUE_GET  tmp
// 12 LOAD       payload, word 1        (the expression's value)
//
// Row 8's one element is the try segment of aggregate_elements. tmp is the
// node's synthetic local n_tokens + node (local_scatter), as for a match.
import primitive_types;
import native_value_layout;
import type_checker.checked_type_graph;
import hir_records;
import codegen.lir.semantic.common;
import codegen.lir.schedule.common;
import codegen.lowering_ir;
import gpu_index;

struct Params
{
    uint n_hir_nodes;
    uint lir_capacity;
    uint n_tokens;
    uint resident_rows;
    uint schedule_packed_bits;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_expr_root;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<uint> compact_call_arg_count;
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
StructuredBuffer<uint> semantic_aggregate_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_word_count_by_hir;
StructuredBuffer<uint> type_instance_native_words;
StructuredBuffer<uint> semantic_function_id;
StructuredBuffer<SemanticLirFunction> semantic_lir_functions;
StructuredBuffer<uint> semantic_execution_rank;
StructuredBuffer<uint> semantic_lir_count;
StructuredBuffer<uint> semantic_lir_offset;
StructuredBuffer<uint> semantic_lir_value_row_by_hir;
RWStructuredBuffer<SemanticLirCore> semantic_lir_core;
RWStructuredBuffer<SemanticLirOperands> semantic_lir_operands;
RWStructuredBuffer<uint> semantic_lir_layout_word_offset;
RWStructuredBuffer<TargetScheduleKey> semantic_lir_schedule;

static const uint DISPATCH_X_STRIDE = 16776960u;

// The operand's own value row. Its expression root is the `?` itself, so the
// root is only a fallback for an operand without rows of its own.
uint value_row(uint node, uint try_node, uint hir_count)
{
    if (node >= hir_count) return LIR_INVALID;
    uint row = semantic_lir_value_row_by_hir[node];
    if (row != LIR_INVALID) return semantic_lir_offset[node] + row;
    uint root = compact_expr_root[node];
    if (root >= hir_count || root == try_node) return LIR_INVALID;
    row = semantic_lir_value_row_by_hir[root];
    return row != LIR_INVALID ? semantic_lir_offset[root] + row : LIR_INVALID;
}

// The machine class and word count of a checked reference, as scatter
// gives value rows: scalars are their code with no words, aggregates class 0.
uint2 reference_layout(uint tag, uint payload, uint hir_count)
{
    if (tag == 1u)
    {
        if (payload == SEMANTIC_LIR_TY_STRING) return uint2(payload, 2u);
        if (payload < 128u) return uint2(payload, 0u);
        uint token = payload >= 4096u ? (payload >= 6144u ? payload - 6144u : payload - 4096u)
            : LIR_INVALID;
        uint declaration = token < gParams.n_tokens
            ? semantic_aggregate_hir_by_name_token[token] : LIR_INVALID;
        return uint2(payload, declaration < hir_count
            ? semantic_struct_word_count_by_hir[declaration] : 0u);
    }
    if (tag == 3u && payload < checked_type_capacity())
    {
        if (type_instance_kind[payload] == 4u) return uint2(SEMANTIC_LIR_TY_POINTER, 0u);
        return uint2(0u, type_instance_kind[payload] == 3u
            ? NATIVE_SLICE_WORDS : type_instance_native_words[payload]);
    }
    return uint2(0u, 0u);
}

SemanticLirCore row_core(uint op, uint tag, uint payload, uint2 layout, uint flags)
{
    SemanticLirCore core;
    core.type_id = layout.x;
    core.type_ref_payload = payload;
    core.flags = flags | (op << SEMANTIC_LIR_OP_SHIFT) |
        (tag << SEMANTIC_LIR_TYPE_REF_TAG_SHIFT);
    core.value_word_count = layout.y;
    return core;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (node >= hir_count || compact_hir_core[node].kind != HIR_TRY_EXPR ||
        semantic_lir_count[node] < SEMANTIC_TRY_ROW_COUNT) return;
    HirCore hir = compact_hir_core[node];
    uint operand = compact_hir_payload[node].b;
    uint first = semantic_lir_offset[node];
    uint tmp = gParams.n_tokens + node;

    // The operand's Result<T, E> or Option<T>, the function's result type.
    uint instance = operand < hir_count && semantic_expr_ref_tag[operand] == 3u
        ? semantic_expr_ref_payload[operand] : LIR_INVALID;
    bool result_form = instance < checked_type_capacity() && type_instance_arg_count[instance] == 2u;
    uint error_tag = 0u; uint error = LIR_INVALID;
    bool valid = instance < checked_type_capacity() &&
        (!result_form || ScopedCheckedTypeGraph.argument(instance, 1u, error_tag, error));
    uint function_id = semantic_function_id[node];
    SemanticLirFunction function = semantic_lir_functions[function_id < 0xffffffffu ? function_id : 0u];
    // The targets read only the instance tag of an aggregate row; its width
    // is the function's checked result width. The operand stands in for the
    // function's own instance, which this pass has no binding for.
    uint return_tag = 3u;
    uint return_payload = instance;
    uint operand_row = value_row(operand, node, hir_count);
    valid = valid && function_id != LIR_INVALID && operand_row != LIR_INVALID;
    uint element = compact_array_element_row_count[0u] + compact_field_count[0u] +
        compact_call_arg_count[0u] + node;
    uint2 pointer = uint2(SEMANTIC_LIR_TY_POINTER, 0u);
    uint2 tag_layout = uint2(3u, 0u);
    uint2 error_layout = reference_layout(error_tag, error, hir_count);
    uint2 value_layout = reference_layout(semantic_expr_ref_tag[node], semantic_expr_ref_payload[node], hir_count);
    uint2 return_layout = uint2(function.result_type, function.result_word_count);

    // Rows past the 13 (an argument snapshot, projection loads) keep their
    // scatter contents but must follow row 12 in this schedule.
    uint row_count = min(semantic_lir_count[node], 128u);
    for (uint local_row = 0u; local_row < row_count; local_row++)
    {
        if (local_row >= SEMANTIC_TRY_ROW_COUNT)
        {
            uint appended = first + local_row;
            SemanticLirSchedule tail;
            tail.execution_region = hir.token_end > hir.token_start ? hir.token_end - 1u : hir.token_end;
            tail.execution_rank = 0xffffffffu - hir.token_start;
            tail.execution_tie =
                (0x00ffffffu - min(semantic_execution_rank[node], 0x00ffffffu)) * 128u + local_row;
            semantic_lir_schedule[appended] = target_schedule_pack(tail, gParams.schedule_packed_bits);
            continue;
        }
        uint row = first + local_row;
        SemanticLirOperands operands;
        operands.result = row;
        operands.a = LIR_INVALID;
        operands.b = LIR_INVALID;
        operands.c = LIR_INVALID;
        uint word_offset = LIR_INVALID;
        uint unsupported = valid ? 0u : SEMANTIC_LIR_FLAG_UNSUPPORTED;
        SemanticLirCore core = row_core(SEMANTIC_LIR_OP_NOP, 1u, 3u, tag_layout, unsupported);
        if (local_row == 0u || local_row == 1u || local_row == 6u || local_row == 11u)
        {
            bool set = local_row == 0u;
            core = row_core(set ? SEMANTIC_LIR_OP_VALUE_SET : SEMANTIC_LIR_OP_VALUE_GET,
                1u, SEMANTIC_LIR_TY_POINTER, pointer, unsupported);
            operands.a = tmp;
            if (set) operands.b = operand_row;
            if (local_row == 6u && !result_form)
                core = row_core(SEMANTIC_LIR_OP_NOP, 1u, 3u, tag_layout, unsupported);
        }
        else if (local_row == 2u || local_row == 7u || local_row == 12u)
        {
            bool tag_word = local_row == 2u;
            uint tag = tag_word ? 1u : local_row == 7u ? error_tag : semantic_expr_ref_tag[node];
            uint payload = tag_word ? 3u : local_row == 7u ? error : semantic_expr_ref_payload[node];
            uint2 layout = tag_word ? tag_layout : local_row == 7u ? error_layout : value_layout;
            core = row_core(SEMANTIC_LIR_OP_LOAD, tag, payload, layout,
                unsupported | SEMANTIC_LIR_FLAG_FIELD);
            operands.a = row - 1u;
            operands.b = tag_word ? 0u : 1u;
            if (!tag_word) operands.c = 1u;
            word_offset = operands.b;
            if (local_row == 7u && !result_form)
            {
                core = row_core(SEMANTIC_LIR_OP_NOP, 1u, 3u, tag_layout, unsupported);
                operands.a = LIR_INVALID; operands.b = LIR_INVALID; operands.c = LIR_INVALID;
                word_offset = LIR_INVALID;
            }
        }
        else if (local_row == 3u)
        {
            core = row_core(SEMANTIC_LIR_OP_CONST_I32, 1u, 3u, tag_layout, unsupported);
            operands.a = 1u;
        }
        else if (local_row == 4u)
        {
            core = row_core(SEMANTIC_LIR_OP_COMPARE, 1u, 3u, tag_layout, unsupported);
            operands.a = first + 2u;
            operands.b = first + 3u;
            operands.c = 0u;
        }
        else if (local_row == 5u)
        {
            core = row_core(SEMANTIC_LIR_OP_IF_BEGIN, 1u, 3u, tag_layout, unsupported);
            operands.a = first + 4u;
            operands.b = first + 10u;
            operands.c = 0u;
        }
        else if (local_row == 8u)
        {
            core = row_core(SEMANTIC_LIR_OP_AGGREGATE_NEW, return_tag, return_payload,
                return_layout, unsupported);
            operands.a = element;
            operands.b = result_form ? 1u : 0u;
            operands.c = SEMANTIC_LIR_AGGREGATE_ENUM | 1u;
        }
        else if (local_row == 9u)
        {
            core = row_core(SEMANTIC_LIR_OP_RETURN, return_tag, return_payload,
                return_layout, unsupported);
            operands.a = first + 8u;
        }
        else if (local_row == 10u)
            core = row_core(SEMANTIC_LIR_OP_CONTROL_END, 1u, 3u, tag_layout, unsupported);

        // The default expression schedule at the `?` token, rows in order.
        SemanticLirSchedule schedule;
        schedule.execution_region = hir.token_end > hir.token_start ? hir.token_end - 1u : hir.token_end;
        schedule.execution_rank = 0xffffffffu - hir.token_start;
        schedule.execution_tie =
            (0x00ffffffu - min(semantic_execution_rank[node], 0x00ffffffu)) * 128u + local_row;
        semantic_lir_schedule[row] = target_schedule_pack(schedule, gParams.schedule_packed_bits);
        if (row < gParams.resident_rows)
        {
            semantic_lir_core[row] = core;
            semantic_lir_operands[row] = operands;
            semantic_lir_layout_word_offset[row] = word_offset;
        }
    }
}
