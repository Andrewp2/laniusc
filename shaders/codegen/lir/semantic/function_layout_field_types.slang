// Struct field type lookups for the aggregate layout walk
// (function_layout_words.slang). Included after the declaring kernel's
// buffers and gParams.
#include "function_layout_constants.slang"

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
            semantic_aggregate_hir_by_name_token[source_token] < hir_count)
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
                semantic_aggregate_hir_by_name_token[source_token] < hir_count)
                token = source_token;
        }
    }
    if (token >= gParams.n_tokens) return INVALID;
    uint result = semantic_aggregate_hir_by_name_token[token];
    return result < hir_count && compact_hir_core[result].kind == HIR_STRUCT_ITEM
        ? result : INVALID;
}

uint array_length(uint type_node, uint hir_count)
{
    if (type_node >= hir_count) return INVALID;
    if (semantic_expr_ref_tag[type_node] == 3u)
    {
        uint instance = semantic_expr_ref_payload[type_node];
        uint capacity; uint stride;
        type_instance_kind.GetDimensions(capacity, stride);
        if (instance >= capacity) return INVALID;
        if (type_instance_kind[instance] == 2u)
        {
            uint count;
            return checked_source_array_count(type_instance_len_kind[instance],
                type_instance_len_payload[instance], gParams.n_tokens, count) &&
                count < 0xfffffffeu ? count : INVALID;
        }
    }
    // A syntactic fixed array without its checked instance has no length.
    // HIR payload.d names an operand node; it is never an inline count.
    return compact_hir_core[type_node].kind == HIR_TYPE &&
        compact_hir_payload[type_node].a == HIR_TYPE_FORM_ARRAY ? INVALID : 1u;
}

uint array_element_type(uint type_node, uint hir_count)
{
    if (type_node >= hir_count || compact_hir_core[type_node].kind != HIR_TYPE)
        return type_node;
    HirPayload payload = compact_hir_payload[type_node];
    return payload.a == HIR_TYPE_FORM_ARRAY ? payload.b : type_node;
}
