// The checked type a type row (a field, a payload, a declared result)
// denotes, translated into the store.
import type_checker.retention.retention_store;
import type_checker.retention.retention_job;
import type_checker.retention.retained_row_classes;

public StructuredBuffer<uint> semantic_type_ref_tag_by_hir;
public StructuredBuffer<uint> semantic_type_ref_payload_by_hir;
public StructuredBuffer<uint> semantic_expr_ref_tag_by_hir;
public StructuredBuffer<uint> semantic_expr_ref_payload_by_hir;
public StructuredBuffer<uint> semantic_value_const_present_by_hir;
public StructuredBuffer<uint2> semantic_value_const_by_hir;

public uint type_row_term(uint row)
{
    if (!valid_row(row)) return RT_NONE;
    uint term = translate_checked(semantic_type_ref_tag_by_hir[row], semantic_type_ref_payload_by_hir[row]);
    if (term == RT_NONE || term == RT_UNKNOWN)
    {
        uint fallback = translate_checked(semantic_expr_ref_tag_by_hir[row], semantic_expr_ref_payload_by_hir[row]);
        if (fallback != RT_NONE) term = fallback;
    }
    // A constant argument in a type application (`Grid<T, N>`) is a TYPE
    // syntax row, but denotes the checked constant parameter, not a type.
    // The value artifact already names its exact declaration token. Keep
    // that ParamId, as the row's constant-value column does, rather than
    // leaving a complete type application's child untyped.
    if (term == RT_NONE && (semantic_value_const_present_by_hir[row] & RT_CONST_SYMBOLIC) != 0u)
    {
        uint param = param_map_find(semantic_value_const_by_hir[row].x);
        if (param == RT_INVALID || rt_param_key[param].y != RT_DOMAIN_CONST) return RT_UNKNOWN;
        term = rt_param_leaf(param);
    }
    return term;
}

public StructuredBuffer<uint> compact_fn_return_type;
public StructuredBuffer<uint> compact_const_value;
public StructuredBuffer<uint> semantic_param_ref_tag_by_row;
public StructuredBuffer<uint> semantic_param_ref_payload_by_row;
