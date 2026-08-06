// Compute the by-value machine-word layout of each fixed struct. One lane owns
// one declaration and writes only that declaration's direct field rows. Nested
// declarations are traversed read-only, so independent layouts remain parallel.

import hir_records;
import gpu_index;

struct Params { uint n_hir_nodes; uint param_capacity; uint n_tokens; uint reserved; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> semantic_expr_ref_tag;
StructuredBuffer<uint> semantic_expr_ref_payload;
StructuredBuffer<uint> semantic_aggregate_decl_token;
StructuredBuffer<uint> semantic_struct_hir_by_name_token;
StructuredBuffer<uint> semantic_struct_field_start_by_hir;
StructuredBuffer<uint> semantic_struct_field_count_by_hir;
RWStructuredBuffer<uint> semantic_struct_word_count_by_hir;
RWStructuredBuffer<uint> semantic_struct_field_word_offset_by_row;
RWStructuredBuffer<uint> semantic_struct_field_word_count_by_row;

static const uint INVALID = 0xffffffffu;
static const uint HIR_TYPE = 5u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 1048576u;
static const uint MAX_LAYOUT_DEPTH = 64u;
static const uint DISPATCH_X_STRIDE = 16776960u;

uint nested_struct(uint type_node, uint hir_count)
{
    if (type_node >= hir_count || compact_hir_core[type_node].kind != HIR_TYPE)
        return INVALID;
    uint token = semantic_aggregate_decl_token[type_node];
    if (token >= gParams.n_tokens && semantic_expr_ref_tag[type_node] == TYPE_REF_SCALAR)
    {
        uint type_id = semantic_expr_ref_payload[type_node];
        if (type_id >= TY_STRUCT_BASE && type_id < TY_ENUM_BASE)
            token = type_id - TY_STRUCT_BASE;
    }
    if (token >= gParams.n_tokens)
    {
        uint source_token = compact_hir_core[type_node].token_start;
        if (source_token < gParams.n_tokens &&
            semantic_struct_hir_by_name_token[source_token] < hir_count)
            token = source_token;
    }
    // Canonical type rows retain their path/value HIR in payload.b. Checked
    // type projection normally resolves the wrapper itself; following the
    // canonical value is the general fallback for declaration-field types.
    uint value_node = compact_hir_payload[type_node].b;
    if (token >= gParams.n_tokens && value_node < hir_count)
    {
        token = semantic_aggregate_decl_token[value_node];
        if (token >= gParams.n_tokens &&
            semantic_expr_ref_tag[value_node] == TYPE_REF_SCALAR)
        {
            uint type_id = semantic_expr_ref_payload[value_node];
            if (type_id >= TY_STRUCT_BASE && type_id < TY_ENUM_BASE)
                token = type_id - TY_STRUCT_BASE;
        }
        if (token >= gParams.n_tokens)
        {
            uint source_token = compact_hir_core[value_node].token_start;
            if (source_token < gParams.n_tokens &&
                semantic_struct_hir_by_name_token[source_token] < hir_count)
                token = source_token;
        }
    }
    if (token >= gParams.n_tokens) return INVALID;
    uint result = semantic_struct_hir_by_name_token[token];
    return result < hir_count && compact_hir_core[result].kind == HIR_STRUCT_ITEM
        ? result : INVALID;
}

uint array_length(uint type_node, uint hir_count)
{
    if (type_node >= hir_count || compact_hir_core[type_node].kind != HIR_TYPE)
        return 1u;
    HirPayload payload = compact_hir_payload[type_node];
    return payload.a == HIR_TYPE_FORM_ARRAY && payload.d != INVALID
        ? payload.d : 1u;
}

uint array_element_type(uint type_node, uint hir_count)
{
    if (type_node >= hir_count || compact_hir_core[type_node].kind != HIR_TYPE)
        return type_node;
    HirPayload payload = compact_hir_payload[type_node];
    return payload.a == HIR_TYPE_FORM_ARRAY ? payload.b : type_node;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint root = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint hir_count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    if (root >= hir_count || compact_hir_core[root].kind != HIR_STRUCT_ITEM) return;

    uint stack_struct[MAX_LAYOUT_DEPTH];
    uint stack_next[MAX_LAYOUT_DEPTH];
    uint stack_total[MAX_LAYOUT_DEPTH];
    uint stack_multiplier[MAX_LAYOUT_DEPTH];
    uint stack_parent_field[MAX_LAYOUT_DEPTH];
    uint depth = 0u;
    stack_struct[0u] = root;
    stack_next[0u] = 0u;
    stack_total[0u] = 0u;
    stack_multiplier[0u] = 1u;
    stack_parent_field[0u] = INVALID;

    for (;;)
    {
        uint current = stack_struct[depth];
        uint count = semantic_struct_field_count_by_hir[current];
        uint start = semantic_struct_field_start_by_hir[current];
        if (stack_next[depth] >= count)
        {
            uint completed = stack_total[depth] * stack_multiplier[depth];
            uint parent_field = stack_parent_field[depth];
            if (depth == 0u)
            {
                semantic_struct_word_count_by_hir[root] = completed;
                return;
            }
            depth -= 1u;
            if (depth == 0u && parent_field != INVALID)
            {
                semantic_struct_field_word_offset_by_row[parent_field] = stack_total[0u];
                semantic_struct_field_word_count_by_row[parent_field] = completed;
            }
            stack_total[depth] += completed;
            continue;
        }

        uint ordinal = stack_next[depth]++;
        uint field_row = start != INVALID ? start + ordinal : INVALID;
        if (field_row >= gParams.n_hir_nodes)
        {
            semantic_struct_word_count_by_hir[root] = INVALID;
            return;
        }
        HirField field = compact_fields[field_row];
        if (field.owner != current || field.ordinal != ordinal)
        {
            semantic_struct_word_count_by_hir[root] = INVALID;
            return;
        }

        uint multiplier = array_length(field.value, hir_count);
        uint element_type = array_element_type(field.value, hir_count);
        uint child = nested_struct(element_type, hir_count);
        if (child == INVALID)
        {
            if (depth == 0u)
            {
                semantic_struct_field_word_offset_by_row[field_row] = stack_total[0u];
                semantic_struct_field_word_count_by_row[field_row] = multiplier;
            }
            stack_total[depth] += multiplier;
            continue;
        }

        if (depth + 1u >= MAX_LAYOUT_DEPTH)
        {
            semantic_struct_word_count_by_hir[root] = INVALID;
            return;
        }
        for (uint ancestor = 0u; ancestor <= depth; ancestor += 1u)
        {
            if (stack_struct[ancestor] == child)
            {
                semantic_struct_word_count_by_hir[root] = INVALID;
                return;
            }
        }
        depth += 1u;
        stack_struct[depth] = child;
        stack_next[depth] = 0u;
        stack_total[depth] = 0u;
        stack_multiplier[depth] = multiplier;
        stack_parent_field[depth] = field_row;
    }
}
